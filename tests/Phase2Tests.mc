import Toybox.Lang;
import Toybox.Test;
import Toybox.System;
import Toybox.WatchUi;

function phase2ApiSet(id as String, index as Number, weight as String, reps as Number,
                     timer as Number?, unilateral as Boolean, warmup as Boolean) as Dictionary {
    return {"setId" => id, "index" => index, "isWarmup" => warmup,
        "reps" => reps, "minReps" => null, "isAmrap" => false,
        "weight" => weight, "isUnilateral" => unilateral, "timer" => 90,
        "setTimer" => timer, "completed" => null};
}

function phase2ApiWorkout(name as String, startTime as Long, entryName as String,
                           timed as Boolean, unilateral as Boolean,
                           setIdPrefix as String) as Dictionary {
    var sets = [];
    var weight = timed ? "0kg" : "60kg";
    var timer = timed ? 35 : null;
    sets.add(phase2ApiSet(setIdPrefix + "-one", 0, weight, timed ? 1 : 10,
        timer, unilateral, false));
    sets.add(phase2ApiSet(setIdPrefix + "-two", 1, weight, timed ? 1 : 10,
        timer, unilateral, false));
    var entry = {"entryId" => "raw-entry-id", "exerciseId" => "raw-exercise-id",
        "equipment" => "machine", "name" => entryName, "superset" => null,
        "warmupSets" => [phase2ApiSet(setIdPrefix + "-warm", 0, weight,
            timed ? 1 : 8, timer, unilateral, true)], "sets" => sets};
    return {"data" => {"workout" => {
        "programId" => "x0001xxx", "programName" => "Test Program",
        "dayName" => name, "dayData" => {"day" => 2, "week" => 1,
            "dayInWeek" => 2}, "startTime" => startTime, "entries" => [entry]
    }}};
}

function phase2Completed(load100 as Number?, reps as Number?, duration as Number?,
                         at as Number) as Dictionary {
    return {"slot" => 0, "sequence" => 1, "completedAt" => at,
        "updatedAt" => at, "load100" => load100, "reps" => reps,
        "durationSec" => duration, "activeSec" => duration == null ? 35 : duration};
}

function phase2UploadSession(type as String, unilateral as Boolean,
                             start as Number, end as Number) as Dictionary {
    var slots = [];
    slots.add({"completed" => null});
    if (Model.sameString(type, "timed")) {
        slots.add({"completed" => phase2Completed(null, null, 40, end - 5)});
    } else {
        slots.add({"completed" => phase2Completed(5550, 8, null, end - 10)});
    }
    slots.add({"completed" => phase2Completed(5625, 9, null, end - 5)});
    return {"id" => "session-1", "status" => "completed",
        "programId" => "x0001xxx", "week" => 1, "dayInWeek" => 2,
        "templateName" => "DayBx", "startedAt" => start, "endedAt" => end,
        "substitutions" => [{"from" => "Row", "to" => "Cable Row"}],
        "exercises" => [{"entryId" => "e1", "liftosaurEntryId" => "raw-entry-id",
            "exerciseId" => "lift-row-1", "name" => "Row", "loadType" => type,
            "unilateral" => unilateral, "liftosaurPlannedSetCount" => 1,
            "slots" => slots}]};
}

(:test)
function testLiftoscriptDaysAndLimits(logger as Test.Logger) as Boolean {
    var parsed = LiftosaurLogic.parseDays(
        "# Week 1\r\n## Upper\r\n// ignored\r\n## Lower\r\n# Week 2\r\n## Upper\r\n");
    var days = parsed as Array;
    var tooMany = "# Week 1\n";
    for (var i = 0; i < 9; i++) {
        tooMany += "## Day " + i.toString() + "\n";
    }
    var opaqueIdReply = phase2ApiWorkout("Opaque", "1790752141000".toLong(),
        "Row", false, false, "opaque");
    var opaqueData = opaqueIdReply["data"] as Dictionary;
    var opaqueWorkout = opaqueData["workout"] as Dictionary;
    opaqueWorkout["programId"] = "Program_A1";
    var opaqueRoutine = Catalog.parseRoutine(opaqueIdReply, 1, 1);
    return check(logger, parsed != null && days.size() == 3 && days[1]["dayInWeek"] == 2 &&
            days[2]["week"] == 2 && Model.sameString(days[2]["name"], "Upper"),
            "Liftoscript headers parse CRLF, comments, repeated day names and per-week coordinates") &&
        check(logger, LiftosaurLogic.parseDays("## Upper\n# Week 1\n") == null &&
            LiftosaurLogic.parseDays("# Week nope\n## Upper\n") == null &&
            LiftosaurLogic.parseDays("# Week 1\n## Upper\n# Week 1\n## Lower\n") == null,
            "headers before a week, malformed weeks, and duplicate week blocks are rejected") &&
        check(logger, LiftosaurLogic.parseDays(tooMany) == null &&
            LiftosaurLogic.parseDays("# Week 1001\n## Upper\n") == null,
            "routine count and week bounds are enforced while parsing") &&
        check(logger, opaqueRoutine != null &&
            Model.sameString((opaqueRoutine as Dictionary)["programId"], "Program_A1"),
            "external Liftosaur program IDs remain opaque bounded text");
}

