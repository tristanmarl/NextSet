import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

module Issue2Tests {

    // GitHub issue #2: a public 12-week x 2-day program (custom progress blocks, a "used: none"
    // template, AMRAP, supersets, a variation exercise, per-set rests) must sync. The day replies
    // below are built from the shapes Liftosaur sends for it.

    function issue2Set(id as String, reps as Number, minReps as Number?, weight as String,
                       rest as Number, amrap as Boolean, unilateral as Boolean,
                       warmup as Boolean) as Dictionary {
        return {"setId" => id, "index" => 0, "isWarmup" => warmup, "reps" => reps,
            "minReps" => minReps, "isAmrap" => amrap, "weight" => weight,
            "isUnilateral" => unilateral, "timer" => rest, "setTimer" => null,
            "completed" => null};
    }

    // n identical sets of an exercise; opts: "min" (range low), "amrap" (last set), "uni", "warm"
    // (CIQ 3.4 allows at most 9 arguments per function).
    function issue2Entry(key as String, name as String, equipment as String?, superset as String?,
                         count as Number, reps as Number, weight as String, rest as Number,
                         opts as Dictionary) as Dictionary {
        var sets = [];
        for (var i = 0; i < count; i++) {
            sets.add(issue2Set(key + "-s" + i.toString(), reps, opts["min"] as Number?, weight, rest,
                opts["amrap"] == true && i == count - 1, opts["uni"] == true, false));
        }
        var warmups = opts["warm"] == null ? [] : opts["warm"];
        return {"entryId" => "entry-" + key, "exerciseId" => key, "equipment" => equipment,
            "name" => name, "superset" => superset, "notes" => null, "description" => null,
            "hasUpdateScript" => true, "promptedVars" => null, "warmupSets" => warmups,
            "sets" => sets};
    }

    function issue2Warmups(key as String, weight as String) as Array {
        return [issue2Set(key + "-w0", 5, null, "30kg", 0, false, false, true),
            issue2Set(key + "-w1", 3, null, "60kg", 0, false, false, true),
            issue2Set(key + "-w2", 1, null, weight, 0, false, false, true)];
    }

    function issue2Reply(dayName as String, dayInWeek as Number, entries as Array) as Dictionary {
        return {"data" => {"workout" => {"programId" => "1cc9198d",
            "programName" => "Fighter progressive overload", "dayName" => dayName,
            "dayData" => {"day" => dayInWeek, "week" => 1, "dayInWeek" => dayInWeek},
            "startTime" => 1790752141000l, "entries" => entries}}};
    }

    function issue2Day1() as Dictionary {
        return issue2Reply("Day 1", 1, [
            issue2Entry("squat", "Squat", "barbell", null, 5, 5, "90kg", 120,
                {"warm" => issue2Warmups("sq", "72kg")}),
            issue2Entry("bench", "Bench Press", "barbell", null, 5, 5, "70kg", 120,
                {"warm" => issue2Warmups("bp", "60kg")}),
            issue2Entry("pullup", "Pull Up, Band", null, "A", 5, 5, "55kg", 20, {}),
            issue2Entry("bulg", "Bulgarian Split Squat", "barbell", "A", 3, 15, "20kg", 45,
                {"min" => 8, "uni" => true})]);
    }

    function issue2Day2() as Dictionary {
        return issue2Reply("Day 2", 2, [
            issue2Entry("squat", "Squat", "barbell", null, 5, 5, "90kg", 120, {}),
            issue2Entry("bench", "Bench Press", "barbell", null, 5, 5, "70kg", 120, {}),
            issue2Entry("rdl", "Romanian Deadlift", "barbell", null, 5, 5, "100kg", 120,
                {"warm" => issue2Warmups("rd", "85kg")}),
            issue2Entry("adduct", "Cable Hip Adduction", "cable", "A", 3, 12, "2.5kg", 30,
                {"amrap" => true, "uni" => true}),
            issue2Entry("curl", "Incline Curl", "dumbbell", "A", 3, 9, "10kg", 60, {})]);
    }

    (:test)
    function testIssue2Week1RepliesParse(logger as Test.Logger) as Boolean {
        var day1 = Catalog.parseRoutine(issue2Day1(), 1, 1);
        var problem1 = Catalog.lastProblem;
        var day2 = Catalog.parseRoutine(issue2Day2(), 1, 2);
        var problem2 = Catalog.lastProblem;
        var ok = WorkoutTests.check(logger, day1 != null, "Week 1 Day 1 is accepted: " +
            (problem1 == null ? "" : problem1));
        ok = WorkoutTests.check(logger, day2 != null, "Week 1 Day 2 is accepted: " +
            (problem2 == null ? "" : problem2)) && ok;
        if (day1 != null && day2 != null) {
            var entries1 = (day1 as Dictionary)["entries"] as Array;
            var entries2 = (day2 as Dictionary)["entries"] as Array;
            var pull = entries1[2] as Dictionary;
            var bulg = entries1[3] as Dictionary;
            var adduct = entries2[3] as Dictionary;
            ok = WorkoutTests.check(logger, entries1.size() == 4 && entries2.size() == 5, "all exercises kept") && ok;
            ok = WorkoutTests.check(logger, Model.sameString(pull["superset"], "A") &&
                pull["load100"] == null && pull["startingLoad100"] == 5500, "Pull Up, Band keeps 55 kg and superset A") && ok;
            ok = WorkoutTests.check(logger, bulg["unilateral"] == true, "Bulgarian Split Squat is unilateral") && ok;
            ok = WorkoutTests.check(logger, adduct["workingSetCount"] == 3 &&
                ((adduct["setTargets"] as Array).size() == 3), "AMRAP last set stays a normal set") && ok;
        }
        return ok;
    }
}
