import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

function resilienceActiveWrites(store as UploadMemoryStore) as Number {
    var count = 0;
    for (var i = 0; i < store.writes.size(); i++) {
        if ((store.writes[i] as String).find("active.") == 0) {
            count++;
        }
    }
    return count;
}

// The 2026-10-29 firmware crash came in the second a rest expired, when the session save, the
// 1 s vibration and the redraw all ran in one tick. The save now follows ~2 s later.
(:test)
function testRestExpiryVibratesWithoutSaving(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var store = onePressStore(session);
    var controller = new SessionController(store);
    var id = warmupFirst(session);
    var logged = controller.completeDraft(id, 0, 1790752200);
    var rest = controller.session()["rest"] as Dictionary?;
    if (!logged || rest == null) {
        return check(logger, false, "a logged set starts a rest");
    }
    var endsAt = (rest as Dictionary)["endsAt"] as Number;
    store.writes = [];
    var alert = controller.onTick(endsAt, true);
    var expired = Model.sameString(controller.session()["rest"]["state"], "expired");
    var writesAtExpiry = resilienceActiveWrites(store);
    var pending = controller.hasPendingDraft();
    var again = controller.onTick(endsAt + 1, true);
    controller.flushDraft();
    var writesAfterFlush = resilienceActiveWrites(store);
    var reloaded = new SessionController(store);
    var reloadedRest = reloaded.session()["rest"] as Dictionary;
    var ok1 = check(logger, alert && expired, "rest expiry still alerts and marks the rest expired");
    var ok2 = check(logger, writesAtExpiry == 0 && pending, "rest expiry does not write the session in the alert tick");
    var ok3 = check(logger, !again, "the rest alert fires once");
    return ok1 && ok2 && ok3 && check(logger, writesAfterFlush == 1 && Model.sameString(reloadedRest["state"], "expired"),
        "the deferred flush saves the expired rest once");
}

(:test)
function testCheckpointWritesOnlyTheSmallKey(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var store = onePressStore(session);
    var controller = new SessionController(store);
    var last = controller.session()["lastCheckpointAt"] as Number;
    store.writes = [];
    var early = controller.checkpoint(last + 10);
    var writesEarly = store.writes.size();
    var due = controller.checkpoint(last + 31);
    var onlyKey = store.writes.size() == 1 && Model.sameString(store.writes[0], "ckpt");
    var id = session["id"] as String;
    var ok1 = check(logger, early && writesEarly == 0, "no checkpoint write within 30 s");
    var ok2 = check(logger, due && onlyKey, "a due checkpoint writes only the ckpt key, not the session");
    var ok3 = check(logger, controller.session()["lastCheckpointAt"] == last + 31,
        "the checkpoint time is kept in memory for the next commit");
    return ok1 && ok2 && ok3 && check(logger, store.loadCheckpoint(id) == last + 31 && store.loadCheckpoint("other") == null,
        "the checkpoint key is read back only for its own session");
}

(:test)
function testRecoveryUsesTheCheckpointKey(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var plain = onePressStore(session);
    var withKey = onePressStore(session);
    // onePressStore saves lastCheckpointAt = 1790752141; the key says the app was alive 59 s later.
    withKey.saveCheckpoint(session["id"] as String, 1790752200);
    var gapPlain = new SessionController(plain).session()["recoveryGapSec"] as Number;
    var gapKey = new SessionController(withKey).session()["recoveryGapSec"] as Number;
    var future = onePressStore(session);
    future.saveCheckpoint(session["id"] as String, Time.now().value() + 3600);
    var gapFuture = new SessionController(future).session()["recoveryGapSec"] as Number;
    var ok = check(logger, gapPlain - gapKey >= 58 && gapPlain - gapKey <= 60,
        "recovery excludes only the time after the newer checkpoint key");
    return ok && check(logger, gapFuture - gapPlain >= -1 && gapFuture - gapPlain <= 1,
        "a checkpoint key in the future is ignored");
}

(:test)
function testActiveCommitsSkipStoredReads(logger as Test.Logger) as Boolean {
    var session = warmupSession(1, false) as Dictionary;
    var store = onePressStore(session);
    var first = SessionLogic.copyDictionary(session);
    first["sessionSeq"] = 2;
    var second = SessionLogic.copyDictionary(session);
    second["sessionSeq"] = 3;
    store.reads = [];
    var savedFirst = store.commitPair("active", first);
    var savedSecond = store.commitPair("active", second);
    var activeReads = 0;
    for (var i = 0; i < store.reads.size(); i++) {
        if ((store.reads[i] as String).find("active.") == 0) {
            activeReads++;
        }
    }
    var loaded = store.loadPair("active") as Dictionary?;
    var ok = check(logger, savedFirst && savedSecond && activeReads == 0,
        "commits after the first do not read the stored sessions back");
    return ok && check(logger, loaded != null && (loaded as Dictionary)["sessionSeq"] == 3,
        "the newest commit is still the one loaded");
}

(:test)
function testFitTextFitsTheByteLimit(logger as Test.Logger) as Boolean {
    var plain = "Seated Row";
    var umlauts = "";
    for (var i = 0; i < 40; i++) {
        umlauts += "ä";
    }
    var cut = StrengthRecorder.fitText(umlauts, 64);
    var ok = check(logger, Model.sameString(StrengthRecorder.fitText(plain, 64), plain), "short names are unchanged");
    return ok && check(logger, cut.length() == 32 && cut.toUtf8Array().size() == 64,
        "long multibyte names are cut at whole characters to 64 bytes");
}

// liftosaur2garmin failed on the "// NextSet session …" line every NextSet workout carried, and
// Liftosaur recorded "duration: 2s" without intervals.
(:test)
function testFinishBodySendsIntervalsAndNoRoutineNote(logger as Test.Logger) as Boolean {
    var job = UploadLogic.makeJob(phase2UploadSession("weight", false, 1790752141, 1790755141)) as Dictionary;
    job["substitutions"] = [];
    job.remove("extraWarmups");
    var body = UploadLogic.finishBody(job);
    var intervals = body["intervals"] as Array?;
    var first = intervals == null || intervals.size() != 1 ? null : intervals[0] as Array;
    var ok = check(logger, body["notes"] == null, "a workout with nothing to report sends no notes");
    return ok && check(logger, first != null && first.size() == 2 &&
            (first[0] as Long).compareTo(job["startTime"] as Long) == 0 &&
            (first[1] as Long).compareTo(job["endTime"] as Long) == 0,
        "finish sends one interval from the workout start to its end");
}
