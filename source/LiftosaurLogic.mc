import Toybox.Application;
import Toybox.Lang;

module LiftosaurLogic {
    const MAX_PROGRAM_BYTES = 16384;
    const PARSE_CHUNK = 1024;
    // Peak a reply adds while it is converted, measured in the simulator with a 10-exercise,
    // 4-set day (about 91 KB) and a 16 KB program (about 27 KB), plus margin; see docs/DEVICE_TESTS.md.
    const SYNC_NEED_DAY = 112640;
    const SYNC_NEED_PROGRAM = 49152;

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

    // line = the header line from its first "#" (at most the rest of PARSE_CHUNK from line start).
    function lineProblem(line as String, text as String) as Null {
        var chars = line.toCharArray();
        var to = chars.size();
        while (to > 0 && isSpaceChar(chars[to - 1])) {
            to--;
        }
        var shown = to > 24 ? 24 : to;
        parseProblem = "Line \"" + line.substring(0, shown) + "\": " + text;
        return null;
    }

    // Start index of the line holding the "#" at index p when that "#" is the first non-blank
    // character of the line and lies within PARSE_CHUNK characters of the line start (longer lines
    // are only read that far); else -1.
    function headerLineStart(programText as String, p as Number) as Number {
        var k = p;
        while (k > 0 && p - k < PARSE_CHUNK) {
            var c = programText.substring(k - 1, k).toCharArray()[0];
            if (c == '\n') {
                return k;
            }
            if (!isSpaceChar(c)) {
                return -1;
            }
            k--;
        }
        return k == 0 && p < PARSE_CHUNK ? 0 : -1;
    }

    // Weeks of day names: Array of Arrays of Strings, index 0 = week 1. Liftoscript numbers weeks
    // by position: every line starting with a single "#" opens the next week, whatever its text.
    // "## Name" is a day. Days before any week header form an implicit week 1 (a "#" line after
    // them is ambiguous and rejected). Single pass; only day names become substrings.
    function parseDays(programText as String) as Array? {
        return parseDaysFor(programText, 0);
    }

    // weekWanted > 0: every header is still validated and counted, but only that week keeps its
    // names; the other entries are null (the Array is as long as the number of weeks).
    function parseDaysFor(programText as String, weekWanted as Number) as Array? {
        parseProblem = null;
        // ponytail: Liftoscript scan is capped at 16 KiB; raise if larger programs are supported.
        // No toCharArray() of the whole 16 KiB text (and of toUtf8Array() for its size): that cost
        // ~75 KB each at the same moment as the raw reply; the size is counted per chunk.
        var length = programText.length();
        var bytes = 0;
        for (var at = 0; at < length; at += PARSE_CHUNK) {
            var piece = programText.substring(at, at + PARSE_CHUNK < length ? at + PARSE_CHUNK : length);
            bytes += (piece as String).toUtf8Array().size();
        }
        if (bytes > MAX_PROGRAM_BYTES) {
            parseProblem = "Program over 16 KB";
            return null;
        }
        var weeks = [];
        var current = null;
        var started = false;
        var implicit = false;
        var total = 0;
        var pos = 0;
        // Interpreted work must follow the number of "#" characters, not the text length (the
        // watchdog counts bytecodes: a 16 KB per-character loop tripped it on an FR255). The bulk
        // is skipped with the native String.find on windows of PARSE_CHUNK characters.
        while (pos < length) {
            var end = pos + PARSE_CHUNK < length ? pos + PARSE_CHUNK : length;
            var window = programText.substring(pos, end) as String;
            var wlen = end - pos;
            var rest = window;
            var base = 0;
            var jump = -1;
            // Inside one window every substring is short; only a header line that starts before
            // or runs past the window falls back to the (slower) full-text lookups.
            while (jump < 0) {
                var idx = rest.find("#");
                if (idx == null) {
                    jump = end;
                    break;
                }
                var q = base + (idx as Number);
                var tail = window.substring(q > 16 ? q - 16 : 0, q) as String;
                var tailChars = tail.toCharArray();
                var j = tailChars.size() - 1;
                while (j >= 0 && isSpaceChar(tailChars[j])) {
                    j--;
                }
                var ls = -200000;      // line start relative to the window; -200000 = not known yet
                if (j >= 0) {
                    ls = tailChars[j] == '\n' ? q - tailChars.size() + j + 1 : -100000;   // -100000 = not a header
                } else if (q - tailChars.size() == 0 && pos == 0) {
                    ls = 0;
                }
                if (ls == -200000) {
                    var lineStart = headerLineStart(programText, pos + q);
                    ls = lineStart < 0 ? -100000 : lineStart - pos;
                }
                if (ls == -100000) {
                    base = q + 1;
                    rest = window.substring(base, wlen) as String;
                    continue;
                }
                var line = null;
                if (ls >= 0) {
                    var lineRest = window.substring(q, wlen) as String;
                    var newline = lineRest.find("\n");
                    if (newline != null) {
                        line = lineRest.substring(0, newline as Number) as String;
                    } else if (end == length) {
                        line = lineRest;
                    }
                }
                if (line == null) {
                    // starts before the window or runs past it: read from the full text, at most
                    // PARSE_CHUNK characters from the line start (indentation counts)
                    var cut = pos + ls + PARSE_CHUNK < length ? pos + ls + PARSE_CHUNK : length;
                    line = programText.substring(pos + q, cut) as String;
                    var newline = line.find("\n");
                    if (newline != null) {
                        line = line.substring(0, newline as Number) as String;
                    }
                    jump = pos + q + line.length();
                }
                var lineText = line as String;
                if (jump < 0) {
                    base = q + lineText.length();
                    rest = window.substring(base, wlen) as String;
                }
                var second = lineText.length() >= 2 ? lineText.substring(1, 2) as String : "";
                if (Model.sameString(second, "#")) {
                    var spaced = lineText.length() >= 3 && Model.sameString(lineText.substring(2, 3) as String, " ");
                    var name = spaced ? trim(lineText.substring(3, lineText.length()) as String) : "";
                    if (!spaced || name.length() == 0) {
                        return lineProblem(lineText, "day header needs a space");
                    }
                    if (!Model.validNonblankText(name, 64)) {
                        return lineProblem(lineText, "bad day name");
                    }
                    if (!started) {
                        started = true;
                        current = weekWanted <= 1 ? [] : null;
                        weeks.add(current);
                        implicit = true;
                    }
                    if (current != null) {
                        (current as Array).add(name);
                    }
                    total++;
                    if (total > Model.MAX_PROGRAM_DAYS) {
                        parseProblem = "Program over " + Model.MAX_PROGRAM_DAYS.toString() + " days";
                        return null;
                    }
                } else {
                    if (implicit) {
                        return lineProblem(lineText, "week header after days");
                    }
                    if (weeks.size() >= Model.MAX_PROGRAM_WEEKS) {
                        parseProblem = "Program over " + Model.MAX_PROGRAM_WEEKS.toString() + " weeks";
                        return null;
                    }
                    started = true;
                    current = weekWanted <= 0 || weeks.size() + 1 == weekWanted ? [] : null;
                    weeks.add(current);
                }
            }
            pos = jump;
        }
        if (total == 0) {
            parseProblem = "No days (## Name) in program";
            return null;
        }
        return weeks;
    }

