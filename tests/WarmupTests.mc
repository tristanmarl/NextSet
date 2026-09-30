import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

function warmupTarget(load100 as Number?, reps as Number?) as Dictionary {
    return {"reps" => reps, "load100" => load100, "durationSec" => null, "restSec" => null};
}

// Fixture routine with warmups added to the first two weight entries (a superset pair "Z").
function warmupSession(warmups as Number, superset as Boolean) as Dictionary? {
    var routine = SessionLogic.copyDictionary(workoutFixtureRoutine(1) as Dictionary);
    var source = routine["entries"] as Array;
    var entries = [];
    var marked = 0;
    for (var i = 0; i < source.size(); i++) {
        var entry = SessionLogic.copyDictionary(source[i] as Dictionary);
        entry["superset"] = null;
        if (marked < 2 && Model.sameString(entry["loadType"], "weight") &&
            (entry["workingSetCount"] as Number) >= 2) {
            var list = [];
            for (var w = 0; w < warmups; w++) {
                list.add(warmupTarget(2000 + w * 1000, 8));
            }
            entry["warmups"] = list;
            entry["restSec"] = 60;
            entry["superset"] = superset ? "Z" : null;
            marked++;
        }
        entries.add(entry);
    }
    routine["entries"] = entries;
    var config = {"routines" => [routine], "settings" => {"defaultRestSec" => 90},
        "incrementOverrides" => {}};
    return Catalog.createSession(routine["id"] as String, "wu-1", 1, 1790752141, null, config);
}

function warmupFirst(session as Dictionary) as String {
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        if (SessionLogic.warmupCount(exercises[i] as Dictionary) > 0) {
            return (exercises[i] as Dictionary)["entryId"] as String;
        }
    }
    return "";
}

(:test)
function testWarmupSlotsFlowTotalsAndSkip(logger as Test.Logger) as Boolean {
    var made = warmupSession(2, false);
    var capped = warmupSession(6, false);
    if (made == null || capped == null) {
        return check(logger, false, "warmup fixture sessions are created");
    }
    var session = made as Dictionary;
    var id = warmupFirst(session);
    var exercise = UiFormat.exercise(session, id) as Dictionary;
    var cappedExercise = UiFormat.exercise(capped as Dictionary, warmupFirst(capped as Dictionary)) as Dictionary;
    var created = SessionLogic.warmupCount(exercise) == 2 && SessionLogic.nextSlot(exercise) == 0 &&
        SessionLogic.activeSlot(exercise) == Model.WARMUP_BASE &&
        SessionLogic.warmupCount(cappedExercise) == Model.MAX_WARMUP_SLOTS;
    var valid = Model.validStoredSession(session, false);
    var actual = {"load100" => 2000, "reps" => 8};
    var afterOne = SessionLogic.completeSet(session, id, Model.WARMUP_BASE, actual, 1790752200) as Dictionary;
    var afterExercise = UiFormat.exercise(afterOne, id) as Dictionary;
    var rest = afterOne["rest"] as Dictionary;
    var lap = SessionLogic.lapPayload(afterExercise, Model.WARMUP_BASE);
    var afterTwo = SessionLogic.completeSet(afterOne, id, Model.WARMUP_BASE + 1,
        {"load100" => 3000, "reps" => 8}, 1790752260) as Dictionary;
    var twoExercise = UiFormat.exercise(afterTwo, id) as Dictionary;
    var totalsBefore = SessionLogic.totals(session);
    var totalsAfter = SessionLogic.totals(afterTwo);
    var skipped = SessionLogic.skipWarmups(session, id) as Dictionary;
    var skippedExercise = UiFormat.exercise(skipped, id) as Dictionary;
    var undone = SessionLogic.undoSet(afterOne, id, Model.WARMUP_BASE) as Dictionary;
    return check(logger, created && valid,
            "warmup slots come from the routine (max four) and validate") &&
        check(logger, Model.sameString(rest["entryId"], id) && rest["slot"] == Model.WARMUP_BASE &&
            SessionLogic.activeSlot(afterExercise) == Model.WARMUP_BASE + 1 &&
            Model.validStoredSession(afterOne, false),
            "a logged warmup starts a rest and the next warmup follows") &&
        check(logger, SessionLogic.activeSlot(twoExercise) == 0 && lap != null &&
            (lap as Dictionary)["set"] == 0,
            "working set 1 follows the last warmup; warmup laps use set 0") &&
        check(logger, totalsBefore["done"] == totalsAfter["done"] &&
            totalsBefore["planned"] == totalsAfter["planned"] &&
            SessionLogic.completedWarmups(twoExercise) == 2 && SessionLogic.completedCount(twoExercise) == 0,
            "warmups never count in the working-set totals") &&
        check(logger, SessionLogic.activeSlot(skippedExercise) == 0 &&
            SessionLogic.nextWarmupSlot(skippedExercise) < 0 &&
            SessionLogic.nextSlot(skippedExercise) == 0,
            "skipping warmups goes straight to the working sets") &&
        check(logger, SessionLogic.completedWarmups(UiFormat.exercise(undone, id) as Dictionary) == 0,
            "a warmup can be undone like a working set");
}

