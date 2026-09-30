import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

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
function testGarminCodeMayBeNull(logger as Test.Logger) as Boolean {
    var chest = Catalog.exercise("machine-chest-press") as Dictionary;
    var routine = sizedRoutine("null-code", 0, 8, 8, 8, 0);
    var first = (routine["entries"] as Array)[0] as Dictionary;
    first["garminCode"] = null;
    var sawGroupOnly = false;
    var categories = Catalog.garminCategories();
    for (var c = 0; c < categories.size(); c++) {
        var count = Catalog.garminEntries(c).size();
        for (var i = 0; i < count; i++) {
            var code = Catalog.garminRow(c, i)["code"];
            if (code == null) {
                sawGroupOnly = true;
            } else if (!check(logger, (code as String).substring(0, 1).equals("_") == false,
                "catalog code has the Connect-only leading underscore: " + code)) {
                return false;
            }
        }
    }
    return check(logger, Model.sameString(chest["garminCategory"], "BENCH_PRESS") &&
            chest["garminCode"] == null, "Chest Press must be group-only BENCH_PRESS") &&
        check(logger, Catalog.validRoutine(routine), "routine with a null garminCode must be valid") &&
        check(logger, sawGroupOnly, "catalog must contain group-only entries");
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
            "Back Extension must be bodyweight") &&
        check(logger, Model.sameString(deadBug["loadType"], "timed") && deadBug["targetDurationSec"] == 35,
            "Dead Bug must be timed with a 35-second target");
}

