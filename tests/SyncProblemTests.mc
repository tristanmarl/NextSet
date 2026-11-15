import Toybox.Lang;
import Toybox.Test;

module SyncProblemTests {

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
    function testWorkoutProblemTexts(logger as Test.Logger) as Boolean {
        var good = Phase2Tests.phase2ApiWorkout("Day", 1l, "Squat", false, false, "g");
        // EMOM ("5x5 60kg 60s|0s auto"): a set timer with five reps is a weight/reps set.
        var emom = Phase2Tests.phase2ApiWorkout("Day", 1l, "Power Clean", true, false, "t");
        for (var s = 0; s < 2; s++) {
            problemSet(emom, s)["reps"] = 5;
            problemSet(emom, s)["weight"] = "60kg";
        }
        var mixed = Phase2Tests.phase2ApiWorkout("Day", 1l, "Power Clean", true, false, "x");
        problemSet(mixed, 0)["reps"] = 5;
        var empty = Phase2Tests.phase2ApiWorkout("Day", 1l, "Squat", false, false, "e");
        problemWorkout(empty)["entries"] = [];
        var noWeight = Phase2Tests.phase2ApiWorkout("Day", 1l, "Squat", false, false, "w");
        problemSet(noWeight, 0)["weight"] = "heavy";
        var many = Phase2Tests.phase2ApiWorkout("Day", 1l, "Squat", false, false, "m");
        var manySets = [];
        for (var i = 0; i < 12; i++) {
            manySets.add(Phase2Tests.phase2ApiSet("m" + i.toString(), i, "60kg", 10, null, false, false));
        }
        problemEntry(many)["sets"] = manySets;
        var dup = Phase2Tests.phase2ApiWorkout("Day", 1l, "Squat", false, false, "d");
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
        var weightOk = weightProblem != null && Model.sameString(weightProblem, "W1 D2 Squat: bad weight");
        var manyOk = manyProblem != null &&
            Model.sameString(manyProblem, "W1 D2 Squat: 12 sets (max 10)");
        var dupOk = dupProblem != null && dupProblem.find("duplicate set id") != null;
        var parsed = Catalog.parseRoutine(noWeight, 1, 1);
        var catalogOk = parsed == null && Catalog.lastProblem != null &&
            Model.sameString(Catalog.lastProblem, "W1 D2 Squat: bad weight");
        var validAgain = Catalog.parseRoutine(good, 1, 1);
        return WorkoutTests.check(logger, goodProblem == null && Model.validLiftosaurWorkout(good),
                "a valid workout has no problem") &&
            WorkoutTests.check(logger, emomOk, "EMOM sets (set timer, several reps) sync as a weight exercise") &&
            WorkoutTests.check(logger, emomTargetOk, "EMOM targets keep reps and load, no hold duration") &&
            WorkoutTests.check(logger, mixedOk, "an exercise mixing holds and EMOM sets is named") &&
            WorkoutTests.check(logger, emptyOk, "empty day is named") &&
            WorkoutTests.check(logger, weightOk, "an unreadable weight is named") &&
            WorkoutTests.check(logger, manyOk, "too many sets is named") &&
            WorkoutTests.check(logger, dupOk && notObject != null, "duplicate ids and non-objects are named") &&
            WorkoutTests.check(logger, catalogOk, "Catalog.parseRoutine records the same reason") &&
            WorkoutTests.check(logger, validAgain != null && Catalog.lastProblem == null,
                "a good parse clears the reason");
    }

    (:test)
    function testSyncReasonsAreStoredAndShown(logger as Test.Logger) as Boolean {
        var reply = Phase2Tests.phase2ApiWorkout("Dayy", 1l, "Squat", false, false, "j");
        // The reply is for week 1, day 2; the journal waits for day 1.
        var badWeek = new UploadStoreTests.UploadMemoryStore();
        var journal = {"sequence" => 1, "phase" => "probe", "index" => 0, "programId" => "x0001xxx",
            "programName" => "P", "nextWeek" => 1, "nextDay" => 2, "routineIds" => []};
        var saved = badWeek.commitPair("rsync", journal);
        LiftosaurLogic.saveSyncProblem("old problem");
        var controller = new SessionController(badWeek);
        controller.handleApiResponse(Liftosaur.REQ_SYNC_DAY, null, 200, reply);
        SyncStageTests.syncSettle(controller);
        var problem = LiftosaurLogic.loadSyncProblem();
        var reasonOk = problem != null && Model.sameString(problem, "W1 D1: API sent another week or day");
        var diagnostics = controller.diagnostics();
        var diagOk = diagnostics.find("Last sync: W1 D1: API sent another week or day") != null;
        var codeOk = controller.errorCode() == Err.ROUTINE_SYNC_INVALID_RESPONSE;
        LiftosaurLogic.saveSyncProblem(null);
        var cleared = LiftosaurLogic.loadSyncProblem() == null &&
            new SessionController(new UploadStoreTests.UploadMemoryStore()).diagnostics().find("Last sync:") == null;
        return WorkoutTests.check(logger, saved, "the journal is saved") &&
            WorkoutTests.check(logger, reasonOk && diagOk && codeOk,
                "a rejected day stores its reason and Diagnostics shows it") &&
            WorkoutTests.check(logger, cleared, "the reason can be cleared");
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
        var okWidth = WorkoutTests.check(logger, ok, "every wrapped line fits the width");
        var okText = WorkoutTests.check(logger, Model.sameString(joined, "Last sync: day 2 has no weight on set 3 · Free 400 KB"),
            "wrapping loses no text");
        var long = TextWrap.breakLines("abcdefghijklmnopqrstuvwxyz", m, 100);
        var okCut = WorkoutTests.check(logger, long.size() == 3 && (long[0] as String).length() == 10,
            "an overlong word is cut by characters");
        var okEmpty = WorkoutTests.check(logger, TextWrap.breakLines("", m, 100).size() == 0, "empty text has no lines");
        var okClamp = WorkoutTests.check(logger, TextWrap.clampTop(9, 10, 4) == 6 && TextWrap.clampTop(-1, 10, 4) == 0 &&
            TextWrap.clampTop(3, 2, 4) == 0, "scroll offset is clamped");
        return okWidth && okText && okCut && okEmpty && okClamp;
    }
}
