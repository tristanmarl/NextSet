import Toybox.Lang;
import Toybox.Test;

// Per-set rest (Liftosaur `timer` of each working set) and AMRAP sets ("3+").
function amrapRestReply() as Dictionary {
    var reply = phase2ApiWorkout("Pull", 1111111111111l, "Pull Up", false, false, "ar");
    problemSet(reply, 0)["timer"] = 20;
    problemSet(reply, 1)["timer"] = 120;
    problemSet(reply, 1)["isAmrap"] = true;
    return reply;
}

(:test)
function testPerSetRestAndAmrapParsed(logger as Test.Logger) as Boolean {
    var routine = Catalog.parseRoutine(amrapRestReply(), 1, 1) as Dictionary;
    var entry = (routine["entries"] as Array)[0] as Dictionary;
    var targets = entry["setTargets"] as Array;
    var first = targets[0] as Dictionary;
    var second = targets[1] as Dictionary;
    var restOk = first["restSec"] == 20 && second["restSec"] == 120;
    var amrapOk = first["amrap"] == null && second["amrap"] == true;
    var session = askSession(amrapRestReply(), "ar-1") as Dictionary;
    var slots = (session["exercises"] as Array)[0]["slots"] as Array;
    var slotRest = (slots[0] as Dictionary)["restSec"] == 20 &&
        (slots[1] as Dictionary)["restSec"] == 120;
    var slotAmrap = (slots[0] as Dictionary)["amrap"] == null &&
        (slots[1] as Dictionary)["amrap"] == true;
    var valid = Model.validPlanTarget(second, "weight");
    var ok = check(logger, restOk, "each set target carries its own timer");
    ok = check(logger, amrapOk, "only the AMRAP set carries the flag") && ok;
    ok = check(logger, slotRest && slotAmrap, "slots copy per-set rest and AMRAP") && ok;
    return check(logger, valid, "the validator accepts the new target fields") && ok;
}

(:test)
function testRestFollowsTheLoggedSet(logger as Test.Logger) as Boolean {
    var session = askSession(amrapRestReply(), "ar-2") as Dictionary;
    var actual = {"load100" => 6000, "reps" => 10};
    var afterFirst = SessionLogic.completeSet(session, "e1", 0, actual, 1790752200) as Dictionary;
    var restFirst = (afterFirst["rest"] as Dictionary)["durationSec"];
    var exercise = (session["exercises"] as Array)[0] as Dictionary;
    var slots = exercise["slots"] as Array;
    (slots[1] as Dictionary).remove("restSec");
    var afterOld = SessionLogic.completeSet(session, "e1", 0, actual, 1790752200) as Dictionary;
    var restFallback = SessionLogic.completeSet(afterOld, "e1", 1, actual, 1790752300) as Dictionary;
    var ok = check(logger, restFirst == 20, "the first set rests for its own 20 s");
    var done = restFallback["rest"] == null;
    ok = check(logger, done, "no rest after the last set") && ok;
    // An exercise without per-set rest (cached before this change) uses the exercise rest.
    (slots[0] as Dictionary).remove("restSec");
    var old = SessionLogic.completeSet(session, "e1", 0, actual, 1790752200) as Dictionary;
    var oldRest = (old["rest"] as Dictionary)["durationSec"];
    return check(logger, oldRest == exercise["restSec"], "old routines fall back to the exercise rest") && ok;
}

(:test)
function testSupersetRoundUsesRestOfLastSlot(logger as Test.Logger) as Boolean {
    var session = phase2SupersetSession() as Dictionary;
    var ids = phase2FirstSuperset(session);
    var a1 = ids[0] as String;
    var a2 = ids[1] as String;
    var ex1 = UiFormat.exercise(session, a1) as Dictionary;
    var ex2 = UiFormat.exercise(session, a2) as Dictionary;
    var slot1 = (ex1["slots"] as Array)[0] as Dictionary;
    var slot2 = (ex2["slots"] as Array)[0] as Dictionary;
    slot1["restSec"] = 30;
    slot2["restSec"] = 45;
    var actual = {"load100" => 5000, "reps" => 8};
    var afterA1 = SessionLogic.completeSet(session, a1, 0, actual, 1790752200) as Dictionary;
    var noRest = afterA1["rest"] == null;
    var afterA2 = SessionLogic.completeSet(afterA1, a2, 0, actual, 1790752260) as Dictionary;
    var roundRest = (afterA2["rest"] as Dictionary)["durationSec"];
    var ok = check(logger, noRest, "no rest inside a superset round");
    return check(logger, roundRest == 45, "the round rests for the slot that ended it") && ok;
}

(:test)
function testAmrapRepsFormatted(logger as Test.Logger) as Boolean {
    var session = askSession(amrapRestReply(), "ar-3") as Dictionary;
    var exercise = (session["exercises"] as Array)[0] as Dictionary;
    var plain = UiFormat.repsText(exercise, 0);
    var amrap = UiFormat.repsText(exercise, 1);
    var line = UiFormat.draftLine(exercise, 1);
    var parts = UiFormat.valueParts(exercise, 1, null, 0);
    var last = (parts[parts.size() - 1] as Array)[0];
    var preview = Navigator.targetPreview(
        ((Catalog.parseRoutine(amrapRestReply(), 1, 1) as Dictionary)["entries"] as Array)[0]["setTargets"] as Array,
        "weight");
    var ok = check(logger, Model.sameString(plain, "10"), "a normal set shows plain reps");
    ok = check(logger, Model.sameString(amrap, "10+"), "an AMRAP set shows N+") && ok;
    ok = check(logger, Model.sameString(line, "60 kg × 10+"), "the next-set line shows N+") && ok;
    ok = check(logger, Model.sameString(last, "10+"), "the big reps part shows N+") && ok;
    return check(logger, Model.sameString(preview, "60×10/60×10+"), "the routine preview shows N+") && ok;
}
