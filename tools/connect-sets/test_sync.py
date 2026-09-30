"""Self-check: python test_sync.py (needs fitdecode + garminconnect installed, as sync.py imports them). Offline."""
import datetime as dt
import importlib
import json
import pathlib
import re
import sqlite3
import tempfile

import os
tmp = pathlib.Path(tempfile.mkdtemp())
os.environ["DATA"] = str(tmp)
import sync, archive, liftosaur as lo

T0 = dt.datetime(2026, 1, 1, 10, 0, 0, tzinfo=dt.timezone.utc)
R = "Seated Row"


def lap(offset, secs, exercise, n, reps=10, kg=50.0, duration_s=0, active_s=None):
    return {"active_s": active_s, "start_time": T0 + dt.timedelta(seconds=offset), "total_timer_time": secs,
            "exercise": exercise, "set": n, "reps": reps, "weight_kg": kg, "duration_s": duration_s}


def sets_of(laps):
    return archive.normalize(1, "Upper", T0, T0 + dt.timedelta(hours=1), laps)["sets"]


# --- archive normalization (void / last-wins merge) ---
s = sets_of([lap(0, 100, R, 1, reps=9, kg=55.0, active_s=20)])
assert s == [{"exercise": R, "set": 1, "reps": 9, "weight_kg": 55.0, "duration_s": 0, "active_s": 20,
              "garmin_category": "", "garmin_code": "", "start_time": "2026-01-01T10:00:00Z"}]
# blank closing lap dropped; None weight / codes normalized
s = sets_of([lap(0, 100, R, 1, kg=None) | {"garmin_category": "ROW", "garmin_code": None}, lap(100, 5, "", 0)])
assert len(s) == 1 and s[0]["weight_kg"] == 0 and s[0]["garmin_category"] == "ROW" and s[0]["garmin_code"] == ""
# last lap per (exercise, set) wins (correction); void last lap drops the set (undo); sorted by start
s = sets_of([lap(0, 100, R, 1, reps=10), lap(100, 100, R, 2, reps=8), lap(200, 60, R, 1, reps=9) | {"void": 0}])
assert [x["reps"] for x in s] == [9, 8]
s = sets_of([lap(0, 100, R, 1), lap(100, 100, R, 2), lap(200, 10, R, 2) | {"void": 1}])
assert [x["set"] for x in s] == [1]
s = sets_of([lap(0, 100, R, 1), lap(100, 10, R, 1) | {"void": 1}, lap(110, 100, R, 1, reps=7)])
assert [x["reps"] for x in s] == [7] and s[0]["start_time"] == "2026-01-01T10:01:50Z"  # relog supplies timing
s = sets_of([lap(0, 100, R, 1, reps=10, kg=50.0), lap(300, 5, R, 1, reps=9, kg=55.0)])
assert len(s) == 1 and s[0]["reps"] == 9 and s[0]["weight_kg"] == 55.0 and s[0]["start_time"] == "2026-01-01T10:00:00Z"

# --- archive store: JSON + sqlite, idempotent upsert ---
w = archive.normalize(42, "Upper", T0, T0 + dt.timedelta(minutes=30), [lap(0, 100, R, 1), lap(100, 100, R, 2)])
d = tmp / "arch"
archive.store(d, w)
archive.store(d, w)
assert archive.load(d, 42) == w
db = sqlite3.connect(d / "nextset.db")
assert db.execute("select count(*) from workouts").fetchone() == (1,)
assert db.execute("select count(*) from sets").fetchone() == (2,)
w["sets"] = w["sets"][:1]
archive.store(d, w)  # shrinks: old rows replaced, not appended
assert db.execute("select count(*) from sets").fetchone() == (1,)
assert db.execute("select name, start, end from workouts").fetchone() == ("Upper", "2026-01-01T10:00:00Z", "2026-01-01T10:30:00Z")

# --- Liftosaur matching + call building, fixture = sanitized /workout/next (setIds differ on every GET) ---
def pset(sid, reps, weight, timer=None, uni=False, warm=False):
    return {"setId": sid, "index": 0, "isWarmup": warm, "reps": reps, "weight": weight, "isUnilateral": uni,
            "timer": 90, "setTimer": timer, "completed": None}


