import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

// An active session (with workout clock fields) stored the way commitWorkoutStart would leave it.
function onePressStore(session as Dictionary) as UploadMemoryStore {
    var stored = SessionLogic.copyDictionary(session);
    var clock = WorkoutClock.start(1790752141);
    var keys = clock.keys();
    for (var i = 0; i < keys.size(); i++) {
        stored[keys[i]] = clock[keys[i]];
    }
    stored["fitState"] = "recording";
    var store = new UploadMemoryStore();
    store.commitPair("active", stored);
    return store;
}

function onePressFind(session as Dictionary, type as String) as String {
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        if (Model.sameString((exercises[i] as Dictionary)["loadType"], type)) {
            return (exercises[i] as Dictionary)["entryId"] as String;
        }
    }
    return "";
}

(:test)
function testOnePressLogsWeightBodyweightAndWarmup(logger as Test.Logger) as Boolean {
    var made = warmupSession(1, false);
    var lowerRoutine = workoutFixtureRoutine(2) as Dictionary;
    var lowerConfig = {"routines" => [lowerRoutine], "settings" => {"defaultRestSec" => 90},
        "incrementOverrides" => {}};
    var lower = Catalog.createSession(lowerRoutine["id"] as String, "lw-1", 1, 1790752141, null,
        lowerConfig);
    if (made == null || lower == null) {
        return check(logger, false, "one-press fixture sessions are created");
    }
    var weightSession = made as Dictionary;
    var weightId = warmupFirst(weightSession);
    var weightController = new SessionController(onePressStore(weightSession));
    var warmupSaved = weightController.completeDraft(weightId, Model.WARMUP_BASE, 1790752200);
    var afterWarmup = UiFormat.exercise(weightController.session() as Dictionary, weightId) as Dictionary;
    var workingSaved = weightController.completeDraft(weightId, 0, 1790752230);
    var afterWorking = UiFormat.exercise(weightController.session() as Dictionary, weightId) as Dictionary;
    var bodySession = lower as Dictionary;
    var bodyId = onePressFind(bodySession, "bodyweight");
    var bodyController = new SessionController(onePressStore(bodySession));
    var bodySaved = bodyController.completeDraft(bodyId, 0, 1790752200);
    var afterBody = UiFormat.exercise(bodyController.session() as Dictionary, bodyId) as Dictionary;
    var bodyDone = (Model.slotAt(afterBody, 0) as Dictionary)["completed"] as Dictionary;
    return check(logger, warmupSaved && SessionLogic.completedWarmups(afterWarmup) == 1 &&
            weightController.session()["rest"] != null,
            "one press logs a warmup and starts its rest") &&
        check(logger, workingSaved && SessionLogic.completedCount(afterWorking) == 1 &&
            (Model.slotAt(afterWorking, 0) as Dictionary)["completed"]["activeSec"] == null,
            "one press logs a weight set with no set clock") &&
        check(logger, bodySaved && SessionLogic.completedCount(afterBody) == 1 &&
            bodyDone["reps"] instanceof Number,
            "one press logs a bodyweight set");
}

(:test)
function testTimedSetStillStartsThenLogs(logger as Test.Logger) as Boolean {
    var lowerRoutine = workoutFixtureRoutine(2) as Dictionary;
    var config = {"routines" => [lowerRoutine], "settings" => {"defaultRestSec" => 90},
        "incrementOverrides" => {}};
    var session = Catalog.createSession(lowerRoutine["id"] as String, "tm-1", 1, 1790752141, null,
        config) as Dictionary;
    var timedId = onePressFind(session, "timed");
    var controller = new SessionController(onePressStore(session));
    var started = controller.startTimed(timedId, 0, 1790752200);
    var running = controller.hasRunningTimed();
    var logged = controller.completeTimed(timedId, 0, 1790752235);
    var exercise = UiFormat.exercise(controller.session() as Dictionary, timedId) as Dictionary;
    return check(logger, started && running && logged && SessionLogic.completedCount(exercise) == 1,
        "timed sets still start a countdown and log on the second press");
}

(:test)
function testSessionSavedWithSetClockStillLoads(logger as Test.Logger) as Boolean {
    var session = warmupSession(0, false) as Dictionary;
    var saved = SessionLogic.copyDictionary(session);
    saved["setRun"] = {"entryId" => "e1", "slot" => 0, "startedAt" => 1790752150};
    var store = onePressStore(saved);
    var valid = Model.validStoredSession(saved, false);
    var controller = new SessionController(store);
    var loaded = controller.session();
    return check(logger, valid && loaded != null && controller.hasActiveSession() &&
            (loaded as Dictionary)["setRun"] == null &&
            controller.errorCode() != Err.SAVED_WORKOUT_IS_DAMAGED,
        "a 0.3.1 session with a running set loads with the set clock dropped");
}

(:test)
function testCancelRunsOnlyDiscardSteps(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var store = onePressStore(session);
    var controller = new SessionController(store);
    var id = warmupFirst(session);
    controller.completeDraft(id, 0, 1790752200);
    store.writes = [];
    var started = controller.finish("aborted", 1790752300);
    var finished = false;
    for (var i = 0; i < 5 && !finished; i++) {
        finished = controller.advanceFinalization();
    }
    var foreign = 0;
    for (var i = 0; i < store.writes.size(); i++) {
        if ((store.writes[i] as String).find("active.") != 0) {
            foreign++;
        }
    }
    return check(logger, started && finished && foreign == 0 && store.writes.size() == 2,
            "cancelling writes only the finalizing state and the tombstone (no history, cache or upload)") &&
        check(logger, controller.pendingUploadCount() == 0 && store.peekSession("history0") == null,
            "a cancelled workout leaves no history entry or queued upload");
}

(:test)
function testFinishWithoutActiveWorkoutSetsARealError(logger as Test.Logger) as Boolean {
    var controller = new SessionController(new UploadMemoryStore());
    var finished = controller.finish("aborted", 1790752300);
    return check(logger, !finished && controller.errorCode() == Err.NO_ACTIVE_WORKOUT &&
        Model.sameString(controller.errorMessage(), "No active workout"),
        "finishing without an active workout reports a specific error, not a generic one");
}
