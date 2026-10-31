import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class HomeView extends WatchUi.View {
    private var _routineIndex as Number = 0;
    private var _routines as Array = [];

    public function initialize() {
        View.initialize();
    }

    // Also refresh on updates: async routine sync can complete while Home stays visible.
    public function onShow() as Void {
        refreshRoutines();
    }

    private function refreshRoutines() as Void {
        var controller = getApp().controller();
        var selected = _routineIndex >= 0 && _routineIndex < _routines.size() ?
            _routines[_routineIndex] as Dictionary : null;
        var selectedWeek = selected != null ? selected["week"] : null;
        var selectedDay = selected != null ? selected["dayInWeek"] : null;
        _routines = controller.routineTemplates();
        if (_routines.size() == 0) {
            _routineIndex = -1;
        } else {
            _routineIndex = -1;
            if (selectedWeek instanceof Number && selectedDay instanceof Number) {
                for (var i = 0; i < _routines.size(); i++) {
                    var routine = _routines[i] as Dictionary;
                    if (routine["week"] == selectedWeek && routine["dayInWeek"] == selectedDay) {
                        _routineIndex = i;
                        break;
                    }
                }
            }
            if (_routineIndex < 0) {
                var nextId = controller.nextRoutineId();
                for (var i = 0; i < _routines.size(); i++) {
                    if (Model.sameString((_routines[i] as Dictionary)["id"], nextId)) {
                        _routineIndex = i;
                        break;
                    }
                }
            }
            if (_routineIndex < 0) {
                _routineIndex = 0;
            }
        }
    }

    public function onUpdate(dc as Dc) as Void {
        refreshRoutines();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var controller = getApp().controller();
        var notice = getHomeNotice();
        var active = controller.hasActiveSession();
        var routine = !active && _routineIndex >= 0 && _routineIndex < _routines.size() ?
            _routines[_routineIndex] as Dictionary : null;
        // Day name on top, then its state; first-run hints only while nothing is set up.
        var h = dc.getHeight();
        var title = null;
        var tag = null;
        var tagColor = Graphics.COLOR_GREEN;
        var hint = null;
        if (active) {
            var session = controller.session() as Dictionary;
            title = session["templateName"] as String;
            var totals = SessionLogic.totals(session);
            tag = totals["done"].toString() + "/" + totals["planned"].toString() + " sets";
        } else if (routine != null) {
            title = routine["name"] as String;
            if (Model.sameString(routine["id"], controller.nextRoutineId())) {
                tag = "Next";
            }
            if ((routine["entries"] as Array).size() == 0) {
                hint = "START: Add an exercise";
            }
        } else {
            var keyed = controller.hasKey();
            title = keyed ? "No routines" : "No Liftosaur key";
            hint = keyed ? "START: Sync routines" : "START: Enter key";
        }
        UiFormat.drawTitle(dc, title as String, h * 38 / 100);
        if (tag != null) {
            dc.setColor(tagColor, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, h * 56 / 100, Graphics.FONT_SMALL, tag as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        var bottom = notice != null ? notice : hint;
        if (bottom != null) {
            dc.setColor(notice != null && controller.errorCode() != Err.NONE ? Graphics.COLOR_RED :
                Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, h * 74 / 100, UiFormat.captionFont(), bottom as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        // Keys are marked with drawn icons: START = open/resume, UP/DOWN = pick a day, hold UP = menu.
        Icons.startMarker(dc, "play");
        if (routine != null && _routines.size() > 1) {
            Icons.browseMarkers(dc);
        }
        Icons.menuMarker(dc);
    }

    private function getHomeNotice() as String? {
        var controller = getApp().controller();
        var code = controller.errorCode();
        var activity = controller.activityLabel();
        if (activity != null) {
            return activity;
        }
        var short = Err.shortMessage(code);
        if (short != null) {
            return short;
        }
        if (code == Err.NONE && controller.infoNotice() != null) {
            return controller.infoNotice();
        }
        var pending = controller.pendingUploadCount();
        if (pending > 0) {
            return "Upload " + pending.toString() + " pending";
        }
        return controller.errorMessage() == null ? null : "Check workout status";
    }

    public function moveRoutine(direction as Number) as Void {
        var count = _routines.size();
        if (count > 0) {
            _routineIndex = (_routineIndex + direction + count) % count;
            WatchUi.requestUpdate();
        }
    }

    public function selectedTemplateId() as String? {
        return _routineIndex >= 0 && _routineIndex < _routines.size() ?
            (_routines[_routineIndex] as Dictionary)["id"] as String : null;
    }
}

class StartingWorkoutView extends WatchUi.View {
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        UiFormat.drawTitle(dc, "Starting…", dc.getHeight() / 2);
    }
}

class FinishingWorkoutView extends WatchUi.View {
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var error = getApp().controller().errorMessage();
        var session = getApp().controller().session();
        var cancelling = session != null && Model.sameString((session as Dictionary)["finishOutcome"], "aborted");
        var message = error == null ? (cancelling ? "Cancelling…" : "Saving…") : error as String;
        // Wraps instead of cutting; with an error a retry hint sits below.
        var h = dc.getHeight();
        UiFormat.drawTitle(dc, message, error == null ? h / 2 : h * 42 / 100);
        if (error != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, h * 66 / 100, UiFormat.captionFont(), "START: retry",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            Icons.startMarker(dc, "play");
        }
    }
}

// Consumes every key and touch while a workout starts or saves. After a failed save START (or
// hold UP) retries; this was only reachable by a tap before.
class FinishingWorkoutDelegate extends KeyDelegate {
    public function initialize() {
        KeyDelegate.initialize();
    }

    public function onStartKey() as Boolean {
        if (getApp().controller().errorMessage() != null) {
            getApp().retryPendingFinalization();
        }
        return true;
    }

    public function onMenuKey() as Boolean {
        return onStartKey();
    }
}
