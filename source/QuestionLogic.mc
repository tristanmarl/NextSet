import Toybox.Lang;
import Toybox.Math;

// Pure helpers for QuestionView: prompted values are numbers or strings such as "225lb",
// "100kg" or "80%". Unit-tested.
module QuestionLogic {
    // [number, unit, step, decimals] for a prompted value. Steps: 5 lb, 2.5 kg, 1 % or 1;
    // 0.5 for a plain number that is not whole.
    function parse(value as Object?) as Array {
        if (value instanceof Number) {
            return [value, "", 1, false];
        }
        if (value instanceof Float || value instanceof Double) {
            var whole = (value as Numeric).toNumber() == value;
            return [(value as Numeric).toFloat(), "", whole ? 1 : 0.5, !whole];
        }
        if (!(value instanceof String)) {
            return [0, "", 1, false];
        }
        var text = value as String;
        var end = text.length();
        while (end > 0) {
            var c = text.substring(end - 1, end);
            if (Model.sameString(c, "%") || (c.toNumber() == null && !Model.sameString(c, "."))) {
                end--;
            } else {
                break;
            }
        }
        var unit = text.substring(end, text.length());
        var amount = text.substring(0, end).toFloat();
        if (amount == null) {
            return [0, unit, 1, false];
        }
        var decimals = amount.toNumber() != amount;
        var step = Model.sameString(unit, "lb") ? 5 : (Model.sameString(unit, "kg") ? 2.5 : 1);
        return [decimals ? amount : amount.toNumber(), unit, step, decimals || step == 2.5];
    }

    // "8", "8.5", "102.5": at most one decimal, none when whole.
    function format(value as Numeric, decimals as Boolean) as String {
        var tenths = Math.round(value * 10).toNumber();
        if (!decimals || tenths % 10 == 0) {
            return (tenths / 10).toString();
        }
        return (tenths / 10).toString() + "." + (tenths % 10).abs().toString();
    }

    // Questions after logging `slot` of an exercise (as it is after the save): the set's RPE when
    // its plan asks for one, and the prompted variables once no working set is left.
    function afterSet(exercise as Dictionary, entryId as String, slot as Number) as Array<Dictionary> {
        var questions = [] as Array<Dictionary>;
        var logged = Model.slotAt(exercise, slot);
        if (slot < 0 || slot >= Model.WARMUP_BASE || logged == null ||
            !((logged as Dictionary)["completed"] instanceof Dictionary)) {
            return questions;
        }
        var targets = exercise["planTargets"];
        var target = targets instanceof Array && slot < (targets as Array).size() ?
            (targets as Array)[slot] as Dictionary : null;
        if (target != null && target["logRpe"] == true) {
            questions.add({"kind" => "rpe", "entryId" => entryId, "slot" => slot,
                "value" => target["rpe10"] instanceof Number ? target["rpe10"] : 80});
        }
        var prompts = exercise["prompts"];
        if (prompts instanceof Array && SessionLogic.nextSlot(exercise) < 0) {
            var answers = exercise["userVars"] instanceof Dictionary ? exercise["userVars"] as Dictionary : {};
            for (var i = 0; i < (prompts as Array).size(); i++) {
                var item = (prompts as Array)[i] as Dictionary;
                var name = item["name"] as String;
                questions.add({"kind" => "var", "entryId" => entryId, "name" => name,
                    "value" => answers.hasKey(name) ? answers[name] : item["value"]});
            }
        }
        return questions;
    }
}
