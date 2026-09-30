import Toybox.Lang;

module Model {
    const MAX_EXERCISES = 32;
    const MAX_TEMPLATES = 8;
    const MAX_ENTRIES = 12;
    const MAX_SETS = 10;
    const MAX_SETS_PER_WORKOUT = 60;
    const MAX_REPS = 100;
    const MAX_DURATION_SEC = 3600;
    const MAX_REST_SEC = 1800;
    const MAX_LOAD100 = 99975;

    function byteLength(value as String) as Number {
        return value.toUtf8Array().size();
    }

    function sameString(left as Object?, right as Object?) as Boolean {
        return left instanceof String && right instanceof String &&
            (left as String).equals(right as String);
    }

    function validId(value as Object?) as Boolean {
        if (!(value instanceof String)) {
            return false;
        }
        var id = value as String;
        if (byteLength(id) < 1 || byteLength(id) > 40) {
            return false;
        }
        var bytes = id.toUtf8Array();
        for (var i = 0; i < bytes.size(); i++) {
            var char = bytes[i];
            if (!(char >= 97 && char <= 122) &&
                !(char >= 48 && char <= 57) && char != 45) {
                return false;
            }
        }
        return true;
    }

    function validText(value as Object?, maxBytes as Number, nullable as Boolean) as Boolean {
        if (value == null) {
            return nullable;
        }
        return value instanceof String && byteLength(value as String) <= maxBytes;
    }

    function validNonblankText(value as Object?, maxBytes as Number) as Boolean {
        if (!validText(value, maxBytes, false)) {
            return false;
        }
        var bytes = (value as String).toUtf8Array();
        for (var i = 0; i < bytes.size(); i++) {
            if (bytes[i] > 32 && bytes[i] != 127) {
                return true;
            }
        }
        return false;
    }

    function inRange(value as Object?, min as Number, max as Number, nullable as Boolean) as Boolean {
        if (value == null) {
            return nullable;
        }
        return value instanceof Number && value >= min && value <= max;
    }

    function validLoadType(value as Object?) as Boolean {
        return sameString(value, "weight") || sameString(value, "assistance") ||
            sameString(value, "bodyweight") || sameString(value, "timed");
    }

    function validExercise(exercise as Object?) as Boolean {
        if (!(exercise instanceof Dictionary)) {
            return false;
        }
        var type = exercise["loadType"];
        if (!validId(exercise["id"]) || !validText(exercise["name"], 64, false) ||
            !validLoadType(type) ||
            !inRange(exercise["defaultRestSec"], 0, MAX_REST_SEC, true) ||
            !validText(exercise["notes"], 160, true)) {
            return false;
        }
        if (sameString(type, "weight") || sameString(type, "assistance")) {
            return sameString(exercise["unit"], "kg") &&
                inRange(exercise["increment100"], 25, 10000, false) &&
                (exercise["increment100"] % 25) == 0;
        }
        return exercise["unit"] == null && exercise["increment100"] == null;
    }

