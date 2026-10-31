import Toybox.Lang;
import Toybox.Math;

module UploadLogic {
    const ALPHABET = "abcdefghijklmnopqrstuvwxyz";

    function enqueue(ids as Array, job as Dictionary) as Array? {
        if (!Model.validUpload(job) || ids.size() >= QueueLimits.MAX_PENDING_UPLOADS) {
            return null;
        }
        var id = job["sessionId"];
        var result = [];
        for (var i = 0; i < ids.size(); i++) {
            if (!Model.sameString(ids[i], id)) {
                result.add(ids[i]);
            } else {
                return null;
            }
        }
        result.add(id);
        return result;
    }

    function appendIdFor(seed as String, used as Array) as String {
        var hash = 0;
        var bytes = seed.toUtf8Array();
        for (var i = 0; i < bytes.size(); i++) {
            hash = (hash * 17 + bytes[i]) % 100000000;
        }
        var result = "";
        var collision = true;
        while (collision) {
            var value = hash;
            result = "";
            for (var i = 0; i < 6; i++) {
                var position = value % 26;
                result = ALPHABET.substring(position, position + 1) + result;
                value = value / 26;
            }
            collision = false;
            for (var i = 0; i < used.size(); i++) {
                if (Model.sameString(used[i], result)) {
                    collision = true;
                    hash = (hash + 1) % 100000000;
                    break;
                }
            }
        }
        used.add(result);
        return result;
    }

    function makeJob(session as Dictionary) as Dictionary? {
        var programId = session["programId"];
        var week = session["week"];
        var dayInWeek = session["dayInWeek"];
        var exercises = session["exercises"];
        if (!Model.sameString(session["status"], "completed") ||
            !Model.validId(session["id"]) || !Model.validProgramId(programId) ||
            !Model.inRange(week, 1, 1000, false) ||
            !Model.inRange(dayInWeek, 1, 1000, false) ||
            !Model.inRange(session["startedAt"], 0, 2147483647, false) ||
            !Model.inRange(session["endedAt"], session["startedAt"] as Number, 2147483647, false) ||
            !Model.validNonblankText(session["templateName"], 64) ||
            !(exercises instanceof Array)) {
            return null;
        }
        var start = session["startedAt"] as Number;
        var end = session["endedAt"] as Number;
        var startTime = start.toLong() * 1000;
        var endTime = end.toLong() * 1000;
        var mappedExercises = [];
        var appendIds = [];
        var total = 0;
        var sourceExercises = exercises as Array;
        for (var e = 0; e < sourceExercises.size(); e++) {
            var exercise = sourceExercises[e] as Dictionary;
            var sourceSlots = exercise["slots"];
            var liftEntryId = exercise["liftosaurEntryId"];
            var planned = exercise["liftosaurPlannedSetCount"];
            if (!(sourceSlots instanceof Array) || !Model.validNonblankText(liftEntryId, 64) ||
                !Model.inRange(planned, 1, Model.MAX_SETS, false)) {
                continue;
            }
            var type = exercise["loadType"] as String;
            if (!(Model.sameString(type, "weight") || Model.sameString(type, "assistance") ||
                Model.sameString(type, "bodyweight") || Model.sameString(type, "timed"))) {
                continue;
            }
            var sets = [];
            var slots = sourceSlots as Array;
            for (var i = 0; i < slots.size(); i++) {
                var completed = (slots[i] as Dictionary)["completed"];
                if (!(completed instanceof Dictionary)) {
                    continue;
                }
                var performed = completed as Dictionary;
                var timed = Model.sameString(type, "timed");
                var reps = timed ? 1 : performed["reps"];
                var load100 = performed["load100"];
                if (!Model.inRange(reps, 1, Model.MAX_REPS, false) ||
                    (timed && !Model.inRange(performed["durationSec"], 1,
                        Model.MAX_DURATION_SEC, false)) ||
                    (!timed && !Model.sameString(type, "bodyweight") &&
                        !Model.inRange(load100, 0, Model.MAX_LOAD100, false)) ||
                    !Model.inRange(performed["completedAt"], start, end, false)) {
                    continue;
                }
                var kg = timed || Model.sameString(type, "bodyweight") ? 0.0 :
                    (load100 as Number) / 100.0;
                var appendId = null;
                if (i + 1 > (planned as Number)) {
                    appendId = appendIdFor((session["id"] as String) + "-" +
                        (exercise["entryId"] as String) + "-" + (i + 1).toString(), appendIds);
                }
                var activeSec = timed ? performed["durationSec"] : performed["activeSec"];
                sets.add({
                    "set" => i + 1,
                    "reps" => reps,
                    "kg" => kg,
                    "rpe10" => performed["rpe10"],
                    "timeLeftSec" => timed ? performed["durationLeftSec"] : null,
                    "timeSec" => timed ? performed["durationSec"] : null,
                    "activeSec" => activeSec,
                    "completedAt" => performed["completedAt"],
                    "appendId" => appendId
                });
            }
            if (sets.size() > 0) {
                var jobExercise = {
                    "entryId" => exercise["entryId"],
                    "liftosaurEntryId" => liftEntryId,
                    "name" => exercise["name"],
                    "loadType" => type,
                    "unilateral" => exercise["unilateral"] == true,
                    "unit" => Model.sameString(exercise["loadUnit"], "lb") ? "lb" : "kg",
                    "userVars" => exercise["userVars"],
                    "plannedSetCount" => planned,
                    "sets" => sets
                };
                var warmupRows = completedWarmupRows(exercise, type, start, end);
                if (warmupRows.size() > 0) {
                    jobExercise["warmups"] = warmupRows;
                }
                mappedExercises.add(jobExercise);
                total += sets.size();
            }
        }
        if (total == 0) {
            return null;
        }
        var substitutions = session["substitutions"] instanceof Array ?
            session["substitutions"] as Array : [];
        var job = {
            "sessionId" => session["id"],
            "routine" => {"programId" => programId, "week" => week,
                "dayInWeek" => dayInWeek, "name" => session["templateName"]},
            "start" => start,
            "end" => end,
            "startTime" => startTime,
            "endTime" => endTime,
            "exercises" => mappedExercises,
            "substitutions" => substitutions,
            "state" => Liftosaur.STATE_START
        };
        return Model.validUpload(job) ? job : null;
    }

