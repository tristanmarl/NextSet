import Toybox.Lang;

module RestClock {
    function copy(rest as Dictionary) as Dictionary {
        var result = {};
        var keys = rest.keys();
        for (var i = 0; i < keys.size(); i++) {
            result[keys[i]] = rest[keys[i]];
        }
        return result;
    }

    function create(id as Number, entryId as String, slot as Number,
                    now as Number, durationSec as Number) as Dictionary? {
        if (id < 0 || slot < 0 || durationSec <= 0 || durationSec > Model.MAX_REST_SEC) {
            return null;
        }
        return {
            "id" => id,
            "entryId" => entryId,
            "slot" => slot,
            "startedAt" => now,
            "durationSec" => durationSec,
            "endsAt" => now + durationSec,
            "state" => "running",
            "alertConsumed" => false
        };
    }

    function remaining(rest as Dictionary, now as Number) as Number {
        if (Model.sameString(rest["state"], "paused")) {
            return rest["remainingWhenPausedSec"] as Number;
        }
        if (!Model.sameString(rest["state"], "running")) {
            return 0;
        }
        var left = (rest["endsAt"] as Number) - now;
        var duration = rest["durationSec"] as Number;
        return left < 0 ? 0 : (left > duration ? duration : left);
    }

    // One short warning 10 s before the end of a rest of at least 20 s.
    function preAlertDue(rest as Dictionary, now as Number) as Boolean {
        if (!Model.sameString(rest["state"], "running") ||
            (rest["durationSec"] as Number) < 20) {
            return false;
        }
        var left = remaining(rest, now);
        return left > 0 && left <= 10;
    }

    function pause(rest as Dictionary, now as Number) as Dictionary? {
        if (!Model.sameString(rest["state"], "running")) {
            return null;
        }
        var result = copy(rest);
        result["state"] = "paused";
        result["remainingWhenPausedSec"] = remaining(rest, now);
        result["pausedAt"] = now;
        return result;
    }

    function resume(rest as Dictionary, now as Number) as Dictionary? {
        if (!Model.sameString(rest["state"], "paused") ||
            !(rest["remainingWhenPausedSec"] instanceof Number)) {
            return null;
        }
        var left = rest["remainingWhenPausedSec"] as Number;
        if (left < 0 || left > Model.MAX_REST_SEC) {
            return null;
        }
        var result = copy(rest);
        result["startedAt"] = now;
        result["durationSec"] = left;
        result["endsAt"] = now + left;
        result["remainingWhenPausedSec"] = null;
        result["pausedAt"] = null;
        result["state"] = "running";
        return result;
    }

    function expire(rest as Dictionary, now as Number) as Dictionary? {
        if (!Model.sameString(rest["state"], "running") ||
            rest["alertConsumed"] == true || remaining(rest, now) > 0) {
            return null;
        }
        var result = copy(rest);
        result["state"] = "expired";
        result["alertConsumed"] = true;
        return result;
    }

    function adjust(rest as Dictionary, now as Number, deltaSec as Number) as Dictionary {
        var value = remaining(rest, now) + deltaSec;
        value = value < 0 ? 0 : (value > Model.MAX_REST_SEC ? Model.MAX_REST_SEC : value);
        var result = copy(rest);
        result["id"] = (rest["id"] as Number) + 1;
        result["startedAt"] = now;
        result["durationSec"] = value;
        result["endsAt"] = now + value;
        // A zero adjustment expires on the next tick, preserving the normal commit-before-alert path.
        result["state"] = "running";
        result["alertConsumed"] = false;
        return result;
    }

    function skip(rest as Dictionary) as Dictionary {
        var result = copy(rest);
        result["state"] = "dismissed";
        result["alertConsumed"] = true;
        return result;
    }
}