(:test)
function testDirectLiftosaurFixtureConversion(logger as Test.Logger) as Boolean {
    var beforeLoad = System.getSystemStats();
    var usedBeforeLoad = beforeLoad.usedMemory;
    var freeBeforeLoad = beforeLoad.freeMemory;
    var program = WatchUi.loadResource(Rez.JsonData.LiftosaurProgram) as Dictionary;
    var programData = program["data"] as Dictionary;
    var days = LiftosaurLogic.parseDays(programData["text"] as String) as Array;
    var upperReply = WatchUi.loadResource(Rez.JsonData.LiftosaurUpper) as Dictionary;
    var lowerReply = WatchUi.loadResource(Rez.JsonData.LiftosaurLower) as Dictionary;
    var afterLoad = System.getSystemStats();
    var usedAfterLoad = afterLoad.usedMemory;
    var freeAfterLoad = afterLoad.freeMemory;
    var fullWorkout = Catalog.workoutFromReply(upperReply) as Dictionary;
    var rawStart = fullWorkout["startTime"];
    var startType = "other";
    if (rawStart instanceof Long) {
        startType = "Long";
    } else if (rawStart instanceof Double) {
        startType = "Double";
    } else if (rawStart instanceof Number) {
        startType = "Number";
    }
    logger.debug("sanitized full-size workout startTime JSON type: " + startType);
    var exactDouble = Model.epochMillis(1790752141000.0d);
    var fractionalDouble = Model.epochMillis(1790752141000.5d);
    var upper = Catalog.parseRoutine(upperReply, 1, 1);
    var lower = Catalog.parseRoutine(lowerReply, 1, 2);
    var afterConversion = System.getSystemStats();
    var usedAfterConversion = afterConversion.usedMemory;
    var freeAfterConversion = afterConversion.freeMemory;
    logger.debug("P2HEAP " + usedBeforeLoad.toString() + " " + freeBeforeLoad.toString());
    logger.debug("P2HEAP " + usedAfterLoad.toString() + " " + freeAfterLoad.toString());
    logger.debug("P2HEAP " + usedAfterConversion.toString() + " " + freeAfterConversion.toString());
    if (upper == null || lower == null) {
        return check(logger, false, "sanitized full-size Liftosaur replies must convert to v4 routines");
    }
    var routines = [upper, lower];
    var config = {"routines" => routines, "settings" => {"defaultRestSec" => 90}};
    var upperRoutine = upper as Dictionary;
    var entries = upperRoutine["entries"] as Array;
    var first = entries[0] as Dictionary;
    var cacheSets = [];
    for (var i = 0; i < (first["setTargets"] as Array).size(); i++) {
        cacheSets.add([i, 8000, 10, null]);
    }
    var cache = {};
    cache[first["exerciseId"]] = {"exerciseId" => first["exerciseId"],
        "loadType" => "weight", "unit" => "kg", "sets" => cacheSets};
    var session = Catalog.createSession(upperRoutine["id"] as String,
        "fixture-session", 1, 1790752141, cache, config) as Dictionary;
    var exercise = (session["exercises"] as Array)[0] as Dictionary;
    var slots = exercise["slots"] as Array;
    var target = ((first["setTargets"] as Array)[0] as Dictionary);
    var draft = (slots[0] as Dictionary)["draft"] as Dictionary;
    var lowerRoutine = lower as Dictionary;
    var lowerEntries = lowerRoutine["entries"] as Array;
    var hasBodyweight = false;
    var hasTimed = false;
    for (var i = 0; i < lowerEntries.size(); i++) {
        var item = lowerEntries[i] as Dictionary;
        hasBodyweight = hasBodyweight || Model.sameString(item["loadType"], "bodyweight");
        hasTimed = hasTimed || Model.sameString(item["loadType"], "timed");
    }
    var rawLowerWorkout = Catalog.workoutFromReply(lowerReply) as Dictionary;
    var rawLowerEntries = rawLowerWorkout["entries"] as Array;
    var bodyweightIndex = -1;
    for (var i = 0; i < rawLowerEntries.size(); i++) {
        var rawEntry = rawLowerEntries[i] as Dictionary;
        var rawSet = ((rawEntry["sets"] as Array)[0]) as Dictionary;
        if (!(rawSet["setTimer"] instanceof Number) &&
            Model.weightLoad100(rawSet["weight"]) == 0) {
            bodyweightIndex = i;
            break;
        }
    }
    if (bodyweightIndex < 0) {
        return check(logger, false, "sanitized lower fixture includes a bodyweight exercise");
    }
    var warmupReply = SessionLogic.copyDictionary(lowerReply);
    var warmupWorkout = Catalog.workoutFromReply(warmupReply) as Dictionary;
    var warmupRawEntry = (warmupWorkout["entries"] as Array)[bodyweightIndex] as Dictionary;
    warmupRawEntry["warmupSets"] = [phase2ApiSet("bodywarm", 0, "3kg", 8,
        null, false, true)];
    var warmupRoutine = Catalog.parseRoutine(warmupReply, 1, 3) as Dictionary;
    var warmupEntry = ((warmupRoutine["entries"] as Array)[bodyweightIndex]) as Dictionary;
    var bodyweightWarmup = ((warmupEntry["warmups"] as Array)[0]) as Dictionary;
    var lastSets = (exercise["last"] as Dictionary)["sets"] as Array;
    var lastFirstSet = lastSets[0] as Array;
    var lastFirstLoad = lastFirstSet[1];
    var next = Catalog.nextRoutineCoordinates(lowerReply) as Dictionary;
    var startOk = Model.epochMillis(rawStart) != null;
    var millisOk = exactDouble != null && fractionalDouble == null;
    var repliesOk = Model.validLiftosaurWorkout(upperReply) &&
        Model.validLiftosaurWorkout(lowerReply);
    var routinesOk = Catalog.validRoutine(upperRoutine) && Catalog.validRoutine(lowerRoutine);
    if (!check(logger, days.size() == 2 && startOk && millisOk && repliesOk && routinesOk,
            "full-size sanitized API replies validate and convert to v4")) {
        return false;
    }
    if (!check(logger, entries.size() == 8 && Catalog.totalSets(upperRoutine) == 19 &&
            lowerEntries.size() == 7 && Catalog.totalSets(lowerRoutine) == 17 &&
            (first["warmups"] as Array).size() == 1,
            "all exercises, per-set targets and warmups survive conversion")) {
        return false;
    }
    if (!check(logger, Model.sameString(exercise["liftosaurEntryId"], first["liftosaurEntryId"]) &&
            draft["load100"] == target["load100"] &&
            lastFirstLoad == 8000,
            "session snapshot preserves Liftosaur identity, prefills plan targets, and keeps last performance")) {
        return false;
    }
    if (!check(logger, Model.validStoredSession(session, false) && hasBodyweight && hasTimed,
            "v4 sessions validate timed/bodyweight targets")) {
        return false;
    }
    if (!check(logger, bodyweightIndex >= 0 && bodyweightWarmup["load100"] == 300 &&
            Model.validTemplate(warmupRoutine),
            "bodyweight warmups retain optional external kilograms for display")) {
        return false;
    }
    if (!check(logger, Model.sameString(Catalog.findRoutineId(routines,
            next["week"] as Number, next["dayInWeek"] as Number), lowerRoutine["id"]),
            "next-day coordinates select the matching synced routine")) {
        return false;
    }
    if (!check(logger, Model.validId(Catalog.liftExerciseId(
            "same-long-source-prefix-a", "machine")) &&
            !Model.sameString(Catalog.liftExerciseId("same-long-source-prefix-a", "machine"),
                Catalog.liftExerciseId("same-long-source-prefix-b", "machine")),
            "stable local exercise ids distinguish similar Liftosaur IDs")) {
        return false;
    }
    return true;
}

