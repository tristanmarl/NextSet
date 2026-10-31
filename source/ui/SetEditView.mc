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

// Editor of one set: the next set's draft or a logged set (correcting). Fields: weight and reps
// (weight and assistance exercises), reps (bodyweight) or the duration (timed). Two levels
// (EditorLogic): SELECT shows the fields big with the selected one framed (UP/DOWN move, START
// enters it, BACK saves what was confirmed and closes); EDIT shows the field yellow and underlined
// (UP/DOWN change it, START keeps it, BACK restores it and returns to SELECT).
class SetEditView extends WatchUi.View {
    private var _entryId as String;
    private var _slot as Number;
    private var _correcting as Boolean;
    private var _fields as Array<String> = ["reps"];
    private var _selected as Number = 0;
    private var _mode as Number = EditorLogic.MODE_SELECT;
    private var _assistance as Boolean = false;
    private var _unit as String = "kg";
    // Current and opening values by field (index = position in _fields).
    private var _values as Array<Number> = [1];
    private var _opened as Array<Number> = [1];
    private var _before as Number = 0;
    private var _increment100 as Number = 100;
    private var _error as String? = null;
    private var _ready as Boolean = false;
    private var _rapid as RapidPress;

    public function initialize(entryId as String, slot as Number, correcting as Boolean) {
        _entryId = entryId;
        _slot = slot;
        _correcting = correcting;
        _rapid = new RapidPress();
        View.initialize();
        loadValues();
    }

    public function mode() as Number {
        return _mode;
    }

