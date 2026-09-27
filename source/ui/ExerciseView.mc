import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class ExerciseView extends WatchUi.View {
    private var _entryId as String;
    private var _message as String? = null;

    public function initialize(entryId as String) {
        _entryId = entryId;
        View.initialize();
    }

    public function entryId() as String {
        return _entryId;
    }

    public function showMessage(message as String) as Void {
        _message = message;
        WatchUi.requestUpdate();
    }

    public function onUpdate(dc as Dc) as Void {
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
        var caption = UiFormat.captionFont();
        var title = current["name"] as String;
        var titleFont = Graphics.FONT_XTINY;
        if (UiFormat.safeText(dc, title, 56, titleFont) != title) {
            titleFont = caption;
        }
        var y = UiFormat.drawLine(dc, title, 56, titleFont) + 2;
        if (slot < 0) {
            y = UiFormat.drawLine(dc, current["closedEarly"] ? "Finished early" :
                "Exercise complete", y + 28, Graphics.FONT_SMALL) + 8;
            y = UiFormat.drawLine(dc, UiFormat.progress(current), y, Graphics.FONT_SMALL) + 8;
        } else {
            y = UiFormat.drawLine(dc, "NEXT SET " + (slot + 1).toString() + "/" +
                planned.toString(), y, caption) + 2;
            var last = UiFormat.lastLine(current, slot);
            if (last != null) {
                y = UiFormat.drawLine(dc, last as String, y, caption) + 2;
            }
            var value = exerciseLine(session as Dictionary, current, slot);
            var valueFont = Graphics.FONT_LARGE;
            if (UiFormat.safeText(dc, value, y, valueFont) != value) {
                valueFont = Graphics.FONT_SMALL;
            }
            if (UiFormat.safeText(dc, value, y, valueFont) != value) {
                valueFont = Graphics.FONT_XTINY;
            }
            y = UiFormat.drawLine(dc, value, y, valueFont) + 4;
        }
        if (_message != null) {
            y = UiFormat.drawLine(dc, _message as String, y, caption) + 2;
        }
        var restStatus = UiFormat.restStatus(session as Dictionary);
        if (restStatus != null) {
            y = UiFormat.drawLine(dc, restStatus as String, y, caption) + 2;
        }
        if (current["notes"] != null) {
            y = UiFormat.drawLine(dc, current["notes"] as String, y, caption) + 2;
        }
        if (slot >= 0) {
            var timed = Model.sameString(current["loadType"], "timed");
            var run = (session as Dictionary)["timedRun"];
            var isRunning = run instanceof Dictionary &&
                Model.sameString(run["entryId"], _entryId) && run["slot"] == slot;
            var adjustment = isRunning ? "RUNNING: MENU TO EDIT" :
                (timed ? "UP/DOWN: MANUAL SEC" : "UP/DOWN: REPS");
            y = UiFormat.drawLine(dc, adjustment, y + 4, caption) + 2;
            y = UiFormat.drawLine(dc, timed ? "START: START / STOP" : "START: LOG",
                y, caption) + 2;
        }
        UiFormat.drawLine(dc, "MENU: ACTIONS", y, caption);
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
            return (elapsed >= exercise["targetDurationSec"] ? "TARGET  " : "RUN  ") +
                elapsed.toString() + " sec";
        }
        var draft = (exercise["slots"] as Array)[slotIndex]["draft"] as Dictionary;
        if (draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
            return "PAUSED  " + draft["measuredSec"].toString() + " sec";
        }
        if (draft["durationEdited"] == true) {
            return "MANUAL  " + draft["durationSec"].toString() + " sec";
        }
        return "TARGET  " + exercise["targetDurationSec"].toString() + " sec";
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
        } else {
            saved = controller.completeDraft(_entryId, slot, now);
        }
        if (saved) {
            _message = "Saved set " + (slot + 1).toString();
        } else {
            _message = getApp().controller().errorMessage() == null ? "Set not saved" : "Save failed";
        }
        WatchUi.requestUpdate();
        return saved;
    }
}

class ExerciseDelegate extends WatchUi.BehaviorDelegate {
    private var _view as ExerciseView;
    private var _armed as Boolean = true;
    private var _lastSavedAt as Number? = null;

    public function initialize(view as ExerciseView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_ENTER) {
            var now = System.getTimer();
            var tooSoon = _lastSavedAt != null && now >= (_lastSavedAt as Number) &&
                now - (_lastSavedAt as Number) < 800;
            if (_armed && !tooSoon && _view.completeDraft(true)) {
                _lastSavedAt = now;
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
        return true;
    }

    public function onMenu() as Boolean {
        Navigator.exerciseMenu(_view.entryId(), _view);
        return true;
    }

    public function onBack() as Boolean {
        var session = getApp().controller().session();
        var run = session == null ? null : (session as Dictionary)["timedRun"];
        if (run instanceof Dictionary && Model.sameString(run["entryId"], _view.entryId()) &&
            !getApp().controller().pauseTimedForEntry(_view.entryId(), Time.now().value())) {
            _view.showMessage("Save failed - timer still running");
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