(:test)
function testUploadJobAndDurableSetMapping(logger as Test.Logger) as Boolean {
    var start = 1790752141;
    var end = 1790752201;
    var session = phase2UploadSession("weight", false, start, end);
    var job = UploadLogic.makeJob(session) as Dictionary;
    var startTime = job["startTime"] as Long;
    var rawReply = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "plan");
    var started = UploadLogic.withStartedWorkout(job, rawReply);
    if (started == null) {
        return check(logger, false, "valid /start response maps completed sets by exact name and slot");
    }
    var saved = started as Dictionary;
    var body = saved["setsBody"] as Dictionary;
    var mapped = body["sets"] as Array;
    var first = mapped[0] as Dictionary;
    var extra = mapped[1] as Dictionary;
    var completed = first["completed"] as Dictionary;
    var extraId = extra["setId"] as String;
    var finish = UploadLogic.finishBody(UploadLogic.setsDone(saved));
    var done = SessionLogic.copyDictionary(saved);
    done["state"] = "done";
    done.remove("setsBody");
    var mismatch = phase2ApiWorkout("Wrong day", startTime, "Row", false, false, "other");
    var retried = UploadLogic.withStartedWorkout(saved, mismatch);
    var wrongStart = phase2ApiWorkout("DayBx", startTime + 1, "Row", false, false, "start");
    var wrongCoordinates = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "coords");
    var wrongCoordinateWorkout = ((wrongCoordinates["data"] as Dictionary)["workout"] as Dictionary);
    var wrongDayData = wrongCoordinateWorkout["dayData"] as Dictionary;
    wrongDayData["dayInWeek"] = 3;
    var wrongProgram = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "program");
    var wrongProgramData = wrongProgram["data"] as Dictionary;
    var wrongProgramWorkout = wrongProgramData["workout"] as Dictionary;
    wrongProgramWorkout["programId"] = "y0001xxx";
    var typeMismatch = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "type");
    var typeWorkout = ((typeMismatch["data"] as Dictionary)["workout"] as Dictionary);
    var typeEntry = ((typeWorkout["entries"] as Array)[0]) as Dictionary;
    var typeSets = typeEntry["sets"] as Array;
    for (var i = 0; i < typeSets.size(); i++) {
        var typeSet = typeSets[i] as Dictionary;
        typeSet["weight"] = "0kg";
    }
    var unilateralMismatch = phase2ApiWorkout("DayBx", startTime, "Row", false, true, "side");
    var wrongTimedShape = UploadLogic.makeJob(session) as Dictionary;
    var wrongTimedExercise = ((wrongTimedShape["exercises"] as Array)[0]) as Dictionary;
    var wrongTimedSet = ((wrongTimedExercise["sets"] as Array)[0]) as Dictionary;
    wrongTimedSet["timeSec"] = 10;
    wrongTimedSet["kg"] = 0.0;
    wrongTimedSet["reps"] = 1;
    var missingAppendId = UploadLogic.makeJob(session) as Dictionary;
    var appendExercise = ((missingAppendId["exercises"] as Array)[0]) as Dictionary;
    var appendSet = ((appendExercise["sets"] as Array)[1]) as Dictionary;
    appendSet.remove("appendId");
    var duplicateSetIdReply = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "dup");
    var duplicateWorkout = ((duplicateSetIdReply["data"] as Dictionary)["workout"] as Dictionary);
    var duplicateEntry = ((duplicateWorkout["entries"] as Array)[0]) as Dictionary;
    var duplicateSets = duplicateEntry["sets"] as Array;
    var duplicateSet = duplicateSets[1] as Dictionary;
    var priorDuplicateSet = duplicateSets[0] as Dictionary;
    duplicateSet["setId"] = priorDuplicateSet["setId"];
    return check(logger, Model.validUpload(job) && job["startTime"] instanceof Long &&
            (job["startTime"] as Long).compareTo(2147483647.toLong()) > 0,
            "upload queue stores exact epoch milliseconds in 64-bit Long values") &&
        check(logger, mapped.size() == 2 && Model.sameString(first["setId"], "plan-two") &&
            completed["reps"] == 8 && Model.sameString(completed["weight"], "55.5kg"),
            "set 2 maps to planned set 2 without shifting over skipped set 1") &&
        check(logger, extra["append"] == true && Model.validAppendId(extraId) &&
            !Model.sameString(extraId, "plan-one") && Model.sameString(extra["entryId"], "raw-entry-id"),
            "extra completed set gets a stable six-letter append ID and live Liftosaur entry ID") &&
        check(logger, Model.sameString(saved["state"], "sets") &&
            Model.sameString(UploadLogic.setsDone(saved)["state"], "finish") &&
            Model.sameString(finish["notes"], "Row -> Cable Row") &&
            Model.validUpload(done),
            "sets success advances to finish; finish notes include substitutions; done is valid") &&
        check(logger, retried == null,
            "start response with the wrong day name is blocked before set writes") &&
        check(logger, UploadLogic.withStartedWorkout(job, typeMismatch) == null &&
            UploadLogic.withStartedWorkout(job, unilateralMismatch) == null,
            "start response with changed exercise type or unilateral setting is blocked") &&
        check(logger, UploadLogic.withStartedWorkout(job, wrongStart) == null &&
            UploadLogic.withStartedWorkout(job, wrongCoordinates) == null &&
            UploadLogic.withStartedWorkout(job, wrongProgram) == null,
            "start response must preserve the exact timestamp, program, week, and day") &&
        check(logger, !Model.validUpload(wrongTimedShape) && !Model.validUpload(missingAppendId),
            "queued sets must match their load type and extra slots must retain append IDs") &&
        check(logger, !Model.validLiftosaurWorkout(duplicateSetIdReply),
            "direct API replies with duplicate set IDs are rejected before mapping");
}

