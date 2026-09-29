import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

class RoutineListDelegate extends WatchUi.Menu2InputDelegate {
    public function initialize() {
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        var id = item.getId() as String;
        if (Model.sameString(id, "create_routine")) {
            var suggested = item.getSubLabel();
            Navigator.createRoutinePicker(suggested instanceof String ?
                suggested as String : "New routine");
        } else if (Model.sameString(id, "routine_limit")) {
            Navigator.feedback("Eight routines maximum");
        } else {
            Navigator.editTemplate(id);
        }
    }

    // Home rebuilds its routine data in onShow, so it is current after edits.
    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class RoutineNameDelegate extends WatchUi.TextPickerDelegate {
    public function initialize() {
        TextPickerDelegate.initialize();
    }

    public function onTextEntered(text as String, changed as Boolean) as Boolean {
        var controller = getApp().controller();
        var id = controller.createRoutine(text);
        // The picker closes itself after this returns; navigate once it is gone.
        if (id != null) {
            getApp().afterTextEntry(id as String, null);
        } else {
            var error = controller.errorMessage();
            getApp().afterTextEntry(null, error == null ? "Routine could not be created" : error as String);
        }
        return true;
    }

    public function onCancel() as Boolean {
        return true;
    }
}

class RoutineRenameDelegate extends WatchUi.TextPickerDelegate {
    private var _templateId as String;

    public function initialize(templateId as String) {
        _templateId = templateId;
        TextPickerDelegate.initialize();
    }

    public function onTextEntered(text as String, changed as Boolean) as Boolean {
        var controller = getApp().controller();
        if (controller.renameRoutine(_templateId, text)) {
            getApp().afterTextEntry(_templateId, null);
        } else {
            var error = controller.errorMessage();
            getApp().afterTextEntry(null, error == null ? "Routine could not be renamed" : error as String);
        }
        return true;
    }

    public function onCancel() as Boolean {
        return true;
    }
}

class DeleteRoutineDelegate extends WatchUi.Menu2InputDelegate {
    private var _templateId as String;

    public function initialize(templateId as String) {
        _templateId = templateId;
        Menu2InputDelegate.initialize();
    }

    public function onSelect(item as MenuItem) as Void {
        if (!Model.sameString(item.getId(), "delete")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return;
        }
        var controller = getApp().controller();
        if (controller.deleteRoutine(_templateId)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.routineList();
        } else {
            var error = controller.errorMessage();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.feedback(error == null ? "Routine could not be deleted" : error as String);
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
        } else if (Model.sameString(id, "rename_routine")) {
            Navigator.renameRoutinePicker(_templateId);
        } else if (Model.sameString(id, "delete_routine")) {
            Navigator.confirmDeleteRoutine(_templateId);
        } else {
            Navigator.routineEntryOptions(_templateId, id, null, false);
        }
    }

    public function onBack() as Void {
        Navigator.routineList();
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
        if (Model.sameString(id, "edit_values")) {
            Navigator.templateEntryFields(_templateId, _entryId, false);
        } else if (Model.sameString(id, "replace")) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Navigator.garminCategoryPage(_templateId, _entryId, 0, "setup", true);
        } else if (Model.sameString(id, "move_up") || Model.sameString(id, "move_down")) {
            var direction = Model.sameString(id, "move_up") ? -1 : 1;
            var saved = getApp().controller().moveRoutineEntry(_templateId, _entryId, direction);
            // Rebuild the entry menu in place with the same move item focused, so START repeats the move.
            Navigator.routineEntryOptions(_templateId, _entryId, id, true);
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

    // Values, order and exercise may have changed; rebuild the routine view underneath.
    public function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        Navigator.editTemplate(_templateId);
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
        var position = Catalog.garminCategoryOrder().indexOf(_categoryIndex);
        while (position >= (page + 1) * 14) {
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
        var addedEntryId = null;
        if (Model.sameString(_mode, "active_swap")) {
            saved = _entryId != null && controller.replaceSessionExercise(
                _entryId as String, _definition, type);
        } else if (Model.sameString(_mode, "active_add")) {
            saved = _entryId != null && controller.addSessionAlternative(
                _entryId as String, _definition, type);
        } else if (_entryId == null) {
            addedEntryId = controller.addRoutineExercise(_templateId, _definition, type);
            saved = addedEntryId != null;
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
            } else {
                // Ask for real values right away (sets, reps, starting load); BACK returns to the routine.
                var target = (_entryId != null ? _entryId : addedEntryId) as String;
                Navigator.routineEntryOptions(_templateId, target, null, false);
                Navigator.templateEntryFields(_templateId, target, false);
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
