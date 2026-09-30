import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

function check(logger as Test.Logger, condition as Boolean, message as String) as Boolean {
    if (!condition) {
        logger.error(message);
        return false;
    }
    return true;
}

function workoutFixtureReply(ordinal as Number) as Dictionary? {
    return WatchUi.loadResource(ordinal == 1 ? Rez.JsonData.LiftosaurUpper :
        Rez.JsonData.LiftosaurLower) as Dictionary;
}

function workoutFixtureRoutine(ordinal as Number) as Dictionary? {
    var reply = workoutFixtureReply(ordinal);
    return reply == null ? null : Catalog.parseRoutine(reply, 1, ordinal);
}

function workoutFixtureConfig() as Dictionary {
    return {"routines" => [workoutFixtureRoutine(1), workoutFixtureRoutine(2)],
        "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true}};
}

function workoutFixtureSession(ordinal as Number, id as String,
                               sequence as Number, startedAt as Number) as Dictionary? {
    var config = workoutFixtureConfig();
    var routine = (config["routines"] as Array)[ordinal - 1] as Dictionary;
    return Catalog.createSession(routine["id"] as String, id, sequence, startedAt,
        null, config);
}

function fixtureEntryWithSetCount(routine as Dictionary, minimum as Number,
                                  loadType as String?) as Dictionary? {
    var entries = routine["entries"] as Array;
    for (var i = 0; i < entries.size(); i++) {
        var entry = entries[i] as Dictionary;
        if ((entry["workingSetCount"] as Number) >= minimum &&
            (loadType == null || Model.sameString(entry["loadType"], loadType))) {
            return entry;
        }
    }
    return null;
}

function fixtureExerciseWithType(session as Dictionary, loadType as String) as Dictionary? {
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        if (Model.sameString((exercises[i] as Dictionary)["loadType"], loadType)) {
            return exercises[i] as Dictionary;
        }
    }
    return null;
}

function fixtureSessionExercise(session as Dictionary, entryId as String) as Dictionary? {
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        var exercise = exercises[i] as Dictionary;
        if (Model.sameString(exercise["entryId"], entryId)) {
            return exercise;
        }
    }
    return null;
}

function fixtureQueueUpload(store as UploadMemoryStore, job as Dictionary) as Boolean {
    var id = job["sessionId"] as String;
    return store.saveUpload(job) && store.saveUploadQueue([id]);
}

function fixtureRepeat(text as String, count as Number) as String {
    var result = "";
    while (result.length() < count) {
        result += text;
    }
    return result.substring(0, count) as String;
}

function fixtureWorstRoutine() as Dictionary {
    var sourceRoutine = workoutFixtureRoutine(1) as Dictionary;
    var sourceEntries = sourceRoutine["entries"] as Array;
    var entries = [];
    for (var e = 0; e < Model.MAX_ENTRIES; e++) {
        var entry = SessionLogic.copyDictionary(sourceEntries[e % sourceEntries.size()] as Dictionary);
        entry["entryId"] = "w" + e.toString();
        entry["exerciseId"] = "x" + e.toString();
        entry["liftosaurEntryId"] = fixtureRepeat("L", 64);
        entry["name"] = fixtureRepeat("N", 64);
        entry["equipment"] = fixtureRepeat("E", 48);
        entry["superset"] = fixtureRepeat("S", 24);
        entry["loadType"] = "weight";
        entry["unit"] = "kg";
        entry["increment100"] = 10000;
        entry["unilateral"] = false;
        entry["restSec"] = Model.MAX_REST_SEC;
        entry["defaultRestSec"] = Model.MAX_REST_SEC;
        entry["workingSetCount"] = 5;
        entry["notes"] = fixtureRepeat("T", 160);
        var targets = [];
        for (var s = 0; s < 5; s++) {
            targets.add({"reps" => Model.MAX_REPS, "load100" => Model.MAX_LOAD100,
                "durationSec" => null});
        }
        entry["setTargets"] = targets;
        entry["warmups"] = [{"reps" => Model.MAX_REPS, "load100" => Model.MAX_LOAD100,
            "durationSec" => null}, {"reps" => Model.MAX_REPS, "load100" => Model.MAX_LOAD100,
            "durationSec" => null}];
        entries.add(entry);
    }
    return {"id" => "sync-2147483647-d1", "revision" => 2147483647,
        "name" => fixtureRepeat("R", 64), "programId" => fixtureRepeat("P", 64),
        "week" => 1000, "dayInWeek" => 1000, "entries" => entries};
}

