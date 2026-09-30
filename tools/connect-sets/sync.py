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
import zipfile
from pathlib import Path

import fitdecode
from garminconnect import Garmin

DATA = Path(os.environ.get("DATA", "/data"))
TOKENS = DATA / "tokens"
STATE = DATA / "state.json"
EXERCISES = json.loads((Path(__file__).parent / "exercises.json").read_text())
LOOKBACK = int(os.environ.get("LOOKBACK", "20"))  # most recent strength activities checked per run
INTERVAL_SEC = int(os.environ.get("INTERVAL_SEC", "1800"))
# ponytail: a lap spans rest + set and the watch only knows when the set was logged, so a
# non-timed set is assumed to take ACTIVE_SEC before its lap ends; the rest fills the remainder.
ACTIVE_SEC = float(os.environ.get("ACTIVE_SEC", "40"))

log = logging.getLogger("connect-sets")


def client():
    api = Garmin()
    api.login(str(TOKENS))
    return api


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {"done": [], "ignored": []}


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
                            | {"active_s": frame.get_value("active_s", fallback=None)})  # 0.2.4+
    return laps if is_nextset else None


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0")


def exercise_sets(laps):
    """Connect exerciseSets from laps. Raises KeyError for an exercise missing in exercises.json."""
    sets, previous = [], None
    for lap in laps:
        name = (lap["exercise"] or "").strip()
        key = (name, lap["set"])
        # Blank closing lap (0.2.3+) and the repeated closing lap of 0.2.1/0.2.2 are not sets.
        if not name or key == previous:
            continue
        previous = key
        code = EXERCISES[name]
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
            "exercises": [{"category": code["category"], "name": code["name"], "probability": 100.0}],
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


def run(dry_run=False, only=None, force=False):
    api = client()
    state = load_state()
    handled = set(state["done"]) | set(state["ignored"])
    if only:
        ids = [int(only)]
    else:
        ids = [a["activityId"] for a in api.get_activities(0, LOOKBACK, "strength_training")]
    for activity_id in ids:
        if activity_id in handled and not only:
            continue
        try:
            finished = process(api, activity_id, dry_run, force)
        except Exception:
            log.exception("%s failed; retried next run", activity_id)
            continue
        if finished and not dry_run:
            state["done"].append(activity_id)
            save_state(state)


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
        while True:
            try:
                run()
            except Exception:
                log.exception("run failed")
            time.sleep(INTERVAL_SEC)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
