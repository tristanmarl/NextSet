import Toybox.Application;
import Toybox.Lang;

module LiftosaurLogic {
    const MAX_PROGRAM_BYTES = 16384;

    function trim(text as String) as String {
        var start = 0;
        var end = text.length();
        while (start < end && isSpace(text.substring(start, start + 1) as String)) {
            start++;
        }
        while (end > start && isSpace(text.substring(end - 1, end) as String)) {
            end--;
        }
        return text.substring(start, end) as String;
    }

    function isSpace(character as String) as Boolean {
        return Model.sameString(character, " ") || Model.sameString(character, "\t") ||
            Model.sameString(character, "\r");
    }

    // Entered key: trimmed, non-empty, at most 128 bytes, printable ASCII without inner spaces.
    function cleanKey(text as String?) as String? {
        if (text == null) {
            return null;
        }
        var key = trim(text as String);
        // trim() ignores newlines; strip them from the ends too.
        var bytes = key.toUtf8Array();
        var from = 0;
        var to = bytes.size();
        while (from < to && (bytes[from] <= 32 || bytes[from] == 127)) {
            from++;
        }
        while (to > from && (bytes[to - 1] <= 32 || bytes[to - 1] == 127)) {
            to--;
        }
        if (from >= to || to - from > 128) {
            return null;
        }
        for (var i = from; i < to; i++) {
            if (bytes[i] <= 32 || bytes[i] >= 127) {
                return null;
            }
        }
        return key.substring(from, to) as String;
    }

    // Phone link or Wi-Fi available; connectionAvailable is null when the device does not report it.
    function isOnline(phoneConnected as Boolean, connectionAvailable as Boolean?) as Boolean {
        return phoneConnected || connectionAvailable == true;
    }

    // Transport failure of a web request as an Err code, Err.NONE for anything else.
    function transportError(responseCode as Number) as Number {
        if (responseCode == -104) {
            return Err.PHONE_NOT_CONNECTED;
        }
        return responseCode == -300 || responseCode == -2 || responseCode == -3 ?
            Err.NO_RESPONSE_WILL_RETRY : Err.NONE;
    }

    // Auto-retry backoff: 2, 5, then 10 minutes.
    function retryDelayMinutes(attempt as Number) as Number {
        return attempt <= 0 ? 2 : (attempt == 1 ? 5 : 10);
    }

    // Summary status line for the Liftosaur upload of the workout just saved; null when the
    // workout has no upload. icon: "check" | "arrow" | "clock" | "cross".
    function summaryUpload(state as String?, uploading as Boolean, errorText as String?) as Dictionary? {
        if (Model.sameString(state, Liftosaur.STATE_DONE)) {
            return {"icon" => "check", "text" => "Uploaded"};
        }
        if (Model.sameString(state, Liftosaur.STATUS_SKIPPED)) {
            return {"icon" => "cross", "text" => "Upload skipped"};
        }
        if (!Model.sameString(state, Liftosaur.STATUS_PENDING)) {
            return null;
        }
        if (uploading) {
            return {"icon" => "arrow", "text" => "Uploading…"};
        }
        return errorText != null ? {"icon" => "cross", "text" => errorText} :
            {"icon" => "clock", "text" => "Pending · next launch"};
    }

    // The summary offers "Sync to Liftosaur" (START uploads now) while this workout's upload is
    // waiting or failed: pending in the queue, not uploading right now, and a key is set. Not
    // when it is done, skipped, uploading, or has no job; nothing without a key.
    function syncActionable(state as String?, uploading as Boolean, hasKey as Boolean) as Boolean {
        return hasKey && !uploading && Model.sameString(state, Liftosaur.STATUS_PENDING);
    }

    // "lftsk_…ab12": prefix and last four characters only.
    function maskKey(key as String) as String {
        if (key.length() <= 10) {
            return "…" + key.substring(key.length() - 2, key.length());
        }
        return key.substring(0, 6) + "…" + key.substring(key.length() - 4, key.length());
    }

    function isSpaceChar(character as Char) as Boolean {
        return character == ' ' || character == '\t' || character == '\r';
    }

    // Why the last parseDays returned null (short text), else null. Built only on failure.
    var parseProblem as String? = null;