function fixtureCompleteAll(session as Dictionary, start as Number) as Dictionary? {
    var current = session;
    var initial = session["exercises"] as Array;
    for (var e = 0; e < initial.size(); e++) {
        var entryId = (initial[e] as Dictionary)["entryId"] as String;
        var count = ((initial[e] as Dictionary)["slots"] as Array).size();
        for (var s = 0; s < count; s++) {
            var exercise = fixtureSessionExercise(current, entryId) as Dictionary;
            var slot = ((exercise["slots"] as Array)[s]) as Dictionary;
            var draft = SessionLogic.copyDictionary(slot["draft"] as Dictionary);
            var completed = SessionLogic.completeSet(current, entryId, s, draft,
                start + 10 + e * 5 + s);
            if (completed == null) {
                return null;
            }
            current = completed as Dictionary;
        }
    }
    return current;
}

function fixtureEstimateBytes(value as Object?) as Number {
    if (value == null) {
        return 1;
    }
    if (value instanceof String) {
        return 3 + (value as String).toUtf8Array().size();
    }
    if (value instanceof Array) {
        var total = 3;
        for (var i = 0; i < (value as Array).size(); i++) {
            total += fixtureEstimateBytes((value as Array)[i]);
        }
        return total;
    }
    if (value instanceof Dictionary) {
        var total = 3;
        var keys = (value as Dictionary).keys();
        for (var i = 0; i < keys.size(); i++) {
            total += fixtureEstimateBytes(keys[i]) +
                fixtureEstimateBytes((value as Dictionary)[keys[i]]);
        }
        return total;
    }
    return value instanceof Boolean ? 2 : 5;
}

function fixtureCommitSize(logger as Test.Logger, store as Store, domain as String,
                           payload as Dictionary) as Boolean {
    var committed = store.commitPair(domain, payload);
    var loaded = committed ? store.loadPair(domain) : null;
    var size = fixtureEstimateBytes(payload);
    logger.debug(domain + " estimated bytes=" + size.toString() + " / 32768");
    return loaded != null && size < 32768;
}

