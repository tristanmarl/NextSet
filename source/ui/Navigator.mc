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
        } else if (controller.hasActiveSession()) {
            menu.addItem(new WatchUi.MenuItem("Resume workout", null, "resume", null));
        }
        menu.addItem(new WatchUi.MenuItem("Workout history", null, "history", null));
        if (controller.configurationEditable()) {
            menu.addItem(new WatchUi.MenuItem("Routines", null, "routines", null));
            menu.addItem(new WatchUi.MenuItem("Settings", null, "settings", null));
        }
        WatchUi.pushView(menu, new HomeMenuDelegate(), WatchUi.SLIDE_UP);
    }

    function routineList() as Void {
        var controller = getApp().controller();
        var routines = controller.routineTemplates();
        var menu = new WatchUi.Menu2({:title=>"Routines"});
        for (var i = 0; i < routines.size(); i++) {
            var routine = routines[i] as Dictionary;
            var entries = routine["entries"] as Array;
            menu.addItem(new WatchUi.MenuItem(routine["name"] as String,
                entries.size() == 0 ? "Add exercise" : entries.size().toString() + " exercises",
                routine["id"], null));
        }
        if (routines.size() < Model.MAX_TEMPLATES) {
            var nameIndex = routines.size() + 1;
            var suggested = "Routine " + nameIndex.toString();
            while (routineNameExists(routines, suggested)) {
                nameIndex++;
                suggested = "Routine " + nameIndex.toString();
            }
            menu.addItem(new WatchUi.MenuItem("Create routine", suggested,
                "create_routine", null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Routine limit reached", "8 routines",
                "routine_limit", null));
        }
        WatchUi.switchToView(menu, new RoutineListDelegate(), WatchUi.SLIDE_UP);
    }

    function routineNameExists(routines as Array, name as String) as Boolean {
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString((routines[i] as Dictionary)["name"], name)) {
                return true;
            }
        }
        return false;
    }

    function createRoutinePicker(name as String) as Void {
        if (WatchUi has :TextPicker) {
            WatchUi.pushView(new WatchUi.TextPicker(name), new RoutineNameDelegate(),
                WatchUi.SLIDE_DOWN);
        } else {
            feedback("Text entry unavailable");
        }
    }

    function renameRoutinePicker(templateId as String) as Void {
        var name = "";
        var routines = getApp().controller().routineTemplates();
        for (var i = 0; i < routines.size(); i++) {
            if (Model.sameString(routines[i]["id"], templateId)) {
                name = routines[i]["name"] as String;
            }
        }
        if (WatchUi has :TextPicker) {
            WatchUi.pushView(new WatchUi.TextPicker(name), new RoutineRenameDelegate(templateId),
                WatchUi.SLIDE_DOWN);
        } else {
            feedback("Text entry unavailable");
        }
    }

    function confirmDeleteRoutine(templateId as String) as Void {
        var menu = new WatchUi.Menu2({:title=>"Delete routine?"});
        menu.addItem(new WatchUi.MenuItem("Cancel", null, "cancel", null));
        menu.addItem(new WatchUi.MenuItem("Delete", null, "delete", null));
        WatchUi.pushView(menu, new DeleteRoutineDelegate(templateId), WatchUi.SLIDE_UP);
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
        if (entries.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("Add exercise", null, "add_exercise", null));
        }
        for (var i = 0; i < entries.size(); i++) {
            var entry = entries[i] as Dictionary;
            var definition = Catalog.exerciseForEntry(entry);
            if (definition == null) {
                feedback("Saved exercise unavailable");
                return;
            }
            var exercise = definition as Dictionary;
            var value = entry["workingSetCount"].toString() + " × " +
                (Model.sameString(exercise["loadType"], "timed") ?
                    entry["targetDurationSec"].toString() + " sec" :
                    (entry["targetRepsMin"] == entry["targetRepsMax"] ?
                        entry["targetRepsMin"].toString() + " reps" :
                        entry["targetRepsMin"].toString() + "–" +
                        entry["targetRepsMax"].toString() + " reps"));
            if ((Model.sameString(exercise["loadType"], "weight") ||
                 Model.sameString(exercise["loadType"], "assistance")) &&
                entry["startingLoad100"] instanceof Number) {
                value += " · " + UiFormat.load100(entry["startingLoad100"] as Number) + " kg";
            }
            menu.addItem(new WatchUi.MenuItem(exercise["name"] as String, value,
                entry["entryId"], null));
        }
        if (entries.size() > 0) {
            menu.addItem(new WatchUi.MenuItem("Add exercise", null, "add_exercise", null));
        }
        menu.addItem(new WatchUi.MenuItem("Rename routine", null, "rename_routine", null));
        if (!Model.sameString(templateId, "upper") && !Model.sameString(templateId, "lower")) {
            menu.addItem(new WatchUi.MenuItem("Delete routine", null, "delete_routine", null));
        }
        WatchUi.switchToView(menu, new RoutineSetupDelegate(templateId), WatchUi.SLIDE_UP);
    }

    function routineEntryOptions(templateId as String, entryId as String) as Void {
        var controller = getApp().controller();
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
        var definition = index < 0 ? null : Catalog.exerciseForEntry(entries[index] as Dictionary);
        if (definition == null) {
            editTemplate(templateId);
            return;
        }
        var menu = new WatchUi.Menu2({:title=>definition["name"] as String});
        menu.addItem(new WatchUi.MenuItem("Edit values", null, "edit_values", null));
        if (index > 0) {
            menu.addItem(new WatchUi.MenuItem("Move up", null, "move_up", null));
        }
        if (index >= 0 && index < (entries as Array).size() - 1) {
            menu.addItem(new WatchUi.MenuItem("Move down", null, "move_down", null));
        }
        menu.addItem(new WatchUi.MenuItem("Replace exercise", null, "replace", null));
        menu.addItem(new WatchUi.MenuItem("Remove exercise", null, "remove", null));
        menu.addItem(new WatchUi.MenuItem("Garmin name", null, "mapping", null));
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
            var label = configFieldLabel(field);
            if (Model.sameString(field, "targetRepsMin")) {
                // One "Reps" row shows the range; START edits the minimum, then the maximum.
                var maximum = getApp().controller().numericConfigValue("template", templateId,
                    entryId, "targetRepsMax");
                label = "Reps";
                detail = value == null || maximum == null ? "" :
                    (value == maximum ? value.toString() : value.toString() + "–" + maximum.toString());
            }
            menu.addItem(new WatchUi.MenuItem(label, detail, field, null));
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
        var order = Catalog.garminCategoryOrder();
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
            var category = categories[order[i] as Number] as Dictionary;
            menu.addItem(new WatchUi.MenuItem(category["name"] as String, null,
                category["code"], null));
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

    function actionsForOverview(entryId as String) as Void {
        actionMenu(entryId, false);
    }

    function actionMenu(entryId as String?, fromExercise as Boolean) as Void {
        var menu = new WatchUi.Menu2({:title=>"Workout"});
        var controller = getApp().controller();
        var session = controller.session();
        if (session != null && !fromExercise) {
            var rest = (session as Dictionary)["rest"];
            if (rest instanceof Dictionary && Model.sameString(rest["state"], "running")) {
                menu.addItem(new WatchUi.MenuItem("Skip rest", null, "rest_skip", null));
            }
        }
        if (entryId != null && session != null) {
            var exercise = UiFormat.exercise(session as Dictionary, entryId as String);
            if (exercise != null) {
                var next = SessionLogic.nextSlot(exercise as Dictionary);
                var done = SessionLogic.completedCount(exercise as Dictionary);
                var running = (session as Dictionary)["timedRun"] instanceof Dictionary;
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
        if (controller.isWorkoutPaused()) {
            menu.addItem(new WatchUi.MenuItem("Resume", null, "resume", null));
        } else if (controller.isWorkoutRunning()) {
            menu.addItem(new WatchUi.MenuItem("Pause", null, "pause", null));
        }
        if (controller.isWorkoutPaused() || controller.isWorkoutRunning()) {
            menu.addItem(new WatchUi.MenuItem("Exit, continue later", null, "exit_segment", null));
        }
        menu.addItem(new WatchUi.MenuItem("Cancel workout", null, "abort", null));
        WatchUi.pushView(menu, new ActionsMenuDelegate(entryId, fromExercise), WatchUi.SLIDE_UP);
    }

    function confirmExit() as Void {
        WatchUi.pushView(new ExitConfirmView(), new ExitConfirmDelegate(), WatchUi.SLIDE_UP);
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
        if (last >= 0) {
            menu.addItem(new WatchUi.MenuItem("Edit last set", null, "edit_last", null));
        }
        if ((exercise["slots"] as Array).size() < Model.MAX_SETS &&
            SessionLogic.totals(session)["planned"] < Model.MAX_SETS_PER_WORKOUT) {
            menu.addItem(new WatchUi.MenuItem("Add set", null, "add_set", null));
        }
        if (last >= 0) {
            menu.addItem(new WatchUi.MenuItem("Undo set " + (last + 1).toString(), null, "undo", null));
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
            var done = SessionLogic.completedCount(exercise);
            menu.addItem(new WatchUi.MenuItem("Skip for today", null, "skip_today", null));
            menu.addItem(new WatchUi.MenuItem(done == 0 ? "Swap for today" :
                "Add alternative today", null, done == 0 ? "swap_today" : "add_alt", null));
        }
        if (exercise["closedEarly"] == true) {
            menu.addItem(new WatchUi.MenuItem("Reopen exercise", null, "reopen", null));
        }
        menu.addItem(new WatchUi.MenuItem("Workout…", null, "workout", null));
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
            getApp().retryPendingFinalization();
        } else if (controller.hasActiveSession()) {
            Navigator.resumeWorkout();
        } else {
            var templateId = _view.selectedTemplateId();
            if (templateId != null) {
                getApp().requestWorkoutStart(templateId as String);
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

class ExitConfirmView extends WatchUi.View {
    public function initialize() {
        View.initialize();
    }

    public function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var caption = UiFormat.captionFont();
        var lines = ["Exit workout?", "Workout continues next time.",
            "Garmin activity so far is saved separately.", "START: EXIT",
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
            Navigator.feedback(error == null ? "Garmin activity unavailable; workout kept locally" :
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
        getApp().requestWorkoutFinish("aborted");
    }

    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

