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

function v2ConfigPayload() as Dictionary {
    return {"schemaVersion" => 2, "nextSessionSeq" => 5,
        "settings" => {"defaultRestSec" => 75, "vibrationEnabled" => true},
        "templateOverrides" => {}, "incrementOverrides" => {},
        "routines" => Catalog.routineTemplates(null), "routineNextEntrySeq" => 1};
}

(:test)
function testMigrateV2ConfigToRoutineKeys(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var stored = store.commitPair("config", v2ConfigPayload());
    var expected = Catalog.routineTemplates(null);
    var controller = new SessionController(new Store());
    var routines = controller.routineTemplates();
    var sameRoutines = routines.size() == expected.size();
    for (var i = 0; sameRoutines && i < expected.size(); i++) {
        var left = routines[i] as Dictionary;
        var right = expected[i] as Dictionary;
        sameRoutines = left["id"].equals(right["id"]) && left["name"].equals(right["name"]) &&
            (left["entries"] as Array).size() == (right["entries"] as Array).size() &&
            (left["entries"] as Array)[0]["exerciseId"].equals((right["entries"] as Array)[0]["exerciseId"]);
    }
    var keysExist = Application.Storage.getValue("routine.upper.a") != null &&
        Application.Storage.getValue("routine.lower.a") != null;
    var reloaded = new Store();
    var config = reloaded.loadPair("config");
    var v3 = config != null && config["schemaVersion"] == 3 && config["routines"] == null &&
        config["routineIds"] instanceof Array && config["routineIds"].size() == 2 &&
        config["nextSessionSeq"] == 5 && controller.defaultRestSec() == 75;
    clearConfigKeys();
    return check(logger, stored, "v2 fixture must be a valid stored config") &&
        check(logger, sameRoutines, "migrated routines must equal the v2 routines") &&
        check(logger, keysExist, "migration must write one key pair per routine") &&
        check(logger, v3, "migration must leave a v3 config with routineIds and no routines");
}

(:test)
function testInterruptedMigrationIsRedone(logger as Test.Logger) as Boolean {
    var store = new Store();
    clearConfigKeys();
    var stored = store.commitPair("config", v2ConfigPayload());
    // Interrupted after the first routine key: config is still v2.
    var seeds = Catalog.routineTemplates(null);
    var partial = store.commitPair("routine.upper", seeds[0] as Dictionary);
    var controller = new SessionController(new Store());
    var loaded = controller.routineTemplates().size() == 2;
    var config = new Store().loadPair("config");
    var migrated = config != null && config["schemaVersion"] == 3 &&
        Application.Storage.getValue("routine.lower.a") != null;
    clearConfigKeys();
    return check(logger, stored && partial, "fixtures must store") &&
        check(logger, loaded, "a load after an interrupted migration must still succeed") &&
        check(logger, migrated, "the next load must finish the migration");
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
    return check(logger, weight["weightKg"] == 62.5 && weight["reps"] == 10 && weight["set"] == 1 &&
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

function slotsOf(exercise as Dictionary, sets as Array) as Dictionary {
    var slots = [];
    for (var i = 0; i < sets.size(); i++) {
        slots.add({"completed" => sets[i]});
    }
    exercise["slots"] = slots;
    return exercise;
}

(:test)
function testFitExerciseLines(logger as Test.Logger) as Boolean {
    var uniform = slotsOf(completedExercise("Row", "weight", 5500, 9, null),
        [{"load100" => 5500, "reps" => 9}, {"load100" => 5500, "reps" => 9}, {"load100" => 5500, "reps" => 9}]);
    var mixed = slotsOf(completedExercise("Row", "weight", 5500, 9, null),
        [{"load100" => 5500, "reps" => 9}, {"load100" => 6250, "reps" => 8}]);
    var assist = slotsOf(completedExercise("Dip", "assistance", 3000, 10, null),
        [{"load100" => 3000, "reps" => 10}, {"load100" => 3000, "reps" => 10}]);
    var body = slotsOf(completedExercise("Push-up", "bodyweight", null, 15, null),
        [{"reps" => 15}, {"reps" => 12}, {"reps" => 10}]);
    var timed = slotsOf(completedExercise("Plank", "timed", null, null, 45),
        [{"durationSec" => 45}, {"durationSec" => 40}]);
    var long = slotsOf(completedExercise(repeatText("é", 30), "weight", 5500, 9, null),
        [{"load100" => 5500, "reps" => 9}, {"load100" => 5500, "reps" => 9}]);
    var empty = {"name" => "Skipped", "loadType" => "weight", "plannedSetCount" => 1, "closedEarly" => false,
        "slots" => [{"completed" => null}]};
    var lines = SessionLogic.fitExerciseLines({"exercises" => [uniform, mixed, assist, body, timed, long, empty]});
    var many = [];
    for (var i = 0; i < 12; i++) {
        many.add(completedExercise("Exercise number " + i.toString(), "weight", 12550, 10, null));
    }
    var twelve = SessionLogic.fitExerciseLines({"exercises" => many});
    var fits = true;
    for (var i = 0; i < lines.size(); i++) {
        fits = fits && Model.byteLength(lines[i]) <= 19;
    }
    for (var i = 0; i < twelve.size(); i++) {
        fits = fits && Model.byteLength(twelve[i]) <= 19;
    }
    return check(logger, lines.size() == 6, "exercises without completed sets are omitted") &&
        check(logger, lines[0].equals("Row 55kg 9/9/9"), "uniform load is shown once") &&
        check(logger, lines[1].equals("Row 9@55 8@62.5"), "mixed loads are shown per set") &&
        check(logger, lines[2].equals("Dip -30kg 10/10"), "assistance is negative") &&
        check(logger, lines[3].equals("Push-up 15/12/10"), "bodyweight shows reps only") &&
        check(logger, lines[4].equals("Plank 45s/40s"), "timed shows seconds") &&
        check(logger, lines[5].equals(repeatText("é", 5) + " 55kg 9/9"), "long names are cut before the numbers") &&
        check(logger, twelve.size() == 12 && twelve[0].equals("Exercise 125.5kg 10"),
            "12 exercises give 12 lines, name cut to fit the suffix") &&
        check(logger, fits, "every line fits 19 bytes") &&
        check(logger, SessionLogic.loadText(5225).equals("52.25") && SessionLogic.loadText(5205).equals("52.05") &&
            SessionLogic.loadText(5250).equals("52.5"), "load text keeps up to two decimals");
}