(:test)
function testRoutineNameAndEmptyRoutine(logger as Test.Logger) as Boolean {
    var tooLong = "";
    for (var i = 0; i < 65; i++) {
        tooLong += "a";
    }
    var routine = {"id" => "routine-empty", "name" => "Empty",
        "revision" => 1, "entries" => []};
    var config = {"routines" => [routine]};
    return check(logger, Model.validNonblankText("Routine 3", 64) &&
            !Model.validNonblankText("   ", 64) && !Model.validNonblankText(tooLong, 64),
            "routine names must be nonblank and at most 64 UTF-8 bytes") &&
        check(logger, Catalog.validRoutine(routine),
            "an empty routine must be a valid saved routine") &&
        check(logger, Catalog.createSession("routine-empty", "empty-1", 1, 100,
            null, config) == null,
            "an empty routine must not create a workout session");
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
    config["schemaVersion"] = 1;
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
function testStoredSessionPayloadValidation(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "validation-1", 1, 100, null, null) as Dictionary;
    var malformed = SessionLogic.copyDictionary(session);
    malformed["rest"] = ["bad", "record"];
    return check(logger, Model.validStoredSession(session, false),
            "a bounded session created from a valid routine must be recoverable") &&
        check(logger, !Model.validStoredSession(malformed, false),
            "malformed nested saved state must be rejected before recovery casts");
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

function clearConfigKeys() as Void {
    var domains = ["config", "routine.upper", "routine.lower", "routine.worst"];
    for (var i = 1; i <= 12; i++) {
        domains.add("routine.routine-" + i.toString());
    }
    for (var i = 0; i < Model.MAX_TEMPLATES; i++) {
        domains.add("routine.worst-" + i.toString());
    }
    for (var i = 0; i < domains.size(); i++) {
        Application.Storage.deleteValue((domains[i] as String) + ".a");
        Application.Storage.deleteValue((domains[i] as String) + ".b");
    }
}

(:test)
function testConfigCacheReflectsEdits(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var controller = new SessionController(store);
    var before = controller.routineTemplates().size();
    var id = controller.createRoutine("Cache test");
    var afterCreate = controller.routineTemplates().size();
    var duplicate = controller.createRoutine("Cache test");
    var afterRejected = controller.routineTemplates().size();
    var saved = controller.updateNumericConfig("setting", "", "", "defaultRestSec", 45);
    var rest = controller.defaultRestSec();
    var rejected = controller.updateNumericConfig("setting", "", "", "defaultRestSec", 99999);
    var restAfterRejected = controller.defaultRestSec();
    var reloaded = new SessionController(new Store());
    var persisted = reloaded.routineTemplates().size() == before + 1 &&
        reloaded.defaultRestSec() == 45;
    var deleted = id != null && controller.deleteRoutine(id as String);
    var afterDelete = controller.routineTemplates().size();
    clearConfigKeys();
    return check(logger, id != null && afterCreate == before + 1,
            "created routine must be visible on the next read") &&
        check(logger, duplicate == null && afterRejected == before + 1,
            "a rejected create must not alter later reads") &&
        check(logger, saved && rest == 45, "saved setting must be visible on the next read") &&
        check(logger, !rejected && restAfterRejected == 45,
            "a rejected edit must not alter later reads") &&
        check(logger, persisted, "a new controller must read the committed config") &&
        check(logger, deleted && afterDelete == before, "delete must be visible on the next read");
}

(:test)
function testCommitPairEnvelopeOnlyRevision(logger as Test.Logger) as Boolean {
    var store = new Store();
    var payload = {"schemaVersion" => 2, "nextSessionSeq" => 1,
        "routines" => Catalog.routineTemplates(null)};
    clearConfigKeys();
    // Valid envelope, invalid payload: still counts as a generation for rev/target choice.
    Application.Storage.setValue("config.a", {"v" => 1, "rev" => 5, "payload" => {}});
    Application.Storage.setValue("config.b", {"v" => 1, "rev" => 3, "payload" => {}});
    var committed = store.commitPair("config", payload);
    var b = Application.Storage.getValue("config.b") as Dictionary;
    var a = Application.Storage.getValue("config.a") as Dictionary;
    var olderTargeted = committed && b["rev"] == 6 && a["rev"] == 5;
    Application.Storage.setValue("config.a", {"v" => 2, "rev" => 9, "payload" => {}});
    var refused = !store.commitPair("config", payload);
    var untouched = (Application.Storage.getValue("config.b") as Dictionary)["rev"] == 6;
    clearConfigKeys();
    return check(logger, olderTargeted, "commit must overwrite the older generation with rev max+1") &&
        check(logger, refused && untouched, "a future-version record must refuse the commit");
}

(:test)
function testValidRoutineMaxConfigAndRejections(logger as Test.Logger) as Boolean {
    var seedEntries = (Catalog.routineTemplates(null)[0] as Dictionary)["entries"] as Array;
    var routines = [];
    for (var r = 0; r < Model.MAX_TEMPLATES; r++) {
        var entries = [];
        for (var e = 0; e < Model.MAX_ENTRIES; e++) {
            var entry = null;
            if (e % 2 == 0) {
                entry = SessionLogic.copyDictionary(seedEntries[e % seedEntries.size()] as Dictionary);
                entry["entryId"] = "r" + r.toString() + "-e" + e.toString();
                // Seed entries may leave fields null; the seed supplies them.
                entry["name"] = null;
            } else {
                entry = {"entryId" => "r" + r.toString() + "-e" + e.toString(),
                    "exerciseId" => "g-" + e.toString(), "name" => "Custom " + e.toString(),
                    "loadType" => "bodyweight", "workingSetCount" => 1, "targetRepsMin" => 8,
                    "targetRepsMax" => 10, "restSec" => 60};
            }
            entries.add(entry);
        }
        routines.add({"id" => "r" + r.toString(), "name" => "R" + r.toString(),
            "revision" => 1, "entries" => entries});
    }
    var allValid = true;
    var first = routines.size() > 0 ? routines[0 * routines.size()] as Dictionary : {};
    for (var r = 0; r < routines.size(); r++) {
        allValid = allValid && Catalog.validRoutine(routines[r] as Dictionary);
    }
    var badLoad = SessionLogic.copyDictionary((first["entries"] as Array)[1] as Dictionary);
    badLoad["loadType"] = "bogus";
    var badEntries = [badLoad];
    var badRoutine = {"id" => "bad", "name" => "Bad", "revision" => 1, "entries" => badEntries};
    var noName = SessionLogic.copyDictionary((first["entries"] as Array)[1] as Dictionary);
    noName["name"] = null;
    var noNameRoutine = {"id" => "bad2", "name" => "Bad", "revision" => 1, "entries" => [noName]};
    var noReps = SessionLogic.copyDictionary((first["entries"] as Array)[1] as Dictionary);
    noReps["targetRepsMin"] = null;
    var noRepsRoutine = {"id" => "bad3", "name" => "Bad", "revision" => 1, "entries" => [noReps]};
    var badIncrement = SessionLogic.copyDictionary((first["entries"] as Array)[0] as Dictionary);
    badIncrement["increment100"] = 30;
    var badIncrementRoutine = {"id" => "bad4", "name" => "Bad", "revision" => 1,
        "entries" => [badIncrement]};
    return check(logger, allValid, "a full 8x12 seed and Garmin routine set must validate") &&
        check(logger, !Catalog.validRoutine(badRoutine), "an invalid load type must be rejected") &&
        check(logger, !Catalog.validRoutine(noNameRoutine),
            "a custom entry without a name must be rejected") &&
        check(logger, !Catalog.validRoutine(noRepsRoutine),
            "a non-timed entry without reps must be rejected") &&
        check(logger, !Catalog.validRoutine(badIncrementRoutine),
            "an increment that is not a multiple of 25 must be rejected") &&
        check(logger, Catalog.exercise("no-such-exercise") == null &&
            Catalog.exercise(seedEntries[0]["exerciseId"] as String) != null,
            "exercise lookup by id must find seeds only");
}

(:test)
function testDiscardingFitStateIsValid(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "disc-1", 1, 100, null, null) as Dictionary;
    session["status"] = "finalizing";
    session["finishOutcome"] = "aborted";
    session["endedAt"] = 200;
    session["fitState"] = "discarding";
    var valid = Model.validStoredSession(session, false);
    session["fitState"] = "bogus";
    return check(logger, valid, "discarding must be a valid fitState") &&
        check(logger, !Model.validStoredSession(session, false), "unknown fitState must be rejected");
}

(:test)
function testPeekSessionEnvelopeOnly(logger as Test.Logger) as Boolean {
    var store = new Store();
    Application.Storage.deleteValue("history0.a");
    Application.Storage.deleteValue("history0.b");
    var empty = store.peekSession("history0") == null;
    Application.Storage.setValue("history0.a", {"v" => 1, "rev" => 1,
        "payload" => {"id" => "s-1", "sessionSeq" => 1}});
    Application.Storage.setValue("history0.b", {"v" => 1, "rev" => 2,
        "payload" => {"id" => "s-2", "sessionSeq" => 2}});
    var newest = store.peekSession("history0");
    var picked = newest != null && newest["id"].equals("s-2") && newest["sessionSeq"] == 2;
    Application.Storage.setValue("history0.b", {"v" => 2, "rev" => 3, "payload" => {}});
    store.peekSession("history0");
    var future = store.hasUnsupportedRecord();
    Application.Storage.deleteValue("history0.a");
    Application.Storage.deleteValue("history0.b");
    return check(logger, empty, "missing history slot must read as empty") &&
        check(logger, picked, "peek must return the newest generation without payload validation") &&
        check(logger, future, "a future-version history record must be flagged unsupported");
}

