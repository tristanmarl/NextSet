import Toybox.Lang;
import Toybox.Test;

// Liftosaur sends weight: null for a set the program gives no weight (`Pull Up / 3x8`): a
// bodyweight set. Weighted holds (`Plank / 3x1 30s / 20kg`) upload their own plan weight.
module NullWeightTests {

    function pullUp(weights as Array) as Dictionary {
        var reply = Phase2Tests.phase2ApiWorkout("Pull", 1l, "Pull Up", false, false, "p");
        var sets = [];
        for (var i = 0; i < weights.size(); i++) {
            var set = Phase2Tests.phase2ApiSet("p" + i.toString(), i, "0kg", 8, null, false, false);
            set["weight"] = weights[i];
            sets.add(set);
        }
        SyncProblemTests.problemEntry(reply)["sets"] = sets;
        return reply;
    }

    function firstEntry(routine as Dictionary?) as Dictionary {
        return ((routine as Dictionary)["entries"] as Array)[0] as Dictionary;
    }

    (:test)
    function testNullWeightIsABodyweightExercise(logger as Test.Logger) as Boolean {
        var reply = pullUp([null, null, null]);
        var absent = pullUp([null, null]);
        (SyncProblemTests.problemSet(absent, 0)).remove("weight");
        var routine = Catalog.parseRoutine(reply, 1, 1);
        var other = Catalog.parseRoutine(absent, 1, 1);
        var ok = WorkoutTests.check(logger, Model.liftosaurWorkoutProblem(reply) == null &&
            Model.liftosaurWorkoutProblem(absent) == null && routine != null && other != null,
            "null and missing weights are valid plan sets");
        if (routine == null) {
            return false;
        }
        var entry = firstEntry(routine);
        var target = (entry["setTargets"] as Array)[0] as Dictionary;
        return WorkoutTests.check(logger, Model.sameString(entry["loadType"], "bodyweight") &&
            entry["unit"] == null && entry["increment100"] == null && target["load100"] == null &&
            entry["workingSetCount"] == 3 && Catalog.validRoutine(routine as Dictionary),
            "the exercise is bodyweight with no load and no unit") && ok;
    }

    (:test)
    function testUnreadableWeightIsStillRejected(logger as Test.Logger) as Boolean {
        var text = pullUp(["heavy", null]);
        var number = pullUp([60, null]);
        var unit = pullUp(["60", null]);
        var parsed = Catalog.parseRoutine(text, 1, 1);
        var problem = Catalog.lastProblem;
        var ok = WorkoutTests.check(logger, parsed == null && problem != null &&
            Model.sameString(problem, "W1 D2 Pull Up: bad weight"), "a text weight is named");
        return WorkoutTests.check(logger, Model.liftosaurWorkoutProblem(number) != null &&
            Model.liftosaurWorkoutProblem(unit) != null, "a number or a weight without unit is rejected") && ok;
    }

    (:test)
    function testMixedNullAndWeightedSets(logger as Test.Logger) as Boolean {
        // Weighted and null sets in one exercise: a weight exercise, the null sets load 0.
        var mixed = Catalog.parseRoutine(pullUp(["60kg", null, null]), 1, 1);
        var poundReply = pullUp([null, "45lb"]);
        SyncProblemTests.problemEntry(poundReply)["warmupSets"] = [];
        var pounds = Catalog.parseRoutine(poundReply, 1, 1);
        var clashReply = pullUp(["60kg", null, "45lb"]);
        SyncProblemTests.problemEntry(clashReply)["warmupSets"] = [];
        var clash = Catalog.parseRoutine(clashReply, 1, 1);
        var ok = WorkoutTests.check(logger, mixed != null, "a mix of weighted and null sets syncs");
        if (mixed == null || pounds == null) {
            return false;
        }
        var entry = firstEntry(mixed);
        var targets = entry["setTargets"] as Array;
        ok = WorkoutTests.check(logger, Model.sameString(entry["loadType"], "weight") &&
            Model.sameString(entry["unit"], "kg") && (targets[0] as Dictionary)["load100"] == 6000 &&
            (targets[1] as Dictionary)["load100"] == 0 && (targets[2] as Dictionary)["load100"] == 0 &&
            entry["startingLoad100"] == 6000, "null sets carry load 0 in the unit of the weighted ones") && ok;
        ok = WorkoutTests.check(logger, Model.sameString(firstEntry(pounds)["unit"], "lb") &&
            ((firstEntry(pounds)["setTargets"] as Array)[0] as Dictionary)["load100"] == 0,
            "a null set before a pound set takes the pound unit") && ok;
        return WorkoutTests.check(logger, clash == null && Catalog.lastProblem != null &&
            (Catalog.lastProblem as String).find("mixes kg and lb") != null,
            "kg and lb in one exercise are still rejected") && ok;
    }

