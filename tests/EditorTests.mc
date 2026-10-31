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

(:test)
function testLastSetEditorRowsPerLoadType(logger as Test.Logger) as Boolean {
    var weight = EditorLogic.rows("weight");
    var assistance = EditorLogic.rows("assistance");
    var bodyweight = EditorLogic.rows("bodyweight");
    var timed = EditorLogic.rows("timed");
    var weightOk = weight.size() == 3 && Model.sameString(weight[0], "load100") &&
        Model.sameString(weight[1], "reps") && Model.sameString(weight[2], "delete");
    var assistOk = assistance.size() == 3 && Model.sameString(assistance[2], "delete");
    var bodyOk = bodyweight.size() == 2 && Model.sameString(bodyweight[0], "reps") &&
        Model.sameString(bodyweight[1], "delete");
    var timedOk = timed.size() == 2 && Model.sameString(timed[0], "durationSec") &&
        Model.sameString(timed[1], "delete");
    var deleteRow = EditorLogic.isDeleteRow(weight, 2) && !EditorLogic.isDeleteRow(weight, 1) &&
        !EditorLogic.isDeleteRow(weight, 3) && !EditorLogic.isDeleteRow(timed, -1);
    var fieldsUnchanged = EditorLogic.fields("weight").size() == 2 && EditorLogic.fields("timed").size() == 1;
    return check(logger, weightOk, "weight rows: weight, reps, Delete") &&
        check(logger, assistOk, "assistance rows end with Delete") &&
        check(logger, bodyOk, "bodyweight rows: reps, Delete") &&
        check(logger, timedOk, "timed rows: duration, Delete") &&
        check(logger, deleteRow, "only the last row is Delete") &&
        check(logger, fieldsUnchanged, "Delete is not a stored field");
}

(:test)
function testHoldUpActionPerLoadType(logger as Test.Logger) as Boolean {
    var weight = Model.sameString(EditorLogic.holdUpAction("weight"), "weight");
    var assist = Model.sameString(EditorLogic.holdUpAction("assistance"), "weight");
    var timed = Model.sameString(EditorLogic.holdUpAction("timed"), "time");
    var body = Model.sameString(EditorLogic.holdUpAction("bodyweight"), "none");
    var unknown = Model.sameString(EditorLogic.holdUpAction(null), "none");
    return check(logger, weight && assist, "hold UP changes the weight of weight and assistance sets") &&
        check(logger, timed, "hold UP changes the time of timed sets") &&
        check(logger, body && unknown, "bodyweight has no hold-UP action");
}

(:test)
function testBackOnSetScreenOpensLastLoggedSet(logger as Test.Logger) as Boolean {
    var none = {"slots" => [{"completed" => null}, {"completed" => null}],
        "warmupSlots" => [{"completed" => null}]};
    var working = {"slots" => [{"completed" => {"sequence" => 3}}, {"completed" => {"sequence" => 5}},
        {"completed" => null}], "warmupSlots" => [{"completed" => {"sequence" => 9}}]};
    var warmupOnly = {"slots" => [{"completed" => null}],
        "warmupSlots" => [{"completed" => {"sequence" => 1}}, {"completed" => {"sequence" => 2}}]};
    var noWarmups = {"slots" => [{"completed" => {"sequence" => 1}}, {"completed" => null}]};
    var noneSlot = SessionLogic.lastLoggedSlot(none);
    var workingSlot = SessionLogic.lastLoggedSlot(working);
    var warmupSlot = SessionLogic.lastLoggedSlot(warmupOnly);
    var plainSlot = SessionLogic.lastLoggedSlot(noWarmups);
    return check(logger, noneSlot == -1 && !EditorLogic.backOpensEditor(noneSlot),
            "with nothing logged BACK goes straight to the Overview") &&
        check(logger, workingSlot == 1 && EditorLogic.backOpensEditor(workingSlot),
            "BACK opens the working set logged last, not a later warmup") &&
        check(logger, warmupSlot == Model.WARMUP_BASE + 1, "warmups count only before any working set") &&
        check(logger, plainSlot == 0, "an exercise without warmups opens its logged set");
}

(:test)
function testLastLoggedSlotFollowsDeleteAndLog(logger as Test.Logger) as Boolean {
    var made = phase2SupersetSession();
    if (made == null) {
        return check(logger, false, "fixture session is created");
    }
    var session = made as Dictionary;
    var id = phase2FirstSuperset(session)[0] as String;
    var actual = {"load100" => 5000, "reps" => 8};
    var one = SessionLogic.completeSet(session, id, 0, actual, 1790752200) as Dictionary;
    var two = SessionLogic.completeSet(one, id, 1, actual, 1790752300) as Dictionary;
    var afterUndo = SessionLogic.undoSet(two, id, 1) as Dictionary;
    var emptied = SessionLogic.undoSet(afterUndo, id, 0) as Dictionary;
    var slotTwo = SessionLogic.lastLoggedSlot(UiFormat.exercise(two, id) as Dictionary);
    var slotAfterUndo = SessionLogic.lastLoggedSlot(UiFormat.exercise(afterUndo, id) as Dictionary);
    var slotEmptied = SessionLogic.lastLoggedSlot(UiFormat.exercise(emptied, id) as Dictionary);
    return check(logger, slotTwo == 1, "the second set is the last logged") &&
        check(logger, slotAfterUndo == 0, "after deleting it the first set is the last") &&
        check(logger, slotEmptied == -1, "after deleting both nothing is logged");
}

(:test)
function testOverviewAddSetRules(logger as Test.Logger) as Boolean {
    var made = phase2SupersetSession();
    if (made == null) {
        return check(logger, false, "fixture session is created");
    }
    var session = made as Dictionary;
    var id = phase2FirstSuperset(session)[0] as String;
    var before = UiFormat.exercise(session, id) as Dictionary;
    var plannedBefore = before["plannedSetCount"] as Number;
    var can = SessionLogic.canAddSet(session, id);
    var added = SessionLogic.addSet(session, id);
    var after = added == null ? null : UiFormat.exercise(added as Dictionary, id);
    var grew = after != null && (after as Dictionary)["plannedSetCount"] == plannedBefore + 1;
    var unknown = SessionLogic.canAddSet(session, "no-such-entry");
    var full = SessionLogic.copyDictionary(before);
    var fullSlots = [];
    for (var i = 0; i < Model.MAX_SETS; i++) {
        fullSlots.add({"draft" => {}, "completed" => null});
    }
    full["slots"] = fullSlots;
    var fullSession = SessionLogic.copyDictionary(session);
    var list = [];
    var original = session["exercises"] as Array;
    for (var i = 0; i < original.size(); i++) {
        list.add(Model.sameString((original[i] as Dictionary)["entryId"], id) ? full : original[i]);
    }
    fullSession["exercises"] = list;
    var atLimit = SessionLogic.canAddSet(fullSession, id);
    return check(logger, can && grew, "a set can be added to an exercise below the limit") &&
        check(logger, !unknown, "no set is added to an unknown exercise") &&
        check(logger, !atLimit && SessionLogic.addSet(fullSession, id) == null,
            "no set is added at the per-exercise limit");
}