(:test)
function testRenameRoutineAndRepsRange(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var controller = new SessionController(store);
    var first = controller.createRoutine("Rename A");
    var second = controller.createRoutine("Rename B");
    var okRename = second != null && controller.renameRoutine(second as String, "Rename C");
    var duplicate = second != null && controller.renameRoutine(second as String, "Rename A");
    var blank = second != null && controller.renameRoutine(second as String, "   ");
    var missing = controller.renameRoutine("no-such-routine", "Rename D");
    var names = "";
    var routines = controller.routineTemplates();
    for (var i = 0; i < routines.size(); i++) {
        names += routines[i]["name"] as String + "|";
    }
    var renamedVisible = names.find("Rename C|") != null && names.find("Rename B|") == null;
    var entry = ((controller.routineTemplates()[0] as Dictionary)["entries"] as Array)[0] as Dictionary;
    var entryId = entry["entryId"] as String;
    var raised = controller.updateNumericConfig("template", "upper", entryId, "targetRepsMin", 40);
    var after = controller.templateEntry("upper", entryId) as Dictionary;
    var raisedBoth = raised && after["targetRepsMin"] == 40 && after["targetRepsMax"] == 40;
    var lowered = controller.updateNumericConfig("template", "upper", entryId, "targetRepsMax", 30);
    clearConfigKeys();
    return check(logger, first != null && okRename && renamedVisible, "rename must be visible") &&
        check(logger, !duplicate && !blank && !missing,
            "duplicate, blank and unknown-routine renames must be rejected") &&
        check(logger, raisedBoth, "raising min reps above max must raise max with it") &&
        check(logger, !lowered, "max reps below min must still be rejected");
}

(:test)
function testDeleteAnyRoutineAndDefaultRestForNewExercise(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var controller = new SessionController(store);
    var restSaved = controller.updateNumericConfig("setting", "", "", "defaultRestSec", 45);
    var definition = {"id" => "g-test-lift", "name" => "Test Lift", "category" => "CURL",
        "code" => "BARBELL_BICEPS_CURL", "isBodyWeight" => false};
    var entryId = controller.addRoutineExercise("upper", definition, "weight");
    var entry = entryId == null ? null : controller.templateEntry("upper", entryId as String);
    var restOk = restSaved && entry != null && entry["restSec"] == 45 && entry["defaultRestSec"] == 45;
    var deletedUpper = controller.deleteRoutine("upper");
    var deletedLower = controller.deleteRoutine("lower");
    var remaining = controller.routineTemplates().size();
    clearConfigKeys();
    return check(logger, restOk, "a new exercise must use the configured default rest") &&
        check(logger, deletedUpper, "the built-in Upper routine must be deletable") &&
        check(logger, !deletedLower && remaining == 1, "the last routine must be kept");
}

function repeatText(unit as String, count as Number) as String {
    // Doubling then one substring keeps allocation low; linear concatenation exhausts the heap.
    var text = unit;
    while (text.length() < count) {
        text += text;
    }
    text = text.substring(0, count) as String;
    return text;
}

// Worst-case routine: 12 entries x 5 sets = 60 sets, 64-byte names, 160-byte notes, max values.
function worstCaseRoutine(routineId as String, index as Number) as Dictionary {
    return sizedRoutine(routineId, index, 64, 48, 64, 160);
}

// Same shape with configurable string lengths (name, Garmin category, Garmin code, notes).
function sizedRoutine(routineId as String, index as Number, nameLength as Number,
                      categoryLength as Number, codeLength as Number,
                      notesLength as Number) as Dictionary {
    var entries = [];
    for (var e = 0; e < Model.MAX_ENTRIES; e++) {
        var tag = index.toString() + "-" + e.toString();
        entries.add({
            "entryId" => "r" + tag,
            "exerciseId" => "g-" + tag,
            "name" => repeatText("n", nameLength),
            "garminCategory" => repeatText("C", categoryLength),
            "garminCode" => repeatText("K", codeLength),
            "isBodyWeight" => false,
            "loadType" => "weight",
            "unit" => "kg",
            "increment100" => 10000,
            "defaultRestSec" => Model.MAX_REST_SEC,
            "workingSetCount" => 5,
            "targetRepsMin" => Model.MAX_REPS,
            "targetRepsMax" => Model.MAX_REPS,
            "targetDurationSec" => null,
            "startingLoad100" => Model.MAX_LOAD100,
            "restSec" => Model.MAX_REST_SEC,
            "notes" => notesLength > 0 ? repeatText("t", notesLength) : null
        });
    }
    return {"id" => routineId, "name" => repeatText("R", 63) + index.toString(),
        "revision" => 1000000, "entries" => entries};
}

function completeEverySet(session as Dictionary, now as Number) as Dictionary {
    var exercises = session["exercises"] as Array;
    var current = session;
    for (var i = 0; i < exercises.size(); i++) {
        var entryId = exercises[i]["entryId"] as String;
        var planned = exercises[i]["plannedSetCount"] as Number;
        for (var j = 0; j < planned; j++) {
            var next = SessionLogic.completeSet(current, entryId, j,
                {"load100" => Model.MAX_LOAD100, "reps" => Model.MAX_REPS}, now + 1000 + i * 10 + j);
            current = next as Dictionary;
        }
    }
    return current;
}

