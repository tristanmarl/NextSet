import Toybox.Lang;
import Toybox.Test;

// Runs the staged commits of the last sync reply (the 150 ms timer does it on a watch).
function syncSettle(controller as SessionController) as Void {
    while (controller.pendingSyncSteps() > 0) {
        controller.runPendingSyncStep();
    }
}

function stageJournalFor(program as String) as Dictionary {
    return {"sequence" => 2, "phase" => "days", "index" => 0, "programId" => program,
        "programName" => "P", "nextWeek" => 1, "nextDay" => 1,
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "Day 1"},
            {"week" => 1, "dayInWeek" => 2, "name" => "Day 2"}], "routineIds" => []};
}

// A store holding the seeded routine and config plus the given journal.
function stageStore(journal as Dictionary) as UploadMemoryStore {
    var store = new UploadMemoryStore();
    var seed = Catalog.parseRoutine(issue2Day1(), 1, 1) as Dictionary;
    syncSeedStore(store, seed);
    store.commitPair("rsync", journal);
    return store;
}

// A store over the same stored values with an empty cache: a relaunch of the app.
function relaunch(store as UploadMemoryStore) as UploadMemoryStore {
    var fresh = new UploadMemoryStore();
    fresh.shareValuesWith(store);
    return fresh;
}

function storedRev(store as UploadMemoryStore, key as String) as Number {
    var record = store.values()[key];
    return record instanceof Dictionary ? (record as Dictionary)["rev"] as Number : 0;
}

(:test)
function testRevisionCacheAvoidsRereads(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var ok = check(logger, store.commitPair("rsync", {"sequence" => 1, "phase" => "first",
        "index" => 0, "routineIds" => []}), "first commit");
    var afterFirst = store.reads.size();
    var second = store.commitPair("rsync", {"sequence" => 2, "phase" => "first",
        "index" => 0, "routineIds" => []});
    var third = store.commitPair("rsync", {"sequence" => 3, "phase" => "first",
        "index" => 0, "routineIds" => []});
    ok = check(logger, second && third, "later commits succeed") && ok;
    ok = check(logger, store.reads.size() == afterFirst,
        "later commits read no old envelope") && ok;
    var beforeLoad = store.reads.size();
    var loaded = store.loadRoutineSync();
    ok = check(logger, loaded != null && loaded["sequence"] == 3, "the newest generation loads") && ok;
    ok = check(logger, store.reads.size() == beforeLoad + 1,
        "a load with known revisions reads one generation, not two") && ok;
    return check(logger, storedRev(store, "rsync.a") == 3 && storedRev(store, "rsync.b") == 2,
        "revisions count up across the two generations") && ok;
}

(:test)
function testRevisionCacheAfterFailedWrite(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var journal = {"sequence" => 1, "phase" => "first", "index" => 0, "routineIds" => []};
    var ok = check(logger, store.commitPair("rsync", journal), "commit 1 (a, rev 1)");
    ok = check(logger, store.commitPair("rsync", journal), "commit 2 (b, rev 2)") && ok;
    store.failNextWrite("rsync.a");
    var failed = !store.commitPair("rsync", journal);
    var readsBefore = store.reads.size();
    var retry = store.commitPair("rsync", journal);
    ok = check(logger, failed, "a failed write reports failure") && ok;
    ok = check(logger, store.reads.size() > readsBefore,
        "the cache was dropped: the retry reads the envelopes again") && ok;
    ok = check(logger, retry && storedRev(store, "rsync.a") == 3 && storedRev(store, "rsync.b") == 2,
        "the retry writes the older generation with the next revision") && ok;
    var next = store.commitPair("rsync", journal);
    return check(logger, next && storedRev(store, "rsync.b") == 4,
        "revisions stay in order after the recovery") && ok;
}

(:test)
function testRevisionCacheAcrossRelaunch(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var journal = {"sequence" => 1, "phase" => "first", "index" => 0, "routineIds" => []};
    store.commitPair("rsync", journal);
    store.commitPair("rsync", journal);
    store.commitPair("rsync", journal);
    var again = relaunch(store);
    var ok = check(logger, again.reads.size() == 0, "a relaunched store starts with an empty cache");
    var committed = again.commitPair("rsync", journal);
    ok = check(logger, committed && again.reads.size() == 2,
        "the first commit of the launch reads each envelope once") && ok;
    ok = check(logger, storedRev(store, "rsync.b") == 4, "the revision continues from the stored one") && ok;
    var readsAfter = again.reads.size();
    again.commitPair("rsync", journal);
    ok = check(logger, again.reads.size() == readsAfter && storedRev(store, "rsync.a") == 5,
        "later commits use the cache") && ok;
    // A delete drops the entries: the next commit starts from revision 1 again.
    again.deletePair("rsync");
    var fresh = again.commitPair("rsync", journal);
    return check(logger, fresh && storedRev(store, "rsync.a") == 1, "a delete drops the cache") && ok;
}

