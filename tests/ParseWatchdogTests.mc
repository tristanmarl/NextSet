import Toybox.Lang;
import Toybox.Test;

// parseDaysFor must do interpreted work proportional to the number of "#" characters, not to the
// text length (watchdog on a real FR255). The old per-character scan is kept here as an
// equivalence oracle: the new parser must give the same weeks and the same parseProblem.
module ParseOld {
    var problem as String? = null;

    function lineProblem(source as String, from as Number, to as Number, text as String) as Null {
        var shown = to - from > 24 ? 24 : to - from;
        problem = "Line \"" + source.substring(from, from + shown) + "\": " + text;
        return null;
    }

    function parse(programText as String, weekWanted as Number) as Array? {
        problem = null;
        var length = programText.length();
        var bytes = 0;
        for (var at = 0; at < length; at += LiftosaurLogic.PARSE_CHUNK) {
            var piece = programText.substring(at, at + LiftosaurLogic.PARSE_CHUNK < length ? at + LiftosaurLogic.PARSE_CHUNK : length);
            bytes += (piece as String).toUtf8Array().size();
        }
        if (bytes > LiftosaurLogic.MAX_PROGRAM_BYTES) {
            problem = "Program over 16 KB";
            return null;
        }
        var weeks = [];
        var current = null;
        var started = false;
        var implicit = false;
        var total = 0;
        var pos = 0;
        var skipping = false;
        while (pos < length) {
            var last = pos + LiftosaurLogic.PARSE_CHUNK >= length;
            var chunk = programText.substring(pos, last ? length : pos + LiftosaurLogic.PARSE_CHUNK) as String;
            var chars = chunk.toCharArray();
            var count = chars.size();
            var limit = count;
            var partial = false;
            if (!last) {
                var newline = count - 1;
                while (newline >= 0 && chars[newline] != '\n') {
                    newline--;
                }
                if (newline >= 0) {
                    limit = newline + 1;
                } else {
                    partial = true;
                }
            }
            pos += limit;
            var start = 0;
            if (skipping) {
                while (start < limit && chars[start] != '\n') {
                    start++;
                }
                if (start >= limit) {
                    continue;
                }
                start++;
                skipping = false;
            }
            for (var i = start; i <= limit; i++) {
                if (i < limit && chars[i] != '\n') {
                    continue;
                }
                var from = start;
                var to = i;
                start = i + 1;
                while (from < to && LiftosaurLogic.isSpaceChar(chars[from])) {
                    from++;
                }
                while (to > from && LiftosaurLogic.isSpaceChar(chars[to - 1])) {
                    to--;
                }
                if (from >= to || chars[from] != '#') {
                    continue;
                }
                if (to - from >= 2 && chars[from + 1] == '#') {
                    if (to - from < 3 || chars[from + 2] != ' ') {
                        return lineProblem(chunk, from, to, "day header needs a space");
                    }
                    var name = LiftosaurLogic.trim(chunk.substring(from + 3, to) as String);
                    if (!Model.validNonblankText(name, 64)) {
                        return lineProblem(chunk, from, to, "bad day name");
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
                        problem = "Program over " + Model.MAX_PROGRAM_DAYS.toString() + " days";
                        return null;
                    }
                } else {
                    if (implicit) {
                        return lineProblem(chunk, from, to, "week header after days");
                    }
                    if (weeks.size() >= Model.MAX_PROGRAM_WEEKS) {
                        problem = "Program over " + Model.MAX_PROGRAM_WEEKS.toString() + " weeks";
                        return null;
                    }
                    started = true;
                    current = weekWanted <= 0 || weeks.size() + 1 == weekWanted ? [] : null;
                    weeks.add(current);
                }
            }
            skipping = partial;
        }
        if (total == 0) {
            problem = "No days (## Name) in program";
            return null;
        }
        return weeks;
    }

    // Weeks and names as one string ("-" for a week not kept), or "null: <problem>".
    function show(weeks as Array?, why as String?) as String {
        if (weeks == null) {
            return "null: " + (why == null ? "-" : why);
        }
        var out = "";
        for (var w = 0; w < weeks.size(); w++) {
            out += "[";
            var names = weeks[w];
            if (names == null) {
                out += "-";
            } else {
                for (var d = 0; d < (names as Array).size(); d++) {
                    out += (names as Array)[d] + "|";
                }
            }
            out += "]";
        }
        return out;
    }

