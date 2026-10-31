import Toybox.Lang;
import Toybox.Test;

// Sets that ask for a value (Liftosaur API): RPE, prompted state variables, one-sided timed holds.
function askSession(reply as Dictionary, id as String) as Dictionary? {
    var routine = Catalog.parseRoutine(reply, 1, 1);
    if (routine == null) {
        return null;
    }
    return Catalog.createSession((routine as Dictionary)["id"] as String, id, 1, 1790752141, null,
        {"routines" => [routine], "settings" => {"defaultRestSec" => 90}});
}

function askReply() as Dictionary {
    var reply = phase2ApiWorkout("Ask", 1111111111111l, "Squat", false, false, "ask");
    var workout = (reply["data"] as Dictionary)["workout"] as Dictionary;
    var entry = (workout["entries"] as Array)[0] as Dictionary;
    entry["promptedVars"] = [{"name" => "rpe", "value" => 8}, {"name" => "target", "value" => "225lb"}];
    var first = (entry["sets"] as Array)[0] as Dictionary;
    first["logRpe"] = true;
    first["rpe"] = 7.5;
    return reply;
}

(:test)
function testQuestionValues(logger as Test.Logger) as Boolean {
    var lb = QuestionLogic.parse("225lb");
    var kg = QuestionLogic.parse("102.5kg");
    var pct = QuestionLogic.parse("80%");
    var plain = QuestionLogic.parse(8);
    var lbOk = lb[0] == 225 && Model.sameString(lb[1], "lb") && lb[2] == 5;
    var kgOk = Model.sameString(QuestionLogic.format(kg[0] as Numeric, kg[3] as Boolean), "102.5") &&
        Model.sameString(kg[1], "kg") && kg[2] == 2.5;
    var pctOk = pct[0] == 80 && Model.sameString(pct[1], "%") && pct[2] == 1;
    var plainOk = plain[0] == 8 && Model.sameString(plain[1], "") &&
        Model.sameString(QuestionLogic.format(8.5, true), "8.5") &&
        Model.sameString(QuestionLogic.format(9.0, true), "9");
    return check(logger, lbOk && kgOk, "weights keep their unit and step") &&
        check(logger, pctOk && plainOk, "percentages and plain numbers parse and format");
}

(:test)
function testAskSyncAndQuestions(logger as Test.Logger) as Boolean {
    var session = askSession(askReply(), "ask-1");
    if (session == null) {
        return check(logger, false, "a workout with prompts and RPE syncs");
    }
    var exercise = ((session as Dictionary)["exercises"] as Array)[0] as Dictionary;
    var target = (exercise["planTargets"] as Array)[0] as Dictionary;
    var defaults = exercise["userVars"] as Dictionary;
    var synced = target["logRpe"] == true && target["rpe10"] == 75 &&
        (exercise["prompts"] as Array).size() == 2 && defaults["rpe"] == 8 &&
        Model.sameString(defaults["target"], "225lb");
    var entryId = exercise["entryId"] as String;
    var none = QuestionLogic.afterSet(exercise, entryId, 0).size() == 0;
    var one = SessionLogic.completeSet(session as Dictionary, entryId, 0,
        {"load100" => 6000, "reps" => 10}, 1790752200) as Dictionary;
    var afterFirst = QuestionLogic.afterSet((one["exercises"] as Array)[0] as Dictionary, entryId, 0);
    var two = SessionLogic.completeSet(one, entryId, 1, {"load100" => 6000, "reps" => 10},
        1790752300) as Dictionary;
    var afterLast = QuestionLogic.afterSet((two["exercises"] as Array)[0] as Dictionary, entryId, 1);
    var rpeQuestion = afterFirst.size() == 1 && Model.sameString(afterFirst[0]["kind"], "rpe") &&
        afterFirst[0]["value"] == 75;
    var varQuestions = afterLast.size() == 2 && Model.sameString(afterLast[0]["kind"], "var");
    var rated = SessionLogic.setRpe(two, entryId, 0, 85);
    var answered = rated == null ? null : SessionLogic.setUserVar(rated as Dictionary, entryId, "target", "235lb");
    var stored = answered != null && Model.validStoredSession(answered, false);
    var answeredExercise = answered == null ? null : ((answered as Dictionary)["exercises"] as Array)[0] as Dictionary;
    var values = answeredExercise != null &&
        (Model.slotAt(answeredExercise as Dictionary, 0) as Dictionary)["completed"]["rpe10"] == 85 &&
        Model.sameString((answeredExercise as Dictionary)["userVars"]["target"], "235lb");
    var unknownVar = SessionLogic.setUserVar(two, entryId, "other", 1) == null;
    return check(logger, synced, "RPE targets and prompted variables are kept at sync") &&
        check(logger, none && rpeQuestion, "an RPE set asks for the RPE once it is logged") &&
        check(logger, varQuestions, "prompted variables are asked after the last set") &&
        check(logger, stored && values && unknownVar, "answers are stored and valid");
}

