"""NextSet archive + Liftosaur sync (formerly: copy laps into Garmin Connect exercise sets; dropped).

NextSet (a Connect IQ app) writes one FIT lap per set with developer fields (exercise, set, reps,
weight_kg, duration_s, active_s, ...). This job downloads each new NextSet activity's original FIT
from Garmin Connect (read-only), archives it (data/archive/<activityId>.json + nextset.db) and, when
LIFTOSAUR_SYNC=1, logs it into the matching Liftosaur workout (start/sets/finish).

Commands:
  login                          prompt for Garmin email/password once, store tokens in $DATA/tokens
  run [--dry-run] [--only ID]    archive recent strength activities (+ Liftosaur write-back if enabled)
  archive-backfill --lookback N  archive the last N strength activities (read-only, skips archived ones)
  liftosaur-discover             GET-only: save Liftosaur settings/program/workout JSON to data/liftosaur-discovery/
  liftosaur-sync [--dry-run] [--only ID]
                                 write archived workouts to Liftosaur (default: those started since LIFTOSAUR_SINCE)
  loop                           run every $INTERVAL_SEC seconds (container entrypoint)
"""

import datetime as dt
import getpass
import io
import json
import logging
import os
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

import fitdecode
from garminconnect import Garmin

import archive
import liftosaur

DATA = Path(os.environ.get("DATA", "/data"))
TOKENS = DATA / "tokens"
STATE = DATA / "state.json"
ARCHIVE = DATA / "archive"
DISCOVERY = DATA / "liftosaur-discovery"
LOOKBACK = int(os.environ.get("LOOKBACK", "20"))  # most recent strength activities checked per run
INTERVAL_SEC = int(os.environ.get("INTERVAL_SEC", "600"))
FAIL_ALERT_AFTER = int(os.environ.get("FAIL_ALERT_AFTER", "3"))
NTFY_URL = os.environ.get("NTFY_URL", "")
LIFTOSAUR_SYNC = os.environ.get("LIFTOSAUR_SYNC", "0") == "1"  # nothing is written to Liftosaur unless 1


def parse_since(v):
    """LIFTOSAUR_SINCE: ISO datetime (naive = UTC) or unix seconds -> aware datetime, None when unset."""
    if not v:
        return None
    t = dt.datetime.fromtimestamp(float(v), dt.timezone.utc) if v.replace(".", "", 1).isdigit() else dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


# The loop only writes activities that started at or after this; unset = write nothing (never a default window).
LIFTOSAUR_SINCE = parse_since(os.environ.get("LIFTOSAUR_SINCE", ""))
LIFTOSAUR_MIN_SEC = int(os.environ.get("LIFTOSAUR_MIN_SEC", "300"))  # shorter workouts are skipped (test logs)

log = logging.getLogger("connect-sets")


def client():
    api = Garmin()
    api.login(str(TOKENS))
    return api


def load_state():
    try:
        return json.loads(STATE.read_text()) if STATE.exists() else {"done": [], "ignored": []}
    except json.JSONDecodeError:
        bad = STATE.with_name(f"{STATE.name}.bad-{int(time.time())}")
        STATE.rename(bad)
        log.error("state.json is corrupt; moved to %s, starting empty", bad.name)
        return {"done": [], "ignored": []}


def save_state(state):
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1))
    tmp.replace(STATE)


def fit_bytes(api, activity_id):
    raw = api.download_activity(str(activity_id), dl_fmt=Garmin.ActivityDownloadFormat.ORIGINAL)
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        name = next(n for n in z.namelist() if n.lower().endswith(".fit"))
        return z.read(name)


