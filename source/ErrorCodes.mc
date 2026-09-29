import Toybox.Lang;

// Error codes for SessionController; the UI branches on codes, never on message text.
module Err {
    const NONE = 0;
    const UPDATE_APP_TO_RESUME = 1;
    const SAVED_WORKOUT_IS_DAMAGED = 2;
    const RECOVERED_EARLIER_CHECKPOINT = 3;
    const SAVED_SETTINGS_ARE_DAMAGED = 4;
    const SETTINGS_MIGRATION_SAVE_FAILED = 5;
    const SETTINGS_SAVE_FAILED = 6;
    const ROUTINE_LIST_IS_INVALID = 7;
    const ROUTINE_NAME_IS_REQUIRED_64_BYTES_MAX = 8;
    const ROUTINE_LIMIT_REACHED = 9;
    const ROUTINE_NAME_ALREADY_EXISTS = 10;
    const ROUTINE_COULD_NOT_BE_CREATED = 11;
    const UPPER_AND_LOWER_ROUTINES_ARE_KEPT = 12;
    const ROUTINE_NOT_FOUND = 13;
    const ACTIVITY_STATE_SAVE_FAILED = 14;
    const ACTIVITY_RESUME_FAILED = 15;
    const ACTIVITY_SAVE_FAILED = 16;
    const ACTIVITY_RECORDING_FAILED_TO_START_STATE_SAVE_FAILED = 17;
    const ACTIVITY_RECORDING_FAILED_TO_START = 18;
    const ACTIVITY_STATE_SAVE_AND_DISCARD_FAILED = 19;
    const FITSTATE = 20;
    const FAILED = 21;
    const ACTIVITY_PAUSE_FAILED = 22;
    const SAVE_FAILED_RETRY_BEFORE_CONTINUING = 23;
    const TIMED_SET_RECOVERY_FAILED = 24;
    const RECOVERY_SAVE_FAILED = 25;
    const HISTORY_NEEDS_NEWER_APP = 26;
    const HISTORY_SAVE_FAILED = 27;
    const PREVIOUS_PERFORMANCE_SAVE_FAILED = 28;
    const WORKOUT_ARCHIVE_SAVED_RETRY_FINISH = 29;
    const ACTIVITY_RESULT_UNKNOWN = 30;
    const ACTIVITY_DISCARD_FAILED = 31;
    const WORKOUT_IS_ALREADY_STARTING = 32;
    const WORKOUT_CANNOT_START = 33;
    const ROUTINE_HAS_NO_EXERCISES = 34;
    const WORKOUT_COULD_NOT_BE_CREATED = 35;
    const COULD_NOT_RESERVE_WORKOUT_ID = 36;
    const EXERCISE_CHOICE_INVALID = 37;
    const FINISH_OR_PAUSE_THE_CURRENT_SET_FIRST = 38;
    const WORKOUT_IS_ALREADY_FINISHING = 39;
    const LOG_A_SET_BEFORE_SAVING = 40;
    const ACTIVITY_SAVED_HISTORY_UPDATE_FAILED = 41;

    const MESSAGES = [
        null,
        "Update app to resume",
        "Saved workout is damaged",
        "Recovered earlier checkpoint",
        "Saved settings are damaged",
        "Settings migration save failed",
        "Settings save failed",
        "Routine list is invalid",
        "Routine name is required (64 bytes max)",
        "Routine limit reached",
        "Routine name already exists",
        "Routine could not be created",
        "Upper and Lower routines are kept",
        "Routine not found",
        "Activity state save failed",
        "Activity resume failed",
        "Activity save failed",
        "Activity recording failed to start; state save failed",
        "Activity recording failed to start",
        "Activity state save and discard failed",
        "fitState",
        "failed",
        "Activity pause failed",
        "Save failed. Retry before continuing.",
        "Timed set recovery failed",
        "Recovery save failed",
        "History needs newer app",
        "History save failed",
        "Previous performance save failed",
        "Workout archive saved; retry finish",
        "Activity result unknown",
        "Activity discard failed",
        "Workout is already starting",
        "Workout cannot start",
        "Routine has no exercises",
        "Workout could not be created",
        "Could not reserve workout ID",
        "Exercise choice invalid",
        "Finish or pause the current set first",
        "Workout is already finishing",
        "Log a set before saving",
        "Activity saved; history update failed"
    ];

    function message(code as Number) as String? {
        return code > 0 && code < MESSAGES.size() ? MESSAGES[code] as String : null;
    }
}