(:test)
function testUploadRetryIdentityAndQueueBound(logger as Test.Logger) as Boolean {
    var session = phase2UploadSession("weight", false, 1790752141, 1790752201);
    var job = UploadLogic.makeJob(session) as Dictionary;
    var startTime = job["startTime"] as Long;
    var reply = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "plan");
    var first = UploadLogic.withStartedWorkout(job, reply) as Dictionary;
    var firstSetId = (((first["setsBody"] as Dictionary)["sets"] as Array)[0] as Dictionary)["setId"];
    var changed = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "newids");
    var resumed = UploadLogic.withStartedWorkout(first, changed) as Dictionary;
    var retrySetId = (((resumed["setsBody"] as Dictionary)["sets"] as Array)[0] as Dictionary)["setId"];
    var ids = [];
    for (var i = 0; i < 4; i++) {
        var candidate = SessionLogic.copyDictionary(job);
        candidate["sessionId"] = "session-" + (i + 2).toString();
        ids = UploadLogic.enqueue(ids, candidate) as Array;
    }
    var full = UploadLogic.enqueue(ids, job);
    var collisionReply = phase2ApiWorkout("DayBx", startTime, "Row", false, false, "collision");
    var collisionWorkout = (((collisionReply["data"] as Dictionary)["workout"] as Dictionary));
    var collisionEntry = (collisionWorkout["entries"] as Array)[0] as Dictionary;
    var collisionSets = collisionEntry["sets"] as Array;
    var plannedSetTwo = (collisionSets[1] as Dictionary);
    var appendId = ((((job["exercises"] as Array)[0] as Dictionary)["sets"] as Array)[1] as Dictionary)["appendId"];
    plannedSetTwo["setId"] = appendId;
    var collisionStarted = UploadLogic.withStartedWorkout(job, collisionReply) as Dictionary;
    var collisionMapped = (((collisionStarted["setsBody"] as Dictionary)["sets"] as Array)[1] as Dictionary);
    return check(logger, Model.sameString(firstSetId, retrySetId),
            "a resumed start handshake preserves the exact saved sets body despite regenerated preview IDs") &&
        check(logger, ids.size() == QueueLimits.MAX_PENDING_UPLOADS && full == null,
            "upload queue refuses a fifth pending workout") &&
        check(logger, Model.validAppendId(collisionMapped["setId"]) &&
            !Model.sameString(collisionMapped["setId"], appendId),
            "append IDs are regenerated if they collide with the start response's set IDs");
}