NEXT = {"programId": "prog01", "programName": "Fake Program", "dayName": "Lower",
        "dayData": {"day": 2, "week": 1, "dayInWeek": 2}, "startTime": 1790759103151, "entries": [
    {"entryId": "legPress_leverageMachine", "name": "Leg Press", "equipment": "leverageMachine",
     "warmupSets": [pset("aaaaaa", 10, "100kg", warm=True)],
     "sets": [pset("bbbbbb", 9, "200kg"), pset("cccccc", 9, "200kg")]},
    {"entryId": "singleLegHipThrust_leverageMachine", "name": "Single Leg Hip Thrust", "warmupSets": [],
     "sets": [pset("dddddd", 10, "60kg", uni=True)]},
    {"entryId": "pullUp_leverageMachine", "name": "Pull Up", "warmupSets": [], "sets": [pset("eeeeee", 9, "25kg")]},
    {"entryId": "rzrshgtr", "name": "Dead Bug", "warmupSets": [],
     "sets": [pset("ffffff", 1, "0kg", timer=35), pset("gggggg", 1, "0kg", timer=35)]},
    {"entryId": "backExtension_bodyweight", "name": "Back Extension", "warmupSets": [], "sets": [pset("hhhhhh", 10, "0kg")]},
]}


def ws(name, sets, aid=7):
    return {"activityId": aid, "name": name, "start": "2026-09-30T07:09:01Z", "end": "2026-09-30T07:49:01Z",
            "sets": [{"exercise": e, "set": n, "reps": r, "weight_kg": kg, "duration_s": dur, "active_s": 0,
                      "garmin_category": "", "garmin_code": "", "start_time": ""} for e, n, r, kg, dur in sets]}


TEXT = "# Week 1\n## Upper\nSeated Row / 3x9 / 55kg\n## Lower\nLeg Press / 4x9 / 213kg\n"
assert lo.parse_days(TEXT) == [(1, 1, "Upper"), (1, 2, "Lower")]
DAYS = ("prog01", lo.parse_days(TEXT))
assert lo.resolve_day(DAYS[1], " lower ") == ((1, 2), None)
assert lo.resolve_day(DAYS[1], "Push")[0] is None and "no program day" in lo.resolve_day(DAYS[1], "Push")[1]
amb = lo.parse_days(TEXT + "# Week 2\n## Upper\nX / 1x1 / 1kg\n")
assert lo.resolve_day(amb, "Upper") == (None, "2 program days named 'Upper'") and lo.resolve_day(amb, "Lower")[0] == (1, 2)
assert lo.kg_str(62.5) == "62.5kg" and lo.kg_str(-30.0) == "30kg" and lo.kg_str(None) == "0kg" and lo.kg_str(213.0) == "213kg"

W = ws("Lower", [("Leg Press", 1, 9, 213.0, 0), ("Leg Press", 2, 8, 213.0, 0), ("Leg Press", 3, 7, 200.0, 0),  # 3rd = extra
                 ("Single Leg Hip Thrust", 1, 10, 60.0, 0),
                 ("Pull Up", 1, 9, -30.0, 0),
                 ("Dead Bug", 1, 0, 0, 35), ("Dead Bug", 2, 0, 0, 30),
                 ("Leg Curl Machine", 1, 12, 40.0, 0)])  # not in the plan
calls, notes, unknown = lo.build_calls(NEXT, W)
assert [c[0] for c in calls] == ["/workout/start", "/workout/sets", "/workout/finish"]
assert calls[0][1] == {"programId": "prog01", "week": 1, "dayInWeek": 2, "startTime": lo.to_ms(W["start"])}
assert calls[0][1]["startTime"] == 1790752141000
sets = calls[1][1]["sets"]
by = {(c["entryId"], c["setId"]): c for c in sets}
assert by[("legPress_leverageMachine", "bbbbbb")]["completed"] == {"weight": "213kg", "reps": 9}
assert by[("legPress_leverageMachine", "cccccc")]["completed"]["reps"] == 8
app = [c for c in sets if c.get("append")]
assert len(app) == 1 and re.fullmatch(r"[a-z]{6}", app[0]["setId"]) and app[0]["setId"] not in {"aaaaaa", "bbbbbb"}
assert app[0]["entryId"] == "legPress_leverageMachine" and app[0]["completed"] == {"weight": "200kg", "reps": 7}
assert by[("singleLegHipThrust_leverageMachine", "dddddd")]["completed"] == {"weight": "60kg", "reps": 10, "repsLeft": 10}
assert by[("pullUp_leverageMachine", "eeeeee")]["completed"]["weight"] == "30kg"  # assistance sign dropped
assert by[("rzrshgtr", "ffffff")]["completed"] == {"weight": "0kg", "reps": 1, "setTimer": 35}
assert by[("rzrshgtr", "gggggg")]["completed"]["setTimer"] == 30
assert not any(c["setId"] in ("aaaaaa", "hhhhhh") for c in sets)  # warmup and not-done planned sets stay incomplete
assert unknown == ["Leg Curl Machine"]
assert any("Leg Curl Machine" in n for n in notes) and any("Back Extension" in n for n in notes)
fin = calls[2][1]
assert fin["startTime"] == calls[0][1]["startTime"] and fin["endTime"] == lo.to_ms(W["end"]) and "Leg Curl Machine" in fin["notes"]
assert fin["endTime"] - fin["startTime"] == 40 * 60 * 1000
# exact, case-sensitive names; timed/untimed mismatch is left out with a note
c, n, u = lo.build_calls(NEXT, ws("Lower", [("leg press", 1, 9, 213.0, 0), ("Dead Bug", 1, 10, 0, 0)]))
assert c[1][1]["sets"] == [] and u == ["leg press"] and any("Dead Bug set 1" in x for x in n)
# duplicate plan name is ambiguous, not guessed
dup = json.loads(json.dumps(NEXT)); dup["entries"].append(dict(dup["entries"][0], entryId="other"))
c, n, u = lo.build_calls(dup, ws("Lower", [("Leg Press", 1, 9, 213.0, 0)]))
assert c[1][1]["sets"] == [] and any("ambiguous" in x for x in n)


