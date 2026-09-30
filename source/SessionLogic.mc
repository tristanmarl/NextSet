import Toybox.Lang;

module SessionLogic {
    function copyDictionary(source as Dictionary) as Dictionary {
        var copy = {};
        var keys = source.keys();
        for (var i = 0; i < keys.size(); i++) {
            copy[keys[i]] = source[keys[i]];
        }
        return copy;
    }

    function exerciseIndex(session as Dictionary, entryId as String) as Number {
        var exercises = session["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            if (Model.sameString(exercises[i]["entryId"], entryId)) {
                return i;
            }
        }
        return -1;
    }

    function slotCandidate(session as Dictionary, exerciseIndex as Number, slotIndex as Number) as Dictionary {
        var candidate = copyDictionary(session);
        var sourceExercises = session["exercises"] as Array;
        var exercises = [];
        var updatedExercise = null;
        var updatedSlot = null;
        for (var i = 0; i < sourceExercises.size(); i++) {
            if (i == exerciseIndex) {
                updatedExercise = copyDictionary(sourceExercises[i] as Dictionary);
                var sourceSlots = sourceExercises[i]["slots"] as Array;
                var slots = [];
                for (var j = 0; j < sourceSlots.size(); j++) {
                    if (j == slotIndex) {
                        updatedSlot = copyDictionary(sourceSlots[j] as Dictionary);
                        updatedSlot["draft"] = copyDictionary(sourceSlots[j]["draft"] as Dictionary);
                        slots.add(updatedSlot);
                    } else {
                        slots.add(sourceSlots[j]);
                    }
                }
                updatedExercise["slots"] = slots;
                exercises.add(updatedExercise);
            } else {
                exercises.add(sourceExercises[i]);
            }
        }
        candidate["exercises"] = exercises;
        var result = {};
        result["session"] = candidate;
        result["exercise"] = updatedExercise;
        result["slot"] = updatedSlot;
        return result;
    }

    function exerciseCandidate(session as Dictionary, exerciseIndex as Number) as Dictionary {
        var candidate = copyDictionary(session);
        var sourceExercises = session["exercises"] as Array;
        var exercises = [];
        var updatedExercise = null;
        for (var i = 0; i < sourceExercises.size(); i++) {
            if (i == exerciseIndex) {
                updatedExercise = copyDictionary(sourceExercises[i] as Dictionary);
                var slots = sourceExercises[i]["slots"] as Array;
                var copiedSlots = [];
                for (var j = 0; j < slots.size(); j++) {
                    copiedSlots.add(slots[j]);
                }
                updatedExercise["slots"] = copiedSlots;
                exercises.add(updatedExercise);
            } else {
                exercises.add(sourceExercises[i]);
            }
        }
        candidate["exercises"] = exercises;
        var result = {};
        result["session"] = candidate;
        result["exercise"] = updatedExercise;
        return result;
    }

    function timedSlotCandidate(session as Dictionary, entryId as String,
                                slotIndex as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        if (!Model.sameString(exercise["loadType"], "timed") || exercise["closedEarly"] ||
            slotIndex < 0 || slotIndex >= slots.size() || slots[slotIndex]["completed"] != null) {
            return null;
        }
        return slotCandidate(session, index, slotIndex);
    }

    function timedElapsedSec(run as Dictionary, now as Number) as Number {
        var accumulated = run["accumulatedSec"] instanceof Number ? run["accumulatedSec"] as Number : 0;
        var startedAt = run["startedAt"] instanceof Number ? run["startedAt"] as Number : now;
        var elapsed = accumulated + (now > startedAt ? now - startedAt : 0);
        return elapsed < 0 ? 0 : (elapsed > Model.MAX_DURATION_SEC ? Model.MAX_DURATION_SEC : elapsed);
    }

    function startTimed(session as Dictionary, entryId as String, slotIndex as Number,
                        now as Number) as Dictionary? {
        if (session["timedRun"] != null) {
            return null;
        }
        var state = timedSlotCandidate(session, entryId, slotIndex);
        if (state == null) {
            return null;
        }
        var draft = (state["slot"] as Dictionary)["draft"] as Dictionary;
        var accumulated = draft["measuredSec"] instanceof Number ? draft["measuredSec"] as Number : 0;
        if (!Model.inRange(accumulated, 0, Model.MAX_DURATION_SEC, false)) {
            return null;
        }
        var candidate = state["session"] as Dictionary;
        candidate["timedRun"] = {
            "entryId" => entryId,
            "slot" => slotIndex,
            "startedAt" => now,
            "accumulatedSec" => accumulated,
            "targetAlertConsumed" => draft["targetAlertConsumed"] == true
        };
        return candidate;
    }

    function pauseTimed(session as Dictionary, entryId as String, slotIndex as Number,
                        now as Number) as Dictionary? {
        var run = session["timedRun"];
        if (!(run instanceof Dictionary) || !Model.sameString(run["entryId"], entryId) ||
            run["slot"] != slotIndex) {
            return null;
        }
        var state = timedSlotCandidate(session, entryId, slotIndex);
        if (state == null) {
            return null;
        }
        var candidate = state["session"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        var draft = slot["draft"] as Dictionary;
        draft["measuredSec"] = timedElapsedSec(run as Dictionary, now);
        draft["targetAlertConsumed"] = run["targetAlertConsumed"] == true;
        candidate["timedRun"] = null;
        return candidate;
    }

    function cancelTimed(session as Dictionary, entryId as String,
                         slotIndex as Number) as Dictionary? {
        var run = session["timedRun"];
        if (run != null && (!(run instanceof Dictionary) ||
            !Model.sameString(run["entryId"], entryId) || run["slot"] != slotIndex)) {
            return null;
        }
        var state = timedSlotCandidate(session, entryId, slotIndex);
        if (state == null) {
            return null;
        }
        var candidate = state["session"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        var draft = slot["draft"] as Dictionary;
        draft["measuredSec"] = 0;
        draft["targetAlertConsumed"] = false;
        candidate["timedRun"] = null;
        return candidate;
    }

    function completeTimed(session as Dictionary, entryId as String, slotIndex as Number,
                           now as Number) as Dictionary? {
        var state = timedSlotCandidate(session, entryId, slotIndex);
        if (state == null) {
            return null;
        }
        var run = session["timedRun"];
        if (run != null && !(run instanceof Dictionary)) {
            return null;
        }
        var draft = (state["slot"] as Dictionary)["draft"] as Dictionary;
        var duration = 0;
        if (run instanceof Dictionary) {
            if (!Model.sameString(run["entryId"], entryId) || run["slot"] != slotIndex) {
                return null;
            }
            duration = timedElapsedSec(run as Dictionary, now);
        } else if (draft["measuredSec"] instanceof Number) {
            duration = draft["measuredSec"] as Number;
        }
        if (!Model.inRange(duration, 1, Model.MAX_DURATION_SEC, false)) {
            return null;
        }
        var base = state["session"] as Dictionary;
        base["timedRun"] = null;
        var actual = {"durationSec" => duration};
        var candidate = completeSet(base, entryId, slotIndex, actual, now);
        if (candidate == null) {
            return null;
        }
        var changed = candidate as Dictionary;
        var changedExercise = (changed["exercises"] as Array)[exerciseIndex(changed, entryId)] as Dictionary;
        var completedSlot = (changedExercise["slots"] as Array)[slotIndex] as Dictionary;
        var completed = completedSlot["completed"] as Dictionary;
        var completedDraft = completedSlot["draft"] as Dictionary;
        completed["durationSource"] = "measured";
        completedDraft["measuredSec"] = 0;
        completedDraft["durationEdited"] = false;
        completedDraft["targetAlertConsumed"] = false;
        return changed;
    }

    function setRunMatches(session as Dictionary, entryId as String, slotIndex as Number) as Boolean {
        var run = session["setRun"];
        return run instanceof Dictionary && Model.sameString(run["entryId"], entryId) &&
            run["slot"] == slotIndex;
    }

    function setElapsedSec(run as Dictionary, now as Number) as Number {
        var startedAt = run["startedAt"] instanceof Number ? run["startedAt"] as Number : now;
        var elapsed = now - startedAt;
        return elapsed < 0 ? 0 : (elapsed > Model.MAX_DURATION_SEC ? Model.MAX_DURATION_SEC : elapsed);
    }

    // Explicit "start set" for non-timed sets: records when the set began so the logged set can
    // carry its real duration. Starting a set also ends a running or expired rest.
    function startSet(session as Dictionary, entryId as String, slotIndex as Number,
                      now as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0 || session["setRun"] != null || session["timedRun"] != null ||
            !Model.inRange(now, 0, 2147483647, false)) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        if (Model.sameString(exercise["loadType"], "timed") || exercise["closedEarly"] ||
            slotIndex < 0 || slotIndex >= slots.size() || slots[slotIndex]["completed"] != null) {
            return null;
        }
        var candidate = copyDictionary(session);
        candidate["setRun"] = {"entryId" => entryId, "slot" => slotIndex, "startedAt" => now};
        var rest = session["rest"];
        if (rest instanceof Dictionary && (Model.sameString(rest["state"], "running") ||
            Model.sameString(rest["state"], "expired"))) {
            candidate["rest"] = RestClock.skip(rest as Dictionary);
        }
        return candidate;
    }

    function cancelSet(session as Dictionary, entryId as String, slotIndex as Number) as Dictionary? {
        if (!setRunMatches(session, entryId, slotIndex)) {
            return null;
        }
        var candidate = copyDictionary(session);
        candidate["setRun"] = null;
        return candidate;
    }

    function validActual(exercise as Dictionary, actual as Dictionary) as Boolean {
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
            return Model.inRange(actual["load100"], 0, Model.MAX_LOAD100, false) &&
                Model.inRange(actual["reps"], 1, Model.MAX_REPS, false);
        }
        if (Model.sameString(type, "bodyweight")) {
            return Model.inRange(actual["reps"], 1, Model.MAX_REPS, false);
        }
        return Model.sameString(type, "timed") &&
            Model.inRange(actual["durationSec"], 1, Model.MAX_DURATION_SEC, false);
    }

    function applyActual(exercise as Dictionary, slot as Dictionary, actual as Dictionary) as Void {
        var draft = slot["draft"] as Dictionary;
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
            draft["load100"] = actual["load100"];
            draft["reps"] = actual["reps"];
        } else if (Model.sameString(type, "bodyweight")) {
            draft["reps"] = actual["reps"];
        } else {
            draft["durationSec"] = actual["durationSec"];
        }
    }

    function completeSet(session as Dictionary, entryId as String, slotIndex as Number,
                         actual as Dictionary, now as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercises = session["exercises"] as Array;
        var exercise = exercises[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        if (exercise["closedEarly"] || slotIndex < 0 || slotIndex >= slots.size() ||
            slots[slotIndex]["completed"] != null || !validActual(exercise, actual)) {
            return null;
        }

        var state = slotCandidate(session, index, slotIndex);
        var candidate = state["session"] as Dictionary;
        var changedExercise = state["exercise"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        var completed = {};
        var sequence = session["nextSetSequence"] as Number;
        completed["slot"] = slotIndex;
        completed["sequence"] = sequence;
        completed["completedAt"] = now;
        completed["updatedAt"] = now;
        completed["load100"] = null;
        completed["reps"] = null;
        completed["durationSec"] = null;
        if (Model.sameString(changedExercise["loadType"], "weight") || Model.sameString(changedExercise["loadType"], "assistance")) {
            completed["load100"] = actual["load100"];
            completed["reps"] = actual["reps"];
        } else if (Model.sameString(changedExercise["loadType"], "bodyweight")) {
            completed["reps"] = actual["reps"];
        } else {
            completed["durationSec"] = actual["durationSec"];
            completed["durationSource"] = "manual";
        }
        if (setRunMatches(session, entryId, slotIndex)) {
            completed["activeSec"] = setElapsedSec(session["setRun"] as Dictionary, now);
            candidate["setRun"] = null;
        }
        applyActual(changedExercise, slot, actual);
        if (Model.sameString(changedExercise["loadType"], "timed")) {
            var timedDraft = slot["draft"] as Dictionary;
            timedDraft["durationEdited"] = false;
            timedDraft["targetAlertConsumed"] = false;
        }
        slot["completed"] = completed;
        candidate["nextSetSequence"] = sequence + 1;
        var currentRestGeneration = session["restGeneration"] instanceof Number ?
            session["restGeneration"] as Number : 0;
        var restGeneration = currentRestGeneration + 1;
        candidate["restGeneration"] = restGeneration;
        candidate["rest"] = nextSlot(changedExercise) >= 0 ? RestClock.create(
            restGeneration,
            entryId,
            slotIndex,
            now,
            changedExercise["restSec"] as Number
        ) : null;
        var pointer = {};
        pointer["entryId"] = entryId;
        pointer["slot"] = slotIndex;
        candidate["lastCompleted"] = pointer;
        return candidate;
    }

    function updateFollowingLoads(exercise as Dictionary, slotIndex as Number,
                                  load100 as Number) as Void {
        var slots = exercise["slots"] as Array;
        for (var i = slotIndex + 1; i < slots.size(); i++) {
            if (slots[i]["completed"] != null) {
                continue;
            }
            var following = copyDictionary(slots[i] as Dictionary);
            var draft = copyDictionary(following["draft"] as Dictionary);
            draft["load100"] = load100;
            following["draft"] = draft;
            slots[i] = following;
        }
    }

    function correctSet(session as Dictionary, entryId as String, slotIndex as Number,
                        actual as Dictionary, now as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        if (slotIndex < 0 || slotIndex >= slots.size() ||
            slots[slotIndex]["completed"] == null || !validActual(exercise, actual)) {
            return null;
        }
        var state = slotCandidate(session, index, slotIndex);
        var candidate = state["session"] as Dictionary;
        var changedExercise = state["exercise"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        var completed = copyDictionary(slot["completed"] as Dictionary);
        var loadable = Model.sameString(changedExercise["loadType"], "weight") ||
            Model.sameString(changedExercise["loadType"], "assistance");
        var loadChanged = loadable && completed["load100"] != actual["load100"];
        if (loadable) {
            completed["load100"] = actual["load100"];
            completed["reps"] = actual["reps"];
        } else if (Model.sameString(changedExercise["loadType"], "bodyweight")) {
            completed["reps"] = actual["reps"];
        } else {
            completed["durationSec"] = actual["durationSec"];
            completed["durationSource"] = "manual";
        }
        completed["updatedAt"] = now;
        applyActual(changedExercise, slot, actual);
        slot["completed"] = completed;
        if (loadChanged) {
            updateFollowingLoads(changedExercise, slotIndex, actual["load100"] as Number);
        }
        return candidate;
    }

    function updateDraft(session as Dictionary, entryId as String, slotIndex as Number,
                         field as String, value as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        var run = session["timedRun"];
        if (slotIndex < 0 || slotIndex >= slots.size() ||
            slots[slotIndex]["completed"] != null || exercise["closedEarly"] ||
            (run instanceof Dictionary && Model.sameString(run["entryId"], entryId) &&
             run["slot"] == slotIndex)) {
            return null;
        }
        var type = exercise["loadType"];
        if (Model.sameString(field, "load100") &&
            (Model.sameString(type, "weight") || Model.sameString(type, "assistance"))) {
            if (!Model.inRange(value, 0, Model.MAX_LOAD100, false)) {
                return null;
            }
        } else if (Model.sameString(field, "reps") && !Model.sameString(type, "timed")) {
            if (!Model.inRange(value, 1, Model.MAX_REPS, false)) {
                return null;
            }
        } else if (Model.sameString(field, "durationSec") && Model.sameString(type, "timed")) {
            if (!Model.inRange(value, 1, Model.MAX_DURATION_SEC, false)) {
                return null;
            }
        } else {
            return null;
        }
        var state = slotCandidate(session, index, slotIndex);
        var changedExercise = state["exercise"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        var draft = slot["draft"] as Dictionary;
        draft[field] = value;
        if (Model.sameString(field, "load100")) {
            updateFollowingLoads(changedExercise, slotIndex, value);
        }
        if (Model.sameString(type, "timed") && Model.sameString(field, "durationSec")) {
            draft["measuredSec"] = 0;
            draft["durationEdited"] = true;
            draft["targetAlertConsumed"] = false;
        }
        return state["session"] as Dictionary;
    }

    function addSet(session as Dictionary, entryId as String) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0 || totals(session)["planned"] >= Model.MAX_SETS_PER_WORKOUT) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var sourceSlots = exercise["slots"] as Array;
        if (sourceSlots.size() == 0 || sourceSlots.size() >= Model.MAX_SETS) {
            return null;
        }

        var state = exerciseCandidate(session, index);
        var changedExercise = state["exercise"] as Dictionary;
        var slots = changedExercise["slots"] as Array;
        var draft = copyDictionary(sourceSlots[sourceSlots.size() - 1]["draft"] as Dictionary);
        if (Model.sameString(exercise["loadType"], "timed")) {
            draft["measuredSec"] = 0;
            draft["durationEdited"] = false;
            draft["targetAlertConsumed"] = false;
        }
        var newSlot = {};
        newSlot["draft"] = draft;
        newSlot["completed"] = null;
        slots.add(newSlot);
        changedExercise["plannedSetCount"] = (exercise["plannedSetCount"] as Number) + 1;
        changedExercise["closedEarly"] = false;
        return state["session"] as Dictionary;
    }

    function undoSet(session as Dictionary, entryId as String, slotIndex as Number) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercise = (session["exercises"] as Array)[index] as Dictionary;
        var slots = exercise["slots"] as Array;
        if (slotIndex < 0 || slotIndex >= slots.size() || slots[slotIndex]["completed"] == null) {
            return null;
        }
        var state = slotCandidate(session, index, slotIndex);
        var candidate = state["session"] as Dictionary;
        var changedExercise = state["exercise"] as Dictionary;
        var slot = state["slot"] as Dictionary;
        slot["completed"] = null;
        changedExercise["closedEarly"] = false;
        var rest = candidate["rest"];
        if (rest instanceof Dictionary && Model.sameString(rest["entryId"], entryId) &&
            rest["slot"] == slotIndex) {
            candidate["rest"] = null;
        }
        if (candidate["lastCompleted"] != null &&
            Model.sameString(candidate["lastCompleted"]["entryId"], entryId) &&
            candidate["lastCompleted"]["slot"] == slotIndex) {
            candidate["lastCompleted"] = latestPointer(candidate);
        }
        return candidate;
    }

    function latestPointer(session as Dictionary) as Dictionary? {
        var exercises = session["exercises"] as Array;
        var latest = null;
        var latestSequence = -1;
        for (var i = 0; i < exercises.size(); i++) {
            var slots = exercises[i]["slots"] as Array;
            for (var j = 0; j < slots.size(); j++) {
                var completed = slots[j]["completed"];
                if (completed != null && completed["sequence"] > latestSequence) {
                    latestSequence = completed["sequence"];
                    latest = {"entryId" => exercises[i]["entryId"], "slot" => j};
                }
            }
        }
        return latest;
    }

    function closeExercise(session as Dictionary, entryId as String, closed as Boolean) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var state = exerciseCandidate(session, index);
        var exercise = state["exercise"] as Dictionary;
        exercise["closedEarly"] = closed;
        var candidate = state["session"] as Dictionary;
        candidate["setRun"] = null;
        var rest = candidate["rest"];
        if (closed && rest instanceof Dictionary && Model.sameString(rest["entryId"], entryId)) {
            candidate["rest"] = null;
        }
        if (closed && candidate["nextSetSequence"] instanceof Number) {
            candidate["nextSetSequence"] = (candidate["nextSetSequence"] as Number) + 1;
        }
        return candidate;
    }

    function completedCount(exercise as Dictionary) as Number {
        var count = 0;
        var slots = exercise["slots"] as Array;
        for (var i = 0; i < slots.size(); i++) {
            if (slots[i]["completed"] != null) {
                count++;
            }
        }
        return count;
    }

    function exerciseStatus(exercise as Dictionary) as String {
        var done = completedCount(exercise);
        var planned = exercise["plannedSetCount"] as Number;
        if (done == planned) {
            return "full";
        }
        if (exercise["closedEarly"]) {
            return "closed";
        }
        return done > 0 ? "partial" : "empty";
    }

    function nextSlot(exercise as Dictionary) as Number {
        if (exercise["closedEarly"]) {
            return -1;
        }
        var slots = exercise["slots"] as Array;
        for (var i = 0; i < slots.size(); i++) {
            if (slots[i]["completed"] == null) {
                return i;
            }
        }
        return -1;
    }

    function totals(session as Dictionary) as Dictionary {
        var done = 0;
        var planned = 0;
        var exercises = session["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            var exerciseDone = completedCount(exercise);
            done += exerciseDone;
            planned += exercise["closedEarly"] == true ? exerciseDone : exercise["plannedSetCount"];
        }
        return {"done" => done, "planned" => planned};
    }

    function archivedSession(ended as Dictionary) as Dictionary {
        var archive = {};
        var fields = ["id", "sessionSeq", "templateId", "templateRevision", "templateName",
            "startedAt", "endedAt", "status", "completionKind", "elapsedSec", "activeSec",
            "fitState", "fitSegments", "fitUnknownSegments"];
        for (var i = 0; i < fields.size(); i++) {
            var field = fields[i] as String;
            if (ended.hasKey(field)) {
                archive[field] = ended[field];
            }
        }
        var exercises = ended["exercises"] as Array;
        var archivedExercises = [];
        for (var i = 0; i < exercises.size(); i++) {
            var source = exercises[i] as Dictionary;
            var exercise = {
                "entryId" => source["entryId"],
                "exerciseId" => source["exerciseId"],
                "name" => source["name"],
                "loadType" => source["loadType"],
                "loadUnit" => source["loadUnit"],
                "plannedSetCount" => source["plannedSetCount"],
                "closedEarly" => source["closedEarly"]
            };
            var slots = source["slots"] as Array;
            var archivedSlots = [];
            for (var j = 0; j < slots.size(); j++) {
                archivedSlots.add({"completed" => (slots[j] as Dictionary)["completed"]});
            }
            exercise["slots"] = archivedSlots;
            archivedExercises.add(exercise);
        }
        archive["exercises"] = archivedExercises;
        return archive;
    }

    function truncateBytes(text as String, maxBytes as Number) as String {
        var result = text;
        while (result.length() > 0 && Model.byteLength(result) > maxBytes) {
            result = result.substring(0, result.length() - 1) as String;
        }
        return result;
    }

    // Values for one FIT lap developer-field set, from a completed set. Weight is kg: negative for
    // assistance (the offset from bodyweight), 0 for bodyweight and timed. Reps and duration are
    // 0 when they do not apply. activeSec is the set time: the measured duration for timed sets,
    // else the start-to-log time (0 when the set was not started explicitly, i.e. unknown).
    // garminCategory/garminCode identify the exercise for Garmin Connect ("" when unmapped or group-only).
    function lapPayload(exercise as Dictionary, slotIndex as Number) as Dictionary? {
        var completed = ((exercise["slots"] as Array)[slotIndex] as Dictionary)["completed"];
        if (!(completed instanceof Dictionary)) {
            return null;
        }
        var type = exercise["loadType"];
        var load100 = completed["load100"] instanceof Number ? completed["load100"] as Number : 0;
        var kg = load100 / 100.0;
        if (Model.sameString(type, "assistance")) {
            kg = -kg;
        } else if (!Model.sameString(type, "weight")) {
            kg = 0.0;
        }
        var category = exercise["garminCategory"];
        var code = exercise["garminCode"];
        return {
            "name" => truncateBytes(exercise["name"] as String, 64),
            "garminCategory" => category instanceof String ? truncateBytes(category as String, 23) : "",
            "garminCode" => code instanceof String ? truncateBytes(code as String, 64) : "",
            "set" => slotIndex + 1,
            "reps" => completed["reps"] instanceof Number ? completed["reps"] as Number : 0,
            "weightKg" => kg,
            "durationSec" => completed["durationSec"] instanceof Number ?
                completed["durationSec"] as Number : 0,
            "activeSec" => Model.sameString(type, "timed") ?
                (completed["durationSec"] instanceof Number ? completed["durationSec"] as Number : 0) :
                (completed["activeSec"] instanceof Number ? completed["activeSec"] as Number : 0)
        };
    }

    // Session-level FIT summary: completed sets, volume (weight x reps, weight exercises only,
    // kg) and the number of exercises with at least one completed set.
    function fitSummary(session as Dictionary) as Dictionary {
        var sets = 0;
        var exerciseCount = 0;
        var volume100 = 0;
        var exercises = session["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            var done = completedCount(exercise);
            sets += done;
            if (done > 0) {
                exerciseCount++;
            }
            if (Model.sameString(exercise["loadType"], "weight")) {
                var slots = exercise["slots"] as Array;
                for (var j = 0; j < slots.size(); j++) {
                    var completed = slots[j]["completed"];
                    if (completed instanceof Dictionary && completed["load100"] instanceof Number &&
                        completed["reps"] instanceof Number) {
                        volume100 += (completed["load100"] as Number) * (completed["reps"] as Number);
                    }
                }
            }
        }
        return {"sets" => sets, "volumeKg" => volume100 / 100.0, "exercises" => exerciseCount};
    }
}
