import Toybox.Lang;
import Toybox.Test;

// parseDays scans the text in chunks of whole lines; headers must parse the same wherever a
// chunk boundary falls, including lines longer than a chunk and multibyte characters.
function chunkProgram(pad as Number, filler as String) as String {
    var comment = "";
    for (var i = 0; i < pad; i++) {
        comment += filler;
    }
    return "# Week 1\n// " + comment + "\n## Upper\r\n  ## Lower  \n" + comment + "\n# Week 2 - Deload\n// " +
        comment + "\n## Push\n## Pull\n## Legs";
}

function chunkOk(weeks as Array?) as Boolean {
    if (weeks == null || weeks.size() != 2) {
        return false;
    }
    var first = (weeks as Array)[0] as Array;
    var second = (weeks as Array)[1] as Array;
    return first.size() == 2 && second.size() == 3 &&
        Model.sameString(first[0], "Upper") && Model.sameString(first[1], "Lower") &&
        Model.sameString(second[0], "Push") && Model.sameString(second[2], "Legs");
}

(:test)
function testParseDaysAcrossChunkBoundaries(logger as Test.Logger) as Boolean {
    var allOk = true;
    var failedPad = -1;
    for (var pad = 960; pad <= 1100; pad += 1) {
        if (!chunkOk(LiftosaurLogic.parseDays(chunkProgram(pad, "x")))) {
            allOk = false;
            failedPad = pad;
            break;
        }
    }
    logger.debug("first failing pad " + failedPad.toString());
    return check(logger, allOk, "headers parse at every chunk boundary offset");
}

(:test)
function testParseDaysLongLinesAndMultibyte(logger as Test.Logger) as Boolean {
    var longComment = chunkOk(LiftosaurLogic.parseDays(chunkProgram(1, "x")));
    var veryLong = chunkOk(LiftosaurLogic.parseDays(chunkProgram(1500, "ab ")));
    var multibyte = chunkOk(LiftosaurLogic.parseDays(chunkProgram(700, "é")));
    var multibyteEdge = true;
    for (var pad = 1015; pad <= 1030; pad++) {
        multibyteEdge = multibyteEdge && chunkOk(LiftosaurLogic.parseDays(chunkProgram(pad, "é")));
    }
    // A header line longer than a chunk is rejected as a bad day name, not skipped.
    var longName = "";
    for (var i = 0; i < 1500; i++) {
        longName += "n";
    }
    var tooLongName = LiftosaurLogic.parseDays("# Week 1\n## " + longName + "\n") == null;
    var weekAfterLong = LiftosaurLogic.parseDays("# Week 1 " + longName + "\n## A\n# Week 2\n## B\n") as Array;
    var first = check(logger, longComment && veryLong, "comment lines longer than a chunk are skipped");
    var second = check(logger, multibyte && multibyteEdge, "multibyte characters across chunk edges");
    var third = check(logger, tooLongName, "a day name longer than a chunk is rejected");
    var fourth = check(logger, weekAfterLong.size() == 2 && (weekAfterLong[1] as Array).size() == 1,
        "a week header longer than a chunk still opens its week");
    return first && second && third && fourth;
}

(:test)
function testParseDaysByteLimitCountsMultibyte(logger as Test.Logger) as Boolean {
    // 9000 two-byte characters are 18000 bytes: over the 16 KiB cap although under 16384 chars.
    var filler = "";
    for (var i = 0; i < 9000; i++) {
        filler += "é";
    }
    var over = LiftosaurLogic.parseDays("# Week 1\n// " + filler + "\n## A\n");
    return check(logger, over == null && LiftosaurLogic.parseProblem != null,
        "byte cap counts UTF-8 bytes, not characters");
}