(:test)
function testDirectRoutineFixturesAndSessionSnapshot(logger as Test.Logger) as Boolean {
    var upper = workoutFixtureRoutine(1);
    var lower = workoutFixtureRoutine(2);
    if (upper == null || lower == null) {
        return check(logger, false, "sanitized Liftosaur fixtures parse into v4 routines");
    }
    var upperRoutine = upper as Dictionary;
    var lowerRoutine = lower as Dictionary;
    var session = Catalog.createSession(upperRoutine["id"] as String,
        "fixture-session", 1, 1790752141, null, workoutFixtureConfig());
    if (session == null) {
        return check(logger, false, "Liftosaur routine creates a valid session snapshot");
    }
    var snapshot = session as Dictionary;
    var firstEntry = (upperRoutine["entries"] as Array)[0] as Dictionary;
    var firstExercise = (snapshot["exercises"] as Array)[0] as Dictionary;
    var firstTarget = (firstEntry["setTargets"] as Array)[0] as Dictionary;
    var firstDraft = ((firstExercise["slots"] as Array)[0] as Dictionary)["draft"] as Dictionary;
    var lowerHasBodyweight = false;
    var lowerHasTimed = false;
    var lowerEntries = lowerRoutine["entries"] as Array;
    for (var i = 0; i < lowerEntries.size(); i++) {
        lowerHasBodyweight = lowerHasBodyweight ||
            Model.sameString((lowerEntries[i] as Dictionary)["loadType"], "bodyweight");
        lowerHasTimed = lowerHasTimed ||
            Model.sameString((lowerEntries[i] as Dictionary)["loadType"], "timed");
    }
    return check(logger, Catalog.validRoutine(upperRoutine) && Catalog.validRoutine(lowerRoutine) &&
            upperRoutine["week"] == 1 && upperRoutine["dayInWeek"] == 1,
            "Liftosaur fixture routines retain stable day metadata") &&
        check(logger, Catalog.totalSets(upperRoutine) == 19 && Catalog.totalSets(lowerRoutine) == 17 &&
            (firstEntry["warmups"] as Array).size() > 0,
            "working targets and display-only warmups convert without adding logged slots") &&
        check(logger, Model.validStoredSession(snapshot, false) &&
            Model.sameString(firstExercise["liftosaurEntryId"], firstEntry["liftosaurEntryId"]) &&
            firstDraft["load100"] == firstTarget["load100"] &&
            firstDraft["reps"] == firstTarget["reps"] && lowerHasBodyweight && lowerHasTimed,
            "session drafts use each plan target while preserving Liftosaur identity and load types");
}

(:test)
function testSessionCommandsAndCorrection(logger as Test.Logger) as Boolean {
    var routine = workoutFixtureRoutine(1) as Dictionary;
    var session = workoutFixtureSession(1, "test-session", 1, 100) as Dictionary;
    var first = fixtureEntryWithSetCount(routine, 2, null) as Dictionary;
    var entries = routine["entries"] as Array;
    var second = null;
    for (var i = 0; i < entries.size(); i++) {
        var candidate = entries[i] as Dictionary;
        if (!Model.sameString(candidate["entryId"], first["entryId"])) {
            second = candidate;
            break;
        }
    }
    var firstId = first["entryId"] as String;
    var secondId = (second as Dictionary)["entryId"] as String;
    var firstExercise = fixtureSessionExercise(session, firstId) as Dictionary;
    var actual0 = SessionLogic.copyDictionary(
        ((firstExercise["slots"] as Array)[0] as Dictionary)["draft"] as Dictionary);
    var completed1 = SessionLogic.completeSet(session, firstId, 0, actual0, 110) as Dictionary;
    var secondExercise = null;
    for (var i = 0; i < (session["exercises"] as Array).size(); i++) {
        var candidate = (session["exercises"] as Array)[i] as Dictionary;
        if (Model.sameString(candidate["entryId"], secondId)) {
            secondExercise = candidate;
            break;
        }
    }
    var actualSecond = SessionLogic.copyDictionary(
        ((secondExercise as Dictionary)["slots"] as Array)[0]["draft"] as Dictionary);
    var interleaved = SessionLogic.completeSet(completed1, secondId, 0, actualSecond, 120) as Dictionary;
    var nextDraft = SessionLogic.copyDictionary(
        ((firstExercise["slots"] as Array)[1]["draft"] as Dictionary));
    var completed2 = SessionLogic.completeSet(interleaved, firstId, 1, nextDraft, 130) as Dictionary;
    var correction = SessionLogic.copyDictionary(actual0);
    if (Model.sameString(first["loadType"], "weight") ||
        Model.sameString(first["loadType"], "assistance")) {
        correction["load100"] = (actual0["load100"] as Number) + 25;
    }
    var corrected = SessionLogic.correctSet(completed2, firstId, 0, correction, 200) as Dictionary;
    var correctedExercise = fixtureSessionExercise(corrected, firstId) as Dictionary;
    var correctedValue = ((correctedExercise["slots"] as Array)[0] as Dictionary)["completed"] as Dictionary;
    var undone = SessionLogic.undoSet(corrected, firstId, 0) as Dictionary;
    return check(logger, SessionLogic.totals(session)["done"] == 0 &&
            SessionLogic.totals(undone)["done"] == 2,
            "candidate writes remain isolated across interleaved completion and undo") &&
        check(logger, correctedValue["completedAt"] == 110 && correctedValue["updatedAt"] == 200,
            "correcting a set preserves its original completion time") &&
        check(logger, SessionLogic.completeSet(completed2, firstId, 0, actual0, 210) == null &&
            Model.sameString(SessionLogic.exerciseStatus(
                fixtureSessionExercise(undone, firstId) as Dictionary), "partial"),
            "duplicate completion is rejected and undo reopens the exercise");
}

