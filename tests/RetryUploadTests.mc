import Toybox.Lang;
import Toybox.Test;

// Transient failures are retried, a reply too large for the watch does not lose an applied
// write, a start for our own workout never needs /workout/current, and finish notes stay under
// Liftosaur's limit.
module RetryUploadTests {

    function sampleJob() as Dictionary {
        return UploadLogic.makeJob(
            Phase2Tests.phase2UploadSession("weight", false, 1790752141, 1790752201)) as Dictionary;
    }

    function startReply(job as Dictionary) as Dictionary {
        return Phase2Tests.phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", false, false, "r");
    }

    // A store holding the job after its start reply: state "sets" with the sets body.
    function setsStore() as UploadStoreTests.UploadMemoryStore {
        var job = sampleJob();
        var started = UploadLogic.withStartedWorkout(job, startReply(job)) as Dictionary;
        var store = new UploadStoreTests.UploadMemoryStore();
        WorkoutTests.fixtureQueueUpload(store, started);
        return store;
    }

    function stateOf(store as UploadStoreTests.UploadMemoryStore) as String? {
        var job = store.loadUpload("session-1");
        return job == null ? null : job["state"] as String;
    }

    (:test)
    function testTransientCodesAreRetried(logger as Test.Logger) as Boolean {
        var retry = [408, 429, 500, 502, 503, 504, 599, -1, -2, -3, -4, -5, -101, -103, -300, -1003, -1004];
        var final = [200, 400, 401, 403, 404, 409, 422, 499, 600, 0, -102, -200, -201, -202, -400, -401,
            -402, -403, -1000, -1001, -1002];
        var ok = true;
        for (var i = 0; i < retry.size(); i++) {
            ok = ok && LiftosaurLogic.transportError(retry[i] as Number) == Err.NO_RESPONSE_WILL_RETRY &&
                LiftosaurLogic.retryable(retry[i] as Number);
        }
        var firstOk = WorkoutTests.check(logger, ok, "timeouts, dropped links, 408, 429 and 5xx are retried");
        ok = true;
        for (var i = 0; i < final.size(); i++) {
            ok = ok && LiftosaurLogic.transportError(final[i] as Number) == Err.NONE;
        }
        var secondOk = WorkoutTests.check(logger, ok, "4xx answers, bad requests and too-large replies are not retried");
        return firstOk && secondOk && WorkoutTests.check(logger,
            LiftosaurLogic.transportError(-104) == Err.PHONE_NOT_CONNECTED, "no phone link keeps its own error");
    }