class Fake:
    """Records calls; never touches the network."""
    def __init__(self, nxt=NEXT, cur=None, fail=None):
        self.nxt, self.cur, self.fail, self.log = nxt, cur, fail, []

    def get(self, path):
        self.log.append(("GET", path))
        if path == "/programs/current":
            return {"id": "prog01", "name": "Fake Program", "text": TEXT}
        return {"workout": self.cur if path == "/workout/current" else self.nxt}

    def post(self, path, body):
        self.log.append(("POST", path, body))
        if self.fail:
            raise lo.LiftoError(409, self.fail)
        return {"workout": json.loads(json.dumps(NEXT))}


out = []
f = Fake()
assert lo.sync_one(f, W, True, out.append)[0] == "dry-run" and len(out) == 3 and out[0].startswith("POST /workout/start")
assert all(x[0] == "GET" for x in f.log)  # dry run never writes
f = Fake()
st, _ = lo.sync_one(f, W, False)
assert st == "done" and [x[1] for x in f.log if x[0] == "POST"] == ["/workout/start", "/workout/sets", "/workout/finish"]
assert lo.sync_one(Fake(), ws("Push", []), False)[0] == "skipped"  # no such program day
st, why = lo.sync_one(Fake(), ws("Lower", [("Nope", 1, 5, 1.0, 0)]), False)
assert st == "skipped" and "no watch set matches" in why
f = Fake()  # any day, not only the "next" one: the day is resolved by name and requested explicitly
lo.sync_one(f, ws("Lower", []), True, lambda x: None)
assert ("GET", "/workout/next?programId=prog01&week=1&dayInWeek=2") in f.log
f = Fake()
lo.sync_one(f, ws("Upper", []), True, lambda x: None)
assert ("GET", "/workout/next?programId=prog01&week=1&dayInWeek=1") in f.log
f = Fake(cur={"dayName": "Upper", "startTime": 1})
assert lo.sync_one(f, W, False)[0] == "blocked" and not [x for x in f.log if x[0] == "POST"]  # never touches an app workout
assert lo.sync_one(Fake(cur={"dayName": "Lower", "startTime": lo.to_ms(W["start"])}), W, False)[0] == "done"  # our own retry
assert lo.sync_one(Fake(fail="workout_already_active"), W, False)[0] == "blocked"
assert lo.sync_one(Fake(fail="workout_start_time_taken"), W, False)[0] == "skipped"
assert lo.sync_one(Fake(fail="boom"), W, False)[0] == "failed"
assert re.fullmatch(r"[0-9a-f]{32}", lo.device_id(tmp)) and lo.device_id(tmp) == lo.device_id(tmp)

# liftosaur_pass: cut-off, min duration, final statuses, oldest first, dry run records nothing
sync.ARCHIVE = tmp / "arch2"
now = dt.datetime.now(dt.timezone.utc)
def put(aid, age_h, secs=1800):
    st_ = now - dt.timedelta(hours=age_h)
    archive.store(sync.ARCHIVE, ws("Lower", [], aid) | {"start": archive.iso(st_), "end": archive.iso(st_ + dt.timedelta(seconds=secs))})
