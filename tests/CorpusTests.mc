import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

// Every Liftosaur built-in program (public Liftoscript, see scripts/corpus.py and docs/CORPUS.md)
// goes through LiftosaurLogic.parseDays; the weeks/days (or the rejection reason) are compared with
// values computed outside Monkey C. Fixtures: tests/resources/data/corpus*.xml, ids in CorpusData.mc.

// null when program number `index` parses as expected, else a short description of the mismatch.
function corpusMismatch(index as Number) as String? {
    var doc = WatchUi.loadResource(corpusIds()[index]) as Dictionary;
    var id = doc["id"] as String;
    var weeks = LiftosaurLogic.parseDays(doc["text"] as String);
    var expectedProblem = doc["problem"];
    if (expectedProblem != null) {
        if (weeks != null) {
            return id + ": parsed, expected rejection";
        }
        if (!Model.sameString(LiftosaurLogic.parseProblem, expectedProblem)) {
            return id + ": problem " + LiftosaurLogic.parseProblem;
        }
        return null;
    }
    if (weeks == null) {
        return id + ": rejected: " + LiftosaurLogic.parseProblem;
    }
    var expectedWeeks = doc["weeks"] as Array;
    var gotWeeks = weeks as Array;
    if (gotWeeks.size() != expectedWeeks.size()) {
        return id + ": " + gotWeeks.size().toString() + " weeks, expected " + expectedWeeks.size().toString();
    }
    for (var w = 0; w < gotWeeks.size(); w++) {
        var got = gotWeeks[w] as Array;
        var want = expectedWeeks[w] as Array;
        if (got.size() != want.size()) {
            return id + ": week " + (w + 1).toString() + " has " + got.size().toString() + " days, expected " + want.size().toString();
        }
        for (var d = 0; d < got.size(); d++) {
            if (!Model.sameString(got[d], want[d])) {
                return id + ": week " + (w + 1).toString() + " day " + (d + 1).toString() + " differs";
            }
        }
    }
    return null;
}

function corpusRange(logger as Test.Logger, from as Number, to as Number) as Boolean {
    var count = corpusIds().size();
    var failures = 0;
    for (var i = from; i < to && i < count; i++) {
        var problem = corpusMismatch(i);
        if (problem != null) {
            logger.error(problem as String);
            failures++;
        }
    }
    return check(logger, failures == 0, "corpus programs " + from.toString() + ".." + (to - 1).toString());
}

(:test)
function testCorpusCount(logger as Test.Logger) as Boolean {
    return check(logger, corpusIds().size() == 61, "61 built-in programs in the corpus");
}

(:test)
function testCorpus00(logger as Test.Logger) as Boolean { return corpusRange(logger, 0, 8); }

(:test)
function testCorpus08(logger as Test.Logger) as Boolean { return corpusRange(logger, 8, 16); }

(:test)
function testCorpus16(logger as Test.Logger) as Boolean { return corpusRange(logger, 16, 24); }

(:test)
function testCorpus24(logger as Test.Logger) as Boolean { return corpusRange(logger, 24, 32); }

(:test)
function testCorpus32(logger as Test.Logger) as Boolean { return corpusRange(logger, 32, 40); }

(:test)
function testCorpus40(logger as Test.Logger) as Boolean { return corpusRange(logger, 40, 48); }

(:test)
function testCorpus48(logger as Test.Logger) as Boolean { return corpusRange(logger, 48, 56); }

(:test)
function testCorpus56(logger as Test.Logger) as Boolean { return corpusRange(logger, 56, 64); }

// The largest built-in (Sheiko, 14 KB) fits; its text twice is over the 16 KB cap.
(:test)
function testCorpusLargestFitsAndDoubledIsRejected(logger as Test.Logger) as Boolean {
    var count = corpusIds().size();
    var sheiko = null;
    for (var i = 0; i < count; i++) {
        var doc = WatchUi.loadResource(corpusIds()[i]) as Dictionary;
        if (Model.sameString(doc["id"], "sheiko-29-32")) {
            sheiko = doc["text"];
            break;
        }
    }
    var found = check(logger, sheiko != null, "sheiko fixture present");
    var fits = check(logger, LiftosaurLogic.parseDays(sheiko as String) != null, "14 KB program parses");
    var doubled = LiftosaurLogic.parseDays((sheiko as String) + "\n" + (sheiko as String));
    var rejected = check(logger, doubled == null &&
        Model.sameString(LiftosaurLogic.parseProblem, "Program over 16 KB"), "28 KB program rejected");
    return found && fits && rejected;
}
