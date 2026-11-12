import Toybox.Lang;
import Toybox.Test;

function problemWeeks(text as String) as Array {
    var parsed = LiftosaurLogic.parseDays(text);
    return parsed == null ? [] : parsed as Array;
}

function problemEntry(reply as Dictionary) as Dictionary {
    var data = reply["data"] as Dictionary;
    var workout = data["workout"] as Dictionary;
    return (workout["entries"] as Array)[0] as Dictionary;
}

function problemWorkout(reply as Dictionary) as Dictionary {
    var data = reply["data"] as Dictionary;
    return data["workout"] as Dictionary;
}

function problemSet(reply as Dictionary, index as Number) as Dictionary {
    return (problemEntry(reply)["sets"] as Array)[index] as Dictionary;
}

(:test)
function testWeekHeadersAreOrdinal(logger as Test.Logger) as Boolean {
    var deload = problemWeeks("# Week 1\n## A\n# Week 4 - Deload\n## B\n## C\n");
    var sheiko = problemWeeks("# #29 Preparation - Week 1\n## A\n# #30 Preparation - Week 2\n## B\n");
    var named = problemWeeks("# Heavy\n## A\n# Deload\n## B\n# \n## C\n#\n## D\n");
    var duplicates = problemWeeks("# Week 1\n## A\n# Week 1\n## B\n");
    var shapeDeload = deload.size() == 2 && (deload[0] as Array).size() == 1 &&
        (deload[1] as Array).size() == 2 && Model.sameString((deload[1] as Array)[1], "C");
    var shapeSheiko = sheiko.size() == 2 && (sheiko[0] as Array).size() == 1 &&
        Model.sameString((sheiko[1] as Array)[0], "B");
    var shapeNamed = named.size() == 4 && Model.sameString((named[1] as Array)[0], "B") &&
        Model.sameString((named[3] as Array)[0], "D");
    var shapeDuplicates = duplicates.size() == 2 && Model.sameString((duplicates[1] as Array)[0], "B");
    return check(logger, shapeDeload, "'# Week 4 - Deload' is simply the next week") &&
        check(logger, shapeSheiko, "'# #29 Preparation - Week 1' is a week header") &&
        check(logger, shapeNamed, "free-text and empty week names are numbered by position") &&
        check(logger, shapeDuplicates, "duplicate week names are fine");
}

(:test)
function testBigProgramsAndImplicitWeek(logger as Test.Logger) as Boolean {
    var big = "";
    for (var w = 1; w <= 16; w++) {
        big += "# Week " + w.toString() + "\n";
        for (var d = 1; d <= 4; d++) {
            big += "## Day " + d.toString() + "\n";
        }
    }
    var weeks = problemWeeks(big);
    var nine = "# Week 1\n## A\n# Week 2\n";
    for (var d = 0; d < 9; d++) {
        nine += "## Day " + d.toString() + "\n";
    }
    var nineWeeks = problemWeeks(nine);
    var implicit = problemWeeks("## Upper\n## Lower\n");
    var late = LiftosaurLogic.parseDays("## Upper\n# Week 1\n## Lower\n");
    var lateProblem = LiftosaurLogic.parseProblem;
    var okRows = LiftosaurLogic.weekDayRows(weeks, 16);
    var tooWide = LiftosaurLogic.weekDayRows(nineWeeks, 2);
    var ok = LiftosaurLogic.weekDayRows(nineWeeks, 1);
    var missing = LiftosaurLogic.weekDayRows(nineWeeks, 5);
    var missingProblem = LiftosaurLogic.parseProblem;
    var sixteen = weeks.size() == 16 && (weeks[15] as Array).size() == 4;
    var rows = okRows != null && (okRows as Array).size() == 4 &&
        (okRows as Array)[3]["week"] == 16 && (okRows as Array)[3]["dayInWeek"] == 4;
    var implicitShape = implicit.size() == 1 && (implicit[0] as Array).size() == 2;
    var lateText = lateProblem != null && lateProblem.find("week header after days") != null;
    var wideRows = tooWide != null && (tooWide as Array).size() == 8 &&
        Model.sameString((tooWide as Array)[7]["name"], "Day 7");
    var missingText = missingProblem != null &&
        Model.sameString(missingProblem, "Week 5 not in program text");
    return check(logger, sixteen && rows, "16 weeks of 4 days parse and expose the current week") &&
        check(logger, nineWeeks.size() == 2 && ok != null,
            "a 9-day week elsewhere does not fail the parse or the sync of another week") &&
        check(logger, wideRows, "a synced week over 8 days keeps its first eight days") &&
        check(logger, missing == null && missingText, "a week missing from the text is named") &&
        check(logger, implicitShape, "days before any header form an implicit week 1") &&
        check(logger, late == null && lateText, "a '#' header after implicit days is rejected");
}

