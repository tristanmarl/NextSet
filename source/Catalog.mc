import Toybox.Lang;
import Toybox.WatchUi;

module Catalog {
    var _data as Dictionary? = null;
    var _exerciseIndex as Dictionary? = null;
    var _garminOrder as Array? = null;
    var _garminCategories as Array? = null;
    var _garminIndex as Number = -1;
    var _garminEntries as Array? = null;
    var _garminResources = [
        $.Rez.JsonData.Garmin00, $.Rez.JsonData.Garmin01, $.Rez.JsonData.Garmin02,
        $.Rez.JsonData.Garmin03, $.Rez.JsonData.Garmin04, $.Rez.JsonData.Garmin05,
        $.Rez.JsonData.Garmin06, $.Rez.JsonData.Garmin07, $.Rez.JsonData.Garmin08,
        $.Rez.JsonData.Garmin09, $.Rez.JsonData.Garmin10, $.Rez.JsonData.Garmin11,
        $.Rez.JsonData.Garmin12, $.Rez.JsonData.Garmin13, $.Rez.JsonData.Garmin14,
        $.Rez.JsonData.Garmin15, $.Rez.JsonData.Garmin16, $.Rez.JsonData.Garmin17,
        $.Rez.JsonData.Garmin18, $.Rez.JsonData.Garmin19, $.Rez.JsonData.Garmin20,
        $.Rez.JsonData.Garmin21, $.Rez.JsonData.Garmin22, $.Rez.JsonData.Garmin23,
        $.Rez.JsonData.Garmin24, $.Rez.JsonData.Garmin25, $.Rez.JsonData.Garmin26,
        $.Rez.JsonData.Garmin27, $.Rez.JsonData.Garmin28, $.Rez.JsonData.Garmin29,
        $.Rez.JsonData.Garmin30, $.Rez.JsonData.Garmin31, $.Rez.JsonData.Garmin32,
        $.Rez.JsonData.Garmin33, $.Rez.JsonData.Garmin34, $.Rez.JsonData.Garmin35,
        $.Rez.JsonData.Garmin36, $.Rez.JsonData.Garmin37, $.Rez.JsonData.Garmin38,
        $.Rez.JsonData.Garmin39, $.Rez.JsonData.Garmin40, $.Rez.JsonData.Garmin41,
        $.Rez.JsonData.Garmin42, $.Rez.JsonData.Garmin43, $.Rez.JsonData.Garmin44,
        $.Rez.JsonData.Garmin45, $.Rez.JsonData.Garmin46
    ];

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

    // Comma separated list -> Array of Strings.
    function splitList(text as String) as Array {
        var result = [];
        var rest = text;
        while (rest.length() > 0) {
            var cut = rest.find(",");
            if (cut == null) {
                result.add(rest);
                break;
            }
            result.add(rest.substring(0, cut as Number));
            rest = rest.substring((cut as Number) + 1, rest.length()) as String;
        }
        return result;
    }

    // Category codes; the index is also the Garmin<NN> resource number.
    function garminCategories() as Array {
        if (_garminCategories == null) {
            _garminCategories = splitList(WatchUi.loadResource($.Rez.JsonData.GarminCategories) as String);
        }
        return _garminCategories as Array;
    }

    function garminCategoryName(index as Number) as String {
        return titleCase(garminCategories()[index] as String);
    }

    // "BENCH_PRESS" -> "Bench Press"; leading underscores are ignored.
    function titleCase(code as String) as String {
        var result = "";
        var rest = code.toLower();
        while (rest.length() > 0) {
            var cut = rest.find("_");
            var word = cut == null ? rest : rest.substring(0, cut as Number);
            rest = cut == null ? "" : rest.substring((cut as Number) + 1, rest.length()) as String;
            if (word.length() > 0) {
                result += (result.length() > 0 ? " " : "") +
                    word.substring(0, 1).toUpper() + word.substring(1, word.length());
            }
        }
        return result;
    }

    // "g<category index>-<code>" as lowercase letters, digits and "-" (Model.validId, max 40).
    // A slug over 36 characters keeps its first 16 and last 20; scripts/generate_garmin_catalog.py
    // asserts the ids are unique across the catalog.
    function garminId(categoryIndex as Number, code as String) as String {
        var slug = "";
        var rest = code.toLower();
        while (rest.length() > 0) {
            var cut = rest.find("_");
            var word = cut == null ? rest : rest.substring(0, cut as Number);
            rest = cut == null ? "" : rest.substring((cut as Number) + 1, rest.length()) as String;
            if (word.length() > 0) {
                slug += (slug.length() > 0 ? "-" : "") + word;
            }
        }
        if (slug.length() > 36) {
            slug = slug.substring(0, 16) + slug.substring(slug.length() - 20, slug.length());
        }
        return "g" + categoryIndex.format("%02d") + "-" + slug;
    }

