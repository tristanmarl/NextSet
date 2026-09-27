import Toybox.Lang;
import Toybox.Test;

function check(logger as Test.Logger, condition as Boolean, message as String) as Boolean {
    if (!condition) {
        logger.error(message);
        return false;
    }
    return true;
}

(:test)
function testSeedCatalog(logger as Test.Logger) as Boolean {
    var upper = Catalog.template("upper");
    var lower = Catalog.template("lower");
    logger.debug("exercises=" + Catalog.exercises().size() + " templates=" + Catalog.templates().size());
    var defs = Catalog.exercises();
    for (var i = 0; i < defs.size(); i++) {
        if (!Model.validExercise(defs[i])) {
            var exercise = defs[i] as Dictionary;
            logger.debug("invalid " + exercise["id"] + " id=" + Model.validId(exercise["id"]) +
                " name=" + Model.validText(exercise["name"], 64, false) +
                " type=" + Model.validLoadType(exercise["loadType"]) +
                " rest=" + Model.inRange(exercise["defaultRestSec"], 0, Model.MAX_REST_SEC, false) +
                " notes=" + Model.validText(exercise["notes"], 160, true) +
                " increment=" + exercise["increment100"] + " unit=" + exercise["unit"]);
        }
    }
    var allTemplates = Catalog.templates();
    for (var t = 0; t < allTemplates.size(); t++) {
        if (!Model.validTemplate(allTemplates[t])) {
            logger.debug("invalid template " + allTemplates[t]["id"]);
        }
    }
    return check(logger, Catalog.valid(), "seed catalog is invalid") &&
        check(logger, upper != null && Catalog.totalSets(upper as Dictionary) == 19,
            "Upper must contain 19 planned sets") &&
        check(logger, lower != null && Catalog.totalSets(lower as Dictionary) == 17,
            "Lower must contain 17 planned sets");
}

(:test)
function testSessionCommands(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "test-1", 1, 100, null, null) as Dictionary;
    var original = session;
    var row = {};
    row["load100"] = 5500;
    row["reps"] = 9;
    var chest = {};
    chest["load100"] = 6500;
    chest["reps"] = 8;
    var afterRow1 = SessionLogic.completeSet(session, "upper-row", 0, row, 110) as Dictionary;
    var afterChest = SessionLogic.completeSet(afterRow1, "upper-chest", 0, chest, 120) as Dictionary;
    var afterRow2 = SessionLogic.completeSet(afterChest, "upper-row", 1, row, 130) as Dictionary;
    var correctedValues = {};
    correctedValues["load100"] = 5500;
    correctedValues["reps"] = 8;
    var corrected = SessionLogic.correctSet(afterRow2, "upper-row", 0, correctedValues, 200) as Dictionary;
    var correctedRow = (corrected["exercises"] as Array)[0] as Dictionary;
    var correctedSet = ((correctedRow["slots"] as Array)[0] as Dictionary)["completed"] as Dictionary;
    var undo = SessionLogic.undoSet(corrected, "upper-row", 0) as Dictionary;
    var totals = SessionLogic.totals(undo);

    return check(logger, SessionLogic.totals(original)["done"] == 0,
            "candidate writes mutated the original session") &&
        check(logger, totals["done"] == 2 && totals["planned"] == 19,
            "interleaved completion and undo totals are wrong") &&
        check(logger, correctedSet["completedAt"] == 110 && correctedSet["updatedAt"] == 200,
            "correction must preserve completion time") &&
        check(logger, SessionLogic.completeSet(afterRow2, "upper-row", 0, row, 210) == null,
            "duplicate completion was accepted") &&
        check(logger, Model.sameString(SessionLogic.exerciseStatus((undo["exercises"] as Array)[0]), "partial"),
            "undo should reopen a partially completed exercise");
}