(:test)
function testUploadTimedUnilateralAndAssistance(logger as Test.Logger) as Boolean {
    var start = 1790752141;
    var end = 1790752201;
    var timedSession = phase2UploadSession("timed", false, start, end);
    var timedJob = UploadLogic.makeJob(timedSession) as Dictionary;
    var timedStart = timedJob["startTime"] as Long;
    var timedReply = phase2ApiWorkout("DayBx", timedStart, "Row", true, false, "time");
    var timedStarted = UploadLogic.withStartedWorkout(timedJob, timedReply) as Dictionary;
    var timedSet = ((((timedStarted["setsBody"] as Dictionary)["sets"] as Array)[0] as Dictionary)
        ["completed"] as Dictionary);
    var unilateralSession = phase2UploadSession("assistance", true, start, end);
    var unilateralJob = UploadLogic.makeJob(unilateralSession) as Dictionary;
    var unilateralReply = phase2ApiWorkout("DayBx", unilateralJob["startTime"] as Long,
        "Row", false, true, "assist");
    var unilateralStarted = UploadLogic.withStartedWorkout(unilateralJob, unilateralReply) as Dictionary;
    var unilateralSet = ((((unilateralStarted["setsBody"] as Dictionary)["sets"] as Array)[0] as Dictionary)
        ["completed"] as Dictionary);
    var invalidTimedUnilateral = phase2ApiWorkout("DayBx", timedStart, "Row", true, true, "bad");
    var fullWorkout = (((invalidTimedUnilateral["data"] as Dictionary)["workout"] as Dictionary));
    return check(logger, timedSet["reps"] == 1 && timedSet["setTimer"] == 40 &&
            Model.sameString(timedSet["weight"], "0kg"),
            "timed set mapping uploads measured duration with planned reps and zero load") &&
        check(logger, unilateralSet["reps"] == 8 && unilateralSet["repsLeft"] == 8 &&
            Model.sameString(unilateralSet["weight"], "55.5kg"),
            "unilateral assistance mapping keeps positive load and reports repsLeft") &&
        check(logger, !Model.validLiftosaurWorkout(invalidTimedUnilateral) &&
            Catalog.parseRoutine(invalidTimedUnilateral, 1, 1) == null,
            "timed unilateral workouts are rejected because the watch cannot record both holds");
}