// Rough serialized size (type byte + length header + payload), for comparison with the 32 KB limit.
function estimateBytes(value as Object?) as Number {
    if (value == null) {
        return 1;
    }
    if (value instanceof String) {
        return 3 + value.toUtf8Array().size();
    }
    if (value instanceof Array) {
        var total = 3;
        for (var i = 0; i < value.size(); i++) {
            total += estimateBytes(value[i]);
        }
        return total;
    }
    if (value instanceof Dictionary) {
        var total = 3;
        var keys = value.keys();
        for (var i = 0; i < keys.size(); i++) {
            total += estimateBytes(keys[i]) + estimateBytes(value[keys[i]]);
        }
        return total;
    }
    return value instanceof Boolean ? 2 : 5;
}

function commitAndReload(logger as Test.Logger, store as Store, domain as String,
                         payload as Dictionary, enforceSize as Boolean) as Boolean {
    var committed = store.commitPair(domain, payload);
    var loaded = committed ? store.loadPair(domain) : null;
    var bytes = estimateBytes(payload);
    logger.debug(domain + " commit=" + committed + " reload=" + (loaded != null) +
        " estimatedBytes=" + bytes.toString() + " of 32768");
    // The simulator does not enforce the 32 KB value limit, so check the estimate explicitly.
    return committed && loaded != null && (!enforceSize || bytes < 32768);
}

(:test)
function testWorstCaseStorageCommits(logger as Test.Logger) as Boolean {
    var store = new Store();
    var domains = ["active", "history0", "last"];
    for (var d = 0; d < domains.size(); d++) {
        Application.Storage.deleteValue((domains[d] as String) + ".a");
        Application.Storage.deleteValue((domains[d] as String) + ".b");
    }
    clearConfigKeys();
    var now = Time.now().value();
    var routine = worstCaseRoutine("worst", 0);
    var config = {"schemaVersion" => 2, "nextSessionSeq" => 2147483647,
        "settings" => {"defaultRestSec" => 1800, "vibrationEnabled" => true},
        "templateOverrides" => {}, "incrementOverrides" => {},
        "routines" => [routine], "routineNextEntrySeq" => 2147483647};

    // First workout builds the previous-performance cache that the second one prefills from.
    var first = completeEverySet(Catalog.createSession("worst", "session-1", 1, now, null,
        config) as Dictionary, now);
    first["status"] = "completed";
    first["endedAt"] = now + 5000;
    var archive = SessionLogic.archivedSession(first);
    var cache = LastPerformance.merge(null, archive);
    var session = Catalog.createSession("worst", "session-2", 2, now, cache, config) as Dictionary;
    var clock = WorkoutClock.start(now);
    var clockKeys = clock.keys();
    for (var i = 0; i < clockKeys.size(); i++) {
        session[clockKeys[i]] = clock[clockKeys[i]];
    }
    session = completeEverySet(session, now);
    session["status"] = "finalizing";
    session["finishOutcome"] = "completed";
    session["endedAt"] = now + 86000;
    session["completionKind"] = "full";
    session["elapsedSec"] = 86000;
    session["activeSec"] = 86000;
    session["fitState"] = "saving";
    session["fitSegments"] = 999;
    session["fitUnknownSegments"] = 999;
    session["lastCheckpointAt"] = now + 86000;
    var ended = SessionLogic.copyDictionary(session);
    ended["status"] = "completed";

    // Config v3 holds only settings and 8 routine ids of the maximum length; each routine has its own key.
    var ids = [];
    for (var r = 0; r < Model.MAX_TEMPLATES; r++) {
        ids.add(repeatText("i", 39) + r.toString());
    }
    var configV3 = {"schemaVersion" => 3, "nextSessionSeq" => 2147483647,
        "settings" => {"defaultRestSec" => 1800, "vibrationEnabled" => true},
        "templateOverrides" => {}, "incrementOverrides" => {},
        "routineIds" => ids, "routineNextEntrySeq" => 2147483647};

    var results = [
        commitAndReload(logger, store, "active", session, true),
        commitAndReload(logger, store, "history0", SessionLogic.archivedSession(ended), true),
        commitAndReload(logger, store, "last", cache, true),
        commitAndReload(logger, store, "routine.worst", routine, true),
        commitAndReload(logger, store, "config", configV3, true)
    ];
    var configSmall = estimateBytes(configV3) < 4096;
    for (var d = 0; d < domains.size(); d++) {
        Application.Storage.deleteValue((domains[d] as String) + ".a");
        Application.Storage.deleteValue((domains[d] as String) + ".b");
    }
    clearConfigKeys();
    return check(logger, results[0], "worst-case active session must commit and reload") &&
        check(logger, results[1], "worst-case archived history must commit and reload") &&
        check(logger, results[2], "worst-case last-performance cache must commit and reload") &&
        check(logger, results[3], "a worst-case 12-entry routine must commit under 32 KB") &&
        check(logger, results[4] && configSmall, "config v3 must commit and stay small");
}

