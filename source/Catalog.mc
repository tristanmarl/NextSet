import Toybox.Lang;
import Toybox.WatchUi;

module Catalog {
    var _data as Dictionary? = null;

    function data() as Dictionary {
        if (_data == null) {
            _data = WatchUi.loadResource($.Rez.JsonData.Seeds) as Dictionary;
        }
        return _data as Dictionary;
    }

    function exercises() as Array {
        return data()["exercises"] as Array;
    }

    function templates() as Array {
        return data()["templates"] as Array;
    }

    function exercise(id as String) as Dictionary? {
        var list = exercises();
        for (var i = 0; i < list.size(); i++) {
            if (Model.sameString(list[i]["id"], id)) {
                return list[i] as Dictionary;
            }
        }
        return null;
    }

    function template(id as String) as Dictionary? {
        var list = templates();
        for (var i = 0; i < list.size(); i++) {
            if (Model.sameString(list[i]["id"], id)) {
                return list[i] as Dictionary;
            }
        }
        return null;
    }

    function totalSets(template as Dictionary) as Number {
        var total = 0;
        var entries = template["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            total += entries[i]["workingSetCount"];
        }
        return total;
    }

    function dictionaryValue(source as Dictionary?, key as String) as Object? {
        if (source == null) {
            return null;
        }
        var keys = (source as Dictionary).keys();
        for (var i = 0; i < keys.size(); i++) {
            if (Model.sameString(keys[i], key)) {
                return (source as Dictionary)[keys[i]];
            }
        }
        return null;
    }

    function overridesFor(config as Dictionary?, templateId as String,
                          entryId as String) as Dictionary? {
        var templates = dictionaryValue(config, "templateOverrides");
        var templateOverrides = dictionaryValue(
            templates instanceof Dictionary ? templates as Dictionary : null,
            templateId
        );
        var entryOverrides = dictionaryValue(
            templateOverrides instanceof Dictionary ? templateOverrides as Dictionary : null,
            entryId
        );
        return entryOverrides instanceof Dictionary ? entryOverrides as Dictionary : null;
    }

    function valid() as Boolean {
        var list = exercises();
        var allTemplates = templates();
        if (list.size() < 1 || list.size() > Model.MAX_EXERCISES ||
            allTemplates.size() < 1 || allTemplates.size() > Model.MAX_TEMPLATES) {
            return false;
        }
        for (var i = 0; i < list.size(); i++) {
            if (!Model.validExercise(list[i])) {
                return false;
            }
        }
        for (var t = 0; t < allTemplates.size(); t++) {
            var workout = allTemplates[t] as Dictionary;
            if (!Model.validTemplate(workout)) {
                return false;
            }
            var entries = workout["entries"] as Array;
            for (var e = 0; e < entries.size(); e++) {
                var definition = exercise(entries[e]["exerciseId"] as String);
                if (definition == null) {
                    return false;
                }
                if (Model.sameString(definition["loadType"], "timed") && entries[e]["targetDurationSec"] == null) {
                    return false;
                }
                if (!Model.sameString(definition["loadType"], "timed") && entries[e]["targetRepsMin"] == null) {
                    return false;
                }
            }
        }
        return true;
    }

    function createSession(templateId as String, id as String, sequence as Number,
                           now as Number, cache as Dictionary?, config as Dictionary?) as Dictionary? {
        var workout = template(templateId);
        if (workout == null || !valid()) {
            return null;
        }
        var sessionExercises = [];
        var entries = workout["entries"] as Array;
        var settings = dictionaryValue(config, "settings");
        var configuredDefaultRest = dictionaryValue(
            settings instanceof Dictionary ? settings as Dictionary : null,
            "defaultRestSec"
        );
        var defaultRest = Model.inRange(configuredDefaultRest, 0, Model.MAX_REST_SEC, false) ?
            configuredDefaultRest as Number : 90;
        var counts = [];
        var candidateTotal = 0;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var count = entry["workingSetCount"] as Number;
            var entryOverrides = overridesFor(config, templateId, entry["entryId"] as String);
            var countOverride = dictionaryValue(entryOverrides, "workingSetCount");
            if (Model.inRange(countOverride, 1, Model.MAX_SETS, false)) {
                count = countOverride as Number;
            }
            counts.add(count);
            candidateTotal += count;
        }
        // ponytail: reject all count overrides together if they exceed the
        // workout ceiling; per-entry greedy acceptance would make results depend
        // on seed entry order.
        if (candidateTotal > Model.MAX_SETS_PER_WORKOUT) {
            for (var i = 0; i < entries.size(); i++) {
                counts[i] = (entries[i] as Dictionary)["workingSetCount"];
            }
        }