def read_fit(data):
    """{"start", "end", "laps"} from a NextSet FIT, or None when it was not written by NextSet."""
    laps, is_nextset = [], False
    with fitdecode.FitReader(io.BytesIO(data)) as fit:
        for frame in fit:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            if frame.name == "session" and frame.has_field("nextset_version"):
                is_nextset = True
            elif frame.name == "lap" and frame.has_field("exercise"):
                laps.append({f: frame.get_value(f) for f in
                             ("start_time", "total_timer_time", "exercise", "set", "reps",
                              "weight_kg", "duration_s")}
                            | {f: frame.get_value(f, fallback=None) for f in
                                  ("active_s", "garmin_category", "garmin_code", "void")})  # 0.2.4+, 0.2.5+
    if not is_nextset or not laps:
        return None
    # The FIT session start_time was observed equal to the stop time (0.2.5), so the span comes from the laps.
    start = min(l["start_time"] for l in laps)
    end = max(l["start_time"] + dt.timedelta(seconds=l["total_timer_time"] or 0) for l in laps)
    return {"start": start, "end": end, "laps": laps}


def process(api, activity_id, dry_run=False):
    """Archive one activity. Returns "archived", "ignored" (not NextSet) or "dry" (printed only)."""
    fit = read_fit(fit_bytes(api, activity_id))
    if fit is None:
        log.info("%s is not a NextSet activity", activity_id)
        return "ignored"
    name = (api.get_activity(activity_id) or {}).get("activityName") or ""
    w = archive.normalize(activity_id, name, fit["start"], fit["end"], fit["laps"])
    if dry_run:
        print(json.dumps(w, indent=1))
        return "dry"
    archive.store(ARCHIVE, w)
    log.info("%s archived: %s, %d sets", activity_id, name, len(w["sets"]))
    return "archived"


def strength_ids(api, count):
    """Most recent `count` strength activity ids. Garmin rejects a "strength_training" type filter (it is a
    sub type), so filter client-side; pages of 50."""
    ids, offset = [], 0
    while offset < count:
        page = api.get_activities(offset, min(50, count - offset))
        ids += [a["activityId"] for a in page if a.get("activityType", {}).get("typeKey") == "strength_training"]
        if len(page) < min(50, count - offset):
            break
        offset += len(page)
    return ids


def backfill(api, lookback):
    """Read-only on Garmin. Returns (archived, skipped_existing, ignored)."""
    n = [0, 0, 0]
    for i in strength_ids(api, lookback):
        if (ARCHIVE / f"{i}.json").exists():
            n[1] += 1
            continue
        n[0 if process(api, i) == "archived" else 2] += 1
    return tuple(n)


def ntfy(title, body):
    if not NTFY_URL:
        log.warning("%s: %s (NTFY_URL not set)", title, body)
        return
    try:
        req = urllib.request.Request(NTFY_URL, body.encode(), {"Title": title, "Priority": "high"})
        urllib.request.urlopen(req, timeout=10).close()
    except Exception as e:
        log.warning("ntfy failed: %s", type(e).__name__)


class Alerter:
    """Alert once after `after` consecutive failed runs, once on recovery. send(title, body) is injected.
    ponytail: in-memory only, a container restart resets the counter."""

    def __init__(self, send, after):
        self.send, self.after, self.fails, self.alerted = send, after, 0, False

    def record(self, error=None):
        """error: None on a successful run, else a short summary string."""
        if error is None:
            if self.alerted:
                self.send("NextSet sync recovered", "Sync is working again.")
            self.fails, self.alerted = 0, False
            return
        self.fails += 1
        if self.fails >= self.after and not self.alerted:
            self.alerted = True
            self.send("NextSet sync failing", error[:300])


def liftosaur_client():
    key = os.environ["LIFTOSAUR_API_KEY"]
    return liftosaur.Client(key, liftosaur.device_id(DATA))


