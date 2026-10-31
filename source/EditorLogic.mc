import Toybox.Lang;

// Pure rules of the set editor and of the set-position display, unit-tested in tests/.
// The editor has two levels: SELECT (UP/DOWN move between the fields, START enters one, BACK
// closes the editor and saves) and EDIT (UP/DOWN change the field, START keeps the value, BACK
// restores the value the field had when it was entered).
module EditorLogic {
    const MODE_SELECT = 0;
    const MODE_EDIT = 1;
    // More planned sets than this are shown as "4/8" instead of one dot each.
    const MAX_DOTS = 6;

    // Draft or completed-set fields the editor offers for an exercise's load type, in screen order.
    function fields(loadType as String?) as Array<String> {
        if (Model.sameString(loadType, "weight") || Model.sameString(loadType, "assistance")) {
            return ["load100", "reps"];
        }
        if (Model.sameString(loadType, "timed")) {
            return ["durationSec"];
        }
        return ["reps"];
    }

    // Row id after the fields in the two-level editor of a logged set: START opens Delete set N?.
    const ROW_DELETE = "delete";

    // Rows of the two-level editor of a logged set: the fields, then Delete.
    function rows(loadType as String?) as Array<String> {
        var list = fields(loadType);
        var all = [] as Array<String>;
        for (var i = 0; i < list.size(); i++) {
            all.add(list[i]);
        }
        all.add(ROW_DELETE);
        return all;
    }

    function isDeleteRow(rows as Array<String>, selected as Number) as Boolean {
        return selected >= 0 && selected < rows.size() && Model.sameString(rows[selected], ROW_DELETE);
    }

    // What hold UP does on the set screen: "weight" (Change weight), "time" (Change time) or
    // "none" (bodyweight: reps are changed with UP/DOWN, no hold, no icon).
    function holdUpAction(loadType as String?) as String {
        var field = singleField(loadType);
        if (field == null) {
            return "none";
        }
        return Model.sameString(field, "durationSec") ? "time" : "weight";
    }

    // What BACK does on the set screen: open the last logged set in the editor when the exercise
    // has one (slot >= 0), else go straight to the Overview.
    function backOpensEditor(lastLoggedSlot as Number) as Boolean {
        return lastLoggedSlot >= 0;
    }

    // The single field of the one-field editor ("Change weight" / "Change time"); null for
    // bodyweight, whose reps are changed on the set screen.
    function singleField(loadType as String?) as String? {
        if (Model.sameString(loadType, "weight") || Model.sameString(loadType, "assistance")) {
            return "load100";
        }
        return Model.sameString(loadType, "timed") ? "durationSec" : null;
    }

    // The one-field editor opens directly in EDIT; the two-level editor opens in SELECT.
    function initialMode(single as Boolean) as Number {
        return single ? MODE_EDIT : MODE_SELECT;
    }

    // One-field editor: START in EDIT saves and closes. Two-level editor: START toggles the level.
    function startSaves(single as Boolean, mode as Number) as Boolean {
        return single && mode == MODE_EDIT;
    }

    // One-field editor: BACK always cancels without saving. Two-level editor: BACK saves only in SELECT.
    function backSaves(single as Boolean, mode as Number) as Boolean {
        return !single && mode == MODE_SELECT;
    }

    // The weight (first field) is preselected: reps can already be changed on the set screen.
    function initialSelection() as Number {
        return 0;
    }

    // UP = -1, DOWN = +1; wraps around.
    function moveSelection(selected as Number, count as Number, direction as Number) as Number {
        if (count <= 0) {
            return 0;
        }
        return (selected + direction + count) % count;
    }

    // START: SELECT enters the selected field, EDIT keeps the value and returns to SELECT.
    function modeAfterStart(mode as Number) as Number {
        return mode == MODE_SELECT ? MODE_EDIT : MODE_SELECT;
    }

    // BACK in EDIT restores the field and returns to SELECT; BACK in SELECT closes the editor.
    function modeAfterBack(mode as Number) as Number {
        return MODE_SELECT;
    }

    function backClosesEditor(mode as Number) as Boolean {
        return mode == MODE_SELECT;
    }

    function useDots(planned as Number) as Boolean {
        return planned <= MAX_DOTS;
    }

    // "4/8": position of the set being done out of the planned sets (slot is 0-based).
    function counterText(slot as Number, planned as Number) as String {
        var position = slot < 0 ? planned : slot + 1;
        return position.toString() + "/" + planned.toString();
    }
}
