import Toybox.Lang;
import Toybox.Test;

function makePrefillSnapshot(id as String, type as String, unit as String?, count as Number,
                             load as Number?, reps as Number?, duration as Number?) as Dictionary {
    var slots = [];
    for (var i = 0; i < count; i++) {
        var draft = {"load100" => load, "reps" => reps, "durationSec" => duration};
        slots.add({"draft" => draft, "completed" => null});
    }
    return {"exerciseId" => id, "loadType" => type, "loadUnit" => unit,
        "targetRepsMin" => reps, "targetRepsMax" => reps == null ? null : reps + 4,
        "targetDurationSec" => duration, "slots" => slots, "last" => null};
}

function makeCacheExercise(id as String, type as String, unit as String?, setValues as Array) as Dictionary {
    var slots = [];
    for (var i = 0; i < setValues.size(); i++) {
        var values = setValues[i];
        var completed = null;
        if (values != null) {
            completed = {"load100" => values[0], "reps" => values[1], "durationSec" => values[2]};
        }
        slots.add({"completed" => completed});
    }
    return {"exerciseId" => id, "loadType" => type, "loadUnit" => unit, "slots" => slots};
}

function makeEndedSession(id as String, seq as Number, status as String, endedAt as Number,
                          exercises as Array) as Dictionary {
    return {"id" => id, "sessionSeq" => seq, "status" => status, "completionKind" => "partial",
        "endedAt" => endedAt, "exercises" => exercises};
}

(:test)
function testLastPerformanceMergeAndSparsePrefill(logger as Test.Logger) as Boolean {
    var prior = {"exerciseId" => "row", "loadType" => "weight", "unit" => "kg",
        "sourceSessionId" => "session-4", "sourceSessionSeq" => 4, "sourceEndedAt" => 200,
        "sets" => [[0, 5000, 8, null], [1, 5500, 8, null]]};
    var untouched = {"exerciseId" => "other", "loadType" => "bodyweight", "unit" => null,
        "sourceSessionId" => "session-3", "sourceSessionSeq" => 3, "sourceEndedAt" => 150,
        "sets" => [[0, null, 10, null]]};
    var cache = {"row" => prior, "other" => untouched};
    var row = makeCacheExercise("row", "weight", "kg", [
        [0, 3, null], null, [6500, 7, null]
    ]);
    var session = makeEndedSession("session-5", 5, "completed", 300, [row]);
    var merged = LastPerformance.merge(cache, session);
    var entry = merged["row"] as Dictionary;
    var sets = entry["sets"] as Array;
    var snapshot = makePrefillSnapshot("row", "weight", "kg", 5, 5000, 8, null);
    var filled = LastPerformance.prefill(snapshot, entry);
    var slots = filled["slots"] as Array;
    var d0 = slots[0]["draft"];
    var d1 = slots[1]["draft"];
    var d2 = slots[2]["draft"];

    return check(logger, sets.size() == 2 && (sets[0] as Array)[0] == 0 &&
            (sets[0] as Array)[1] == 0 && (sets[1] as Array)[0] == 2,
            "cache replaces old sets and keeps performed slot order, including zero load") &&
        check(logger, merged["other"] == untouched && prior["sourceSessionSeq"] == 4,
            "merge preserves untouched entries and the source cache") &&
        check(logger, d0["load100"] == 0 && d0["reps"] == 3 &&
            d1["load100"] == 6500 && d1["reps"] == 7 && d2["load100"] == 6500,
            "prefill matches sparse slots and repeats the last performed set") &&
        check(logger, slots[4]["draft"]["reps"] == 7 && slots[0]["completed"] == null &&
            (filled["last"]["sets"] as Array).size() == 2,
            "grown plan is uncompleted and retains the full frozen baseline") &&
        check(logger, snapshot["slots"][0]["draft"]["load100"] == 5000,
            "prefill does not mutate the supplied session snapshot");
}

