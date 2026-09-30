import Toybox.Lang;

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

    function parseRoutine(reply as Object?, syncSeq as Number, ordinal as Number) as Dictionary? {
        if (!Model.validLiftosaurWorkout(reply) ||
            !Model.inRange(syncSeq, 1, 2147483647, false) ||
            !Model.inRange(ordinal, 1, Model.MAX_TEMPLATES, false)) {
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
                return null;
            }
            var firstSet = sets[0] as Dictionary;
            var timed = firstSet["setTimer"] instanceof Number;
            var bodyweight = true;
            var isUnilateral = false;
            for (var s = 0; s < sets.size(); s++) {
                var sourceSet = sets[s] as Dictionary;
                if ((sourceSet["setTimer"] instanceof Number) != timed) {
                    return null;
                }
                isUnilateral = isUnilateral || sourceSet["isUnilateral"] == true;
                if (Model.weightLoad100(sourceSet["weight"]) != 0) {
                    bodyweight = false;
                }
            }
            // ponytail: timed unilateral is unsupported until the watch can record both holds.
            if (timed && isUnilateral) {
                return null;
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
                targets.add({
                    "reps" => reps,
                    "minReps" => lowReps,
                    "load100" => Model.sameString(type, "weight") ? load100 : null,
                    "durationSec" => sourceSet["setTimer"]
                });
            }
            var warmups = [];
            var sourceWarmups = source["warmupSets"];
            if (sourceWarmups instanceof Array) {
                for (var w = 0; w < (sourceWarmups as Array).size(); w++) {
                    var warmup = (sourceWarmups as Array)[w] as Dictionary;
                    var warmupReps = warmup["reps"] instanceof Number ?
                        warmup["reps"] : warmup["minReps"];
                    warmups.add({
                        "reps" => warmupReps,
                        "load100" => Model.weightLoad100(warmup["weight"]),
                        "durationSec" => warmup["setTimer"]
                    });
                }
            }
            if (targets.size() == 0) {
                return null;
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
                "unit" => Model.sameString(type, "weight") ? "kg" : null,
                "increment100" => Model.sameString(type, "weight") ? 100 : null,
                "workingSetCount" => sets.size(),
                "restSec" => restSec,
                "defaultRestSec" => restSec,
                "setTargets" => targets,
                "warmups" => warmups,
                "targetRepsMin" => timed ? null : firstTarget["reps"],
                "targetRepsMax" => timed ? null : firstTarget["reps"],
                "targetDurationSec" => firstSet["setTimer"],
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
        return validRoutine(routine) ? routine : null;
    }

    function nextRoutineCoordinates(reply as Object?) as Dictionary? {
        if (!Model.validLiftosaurWorkout(reply)) {
            return null;
        }
        var workout = workoutFromReply(reply) as Dictionary;
        var day = workout["dayData"] as Dictionary;
        return {"programId" => workout["programId"], "week" => day["week"],
            "dayInWeek" => day["dayInWeek"]};
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

    function overridesFor(config as Dictionary?, routineId as String,
                          entryId as String) as Dictionary? {
        var allOverrides = dictionaryValue(config, "templateOverrides");
        var routineOverrides = dictionaryValue(
            allOverrides instanceof Dictionary ? allOverrides as Dictionary : null,
            routineId
        );
        var entryOverrides = dictionaryValue(
            routineOverrides instanceof Dictionary ? routineOverrides as Dictionary : null,
            entryId
        );
        return entryOverrides instanceof Dictionary ? entryOverrides as Dictionary : null;
    }

    function cloneTargets(targets as Array) as Array {
        var result = [];
        for (var i = 0; i < targets.size(); i++) {
            result.add(SessionLogic.copyDictionary(targets[i] as Dictionary));
        }
        return result;
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
                slots.add({"draft" => draft, "completed" => null});
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
                "notes" => entry["notes"],
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
}
