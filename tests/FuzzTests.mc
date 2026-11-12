import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

// Helpers of the fuzz tests, in one module: Connect IQ 3.4 allows only 253 global members.
module FuzzKit {
    function fuzzReplyFixtures() as Array {
        var warm = issue2Warmups("sq", "100kg");
        var issue2 = issue2Reply("Day A", 1, [
            issue2Entry("sq", "Squat", "barbell", "ss", 3, 5, "100kg", 90,
                {"amrap" => true, "warm" => warm, "min" => 3}),
            issue2Entry("row", "Row", "cable", "ss", 2, 8, "50lb", 60, {"uni" => true})]);
        return [workoutFixtureReply(1), workoutFixtureReply(2),
            phase2ApiWorkout("DayBx", 1790752141000l, "Row", false, false, "a"),
            phase2ApiWorkout("DayBx", 1790752141000l, "Plank", true, true, "b"), issue2];
    }

    function fuzzProgramFixtures() as Array {
        return [WatchUi.loadResource(Rez.JsonData.LiftosaurProgram), WatchUi.loadResource(Rez.JsonData.Issue2Program)];
    }

    function fuzzConfig(routine as Dictionary) as Dictionary {
        return {"routines" => [routine], "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
            "incrementOverrides" => {"Squat" => 500}};
    }

    // A started-and-one-set-logged session of the first Upper exercise.
    function fuzzActiveSession() as Dictionary {
        var session = workoutFixtureSession(1, "session-1", 1, 1790752141) as Dictionary;
        var exercise = (session["exercises"] as Array)[0] as Dictionary;
        var slot = Model.slotAt(exercise, 0) as Dictionary;
        var done = SessionLogic.completeSet(session, exercise["entryId"] as String, 0,
            slot["draft"] as Dictionary, 1790752200);
        return done == null ? session : done as Dictionary;
    }

    function fuzzJob(type as String, unilateral as Boolean) as Dictionary {
        return UploadLogic.makeJob(phase2UploadSession(type, unilateral, 1790752141, 1790752201)) as Dictionary;
    }

    function fuzzResponseCode() as Number {
        var codes = [200, 200, 200, 201, 204, 401, 403, 404, 409, 429, 500, 0, -1, -2, -104, -300, -402, -403, 2147483647];
        return codes[Fuzz.rand(codes.size())] as Number;
    }

    // The pivot work the sync runs once a journal is complete, on whatever journal is stored.
    function fuzzSettleJournal(controller as SessionController, store as UploadMemoryStore) as Void {
        var journal = store.loadRoutineSync();
        if (journal != null) {
            controller.settleRoutineSync(journal as Dictionary);
            controller.applyRoutineSync(journal as Dictionary);
        }
    }

    function fuzzRawCommit(store as UploadMemoryStore, domain as String, payload as Object?) as Void {
        Fuzz.rev++;
        store.writeKey(domain + ".a", {"v" => 1, "rev" => Fuzz.rev, "payload" => payload});
    }

    // A started sync request leaves a running timer behind and a device allows only a few, so the sync
    // and upload tests share one controller (and its store) across their cases. Between cases the
    // stored sync state is reset here.
    function fuzzResetSyncStore(store as UploadMemoryStore, first as Dictionary, journal as Object?) as Void {
        store.deletePair("rsync");
        store.deletePair("config");
        syncSeedStore(store, first);
        fuzzRawCommit(store, "rsync", journal);
    }

    // Writes every stored domain, then corrupts some of the raw stored values.
    function fuzzSeedStore(store as UploadMemoryStore, parts as Dictionary) as Void {
        var domains = parts.keys();
        for (var i = 0; i < domains.size(); i++) {
            var payload = parts[domains[i]] as Dictionary;
            store.commitPair(domains[i] as String, payload);
            store.commitPair(domains[i] as String, payload);
        }
        store.writeKey("ckpt", ["session-1", 1790752150]);
    }

    // The workout operations that read an accepted session.
    function fuzzSessionConsumers(s as Dictionary, ended as Boolean) as Void {
                    var exercises = s["exercises"] as Array;
            SessionLogic.totals(s);
            SessionLogic.latestPointer(s);
            SessionLogic.fitSummary(s);
            for (var e = 0; e < exercises.size(); e++) {
                var exercise = exercises[e] as Dictionary;
                var id = exercise["entryId"] as String;
                SessionLogic.activeSlot(exercise);
                SessionLogic.lastLoggedSlot(exercise);
                SessionLogic.nextSlot(exercise);
                SessionLogic.exerciseStatus(exercise);
                SessionLogic.completedCount(exercise);
                SessionLogic.supersetNext(s, id);
                SessionLogic.supersetLabel(s, e);
                SessionLogic.nextUp(s, id);
                SessionLogic.canAddSet(s, id);
                SessionLogic.addSet(s, id);
                SessionLogic.closeExercise(s, id, true);
                SessionLogic.skipWarmups(s, id);
                SessionLogic.setRpe(s, id, 0, 80);
                SessionLogic.setUserVar(s, id, "x", 1);
                SessionLogic.updateDraft(s, id, 0, "reps", 7);
                SessionLogic.startTimed(s, id, 0, 1790752400);
                SessionLogic.lapPayload(exercise, 0);
                var slots = [0, 1, 100];
                for (var k = 0; k < slots.size(); k++) {
                    var slot = Model.slotAt(exercise, slots[k] as Number);
                    if (slot == null) {
                        continue;
                    }
                    var draft = (slot as Dictionary)["draft"];
                    if (draft instanceof Dictionary) {
                        SessionLogic.completeSet(s, id, slots[k] as Number, draft as Dictionary, 1790752400);
                        SessionLogic.correctSet(s, id, slots[k] as Number, draft as Dictionary, 1790752400);
                    }
                    SessionLogic.undoSet(s, id, slots[k] as Number);
                    SessionLogic.completeTimed(s, id, slots[k] as Number, 1790752400);
                }
            }
            if (ended) {
                SessionLogic.archivedSession(s);
                UploadLogic.makeJob(s);
                LastPerformance.merge({}, s);
            }
    }