    // Liftosaur names a day of a multi-week program "<week name> - <day name>" ("Week 7 - Day 1"),
    // a single-week program just "<day name>"; the program text gives only the day name.
    function dayNameMatches(apiName as Object?, textName as Object?) as Boolean {
        if (!(apiName instanceof String) || !(textName instanceof String)) {
            return false;
        }
        var api = apiName as String;
        var suffix = " - " + (textName as String);
        if (api.equals(textName as String)) {
            return true;
        }
        return api.length() > suffix.length() &&
            (api.substring(api.length() - suffix.length(), api.length()) as String).equals(suffix);
    }

    // Day rows [{week, dayInWeek, name}] of one week of a parseDays result (at most eight), or
    // null when the program has no such week or it has no days (reason in parseProblem).
    function weekDayRows(weeks as Array, week as Number) as Array? {
        if (week < 1 || week > weeks.size()) {
            parseProblem = "Week " + week.toString() + " not in program text";
            return null;
        }
        var names = weeks[week - 1];
        if (!(names instanceof Array) || (names as Array).size() == 0) {
            parseProblem = "Week " + week.toString() + " has no days";
            return null;
        }
        // Over eight days: the first eight are synced, the caller notes the rest as skipped.
        var rows = [];
        for (var i = 0; i < (names as Array).size() && i < Model.MAX_TEMPLATES; i++) {
            rows.add({"week" => week, "dayInWeek" => i + 1, "name" => (names as Array)[i]});
        }
        return rows;
    }

    // Free app memory a sync request needs before it is sent (its reply is held whole while it
    // is converted); 0 for requests that are not routine sync. Measured values: docs/DEVICE_TESTS.md.
    function syncMemoryNeed(purpose as String) as Number {
        if (Model.sameString(purpose, Liftosaur.REQ_SYNC_DAY) ||
            Model.sameString(purpose, Liftosaur.REQ_SYNC_NEXT)) {
            return SYNC_NEED_DAY;
        }
        return Model.sameString(purpose, Liftosaur.REQ_SYNC_PROGRAM) ? SYNC_NEED_PROGRAM : 0;
    }

    function enoughFree(purpose as String, free as Number) as Boolean {
        return free >= syncMemoryNeed(purpose);
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
