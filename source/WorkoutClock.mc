import Toybox.Lang;

// Pure epoch-second accounting. start() fields fit existing session records.
// pause/resume/checkpoint/recover return copies; pause/resume return null for
// invalid transitions. Recovery excludes the active gap since the last saved
// checkpoint once; while explicitly paused, that time is counted by resume.
// Active time excludes pause and recovery gaps; subtract rest time later.
module WorkoutClock {
    function copy(session as Dictionary) as Dictionary {
        var result = {};
        var keys = session.keys();
        for (var i = 0; i < keys.size(); i++) {
            result[keys[i]] = session[keys[i]];
        }
        return result;
    }

    function nonNegative(value as Number) as Number {
        return value < 0 ? 0 : value;
    }

    function eventTime(session as Dictionary, now as Number) as Number {
        var value = now;
        var startedAt = session["startedAt"] as Number;
        if (value < startedAt) {
            value = startedAt;
        }
        if (session["lastCheckpointAt"] instanceof Number &&
            value < (session["lastCheckpointAt"] as Number)) {
            value = session["lastCheckpointAt"] as Number;
        }
        return value;
    }

    function start(now as Number) as Dictionary {
        return {
            "startedAt" => now,
            "pauseStartedAt" => null,
            "pausedSec" => 0,
            "lastCheckpointAt" => now,
            "recoveryGapSec" => 0
        };
    }

    function elapsed(session as Dictionary, now as Number) as Number {
        return nonNegative(now - (session["startedAt"] as Number));
    }

    function active(session as Dictionary, now as Number) as Number {
        var seconds = elapsed(session, now);
        var paused = session["pausedSec"] instanceof Number ?
            session["pausedSec"] as Number : 0;
        var recovery = session["recoveryGapSec"] instanceof Number ?
            session["recoveryGapSec"] as Number : 0;
        if (session["pauseStartedAt"] instanceof Number) {
            paused += nonNegative(now - (session["pauseStartedAt"] as Number));
        }
        return nonNegative(seconds - paused - recovery);
    }

    function pause(session as Dictionary, now as Number) as Dictionary? {
        if (session["pauseStartedAt"] instanceof Number) {
            return null;
        }
        var result = copy(session);
        var at = eventTime(session, now);
        result["pauseStartedAt"] = at;
        result["lastCheckpointAt"] = at;
        return result;
    }

    function resume(session as Dictionary, now as Number) as Dictionary? {
        if (!(session["pauseStartedAt"] instanceof Number)) {
            return null;
        }
        var result = copy(session);
        var at = eventTime(session, now);
        var pauseStartedAt = session["pauseStartedAt"] as Number;
        var paused = session["pausedSec"] instanceof Number ?
            session["pausedSec"] as Number : 0;
        result["pausedSec"] = paused + nonNegative(at - pauseStartedAt);
        result["pauseStartedAt"] = null;
        result["lastCheckpointAt"] = at;
        return result;
    }

    function checkpoint(session as Dictionary, now as Number) as Dictionary {
        var result = copy(session);
        result["lastCheckpointAt"] = eventTime(session, now);
        return result;
    }

    function recover(session as Dictionary, now as Number) as Dictionary {
        var result = copy(session);
        var at = eventTime(session, now);
        var gap = 0;
        if (!(session["pauseStartedAt"] instanceof Number) &&
            session["lastCheckpointAt"] instanceof Number) {
            gap = nonNegative(at - (session["lastCheckpointAt"] as Number));
        }
        var recovery = session["recoveryGapSec"] instanceof Number ?
            session["recoveryGapSec"] as Number : 0;
        result["recoveryGapSec"] = recovery + gap;
        result["lastCheckpointAt"] = at;
        return result;
    }
}
