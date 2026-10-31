import Toybox.Lang;
import Toybox.Test;

// Liftosaur accounts in pounds send "135lb": parse, keep the unit, upload in the same unit.
function poundReply(warmupWeight as String) as Dictionary {
    var reply = phase2ApiWorkout("Pounds", 1111111111111l, "Bench Press", false, false, "lbs");
    var workout = (reply["data"] as Dictionary)["workout"] as Dictionary;
    var entry = (workout["entries"] as Array)[0] as Dictionary;
    var sets = entry["sets"] as Array;
    for (var i = 0; i < sets.size(); i++) {
        var set = sets[i] as Dictionary;
        set["weight"] = "135lb";
    }
    var warmup = (entry["warmupSets"] as Array)[0] as Dictionary;
    warmup["weight"] = warmupWeight;
    return reply;
}

(:test)
function testPoundWeightsParse(logger as Test.Logger) as Boolean {
    var unitLb = Model.sameString(Model.weightUnit("225lb"), "lb");
    var unitKg = Model.sameString(Model.weightUnit("100kg"), "kg");
    var unitBad = Model.weightUnit("100") == null && Model.weightUnit("100lbs") == null;
    var loads = Model.weightLoad100("135lb") == 13500 && Model.weightLoad100("62.5kg") == 6250;
    return check(logger, unitLb && unitKg && unitBad, "weight units are kg or lb") &&
        check(logger, loads, "weights keep their own unit in hundredths");
}

(:test)
function testPoundRoutineKeepsUnit(logger as Test.Logger) as Boolean {
    var routine = Catalog.parseRoutine(poundReply("95lb"), 1, 1);
    if (routine == null) {
        return check(logger, false, "a pound routine parses");
    }
    var entry = ((routine as Dictionary)["entries"] as Array)[0] as Dictionary;
    var unitOk = Model.sameString(entry["unit"], "lb");
    var stepOk = entry["increment100"] == 500;
    var loadOk = entry["startingLoad100"] == 13500;
    var session = Catalog.createSession((routine as Dictionary)["id"] as String, "lb-1", 1, 1790752141,
        null, {"routines" => [routine], "settings" => {"defaultRestSec" => 90}});
    var exercise = session == null ? null :
        ((session as Dictionary)["exercises"] as Array)[0] as Dictionary;
    var sessionUnit = exercise != null && Model.sameString(UiFormat.unit(exercise as Dictionary), "lb");
    var mixed = Catalog.parseRoutine(poundReply("40kg"), 1, 1) == null;
    return check(logger, unitOk && stepOk && loadOk, "a pound exercise keeps lb and a 5 lb step") &&
        check(logger, sessionUnit, "the session exercise shows lb") &&
        check(logger, mixed, "an exercise mixing kg and lb is rejected");
}

(:test)
function testPoundUploadAndFit(logger as Test.Logger) as Boolean {
    var strings = Model.sameString(UploadLogic.weightString(13500, "lb"), "135lb") &&
        Model.sameString(UploadLogic.weightString(6250, "kg"), "62.5kg") &&
        Model.sameString(UploadLogic.weightString(6250, null), "62.5kg");
    var mapped = UploadLogic.mappedCompleted({"unit" => "lb", "unilateral" => false},
        {"kg" => 135.0, "reps" => 5}, {"reps" => 5, "weight" => "135lb"});
    var mappedOk = mapped != null && Model.sameString((mapped as Dictionary)["weight"], "135lb");
    var oldJob = UploadLogic.mappedCompleted({"unilateral" => false},
        {"kg" => 60.0, "reps" => 5}, {"reps" => 5, "weight" => "60kg"});
    var oldJobOk = oldJob != null && Model.sameString((oldJob as Dictionary)["weight"], "60kg");
    var kg = Model.toKg(100.0, "lb");
    var fitOk = kg > 45.35 && kg < 45.37 && Model.toKg(100.0, "kg") == 100.0;
    return check(logger, strings, "weights upload in their own unit") &&
        check(logger, mappedOk, "a pound set uploads as lb") &&
        check(logger, oldJobOk, "queued jobs from before pound support stay kg") &&
        check(logger, fitOk, "FIT weight fields are converted to kg");
}
