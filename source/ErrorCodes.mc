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
    const ROUTINE_NOT_FOUND = 12;
    const ACTIVITY_STATE_SAVE_FAILED = 13;
    const ACTIVITY_RESUME_FAILED = 14;
    const ACTIVITY_SAVE_FAILED = 15;
    const ACTIVITY_RECORDING_FAILED_TO_START_STATE_SAVE_FAILED = 16;
    const ACTIVITY_RECORDING_FAILED_TO_START = 17;
    const ACTIVITY_STATE_SAVE_AND_DISCARD_FAILED = 18;
    const SAVE_FAILED_RETRY_BEFORE_CONTINUING = 19;
    const TIMED_SET_RECOVERY_FAILED = 20;
    const RECOVERY_SAVE_FAILED = 21;
    const HISTORY_NEEDS_NEWER_APP = 22;
    const HISTORY_SAVE_FAILED = 23;
    const PREVIOUS_PERFORMANCE_SAVE_FAILED = 24;
    const WORKOUT_ARCHIVE_SAVED_RETRY_FINISH = 25;
    const ACTIVITY_RESULT_UNKNOWN = 26;
    const ACTIVITY_DISCARD_FAILED = 27;
    const WORKOUT_IS_ALREADY_STARTING = 28;
    const WORKOUT_CANNOT_START = 29;
    const ROUTINE_HAS_NO_EXERCISES = 30;
    const WORKOUT_COULD_NOT_BE_CREATED = 31;
    const COULD_NOT_RESERVE_WORKOUT_ID = 32;
    const EXERCISE_CHOICE_INVALID = 33;
    const FINISH_OR_PAUSE_THE_CURRENT_SET_FIRST = 34;
    const WORKOUT_IS_ALREADY_FINISHING = 35;
    const LOG_A_SET_BEFORE_SAVING = 36;
    const ACTIVITY_SAVED_HISTORY_UPDATE_FAILED = 37;
    const AT_LEAST_ONE_ROUTINE_IS_KEPT = 38;
    const LIFTOSAUR_KEY_REQUIRED = 39;
    const ROUTINE_SYNC_REQUEST_FAILED = 40;
    const LIFTOSAUR_UNAUTHORIZED = 41;
    const ROUTINE_SYNC_INVALID_RESPONSE = 42;
    const ROUTINE_SYNC_SAVE_FAILED = 43;
    const ROUTINE_SYNC_RESPONSE_TOO_LARGE = 44;
    const UPLOAD_QUEUE_FULL = 45;
    const UPLOAD_QUEUE_DAMAGED = 46;
    const WORKOUT_UPLOAD_FAILED = 47;
    const WORKOUT_UPLOAD_BLOCKED = 48;
    const WORKOUT_UPLOAD_PROGRAM_ERROR = 49;
    const WORKOUT_UPLOAD_MAPPING = 50;

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
        "Routine not found",
        "Activity state save failed",
        "Activity resume failed",
        "Activity save failed",
        "Activity recording failed to start; state save failed",
        "Activity recording failed to start",
        "Activity state save and discard failed",
        "Save failed. Retry before continuing.",
        "Timed set recovery failed",
        "Recovery save failed",
        "History needs newer app",
        "History save failed",
        "Previous performance save failed",
        "Workout not closed; retry finish",
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
        "Activity saved; history update failed",
        "At least one routine is required",
        "Set the Liftosaur key in the Connect IQ app",
        "Could not reach Liftosaur",
        "Liftosaur key was rejected",
        "Liftosaur routine data is invalid",
        "Could not save routines",
        "Liftosaur response too large; try later",
        "Workout upload queue is full",
        "Workout upload queue is damaged",
        "Workout upload failed; it will retry",
        "Liftosaur has another workout open",
        "Fix the program in Liftosaur, then retry",
        "Program changed; skip the upload or re-sync"
    ];

    function message(code as Number) as String? {
        return code > 0 && code < MESSAGES.size() ? MESSAGES[code] as String : null;
    }
}
