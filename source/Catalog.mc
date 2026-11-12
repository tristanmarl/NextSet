import Toybox.Lang;
import Toybox.Math;

module Catalog {
    function workoutFromReply(reply as Object?) as Dictionary? {
        if (!(reply instanceof Dictionary)) {
            return null;
        }
        var root = reply as Dictionary;
        var data = root["data"] instanceof Dictionary ? root["data"] as Dictionary : root;
        var workout = data["workout"] instanceof Dictionary ? data["workout"] : data;
        return workout instanceof Dictionary ? workout as Dictionary : null;
    }

    function routineId(syncSeq as Number, ordinal as Number) as String {
        return "sync-" + syncSeq.toString() + "-d" + ordinal.toString();
    }

    // Why the last parseRoutine returned null (short text), else null. Built only on failure.
    var lastProblem as String? = null;

    // Records "W1 D2 Name: text" (name only when an exercise is given) and returns null.
    function reject(workout as Dictionary, source as Dictionary?, text as String) as Dictionary? {
        var day = workout["dayData"] as Dictionary;
        lastProblem = Model.fit("W" + day["week"].toString() + " D" + day["dayInWeek"].toString() +
            (source == null ? ": " : " " + Model.nameTag(source["name"]) + ": ") + text, 60);
        return null;
    }

    // The routine, checked with validRoutine.
    function parseRoutine(reply as Object?, syncSeq as Number, ordinal as Number) as Dictionary? {
        var routine = projectRoutine(reply, syncSeq, ordinal);
        if (routine != null && !validRoutine(routine as Dictionary)) {
            return reject(workoutFromReply(reply) as Dictionary, null, "routine rejected");
        }
        return routine;
    }

    // Reply check and projection only: the sync validates the routine (validRoutine) in its own
    // step, right before the commit, so one callback never walks a day four times.
    function projectRoutine(reply as Object?, syncSeq as Number, ordinal as Number) as Dictionary? {
        return checkReply(reply) ? projectChecked(reply, syncSeq, ordinal) : null;
    }

    // The walk over the raw reply alone (the reason is left in lastProblem).
    function checkReply(reply as Object?) as Boolean {
        lastProblem = Model.liftosaurWorkoutProblem(reply);
        return lastProblem == null;
    }