    (:test)
    function testUploadFailuresChooseRetryOrStop(logger as Test.Logger) as Boolean {
        var transient = setsStore();
        var transientController = new SessionController(transient);
        transientController.handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", 503, null);
        var permanent = setsStore();
        var permanentController = new SessionController(permanent);
        permanentController.handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", 400,
            {"error" => {"code" => "invalid_input", "message" => "x"}});
        var ok = WorkoutTests.check(logger, transientController.errorCode() == Err.NO_RESPONSE_WILL_RETRY &&
            Model.sameString(stateOf(transient), Liftosaur.STATE_SETS), "a 503 on sets keeps the job and retries");
        return WorkoutTests.check(logger, permanentController.errorCode() == Err.WORKOUT_UPLOAD_FAILED &&
            Model.sameString(stateOf(permanent), Liftosaur.STATE_SETS), "a 400 is not retried automatically") && ok;
    }

    (:test)
    function testTooLargeReplyToAppliedWrites(logger as Test.Logger) as Boolean {
        var sets = setsStore();
        var setsController = new SessionController(sets);
        setsController.handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", -402, null);
        var oom = setsStore();
        new SessionController(oom).handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", -403, null);
        var ok = WorkoutTests.check(logger, Model.sameString(stateOf(sets), Liftosaur.STATE_FINISH) &&
            setsController.errorCode() == Err.NONE && Model.sameString(stateOf(oom), Liftosaur.STATE_FINISH),
            "a sets reply too large (-402) or out of memory (-403) counts as applied: on to finish");
        var finish = setsStore();
        var finishController = new SessionController(finish);
        finishController.handleApiResponse(Liftosaur.REQ_UPLOAD_SETS, "session-1", 200, null);
        finishController.handleApiResponse(Liftosaur.REQ_UPLOAD_FINISH, "session-1", -402, null);
        var statuses = finishController.uploadStatuses();
        ok = WorkoutTests.check(logger, finishController.pendingUploadCount() == 0 &&
            Model.sameString(statuses["session-1"], Liftosaur.STATE_DONE),
            "a finish reply too large is done") && ok;
        var start = new UploadStoreTests.UploadMemoryStore();
        var job = sampleJob();
        WorkoutTests.fixtureQueueUpload(start, job);
        var startController = new SessionController(start);
        startController.handleApiResponse(Liftosaur.REQ_UPLOAD_START, "session-1", -402, null);
        var saved = start.loadUpload("session-1") as Dictionary;
        return WorkoutTests.check(logger, startController.errorCode() == Err.WORKOUT_UPLOAD_RESPONSE_TOO_LARGE &&
            Model.sameString(saved["state"], Liftosaur.STATE_START) && startController.pendingUploadCount() == 1 &&
            Err.message(Err.WORKOUT_UPLOAD_RESPONSE_TOO_LARGE) != null &&
            Err.shortMessage(Err.WORKOUT_UPLOAD_RESPONSE_TOO_LARGE) != null,
            "a start reply too large is a clear error; the job stays queued to skip") && ok;
    }

    (:test)
    function testStartConflictBlocksWithoutAskingCurrent(logger as Test.Logger) as Boolean {
        var conflict = {"error" => {"code" => Liftosaur.ERR_ALREADY_ACTIVE, "message" => "open"}};
        var ok = true;
        var purposes = [Liftosaur.REQ_UPLOAD_START, Liftosaur.REQ_UPLOAD_RESUME_SETS];
        for (var i = 0; i < purposes.size(); i++) {
            var store = setsStore();
            var controller = new SessionController(store);
            controller.handleApiResponse(purposes[i] as String, "session-1", 409, conflict);
            ok = WorkoutTests.check(logger, Model.sameString(stateOf(store), Liftosaur.STATE_BLOCKED) &&
                controller.errorCode() == Err.WORKOUT_UPLOAD_BLOCKED,
                "409 workout_already_active after " + (purposes[i] as String) + " blocks the job") && ok;
        }
        return ok;
    }

    (:test)
    function testFinishNotesAreCapped(logger as Test.Logger) as Boolean {
        var job = sampleJob();
        job["substitutions"] = [];
        var extras = [];
        for (var i = 0; i < 80; i++) {
            extras.add(WorkoutTests.fixtureRepeat("w", 50));
        }
        job["extraWarmups"] = extras;
        var long = UploadLogic.finishBody(job)["notes"] as String;
        var astral = sampleJob();
        astral["substitutions"] = [];
        astral["extraWarmups"] = [WorkoutTests.fixtureRepeat("💪", 1500)];
        var wide = UploadLogic.finishBody(astral)["notes"] as String;
        var small = sampleJob();
        small["substitutions"] = [];
        small["extraWarmups"] = ["Row x2"];
        var short = UploadLogic.finishBody(small)["notes"] as String;
        var plain = sampleJob();
        plain["substitutions"] = [];
        var none = UploadLogic.finishBody(plain);
        var ok = WorkoutTests.check(logger, long.length() == 2000 && long.find("extra warmups: ") == 0,
            "notes over 2000 characters are cut to 2000");
        ok = WorkoutTests.check(logger, wide.length() == 15 + 992 &&
            UploadLogic.capNotes(WorkoutTests.fixtureRepeat("💪", 1001)).length() == 1000,
            "characters beyond U+FFFF count twice and are never split") && ok;
        return WorkoutTests.check(logger, Model.sameString(short, "extra warmups: Row x2") &&
            !none.hasKey("notes"), "short notes are unchanged and empty notes are not sent") && ok;
    }
}
