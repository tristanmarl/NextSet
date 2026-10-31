import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

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
        if (Navigator.staleWorkoutView()) {
            return;
        }
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
        if (Model.sameString(id, "edit_last") || Model.sameString(id, "delete_last")) {
            // In a superset the set just logged may belong to another member.
            var session = controller.session() as Dictionary;
            var target = SessionLogic.lastEditEntryId(session, _entryId);
            var lastExercise = target == null ? null : UiFormat.exercise(session, target as String);
            if (lastExercise == null) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                return;
            }
            var lastSlot = UiFormat.lastSlot(lastExercise as Dictionary);
            if (Model.sameString(id, "delete_last")) {
                // The confirmation pops itself and this menu.
                Navigator.confirmUndo(target as String, lastSlot, _view, _fromOverview);
                return;
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.setEdit(target as String, lastSlot, true, false);
            return;
        }
        if (Model.sameString(id, "log_timed")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _view.logPausedTimed();
            return;
        }
        if (Model.sameString(id, "edit_next")) {
            var nextExercise = UiFormat.exercise(controller.session() as Dictionary, _entryId) as Dictionary;
            var slot = SessionLogic.activeSlot(nextExercise);
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
            }
            getApp().markFocusHintSeen();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.setEdit(_entryId, slot, false, true);
            return;
        }
        if (Model.sameString(id, "skip_warmups")) {
            controller.skipWarmups(_entryId);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
            return;
        }
        if (Model.sameString(id, "rest_skip")) {
            controller.restAction("skip", Time.now().value());
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
            return;
        }
        if (Model.sameString(id, "finish")) {
            Navigator.review();
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

