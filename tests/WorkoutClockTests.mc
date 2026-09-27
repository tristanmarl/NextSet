import Toybox.Lang;
import Toybox.Test;

function workoutClockCheck(logger as Test.Logger, condition as Boolean, message as String) as Boolean {
    if (!condition) {
        logger.error(message);
        return false;
    }
    return true;
}

(:test)
function testWorkoutClockStartAndCheckpoint(logger as Test.Logger) as Boolean {
    var session = WorkoutClock.start(100);
    var saved = WorkoutClock.checkpoint(session, 125);
    return workoutClockCheck(logger, session["startedAt"] == 100 &&
            session["lastCheckpointAt"] == 100 && session["pausedSec"] == 0 &&
            session["recoveryGapSec"] == 0 && WorkoutClock.elapsed(session, 130) == 30 &&
            WorkoutClock.active(session, 130) == 30,
            "start must initialize legacy fields and both time totals") &&
        workoutClockCheck(logger, saved["lastCheckpointAt"] == 125 &&
            session["lastCheckpointAt"] == 100,
            "checkpoint must return a copy and leave its input unchanged");
}

(:test)
function testWorkoutClockPauseResume(logger as Test.Logger) as Boolean {
    var session = WorkoutClock.start(100);
    var paused = WorkoutClock.pause(session, 140) as Dictionary;
    var resumed = WorkoutClock.resume(paused, 200) as Dictionary;
    return workoutClockCheck(logger, WorkoutClock.elapsed(paused, 170) == 70 &&
            WorkoutClock.active(paused, 170) == 40 &&
            paused["pauseStartedAt"] == 140 &&
            WorkoutClock.elapsed(resumed, 210) == 110 && WorkoutClock.active(resumed, 210) == 50 &&
            WorkoutClock.elapsed(resumed, 210) >= WorkoutClock.active(resumed, 210) &&
            resumed["pausedSec"] == 60 && resumed["pauseStartedAt"] == null,
            "explicit pause duration must be excluded exactly once") &&
        workoutClockCheck(logger, WorkoutClock.pause(paused, 180) == null &&
            WorkoutClock.resume(resumed, 220) == null && session["pausedSec"] == 0,
            "invalid pause transitions must not mutate their inputs");
}

(:test)
function testWorkoutClockRecoveryGapOnce(logger as Test.Logger) as Boolean {
    var session = WorkoutClock.checkpoint(WorkoutClock.start(100), 130);
    var recovered = WorkoutClock.recover(session, 200);
    var recoveredAgain = WorkoutClock.recover(recovered, 200);
    return workoutClockCheck(logger, recovered["lastCheckpointAt"] == 200 &&
            recovered["recoveryGapSec"] == 70 &&
            WorkoutClock.elapsed(recovered, 220) == 120 && WorkoutClock.active(recovered, 220) == 50 &&
            WorkoutClock.elapsed(recovered, 220) >= WorkoutClock.active(recovered, 220) &&
            recoveredAgain["recoveryGapSec"] == 70,
            "recovery must exclude the checkpoint gap once") &&
        workoutClockCheck(logger, session["lastCheckpointAt"] == 130 &&
            session["recoveryGapSec"] == 0,
            "recovery must leave the saved session unchanged");
}

(:test)
function testWorkoutClockRecoveryWhilePaused(logger as Test.Logger) as Boolean {
    var paused = WorkoutClock.pause(WorkoutClock.start(100), 130) as Dictionary;
    var recovered = WorkoutClock.recover(paused, 200);
    var resumed = WorkoutClock.resume(recovered, 220) as Dictionary;
    return workoutClockCheck(logger, recovered["recoveryGapSec"] == 0 &&
            WorkoutClock.elapsed(resumed, 230) == 130 && WorkoutClock.active(resumed, 230) == 40 &&
            WorkoutClock.elapsed(resumed, 230) >= WorkoutClock.active(resumed, 230) &&
            resumed["pausedSec"] == 90,
            "recovery during explicit pause must be counted by resume only");
}

(:test)
function testWorkoutClockBackwardTimeClamps(logger as Test.Logger) as Boolean {
    var session = WorkoutClock.start(100);
    var paused = WorkoutClock.pause(session, 90) as Dictionary;
    var resumed = WorkoutClock.resume(paused, 80) as Dictionary;
    var recovered = WorkoutClock.recover(session, 90);
    return workoutClockCheck(logger, paused["pauseStartedAt"] == 100 &&
            resumed["pausedSec"] == 0 && WorkoutClock.elapsed(resumed, 90) == 0 &&
            recovered["recoveryGapSec"] == 0 && recovered["lastCheckpointAt"] == 100,
            "backward epoch inputs must not produce negative time");
}