    // Completed, valid warmups of an exercise as job rows; "index" is the warmup position.
    function completedWarmupRows(exercise as Dictionary, type as String, start as Number,
                                 end as Number) as Array {
        var rows = [];
        var warmups = exercise["warmupSlots"];
        var timed = Model.sameString(type, "timed");
        for (var w = 0; warmups instanceof Array && w < (warmups as Array).size(); w++) {
            var completed = ((warmups as Array)[w] as Dictionary)["completed"];
            if (!(completed instanceof Dictionary)) {
                continue;
            }
            var done = completed as Dictionary;
            var reps = timed ? 1 : done["reps"];
            var load100 = done["load100"];
            var loaded = Model.sameString(type, "weight") || Model.sameString(type, "assistance");
            if (!Model.inRange(reps, 1, Model.MAX_REPS, false) ||
                (timed && !Model.inRange(done["durationSec"], 1, Model.MAX_DURATION_SEC, false)) ||
                (loaded && !Model.inRange(load100, 0, Model.MAX_LOAD100, false)) ||
                !Model.inRange(done["completedAt"], start, end, false)) {
                continue;
            }
            rows.add({"index" => w, "reps" => reps,
                "kg" => loaded ? (load100 as Number) / 100.0 : 0.0,
                "rpe10" => done["rpe10"],
                "timeSec" => timed ? done["durationSec"] : null,
                "completedAt" => done["completedAt"]});
        }
        return rows;
    }

    function startBody(job as Dictionary) as Dictionary {
        var routine = job["routine"] as Dictionary;
        return {"programId" => routine["programId"], "week" => routine["week"],
            "dayInWeek" => routine["dayInWeek"], "startTime" => job["startTime"]};
    }

    function setsDone(job as Dictionary) as Dictionary {
        var next = SessionLogic.copyDictionary(job);
        next["state"] = Liftosaur.STATE_FINISH;
        return next;
    }