(:test)
function testSeedSemantics(logger as Test.Logger) as Boolean {
    var lower = Catalog.createSession("lower", "test-2", 2, 100, null, null) as Dictionary;
    var exercises = lower["exercises"] as Array;
    var press = exercises[0] as Dictionary;
    var hyper = exercises[5] as Dictionary;
    var deadBug = exercises[6] as Dictionary;
    return check(logger, ((press["slots"] as Array)[0]["draft"])["load100"] == 21300,
            "Leg Press must retain 213 kg") &&
        check(logger, Model.sameString(hyper["loadType"], "bodyweight") && hyper["loadUnit"] == null,
            "Hyperextension must be bodyweight") &&
        check(logger, Model.sameString(deadBug["loadType"], "timed") && deadBug["targetDurationSec"] == 35,
            "Dead Bug must be timed with a 35-second target");
}

(:test)
function testTimedSetLifecycle(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("lower", "timed-1", 1, 100, null, null) as Dictionary;
    var running = SessionLogic.startTimed(session, "lower-dead-bug", 0, 100) as Dictionary;
    var run = running["timedRun"] as Dictionary;
    var elapsedAtTarget = SessionLogic.timedElapsedSec(run, 135);
    var slotBeforeTarget = ((running["exercises"] as Array)[6]["slots"] as Array)[0] as Dictionary;
    var paused = SessionLogic.pauseTimed(running, "lower-dead-bug", 0, 135) as Dictionary;
    var pausedDraft = ((paused["exercises"] as Array)[6]["slots"] as Array)[0]["draft"] as Dictionary;
    var resumed = SessionLogic.startTimed(paused, "lower-dead-bug", 0, 200) as Dictionary;
    var secondRunRejected = SessionLogic.startTimed(resumed, "lower-dead-bug", 1, 200) == null;
    var completed = SessionLogic.completeTimed(resumed, "lower-dead-bug", 0, 203) as Dictionary;
    var completedSlot = ((completed["exercises"] as Array)[6]["slots"] as Array)[0] as Dictionary;
    var completedSet = completedSlot["completed"] as Dictionary;
    var canceledStart = SessionLogic.startTimed(completed, "lower-dead-bug", 1, 300) as Dictionary;
    var canceled = SessionLogic.cancelTimed(canceledStart, "lower-dead-bug", 1) as Dictionary;
    var canceledDraft = ((canceled["exercises"] as Array)[6]["slots"] as Array)[1]["draft"] as Dictionary;

    return check(logger, elapsedAtTarget == 35 && slotBeforeTarget["completed"] == null,
            "reaching the target measures time without completing the set") &&
        check(logger, paused["timedRun"] == null && pausedDraft["measuredSec"] == 35,
            "pause checkpoints the elapsed seconds into the slot") &&
        check(logger, secondRunRejected,
            "a second timed set cannot run concurrently") &&
        check(logger, completedSet["durationSec"] == 38 &&
            Model.sameString(completedSet["durationSource"], "measured") &&
            completedSlot["draft"]["measuredSec"] == 0 && completed["timedRun"] == null,
            "resume accumulates whole seconds and completes the measured duration") &&
        check(logger, canceled["timedRun"] == null && canceledDraft["measuredSec"] == 0,
            "cancel clears the timed run and its paused measurement");
}

