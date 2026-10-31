import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Key-only finish flow: ReviewView (elapsed time, sets and exercises done) -> START saves,
// BACK opens the Keep/Discard ConfirmView. The same ConfirmView (with a ConfirmAction) guards
// the other destructive choices. No Menu2: menus accept taps.

// START presses this soon after a screen opened are ignored (the set-logging press that opened
// the end-of-workout prompt must not also confirm it).
module FinishGuard {
    const OPEN_GUARD_MS = 800;

    function tooSoon(openedAt as Number, now as Number) as Boolean {
        return now >= openedAt && now - openedAt < OPEN_GUARD_MS;
    }
}

class ReviewView extends WatchUi.View {
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var session = getApp().controller().session();
        if (session == null) {
            UiFormat.drawLine(dc, "No active workout", dc.getHeight() / 2 - 10, Graphics.FONT_SMALL);
            return;
        }
        // Same places as the set screen: title, a small row, the big value (workout time).
        var stats = UiFormat.reviewStats(session as Dictionary, Time.now().value());
        var h = dc.getHeight();
        UiFormat.drawTitle(dc, "Finish?", h * 25 / 100);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, h * 39 / 100, Graphics.FONT_SMALL,
            UiFormat.plural(stats["sets"] as Number, "set") + " · " +
                UiFormat.plural(stats["exercises"] as Number, "exercise"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        UiFormat.drawBig(dc, [[UiFormat.clockText(stats["elapsedSec"] as Number), "num"]],
            h * 57 / 100, -1, Graphics.COLOR_WHITE);
        if (stats["sets"] as Number > 0) {
            Icons.startMarker(dc, "check");
        }
        Icons.backMarker(dc);
    }
}

class ReviewDelegate extends KeyDelegate {
    private var _openedAt as Number;

    public function initialize() {
        KeyDelegate.initialize();
        _openedAt = System.getTimer();
    }

    // START saves; the controller still refuses a workout without a logged set.
    public function onStartKey() as Boolean {
        if (Navigator.staleWorkoutView() || FinishGuard.tooSoon(_openedAt, System.getTimer())) {
            return true;
        }
        var session = getApp().controller().session();
        if (session != null && SessionLogic.totals(session as Dictionary)["done"] == 0) {
            Navigator.feedback(Err.message(Err.LOG_A_SET_BEFORE_SAVING) as String);
            return true;
        }
        getApp().requestWorkoutFinish("completed");
        return true;
    }

    // BACK: Keep working / Discard choice (BACK there returns here).
    public function onBackKey() as Boolean {
        if (Navigator.staleWorkoutView()) {
            return true;
        }
        Navigator.confirmDiscard(true);
        return true;
    }
}

// What a ConfirmView does when its second choice is confirmed. The action pops or replaces the
// confirmation itself (some also close the menu below it).
class ConfirmAction {
    public function initialize() {
    }

    // True for actions on the running workout: a stale view is redirected to Home instead.
    public function isWorkout() as Boolean {
        return false;
    }

    // Views to pop when the first (safe) choice is confirmed.
    public function keepPops() as Number {
        return 1;
    }

    public function run() as Void {
    }
}

class DiscardWorkoutAction extends ConfirmAction {
    private var _fromReview as Boolean;

    public function initialize(fromReview as Boolean) {
        ConfirmAction.initialize();
        _fromReview = fromReview;
    }

    public function isWorkout() as Boolean {
        return true;
    }

    public function keepPops() as Number {
        return _fromReview ? 2 : 1;
    }

    // Replaces the confirmation with the "Finishing" screen like a normal finish.
    public function run() as Void {
        getApp().requestWorkoutFinish("aborted");
    }
}

class DeleteSetAction extends ConfirmAction {
    private var _entryId as String;
    private var _slot as Number;
    private var _view as ExerciseView;
    private var _fromOverview as Boolean;

    public function initialize(entryId as String, slot as Number, view as ExerciseView,
                               fromOverview as Boolean) {
        ConfirmAction.initialize();
        _entryId = entryId;
        _slot = slot;
        _view = view;
        _fromOverview = fromOverview;
    }

    public function isWorkout() as Boolean {
        return true;
    }