(:test)
function testOneSidedTimedHolds(logger as Test.Logger) as Boolean {
    var session = askSession(phase2ApiWorkout("Side", 1111111111111l, "Plank", true, true, "side"),
        "side-1");
    if (session == null) {
        return check(logger, false, "a one-sided timed workout syncs");
    }
    var entryId = (((session as Dictionary)["exercises"] as Array)[0] as Dictionary)["entryId"] as String;
    var t = 1790752200;
    var left = SessionLogic.completeTimed(SessionLogic.startTimed(session as Dictionary, entryId, 0, t)
        as Dictionary, entryId, 0, t + 30) as Dictionary;
    var leftSlot = Model.slotAt((left["exercises"] as Array)[0] as Dictionary, 0) as Dictionary;
    var leftOk = leftSlot["completed"] == null && leftSlot["draft"]["leftSec"] == 30 &&
        left["timedRun"] == null && Model.validStoredSession(left, false);
    var right = SessionLogic.completeTimed(SessionLogic.startTimed(left, entryId, 0, t + 40)
        as Dictionary, entryId, 0, t + 75) as Dictionary;
    var rightSlot = Model.slotAt((right["exercises"] as Array)[0] as Dictionary, 0) as Dictionary;
    var done = rightSlot["completed"] as Dictionary;
    var rightOk = done["durationSec"] == 35 && done["durationLeftSec"] == 30 &&
        rightSlot["draft"]["leftSec"] == null && Model.validStoredSession(right, false);
    return check(logger, leftOk, "the first hold of a one-sided set is the left side") &&
        check(logger, rightOk, "the second hold completes the set with both sides");
}

(:test)
function testAskUploadValues(logger as Test.Logger) as Boolean {
    var plan = {"reps" => 5, "weight" => "100kg", "logRpe" => true, "rpe" => 7};
    var rated = UploadLogic.mappedCompleted({"unilateral" => false},
        {"kg" => 100.0, "reps" => 5, "rpe10" => 85}, plan, null);
    var unrated = UploadLogic.mappedCompleted({"unilateral" => false},
        {"kg" => 100.0, "reps" => 5}, plan, null);
    var rpeOk = rated != null && rated["rpe"] == 8.5 && unrated != null && unrated["rpe"] == 7;
    var prompted = [{"name" => "rpe", "value" => 8}, {"name" => "target", "value" => "225lb"}];
    var withVars = UploadLogic.mappedCompleted({"unilateral" => false, "userVars" => {"rpe" => 9}},
        {"kg" => 100.0, "reps" => 5}, {"reps" => 5, "weight" => "100kg"}, prompted);
    var vars = withVars == null ? null : withVars["userVars"] as Dictionary?;
    var varsOk = vars != null && vars["rpe"] == 9 && Model.sameString(vars["target"], "225lb");
    var noVars = withVars != null && UploadLogic.mappedCompleted({"unilateral" => false},
        {"kg" => 100.0, "reps" => 5}, {"reps" => 5, "weight" => "100kg"}, [])["userVars"] == null;
    var sided = UploadLogic.mappedCompleted({"unilateral" => true},
        {"kg" => 0.0, "reps" => 1, "timeSec" => 35, "timeLeftSec" => 30},
        {"reps" => 1, "weight" => "0kg", "setTimer" => 35, "isUnilateral" => true}, null);
    var sidedOk = sided != null && sided["setTimer"] == 35 && sided["setTimerLeft"] == 30;
    return check(logger, rpeOk, "RPE uploads as given, else the program's target") &&
        check(logger, varsOk && noVars, "prompted variables upload the answers, else the suggestion") &&
        check(logger, sidedOk, "one-sided timed sets upload both holds");
}