    // Display order of category indices: common strength categories first, then the rest as stored.
    function garminCategoryOrder() as Array {
        if (_garminOrder == null) {
            var common = ["BENCH_PRESS", "SQUAT", "DEADLIFT", "ROW", "SHOULDER_PRESS", "PULL_UP",
                "CURL", "TRICEPS_EXTENSION", "LUNGE", "PLANK", "CORE", "LATERAL_RAISE", "LEG_CURL"];
            var order = [];
            for (var i = 0; i < common.size(); i++) {
                var index = garminCategoryIndex(common[i] as String);
                if (index >= 0) {
                    order.add(index);
                }
            }
            var total = garminCategories().size();
            for (var i = 0; i < total; i++) {
                if (order.indexOf(i) < 0) {
                    order.add(i);
                }
            }
            _garminOrder = order;
        }
        return _garminOrder as Array;
    }

    // Raw entries of one category ("CODE", "CODE*" bodyweight, "CODE!" group-only in Connect);
    // only one category is kept in memory.
    function garminEntries(categoryIndex as Number) as Array {
        if (_garminIndex != categoryIndex) {
            if (categoryIndex < 0 || categoryIndex >= _garminResources.size()) {
                return [];
            }
            _garminEntries = splitList(WatchUi.loadResource(_garminResources[categoryIndex]) as String);
            _garminIndex = categoryIndex;
        }
        return _garminEntries as Array;
    }

    function entryFlag(entry as String, flag as String) as Boolean {
        return entry.find(flag) != null;
    }

    function entryCode(entry as String) as String {
        var end = entry.length();
        while (end > 0 && (entry.substring(end - 1, end).equals("*") ||
               entry.substring(end - 1, end).equals("!"))) {
            end--;
        }
        return entry.substring(0, end) as String;
    }

    // Picker row {id, name, category, code (null when group-only), isBodyWeight (true or null)}.
    function garminRow(categoryIndex as Number, position as Number) as Dictionary {
        var entry = garminEntries(categoryIndex)[position] as String;
        var code = entryCode(entry);
        return {
            "id" => garminId(categoryIndex, code),
            "name" => titleCase(code),
            "category" => garminCategories()[categoryIndex],
            "code" => entryFlag(entry, "!") ? null : code,
            "isBodyWeight" => entryFlag(entry, "*") ? true : null
        };
    }

    function garminExercise(categoryIndex as Number, id as String) as Dictionary? {
        var entries = garminEntries(categoryIndex);
        for (var i = 0; i < entries.size(); i++) {
            if (Model.sameString(garminId(categoryIndex, entryCode(entries[i] as String)), id)) {
                return garminRow(categoryIndex, i);
            }
        }
        return null;
    }

    function garminCategoryIndex(code as String) as Number {
        var categories = garminCategories();
        for (var i = 0; i < categories.size(); i++) {
            if (Model.sameString(categories[i], code)) {
                return i;
            }
        }
        return -1;
    }

    function garminName(category as String, code as String) as String {
        var index = garminCategoryIndex(category);
        if (index >= 0) {
            var entries = garminEntries(index);
            for (var i = 0; i < entries.size(); i++) {
                var entry = entries[i] as String;
                if (!entryFlag(entry, "!") && Model.sameString(entryCode(entry), code)) {
                    return titleCase(code);
                }
            }
        }
        return code;
    }

    function routineTemplates(config as Dictionary?) as Array {
        var saved = dictionaryValue(config, "routines");
        if (saved instanceof Array) {
            return saved as Array;
        }
        var result = [];
        var seeded = templates();
        for (var i = 0; i < seeded.size(); i++) {
            var source = seeded[i] as Dictionary;
            var routine = SessionLogic.copyDictionary(source);
            var entries = [];
            var sourceEntries = source["entries"] as Array;
            for (var j = 0; j < sourceEntries.size(); j++) {
                var entry = SessionLogic.copyDictionary(sourceEntries[j] as Dictionary);
                var definition = exercise(entry["exerciseId"] as String) as Dictionary;
                entry["name"] = definition["name"];
                entry["loadType"] = definition["loadType"];
                entry["unit"] = definition["unit"];
                entry["defaultRestSec"] = definition["defaultRestSec"];
                entry["isBodyWeight"] = definition["isBodyWeight"];
                entry["garminCategory"] = definition["garminCategory"];
                entry["garminCode"] = definition["garminCode"];
                entries.add(entry);
            }
            routine["entries"] = entries;
            result.add(routine);
        }
        return result;
    }

    function routineTemplate(config as Dictionary?, id as String) as Dictionary? {
        var list = routineTemplates(config);
        for (var i = 0; i < list.size(); i++) {
            if (Model.sameString(list[i]["id"], id)) {
                return list[i] as Dictionary;
            }
        }
        return null;
    }

