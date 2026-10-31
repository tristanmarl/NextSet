import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.WatchUi;

class HistoryView extends WatchUi.View {
    private var _sessions as Array;
    private var _selected as Number = 0;
    private var _detail as Boolean = false;
    private var _detailLines as Array = [];
    private var _detailOffset as Number = 0;
    private var _detailVisible as Number = 5;
    private var _detailChars as Number = 0;
    private var _uploads as Dictionary;

    public function initialize() {
        _sessions = getApp().controller().historySessions();
        _uploads = getApp().controller().uploadStatuses();
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
        // One workout per page (UP/DOWN browse, START opens the sets): day name, date with
        // "cancelled" or "partial" only when it applies, sets done big, and the status row.
        var record = _sessions[_selected] as Dictionary;
        var h = height;
        var unavailable = record["unavailable"] == true || !(record["exercises"] instanceof Array);
        UiFormat.drawTitle(dc, unavailable ? "Workout unavailable" :
            shortText(record["templateName"], 30, "Workout"), h * 25 / 100);
        if (unavailable) {
            Icons.backMarker(dc);
            Icons.browseMarkers(dc);
            return;
        }
        var totals = SessionLogic.totals(record);
        var label = statusLabel(record, totals);
        var row = shortDate(record) + (label == null ? "" : " · " + label);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(width / 2, h * 39 / 100, Graphics.FONT_SMALL, row,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        UiFormat.drawBig(dc, [[totals["done"].toString() + "/" + totals["planned"].toString(), "num"],
            ["sets", "unit"]], h * 57 / 100, -1, Graphics.COLOR_WHITE);
        drawStatus(dc, record, h * 79 / 100, caption);
        Icons.startMarker(dc, "play");
        Icons.backMarker(dc);
        if (_sessions.size() > 1) {
            Icons.browseMarkers(dc);
        }
    }

    // Garmin and Liftosaur as check icons when fine; the first problem in words (red) otherwise.
    private function drawStatus(dc as Dc, record as Dictionary, y as Number,
                                font as Graphics.FontType) as Void {
        var fit = record["fitState"];
        var problem = null;
        if (!Model.sameString(fit, "saved") && !Model.sameString(fit, "segment_saved") &&
            !Model.sameString(record["status"], "aborted")) {
            problem = fitStatusLabel(record);
        }
        var state = record["id"] instanceof String ? _uploads[record["id"]] : null;
        if (problem == null && Model.sameString(state, Liftosaur.STATUS_SKIPPED)) {
            problem = "Liftosaur skipped";
        }
        if (problem != null) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, y, font, problem as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            return;
        }
        var s = Icons.unit(dc);
        var parts = Model.sameString(record["status"], "aborted") ? [] : ["Garmin"];
        if (Model.sameString(state, Liftosaur.STATE_DONE) || Model.sameString(state, Liftosaur.STATUS_PENDING)) {
            parts.add("Liftosaur");
        }
        if (parts.size() == 0) {
            return;
        }
        var gap = s * 4;
        var total = 0;
        for (var i = 0; i < parts.size(); i++) {
            total += s * 3 + dc.getTextWidthInPixels(parts[i] as String, font) + (i > 0 ? gap : 0);
        }
        var x = (dc.getWidth() - total) / 2;
        for (var i = 0; i < parts.size(); i++) {
            var pending = Model.sameString(parts[i], "Liftosaur") && Model.sameString(state, Liftosaur.STATUS_PENDING);
            if (pending) {
                Icons.clock(dc, x + s, y, s, Graphics.COLOR_WHITE);
            } else {
                Icons.check(dc, x + s, y, s, Graphics.COLOR_GREEN);
            }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(x + s * 3, y, font, parts[i] as String,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += s * 3 + dc.getTextWidthInPixels(parts[i] as String, font) + gap;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    }

    // Detail page: all lines scroll (workout name, date, sets, then the exercises). The lines are
    // wrapped to what fits the narrowest row of the band, so drawLine never has to cut text.
    private function drawDetail(dc as Dc) as Void {
        var height = dc.getHeight();
        var caption = UiFormat.captionFont();
        var record = _sessions[_selected] as Dictionary;
        var y = height * 20 / 100;
        var footerY = height - 28;
        var rowHeight = dc.getFontHeight(caption) + 4;
        var chars = fitChars(dc, caption, y, footerY - rowHeight);
        if (chars != _detailChars) {
            _detailChars = chars;
            _detailLines = detailLines(record, chars);
        }
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

    // Characters of the caption font that fit the screen circle at both ends of the text band.
    private function fitChars(dc as Dc, font as Graphics.FontType, top as Number,
                              bottom as Number) as Number {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var radius = (width < height ? width : height) / 2 - 12;
        var fontHeight = dc.getFontHeight(font);
        var narrow = width;
        var edges = [top, bottom + fontHeight];
        for (var i = 0; i < 2; i++) {
            var offset = ((edges[i] as Number) - height / 2).abs();
            var remaining = radius * radius - offset * offset;
            var chord = remaining <= 0 ? 0 : (2 * Math.sqrt(remaining) - 16).toNumber();
            if (chord < narrow) {
                narrow = chord;
            }
        }
        var average = dc.getTextWidthInPixels("0123456789abcdefghij", font) / 20;
        var chars = average > 0 ? narrow / average : 20;
        return chars < 12 ? 12 : chars;
    }

    // "cancelled" or "partial", null for a full workout (no word when all is well).
    private function statusLabel(record as Dictionary, totals as Dictionary) as String? {
        if (Model.sameString(record["status"], "aborted")) {
            return "cancelled";
        }
        if (Model.sameString(record["completionKind"], "full") ||
            (totals["planned"] > 0 && totals["done"] == totals["planned"])) {
            return null;
        }
        return "partial";
    }

    private function detailLines(record as Dictionary, chars as Number) as Array {
        var lines = [];
        if (record["unavailable"] == true || !(record["exercises"] instanceof Array)) {
            lines.add("Workout unavailable");
            lines.add("Details unavailable");
            return lines;
        }
        var totals = SessionLogic.totals(record);
        lines.add(shortText(record["templateName"], chars, "Workout"));
        var when = dateAndElapsed(record);
        if (when.length() > 0) {
            lines.add(when);
        }
        lines.add(totals["done"].toString() + "/" + totals["planned"].toString() + " sets");
        if (!Model.sameString(record["fitState"], "saved") && !Model.sameString(record["status"], "aborted")) {
            lines.add(fitStatusLabel(record));
        }
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
            var count = "  " + done.toString() + "/" + planned.toString();
            var name = shortText(exercise["name"], chars - count.length(), "Exercise");
            lines.add(name + count);
            var warmupLine = "";
            var warmups = exercise["warmupSlots"];
            for (var w = 0; warmups instanceof Array && w < (warmups as Array).size(); w++) {
                var warmupDone = (warmups as Array)[w]["completed"];
                if (!(warmupDone instanceof Dictionary)) {
                    continue;
                }
                var entry = "W" + (w + 1).toString() + " " + setValue(exercise, warmupDone as Dictionary);
                if (warmupLine.length() > 0 && warmupLine.length() + entry.length() > chars - 2) {
                    lines.add("  " + warmupLine);
                    warmupLine = entry;
                } else {
                    warmupLine += (warmupLine.length() == 0 ? "" : "  ") + entry;
                }
            }
            if (warmupLine.length() > 0) {
                lines.add("  " + warmupLine);
            }

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
                    valueLine.length() + separator.length() + value.length() > chars - 2) {
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
            return "BW×" + completed["reps"].toString();
        }
        var load = UiFormat.load100(completed["load100"] as Number);
        var unit = exercise["loadUnit"] instanceof String ? exercise["loadUnit"] as String : "kg";
        var assistance = Model.sameString(exercise["loadType"], "assistance") ? " assist" : "";
        return load + unit + assistance + "×" + completed["reps"].toString();
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
            _detailChars = 0;
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

class HistoryDelegate extends KeyDelegate {
    private var _view as HistoryView;

    public function initialize(view as HistoryView) {
        _view = view;
        KeyDelegate.initialize();
    }

    public function onUpKey() as Boolean {
        _view.move(-1);
        return true;
    }

    public function onDownKey() as Boolean {
        _view.move(1);
        return true;
    }

    public function onStartKey() as Boolean {
        _view.select();
        return true;
    }

    public function onBackKey() as Boolean {
        _view.back();
        return true;
    }

    public function onMenuKey() as Boolean {
        _view.back();
        return true;
    }
}
