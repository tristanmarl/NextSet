import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

module Navigator {
    function home() as Void {
        var view = new HomeView();
        WatchUi.switchToView(view, new HomeDelegate(view), WatchUi.SLIDE_DOWN);
    }

    function startingWorkout() as Void {
        WatchUi.switchToView(new StartingWorkoutView(), new StartingWorkoutDelegate(),
            WatchUi.SLIDE_UP);
    }

    function finishingWorkout() as Void {
        WatchUi.switchToView(new FinishingWorkoutView(), new FinishingWorkoutDelegate(),
            WatchUi.SLIDE_UP);
    }

    function homeMenu() as Void {
        var menu = new WatchUi.Menu2({:title=>"Menu"});
        var controller = getApp().controller();
        if (controller.hasRecoverySaveFailure()) {
            menu.addItem(new WatchUi.MenuItem("Retry recovery save", null, "recover", null));
        } else if (controller.hasPendingFinalization()) {
            menu.addItem(new WatchUi.MenuItem("Retry workout save", null, "retry", null));
        }
        menu.addItem(new WatchUi.MenuItem("Workout history", null, "history", null));
        if (controller.configurationEditable()) {
            menu.addItem(new WatchUi.MenuItem("Sync routines", null, "sync", null));
            addUploadItems(menu, controller);
            menu.addItem(new WatchUi.MenuItem("Routines", null, "routines", null));
            menu.addItem(new WatchUi.MenuItem("Settings", null, "settings", null));
        }
        WatchUi.pushView(menu, new HomeMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function addUploadItems(menu as WatchUi.Menu2, controller as SessionController) as Void {
        var pending = controller.pendingUploadCount();
        if (pending > 0) {
            menu.addItem(new WatchUi.MenuItem("Retry workout upload",
                pending.toString() + " pending", "retry_upload", null));
        }
        if (controller.uploadQueueDamaged()) {
            menu.addItem(new WatchUi.MenuItem("Clear upload queue", null, "clear_queue", null));
        } else if (controller.hasStuckUpload()) {
            menu.addItem(new WatchUi.MenuItem("Skip this upload", null, "skip_upload", null));
        }
    }

    // Destructive queue actions need a second step; local workout history is never touched.
    function confirmQueue(action as String) as Void {
        var title = Model.sameString(action, "clear_queue") ? "Clear queue" :
            (Model.sameString(action, "clear_key") ? "Clear key" : "Skip upload");
        var menu = new WatchUi.Menu2({:title=>title + "?"});
        menu.addItem(new WatchUi.MenuItem("Keep", null, "cancel", null));
        menu.addItem(new WatchUi.MenuItem(title, null, action, null));
        WatchUi.pushView(menu, new ConfirmQueueDelegate(), WatchUi.SLIDE_UP);
    }

    function routineList() as Void {
        var controller = getApp().controller();
        var routines = controller.routineTemplates();
        var menu = new WatchUi.Menu2({:title=>"Routines"});
        for (var i = 0; i < routines.size(); i++) {
            var routine = routines[i] as Dictionary;
            var entries = routine["entries"] as Array;
            menu.addItem(new WatchUi.MenuItem(routine["name"] as String,
                entries.size().toString() + " exercises · W" + routine["week"].toString() +
                    " D" + routine["dayInWeek"].toString(),
                routine["id"], null));
        }
        if (routines.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("No routines synced", null, "empty", null));
        }
        WatchUi.switchToView(menu, new RoutineListDelegate(), WatchUi.SLIDE_UP);
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

    // Replaces the current exercise view (superset alternation) without growing the stack.
    function switchToExercise(entryId as String) as Void {
        var view = new ExerciseView(entryId);
        WatchUi.switchToView(view, new ExerciseDelegate(view), WatchUi.SLIDE_IMMEDIATE);
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
        menu.addItem(new WatchUi.MenuItem("Sync routines", null, "sync", null));
        menu.addItem(new WatchUi.MenuItem("Liftosaur key", controller.keyLabel(), "key", null));
        if (controller.hasKey()) {
            menu.addItem(new WatchUi.MenuItem("Test key", null, "test_key", null));
            menu.addItem(new WatchUi.MenuItem("Clear key", null, "clear_key", null));
        }
        addUploadItems(menu, controller);
        menu.addItem(new WatchUi.MenuItem("Default rest (new exercises)", controller.defaultRestSec().toString() + " sec",
            "default_rest", null));
        menu.addItem(new WatchUi.MenuItem(controller.vibrationEnabled() ? "Vibration: On" : "Vibration: Off",
            null, "vibration", null));
        WatchUi.switchToView(menu, new SettingsMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function syncRoutines() as Void {
        if (!getApp().controller().syncRoutines()) {
            var error = getApp().controller().errorMessage();
            feedback(error == null ? "Routine sync could not start" : error as String);
        }
    }

    function editTemplate(templateId as String) as Void {
        var routines = getApp().controller().routineTemplates();
        var selected = null;
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString((routines[i] as Dictionary)["id"], templateId)) {
                selected = routines[i] as Dictionary;
                break;
            }
        }
        if (selected == null) {
            return;
        }
        var menu = new WatchUi.Menu2({:title=>selected["name"] as String});
        var entries = selected["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var targets = entry["setTargets"] as Array;
            var detail = entry["workingSetCount"].toString() + " sets · " +
                targetPreview(targets, entry["loadType"] as String);
            var warmups = entry["warmups"] as Array;
            if (warmups.size() > 0) {
                detail += " · WU " + targetPreview(warmups, entry["loadType"] as String);
            }
            if (entry["restSec"] instanceof Number) {
                detail += " · rest " + entry["restSec"].toString() + "s";
            }
            if (entry["equipment"] instanceof String && (entry["equipment"] as String).length() > 0) {
                detail += " · " + (entry["equipment"] as String);
            }
            if (entry["superset"] instanceof String && (entry["superset"] as String).length() > 0) {
                detail += " · superset " + (entry["superset"] as String);
            }
            menu.addItem(new WatchUi.MenuItem(entry["name"] as String, detail,
                entry["entryId"] as String, null));
        }
        if (entries.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("No exercises", null, "read_only", null));
        }
        WatchUi.pushView(menu, new RoutineDetailDelegate(templateId), WatchUi.SLIDE_UP);
    }

    function targetPreview(targets as Array, loadType as String) as String {
        var result = "";
        var count = targets.size() < 3 ? targets.size() : 3;
        for (var i = 0; i < count; i++) {
            var target = targets[i] as Dictionary;
            if (i > 0) {
                result += "/";
            }
            if (Model.sameString(loadType, "timed")) {
                result += target["durationSec"].toString() + "s";
            } else if (target["load100"] instanceof Number) {
                result += UiFormat.load100(target["load100"] as Number) + "×" +
                    target["reps"].toString();
            } else {
                result += target["reps"].toString();
            }
        }
        if (targets.size() > count) {
            result += "/+" + (targets.size() - count).toString();
        }
        return result;
    }

    function routineExerciseDetail(templateId as String, entryId as String) as Void {
        var routines = getApp().controller().routineTemplates();
        for (var r = 0; r < routines.size(); r++) {
            var routine = routines[r] as Dictionary;
            if (!Model.sameString(routine["id"], templateId)) {
                continue;
            }
            var entries = routine["entries"] as Array;
            for (var e = 0; e < entries.size(); e++) {
                var entry = entries[e] as Dictionary;
                if (!Model.sameString(entry["entryId"], entryId)) {
                    continue;
                }
                var menu = new WatchUi.Menu2({:title=>entry["name"] as String});
                var targets = entry["setTargets"] as Array;
                for (var s = 0; s < targets.size(); s++) {
                    menu.addItem(new WatchUi.MenuItem("Set " + (s + 1).toString(),
                        targetPreview([targets[s]], entry["loadType"] as String), "read_only", null));
                }
                var warmups = entry["warmups"] as Array;
                for (var w = 0; w < warmups.size(); w++) {
                    menu.addItem(new WatchUi.MenuItem("Warm-up " + (w + 1).toString(),
                        targetPreview([warmups[w]], entry["loadType"] as String), "read_only", null));
                }
                var rest = entry["restSec"] instanceof Number ? entry["restSec"] as Number :
                    getApp().controller().defaultRestSec();
                menu.addItem(new WatchUi.MenuItem("Rest", rest.toString() + " sec",
                    "read_only", null));
                if (entry["equipment"] instanceof String &&
                    (entry["equipment"] as String).length() > 0) {
                    menu.addItem(new WatchUi.MenuItem("Equipment", entry["equipment"] as String,
                        "read_only", null));
                }
                if (entry["superset"] instanceof String &&
                    (entry["superset"] as String).length() > 0) {
                    menu.addItem(new WatchUi.MenuItem("Superset", entry["superset"] as String,
                        "read_only", null));
                }
                WatchUi.pushView(menu, new RoutineDetailDelegate(templateId), WatchUi.SLIDE_UP);
                return;
            }
        }
    }

    function programExercisePicker(entryId as String, mode as String,
                                   view as ExerciseView, fromOverview as Boolean) as Void {
        var exercises = getApp().controller().programExercises();
        var menu = new WatchUi.Menu2({:title=>"Program exercises"});
        for (var i = 0; i < exercises.size(); i++) {
            var exercise = exercises[i] as Dictionary;
            var detail = exercise["equipment"] instanceof String &&
                (exercise["equipment"] as String).length() > 0 ?
                exercise["equipment"] as String : exercise["loadType"] as String;
            menu.addItem(new WatchUi.MenuItem(exercise["name"] as String, detail,
                exercise["id"], null));
        }
        if (exercises.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("Sync routines first", null, "none", null));
        }
        WatchUi.pushView(menu,
            new ProgramExerciseDelegate(entryId, mode, view, fromOverview), WatchUi.SLIDE_UP);
    }