put(1, 100); put(2, 5); put(3, 2); put(4, 1, secs=60)  # 4 = a 60 s test log
sync.save_state = lambda s: None
sync.ntfy = lambda t, b: None
sync.liftosaur.program_days = lambda c: DAYS
seen = []
lo.sync_one = lambda c, w, dry, *a, **k: (seen.append(w["activityId"]) or ("done", "ok"))
state = {"done": [], "ignored": []}
sync.LIFTOSAUR_SINCE = None  # unset: writes nothing (never a default window), --only still works
assert sync.liftosaur_pass(state, lifto=object()) == 0 and seen == [] and not state.get("liftosaur")
sync.liftosaur_pass(state, only=1, lifto=object())
assert seen == [1] and state["liftosaur"]["1"]["status"] == "done"
seen.clear(); state = {"done": [], "ignored": []}
sync.LIFTOSAUR_SINCE = now - dt.timedelta(hours=6)
assert sync.liftosaur_pass(state, dry_run=True, lifto=object()) == 0 and seen == [2, 3] and not state.get("liftosaur")
seen.clear()
assert sync.liftosaur_pass(state, lifto=object()) == 0 and seen == [2, 3]
got = {k: v["status"] for k, v in state["liftosaur"].items()}
assert got == {"2": "done", "3": "done", "4": "skipped"} and "LIFTOSAUR_MIN_SEC" in state["liftosaur"]["4"]["detail"]
seen.clear()
sync.liftosaur_pass(state, lifto=object())
assert seen == []  # done/skipped are final
sync.liftosaur_pass(state, only=4, lifto=object())
assert seen == [4]  # --only bypasses the minimum duration too
lo.sync_one = lambda c, w, dry, *a, **k: ("failed", "x")
state = {"done": [], "ignored": []}
assert sync.liftosaur_pass(state, lifto=object()) == 2 and sync.liftosaur_pass(state, lifto=object()) == 2  # retried
assert sync.parse_since("") is None
assert sync.parse_since("1790759103") == dt.datetime.fromtimestamp(1790759103, dt.timezone.utc)
assert sync.parse_since("2026-09-30T07:00:00Z") == dt.datetime(2026, 9, 30, 7, tzinfo=dt.timezone.utc)
assert sync.parse_since("2026-09-30T07:00:00").tzinfo is not None

# alerter: none before threshold, one at threshold, no repeats, one recovery, quiet success
sent = []
a = sync.Alerter(lambda title, body: sent.append((title, body)), 3)
a.record(None)
assert sent == []
a.record("x"); a.record("x")
assert sent == []
a.record("e" * 500)
assert [s[0] for s in sent] == ["NextSet sync failing"] and len(sent[0][1]) == 300
a.record("x"); a.record("x")
assert len(sent) == 1
a.record(None)
assert [s[0] for s in sent] == ["NextSet sync failing", "NextSet sync recovered"]
a.record(None)
assert len(sent) == 2
a.record("x"); a.record(None)  # below threshold then success: nothing
assert len(sent) == 2


# run(): archives new activities, ignores non-NextSet, dry run stores nothing, LIFTOSAUR_SYNC gates the write-back
class Api: pass
sync.client = lambda: Api()
sync.load_state = lambda: {"done": [], "ignored": []}
saved = []
sync.save_state = saved.append
Api.get_activities = lambda self, a, b: [{"activityId": 1, "activityType": {"typeKey": "strength_training"}},
                                         {"activityId": 2, "activityType": {"typeKey": "running"}}]
res = iter(["archived"])
sync.process = lambda api, i, dry=False: next(res)
sync.liftosaur_pass = lambda *a, **k: (_ for _ in ()).throw(AssertionError("LIFTOSAUR_SYNC is 0"))
assert sync.run() == 0 and saved[-1]["done"] == [1]
sync.process = lambda api, i, dry=False: "dry"
n = len(saved)
assert sync.run(dry_run=True) == 0 and len(saved) == n
sync.process = lambda api, i, dry=False: 1 / 0
assert sync.run() == 1  # failure counted, retried next run
sync.LIFTOSAUR_SYNC = True
sync.process = lambda api, i, dry=False: "ignored"
sync.liftosaur_pass = lambda state: 3
assert sync.run() == 3

# corrupt state.json is moved aside and replaced by an empty state
importlib.reload(sync)
t2 = pathlib.Path(tempfile.mkdtemp())
sync.STATE = t2 / "state.json"
sync.STATE.write_text("{not json")
assert sync.load_state() == {"done": [], "ignored": []}
assert not sync.STATE.exists() and len(list(t2.glob("state.json.bad-*"))) == 1
sync.STATE.write_text('{"done": [5], "ignored": []}')
assert sync.load_state()["done"] == [5]
print("ok")
