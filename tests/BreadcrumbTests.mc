import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

(:test)
function testBreadcrumbStepNames(logger as Test.Logger) as Boolean {
    var day = Breadcrumb.format([3, 1, 3, 38, 2]);
    var ok1 = check(logger, day != null && Model.sameString(day, "day reply W1 D3, 38 KB free"),
        "a day reply crumb names week, day and free memory");
    var fit = Breadcrumb.format([11, 0, 0, 120, 1]);
    var ok2 = check(logger, fit != null && Model.sameString(fit, "FIT save, 120 KB free"),
        "a crumb without a day omits W/D");
    var names = true;
    for (var step = 1; step <= 12; step += 1) {
        var text = Breadcrumb.format([step, 0, 0, 10, 0]);
        if (text == null || (text as String).find("step ") != null) {
            names = false;
        }
    }
    var ok3 = check(logger, names, "every step code 1-12 has a name");
    var ok4 = check(logger, Breadcrumb.format([0]) == null && Breadcrumb.format(null) == null &&
        Breadcrumb.format(["x", 1, 1, 1]) == null, "a cleared or malformed crumb formats to null");
    var ok5 = check(logger, Breadcrumb.stepForPurpose(Liftosaur.REQ_SYNC_DAY) == 3 &&
        Breadcrumb.stepForPurpose(Liftosaur.REQ_UPLOAD_FINISH) == 9 &&
        Breadcrumb.stepForPurpose(Liftosaur.REQ_KEY_TEST) == 0, "web purposes map to step codes");
    var ok6 = check(logger, Breadcrumb.versionCode("0.5.0") == 500 && Breadcrumb.versionCode("1.12.3") == 11203,
        "version string becomes a Number");
    var line = Breadcrumb.summaryText("0.5.0", "006-B4315-00", "day reply W1 D3", "W1 D3: bad");
    var ok7 = check(logger, Model.sameString(line,
        "NextSet 0.5.0 006-B4315-00 stop:day reply W1 D3 sync:W1 D3: bad"), "one-line summary");
    return ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7;
}

(:test)
function testBreadcrumbLaunchDetection(logger as Test.Logger) as Boolean {
    Breadcrumb.leave();
    Breadcrumb.clearLast();
    var clean = Breadcrumb.onLaunch(500);
    var ok1 = check(logger, !clean && Breadcrumb.last() == null, "a clean run leaves no crumb.last");
    Breadcrumb.enter(Breadcrumb.STEP_SYNC_DAY, 1, 3);
    var moved = Breadcrumb.onLaunch(500);
    var last = Breadcrumb.last();
    var ok2 = check(logger, moved && last != null && (last as Array).size() == 6 &&
        (last as Array)[0] == 3 && (last as Array)[1] == 1 && (last as Array)[2] == 3 &&
        (last as Array)[5] == 500, "a left-over crumb moves to crumb.last with the version");
    var gone = Application.Storage.getValue(Breadcrumb.KEY) == null;
    var ok3 = check(logger, gone, "crumb is cleared after the move");
    var shown = Breadcrumb.format(last);
    var ok4 = check(logger, shown != null && (shown as String).find("day reply W1 D3") == 0,
        "crumb.last formats for Diagnostics");
    Breadcrumb.enter(Breadcrumb.STEP_FINALIZE, 0, 0);
    Breadcrumb.leave();
    var after = Breadcrumb.onLaunch(500);
    var ok5 = check(logger, !after && Application.Storage.getValue(Breadcrumb.KEY) == null,
        "enter then leave leaves nothing");
    Breadcrumb.clearLast();
    return ok1 && ok2 && ok3 && ok4 && ok5;
}

(:test)
function testBreadcrumbNeverThrows(logger as Test.Logger) as Boolean {
    var threw = false;
    try {
        Breadcrumb.enter(Breadcrumb.STEP_FIT_SAVE, 0, 0);
        Breadcrumb.leave();
        Breadcrumb.leave();
        Breadcrumb.enterForPurpose(null);
        Breadcrumb.onLaunch(0);
        Breadcrumb.at(1, 2);
    } catch (error) {
        threw = true;
    }
    Breadcrumb.leave();
    return check(logger, !threw, "enter, leave and launch handling never throw");
}