(:test)
function testParseProblemTexts(logger as Test.Logger) as Boolean {
    LiftosaurLogic.parseDays("# Week 1\n##Day 1\n");
    var noSpace = LiftosaurLogic.parseProblem;
    LiftosaurLogic.parseDays("# Week 1\n");
    var none = LiftosaurLogic.parseProblem;
    var huge = "";
    for (var i = 0; i < 700; i++) {
        huge += "// padding padding padding\n";
    }
    var tooBig = LiftosaurLogic.parseDays(huge);
    var bigProblem = LiftosaurLogic.parseProblem;
    var okParse = LiftosaurLogic.parseDays("# Week 1\n## A\n");
    var cleared = LiftosaurLogic.parseProblem;
    var daysLimit = "# Week 1\n";
    for (var i = 0; i < 161; i++) {
        daysLimit += "## D\n";
    }
    LiftosaurLogic.parseDays(daysLimit);
    var daysProblem = LiftosaurLogic.parseProblem;
    var noSpaceOk = noSpace != null &&
        Model.sameString(noSpace, "Line \"##Day 1\": day header needs a space");
    return check(logger, noSpaceOk, "missing space after ## is named with the line") &&
        check(logger, none != null && none.find("No days") != null, "no days is named") &&
        check(logger, tooBig == null && bigProblem != null &&
            Model.sameString(bigProblem, "Program over 16 KB"), "oversized text is named") &&
        check(logger, okParse != null && cleared == null, "a good parse leaves no problem") &&
        check(logger, daysProblem != null && daysProblem.find("over 160 days") != null,
            "the total day cap is named");
}

