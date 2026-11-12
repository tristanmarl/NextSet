import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Crash breadcrumb. Monkey C cannot catch out-of-memory, watchdog or null/type errors, so before a
// heavy step the app writes `crumb` = [step, week, day, freeKB, appStartSeq] (Numbers only) and
// clears it after the step. A crumb still present at the next launch means the previous run died in
// that step; `NextSetApp.onStart` moves it to `crumb.last` and Settings → Diagnostics shows it.
// Step codes are persisted: never renumber them. enter/leave never read storage and never throw.
// Never call these from onTick, rest/alert code, the set-logging press or updateDraft.
module Breadcrumb {
    const KEY = "crumb";
    const KEY_LAST = "crumb.last";

    const STEP_SYNC_PROGRAM = 1;
    const STEP_SYNC_NEXT = 2;
    const STEP_SYNC_DAY = 3;
    const STEP_ROUTINE_COMMIT = 4;
    const STEP_JOURNAL_COMMIT = 5;
    const STEP_SYNC_PIVOT = 6;
    const STEP_UPLOAD_START = 7;
    const STEP_UPLOAD_SETS = 8;
    const STEP_UPLOAD_FINISH = 9;
    const STEP_FINALIZE = 10;
    const STEP_FIT_SAVE = 11;
    const STEP_HISTORY = 12;

    // Day being requested; set in memory only (no storage) when a day request goes out.
    var week = 0;
    var day = 0;
    // Counts launches in memory only; the crumb carries the number of this launch.
    var startSeq = 0;

    function at(w as Number, d as Number) as Void {
        week = w;
        day = d;
    }

    function enter(step as Number, w as Number, d as Number) as Void {
        try {
            Application.Storage.setValue(KEY,
                [step, w, d, System.getSystemStats().freeMemory / 1024, startSeq] as Array<Number>);
        } catch (error) {
        }
    }

    function leave() as Void {
        try {
            Application.Storage.deleteValue(KEY);
        } catch (error) {
        }
    }

    // Step for a web response purpose; 0 = no crumb (key test, unknown).
    function stepForPurpose(purpose as String?) as Number {
        if (purpose == null) {
            return 0;
        }
        if (purpose.equals(Liftosaur.REQ_SYNC_PROGRAM)) {
            return STEP_SYNC_PROGRAM;
        }
        if (purpose.equals(Liftosaur.REQ_SYNC_NEXT)) {
            return STEP_SYNC_NEXT;
        }
        if (purpose.equals(Liftosaur.REQ_SYNC_DAY)) {
            return STEP_SYNC_DAY;
        }
        if (purpose.equals(Liftosaur.REQ_UPLOAD_SETS)) {
            return STEP_UPLOAD_SETS;
        }
        if (purpose.equals(Liftosaur.REQ_UPLOAD_FINISH)) {
            return STEP_UPLOAD_FINISH;
        }
        if (purpose.equals(Liftosaur.REQ_UPLOAD_PREVIEW) || purpose.equals(Liftosaur.REQ_UPLOAD_START) ||
            purpose.equals(Liftosaur.REQ_UPLOAD_RESUME_SETS) || purpose.equals(Liftosaur.REQ_UPLOAD_CURRENT) ||
            purpose.equals(Liftosaur.REQ_UPLOAD_CURRENT_RESUME)) {
            return STEP_UPLOAD_START;
        }
        return 0;
    }

    function enterForPurpose(purpose as String?) as Void {
        var step = stepForPurpose(purpose);
        if (step != 0) {
            enter(step, step == STEP_SYNC_DAY ? week : 0, step == STEP_SYNC_DAY ? day : 0);
        }
    }