    function same(text as String, weekWanted as Number) as Boolean {
        var newWeeks = LiftosaurLogic.parseDaysFor(text, weekWanted);
        var newShown = show(newWeeks, LiftosaurLogic.parseProblem);
        var oldWeeks = parse(text, weekWanted);
        var oldShown = show(oldWeeks, problem);
        return newShown.equals(oldShown);
    }
}

function repeatText(piece as String, times as Number) as String {
    var out = "";
    for (var i = 0; i < times; i++) {
        out += piece;
    }
    return out;
}

// About 16 KB: long French cue comments with accents and "#" inside, indented headers, CRLF.
function frenchProgram(weeks as Number, days as Number) as String {
    var cue = "// Séance #29 : garder les omoplates serrées, « pousser le sol », expirer à l'effort ; " +
        "reprise après l'échauffement, très lent à la descente (3 s) ## pas un titre # non plus\r\n";
    var text = "";
    for (var w = 1; w <= weeks; w++) {
        text += (w % 2 == 0 ? "  # Semaine " : "# Semaine ") + w.toString() + " - Décharge #" + w.toString() + "\r\n";
        for (var d = 1; d <= days; d++) {
            text += cue;
            text += (d % 2 == 0 ? "\t## Jour " : "## Jour ") + d.toString() + " é\r\n";
            text += cue + "Squat / 3x8 / 60kg\r\n" + cue;
        }
    }
    return text;
}

function weekNamesOk(weeks as Array?, week as Number, days as Number) as Boolean {
    if (weeks == null) {
        return false;
    }
    var names = (weeks as Array)[week - 1];
    if (names == null || (names as Array).size() != days) {
        return false;
    }
    for (var d = 1; d <= days; d++) {
        if (!Model.sameString((names as Array)[d - 1], "Jour " + d.toString() + " é")) {
            return false;
        }
    }
    return true;
}

(:test)
function testParseWatchdogFrench16K(logger as Test.Logger) as Boolean {
    var text = frenchProgram(5, 5);
    logger.debug("french program chars " + text.length().toString());
    var big = text.length() > 10000 && text.toUtf8Array().size() <= LiftosaurLogic.MAX_PROGRAM_BYTES;
    var all = LiftosaurLogic.parseDays(text);
    var allOk = all != null && all.size() == 5 && weekNamesOk(all, 1, 5) && weekNamesOk(all, 5, 5);
    var wanted = LiftosaurLogic.parseDaysFor(text, 3);
    var wantedOk = wanted != null && wanted.size() == 5 && wanted[0] == null && wanted[1] == null &&
        wanted[3] == null && weekNamesOk(wanted, 3, 5);
    var oracle = ParseOld.same(text, 0) && ParseOld.same(text, 1) && ParseOld.same(text, 5) && ParseOld.same(text, 9);
    var first = check(logger, big, "program is large");
    var second = check(logger, allOk, "parseDays reads all weeks and names");
    var third = check(logger, wantedOk, "parseDaysFor keeps only the wanted week");
    var fourth = check(logger, oracle, "same as the old scan");
    return first && second && third && fourth;
}

(:test)
function testParseWatchdogMaxSizeProgram(logger as Test.Logger) as Boolean {
    var text = frenchProgram(5, 5);
    var pad = LiftosaurLogic.MAX_PROGRAM_BYTES - text.toUtf8Array().size();
    var tail = pad > 0 ? "// " + repeatText("é", pad / 2 - 4) : "";
    var near = text + tail;
    var nearBytes = near.toUtf8Array().size();
    var sizeOk = nearBytes > 16000 && nearBytes <= LiftosaurLogic.MAX_PROGRAM_BYTES;
    var oracle = ParseOld.same(near, 0) && ParseOld.same(near, 2) && LiftosaurLogic.parseDays(near) != null;
    var over = near + repeatText("x", 600);
    var overOk = LiftosaurLogic.parseDays(over) == null &&
        Model.sameString(LiftosaurLogic.parseProblem, "Program over 16 KB") && ParseOld.same(over, 0);
    var first = check(logger, sizeOk && oracle, "program near 16 KB parses and matches the old scan");
    var second = check(logger, overOk, "program over 16 KB is rejected");
    return first && second;
}