(:test)
function testWorkoutProblemTexts(logger as Test.Logger) as Boolean {
    var good = phase2ApiWorkout("Day", 1l, "Squat", false, false, "g");
    // EMOM ("5x5 60kg 60s|0s auto"): a set timer with five reps is a weight/reps set.
    var emom = phase2ApiWorkout("Day", 1l, "Power Clean", true, false, "t");
    for (var s = 0; s < 2; s++) {
        problemSet(emom, s)["reps"] = 5;
        problemSet(emom, s)["weight"] = "60kg";
    }
    var mixed = phase2ApiWorkout("Day", 1l, "Power Clean", true, false, "x");
    problemSet(mixed, 0)["reps"] = 5;
    var empty = phase2ApiWorkout("Day", 1l, "Squat", false, false, "e");
    problemWorkout(empty)["entries"] = [];
    var noWeight = phase2ApiWorkout("Day", 1l, "Squat", false, false, "w");
    problemSet(noWeight, 0)["weight"] = null;
    var many = phase2ApiWorkout("Day", 1l, "Squat", false, false, "m");
    var manySets = [];
    for (var i = 0; i < 12; i++) {
        manySets.add(phase2ApiSet("m" + i.toString(), i, "60kg", 10, null, false, false));
    }
    problemEntry(many)["sets"] = manySets;
    var dup = phase2ApiWorkout("Day", 1l, "Squat", false, false, "d");
    problemSet(dup, 1)["setId"] = problemSet(dup, 0)["setId"];
    var goodProblem = Model.liftosaurWorkoutProblem(good);
    var emomProblem = Model.liftosaurWorkoutProblem(emom);
    var mixedProblem = Model.liftosaurWorkoutProblem(mixed);
    var emptyProblem = Model.liftosaurWorkoutProblem(empty);
    var weightProblem = Model.liftosaurWorkoutProblem(noWeight);
    var manyProblem = Model.liftosaurWorkoutProblem(many);
    var dupProblem = Model.liftosaurWorkoutProblem(dup);
    var notObject = Model.liftosaurWorkoutProblem("x");
    var emomRoutine = Catalog.parseRoutine(emom, 1, 1);
    var emomEntry = emomRoutine == null ? null :
        ((emomRoutine as Dictionary)["entries"] as Array)[0] as Dictionary;
    var emomTarget = emomEntry == null ? null : (emomEntry["setTargets"] as Array)[0] as Dictionary;
    var emomOk = emomProblem == null && emomEntry != null &&
        Model.sameString(emomEntry["loadType"], "weight") && emomEntry["targetDurationSec"] == null;
    var emomTargetOk = emomTarget != null && emomTarget["reps"] == 5 &&
        emomTarget["load100"] == 6000 && emomTarget["durationSec"] == null;
    var mixedOk = mixedProblem != null &&
        Model.sameString(mixedProblem, "W1 D2 Power Clean: mixes timed and normal sets");
    var emptyOk = emptyProblem != null && Model.sameString(emptyProblem, "W1 D2: no exercises");
    var weightOk = weightProblem != null && Model.sameString(weightProblem, "W1 D2 Squat: no weight");
    var manyOk = manyProblem != null &&
        Model.sameString(manyProblem, "W1 D2 Squat: 12 sets (max 10)");
    var dupOk = dupProblem != null && dupProblem.find("duplicate set id") != null;
    var parsed = Catalog.parseRoutine(noWeight, 1, 1);
    var catalogOk = parsed == null && Catalog.lastProblem != null &&
        Model.sameString(Catalog.lastProblem, "W1 D2 Squat: no weight");
    var validAgain = Catalog.parseRoutine(good, 1, 1);
    return check(logger, goodProblem == null && Model.validLiftosaurWorkout(good),
            "a valid workout has no problem") &&
        check(logger, emomOk, "EMOM sets (set timer, several reps) sync as a weight exercise") &&
        check(logger, emomTargetOk, "EMOM targets keep reps and load, no hold duration") &&
        check(logger, mixedOk, "an exercise mixing holds and EMOM sets is named") &&
        check(logger, emptyOk, "empty day is named") &&
        check(logger, weightOk, "missing weight is named") &&
        check(logger, manyOk, "too many sets is named") &&
        check(logger, dupOk && notObject != null, "duplicate ids and non-objects are named") &&
        check(logger, catalogOk, "Catalog.parseRoutine records the same reason") &&
        check(logger, validAgain != null && Catalog.lastProblem == null,
            "a good parse clears the reason");
}

