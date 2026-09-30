import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class NumberEditView extends WatchUi.View {
    private var _entryId as String;
    private var _slot as Number;
    private var _field as String;
    private var _correcting as Boolean;
    private var _configKind as String?;
    private var _parentId as String?;
    private var _configTitle as String?;
    private var _value as Number = 0;
    private var _increment100 as Number = 100;
    private var _loadType as String? = null;
    private var _stepMode as Number = 0;
    private var _error as String? = null;

    public function initialize(entryId as String, slot as Number, field as String,
                               correcting as Boolean, configKind as String?,
                               parentId as String?, configTitle as String?) {
        _entryId = entryId;
        _slot = slot;
        _field = field;
        _correcting = correcting;
        _configKind = configKind;
        _parentId = parentId;
        _configTitle = configTitle;
        View.initialize();
        loadValue();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var caption = UiFormat.captionFont();
        var title = _configKind != null ? "EDIT CONFIG" :
            ("Set " + (_slot + 1).toString() + (_correcting ? " (done) · " : " · ") +
                fieldWord());
        var y = UiFormat.drawLine(dc, title, 72, Graphics.FONT_XTINY) + 6;
        y = UiFormat.drawLine(dc, fieldLabel(), y, Graphics.FONT_SMALL) + 6;
        y = UiFormat.drawLine(dc, displayValue(), y, Graphics.FONT_LARGE) + 10;
        if (isLoadField() || _configKind != null) {
            y = UiFormat.drawLine(dc, stepLabel() + " · MENU step", y, caption) + 4;
        }
        y = UiFormat.drawLine(dc, "UP/DOWN change · START save", y, caption) + 4;
        if (_error != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_BLACK);
            UiFormat.drawLine(dc, _error as String, y, caption);
        }
    }

    public function adjust(direction as Number) as Void {
        var step = isLoadField() ? stepSize() :
            (_configKind != null ? stepModeValue() : 1);
        var minimum = minimumValue();
        var maximum = maximumValue();
        var candidate = _value + direction * step;
        _value = candidate < minimum ? minimum : (candidate > maximum ? maximum : candidate);
        _error = null;
        WatchUi.requestUpdate();
    }

    public function save() as Void {
        var controller = getApp().controller();
        var saved = false;
        if (_configKind != null) {
            saved = controller.updateNumericConfig(_configKind as String,
                _parentId == null ? "" : _parentId as String,
                _entryId, _field, _value);
        } else if (_correcting) {
            var context = editorContext();
            if (context != null) {
                var completed = (context as Dictionary)["completed"] as Dictionary;
                var actual = SessionLogic.copyDictionary(completed);
                actual[_field] = _value;
                saved = controller.correctSet(_entryId, _slot, actual, Time.now().value());
            }
        } else {
            saved = controller.updateDraft(_entryId, _slot, _field, _value);
        }
        if (saved) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            if (Model.sameString(_configKind, "setting")) {
                Navigator.settings();
            }
        } else {
            var problem = controller.errorCode();
            _error = problem == Err.SETTINGS_SAVE_FAILED ||
                 problem == Err.SAVE_FAILED_RETRY_BEFORE_CONTINUING ?
                 "SAVE FAILED" : "INVALID VALUE";
            WatchUi.requestUpdate();
        }
    }

    public function cancel() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    public function cycleStep() as Void {
        if (isLoadField() || _configKind != null) {
            _stepMode = (_stepMode + 1) % 3;
            WatchUi.requestUpdate();
        }
    }

    private function loadValue() as Void {
        if (_configKind != null) {
            var configValue = getApp().controller().numericConfigValue(_configKind as String,
                _parentId == null ? "" : _parentId as String,
                _entryId, _field);
            if (configValue == null) {
                _error = "VALUE UNAVAILABLE";
                return;
            }
            _value = configValue as Number;
            return;
        }
        var context = editorContext();
        if (context == null) {
            _error = "SET UNAVAILABLE";
            return;
        }
        var data = context as Dictionary;
        var exercise = data["exercise"] as Dictionary;
        var values = _correcting ? data["completed"] as Dictionary : data["draft"] as Dictionary;
        _loadType = exercise["loadType"] as String;
        if (!validField() || values[_field] == null || !(values[_field] instanceof Number)) {
            _error = "FIELD UNAVAILABLE";
            return;
        }
        _value = values[_field] as Number;
        if (isLoadField()) {
            _increment100 = exercise["weightIncrement100"] as Number;
        }
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
        var slot = found as Dictionary;
        var completed = slot["completed"];
        if (_correcting ? completed == null : completed != null) {
            return null;
        }
        var context = {};
        context["exercise"] = exercise;
        context["draft"] = slot["draft"];
        context["completed"] = completed;
        return context;
    }

    private function validField() as Boolean {
        if (Model.sameString(_loadType, "weight") || Model.sameString(_loadType, "assistance")) {
            return Model.sameString(_field, "load100") || Model.sameString(_field, "reps");
        }
        if (Model.sameString(_loadType, "bodyweight")) {
            return Model.sameString(_field, "reps");
        }
        return Model.sameString(_loadType, "timed") && Model.sameString(_field, "durationSec");
    }

    private function isLoadField() as Boolean {
        return Model.sameString(_field, "load100") ||
            Model.sameString(_field, "startingLoad100") ||
            Model.sameString(_field, "increment100");
    }

    private function minimumValue() as Number {
        if (Model.sameString(_field, "defaultRestSec") || Model.sameString(_field, "restSec") ||
            Model.sameString(_field, "load100") || Model.sameString(_field, "startingLoad100")) {
            return 0;
        }
        return Model.sameString(_field, "increment100") ? 25 : 1;
    }

    private function maximumValue() as Number {
        if (isLoadField()) {
            return Model.sameString(_field, "increment100") ? 10000 : Model.MAX_LOAD100;
        }
        if (Model.sameString(_field, "defaultRestSec") || Model.sameString(_field, "restSec")) {
            return Model.MAX_REST_SEC;
        }
        if (Model.sameString(_field, "workingSetCount")) {
            return Model.MAX_SETS;
        }
        return Model.sameString(_field, "targetRepsMin") || Model.sameString(_field, "targetRepsMax") ?
            Model.MAX_REPS : Model.MAX_DURATION_SEC;
    }

    private function stepLabel() as String {
        if (isLoadField()) {
            return "STEP " + UiFormat.load100(stepSize()) + " kg";
        }
        var step = stepModeValue();
        return "STEP " + step.toString() +
            ((Model.sameString(_field, "defaultRestSec") || Model.sameString(_field, "restSec") ||
              Model.sameString(_field, "targetDurationSec")) ? " sec" : "");
    }

    private function stepModeValue() as Number {
        if (Model.sameString(_field, "increment100")) {
            return _stepMode == 1 ? 50 : (_stepMode == 2 ? 25 : 100);
        }
        return _stepMode == 1 ? 10 : (_stepMode == 2 ? 30 : 1);
    }

    private function fieldWord() as String {
        if (isLoadField()) {
            return Model.sameString(_loadType, "assistance") ? "assistance" : "load";
        }
        return Model.sameString(_field, "reps") ? "reps" : "duration";
    }

    private function fieldLabel() as String {
        if (_configKind != null) {
            return _configTitle as String;
        }
        if (isLoadField()) {
            return Model.sameString(_loadType, "assistance") ? "ASSISTANCE (KG)" : "LOAD (KG)";
        }
        return Model.sameString(_field, "reps") ? "REPS" : "DURATION (SEC)";
    }

    private function displayValue() as String {
        if (isLoadField()) {
            return UiFormat.load100(_value) + " kg";
        }
        if (Model.sameString(_field, "reps") || Model.sameString(_field, "targetRepsMin") ||
            Model.sameString(_field, "targetRepsMax")) {
            return _value.toString() + " reps";
        }
        if (Model.sameString(_field, "workingSetCount")) {
            return _value.toString() + " sets";
        }
        return _value.toString() + " sec";
    }

    private function stepSize() as Number {
        if (Model.sameString(_field, "increment100")) {
            return _stepMode == 1 ? 50 : (_stepMode == 2 ? 25 : 100);
        }
        if (_stepMode == 1) {
            return _increment100 * 5;
        }
        if (_stepMode == 2) {
            return 25;
        }
        return _increment100;
    }

}

class NumberEditDelegate extends WatchUi.BehaviorDelegate {
    private var _view as NumberEditView;

    public function initialize(view as NumberEditView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        var key = event.getKey();
        if (key == KEY_UP) {
            _view.adjust(1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.adjust(-1);
            return true;
        }
        if (key == KEY_ENTER) {
            _view.save();
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        return false;
    }

    public function onMenu() as Boolean {
        _view.cycleStep();
        return true;
    }

    public function onBack() as Boolean {
        _view.cancel();
        return true;
    }
}