(:test)
function testSupersetMemberDoesWarmupsFirst(logger as Test.Logger) as Boolean {
    var made = warmupSession(1, true);
    if (made == null) {
        return check(logger, false, "superset warmup session is created");
    }
    var session = made as Dictionary;
    var exercises = session["exercises"] as Array;
    var ids = [] as Array<String>;
    for (var i = 0; i < exercises.size(); i++) {
        if (SessionLogic.inSuperset(exercises[i] as Dictionary)) {
            ids.add((exercises[i] as Dictionary)["entryId"]);
        }
    }
    var a1 = ids[0];
    var a2 = ids[1];
    var opening = SessionLogic.activeSlot(UiFormat.exercise(session, a1) as Dictionary);
    var afterWarmup = SessionLogic.completeSet(session, a1, Model.WARMUP_BASE,
        {"load100" => 2000, "reps" => 8}, 1790752200) as Dictionary;
    var nextMember = SessionLogic.supersetNext(afterWarmup, a1);
    var stillA1 = SessionLogic.activeSlot(UiFormat.exercise(afterWarmup, a1) as Dictionary);
    var rotated = SessionLogic.completeSet(afterWarmup, a1, 0,
        {"load100" => 5000, "reps" => 8}, 1790752260) as Dictionary;
    return check(logger, opening == Model.WARMUP_BASE && stillA1 == 0 &&
            afterWarmup["rest"] != null,
            "a superset member shows its warmups first and rests after a warmup") &&
        check(logger, Model.sameString(nextMember, a2) && rotated["rest"] == null,
            "the A1/A2 rotation only alternates on working sets");
}

(:test)
function testWarmupUploadMappingExtraAndMissing(logger as Test.Logger) as Boolean {
    var start = 1790752141;
    var end = 1790752201;
    var session = phase2UploadSession("weight", false, start, end);
    var exercise = ((session["exercises"] as Array)[0]) as Dictionary;
    var doneOne = phase2Completed(2000, 8, null, end - 20);
    var doneTwo = phase2Completed(3000, 6, null, end - 15);
    doneOne["slot"] = Model.WARMUP_BASE;
    doneTwo["slot"] = Model.WARMUP_BASE + 1;
    var one = {"draft" => null, "completed" => doneOne};
    var two = {"draft" => null, "completed" => doneTwo};
    exercise["warmupSlots"] = [one, two];
    var job = UploadLogic.makeJob(session) as Dictionary;
    var rows = ((job["exercises"] as Array)[0] as Dictionary)["warmups"] as Array;
    var reply = phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", false, false, "plan");
    var started = UploadLogic.withStartedWorkout(job, reply) as Dictionary;
    var mapped = (started["setsBody"] as Dictionary)["sets"] as Array;
    var warmupRow = null;
    for (var i = 0; i < mapped.size(); i++) {
        if (Model.sameString((mapped[i] as Dictionary)["setId"], "plan-warm")) {
            warmupRow = mapped[i];
        }
    }
    var completed = warmupRow == null ? null : (warmupRow as Dictionary)["completed"] as Dictionary;
    var notes = UploadLogic.finishBody(started)["notes"] as String;
    var none = phase2UploadSession("weight", false, start, end);
    var noneJob = UploadLogic.makeJob(none) as Dictionary;
    var noneStarted = UploadLogic.withStartedWorkout(noneJob, reply) as Dictionary;
    return check(logger, rows.size() == 2 && Model.validUpload(job) && UploadLogic.previewMaps(job, reply),
            "completed warmups are stored on the job and the preview accepts them") &&
        check(logger, completed != null && completed["reps"] == 8 &&
            Model.sameString(completed["weight"], "20kg"),
            "warmup 1 maps to the start reply's first warmup set id") &&
        check(logger, (started["extraWarmups"] as Array).size() == 1 &&
            notes.find("extra warmups: Row x1") != null,
            "warmups beyond the planned ones are listed in the finish notes, not appended") &&
        check(logger, noneStarted["extraWarmups"] == null &&
            ((noneStarted["setsBody"] as Dictionary)["sets"] as Array).size() == 2,
            "unlogged warmups add nothing to the upload");
}