    function validTemplate(template as Object?) as Boolean {
        if (!(template instanceof Dictionary)) {
            return false;
        }
        var entries = template["entries"];
        if (!validId(template["id"]) || !validText(template["name"], 64, false) ||
            !inRange(template["revision"], 1, 1000000, false) ||
            !(entries instanceof Array) || entries.size() > MAX_ENTRIES) {
            return false;
        }
        var total = 0;
        var ids = [];
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (!(entry instanceof Dictionary) ||
                !validId(entry["entryId"]) || !validId(entry["exerciseId"]) ||
                !inRange(entry["workingSetCount"], 1, MAX_SETS, false) ||
                !inRange(entry["increment100"], 25, 10000, true) ||
                (entry["increment100"] instanceof Number &&
                 (entry["increment100"] % 25) != 0)) {
                return false;
            }
            for (var j = 0; j < ids.size(); j++) {
                if (sameString(ids[j], entry["entryId"])) {
                    return false;
                }
            }
            ids.add(entry["entryId"]);
            total += entry["workingSetCount"];
            if (entry["targetRepsMin"] != null || entry["targetRepsMax"] != null) {
                if (!inRange(entry["targetRepsMin"], 1, MAX_REPS, false) ||
                    !inRange(entry["targetRepsMax"], entry["targetRepsMin"], MAX_REPS, false)) {
                    return false;
                }
            }
            if (!inRange(entry["targetDurationSec"], 1, MAX_DURATION_SEC, true) ||
                !inRange(entry["restSec"], 0, MAX_REST_SEC, true) ||
                !inRange(entry["startingLoad100"], 0, MAX_LOAD100, true) ||
                !validText(entry["notes"], 160, true)) {
                return false;
            }
        }
        return total <= MAX_SETS_PER_WORKOUT;
    }

    function validStoredSession(session as Object?, history as Boolean) as Boolean {
        if (!(session instanceof Dictionary)) {
            return false;
        }
        var record = session as Dictionary;
        var status = record["status"];
        if (!history && (sameString(status, "completed") || sameString(status, "aborted")) &&
            !(record["exercises"] instanceof Array)) {
            return validId(record["id"]) && inRange(record["sessionSeq"], 1, 2147483647, false) &&
                inRange(record["endedAt"], 0, 2147483647, false);
        }
        if (!(sameString(status, "active") ||
              sameString(status, "finalizing") ||
              (history && (sameString(status, "completed") || sameString(status, "aborted")))) ||
            !validId(record["id"]) || !inRange(record["sessionSeq"], 1, 2147483647, false) ||
            !validId(record["templateId"]) ||
            !inRange(record["templateRevision"], 1, 1000000, false) ||
            !validNonblankText(record["templateName"], 64) ||
            !inRange(record["startedAt"], 0, 2147483647, false) ||
            !(record["exercises"] instanceof Array)) {
            return false;
        }
        if (record["endedAt"] != null && !inRange(record["endedAt"], 0, 2147483647, false)) {
            return false;
        }
        if (record["completionKind"] != null &&
            !sameString(record["completionKind"], "full") &&
            !sameString(record["completionKind"], "partial")) {
            return false;
        }
        if (record["fitSegments"] != null && !inRange(record["fitSegments"], 0, 1000, false)) {
            return false;
        }
        if (record["fitUnknownSegments"] != null &&
            !inRange(record["fitUnknownSegments"], 0, 1000, false)) {
            return false;
        }
        var fitState = record["fitState"];
        if (fitState != null && !(sameString(fitState, "recording") ||
            sameString(fitState, "paused") || sameString(fitState, "segment_saved") ||
            sameString(fitState, "interrupted") || sameString(fitState, "failed") ||
            sameString(fitState, "saving") || sameString(fitState, "saved") ||
            sameString(fitState, "unknown") || sameString(fitState, "discarded") ||
            sameString(fitState, "discard_failed") ||
            sameString(fitState, "discarding"))) {
            return false;
        }
        if (sameString(status, "finalizing")) {
            if (!(sameString(record["finishOutcome"], "completed") ||
                  sameString(record["finishOutcome"], "aborted")) ||
                !inRange(record["endedAt"], 0, 2147483647, false)) {
                return false;
            }
        } else if (history &&
            (!inRange(record["endedAt"], 0, 2147483647, false) ||
             !inRange(record["elapsedSec"], 0, 2147483647, false) ||
             !inRange(record["activeSec"], 0, 2147483647, false))) {
            return false;
        }
        if (record["pausedSec"] != null && !inRange(record["pausedSec"], 0, 2147483647, false)) {
            return false;
        }
        if (record["recoveryGapSec"] != null &&
            !inRange(record["recoveryGapSec"], 0, 2147483647, false)) {
            return false;
        }
        if (record["lastCheckpointAt"] != null &&
            !inRange(record["lastCheckpointAt"], 0, 2147483647, false)) {
            return false;
        }

        var exercises = record["exercises"] as Array;
        if (exercises.size() < 1 || exercises.size() > MAX_ENTRIES) {
            return false;
        }
        var totalSlots = 0;
        var entryIds = [];
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i];
            if (!(exercise instanceof Dictionary)) {
                return false;
            }
            var item = exercise as Dictionary;
            var type = item["loadType"];
            var planned = item["plannedSetCount"];
            var slots = item["slots"];
            if (!validId(item["entryId"]) || !validId(item["exerciseId"]) ||
                !validNonblankText(item["name"], 64) || !validLoadType(type) ||
                !validText(item["garminCategory"], 64, true) || !validText(item["garminCode"], 64, true) ||
                !(sameString(type, "weight") || sameString(type, "assistance") ?
                    sameString(item["loadUnit"], "kg") : item["loadUnit"] == null) ||
                !inRange(planned, 1, MAX_SETS, false) ||
                !(slots instanceof Array) || (slots as Array).size() != planned ||
                !(item["closedEarly"] instanceof Boolean) ||
                !inRange(item["restSec"], 0, MAX_REST_SEC, true) ||
                !inRange(item["weightIncrement100"], 25, 10000, true) ||
                !inRange(item["targetRepsMin"], 1, MAX_REPS, true) ||
                !inRange(item["targetRepsMax"], 1, MAX_REPS, true) ||
                !inRange(item["targetDurationSec"], 1, MAX_DURATION_SEC, true) ||
                !validText(item["notes"], 160, true)) {
                return false;
            }
            for (var j = 0; j < entryIds.size(); j++) {
                if (sameString(entryIds[j], item["entryId"])) {
                    return false;
                }
            }
            entryIds.add(item["entryId"]);
            var setSlots = slots as Array;
            totalSlots += setSlots.size();
            for (var s = 0; s < setSlots.size(); s++) {
                var slot = setSlots[s];
                if (!(slot instanceof Dictionary)) {
                    return false;
                }
                var savedSlot = slot as Dictionary;
                if (!history && !(savedSlot["draft"] instanceof Dictionary)) {
                    return false;
                }
                if (savedSlot["draft"] != null && !validSavedDraft(type, savedSlot["draft"])) {
                    return false;
                }
                var completed = savedSlot["completed"];
                if (completed != null && !validCompletedSet(type, completed, s)) {
                    return false;
                }
            }
        }
        if (totalSlots > MAX_SETS_PER_WORKOUT) {
            return false;
        }
        if (record["nextSetSequence"] != null &&
            !inRange(record["nextSetSequence"], 1, 2147483647, false)) {
            return false;
        }
        if (record["restGeneration"] != null &&
            !inRange(record["restGeneration"], 0, 2147483647, false)) {
            return false;
        }
        if (record["timedRun"] != null && !validTimedRun(record["timedRun"], exercises)) {
            return false;
        }
        if (record["setRun"] != null && !validSetRun(record["setRun"], exercises)) {
            return false;
        }
        if (record["rest"] != null && !validRest(record["rest"], exercises)) {
            return false;
        }
        if (record["lastCompleted"] != null && !validSessionPointer(record["lastCompleted"], exercises)) {
            return false;
        }
        return true;
    }

    function validSavedDraft(type as Object?, draft as Object?) as Boolean {
        if (!(draft instanceof Dictionary)) {
            return false;
        }
        var values = draft as Dictionary;
        if (!inRange(values["load100"], 0, MAX_LOAD100, true) ||
            !inRange(values["reps"], 1, MAX_REPS, true) ||
            !inRange(values["durationSec"], 1, MAX_DURATION_SEC, true) ||
            !inRange(values["measuredSec"], 0, MAX_DURATION_SEC, true) ||
            (values["durationEdited"] != null && !(values["durationEdited"] instanceof Boolean)) ||
            (values["targetAlertConsumed"] != null &&
             !(values["targetAlertConsumed"] instanceof Boolean))) {
            return false;
        }
        if (sameString(type, "weight") || sameString(type, "assistance")) {
            return values["durationSec"] == null;
        }
        if (sameString(type, "bodyweight")) {
            return values["load100"] == null && values["durationSec"] == null;
        }
        return values["load100"] == null && values["reps"] == null;
    }

    function validCompletedSet(type as Object?, completed as Object?, slot as Number) as Boolean {
        if (!(completed instanceof Dictionary)) {
            return false;
        }
        var set = completed as Dictionary;
        if (set["slot"] != slot || !inRange(set["sequence"], 1, 2147483647, false) ||
            !inRange(set["completedAt"], 0, 2147483647, false) ||
            (set["updatedAt"] != null && !inRange(set["updatedAt"], 0, 2147483647, false)) ||
            (set["activeSec"] != null && !inRange(set["activeSec"], 0, MAX_DURATION_SEC, false))) {
            return false;
        }
        if (sameString(type, "weight") || sameString(type, "assistance")) {
            return inRange(set["load100"], 0, MAX_LOAD100, false) &&
                inRange(set["reps"], 1, MAX_REPS, false) && set["durationSec"] == null;
        }
        if (sameString(type, "bodyweight")) {
            return set["load100"] == null && inRange(set["reps"], 1, MAX_REPS, false) &&
                set["durationSec"] == null;
        }
        return set["load100"] == null && set["reps"] == null &&
            inRange(set["durationSec"], 1, MAX_DURATION_SEC, false) &&
            (sameString(set["durationSource"], "manual") ||
             sameString(set["durationSource"], "measured"));
    }

    function validSessionPointer(pointer as Object?, exercises as Array) as Boolean {
        if (!(pointer instanceof Dictionary)) {
            return false;
        }
        var item = pointer as Dictionary;
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (sameString(item["entryId"], exercise["entryId"])) {
                return inRange(item["slot"], 0, (exercise["slots"] as Array).size() - 1, false);
            }
        }
        return false;
    }

    function validTimedRun(run as Object?, exercises as Array) as Boolean {
        if (!(run instanceof Dictionary)) {
            return false;
        }
        var item = run as Dictionary;
        if (!validId(item["entryId"]) ||
            !inRange(item["slot"], 0, MAX_SETS - 1, false) ||
            !inRange(item["startedAt"], 0, 2147483647, false) ||
            !inRange(item["accumulatedSec"], 0, MAX_DURATION_SEC, false) ||
            !(item["targetAlertConsumed"] instanceof Boolean)) {
            return false;
        }
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (sameString(item["entryId"], exercise["entryId"])) {
                var slot = item["slot"] as Number;
                return sameString(exercise["loadType"], "timed") &&
                    slot < (exercise["slots"] as Array).size() &&
                    (exercise["slots"] as Array)[slot]["completed"] == null;
            }
        }
        return false;
    }

    function validSetRun(run as Object?, exercises as Array) as Boolean {
        if (!(run instanceof Dictionary)) {
            return false;
        }
        var item = run as Dictionary;
        if (!validId(item["entryId"]) || !inRange(item["slot"], 0, MAX_SETS - 1, false) ||
            !inRange(item["startedAt"], 0, 2147483647, false)) {
            return false;
        }
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (sameString(item["entryId"], exercise["entryId"])) {
                var slot = item["slot"] as Number;
                return !sameString(exercise["loadType"], "timed") &&
                    slot < (exercise["slots"] as Array).size() &&
                    (exercise["slots"] as Array)[slot]["completed"] == null;
            }
        }
        return false;
    }

    function validRest(rest as Object?, exercises as Array) as Boolean {
        if (!(rest instanceof Dictionary)) {
            return false;
        }
        var item = rest as Dictionary;
        if (!inRange(item["id"], 0, 2147483647, false) || !validId(item["entryId"]) ||
            !inRange(item["slot"], 0, MAX_SETS - 1, false) ||
            !inRange(item["startedAt"], 0, 2147483647, false) ||
            !inRange(item["durationSec"], 0, MAX_REST_SEC, false) ||
            !inRange(item["endsAt"], 0, 2147483647, false) ||
            !(sameString(item["state"], "running") || sameString(item["state"], "paused") ||
              sameString(item["state"], "expired") || sameString(item["state"], "dismissed")) ||
            !(item["alertConsumed"] instanceof Boolean)) {
            return false;
        }
        if (item["remainingWhenPausedSec"] != null &&
            !inRange(item["remainingWhenPausedSec"], 0, MAX_REST_SEC, false)) {
            return false;
        }
        if (item["pausedAt"] != null && !inRange(item["pausedAt"], 0, 2147483647, false)) {
            return false;
        }
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (sameString(item["entryId"], exercise["entryId"])) {
                return (item["slot"] as Number) < (exercise["slots"] as Array).size();
            }
        }
        return false;
    }
}