    // intervals carries the real duration: with startTime/endTime alone Liftosaur recorded the
    // seconds between the start and finish requests ("duration: 2s"). notes become a "//" line
    // above the history record, so they are sent only when there is something to report.
    function finishBody(job as Dictionary) as Dictionary {
        var notes = "";
        var substitutions = job["substitutions"] as Array;
        for (var i = 0; i < substitutions.size(); i++) {
            var change = substitutions[i] as Dictionary;
            notes += (notes.length() > 0 ? "; " : "") + (change["from"] as String) + " -> " +
                (change["to"] as String);
        }
        var extras = job["extraWarmups"];
        for (var i = 0; extras instanceof Array && i < (extras as Array).size(); i++) {
            notes += (notes.length() > 0 ? "; " : "") + "extra warmups: " +
                ((extras as Array)[i] as String);
        }
        var body = {"startTime" => job["startTime"], "endTime" => job["endTime"],
            "intervals" => [[job["startTime"], job["endTime"]]]};
        if (notes.length() > 0) {
            body["notes"] = notes;
        }
        return body;
    }

    function responseWorkout(reply as Object?) as Dictionary? {
        return Catalog.workoutFromReply(reply);
    }

    function workingSets(entry as Dictionary) as Array {
        var source = entry["sets"] as Array;
        var result = [];
        for (var i = 0; i < source.size(); i++) {
            if ((source[i] as Dictionary)["isWarmup"] != true) {
                result.add(source[i]);
            }
        }
        return result;
    }

    function liveLoadType(entry as Dictionary) as String? {
        var sets = workingSets(entry);
        if (sets.size() == 0) {
            return null;
        }
        var timed = false;
        var bodyweight = true;
        for (var i = 0; i < sets.size(); i++) {
            var set = sets[i] as Dictionary;
            timed = timed || set["setTimer"] instanceof Number;
            if (Model.weightLoad100(set["weight"]) != 0) {
                bodyweight = false;
            }
        }
        return timed ? "timed" : (bodyweight ? "bodyweight" : "weight");
    }

    function liveUnilateral(entry as Dictionary) as Boolean {
        var sets = workingSets(entry);
        for (var i = 0; i < sets.size(); i++) {
            if ((sets[i] as Dictionary)["isUnilateral"] == true) {
                return true;
            }
        }
        return false;
    }

    // "62.5kg" / "135lb": the weight in the unit Liftosaur sent (jobs without a unit are kg).
    function kgString(load100 as Number) as String {
        return weightString(load100, "kg");
    }

    function weightString(load100 as Number, unit as Object?) as String {
        var suffix = Model.sameString(unit, "lb") ? "lb" : "kg";
        var whole = load100 / 100;
        var fraction = load100 % 100;
        if (fraction == 0) {
            return whole.toString() + suffix;
        }
        if (fraction % 10 == 0) {
            return whole.toString() + "." + (fraction / 10).toString() + suffix;
        }
        return whole.toString() + "." + (fraction < 10 ? "0" : "") +
            fraction.toString() + suffix;
    }

    // Values Liftosaur requires beyond reps and weight (API "sets that ask for a value"): rpe for
    // logRpe sets, userVars when the entry has prompted variables, setTimerLeft for one-sided
    // timed sets. A value the lifter did not give falls back to the program's own suggestion.
    function mappedCompleted(exercise as Dictionary, set as Dictionary,
                             plan as Dictionary, prompted as Object?) as Dictionary? {
        var timedPlan = plan["setTimer"] instanceof Number;
        var timedSession = set["timeSec"] instanceof Number;
        if (timedPlan != timedSession) {
            return null;
        }
        var result = {};
        if (timedPlan) {
            var plannedReps = plan["reps"] instanceof Number ? plan["reps"] : plan["minReps"];
            result["reps"] = plannedReps;
            result["weight"] = "0kg";
            result["setTimer"] = set["timeSec"];
            if (plan["isUnilateral"] == true || exercise["unilateral"] == true) {
                result["setTimerLeft"] = set["timeLeftSec"] instanceof Number ? set["timeLeftSec"] : set["timeSec"];
            }
        } else {
            result["reps"] = set["reps"];
            // "kg" is the stored field name; the value is in the exercise's unit.
            result["weight"] = weightString(Math.round((set["kg"] as Numeric) * 100.0).toNumber(),
                exercise["unit"]);
            if (plan["isUnilateral"] == true || exercise["unilateral"] == true) {
                result["repsLeft"] = set["reps"];
            }
        }
        if (plan["logRpe"] == true) {
            var target = plan["rpe"];
            result["rpe"] = set["rpe10"] instanceof Number ? rpeValue(set["rpe10"] as Number) :
                (target instanceof Number || target instanceof Float || target instanceof Double ? target : 8);
        }
        var vars = userVarsFor(prompted, exercise["userVars"]);
        if (vars != null) {
            result["userVars"] = vars;
        }
        return Model.validMappedSet({"entryId" => "x", "setId" => "x",
            "completed" => result}) ? result : null;
    }

