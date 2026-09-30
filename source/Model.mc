import Toybox.Lang;
import Toybox.Math;

module Model {
    const MAX_EXERCISES = 32;
    const MAX_TEMPLATES = 8;
    const MAX_PROGRAM_DAYS = 48;
    // Warmup slots are addressed as WARMUP_BASE + index so one slot number identifies either kind.
    const WARMUP_BASE = 100;
    const MAX_WARMUP_SLOTS = 4;
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

    function validProgramId(value as Object?) as Boolean {
        return validNonblankText(value, 64);
    }

    function inRange(value as Object?, min as Number, max as Number, nullable as Boolean) as Boolean {
        if (value == null) {
            return nullable;
        }
        return value instanceof Number && value >= min && value <= max;
    }

    function validKg(value as Object?) as Boolean {
        return (value instanceof Number || value instanceof Float || value instanceof Double) &&
            (value as Numeric) >= 0 && (value as Numeric) <= MAX_LOAD100 / 100.0;
    }

    function load100(value as Object?) as Number? {
        if (!validKg(value)) {
            return null;
        }
        return Math.round((value as Numeric) * 100.0).toNumber();
    }

    function validLoadType(value as Object?) as Boolean {
        return sameString(value, "weight") || sameString(value, "assistance") ||
            sameString(value, "bodyweight") || sameString(value, "timed");
    }

    // The slot dictionary for a working (0..) or warmup (WARMUP_BASE..) slot number, else null.
    function slotAt(exercise as Dictionary, slot as Number) as Dictionary? {
        var warmup = slot >= WARMUP_BASE;
        var list = exercise[warmup ? "warmupSlots" : "slots"];
        var index = warmup ? slot - WARMUP_BASE : slot;
        if (slot < 0 || !(list instanceof Array) || index >= (list as Array).size()) {
            return null;
        }
        return (list as Array)[index] as Dictionary;
    }

    function validPlanTarget(target as Object?, type as Object?) as Boolean {
        if (!(target instanceof Dictionary)) {
            return false;
        }
        var set = target as Dictionary;
        if (sameString(type, "timed")) {
            return set["load100"] == null && set["reps"] == 1 &&
                inRange(set["durationSec"], 1, MAX_DURATION_SEC, false);
        }
        if (set["durationSec"] != null || !inRange(set["reps"], 1, MAX_REPS, false) ||
            (set["minReps"] != null && !(inRange(set["minReps"], 1, MAX_REPS, false) &&
                (set["minReps"] as Number) < (set["reps"] as Number)))) {
            return false;
        }
        return sameString(type, "bodyweight") ? set["load100"] == null :
            sameString(type, "weight") && inRange(set["load100"], 0, MAX_LOAD100, false);
    }

    function validWarmupTarget(target as Object?) as Boolean {
        if (!(target instanceof Dictionary)) {
            return false;
        }
        var set = target as Dictionary;
        var repsValid = inRange(set["reps"], 1, MAX_REPS, true);
        var durationValid = inRange(set["durationSec"], 1, MAX_DURATION_SEC, true);
        return repsValid && inRange(set["restSec"], 0, MAX_REST_SEC, true) &&
            inRange(set["load100"], 0, MAX_LOAD100, true) && durationValid &&
            (set["durationSec"] == null || set["reps"] == 1);
    }

    function weightLoad100(weight as Object?) as Number? {
        if (!(weight instanceof String) || (weight as String).length() < 3) {
            return null;
        }
        var value = weight as String;
        if (!sameString(value.substring(value.length() - 2, value.length()), "kg")) {
            return null;
        }
        var kilograms = value.substring(0, value.length() - 2).toDouble();
        return validKg(kilograms) ? load100(kilograms) : null;
    }

    function validLiftosaurSet(set as Object?) as Boolean {
        if (!(set instanceof Dictionary)) {
            return false;
        }
        var item = set as Dictionary;
        var reps = item["reps"] instanceof Number ? item["reps"] : item["minReps"];
        var timer = item["setTimer"];
        return validNonblankText(item["setId"], 64) &&
            (item["isWarmup"] == null || item["isWarmup"] instanceof Boolean) &&
            inRange(reps, 1, MAX_REPS, false) && weightLoad100(item["weight"]) != null &&
            inRange(item["timer"], 0, MAX_REST_SEC, true) &&
            inRange(timer, 1, MAX_DURATION_SEC, true) &&
            (timer == null || reps == 1) &&
            (item["isUnilateral"] == null || item["isUnilateral"] instanceof Boolean);
    }

