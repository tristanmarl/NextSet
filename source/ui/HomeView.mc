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
        var caption = UiFormat.captionFont();
        var active = controller.hasActiveSession();
        var routine = !active && _routineIndex >= 0 && _routineIndex < _routines.size() ?
            _routines[_routineIndex] as Dictionary : null;
        var lines = ["NextSet"];
        var fonts = [Graphics.FONT_LARGE];
        var gaps = [6];
        if (active) {
            var session = controller.session() as Dictionary;
            lines.add("WORKOUT ACTIVE");
            fonts.add(Graphics.FONT_SMALL);
            gaps.add(5);
            lines.add(session["templateName"] as String);
            fonts.add(caption);
            gaps.add(8);
        } else if (routine != null) {
            var entries = routine["entries"] as Array;
            var empty = entries.size() == 0;
            var nextId = controller.nextRoutineId();
            lines.add((Model.sameString(routine["id"], nextId) ? "NEXT · " : "") +
                (routine["name"] as String));
            fonts.add(Graphics.FONT_MEDIUM);
            gaps.add(5);
            var totalSets = 0;
            for (var i = 0; i < entries.size(); i++) {
                totalSets += (entries[i] as Dictionary)["workingSetCount"] as Number;
            }
            var summary = entries.size().toString() + " ex · " + totalSets.toString() + " sets";
            lines.add(summary);
            fonts.add(caption);
            gaps.add(8);
            if (empty) {
                lines.add("START: Add an exercise");
                fonts.add(Graphics.FONT_XTINY);
                gaps.add(8);
            }
        } else {
            var keyed = controller.hasKey();
            lines.add(keyed ? "No routines synced" : "No Liftosaur key");
            fonts.add(Graphics.FONT_SMALL);
            gaps.add(8);
            lines.add(keyed ? "START: Sync routines" : "START: Enter key");
            fonts.add(Graphics.FONT_XTINY);
            gaps.add(8);
        }
        if (notice != null) {
            lines.add(notice as String);
            fonts.add(caption);
            gaps.add(0);
        }
        var totalHeight = 0;
        for (var i = 0; i < lines.size(); i++) {
            totalHeight += dc.getFontHeight(fonts[i] as Graphics.FontType) +
                (gaps[i] as Number);
        }
        var y = (dc.getHeight() - totalHeight) / 2;
        for (var i = 0; i < lines.size(); i++) {
            if (notice != null && i == lines.size() - 1) {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            }
            y = UiFormat.drawLine(dc, lines[i] as String, y,
                fonts[i] as Graphics.FontType) + (gaps[i] as Number);
        }
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
        var y = (dc.getHeight() - dc.getFontHeight(Graphics.FONT_MEDIUM)) / 2;
        UiFormat.drawLine(dc, "Starting workout…", y, Graphics.FONT_MEDIUM);
    }
}

class FinishingWorkoutView extends WatchUi.View {
    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var error = getApp().controller().errorMessage();
        var session = getApp().controller().session();
        var cancelling = session != null && Model.sameString((session as Dictionary)["finishOutcome"], "aborted");
        var message = error == null ? (cancelling ? "Cancelling workout…" : "Saving workout…") :
            error as String;
        var y = (dc.getHeight() - dc.getFontHeight(Graphics.FONT_SMALL)) / 2;
        UiFormat.drawLine(dc, message, y, Graphics.FONT_SMALL);
        if (error != null) {
            UiFormat.drawLine(dc, "SELECT TO RETRY", y + dc.getFontHeight(Graphics.FONT_SMALL),
                Graphics.FONT_XTINY);
        }
    }
}

class FinishingWorkoutDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        return true;
    }

    public function onSelect() as Boolean {
        if (getApp().controller().errorMessage() != null) {
            getApp().retryPendingFinalization();
        }
        return true;
    }

    public function onMenu() as Boolean {
        return onSelect();
    }

    public function onBack() as Boolean {
        return true;
    }
}
