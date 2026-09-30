import Toybox.Lang;

module LastPerformance {
    // ponytail: cap prefill to 32 exercises; retain a larger index when cache history needs it.
    const MAX_CACHE_ENTRIES = 32;
    const MAX_READ_ENTRIES = 128;

    // Cached tuples are [slot, load100, reps, durationSec], ordered by slot.
    function sameNullableString(left as Object?, right as Object?) as Boolean {
        return left == null ? right == null : Model.sameString(left, right);
    }

    function validTuple(exercise as Dictionary, tuple as Object?) as Boolean {
        if (!(tuple instanceof Array) || (tuple as Array).size() != 4) {
            return false;
        }
        var values = tuple as Array;
        if (!Model.inRange(values[0], 0, Model.MAX_SETS - 1, false)) {
            return false;
        }
        var type = exercise["loadType"];
        if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
            return Model.inRange(values[1], 0, Model.MAX_LOAD100, false) &&
                Model.inRange(values[2], 1, Model.MAX_REPS, false) && values[3] == null;
        }
        if (Model.sameString(type, "bodyweight")) {
            return values[1] == null && Model.inRange(values[2], 1, Model.MAX_REPS, false) &&
                values[3] == null;
        }
        return Model.sameString(type, "timed") && values[1] == null && values[2] == null &&
            Model.inRange(values[3], 1, Model.MAX_DURATION_SEC, false);
    }

    function validCacheEntry(id as Object?, entry as Object?) as Boolean {
        if (!Model.validId(id) || !(entry instanceof Dictionary)) {
            return false;
        }
        var item = entry as Dictionary;
        var type = item["loadType"];
        var unit = item["unit"];
        var sets = item["sets"];
        if (!Model.sameString(item["exerciseId"], id) || !Model.validLoadType(type) ||
            !Model.validId(item["sourceSessionId"]) ||
            !Model.inRange(item["sourceSessionSeq"], 1, 2147483647, false) ||
            !Model.inRange(item["sourceEndedAt"], 0, 2147483647, false) ||
            (item["completionKind"] != null &&
             !Model.sameString(item["completionKind"], "full") &&
             !Model.sameString(item["completionKind"], "partial")) ||
            !(sets instanceof Array) || (sets as Array).size() == 0 ||
            (sets as Array).size() > Model.MAX_SETS) {
            return false;
        }
        if ((Model.sameString(type, "weight") || Model.sameString(type, "assistance")) ?
            !Model.sameString(unit, "kg") : unit != null) {
            return false;
        }
        var exercise = {"exerciseId" => id, "loadType" => type};
        var values = sets as Array;
        for (var j = 0; j < values.size(); j++) {
            if (!validTuple(exercise, values[j]) ||
                (j > 0 && (values[j - 1] as Array)[0] >= (values[j] as Array)[0])) {
                return false;
            }
        }
        return true;
    }

    function sanitizeCache(cache as Dictionary) as Dictionary {
        var clean = {};
        var ids = cache.keys();
        if (ids.size() > MAX_READ_ENTRIES) {
            return clean;
        }
        for (var i = 0; i < ids.size(); i++) {
            var id = ids[i];
            if (validCacheEntry(id, cache[id])) {
                clean[id] = cache[id];
            }
        }
        return clean;
    }

    function validCache(cache as Object?) as Boolean {
        if (!(cache instanceof Dictionary)) {
            return false;
        }
        var saved = cache as Dictionary;
        return saved.keys().size() <= MAX_READ_ENTRIES &&
            sanitizeCache(saved).keys().size() == saved.keys().size();
    }

    function performedSets(exercise as Dictionary) as Array {
        var result = [];
        var slots = exercise["slots"] as Array;
        var type = exercise["loadType"];
        for (var i = 0; i < slots.size(); i++) {
            var completed = slots[i]["completed"];
            if (!(completed instanceof Dictionary)) {
                continue;
            }
            var tuple = [i, null, null, null];
            if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
                tuple[1] = completed["load100"];
                tuple[2] = completed["reps"];
            } else if (Model.sameString(type, "bodyweight")) {
                tuple[2] = completed["reps"];
            } else if (Model.sameString(type, "timed")) {
                tuple[3] = completed["durationSec"];
            }
            if (validTuple(exercise, tuple)) {
                result.add(tuple);
            }
        }
        return result;
    }

    function merge(cache as Dictionary?, endedSession as Dictionary) as Dictionary {
        var result = {};
        if (cache != null) {
            var keys = (cache as Dictionary).keys();
            for (var i = 0; i < keys.size(); i++) {
                result[keys[i]] = (cache as Dictionary)[keys[i]];
            }
        }
        if (!Model.sameString(endedSession["status"], "completed") ||
            !(endedSession["sessionSeq"] instanceof Number) ||
            !(endedSession["id"] instanceof String) || !(endedSession["endedAt"] instanceof Number)) {
            return result;
        }

        var sequence = endedSession["sessionSeq"] as Number;
        var exercises = endedSession["exercises"] as Array;
        for (var e = 0; e < exercises.size(); e++) {
            var exercise = exercises[e] as Dictionary;
            var id = exercise["exerciseId"];
            var type = exercise["loadType"];
            var unit = exercise["loadUnit"];
            if (!Model.validId(id) || !Model.validLoadType(type)) {
                continue;
            }
            var sets = performedSets(exercise);
            if (sets.size() == 0) {
                continue;
            }

            var old = result[id as String];
            if (old instanceof Dictionary && old["sourceSessionSeq"] instanceof Number) {
                var oldSequence = old["sourceSessionSeq"] as Number;
                if (oldSequence > sequence ||
                    (oldSequence == sequence && !Model.sameString(old["sourceSessionId"], endedSession["id"]))) {
                    continue;
                }
            }
            var entry = {};
            entry["exerciseId"] = id;
            entry["loadType"] = type;
            entry["unit"] = unit;
            entry["sourceSessionId"] = endedSession["id"];
            entry["sourceSessionSeq"] = sequence;
            entry["sourceEndedAt"] = endedSession["endedAt"];
            entry["completionKind"] = endedSession["completionKind"];
            entry["sets"] = sets;
            result[id as String] = entry;
        }
        var keys = result.keys();
        if (keys.size() <= MAX_CACHE_ENTRIES) {
            return result;
        }
        var chosen = [];
        for (var i = 0; i < keys.size(); i++) {
            chosen.add(false);
        }
        var bounded = {};
        for (var pick = 0; pick < MAX_CACHE_ENTRIES; pick++) {
            var newest = -1;
            var newestIndex = -1;
            for (var i = 0; i < keys.size(); i++) {
                if (chosen[i]) {
                    continue;
                }
                var cachedSequence = result[keys[i]]["sourceSessionSeq"] as Number;
                if (cachedSequence > newest) {
                    newest = cachedSequence;
                    newestIndex = i;
                }
            }
            if (newestIndex < 0) {
                break;
            }
            chosen[newestIndex] = true;
            bounded[keys[newestIndex]] = result[keys[newestIndex]];
        }
        return bounded;
    }

    function matchingSets(exercise as Dictionary, cached as Dictionary?) as Array? {
        if (cached == null || !Model.sameString(cached["exerciseId"], exercise["exerciseId"]) ||
            !Model.sameString(cached["loadType"], exercise["loadType"]) ||
            !sameNullableString(cached["unit"], exercise["loadUnit"]) ||
            !(cached["sets"] instanceof Array)) {
            return null;
        }
        var sets = cached["sets"] as Array;
        if (sets.size() == 0 || sets.size() > Model.MAX_SETS) {
            return null;
        }
        for (var i = 0; i < sets.size(); i++) {
            if (!validTuple(exercise, sets[i])) {
                return null;
            }
            if (i > 0 && (sets[i - 1] as Array)[0] >= (sets[i] as Array)[0]) {
                return null;
            }
        }
        return sets;
    }

    function cloneEntry(cached as Dictionary, sets as Array) as Dictionary {
        var copy = SessionLogic.copyDictionary(cached);
        var copiedSets = [];
        for (var i = 0; i < sets.size(); i++) {
            var tuple = sets[i] as Array;
            copiedSets.add([tuple[0], tuple[1], tuple[2], tuple[3]]);
        }
        copy["sets"] = copiedSets;
        return copy;
    }

    // Returns a new exercise snapshot; it never changes the current session or cache.
    function prefill(exerciseSnapshot as Dictionary, cachedEntry as Dictionary?) as Dictionary {
        var exercise = SessionLogic.copyDictionary(exerciseSnapshot);
        var prior = matchingSets(exerciseSnapshot, cachedEntry);
        var slots = exerciseSnapshot["slots"] as Array;
        var filledSlots = [];
        var lastSet = prior == null ? null : (prior as Array)[(prior as Array).size() - 1];

        for (var i = 0; i < slots.size(); i++) {
            var original = slots[i] as Dictionary;
            var slot = SessionLogic.copyDictionary(original);
            var draft = SessionLogic.copyDictionary(original["draft"] as Dictionary);
            var source = null;
            if (prior != null) {
                var sets = prior as Array;
                for (var j = 0; j < sets.size(); j++) {
                    var tuple = sets[j] as Array;
                    if (tuple[0] == i) {
                        source = tuple;
                        break;
                    }
                }
                if (source == null) {
                    source = lastSet;
                }
            }

            var type = exerciseSnapshot["loadType"];
            if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
                var defaultLoad = draft["load100"];
                draft["load100"] = source != null ? (source as Array)[1] :
                    (Model.inRange(defaultLoad, 0, Model.MAX_LOAD100, false) ? defaultLoad : 0);
                var defaultReps = exerciseSnapshot["targetRepsMin"];
                draft["reps"] = source != null ? (source as Array)[2] :
                    (Model.inRange(defaultReps, 1, Model.MAX_REPS, false) ? defaultReps : 1);
                draft["durationSec"] = null;
            } else if (Model.sameString(type, "bodyweight")) {
                var defaultReps = exerciseSnapshot["targetRepsMin"];
                draft["load100"] = null;
                draft["reps"] = source != null ? (source as Array)[2] :
                    (Model.inRange(defaultReps, 1, Model.MAX_REPS, false) ? defaultReps : 1);
                draft["durationSec"] = null;
            } else {
                var target = exerciseSnapshot["targetDurationSec"];
                draft["load100"] = null;
                draft["reps"] = null;
                draft["durationSec"] = source != null ? (source as Array)[3] :
                    (Model.inRange(target, 1, Model.MAX_DURATION_SEC, false) ? target : null);
            }
            slot["draft"] = draft;
            slot["completed"] = null;
            filledSlots.add(slot);
        }
        exercise["slots"] = filledSlots;
        exercise["last"] = prior != null ? cloneEntry(cachedEntry as Dictionary, prior as Array) : null;
        return exercise;
    }

    function applyPlanTargets(prefilled as Dictionary, targets as Array) as Dictionary {
        var exercise = SessionLogic.copyDictionary(prefilled);
        var sourceSlots = prefilled["slots"] as Array;
        var slots = [];
        for (var i = 0; i < sourceSlots.size(); i++) {
            var slot = SessionLogic.copyDictionary(sourceSlots[i] as Dictionary);
            var draft = SessionLogic.copyDictionary(slot["draft"] as Dictionary);
            var target = targets[i < targets.size() ? i : targets.size() - 1] as Dictionary;
            draft["load100"] = target["load100"];
            draft["reps"] = Model.sameString(exercise["loadType"], "timed") ?
                null : target["reps"];
            draft["durationSec"] = target["durationSec"];
            draft["durationEdited"] = false;
            draft["targetAlertConsumed"] = false;
            slot["draft"] = draft;
            slots.add(slot);
        }
        exercise["slots"] = slots;
        return exercise;
    }
}
