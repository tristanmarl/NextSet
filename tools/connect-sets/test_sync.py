"""Self-check: python test_sync.py (needs fitdecode + garmin-fit-sdk + garminconnect installed, as sync.py imports them)."""
import datetime as dt
import json
import os

os.environ["DATA"] = "/tmp"
import sync

T0 = dt.datetime(2026, 1, 1, 10, 0, 0, tzinfo=dt.timezone.utc)


def lap(offset, secs, exercise, n, reps=10, kg=50.0, duration_s=0, active_s=None):
    return {"active_s": active_s,"start_time": T0 + dt.timedelta(seconds=offset), "total_timer_time": secs,
            "exercise": exercise, "set": n, "reps": reps, "weight_kg": kg, "duration_s": duration_s}


def active(sets):
    return [s for s in sets if s["setType"] == "ACTIVE"]


# normal set: 100 s lap = 60 s rest + ACTIVE_SEC set, weight in grams
s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1)])
assert len(s) == 1 and s[0]["duration"] == sync.ACTIVE_SEC
assert s[0]["repetitionCount"] == 10 and s[0]["weight"] == 50000
assert s[0]["exercises"][0]["category"] == "ROW" and s[0]["messageIndex"] == 0

# active_s (explicit START) is the set duration when >= 3, else the ACTIVE_SEC fallback
s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1, active_s=25)])
assert s[0]["duration"] == 25 and s[0]["repetitionCount"] == 10
for a in (0, 2, None):
    s = active(sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1, active_s=a)]))
    assert s[0]["duration"] == sync.ACTIVE_SEC
# a timed set still uses duration_s even if active_s is present
s = active(sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1, reps=0, duration_s=30, active_s=30)]))
assert s[0]["duration"] == 30

# second set gets a REST before it
s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1), lap(100, 100, "Seated Row Machine", 2)])
assert [x["setType"] for x in s] == ["ACTIVE", "REST", "ACTIVE"]

# timed set: duration from duration_s, no reps
s = active(sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1, reps=0, duration_s=30)]))
assert s[0]["duration"] == 30 and s[0]["repetitionCount"] is None

# assistance (negative kg) and bodyweight -> no weight
for kg in (-30.0, 0, None):
    s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1, kg=kg)])
    assert s[0]["weight"] is None

# blank closing lap and duplicate lap are dropped
s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1), lap(100, 5, "", 0),
                        lap(105, 5, "Seated Row Machine", 1)])
assert len(active(s)) == 1

# 0.2.5 lap codes are used without exercises.json; empty code -> group only; old lap -> exercises.json
s = sync.exercise_sets([lap(0, 100, "Not In Json", 1) | {"garmin_category": "ROW", "garmin_code": "SEATED_CABLE_ROW"}])
assert s[0]["exercises"][0]["category"] == "ROW" and s[0]["exercises"][0]["name"] == "SEATED_CABLE_ROW"
s = sync.exercise_sets([lap(0, 100, "Not In Json", 1) | {"garmin_category": "BENCH_PRESS", "garmin_code": ""}])
assert s[0]["exercises"][0]["category"] == "BENCH_PRESS" and s[0]["exercises"][0]["name"] is None
s = sync.exercise_sets([lap(0, 100, "Seated Row Machine", 1) | {"garmin_category": "", "garmin_code": ""}])
assert s[0]["exercises"][0]["category"] == "ROW"

# unknown exercise raises
try:
    sync.exercise_sets([lap(0, 100, "No Such Exercise", 1)])
    raise SystemExit("expected KeyError")
except KeyError:
    pass

# invalid name -> None, invalid category -> UNKNOWN/None, every exercises.json entry valid
sync.EXERCISES["Bad Name"] = {"category": "ROW", "name": "NOT_A_REAL_NAME"}
sync.EXERCISES["Bad Cat"] = {"category": "NOPE", "name": "X"}
assert sync.garmin_exercise("Bad Name") == ("ROW", None)
sync.EXERCISES["Generic"] = {"category": "BENCH_PRESS", "name": "BENCH_PRESS"}
assert sync.garmin_exercise("Generic") == ("BENCH_PRESS", None)
assert sync.garmin_exercise("Bad Cat") == ("UNKNOWN", None)
for n, e in json.loads(open("exercises.json").read()).items():
    assert sync.garmin_exercise(n) == (e["category"], e["name"]), n

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

print("ok")