// Diagnostic: does the simulator enforce the 32 KB per-value limit? Logs only; asserts nothing.
(:test)
function testStorageValueLimitProbe(logger as Test.Logger) as Boolean {
    // One 8000-char string referenced k times: small heap, k * 8000 bytes when serialized.
    var chunk = repeatText("x", 8000);
    var counts = [3, 4, 5, 9, 25, 125];
    for (var i = 0; i < counts.size(); i++) {
        var count = counts[i] as Number;
        var rows = [];
        for (var j = 0; j < count; j++) {
            rows.add(chunk);
        }
        var outcome = "stored";
        try {
            Application.Storage.setValue("probe.value", {"rows" => rows});
            var back = Application.Storage.getValue("probe.value");
            outcome = back instanceof Dictionary && back["rows"].size() == count ?
                "stored and readable" : "stored but not readable";
        } catch (error) {
            outcome = "threw " + error.getErrorMessage();
        }
        logger.debug("probe ~" + (count * 8).toString() + " KB: " + outcome);
    }
    Application.Storage.deleteValue("probe.value");
    return true;
}

(:test)
function testOldConfigSchemaStartsFromDefaults(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var routines = Catalog.routineTemplates(null);
    var stored = store.commitPair("config", {"schemaVersion" => 2, "nextSessionSeq" => 5,
        "settings" => {"defaultRestSec" => 75, "vibrationEnabled" => false},
        "templateOverrides" => {}, "incrementOverrides" => {},
        "routines" => routines, "routineNextEntrySeq" => 1});
    var controller = new SessionController(new Store());
    var count = controller.routineTemplates().size();
    var rest = controller.defaultRestSec();
    var error = controller.errorCode();
    var saved = controller.setVibrationEnabled(true);
    var config = new Store().loadPair("config");
    var v3 = config != null && config["schemaVersion"] == 3 && config["nextSessionSeq"] == 5;
    clearConfigKeys();
    return check(logger, stored, "the v2 fixture must be a valid stored record") &&
        check(logger, count == Catalog.routineTemplates(null).size() && rest == 90 &&
            error == Err.NONE, "an old schema must give default routines and settings, no error") &&
        check(logger, saved && v3, "the next save must write a v3 config keeping nextSessionSeq");
}

(:test)
function testRoutineRoundTripThroughFreshController(logger as Test.Logger) as Boolean {
    clearConfigKeys();
    var first = new SessionController(new Store());
    var created = first.createRoutine("Trip A");
    var renamed = created != null && first.renameRoutine(created as String, "Trip B");
    var entryId = ((first.routineTemplates()[0] as Dictionary)["entries"] as Array)[0]["entryId"] as String;
    var edited = first.updateNumericConfig("template", "upper", entryId, "restSec", 33);
    var second = new SessionController(new Store());
    var names = "";
    var routines = second.routineTemplates();
    for (var i = 0; i < routines.size(); i++) {
        names += (routines[i] as Dictionary)["name"] as String + "|";
    }
    var seen = renamed && edited && routines.size() == 3 && names.find("Trip B|") != null &&
        (second.templateEntry("upper", entryId) as Dictionary)["restSec"] == 33;
    var deleted = second.deleteRoutine("upper");
    var third = new SessionController(new Store());
    var gone = deleted && third.routineTemplates().size() == 2 &&
        Application.Storage.getValue("routine.upper.a") == null &&
        Application.Storage.getValue("routine.upper.b") == null;
    var lower = third.routineTemplates().size() == 2 &&
        Application.Storage.getValue("routine.lower.a") != null;
    clearConfigKeys();
    return check(logger, created != null && seen, "create, rename and edit must persist across controllers") &&
        check(logger, gone, "delete must persist and remove the routine keys") &&
        check(logger, lower, "other routine keys must stay");
}

(:test)
function testMissingRoutineKeyIsDroppedWithError(logger as Test.Logger) as Boolean {
    clearConfigKeys();
    var first = new SessionController(new Store());
    var saved = first.updateNumericConfig("setting", "", "", "defaultRestSec", 61);
    Application.Storage.deleteValue("routine.lower.a");
    Application.Storage.deleteValue("routine.lower.b");
    var second = new SessionController(new Store());
    var remaining = second.routineTemplates();
    var damaged = second.errorCode() == Err.SAVED_SETTINGS_ARE_DAMAGED;
    var others = remaining.size() == 1 && remaining[0]["id"].equals("upper") &&
        second.defaultRestSec() == 61;
    Application.Storage.deleteValue("routine.upper.a");
    Application.Storage.deleteValue("routine.upper.b");
    var third = new SessionController(new Store());
    var none = third.routineTemplates().size() == 0;
    clearConfigKeys();
    return check(logger, saved, "the first save must write config and routines") &&
        check(logger, damaged && others, "a missing routine is dropped, the rest stay usable, error is reported") &&
        check(logger, none, "with every routine missing the settings are unusable");
}

function completedExercise(name as String, type as String, load100 as Number?, reps as Number?,
                           durationSec as Number?) as Dictionary {
    return {"name" => name, "loadType" => type, "plannedSetCount" => 2, "closedEarly" => false,
        "slots" => [
            {"completed" => {"load100" => load100, "reps" => reps, "durationSec" => durationSec}},
            {"completed" => null}]};
}

