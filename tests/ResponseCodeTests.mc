import Toybox.Lang;
import Toybox.Test;

// A failed Test key or sync names the response code, on screen and in Diagnostics, so a field
// report says what went wrong.
module ResponseCodeTests {

    (:test)
    function testCodeLabels(logger as Test.Logger) as Boolean {
        var http = Model.sameString(LiftosaurLogic.codeLabel(404), "HTTP 404") &&
            Model.sameString(LiftosaurLogic.codeLabel(503), "HTTP 503");
        var ciq = Model.sameString(LiftosaurLogic.codeLabel(-400), "CIQ -400") &&
            Model.sameString(LiftosaurLogic.codeLabel(0), "CIQ 0");
        return WorkoutTests.check(logger, http, "server replies read HTTP n") &&
            WorkoutTests.check(logger, ciq, "Connect IQ errors read CIQ n");
    }

    (:test)
    function testKeyTestFailureTexts(logger as Test.Logger) as Boolean {
        var phone = Model.sameString(LiftosaurLogic.keyTestFailure(-104), "Phone not connected");
        var timeout = Model.sameString(LiftosaurLogic.keyTestFailure(-300), "No response · CIQ -300");
        var server = Model.sameString(LiftosaurLogic.keyTestFailure(502), "No response · HTTP 502");
        var unreadable = Model.sameString(LiftosaurLogic.keyTestFailure(-400), "Request failed · CIQ -400");
        var missing = Model.sameString(LiftosaurLogic.keyTestFailure(404), "Request failed · HTTP 404");
        return WorkoutTests.check(logger, phone, "no phone link keeps its own text") &&
            WorkoutTests.check(logger, timeout && server, "retryable codes read No response with the code") &&
            WorkoutTests.check(logger, unreadable && missing, "other codes read Request failed with the code");
    }

    (:test)
    function testFailedSyncShowsCode(logger as Test.Logger) as Boolean {
        LiftosaurLogic.saveSyncProblem(null);
        var controller = new SessionController(new UploadStoreTests.UploadMemoryStore());
        controller.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, -400, null);
        var codeOk = controller.errorCode() == Err.ROUTINE_SYNC_REQUEST_FAILED;
        var noticeOk = Model.sameString(controller.syncFailedNotice(), "Sync failed · CIQ -400");
        var problem = LiftosaurLogic.loadSyncProblem();
        var problemOk = problem != null && Model.sameString(problem, "Request failed: CIQ -400");
        var diagOk = controller.diagnostics().find("Last sync: Request failed: CIQ -400") != null;
        controller.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 404,
            {"error" => {"code" => "not_found", "message" => "x"}});
        var secondOk = Model.sameString(controller.syncFailedNotice(), "Sync failed · HTTP 404");
        LiftosaurLogic.saveSyncProblem(null);
        var notSent = Model.sameString(LiftosaurLogic.syncFailedNotice(null), "Sync request not sent");
        return WorkoutTests.check(logger, codeOk, "the failure keeps its error code") &&
            WorkoutTests.check(logger, noticeOk && secondOk, "the Home notice names the response code") &&
            WorkoutTests.check(logger, problemOk && diagOk, "Diagnostics names the response code") &&
            WorkoutTests.check(logger, notSent, "a request that never went out says so");
    }
}