(:test)
function testLiftoscriptImplicitWeekMultiWeekAndFilter(logger as Test.Logger) as Boolean {
    var implicit = LiftosaurLogic.parseDays("## Upper\n## Lower\n") as Array;
    var multi = "";
    for (var w = 1; w <= 3; w++) {
        multi += "# Week " + w.toString() + "\n";
        for (var d = 0; d < 6; d++) {
            multi += "## Day " + d.toString() + "\n";
        }
    }
    var parsed = LiftosaurLogic.parseDays(multi);
    var weekTwo = parsed == null ? [] : LiftosaurLogic.daysForWeek(parsed as Array, 2);
    var nineInWeek = "# Week 1\n";
    for (var d = 0; d < 9; d++) {
        nineInWeek += "## Day " + d.toString() + "\n";
    }
    return check(logger, implicit.size() == 2 && implicit[0]["week"] == 1 &&
            implicit[1]["dayInWeek"] == 2,
            "days without a week header belong to an implicit week 1") &&
        check(logger, parsed != null && (parsed as Array).size() == 18 && weekTwo.size() == 6 &&
            weekTwo[0]["week"] == 2 && weekTwo[5]["dayInWeek"] == 6,
            "multi-week programs parse past eight total days and filter to one week") &&
        check(logger, LiftosaurLogic.parseDays(nineInWeek) == null,
            "the eight-day cap applies per week");
}

(:test)
function testUploadPreviewAndSkipQueue(logger as Test.Logger) as Boolean {
    var session = phase2UploadSession("weight", false, 1790752141, 1790752201);
    var job = UploadLogic.makeJob(session) as Dictionary;
    var preview = phase2ApiWorkout("DayBx", 1111111111111l, "Row", false, false, "pv");
    var renamed = phase2ApiWorkout("DayBx", 1111111111111l, "Other", false, false, "pv");
    var store = new UploadMemoryStore();
    var saved = fixtureQueueUpload(store, job);
    var controller = new SessionController(store);
    controller.handleApiResponse("upload_preview", "session-1", 200, renamed);
    var after = store.loadUpload("session-1") as Dictionary;
    var stuck = controller.hasStuckUpload();
    var code = controller.errorCode();
    var skipped = controller.skipUpload();
    var damagedStore = new UploadMemoryStore();
    damagedStore.writeKey("uploadq.a", 5);
    var damagedController = new SessionController(damagedStore);
    var wasDamaged = damagedController.uploadQueueDamaged();
    var cleared = damagedController.clearUploadQueue();
    return check(logger, UploadLogic.previewMaps(job, preview) &&
            !UploadLogic.previewMaps(job, renamed) &&
            UploadLogic.withStartedWorkout(job, preview) == null,
            "preview matching ignores the regenerated start time and set ids but keeps name rules") &&
        check(logger, saved && Model.sameString(after["state"], "start") &&
            Model.sameString(after["lastError"], "program_changed") && stuck &&
            code == Err.WORKOUT_UPLOAD_MAPPING,
            "a preview mismatch marks the job failed (not blocked) without starting it") &&
        check(logger, skipped && store.loadUploadQueue().size() == 0 && !controller.hasStuckUpload(),
            "skipping retires the head upload") &&
        check(logger, wasDamaged && cleared && !damagedController.uploadQueueDamaged(),
            "clearing resets a damaged queue manifest");
}

function phase2SupersetSession() as Dictionary? {
    var routine = SessionLogic.copyDictionary(workoutFixtureRoutine(1) as Dictionary);
    var source = routine["entries"] as Array;
    var entries = [];
    var marked = 0;
    for (var i = 0; i < source.size(); i++) {
        var entry = SessionLogic.copyDictionary(source[i] as Dictionary);
        entry["superset"] = null;
        if (marked < 2 && Model.sameString(entry["loadType"], "weight") &&
            (entry["workingSetCount"] as Number) >= 2) {
            entry["superset"] = "Z";
            entry["restSec"] = 60;
            marked++;
        }
        entries.add(entry);
    }
    routine["entries"] = entries;
    var config = {"routines" => [routine], "settings" => {"defaultRestSec" => 90},
        "incrementOverrides" => {}};
    return Catalog.createSession(routine["id"] as String, "ss-1", 1, 1790752141, null, config);
}

