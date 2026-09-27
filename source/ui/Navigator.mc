import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

module Navigator {
    function home() as Void {
        WatchUi.switchToView(new HomeView(), new HomeDelegate(), WatchUi.SLIDE_DOWN);
    }

    function homeMenu() as Void {
        var menu = new WatchUi.Menu2({:title=>"Menu"});
        var controller = getApp().controller();
        if (controller.hasRecoverySaveFailure()) {
            menu.addItem(new WatchUi.MenuItem("Retry recovery save", null, "recover", null));
        } else if (controller.hasPendingFinalization()) {
            menu.addItem(new WatchUi.MenuItem("Retry workout save", null, "retry", null));
        } else if (controller.hasActiveSession()) {
            menu.addItem(new WatchUi.MenuItem("Resume workout", null, "resume", null));
        } else {
            menu.addItem(new WatchUi.MenuItem("New workout", null, "new", null));
        }
        menu.addItem(new WatchUi.MenuItem("Workout history", null, "history", null));
        if (controller.configurationEditable()) {
            menu.addItem(new WatchUi.MenuItem("Upper setup", null, "edit_upper", null));
            menu.addItem(new WatchUi.MenuItem("Lower setup", null, "edit_lower", null));
            menu.addItem(new WatchUi.MenuItem("Load increments", null, "increments", null));
            menu.addItem(new WatchUi.MenuItem("Settings", null, "settings", null));
        }
        WatchUi.pushView(menu, new HomeMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function templates() as Void {
        if (!Catalog.valid()) {
            return;
        }
        var menu = new WatchUi.Menu2({:title=>"Select workout"});
        var templates = Catalog.templates();
        for (var i = 0; i < templates.size(); i++) {
            var workout = templates[i] as Dictionary;
            var label = workout["name"] as String;
            var detail = getApp().controller().templateTotalSets(workout["id"] as String).toString() + " sets";
            menu.addItem(new WatchUi.MenuItem(label, detail, workout["id"], null));
        }
        WatchUi.pushView(menu, new TemplateMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function overview() as Void {
        var session = getApp().controller().session();
        if (session == null) {
            home();
            return;
        }
        var view = new OverviewView();
        WatchUi.pushView(view, new OverviewDelegate(view), WatchUi.SLIDE_UP);
    }

    function resumeWorkout() as Void {
        var controller = getApp().controller();
        if (controller.isWorkoutPaused()) {
            if (!controller.resumeWorkout(Time.now().value())) {
                home();
                return;
            }
            getApp().startTimer(true);
        }
        overview();
    }

    function history() as Void {
        var view = new HistoryView();
        WatchUi.pushView(view, new HistoryDelegate(view), WatchUi.SLIDE_UP);
    }

    function exercise(entryId as String) as Void {
        var session = getApp().controller().session();
        if (session != null) {
            var exercise = UiFormat.exercise(session as Dictionary, entryId);
            if (exercise != null && SessionLogic.nextSlot(exercise as Dictionary) < 0) {
                exerciseMenuForEntry(entryId, new ExerciseView(entryId), true);
                return;
            }
        }
        var view = new ExerciseView(entryId);
        WatchUi.pushView(view, new ExerciseDelegate(view), WatchUi.SLIDE_UP);
    }

    function numberEdit(entryId as String, slot as Number, field as String,
                        correcting as Boolean) as Void {
        var view = new NumberEditView(entryId, slot, field, correcting, null, null, null);
        WatchUi.pushView(view, new NumberEditDelegate(view), WatchUi.SLIDE_UP);
    }

    function configNumberEdit(kind as String, parentId as String, id as String,
                              field as String, title as String) as Void {
        var view = new NumberEditView(id, 0, field, false, kind, parentId, title);
        WatchUi.pushView(view, new NumberEditDelegate(view), WatchUi.SLIDE_UP);
    }

    function settings() as Void {
        var menu = new WatchUi.Menu2({:title=>"Settings"});
        var controller = getApp().controller();
        menu.addItem(new WatchUi.MenuItem("Default rest", controller.defaultRestSec().toString() + " sec",
            "default_rest", null));
        menu.addItem(new WatchUi.MenuItem(controller.vibrationEnabled() ? "Vibration: On" : "Vibration: Off",
            null, "vibration", null));
        WatchUi.switchToView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function editTemplate(templateId as String) as Void {
        var template = Catalog.template(templateId);
        if (template == null || !getApp().controller().configurationEditable()) {
            return;
        }
        var templateName = (template as Dictionary)["name"] as String;
        var menu = new WatchUi.Menu2({:title=>templateName + " numbers"});
        var entries = (template as Dictionary)["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var definition = Catalog.exercise(entry["exerciseId"] as String) as Dictionary;
            menu.addItem(new WatchUi.MenuItem(definition["name"] as String, null,
                entry["entryId"], null));
        }
        WatchUi.switchToView(menu, new TemplateEntryMenuDelegate(templateId), WatchUi.SLIDE_UP);
    }

    function templateEntryFields(templateId as String, entryId as String,
                                 replace as Boolean) as Void {
        var entry = getApp().controller().templateEntry(templateId, entryId);
        if (entry == null) {
            return;
        }
        var exerciseId = (entry as Dictionary)["exerciseId"] as String;
        var definition = Catalog.exercise(exerciseId) as Dictionary;
        var type = definition["loadType"] as String;
        var menu = new WatchUi.Menu2({:title=>definition["name"] as String});
        var fields = ["workingSetCount"];
        if (Model.sameString(type, "timed")) {
            fields.add("targetDurationSec");
        } else {
            fields.add("targetRepsMin");
            fields.add("targetRepsMax");
        }
        if (Model.sameString(type, "weight") || Model.sameString(type, "assistance")) {
            fields.add("startingLoad100");
        }
        fields.add("restSec");
        for (var i = 0; i < fields.size(); i++) {
            var field = fields[i] as String;
            var value = getApp().controller().numericConfigValue("template", templateId, entryId, field);
            var detail = value == null ? "" : configValueLabel(field, value as Number);
            menu.addItem(new WatchUi.MenuItem(configFieldLabel(field), detail, field, null));
        }
        var delegate = new TemplateFieldMenuDelegate(templateId, entryId);
        if (replace) {
            WatchUi.switchToView(menu, delegate, WatchUi.SLIDE_UP);
        } else {
            WatchUi.pushView(menu, delegate, WatchUi.SLIDE_UP);
        }
    }

    function configFieldLabel(field as String) as String {
        if (Model.sameString(field, "workingSetCount")) {
            return "Set count";
        }
        if (Model.sameString(field, "targetRepsMin")) {
            return "Minimum reps";
        }
        if (Model.sameString(field, "targetRepsMax")) {
            return "Maximum reps";
        }
        if (Model.sameString(field, "targetDurationSec")) {
            return "Target duration";
        }
        if (Model.sameString(field, "startingLoad100")) {
            return "Starting load";
        }
        if (Model.sameString(field, "defaultRestSec")) {
            return "Default rest";
        }
        return "Rest after set";
    }

    function configValueLabel(field as String, value as Number) as String {
        if (Model.sameString(field, "startingLoad100")) {
            return UiFormat.load100(value) + " kg";
        }
        if (Model.sameString(field, "workingSetCount")) {
            return value.toString() + " sets";
        }
        if (Model.sameString(field, "targetRepsMin") || Model.sameString(field, "targetRepsMax")) {
            return value.toString() + " reps";
        }
        return value.toString() + " sec";
    }

    function editIncrements() as Void {
        var menu = new WatchUi.Menu2({:title=>"Load increments"});
        var exercises = Catalog.exercises();
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            if (Model.sameString(exercise["loadType"], "weight") ||
                Model.sameString(exercise["loadType"], "assistance")) {
                var value = getApp().controller().numericConfigValue("increment", "",
                    exercise["id"] as String, "increment100");
                menu.addItem(new WatchUi.MenuItem(exercise["name"] as String,
                    value == null ? "" : UiFormat.load100(value as Number) + " kg",
                    exercise["id"], null));
            }
        }
        WatchUi.switchToView(menu, new IncrementMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function correctionMenu(entryId as String) as Void {
        var session = getApp().controller().session() as Dictionary;
        var exercise = UiFormat.exercise(session, entryId) as Dictionary;
        var menu = new WatchUi.Menu2({:title=>"Edit last set"});
        if (Model.sameString(exercise["loadType"], "weight") ||
            Model.sameString(exercise["loadType"], "assistance")) {
            menu.addItem(new WatchUi.MenuItem("Edit load", null, "corr_load", null));
            menu.addItem(new WatchUi.MenuItem("Edit reps", null, "corr_reps", null));
        } else if (Model.sameString(exercise["loadType"], "timed")) {
            menu.addItem(new WatchUi.MenuItem("Edit duration", null, "corr_duration", null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Edit reps", null, "corr_reps", null));
        }
        WatchUi.pushView(menu, new CorrectionMenuDelegate(entryId), WatchUi.SLIDE_UP);
    }

    function actions() as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout"});
        var session = getApp().controller().session();
        if (session != null && SessionLogic.totals(session as Dictionary)["done"] > 0) {
            menu.addItem(new WatchUi.MenuItem("Save workout", null, "finish", null));
        }
        menu.addItem(new WatchUi.MenuItem("Cancel workout", null, "abort", null));
        WatchUi.pushView(menu, new ActionsMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function workoutComplete() as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout complete"});
        menu.addItem(new WatchUi.MenuItem("Save workout", null, "finish", null));
        menu.addItem(new WatchUi.MenuItem("Keep working", null, "keep", null));
        WatchUi.pushView(menu, new WorkoutCompleteDelegate(), WatchUi.SLIDE_UP);
    }

    function confirm(action as String) as Void {
        var canceling = Model.sameString(action, "abort");
        var title = canceling ? "Cancel workout?" : "Save workout?";
        var menu = new WatchUi.Menu2({:title=>title});
        menu.addItem(new WatchUi.MenuItem(canceling ? "Keep workout" : "Keep working",
            null, "cancel", null));
        menu.addItem(new WatchUi.MenuItem(canceling ? "Cancel workout" : "Save workout",
            null, action, null));
        WatchUi.pushView(menu, new ConfirmMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function confirmUndo(entryId as String, slot as Number, view as ExerciseView,
                         fromOverview as Boolean) as Void {
        var menu = new WatchUi.Menu2({:title=>"Undo set " + (slot + 1).toString() + "?"});
        menu.addItem(new WatchUi.MenuItem("Cancel", null, "cancel", null));
        menu.addItem(new WatchUi.MenuItem("Undo", null, "undo", null));
        WatchUi.pushView(menu, new UndoConfirmMenuDelegate(entryId, slot, view, fromOverview), WatchUi.SLIDE_UP);
    }

    function exerciseMenu(entryId as String, view as ExerciseView) as Void {
        exerciseMenuForEntry(entryId, view, false);
    }

    function exerciseMenuForEntry(entryId as String, view as ExerciseView,
                                  fromOverview as Boolean) as Void {
        var menu = new WatchUi.Menu2({:title=>"Exercise"});
        var session = getApp().controller().session() as Dictionary;
        var exercise = UiFormat.exercise(session, entryId) as Dictionary;
        var next = SessionLogic.nextSlot(exercise);
        var last = UiFormat.lastSlot(exercise);
        if (Model.sameString(exercise["loadType"], "weight") ||
            Model.sameString(exercise["loadType"], "assistance")) {
            if (next >= 0) {
                var draft = ((exercise["slots"] as Array)[next] as Dictionary)["draft"] as Dictionary;
                var loadLabel = UiFormat.load100(draft["load100"] as Number) +
                    (Model.sameString(exercise["loadType"], "assistance") ? " kg assist" : " kg");
                var action = Model.sameString(exercise["loadType"], "assistance") ?
                    "Change assistance" : "Change load";
                menu.addItem(new WatchUi.MenuItem(action, loadLabel, "edit_next", null));
            }
        } else if (next >= 0 && Model.sameString(exercise["loadType"], "timed")) {
            menu.addItem(new WatchUi.MenuItem("Edit duration", null, "edit_next", null));
        }
        if ((exercise["slots"] as Array).size() < Model.MAX_SETS &&
            SessionLogic.totals(session)["planned"] < Model.MAX_SETS_PER_WORKOUT) {
            menu.addItem(new WatchUi.MenuItem("Add set", null, "add_set", null));
        }
        if (Model.sameString(exercise["loadType"], "timed") && next >= 0) {
            var run = session["timedRun"];
            var draft = ((exercise["slots"] as Array)[next] as Dictionary)["draft"] as Dictionary;
            if (!(run instanceof Dictionary) && draft["measuredSec"] instanceof Number &&
                draft["measuredSec"] > 0) {
                menu.addItem(new WatchUi.MenuItem("Log paused set",
                    draft["measuredSec"].toString() + " sec", "log_timed", null));
            }
        }
        if (last >= 0) {
            menu.addItem(new WatchUi.MenuItem("Edit last set", null, "edit_last", null));
        }
        if (last >= 0) {
            menu.addItem(new WatchUi.MenuItem("Undo set " + (last + 1).toString(), null, "undo", null));
        }
        var rest = session["rest"];
        if (!fromOverview && rest instanceof Dictionary &&
            Model.sameString(rest["state"], "running")) {
            menu.addItem(new WatchUi.MenuItem("Skip rest", null, "rest_skip", null));
        }
        if (exercise["closedEarly"] == true) {
            menu.addItem(new WatchUi.MenuItem("Reopen exercise", null, "reopen", null));
        }
        WatchUi.pushView(menu, new ExerciseMenuDelegate(entryId, view, fromOverview), WatchUi.SLIDE_UP);
    }

    function summary(outcome as String) as Void {
        WatchUi.switchToView(new SummaryView(outcome), new SummaryDelegate(), WatchUi.SLIDE_UP);
    }

    function finalized(outcome as String) as Void {
        if (Model.sameString(outcome, "aborted")) {
            getApp().stopTimer();
            System.exit();
        } else {
            summary(outcome);
        }
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        var controller = getApp().controller();
        if (controller.hasRecoverySaveFailure()) {
            if (controller.retryRecovery(Time.now().value())) {
                getApp().startTimer(true);
                Navigator.overview();
            }
        } else if (controller.hasPendingFinalization()) {
            if (controller.retryFinalization()) {
                var session = controller.session() as Dictionary;
                Navigator.finalized(session["status"] as String);
            }
        } else if (controller.hasActiveSession()) {
            Navigator.resumeWorkout();
        } else {
            Navigator.templates();
        }
        return true;
    }

    public function onMenu() as Boolean {
        Navigator.homeMenu();
        return true;
    }

    public function onBack() as Boolean {
        if (getApp().controller().hasActiveSession()) {
            Navigator.actions();
            return true;
        }
        return false;
    }
}

class HomeMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (Model.sameString(item.getId(), "retry")) {
            if (getApp().controller().retryFinalization()) {
                var session = getApp().controller().session() as Dictionary;
                Navigator.finalized(session["status"] as String);
            }
        } else if (Model.sameString(item.getId(), "recover")) {
            if (getApp().controller().retryRecovery(Time.now().value())) {
                getApp().startTimer(true);
                Navigator.overview();
            }
        } else if (Model.sameString(item.getId(), "new")) {
            Navigator.templates();
        } else if (Model.sameString(item.getId(), "resume")) {
            Navigator.resumeWorkout();
        } else if (Model.sameString(item.getId(), "history")) {
            Navigator.history();
        } else if (Model.sameString(item.getId(), "edit_upper")) {
            Navigator.editTemplate("upper");
        } else if (Model.sameString(item.getId(), "edit_lower")) {
            Navigator.editTemplate("lower");
        } else if (Model.sameString(item.getId(), "increments")) {
            Navigator.editIncrements();
        } else if (Model.sameString(item.getId(), "settings")) {
            Navigator.settings();
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "default_rest")) {
            Navigator.configNumberEdit("setting", "", "", "defaultRestSec", "Default rest");
        } else if (Model.sameString(id, "vibration")) {
            if (getApp().controller().toggleVibration()) {
                Navigator.settings();
            }
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class TemplateEntryMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;

    public function initialize(templateId as String) {
        _templateId = templateId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        Navigator.templateEntryFields(_templateId, item.getId() as String, false);
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class TemplateFieldMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String;

    public function initialize(templateId as String, entryId as String) {
        _templateId = templateId;
        _entryId = entryId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var field = item.getId() as String;
        Navigator.configNumberEdit("template", _templateId, _entryId, field,
            Navigator.configFieldLabel(field));
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class IncrementMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        Navigator.configNumberEdit("increment", "", item.getId() as String,
            "increment100", "Load increment");
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class TemplateMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var ok = getApp().controller().startWorkout(item.getId() as String, Time.now().value());
        if (ok) {
            getApp().startTimer(false);
            Navigator.overview();
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.home();
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ActionsMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "finish")) {
            if (getApp().controller().finish("completed", Time.now().value())) {
                Navigator.finalized("completed");
            } else {
                Navigator.home();
            }
        } else if (Model.sameString(id, "abort")) {
            Navigator.confirm(id);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ConfirmMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "cancel")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        if (!Model.sameString(id, "abort")) {
            return;
        }
        if (getApp().controller().finish("aborted", Time.now().value())) {
            Navigator.finalized("aborted");
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.home();
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
            if (getApp().controller().finish("completed", Time.now().value())) {
                Navigator.finalized("completed");
            } else {
                Navigator.home();
            }
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
            Navigator.correctionMenu(_entryId);
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
        var session = controller.session() as Dictionary;
        var exercise = UiFormat.exercise(session, _entryId) as Dictionary;
        if (Model.sameString(id, "undo")) {
            Navigator.confirmUndo(_entryId, UiFormat.lastSlot(exercise), _view, _fromOverview);
            return;
        } else if (Model.sameString(id, "reopen")) {
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
            _view.showMessage("Undo not saved");
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

    public function initialize(entryId as String) {
        _entryId = entryId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var session = getApp().controller().session() as Dictionary;
        var exercise = UiFormat.exercise(session, _entryId) as Dictionary;
        var slot = UiFormat.lastSlot(exercise);
        var id = item.getId() as String;
        var field = Model.sameString(id, "corr_load") ? "load100" :
            (Model.sameString(id, "corr_reps") ? "reps" : "durationSec");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        Navigator.numberEdit(_entryId, slot, field, true);
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
