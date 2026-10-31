import Toybox.Lang;
import Toybox.Test;

(:test)
function testRestRingFraction(logger as Test.Logger) as Boolean {
    var rest = RestClock.create(1, "a", 0, 100, 60) as Dictionary;
    var full = RestClock.ringFraction(rest, 100);
    var half = RestClock.ringFraction(rest, 130);
    var empty = RestClock.ringFraction(rest, 160);
    var beyond = RestClock.ringFraction(rest, 400);
    var before = RestClock.ringFraction(rest, 50);
    var paused = RestClock.pause(rest, 145) as Dictionary;
    var pausedFraction = RestClock.ringFraction(paused, 9999);
    var expired = RestClock.expire(rest, 170) as Dictionary;
    var over = RestClock.ringFraction(expired, 190);
    var skipped = RestClock.ringFraction(RestClock.skip(rest), 110);
    var okRunning = full == 1.0 && half == 0.5 && empty == 0.0 && beyond == 0.0 && before == 1.0;
    var okOther = pausedFraction == 0.25 && over == 0.0 && skipped == 0.0;
    return clockCheck(logger, okRunning, "running ring fraction must go 1 -> 0 and clamp") &&
        clockCheck(logger, okOther, "paused keeps its fraction; overtime and skipped are 0");
}

(:test)
function testRestRingEndAngle(logger as Test.Logger) as Boolean {
    var top = RestClock.ringEndDegrees(1.0);
    var quarter = RestClock.ringEndDegrees(0.25);
    var half = RestClock.ringEndDegrees(0.5);
    return clockCheck(logger, top == -270 && quarter == 0 && half == -90,
        "ring arc end angle must run clockwise from 12 o'clock");
}