function phase2FirstSuperset(session as Dictionary) as Array {
    var ids = [];
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        if (SessionLogic.inSuperset(exercises[i] as Dictionary)) {
            ids.add((exercises[i] as Dictionary)["entryId"]);
        }
    }
    return ids;
}

(:test)
function testSupersetAlternationRestAndLabels(logger as Test.Logger) as Boolean {
    var made = phase2SupersetSession();
    if (made == null) {
        return check(logger, false, "superset fixture session is created");
    }
    var session = made as Dictionary;
    var ids = phase2FirstSuperset(session);
    var a1 = ids[0] as String;
    var a2 = ids[1] as String;
    var exerciseA1 = UiFormat.exercise(session, a1) as Dictionary;
    var actual = {"load100" => 5000, "reps" => 8};
    var firstNext = SessionLogic.supersetNext(session, a1);
    var afterA1 = SessionLogic.completeSet(session, a1, 0, actual, 1790752200) as Dictionary;
    var restAfterA1 = afterA1["rest"];
    var editFromA2 = SessionLogic.lastEditEntryId(afterA1, a2);
    var upNext = SessionLogic.nextUp(afterA1, a1) as Dictionary;
    var afterA2 = SessionLogic.completeSet(afterA1, a2, 0, actual, 1790752260) as Dictionary;
    var restAfterA2 = afterA2["rest"] as Dictionary;
    var wrapped = SessionLogic.supersetNext(afterA2, a2);
    var closed = SessionLogic.closeExercise(afterA2, a1, true) as Dictionary;
    var onlyA2 = SessionLogic.supersetNext(closed, a2);
    var labelOne = SessionLogic.supersetLabel(session, SessionLogic.exerciseIndex(session, a1));
    var labelTwo = SessionLogic.supersetLabel(session, SessionLogic.exerciseIndex(session, a2));
    var c1 = Model.sameString(firstNext, a2) && Model.sameString(labelOne, "Z1") &&
        Model.sameString(labelTwo, "Z2");
    var c2 = restAfterA1 == null && Model.sameString(restAfterA2["entryId"], a2) &&
        Model.sameString(wrapped, a1);
    var c3 = Model.sameString(editFromA2, a1) && Model.sameString(upNext["entryId"], a2);
    var c4 = Model.sameString(onlyA2, a2) && exerciseA1["superset"] != null;
    return check(logger, c1, "superset members alternate in routine order and are labelled Z1/Z2") &&
        check(logger, c2, "rest starts only when the round wraps back to the first member") &&
        check(logger, c3,
            "edit-last targets the exercise where the set was logged; next-up follows the superset") &&
        check(logger, c4, "a member closed early is skipped and the others continue");
}

(:test)
function testRestPreAlertStepAndRepRange(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(1, "e1", 0, 1000, 60) as Dictionary;
    var short = RestClock.create(2, "e1", 0, 1000, 15) as Dictionary;
    var routine = SessionLogic.copyDictionary(workoutFixtureRoutine(1) as Dictionary);
    var entries = [];
    var source = routine["entries"] as Array;
    var weightName = null;
    for (var i = 0; i < source.size(); i++) {
        var entry = SessionLogic.copyDictionary(source[i] as Dictionary);
        if (weightName == null && Model.sameString(entry["loadType"], "weight")) {
            weightName = entry["name"];
        }
        entries.add(entry);
    }
    routine["entries"] = entries;
    var overrides = {};
    overrides[weightName as String] = 250;
    var config = {"routines" => [routine], "settings" => {"defaultRestSec" => 90},
        "incrementOverrides" => overrides};
    var session = Catalog.createSession(routine["id"] as String, "st-1", 1, 1790752141, null,
        config) as Dictionary;
    var stepped = null;
    var plain = null;
    var exercises = session["exercises"] as Array;
    for (var i = 0; i < exercises.size(); i++) {
        var exercise = exercises[i] as Dictionary;
        if (Model.sameString(exercise["loadType"], "weight")) {
            if (Model.sameString(exercise["name"], weightName)) {
                stepped = exercise["weightIncrement100"];
            } else if (plain == null) {
                plain = exercise["weightIncrement100"];
            }
        }
    }
    var reply = phase2ApiWorkout("Range", 1111111111111l, "Row", false, false, "rng");
    var replyWorkout = (reply["data"] as Dictionary)["workout"] as Dictionary;
    var replySet = (((replyWorkout["entries"] as Array)[0] as Dictionary)["sets"] as Array)[0] as Dictionary;
    replySet["minReps"] = 8;
    replySet["reps"] = 10;
    var ranged = Catalog.parseRoutine(reply, 1, 1) as Dictionary;
    var rangedSession = Catalog.createSession(ranged["id"] as String, "rg-1", 1, 1790752141, null,
        {"routines" => [ranged], "settings" => {"defaultRestSec" => 90}}) as Dictionary;
    var rangedExercise = (rangedSession["exercises"] as Array)[0] as Dictionary;
    var store = new UploadMemoryStore();
    for (var i = 0; i < 10; i++) {
        store.markUploadStatus("s" + i.toString(), i == 9 ? "skipped" : "done");
    }
    var statuses = store.loadUploadStatus();
    return check(logger, !RestClock.preAlertDue(rest, 1000) && RestClock.preAlertDue(rest, 1052) &&
            !RestClock.preAlertDue(rest, 1060) && !RestClock.preAlertDue(short, 1010),
            "pre-rest alert is due only in the last 10 s of a rest of at least 20 s") &&
        check(logger, stepped == 250 && (plain == null || plain == 100),
            "a per-exercise-name weight step overrides the default increment") &&
        check(logger, Model.sameString(UiFormat.repRange(rangedExercise, 0), "8–10") &&
            rangedExercise["targetRepsMin"] == 8 && rangedExercise["targetRepsMax"] == 10 &&
            UiFormat.repRange(rangedExercise, 1) == null,
            "a rep range is shown only when the API gives both bounds") &&
        check(logger, statuses.size() == 8 && !statuses.hasKey("s0") &&
            Model.sameString(statuses["s9"], "skipped"),
            "upload status map keeps the newest eight outcomes");
}