    function lineProblem(source as String, from as Number, to as Number, text as String) as Null {
        var shown = to - from > 24 ? 24 : to - from;
        parseProblem = "Line \"" + source.substring(from, from + shown) + "\": " + text;
        return null;
    }

    // Weeks of day names: Array of Arrays of Strings, index 0 = week 1. Liftoscript numbers weeks
    // by position: every line starting with a single "#" opens the next week, whatever its text.
    // "## Name" is a day. Days before any week header form an implicit week 1 (a "#" line after
    // them is ambiguous and rejected). Single pass; only day names become substrings.
    function parseDays(programText as String) as Array? {
        parseProblem = null;
        // ponytail: Liftoscript scan is capped at 16 KiB; raise if larger programs are supported.
        if (Model.byteLength(programText) > MAX_PROGRAM_BYTES) {
            parseProblem = "Program over 16 KB";
            return null;
        }
        var chars = programText.toCharArray();
        var count = chars.size();
        var weeks = [];
        var current = null;
        var implicit = false;
        var total = 0;
        var start = 0;
        for (var i = 0; i <= count; i++) {
            if (i < count && chars[i] != '\n') {
                continue;
            }
            var from = start;
            var to = i;
            start = i + 1;
            while (from < to && isSpaceChar(chars[from])) {
                from++;
            }
            while (to > from && isSpaceChar(chars[to - 1])) {
                to--;
            }
            if (from >= to || chars[from] != '#') {
                continue;
            }
            if (to - from >= 2 && chars[from + 1] == '#') {
                if (to - from < 3 || chars[from + 2] != ' ') {
                    return lineProblem(programText, from, to, "day header needs a space");
                }
                var name = trim(programText.substring(from + 3, to) as String);
                if (!Model.validNonblankText(name, 64)) {
                    return lineProblem(programText, from, to, "bad day name");
                }
                if (current == null) {
                    current = [];
                    weeks.add(current);
                    implicit = true;
                }
                (current as Array).add(name);
                total++;
                if (total > Model.MAX_PROGRAM_DAYS) {
                    parseProblem = "Program over " + Model.MAX_PROGRAM_DAYS.toString() + " days";
                    return null;
                }
            } else {
                if (implicit) {
                    return lineProblem(programText, from, to, "week header after days");
                }
                if (weeks.size() >= Model.MAX_PROGRAM_WEEKS) {
                    parseProblem = "Program over " + Model.MAX_PROGRAM_WEEKS.toString() + " weeks";
                    return null;
                }
                current = [];
                weeks.add(current);
            }
        }
        if (total == 0) {
            parseProblem = "No days (## Name) in program";
            return null;
        }
        return weeks;
    }

    // Day rows [{week, dayInWeek, name}] of one week of a parseDays result (at most eight), or
    // null when the program has no such week or it has no days (reason in parseProblem).
    function weekDayRows(weeks as Array, week as Number) as Array? {
        if (week < 1 || week > weeks.size()) {
            parseProblem = "Week " + week.toString() + " not in program text";
            return null;
        }
        var names = weeks[week - 1] as Array;
        if (names.size() == 0) {
            parseProblem = "Week " + week.toString() + " has no days";
            return null;
        }
        // Over eight days: the first eight are synced, the caller notes the rest as skipped.
        var rows = [];
        for (var i = 0; i < names.size() && i < Model.MAX_TEMPLATES; i++) {
            rows.add({"week" => week, "dayInWeek" => i + 1, "name" => names[i]});
        }
        return rows;
    }

    // Reason of the last rejected sync, kept in the small storage key "diag.sync" (null = none).
    function saveSyncProblem(text as String?) as Void {
        try {
            if (text != null) {
                Application.Storage.setValue("diag.sync", text);
            } else if (Application.Storage.getValue("diag.sync") != null) {
                Application.Storage.deleteValue("diag.sync");
            }
        } catch (error) {
        }
    }

    function loadSyncProblem() as String? {
        try {
            var value = Application.Storage.getValue("diag.sync");
            return value instanceof String ? Model.fit(value as String, 80) : null;
        } catch (error) {
        }
        return null;
    }

    // The days of one week, in program order; the sync fetches only the current week.
    function daysForWeek(days as Array, week as Number) as Array {
        var result = [];
        for (var i = 0; i < days.size(); i++) {
            if ((days[i] as Dictionary)["week"] == week) {
                result.add(days[i]);
            }
        }
        return result;
    }
}