(:test)
function testPerSetTargetsSurviveActualLoadCorrection(logger as Test.Logger) as Boolean {
    var session = workoutFixtureSession(1, "targets-session", 1, 100) as Dictionary;
    var exercises = session["exercises"] as Array;
    var index = -1;
    for (var i = 0; i < exercises.size(); i++) {
        var exercise = exercises[i] as Dictionary;
        if ((exercise["slots"] as Array).size() > 1 &&
            Model.sameString(exercise["loadType"], "weight")) {
            index = i;
            break;
        }
    }
    if (index < 0) {
        return check(logger, false, "fixture contains a multi-set weight exercise");
    }
    var exercise = exercises[index] as Dictionary;
    var entryId = exercise["entryId"] as String;
    var targets = exercise["planTargets"] as Array;
    var firstTarget = SessionLogic.copyDictionary(targets[0] as Dictionary);
    var secondTarget = SessionLogic.copyDictionary(targets[1] as Dictionary);
    var secondLoad = (firstTarget["load100"] as Number) + 100;
    secondTarget["load100"] = secondLoad;
    var nextTargets = [firstTarget, secondTarget];
    for (var i = 2; i < targets.size(); i++) {
        nextTargets.add(targets[i]);
    }
    exercise["planTargets"] = nextTargets;
    var slots = exercise["slots"] as Array;
    var secondSlot = SessionLogic.copyDictionary(slots[1] as Dictionary);
    var secondDraft = SessionLogic.copyDictionary(secondSlot["draft"] as Dictionary);
    secondDraft["load100"] = secondLoad;
    secondSlot["draft"] = secondDraft;
    slots[1] = secondSlot;
    var firstDraft = SessionLogic.copyDictionary(slots[0]["draft"] as Dictionary);
    var completed = SessionLogic.completeSet(session, entryId, 0, firstDraft, 110) as Dictionary;
    var corrected = SessionLogic.copyDictionary(firstDraft);
    corrected["load100"] = (firstDraft["load100"] as Number) + 25;
    var changed = SessionLogic.correctSet(completed, entryId, 0, corrected, 120) as Dictionary;
    var changedExercise = (changed["exercises"] as Array)[index] as Dictionary;
    var preserved = (((changedExercise["slots"] as Array)[1] as Dictionary)["draft"] as Dictionary);
    return check(logger, Model.validStoredSession(session, false) &&
            preserved["load100"] == secondLoad,
            "editing one actual set does not overwrite a different later plan target");
}

