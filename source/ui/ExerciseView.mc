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
        var slot = SessionLogic.activeSlot(current);
        var planned = current["plannedSetCount"] as Number;
        var loadType = current["loadType"] as String;
        var tappableLoad = Model.sameString(loadType, "weight") ||
            Model.sameString(loadType, "assistance");
        var caption = UiFormat.captionFont();
        var titleFont = Graphics.FONT_MEDIUM;
        var name = current["name"] as String;
        var groupLabel = SessionLogic.supersetLabel(session as Dictionary,
            SessionLogic.exerciseIndex(session as Dictionary, _entryId));
        if (groupLabel != null) {
            name = (groupLabel as String) + " " + name;
        }
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
        // Running rest, or the overtime count-up once it has run out.
        var restStatus = slot < 0 ? null : (UiFormat.restStatus(session as Dictionary) != null ?
            UiFormat.restStatus(session as Dictionary) : UiFormat.restOvertime(session as Dictionary));
        if (restStatus != null) {
            drawRestRing(dc, session as Dictionary);
        }
        var nextUp = restStatus == null ? null : UiFormat.nextUpLine(session as Dictionary);
        var last = slot < 0 || restStatus != null ? null : UiFormat.lastLine(current, slot);
        // Target is lowest priority: only shown when notes and messages leave room.
        var target = slot < 0 || restStatus != null || _message != null ||
            current["notes"] instanceof String ? null :
            UiFormat.targetLine(current, slot);
        // How to reach the load: shown until the first switch, and while the load is selected.
        var focusable = tappableLoad && slot >= 0 && restStatus == null;
        var hint = !focusable ? null : (_loadFocused ? "MENU: change reps" :
            (getApp().focusHintSeen ? null : "MENU: change load"));
        if (hint != null) {
            target = null;
        }
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
                if (target != null || hint != null) {
                    mainHeight += dc.getFontHeight(caption) + 2;
                }
                if (current["notes"] instanceof String) {
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
            y = UiFormat.drawLine(dc, UiFormat.progress(current), y, Graphics.FONT_SMALL) + 4;
            UiFormat.drawLine(dc, "Hold UP: add set", y, caption);
            Icons.backMarker(dc);
            Icons.menuMarker(dc);
            return;
        }

        y += 4;
        var range = UiFormat.repRange(current, slot);
        var setTitle = slot >= Model.WARMUP_BASE ?
            "Warmup " + (slot - Model.WARMUP_BASE + 1).toString() + "/" +
                SessionLogic.warmupCount(current).toString() :
            "Set " + (slot + 1).toString() + "/" + planned.toString() +
                (range == null ? "" : " · " + range);
        y = UiFormat.drawLine(dc, setTitle, y, setFont) + 7;
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
        var draftValues = (Model.slotAt(current, slot) as Dictionary)["draft"] as Dictionary;
        if (tappableLoad && Model.sameString(visibleValue, value)) {
            var loadLabel = UiFormat.load100(draftValues["load100"] as Number) + " kg" +
                (Model.sameString(loadType, "assistance") ? " assist" : "");
            _loadTapLeft = lineLeft - 10;
            _loadTapRight = lineLeft + dc.getTextWidthInPixels(loadLabel, valueFont) + 10;
            _loadTapTop = valueY - 3;
            _loadTapBottom = valueY + valueHeight + 3;
            y = UiFormat.drawSetValue(dc, loadLabel, draftValues["reps"].toString(), _loadFocused,
                valueY, valueFont) + 6;
        } else {
            y = UiFormat.drawLine(dc, value, valueY, valueFont) + 6;
        }

        if (restStatus != null) {
            y = UiFormat.drawRestLine(dc, session as Dictionary, y, Graphics.FONT_SMALL);
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
        if (hint != null) {
            y = UiFormat.drawLine(dc, hint as String, y, caption) + 2;
        }
        if (restStatus == null && current["notes"] instanceof String) {
            y = UiFormat.drawLine(dc, current["notes"] as String, y, caption) + 2;
        }
        if (restStatus == null && _message != null) {
            y = UiFormat.drawLine(dc, _message as String, y, caption) + 2;
        }

        var timed = Model.sameString(loadType, "timed");
        var run = (session as Dictionary)["timedRun"];
        var isRunning = run instanceof Dictionary &&
            Model.sameString(run["entryId"], _entryId) && run["slot"] == slot;
        var draft = (Model.slotAt(current, slot) as Dictionary)["draft"] as Dictionary;
        var measured = draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0;
        var manuallyEdited = draft["durationEdited"] == true;
        // The hint line is now the transient confirmation of the last logged set.
        var confirmation = getApp().confirmText;
        if (confirmation != null) {
            var s = Icons.unit(dc);
            var width = dc.getTextWidthInPixels(confirmation as String, caption);
            Icons.check(dc, dc.getWidth() / 2 - width / 2 - s * 2, y + 2 + dc.getFontHeight(caption) / 2,
                s, Graphics.COLOR_GREEN);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_BLACK);
            UiFormat.drawLine(dc, confirmation as String, y + 2, caption);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        }
        // Button hints at the physical keys: START = play / stop / log, BACK = overview.
        Icons.startMarker(dc, timed ? (isRunning ? "stop" : ((measured || !manuallyEdited) ? "play" : "check")) :
            "check");
        Icons.backMarker(dc);
        Icons.focusMarkers(dc, _loadFocused && tappableLoad);
    }

    // Countdown ring at the very edge, outside the button-hint icons (inside them it would run
    // through the title and rest lines): dim full circle, a yellow arc clockwise from 12 o'clock
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
        dc.setColor(expired ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
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
        getApp().focusHintSeen = true;
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
        getApp().focusHintSeen = true;
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

    private function afterSetSaved(slot as Number) as Void {
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
