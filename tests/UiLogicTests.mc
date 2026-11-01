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

(:test)
function testReviewStatsAndPlural(logger as Test.Logger) as Boolean {
    var session = {
        "startedAt" => 1000,
        "exercises" => [
            {"plannedSetCount" => 2, "closedEarly" => false,
             "slots" => [{"completed" => {"reps" => 5}}, {"completed" => {"reps" => 5}}]},
            {"plannedSetCount" => 3, "closedEarly" => true,
             "slots" => [{"completed" => {"reps" => 8}}, {"completed" => null}, {"completed" => null}]},
            {"plannedSetCount" => 3, "closedEarly" => false,
             "slots" => [{"completed" => null}, {"completed" => null}, {"completed" => null}]}
        ]
    };
    var stats = UiFormat.reviewStats(session, 1000 + 754);
    var okStats = stats["elapsedSec"] == 754 && stats["sets"] == 3 && stats["exercises"] == 2;
    var early = UiFormat.reviewStats(session, 900);
    var okPlural = Model.sameString(UiFormat.plural(1, "set"), "1 set") &&
        Model.sameString(UiFormat.plural(0, "set"), "0 sets") &&
        Model.sameString(UiFormat.plural(12, "exercise"), "12 exercises");
    return check(logger, okStats, "review stats must count elapsed time, sets and exercises") &&
        check(logger, early["elapsedSec"] == 0 && okPlural, "review time clamps at 0; plurals");
}

(:test)
function testFinishGuardIgnoresEarlyStart(logger as Test.Logger) as Boolean {
    var early = FinishGuard.tooSoon(5000, 5400);
    var later = FinishGuard.tooSoon(5000, 5800);
    var clockWrap = FinishGuard.tooSoon(5000, 4000);
    return check(logger, early && !later && !clockWrap,
        "a START right after a screen opens is ignored, later ones are not");
}

(:test)
function testFinishChoices(logger as Test.Logger) as Boolean {
    var labels = FinishLogic.label(0) + FinishLogic.label(1) + FinishLogic.label(2);
    var okLabels = Model.sameString(labels, "ResumeSaveDiscard");
    var okMove = FinishLogic.move(0, 1) == 1 && FinishLogic.move(1, 1) == 2 &&
        FinishLogic.move(2, 1) == 0 && FinishLogic.move(0, -1) == 2 && FinishLogic.move(2, -1) == 1;
    var resume = FinishLogic.actionFor(FinishLogic.RESUME, 0);
    var saveNone = FinishLogic.actionFor(FinishLogic.SAVE, 0);
    var saveSome = FinishLogic.actionFor(FinishLogic.SAVE, 3);
    var discard = FinishLogic.actionFor(FinishLogic.DISCARD, 3);
    var okResume = Model.sameString(resume, FinishLogic.ACT_RESUME);
    var okSave = Model.sameString(saveNone, FinishLogic.ACT_NEED_SET) &&
        Model.sameString(saveSome, FinishLogic.ACT_SAVE);
    var okDiscard = Model.sameString(discard, FinishLogic.ACT_CONFIRM_DISCARD) &&
        Model.sameString(FinishLogic.actionFor(FinishLogic.DISCARD, 0), FinishLogic.ACT_CONFIRM_DISCARD);
    var okBack = Model.sameString(FinishLogic.backAction(), FinishLogic.ACT_RESUME);
    return check(logger, okLabels && okMove, "Resume, Save, Discard in order; UP/DOWN wrap") &&
        check(logger, okResume && okBack, "Resume is first; BACK resumes") &&
        check(logger, okSave, "Save needs a logged set") &&
        check(logger, okDiscard, "Discard asks for confirmation");
}

(:test)
function testSyncActionByUploadState(logger as Test.Logger) as Boolean {
    var pending = LiftosaurLogic.syncActionable(Liftosaur.STATUS_PENDING, false, true);
    var uploading = LiftosaurLogic.syncActionable(Liftosaur.STATUS_PENDING, true, true);
    var done = LiftosaurLogic.syncActionable(Liftosaur.STATE_DONE, false, true);
    var skipped = LiftosaurLogic.syncActionable(Liftosaur.STATUS_SKIPPED, false, true);
    var noJob = LiftosaurLogic.syncActionable(null, false, true);
    var noKey = LiftosaurLogic.syncActionable(Liftosaur.STATUS_PENDING, false, false);
    return check(logger, pending, "pending or failed upload offers sync") &&
        check(logger, !uploading, "no sync label while uploading") &&
        check(logger, !done && !skipped && !noJob, "no sync label when done, skipped or without a job") &&
        check(logger, !noKey, "no sync label without a Liftosaur key");
}