(:test)
function testTimedPlanTargetAndFitPayload(logger as Test.Logger) as Boolean {
    var session = workoutFixtureSession(2, "timed-session", 1, 100) as Dictionary;
    var exercise = fixtureExerciseWithType(session, "timed");
    if (exercise == null) {
        return check(logger, false, "lower fixture contains a timed exercise");
    }
    var timed = exercise as Dictionary;
    var entryId = timed["entryId"] as String;
    var targets = timed["planTargets"] as Array;
    var target = (targets[0] as Dictionary)["durationSec"] as Number;
    var started = SessionLogic.startTimed(session, entryId, 0, 100) as Dictionary;
    var run = started["timedRun"] as Dictionary;
    var completion = SessionLogic.completeTimed(started, entryId, 0, 100 + target) as Dictionary;
    var completedExercise = null;
    var completedExercises = completion["exercises"] as Array;
    for (var i = 0; i < completedExercises.size(); i++) {
        if (Model.sameString((completedExercises[i] as Dictionary)["entryId"], entryId)) {
            completedExercise = completedExercises[i] as Dictionary;
            break;
        }
    }
    var lap = SessionLogic.lapPayload(completedExercise as Dictionary, 0) as Dictionary;
    return check(logger, SessionLogic.timedElapsedSec(run, 100 + target) == target &&
            Model.validStoredSession(started, false),
            "timed set timer uses a validated per-slot plan target") &&
        check(logger, lap["durationSec"] == target && lap["weightKg"] == 0.0 &&
            !lap.hasKey("garminCategory") && !lap.hasKey("garminCode"),
            "FIT fallback keeps measured set data without exercise catalog mappings");
}

(:test)
function testV4ConfigAndCommittedSyncReplay(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var reply = workoutFixtureReply(1) as Dictionary;
    var routine = Catalog.parseRoutine(reply, 5, 1) as Dictionary;
    var routineId = routine["id"] as String;
    var storedRoutine = store.commitPair("routine." + routineId, routine);
    var config = {"schemaVersion" => 4, "nextSessionSeq" => 1,
        "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
        "incrementOverrides" => {},
        "routineIds" => [routineId], "routineSyncSeq" => 5,
        "programId" => routine["programId"], "programName" => "Test Program",
        "nextRoutineId" => routineId};
    var storedConfig = store.commitPair("config", config);
    var replayJournal = {"sequence" => 5, "phase" => "days", "index" => 1,
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "DayAx"}],
        "routineIds" => [routineId], "programId" => routine["programId"],
        "programName" => "Test Program", "nextWeek" => 1, "nextDay" => 1};
    var storedJournal = store.commitPair("rsync", replayJournal);
    var controller = new SessionController(store);
    controller.retryUploads();
    var remainingJournal = store.loadRoutineSync();
    var visibleRoutines = controller.routineTemplates();
    return check(logger, storedRoutine && storedConfig && storedJournal &&
            SessionLogic.routineSyncAlreadyCommitted(5, 5) &&
            SessionLogic.routineSyncAlreadyCommitted(5, 6) &&
            !SessionLogic.routineSyncAlreadyCommitted(6, 5),
            "a durable config pivot is distinguishable from a partial routine stage") &&
        check(logger, remainingJournal == null && visibleRoutines.size() == 1 &&
            Model.sameString((visibleRoutines[0] as Dictionary)["id"], routineId),
            "restart drops a stale post-pivot journal without overwriting active routine domains");
}

