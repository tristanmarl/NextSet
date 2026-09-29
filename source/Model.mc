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
}
