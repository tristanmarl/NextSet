import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class ExerciseView extends WatchUi.View {
    private var _entryId as String;
    private var _message as String? = null;
    private var _loadTapLeft as Number = -1;
    private var _loadTapRight as Number = -1;
    private var _loadTapTop as Number = -1;
    private var _loadTapBottom as Number = -1;

    public function initialize(entryId as String) {
        _entryId = entryId;
        View.initialize();
    }

    public function entryId() as String {
        return _entryId;
    }

    public function showMessage(message as String) as Void {
        _message = message.length() == 0 ? null : message;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
        _loadTapLeft = -1;
        _loadTapRight = -1;
        _loadTapTop = -1;
        _loadTapBottom = -1;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM,
                "No active workout", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM,
                "Exercise unavailable", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var current = exercise as Dictionary;
        var slot = SessionLogic.nextSlot(current);
        var planned = current["plannedSetCount"] as Number;
        var loadType = current["loadType"] as String;
        var tappableLoad = Model.sameString(loadType, "weight") ||
            Model.sameString(loadType, "assistance");
        var caption = UiFormat.captionFont();
        var titleFont = Graphics.FONT_MEDIUM;
        var name = current["name"] as String;
        var titleLines = UiFormat.wrapTitle(dc, name, titleFont,
            dc.getWidth() * 0.72);
        if (titleLines.size() == 1 && !Model.sameString(titleLines[0], name)) {
            titleFont = Graphics.FONT_SMALL;
            titleLines = UiFormat.wrapTitle(dc, name, titleFont, dc.getWidth() * 0.62);
            if (titleLines.size() == 1 && !Model.sameString(titleLines[0], name)) {
                titleFont = Graphics.FONT_XTINY;
                titleLines = UiFormat.wrapTitle(dc, name, titleFont, dc.getWidth() * 0.62);
            }
        }
        var titleHeight = dc.getFontHeight(titleFont);
        var setFont = Graphics.FONT_SMALL;
        var setHeight = dc.getFontHeight(setFont);
        var valueFont = Graphics.FONT_MEDIUM;
        var valueHeight = dc.getFontHeight(valueFont);
        var mainHeight = titleLines.size() * titleHeight + 5 + setHeight + 8 + valueHeight;
        // A started set shows its elapsed time where the rest countdown would be (starting a set
        // ends rest), which also hides the lower-priority lines.
        var restStatus = slot < 0 ? null : UiFormat.setStatus(session as Dictionary, _entryId);
        if (restStatus == null && slot >= 0) {
            restStatus = UiFormat.restStatus(session as Dictionary);
        }
        var nextUp = restStatus == null || UiFormat.setStatus(session as Dictionary, _entryId) != null ?
            null : UiFormat.nextUpLine(session as Dictionary);
        var last = slot < 0 || restStatus != null ? null : UiFormat.lastLine(current, slot);
        var warmups = slot < 0 || restStatus != null ? null : UiFormat.warmupsLine(current);
        // Target is lowest priority: only shown when notes and messages leave room.
        var target = slot < 0 || restStatus != null || _message != null ||
            current["notes"] instanceof String || warmups != null ? null :
            UiFormat.targetLine(current, slot);
        if (slot < 0) {
            mainHeight = titleLines.size() * titleHeight + 8 + dc.getFontHeight(Graphics.FONT_SMALL) +
                4 + dc.getFontHeight(Graphics.FONT_SMALL);
        } else {
            mainHeight += 8 + dc.getFontHeight(caption);
            if (restStatus != null) {
                mainHeight += dc.getFontHeight(Graphics.FONT_SMALL) + 3;
                if (nextUp != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
            } else {
                if (last != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
                if (target != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
                if (current["notes"] instanceof String) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                } else if (warmups != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
                if (_message != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
            }
        }
        var y = (dc.getHeight() - mainHeight) / 2;
        for (var i = 0; i < titleLines.size(); i++) {
            y = UiFormat.drawLine(dc, titleLines[i] as String, y, titleFont) + 1;
        }
        if (slot < 0) {
            y += 7;
            y = UiFormat.drawLine(dc, current["closedEarly"] ? "Finished early" :
                "Complete", y, Graphics.FONT_SMALL) + 4;
            UiFormat.drawLine(dc, UiFormat.progress(current), y, Graphics.FONT_SMALL);
            return;
        }

        y += 4;
        var range = UiFormat.repRange(current, slot);
        y = UiFormat.drawLine(dc, "Set " + (slot + 1).toString() + "/" +
            planned.toString() + (range == null ? "" : " · " + range), y, setFont) + 7;
        var value = exerciseLine(session as Dictionary, current, slot);
        var valueY = y;
        var visibleValue = UiFormat.safeText(dc, value, valueY, valueFont);
        if (!Model.sameString(visibleValue, value)) {
            valueFont = Graphics.FONT_SMALL;
            valueHeight = dc.getFontHeight(valueFont);
            visibleValue = UiFormat.safeText(dc, value, valueY, valueFont);
        }
        var valueWidth = dc.getTextWidthInPixels(visibleValue, valueFont);
        var lineLeft = (dc.getWidth() - valueWidth) / 2;
        var tapLoadWidth = 0;
        if (tappableLoad) {
            var draft = ((current["slots"] as Array)[slot] as Dictionary)["draft"] as Dictionary;
            var loadLabel = UiFormat.load100(draft["load100"] as Number) + " kg";
            if (Model.sameString(loadType, "assistance")) {
                loadLabel += " assist";
            }
            tapLoadWidth = dc.getTextWidthInPixels(loadLabel, valueFont);
            _loadTapLeft = lineLeft - 10;
            _loadTapRight = lineLeft + tapLoadWidth + 10;
            _loadTapTop = valueY - 3;
            _loadTapBottom = valueY + valueHeight + 3;
        }
        y = UiFormat.drawLine(dc, value, valueY, valueFont) + 6;
        if (tappableLoad) {
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
            dc.drawLine(lineLeft, valueY + valueHeight - 2, lineLeft + tapLoadWidth,
                valueY + valueHeight - 2);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        }

        if (restStatus != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            y = UiFormat.drawLine(dc, restStatus as String, y, Graphics.FONT_SMALL) + 3;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            if (nextUp != null) {
                y = UiFormat.drawLine(dc, nextUp as String, y, caption) + 2;
            }
        }
        if (last != null) {
            y = UiFormat.drawLine(dc, last as String, y, caption) + 2;
        }
        if (target != null) {
            y = UiFormat.drawLine(dc, target as String, y, caption) + 2;
        }
        if (restStatus == null && current["notes"] instanceof String) {
            y = UiFormat.drawLine(dc, current["notes"] as String, y, caption) + 2;
        } else if (restStatus == null && warmups != null) {
            y = UiFormat.drawLine(dc, warmups as String, y, caption) + 2;
        }
        if (restStatus == null && _message != null) {
            y = UiFormat.drawLine(dc, _message as String, y, caption) + 2;
        }

        var timed = Model.sameString(loadType, "timed");
        var run = (session as Dictionary)["timedRun"];
        var isRunning = run instanceof Dictionary &&
            Model.sameString(run["entryId"], _entryId) && run["slot"] == slot;
        var draft = ((current["slots"] as Array)[slot] as Dictionary)["draft"] as Dictionary;
        var measured = draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0;
        var manuallyEdited = draft["durationEdited"] == true;
        var setRunning = !timed && SessionLogic.setRunMatches(session as Dictionary, _entryId, slot);
        var cue = timed ? (isRunning ? "START finish" :
            (measured ? "START resume" :
            (manuallyEdited ? "START log" : "START begin"))) :
            (setRunning ? "UP/DOWN reps · START log" : "UP/DOWN reps · START set");
        UiFormat.drawLine(dc, cue, y + 2, caption);
    }

    public function tapLoadAt(x as Number, y as Number) as Boolean {
        if (_loadTapLeft < 0 || x < _loadTapLeft || x > _loadTapRight ||
            y < _loadTapTop || y > _loadTapBottom) {
            return false;
        }
        var session = getApp().controller().session();
        if (session == null) {
            return false;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            return false;
        }
        var current = exercise as Dictionary;
        var slot = SessionLogic.nextSlot(current);
        if (slot < 0 || (!Model.sameString(current["loadType"], "weight") &&
            !Model.sameString(current["loadType"], "assistance"))) {
            return false;
        }
        Navigator.numberEdit(_entryId, slot, "load100", false);
        return true;
    }

    private function exerciseLine(session as Dictionary, exercise as Dictionary,
                                  slotIndex as Number) as String {
        if (!Model.sameString(exercise["loadType"], "timed")) {
            return UiFormat.draftLine(exercise, slotIndex);
        }
        var run = session["timedRun"];
        if (run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
            run["slot"] == slotIndex) {
            var elapsed = getApp().controller().timedElapsed(Time.now().value());
            return "RUN  " + elapsed.toString() + "/" +
                targetDurationSec(exercise, slotIndex).toString() + " sec";
        }
        var draft = (exercise["slots"] as Array)[slotIndex]["draft"] as Dictionary;
        if (draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
            return "PAUSED  " + draft["measuredSec"].toString() + "/" +
                targetDurationSec(exercise, slotIndex).toString() + " sec";
        }
        if (draft["durationEdited"] == true) {
            return "MANUAL  " + draft["durationSec"].toString() + "/" +
                targetDurationSec(exercise, slotIndex).toString() + " sec";
        }
        return "TARGET  " + targetDurationSec(exercise, slotIndex).toString() + " sec";
    }

    private function targetDurationSec(exercise as Dictionary, slotIndex as Number) as Number {
        var targets = exercise["planTargets"];
        if (targets instanceof Array && slotIndex >= 0 && slotIndex < (targets as Array).size()) {
            var value = (targets as Array)[slotIndex]["durationSec"];
            if (value instanceof Number) {
                return value as Number;
            }
        }
        return exercise["targetDurationSec"] as Number;
    }

    public function adjustDraft(direction as Number) as Void {
        var controller = getApp().controller();
        var session = controller.session();
        if (session == null) {
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            return;
        }
        var current = exercise as Dictionary;
        var slot = SessionLogic.nextSlot(current);
        if (slot < 0) {
            return;
        }
        var draft = ((current["slots"] as Array)[slot] as Dictionary)["draft"] as Dictionary;
        var timed = Model.sameString(current["loadType"], "timed");
        var run = (session as Dictionary)["timedRun"];
        if (timed && run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
            run["slot"] == slot) {
            _message = "Use MENU to edit";
            WatchUi.requestUpdate();
            return;
        }
        var field = timed ? "durationSec" : "reps";
        var oldValue = draft[field] == null ? 0 : draft[field] as Number;
        var newValue = oldValue + direction;
        if (!timed && newValue < 1) {
            newValue = 1;
        }
        if (timed && newValue < 1) {
            newValue = 1;
        }
        if (controller.updateDraft(_entryId, slot, field, newValue)) {
            _message = null;
            WatchUi.requestUpdate();
        } else {
            _message = "Could not save change";
            WatchUi.requestUpdate();
        }
    }

    public function completeDraft(armed as Boolean) as Boolean {
        if (!armed) {
            return false;
        }
        var session = getApp().controller().session();
        if (session == null) {
            return false;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            return false;
        }
        var slot = SessionLogic.nextSlot(exercise as Dictionary);
        if (slot < 0) {
            return false;
        }
        var now = Time.now().value();
        var controller = getApp().controller();
        var saved = false;
        var timed = Model.sameString((exercise as Dictionary)["loadType"], "timed");
        var draft = ((exercise as Dictionary)["slots"] as Array)[slot]["draft"] as Dictionary;
        if (timed) {
            var run = (session as Dictionary)["timedRun"];
            if (run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
                run["slot"] == slot) {
                saved = controller.completeTimed(_entryId, slot, now);
            } else if (draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
                saved = controller.startTimed(_entryId, slot, now);
                _message = saved ? "Timer resumed" : "Timer not started";
                WatchUi.requestUpdate();
                return saved;
            } else if (draft["durationEdited"] == true) {
                saved = controller.completeDraft(_entryId, slot, now);
            } else {
                saved = controller.startTimed(_entryId, slot, now);
                _message = saved ? "Timer started" : "Timer not started";
                WatchUi.requestUpdate();
                return saved;
            }
        } else if (SessionLogic.setRunMatches(session as Dictionary, _entryId, slot)) {
            saved = controller.completeDraft(_entryId, slot, now);
        } else {
            // First START starts the set (and ends rest); the second START logs it.
            saved = controller.startSet(_entryId, slot, now);
            _message = saved ? null : "Set not started";
            WatchUi.requestUpdate();
            return saved;
        }
        if (saved) {
            afterSetSaved();
        } else {
            _message = getApp().controller().errorMessage() == null ? "Set not saved" : "Save failed";
            WatchUi.requestUpdate();
        }
        return saved;
    }

    public function logPausedTimed() as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            return;
        }
        var slot = SessionLogic.nextSlot(exercise as Dictionary);
        if (slot < 0) {
            return;
        }
        var draft = ((exercise as Dictionary)["slots"] as Array)[slot]["draft"] as Dictionary;
        if (!(draft["measuredSec"] instanceof Number) || draft["measuredSec"] <= 0) {
            return;
        }
        if (getApp().controller().completeTimed(_entryId, slot, Time.now().value())) {
            afterSetSaved();
        } else {
            _message = "Set not saved";
            WatchUi.requestUpdate();
        }
    }

    private function afterSetSaved() as Void {
        _message = null;
        var session = getApp().controller().session();
        if (session == null) {
            WatchUi.requestUpdate();
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        var following = SessionLogic.supersetNext(session as Dictionary, _entryId);
        if (following != null && !Model.sameString(following, _entryId)) {
            // Superset: replace this view with the next member; BACK still returns to Overview.
            Navigator.switchToExercise(following as String);
            return;
        }
        if (exercise == null || SessionLogic.nextSlot(exercise as Dictionary) >= 0) {
            WatchUi.requestUpdate();
            return;
        }
        var totals = SessionLogic.totals(session as Dictionary);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
        if (totals["planned"] > 0 && totals["done"] == totals["planned"]) {
            Navigator.workoutComplete();
        }
    }
}

class ExerciseDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ExerciseView;
    private var _armed as Boolean = true;

    public function initialize(view as ExerciseView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_ENTER) {
            var now = System.getTimer();
            var lastSavedAt = getApp().lastSetSavedAt;
            var tooSoon = lastSavedAt != null && now >= (lastSavedAt as Number) &&
                now - (lastSavedAt as Number) < 800;
            if (_armed && !tooSoon && _view.completeDraft(true)) {
                getApp().lastSetSavedAt = now;
            }
            _armed = false;
            return true;
        }
        if (key == KEY_UP) {
            _view.adjustDraft(1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.adjustDraft(-1);
            return true;
        }
        return false;
    }

    public function onKeyReleased(event as KeyEvent) as Boolean {
        if (event.getKey() == KEY_ENTER) {
            _armed = true;
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        return false;
    }

    public function onTap(event as ClickEvent) as Boolean {
        var coordinates = event.getCoordinates();
        _view.tapLoadAt(coordinates[0], coordinates[1]);
        return true;
    }

    public function onMenu() as Boolean {
        Navigator.exerciseMenu(_view.entryId(), _view);
        return true;
    }

    // BACK returns to Overview; a running timed set on this exercise is paused first; a
    // started (non-timed) set keeps running.
    public function onBack() as Boolean {
        var controller = getApp().controller();
        var session = controller.session();
        if (session != null) {
            var run = (session as Dictionary)["timedRun"];
            if (run instanceof Dictionary && Model.sameString(run["entryId"], _view.entryId()) &&
                !controller.pauseTimedForEntry(_view.entryId(), Time.now().value())) {
                Navigator.feedback("Timed set could not be paused");
                return true;
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
        return true;
    }
}