(:test)
function testFitLapPayloadFromCompletedSet(logger as Test.Logger) as Boolean {
    var weight = SessionLogic.lapPayload(completedExercise("Row", "weight", 6250, 10, null), 0) as Dictionary;
    var assist = SessionLogic.lapPayload(completedExercise("Pull-up", "assistance", 2500, 8, null), 0) as Dictionary;
    var body = SessionLogic.lapPayload(completedExercise("Push-up", "bodyweight", null, 15, null), 0) as Dictionary;
    var timed = SessionLogic.lapPayload(completedExercise("Plank", "timed", null, null, 45), 0) as Dictionary;
    var open = SessionLogic.lapPayload(completedExercise("Row", "weight", 6250, 10, null), 1);
    var long = SessionLogic.truncateBytes(repeatText("é", 40), 64);
    return check(logger, weight["void"] == 0, "lap payload is not void by default") &&
        check(logger, weight["weightKg"] == 62.5 && weight["reps"] == 10 && weight["set"] == 1 &&
            weight["durationSec"] == 0 && weight["name"].equals("Row"),
            "weight set: kg, reps, 1-based set number") &&
        check(logger, assist["weightKg"] == -25.0, "assistance is a negative kg offset") &&
        check(logger, body["weightKg"] == 0.0 && body["reps"] == 15, "bodyweight has 0 kg") &&
        check(logger, timed["reps"] == 0 && timed["durationSec"] == 45 && timed["weightKg"] == 0.0,
            "timed set has duration and no reps") &&
        check(logger, open == null, "an open slot has no lap payload") &&
        check(logger, Model.byteLength(long) <= 64 && long.length() == 32,
            "names are truncated to whole characters within 64 bytes");
}

(:test)
function testFitLapPayloadGarminCodes(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "garmin-1", 1, 100, null, null) as Dictionary;
    var row = {"load100" => 5500, "reps" => 9};
    var done = SessionLogic.completeSet(session, "upper-row", 0, row, 1000) as Dictionary;
    done = SessionLogic.completeSet(done, "upper-chest", 0, row, 1001) as Dictionary;
    var rowLap = SessionLogic.lapPayload(
        (done["exercises"] as Array)[SessionLogic.exerciseIndex(done, "upper-row")] as Dictionary, 0) as Dictionary;
    var chestLap = SessionLogic.lapPayload(
        (done["exercises"] as Array)[SessionLogic.exerciseIndex(done, "upper-chest")] as Dictionary, 0) as Dictionary;
    var plain = SessionLogic.lapPayload(completedExercise("Row", "weight", 6250, 10, null), 0) as Dictionary;
    return check(logger, rowLap["garminCategory"].equals("ROW") &&
            rowLap["garminCode"].equals("SEATED_CABLE_ROW") && Model.validStoredSession(done, false),
            "seed exercise carries its Garmin category and code") &&
        check(logger, chestLap["garminCategory"].equals("BENCH_PRESS") && chestLap["garminCode"].equals(""),
            "group-only exercise has an empty code") &&
        check(logger, plain["garminCategory"].equals("") && plain["garminCode"].equals(""),
            "exercise without a Garmin mapping has empty category and code");
}

(:test)
function testFitSummaryVolume(logger as Test.Logger) as Boolean {
    var session = {"exercises" => [
        completedExercise("Row", "weight", 6250, 10, null),
        completedExercise("Pull-up", "assistance", 2500, 8, null),
        completedExercise("Plank", "timed", null, null, 45),
        {"name" => "Skipped", "loadType" => "weight", "plannedSetCount" => 1, "closedEarly" => false,
            "slots" => [{"completed" => null}]}]};
    var summary = SessionLogic.fitSummary(session);
    return check(logger, summary["sets"] == 3, "completed sets are counted") &&
        check(logger, summary["exercises"] == 3, "exercises without a completed set are not counted") &&
        check(logger, summary["volumeKg"] == 625.0,
            "volume is weight x reps for weight exercises only (62.5 x 10)");
}

(:test)
function testSetStartAndLog(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "setrun-1", 1, 100, null, null) as Dictionary;
    var row = {"load100" => 5500, "reps" => 9};
    var started = SessionLogic.startSet(session, "upper-row", 0, 1000) as Dictionary;
    var run = started["setRun"] as Dictionary;
    var doubleStart = SessionLogic.startSet(started, "upper-row", 0, 1001);
    var logged = SessionLogic.completeSet(started, "upper-row", 0, row, 1042) as Dictionary;
    var exercise = (logged["exercises"] as Array)[SessionLogic.exerciseIndex(logged, "upper-row")] as Dictionary;
    var completed = ((exercise["slots"] as Array)[0] as Dictionary)["completed"] as Dictionary;
    var payload = SessionLogic.lapPayload(exercise, 0) as Dictionary;
    var plain = SessionLogic.completeSet(session, "upper-row", 0, row, 1042) as Dictionary;
    var plainExercise = (plain["exercises"] as Array)[SessionLogic.exerciseIndex(plain, "upper-row")] as Dictionary;
    var otherSlot = SessionLogic.completeSet(started, "upper-row", 1, row, 1042) as Dictionary;
    var replaced = SessionLogic.startSet(started, "upper-chest", 0, 1010) as Dictionary;
    return check(logger, run["entryId"].equals("upper-row") && run["slot"] == 0 &&
            run["startedAt"] == 1000 && session["setRun"] == null && Model.validStoredSession(started, false),
            "start records the set run and leaves the input untouched") &&
        check(logger, doubleStart != null && doubleStart["setRun"]["startedAt"] == 1001,
            "starting again replaces the running set") &&
        check(logger, replaced["setRun"]["entryId"].equals("upper-chest") &&
            Model.validStoredSession(replaced, false),
            "a set on another exercise replaces the running set") &&
        check(logger, completed["activeSec"] == 42 && payload["activeSec"] == 42 &&
            logged["setRun"] == null && Model.validStoredSession(logged, false),
            "logging a started set stores activeSec and clears the run") &&
        check(logger, SessionLogic.lapPayload(plainExercise, 0)["activeSec"] == 0,
            "logging without a start has unknown (0) activeSec") &&
        check(logger, otherSlot["setRun"] != null && otherSlot["setRun"]["slot"] == 0 &&
            Model.validStoredSession(otherSlot, false) &&
            ((((otherSlot["exercises"] as Array)[SessionLogic.exerciseIndex(otherSlot, "upper-row")]
                as Dictionary)["slots"] as Array)[1]["completed"]["activeSec"]) == null,
            "logging another slot keeps the running set and does not use its start time");
}