    function correctionMenu(entryId as String, view as ExerciseView, fromOverview as Boolean) as Void {
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
        menu.addItem(new WatchUi.MenuItem("Delete set " + (UiFormat.lastSlot(exercise) + 1).toString(),
            null, "corr_delete", null));
        WatchUi.pushView(menu, new CorrectionMenuDelegate(entryId, view, fromOverview), WatchUi.SLIDE_UP);
    }

    function actions() as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout"});
        var session = getApp().controller().session();
        if (session != null && SessionLogic.totals(session as Dictionary)["done"] > 0) {
            menu.addItem(new WatchUi.MenuItem("Finish workout", null, "finish", null));
        }
        menu.addItem(new WatchUi.MenuItem("Cancel workout", null, "abort", null));
        WatchUi.pushView(menu, new ActionsMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function activityResultActions() as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout saved"});
        if (getApp().controller().canRetryActivitySave()) {
            menu.addItem(new WatchUi.MenuItem("Retry Garmin save", null, "retry", null));
        }
        menu.addItem(new WatchUi.MenuItem("Keep local log and exit", null, "exit", null));
        WatchUi.pushView(menu, new ActivityResultDelegate(), WatchUi.SLIDE_UP);
    }

    function feedback(message as String) as Void {
        WatchUi.pushView(new FeedbackView(message), new FeedbackDelegate(), WatchUi.SLIDE_UP);
    }

