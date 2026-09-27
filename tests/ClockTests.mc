import Toybox.Lang;
import Toybox.Test;

function clockCheck(logger as Test.Logger, condition as Boolean, message as String) as Boolean {
    if (!condition) {
        logger.error(message);
        return false;
    }
    return true;
}

(:test)
function testRestClockDeadlineExpiry(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(4, "upper-row", 1, 100, 60) as Dictionary;
    var before = RestClock.expire(rest, 159);
    var expired = RestClock.expire(rest, 160) as Dictionary;
    return clockCheck(logger, rest["endsAt"] == 160 &&
            RestClock.remaining(rest, 100) == 60 &&
            RestClock.remaining(rest, 159) == 1 &&
            RestClock.remaining(rest, 160) == 0,
            "rest deadline and remaining clamp are wrong") &&
        clockCheck(logger, before == null &&
            Model.sameString(expired["state"], "expired") && expired["alertConsumed"] == true &&
            RestClock.expire(expired, 200) == null &&
            Model.sameString(rest["state"], "running"),
            "expiry must be returned once without mutating its input");
}

(:test)
function testRestClockAdjustSkipAndGeneration(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(8, "upper-row", 0, 100, 1780) as Dictionary;
    var capped = RestClock.adjust(rest, 100, 30);
    var shortRest = RestClock.create(8, "upper-row", 0, 100, 20) as Dictionary;
    var zero = RestClock.adjust(shortRest, 115, -30);
    var zeroExpiry = RestClock.expire(zero, 115) as Dictionary;
    var skipped = RestClock.skip(rest);
    return clockCheck(logger, capped["id"] == 9 && capped["startedAt"] == 100 &&
            capped["endsAt"] == 1900 && capped["durationSec"] == Model.MAX_REST_SEC &&
            RestClock.remaining(capped, 100) == Model.MAX_REST_SEC,
            "positive adjustment must clamp and advance generation") &&
        clockCheck(logger, zero["id"] == 9 && zero["durationSec"] == 0 &&
            Model.sameString(zero["state"], "running") && zero["alertConsumed"] == false &&
            Model.sameString(zeroExpiry["state"], "expired") && zeroExpiry["alertConsumed"] == true,
            "zero adjustment must expire through the next tick") &&
        clockCheck(logger, RestClock.create(1, "upper-row", 0, 100, 0) == null &&
            skipped["id"] == 8 && Model.sameString(skipped["state"], "dismissed") &&
            skipped["alertConsumed"] == true && Model.sameString(rest["state"], "running"),
            "zero-duration create or skip semantics are wrong");
}

(:test)
function testRestClockPauseResume(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(2, "upper-row", 1, 100, 60) as Dictionary;
    var paused = RestClock.pause(rest, 125) as Dictionary;
    var resumed = RestClock.resume(paused, 500) as Dictionary;
    return clockCheck(logger, Model.sameString(paused["state"], "paused") &&
            RestClock.remaining(paused, 300) == 35 && RestClock.pause(paused, 300) == null,
            "paused rest must preserve its remaining duration") &&
        clockCheck(logger, Model.sameString(resumed["state"], "running") &&
            resumed["endsAt"] == 535 && RestClock.remaining(resumed, 500) == 35 &&
            Model.sameString(rest["state"], "running"),
            "resuming rest must restart from its saved remaining duration without mutating source");
}
