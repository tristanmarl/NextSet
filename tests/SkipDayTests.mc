import Toybox.Lang;
import Toybox.Test;

// A /workout/next day reply for week 1, day dayInWeek, built on the Phase 2 fixture.
function skipDayReply(name as String, dayInWeek as Number, prefix as String) as Dictionary {
    var reply = phase2ApiWorkout(name, 1l, "Squat", false, false, prefix);
    var workout = problemWorkout(reply);
    workout["dayData"] = {"day" => dayInWeek, "week" => 1, "dayInWeek" => dayInWeek};
    return reply;
}

(:test)
function testSyncSkipsEmptyAndUnsupportedDays(logger as Test.Logger) as Boolean {
    var ok = true;
    var empty = skipDayReply("Rest", 1, "a");
    problemWorkout(empty)["entries"] = [];
    var good = skipDayReply("Legs", 2, "b");
    var noWeight = skipDayReply("Arms", 3, "c");
    problemSet(noWeight, 0)["weight"] = null;
    var first = Catalog.parseRoutine(good, 1, 1) as Dictionary;
    var store = new UploadMemoryStore();
    var seeded = syncSeedStore(store, first);
    var journal = {"sequence" => 2, "phase" => "days", "index" => 0,
        "programId" => "x0001xxx", "programName" => "P", "nextWeek" => 1, "nextDay" => 1,
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "Rest"},
            {"week" => 1, "dayInWeek" => 2, "name" => "Legs"},
            {"week" => 1, "dayInWeek" => 3, "name" => "Arms"}], "routineIds" => []};
    var saved = store.commitPair("rsync", journal);
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, empty);
    syncSettle(controller);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, good);
    syncSettle(controller);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, noWeight);
    syncSettle(controller);
    var after = store.loadRoutineSync() as Dictionary;
    var ids = after["routineIds"] as Array;
    var walked = after["index"] == 3 && ids.size() == 1 &&
        Model.sameString(ids[0], "sync-2-d2");
    var noted = after["skipCount"] == 1 &&
        Model.sameString(after["skipNote"], "W1 D3 Squat: no weight");
    var pivoted = controller.applyRoutineSync(after);
    var config = store.loadPair("config") as Dictionary;
    var nextOk = Model.sameString(config["nextRoutineId"], "sync-2-d2");
    var noError = controller.errorCode() == Err.NONE;
    ok = check(logger, seeded && saved, "fixture store and journal are saved") && ok;
    ok = check(logger, walked, "an empty day and an unsupported day advance without a routine") && ok;
    ok = check(logger, noted, "only the unsupported day is counted, with its reason") && ok;
    ok = check(logger, pivoted && noError, "the sync completes with the supported day") && ok;
    return check(logger, nextOk, "a skipped next day falls back to the next synced day") && ok;
}

(:test)
function testSyncStillStopsOnWrongDay(logger as Test.Logger) as Boolean {
    var ok = true;
    var good = skipDayReply("Legs", 2, "b");
    var first = Catalog.parseRoutine(good, 1, 1) as Dictionary;
    var store = new UploadMemoryStore();
    var seeded = syncSeedStore(store, first);
    var journal = {"sequence" => 2, "phase" => "days", "index" => 0,
        "programId" => "x0001xxx", "programName" => "P", "nextWeek" => 1, "nextDay" => 1,
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "Legs"}], "routineIds" => []};
    var saved = store.commitPair("rsync", journal);
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, good);
    syncSettle(controller);
    var after = store.loadRoutineSync() as Dictionary;
    ok = check(logger, seeded && saved, "fixture store and journal are saved") && ok;
    ok = check(logger, after["index"] == 0, "a reply for another day does not advance the sync") && ok;
    return check(logger, controller.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE,
        "a reply for another day still stops the sync") && ok;
}

(:test)
function testNextRoutineFallbackAndSkipJournal(logger as Test.Logger) as Boolean {
    var ok = true;
    var routines = [{"id" => "d2", "week" => 1, "dayInWeek" => 2},
        {"id" => "d4", "week" => 1, "dayInWeek" => 4}];
    var exact = Catalog.nextRoutineId(routines, 1, 4);
    var later = Catalog.nextRoutineId(routines, 1, 3);
    var wrap = Catalog.nextRoutineId(routines, 1, 5);
    var none = Catalog.nextRoutineId([], 1, 1);
    var store = new UploadMemoryStore();
    var base = {"sequence" => 2, "phase" => "days", "index" => 2,
        "programId" => "x0001xxx", "programName" => "P", "nextWeek" => 1, "nextDay" => 1,
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "A"},
            {"week" => 1, "dayInWeek" => 2, "name" => "B"}],
        "routineIds" => ["sync-2-d2"], "skipCount" => 1, "skipNote" => "W1 D1 Squat: no weight"};
    var accepted = store.commitPair("rsync", base);
    var badCount = SessionLogic.copyDictionary(base);
    badCount["skipCount"] = -1;
    var tooManyIds = SessionLogic.copyDictionary(base);
    tooManyIds["index"] = 0;
    ok = check(logger, Model.sameString(exact, "d4") && Model.sameString(later, "d4"),
        "the next day, or the next synced day after it, is offered") && ok;
    ok = check(logger, Model.sameString(wrap, "d2") && none == null,
        "past the last synced day the first is offered; nothing when none synced") && ok;
    ok = check(logger, accepted, "a journal with fewer routines than days (skips) is valid") && ok;
    ok = check(logger, !store.commitPair("rsync", badCount), "a negative skip count is rejected") && ok;
    return check(logger, !store.commitPair("rsync", tooManyIds),
        "more routine ids than walked days is rejected") && ok;
}

(:test)
function testEmomUploadsRepsAndWeight(logger as Test.Logger) as Boolean {
    var ok = true;
    var plan = {"reps" => 5, "weight" => "60kg", "setTimer" => 60, "timer" => 0};
    var mapped = UploadLogic.mappedCompleted({"unilateral" => false, "unit" => "kg"},
        {"kg" => 60.0, "reps" => 5}, plan, null);
    var hold = UploadLogic.mappedCompleted({"unilateral" => false},
        {"timeSec" => 40}, {"reps" => 1, "weight" => "0kg", "setTimer" => 35}, null);
    var emomOk = mapped != null && mapped["reps"] == 5 &&
        Model.sameString(mapped["weight"], "60kg") && mapped["setTimer"] == null;
    var holdOk = hold != null && hold["reps"] == 1 && hold["setTimer"] == 40;
    ok = check(logger, emomOk, "an EMOM set uploads its reps and weight without a set timer") && ok;
    return check(logger, holdOk, "a one-rep hold still uploads as a timed set") && ok;
}