    // Result of an async action: replaces a "Testing…" feedback still on screen, else pushes.
    function replaceFeedback(message as String) as Void {
        if (WatchUi.getCurrentView()[0] instanceof FeedbackView) {
            WatchUi.switchToView(new FeedbackView(message), new FeedbackDelegate(), WatchUi.SLIDE_IMMEDIATE);
        } else {
            feedback(message);
        }
    }

    // Key entry (empty field; the key is never shown). autoSync: start a routine sync once saved.
    function enterKey(autoSync as Boolean) as Void {
        WatchUi.pushView(new WatchUi.TextPicker(""), new KeyTextDelegate(autoSync), WatchUi.SLIDE_UP);
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
        var menu = new WatchUi.Menu2({:title=>"Delete set " + (slot + 1).toString() + "?"});
        menu.addItem(new WatchUi.MenuItem("Cancel", null, "cancel", null));
        menu.addItem(new WatchUi.MenuItem("Delete", null, "undo", null));
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
        var lastEntry = SessionLogic.lastEditEntryId(session, entryId);
        var last = lastEntry == null ? -1 : 0;
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
        if (last >= 0) {
            menu.addItem(new WatchUi.MenuItem("Edit last set", null, "edit_last", null));
        }
        if (Model.sameString(exercise["loadType"], "weight")) {
            menu.addItem(new WatchUi.MenuItem("Weight step",
                UiFormat.load100(exercise["weightIncrement100"] as Number) + " kg", "weight_step", null));
        }
        if ((exercise["slots"] as Array).size() < Model.MAX_SETS &&
            SessionLogic.totals(session)["planned"] < Model.MAX_SETS_PER_WORKOUT) {
            menu.addItem(new WatchUi.MenuItem("Add set", null, "add_set", null));
        }
        var running = session["timedRun"] instanceof Dictionary;
        if (Model.sameString(exercise["loadType"], "timed") && next >= 0) {
            var draft = ((exercise["slots"] as Array)[next] as Dictionary)["draft"] as Dictionary;
            if (!running && draft["measuredSec"] instanceof Number && draft["measuredSec"] > 0) {
                menu.addItem(new WatchUi.MenuItem("Log paused set",
                    draft["measuredSec"].toString() + " sec", "log_timed", null));
            }
        }
        var rest = session["rest"];
        if (!fromOverview && rest instanceof Dictionary &&
            Model.sameString(rest["state"], "running")) {
            menu.addItem(new WatchUi.MenuItem("Skip rest", null, "rest_skip", null));
        }
        if (next >= 0 && !running) {
            menu.addItem(new WatchUi.MenuItem("Skip exercise", null, "skip_today", null));
            // Swap when nothing is logged yet; otherwise add an alternative for the rest of the sets.
            menu.addItem(new WatchUi.MenuItem("Replace exercise", null,
                SessionLogic.completedCount(exercise) == 0 ? "swap_today" : "add_alt", null));
        }
        if (exercise["closedEarly"] == true) {
            menu.addItem(new WatchUi.MenuItem("Reopen exercise", null, "reopen", null));
        }
        menu.addItem(new WatchUi.MenuItem("Workout…", null, "workout", null));
        WatchUi.pushView(menu, new ExerciseMenuDelegate(entryId, view, fromOverview), WatchUi.SLIDE_UP);
    }