(:test)
function testSetStartEndsRestAndRejectsInvalid(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "setrun-2", 1, 100, null, null) as Dictionary;
    var row = {"load100" => 5500, "reps" => 9};
    var resting = SessionLogic.completeSet(session, "upper-row", 0, row, 1000) as Dictionary;
    var started = SessionLogic.startSet(resting, "upper-row", 1, 1005) as Dictionary;
    var timedStart = SessionLogic.startSet(session, "lower-dead-bug", 0, 1000);
    var timedSession = Catalog.createSession("lower", "setrun-3", 1, 100, null, null) as Dictionary;
    var timedRejected = SessionLogic.startSet(timedSession, "lower-dead-bug", 0, 1000) == null;
    return check(logger, Model.sameString(resting["rest"]["state"], "running") &&
            Model.sameString(started["rest"]["state"], "dismissed"),
            "starting a set dismisses the running rest") &&
        check(logger, SessionLogic.startSet(session, "nope", 0, 1000) == null &&
            SessionLogic.startSet(session, "upper-row", 99, 1000) == null &&
            SessionLogic.startSet(resting, "upper-row", 0, 1005) == null &&
            SessionLogic.startSet(session, "upper-row", 0, -1) == null,
            "unknown exercise, bad slot, completed slot and bad time are rejected") &&
        check(logger, timedStart == null && timedRejected, "timed exercises keep their own timer flow");
}

(:test)
function testStoredSetRunValidation(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("lower", "setrun-4", 1, 100, null, null) as Dictionary;
    var good = SessionLogic.copyDictionary(session);
    good["setRun"] = {"entryId" => "lower-leg-press", "slot" => 0, "startedAt" => 5};
    var bad = [
        {"entryId" => "lower-leg-press", "slot" => 99, "startedAt" => 5},
        {"entryId" => "missing", "slot" => 0, "startedAt" => 5},
        {"entryId" => "lower-dead-bug", "slot" => 0, "startedAt" => 5},
        {"entryId" => "lower-leg-press", "slot" => 0, "startedAt" => -5},
        "junk"];
    var ok = true;
    for (var i = 0; i < bad.size(); i++) {
        var candidate = SessionLogic.copyDictionary(session);
        candidate["setRun"] = bad[i];
        ok = ok && !Model.validStoredSession(candidate, false);
    }
    return check(logger, Model.validStoredSession(session, false) && Model.validStoredSession(good, false),
            "sessions without or with a valid setRun are valid") &&
        check(logger, ok, "malformed or mismatched setRun is rejected");
}

(:test)
function testUndoClearsSetRun(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("upper", "setrun-4", 1, 100, null, null) as Dictionary;
    var row = {"load100" => 5500, "reps" => 9};
    var done = SessionLogic.completeSet(session, "upper-row", 0, row, 1000) as Dictionary;
    var started = SessionLogic.startSet(done, "upper-row", 1, 1005) as Dictionary;
    var undone = SessionLogic.undoSet(started, "upper-row", 0) as Dictionary;
    var redone = SessionLogic.completeSet(undone, "upper-row", 0, row, 1100) as Dictionary;
    var next = SessionLogic.nextSlot(
        (started["exercises"] as Array)[SessionLogic.exerciseIndex(started, "upper-row")] as Dictionary);
    var nextAfterUndo = SessionLogic.nextSlot(
        (undone["exercises"] as Array)[SessionLogic.exerciseIndex(undone, "upper-row")] as Dictionary);
    return check(logger, started["setRun"] != null && undone["setRun"] == null &&
            Model.validStoredSession(undone, false), "undo clears the running set") &&
        check(logger, SessionLogic.setRunMatches(started, "upper-row", next) &&
            !SessionLogic.setRunMatches(started, "upper-row", nextAfterUndo) &&
            redone["setRun"] == null, "a stale set run never matches the next slot");
}

(:test)
function testStartTimedReplacesSetRunAndEndsRest(logger as Test.Logger) as Boolean {
    var session = Catalog.createSession("lower", "timed-2", 1, 100, null, null) as Dictionary;
    var row = {"load100" => 5500, "reps" => 9};
    var resting = SessionLogic.completeSet(session, "lower-leg-press", 0, row, 1000) as Dictionary;
    var started = SessionLogic.startSet(resting, "lower-leg-press", 1, 1002) as Dictionary;
    var timed = SessionLogic.startTimed(started, "lower-dead-bug", 0, 1005) as Dictionary;
    var timedWhileResting = SessionLogic.startTimed(resting, "lower-dead-bug", 0, 1005) as Dictionary;
    var rejected = SessionLogic.startSet(timed, "lower-leg-press", 1, 1010);
    return check(logger, started["setRun"] != null && timed["setRun"] == null &&
            timed["timedRun"] != null && Model.validStoredSession(timed, false),
            "starting a timed set clears a started plain set") &&
        check(logger, Model.sameString(resting["rest"]["state"], "running") &&
            Model.sameString(timedWhileResting["rest"]["state"], "dismissed"),
            "starting a timed set ends a running rest") &&
        check(logger, rejected == null, "a plain set cannot start while a timed set runs");
}

