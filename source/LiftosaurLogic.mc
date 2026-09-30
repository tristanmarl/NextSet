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