    // Projection of a reply checkReply accepted, in its own sync step.
    function projectChecked(reply as Object?, syncSeq as Number, ordinal as Number) as Dictionary? {
        if (!Model.inRange(syncSeq, 1, 2147483647, false) ||
            !Model.inRange(ordinal, 1, Model.MAX_TEMPLATES, false)) {
            lastProblem = "Day number out of range";
            return null;
        }
        var workout = workoutFromReply(reply) as Dictionary;
        var sourceEntries = workout["entries"] as Array;
        var entries = [];
        for (var e = 0; e < sourceEntries.size(); e++) {
            var source = sourceEntries[e] as Dictionary;
            var sourceSets = source["sets"] as Array;
            var sets = [];
            for (var s = 0; s < sourceSets.size(); s++) {
                if ((sourceSets[s] as Dictionary)["isWarmup"] != true) {
                    sets.add(sourceSets[s]);
                }
            }
            if (sets.size() == 0 || sets.size() > Model.MAX_SETS) {
                return reject(workout, source, sets.size() == 0 ? "only warmup sets" :
                    sets.size().toString() + " sets (max " + Model.MAX_SETS.toString() + ")");
            }
            var firstSet = sets[0] as Dictionary;
            var timed = Model.timedSet(firstSet);
            // kg or lb as Liftosaur sends it; one exercise never mixes units.
            var unit = Model.weightUnit(firstSet["weight"]);
            var bodyweight = true;
            var isUnilateral = false;
            for (var s = 0; s < sets.size(); s++) {
                var sourceSet = sets[s] as Dictionary;
                if (Model.timedSet(sourceSet) != timed ||
                    !Model.sameString(Model.weightUnit(sourceSet["weight"]), unit)) {
                    return reject(workout, source, Model.timedSet(sourceSet) != timed ?
                        "mixes timed and normal sets" : "mixes kg and lb");
                }
                isUnilateral = isUnilateral || sourceSet["isUnilateral"] == true;
                if (Model.weightLoad100(sourceSet["weight"]) != 0) {
                    bodyweight = false;
                }
            }
            var type = timed ? "timed" : (bodyweight ? "bodyweight" : "weight");
            var equipment = source["equipment"] instanceof String ?
                source["equipment"] as String : "";
            var liftId = source["exerciseId"] instanceof String ?
                source["exerciseId"] as String : source["entryId"] as String;
            var exerciseId = liftExerciseId(liftId + "-" + (source["name"] as String), equipment);
            var targets = [];
            for (var s = 0; s < sets.size(); s++) {
                var sourceSet = sets[s] as Dictionary;
                var reps = sourceSet["reps"] instanceof Number ?
                    sourceSet["reps"] : sourceSet["minReps"];
                var load100 = Model.weightLoad100(sourceSet["weight"]);
                // A range only when the API gives both bounds; nothing is inferred otherwise.
                var lowReps = sourceSet["reps"] instanceof Number &&
                    sourceSet["minReps"] instanceof Number &&
                    (sourceSet["minReps"] as Number) < (sourceSet["reps"] as Number) ?
                    sourceSet["minReps"] : null;
                var rpe = sourceSet["rpe"];
                var setRest = sourceSet["timer"];
                targets.add({
                    // Per-set rest and AMRAP ("3+"); both omitted from the cache when absent.
                    "restSec" => Model.inRange(setRest, 0, Model.MAX_REST_SEC, false) ? setRest : null,
                    "amrap" => sourceSet["isAmrap"] == true ? true : null,
                    "reps" => reps,
                    "minReps" => lowReps,
                    "load100" => Model.sameString(type, "weight") ? load100 : null,
                    "durationSec" => timed ? sourceSet["setTimer"] : null,
                    "logRpe" => sourceSet["logRpe"] == true ? true : null,
                    "rpe10" => rpe instanceof Number || rpe instanceof Float || rpe instanceof Double ?
                        clampRpe10(Math.round((rpe as Numeric) * 10.0).toNumber()) : null
                });
            }
            var warmups = [];
            var sourceWarmups = source["warmupSets"];
            if (sourceWarmups instanceof Array) {
                for (var w = 0; w < (sourceWarmups as Array).size(); w++) {
                    var warmup = (sourceWarmups as Array)[w] as Dictionary;
                    if (!Model.sameString(Model.weightUnit(warmup["weight"]), unit) &&
                        Model.weightLoad100(warmup["weight"]) != 0) {
                        return reject(workout, source, "warmup unit differs");
                    }
                    var warmupReps = warmup["reps"] instanceof Number ?
                        warmup["reps"] : warmup["minReps"];
                    warmups.add({
                        "reps" => warmupReps,
                        "load100" => Model.weightLoad100(warmup["weight"]),
                        "durationSec" => timed ? warmup["setTimer"] : null,
                        "restSec" => warmup["timer"] instanceof Number ? warmup["timer"] : null
                    });
                }
            }
            if (targets.size() == 0) {
                return reject(workout, source, "no sets");
            }
            var firstTarget = targets[0] as Dictionary;
            var restSec = firstSet["timer"];
            entries.add({
                "entryId" => "e" + (e + 1).toString(),
                "liftosaurEntryId" => source["entryId"],
                "exerciseId" => exerciseId,
                "name" => source["name"],
                "equipment" => source["equipment"],
                "superset" => source["superset"],
                "unilateral" => isUnilateral,
                "loadType" => type,
                "unit" => Model.sameString(type, "weight") ? unit : null,
                // Automatic step: 2.5 kg or 5 lb (the API has no rounding field).
                "increment100" => Model.sameString(type, "weight") ?
                    Model.defaultIncrement100(unit) : null,
                "workingSetCount" => sets.size(),
                "restSec" => restSec,
                "defaultRestSec" => restSec,
                "setTargets" => targets,
                "warmups" => warmups,
                "targetRepsMin" => timed ? null : firstTarget["reps"],
                "targetRepsMax" => timed ? null : firstTarget["reps"],
                "targetDurationSec" => timed ? firstSet["setTimer"] : null,
                "prompts" => promptsOf(source["promptedVars"]),
                "startingLoad100" => Model.sameString(type, "weight") ?
                    Model.weightLoad100(firstSet["weight"]) : null
            });
        }
        var dayData = workout["dayData"] as Dictionary;
        var routine = {
            "id" => routineId(syncSeq, ordinal),
            "revision" => syncSeq,
            "name" => workout["dayName"],
            "programId" => workout["programId"],
            "week" => dayData["week"],
            "dayInWeek" => dayData["dayInWeek"],
            "entries" => entries
        };
        return routine;
    }

