"""Copy NextSet per-set laps into Garmin Connect's native exercise sets.

NextSet (a Connect IQ app) cannot write FIT `set` messages, so it writes one lap per set with
developer fields (exercise, set, reps, weight_kg, duration_s, active_s). This job downloads each new
NextSet activity's original FIT from Garmin Connect, turns the laps into exercise sets and writes
them through Connect's unofficial exerciseSets endpoint (the one Connect web's set editor uses).

Commands:
  login              prompt for Garmin email/password once, store tokens in $DATA/tokens
  dump ACTIVITY_ID   print an activity's current exerciseSets JSON
  run [--dry-run] [--only ID] [--force]
                     process recent strength activities; --dry-run prints payloads only
  loop               run every $INTERVAL_SEC seconds (container entrypoint)
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
from garmin_fit_sdk import Profile
from garminconnect import Garmin

DATA = Path(os.environ.get("DATA", "/data"))
TOKENS = DATA / "tokens"
STATE = DATA / "state.json"
EXERCISES = json.loads((Path(__file__).parent / "exercises.json").read_text())
LOOKBACK = int(os.environ.get("LOOKBACK", "20"))  # most recent strength activities checked per run
INTERVAL_SEC = int(os.environ.get("INTERVAL_SEC", "600"))
FAIL_ALERT_AFTER = int(os.environ.get("FAIL_ALERT_AFTER", "3"))
NTFY_URL = os.environ.get("NTFY_URL", "")
# ponytail: a lap spans rest + set and the watch only knows when the set was logged, so a
# non-timed set is assumed to take ACTIVE_SEC before its lap ends; the rest fills the remainder.
ACTIVE_SEC = float(os.environ.get("ACTIVE_SEC", "40"))

log = logging.getLogger("connect-sets")
_warned = set()


def garmin_exercise(name, category=None, sub=None):
    """(category, name) checked against the pinned garmin-fit-sdk profile: Garmin rejects unknown names with
    400 "Invalid Sub-Category", so degrade to name None / UNKNOWN. Uses the lap's `category`/`sub` (0.2.5+
    FITs) when given, else the exercises.json entry `name`."""
    if not category:
        category, sub = EXERCISES[name]["category"], EXERCISES[name]["name"]
    types = Profile["types"]
    if category.lower() not in types["exercise_category"].values():
        category, sub, why = "UNKNOWN", None, "category is not in the FIT profile"
    elif sub is not None and sub.lower() not in types.get(category.lower() + "_exercise_name", {}).values():
        sub, why = None, "name is not in the FIT profile"
    else:
        return category, sub
    if name not in _warned:
        _warned.add(name)
        log.warning("%s: %s; sending %s/None", name, why, category)
    return category, sub


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


def nextset_laps(data):
    """Lap dicts carrying NextSet fields, or None when the FIT was not written by NextSet."""
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
    return laps if is_nextset else None


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0")


def exercise_sets(laps):
    """Connect exerciseSets from laps. Raises KeyError for an old-FIT exercise missing in exercises.json."""
    # A correction or undo writes another lap for the same (exercise, set). Values come from the last
    # lap (dropped when void); timing (the lap window) from the first lap, because a correction lap is
    # short and late. After a void lap the re-logged lap is the real set and supplies timing too.
    # The blank closing lap (0.2.3+) is not a set. Old FITs have no void.
    last, timing = {}, {}
    for lap in laps:
        name = (lap["exercise"] or "").strip()
        if name:
            key = (name, lap["set"])
            if key not in last or last[key].get("void"):
                timing[key] = lap
            last[key] = lap
    kept = sorted(((k[0], l | {"start_time": timing[k]["start_time"],
                              "total_timer_time": timing[k]["total_timer_time"]})
                   for k, l in last.items() if not l.get("void")),
                  key=lambda nl: nl[1]["start_time"])
    sets = []
    for name, lap in kept:
        category, sub = garmin_exercise(name, lap.get("garmin_category"), lap.get("garmin_code") or None)
        end = lap["start_time"] + dt.timedelta(seconds=lap["total_timer_time"] or 0)
        timed = bool(lap["duration_s"])
        measured = lap.get("active_s") or 0  # set time from an explicit START press (0.2.4+)
        active = float(lap["duration_s"]) if timed else (float(measured) if measured >= 3 else ACTIVE_SEC)
        active = min(active, lap["total_timer_time"] or active)
        start = end - dt.timedelta(seconds=active)
        rest = (start - lap["start_time"]).total_seconds()
        if rest >= 1 and sets:
            sets.append({"exercises": [], "duration": rest, "repetitionCount": None,
                         "weight": None, "setType": "REST", "startTime": iso(lap["start_time"]),
                         "wktStepIndex": None})
        weight = lap["weight_kg"] or 0
        sets.append({
            "exercises": [{"category": category, "name": sub, "probability": 100.0}],
            "duration": active,
            "repetitionCount": None if timed else lap["reps"],
            # Connect stores grams. Assistance is logged as negative kg, which Connect cannot show.
            "weight": weight * 1000 if weight > 0 else None,
            "setType": "ACTIVE",
            "startTime": iso(start),
            "wktStepIndex": None,
        })
    for i, s in enumerate(sets):
        s["messageIndex"] = i
    return sets


def process(api, activity_id, dry_run, force):
    """True when finished with this activity (written, not NextSet, or already has sets)."""
    if not force and (api.get_activity_exercise_sets(activity_id) or {}).get("exerciseSets"):
        log.info("%s already has exercise sets, leaving it alone", activity_id)
        return True
    laps = nextset_laps(fit_bytes(api, activity_id))
    if laps is None:
        log.info("%s is not a NextSet activity", activity_id)
        return True
    try:
        sets = exercise_sets(laps)
    except KeyError as e:
        log.error("%s: exercise %s missing in exercises.json; not written", activity_id, e)
        return False
    payload = {"activityId": int(activity_id), "exerciseSets": sets}
    if dry_run:
        print(json.dumps(payload, indent=1))
        return False
    api.set_activity_exercise_sets(activity_id, payload)
    log.info("%s: wrote %d sets", activity_id, sum(s["setType"] == "ACTIVE" for s in sets))
    return True


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


def run(dry_run=False, only=None, force=False):
    api = client()
    state = load_state()
    handled = set(state["done"]) | set(state["ignored"])
    if only:
        ids = [int(only)]
    else:
        # Garmin rejects a "strength_training" type filter (it is a sub type), so filter client-side
        ids = [a["activityId"] for a in api.get_activities(0, LOOKBACK)
               if a.get("activityType", {}).get("typeKey") == "strength_training"]
    failed = 0
    for activity_id in ids:
        if activity_id in handled and not only:
            continue
        try:
            finished = process(api, activity_id, dry_run, force)
        except Exception:
            log.exception("%s failed; retried next run", activity_id)
            failed += 1
            continue
        if finished and not dry_run:
            state["done"].append(activity_id)
            save_state(state)
        elif not finished and not dry_run:
            failed += 1  # e.g. exercise missing in exercises.json: retried next run, must alert
    return failed


def main(argv):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    DATA.mkdir(parents=True, exist_ok=True)
    cmd = argv[1] if len(argv) > 1 else "run"
    if cmd == "login":
        api = Garmin(input("Garmin email: "), getpass.getpass("Garmin password: "))
        api.login(str(TOKENS))
        TOKENS.chmod(0o700) if TOKENS.is_dir() else TOKENS.chmod(0o600)
        print("Logged in; tokens saved to", TOKENS)
    elif cmd == "dump":
        print(json.dumps(client().get_activity_exercise_sets(argv[2]), indent=1))
    elif cmd == "run":
        only = argv[argv.index("--only") + 1] if "--only" in argv else None
        run("--dry-run" in argv, only, "--force" in argv)
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