    public function selectedField() as Number {
        return _selected;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var title = (_correcting ? "Edit " : "Next ") +
            (_slot >= Model.WARMUP_BASE ? "warmup " : "set ") + UiFormat.slotLabel(_slot);
        UiFormat.drawTitle(dc, title, h * 25 / 100);
        var count = _ready ? _fields.size() : 0;
        var editing = _mode == EditorLogic.MODE_EDIT;
        for (var i = 0; i < count; i++) {
            var y = count == 1 ? h * 57 / 100 : (i == 0 ? h * 50 / 100 : h * 71 / 100);
            var box = UiFormat.drawBigFrom(dc, fieldParts(i), y, editing && i == _selected ? 0 : -1,
                Graphics.COLOR_WHITE, count == 1 ? 0 : 1);
            if (!editing && i == _selected) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                dc.setPenWidth(3);
                dc.drawRoundedRectangle(box[0] - 10, box[2] - 6, box[1] - box[0] + 20,
                    box[3] - box[2] + 12, 10);
                dc.setPenWidth(1);
            }
        }
        if (_error != null) {
            UiFormat.drawHrRow(dc, h * 88 / 100, _error);
        }
        Icons.backMarker(dc);
        if (!_ready) {
            return;
        }
        Icons.startMarker(dc, editing ? "check" : "play");
        if (editing) {
            Icons.focusMarkers(dc);
        } else if (count > 1) {
            Icons.browseMarkers(dc);
        }
    }

    // Big-value parts of one field.
    private function fieldParts(index as Number) as Array {
        var field = _fields[index];
        var value = _values[index];
        if (Model.sameString(field, "load100")) {
            return [[UiFormat.load100(value), "num"], [_unit + (_assistance ? " assist" : ""), "unit"]];
        }
        if (Model.sameString(field, "durationSec")) {
            return [[value.toString(), "num"], ["s", "unit"]];
        }
        return [[value.toString(), "num"], ["reps", "unit"]];
    }

    // UP: SELECT moves the selection up, EDIT raises the value.
    public function up() as Void {
        step(1);
    }

    public function down() as Void {
        step(-1);
    }

    private function step(direction as Number) as Void {
        _error = null;
        if (_mode == EditorLogic.MODE_SELECT) {
            _selected = EditorLogic.moveSelection(_selected, _fields.size(), -direction);
        } else {
            adjust(direction);
        }
        WatchUi.requestUpdate();
    }

    private function adjust(direction as Number) as Void {
        var field = _fields[_selected];
        var value = _values[_selected];
        if (Model.sameString(field, "load100")) {
            value += direction * _increment100 * _rapid.multiplier(direction);
            value = value < 0 ? 0 : (value > Model.MAX_LOAD100 ? Model.MAX_LOAD100 : value);
        } else if (Model.sameString(field, "durationSec")) {
            value += direction * _rapid.multiplier(direction);
            value = value < 1 ? 1 : (value > Model.MAX_DURATION_SEC ? Model.MAX_DURATION_SEC : value);
        } else {
            value += direction;
            value = value < 1 ? 1 : (value > Model.MAX_REPS ? Model.MAX_REPS : value);
        }
        _values[_selected] = value;
    }

    // START: enter the selected field, or keep the edited value.
    public function startPressed() as Void {
        if (!_ready) {
            return;
        }
        _error = null;
        if (_mode == EditorLogic.MODE_SELECT) {
            _before = _values[_selected];
            _rapid = new RapidPress();
        }
        _mode = EditorLogic.modeAfterStart(_mode);
        WatchUi.requestUpdate();
    }

    // BACK: in EDIT restore the field and return to SELECT; in SELECT save and close.
    public function backPressed() as Void {
        if (!EditorLogic.backClosesEditor(_mode)) {
            _values[_selected] = _before;
            _mode = EditorLogic.modeAfterBack(_mode);
            _error = null;
            WatchUi.requestUpdate();
            return;
        }
        close();
    }

    private function changed() as Boolean {
        for (var i = 0; i < _values.size(); i++) {
            if (_values[i] != _opened[i]) {
                return true;
            }
        }
        return false;
    }

    // Saves the confirmed values (next set: draft, logged set: correction) and pops the editor.
    // A second BACK after a failed save leaves without saving.
    private function close() as Void {
        var failedBefore = _error != null;
        if (!_ready || !changed() || failedBefore) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        var controller = getApp().controller();
        var context = editorContext();
        var saved = false;
        if (context != null && _correcting) {
            var actual = SessionLogic.copyDictionary((context as Dictionary)["completed"] as Dictionary);
            for (var i = 0; i < _fields.size(); i++) {
                actual[_fields[i]] = _values[i];
            }
            saved = controller.correctSet(_entryId, _slot, actual, Time.now().value());
        } else if (context != null) {
            saved = true;
            for (var i = 0; i < _fields.size(); i++) {
                if (_values[i] != _opened[i]) {
                    saved = saved && controller.updateDraft(_entryId, _slot, _fields[i], _values[i]);
                }
            }
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

    private function loadValues() as Void {
        var context = editorContext();
        if (context == null) {
            _error = "Set unavailable";
            return;
        }
        var data = context as Dictionary;
        var exercise = data["exercise"] as Dictionary;
        var values = (_correcting ? data["completed"] : data["draft"]) as Dictionary;
        _assistance = Model.sameString(exercise["loadType"], "assistance");
        _unit = UiFormat.unit(exercise);
        _fields = EditorLogic.fields(exercise["loadType"] as String);
        _increment100 = exercise["weightIncrement100"] instanceof Number ?
            exercise["weightIncrement100"] as Number : 100;
        var current = [];
        for (var i = 0; i < _fields.size(); i++) {
            var value = values[_fields[i]];
            current.add(value instanceof Number ? value as Number : (Model.sameString(_fields[i], "load100") ? 0 : 1));
        }
        _values = current as Array<Number>;
        _opened = [];
        for (var i = 0; i < _values.size(); i++) {
            _opened.add(_values[i]);
        }
        _selected = EditorLogic.initialSelection();
        _ready = true;
    }

    private function editorContext() as Dictionary? {
        var session = getApp().controller().session();
        if (session == null) {
            return null;
        }
        var exercise = UiFormat.exercise(session as Dictionary, _entryId);
        if (exercise == null) {
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

class SetEditDelegate extends KeyDelegate {
    private var _view as SetEditView;

    public function initialize(view as SetEditView) {
        _view = view;
        KeyDelegate.initialize();
    }

    public function onStartKey() as Boolean {
        _view.startPressed();
        return true;
    }

    public function onUpKey() as Boolean {
        _view.up();
        return true;
    }

    public function onDownKey() as Boolean {
        _view.down();
        return true;
    }

    public function onBackKey() as Boolean {
        _view.backPressed();
        return true;
    }
}
