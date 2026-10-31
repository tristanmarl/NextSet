import Toybox.Lang;
import Toybox.Test;

(:test)
function testEditorFieldsPerLoadType(logger as Test.Logger) as Boolean {
    var weight = EditorLogic.fields("weight");
    var assistance = EditorLogic.fields("assistance");
    var bodyweight = EditorLogic.fields("bodyweight");
    var timed = EditorLogic.fields("timed");
    var weightOk = weight.size() == 2 && Model.sameString(weight[0], "load100") &&
        Model.sameString(weight[1], "reps");
    var assistOk = assistance.size() == 2 && Model.sameString(assistance[0], "load100");
    var bodyOk = bodyweight.size() == 1 && Model.sameString(bodyweight[0], "reps");
    var timedOk = timed.size() == 1 && Model.sameString(timed[0], "durationSec");
    return check(logger, weightOk, "weight exercises edit weight then reps") &&
        check(logger, assistOk, "assistance exercises edit assistance then reps") &&
        check(logger, bodyOk, "bodyweight exercises edit reps only") &&
        check(logger, timedOk, "timed exercises edit the duration only") &&
        check(logger, EditorLogic.initialSelection() == 0, "the weight is preselected");
}

(:test)
function testEditorModeTransitions(logger as Test.Logger) as Boolean {
    var enter = EditorLogic.modeAfterStart(EditorLogic.MODE_SELECT);
    var confirm = EditorLogic.modeAfterStart(EditorLogic.MODE_EDIT);
    var revert = EditorLogic.modeAfterBack(EditorLogic.MODE_EDIT);
    var closes = EditorLogic.backClosesEditor(EditorLogic.MODE_SELECT);
    var staysOpen = EditorLogic.backClosesEditor(EditorLogic.MODE_EDIT);
    return check(logger, enter == EditorLogic.MODE_EDIT, "START in SELECT enters the field") &&
        check(logger, confirm == EditorLogic.MODE_SELECT, "START in EDIT confirms and returns to SELECT") &&
        check(logger, revert == EditorLogic.MODE_SELECT, "BACK in EDIT returns to SELECT") &&
        check(logger, closes, "BACK in SELECT closes the editor") &&
        check(logger, !staysOpen, "BACK in EDIT does not close the editor");
}

(:test)
function testEditorSelectionMoves(logger as Test.Logger) as Boolean {
    var down = EditorLogic.moveSelection(0, 2, 1);
    var up = EditorLogic.moveSelection(0, 2, -1);
    var single = EditorLogic.moveSelection(0, 1, 1);
    var none = EditorLogic.moveSelection(0, 0, 1);
    return check(logger, down == 1 && up == 1, "two fields wrap in both directions") &&
        check(logger, single == 0 && none == 0, "one or no field keeps the selection at 0");
}

(:test)
function testSetCounterThreshold(logger as Test.Logger) as Boolean {
    var six = EditorLogic.useDots(6);
    var seven = EditorLogic.useDots(7);
    var one = EditorLogic.useDots(1);
    return check(logger, six && one, "up to 6 planned sets are dots") &&
        check(logger, !seven, "more than 6 planned sets are a number") &&
        check(logger, Model.sameString(EditorLogic.counterText(3, 8), "4/8"), "slot 3 of 8 reads 4/8") &&
        check(logger, Model.sameString(EditorLogic.counterText(-1, 8), "8/8"), "all done reads 8/8");
}

(:test)
function testSingleFieldEditorRules(logger as Test.Logger) as Boolean {
    var weight = EditorLogic.singleField("weight");
    var assist = EditorLogic.singleField("assistance");
    var timed = EditorLogic.singleField("timed");
    var body = EditorLogic.singleField("bodyweight");
    var fieldsOk = Model.sameString(weight, "load100") && Model.sameString(assist, "load100") &&
        Model.sameString(timed, "durationSec");
    var opens = EditorLogic.initialMode(true) == EditorLogic.MODE_EDIT &&
        EditorLogic.initialMode(false) == EditorLogic.MODE_SELECT;
    var startSavesSingle = EditorLogic.startSaves(true, EditorLogic.MODE_EDIT);
    var startKeepsTwoLevel = !EditorLogic.startSaves(false, EditorLogic.MODE_EDIT) &&
        !EditorLogic.startSaves(false, EditorLogic.MODE_SELECT);
    var backCancelsSingle = !EditorLogic.backSaves(true, EditorLogic.MODE_EDIT);
    var backSavesTwoLevel = EditorLogic.backSaves(false, EditorLogic.MODE_SELECT) &&
        !EditorLogic.backSaves(false, EditorLogic.MODE_EDIT);
    return check(logger, fieldsOk, "weight, assistance and timed have one field to change") &&
        check(logger, body == null, "bodyweight has no one-field editor") &&
        check(logger, opens, "the one-field editor opens in EDIT, the two-level one in SELECT") &&
        check(logger, startSavesSingle && startKeepsTwoLevel, "START saves only in the one-field editor") &&
        check(logger, backCancelsSingle && backSavesTwoLevel, "BACK never saves in the one-field editor");
}

(:test)
function testAutomaticWeightStepDefault(logger as Test.Logger) as Boolean {
    var kg = Model.defaultIncrement100("kg");
    var lb = Model.defaultIncrement100("lb");
    var none = Model.defaultIncrement100(null);
    return check(logger, kg == 250 && none == 250, "the automatic step is 2.5 kg") &&
        check(logger, lb == 500, "the automatic step is 5 lb");
}
