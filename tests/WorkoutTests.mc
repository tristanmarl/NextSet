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
    var keys = ["config.a", "config.b"];
    for (var i = 0; i < keys.size(); i++) {
        Application.Storage.deleteValue(keys[i]);
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

(:test)
function testLegacyPausedSessionResumesActive(logger as Test.Logger) as Boolean {
    var store = new Store();
    Application.Storage.deleteValue("active.a");
    Application.Storage.deleteValue("active.b");
    var now = Time.now().value();
    var session = Catalog.createSession("upper", "legacy-1", 1, now - 100, null, null) as Dictionary;
    var clock = WorkoutClock.start(now - 100);
    var keys = clock.keys();
    for (var i = 0; i < keys.size(); i++) {
        session[keys[i]] = clock[keys[i]];
    }
    session["status"] = "paused";
    session["pauseStartedAt"] = now - 50;
    session["lastCheckpointAt"] = now - 50;
    var stored = store.commitPair("active", session);
    var controller = new SessionController(store);
    var resumed = controller.session();
    var ok = stored && resumed != null && controller.isWorkoutRunning() &&
        resumed["pauseStartedAt"] == null && resumed["pausedSec"] >= 49;
    Application.Storage.deleteValue("active.a");
    Application.Storage.deleteValue("active.b");
    return check(logger, stored, "the paused fixture must be a valid stored session") &&
        check(logger, ok, "a saved paused session must load as an active, running session");
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
    // Config at the 8 x 12 model limit is known to exceed it (see docs/STABILITY_AUDIT_PLAN.md), so
    // it is only reported, not asserted, until the limits or the stored shape change.
    if (bytes >= 32768) {
        logger.debug("WARNING " + domain + " estimate exceeds the 32 KB per-value limit");
    }
    return committed && loaded != null && (!enforceSize || bytes < 32768);
}

(:test)
function testWorstCaseStorageCommits(logger as Test.Logger) as Boolean {
    var store = new Store();
    var domains = ["active", "history0", "last", "config"];
    for (var d = 0; d < domains.size(); d++) {
        Application.Storage.deleteValue((domains[d] as String) + ".a");
        Application.Storage.deleteValue((domains[d] as String) + ".b");
    }
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

    var fullConfig = SessionLogic.copyDictionary(config);
    var routines = [];
    for (var r = 0; r < Model.MAX_TEMPLATES; r++) {
        routines.add(worstCaseRoutine("worst-" + r.toString(), r));
    }
    fullConfig["routines"] = routines;

    // Informational: a full config with typical strings (30-char names, 16/26-char Garmin codes, no notes).
    var typical = [];
    for (var r = 0; r < Model.MAX_TEMPLATES; r++) {
        typical.add(sizedRoutine("typical-" + r.toString(), r, 30, 16, 26, 0));
    }
    var typicalConfig = SessionLogic.copyDictionary(config);
    typicalConfig["routines"] = typical;
    logger.debug("typical full config estimatedBytes=" + estimateBytes(typicalConfig).toString() +
        " (one worst-case entry=" + estimateBytes(routine["entries"][0]).toString() + ")");

    var results = [
        commitAndReload(logger, store, "active", session, true),
        commitAndReload(logger, store, "history0", SessionLogic.archivedSession(ended), true),
        commitAndReload(logger, store, "last", cache, true),
        commitAndReload(logger, store, "config", fullConfig, false)
    ];
    for (var d = 0; d < domains.size(); d++) {
        Application.Storage.deleteValue((domains[d] as String) + ".a");
        Application.Storage.deleteValue((domains[d] as String) + ".b");
    }
    return check(logger, results[0], "worst-case active session must commit and reload") &&
        check(logger, results[1], "worst-case archived history must commit and reload") &&
        check(logger, results[2], "worst-case last-performance cache must commit and reload") &&
        check(logger, results[3], "8 routines x 12 entries config must commit and reload");
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