    function weightStepMenu(entryId as String) as Void {
        var menu = new WatchUi.Menu2({:title=>"Weight step"});
        var steps = [50, 100, 250, 500];
        for (var i = 0; i < steps.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(UiFormat.load100(steps[i]) + " kg", null,
                steps[i].toString(), null));
        }
        WatchUi.pushView(menu, new WeightStepDelegate(entryId), WatchUi.SLIDE_UP);
    }

    function summary(outcome as String) as Void {
        WatchUi.switchToView(new SummaryView(outcome), new SummaryDelegate(), WatchUi.SLIDE_UP);
    }

    function exitApp() as Void {
        getApp().stopTimer();
        System.exit();
    }

    // After skipping: when nothing is left to do and a set is logged, offer to save the workout.
    function promptIfWorkoutDone() as Void {
        var session = getApp().controller().session();
        if (session == null) {
            return;
        }
        var exercises = (session as Dictionary)["exercises"] as Array;
        for (var i = 0; i < exercises.size(); i++) {
            if (SessionLogic.nextSlot(exercises[i] as Dictionary) >= 0) {
                return;
            }
        }
        if (SessionLogic.totals(session as Dictionary)["done"] > 0) {
            workoutComplete();
        }
    }

    function finalized(outcome as String) as Void {
        if (Model.sameString(outcome, "aborted")) {
            exitApp();
        } else {
            summary(outcome);
        }
    }
}

class HomeDelegate extends WatchUi.BehaviorDelegate {
    private var _view as HomeView;

    public function initialize(view as HomeView) {
        _view = view;
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        if (getApp().controller().hasActiveSession() ||
            getApp().controller().hasPendingFinalization() ||
            getApp().controller().hasRecoverySaveFailure()) {
            return false;
        }
        var key = event.getKey();
        if (key == KEY_UP) {
            _view.moveRoutine(-1);
            return true;
        }
        if (key == KEY_DOWN) {
            _view.moveRoutine(1);
            return true;
        }
        return false;
    }

