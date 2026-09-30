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

    function weekNumber(header as String) as Number? {
        if (header.length() < 8 ||
            !Model.sameString(header.substring(0, 7) as String, "# Week ")) {
            return null;
        }
        var digits = header.substring(7, header.length()) as String;
        if (digits.length() < 1 || digits.length() > 4) {
            return null;
        }
        var value = 0;
        var bytes = digits.toUtf8Array();
        for (var i = 0; i < bytes.size(); i++) {
            if (bytes[i] < 48 || bytes[i] > 57) {
                return null;
            }
            value = value * 10 + bytes[i] - 48;
        }
        return Model.inRange(value, 1, 1000, false) ? value : null;
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

    // Single pass over the characters; only header lines are turned into substrings.
    function parseDays(programText as String) as Array? {
        // ponytail: Liftoscript scan is capped at 16 KiB; raise if larger programs are supported.
        if (Model.byteLength(programText) > MAX_PROGRAM_BYTES) {
            return null;
        }
        var chars = programText.toCharArray();
        var count = chars.size();
        var days = [];
        var seenWeeks = {};
        var week = null;
        var dayInWeek = 0;
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
            var line = programText.substring(from, to) as String;
            if (line.find("# Week") == 0) {
                var parsedWeek = weekNumber(line);
                if (parsedWeek == null || seenWeeks.hasKey(parsedWeek.toString())) {
                    return null;
                }
                week = parsedWeek as Number;
                seenWeeks[week.toString()] = true;
                dayInWeek = 0;
            } else if (line.find("##") == 0) {
                if (line.find("## ") != 0) {
                    return null;
                }
                var name = trim(line.substring(3, line.length()) as String);
                if (!Model.validNonblankText(name, 64)) {
                    return null;
                }
                if (!(week instanceof Number)) {
                    // Days before any "# Week" header belong to an implicit week 1.
                    week = 1;
                    seenWeeks["1"] = true;
                }
                dayInWeek++;
                days.add({"week" => week, "dayInWeek" => dayInWeek, "name" => name});
                if (dayInWeek > Model.MAX_TEMPLATES || days.size() > Model.MAX_PROGRAM_DAYS) {
                    return null;
                }
            }
        }
        return days.size() == 0 ? null : days;
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