    function stepName(step as Number) as String {
        switch (step) {
            case STEP_SYNC_PROGRAM: return "program reply";
            case STEP_SYNC_NEXT: return "next reply";
            case STEP_SYNC_DAY: return "day reply";
            case STEP_ROUTINE_COMMIT: return "routine save";
            case STEP_JOURNAL_COMMIT: return "journal save";
            case STEP_SYNC_PIVOT: return "sync finish";
            case STEP_UPLOAD_START: return "upload start";
            case STEP_UPLOAD_SETS: return "upload sets";
            case STEP_UPLOAD_FINISH: return "upload finish";
            case STEP_FINALIZE: return "workout save";
            case STEP_FIT_SAVE: return "FIT save";
            case STEP_HISTORY: return "history";
        }
        return "step " + step.toString();
    }

    // "day reply W1 D3, 38 KB free"; null when the crumb is not a usable stop record.
    function format(crumb as Object?) as String? {
        if (!(crumb instanceof Array) || (crumb as Array).size() < 4) {
            return null;
        }
        var a = crumb as Array;
        for (var i = 0; i < 4; i += 1) {
            if (!(a[i] instanceof Number)) {
                return null;
            }
        }
        var step = a[0] as Number;
        if (step <= 0) {
            return null;
        }
        var text = stepName(step);
        if ((a[1] as Number) > 0) {
            text += " W" + (a[1] as Number).toString() + " D" + (a[2] as Number).toString();
        }
        return text + ", " + (a[3] as Number).toString() + " KB free";
    }

    // Short form for the one-line summary: "day reply W1 D3".
    function shortStop(crumb as Object?) as String {
        var full = format(crumb);
        if (full == null) {
            return "none";
        }
        var comma = (full as String).find(",");
        return comma == null ? full as String : (full as String).substring(0, comma) as String;
    }

    // Once per launch: a crumb left behind is moved to crumb.last (plus the app version); `crumb`
    // is then cleared and this run's launch number written in memory. Returns true if one was moved.
    function onLaunch(version as Number) as Boolean {
        var moved = false;
        try {
            var left = Application.Storage.getValue(KEY);
            var seq = 0;
            if (left instanceof Array && (left as Array).size() >= 5 && (left as Array)[4] instanceof Number) {
                seq = (left as Array)[4] as Number;
            }
            if (format(left) != null) {
                var a = left as Array;
                Application.Storage.setValue(KEY_LAST,
                    [a[0], a[1], a[2], a[3], seq, version] as Array<Number>);
                moved = true;
            }
            Application.Storage.deleteValue(KEY);
            startSeq = (seq + 1) % 1000;
        } catch (error) {
        }
        return moved;
    }

    // "0.5.0" -> 500 (major * 10000 + minor * 100 + patch); 0 when unreadable.
    function versionCode(text as String) as Number {
        var parts = [0, 0, 0];
        var part = 0;
        var value = 0;
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size() && part < 3; i += 1) {
            var c = chars[i];
            if (c == '.') {
                parts[part] = value;
                part += 1;
                value = 0;
            } else if (c >= '0' && c <= '9') {
                value = value * 10 + (c.toNumber() - '0'.toNumber());
            } else {
                return 0;
            }
        }
        if (part < 3) {
            parts[part] = value;
        }
        return (parts[0] as Number) * 10000 + (parts[1] as Number) * 100 + (parts[2] as Number);
    }

    // One compact line to paste into a bug report: version, part number, stop, last sync reason.
    function summary(problem as String?) as String {
        var version = "?";
        var part = "?";
        try {
            version = WatchUi.loadResource($.Rez.Strings.AppVersion) as String;
            var number = System.getDeviceSettings().partNumber;
            part = number == null ? "?" : number;
        } catch (error) {
        }
        return summaryText(version, part, shortStop(last()), problem);
    }

    function summaryText(version as String, part as String, stop as String, problem as String?) as String {
        return "NextSet " + version + " " + part + " stop:" + stop +
            (problem == null ? "" : " sync:" + problem);
    }

    function last() as Array? {
        try {
            var value = Application.Storage.getValue(KEY_LAST);
            return value instanceof Array ? value as Array : null;
        } catch (error) {
            return null;
        }
    }

    function clearLast() as Void {
        try {
            Application.Storage.deleteValue(KEY_LAST);
        } catch (error) {
        }
    }
}