    public function run() as Void {
        if (!getApp().controller().undoSet(_entryId, _slot)) {
            _view.showMessage("Set not deleted");
        }
        // The confirmation and the exercise menu below it.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (_fromOverview && getApp().controller().errorMessage() != null) {
            Navigator.home();
        } else {
            WatchUi.requestUpdate();
        }
    }
}

// Destructive upload-queue / key actions; local workout history is never touched.
class QueueAction extends ConfirmAction {
    private var _action as String;

    public function initialize(action as String) {
        ConfirmAction.initialize();
        _action = action;
    }

    public function run() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        var controller = getApp().controller();
        if (Model.sameString(_action, "clear_key")) {
            // Back to a refreshed Settings (the key label and key items change).
            controller.clearKey();
            Navigator.settings();
            return;
        }
        var done = Model.sameString(_action, "clear_queue") ? controller.clearUploadQueue() :
            controller.skipUpload();
        // Also leave the parent menu so Home shows the result.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (!done) {
            Navigator.feedback("Could not change the upload queue");
        }
    }
}

// Two choices, the safe one first and selected: UP/DOWN move, START confirms, BACK goes back.
class ConfirmView extends WatchUi.View {
    public var selected as Number = 0;
    private var _title as String;
    private var _keepLabel as String;
    private var _actionLabel as String;

    public function initialize(title as String, keepLabel as String, actionLabel as String) {
        View.initialize();
        _title = title;
        _keepLabel = keepLabel;
        _actionLabel = actionLabel;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        UiFormat.drawTitle(dc, _title, h * 25 / 100);
        // The selected choice is yellow and underlined (what START will do); the other is gray.
        var items = [_keepLabel, _actionLabel];
        var font = Graphics.FONT_MEDIUM;
        for (var i = 0; i < 2; i++) {
            var active = i == selected;
            var y = h * (50 + 17 * i) / 100;
            dc.setColor(active ? Graphics.COLOR_YELLOW : Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            dc.drawText(dc.getWidth() / 2, y, font, items[i] as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            if (active) {
                var width = dc.getTextWidthInPixels(items[i] as String, font);
                dc.setPenWidth(3);
                dc.drawLine((dc.getWidth() - width) / 2, y + dc.getFontHeight(font) / 2,
                    (dc.getWidth() + width) / 2, y + dc.getFontHeight(font) / 2);
                dc.setPenWidth(1);
            }
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        Icons.startMarker(dc, "check");
        Icons.backMarker(dc);
        Icons.browseMarkers(dc);
    }
}

class ConfirmDelegate extends KeyDelegate {
    private var _view as ConfirmView;
    private var _action as ConfirmAction;
    private var _openedAt as Number;

    public function initialize(view as ConfirmView, action as ConfirmAction) {
        KeyDelegate.initialize();
        _view = view;
        _action = action;
        _openedAt = System.getTimer();
    }

    public function onUpKey() as Boolean {
        return toggle();
    }

    public function onDownKey() as Boolean {
        return toggle();
    }

    private function toggle() as Boolean {
        if (_action.isWorkout() && Navigator.staleWorkoutView()) {
            return true;
        }
        _view.selected = (_view.selected + 1) % 2;
        WatchUi.requestUpdate();
        return true;
    }

    public function onStartKey() as Boolean {
        if (_action.isWorkout() && Navigator.staleWorkoutView()) {
            return true;
        }
        if (FinishGuard.tooSoon(_openedAt, System.getTimer())) {
            return true;
        }
        if (_view.selected == 0) {
            for (var i = 0; i < _action.keepPops(); i++) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
            }
            return true;
        }
        _action.run();
        return true;
    }

    public function onBackKey() as Boolean {
        if (_action.isWorkout() && Navigator.staleWorkoutView()) {
            return true;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class ActivityResultDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (Model.sameString(item.getId(), "retry")) {
            if (getApp().controller().retryActivitySave()) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.requestUpdate();
            } else {
                Navigator.feedback("Garmin save failed; local log is safe");
            }
        } else if (Model.sameString(item.getId(), "exit")) {
            if (getApp().controller().keepLocalLogAndCloseActivity()) {
                Navigator.exitApp();
            } else {
                Navigator.feedback("Local log remains safe; activity could not be closed");
            }
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