    (:test)
    function testNullWarmupWeight(logger as Test.Logger) as Boolean {
        var reply = pullUp(["60kg", "60kg"]);
        var warmup = Phase2Tests.phase2ApiSet("pw", 0, "0kg", 5, null, false, true);
        warmup["weight"] = null;
        SyncProblemTests.problemEntry(reply)["warmupSets"] = [warmup];
        var routine = Catalog.parseRoutine(reply, 1, 1);
        var warm = routine == null ? null : (firstEntry(routine)["warmups"] as Array)[0];
        return WorkoutTests.check(logger, warm != null && (warm as Dictionary)["load100"] == 0,
            "a warmup without weight loads 0");
    }

    function bodyweightJob() as Dictionary {
        var session = Phase2Tests.phase2UploadSession("weight", false, 1790752141, 1790752201);
        var exercise = ((session["exercises"] as Array)[0]) as Dictionary;
        exercise["loadType"] = "bodyweight";
        var slots = exercise["slots"] as Array;
        for (var i = 0; i < slots.size(); i++) {
            var completed = (slots[i] as Dictionary)["completed"];
            if (completed != null) {
                (completed as Dictionary)["load100"] = null;
            }
        }
        return UploadLogic.makeJob(session) as Dictionary;
    }

    (:test)
    function testUploadMapsNullWeightPlans(logger as Test.Logger) as Boolean {
        var job = bodyweightJob();
        var reply = pullUp([null, null, null]);
        SyncProblemTests.problemWorkout(reply)["startTime"] = job["startTime"];
        SyncProblemTests.problemWorkout(reply)["dayName"] = "DayBx";
        var entry = SyncProblemTests.problemEntry(reply);
        entry["name"] = "Row";
        var liveType = UploadLogic.liveLoadType(entry);
        var preview = UploadLogic.previewMaps(job, reply);
        var started = UploadLogic.withStartedWorkout(job, reply);
        var ok = WorkoutTests.check(logger, liveType != null && Model.sameString(liveType, "bodyweight"),
            "null-weight sets are a bodyweight exercise for the upload mapping");
        ok = WorkoutTests.check(logger, preview && started != null, "the upload preview maps") && ok;
        if (started == null) {
            return false;
        }
        var rows = ((started as Dictionary)["setsBody"] as Dictionary)["sets"] as Array;
        var completed = (rows[0] as Dictionary)["completed"] as Dictionary;
        return WorkoutTests.check(logger, Model.sameString(completed["weight"], "0kg") && completed["reps"] == 8,
            "a bodyweight set still sends weight 0kg") && ok;
    }

    function holdRows(planWeight as Object?) as Array? {
        var session = Phase2Tests.phase2UploadSession("timed", false, 1790752141, 1790752201);
        var job = UploadLogic.makeJob(session) as Dictionary;
        var reply = Phase2Tests.phase2ApiWorkout("DayBx", job["startTime"] as Long, "Row", true, false, "h");
        var sets = SyncProblemTests.problemEntry(reply)["sets"] as Array;
        for (var i = 0; i < sets.size(); i++) {
            var set = sets[i] as Dictionary;
            set["weight"] = planWeight;
        }
        var started = UploadLogic.withStartedWorkout(job, reply);
        return started == null ? null : ((started as Dictionary)["setsBody"] as Dictionary)["sets"] as Array;
    }

    (:test)
    function testWeightedHoldSendsItsPlanWeight(logger as Test.Logger) as Boolean {
        var kg = holdRows("20kg");
        var pounds = holdRows("45lb");
        var zero = holdRows("0kg");
        var none = holdRows(null);
        if (kg == null || pounds == null || zero == null || none == null) {
            return WorkoutTests.check(logger, false, "the hold fixtures map");
        }
        var ok = WorkoutTests.check(logger,
            Model.sameString(((kg[0] as Dictionary)["completed"] as Dictionary)["weight"], "20kg") &&
            Model.sameString(((pounds[0] as Dictionary)["completed"] as Dictionary)["weight"], "45lb"),
            "a weighted hold sends the plan's weight string");
        var timer = ((kg[0] as Dictionary)["completed"] as Dictionary)["setTimer"];
        return WorkoutTests.check(logger, Model.sameString(((zero[0] as Dictionary)["completed"] as Dictionary)["weight"], "0kg") &&
            Model.sameString(((none[0] as Dictionary)["completed"] as Dictionary)["weight"], "0kg") && timer == 40,
            "a hold without weight (0 or null) sends 0kg and its measured time") && ok;
    }
}