    function validLiftosaurEntry(entry as Object?) as Boolean {
        if (!(entry instanceof Dictionary)) {
            return false;
        }
        var item = entry as Dictionary;
        var sets = item["sets"];
        var warmups = item["warmupSets"];
        if (!validNonblankText(item["entryId"], 64) ||
            (item["exerciseId"] != null && !validNonblankText(item["exerciseId"], 64)) ||
            !validNonblankText(item["name"], 64) ||
            !validText(item["equipment"], 48, true) ||
            !validText(item["superset"], 24, true) ||
            !(sets instanceof Array) || (sets as Array).size() < 1 ||
            (sets as Array).size() > MAX_SETS ||
            (warmups != null && (!(warmups instanceof Array) ||
                (warmups as Array).size() > MAX_SETS))) {
            return false;
        }
        var values = sets as Array;
        var timed = null;
        for (var i = 0; i < values.size(); i++) {
            if (!validLiftosaurSet(values[i])) {
                return false;
            }
            var isTimed = (values[i] as Dictionary)["setTimer"] instanceof Number;
            if (timed != null && timed != isTimed) {
                return false;
            }
            timed = isTimed;
        }
        if (warmups instanceof Array) {
            values = warmups as Array;
            for (var i = 0; i < values.size(); i++) {
                if (!validLiftosaurSet(values[i])) {
                    return false;
                }
            }
        }
        for (var i = 0; i < (sets as Array).size(); i++) {
            var workingSet = (sets as Array)[i] as Dictionary;
            if (workingSet["isUnilateral"] == true &&
                workingSet["setTimer"] instanceof Number) {
                return false;
            }
        }
        return true;
    }

    function validLiftosaurWorkout(reply as Object?) as Boolean {
        if (!(reply instanceof Dictionary)) {
            return false;
        }
        var envelope = reply as Dictionary;
        var data = envelope["data"] instanceof Dictionary ? envelope["data"] as Dictionary : envelope;
        var workout = data["workout"] instanceof Dictionary ? data["workout"] as Dictionary : data;
        var day = workout["dayData"];
        var entries = workout["entries"];
        if (!validProgramId(workout["programId"]) || !validNonblankText(workout["dayName"], 64) ||
            !(day instanceof Dictionary) || !inRange((day as Dictionary)["week"], 1, 1000, false) ||
            !inRange((day as Dictionary)["dayInWeek"], 1, 1000, false) ||
            !(entries instanceof Array) || (entries as Array).size() < 1 ||
            (entries as Array).size() > MAX_ENTRIES) {
            return false;
        }
        var totalSets = 0;
        var setIds = [];
        var values = entries as Array;
        for (var i = 0; i < values.size(); i++) {
            if (!validLiftosaurEntry(values[i])) {
                return false;
            }
            var entry = values[i] as Dictionary;
            totalSets += (entry["sets"] as Array).size();
            if (entry["warmupSets"] instanceof Array) {
                totalSets += (entry["warmupSets"] as Array).size();
            }
            var sourceArrays = [entry["sets"], entry["warmupSets"]];
            for (var a = 0; a < sourceArrays.size(); a++) {
                if (!(sourceArrays[a] instanceof Array)) {
                    continue;
                }
                var sourceSets = sourceArrays[a] as Array;
                for (var s = 0; s < sourceSets.size(); s++) {
                    var setId = (sourceSets[s] as Dictionary)["setId"];
                    for (var prior = 0; prior < setIds.size(); prior++) {
                        if (sameString(setIds[prior], setId)) {
                            return false;
                        }
                    }
                    setIds.add(setId);
                }
            }
        }
        return totalSets <= MAX_SETS_PER_WORKOUT;
    }