    // Program, week, day and name of a /workout/next reply whose envelope is well formed,
    // whatever its exercises (none, or ones NextSet cannot run), else null. The sync uses it to
    // tell a reply for the wrong day (stop) from a day it skips (empty or unsupported).
    function dayCoordinates(reply as Object?) as Dictionary? {
        var workout = workoutFromReply(reply);
        if (workout == null) {
            return null;
        }
        var day = workout["dayData"];
        if (!(workout["entries"] instanceof Array) ||
            !Model.validProgramId(workout["programId"]) ||
            !Model.validNonblankText(workout["dayName"], Model.MAX_DAY_NAME_BYTES) || !(day instanceof Dictionary) ||
            !Model.inRange((day as Dictionary)["week"], 1, 1000, false) ||
            !Model.inRange((day as Dictionary)["dayInWeek"], 1, 1000, false)) {
            return null;
        }
        return {"programId" => workout["programId"], "name" => workout["dayName"],
            "week" => (day as Dictionary)["week"], "dayInWeek" => (day as Dictionary)["dayInWeek"],
            "exercises" => (workout["entries"] as Array).size()};
    }

    // The routine to offer next: Liftosaur's next day, or when that day was skipped (no
    // exercises) the next synced day after it in the week, else the first synced day.
    function nextRoutineId(routines as Array, week as Number, dayInWeek as Number) as String? {
        var exact = findRoutineId(routines, week, dayInWeek);
        if (exact != null || routines.size() == 0) {
            return exact;
        }
        for (var i = 0; i < routines.size(); i++) {
            var routine = routines[i] as Dictionary;
            if (routine["week"] == week && (routine["dayInWeek"] as Number) > dayInWeek) {
                return routine["id"] as String;
            }
        }
        return (routines[0] as Dictionary)["id"] as String;
    }

    function findRoutineId(routines as Array, week as Number, dayInWeek as Number) as String? {
        for (var i = 0; i < routines.size(); i++) {
            var routine = routines[i] as Dictionary;
            if (routine["week"] == week && routine["dayInWeek"] == dayInWeek) {
                return routine["id"] as String;
            }
        }
        return null;
    }

    function liftExerciseId(sourceId as String, equipment as String) as String {
        var source = sourceId + (equipment.length() > 0 ? "-" + equipment : "");
        var text = source.toLower();
        var slug = "";
        var hash = 17;
        for (var i = 0; i < text.length(); i++) {
            var character = text.substring(i, i + 1) as String;
            var bytes = character.toUtf8Array();
            for (var b = 0; b < bytes.size(); b++) {
                hash = (hash * 31 + bytes[b]) % 10000000;
            }
            if (Model.validId(character)) {
                if (slug.length() < 25) {
                    slug += character;
                }
            } else if (slug.length() > 0 &&
                       !Model.sameString(slug.substring(slug.length() - 1,
                           slug.length()) as String, "-") && slug.length() < 25) {
                slug += "-";
            }
        }
        if (slug.length() == 0) {
            slug = "exercise";
        } else if (Model.sameString(slug.substring(slug.length() - 1,
            slug.length()) as String, "-")) {
            slug = slug.substring(0, slug.length() - 1) as String;
        }
        return "lift-" + slug + "-" + hash.toString();
    }

    function routineTemplates(config as Dictionary?) as Array {
        var saved = dictionaryValue(config, "routines");
        return saved instanceof Array ? saved as Array : [];
    }

