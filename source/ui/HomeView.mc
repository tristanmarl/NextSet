import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class HomeView extends WatchUi.View {
    private var _routineIndex as Number = 0;
    private var _routines as Array = [];
    private var _lastDone as Dictionary = {};

    public function initialize() {
        View.initialize();
    }

    // Also runs when a menu or the routine editor closes, so routine changes show up.
    public function onShow() as Void {
        reload();
    }

    private function reload() as Void {
        _lastDone = {};
        loadLastDone();
        _routines = getApp().controller().routineTemplates();
        if (_routines.size() == 0) {
            _routineIndex = -1;
        } else if (_routineIndex < 0 || _routineIndex >= _routines.size()) {
            _routineIndex = 0;
        }
    }

    // Newest completed session per routine, from history envelopes only (cheap, once per view).
    private function loadLastDone() as Void {
        for (var i = 0; i < 4; i++) {
            var record = getApp().controller().peekHistory(i);
            if (record != null && Model.sameString(record["status"], "completed") &&
                record["templateId"] instanceof String && record["endedAt"] instanceof Number) {
                var previous = _lastDone[record["templateId"]];
                if (!(previous instanceof Number) || previous < record["endedAt"]) {
                    _lastDone[record["templateId"]] = record["endedAt"];
                }
            }
        }
    }

    private function lastDoneLabel(templateId as String) as String? {
        var endedAt = _lastDone[templateId];
        if (!(endedAt instanceof Number)) {
            return null;
        }
        var now = Time.now().value();
        var info = Gregorian.info(new Time.Moment(endedAt), Time.FORMAT_MEDIUM);
        if (now < endedAt || now - endedAt >= 6 * 86400) {
            return "last " + info.month.toString() + " " + info.day.toString();
        }
        return "last " + info.day_of_week.toString();
    }

    public function onUpdate(dc as Dc) as Void {
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
            lines.add("START: Resume");
            fonts.add(Graphics.FONT_XTINY);
            gaps.add(8);
        } else if (routine != null) {
            var entries = routine["entries"] as Array;
            var empty = entries.size() == 0;
            lines.add(routine["name"] as String);
            fonts.add(Graphics.FONT_MEDIUM);
            gaps.add(5);
            var totalSets = 0;
            for (var i = 0; i < entries.size(); i++) {
                totalSets += (entries[i] as Dictionary)["workingSetCount"] as Number;
            }
            var summary = entries.size().toString() + " ex · " + totalSets.toString() + " sets";
            var last = lastDoneLabel(routine["id"] as String);
            lines.add(last == null ? summary : summary + " · " + last);
            fonts.add(caption);
            gaps.add(8);
            lines.add(empty ? "START: Add an exercise" : "UP/DOWN select · START begin");
            fonts.add(Graphics.FONT_XTINY);
            gaps.add(8);
        } else {
            lines.add("Workout unavailable");
            fonts.add(Graphics.FONT_SMALL);
            gaps.add(8);
        }
        lines.add(active ? "MENU: Menu" : "MENU: History/Edit");
        fonts.add(caption);
        gaps.add(notice == null ? 0 : 4);
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
    }

    private function getHomeNotice() as String? {
        var error = getApp().controller().errorMessage();
        var code = getApp().controller().errorCode();
        if (code == Err.RECOVERED_EARLIER_CHECKPOINT) {
            return "Recovered checkpoint";
        }
        if (code == Err.RECOVERY_SAVE_FAILED ||
            code == Err.TIMED_SET_RECOVERY_FAILED) {
            return "Recovery save failed";
        }
        if (code == Err.SAVE_FAILED_RETRY_BEFORE_CONTINUING) {
            return "Save failed. Retry";
        }
        if (code == Err.SAVED_WORKOUT_IS_DAMAGED) {
            return "Workout data damaged";
        }
        if (code == Err.SAVED_SETTINGS_ARE_DAMAGED) {
            return "Settings data damaged";
        }
        if (code == Err.UPDATE_APP_TO_RESUME) {
            return "Update app to resume";
        }
        if (code == Err.ROUTINE_NOT_FOUND) {
            return "Routine not found";
        }
        if (code == Err.WORKOUT_CANNOT_START) {
            return "Workout cannot start";
        }
        if (code == Err.COULD_NOT_RESERVE_WORKOUT_ID) {
            return "Could not start workout";
        }
        if (code == Err.WORKOUT_COULD_NOT_BE_CREATED) {
            return "Workout creation failed";
        }
        if (code == Err.ACTIVITY_RECORDING_FAILED_TO_START) {
            return "Recording failed to start";
        }
        if (code == Err.ACTIVITY_DISCARD_FAILED) {
            return "Recording cleanup failed";
        }
        if (code == Err.HISTORY_SAVE_FAILED) {
            return "History save failed";
        }
        if (code == Err.PREVIOUS_PERFORMANCE_SAVE_FAILED) {
            return "Last time save failed";
        }
        if (code == Err.WORKOUT_ARCHIVE_SAVED_RETRY_FINISH) {
            return "Retry to finish";
        }
        if (code == Err.LOG_A_SET_BEFORE_SAVING) {
            return "Log one set first";
        }
        if (code == Err.HISTORY_NEEDS_NEWER_APP) {
            return "Update app to save history";
        }
        return error == null ? null : "Check workout status";
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
        var message = error == null ? "Saving workout…" : error as String;
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
