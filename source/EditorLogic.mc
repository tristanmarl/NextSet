import Toybox.Lang;

// Pure rules of the set editor and of the set-position display, unit-tested in tests/.
// The editor has two levels: SELECT (UP/DOWN move between the fields, START enters one, BACK
// closes the editor and saves) and EDIT (UP/DOWN change the field, START keeps the value, BACK
// restores the value the field had when it was entered).
module EditorLogic {
    const MODE_SELECT = 0;
    const MODE_EDIT = 1;

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

    // First row of the two-level editor of a logged set: START saves any change and returns to the
    // set screen (the editor opens preselected on it, so BACK then START just continues).
    const ROW_CONTINUE = "continue";

    // Rows of the two-level editor of a logged set: Continue, the fields, then Delete.
    function rows(loadType as String?) as Array<String> {
        var list = fields(loadType);
        var all = [ROW_CONTINUE] as Array<String>;
        for (var i = 0; i < list.size(); i++) {
            all.add(list[i]);
        }
        all.add(ROW_DELETE);
        return all;
    }

    function isContinueRow(rows as Array<String>, selected as Number) as Boolean {
        return selected >= 0 && selected < rows.size() && Model.sameString(rows[selected], ROW_CONTINUE);
    }

    // Number of rows before the first field (1 with the Continue row, else 0): row index minus this
    // is the field index.
    function fieldOffset(rows as Array<String>) as Number {
        return isContinueRow(rows, 0) ? 1 : 0;
    }

    // The START edge icon in the two-level editor: play on Continue, check on every other row and
    // while a field is edited. The next-set editor (no Continue row) keeps play in SELECT.
    function startIcon(rows as Array<String>, selected as Number, mode as Number) as String {
        if (mode == MODE_EDIT) {
            return "check";
        }
        if (isContinueRow(rows, selected)) {
            return "play";
        }
        return fieldOffset(rows) == 1 ? "check" : "play";
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

    // The first row is preselected: Continue in the last-set editor, else the weight (reps can
    // already be changed on the set screen).
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
}
