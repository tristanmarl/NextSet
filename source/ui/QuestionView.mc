import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Values a program asks for after a set (RPE) or after an exercise (prompted state variables).
// Each question starts at the program's suggestion: UP/DOWN change it, START saves it, BACK keeps
// the suggestion. Answers are sent with the upload; an unanswered one sends the suggestion.
// Question: {"kind" => "rpe"|"var", "entryId", "slot" (rpe), "name" (var), "value"}.
class QuestionView extends WatchUi.View {
    private var _questions as Array<Dictionary>;
    private var _index as Number = 0;
    private var _value as Numeric = 0;
    private var _unit as String = "";
    private var _step as Numeric = 1;
    private var _decimals as Boolean = false;
    private var _isString as Boolean = false;
    private var _error as String? = null;
    public var openedAt as Number;

    public function initialize(questions as Array<Dictionary>) {
        View.initialize();
        _questions = questions;
        openedAt = System.getTimer();
        load();
    }

    private function load() as Void {
        var question = _questions[_index];
        _error = null;
        if (Model.sameString(question["kind"], "rpe")) {
            _value = (question["value"] as Number) / 10.0;
            _unit = "";
            _step = 0.5;
            _decimals = true;
            _isString = false;
            return;
        }
        var parsed = QuestionLogic.parse(question["value"]);
        _value = parsed[0] as Numeric;
        _unit = parsed[1] as String;
        _step = parsed[2] as Numeric;
        _decimals = parsed[3] as Boolean;
        _isString = question["value"] instanceof String;
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var h = dc.getHeight();
        var question = _questions[_index];
        UiFormat.drawTitle(dc, Model.sameString(question["kind"], "rpe") ? "RPE" :
            question["name"] as String, h * 25 / 100);
        var parts = [[QuestionLogic.format(_value, _decimals), "num"]];
        if (_unit.length() > 0) {
            parts.add([_unit, "unit"]);
        }
        UiFormat.drawBig(dc, parts, h * 57 / 100, 0, Graphics.COLOR_WHITE);
        if (_error != null) {
            UiFormat.drawHrRow(dc, h * 79 / 100, _error);
        }
        Icons.startMarker(dc, "check");
        Icons.backMarker(dc);
        Icons.focusMarkers(dc);
    }

    public function adjust(direction as Number) as Void {
        var question = _questions[_index];
        var next = _value + direction * _step;
        if (Model.sameString(question["kind"], "rpe")) {
            next = next < 1 ? 1 : (next > 10 ? 10 : next);
        } else if (next < 0) {
            next = 0;
        }
        _value = next;
        _error = null;
        WatchUi.requestUpdate();
    }

    // START saves this answer, BACK keeps the suggestion; then the next question or close.
    public function finish(save as Boolean) as Void {
        var question = _questions[_index];
        if (save) {
            var controller = getApp().controller();
            var saved = false;
            if (Model.sameString(question["kind"], "rpe")) {
                saved = controller.setRpe(question["entryId"] as String, question["slot"] as Number,
                    Math.round(_value * 10).toNumber());
            } else {
                var value = _isString ? QuestionLogic.format(_value, _decimals) + _unit :
                    (_decimals ? _value.toFloat() : Math.round(_value).toNumber());
                saved = controller.setUserVar(question["entryId"] as String, question["name"] as String,
                    value);
            }
            if (!saved) {
                _error = "Not saved";
                WatchUi.requestUpdate();
                return;
            }
        }
        if (_index + 1 < _questions.size()) {
            _index++;
            load();
            WatchUi.requestUpdate();
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class QuestionDelegate extends KeyDelegate {
    private var _view as QuestionView;

    public function initialize(view as QuestionView) {
        KeyDelegate.initialize();
        _view = view;
    }

    public function onUpKey() as Boolean {
        _view.adjust(1);
        return true;
    }

    public function onDownKey() as Boolean {
        _view.adjust(-1);
        return true;
    }

    public function onStartKey() as Boolean {
        // The press that logged the set must not also answer the question.
        if (!FinishGuard.tooSoon(_view.openedAt, System.getTimer())) {
            _view.finish(true);
        }
        return true;
    }

    public function onBackKey() as Boolean {
        _view.finish(false);
        return true;
    }
}