(:test)
function testDamagedGenerationIsNotCached(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var journal = {"sequence" => 1, "phase" => "first", "index" => 0, "routineIds" => []};
    store.commitPair("rsync", journal);
    store.writeKey("rsync.b", "garbage");
    store.forgetRevisions("rsync");   // written behind the store's back
    var loaded = store.loadRoutineSync();
    var ok = check(logger, loaded == null && store.hasCorruptRecord(),
        "a damaged generation is still reported");
    var again = store.loadRoutineSync();
    return check(logger, again == null && store.hasCorruptRecord(),
        "and again on the next load (not hidden by the cache)") && ok;
}

// Reply for day 1 of the issue 2 program, and the journal that waits for it.
(:test)
function testJournalResumesBeforeAnyCommit(logger as Test.Logger) as Boolean {
    return boundaryResume(logger, 0);
}

(:test)
function testJournalResumesAfterRoutineCommit(logger as Test.Logger) as Boolean {
    return boundaryResume(logger, 1);
}

(:test)
function testJournalResumesAfterJournalCommit(logger as Test.Logger) as Boolean {
    return boundaryResume(logger, 2);
}

function boundaryResume(logger as Test.Logger, boundary as Number) as Boolean {
    var ok = true;
    {
        var store = stageStore(stageJournalFor("1cc9198d"));
        var controller = new SessionController(store);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, issue2Day1());
        var steps = controller.pendingSyncSteps();
        for (var i = 0; i < boundary; i++) {
            controller.runPendingSyncStep();
        }
        // The app is killed here: only what is stored survives.
        var relaunched = relaunch(store);
        var journal = relaunched.loadRoutineSync() as Dictionary;
        var routine = relaunched.loadPair("routine.sync-2-d1");
        var routineStored = routine != null;
        var pointsPast = journal["index"] == 1;
        ok = check(logger, steps == 2, "a routine day reply stages two commits (boundary " +
            boundary.toString() + ")") && ok;
        ok = check(logger, routineStored == (boundary >= 1), "the routine is stored after step 1 only") && ok;
        ok = check(logger, pointsPast == (boundary == 2), "the journal moves after step 2 only") && ok;
        ok = check(logger, !pointsPast || routineStored, "the journal never points past a missing routine") && ok;
        if (!pointsPast) {
            // Resume: the same day is asked again and the sync completes.
            var resumed = new SessionController(relaunched);
            resumed.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, issue2Day1());
            syncSettle(resumed);
            journal = relaunched.loadRoutineSync() as Dictionary;
        }
        var ids = journal["routineIds"] as Array;
        ok = check(logger, journal["index"] == 1 && ids.size() == 1 &&
            Model.sameString(ids[0], "sync-2-d1"), "the resumed sync reaches day 2 with one routine") && ok;
        var pivot = new SessionController(relaunched);
        ok = check(logger, pivot.applyRoutineSync(journal), "the pivot works from the resumed journal") && ok;
    }
    return ok;
}

(:test)
function testFailedStepStopsWithSaveError(logger as Test.Logger) as Boolean {
    var store = stageStore(stageJournalFor("1cc9198d"));
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, issue2Day1());
    store.failNextWrite("routine.sync-2-d1.a");
    syncSettle(controller);
    var journal = store.loadRoutineSync() as Dictionary;
    var ok = check(logger, controller.errorCode() == Err.ROUTINE_SYNC_SAVE_FAILED,
        "a failed routine commit ends the sync with the save error");
    ok = check(logger, journal["index"] == 0 && controller.pendingSyncSteps() == 0,
        "the journal stays at the day and nothing is left staged") && ok;
    return ok;
}

(:test)
function testNewFlowAsksNextBeforeProgram(logger as Test.Logger) as Boolean {
    var store = stageStore({"sequence" => 2, "phase" => "first", "index" => 0, "routineIds" => []});
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, issue2Day1());
    syncSettle(controller);
    var week = store.loadRoutineSync() as Dictionary;
    var weekOk = Model.sameString(week["phase"], "week") &&
        Model.sameString(week["programId"], "1cc9198d") && week["nextWeek"] == 1 &&
        week["nextDay"] == 1 && week["programName"] == null;
    // A relaunch in this phase resumes by asking /programs/current.
    var resumed = new SessionController(relaunch(store));
    resumed.handleApiResponse(Liftosaur.REQ_SYNC_PROGRAM, null, 200, {"data" => issue2Program()});
    syncSettle(resumed);
    var days = relaunch(store).loadRoutineSync() as Dictionary;
    var rows = days["days"] as Array;
    var ok = check(logger, weekOk, "the first reply fixes program, week and day");
    ok = check(logger, Model.sameString(days["phase"], "days") && days["weeks"] == null &&
        rows.size() == 2 && Model.sameString(rows[1]["name"], "Day 2") &&
        Model.sameString(days["programName"], "Fighter progressive overload"),
        "the program reply keeps only the current week's days") && ok;
    return check(logger, resumed.errorCode() == Err.NONE, "no sync error") && ok;
}