    function routineTemplate(config as Dictionary?, id as String) as Dictionary? {
        var routines = routineTemplates(config);
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString((routines[i] as Dictionary)["id"], id)) {
                return routines[i] as Dictionary;
            }
        }
        return null;
    }

    function exerciseForEntry(entry as Dictionary) as Dictionary? {
        if (!Model.validId(entry["exerciseId"])) {
            return null;
        }
        var exercise = SessionLogic.copyDictionary(entry);
        exercise["id"] = entry["exerciseId"];
        exercise["defaultRestSec"] = entry["restSec"];
        return exercise;
    }

    function allRoutineExercises(config as Dictionary?) as Array {
        var result = [];
        var ids = {};
        var routines = routineTemplates(config);
        for (var r = 0; r < routines.size(); r++) {
            var entries = (routines[r] as Dictionary)["entries"] as Array;
            for (var e = 0; e < entries.size(); e++) {
                var entry = entries[e] as Dictionary;
                var id = entry["exerciseId"] as String;
                if (!ids.hasKey(id)) {
                    ids[id] = true;
                    var exercise = SessionLogic.copyDictionary(entry);
                    exercise["id"] = id;
                    exercise["defaultRestSec"] = entry["restSec"];
                    result.add(exercise);
                }
            }
        }
        return result;
    }

    function validRoutine(routine as Dictionary) as Boolean {
        return Model.validTemplate(routine);
    }

    function totalSets(routine as Dictionary) as Number {
        var total = 0;
        var entries = routine["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            total += (entries[i] as Dictionary)["workingSetCount"] as Number;
        }
        return total;
    }

    function dictionaryValue(source as Dictionary?, key as String) as Object? {
        return source != null && (source as Dictionary).hasKey(key) ?
            (source as Dictionary)[key] : null;
    }

    function cloneTargets(targets as Array) as Array {
        var result = [];
        for (var i = 0; i < targets.size(); i++) {
            result.add(SessionLogic.copyDictionary(targets[i] as Dictionary));
        }
        return result;
    }

    // Trackable warmup slots from the routine's warmup targets (at most MAX_WARMUP_SLOTS); a
    // target that cannot give a valid draft is dropped. Loads only for weight exercises.
    function warmupSlotsFor(type as String, warmups as Array, firstTarget as Dictionary) as Array {
        var slots = [];
        for (var w = 0; w < warmups.size() && slots.size() < Model.MAX_WARMUP_SLOTS; w++) {
            var target = warmups[w] as Dictionary;
            var reps = target["reps"] instanceof Number ? target["reps"] : firstTarget["reps"];
            var draft = null;
            if (Model.sameString(type, "timed")) {
                var duration = target["durationSec"] instanceof Number ? target["durationSec"] :
                    firstTarget["durationSec"];
                draft = {"load100" => null, "reps" => null, "durationSec" => duration,
                    "durationEdited" => false, "targetAlertConsumed" => false};
            } else {
                draft = {"load100" => Model.sameString(type, "weight") ? target["load100"] : null,
                    "reps" => reps, "durationSec" => null,
                    "durationEdited" => false, "targetAlertConsumed" => false};
            }
            var slot = {"draft" => draft, "completed" => null, "restSec" => target["restSec"]};
            if (Model.validSavedDraft(type, draft) &&
                (!Model.sameString(type, "weight") || draft["load100"] instanceof Number) &&
                (Model.sameString(type, "timed") ? draft["durationSec"] instanceof Number :
                    draft["reps"] instanceof Number)) {
                slots.add(slot);
            }
        }
        return slots;
    }

    function createSession(templateId as String, id as String, sequence as Number,
                           now as Number, cache as Dictionary?, config as Dictionary?) as Dictionary? {
        var routine = routineTemplate(config, templateId);
        if (routine == null || !validRoutine(routine as Dictionary)) {
            return null;
        }
        var plan = routine as Dictionary;
        var sessionExercises = [];
        var entries = plan["entries"] as Array;
        var settings = dictionaryValue(config, "settings");
        var configuredRest = dictionaryValue(
            settings instanceof Dictionary ? settings as Dictionary : null,
            "defaultRestSec"
        );
        var defaultRest = Model.inRange(configuredRest, 0, Model.MAX_REST_SEC, false) ?
            configuredRest as Number : 90;
        var incrementOverrides = dictionaryValue(config, "incrementOverrides");
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var definition = exerciseForEntry(entry) as Dictionary;
            var type = definition["loadType"] as String;
            var timed = Model.sameString(type, "timed");
            var loadable = Model.sameString(type, "weight");
            var targets = entry["setTargets"] as Array;
            var count = entry["workingSetCount"] as Number;
            var rest = Model.inRange(entry["restSec"], 0, Model.MAX_REST_SEC, false) ?
                entry["restSec"] as Number : defaultRest;
            var increment = entry["increment100"];
            // A routine cached before 0.4.2 holds the old 1 kg default; it was never user-set
            // (overrides live in config), so it becomes the 2.5 kg default.
            if (loadable && increment == 100 && !Model.sameString(definition["unit"], "lb")) {
                increment = Model.defaultIncrement100("kg");
            }
            var incrementOverride = dictionaryValue(
                incrementOverrides instanceof Dictionary ? incrementOverrides as Dictionary : null,
                definition["name"] as String
            );
            if (loadable && Model.inRange(incrementOverride, 25, 10000, false) &&
                ((incrementOverride as Number) % 25) == 0) {
                increment = incrementOverride;
            }
            var slots = [];
            for (var s = 0; s < count; s++) {
                var target = targets[s < targets.size() ? s : targets.size() - 1] as Dictionary;
                var draft = {
                    "load100" => target["load100"],
                    "reps" => target["reps"],
                    "durationSec" => target["durationSec"],
                    "durationEdited" => false,
                    "targetAlertConsumed" => false
                };
                var slot = {"draft" => draft, "completed" => null};
                if (Model.inRange(target["restSec"], 0, Model.MAX_REST_SEC, false)) {
                    slot["restSec"] = target["restSec"];
                }
                if (target["amrap"] == true) {
                    slot["amrap"] = true;
                }
                slots.add(slot);
            }
            var firstTarget = targets[0] as Dictionary;
            var minReps = null;
            var maxReps = null;
            var minDuration = null;
            var maxDuration = null;
            for (var t = 0; t < targets.size(); t++) {
                var target = targets[t] as Dictionary;
                var value = timed ? target["durationSec"] : target["reps"];
                if (timed) {
                    minDuration = minDuration == null || value < minDuration ? value : minDuration;
                    maxDuration = maxDuration == null || value > maxDuration ? value : maxDuration;
                } else {
                    var low = target["minReps"] instanceof Number ? target["minReps"] : value;
                    minReps = minReps == null || low < minReps ? low : minReps;
                    maxReps = maxReps == null || value > maxReps ? value : maxReps;
                }
            }
            var warmupSlots = warmupSlotsFor(type, entry["warmups"] as Array, firstTarget);
            var snapshot = {
                "entryId" => entry["entryId"],
                "liftosaurEntryId" => entry["liftosaurEntryId"],
                "liftosaurPlannedSetCount" => count,
                "exerciseId" => definition["id"],
                "name" => definition["name"],
                "loadType" => type,
                "loadUnit" => definition["unit"],
                "equipment" => entry["equipment"],
                "superset" => entry["superset"],
                "unilateral" => entry["unilateral"],
                "weightIncrement100" => increment,
                "restSec" => rest,
                "plannedSetCount" => count,
                "targetRepsMin" => minReps,
                "targetRepsMax" => maxReps,
                "targetDurationSec" => minDuration,
                "planTargets" => cloneTargets(targets),
                "warmups" => cloneTargets(entry["warmups"] as Array),
                "warmupSlots" => warmupSlots,
                "notes" => entry["notes"],
                "prompts" => entry["prompts"],
                "userVars" => defaultUserVars(entry["prompts"]),
                "closedEarly" => false,
                "slots" => slots
            };
            var cached = cache == null ? null : cache[definition["id"] as String];
            var filled = LastPerformance.prefill(snapshot,
                cached instanceof Dictionary ? cached as Dictionary : null);
            sessionExercises.add(LastPerformance.applyPlanTargets(filled, targets));
        }

        return {
            "id" => id,
            "sessionSeq" => sequence,
            "templateId" => plan["id"],
            "templateRevision" => plan["revision"],
            "templateName" => plan["name"],
            "programId" => plan["programId"],
            "week" => plan["week"],
            "dayInWeek" => plan["dayInWeek"],
            "startedAt" => now,
            "endedAt" => null,
            "status" => "active",
            "completionKind" => null,
            "fitSegments" => 0,
            "exercises" => sessionExercises,
            "substitutions" => [],
            "rest" => null,
            "restGeneration" => 0,
            "nextSetSequence" => 1,
            "lastCompleted" => null
        };
    }

    function clampRpe10(value as Number) as Number {
        return value < 10 ? 10 : (value > 100 ? 100 : value);
    }

    // Prompted state variables as the entry advertises them; null when there are none.
    function promptsOf(value as Object?) as Array? {
        if (!(value instanceof Array) || (value as Array).size() == 0) {
            return null;
        }
        var result = [];
        for (var i = 0; i < (value as Array).size() && i < 4; i++) {
            var item = (value as Array)[i];
            if (item instanceof Dictionary) {
                result.add({"name" => item["name"], "value" => item["value"]});
            }
        }
        return Model.validPrompts(result) && result.size() > 0 ? result : null;
    }

    // Answers start at the advertised values, so a skipped question still sends a value.
    function defaultUserVars(prompts as Object?) as Dictionary? {
        if (!(prompts instanceof Array)) {
            return null;
        }
        var result = {};
        for (var i = 0; i < (prompts as Array).size(); i++) {
            var item = (prompts as Array)[i] as Dictionary;
            result[item["name"]] = item["value"];
        }
        return result;
    }
}
