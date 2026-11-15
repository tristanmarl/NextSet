import Toybox.Lang;
import Toybox.Test;

module EmptyExerciseTests {

    // An entry like Liftosaur's reply for "Back Extension, Bodyweight / 35s+|60s": no set count.
    function emptyEntry(sets as Array) as Dictionary {
        return {"entryId" => "empty-entry-id", "exerciseId" => "empty-exercise-id",
            "equipment" => null, "name" => "Back Extension", "superset" => null,
            "warmupSets" => [], "sets" => sets};
    }

    function entriesOf(reply as Dictionary) as Array {
        return SyncProblemTests.problemWorkout(reply)["entries"] as Array;
    }

    // Week 1 day dayInWeek: the Squat entry of the fixture, then the given extra entry.
    function dayWith(dayInWeek as Number, prefix as String, extra as Dictionary?) as Dictionary {
        var reply = SkipDayTests.skipDayReply("Day" + dayInWeek.toString(), dayInWeek, prefix);
        if (extra != null) {
            entriesOf(reply).add(extra);
        }
        return reply;
    }

    (:test)
    function testEmptyEntryIsLeftOut(logger as Test.Logger) as Boolean {
        var reply = dayWith(2, "a", emptyEntry([]));
        var problem = Model.liftosaurWorkoutProblem(reply);
        var routine = Catalog.parseRoutine(reply, 1, 1);
        var entries = routine == null ? [] : (routine as Dictionary)["entries"] as Array;
        var kept = entries.size() == 1 && Model.sameString((entries[0] as Dictionary)["name"], "Squat") &&
            Model.sameString((entries[0] as Dictionary)["entryId"], "e1");
        var note = Catalog.leftOut != null &&
            Model.sameString(Catalog.leftOut, "W1 D2 Back Extension: no sets, left out");
        var ok = WorkoutTests.check(logger, problem == null, "an entry with empty sets passes the raw walk");
        ok = WorkoutTests.check(logger, routine != null && kept, "the routine keeps the other exercises") && ok;
        return WorkoutTests.check(logger, note, "the left-out exercise is noted") && ok;
    }

    (:test)
    function testWarmupOnlyEntryIsLeftOut(logger as Test.Logger) as Boolean {
        var warm = Phase2Tests.phase2ApiSet("wo-one", 0, "20kg", 8, null, false, true);
        var reply = dayWith(2, "b", emptyEntry([warm]));
        var routine = Catalog.parseRoutine(reply, 1, 1);
        var entries = routine == null ? [] : (routine as Dictionary)["entries"] as Array;
        var ok = WorkoutTests.check(logger, routine != null && entries.size() == 1,
            "an entry with only warmup sets is left out");
        return WorkoutTests.check(logger, Catalog.leftOut != null, "and noted") && ok;
    }

    (:test)
    function testAllEmptyDayAndBadSets(logger as Test.Logger) as Boolean {
        var reply = dayWith(2, "c", null);
        SyncProblemTests.problemWorkout(reply)["entries"] = [emptyEntry([])];
        var routine = Catalog.parseRoutine(reply, 1, 1);
        var ok = WorkoutTests.check(logger, routine == null && Catalog.dayEmpty && Catalog.lastProblem == null,
            "a day whose exercises are all empty is a day without exercises");
        var bad = dayWith(2, "d", emptyEntry([]));
        var badEntry = entriesOf(bad)[1] as Dictionary;
        badEntry["sets"] = "none";
        var badProblem = Model.liftosaurWorkoutProblem(bad);
        ok = WorkoutTests.check(logger, badProblem != null && !Catalog.checkReply(bad),
            "sets that are not a list still reject the day") && ok;
        var badSet = dayWith(2, "e", emptyEntry([]));
        SyncProblemTests.problemSet(badSet, 0)["weight"] = "heavy";
        return WorkoutTests.check(logger, !Catalog.checkReply(badSet),
            "every other entry problem still rejects the day") && ok;
    }

    (:test)
    function testSyncLeavesOutEmptyExercise(logger as Test.Logger) as Boolean {
        var first = dayWith(1, "f", emptyEntry([]));
        var allEmpty = dayWith(2, "g", null);
        SyncProblemTests.problemWorkout(allEmpty)["entries"] = [emptyEntry([])];
        var seedRoutine = Catalog.parseRoutine(dayWith(2, "s", null), 1, 1) as Dictionary;
        var store = new UploadStoreTests.UploadMemoryStore();
        var seeded = SyncTests.syncSeedStore(store, seedRoutine);
        var journal = {"sequence" => 2, "phase" => "probe", "index" => 0,
            "programId" => "x0001xxx", "programName" => "P", "nextWeek" => 1, "nextDay" => 1,
            "routineIds" => []};
        var saved = store.commitPair("rsync", journal);
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, first);
        SyncStageTests.syncSettle(controller);
        var afterFirst = store.loadRoutineSync() as Dictionary;
        var ids = afterFirst["routineIds"] as Array;
        var firstOk = afterFirst["index"] == 1 && ids.size() == 1 && afterFirst["skipCount"] == null &&
            Model.sameString(afterFirst["skipNote"], "W1 D1 Back Extension: no sets, left out");
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, allEmpty);
        SyncStageTests.syncSettle(controller);
        var afterSecond = store.loadRoutineSync() as Dictionary;
        var secondOk = afterSecond["index"] == 2 && (afterSecond["routineIds"] as Array).size() == 1 &&
            afterSecond["skipCount"] == null;
        var pivoted = controller.applyRoutineSync(afterSecond);
        var ok = WorkoutTests.check(logger, seeded && saved, "fixture store and journal are saved");
        ok = WorkoutTests.check(logger, firstOk, "the day syncs with a note and is not counted as skipped") && ok;
        ok = WorkoutTests.check(logger, secondOk, "an all-empty day advances without a routine or skip") && ok;
        return WorkoutTests.check(logger, pivoted && controller.errorCode() == Err.NONE,
            "the sync completes") && ok;
    }

    (:test)
    function testUploadPreviewWithEmptyEntry(logger as Test.Logger) as Boolean {
        var session = Phase2Tests.phase2UploadSession("weight", false, 1790752141, 1790752201);
        var job = UploadLogic.makeJob(session) as Dictionary;
        var preview = Phase2Tests.phase2ApiWorkout("DayBx", 1111111111111l, "Row", false, false, "pv");
        entriesOf(preview).add(emptyEntry([]));
        var front = Phase2Tests.phase2ApiWorkout("DayBx", 1111111111111l, "Row", false, false, "pw");
        var rowEntry = entriesOf(front)[0];
        SyncProblemTests.problemWorkout(front)["entries"] = [emptyEntry([]), rowEntry];
        var maps = UploadLogic.previewMaps(job, preview);
        var mapsFront = UploadLogic.previewMaps(job, front);
        var exact = SyncProblemTests.problemWorkout(preview);
        exact["startTime"] = job["startTime"];
        var started = UploadLogic.withStartedWorkout(job, preview);
        var ok = WorkoutTests.check(logger, maps && mapsFront,
            "the preview maps a reply that holds an exercise without sets");
        return WorkoutTests.check(logger, started != null,
            "a started workout with an empty exercise maps the saved sets") && ok;
    }
}
