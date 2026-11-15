import Toybox.Lang;
import Toybox.Test;

// Routine sync without the program text: the first /workout/next gives program, name, week and
// next day; then day 1, 2, ... of that week are asked one by one until the server answers 404
// day_not_found.
module ProbeTests {

    // A /workout/next reply for the given week and day, named name.
    function dayReply(name as String, week as Number, day as Number, prefix as String) as Dictionary {
        var reply = Phase2Tests.phase2ApiWorkout(name, 1l, "Squat", false, false, prefix);
        SyncProblemTests.problemWorkout(reply)["dayData"] = {"day" => day, "week" => week, "dayInWeek" => day};
        return reply;
    }

    function probeJournal(week as Number, nextDay as Number, index as Number, ids as Array) as Dictionary {
        return {"sequence" => 2, "phase" => "probe", "index" => index, "programId" => "x0001xxx",
            "programName" => "Test Program", "nextWeek" => week, "nextDay" => nextDay,
            "routineIds" => ids};
    }

    // A store with the seeded routine and config plus the given journal.
    function probeStore(journal as Dictionary) as UploadStoreTests.UploadMemoryStore {
        var store = new UploadStoreTests.UploadMemoryStore();
        var seed = Catalog.parseRoutine(dayReply("Seed", 1, 1, "s"), 1, 1) as Dictionary;
        SyncTests.syncSeedStore(store, seed);
        store.commitPair("rsync", journal);
        return store;
    }

    function notFound() as Dictionary {
        return {"error" => {"code" => "day_not_found", "message" => "Week 1 day 3 is not in program"}};
    }

    function phaseOf(store as UploadStoreTests.UploadMemoryStore) as String? {
        var journal = store.loadRoutineSync();
        return journal == null ? null : journal["phase"] as String;
    }