        var incrementOverrides = dictionaryValue(config, "incrementOverrides");
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var definition = exercise(entry["exerciseId"] as String) as Dictionary;
            var type = definition["loadType"] as String;
            var isTimed = Model.sameString(type, "timed");
            var isLoadable = Model.sameString(type, "weight") || Model.sameString(type, "assistance");
            var entryOverrides = overridesFor(config, templateId, entry["entryId"] as String);
            var count = counts[i] as Number;
            var minimum = entry["targetRepsMin"] as Number?;
            var maximum = entry["targetRepsMax"] as Number?;
            var duration = entry["targetDurationSec"] as Number?;
            var startingLoad = entry["startingLoad100"] as Number?;
            var rest = entry["restSec"] instanceof Number ? entry["restSec"] as Number :
                (definition["defaultRestSec"] instanceof Number ?
                    definition["defaultRestSec"] as Number : defaultRest);

            var override = dictionaryValue(entryOverrides, "restSec");
            if (Model.inRange(override, 0, Model.MAX_REST_SEC, false)) {
                rest = override as Number;
            }
            if (!isTimed) {
                var seedMinimum = minimum;
                var seedMaximum = maximum;
                override = dictionaryValue(entryOverrides, "targetRepsMin");
                if (Model.inRange(override, 1, Model.MAX_REPS, false)) {
                    minimum = override as Number;
                }
                override = dictionaryValue(entryOverrides, "targetRepsMax");
                if (Model.inRange(override, 1, Model.MAX_REPS, false)) {
                    maximum = override as Number;
                }
                if (minimum != null && maximum != null && (minimum as Number) > (maximum as Number)) {
                    minimum = seedMinimum;
                    maximum = seedMaximum;
                }
            }
            if (isTimed) {
                override = dictionaryValue(entryOverrides, "targetDurationSec");
                if (Model.inRange(override, 1, Model.MAX_DURATION_SEC, false)) {
                    duration = override as Number;
                }
            }
            if (isLoadable) {
                override = dictionaryValue(entryOverrides, "startingLoad100");
                if (Model.inRange(override, 0, Model.MAX_LOAD100, false)) {
                    startingLoad = override as Number;
                }
            }

            var increment = definition["increment100"];
            var incrementOverride = dictionaryValue(
                incrementOverrides instanceof Dictionary ? incrementOverrides as Dictionary : null,
                definition["id"] as String
            );
            if (isLoadable && Model.inRange(incrementOverride, 25, 10000, false) &&
                ((incrementOverride as Number) % 25) == 0) {
                increment = incrementOverride;
            }

            var slots = [];
            for (var slotIndex = 0; slotIndex < count; slotIndex++) {
                var draft = {};
                draft["load100"] = startingLoad;
                draft["reps"] = minimum;
                draft["durationSec"] = duration;
                draft["durationEdited"] = false;
                draft["targetAlertConsumed"] = false;
                var slot = {};
                slot["draft"] = draft;
                slot["completed"] = null;
                slots.add(slot);
            }
            var snapshot = {};
            snapshot["entryId"] = entry["entryId"];
            snapshot["exerciseId"] = definition["id"];
            snapshot["name"] = definition["name"];
            snapshot["loadType"] = type;
            snapshot["loadUnit"] = definition["unit"];
            snapshot["weightIncrement100"] = increment;
            snapshot["restSec"] = rest;
            snapshot["plannedSetCount"] = count;
            snapshot["targetRepsMin"] = minimum;
            snapshot["targetRepsMax"] = maximum;
            snapshot["targetDurationSec"] = duration;
            snapshot["notes"] = entry["notes"] != null ? entry["notes"] : definition["notes"];
            snapshot["closedEarly"] = false;
            snapshot["slots"] = slots;
            var cached = cache == null ? null : cache[definition["id"] as String];
            sessionExercises.add(LastPerformance.prefill(
                snapshot,
                cached instanceof Dictionary ? cached as Dictionary : null
            ));
        }

        var session = {};
        session["id"] = id;
        session["sessionSeq"] = sequence;
        session["templateId"] = workout["id"];
        session["templateRevision"] = workout["revision"];
        session["templateName"] = workout["name"];
        session["startedAt"] = now;
        session["endedAt"] = null;
        session["status"] = "active";
        session["completionKind"] = null;
        session["exercises"] = sessionExercises;
        session["rest"] = null;
        session["restGeneration"] = 0;
        session["nextSetSequence"] = 1;
        session["lastCompleted"] = null;
        return session;
    }
}
