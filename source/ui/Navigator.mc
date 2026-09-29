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
            menu.addItem(new WatchUi.MenuItem("Edit Upper", null, "edit_upper", null));
            menu.addItem(new WatchUi.MenuItem("Edit Lower", null, "edit_lower", null));
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
        var templates = getApp().controller().routineTemplates();
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
        var controller = getApp().controller();
        var templates = controller.routineTemplates();
        var template = null;
        for (var i = 0; i < templates.size(); i++) {
            if (Model.sameString(templates[i]["id"], templateId)) {
                template = templates[i] as Dictionary;
                break;
            }
        }
        if (template == null || !getApp().controller().configurationEditable()) {
            return;
        }
        var templateName = (template as Dictionary)["name"] as String;
        var menu = new WatchUi.Menu2({:title=>"Edit " + templateName});
        var entries = (template as Dictionary)["entries"] as Array;
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var definition = controller.templateExercise(templateId, entry["entryId"] as String) as Dictionary;
            var value = entry["workingSetCount"].toString() + " × " +
                (Model.sameString(definition["loadType"], "timed") ?
                    entry["targetDurationSec"].toString() + " sec" :
                    (entry["targetRepsMin"] == entry["targetRepsMax"] ?
                        entry["targetRepsMin"].toString() + " reps" :
                        entry["targetRepsMin"].toString() + "–" +
                        entry["targetRepsMax"].toString() + " reps"));
            menu.addItem(new WatchUi.MenuItem(definition["name"] as String, value,
                entry["entryId"], null));
        }
        menu.addItem(new WatchUi.MenuItem("Add exercise", null, "add_exercise", null));
        WatchUi.switchToView(menu, new RoutineSetupDelegate(templateId), WatchUi.SLIDE_UP);
    }

    function routineEntryOptions(templateId as String, entryId as String) as Void {
        var controller = getApp().controller();
        var entry = controller.templateEntry(templateId, entryId);
        var definition = controller.templateExercise(templateId, entryId);
        if (entry == null || definition == null) {
            editTemplate(templateId);
            return;
        }
        var entries = null;
        var routines = controller.routineTemplates();
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString(routines[i]["id"], templateId)) {
                entries = routines[i]["entries"] as Array;
                break;
            }
        }
        if (entries == null) {
            editTemplate(templateId);
            return;
        }
        var index = -1;
        for (var i = 0; i < (entries as Array).size(); i++) {
            if (Model.sameString(entries[i]["entryId"], entryId)) {
                index = i;
                break;
            }
        }
        var menu = new WatchUi.Menu2({:title=>definition["name"] as String});
        menu.addItem(new WatchUi.MenuItem("Mapping details", null, "mapping", null));
        menu.addItem(new WatchUi.MenuItem("Edit values", null, "edit_values", null));
        menu.addItem(new WatchUi.MenuItem("Replace exercise", null, "replace", null));
        if (index > 0) {
            menu.addItem(new WatchUi.MenuItem("Move up", null, "move_up", null));
        }
        if (index >= 0 && index < (entries as Array).size() - 1) {
            menu.addItem(new WatchUi.MenuItem("Move down", null, "move_down", null));
        }
        menu.addItem(new WatchUi.MenuItem("Remove exercise", null, "remove", null));
        WatchUi.pushView(menu, new RoutineEntryDelegate(templateId, entryId), WatchUi.SLIDE_UP);
    }

    function mappingDetails(templateId as String, entryId as String) as Void {
        WatchUi.pushView(new MappingDetailView(templateId, entryId),
            new MappingDetailDelegate(), WatchUi.SLIDE_UP);
    }

    function templateEntryFields(templateId as String, entryId as String,
                                 replace as Boolean) as Void {
        var entry = getApp().controller().templateEntry(templateId, entryId);
        if (entry == null) {
            return;
        }
        var definition = getApp().controller().templateExercise(templateId, entryId) as Dictionary;
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
            fields.add("increment100");
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

    function garminCategoryPage(templateId as String, entryId as String?, page as Number,
                                mode as String, push as Boolean) as Void {
        var categories = Catalog.garminCategories();
        var pageSize = 14;
        var pages = pageCount(categories.size(), pageSize);
        var menu = new WatchUi.Menu2({:title=>"Choose category " + (page + 1).toString() + "/" + pages.toString()});
        menu.addItem(new WatchUi.MenuItem("Recent", null, "recent", null));
        menu.addItem(new WatchUi.MenuItem("Used in routines", null, "used", null));
        var start = page * pageSize;
        var end = start + pageSize;
        if (end > categories.size()) {
            end = categories.size();
        }
        for (var i = start; i < end; i++) {
            menu.addItem(new WatchUi.MenuItem(categories[i]["name"] as String, null,
                categories[i]["code"], null));
        }
        if (page > 0) {
            menu.addItem(new WatchUi.MenuItem("Previous categories", null, "prev", null));
        }
        if (page + 1 < pages) {
            menu.addItem(new WatchUi.MenuItem("More categories", null, "next", null));
        }
        var delegate = new GarminCategoryDelegate(templateId, entryId, page, mode);
        if (push) {
            WatchUi.pushView(menu, delegate, WatchUi.SLIDE_UP);
        } else {
            WatchUi.switchToView(menu, delegate, WatchUi.SLIDE_UP);
        }
    }

    function garminQuickList(templateId as String, entryId as String?, mode as String,
                             source as String) as Void {
        var controller = getApp().controller();
        var items = Model.sameString(source, "recent") ? controller.recentGarminExercises() :
            controller.usedGarminExercises();
        var menu = new WatchUi.Menu2({:title=>Model.sameString(source, "recent") ?
            (items.size() == 0 ? "No recent choices" : "Recent exercises") :
            (items.size() == 0 ? "No used choices" : "Used in routines")});
        for (var i = 0; i < items.size(); i++) {
            var definition = items[i] as Dictionary;
            var name = definition["pickerName"] instanceof String ?
                definition["pickerName"] as String : definition["name"] as String;
            var category = definition["category"] as String;
            var categoryIndex = Catalog.garminCategoryIndex(category);
            var categoryName = categoryIndex < 0 ? "" :
                Catalog.garminCategories()[categoryIndex]["name"] as String;
            menu.addItem(new WatchUi.MenuItem(name, categoryName, definition["id"], null));
        }
        WatchUi.switchToView(menu,
            new GarminQuickDelegate(templateId, entryId, mode, source), WatchUi.SLIDE_UP);
    }

    function garminExercisePage(templateId as String, entryId as String?,
                                categoryIndex as Number, page as Number,
                                mode as String) as Void {
        var categories = Catalog.garminCategories();
        var rows = Catalog.garminExercises(categoryIndex);
        var pageSize = 20;
        var pages = pageCount(rows.size(), pageSize);
        var menu = new WatchUi.Menu2({:title=>(categories[categoryIndex]["name"] as String) +
            " " + (page + 1).toString() + "/" + pages.toString()});
        var start = page * pageSize;
        var end = start + pageSize;
        if (end > rows.size()) {
            end = rows.size();
        }
        for (var i = start; i < end; i++) {
            menu.addItem(new WatchUi.MenuItem(rows[i]["name"] as String,
                null, rows[i]["id"], null));
        }
        if (page > 0) {
            menu.addItem(new WatchUi.MenuItem("Previous exercises", null, "prev", null));
        }
        if (page + 1 < pages) {
            menu.addItem(new WatchUi.MenuItem("More exercises", null, "next", null));
        }
        WatchUi.switchToView(menu,
            new GarminExerciseDelegate(templateId, entryId, categoryIndex, page, mode), WatchUi.SLIDE_UP);
    }

    function garminTrackingType(templateId as String, entryId as String?,
                                categoryIndex as Number, page as Number,
                                definition as Dictionary, mode as String,
                                source as String, defaultType as String) as Void {
        var menu = new WatchUi.Menu2({:title=>definition["name"] as String});
        var types = ["weight", "assistance", "bodyweight", "timed"];
        menu.addItem(new WatchUi.MenuItem(trackingLabel(defaultType) + " · suggested",
            null, defaultType, null));
        for (var i = 0; i < types.size(); i++) {
            var type = types[i] as String;
            if (!Model.sameString(type, defaultType)) {
                menu.addItem(new WatchUi.MenuItem(trackingLabel(type), null, type, null));
            }
        }
        WatchUi.switchToView(menu, new GarminTrackingDelegate(templateId, entryId,
            categoryIndex, page, definition, mode, source, defaultType), WatchUi.SLIDE_UP);
    }

    function trackingLabel(type as String) as String {
        if (Model.sameString(type, "assistance")) {
            return "Assistance";
        }
        if (Model.sameString(type, "bodyweight")) {
            return "Bodyweight";
        }
        if (Model.sameString(type, "timed")) {
            return "Timed";
        }
        return "Weight";
    }

    function suggestedTrackingType(definition as Dictionary, mode as String,
                                    templateId as String, entryId as String?) as String {
        if (Model.sameString(mode, "active_swap") && entryId != null) {
            var session = getApp().controller().session();
            var exercise = session == null ? null :
                UiFormat.exercise(session as Dictionary, entryId as String);
            if (exercise != null) {
                return (exercise as Dictionary)["loadType"] as String;
            }
        } else if (Model.sameString(mode, "setup") && entryId != null) {
            var existing = getApp().controller().templateExercise(templateId, entryId as String);
            if (existing != null) {
                return (existing as Dictionary)["loadType"] as String;
            }
        }
        return definition["isBodyWeight"] == true ? "bodyweight" : "weight";
    }

    function pageCount(itemCount as Number, pageSize as Number) as Number {
        var pages = 0;
        for (var remaining = itemCount; remaining > 0; remaining -= pageSize) {
            pages++;
        }
        return pages > 0 ? pages : 1;
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
        if (Model.sameString(field, "increment100")) {
            return "Load increment";
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
        if (Model.sameString(field, "increment100")) {
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
        actionMenu(null, false);
    }

    function actionsForEntry(entryId as String) as Void {
        actionMenu(entryId, true);
    }

    function actionsForOverview(entryId as String) as Void {
        actionMenu(entryId, false);
    }

    function actionMenu(entryId as String?, fromExercise as Boolean) as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout"});
        var controller = getApp().controller();
        var session = controller.session();
        if (controller.isWorkoutPaused()) {
            menu.addItem(new WatchUi.MenuItem("Resume", null, "resume", null));
            menu.addItem(new WatchUi.MenuItem("Save segment & exit",
                "Resume may split activity", "exit_segment", null));
        } else if (controller.isWorkoutRunning()) {
            menu.addItem(new WatchUi.MenuItem("Pause", null, "pause", null));
            menu.addItem(new WatchUi.MenuItem("Save segment & exit",
                "Resume may split activity", "exit_segment", null));
        }
        if (entryId != null && session != null) {
            var exercise = UiFormat.exercise(session as Dictionary, entryId as String);
            if (exercise != null) {
                menu.addItem(new WatchUi.MenuItem(fromExercise ? "Exercise options" :
                    "Open exercise", null, "exercise", null));
                if (fromExercise) {
                    menu.addItem(new WatchUi.MenuItem("Back to overview", null, "overview", null));
                }
                var next = SessionLogic.nextSlot(exercise as Dictionary);
                var done = SessionLogic.completedCount(exercise as Dictionary);
                var running = (session as Dictionary)["timedRun"] instanceof Dictionary;
                var rest = (session as Dictionary)["rest"];
                if (rest instanceof Dictionary && Model.sameString(rest["state"], "running")) {
                    menu.addItem(new WatchUi.MenuItem("Skip rest", null, "rest_skip", null));
                }
                if (next >= 0 && !running) {
                    menu.addItem(new WatchUi.MenuItem("Skip for today", null, "skip_today", null));
                    menu.addItem(new WatchUi.MenuItem(done == 0 ? "Swap for today" :
                        "Add alternative today", null, done == 0 ? "swap_today" : "add_alt", null));
                }
            }
        }
        if (session != null && SessionLogic.totals(session as Dictionary)["done"] > 0) {
            menu.addItem(new WatchUi.MenuItem("Finish workout", null, "finish", null));
        }
        menu.addItem(new WatchUi.MenuItem("Cancel workout", null, "abort", null));
        WatchUi.pushView(menu, new ActionsMenuDelegate(entryId, fromExercise), WatchUi.SLIDE_UP);
    }

    function confirmExit() as Void {
        WatchUi.pushView(new ExitConfirmView(), new ExitConfirmDelegate(), WatchUi.SLIDE_UP);
    }

    function activityResultActions() as Void {
        var menu = new WatchUi.Menu2({:title=>"NextSet log saved"});
        if (getApp().controller().canRetryActivitySave()) {
            menu.addItem(new WatchUi.MenuItem("Retry Garmin save", null, "retry", null));
        }
        menu.addItem(new WatchUi.MenuItem("Keep local log and exit", null, "exit", null));
        WatchUi.pushView(menu, new ActivityResultDelegate(), WatchUi.SLIDE_UP);
    }

    function feedback(message as String) as Void {
        WatchUi.pushView(new FeedbackView(message), new FeedbackDelegate(), WatchUi.SLIDE_UP);
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

    function exitApp() as Void {
        getApp().stopTimer();
        System.exit();
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
            if (controller.retryFinalization()) {
                var session = controller.session() as Dictionary;
                Navigator.finalized(session["status"] as String);
            }
        } else if (controller.hasActiveSession()) {
            Navigator.resumeWorkout();
        } else {
            var templateId = _view.selectedTemplateId();
            if (templateId != null && controller.startWorkout(templateId as String, Time.now().value())) {
                getApp().startTimer(false);
                Navigator.overview();
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

class RoutineSetupDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;

    public function initialize(templateId as String) {
        _templateId = templateId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "add_exercise")) {
            Navigator.garminCategoryPage(_templateId, null, 0, "setup", true);
        } else {
            Navigator.routineEntryOptions(_templateId, id);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class RoutineEntryDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String;

    public function initialize(templateId as String, entryId as String) {
        _templateId = templateId;
        _entryId = entryId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "mapping")) {
            Navigator.mappingDetails(_templateId, _entryId);
        } else if (Model.sameString(id, "edit_values")) {
            Navigator.templateEntryFields(_templateId, _entryId, false);
        } else if (Model.sameString(id, "replace")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.garminCategoryPage(_templateId, _entryId, 0, "setup", true);
        } else if (Model.sameString(id, "move_up") || Model.sameString(id, "move_down")) {
            var direction = Model.sameString(id, "move_up") ? -1 : 1;
            var saved = getApp().controller().moveRoutineEntry(_templateId, _entryId, direction);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.editTemplate(_templateId);
            if (!saved) {
                var error = getApp().controller().errorMessage();
                Navigator.feedback(error == null ? "Routine change could not be saved" : error as String);
            }
        } else if (Model.sameString(id, "remove")) {
            var menu = new WatchUi.Menu2({:title=>"Remove exercise?"});
            menu.addItem(new WatchUi.MenuItem("Cancel", null, "cancel", null));
            menu.addItem(new WatchUi.MenuItem("Remove", null, "confirm_remove", null));
            WatchUi.pushView(menu, new RemoveRoutineEntryDelegate(_templateId, _entryId), WatchUi.SLIDE_UP);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class RemoveRoutineEntryDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String;

    public function initialize(templateId as String, entryId as String) {
        _templateId = templateId;
        _entryId = entryId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (Model.sameString(item.getId(), "confirm_remove")) {
            var saved = getApp().controller().removeRoutineEntry(_templateId, _entryId);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.editTemplate(_templateId);
            if (!saved) {
                var error = getApp().controller().errorMessage();
                Navigator.feedback(error == null ? "Exercise could not be removed" : error as String);
            }
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class GarminCategoryDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String?;
    private var _page as Number;
    private var _mode as String;

    public function initialize(templateId as String, entryId as String?, page as Number,
                               mode as String) {
        _templateId = templateId;
        _entryId = entryId;
        _page = page;
        _mode = mode;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "next")) {
            Navigator.garminCategoryPage(_templateId, _entryId, _page + 1, _mode, false);
            return;
        }
        if (Model.sameString(id, "prev")) {
            Navigator.garminCategoryPage(_templateId, _entryId, _page - 1, _mode, false);
            return;
        }
        if (Model.sameString(id, "recent") || Model.sameString(id, "used")) {
            Navigator.garminQuickList(_templateId, _entryId, _mode,
                Model.sameString(id, "recent") ? "recent" : "used");
            return;
        }
        var categories = Catalog.garminCategories();
        for (var i = 0; i < categories.size(); i++) {
            if (Model.sameString(categories[i]["code"], id)) {
                Navigator.garminExercisePage(_templateId, _entryId, i, 0, _mode);
                return;
            }
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class GarminExerciseDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String?;
    private var _categoryIndex as Number;
    private var _page as Number;
    private var _mode as String;

    public function initialize(templateId as String, entryId as String?,
                               categoryIndex as Number, page as Number, mode as String) {
        _templateId = templateId;
        _entryId = entryId;
        _categoryIndex = categoryIndex;
        _page = page;
        _mode = mode;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "next")) {
            Navigator.garminExercisePage(_templateId, _entryId, _categoryIndex, _page + 1, _mode);
        } else if (Model.sameString(id, "prev")) {
            Navigator.garminExercisePage(_templateId, _entryId, _categoryIndex, _page - 1, _mode);
        } else {
            var definition = Catalog.garminExercise(_categoryIndex, id);
            if (definition != null) {
                Navigator.garminTrackingType(_templateId, _entryId, _categoryIndex,
                    _page, definition as Dictionary, _mode, "browse",
                    Navigator.suggestedTrackingType(definition as Dictionary, _mode,
                        _templateId, _entryId));
            }
        }
    }

    public function onBack() as Void {
        var page = 0;
        while (_categoryIndex >= (page + 1) * 14) {
            page++;
        }
        Navigator.garminCategoryPage(_templateId, _entryId, page, _mode, false);
    }
}

class GarminQuickDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String?;
    private var _mode as String;
    private var _source as String;

    public function initialize(templateId as String, entryId as String?, mode as String,
                               source as String) {
        _templateId = templateId;
        _entryId = entryId;
        _mode = mode;
        _source = source;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        var controller = getApp().controller();
        var items = Model.sameString(_source, "recent") ? controller.recentGarminExercises() :
            controller.usedGarminExercises();
        for (var i = 0; i < items.size(); i++) {
            var definition = items[i] as Dictionary;
            if (Model.sameString(definition["id"], id)) {
                var category = definition["category"] as String;
                var categoryIndex = Catalog.garminCategoryIndex(category);
                Navigator.garminTrackingType(_templateId, _entryId, categoryIndex, 0,
                    definition, _mode, _source,
                    Navigator.suggestedTrackingType(definition, _mode, _templateId, _entryId));
                return;
            }
        }
    }

    public function onBack() as Void {
        Navigator.garminCategoryPage(_templateId, _entryId, 0, _mode, false);
    }
}

class GarminTrackingDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;
    private var _entryId as String?;
    private var _categoryIndex as Number;
    private var _page as Number;
    private var _definition as Dictionary;
    private var _mode as String;
    private var _source as String;
    private var _defaultType as String;

    public function initialize(templateId as String, entryId as String?,
                               categoryIndex as Number, page as Number,
                               definition as Dictionary, mode as String,
                               source as String, defaultType as String) {
        _templateId = templateId;
        _entryId = entryId;
        _categoryIndex = categoryIndex;
        _page = page;
        _definition = definition;
        _mode = mode;
        _source = source;
        _defaultType = defaultType;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var controller = getApp().controller();
        var type = item.getId() as String;
        var saved = false;
        if (Model.sameString(_mode, "active_swap")) {
            saved = _entryId != null && controller.replaceSessionExercise(
                _entryId as String, _definition, type);
        } else if (Model.sameString(_mode, "active_add")) {
            saved = _entryId != null && controller.addSessionAlternative(
                _entryId as String, _definition, type);
        } else if (_entryId == null) {
            saved = controller.addRoutineExercise(_templateId, _definition, type);
        } else {
            saved = controller.replaceRoutineExercise(_templateId, _entryId as String,
                _definition, type);
        }
        if (saved) {
            controller.rememberGarminExercise(_definition, _categoryIndex);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (Model.sameString(_mode, "setup")) {
            Navigator.editTemplate(_templateId);
            if (!saved) {
                Navigator.feedback(controller.errorMessage() == null ?
                    "Exercise change could not be saved" : controller.errorMessage() as String);
            }
        } else if (!saved) {
            Navigator.feedback(controller.errorMessage() == null ?
                "Workout unchanged; save failed" : controller.errorMessage() as String);
        } else {
            WatchUi.requestUpdate();
        }
    }

    public function onBack() as Void {
        if (Model.sameString(_source, "browse")) {
            Navigator.garminExercisePage(_templateId, _entryId, _categoryIndex, _page, _mode);
        } else {
            Navigator.garminQuickList(_templateId, _entryId, _mode, _source);
        }
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
    private var _entryId as String?;
    private var _fromExercise as Boolean;

    public function initialize(entryId as String?, fromExercise as Boolean) {
        _entryId = entryId;
        _fromExercise = fromExercise;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        var controller = getApp().controller();
        if (Model.sameString(id, "pause")) {
            if (controller.pauseWorkout(Time.now().value())) {
                getApp().stopTimer();
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                if (_fromExercise) {
                    WatchUi.popView(WatchUi.SLIDE_DOWN);
                }
                WatchUi.requestUpdate();
            } else {
                Navigator.feedback("Pause could not be saved");
            }
        } else if (Model.sameString(id, "resume")) {
            if (controller.resumeWorkout(Time.now().value())) {
                getApp().startTimer(true);
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.requestUpdate();
            } else {
                Navigator.feedback("Resume could not be saved");
            }
        } else if (Model.sameString(id, "exit_segment")) {
            Navigator.confirmExit();
        } else if (Model.sameString(id, "exercise") && _entryId != null) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            if (_fromExercise) {
                var view = new ExerciseView(_entryId as String);
                Navigator.exerciseMenuForEntry(_entryId as String, view, false);
            } else {
                Navigator.exercise(_entryId as String);
            }
        } else if (Model.sameString(id, "overview") && _entryId != null) {
            var session = controller.session() as Dictionary;
            var run = session["timedRun"];
            if (run instanceof Dictionary && Model.sameString(run["entryId"], _entryId as String) &&
                !controller.pauseTimedForEntry(_entryId as String, Time.now().value())) {
                Navigator.feedback("Timed set could not be paused");
                return;
            }
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.requestUpdate();
        } else if (Model.sameString(id, "skip_today") && _entryId != null) {
            if (controller.closeExercise(_entryId as String, true)) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.requestUpdate();
            } else {
                Navigator.feedback("Exercise unchanged; save failed");
            }
        } else if (Model.sameString(id, "rest_skip")) {
            if (controller.restAction("skip", Time.now().value())) {
                WatchUi.popView(WatchUi.SLIDE_DOWN);
                WatchUi.requestUpdate();
            } else {
                Navigator.feedback("Rest unchanged; save failed");
            }
        } else if ((Model.sameString(id, "swap_today") || Model.sameString(id, "add_alt")) &&
                   _entryId != null) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.garminCategoryPage((controller.session() as Dictionary)["templateId"] as String,
                _entryId, 0, Model.sameString(id, "swap_today") ? "active_swap" : "active_add", true);
        } else if (Model.sameString(id, "finish")) {
            if (controller.finish("completed", Time.now().value())) {
                Navigator.finalized("completed");
            } else {
                Navigator.feedback(controller.errorMessage() == null ?
                    "Workout could not be finished" : controller.errorMessage() as String);
            }
        } else if (Model.sameString(id, "abort")) {
            Navigator.confirm(id);
        }
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class ExitConfirmView extends WatchUi.View {
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var caption = UiFormat.captionFont();
        var lines = ["Exit workout?", "The current FIT segment will be saved.",
            "Resuming later may create another activity.", "START: SAVE SEGMENT & EXIT",
            "BACK: KEEP WORKING"];
        var fonts = [Graphics.FONT_SMALL, caption, caption, Graphics.FONT_XTINY, Graphics.FONT_XTINY];
        var gap = [8, 4, 12, 4, 0];
        var height = 0;
        for (var i = 0; i < lines.size(); i++) {
            height += dc.getFontHeight(fonts[i]) + gap[i];
        }
        var y = (dc.getHeight() - height) / 2;
        for (var i = 0; i < lines.size(); i++) {
            y = UiFormat.drawLine(dc, lines[i] as String, y, fonts[i] as Graphics.FontType) +
                (gap[i] as Number);
        }
    }
}

class ExitConfirmDelegate extends WatchUi.BehaviorDelegate {
    public function initialize() {
        BehaviorDelegate.initialize();
    }

    public function onSelect() as Boolean {
        if (getApp().controller().saveRecordingSegment()) {
            Navigator.exitApp();
        } else {
            var error = getApp().controller().errorMessage();
            Navigator.feedback(error == null ? "FIT segment unavailable; workout kept locally" :
                error as String);
        }
        return true;
    }

    public function onBack() as Boolean {
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

class MappingDetailView extends WatchUi.View {
    private var _templateId as String;
    private var _entryId as String;

    public function initialize(templateId as String, entryId as String) {
        _templateId = templateId;
        _entryId = entryId;
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var entry = getApp().controller().templateEntry(_templateId, _entryId);
        var exercise = getApp().controller().templateExercise(_templateId, _entryId);
        if (entry == null || exercise == null) {
            UiFormat.drawLine(dc, "Mapping unavailable", dc.getHeight() / 2,
                Graphics.FONT_SMALL);
            return;
        }
        var current = entry as Dictionary;
        var definition = exercise as Dictionary;
        var mapped = Catalog.garminName(current["garminCategory"] as String,
            current["garminCode"] as String);
        var caption = UiFormat.captionFont();
        var lines = ["NEXTSET", definition["name"] as String, "GARMIN", mapped,
            "Local exercise mapping only", "FIT contains no native set rows", "BACK to edit"];
        var fonts = [Graphics.FONT_XTINY, caption, Graphics.FONT_XTINY, caption,
            caption, caption, Graphics.FONT_XTINY];
        var gap = [4, 8, 4, 12, 4, 12, 0];
        var totalHeight = 0;
        for (var i = 0; i < lines.size(); i++) {
            totalHeight += dc.getFontHeight(fonts[i] as Graphics.FontType) + gap[i];
        }
        var y = (dc.getHeight() - totalHeight) / 2;
        for (var i = 0; i < lines.size(); i++) {
            var font = fonts[i] as Graphics.FontType;
            if (i == 1 || i == 3) {
                var wrapped = UiFormat.wrapTitle(dc, lines[i] as String, font, dc.getWidth() * 0.72);
                for (var j = 0; j < wrapped.size(); j++) {
                    y = UiFormat.drawLine(dc, wrapped[j] as String, y, font);
                }
            } else {
                y = UiFormat.drawLine(dc, lines[i] as String, y, font);
            }
            y += gap[i] as Number;
        }
    }
}

class MappingDetailDelegate extends WatchUi.BehaviorDelegate {
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