(:test)
function testKeyCleaningAndMasking(logger as Test.Logger) as Boolean {
    var long = "";
    for (var i = 0; i < 129; i++) {
        long += "k";
    }
    var store = new UploadMemoryStore();
    var saved = store.saveApiKey("lftsk_abcdefghijklmnop1234");
    var loaded = store.loadApiKey();
    store.deleteApiKey();
    return check(logger, Model.sameString(LiftosaurLogic.cleanKey("  lftsk_abc123 \n"), "lftsk_abc123") &&
            LiftosaurLogic.cleanKey("   \n") == null && LiftosaurLogic.cleanKey(long) == null &&
            LiftosaurLogic.cleanKey("lftsk abc") == null && LiftosaurLogic.cleanKey(null) == null,
            "entered keys are trimmed and empty, oversized or spaced keys are rejected") &&
        check(logger, Model.sameString(LiftosaurLogic.maskKey("lftsk_abcdefghijklmnop1234"),
            "lftsk_…1234") && !(LiftosaurLogic.maskKey("lftsk_abcdefghijklmnop1234").find("abcdef") != null),
            "the masked key shows only the prefix and last four characters") &&
        check(logger, saved && Model.sameString(loaded, "lftsk_abcdefghijklmnop1234") &&
            store.loadApiKey() == null,
            "the key round-trips through the two-generation store and can be deleted");
}

(:test)
function testOfflineMappingAndRetryBackoff(logger as Test.Logger) as Boolean {
    return check(logger, LiftosaurLogic.isOnline(true, null) && LiftosaurLogic.isOnline(false, true) &&
            !LiftosaurLogic.isOnline(false, false) && !LiftosaurLogic.isOnline(false, null),
            "online means a phone link or an available connection") &&
        check(logger, LiftosaurLogic.transportError(-104) == Err.PHONE_NOT_CONNECTED &&
            LiftosaurLogic.transportError(-300) == Err.NO_RESPONSE_WILL_RETRY &&
            LiftosaurLogic.transportError(-2) == Err.NO_RESPONSE_WILL_RETRY &&
            LiftosaurLogic.transportError(-3) == Err.NO_RESPONSE_WILL_RETRY &&
            LiftosaurLogic.transportError(401) == Err.NONE &&
            LiftosaurLogic.transportError(-403) == Err.NONE,
            "transport response codes map to offline or no-response errors only") &&
        check(logger, LiftosaurLogic.retryDelayMinutes(0) == 2 && LiftosaurLogic.retryDelayMinutes(1) == 5 &&
            LiftosaurLogic.retryDelayMinutes(2) == 10 && LiftosaurLogic.retryDelayMinutes(9) == 10,
            "auto-retry backs off 2, 5, then 10 minutes") &&
        check(logger, Model.sameString(Err.shortMessage(Err.PHONE_NOT_CONNECTED), "Phone not connected"),
            "the offline error has its Home text");
}
