import Toybox.Lang;

module SessionLogic {
    function routineSyncAlreadyCommitted(syncSequence as Number,
                                         configSequence as Number) as Boolean {
        return configSequence >= syncSequence;
    }

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
                var warmup = slotIndex >= Model.WARMUP_BASE;
                var listKey = warmup ? "warmupSlots" : "slots";
                var target = warmup ? slotIndex - Model.WARMUP_BASE : slotIndex;
                var sourceSlots = sourceExercises[i][listKey] as Array;
                var slots = [];
                for (var j = 0; j < sourceSlots.size(); j++) {
                    if (j == target) {
                        updatedSlot = copyDictionary(sourceSlots[j] as Dictionary);
                        updatedSlot["draft"] = copyDictionary(sourceSlots[j]["draft"] as Dictionary);
                        slots.add(updatedSlot);
                    } else {
                        slots.add(sourceSlots[j]);
                    }
                }
                updatedExercise[listKey] = slots;
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
                if (sourceExercises[i]["warmupSlots"] instanceof Array) {
                    updatedExercise["warmupSlots"] =
                        (sourceExercises[i]["warmupSlots"] as Array).slice(0, null);
                }
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
        var existing = Model.slotAt(exercise, slotIndex);
        if (!Model.sameString(exercise["loadType"], "timed") || exercise["closedEarly"] ||
            existing == null || (existing as Dictionary)["completed"] != null) {
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
        var rest = candidate["rest"];
        if (rest instanceof Dictionary && (Model.sameString(rest["state"], "running") ||
            Model.sameString(rest["state"], "expired"))) {
            candidate["rest"] = RestClock.skip(rest as Dictionary);
        }
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
        var existing = Model.slotAt(exercise, slotIndex);
        if (exercise["closedEarly"] || existing == null ||
            (existing as Dictionary)["completed"] != null || !validActual(exercise, actual)) {
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
        var warmupSet = slotIndex >= Model.WARMUP_BASE;
        var wantRest = nextSlot(changedExercise) >= 0;
        if (!warmupSet && inSuperset(changedExercise)) {
            // Superset: rest only when the round ends (next member wraps) or the group is done.
            var following = supersetNext(candidate, entryId);
            wantRest = following != null && supersetWraps(candidate, entryId, following as String);
        }
        candidate["rest"] = wantRest ? RestClock.create(
            restGeneration,
            entryId,
            slotIndex,
            now,
            warmupSet ? (slot["restSec"] instanceof Number ? slot["restSec"] as Number : 60) :
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
        var targets = exercise["planTargets"];
        var sourceTarget = targets instanceof Array && slotIndex < (targets as Array).size() ?
            (targets as Array)[slotIndex] as Dictionary : null;
        for (var i = slotIndex + 1; i < slots.size(); i++) {
            if (slots[i]["completed"] != null) {
                continue;
            }
            if (sourceTarget != null && targets instanceof Array &&
                i < (targets as Array).size() &&
                (targets as Array)[i]["load100"] != sourceTarget["load100"]) {
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
        var existing = Model.slotAt(exercise, slotIndex);
        if (existing == null || (existing as Dictionary)["completed"] == null ||
            !validActual(exercise, actual)) {
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
        if (loadChanged && slotIndex < Model.WARMUP_BASE) {
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
        var existing = Model.slotAt(exercise, slotIndex);
        var run = session["timedRun"];
        if (existing == null ||
            (existing as Dictionary)["completed"] != null || exercise["closedEarly"] ||
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
        if (Model.sameString(field, "load100") && slotIndex < Model.WARMUP_BASE) {
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
        var existing = Model.slotAt(exercise, slotIndex);
        if (existing == null || (existing as Dictionary)["completed"] == null) {
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
            var warmups = exercises[i]["warmupSlots"];
            for (var j = 0; warmups instanceof Array && j < (warmups as Array).size(); j++) {
                var completed = (warmups as Array)[j]["completed"];
                if (completed != null && completed["sequence"] > latestSequence) {
                    latestSequence = completed["sequence"];
                    latest = {"entryId" => exercises[i]["entryId"], "slot" => Model.WARMUP_BASE + j};
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
        var rest = candidate["rest"];
        if (closed && rest instanceof Dictionary && Model.sameString(rest["entryId"], entryId)) {
            candidate["rest"] = null;
        }
        if (closed && candidate["nextSetSequence"] instanceof Number) {
            candidate["nextSetSequence"] = (candidate["nextSetSequence"] as Number) + 1;
        }
        return candidate;
    }

    function inSuperset(exercise as Dictionary) as Boolean {
        var label = exercise["superset"];
        return label instanceof String && (label as String).length() > 0;
    }

    function sameGroup(first as Dictionary, second as Dictionary) as Boolean {
        return inSuperset(first) && Model.sameString(first["superset"], second["superset"]);
    }

    // Round-robin: the next group member (routine order, wrapping, the exercise itself last)
    // that still has an open set; null when the exercise is ungrouped or the group is done.
    function supersetNext(session as Dictionary, entryId as String) as String? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercises = session["exercises"] as Array;
        var current = exercises[index] as Dictionary;
        if (!inSuperset(current)) {
            return null;
        }
        for (var offset = 1; offset <= exercises.size(); offset++) {
            var item = exercises[(index + offset) % exercises.size()] as Dictionary;
            if (sameGroup(current, item) && nextSlot(item) >= 0) {
                return item["entryId"] as String;
            }
        }
        return null;
    }

    function supersetWraps(session as Dictionary, entryId as String, nextId as String) as Boolean {
        return exerciseIndex(session, nextId) <= exerciseIndex(session, entryId);
    }

    // "A1" for the first member of group A, "A2" for the second...; null when ungrouped.
    function supersetLabel(session as Dictionary, index as Number) as String? {
        var exercises = session["exercises"] as Array;
        var current = exercises[index] as Dictionary;
        if (!inSuperset(current)) {
            return null;
        }
        var position = 1;
        for (var i = 0; i < index; i++) {
            if (sameGroup(current, exercises[i] as Dictionary)) {
                position++;
            }
        }
        return (current["superset"] as String) + position.toString();
    }

    // The exercise whose last logged set "Edit last set" should change: the session's latest set
    // when it belongs to this exercise's superset, else this exercise's own last set.
    function lastEditEntryId(session as Dictionary, entryId as String) as String? {
        var pointer = session["lastCompleted"];
        var own = exerciseIndex(session, entryId);
        if (own < 0) {
            return null;
        }
        var exercises = session["exercises"] as Array;
        if (pointer instanceof Dictionary && !Model.sameString(pointer["entryId"], entryId)) {
            var other = exerciseIndex(session, pointer["entryId"] as String);
            if (other >= 0 && sameGroup(exercises[own] as Dictionary, exercises[other] as Dictionary) &&
                hasLogged(exercises[other] as Dictionary)) {
                return pointer["entryId"] as String;
            }
        }
        return hasLogged(exercises[own] as Dictionary) ? entryId : null;
    }

    // Where the lifter goes after the rest that follows entryId: the next open set, or null.
    function nextUp(session as Dictionary, entryId as String) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var exercises = session["exercises"] as Array;
        var targetId = supersetNext(session, entryId);
        if (targetId == null && nextSlot(exercises[index] as Dictionary) >= 0) {
            targetId = entryId;
        }
        for (var offset = 1; targetId == null && offset < exercises.size(); offset++) {
            var item = exercises[(index + offset) % exercises.size()] as Dictionary;
            if (nextSlot(item) >= 0) {
                targetId = item["entryId"] as String;
            }
        }
        if (targetId == null) {
            return null;
        }
        var target = exercises[exerciseIndex(session, targetId as String)] as Dictionary;
        return {"entryId" => targetId, "slot" => nextSlot(target)};
    }

    // First open warmup slot number (WARMUP_BASE + i), or -1 when none or warmups were skipped.
    function nextWarmupSlot(exercise as Dictionary) as Number {
        var warmups = exercise["warmupSlots"];
        if (exercise["warmupSkipped"] == true || !(warmups instanceof Array)) {
            return -1;
        }
        for (var i = 0; i < (warmups as Array).size(); i++) {
            if ((warmups as Array)[i]["completed"] == null) {
                return Model.WARMUP_BASE + i;
            }
        }
        return -1;
    }

    // The slot the set screen works on: open warmups first, then the next working set.
    function activeSlot(exercise as Dictionary) as Number {
        var working = nextSlot(exercise);
        if (working < 0) {
            return -1;
        }
        var warmup = nextWarmupSlot(exercise);
        return warmup >= 0 ? warmup : working;
    }

    function warmupCount(exercise as Dictionary) as Number {
        var warmups = exercise["warmupSlots"];
        return warmups instanceof Array ? (warmups as Array).size() : 0;
    }

    function completedWarmups(exercise as Dictionary) as Number {
        var count = 0;
        var warmups = exercise["warmupSlots"];
        for (var i = 0; warmups instanceof Array && i < (warmups as Array).size(); i++) {
            if ((warmups as Array)[i]["completed"] != null) {
                count++;
            }
        }
        return count;
    }

    function hasLogged(exercise as Dictionary) as Boolean {
        return completedCount(exercise) > 0 || completedWarmups(exercise) > 0;
    }

    // Marks the remaining warmups of an exercise as skipped.
    function skipWarmups(session as Dictionary, entryId as String) as Dictionary? {
        var index = exerciseIndex(session, entryId);
        if (index < 0) {
            return null;
        }
        var state = exerciseCandidate(session, index);
        var changed = state["exercise"] as Dictionary;
        changed["warmupSkipped"] = true;
        return state["session"] as Dictionary;
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
            var warmups = source["warmupSlots"];
            if (warmups instanceof Array && (warmups as Array).size() > 0) {
                var archivedWarmups = [];
                for (var j = 0; j < (warmups as Array).size(); j++) {
                    archivedWarmups.add({"completed" => ((warmups as Array)[j] as Dictionary)["completed"]});
                }
                exercise["warmupSlots"] = archivedWarmups;
            }
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
    // "void" is 1 only for the lap that retracts an undone set (set by the controller).
    function lapPayload(exercise as Dictionary, slotIndex as Number) as Dictionary? {
        var lapSlot = Model.slotAt(exercise, slotIndex);
        var completed = lapSlot == null ? null : (lapSlot as Dictionary)["completed"];
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
        return {
            "name" => truncateBytes(exercise["name"] as String, 64),
            // Set 0 marks a warmup lap; working sets are numbered from 1.
            "set" => slotIndex >= Model.WARMUP_BASE ? 0 : slotIndex + 1,
            "void" => 0,
            "reps" => completed["reps"] instanceof Number ? completed["reps"] as Number : 0,
            "weightKg" => kg,
            "durationSec" => completed["durationSec"] instanceof Number ?
                completed["durationSec"] as Number : 0,
            // Only timed sets have an active time now; plain sets log in one press.
            "activeSec" => Model.sameString(type, "timed") &&
                completed["durationSec"] instanceof Number ? completed["durationSec"] as Number : 0
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