(:test)
function testUploadResponseCallbacks(logger as Test.Logger) as Boolean {
    var takenStore = new UploadMemoryStore();
    var takenJob = uploadStoreTestJob("taken-session");
    var takenSaved = fixtureQueueUpload(takenStore, takenJob);
    var takenController = new SessionController(takenStore);
    takenController.handleApiResponse("upload_start", "taken-session", 409,
        {"error" => {"code" => "workout_start_time_taken"}});
    var takenAfter = takenStore.loadUpload("taken-session") as Dictionary;
    var takenQueue = takenStore.loadUploadQueue() as Array;

    var activeStore = new UploadMemoryStore();
    var activeJob = uploadStoreTestJob("active-session");
    var activeSaved = fixtureQueueUpload(activeStore, activeJob);
    var activeController = new SessionController(activeStore);
    activeController.handleApiResponse("upload_start", "active-session", 409,
        {"error" => {"code" => "workout_already_active"}});
    var activeAfter = activeStore.loadUpload("active-session") as Dictionary;
    var activeQueue = activeStore.loadUploadQueue() as Array;

    var setsStore = new UploadMemoryStore();
    var setsJob = uploadStoreTestJob("sets-session");
    setsJob["state"] = "sets";
    setsJob["setsBody"] = {"sets" => [{"entryId" => "exercise-1", "setId" => "set-1",
        "completed" => {"reps" => 8, "weight" => "55.5kg"}}]};
    var setsSaved = fixtureQueueUpload(setsStore, setsJob);
    var setsController = new SessionController(setsStore);
    setsController.handleApiResponse("upload_sets", "sets-session", 200, null);
    var setsAfter = setsStore.loadUpload("sets-session") as Dictionary;
    var setsQueue = setsStore.loadUploadQueue() as Array;

    var finishStore = new UploadMemoryStore();
    var finishJob = uploadStoreTestJob("finish-session");
    finishJob["state"] = "finish";
    finishJob["setsBody"] = {"sets" => [{"entryId" => "exercise-1", "setId" => "set-1",
        "completed" => {"reps" => 8, "weight" => "55.5kg"}}]};
    var finishSaved = fixtureQueueUpload(finishStore, finishJob);
    var finishController = new SessionController(finishStore);
    finishController.handleApiResponse("upload_finish", "finish-session", 200, null);
    var finishAfter = finishStore.loadUpload("finish-session");
    var finishQueue = finishStore.loadUploadQueue() as Array;

    var unauthorizedStore = new UploadMemoryStore();
    var unauthorizedJob = uploadStoreTestJob("unauthorized-session");
    var unauthorizedSaved = fixtureQueueUpload(unauthorizedStore, unauthorizedJob);
    var unauthorizedController = new SessionController(unauthorizedStore);
    unauthorizedController.handleApiResponse("upload_start", "unauthorized-session", 401, null);
    var unauthorizedAfter = unauthorizedStore.loadUpload("unauthorized-session") as Dictionary;
    var unauthorizedQueue = unauthorizedStore.loadUploadQueue() as Array;

    var programStore = new UploadMemoryStore();
    var programJob = uploadStoreTestJob("program-session");
    var programSaved = fixtureQueueUpload(programStore, programJob);
    var programController = new SessionController(programStore);
    programController.handleApiResponse("upload_start", "program-session", 422,
        {"error" => {"code" => "program_error"}});
    var programAfter = programStore.loadUpload("program-session") as Dictionary;
    var programQueue = programStore.loadUploadQueue() as Array;

    var resumeStore = new UploadMemoryStore();
    var resumeJob = uploadStoreTestJob("resume-session");
    resumeJob["state"] = "sets";
    resumeJob["setsBody"] = {"sets" => [{"entryId" => "exercise-1", "setId" => "durable-id",
        "completed" => {"reps" => 8, "weight" => "55.5kg"}}]};
    resumeJob["state"] = "blocked";
    resumeJob["lastError"] = "workout_already_active";
    var resumeSaved = fixtureQueueUpload(resumeStore, resumeJob);
    var resumeController = new SessionController(resumeStore);
    resumeController.retryUploads();
    var resumeAfter = resumeStore.loadUpload("resume-session") as Dictionary;
    var resumedBody = resumeAfter["setsBody"] as Dictionary;
    var resumedRows = resumedBody["sets"] as Array;
    var resumedSet = resumedRows[0] as Dictionary;
    var resumeQueue = resumeStore.loadUploadQueue() as Array;

    var result = true;
    result = check(logger, takenSaved && Model.sameString(takenAfter["state"], "done") &&
        takenQueue.size() == 0,
        "409 start-time duplicate is durably acknowledged without reuploading") && result;
    result = check(logger, activeSaved && Model.sameString(activeAfter["state"], "blocked") &&
        activeQueue.size() == 1 &&
        Model.sameString(activeAfter["lastError"], "workout_already_active"),
        "409 already-active keeps the upload queued and blocked") && result;
    result = check(logger, setsSaved && Model.sameString(setsAfter["state"], "finish") &&
        setsQueue.size() == 1 && setsAfter["setsBody"] != null,
        "sets success persists the finish stage before any acknowledgement") && result;
    // The done record may already be retired (deleted) once the queue commit no longer references it.
    result = check(logger, finishSaved && (finishAfter == null ||
        Model.sameString((finishAfter as Dictionary)["state"], "done")) && finishQueue.size() == 0,
        "finish success persists acknowledgement and removes the queued item") && result;
    result = check(logger, unauthorizedSaved && unauthorizedQueue.size() == 1 &&
        Model.sameString(unauthorizedAfter["lastError"], "http-401") &&
        unauthorizedController.errorCode() == Err.LIFTOSAUR_UNAUTHORIZED,
        "authorization failures retain the queue with bounded restart-visible error data") && result;
    result = check(logger, programSaved && programQueue.size() == 1 &&
        Model.sameString(programAfter["lastError"], "program_error") &&
        programController.errorCode() == Err.WORKOUT_UPLOAD_PROGRAM_ERROR,
        "program validation failures retain the queue and show the Liftosaur repair error") && result;
    result = check(logger, resumeSaved && Model.sameString(resumeAfter["state"], "sets") &&
        Model.sameString(resumedSet["setId"], "durable-id") && resumeQueue.size() == 1,
        "retrying a blocked mapped workout resumes the persisted sets body after start handshake") && result;
    return result;
}

