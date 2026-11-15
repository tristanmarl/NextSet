import Toybox.Lang;
import Toybox.Test;

module LabelUploadTests {

    // Liftoscript labels: two entries with one name and different entryIds in the same day.

    function labelEntry(entryId as String, name as String, prefix as String, count as Number,
                        weight as String) as Dictionary {
        var sets = [];
        for (var i = 0; i < count; i++) {
            sets.add(Phase2Tests.phase2ApiSet(prefix + i.toString(), i, weight, 5, null, false, false));
        }
        return {"entryId" => entryId, "exerciseId" => "squat", "equipment" => "barbell",
            "name" => name, "superset" => null, "warmupSets" => [], "sets" => sets};
    }

    function labelReply(entries as Array) as Dictionary {
        return {"data" => {"workout" => {
            "programId" => "x0001xxx", "programName" => "Test Program",
            "dayName" => "DayBx", "dayData" => {"day" => 2, "week" => 1, "dayInWeek" => 2},
            "startTime" => 1790752141000l, "entries" => entries}}};
    }

    function labelExercise(id as String, liftId as String?, name as String, planned as Number,
                           count as Number, load100 as Number, end as Number) as Dictionary {
        var slots = [];
        for (var i = 0; i < count; i++) {
            slots.add({"completed" => Phase2Tests.phase2Completed(load100, 5, null, end - 30 + i)});
        }
        return {"entryId" => id, "liftosaurEntryId" => liftId, "exerciseId" => "lift-squat",
            "name" => name, "loadType" => "weight", "unilateral" => false,
            "liftosaurPlannedSetCount" => planned, "slots" => slots};
    }

    function labelJob(exercises as Array) as Dictionary {
        var session = Phase2Tests.phase2UploadSession("weight", false, 1790752141, 1790752201);
        session["exercises"] = exercises;
        return UploadLogic.makeJob(session) as Dictionary;
    }

    function labelRows(job as Dictionary, reply as Dictionary) as Array? {
        var started = UploadLogic.withStartedWorkout(job, reply);
        if (started == null) {
            return null;
        }
        return ((started as Dictionary)["setsBody"] as Dictionary)["sets"] as Array;
    }

    function labelCount(rows as Array, entryId as String, setPrefix as String) as Number {
        var n = 0;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i] as Dictionary;
            if (Model.sameString(row["entryId"], entryId) &&
                (row["setId"] as String).find(setPrefix) == 0) {
                n++;
            }
        }
        return n;
    }

    (:test)
    function testLabeledSameNameEntriesMapByEntryId(logger as Test.Logger) as Boolean {
        var end = 1790752201;
        var job = labelJob([
            labelExercise("e1", "heavy_squat", "Squat", 2, 2, 10000, end),
            labelExercise("e2", "light_squat", "Squat", 3, 3, 6000, end)]);
        // The reply lists the light entry first: only the id can tell them apart.
        var reply = labelReply([labelEntry("light_squat", "Squat", "lt", 3, "60kg"),
            labelEntry("heavy_squat", "Squat", "hv", 2, "100kg")]);
        var rows = labelRows(job, reply);
        if (rows == null) {
            return WorkoutTests.check(logger, false, "labeled duplicates map");
        }
        var list = rows as Array;
        var heavy = labelCount(list, "heavy_squat", "hv");
        var light = labelCount(list, "light_squat", "lt");
        var cross = labelCount(list, "heavy_squat", "lt") + labelCount(list, "light_squat", "hv");
        var first = list[0] as Dictionary;
        var heavyRow = null;
        for (var i = 0; i < list.size(); i++) {
            if (Model.sameString((list[i] as Dictionary)["setId"], "hv0")) {
                heavyRow = list[i];
            }
        }
        var weight = heavyRow == null ? "" : ((heavyRow as Dictionary)["completed"] as Dictionary)["weight"];
        return WorkoutTests.check(logger, list.size() == 5 && heavy == 2 && light == 3 && cross == 0,
                "both labeled exercises upload their sets to their own entry") &&
            WorkoutTests.check(logger, Model.sameString(weight, "100kg") && first["append"] == null,
                "the heavy sets carry the heavy weight and none is an append");
    }

    (:test)
    function testLabeledDuplicateWithSubstitutedExercise(logger as Test.Logger) as Boolean {
        var end = 1790752201;
        // The second Squat was swapped on the watch (no plan id): it is dropped, the first maps by id.
        var job = labelJob([
            labelExercise("e1", "heavy_squat", "Squat", 2, 2, 10000, end),
            labelExercise("e2", null, "Squat", 1, 1, 6000, end)]);
        var reply = labelReply([labelEntry("light_squat", "Squat", "lt", 3, "60kg"),
            labelEntry("heavy_squat", "Squat", "hv", 2, "100kg")]);
        var rows = labelRows(job, reply);
        if (rows == null) {
            return WorkoutTests.check(logger, false, "substituted duplicate still maps the plan exercise");
        }
        var list = rows as Array;
        return WorkoutTests.check(logger, list.size() == 2 && labelCount(list, "heavy_squat", "hv") == 2,
            "only the plan exercise maps, to its own entry; nothing goes to the other one");
    }

    (:test)
    function testLabeledChangedIdsAndCounts(logger as Test.Logger) as Boolean {
        var end = 1790752201;
        var job = labelJob([
            labelExercise("e1", "heavy_squat", "Squat", 2, 2, 10000, end),
            labelExercise("e2", "light_squat", "Squat", 3, 3, 6000, end)]);
        // Program edited: neither id exists any more and two entries share the name: skipped as before.
        var renamed = labelReply([labelEntry("a_squat", "Squat", "aa", 2, "60kg"),
            labelEntry("b_squat", "Squat", "bb", 2, "60kg"), labelEntry("row", "Row", "rw", 2, "50kg")]);
        var skipped = labelRows(job, renamed);
        // Same name once, with a changed id: the unique-name fallback maps one exercise, never both.
        var single = labelReply([labelEntry("other_squat", "Squat", "ss", 3, "60kg")]);
        var rows = labelRows(job, single);
        var oneRow = rows == null ? 0 : (rows as Array).size();
        var entries = rows == null ? 0 : labelCount(rows as Array, "other_squat", "ss");
        return WorkoutTests.check(logger, skipped == null,
                "ambiguous same-name entries without a matching id are skipped") &&
            WorkoutTests.check(logger, oneRow == 2 && entries == 2,
                "a unique name is used by one exercise only (not mapped twice)");
    }

    (:test)
    function testSingleNameUploadUnchanged(logger as Test.Logger) as Boolean {
        var end = 1790752201;
        var job = labelJob([labelExercise("e1", "raw-entry-id", "Row", 2, 2, 5000, end)]);
        var reply = labelReply([labelEntry("raw-entry-id", "Row", "rr", 2, "50kg")]);
        var changedId = labelReply([labelEntry("renamed-id", "Row", "rr", 2, "50kg")]);
        var rows = labelRows(job, reply);
        var other = labelRows(job, changedId);
        return WorkoutTests.check(logger, rows != null && (rows as Array).size() == 2,
                "a single entry maps by id and name") &&
            WorkoutTests.check(logger, other != null && (other as Array).size() == 2 &&
                Model.sameString(((other as Array)[0] as Dictionary)["entryId"], "renamed-id"),
                "a single entry with a different id still maps by its unique name");
    }
}