    // Every (container, key) of a value, found without recursion: [container, key, path].
    function fuzzSpots(root as Object?) as Array {
        var spots = [];
        var queue = [[root, "$"]];
        var head = 0;
        while (head < queue.size() && spots.size() < 400) {
            var item = queue[head] as Array;
            head++;
            var node = item[0];
            var keys = node instanceof Dictionary ? (node as Dictionary).keys() : [];
            if (node instanceof Array) {
                for (var i = 0; i < (node as Array).size(); i++) {
                    keys.add(i);
                }
            }
            for (var k = 0; k < keys.size(); k++) {
                var child = (node as Object)[keys[k]];
                var path = (item[1] as String) + "." + keys[k].toString();
                spots.add([node, keys[k], path]);
                if (child instanceof Dictionary || child instanceof Array) {
                    queue.add([child, path]);
                }
            }
        }
        return spots;
    }

    function fuzzExtremes() as Array {
        return [null, 0, -1, 2147483647, 4294967296l, 1.5f, "", "x", true, [], {},
            Fuzz.rep("long ", 400), "99999999999kg", "-5kg", "0.0000001lb", "1e3kg", "kg", " 60kg "];
    }

}

// Seeded mutation fuzzing of everything that reads outside data (Liftosaur replies, the program
// text, stored records). A case passes when every call returns normally; null, false or a problem
// text are fine. A thrown exception kills the app on a watch, so each one is a failure that names
// its seed and mutations (see FuzzLogic.mc). Each test is bounded to stay under the watchdog.

(:test)
function testFuzzBaselineFixturesAreValid(logger as Test.Logger) as Boolean {
    // The unmutated fixtures must be accepted, so a mutation really exercises the happy path.
    var replies = FuzzKit.fuzzReplyFixtures();
    var parsed = 0;
    for (var i = 0; i < replies.size(); i++) {
        if (Catalog.parseRoutine(replies[i], 1, 1) != null) {
            parsed++;
        }
    }
    var program = (FuzzKit.fuzzProgramFixtures()[0] as Dictionary)["data"] as Dictionary;
    var weeks = LiftosaurLogic.parseDays(program["text"] as String);
    var session = FuzzKit.fuzzActiveSession();
    var done = (((session["exercises"] as Array)[0] as Dictionary)["slots"] as Array)[0] as Dictionary;
    return check(logger, parsed == replies.size(), "all fuzz reply fixtures parse (" + Catalog.lastProblem + ")") &&
        check(logger, weeks != null, "the program fixture parses") &&
        check(logger, done["completed"] != null && Model.validStoredSession(session, false),
            "the logged-set session fixture is valid") &&
        check(logger, Model.validUpload(FuzzKit.fuzzJob("weight", false)) && Model.validUpload(FuzzKit.fuzzJob("timed", true)),
            "the job fixtures are valid");
}