(:test)
function testStoreEnvelopeRevisionAndHistoryPeek(logger as Test.Logger) as Boolean {
    var store = new Store();
    Application.Storage.deleteValue("config.a");
    Application.Storage.deleteValue("config.b");
    var config = {"schemaVersion" => 4, "nextSessionSeq" => 1,
        "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
        "incrementOverrides" => {}, "routineIds" => [],
        "routineSyncSeq" => 0, "programId" => null, "programName" => null,
        "nextRoutineId" => null};
    Application.Storage.setValue("config.a", {"v" => 1, "rev" => 5, "payload" => {}});
    Application.Storage.setValue("config.b", {"v" => 1, "rev" => 3, "payload" => {}});
    var committed = store.commitPair("config", config);
    var a = Application.Storage.getValue("config.a") as Dictionary;
    var b = Application.Storage.getValue("config.b") as Dictionary;
    var wroteOlder = committed && a["rev"] == 5 && b["rev"] == 6;
    Application.Storage.setValue("config.a", {"v" => 2, "rev" => 9, "payload" => {}});
    var futureRefused = !store.commitPair("config", config);
    var oldGenerationKept = (Application.Storage.getValue("config.b") as Dictionary)["rev"] == 6;
    Application.Storage.deleteValue("config.a");
    Application.Storage.deleteValue("config.b");

    Application.Storage.deleteValue("history0.a");
    Application.Storage.deleteValue("history0.b");
    var empty = store.peekSession("history0") == null;
    Application.Storage.setValue("history0.a", {"v" => 1, "rev" => 1,
        "payload" => {"id" => "s-1", "sessionSeq" => 1}});
    Application.Storage.setValue("history0.b", {"v" => 1, "rev" => 2,
        "payload" => {"id" => "s-2", "sessionSeq" => 2}});
    var newest = store.peekSession("history0");
    var selectedNewest = newest != null && Model.sameString(newest["id"], "s-2") &&
        newest["sessionSeq"] == 2;
    Application.Storage.setValue("history0.b", {"v" => 2, "rev" => 3, "payload" => {}});
    store.peekSession("history0");
    var futureHistoryFlagged = store.hasUnsupportedRecord();
    Application.Storage.deleteValue("history0.a");
    Application.Storage.deleteValue("history0.b");
    return check(logger, wroteOlder && futureRefused && oldGenerationKept,
            "store writes over the older envelope generation and refuses unknown newer versions") &&
        check(logger, empty && selectedNewest && futureHistoryFlagged,
            "history peek selects newest envelope without loading full session data");
}

