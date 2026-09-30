import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

function syncSeedStore(store as UploadMemoryStore, first as Dictionary) as Boolean {
    var ids = [first["id"]];
    return store.commitPair("routine." + (first["id"] as String), first) &&
        store.commitPair("config", {"schemaVersion" => 4, "nextSessionSeq" => 1,
            "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
            "incrementOverrides" => {}, "routineIds" => ids, "routineSyncSeq" => 1,
            "programId" => "x0001xxx", "programName" => "P", "nextRoutineId" => first["id"]});
}

function syncJournal(routine as Dictionary, sequence as Number) as Dictionary {
    return {"sequence" => sequence, "phase" => "days", "index" => 0,
        "programId" => routine["programId"], "programName" => "P",
        "nextWeek" => routine["week"], "nextDay" => routine["dayInWeek"],
        "days" => [{"week" => routine["week"], "dayInWeek" => routine["dayInWeek"],
            "name" => routine["name"]}], "routineIds" => []};
}

(:test)
function testReserveReadsFreshConfigAfterSyncPivot(logger as Test.Logger) as Boolean {
    var upperReply = WatchUi.loadResource(Rez.JsonData.LiftosaurUpper);
    var first = Catalog.parseRoutine(upperReply, 1, 1) as Dictionary;
    var second = Catalog.parseRoutine(upperReply, 2, 1) as Dictionary;
    var store = new UploadMemoryStore();
    var seeded = syncSeedStore(store, first);
    var controller = new SessionController(store);
    var prepared = controller.prepareWorkoutStart(first["id"] as String, 1790752141);
    // A sync pivot lands between prepare and reserve.
    var journal = syncJournal(second, 2);
    journal["phase"] = "days";
    journal["index"] = 1;
    journal["routineIds"] = [second["id"]];
    var stored = store.commitPair("routine." + (second["id"] as String), second);
    var pivoted = controller.applyRoutineSync(journal);
    var reserved = controller.reserveWorkoutStart();
    var config = store.loadPair("config") as Dictionary;
    var ids = config["routineIds"] as Array;
    return check(logger, seeded && prepared && stored && pivoted && reserved,
            "prepare, pivot and reserve all succeed") &&
        check(logger, config["routineSyncSeq"] == 2 && config["nextSessionSeq"] == 2 &&
            ids.size() == 1 && Model.sameString(ids[0], second["id"]),
            "reserve bumps only the session sequence and keeps the pivoted routines");
}

(:test)
function testSyncDayResponseDefersPivot(logger as Test.Logger) as Boolean {
    var upperReply = WatchUi.loadResource(Rez.JsonData.LiftosaurUpper);
    var first = Catalog.parseRoutine(upperReply, 1, 1) as Dictionary;
    var store = new UploadMemoryStore();
    var seeded = syncSeedStore(store, first);
    var journal = syncJournal(first, 2);
    var saved = store.commitPair("rsync", journal);
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, upperReply);
    var after = store.loadRoutineSync() as Dictionary;
    var config = store.loadPair("config") as Dictionary;
    var routine = store.loadPair("routine.sync-2-d1");
    return check(logger, seeded && saved && routine != null && after["index"] == 1 &&
            (after["routineIds"] as Array).size() == 1,
            "the last day is committed and journaled before any pivot work") &&
        check(logger, config["routineSyncSeq"] == 1,
            "the config pivot is left to the deferred continuation");
}

(:test)
function testUploadStateMachineWithCannedResponses(logger as Test.Logger) as Boolean {
    var session = phase2UploadSession("weight", false, 1790752141, 1790752201);
    var job = UploadLogic.makeJob(session) as Dictionary;
    var startTime = job["startTime"] as Long;
    var reply = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "plan");
    var preview = phase2ApiWorkout("DayBx", 1111111111111l, "Row", false, false, "pv");
    var store = new UploadMemoryStore();
    var queued = fixtureQueueUpload(store, job);
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_UPLOAD_PREVIEW, "session-1", 200, preview);
    var afterPreview = (store.loadUpload("session-1") as Dictionary)["state"];
    controller.handleApiResponse(Liftosaur.REQ_UPLOAD_START, "session-1", 200, reply);
    var afterStart = store.loadUpload("session-1") as Dictionary;
    controller.handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", 200, null);
    var afterSets = (store.loadUpload("session-1") as Dictionary)["state"];
    controller.handleApiResponse(Liftosaur.REQ_UPLOAD_FINISH, "session-1", 200, null);
    var statuses = controller.uploadStatuses();
    return check(logger, queued && Model.sameString(afterPreview, Liftosaur.STATE_START),
            "a matching preview leaves the job at start (the start request would follow)") &&
        check(logger, Model.sameString(afterStart["state"], Liftosaur.STATE_SETS) &&
            afterStart["setsBody"] instanceof Dictionary,
            "the start reply persists the mapped sets body") &&
        check(logger, Model.sameString(afterSets, Liftosaur.STATE_FINISH),
            "sets success advances to finish") &&
        check(logger, controller.pendingUploadCount() == 0 &&
            Model.sameString(statuses["session-1"], Liftosaur.STATE_DONE),
            "finish success empties the queue and records the outcome");
}

(:test)
function testWorkoutCurrentAdoptsOurOpenWorkout(logger as Test.Logger) as Boolean {
    var session = phase2UploadSession("weight", false, 1790752141, 1790752201);
    var job = UploadLogic.makeJob(session) as Dictionary;
    var startTime = job["startTime"] as Long;
    var ours = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "cur");
    var theirs = phase2ApiWorkout("DayBx", startTime + 1, "Row", false, false, "cur");
    var adoptStore = new UploadMemoryStore();
    var queuedOurs = fixtureQueueUpload(adoptStore, job);
    new SessionController(adoptStore).handleApiResponse(Liftosaur.REQ_UPLOAD_CURRENT,
        "session-1", 200, ours);
    var adopted = adoptStore.loadUpload("session-1") as Dictionary;
    var blockStore = new UploadMemoryStore();
    var queuedTheirs = fixtureQueueUpload(blockStore, job);
    new SessionController(blockStore).handleApiResponse(Liftosaur.REQ_UPLOAD_CURRENT,
        "session-1", 200, theirs);
    var blocked = blockStore.loadUpload("session-1") as Dictionary;
    return check(logger, queuedOurs && Model.sameString(adopted["state"], Liftosaur.STATE_SETS),
            "an open workout with our start time is adopted like a successful start") &&
        check(logger, queuedTheirs && Model.sameString(blocked["state"], Liftosaur.STATE_BLOCKED),
            "an open workout with another start time keeps the job blocked");
}
