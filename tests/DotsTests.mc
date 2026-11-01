import Toybox.Lang;
import Toybox.Test;

(:test)
function testDotsOrderAndStates(logger as Test.Logger) as Boolean {
    // 2 warmups (1 done, the second up next), 3 working sets.
    var warmupNext = DotsLogic.kinds(2, 1, 3, 0, Model.WARMUP_BASE + 1);
    var sizeOk = warmupNext.size() == 5;
    var first = warmupNext[0] == DotsLogic.WARM_DONE && warmupNext[1] == DotsLogic.WARM_CURRENT;
    var rest = warmupNext[2] == DotsLogic.SET_OPEN && warmupNext[3] == DotsLogic.SET_OPEN &&
        warmupNext[4] == DotsLogic.SET_OPEN;
    // Warmups done, second working set up next.
    var working = DotsLogic.kinds(2, 2, 3, 1, 1);
    var workFirst = working[0] == DotsLogic.WARM_DONE && working[1] == DotsLogic.WARM_DONE;
    var workRest = working[2] == DotsLogic.SET_DONE && working[3] == DotsLogic.SET_CURRENT &&
        working[4] == DotsLogic.SET_OPEN;
    // No warmups: only working dots; everything done: no current dot.
    var plain = DotsLogic.kinds(0, 0, 7, 7, -1);
    var allDone = true;
    for (var i = 0; i < plain.size(); i++) {
        allDone = allDone && plain[i] == DotsLogic.SET_DONE;
    }
    return check(logger, sizeOk && first && rest, "warmup dots come first and the next warmup is current") &&
        check(logger, workFirst && workRest, "working dots follow the warmups") &&
        check(logger, plain.size() == 7 && allDone, "seven sets are seven dots, never a counter");
}

(:test)
function testDotsLayoutFits(logger as Test.Logger) as Boolean {
    // Roomy: full size, warmups smaller than working dots, gap of one radius.
    var roomy = DotsLogic.layout(1, 3, 300, 8);
    var full = roomy["radius"] == 8 && roomy["gap"] == 8;
    var smaller = (roomy["warmRadius"] as Number) < (roomy["radius"] as Number);
    // 4 warmups + 10 sets on a 142 px row (fenix7s): it fits, dots do not touch.
    var tight = DotsLogic.layout(4, 10, 142, 8);
    var fits = (tight["width"] as Number) <= 142;
    var apart = (tight["gap"] as Number) >= DotsLogic.MIN_GAP;
    var shrunk = (tight["radius"] as Number) < 8;
    var small = (tight["warmRadius"] as Number) < (tight["radius"] as Number);
    // Medium row: the gap shrinks before the dots do.
    var medium = DotsLogic.layout(0, 8, 8 * 16 + 7 * 5, 8);
    var gapFirst = medium["radius"] == 8 && (medium["gap"] as Number) < 8 &&
        (medium["gap"] as Number) >= DotsLogic.MIN_GAP;
    var one = DotsLogic.layout(0, 1, 100, 8);
    return check(logger, full && smaller, "a short row keeps full size and smaller warmup dots") &&
        check(logger, fits && apart, "4 warmups + 10 sets fit 142 px with a visible gap") &&
        check(logger, shrunk && small, "a long row shrinks its dots, warmups stay smaller") &&
        check(logger, gapFirst, "the gap shrinks before the dots") &&
        check(logger, (one["width"] as Number) == 16, "one dot is one diameter wide");
}

(:test)
function testDotsLayoutExtremes(logger as Test.Logger) as Boolean {
    // 4 warmups + 10 sets at 240 px with the room a round fenix7s leaves, and with no room at
    // all: every radius stays >= 2, the gap >= 1 and the row never has a negative width.
    var cases = [[4, 10, 142], [4, 10, 0], [4, 10, -20], [0, 1, 0], [4, 12, 60]];
    var sane = true;
    for (var i = 0; i < cases.size(); i++) {
        var c = cases[i] as Array<Number>;
        var box = DotsLogic.layout(c[0], c[1], c[2], 8);
        var radius = box["radius"] as Number;
        var small = box["warmRadius"] as Number;
        var gap = box["gap"] as Number;
        var width = box["width"] as Number;
        var ok = radius >= 2 && small >= 2 && gap >= 1 && width >= 0 && small <= radius;
        sane = sane && ok;
    }
    var fit = DotsLogic.layout(4, 10, 142, 8);
    return check(logger, sane, "extreme rows keep radius >= 2, gap >= 1, width >= 0") &&
        check(logger, (fit["width"] as Number) <= 142, "4 warmups + 10 sets fit at 240 px");
}