(:test)
function testWeeksJournalAndSyncReasons(logger as Test.Logger) as Boolean {
    var reply = phase2ApiWorkout("Dayy", 1l, "Squat", false, false, "j");
    // The reply is for week 1, day 2.
    var store = new UploadMemoryStore();
    var base = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [],
        "weeks" => [["A", "Dayy", "C"], ["D"]]};
    var weeksOk = store.commitPair("rsync", base);
    LiftosaurLogic.saveSyncProblem("old problem");
    var controller = new SessionController(store);
    controller.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, reply);
    syncSettle(controller);
    var after = store.loadRoutineSync();
    var daysPhase = after != null && Model.sameString(after["phase"], "days") &&
        after["weeks"] == null && (after["days"] as Array).size() == 3 &&
        (after["days"] as Array)[1]["dayInWeek"] == 2;
    var badWeeks = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [], "weeks" => [["A"], "oops"]};
    var badStore = new UploadMemoryStore();
    var badSaved = badStore.commitPair("rsync", badWeeks);
    // Legacy journal: phase next with a flat day list and no weeks.
    var legacy = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [],
        "days" => [{"week" => 1, "dayInWeek" => 1, "name" => "A"},
            {"week" => 1, "dayInWeek" => 2, "name" => "Dayy"},
            {"week" => 2, "dayInWeek" => 1, "name" => "D"}]};
    var legacyStore = new UploadMemoryStore();
    var legacySaved = legacyStore.commitPair("rsync", legacy);
    var legacyController = new SessionController(legacyStore);
    legacyController.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, reply);
    syncSettle(legacyController);
    var legacyAfter = legacyStore.loadRoutineSync();
    var legacyDays = legacyAfter != null && Model.sameString(legacyAfter["phase"], "days") &&
        (legacyAfter["days"] as Array).size() == 2;
    // Week 1 of the program text has only one day: day 2 of the reply cannot be found, and the
    // sync is rejected with a stored reason.
    var shortWeeks = {"sequence" => 1, "phase" => "next", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "routineIds" => [], "weeks" => [["A"]]};
    var shortStore = new UploadMemoryStore();
    var shortSaved = shortStore.commitPair("rsync", shortWeeks);
    LiftosaurLogic.saveSyncProblem(null);
    var shortController = new SessionController(shortStore);
    shortController.handleApiResponse(Liftosaur.REQ_SYNC_NEXT, null, 200, reply);
    syncSettle(shortController);
    // The journal is fine, so the sync moves on; only the day-name check can reject it.
    var badName = new UploadMemoryStore();
    var nameJournal = {"sequence" => 1, "phase" => "days", "index" => 0, "programId" => "x0001xxx",
        "programName" => "P", "nextWeek" => 1, "nextDay" => 2, "routineIds" => [],
        "days" => [{"week" => 1, "dayInWeek" => 2, "name" => "Other"}]};
    var nameSaved = badName.commitPair("rsync", nameJournal);
    var nameController = new SessionController(badName);
    nameController.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, reply);
    syncSettle(nameController);
    var nameProblem = LiftosaurLogic.loadSyncProblem();
    var nameOk = nameProblem != null && Model.sameString(nameProblem, "W1 D2: day name differs from API");
    var diagnostics = nameController.diagnostics();
    var diagOk = diagnostics.find("Last sync: W1 D2: day name differs") != null;
    var codeOk = nameController.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE;
    LiftosaurLogic.saveSyncProblem(null);
    var cleared = LiftosaurLogic.loadSyncProblem() == null &&
        new SessionController(new UploadMemoryStore()).diagnostics().find("Last sync:") == null;
    return check(logger, weeksOk && daysPhase, "a weeks journal becomes the days of the reported week") &&
        check(logger, badSaved == false || badStore.loadRoutineSync() == null,
            "a weeks journal with a non-array week is rejected by validation") &&
        check(logger, legacySaved && legacyDays, "an old journal with a flat days list still works") &&
        check(logger, shortSaved && nameSaved, "journals are saved") &&
        check(logger, nameOk && diagOk && codeOk,
            "a rejected day stores its reason and Diagnostics shows it") &&
        check(logger, cleared, "the reason can be cleared");
}

class FixedMeasure {
    public function width(text as String) as Number {
        return text.length() * 10;
    }
}

(:test)
function testTextWrapKeepsAllText(logger as Test.Logger) as Boolean {
    var m = new FixedMeasure();
    var lines = TextWrap.breakLines("Last sync: day 2 has no weight on set 3 · Free 400 KB", m, 130);
    var ok = true;
    var joined = "";
    for (var i = 0; i < lines.size(); i++) {
        var line = lines[i] as String;
        ok = ok && line.length() * 10 <= 130;
        joined = joined + (i == 0 ? "" : " ") + line;
    }
    var okWidth = check(logger, ok, "every wrapped line fits the width");
    var okText = check(logger, Model.sameString(joined, "Last sync: day 2 has no weight on set 3 · Free 400 KB"),
        "wrapping loses no text");
    var long = TextWrap.breakLines("abcdefghijklmnopqrstuvwxyz", m, 100);
    var okCut = check(logger, long.size() == 3 && (long[0] as String).length() == 10,
        "an overlong word is cut by characters");
    var okEmpty = check(logger, TextWrap.breakLines("", m, 100).size() == 0, "empty text has no lines");
    var okClamp = check(logger, TextWrap.clampTop(9, 10, 4) == 6 && TextWrap.clampTop(-1, 10, 4) == 0 &&
        TextWrap.clampTop(3, 2, 4) == 0, "scroll offset is clamped");
    return okWidth && okText && okCut && okEmpty && okClamp;
}
