"""NextSet workout archive: one JSON per Garmin activity plus a SQLite copy (data/archive/)."""

import datetime as dt
import json
import sqlite3
from pathlib import Path


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def merge_laps(laps):
    """Sets from laps. A correction or undo writes another lap for the same (exercise, set). Values come
    from the last lap (dropped when void); timing (the lap window) from the first lap, because a correction
    lap is short and late. After a void lap the re-logged lap is the real set and supplies timing too.
    The blank closing lap (0.2.3+) is not a set. Old FITs have no void."""
    last, timing = {}, {}
    for lap in laps:
        name = (lap["exercise"] or "").strip()
        if name:
            key = (name, lap["set"])
            if key not in last or last[key].get("void"):
                timing[key] = lap
            last[key] = lap
    return sorted(((k[0], l | {"start_time": timing[k]["start_time"]})
                   for k, l in last.items() if not l.get("void")), key=lambda nl: nl[1]["start_time"])


def normalize(activity_id, name, start, end, laps):
    """The archived record. start/end are datetimes, name is the Garmin activity name (= watch routine)."""
    sets = [{"exercise": n, "set": l["set"], "reps": l["reps"] or 0, "weight_kg": l["weight_kg"] or 0,
             "duration_s": l["duration_s"] or 0, "active_s": l.get("active_s") or 0,
             "garmin_category": l.get("garmin_category") or "", "garmin_code": l.get("garmin_code") or "",
             "start_time": iso(l["start_time"])} for n, l in merge_laps(laps)]
    return {"activityId": int(activity_id), "name": name, "start": iso(start), "end": iso(end), "sets": sets}


def store(directory, w):
    """Idempotent: rewrites <id>.json and upserts the workout + its sets in nextset.db."""
    d = Path(directory)
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"{w['activityId']}.json"
    p.with_suffix(".tmp").write_text(json.dumps(w, indent=1))
    p.with_suffix(".tmp").replace(p)
    with sqlite3.connect(d / "nextset.db") as db:  # commits on exit
        db.execute("create table if not exists workouts (activity_id integer primary key, name text, start text, end text)")
        db.execute("create table if not exists sets (activity_id integer, exercise text, set_no integer, reps integer,"
                   " weight_kg real, duration_s real, active_s real, garmin_category text, garmin_code text,"
                   " start_time text, primary key (activity_id, exercise, set_no))")
        db.execute("insert or replace into workouts values (?,?,?,?)", (w["activityId"], w["name"], w["start"], w["end"]))
        db.execute("delete from sets where activity_id=?", (w["activityId"],))
        db.executemany("insert into sets values (?,?,?,?,?,?,?,?,?,?)",
                       [(w["activityId"], s["exercise"], s["set"], s["reps"], s["weight_kg"], s["duration_s"],
                         s["active_s"], s["garmin_category"], s["garmin_code"], s["start_time"]) for s in w["sets"]])
    db.close()


def load(directory, activity_id):
    return json.loads((Path(directory) / f"{activity_id}.json").read_text())
