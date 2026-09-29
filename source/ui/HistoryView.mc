import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class HistoryView extends WatchUi.View {
    private var _sessions as Array;
    private var _selected as Number = 0;
    private var _detail as Boolean = false;
    private var _detailLines as Array = [];
    private var _detailOffset as Number = 0;
    private var _detailVisible as Number = 5;

    public function initialize() {
        _sessions = getApp().controller().historySessions();
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_detail) {
            drawDetail(dc);
        } else {
            drawList(dc);
        }
    }

    private function drawList(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var caption = UiFormat.captionFont();
        if (_sessions.size() == 0) {
            UiFormat.drawLine(dc, "No saved workouts", height / 2 - 30, Graphics.FONT_SMALL);
            return;
        }
        if (_selected >= _sessions.size()) {
            _selected = _sessions.size() - 1;
        }
        var y = UiFormat.drawLine(dc, "HISTORY  " + (_selected + 1).toString() + "/" +
            _sessions.size().toString(), 40, Graphics.FONT_XTINY) + 12;
        var footerY = height - 28;
        var rowHeight = dc.getFontHeight(Graphics.FONT_XTINY) + dc.getFontHeight(caption) + 8;
        var visible = (footerY - y) / rowHeight;
        if (visible < 1) {
            visible = 1;
        }
        var first = _selected >= visible ? _selected - visible + 1 : 0;
        for (var i = first; i < _sessions.size() && i < first + visible; i++) {
            var record = _sessions[i] as Dictionary;
            var selected = i == _selected;
            if (selected) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.fillRectangle(32, y, width - 64, rowHeight - 8);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            }
            var title = record["unavailable"] == true ? "Workout unavailable" :
                shortText(record["templateName"], 30, "Workout");
            var detailY = UiFormat.drawLine(dc, title, y, Graphics.FONT_XTINY);
            UiFormat.drawLine(dc, listSummary(record), detailY, caption);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            y += rowHeight;
        }
    }

    private function drawDetail(dc as Dc) as Void {
        var height = dc.getHeight();
        var caption = UiFormat.captionFont();
        var record = _sessions[_selected] as Dictionary;
        var unavailable = record["unavailable"] == true || !(record["exercises"] instanceof Array);
        var title = unavailable ? "Workout unavailable" :
            shortText(record["templateName"], 30, "Workout");
        var y = UiFormat.drawLine(dc, "HISTORY  " + (_selected + 1).toString() + "/" +
            _sessions.size().toString(), 36, caption) + 4;
        y = UiFormat.drawLine(dc, title, y, Graphics.FONT_XTINY) + 4;
        if (!unavailable) {
            var totals = SessionLogic.totals(record);
            y = UiFormat.drawLine(dc, statusLabel(record, totals) + "  " +
                totals["done"].toString() + "/" + totals["planned"].toString() + " sets",
                y, caption) + 4;
            y = UiFormat.drawLine(dc, dateAndElapsed(record), y, caption) + 10;
        }
        var footerY = height - 28;
        var rowHeight = dc.getFontHeight(caption) + 4;
        _detailVisible = (footerY - y) / rowHeight;
        if (_detailVisible < 1) {
            _detailVisible = 1;
        }
        var maxOffset = _detailLines.size() > _detailVisible ?
            _detailLines.size() - _detailVisible : 0;
        if (_detailOffset > maxOffset) {
            _detailOffset = maxOffset;
        }
        var end = _detailOffset + _detailVisible;
        if (end > _detailLines.size()) {
            end = _detailLines.size();
        }
        for (var i = _detailOffset; i < end; i++) {
            y = UiFormat.drawLine(dc, _detailLines[i] as String, y, caption) + 4;
        }
    }

    private function listSummary(record as Dictionary) as String {
        if (record["unavailable"] == true || !(record["exercises"] instanceof Array)) {
            var seq = record["sessionSeq"] instanceof Number ?
                "#" + record["sessionSeq"].toString() : "";
            return "Unavailable  " + seq;
        }
        var totals = SessionLogic.totals(record);
        return statusLabel(record, totals) + "  " + totals["done"].toString() + "/" +
            totals["planned"].toString() + " sets  " + shortDate(record);
    }

    private function statusLabel(record as Dictionary, totals as Dictionary) as String {
        if (Model.sameString(record["status"], "aborted")) {
            return "CANCELLED";
        }
        if (Model.sameString(record["completionKind"], "full") ||
            (totals["planned"] > 0 && totals["done"] == totals["planned"])) {
            return "FULL";
        }
        return "PARTIAL";
    }

    private function detailLines(record as Dictionary) as Array {
        var lines = [];
        if (record["unavailable"] == true || !(record["exercises"] instanceof Array)) {
            lines.add("Saved workout details unavailable");
            return lines;
        }
        lines.add(fitStatusLabel(record));
        if (record["fitSegments"] instanceof Number && record["fitSegments"] > 1) {
            lines.add(record["fitSegments"].toString() + " Garmin activities saved");
        }
        if (record["fitUnknownSegments"] instanceof Number &&
            record["fitUnknownSegments"] > 0) {
            lines.add("One Garmin part unknown");
        }
        var exercises = record["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            var slots = exercise["slots"] as Array;
            var done = SessionLogic.completedCount(exercise);
            var planned = exercise["plannedSetCount"] as Number;
            var name = shortText(exercise["name"], 28, "Exercise");
            lines.add(name + "  " + done.toString() + "/" + planned.toString());

            var valueLine = "";
            var found = false;
            for (var slotIndex = 0; slotIndex < slots.size(); slotIndex++) {
                var completed = slots[slotIndex]["completed"];
                if (!(completed instanceof Dictionary)) {
                    continue;
                }
                found = true;
                var value = setValue(exercise, completed as Dictionary);
                var separator = valueLine.length() == 0 ? "" : "  ";
                if (valueLine.length() > 0 &&
                    valueLine.length() + separator.length() + value.length() > 34) {
                    lines.add("  " + valueLine);
                    valueLine = value;
                } else {
                    valueLine += separator + value;
                }
            }
            if (valueLine.length() > 0) {
                lines.add("  " + valueLine);
            } else if (!found) {
                lines.add("  No sets logged");
            }
        }
        if (lines.size() == 0) {
            lines.add("No exercise details");
        }
        return lines;
    }

    private function fitStatusLabel(record as Dictionary) as String {
        var state = record["fitState"];
        if (Model.sameString(state, "saved")) {
            return "Garmin activity saved";
        }
        if (Model.sameString(state, "failed")) {
            return "Garmin activity failed";
        }
        if (Model.sameString(state, "unknown")) {
            return "Garmin activity unknown";
        }
        if (Model.sameString(state, "discarded") ||
            Model.sameString(state, "discard_failed")) {
            return "Garmin activity not saved";
        }
        return "Garmin status unavailable";
    }

    private function setValue(exercise as Dictionary, completed as Dictionary) as String {
        if (Model.sameString(exercise["loadType"], "timed")) {
            return completed["durationSec"].toString() + "s";
        }
        if (Model.sameString(exercise["loadType"], "bodyweight")) {
            return "BWx" + completed["reps"].toString();
        }
        var load = UiFormat.load100(completed["load100"] as Number);
        var unit = exercise["loadUnit"] instanceof String ? exercise["loadUnit"] as String : "kg";
        var assistance = Model.sameString(exercise["loadType"], "assistance") ? " assist" : "";
        return load + unit + assistance + "x" + completed["reps"].toString();
    }

    private function dateAndElapsed(record as Dictionary) as String {
        var date = shortDate(record);
        var elapsed = record["elapsedSec"];
        if (!(elapsed instanceof Number) || elapsed < 0) {
            return date;
        }
        var minutes = (elapsed as Number) / 60;
        var duration = minutes >= 60 ? (minutes / 60).toString() + "h " +
            (minutes % 60).toString() + "m" : minutes.toString() + "m";
        return date.length() == 0 ? duration : date + "  " + duration;
    }

    private function shortDate(record as Dictionary) as String {
        var endedAt = record["endedAt"];
        if (!(endedAt instanceof Number)) {
            return "";
        }
        var date = Time.Gregorian.info(new Time.Moment(endedAt as Number), Time.FORMAT_SHORT);
        var month = date.month instanceof String ? date.month as String :
            date.month.toString();
        return date.day.toString() + " " + month + " " +
            date.hour.toString() + ":" + twoDigits(date.min);
    }

    private function twoDigits(value as Number) as String {
        return value < 10 ? "0" + value.toString() : value.toString();
    }

    private function shortText(value as Object?, max as Number, fallback as String) as String {
        if (!(value instanceof String) || (value as String).length() == 0) {
            return fallback;
        }
        var text = value as String;
        return text.length() > max ? text.substring(0, max - 2) + ".." : text;
    }

    public function move(direction as Number) as Void {
        if (_detail) {
            var maxOffset = _detailLines.size() > _detailVisible ?
                _detailLines.size() - _detailVisible : 0;
            _detailOffset += direction;
            if (_detailOffset < 0) {
                _detailOffset = 0;
            } else if (_detailOffset > maxOffset) {
                _detailOffset = maxOffset;
            }
        } else if (_sessions.size() > 0) {
            _selected = (_selected + direction + _sessions.size()) % _sessions.size();
        }
        WatchUi.requestUpdate();
    }

    public function select() as Void {
        if (_sessions.size() == 0) {
            return;
        }
        if (_detail) {
            _detail = false;
            _detailOffset = 0;
        } else {
            _detailLines = detailLines(_sessions[_selected] as Dictionary);
            _detail = true;
            _detailOffset = 0;
        }
        WatchUi.requestUpdate();
    }

    public function back() as Void {
        if (_detail) {
            _detail = false;
            _detailOffset = 0;
            WatchUi.requestUpdate();
        } else {
            Navigator.home();
        }
    }
}

class HistoryDelegate extends WatchUi.BehaviorDelegate {
    private var _view as HistoryView;

    public function initialize(view as HistoryView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_UP) {
            _view.move(-1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.move(1);
            return true;
        }
        if (key == KEY_ENTER) {
            _view.select();
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        _view.select();
        return true;
    }

    public function onBack() as Boolean {
        _view.back();
        return true;
    }

    public function onMenu() as Boolean {
        _view.back();
        return true;
    }
}