(:test)
function testParseWatchdogLongLineWithHash(logger as Test.Logger) as Boolean {
    var longLine = "// " + repeatText("note # abc ", 140);   // over 1024 chars, many "#"
    var text = "# Week 1\n" + longLine + "\n## A\n" + longLine + "# x\n## B\n# Week 2\n## C\n";
    var weeks = LiftosaurLogic.parseDays(text);
    var shapeOk = weeks != null && weeks.size() == 2 && (weeks[0] as Array).size() == 2 && (weeks[1] as Array).size() == 1;
    // A "#" after more than a chunk of indentation is not a header (old scan read lines only that far).
    var deep = "# W\n" + repeatText(" ", 1030) + "## Hidden\n## Shown\n";
    var deepWeeks = LiftosaurLogic.parseDays(deep);
    var deepOk = deepWeeks != null && (deepWeeks[0] as Array).size() == 1;
    var oracle = ParseOld.same(text, 0) && ParseOld.same(text, 2) && ParseOld.same(deep, 0);
    var first = check(logger, shapeOk, "long line with # before headers is skipped");
    var second = check(logger, deepOk, "header after a chunk of indentation is not read");
    var third = check(logger, oracle, "same as the old scan");
    return first && second && third;
}

(:test)
function testParseWatchdogEndAndBoundary(logger as Test.Logger) as Boolean {
    var endOk = true;
    var endWeeks = LiftosaurLogic.parseDays("# W\n// x\n## Last");
    endOk = endWeeks != null && (endWeeks[0] as Array).size() == 1 && Model.sameString((endWeeks[0] as Array)[0], "Last");
    var endBare = LiftosaurLogic.parseDays("# W\n## A\n##");
    var endBareOk = endBare == null && Model.sameString(LiftosaurLogic.parseProblem, "Line \"##\": day header needs a space");
    var boundaryOk = true;
    var oracle = true;
    for (var offset = 1010; offset <= 1030; offset++) {
        var text = "# W\n// " + repeatText("a", offset - 7) + "\n## D" + offset.toString() + "\n  ## E\r\n# V\n## F";
        var weeks = LiftosaurLogic.parseDays(text);
        if (weeks == null || weeks.size() != 2 || (weeks[0] as Array).size() != 2 || (weeks[1] as Array).size() != 1) {
            boundaryOk = false;
        }
        // header whose first character sits exactly at the boundary
        var edge = "# W\n" + repeatText("a", offset - 4) + "\n## G\n" + repeatText(" ", 3) + "## H";
        oracle = oracle && ParseOld.same(text, 0) && ParseOld.same(edge, 0) && ParseOld.same(edge, 1);
    }
    var first = check(logger, endOk, "## header at the very end without newline");
    var second = check(logger, endBareOk, "bare ## at the end is a problem");
    var third = check(logger, boundaryOk, "headers around the 1024 boundary");
    var fourth = check(logger, oracle, "boundary cases match the old scan");
    return first && second && third && fourth;
}

(:test)
function testParseWatchdogMatchesOldScan(logger as Test.Logger) as Boolean {
    var pieces = ["# Week 1\n", "## Day A\n", "  ## Day B  \r\n", "##x\n", "## \n", "##\n", "#\n", "// a # b\n",
        "text # more\n", "\t# Week 2\n", "## ", "# ", "é#\n", "\n", " ", "## " + repeatText("n", 70) + "\n",
        repeatText("z", 700), repeatText(" ", 600), "#", "##", "\r\n", "# Deload é\r\n", "## Jour é\n"];
    var seed = 12345;
    var allSame = true;
    var failed = -1;
    for (var n = 0; n < 150 && allSame; n++) {
        var text = "";
        var count = 3 + n % 14;
        for (var k = 0; k < count; k++) {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            text += pieces[(seed >> 8) % pieces.size()];
        }
        if (!ParseOld.same(text, 0) || !ParseOld.same(text, 2)) {
            allSame = false;
            failed = n;
        }
    }
    logger.debug("first differing case " + failed.toString());
    return check(logger, allSame, "150 random texts match the old scan");
}
