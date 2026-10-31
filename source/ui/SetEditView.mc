import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Same-direction presses less than 400 ms apart form a run: from the 4th press each press moves
// two steps, from the 8th four. Holding a button cannot repeat (on the FR965 only hold UP reaches
// the app, as the menu; hold START, DOWN and LIGHT are firmware shortcuts), so fast presses speed up.
class RapidPress {
    private var _lastAt as Number = 0;
    private var _direction as Number = 0;
    private var _count as Number = 0;

    public function initialize() {
    }

    public function multiplier(direction as Number) as Number {
        return multiplierAt(direction, System.getTimer());
    }

    public function multiplierAt(direction as Number, now as Number) as Number {
        _count = direction == _direction && now - _lastAt < 400 ? _count + 1 : 1;
        _direction = direction;
        _lastAt = now;
        return _count >= 8 ? 4 : (_count >= 4 ? 2 : 1);
    }
}

// Load and reps of one set on one screen: the next set (draft) or a logged set (correcting).
// UP/DOWN change the highlighted field, MENU (hold UP) switches it, START saves, BACK cancels. Timed sets keep NumberEditView for their duration.
class SetEditView extends WatchUi.View {
    private var _entryId as String;
    private var _slot as Number;
    private var _correcting as Boolean;
    private var _hasLoad as Boolean = false;
    private var _assistance as Boolean = false;
    private var _loadFocused as Boolean;
    private var _load100 as Number = 0;
    private var _reps as Number = 1;
    private var _increment100 as Number = 100;
    private var _error as String? = null;
    private var _rapid as RapidPress;

    public function initialize(entryId as String, slot as Number, correcting as Boolean,
                               focusLoad as Boolean) {
        _entryId = entryId;
        _slot = slot;
        _correcting = correcting;
        _loadFocused = focusLoad;
        _rapid = new RapidPress();
        View.initialize();
        loadValues();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        // Title, the big value in the set screen's place, an error in the heart-rate row.
        var h = dc.getHeight();
        var title = (_correcting ? "Edit " : "Next ") +
            (_slot >= Model.WARMUP_BASE ? "warmup " : "set ") + UiFormat.slotLabel(_slot);
        UiFormat.drawTitle(dc, title, h * 25 / 100);
        var reps = [_reps.toString(), "num"];
        var parts = _hasLoad ?
            [[UiFormat.load100(_load100), "num"], [_assistance ? "kg assist" : "kg", "unit"], ["×", "sep"], reps] :
            [reps, ["reps", "unit"]];
        UiFormat.drawBig(dc, parts, h * 57 / 100, _hasLoad && _loadFocused ? 0 : (_hasLoad ? 3 : 0),
            Graphics.COLOR_WHITE);
        if (_error != null) {
            UiFormat.drawHrRow(dc, h * 79 / 100, _error);
        }
        Icons.startMarker(dc, "check");
        Icons.backMarker(dc);
        Icons.focusMarkers(dc);
    }

    public function adjust(direction as Number) as Void {
        if (_loadFocused) {
            var value = _load100 + direction * _increment100 * _rapid.multiplier(direction);
            _load100 = value < 0 ? 0 : (value > Model.MAX_LOAD100 ? Model.MAX_LOAD100 : value);
        } else {
            var reps = _reps + direction;
            _reps = reps < 1 ? 1 : (reps > Model.MAX_REPS ? Model.MAX_REPS : reps);
        }
        _error = null;
        WatchUi.requestUpdate();
    }

    public function toggleFocus() as Void {
        if (_hasLoad) {
            _loadFocused = !_loadFocused;
            WatchUi.requestUpdate();
        }
    }

    public function save() as Void {
        var controller = getApp().controller();
        var context = editorContext();
        var saved = false;
        if (context != null && _correcting) {
            var actual = SessionLogic.copyDictionary((context as Dictionary)["completed"] as Dictionary);
            actual["reps"] = _reps;
            if (_hasLoad) {
                actual["load100"] = _load100;
            }
            saved = controller.correctSet(_entryId, _slot, actual, Time.now().value());
        } else if (context != null) {
            saved = (!_hasLoad || controller.updateDraft(_entryId, _slot, "load100", _load100)) &&
                controller.updateDraft(_entryId, _slot, "reps", _reps);
        }
        if (!saved) {
            var problem = controller.errorCode();
            _error = problem == Err.SAVE_FAILED_RETRY_BEFORE_CONTINUING ? "Save failed" : "Not saved";
            WatchUi.requestUpdate();
            return;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (_correcting) {
            var session = controller.session();
            var exercise = session == null ? null : UiFormat.exercise(session as Dictionary, _entryId);
            var text = exercise == null ? null : UiFormat.confirmText(exercise as Dictionary, _slot);
            if (text != null) {
                getApp().showConfirmation(text as String);
            }
        }
        WatchUi.requestUpdate();
    }

    public function cancel() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    private function loadValues() as Void {
        var context = editorContext();
        if (context == null) {
            _error = "Set unavailable";
            _loadFocused = false;
            return;
        }
        var data = context as Dictionary;
        var exercise = data["exercise"] as Dictionary;
        var values = (_correcting ? data["completed"] : data["draft"]) as Dictionary;
        _assistance = Model.sameString(exercise["loadType"], "assistance");
        _hasLoad = _assistance || Model.sameString(exercise["loadType"], "weight");
        _loadFocused = _loadFocused && _hasLoad;
        if (values["reps"] instanceof Number) {
            _reps = values["reps"] as Number;
        }
        if (_hasLoad && values["load100"] instanceof Number) {
            _load100 = values["load100"] as Number;
            _increment100 = exercise["weightIncrement100"] instanceof Number ?
                exercise["weightIncrement100"] as Number : 100;
        }
    }

    private function editorContext() as Dictionary? {
        var session = getApp().controller().session();
        if (session == null) {
            return null;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null || Model.sameString((exercise as Dictionary)["loadType"], "timed")) {
            return null;
        }
        var found = Model.slotAt(exercise as Dictionary, _slot);
        if (found == null) {
            return null;
        }
        var completed = (found as Dictionary)["completed"];
        if (_correcting ? completed == null : completed != null) {
            return null;
        }
        return {"exercise" => exercise, "draft" => (found as Dictionary)["draft"], "completed" => completed};
    }

}

class SetEditDelegate extends WatchUi.BehaviorDelegate {
    private var _view as SetEditView;

    public function initialize(view as SetEditView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_ENTER) {
            _view.save();
            return true;
        }
        if (key == KEY_UP || key == KEY_DOWN) {
            _view.adjust(key == KEY_UP ? 1 : -1);
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        return false;
    }

    public function onMenu() as Boolean {
        _view.toggleFocus();
        return true;
    }

    public function onBack() as Boolean {
        _view.cancel();
        return true;
    }
}
