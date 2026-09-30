import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class ActionsMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "finish")) {
            getApp().requestWorkoutFinish("completed");
        } else if (Model.sameString(id, "abort")) {
            Navigator.confirm(id);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class WorkoutCompleteDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "keep")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (Model.sameString(id, "finish")) {
            getApp().requestWorkoutFinish("completed");
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ExerciseMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _entryId as String;
    private var _view as ExerciseView;
    private var _fromOverview as Boolean;

    public function initialize(entryId as String, view as ExerciseView, fromOverview as Boolean) {
        _entryId = entryId;
        _view = view;
        _fromOverview = fromOverview;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        var controller = getApp().controller();
        if (Model.sameString(id, "add_set")) {
            if (!controller.addSet(_entryId)) {
                _view.showMessage("Could not add set");
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                if (_fromOverview) {
                    Navigator.home();
                }
                return;
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            if (_fromOverview) {
                Navigator.exercise(_entryId);
            } else {
                _view.showMessage("");
                WatchUi.requestUpdate();
            }
            return;
        }
        if (Model.sameString(id, "edit_last")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            // In a superset the set just logged may belong to another member.
            var target = SessionLogic.lastEditEntryId(controller.session() as Dictionary, _entryId);
            if (target != null) {
                Navigator.correctionMenu(target as String, _view, _fromOverview);
            }
            return;
        }
        if (Model.sameString(id, "weight_step")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.weightStepMenu(_entryId);
            return;
        }
        if (Model.sameString(id, "log_timed")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _view.logPausedTimed();
            return;
        }
        if (Model.sameString(id, "edit_next")) {
            var nextExercise = UiFormat.exercise(controller.session() as Dictionary, _entryId) as Dictionary;
            var slot = SessionLogic.nextSlot(nextExercise);
            if (Model.sameString(nextExercise["loadType"], "timed")) {
                var run = (controller.session() as Dictionary)["timedRun"];
                if (run instanceof Dictionary && Model.sameString(run["entryId"], _entryId) &&
                    run["slot"] == slot) {
                    if (!controller.pauseTimed(_entryId, slot, Time.now().value())) {
                        _view.showMessage("Save failed - timer still running");
                        WatchUi.popView(WatchUi.SLIDE_DOWN);
                        return;
                    }
                }
                if (!controller.cancelTimed(_entryId, slot)) {
                    _view.showMessage("Could not edit timed set");
                    WatchUi.popView(WatchUi.SLIDE_DOWN);
                    return;
                }
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                Navigator.numberEdit(_entryId, slot, "durationSec", false);
            } else {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                Navigator.numberEdit(_entryId, slot, "load100", false);
            }
            return;
        }
        if (Model.sameString(id, "rest_skip")) {
            controller.restAction("skip", Time.now().value());
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
            return;
        }
        if (Model.sameString(id, "workout")) {
            Navigator.actions();
            return;
        }
        if (Model.sameString(id, "skip_today")) {
            if (controller.closeExercise(_entryId, true)) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.requestUpdate();
                Navigator.promptIfWorkoutDone();
            } else {
                Navigator.feedback("Exercise unchanged; save failed");
            }
            return;
        }
        if (Model.sameString(id, "swap_today") || Model.sameString(id, "add_alt")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.programExercisePicker(_entryId,
                Model.sameString(id, "swap_today") ? "active_swap" : "active_add",
                _view, _fromOverview);
            return;
        }
        var session = controller.session() as Dictionary;
        var exercise = UiFormat.exercise(session, _entryId) as Dictionary;
        if (Model.sameString(id, "reopen")) {
            if (!controller.closeExercise(_entryId, false)) {
                _view.showMessage("Save failed - exercise unchanged");
            }
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.requestUpdate();
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class WeightStepDelegate extends WatchUi.Menu2InputDelegate {
    private var _entryId as String;

    public function initialize(entryId as String) {
        _entryId = entryId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var ok = getApp().controller().setWeightStep(_entryId, (item.getId() as String).toNumber() as Number);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (!ok) {
            Navigator.feedback("Weight step not saved");
        } else {
            WatchUi.requestUpdate();
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ProgramExerciseDelegate extends WatchUi.Menu2InputDelegate {
    private var _entryId as String;
    private var _mode as String;
    private var _view as ExerciseView;
    private var _fromOverview as Boolean;

    public function initialize(entryId as String, mode as String, view as ExerciseView,
                               fromOverview as Boolean) {
        _entryId = entryId;
        _mode = mode;
        _view = view;
        _fromOverview = fromOverview;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "none")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        var exercises = getApp().controller().programExercises();
        var definition = null;
        for (var i = 0; i < exercises.size(); i++) {
            if (Model.sameString((exercises[i] as Dictionary)["id"], id)) {
                definition = exercises[i] as Dictionary;
                break;
            }
        }
        var succeeded = false;
        if (definition != null) {
            var type = (definition as Dictionary)["loadType"] as String;
            succeeded = Model.sameString(_mode, "active_swap") ?
                getApp().controller().replaceSessionExercise(_entryId,
                    definition as Dictionary, type) :
                getApp().controller().addSessionAlternative(_entryId,
                    definition as Dictionary, type);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (!succeeded) {
            Navigator.feedback("Exercise unchanged");
        } else if (_fromOverview) {
            Navigator.exercise(_entryId);
        } else {
            _view.showMessage("");
            WatchUi.requestUpdate();
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class UndoConfirmMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _entryId as String;
    private var _slot as Number;
    private var _view as ExerciseView;
    private var _fromOverview as Boolean;

    public function initialize(entryId as String, slot as Number, view as ExerciseView,
                               fromOverview as Boolean) {
        _entryId = entryId;
        _slot = slot;
        _view = view;
        _fromOverview = fromOverview;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (Model.sameString(item.getId(), "cancel")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (!getApp().controller().undoSet(_entryId, _slot)) {
            _view.showMessage("Set not deleted");
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (_fromOverview && getApp().controller().errorMessage() != null) {
            Navigator.home();
        } else {
            WatchUi.requestUpdate();
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class CorrectionMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _entryId as String;
    private var _view as ExerciseView;
    private var _fromOverview as Boolean;

    public function initialize(entryId as String, view as ExerciseView, fromOverview as Boolean) {
        _entryId = entryId;
        _view = view;
        _fromOverview = fromOverview;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var session = getApp().controller().session() as Dictionary;
        var exercise = UiFormat.exercise(session, _entryId) as Dictionary;
        var slot = UiFormat.lastSlot(exercise);
        var id = item.getId() as String;
        if (Model.sameString(id, "corr_delete")) {
            Navigator.confirmUndo(_entryId, slot, _view, _fromOverview);
            return;
        }
        var field = Model.sameString(id, "corr_load") ? "load100" :
            (Model.sameString(id, "corr_reps") ? "reps" : "durationSec");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        Navigator.numberEdit(_entryId, slot, field, true);
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