(:test)
function testLastPerformanceEligibilityAndOrdering(logger as Test.Logger) as Boolean {
    var cache = {"row" => {"exerciseId" => "row", "loadType" => "weight", "unit" => "kg",
        "sourceSessionId" => "session-8", "sourceSessionSeq" => 8, "sourceEndedAt" => 800,
        "sets" => [[0, 6000, 8, null]]}};
    var older = makeEndedSession("session-7", 7, "completed", 700,
        [makeCacheExercise("row", "weight", "kg", [[4500, 8, null]])]);
    var aborted = makeEndedSession("session-9", 9, "aborted", 900,
        [makeCacheExercise("row", "weight", "kg", [[7000, 8, null]])]);
    var mergedOlder = LastPerformance.merge(cache, older);
    var mergedAborted = LastPerformance.merge(cache, aborted);
    return check(logger, mergedOlder["row"]["sourceSessionSeq"] == 8,
            "older sequence must not replace a newer cached performance") &&
        check(logger, mergedAborted["row"]["sourceSessionSeq"] == 8,
            "aborted session must never update previous performance");
}

(:test)
function testLastPerformanceTypesAndDefaults(logger as Test.Logger) as Boolean {
    var assistance = makePrefillSnapshot("assist", "assistance", "kg", 1, 2000, 10, null);
    var assistEntry = {"exerciseId" => "assist", "loadType" => "assistance", "unit" => "kg",
        "sourceSessionId" => "session-2", "sourceSessionSeq" => 2, "sourceEndedAt" => 200,
        "sets" => [[0, 3000, 8, null]]};
    var assistFilled = LastPerformance.prefill(assistance, assistEntry);
    var timed = makePrefillSnapshot("dead-bug", "timed", null, 1, null, null, 35);
    var timedEntry = {"exerciseId" => "dead-bug", "loadType" => "timed", "unit" => null,
        "sourceSessionId" => "session-2", "sourceSessionSeq" => 2, "sourceEndedAt" => 200,
        "sets" => [[0, null, null, 42]]};
    var timedFilled = LastPerformance.prefill(timed, timedEntry);
    var noHistory = LastPerformance.prefill(
        makePrefillSnapshot("unknown", "weight", "kg", 1, null, 9, null), null);
    var mismatch = LastPerformance.prefill(assistance, {"exerciseId" => "assist",
        "loadType" => "weight", "unit" => "kg", "sets" => [[0, 5000, 9, null]]});
    var unitMismatch = LastPerformance.prefill(assistance, {"exerciseId" => "assist",
        "loadType" => "assistance", "unit" => "lb", "sets" => [[0, 3000, 8, null]]});
    var bodyweight = LastPerformance.prefill(makePrefillSnapshot("hyper", "bodyweight", null,
        1, null, 10, null), {"exerciseId" => "hyper", "loadType" => "bodyweight", "unit" => null,
        "sets" => [[0, null, 12, null]]});
    return check(logger, assistFilled["slots"][0]["draft"]["load100"] == 3000,
            "assistance must carry its actual value without progression") &&
        check(logger, timedFilled["slots"][0]["draft"]["durationSec"] == 42 &&
            timedFilled["targetDurationSec"] == 35,
            "timed actual is prefilling independently from the target") &&
        check(logger, bodyweight["slots"][0]["draft"]["reps"] == 12 &&
            bodyweight["slots"][0]["draft"]["load100"] == null,
            "bodyweight history copies reps only") &&
        check(logger, noHistory["slots"][0]["draft"]["load100"] == 0 &&
            noHistory["last"] == null,
            "missing loaded default becomes zero while no-history stays explicit") &&
        check(logger, mismatch["slots"][0]["draft"]["load100"] == 2000 &&
            mismatch["last"] == null && unitMismatch["slots"][0]["draft"]["load100"] == 2000 &&
            unitMismatch["last"] == null,
            "type or unit mismatch must not prefill from another load semantic");
}
