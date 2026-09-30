"""Liftosaur REST client + write-back call builder (https://www.liftosaur.com/doc/api).

Liftosaur owns the exercise list: a NextSet exercise name must equal the `name` of a Liftosaur entry
in /workout/next (case-sensitive, trimmed). No mapping file, no fuzzy matching.
Pure functions (match_day, build_*) take plain dicts so test_sync.py can run them offline.
"""

import json
import os
import re
import string
import random
import urllib.error
import urllib.request
import uuid
from pathlib import Path

BASE = "https://www.liftosaur.com/api/v1"
CLIENT = "nextset-nas/0.1.0"


class LiftoError(Exception):
    def __init__(self, status, code, message=""):
        super().__init__(f"{status} {code} {message}")
        self.status, self.code = status, code


def device_id(data_dir):
    """Stable per install: generated once, persisted."""
    p = Path(data_dir) / "liftosaur-device-id"
    if not p.exists():
        p.write_text(uuid.uuid4().hex)
    return p.read_text().strip()


class Client:
    def __init__(self, key, dev_id):
        self.key, self.dev_id = key, dev_id

    def _req(self, method, path, body=None):
        headers = {"Authorization": f"Bearer {self.key}", "Content-Type": "application/json",
                   "X-Liftosaur-Device-Id": self.dev_id, "X-Liftosaur-Client": CLIENT}
        req = urllib.request.Request(BASE + path, None if body is None else json.dumps(body).encode(),
                                     headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.load(r).get("data")
        except urllib.error.HTTPError as e:
            try:
                err = json.load(e).get("error", {})
            except Exception:
                err = {}
            raise LiftoError(e.code, err.get("code", "?"), err.get("message", "")) from None

    def get(self, path):
        return self._req("GET", path)

    def post(self, path, body):
        return self._req("POST", path, body)


def parse_days(text):
    """[(week, dayInWeek, dayName)] from Liftoscript: "# Week N" then "## Day name" lines."""
    week, n, days = 0, 0, []
    for line in text.splitlines():
        if m := re.match(r"# Week (\d+)", line):
            week, n = int(m[1]), 0
        elif line.startswith("## ") and week:
            n += 1
            days.append((week, n, line[3:].strip()))
    return days


def program_days(client):
    """(programId, [(week, dayInWeek, dayName)]) of the active program: one GET, cached by the caller per pass."""
    cur = client.get("/programs/current")
    return cur["id"], parse_days(cur["text"])


def discover(client, outdir):
    """Read-only: GET the endpoints the write-back depends on and save the raw JSON."""
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    def save(name, data):
        (outdir / f"{name}.json").write_text(json.dumps({"data": data}, indent=1))
        return data

    save("settings", client.get("/settings"))
    save("programs", client.get("/programs"))
    cur = save("programs_current", client.get("/programs/current"))
    save("workout_current", client.get("/workout/current"))
    save("workout_next", client.get("/workout/next"))
    for week, dow, _ in parse_days(cur["text"]):  # one preview per day (GET, creates nothing)
        save(f"workout_next_w{week}d{dow}", client.get(f"/workout/next?programId={cur['id']}&week={week}&dayInWeek={dow}"))
    save("history", client.get("/history?limit=5"))


# --- matching / call building (pure) ---------------------------------------------------------------

def resolve_day(days, activity_name):
    """((week, dayInWeek), None) for the program day named like the activity (case-insensitive, exact),
    else (None, skip reason). Several days with that name (e.g. the same name in two weeks) is ambiguous."""
    hits = [(w, d) for w, d, n in days if n.strip().lower() == (activity_name or "").strip().lower()]
    if len(hits) == 1:
        return hits[0], None
    return None, (f"{len(hits)} program days named {activity_name!r}" if hits else f"no program day named {activity_name!r}")


def kg_str(kg):
    """Liftosaur weight string. Assistance is logged as negative kg in NextSet; Liftosaur stores the
    assistance amount as a positive machine weight (unverified for the FR965 user's pull-up/dip)."""
    return f"{abs(kg or 0):g}kg"


def new_id(used):
    while True:
        i = "".join(random.choices(string.ascii_lowercase, k=6))
        if i not in used:
            used.add(i)
            return i


def _completed(plan, s):
    """`completed` dict for archived set `s` against planned set `plan`, or (None, reason)."""
    c = {"weight": kg_str(s["weight_kg"])}
    if plan["setTimer"] is not None:  # timed set: report held seconds (+ reps as planned)
        if not s["duration_s"]:
            return None, "planned set is timed but the watch set has no duration"
        c |= {"reps": plan["reps"], "setTimer": s["duration_s"]}
        if plan["isUnilateral"]:
            c["setTimerLeft"] = s["duration_s"]
    else:
        if not s["reps"]:
            return None, "planned set is untimed but the watch set has no reps"
        c["reps"] = s["reps"]
        if plan["isUnilateral"]:
            c["repsLeft"] = s["reps"]  # ponytail: NextSet logs one set = both sides; API contract for non-AMRAP unilateral unverified
    return c, None


def build_sets(workout, archive_sets):
    """(sets_calls, notes). workout: a /workout/next|start `workout` dict, archive_sets: normalized watch sets.
    Planned working sets are matched by exact exercise name + set order; extra watch sets are appended;
    planned sets without a watch counterpart (and warmups) stay incomplete."""
    by_name, notes = {}, []
    for s in sorted(archive_sets, key=lambda s: (s["exercise"], s["set"])):
        by_name.setdefault(s["exercise"].strip(), []).append(s)
    names = [e["name"].strip() for e in workout["entries"]]
    used = {s["setId"] for e in workout["entries"] for s in e["sets"] + e["warmupSets"]}
    calls, unmatched_plan = [], []
    for e in workout["entries"]:
        name = e["name"].strip()
        if names.count(name) > 1:
            notes.append(f"ambiguous exercise name in plan: {name}")
            by_name.pop(name, None)
            continue
        mine = by_name.pop(name, [])
        if not mine:
            unmatched_plan.append(name)
        plans = e["sets"]
        for i, s in enumerate(mine):
            c, why = _completed(plans[min(i, len(plans) - 1)], s) if plans else (None, "no planned sets")
            if c is None:
                notes.append(f"{name} set {s['set']}: {why}")
            elif i < len(plans):
                calls.append({"entryId": e["entryId"], "setId": plans[i]["setId"], "completed": c})
            else:
                calls.append({"entryId": e["entryId"], "setId": new_id(used), "append": True, "completed": c})
    if by_name:
        notes.append("not in Liftosaur plan (not logged): " + ", ".join(sorted(by_name)))
    if unmatched_plan:
        notes.append("planned, not done: " + ", ".join(unmatched_plan))
    return calls, notes, sorted(by_name)


def to_ms(iso_s):
    import datetime as dt
    return int(dt.datetime.fromisoformat(iso_s.replace("Z", "+00:00")).timestamp() * 1000)


def build_calls(nxt, w):
    """Ordered [(path, body)] for archived workout `w` against /workout/next preview `nxt`, plus notes and
    the NextSet exercise names Liftosaur does not know. Real runs rebuild the sets call from the /start
    response because setIds in /next are regenerated on every GET."""
    start, end = to_ms(w["start"]), to_ms(w["end"])
    day = nxt["dayData"]
    sets, notes, unknown = build_sets(nxt, w["sets"])
    finish_notes = "; ".join([f"NextSet activity {w['activityId']}"] + notes)
    calls = [("/workout/start", {"programId": nxt["programId"], "week": day["week"],
                                 "dayInWeek": day["dayInWeek"], "startTime": start}),
             ("/workout/sets", {"sets": sets}),
             ("/workout/finish", {"startTime": start, "endTime": end, "notes": finish_notes})]
    return calls, notes, unknown


def sync_one(client, w, dry_run, print_fn=print, days=None):
    """Returns (status, detail): done | skipped | blocked | failed. Never discards an app workout.
    `days` = program_days(client), fetched once per pass by the caller.

    The day is the program day whose name equals the routine name; it is started explicitly, so the
    Liftosaur "next day" pointer does not matter. 409 workout_already_active (or a live /workout/current
    that is not ours) -> blocked, retried next run, caller notifies once. 409 workout_start_time_taken ->
    skipped (that start time already is a past workout, most likely an earlier sync whose state write was
    lost). Every write is idempotent, so a failed run is simply repeated with the same startTime."""
    program_id, plan = days or program_days(client)
    day, why = resolve_day(plan, w["name"])
    if why:
        return "skipped", why
    nxt = (client.get(f"/workout/next?programId={program_id}&week={day[0]}&dayInWeek={day[1]}") or {}).get("workout")
    if not nxt:
        return "skipped", "Liftosaur returned no workout for that day"
    calls, notes, unknown = build_calls(nxt, w)
    if not calls[1][1]["sets"]:  # never finish an empty Liftosaur workout (progression would run on nothing)
        return "skipped", "no watch set matches a planned exercise: " + "; ".join(notes)
    if dry_run:
        for path, body in calls:
            print_fn(f"POST {path}  {json.dumps(body)}")
        return "dry-run", "; ".join(notes) or "ok"
    start_ms = calls[0][1]["startTime"]
    try:
        cur = (client.get("/workout/current") or {}).get("workout")
        if cur and cur["startTime"] != start_ms:
            return "blocked", f"a workout ({cur.get('dayName')}) is already active in the Liftosaur app"
        started = client.post(*calls[0])["workout"]
        sets, notes, unknown = build_sets(started, w["sets"])  # ids of the workout that now exists
        client.post("/workout/sets", {"sets": sets})
        client.post("/workout/finish", calls[2][1] | {"notes": "; ".join([f"NextSet activity {w['activityId']}"] + notes)})
    except LiftoError as e:
        if e.code == "workout_already_active":
            return "blocked", "a different workout is already active in the Liftosaur app"
        if e.code == "workout_start_time_taken":
            return "skipped", "start time already belongs to a past Liftosaur workout"
        return "failed", str(e)
    return "done", "; ".join(notes) or "ok"