    function exerciseForEntry(entry as Dictionary) as Dictionary? {
        var id = entry["exerciseId"];
        if (!(id instanceof String)) {
            return null;
        }
        var seeded = exercise(id as String);
        if (seeded != null) {
            var copy = SessionLogic.copyDictionary(seeded as Dictionary);
            var keys = ["name", "loadType", "unit",
                "defaultRestSec", "notes", "isBodyWeight"];
            for (var i = 0; i < keys.size(); i++) {
                var key = keys[i] as String;
                if (entry[key] != null || Model.sameString(key, "unit") ||
                    Model.sameString(key, "increment100")) {
                    copy[key] = entry[key];
                }
            }
            if (entry["increment100"] instanceof Number) {
                copy["increment100"] = entry["increment100"];
            }
            // The seed's Garmin mapping wins over a code stored in an older routine (null allowed).
            copy["garminCategory"] = seeded["garminCategory"];
            copy["garminCode"] = seeded["garminCode"];
            return copy;
        }
        var definition = {};
        definition["id"] = id;
        definition["name"] = entry["name"];
        definition["loadType"] = entry["loadType"];
        definition["unit"] = entry["unit"];
        definition["increment100"] = entry["increment100"];
        definition["defaultRestSec"] = entry["defaultRestSec"];
        definition["notes"] = entry["notes"];
        definition["isBodyWeight"] = entry["isBodyWeight"];
        definition["garminCategory"] = entry["garminCategory"];
        definition["garminCode"] = entry["garminCode"];
        // Catalog ids ("g<NN>-...") resolve to the current catalog row, so a corrected code reaches old
        // routines. Only the entry's stored category resource is loaded (one of 47), not all.
        // Older "g-<hex>" ids never match and keep their stored name and code.
        var storedCategory = entry["garminCategory"];
        if ((id as String).find("g") == 0 && storedCategory instanceof String) {
            var index = garminCategoryIndex(storedCategory as String);
            var row = index < 0 ? null : garminExercise(index, id as String);
            if (row != null) {
                definition["garminCategory"] = (row as Dictionary)["category"];
                definition["garminCode"] = (row as Dictionary)["code"];
            }
        }
        return definition;
    }

    function validRoutine(workout as Dictionary) as Boolean {
        if (!Model.validTemplate(workout)) {
            return false;
        }
        var entries = workout["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            // Only the fields Model.validExercise reads, merged as exerciseForEntry would.
            var id = entry["exerciseId"];
            if (!(id instanceof String)) {
                return false;
            }
            var seeded = exercise(id as String);
            var definition = {"id" => id, "unit" => entry["unit"]};
            var keys = ["name", "loadType", "defaultRestSec", "notes"];
            for (var k = 0; k < keys.size(); k++) {
                var key = keys[k] as String;
                definition[key] = (seeded != null && entry[key] == null) ?
                    seeded[key] : entry[key];
            }
            definition["increment100"] = (seeded != null && !(entry["increment100"] instanceof Number)) ?
                seeded["increment100"] : entry["increment100"];
            if (!Model.validExercise(definition)) {
                return false;
            }
            if (Model.sameString(definition["loadType"], "timed") && entry["targetDurationSec"] == null) {
                return false;
            }
            if (!Model.sameString(definition["loadType"], "timed") && entry["targetRepsMin"] == null) {
                return false;
            }
        }
        return true;
    }

    function exercise(id as String) as Dictionary? {
        if (_exerciseIndex == null) {
            var index = {};
            var list = exercises();
            for (var i = 0; i < list.size(); i++) {
                index[list[i]["id"]] = i;
            }
            _exerciseIndex = index;
        }
        var position = (_exerciseIndex as Dictionary)[id];
        return position instanceof Number ? exercises()[position] as Dictionary : null;
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
        var dictionary = source as Dictionary;
        return dictionary.hasKey(key) ? dictionary[key] : null;
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
        var workout = routineTemplate(config, templateId);
        if (workout == null || !validRoutine(workout as Dictionary) ||
            (workout as Dictionary)["entries"].size() == 0) {
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
            var definition = exerciseForEntry(entry) as Dictionary;
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

            var increment = entry["increment100"] instanceof Number ?
                entry["increment100"] : definition["increment100"];
            var incrementOverride = dictionaryValue(
                incrementOverrides instanceof Dictionary ? incrementOverrides as Dictionary : null,
                definition["id"] as String
            );
            if (isLoadable && !(entry["increment100"] instanceof Number) &&
                Model.inRange(incrementOverride, 25, 10000, false) &&
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
            snapshot["garminCategory"] = entry["garminCategory"];
            snapshot["garminCode"] = entry["garminCode"];
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
        session["fitSegments"] = 0;
        session["exercises"] = sessionExercises;
        session["rest"] = null;
        session["restGeneration"] = 0;
        session["nextSetSequence"] = 1;
        session["lastCompleted"] = null;
        return session;
    }
}