    (:test)
    function testFirstReplyFixesProgramNameWeekAndDay(logger as Test.Logger) as Boolean {
        var store = probeStore({"sequence" => 2, "phase" => "first", "index" => 0, "routineIds" => []});
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, dayReply("Week 7 - Day 3", 7, 3, "f"));
        SyncStageTests.syncSettle(controller);
        var journal = store.loadRoutineSync() as Dictionary;
        var ok = WorkoutTests.check(logger, Model.sameString(journal["phase"], "probe") &&
            Model.sameString(journal["programId"], "x0001xxx") &&
            Model.sameString(journal["programName"], "Test Program") &&
            journal["nextWeek"] == 7 && journal["nextDay"] == 3 && journal["index"] == 0 &&
            (journal["routineIds"] as Array).size() == 0 && journal["days"] == null,
            "the first reply starts the probe at day 1 of its week");
        var noName = dayReply("D", 1, 1, "g");
        SyncProblemTests.problemWorkout(noName).remove("programName");
        var rejected = probeStore({"sequence" => 2, "phase" => "first", "index" => 0, "routineIds" => []});
        var rejector = new SessionController(rejected);
        rejector.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, noName);
        var problem = LiftosaurLogic.loadSyncProblem();
        ok = WorkoutTests.check(logger, rejector.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE &&
            problem != null && Model.sameString(problem, "Program name invalid") &&
            Model.sameString(phaseOf(rejected), "first"), "a reply without a program name is rejected") && ok;
        LiftosaurLogic.saveSyncProblem(null);
        return ok;
    }

    (:test)
    function testProbeUsesTheReplyDayName(logger as Test.Logger) as Boolean {
        var store = probeStore(probeJournal(7, 1, 0, []));
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Week 7 - Day 1", 7, 1, "a"));
        SyncStageTests.syncSettle(controller);
        var journal = store.loadRoutineSync() as Dictionary;
        var routine = store.loadPair("routine.sync-2-d1");
        var ok = WorkoutTests.check(logger, journal["index"] == 1 &&
            (journal["routineIds"] as Array).size() == 1 && routine != null,
            "day 1 is committed and the probe moves to day 2");
        return WorkoutTests.check(logger, routine != null &&
            Model.sameString((routine as Dictionary)["name"], "Week 7 - Day 1") &&
            (routine as Dictionary)["week"] == 7 && (routine as Dictionary)["dayInWeek"] == 1,
            "the routine takes the day name from the reply, no name matching") && ok;
    }

    (:test)
    function testProbeEndsAtDayNotFound(logger as Test.Logger) as Boolean {
        var store = probeStore(probeJournal(1, 2, 0, []));
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Push", 1, 1, "a"));
        SyncStageTests.syncSettle(controller);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Pull", 1, 2, "b"));
        SyncStageTests.syncSettle(controller);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 404, notFound());
        SyncStageTests.syncSettle(controller);
        var journal = store.loadRoutineSync() as Dictionary;
        var ok = WorkoutTests.check(logger, Model.sameString(journal["phase"], "probed") &&
            journal["index"] == 2 && (journal["routineIds"] as Array).size() == 2 &&
            controller.errorCode() == Err.NONE, "a 404 day_not_found after day 2 ends the week");
        var applied = controller.applyRoutineSync(journal);
        var config = store.loadPair("config") as Dictionary;
        return WorkoutTests.check(logger, applied && Model.sameString(config["nextRoutineId"], "sync-2-d2") &&
            (config["routineIds"] as Array).size() == 2,
            "the pivot offers Liftosaur's next day (day 2) of the two synced days") && ok;
    }

    (:test)
    function testProbeEndWithoutBodyAndWithOtherCodes(logger as Test.Logger) as Boolean {
        var noBody = probeStore(probeJournal(1, 1, 1, ["sync-2-d1"]));
        var noBodyController = new SessionController(noBody);
        noBodyController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 404, null);
        SyncStageTests.syncSettle(noBodyController);
        var other = probeStore(probeJournal(1, 1, 1, ["sync-2-d1"]));
        var otherController = new SessionController(other);
        otherController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 404,
            {"error" => {"code" => "not_found", "message" => "Program 'x' not found"}});
        var first = probeStore(probeJournal(1, 1, 0, []));
        var firstController = new SessionController(first);
        firstController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 404, notFound());
        var server = probeStore(probeJournal(1, 1, 1, ["sync-2-d1"]));
        var serverController = new SessionController(server);
        serverController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 503, null);
        var ok = WorkoutTests.check(logger, Model.sameString(phaseOf(noBody), "probed"),
            "a 404 whose body could not be read ends the week after day 1");
        ok = WorkoutTests.check(logger, Model.sameString(phaseOf(other), "probe") &&
            otherController.errorCode() == Err.ROUTINE_SYNC_REQUEST_FAILED,
            "a 404 with another code (no program) is an error") && ok;
        ok = WorkoutTests.check(logger, Model.sameString(phaseOf(first), "probe") &&
            firstController.errorCode() == Err.ROUTINE_SYNC_REQUEST_FAILED,
            "a 404 for day 1 is an error, never an empty week") && ok;
        return WorkoutTests.check(logger, Model.sameString(phaseOf(server), "probe") &&
            serverController.errorCode() == Err.NO_RESPONSE_WILL_RETRY,
            "a 503 keeps the journal and asks for a retry") && ok;
    }

    (:test)
    function testProbeStopsAtEightDaysAndNotesAMore(logger as Test.Logger) as Boolean {
        var ids = [];
        for (var d = 1; d <= 7; d++) {
            ids.add("sync-2-d" + d.toString());
        }
        var store = probeStore(probeJournal(1, 1, 7, ids));
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Day 8", 1, 8, "h"));
        SyncStageTests.syncSettle(controller);
        var eighth = store.loadRoutineSync() as Dictionary;
        var ok = WorkoutTests.check(logger, Model.sameString(eighth["phase"], "probe") && eighth["index"] == 8 &&
            store.loadPair("routine.sync-2-d8") != null, "day 8 is the last routine; the probe asks for day 9");
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Day 9", 1, 9, "i"));
        SyncStageTests.syncSettle(controller);
        var ninth = store.loadRoutineSync() as Dictionary;
        ok = WorkoutTests.check(logger, Model.sameString(ninth["phase"], "probed") && ninth["index"] == 8 &&
            store.loadPair("routine.sync-2-d9") == null && ninth["skipNote"] instanceof String &&
            (ninth["skipNote"] as String).find("days 9+ not synced") != null,
            "an existing ninth day is not synced and is noted") && ok;
        var exact = probeStore(probeJournal(1, 1, 8, ids));
        var exactController = new SessionController(exact);
        exactController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 404, notFound());
        SyncStageTests.syncSettle(exactController);
        var exactJournal = exact.loadRoutineSync() as Dictionary;
        return WorkoutTests.check(logger, Model.sameString(exactJournal["phase"], "probed") &&
            exactJournal["skipNote"] == null, "a week of exactly eight days ends quietly") && ok;
    }

    (:test)
    function testProbeSkipsEmptyDayAndKeepsGoing(logger as Test.Logger) as Boolean {
        var store = probeStore(probeJournal(1, 1, 0, []));
        var controller = new SessionController(store);
        var empty = dayReply("Rest", 1, 1, "e");
        SyncProblemTests.problemWorkout(empty)["entries"] = [];
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, empty);
        SyncStageTests.syncSettle(controller);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, dayReply("Legs", 1, 2, "l"));
        SyncStageTests.syncSettle(controller);
        var journal = store.loadRoutineSync() as Dictionary;
        return WorkoutTests.check(logger, journal["index"] == 2 && (journal["routineIds"] as Array).size() == 1 &&
            Model.sameString((journal["routineIds"] as Array)[0], "sync-2-d2"),
            "an empty day advances the probe without a routine");
    }

    (:test)
    function testOldPhasesRestartFromFirst(logger as Test.Logger) as Boolean {
        var stale = Catalog.parseRoutine(dayReply("Old", 1, 3, "o"), 2, 3) as Dictionary;
        var journals = [
            {"sequence" => 2, "phase" => "program", "index" => 0, "routineIds" => []},
            {"sequence" => 2, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
                "programName" => "P", "routineIds" => [], "weeks" => [["A"], ["B", "C"]]},
            {"sequence" => 2, "phase" => "week", "index" => 0, "routineIds" => [],
                "programId" => "x0001xxx", "nextWeek" => 1, "nextDay" => 1},
            {"sequence" => 2, "phase" => "days", "index" => 3, "programId" => "x0001xxx",
                "programName" => "P", "nextWeek" => 1, "nextDay" => 1, "routineIds" => ["sync-2-d3"],
                "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "A"},
                    {"week" => 1, "dayInWeek" => 2, "name" => "B"},
                    {"week" => 1, "dayInWeek" => 3, "name" => "C"}]}];
        var ok = true;
        for (var i = 0; i < journals.size(); i++) {
            var store = probeStore(journals[i] as Dictionary);
            var committed = store.commitPair("routine.sync-2-d3", stale);
            var loadable = store.loadRoutineSync() != null;
            var controller = new SessionController(store);
            controller.retryUploads();
            var after = store.loadRoutineSync();
            ok = WorkoutTests.check(logger, committed && loadable && after != null &&
                Model.sameString((after as Dictionary)["phase"], "first") &&
                (after as Dictionary)["sequence"] == 2 && (after as Dictionary)["index"] == 0 &&
                ((after as Dictionary)["routineIds"] as Array).size() == 0,
                "journal " + i.toString() + " restarts from the first request") && ok;
            // Only the last journal lists a committed routine; it is dropped, the active ones stay.
            ok = WorkoutTests.check(logger, (store.loadPair("routine.sync-2-d3") == null) == (i == 3) &&
                store.loadPair("routine.sync-1-d1") != null,
                "journal " + i.toString() + ": its unused routines go, the active ones stay") && ok;
        }
        return ok;
    }

    (:test)
    function testProbeJournalValidation(logger as Test.Logger) as Boolean {
        var store = new UploadStoreTests.UploadMemoryStore();
        var good = probeJournal(1, 1, 0, []);
        var ok = WorkoutTests.check(logger, store.commitPair("rsync", good), "a probe journal is accepted");
        var done = probeJournal(1, 1, 8, ["sync-2-d1"]);
        done["phase"] = "probed";
        ok = WorkoutTests.check(logger, store.commitPair("rsync", done), "a probed journal is accepted") && ok;
        var noWeek = probeJournal(1, 1, 0, []);
        noWeek.remove("nextWeek");
        var noName = probeJournal(1, 1, 0, []);
        noName.remove("programName");
        var withDays = probeJournal(1, 1, 0, []);
        withDays["days"] = [];
        var tooFar = probeJournal(1, 1, 9, []);
        ok = WorkoutTests.check(logger, !store.commitPair("rsync", noWeek) &&
            !store.commitPair("rsync", noName) && !store.commitPair("rsync", withDays) &&
            !store.commitPair("rsync", tooFar), "probe journals without week or name, with days, or past day 9 are rejected") && ok;
        return ok;
    }
}