(:test)
function testV3ConfigResetsToV4Defaults(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var stored = store.commitPair("config", {"schemaVersion" => 3,
        "nextSessionSeq" => 5, "settings" => {"defaultRestSec" => 30,
            "vibrationEnabled" => false}, "templateOverrides" => {},
        "incrementOverrides" => {}, "routines" => [{"id" => "old-local-routine"}],
        "routineNextEntrySeq" => 99});
    var controller = new SessionController(store);
    var routines = controller.routineTemplates();
    var rest = controller.defaultRestSec();
    var vibration = controller.vibrationEnabled();
    var resetSaved = controller.setVibrationEnabled(false);
    var current = store.loadPair("config");
    var schemaFour = current != null && current["schemaVersion"] == 4 &&
        current["nextSessionSeq"] == 5 && current["routineSyncSeq"] == 0 &&
        (current["routineIds"] as Array).size() == 0;
    return check(logger, stored && routines.size() == 0 && rest == 90 && vibration &&
            controller.errorCode() == Err.NONE,
            "v3 Liftosaur-bound config is discarded in favor of empty v4/default settings") &&
        check(logger, resetSaved && schemaFour,
            "the first v4 save preserves nextSessionSeq while resetting sync metadata");
}

(:test)
function testWorstCaseV4StorageCommits(logger as Test.Logger) as Boolean {
    var store = new UploadMemoryStore();
    var routine = fixtureWorstRoutine();
    var routineValid = Catalog.validRoutine(routine);
    var configForSession = {"routines" => [routine],
        "settings" => {"defaultRestSec" => Model.MAX_REST_SEC},
        "incrementOverrides" => {}};
    var start = 1790752141;
    var initial = Catalog.createSession(routine["id"] as String,
        "worst-session", 2147483647, start, null, configForSession);
    var allDone = initial == null ? null : fixtureCompleteAll(initial as Dictionary, start);
    if (allDone == null) {
        return check(logger, false, "maximum v4 routine creates and completes a 60-set workout");
    }
    var active = allDone as Dictionary;
    var validActive = Model.validStoredSession(active, false);
    var ended = SessionLogic.copyDictionary(active);
    ended["status"] = "completed";
    ended["endedAt"] = start + 100;
    ended["elapsedSec"] = 100;
    ended["activeSec"] = 100;
    ended["completionKind"] = "full";
    var archive = SessionLogic.archivedSession(ended);
    var cache = LastPerformance.merge(null, archive);
    var ids = [] as Array<String>;
    for (var i = 0; i < Model.MAX_TEMPLATES; i++) {
        ids.add("r" + fixtureRepeat("i", 37) + i.toString());
    }
    var config = {"schemaVersion" => 4, "nextSessionSeq" => 2147483647,
        "settings" => {"defaultRestSec" => Model.MAX_REST_SEC, "vibrationEnabled" => true},
        "incrementOverrides" => {}, "routineIds" => ids,
        "routineSyncSeq" => 2147483647, "programId" => fixtureRepeat("P", 64),
        "programName" => fixtureRepeat("G", 64), "nextRoutineId" => ids[0]};
    var routineStored = fixtureCommitSize(logger, store, "routine." + routine["id"], routine);
    var configStored = fixtureCommitSize(logger, store, "config", config);
    var activeStored = fixtureCommitSize(logger, store, "active", active);
    var historyStored = fixtureCommitSize(logger, store, "history0", archive);
    var cacheStored = fixtureCommitSize(logger, store, "last", cache);
    return check(logger, routineValid && routineStored,
            "a 12-entry routine with 60 targets and maximum field lengths fits one Store domain") &&
        check(logger, configStored && fixtureEstimateBytes(config) < 4096,
            "the v4 config with eight maximum-length routine IDs remains small") &&
        check(logger, validActive && activeStored && historyStored && cacheStored,
            "worst-case 60-set active, archived, and last-performance records commit and reload");
}
