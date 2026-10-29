import Toybox.Lang;
import Toybox.Test;

(:test)
function testRapidPressSpeedsUpOnlyFastRuns(logger as Test.Logger) as Boolean {
    var rapid = new RapidPress();
    var steps = [] as Array<Number>;
    for (var i = 0; i < 9; i++) {
        steps.add(rapid.multiplierAt(1, 1000 + i * 200));
    }
    var slow = rapid.multiplierAt(1, 5000);
    var reverse = rapid.multiplierAt(-1, 5100);
    var ok1 = check(logger, steps[0] == 1 && steps[2] == 1 && steps[3] == 2 && steps[6] == 2,
        "presses 4 to 7 of a fast run move two steps");
    var ok2 = check(logger, steps[7] == 4 && steps[8] == 4, "from the 8th fast press a press moves four steps");
    return ok1 && ok2 && check(logger, slow == 1 && reverse == 1,
        "a pause or a change of direction starts again at one step");
}