    function validTemplate(template as Object?) as Boolean {
        if (!(template instanceof Dictionary)) {
            return false;
        }
        var entries = template["entries"];
        if (!validId(template["id"]) || !validNonblankText(template["name"], 64) ||
            !inRange(template["revision"], 1, 2147483647, false) ||
            !validProgramId(template["programId"]) ||
            !inRange(template["week"], 1, 1000, false) ||
            !inRange(template["dayInWeek"], 1, 1000, false) ||
            !(entries instanceof Array) || entries.size() < 1 || entries.size() > MAX_ENTRIES) {
            return false;
        }
        var total = 0;
        var ids = [];
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i];
            if (!(entry instanceof Dictionary)) {
                return false;
            }
            var item = entry as Dictionary;
            var type = item["loadType"];
            var count = item["workingSetCount"];
            var targets = item["setTargets"];
            var warmups = item["warmups"];
            if (!validId(item["entryId"]) || !validId(item["exerciseId"]) ||
                !validNonblankText(item["liftosaurEntryId"], 64) ||
                !validNonblankText(item["name"], 64) ||
                !validText(item["equipment"], 48, true) ||
                !validText(item["superset"], 24, true) ||
                !(item["unilateral"] instanceof Boolean) ||
                !(sameString(type, "weight") || sameString(type, "bodyweight") ||
                    sameString(type, "timed")) ||
                !(sameString(type, "weight") ? sameString(item["unit"], "kg") &&
                    inRange(item["increment100"], 25, 10000, false) &&
                    (item["increment100"] as Number) % 25 == 0 :
                    item["unit"] == null && item["increment100"] == null) ||
                !inRange(item["restSec"], 0, MAX_REST_SEC, true) ||
                !inRange(count, 1, MAX_SETS, false) ||
                !(targets instanceof Array) || (targets as Array).size() != count ||
                (warmups != null && (!(warmups instanceof Array) ||
                    (warmups as Array).size() > MAX_SETS))) {
                return false;
            }
            for (var j = 0; j < ids.size(); j++) {
                if (sameString(ids[j], item["entryId"])) {
                    return false;
                }
            }
            ids.add(item["entryId"]);
            total += count as Number;
            var setTargets = targets as Array;
            for (var s = 0; s < setTargets.size(); s++) {
                if (!validPlanTarget(setTargets[s], type)) {
                    return false;
                }
            }
            if (warmups instanceof Array) {
                var warmupSets = warmups as Array;
                for (var w = 0; w < warmupSets.size(); w++) {
                    if (!validWarmupTarget(warmupSets[w])) {
                        return false;
                    }
                }
            }
            if (!validText(item["notes"], 160, true)) {
                return false;
            }
        }
        return total <= MAX_SETS_PER_WORKOUT;
    }

    function validEpochMillis(value as Object?) as Boolean {
        if (!(value instanceof Long)) {
            return false;
        }
        var millis = value as Long;
        return millis.compareTo("0".toLong()) >= 0 &&
            millis.compareTo("4102444800000".toLong()) <= 0;
    }

    function epochMillis(value as Object?) as Long? {
        if (value instanceof Long) {
            return validEpochMillis(value) ? value as Long : null;
        }
        if (!(value instanceof Number || value instanceof Double)) {
            return null;
        }
        var numeric = value as Numeric;
        if (numeric < 0 || numeric > 4102444800000.0) {
            return null;
        }
        var millis = numeric.toLong();
        return (millis as Numeric) == numeric ? millis : null;
    }

    function validAppendId(value as Object?) as Boolean {
        if (!(value instanceof String) || (value as String).length() != 6) {
            return false;
        }
        var text = value as String;
        for (var i = 0; i < text.length(); i++) {
            var code = text.toUtf8Array()[i];
            if (code < 97 || code > 122) {
                return false;
            }
        }
        return true;
    }

    function validMappedSet(set as Object?) as Boolean {
        if (!(set instanceof Dictionary)) {
            return false;
        }
        var item = set as Dictionary;
        var completed = item["completed"];
        var append = item["append"] == true;
        if (!validText(item["entryId"], 64, false) || !validText(item["setId"], 64, false) ||
            !(completed instanceof Dictionary) ||
            (item["append"] != null && !(item["append"] instanceof Boolean)) ||
            (append && !validAppendId(item["setId"]))) {
            return false;
        }
        var values = completed as Dictionary;
        return inRange(values["reps"], 1, MAX_REPS, false) &&
            weightLoad100(values["weight"]) != null &&
            inRange(values["setTimer"], 1, MAX_DURATION_SEC, true) &&
            inRange(values["setTimerLeft"], 1, MAX_DURATION_SEC, true) &&
            inRange(values["repsLeft"], 1, MAX_REPS, true) &&
            (values["setTimer"] == null || values["reps"] == 1) &&
            (values["setTimerLeft"] == null || values["setTimer"] != null);
    }

    function validJobWarmups(warmups as Object?, type as Object?, job as Dictionary) as Boolean {
        if (warmups == null) {
            return true;
        }
        if (!(warmups instanceof Array) || (warmups as Array).size() > MAX_WARMUP_SLOTS) {
            return false;
        }
        var rows = warmups as Array;
        for (var w = 0; w < rows.size(); w++) {
            if (!(rows[w] instanceof Dictionary)) {
                return false;
            }
            var row = rows[w] as Dictionary;
            if (!inRange(row["index"], 0, MAX_WARMUP_SLOTS - 1, false) ||
                !inRange(row["reps"], 1, MAX_REPS, false) || !validKg(row["kg"]) ||
                !inRange(row["timeSec"], 1, MAX_DURATION_SEC, true) ||
                (row["timeSec"] instanceof Number) != sameString(type, "timed") ||
                !inRange(row["completedAt"], job["start"] as Number, job["end"] as Number, false)) {
                return false;
            }
        }
        return true;
    }

    function validExtraWarmups(extras as Object?) as Boolean {
        if (extras == null) {
            return true;
        }
        if (!(extras instanceof Array) || (extras as Array).size() > MAX_ENTRIES) {
            return false;
        }
        for (var i = 0; i < (extras as Array).size(); i++) {
            if (!validNonblankText((extras as Array)[i], 72)) {
                return false;
            }
        }
        return true;
    }

    function validUpload(payload as Object?) as Boolean {
        if (!(payload instanceof Dictionary)) {
            return false;
        }
        var job = payload as Dictionary;
        var routine = job["routine"];
        var exercises = job["exercises"];
        var substitutions = job["substitutions"];
        var state = job["state"];
        if (!validId(job["sessionId"]) || !(routine instanceof Dictionary) ||
            !validProgramId((routine as Dictionary)["programId"]) ||
            !inRange((routine as Dictionary)["week"], 1, 1000, false) ||
            !inRange((routine as Dictionary)["dayInWeek"], 1, 1000, false) ||
            !validNonblankText((routine as Dictionary)["name"], 64) ||
            !inRange(job["start"], 0, 2147483647, false) ||
            !inRange(job["end"], job["start"] as Number, 2147483647, false) ||
            !validEpochMillis(job["startTime"]) || !validEpochMillis(job["endTime"]) ||
            (job["endTime"] as Long).compareTo(job["startTime"] as Long) < 0 ||
            !(sameString(state, Liftosaur.STATE_START) || sameString(state, Liftosaur.STATE_SETS) ||
                sameString(state, Liftosaur.STATE_FINISH) || sameString(state, Liftosaur.STATE_BLOCKED) ||
                sameString(state, Liftosaur.STATE_DONE)) ||
            !validText(job["lastError"], 48, true) ||
            !(exercises instanceof Array) || (exercises as Array).size() < 1 ||
            (exercises as Array).size() > MAX_ENTRIES ||
            (substitutions != null && (!(substitutions instanceof Array) ||
                (substitutions as Array).size() > MAX_ENTRIES))) {
            return false;
        }
        if ((job["startTime"] as Long).compareTo(
                ((job["start"] as Number).toLong() * 1000)) != 0 ||
            (job["endTime"] as Long).compareTo(
                ((job["end"] as Number).toLong() * 1000)) != 0) {
            return false;
        }
        var totalSets = 0;
        var appendIds = [];
        var items = exercises as Array;
        for (var i = 0; i < items.size(); i++) {
            if (!(items[i] instanceof Dictionary)) {
                return false;
            }
            var exercise = items[i] as Dictionary;
            var sets = exercise["sets"];
            var type = exercise["loadType"];
            if (!validId(exercise["entryId"]) ||
                !validText(exercise["liftosaurEntryId"], 64, true) ||
                !validNonblankText(exercise["name"], 64) ||
                !(sameString(type, "weight") || sameString(type, "assistance") ||
                    sameString(type, "bodyweight") ||
                    sameString(type, "timed")) ||
                !(exercise["unilateral"] instanceof Boolean) ||
                (sameString(type, "timed") && exercise["unilateral"] == true) ||
                !inRange(exercise["plannedSetCount"], 1, MAX_SETS, false) ||
                !(sets instanceof Array) || (sets as Array).size() < 1 ||
                (sets as Array).size() > MAX_SETS) {
                return false;
            }
            var previousSet = 0;
            var values = sets as Array;
            for (var s = 0; s < values.size(); s++) {
                if (!(values[s] instanceof Dictionary)) {
                    return false;
                }
                var set = values[s] as Dictionary;
                var timed = set["timeSec"] instanceof Number;
                var appendId = set["appendId"];
                if (!inRange(set["set"], 1, MAX_SETS, false) ||
                    (set["set"] as Number) <= previousSet ||
                    (timed != sameString(type, "timed")) ||
                    !inRange(set["reps"], 1, MAX_REPS, false) ||
                    !validKg(set["kg"]) ||
                    !inRange(set["timeSec"], 1, MAX_DURATION_SEC, true) ||
                    !inRange(set["activeSec"], 0, MAX_DURATION_SEC, true) ||
                    !inRange(set["completedAt"], job["start"] as Number,
                        job["end"] as Number, false) ||
                    (appendId != null && !validAppendId(appendId)) ||
                    ((set["set"] as Number) > (exercise["plannedSetCount"] as Number)) !=
                        (appendId != null) ||
                    (timed ? set["reps"] != 1 || (set["kg"] as Numeric) != 0 ||
                        (set["activeSec"] instanceof Number &&
                            (set["activeSec"] as Number) > (set["timeSec"] as Number)) :
                        (set["timeSec"] != null || sameString(type, "timed") ||
                            !sameString(type, "bodyweight") &&
                                !sameString(type, "weight") && !sameString(type, "assistance") ||
                            sameString(type, "bodyweight") && (set["kg"] as Numeric) != 0))) {
                    return false;
                }
                if (appendId != null) {
                    for (var a = 0; a < appendIds.size(); a++) {
                        if (sameString(appendIds[a], appendId)) {
                            return false;
                        }
                    }
                    appendIds.add(appendId);
                }
                previousSet = set["set"] as Number;
            }
            totalSets += values.size();
            if (!validJobWarmups(exercise["warmups"], type, job)) {
                return false;
            }
        }
        if (!validExtraWarmups(job["extraWarmups"])) {
            return false;
        }
        if (totalSets < 1 || totalSets > MAX_SETS_PER_WORKOUT) {
            return false;
        }
        if (substitutions instanceof Array) {
            var changes = substitutions as Array;
            for (var i = 0; i < changes.size(); i++) {
                if (!(changes[i] instanceof Dictionary) ||
                    !validNonblankText((changes[i] as Dictionary)["from"], 64) ||
                    !validNonblankText((changes[i] as Dictionary)["to"], 64)) {
                    return false;
                }
            }
        }
        var setsBody = job["setsBody"];
        if ((sameString(state, Liftosaur.STATE_SETS) || sameString(state, Liftosaur.STATE_FINISH)) &&
            !(setsBody instanceof Dictionary)) {
            return false;
        }
        if (sameString(state, Liftosaur.STATE_DONE) && setsBody != null) {
            return false;
        }
        if (setsBody instanceof Dictionary) {
            var mapped = (setsBody as Dictionary)["sets"];
            if (!(mapped instanceof Array) || (mapped as Array).size() > MAX_SETS_PER_WORKOUT) {
                return false;
            }
            var mappedSets = mapped as Array;
            for (var i = 0; i < mappedSets.size(); i++) {
                if (!validMappedSet(mappedSets[i])) {
                    return false;
                }
            }
        }
        return true;
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
            !inRange(record["templateRevision"], 1, 2147483647, false) ||
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
        var hasProgramId = record["programId"] != null;
        var hasWeek = record["week"] != null;
        var hasDay = record["dayInWeek"] != null;
        if ((hasProgramId || hasWeek || hasDay) &&
            !(validProgramId(record["programId"]) && inRange(record["week"], 1, 1000, false) &&
                inRange(record["dayInWeek"], 1, 1000, false))) {
            return false;
        }
        if (record["substitutions"] != null) {
            var substitutions = record["substitutions"];
            if (!(substitutions instanceof Array) || (substitutions as Array).size() > MAX_ENTRIES) {
                return false;
            }
            var changes = substitutions as Array;
            for (var s = 0; s < changes.size(); s++) {
                if (!(changes[s] instanceof Dictionary) ||
                    !validNonblankText((changes[s] as Dictionary)["from"], 64) ||
                    !validNonblankText((changes[s] as Dictionary)["to"], 64)) {
                    return false;
                }
            }
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
                (item["liftosaurEntryId"] != null &&
                    !validNonblankText(item["liftosaurEntryId"], 64)) ||
                !validNonblankText(item["name"], 64) || !validLoadType(type) ||
                !(sameString(type, "weight") || sameString(type, "assistance") ?
                    sameString(item["loadUnit"], "kg") : item["loadUnit"] == null) ||
                !validText(item["equipment"], 48, true) ||
                !validText(item["superset"], 24, true) ||
                (item["unilateral"] != null && !(item["unilateral"] instanceof Boolean)) ||
                !inRange(planned, 1, MAX_SETS, false) ||
                !(slots instanceof Array) || (slots as Array).size() != planned ||
                !(item["closedEarly"] instanceof Boolean) ||
                !inRange(item["restSec"], 0, MAX_REST_SEC, true) ||
                !inRange(item["weightIncrement100"], 25, 10000, true) ||
                !inRange(item["targetRepsMin"], 1, MAX_REPS, true) ||
                !inRange(item["targetRepsMax"], 1, MAX_REPS, true) ||
                !inRange(item["targetDurationSec"], 1, MAX_DURATION_SEC, true) ||
                !inRange(item["liftosaurPlannedSetCount"], 1, MAX_SETS, true) ||
                !validText(item["notes"], 160, true)) {
                return false;
            }
            if (item["warmups"] != null) {
                var warmups = item["warmups"];
                if (!(warmups instanceof Array) || (warmups as Array).size() > MAX_SETS) {
                    return false;
                }
                var warmupValues = warmups as Array;
                for (var w = 0; w < warmupValues.size(); w++) {
                    if (!validWarmupTarget(warmupValues[w])) {
                        return false;
                    }
                }
            }
            if (item["planTargets"] != null) {
                var planTargets = item["planTargets"];
                if (!(planTargets instanceof Array) || (planTargets as Array).size() > MAX_SETS) {
                    return false;
                }
                var targetValues = planTargets as Array;
                for (var t = 0; t < targetValues.size(); t++) {
                    if (!validPlanTarget(targetValues[t], type)) {
                        return false;
                    }
                }
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
            if (!validWarmupSlots(item, history)) {
                return false;
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
        // A "setRun" saved by 0.3.1 (set clock) is ignored and dropped on the next save.
        if (record["rest"] != null && !validRest(record["rest"], exercises)) {
            return false;
        }
        if (record["lastCompleted"] != null && !validSessionPointer(record["lastCompleted"], exercises)) {
            return false;
        }
        return true;
    }

    // Optional tracked warmups: at most MAX_WARMUP_SLOTS, validated like working slots.
    function validWarmupSlots(exercise as Dictionary, history as Boolean) as Boolean {
        var list = exercise["warmupSlots"];
        if (exercise["warmupSkipped"] != null && !(exercise["warmupSkipped"] instanceof Boolean)) {
            return false;
        }
        if (list == null) {
            return true;
        }
        if (!(list instanceof Array) || (list as Array).size() > MAX_WARMUP_SLOTS) {
            return false;
        }
        var slots = list as Array;
        for (var w = 0; w < slots.size(); w++) {
            if (!(slots[w] instanceof Dictionary)) {
                return false;
            }
            var slot = slots[w] as Dictionary;
            if ((!history && !(slot["draft"] instanceof Dictionary)) ||
                (slot["draft"] != null && !validSavedDraft(exercise["loadType"], slot["draft"])) ||
                !inRange(slot["restSec"], 0, MAX_REST_SEC, true) ||
                (slot["completed"] != null &&
                    !validCompletedSet(exercise["loadType"], slot["completed"], WARMUP_BASE + w))) {
                return false;
            }
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
                return inRange(item["slot"], 0, WARMUP_BASE + MAX_WARMUP_SLOTS - 1, false) &&
                    slotAt(exercise, item["slot"] as Number) != null;
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
            !inRange(item["slot"], 0, WARMUP_BASE + MAX_WARMUP_SLOTS - 1, false) ||
            !inRange(item["startedAt"], 0, 2147483647, false) ||
            !inRange(item["accumulatedSec"], 0, MAX_DURATION_SEC, false) ||
            !(item["targetAlertConsumed"] instanceof Boolean)) {
            return false;
        }
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (sameString(item["entryId"], exercise["entryId"])) {
                var slot = item["slot"] as Number;
                var target = slotAt(exercise, slot);
                return sameString(exercise["loadType"], "timed") && target != null &&
                    (target as Dictionary)["completed"] == null;
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
            !inRange(item["slot"], 0, WARMUP_BASE + MAX_WARMUP_SLOTS - 1, false) ||
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
                return slotAt(exercise, item["slot"] as Number) != null;
            }
        }
        return false;
    }
}
