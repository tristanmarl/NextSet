import Toybox.Lang;
import Toybox.Test;

(:test)
function testOvertimeAndClockText(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(1, "e1", 0, 1000, 60) as Dictionary;
    var expired = RestClock.expire(rest, 1061) as Dictionary;
    return check(logger, RestClock.overtime(expired, 1095) == 35 && RestClock.overtime(expired, 1000) == 0 &&
            RestClock.overtime(rest, 1095) == 0,
            "overtime counts seconds since an expired rest ended and is 0 otherwise") &&
        check(logger, Model.sameString(UiFormat.clockText(75), "1:15") &&
            Model.sameString(UiFormat.clockText(9), "0:09") &&
            Model.sameString(UiFormat.clockText(99999), "99:59") &&
            Model.sameString(UiFormat.clockText(-4), "0:00"),
            "clock text is m:ss, clamped");
}

(:test)
function testSetConfirmationText(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var id = warmupFirst(session);
    var afterWarmup = SessionLogic.completeSet(session, id, Model.WARMUP_BASE,
        {"load100" => 2000, "reps" => 8}, 1790752200) as Dictionary;
    var afterSet = SessionLogic.completeSet(afterWarmup, id, 0,
        {"load100" => 6550, "reps" => 8}, 1790752230) as Dictionary;
    var exercise = UiFormat.exercise(afterSet, id) as Dictionary;
    return check(logger, Model.sameString(UiFormat.confirmText(exercise, Model.WARMUP_BASE),
            "Warmup 1 · 20 kg × 8") &&
            Model.sameString(UiFormat.confirmText(exercise, 0), "Set 1 · 65.5 kg × 8") &&
            UiFormat.confirmText(exercise, 1) == null,
        "the confirmation names the set, load and reps, and only exists for logged sets");
}

(:test)
function testDraftEditsAreDebouncedIntoOneWrite(logger as Test.Logger) as Boolean {
    var session = warmupSession(0, false) as Dictionary;
    var id = warmupFirst(session);
    var store = onePressStore(session);
    var controller = new SessionController(store);
    var exercise = UiFormat.exercise(controller.session() as Dictionary, id);
    var slotId = exercise == null ? (session["exercises"] as Array)[0]["entryId"] as String : id;
    store.writes = [];
    var first = controller.updateDraft(slotId, 0, "reps", 9);
    var second = controller.updateDraft(slotId, 0, "reps", 10);
    var third = controller.updateDraft(slotId, 0, "reps", 11);
    var before = store.writes.size();
    var shown = ((Model.slotAt(UiFormat.exercise(controller.session() as Dictionary, slotId) as Dictionary, 0)
        as Dictionary)["draft"] as Dictionary)["reps"];
    var pending = controller.hasPendingDraft();
    controller.flushDraft();
    return check(logger, first && second && third && before == 0 && pending && shown == 11,
            "draft edits stay in memory with no storage writes") &&
        check(logger, store.writes.size() == 1 && !controller.hasPendingDraft(),
            "one flush persists all pending edits in a single write");
}

(:test)
function testSummaryUploadStatusMapping(logger as Test.Logger) as Boolean {
    var done = LiftosaurLogic.summaryUpload("done", false, null) as Dictionary;
    var uploading = LiftosaurLogic.summaryUpload("pending", true, null) as Dictionary;
    var failing = LiftosaurLogic.summaryUpload("pending", false, "Phone not connected") as Dictionary;
    var waiting = LiftosaurLogic.summaryUpload("pending", false, null) as Dictionary;
    return check(logger, Model.sameString(done["text"], "Uploaded") && Model.sameString(done["icon"], "check") &&
            Model.sameString(uploading["text"], "Uploading…") && Model.sameString(uploading["icon"], "arrow"),
            "done and in-flight uploads map to their icon and text") &&
        check(logger, Model.sameString(failing["text"], "Phone not connected") &&
            Model.sameString(waiting["text"], "Pending · next launch") &&
            LiftosaurLogic.summaryUpload(null, false, null) == null,
            "errors, waiting and non-Liftosaur workouts map correctly");
}