(:test)
function testNumericTemplateOverrides(logger as Test.Logger) as Boolean {
    var row = {};
    row["workingSetCount"] = 4;
    row["targetRepsMin"] = 8;
    row["targetRepsMax"] = 11;
    row["targetDurationSec"] = 90;
    row["restSec"] = 45;
    row["startingLoad100"] = 5750;
    var chest = {};
    chest["workingSetCount"] = 0;
    chest["targetRepsMin"] = 101;
    chest["startingLoad100"] = -25;
    chest["restSec"] = 9999;
    var upperOverrides = {};
    upperOverrides["upper-row"] = row;
    upperOverrides["upper-chest"] = chest;
    var templateOverrides = {};
    templateOverrides["upper"] = upperOverrides;
    var increments = {};
    increments["seated-row-machine"] = 250;
    increments["machine-chest-press"] = 260;
    var config = {};
    config["templateOverrides"] = templateOverrides;
    config["incrementOverrides"] = increments;

    var session = Catalog.createSession("upper", "overrides", 1, 100, null, config) as Dictionary;
    var exercises = session["exercises"] as Array;
    var rowSnapshot = exercises[0] as Dictionary;
    var chestSnapshot = exercises[1] as Dictionary;
    var rowDraft = ((rowSnapshot["slots"] as Array)[0] as Dictionary)["draft"] as Dictionary;
    var chestDraft = ((chestSnapshot["slots"] as Array)[0] as Dictionary)["draft"] as Dictionary;
    var seedRow = (((Catalog.template("upper") as Dictionary)["entries"] as Array)[0]) as Dictionary;
    var timed = {};
    timed["targetRepsMin"] = 7;
    timed["targetDurationSec"] = 42;
    timed["startingLoad100"] = 1000;
    var lowerOverrides = {};
    lowerOverrides["lower-dead-bug"] = timed;
    var lowerTemplates = {};
    lowerTemplates["lower"] = lowerOverrides;
    var lowerConfig = {};
    lowerConfig["templateOverrides"] = lowerTemplates;
    var lower = Catalog.createSession("lower", "timed-overrides", 2, 100, null, lowerConfig) as Dictionary;
    var deadBug = (lower["exercises"] as Array)[6] as Dictionary;

    return check(logger, rowSnapshot["plannedSetCount"] == 4 &&
            rowSnapshot["targetRepsMin"] == 8 && rowSnapshot["targetRepsMax"] == 11 &&
            rowSnapshot["restSec"] == 45 && rowDraft["load100"] == 5750 &&
            rowSnapshot["weightIncrement100"] == 250,
            "valid row overrides must populate the session snapshot and drafts") &&
        check(logger, rowSnapshot["targetDurationSec"] == null,
            "timed-only override must be ignored for a weight exercise") &&
        check(logger, chestSnapshot["plannedSetCount"] == 3 && chestSnapshot["targetRepsMin"] == 8 &&
            chestDraft["load100"] == 6500 && chestSnapshot["restSec"] == 120 &&
            chestSnapshot["weightIncrement100"] == 500,
            "malformed numeric overrides must fall back to seed values") &&
        check(logger, seedRow["workingSetCount"] == 3 && seedRow["targetRepsMin"] == 9 &&
            seedRow["startingLoad100"] == 5500,
            "creating an overridden session must not mutate seed data") &&
        check(logger, deadBug["targetRepsMin"] == null && deadBug["targetDurationSec"] == 42 &&
            ((deadBug["slots"] as Array)[0] as Dictionary)["draft"]["durationSec"] == 42 &&
            ((deadBug["slots"] as Array)[0] as Dictionary)["draft"]["load100"] == null,
            "timed entry accepts duration while rejecting reps and load overrides");
}

(:test)
function testOverrideSetCeiling(logger as Test.Logger) as Boolean {
    var upperOverrides = {};
    var entries = (Catalog.template("upper") as Dictionary)["entries"] as Array;
    for (var i = 0; i < entries.size(); i++) {
        var entry = entries[i] as Dictionary;
        var override = {};
        override["workingSetCount"] = 10;
        upperOverrides[entry["entryId"] as String] = override;
    }
    var templateOverrides = {};
    templateOverrides["upper"] = upperOverrides;
    var config = {};
    config["templateOverrides"] = templateOverrides;
    var session = Catalog.createSession("upper", "ceiling", 1, 100, null, config) as Dictionary;
    var exerciseList = session["exercises"] as Array;
    var total = 0;
    var allEntryCounts = true;
    for (var i = 0; i < exerciseList.size(); i++) {
        var exerciseSnapshot = exerciseList[i] as Dictionary;
        total += exerciseSnapshot["plannedSetCount"];
        var seedCount = (entries[i] as Dictionary)["workingSetCount"];
        if (exerciseSnapshot["plannedSetCount"] != seedCount) {
            allEntryCounts = false;
        }
    }
    return check(logger, total == Catalog.totalSets(Catalog.template("upper") as Dictionary) &&
            total <= Model.MAX_SETS_PER_WORKOUT && allEntryCounts,
            "over-capacity count overrides must fall back to seed counts without dropping entries");
}
