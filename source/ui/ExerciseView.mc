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
    // UP/DOWN change the load instead of the reps (weight and assistance sets; the menu toggles).
    private var _loadFocused as Boolean = false;
    private var _rapid as RapidPress;

    public function initialize(entryId as String) {
        _entryId = entryId;
        _rapid = new RapidPress();
        View.initialize();
    }

    public function entryId() as String {
        return _entryId;
    }

    public function showMessage(message as String) as Void {
        _message = message.length() == 0 ? null : message;
        WatchUi.requestUpdate();
    }

    // Fixed layout (CLAUDE.md UI rules): name at the top, set dots (or the rest time while
    // resting) below it, weight and reps big in the centre, heart rate at the bottom. During a
    // rest the ring runs round the edge and the centre shows the next set.
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
                "No active workout", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
            dc.drawText(dc.getWidth() / 2, dc.getHeight() / 2, Graphics.FONT_MEDIUM,
                "Exercise unavailable", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var h = dc.getHeight();
        var titleY = h * 25 / 100;
        var rowY = h * 39 / 100;
        var valueY = h * 57 / 100;
        var hrY = h * 79 / 100;
        var current = exercise as Dictionary;
        var slot = SessionLogic.activeSlot(current);
        var loadType = current["loadType"] as String;
        var tappableLoad = Model.sameString(loadType, "weight") ||
            Model.sameString(loadType, "assistance");

        var rest = (session as Dictionary)["rest"];
        var resting = slot >= 0 && rest instanceof Dictionary &&
            (Model.sameString(rest["state"], "running") || Model.sameString(rest["state"], "expired"));
        // While resting, the centre shows the set that comes next (in a superset another exercise).
        var shown = current;
        var shownSlot = slot;
        var editable = true;
        if (resting) {
            drawRestRing(dc, session as Dictionary);
            var next = SessionLogic.nextUp(session as Dictionary, (rest as Dictionary)["entryId"] as String);
            if (next != null && !Model.sameString((next as Dictionary)["entryId"], _entryId)) {
                var other = UiFormat.exercise(session as Dictionary, (next as Dictionary)["entryId"] as String);
                if (other != null) {
                    shown = other as Dictionary;
                    shownSlot = (next as Dictionary)["slot"] as Number;
                    editable = false;
                }
            }
        }

        var name = shown["name"] as String;
        var groupLabel = SessionLogic.supersetLabel(session as Dictionary,
            SessionLogic.exerciseIndex(session as Dictionary, shown["entryId"] as String));
        if (groupLabel != null) {
            name = (groupLabel as String) + " " + name;
        }
        UiFormat.drawTitle(dc, name, titleY);

        if (slot < 0) {
            var count = current["plannedSetCount"] as Number;
            Icons.setDots(dc, rowY, count, count, -1);
            var s = Icons.unit(dc);
            Icons.check(dc, dc.getWidth() / 2, valueY, s * 3, Graphics.COLOR_GREEN);
            UiFormat.drawHrRow(dc, hrY, _message);
            Icons.backMarker(dc);
            Icons.menuMarker(dc);
            return;
        }

        if (resting) {
            var running = Model.sameString((rest as Dictionary)["state"], "running");
            var now = Time.now().value();
            var text = running ? UiFormat.clockText(RestClock.remaining(rest as Dictionary, now)) :
                "+" + UiFormat.clockText(RestClock.overtime(rest as Dictionary, now));
            dc.setColor(running ? Graphics.COLOR_BLUE : Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, rowY, Graphics.FONT_LARGE, text,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (Model.sameString(loadType, "timed") && current["unilateral"] == true) {
            var sideDraft = (Model.slotAt(current, slot) as Dictionary)["draft"] as Dictionary;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, rowY, Graphics.FONT_SMALL,
                sideDraft["leftSec"] instanceof Number ? "Right side" : "Left side",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else if (slot >= Model.WARMUP_BASE) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, rowY, Graphics.FONT_SMALL, "Warmup " +
                (slot - Model.WARMUP_BASE + 1).toString() + "/" +
                SessionLogic.warmupCount(current).toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            Icons.setDots(dc, rowY, doneSets(current), current["plannedSetCount"] as Number, slot);
        }

        var timedNow = null;
        var run = (session as Dictionary)["timedRun"];
        var isRunning = run instanceof Dictionary &&
            Model.sameString(run["entryId"], _entryId) && run["slot"] == slot;
        if (isRunning && editable) {
            timedNow = getApp().controller().timedElapsed(Time.now().value());
        }
        var parts = UiFormat.valueParts(shown, shownSlot, timedNow,
            targetDurationSec(shown, shownSlot));
        // Yellow and underlined: the value UP/DOWN change (load, reps or duration).
        var focus = !editable ? -1 : (Model.sameString(loadType, "timed") ? (isRunning ? -1 : 0) :
            (_loadFocused && tappableLoad ? 0 : parts.size() - 1));
        var box = UiFormat.drawBig(dc, parts, valueY, focus, Graphics.COLOR_WHITE);
        if (tappableLoad && editable) {
            _loadTapLeft = box[0] - 10;
            _loadTapRight = box[0] + (box[1] - box[0]) / 2;
            _loadTapTop = box[2] - 4;
            _loadTapBottom = box[3] + 4;
        }

        // Bottom row: heart rate; an error replaces it, and a one-time hint teaches the load switch.
        var hint = null;
        if (_message == null && tappableLoad && editable && !resting && !getApp().focusHintSeen) {
            hint = "Hold UP: change load";
        }
        if (hint != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, hrY, UiFormat.captionFont(), hint as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            UiFormat.drawHrRow(dc, hrY, _message);
        }

        var timed = Model.sameString(loadType, "timed");
        var draft = (Model.slotAt(current, slot) as Dictionary)["draft"] as Dictionary;
        var measured = draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0;
        var manuallyEdited = draft["durationEdited"] == true;
        // Button hints at the physical keys: START = play / stop / log, BACK = overview.
        Icons.startMarker(dc, timed ? (isRunning ? "stop" : ((measured || !manuallyEdited) ? "play" : "check")) :
            "check");
        Icons.backMarker(dc);
        if (editable && !isRunning) {
            Icons.focusMarkers(dc);
        }
    }

    // Working sets of the exercise that are logged.
    private function doneSets(exercise as Dictionary) as Number {
        var count = 0;
        var planned = exercise["plannedSetCount"] as Number;
        for (var i = 0; i < planned; i++) {
            var found = Model.slotAt(exercise, i);
            if (found != null && (found as Dictionary)["completed"] instanceof Dictionary) {
                count++;
            }
        }
        return count;
    }

    // Countdown ring at the very edge, outside the button-hint icons (inside them it would run
    // through the title and rest lines): dim full circle, a blue arc clockwise from 12 o'clock
    // for the remaining rest, and a full green ring once the rest has run out. Redrawn only with
    // the screen, i.e. with the existing 1 s rest redraw.
    private function drawRestRing(dc as Dc, session as Dictionary) as Void {
        var rest = session["rest"];
        if (!(rest instanceof Dictionary)) {
            return;
        }
        var width = dc.getWidth();
        var height = dc.getHeight();
        // The icons sit at min/2 - 2u and reach out to about min/2 - u/2, so a pen of u/2 at the
        // very edge leaves them clear.
        var u = Icons.unit(dc);
        var pen = u / 2 < 3 ? 3 : u / 2;
        var radius = (width < height ? width : height) / 2 - pen / 2;
        var expired = Model.sameString((rest as Dictionary)["state"], "expired");
        var fraction = expired ? 1.0 :
            RestClock.ringFraction(rest as Dictionary, Time.now().value());
        dc.setPenWidth(pen);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
        dc.drawCircle(width / 2, height / 2, radius);
        dc.setColor(expired ? Graphics.COLOR_GREEN : Graphics.COLOR_BLUE, Graphics.COLOR_BLACK);
        if (fraction >= 1.0) {
            dc.drawCircle(width / 2, height / 2, radius);
        } else if (fraction > 0.0) {
            dc.drawArc(width / 2, height / 2, radius, Graphics.ARC_CLOCKWISE, 90,
                RestClock.ringEndDegrees(fraction));
        }
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
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
        var slot = SessionLogic.activeSlot(current);
        if (slot < 0 || (!Model.sameString(current["loadType"], "weight") &&
            !Model.sameString(current["loadType"], "assistance"))) {
            return false;
        }
        _loadFocused = true;
        getApp().markFocusHintSeen();
        WatchUi.requestUpdate();
        return true;
    }

    public function loadFocused() as Boolean {
        return _loadFocused;
    }

    // Menu → Change load / Change reps: UP/DOWN switch between the reps and the load of the next set.
    public function toggleFocus() as Void {
        var session = getApp().controller().session();
        var exercise = session == null ? null : UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null || SessionLogic.activeSlot(exercise as Dictionary) < 0 ||
            (!Model.sameString((exercise as Dictionary)["loadType"], "weight") &&
             !Model.sameString((exercise as Dictionary)["loadType"], "assistance"))) {
            return;
        }
        _loadFocused = !_loadFocused;
        getApp().markFocusHintSeen();
        getApp().clearConfirmation();
        WatchUi.requestUpdate();
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
        var draft = (Model.slotAt(exercise, slotIndex) as Dictionary)["draft"] as Dictionary;
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
        if (slotIndex >= Model.WARMUP_BASE) {
            var warmup = Model.slotAt(exercise, slotIndex);
            var planned = warmup == null ? null : ((warmup as Dictionary)["draft"] as Dictionary)["durationSec"];
            return planned instanceof Number ? planned as Number : exercise["targetDurationSec"] as Number;
        }
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
        getApp().clearConfirmation();
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
        var slot = SessionLogic.activeSlot(current);
        if (slot < 0) {
            return;
        }
        var draft = (Model.slotAt(current, slot) as Dictionary)["draft"] as Dictionary;
        var timed = Model.sameString(current["loadType"], "timed");
        var run = (session as Dictionary)["timedRun"];
        if (timed && run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
            run["slot"] == slot) {
            _message = "Use MENU to edit";
            WatchUi.requestUpdate();
            return;
        }
        var loadable = Model.sameString(current["loadType"], "weight") ||
            Model.sameString(current["loadType"], "assistance");
        var field = timed ? "durationSec" : (_loadFocused && loadable ? "load100" : "reps");
        var oldValue = draft[field] == null ? 0 : draft[field] as Number;
        var newValue = oldValue + direction;
        if (Model.sameString(field, "load100")) {
            var step = current["weightIncrement100"] instanceof Number ? current["weightIncrement100"] as Number : 100;
            newValue = oldValue + direction * step * _rapid.multiplier(direction);
            newValue = newValue < 0 ? 0 : (newValue > Model.MAX_LOAD100 ? Model.MAX_LOAD100 : newValue);
        } else if (newValue < 1) {
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
        var slot = SessionLogic.activeSlot(exercise as Dictionary);
        if (slot < 0) {
            return false;
        }
        var now = Time.now().value();
        var controller = getApp().controller();
        var saved = false;
        var timed = Model.sameString((exercise as Dictionary)["loadType"], "timed");
        var draft = (Model.slotAt(exercise as Dictionary, slot) as Dictionary)["draft"] as Dictionary;
        if (timed) {
            var run = (session as Dictionary)["timedRun"];
            if (run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
                run["slot"] == slot) {
                saved = controller.completeTimed(_entryId, slot, now);
            } else if (draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
                saved = controller.startTimed(_entryId, slot, now);
                _message = saved ? null : "Timer not started";
                WatchUi.requestUpdate();
                return saved;
            } else if (draft["durationEdited"] == true) {
                saved = controller.completeDraft(_entryId, slot, now);
            } else {
                saved = controller.startTimed(_entryId, slot, now);
                _message = saved ? null : "Timer not started";
                WatchUi.requestUpdate();
                return saved;
            }
        } else {
            // One press logs the displayed draft and starts the rest.
            saved = controller.completeDraft(_entryId, slot, now);
        }
        if (saved) {
            afterSetSaved(slot);
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
        var slot = SessionLogic.activeSlot(exercise as Dictionary);
        if (slot < 0) {
            return;
        }
        var draft = (Model.slotAt(exercise as Dictionary, slot) as Dictionary)["draft"] as Dictionary;
        if (!(draft["measuredSec"] instanceof Number) || draft["measuredSec"] <= 0) {
            return;
        }
        if (getApp().controller().completeTimed(_entryId, slot, Time.now().value())) {
            afterSetSaved(slot);
        } else {
            _message = "Set not saved";
            WatchUi.requestUpdate();
        }
    }

    // After a logged set: the usual feedback and navigation, then any values the program asks
    // for (RPE of this set; prompted variables once the exercise's last set is done) on top.
    private function afterSetSaved(slot as Number) as Void {
        afterSetNavigation(slot);
        var session = getApp().controller().session();
        var exercise = session == null ? null : UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise != null) {
            var questions = QuestionLogic.afterSet(exercise as Dictionary, _entryId, slot);
            if (questions.size() > 0) {
                var view = new QuestionView(questions);
                WatchUi.pushView(view, new QuestionDelegate(view), WatchUi.SLIDE_UP);
            }
        }
    }

    private function afterSetNavigation(slot as Number) as Void {
        _message = null;
        _loadFocused = false;
        var saved = getApp().controller().session();
        var savedExercise = saved == null ? null : UiFormat.exercise(saved as Dictionary, _entryId);
        var text = savedExercise == null ? null : UiFormat.confirmText(savedExercise as Dictionary, slot);
        if (text != null) {
            getApp().showConfirmation(text as String);
        }
        if (slot >= Model.WARMUP_BASE) {
            getApp().buzz(false);
            // Warmups of a member are done back to back before it joins the superset rotation.
            WatchUi.requestUpdate();
            return;
        }
        var session = getApp().controller().session();
        if (session == null) {
            WatchUi.requestUpdate();
            return;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        var following = SessionLogic.supersetNext(session as Dictionary, _entryId);
        var switching = following != null && !Model.sameString(following, _entryId);
        getApp().buzz(switching);
        if (switching) {
            // Superset: replace this view with the next member; BACK still returns to Overview.
            Navigator.switchToExercise(following as String);
            return;
        }
        if (exercise == null || SessionLogic.activeSlot(exercise as Dictionary) >= 0) {
            WatchUi.requestUpdate();
            return;
        }
        var totals = SessionLogic.totals(session as Dictionary);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
        if (totals["planned"] > 0 && totals["done"] == totals["planned"]) {
            Navigator.review();
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

    // Keys act on press. On the FR965 only hold UP (menu) reaches the app; hold START, DOWN and
    // LIGHT are firmware shortcuts, so the reps/load switch lives in the menu.
    public function onKey(event as KeyEvent) as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
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
        if (Navigator.staleWorkoutView()) {
            return true;
        }
        Navigator.exerciseMenu(_view.entryId(), _view);
        return true;
    }

    // BACK returns to Overview; a running timed set on this exercise is paused first.
    public function onBack() as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
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