    // 85 -> 8.5, 80 -> 8 (whole numbers stay numbers).
    function rpeValue(rpe10 as Number) as Numeric {
        return rpe10 % 10 == 0 ? rpe10 / 10 : rpe10 / 10.0;
    }

    // One value per prompted variable of the live entry: the lifter's answer, else the
    // advertised value. Null when the entry prompts for nothing.
    function userVarsFor(prompted as Object?, answers as Object?) as Dictionary? {
        if (!(prompted instanceof Array) || (prompted as Array).size() == 0) {
            return null;
        }
        var result = {};
        for (var i = 0; i < (prompted as Array).size(); i++) {
            var item = (prompted as Array)[i];
            if (!(item instanceof Dictionary) || !(item["name"] instanceof String)) {
                continue;
            }
            var name = item["name"] as String;
            var answer = answers instanceof Dictionary ? (answers as Dictionary)[name] : null;
            result[name] = answer != null ? answer : item["value"];
        }
        return result;
    }

    function cloneJob(job as Dictionary) as Dictionary {
        var copy = SessionLogic.copyDictionary(job);
        var sourceExercises = job["exercises"] as Array;
        var exercises = [];
        for (var i = 0; i < sourceExercises.size(); i++) {
            var exercise = SessionLogic.copyDictionary(sourceExercises[i] as Dictionary);
            var sourceSets = (sourceExercises[i] as Dictionary)["sets"] as Array;
            var sets = [];
            for (var s = 0; s < sourceSets.size(); s++) {
                sets.add(SessionLogic.copyDictionary(sourceSets[s] as Dictionary));
            }
            exercise["sets"] = sets;
            exercises.add(exercise);
        }
        copy["exercises"] = exercises;
        return copy;
    }

    function containsString(values as Array, value as Object?) as Boolean {
        for (var i = 0; i < values.size(); i++) {
            if (Model.sameString(values[i], value)) {
                return true;
            }
        }
        return false;
    }

    function withStartedWorkout(job as Dictionary, reply as Object?) as Dictionary? {
        return mapWorkout(job, reply, true);
    }

    // Non-mutating pre-check against a /workout/next preview: same matching rules, but the
    // preview's startTime and set ids are regenerated and only illustrative.
    function previewMaps(job as Dictionary, reply as Object?) as Boolean {
        return mapWorkout(job, reply, false) != null;
    }