(:test)
function testWeekPhaseRejectsOtherProgram(logger as Test.Logger) as Boolean {
    var store = stageStore({"sequence" => 2, "phase" => "week", "index" => 0, "routineIds" => [],
        "programId" => "othertxt", "nextWeek" => 1, "nextDay" => 1});
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_PROGRAM, null, 200, {"data" => issue2Program()});
    syncSettle(controller);
    var journal = store.loadRoutineSync() as Dictionary;
    var problem = LiftosaurLogic.loadSyncProblem();
    var ok = check(logger, Model.sameString(journal["phase"], "week"), "the journal stays in the week phase");
    return check(logger, controller.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE &&
        problem != null && Model.sameString(problem, "Program changed during sync"),
        "a program that differs from /workout/next is rejected with a reason") && ok;
}

(:test)
function testParseDaysForKeepsOneWeek(logger as Test.Logger) as Boolean {
    var text = "# Week 1\n## A\n## B\n# Week 2\n## C\n# Week 3 - Deload\n## D\n## E\n";
    var weeks = LiftosaurLogic.parseDaysFor(text, 3) as Array;
    var ok = check(logger, weeks.size() == 3 && weeks[0] == null && weeks[1] == null,
        "other weeks are not stored but still counted");
    var names = weeks[2] as Array;
    ok = check(logger, names.size() == 2 && Model.sameString(names[1], "E"), "the wanted week keeps its names") && ok;
    var rows = LiftosaurLogic.weekDayRows(weeks, 3) as Array;
    ok = check(logger, rows.size() == 2 && rows[1]["dayInWeek"] == 2, "weekDayRows reads it") && ok;
    ok = check(logger, LiftosaurLogic.weekDayRows(weeks, 1) == null, "an unstored week has no rows") && ok;
    // Validation still covers every header, also in weeks that are not kept.
    var bad = LiftosaurLogic.parseDaysFor("# Week 1\n##Broken\n# Week 2\n## C\n", 2);
    ok = check(logger, bad == null && LiftosaurLogic.parseProblem != null, "a bad header in another week is rejected") && ok;
    var implicit = LiftosaurLogic.parseDaysFor("## A\n## B\n", 1) as Array;
    ok = check(logger, (implicit[0] as Array).size() == 2, "days before a header are week 1") && ok;
    var beyond = LiftosaurLogic.parseDaysFor("# Week 1\n## A\n", 4) as Array;
    return check(logger, beyond.size() == 1 && LiftosaurLogic.weekDayRows(beyond, 4) == null,
        "a week past the program is not found") && ok;
}

(:test)
function testOldJournalPhasesStillResume(logger as Test.Logger) as Boolean {
    // Phase "program" and "next" (with weeks or a flat day list) validate and advance as before.
    var program = {"sequence" => 1, "phase" => "program", "index" => 0, "routineIds" => []};
    var next = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [], "weeks" => [["A"], ["B", "C"]]};
    var flat = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [],
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "A"}]};
    var store = new UploadMemoryStore();
    var ok = check(logger, store.commitPair("rsync", program), "program phase is accepted");
    ok = check(logger, store.commitPair("rsync", next), "next phase with weeks is accepted") && ok;
    ok = check(logger, store.commitPair("rsync", flat), "next phase with days is accepted") && ok;
    var week = {"sequence" => 1, "phase" => "week", "index" => 0, "routineIds" => [],
        "programId" => "x0001xxx", "nextWeek" => 1, "nextDay" => 1};
    ok = check(logger, store.commitPair("rsync", week), "week phase is accepted") && ok;
    week["programName"] = "P";
    ok = check(logger, !store.commitPair("rsync", week), "week phase with a program name is rejected") && ok;
    return ok;
}

(:test)
function testSyncMemoryGuardRules(logger as Test.Logger) as Boolean {
    var ok = check(logger, LiftosaurLogic.syncMemoryNeed(Liftosaur.REQ_SYNC_DAY) > 0 &&
        LiftosaurLogic.syncMemoryNeed(Liftosaur.REQ_SYNC_PROGRAM) > 0 &&
        LiftosaurLogic.syncMemoryNeed(Liftosaur.REQ_SYNC_NEXT) > 0, "sync requests need free memory");
    ok = check(logger, LiftosaurLogic.syncMemoryNeed(Liftosaur.REQ_UPLOAD_START) == 0 &&
        LiftosaurLogic.syncMemoryNeed(Liftosaur.REQ_KEY_TEST) == 0, "other requests are not guarded") && ok;
    return check(logger, Err.message(Err.SYNC_LOW_MEMORY) != null &&
        Err.shortMessage(Err.SYNC_LOW_MEMORY) != null, "the low-memory error has both texts") && ok;
}