(:test)
function testExerciseForEntryCurrentDefinitionWins(logger as Test.Logger) as Boolean {
    var seedEntry = {"exerciseId" => "machine-chest-press", "name" => "Machine Chest Press",
        "loadType" => "weight", "unit" => "kg", "garminCategory" => "BENCH_PRESS",
        "garminCode" => "BENCH_PRESS"};
    var seedDefinition = Catalog.exerciseForEntry(seedEntry) as Dictionary;
    var catalogEntry = {"exerciseId" => "g04-3-way-calf-raise", "name" => "3 Way Calf Raise",
        "loadType" => "weight", "unit" => "kg", "garminCategory" => "CALF_RAISE",
        "garminCode" => "_3_WAY_CALF_RAISE"};
    var oldStyle = {"exerciseId" => "g-22f9fcbbd5af", "name" => "3 Way Calf Raise",
        "loadType" => "weight", "unit" => "kg", "garminCategory" => "CALF_RAISE",
        "garminCode" => "_3_WAY_CALF_RAISE"};
    var catalogDefinition = Catalog.exerciseForEntry(catalogEntry) as Dictionary;
    var unknown = {"exerciseId" => "g-000000000000", "name" => "Gone", "loadType" => "weight",
        "unit" => "kg", "garminCategory" => "CALF_RAISE", "garminCode" => "KEPT"};
    var custom = {"exerciseId" => "custom-1", "name" => "Mine", "loadType" => "weight",
        "unit" => "kg", "garminCategory" => "CALF_RAISE", "garminCode" => "KEPT"};
    return check(logger, seedDefinition["garminCategory"].equals("BENCH_PRESS") &&
            seedDefinition["garminCode"] == null, "seed mapping wins over a stored code") &&
        check(logger, catalogDefinition["garminCode"].equals("3_WAY_CALF_RAISE") &&
            catalogDefinition["garminCategory"].equals("CALF_RAISE"),
            "catalog entry uses the current catalog code") &&
        check(logger, Catalog.exerciseForEntry(oldStyle)["garminCode"].equals("_3_WAY_CALF_RAISE") &&
            Catalog.exerciseForEntry(oldStyle)["name"].equals("3 Way Calf Raise"),
            "an old g-<hex> id keeps its stored name and code") &&
        check(logger, Catalog.exerciseForEntry(unknown)["garminCode"].equals("KEPT") &&
            Catalog.exerciseForEntry(custom)["garminCode"].equals("KEPT"),
            "entries missing from the catalog keep their stored code");
}

(:test)
function testGarminEntryParsing(logger as Test.Logger) as Boolean {
    var parts = Catalog.splitList("A_B,CD*,EF!,GH*!");
    var digits = Catalog.garminExercise(Catalog.garminCategoryIndex("CALF_RAISE"), "g04-3-way-calf-raise");
    var index = Catalog.garminCategoryIndex("BENCH_PRESS");
    var groupOnly = Catalog.garminExercise(index, Catalog.garminId(index, "BENCH_PRESS"));
    return check(logger, parts.size() == 4 && parts[3].equals("GH*!") &&
            Catalog.entryCode("GH*!").equals("GH") && Catalog.entryFlag("CD*", "*") &&
            !Catalog.entryFlag("CD*", "!"), "list split and suffix flags") &&
        check(logger, Catalog.titleCase("3_WAY_CALF_RAISE").equals("3 Way Calf Raise") &&
            Catalog.titleCase("_45_DEGREE_PLANK").equals("45 Degree Plank") &&
            Catalog.garminCategoryName(Catalog.garminCategoryIndex("BENCH_PRESS")).equals("Bench Press"),
            "names are title case with leading underscores dropped") &&
        check(logger, Catalog.garminId(4, "3_WAY_CALF_RAISE").equals("g04-3-way-calf-raise") &&
            Catalog.garminId(15, "WEIGHTED_SINGLE_LEG_HIP_RAISE_WITH_FEET_ON_A_SWISS_BALL").length() == 40,
            "id scheme") &&
        check(logger, digits != null && digits["name"].equals("3 Way Calf Raise") && digits["code"].equals("3_WAY_CALF_RAISE"),
            "leading-digit FIT code without its Connect underscore") &&
        check(logger, groupOnly != null && groupOnly["code"] == null &&
            groupOnly["category"].equals("BENCH_PRESS") && groupOnly["name"].equals("Bench Press"),
            "a ! entry is group-only (code null) but keeps its name and id") &&
        check(logger, Catalog.garminName("BENCH_PRESS", "BARBELL_BENCH_PRESS").equals("Barbell Bench Press"),
            "garminName derives the name from the code");
}

(:test)
function testGarminIdsUniqueAndValid(logger as Test.Logger) as Boolean {
    var seen = {};
    var total = 0;
    var bodyWeight = 0;
    var categories = Catalog.garminCategories();
    for (var c = 0; c < categories.size(); c++) {
        var count = Catalog.garminEntries(c).size();
        for (var i = 0; i < count; i++) {
            var row = Catalog.garminRow(c, i);
            var id = row["id"] as String;
            if (!check(logger, Model.validId(id) && seen[id] == null && row["name"].length() > 0,
                "catalog id must be valid and unique: " + id)) {
                return false;
            }
            seen[id] = true;
            total++;
            bodyWeight += row["isBodyWeight"] == true ? 1 : 0;
        }
    }
    return check(logger, categories.size() == 47 && total == 1531 && bodyWeight == 378,
        "catalog size " + total.toString() + " bodyweight " + bodyWeight.toString());
}