    function mapWorkout(job as Dictionary, reply as Object?, exactStart as Boolean) as Dictionary? {
        if (!Model.validUpload(job) ||
            !(Model.sameString(job["state"], Liftosaur.STATE_START) ||
                Model.sameString(job["state"], Liftosaur.STATE_SETS) ||
                Model.sameString(job["state"], Liftosaur.STATE_FINISH))) {
            return null;
        }
        var workout = responseWorkout(reply);
        if (!Model.validLiftosaurWorkout(reply) || workout == null) {
            return null;
        }
        var routine = job["routine"] as Dictionary;
        var day = workout["dayData"] as Dictionary;
        var returnedStart = Model.epochMillis(workout["startTime"]);
        if (!Model.sameString(workout["programId"], routine["programId"]) ||
            !Model.sameString(workout["dayName"], routine["name"]) ||
            day["week"] != routine["week"] || day["dayInWeek"] != routine["dayInWeek"] ||
            (exactStart && (returnedStart == null ||
                (returnedStart as Long).compareTo(job["startTime"] as Long) != 0))) {
            return null;
        }
        if (job["setsBody"] instanceof Dictionary) {
            return SessionLogic.copyDictionary(job);
        }
        var next = cloneJob(job);
        var entries = workout["entries"] as Array;
        var bodySets = [];
        var extraWarmups = [];
        var usedIds = [];
        for (var e = 0; e < entries.size(); e++) {
            var source = entries[e] as Dictionary;
            var rawWorking = workingSets(source);
            for (var p = 0; p < rawWorking.size(); p++) {
                var rawSet = rawWorking[p] as Dictionary;
                if (Model.validText(rawSet["setId"], 64, false)) {
                    usedIds.add(rawSet["setId"]);
                }
            }
            var warmups = source["warmupSets"];
            if (warmups instanceof Array) {
                for (var w = 0; w < (warmups as Array).size(); w++) {
                    var warmup = (warmups as Array)[w] as Dictionary;
                    if (Model.validText(warmup["setId"], 64, false)) {
                        usedIds.add(warmup["setId"]);
                    }
                }
            }
        }
        var savedExercises = next["exercises"] as Array;
        for (var e = 0; e < savedExercises.size(); e++) {
            var saved = savedExercises[e] as Dictionary;
            var matches = [];
            for (var p = 0; p < entries.size(); p++) {
                if (Model.sameString((entries[p] as Dictionary)["name"], saved["name"])) {
                    matches.add(entries[p]);
                }
            }
            if (matches.size() != 1) {
                continue;
            }
            var source = matches[0] as Dictionary;
            var savedType = saved["loadType"] as String;
            var liveType = liveLoadType(source);
            if (liveType == null ||
                Model.sameString(liveType, "timed") != Model.sameString(savedType, "timed") ||
                Model.sameString(liveType, "bodyweight") !=
                    Model.sameString(savedType, "bodyweight") ||
                liveUnilateral(source) != (saved["unilateral"] == true)) {
                return null;
            }
            var plans = workingSets(source);
            if (plans.size() == 0) {
                continue;
            }
            var performed = saved["sets"] as Array;
            for (var s = 0; s < performed.size(); s++) {
                var set = performed[s] as Dictionary;
                var setNumber = set["set"] as Number;
                var append = setNumber > plans.size();
                var plan = plans[append ? plans.size() - 1 : setNumber - 1] as Dictionary;
                var completed = mappedCompleted(saved, set, plan, source["promptedVars"]);
                if (completed == null) {
                    return null;
                }
                var setId = null;
                var appendId = set["appendId"];
                if (append) {
                    if (!Model.validAppendId(appendId) || containsString(usedIds, appendId)) {
                        appendId = appendIdFor((job["sessionId"] as String) + "-" +
                            (saved["entryId"] as String) + "-" + setNumber.toString(), usedIds);
                        set["appendId"] = appendId;
                    } else {
                        usedIds.add(appendId);
                    }
                    setId = appendId;
                } else {
                    var rawPlan = plans[setNumber - 1] as Dictionary;
                    setId = rawPlan["setId"];
                }
                var mapped = {"entryId" => source["entryId"], "setId" => setId,
                    "completed" => completed};
                if (append) {
                    mapped["append"] = true;
                }
                if (Model.validMappedSet(mapped)) {
                    bodySets.add(mapped);
                }
            }
            // Warmups map by position onto the entry's warmupSets; a count mismatch is never a
            // failure (extras go to the finish notes, unmatched ones are simply not sent).
            var savedWarmups = saved["warmups"];
            var liveWarmups = source["warmupSets"] instanceof Array ?
                source["warmupSets"] as Array : [];
            var extraCount = 0;
            for (var w = 0; savedWarmups instanceof Array && w < (savedWarmups as Array).size(); w++) {
                var warmup = (savedWarmups as Array)[w] as Dictionary;
                var position = warmup["index"] as Number;
                if (position >= liveWarmups.size()) {
                    extraCount++;
                    continue;
                }
                var livePlan = liveWarmups[position] as Dictionary;
                var warmupDone = mappedCompleted(saved, warmup, livePlan, null);
                var warmupMapped = {"entryId" => source["entryId"], "setId" => livePlan["setId"],
                    "completed" => warmupDone};
                if (warmupDone != null && Model.validMappedSet(warmupMapped)) {
                    bodySets.add(warmupMapped);
                }
            }
            if (extraCount > 0) {
                extraWarmups.add((saved["name"] as String) + " x" + extraCount.toString());
            }
        }
        if (bodySets.size() == 0) {
            return null;
        }
        if (extraWarmups.size() > 0) {
            next["extraWarmups"] = extraWarmups;
        }
        next["setsBody"] = {"sets" => bodySets};
        next["state"] = Liftosaur.STATE_SETS;
        return Model.validUpload(next) ? next : null;
    }
}
