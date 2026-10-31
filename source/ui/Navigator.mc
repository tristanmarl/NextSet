import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

module Navigator {
    // A workout view (Overview, Exercise, workout menus) that is still on the stack after the
    // workout ended must not act: show a clean Home instead. Returns true when it redirected.
    function staleWorkoutView() as Boolean {
        var controller = getApp().controller();
        if (controller.hasActiveSession() || controller.hasPendingFinalization()) {
            return false;
        }
        home();
        return true;
    }

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
        var view = new ConfirmView(title + "?", "Keep", title);
        WatchUi.pushView(view, new ConfirmDelegate(view, new QueueAction(action)), WatchUi.SLIDE_UP);
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

    function setEdit(entryId as String, slot as Number, correcting as Boolean,
                     single as Boolean) as Void {
        var view = new SetEditView(entryId, slot, correcting, single);
        WatchUi.pushView(view, new SetEditDelegate(view), WatchUi.SLIDE_UP);
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
        menu.addItem(new WatchUi.MenuItem("Diagnostics", null, "diagnostics", null));
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

    function summary(outcome as String) as Void {
        WatchUi.switchToView(new SummaryView(outcome), new SummaryDelegate(), WatchUi.SLIDE_UP);
    }

    function exitApp() as Void {
        getApp().stopTimer();
        System.exit();
    }

    function finalized(outcome as String) as Void {
        if (Model.sameString(outcome, "aborted")) {
            // A cancelled workout is discarded: back to Home with a notice instead of exiting.
            getApp().stopTimer();
            getApp().controller().setNotice("Workout cancelled");
            home();
        } else {
            summary(outcome);
        }
    }
}

class HomeDelegate extends KeyDelegate {
    private var _view as HomeView;

    public function initialize(view as HomeView) {
        _view = view;
        KeyDelegate.initialize();
    }

    // UP/DOWN pick a day only while no workout is active or being saved.
    private function browsing() as Boolean {
        return !getApp().controller().hasActiveSession() &&
            !getApp().controller().hasPendingFinalization() &&
            !getApp().controller().hasRecoverySaveFailure();
    }

    public function onUpKey() as Boolean {
        if (!browsing()) {
            return false;
        }
        _view.moveRoutine(-1);
        return true;
    }

    public function onDownKey() as Boolean {
        if (!browsing()) {
            return false;
        }
        _view.moveRoutine(1);
        return true;
    }

    public function onStartKey() as Boolean {
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

    public function onMenuKey() as Boolean {
        Navigator.homeMenu();
        return true;
    }

    public function onBackKey() as Boolean {
        if (getApp().controller().hasActiveSession()) {
            Navigator.review();
            return true;
        }
        if (!getApp().controller().hasPendingFinalization()) {
            // Idle Home leaves the app; stale workout views below it are never reached.
            Navigator.exitApp();
            return true;
        }
        return false;
    }
}

class StartingWorkoutDelegate extends KeyDelegate {
    public function initialize() {
        KeyDelegate.initialize();
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
        } else if (Model.sameString(id, "diagnostics")) {
            Navigator.feedback(getApp().controller().diagnostics());
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

class FeedbackDelegate extends KeyDelegate {
    public function initialize() {
        KeyDelegate.initialize();
    }

    public function onBackKey() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    public function onStartKey() as Boolean {
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