(:test)
function testFuzzParseRoutine(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var fixtures = FuzzKit.fuzzReplyFixtures();
    for (var f = 0; f < fixtures.size(); f++) {
        for (var i = 0; i < 40; i++) {
            var seed = f * 1000 + i;
            Fuzz.begin(seed);
            var reply = Fuzz.mutated(fixtures[f], 1 + Fuzz.rand(3));
            try {
                Fuzz.go("ParseRoutine");
                Catalog.dayCoordinates(reply);
                Catalog.workoutFromReply(reply);
                Model.liftosaurWorkoutProblem(reply);
                var routine = Catalog.parseRoutine(reply, 1, 1);
                if (routine != null) {
                    var id = (routine as Dictionary)["id"] as String;
                    Catalog.createSession(id, "session-1", 1, 1790752141, null, FuzzKit.fuzzConfig(routine as Dictionary));
                }
            } catch (ex) {
                Fuzz.caught(logger, "parseRoutine fixture " + f.toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "parseRoutine and friends never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzParseRoutineRandomRoots(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    for (var i = 0; i < 60; i++) {
        Fuzz.begin(50000 + i);
        var reply = Fuzz.junk();
        try {
            Fuzz.go("ParseRoutineRandomRoots");
            Catalog.dayCoordinates(reply);
            Catalog.parseRoutine(reply, 1, 1);
            Catalog.parseRoutine({"data" => reply}, 1, 1);
            Catalog.parseRoutine({"data" => {"workout" => reply}}, 1, 1);
            Model.liftosaurWorkoutProblem({"data" => {"workout" => {"entries" => [reply], "dayData" => reply,
                "programId" => reply, "dayName" => reply, "startTime" => reply}}});
        } catch (ex) {
            Fuzz.caught(logger, "parseRoutine junk root", 50000 + i, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "junk replies are rejected without throwing");
}

(:test)
function testFuzzCreateSessionFromStoredRoutine(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var routines = [workoutFixtureRoutine(1), workoutFixtureRoutine(2)];
    for (var r = 0; r < routines.size(); r++) {
        var routine = routines[r] as Dictionary;
        for (var i = 0; i < 40; i++) {
            var seed = 2000 + r * 100 + i;
            Fuzz.begin(seed);
            var stored = Fuzz.mutatedDict(routine, 1 + Fuzz.rand(3));
            var config = Fuzz.mutatedDict(FuzzKit.fuzzConfig(routine), Fuzz.rand(3));
            config["routines"] = [stored];
            try {
                Fuzz.go("CreateSessionFromStoredRoutine");
                var id = routine["id"] as String;
                Model.validTemplate(stored);
                // Stored routines are validated on load; the consumers only see accepted ones.
                if (Catalog.validRoutine(stored)) {
                    Catalog.routineTemplates(config);
                    Catalog.allRoutineExercises(config);
                }
                var session = Catalog.createSession(id, "session-1", 1, 1790752141, null, config);
                if (session != null) {
                    Model.validStoredSession(session, false);
                }
            } catch (ex) {
                Fuzz.caught(logger, "createSession routine " + r.toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "createSession never throws on stored routines (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzStoredSessionValidators(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var fresh = workoutFixtureSession(2, "session-1", 1, 1790752141) as Dictionary;
    var logged = FuzzKit.fuzzActiveSession();
    var cases = [fresh, logged];
    for (var f = 0; f < cases.size(); f++) {
        for (var i = 0; i < 40; i++) {
            var seed = 3000 + f * 100 + i;
            Fuzz.begin(seed);
            var session = Fuzz.mutated(cases[f], 1 + Fuzz.rand(3));
            try {
                Fuzz.go("StoredSessionValidators");
                Model.validStoredSession(session, false);
                Model.validStoredSession(session, true);
                if (session instanceof Dictionary) {
                    var exercises = (session as Dictionary)["exercises"];
                    if (exercises instanceof Array && (exercises as Array).size() > 0 &&
                        (exercises as Array)[0] instanceof Dictionary) {
                        var exercise = (exercises as Array)[0] as Dictionary;
                        Model.validWarmupSlots(exercise, false);
                        Model.slotAt(exercise, 0);
                        Model.slotAt(exercise, 100);
                        Model.validTimedRun((session as Dictionary)["timedRun"], exercises as Array);
                        Model.validRest((session as Dictionary)["rest"], exercises as Array);
                        Model.validSessionPointer((session as Dictionary)["pointer"], exercises as Array);
                    }
                }
            } catch (ex) {
                Fuzz.caught(logger, "validStoredSession " + f.toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "session validators never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzJobAndPayloadValidators(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var weight = FuzzKit.fuzzJob("weight", false);
    var timed = FuzzKit.fuzzJob("timed", true);
    var cases = [weight, timed];
    for (var f = 0; f < cases.size(); f++) {
        for (var i = 0; i < 40; i++) {
            var seed = 4000 + f * 100 + i;
            Fuzz.begin(seed);
            var job = Fuzz.mutated(cases[f], 1 + Fuzz.rand(3));
            try {
                Fuzz.go("JobAndPayloadValidators");
                Model.validUpload(job);
                // Jobs are validated on load; the consumers only see accepted ones.
                if (Model.validUpload(job)) {
                    Model.validExtraWarmups((job as Dictionary)["extraWarmups"]);
                    UploadLogic.startBody(job as Dictionary);
                    UploadLogic.finishBody(job as Dictionary);
                    UploadLogic.setsDone(job as Dictionary);
                    UploadLogic.cloneJob(job as Dictionary);
                }
            } catch (ex) {
                Fuzz.caught(logger, "validUpload " + f.toString(), seed, ex);
            }
        }
    }
    // Journals, config and queue go through the store's own validators (commitPair).
    var routine = workoutFixtureRoutine(1) as Dictionary;
    var payloads = {
        "config" => {"schemaVersion" => 4, "nextSessionSeq" => 1,
            "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
            "incrementOverrides" => {}, "routineIds" => [routine["id"]], "routineSyncSeq" => 1,
            "programId" => "x0001xxx", "programName" => "P", "nextRoutineId" => routine["id"]},
        "rsync" => syncJournal(routine, 2),
        "uploadq" => {"ids" => ["session-1"], "retired" => ["session-0"]},
        "routine.sync-1-d1" => routine,
        "upstatus" => {"order" => ["session-1"], "map" => {"session-1" => "done"}},
        "apikey" => {"key" => "abc"},
        "device" => {"id" => "abc-1"}
    };
    var domains = payloads.keys();
    for (var d = 0; d < domains.size(); d++) {
        for (var i = 0; i < 40; i++) {
            var seed = 4500 + d * 100 + i;
            Fuzz.begin(seed);
            var payload = Fuzz.mutatedDict(payloads[domains[d]] as Dictionary, 1 + Fuzz.rand(3));
            try {
                Fuzz.go("JobAndPayloadValidators");
                new UploadMemoryStore().commitPair(domains[d] as String, payload);
            } catch (ex) {
                Fuzz.caught(logger, "commitPair " + domains[d].toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "job and payload validators never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzScalarParsers(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var routine = workoutFixtureRoutine(1) as Dictionary;
    for (var i = 0; i < 150; i++) {
        Fuzz.begin(60000 + i);
        var v = Fuzz.junk();
        var w = Fuzz.junk();
        try {
            Fuzz.go("ScalarParsers");
            Model.sameString(v, w);
            Model.validId(v);
            Model.validText(v, 64, false);
            Model.validText(v, 64, true);
            Model.validNonblankText(v, 64);
            Model.validProgramId(v);
            Model.inRange(v, 0, 100, false);
            Model.inRange(v, 0, 100, true);
            Model.validKg(v);
            Model.load100(v);
            Model.validLoadType(v);
            Model.validPlanTarget(v, w);
            Model.validWarmupTarget(v);
            Model.weightLoad100(v);
            Model.weightUnit(v);
            Model.validPrompts(v);
            Model.validUserVars(v);
            Model.validVarValue(v);
            Model.validUnit(v);
            Model.nameTag(v);
            Model.liftosaurSetProblem(v);
            Model.liftosaurEntryProblem(v);
            Model.liftosaurWorkoutProblem(v);
            Model.validEpochMillis(v);
            Model.epochMillis(v);
            Model.validAppendId(v);
            Model.validMappedSet(v);
            Model.validExtraWarmups(v);
            Model.validUpload(v);
            Model.validTemplate(v);
            Model.validSavedDraft(v, w);
            Model.validCompletedSet(v, w, 0);
            Model.validStoredSession(v, false);
            Catalog.promptsOf(v);
            LastPerformance.validCache(v);
            LastPerformance.validCacheEntry(v, w);
            LiftosaurLogic.maskKey(v instanceof String ? v as String : "abc");
            LiftosaurLogic.cleanKey(v instanceof String ? v as String : null);
            LiftosaurLogic.summaryUpload(v instanceof String ? v as String : null, false, null);
            if (v instanceof String) {
                Model.fit(v as String, 40);
                Model.byteLength(v as String);
                Catalog.liftExerciseId(v as String, w instanceof String ? w as String : "");
            }
            if (v instanceof Dictionary) {
                Model.validTimedRun(w, [v]);
                Model.validRest(w, [v]);
                Model.validSessionPointer(w, [v]);
            }
            Model.slotAt(routine, 100);
        } catch (ex) {
            Fuzz.caught(logger, "scalar parsers", 60000 + i, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "scalar parsers never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzLastPerformanceCache(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var ended = SessionLogic.copyDictionary(FuzzKit.fuzzActiveSession());
    ended["status"] = "completed";
    ended["endedAt"] = 1790752300;
    var cache = LastPerformance.merge({}, ended);
    for (var i = 0; i < 40; i++) {
        Fuzz.begin(7000 + i);
        var noisyCache = Fuzz.mutatedDict(cache, 1 + Fuzz.rand(3));
        var noisyEnded = Fuzz.mutatedDict(ended, 1 + Fuzz.rand(3));
        try {
            Fuzz.go("LastPerformanceCache");
            var clean = LastPerformance.sanitizeCache(noisyCache);
            LastPerformance.validCache(noisyCache);
            // The session being finalised is a validated one.
            if (Model.validStoredSession(noisyEnded, true)) {
                LastPerformance.merge(clean, noisyEnded);
            }
        } catch (ex) {
            Fuzz.caught(logger, "LastPerformance", 7000 + i, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "prefill cache reads never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzLiftoscriptText(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    for (var i = 0; i < 80; i++) {
        Fuzz.begin(8000 + i);
        var text = Fuzz.programText(40, 0);
        try {
            Fuzz.go("LiftoscriptText");
            var weeks = LiftosaurLogic.parseDays(text);
            if (weeks != null) {
                for (var w = 1; w <= (weeks as Array).size() + 1; w++) {
                    LiftosaurLogic.weekDayRows(weeks as Array, w);
                }
            }
        } catch (ex) {
            Fuzz.caught(logger, "parseDays generated", 8000 + i, ex);
        }
    }
    var fixtures = FuzzKit.fuzzProgramFixtures();
    for (var f = 0; f < fixtures.size(); f++) {
        var base = ((fixtures[f] as Dictionary)["data"] as Dictionary)["text"] as String;
        for (var i = 0; i < 40; i++) {
            var seed = 8500 + f * 100 + i;
            Fuzz.begin(seed);
            var text = Fuzz.mutateText(base);
            if (Fuzz.rand(2) == 0) {
                text = Fuzz.mutateText(text);
            }
            try {
                Fuzz.go("LiftoscriptText");
                LiftosaurLogic.parseDays(text);
            } catch (ex) {
                Fuzz.caught(logger, "parseDays mutated fixture " + f.toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "parseDays never throws on random text (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzLiftoscriptNearTheCap(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    for (var i = 0; i < 12; i++) {
        Fuzz.begin(9000 + i);
        var text = Fuzz.programText(30, 1 + i % 2);
        try {
            Fuzz.go("LiftoscriptNearTheCap");
            LiftosaurLogic.parseDays(text);
        } catch (ex) {
            Fuzz.caught(logger, "parseDays near cap", 9000 + i, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "parseDays never throws near the 16 KiB cap (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzSyncReplyHandlers(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var upper = workoutFixtureReply(1) as Dictionary;
    var first = workoutFixtureRoutine(1) as Dictionary;
    var programs = FuzzKit.fuzzProgramFixtures();
    var journals = [
        {"sequence" => 2, "phase" => "program", "index" => 0, "days" => [], "routineIds" => []},
        {"sequence" => 2, "phase" => "next", "index" => 0, "programId" => first["programId"],
            "programName" => "P", "weeks" => [["DayAx", "DayBx"], ["DayCx"]], "routineIds" => []},
        syncJournal(first, 2)];
    var purposes = [Liftosaur.REQ_SYNC_PROGRAM, Liftosaur.REQ_SYNC_NEXT, Liftosaur.REQ_SYNC_DAY];
    var store = new UploadMemoryStore();
    var controller = new SessionController(store);
    for (var k = 0; k < 3; k++) {
        for (var i = 0; i < 50; i++) {
            var seed = 10000 + k * 100 + i;
            Fuzz.begin(seed);
            var journal = Fuzz.rand(3) == 0 ? Fuzz.mutatedDict(journals[k], 1 + Fuzz.rand(2)) :
                Fuzz.copy(journals[k]);
            FuzzKit.fuzzResetSyncStore(store, first, journal);
            var base = k == 0 ? programs[i % 2] : upper;
            var data = Fuzz.rand(12) == 0 ? Fuzz.junk() : Fuzz.mutated(base, Fuzz.rand(4));
            var code = Fuzz.rand(5) == 0 ? FuzzKit.fuzzResponseCode() : 200;
            try {
                Fuzz.go("SyncReplyHandlers");
                controller.handleApiResponse(purposes[k], null, code, data);
                FuzzKit.fuzzSettleJournal(controller, store);
                controller.diagnostics();
                controller.errorMessage();
            } catch (ex) {
                Fuzz.caught(logger, "sync " + purposes[k].toString() + " code " + code.toString(), seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "sync reply handlers never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzSyncProgramText(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var first = workoutFixtureRoutine(1) as Dictionary;
    var programs = FuzzKit.fuzzProgramFixtures();
    var store = new UploadMemoryStore();
    var controller = new SessionController(store);
    for (var i = 0; i < 40; i++) {
        var seed = 11000 + i;
        Fuzz.begin(seed);
        var reply = Fuzz.copy(programs[i % 2]) as Dictionary;
        var data = reply["data"] as Dictionary;
        data["text"] = i % 4 == 3 ? Fuzz.programText(30, 1 + Fuzz.rand(2)) : Fuzz.programText(40, 0);
        FuzzKit.fuzzResetSyncStore(store, first, {"sequence" => 2, "phase" => "program", "index" => 0,
            "days" => [], "routineIds" => []});
        try {
            Fuzz.go("SyncProgramText");
            controller.handleApiResponse(Liftosaur.REQ_SYNC_PROGRAM, null, 200, reply);
            FuzzKit.fuzzSettleJournal(controller, store);
        } catch (ex) {
            Fuzz.caught(logger, "sync program text", seed, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "the program reply handler never throws on odd text (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzUploadMapping(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var kinds = [["weight", false], ["timed", true], ["weight", true]];
    for (var k = 0; k < kinds.size(); k++) {
        var type = (kinds[k] as Array)[0] as String;
        var uni = (kinds[k] as Array)[1] as Boolean;
        var session = phase2UploadSession(type, uni, 1790752141, 1790752201);
        var job = UploadLogic.makeJob(session) as Dictionary;
        var reply = phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", Model.sameString(type, "timed"), uni, "p");
        for (var i = 0; i < 40; i++) {
            var seed = 12000 + k * 100 + i;
            Fuzz.begin(seed);
            var noisyReply = Fuzz.mutated(reply, Fuzz.rand(4));
            var noisyJob = Fuzz.rand(3) == 0 ? Fuzz.mutatedDict(job, 1 + Fuzz.rand(2)) : job;
            try {
                Fuzz.go("UploadMapping");
                UploadLogic.previewMaps(noisyJob, noisyReply);
                UploadLogic.withStartedWorkout(noisyJob, noisyReply);
                UploadLogic.mapWorkout(noisyJob, noisyReply, i % 2 == 0);
                if (i % 5 == 0) {
                    UploadLogic.makeJob(Fuzz.mutatedDict(session, 1 + Fuzz.rand(3)));
                }
            } catch (ex) {
                Fuzz.caught(logger, "upload mapping " + type, seed, ex);
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "upload mapping never throws (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzUploadResponseHandlers(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var purposes = [Liftosaur.REQ_UPLOAD_PREVIEW, Liftosaur.REQ_UPLOAD_START, Liftosaur.REQ_UPLOAD_RESUME_SETS,
        Liftosaur.REQ_UPLOAD_CURRENT, Liftosaur.REQ_UPLOAD_CURRENT_RESUME, Liftosaur.REQ_UPLOAD_SETS,
        Liftosaur.REQ_UPLOAD_FINISH, Liftosaur.REQ_KEY_TEST];
    var job = FuzzKit.fuzzJob("weight", false);
    var reply = phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", false, false, "p");
    var conflict = {"error" => {"code" => Liftosaur.ERR_ALREADY_ACTIVE, "message" => "open"}};
    var store = new UploadMemoryStore();
    var controller = new SessionController(store);
    for (var i = 0; i < 80; i++) {
        var seed = 13000 + i;
        Fuzz.begin(seed);
        store.deleteUpload("session-1");
        store.deletePair("uploadq");
        fixtureQueueUpload(store, i % 4 == 0 ? Fuzz.mutatedDict(job, 1) : Fuzz.copy(job) as Dictionary);
        var purpose = purposes[Fuzz.rand(purposes.size())] as String;
        var code = Fuzz.rand(3) == 0 ? FuzzKit.fuzzResponseCode() : 200;
        var data = Fuzz.rand(10) == 0 ? Fuzz.junk() :
            Fuzz.mutated(code == 409 ? conflict : reply, Fuzz.rand(4));
        try {
            Fuzz.go("UploadResponseHandlers");
            if (Fuzz.rand(2) == 0) {
                // Advance the job to the "sets" state with a good start reply first.
                controller.handleApiResponse(Liftosaur.REQ_UPLOAD_START, "session-1", 200, reply);
            }
            controller.handleApiResponse(purpose, "session-1", code, data);
            controller.handleApiResponse(purpose, i % 3 == 0 ? null : "session-9", code, data);
            controller.uploadStatuses();
            controller.uploadSummary();
            controller.activityLabel();
            controller.pendingUploadCount();
            controller.hasStuckUpload();
        } catch (ex) {
            Fuzz.caught(logger, "upload " + purpose.toString() + " code " + code.toString(), seed, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "upload response handlers never throw (" + Fuzz.failures.toString() + ")");
}

(:test)
function testFuzzStoreLoadPaths(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var routine = workoutFixtureRoutine(1) as Dictionary;
    var session = FuzzKit.fuzzActiveSession();
    var ended = SessionLogic.copyDictionary(session);
    ended["status"] = "completed";
    ended["endedAt"] = 1790752300;
    var parts = {
        "config" => {"schemaVersion" => 4, "nextSessionSeq" => 2,
            "settings" => {"defaultRestSec" => 90, "vibrationEnabled" => true},
            "incrementOverrides" => {}, "routineIds" => [routine["id"]], "routineSyncSeq" => 1,
            "programId" => "x0001xxx", "programName" => "P", "nextRoutineId" => routine["id"]},
        "routine.sync-1-d1" => routine,
        "active" => session,
        "history0" => ended,
        "last" => LastPerformance.merge({}, ended),
        "uploadq" => {"ids" => ["session-1"], "retired" => []},
        "upload.session-1" => FuzzKit.fuzzJob("weight", false),
        "upstatus" => {"order" => ["session-0"], "map" => {"session-0" => "done"}},
        "rsync" => syncJournal(routine, 2),
        "device" => {"id" => "abc-1"}
    };
    var keys = ["config.a", "config.b", "routine.sync-1-d1.a", "active.a", "active.b", "history0.a",
        "last.a", "uploadq.a", "uploadq.b", "upload.session-1.a", "upload.session-1.b", "upstatus.a",
        "rsync.a", "device.a", "ckpt"];
    for (var i = 0; i < 60; i++) {
        var seed = 14000 + i;
        Fuzz.begin(seed);
        var store = new UploadMemoryStore();
        FuzzKit.fuzzSeedStore(store, Fuzz.copy(parts) as Dictionary);
        var hits = 1 + Fuzz.rand(3);
        for (var h = 0; h < hits; h++) {
            var key = keys[Fuzz.rand(keys.size())] as String;
            var raw = store.readKey(key);
            if (raw == null) {
                continue;
            }
            if (Fuzz.rand(5) == 0) {
                store.writeKey(key, Fuzz.junk() == null ? 0 : Fuzz.junk());
                Fuzz.trail.add(key + " replaced by junk");
            } else {
                store.writeKey(key, Fuzz.mutated(raw, 1 + Fuzz.rand(2)));
                Fuzz.trail.add("in " + key);
            }
        }
        try {
            Fuzz.go("StoreLoadPaths");
            store.loadUploadQueue();
            store.loadRoutineSync();
            store.loadUploadStatus();
            store.loadUpload("session-1");
            store.loadDeviceId();
            store.loadApiKey();
            store.loadOlderPair("config");
            store.peekSession("active");
            store.peekSession("history0");
            store.loadCheckpoint("session-1");
            store.loadPair("last");
            store.saveUploadQueue(["session-2"]);
            store.markUploadStatus("session-2", "done");
            store.removeUploadFromQueue("session-1");
            store.clearUploadQueue(true);
            var controller = new SessionController(store);
            controller.session();
            controller.errorMessage();
            controller.historySessions();
            controller.routineTemplates();
            controller.programExercises();
            controller.nextRoutineId();
            controller.defaultRestSec();
            controller.vibrationEnabled();
            controller.uploadSummary();
            controller.uploadStatuses();
            controller.pendingUploadCount();
            controller.hasStuckUpload();
            controller.uploadQueueDamaged();
            controller.syncActionable();
            controller.diagnostics();
            controller.checkpointDue(1790752400);
            controller.onTick(1790752400, false);
            controller.timedElapsed(1790752400);
            controller.flushDraft();
        } catch (ex) {
            Fuzz.caught(logger, "store load paths", seed, ex);
        }
    }
    return check(logger, Fuzz.failures == 0, "stored-record load paths never throw (" + Fuzz.failures.toString() + ")");
}

// A session the store accepts must survive every workout operation on it: the active-workout
// edits and the finishing steps that read it (archive, FIT summary, upload job).
(:test)
function testFuzzValidatedSessionConsumers(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var active = FuzzKit.fuzzActiveSession();
    var ended = SessionLogic.copyDictionary(active);
    ended["status"] = "completed";
    ended["endedAt"] = 1790752300;
    var cases = [active, ended];
    var accepted = 0;
    for (var f = 0; f < cases.size(); f++) {
        for (var i = 0; i < 50; i++) {
            var seed = 15000 + f * 100 + i;
            Fuzz.begin(seed);
            var session = Fuzz.mutated(cases[f], Fuzz.rand(3));
            try {
                Fuzz.go("ValidatedSessionConsumers " + f.toString());
                if (!Model.validStoredSession(session, f == 1)) {
                    continue;
                }
                accepted++;
                FuzzKit.fuzzSessionConsumers(session as Dictionary, f == 1);
            } catch (ex) {
                Fuzz.caught(logger, "session consumers " + f.toString(), seed, ex);
            }
        }
    }
    logger.debug("accepted mutated sessions: " + accepted.toString());
    return check(logger, Fuzz.failures == 0, "workout operations never throw on accepted sessions (" + Fuzz.failures.toString() + ")");
}

// Every response handler against every stored state, with good, empty and odd replies: a late or
// stray reply (a day reply while the journal is still at the program step, an upload reply for a
// job already at another step) must be rejected, not index past the stored data.
(:test)
function testFuzzHandlerStateMatrix(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var upper = workoutFixtureReply(1) as Dictionary;
    var first = workoutFixtureRoutine(1) as Dictionary;
    var program = FuzzKit.fuzzProgramFixtures()[0];
    var journals = [
        {"sequence" => 2, "phase" => "program", "index" => 0, "days" => [], "routineIds" => []},
        {"sequence" => 2, "phase" => "next", "index" => 0, "programId" => first["programId"],
            "programName" => "P", "weeks" => [["DayAx"]], "routineIds" => []},
        {"sequence" => 2, "phase" => "next", "index" => 0, "programId" => first["programId"],
            "programName" => "P", "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "DayAx"}],
            "routineIds" => []},
        syncJournal(first, 2),
        {"sequence" => 2, "phase" => "days", "index" => 1, "programId" => first["programId"],
            "programName" => "P", "days" => [{"week" => first["week"], "dayInWeek" => first["dayInWeek"],
            "name" => first["name"]}], "routineIds" => [first["id"]]},
        {"sequence" => 2, "phase" => "days", "index" => 0, "programId" => first["programId"],
            "programName" => "P", "days" => [], "routineIds" => []}];
    var replies = [upper, program, {}, {"data" => {}}, null];
    var purposes = [Liftosaur.REQ_SYNC_PROGRAM, Liftosaur.REQ_SYNC_NEXT, Liftosaur.REQ_SYNC_DAY];
    var store = new UploadMemoryStore();
    var controller = new SessionController(store);
    var n = 0;
    for (var j = 0; j < journals.size(); j++) {
        for (var p = 0; p < purposes.size(); p++) {
            for (var r = 0; r < replies.size(); r++) {
                n++;
                Fuzz.begin(16000 + n);
                Fuzz.trail.add("journal " + j.toString() + " purpose " + purposes[p].toString() +
                    " reply " + r.toString());
                FuzzKit.fuzzResetSyncStore(store, first, Fuzz.copy(journals[j]));
                try {
                    Fuzz.go("HandlerStateMatrix sync");
                    controller.handleApiResponse(purposes[p], null, 200, Fuzz.copy(replies[r]));
                    FuzzKit.fuzzSettleJournal(controller, store);
                } catch (ex) {
                    Fuzz.caught(logger, "sync matrix", 16000 + n, ex);
                }
            }
        }
    }
    var kinds = [FuzzKit.fuzzJob("weight", false), FuzzKit.fuzzJob("timed", true)];
    var purposesUp = [Liftosaur.REQ_UPLOAD_PREVIEW, Liftosaur.REQ_UPLOAD_START, Liftosaur.REQ_UPLOAD_RESUME_SETS,
        Liftosaur.REQ_UPLOAD_CURRENT, Liftosaur.REQ_UPLOAD_CURRENT_RESUME, Liftosaur.REQ_UPLOAD_SETS,
        Liftosaur.REQ_UPLOAD_FINISH];
    var states = [Liftosaur.STATE_START, Liftosaur.STATE_SETS, Liftosaur.STATE_FINISH, Liftosaur.STATE_BLOCKED];
    var conflict = {"error" => {"code" => Liftosaur.ERR_ALREADY_ACTIVE}};
    var taken = {"error" => {"code" => Liftosaur.ERR_START_TIME_TAKEN}};
    for (var k = 0; k < kinds.size(); k++) {
        var job = kinds[k] as Dictionary;
        var good = phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", k == 1, k == 1, "p");
        var data = [good, {}, null, conflict, taken, "text"];
        for (var s = 0; s < states.size(); s++) {
            for (var p = 0; p < purposesUp.size(); p++) {
                for (var d = 0; d < data.size(); d++) {
                    n++;
                    Fuzz.begin(16000 + n);
                    Fuzz.trail.add("job " + k.toString() + " state " + states[s].toString() + " purpose " +
                        purposesUp[p].toString() + " data " + d.toString());
                    var staged = SessionLogic.copyDictionary(job);
                    staged["state"] = states[s];
                    if (Model.sameString(states[s], Liftosaur.STATE_SETS)) {
                        staged["setsBody"] = {"sets" => []};
                    }
                    store.deleteUpload("session-1");
                    store.deletePair("uploadq");
                    fixtureQueueUpload(store, staged);
                    var code = d == 3 || d == 4 ? 409 : 200;
                    try {
                        Fuzz.go("HandlerStateMatrix upload");
                        controller.handleApiResponse(purposesUp[p], "session-1", code, Fuzz.copy(data[d]));
                    } catch (ex) {
                        Fuzz.caught(logger, "upload matrix", 16000 + n, ex);
                    }
                }
            }
        }
    }
    return check(logger, Fuzz.failures == 0, "no handler throws on a reply that does not match its stored state (" + Fuzz.failures.toString() + ")");
}

// Regression: a day reply that arrives while the journal is not at the day step (or after the
// last day) used to index past the journal's day list (Array Out Of Bounds in routineDayReceived).
(:test)
function testStrayDayReplyIsRejected(logger as Test.Logger) as Boolean {
    var upper = workoutFixtureReply(1) as Dictionary;
    var first = workoutFixtureRoutine(1) as Dictionary;
    var store = new UploadMemoryStore();
    var controller = new SessionController(store);
    FuzzKit.fuzzResetSyncStore(store, first, {"sequence" => 2, "phase" => "program", "index" => 0,
        "days" => [], "routineIds" => []});
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, upper);
    var atProgramStep = controller.errorCode();
    FuzzKit.fuzzResetSyncStore(store, first, {"sequence" => 2, "phase" => "days", "index" => 1,
        "programId" => first["programId"], "programName" => "P",
        "days" => [{"week" => first["week"], "dayInWeek" => first["dayInWeek"], "name" => first["name"]}],
        "routineIds" => [first["id"]]});
    controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, upper);
    var afterLastDay = controller.errorCode();
    return check(logger, atProgramStep == Err.ROUTINE_SYNC_INVALID_RESPONSE,
            "a day reply at the program step is rejected") &&
        check(logger, afterLastDay == Err.ROUTINE_SYNC_INVALID_RESPONSE,
            "a day reply after the last day is rejected");
}

// Sweep: every field of a reply, one at a time, set to each extreme value (systematic where the
// random mutation is sampled).
(:test)
function testFuzzFieldSweepOfReplies(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var fixtures = [phase2ApiWorkout("DayBx", 1790752141000l, "Row", false, false, "a"),
        phase2ApiWorkout("DayBx", 1790752141000l, "Plank", true, true, "b")];
    var extremes = FuzzKit.fuzzExtremes();
    var n = 0;
    for (var f = 0; f < fixtures.size(); f++) {
        var reply = fixtures[f] as Dictionary;
        var spots = FuzzKit.fuzzSpots(reply);
        for (var s = 0; s < spots.size(); s++) {
            var spot = spots[s] as Array;
            var holder = spot[0];
            var original = holder[spot[1]];
            for (var v = 0; v < extremes.size(); v++) {
                n++;
                Fuzz.begin(17000 + n);
                Fuzz.trail.add((spot[2] as String) + " = " + Fuzz.typeName(extremes[v]) + " #" + v.toString());
                holder[spot[1]] = extremes[v];
                try {
                    Fuzz.go("FieldSweep " + f.toString());
                    Catalog.dayCoordinates(reply);
                    var routine = Catalog.parseRoutine(reply, 1, 1);
                    if (routine != null) {
                        Catalog.createSession((routine as Dictionary)["id"] as String, "session-1", 1,
                            1790752141, null, FuzzKit.fuzzConfig(routine as Dictionary));
                    }
                } catch (ex) {
                    Fuzz.caught(logger, "field sweep " + f.toString(), 17000 + n, ex);
                }
            }
            holder[spot[1]] = original;
        }
    }
    logger.debug("field sweep cases: " + n.toString());
    return check(logger, Fuzz.failures == 0, "no single field value crashes the reply parser (" + Fuzz.failures.toString() + ")");
}

// Sweep of a stored session and an upload job: each field set to each extreme; whatever the
// validators accept must run through the consumers.
(:test)
function testFuzzFieldSweepOfStoredRecords(logger as Test.Logger) as Boolean {
    Fuzz.failures = 0;
    var active = FuzzKit.fuzzActiveSession();
    var ended = SessionLogic.copyDictionary(active);
    ended["status"] = "completed";
    ended["endedAt"] = 1790752300;
    var job = FuzzKit.fuzzJob("weight", false);
    var reply = phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", false, false, "p");
    var records = [active, ended, job];
    var extremes = FuzzKit.fuzzExtremes();
    var n = 0;
    var accepted = 0;
    for (var f = 0; f < records.size(); f++) {
        var record = records[f] as Dictionary;
        var spots = FuzzKit.fuzzSpots(record);
        for (var s = f; s < spots.size(); s += 7) {
            var spot = spots[s] as Array;
            var holder = spot[0];
            var original = holder[spot[1]];
            for (var v = 0; v < extremes.size(); v++) {
                n++;
                Fuzz.begin(19000 + n);
                Fuzz.trail.add("record " + f.toString() + " " + (spot[2] as String) + " = " +
                    Fuzz.typeName(extremes[v]) + " #" + v.toString());
                holder[spot[1]] = extremes[v];
                try {
                    Fuzz.go("FieldSweepStored");
                    if (f < 2 && Model.validStoredSession(record, f == 1)) {
                        accepted++;
                        FuzzKit.fuzzSessionConsumers(record, f == 1);
                    } else if (f == 2 && Model.validUpload(record)) {
                        accepted++;
                        UploadLogic.startBody(record);
                        UploadLogic.finishBody(record);
                        UploadLogic.setsDone(record);
                        UploadLogic.mapWorkout(record, reply, true);
                        UploadLogic.previewMaps(record, reply);
                    }
                } catch (ex) {
                    Fuzz.caught(logger, "stored sweep " + f.toString(), 19000 + n, ex);
                }
            }
            holder[spot[1]] = original;
        }
    }
    logger.debug("stored sweep cases: " + n.toString() + ", accepted " + accepted.toString());
    return check(logger, Fuzz.failures == 0, "no single field value crashes the stored-record consumers (" + Fuzz.failures.toString() + ")");
}