    public function onSelect() as Boolean {
        var controller = getApp().controller();
        if (controller.hasRecoverySaveFailure()) {
            if (controller.retryRecovery(Time.now().value())) {
                getApp().startTimer(true);
                Navigator.overview();
            }
        } else if (controller.hasPendingFinalization()) {
            getApp().retryPendingFinalization();
        } else if (controller.hasActiveSession()) {
            Navigator.resumeWorkout();
        } else {
            var templateId = _view.selectedTemplateId();
            if (templateId != null) {
                getApp().requestWorkoutStart(templateId as String);
            } else if (!controller.hasKey()) {
                Navigator.enterKey(true);
            } else if (!controller.syncRoutines()) {
                var error = controller.errorMessage();
                Navigator.feedback(error == null ? "Routine sync could not start" :
                    error as String);
            }
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

class StartingWorkoutDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onKey(event as KeyEvent) as Boolean {
        return true;
    }

    public function onSelect() as Boolean {
        return true;
    }

    public function onMenu() as Boolean {
        return true;
    }

    public function onBack() as Boolean {
        return true;
    }
}

class HomeMenuDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (Model.sameString(item.getId(), "retry")) {
            getApp().retryPendingFinalization();
        } else if (Model.sameString(item.getId(), "recover")) {
            if (getApp().controller().retryRecovery(Time.now().value())) {
                getApp().startTimer(true);
                Navigator.overview();
            }
        } else if (Model.sameString(item.getId(), "resume")) {
            Navigator.resumeWorkout();
        } else if (Model.sameString(item.getId(), "history")) {
            Navigator.history();
        } else if (Model.sameString(item.getId(), "sync")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.syncRoutines();
        } else if (Model.sameString(item.getId(), "retry_upload")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            getApp().controller().retryUploads();
        } else if (Model.sameString(item.getId(), "skip_upload") ||
            Model.sameString(item.getId(), "clear_queue")) {
            Navigator.confirmQueue(item.getId() as String);
        } else if (Model.sameString(item.getId(), "routines")) {
            Navigator.routineList();
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
            Navigator.configNumberEdit("setting", "", "", "defaultRestSec", "Default rest (new)");
        } else if (Model.sameString(id, "sync")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.syncRoutines();
        } else if (Model.sameString(id, "retry_upload")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            getApp().controller().retryUploads();
        } else if (Model.sameString(id, "skip_upload") || Model.sameString(id, "clear_queue") ||
            Model.sameString(id, "clear_key")) {
            Navigator.confirmQueue(id);
        } else if (Model.sameString(id, "key")) {
            Navigator.enterKey(false);
        } else if (Model.sameString(id, "test_key")) {
            var problem = getApp().controller().testKey();
            Navigator.feedback(problem == null ? "Testing…" : problem);
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

class RoutineDetailDelegate extends WatchUi.Menu2InputDelegate {
    private var _routineId as String;

    public function initialize(routineId as String) {
        _routineId = routineId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String && !Model.sameString(id, "read_only")) {
            Navigator.routineExerciseDetail(_routineId, id as String);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
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

class FeedbackView extends WatchUi.View {
    private var _message as String;

    public function initialize(message as String) {
        _message = message;
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var lines = UiFormat.wrapTitle(dc, _message, Graphics.FONT_SMALL, dc.getWidth() * 0.72);
        var height = lines.size() * dc.getFontHeight(Graphics.FONT_SMALL);
        var y = (dc.getHeight() - height) / 2;
        for (var i = 0; i < lines.size(); i++) {
            y = UiFormat.drawLine(dc, lines[i] as String, y, Graphics.FONT_SMALL);
        }
        UiFormat.drawLine(dc, "BACK", y + 10, Graphics.FONT_XTINY);
    }
}

class FeedbackDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    public function onSelect() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}

class RoutineListDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var itemId = item.getId() as String;
        if (Model.sameString(itemId, "empty")) {
            Navigator.syncRoutines();
        } else {
            Navigator.editTemplate(itemId);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class KeyTextDelegate extends WatchUi.TextPickerDelegate {
    private var _autoSync as Boolean;

    public function initialize(autoSync as Boolean) {
        _autoSync = autoSync;
        TextPickerDelegate.initialize();
    }

    public function onTextEntered(text as String, changed as Boolean) as Boolean {
        getApp().afterKeyEntry(text, _autoSync);
        return true;
    }

    public function onCancel() as Boolean {
        return true;
    }
}

class ConfirmQueueDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (Model.sameString(id, "cancel")) {
            return;
        }
        var controller = getApp().controller();
        if (Model.sameString(id, "clear_key")) {
            // Back to a refreshed Settings (the key label and key items change).
            controller.clearKey();
            Navigator.settings();
            return;
        }
        var done = Model.sameString(id, "clear_queue") ? controller.clearUploadQueue() :
            (Model.sameString(id, "clear_key") ? controller.clearKey() : controller.skipUpload());
        // Also leave the parent menu so Home shows the result.
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (!done) {
            Navigator.feedback("Could not change the upload queue");
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
        getApp().requestWorkoutFinish("aborted");
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
