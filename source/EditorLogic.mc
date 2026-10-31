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