def liftosaur_pass(state, dry_run=False, only=None, lifto=None):
    """Write archived workouts to Liftosaur, oldest first. Status per activity in state["liftosaur"]:
    done/skipped are final, blocked/failed are retried. Without --only, only workouts started at or after
    LIFTOSAUR_SINCE and at least LIFTOSAUR_MIN_SEC long are considered; --only bypasses both.
    Returns the number failed."""
    if not only and not LIFTOSAUR_SINCE:
        log.warning("LIFTOSAUR_SINCE is not set: writing nothing to Liftosaur")
        return 0
    lifto = lifto or liftosaur_client()
    st = state.setdefault("liftosaur", {})
    ws = sorted((archive.load(ARCHIVE, p.stem) for p in ARCHIVE.glob("*.json")), key=lambda w: w["start"])
    failed, days = 0, None
    for w in ws:
        key = str(w["activityId"])
        start = dt.datetime.fromisoformat(w["start"].replace("Z", "+00:00"))
        secs = (dt.datetime.fromisoformat(w["end"].replace("Z", "+00:00")) - start).total_seconds()
        if only:
            if key != str(only):
                continue
            status = detail = None
        elif st.get(key, {}).get("status") in ("done", "skipped") or start < LIFTOSAUR_SINCE:
            continue
        elif secs < LIFTOSAUR_MIN_SEC:
            status, detail = "skipped", f"workout is {secs:.0f}s, shorter than LIFTOSAUR_MIN_SEC={LIFTOSAUR_MIN_SEC}"
        else:
            status = detail = None
        if status is None:
            try:
                days = days or liftosaur.program_days(lifto)  # once per pass
                status, detail = liftosaur.sync_one(lifto, w, dry_run, days=days)
            except Exception as e:  # network etc.; the type only, error text may echo request data
                status, detail = "failed", type(e).__name__
        log.info("liftosaur %s %s: %s %s", key, w["name"], status, detail)
        if dry_run:
            continue
        if st.get(key, {}).get("status") != status:  # notify on transitions only
            if status in ("skipped", "blocked") or (status == "done" and detail != "ok"):
                ntfy(f"Liftosaur: {w['name']} {status}", detail)
        st[key] = {"status": status, "detail": detail}
        save_state(state)
        failed += status == "failed"
    return failed


def run(dry_run=False, only=None):
    api = client()
    state = load_state()
    handled = set(state["done"]) | set(state["ignored"])
    ids = [int(only)] if only else strength_ids(api, LOOKBACK)
    failed = 0
    for activity_id in ids:
        if activity_id in handled and not only:
            continue
        try:
            result = process(api, activity_id, dry_run)
        except Exception:
            log.exception("%s failed; retried next run", activity_id)
            failed += 1
            continue
        if not dry_run:
            state["done" if result == "archived" else "ignored"].append(activity_id)
            save_state(state)
    if LIFTOSAUR_SYNC and not dry_run and not only:
        failed += liftosaur_pass(state)
    return failed


def main(argv):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    DATA.mkdir(parents=True, exist_ok=True)
    cmd = argv[1] if len(argv) > 1 else "run"
    opt = lambda f: argv[argv.index(f) + 1] if f in argv else None
    if cmd == "login":
        api = Garmin(input("Garmin email: "), getpass.getpass("Garmin password: "))
        api.login(str(TOKENS))
        TOKENS.chmod(0o700) if TOKENS.is_dir() else TOKENS.chmod(0o600)
        print("Logged in; tokens saved to", TOKENS)
    elif cmd == "run":
        run("--dry-run" in argv, opt("--only"))
    elif cmd == "archive-backfill":
        a, s, i = backfill(client(), int(opt("--lookback") or LOOKBACK))
        print(f"archived {a}, already archived {s}, not NextSet {i}")
    elif cmd == "liftosaur-discover":
        liftosaur.discover(liftosaur_client(), DISCOVERY)
        print("saved to", DISCOVERY)
    elif cmd == "liftosaur-sync":
        state = load_state()
        liftosaur_pass(state, "--dry-run" in argv, opt("--only"))
    elif cmd == "loop":
        alerter = Alerter(ntfy, FAIL_ALERT_AFTER)
        while True:
            try:
                n = run()
                alerter.record(f"{n} activities failed (see container logs)" if n else None)
            except Exception as e:
                log.exception("run failed")
                alerter.record(f"{type(e).__name__}: {e}")
            time.sleep(INTERVAL_SEC)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
