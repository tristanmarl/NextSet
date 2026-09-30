import Toybox.Lang;

// Error codes for SessionController; the UI branches on codes, never on message text.
// message() is the long text (feedback and finishing views), shortMessage() the Home notice.
module Err {
    const NONE = 0;
    const UPDATE_APP_TO_RESUME = 1;
    const SAVED_WORKOUT_IS_DAMAGED = 2;
    const RECOVERED_EARLIER_CHECKPOINT = 3;
    const SAVED_SETTINGS_ARE_DAMAGED = 4;
    const SETTINGS_SAVE_FAILED = 6;
    const ROUTINE_LIMIT_REACHED = 9;
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
    const PHONE_NOT_CONNECTED = 51;
    const NO_RESPONSE_WILL_RETRY = 52;
    const NO_ACTIVE_WORKOUT = 53;

    function message(code as Number) as String? {
        switch (code) {
            case UPDATE_APP_TO_RESUME:
                return "Update app to resume";
            case SAVED_WORKOUT_IS_DAMAGED:
                return "Saved workout is damaged";
            case RECOVERED_EARLIER_CHECKPOINT:
                return "Recovered earlier checkpoint";
            case SAVED_SETTINGS_ARE_DAMAGED:
                return "Saved settings are damaged";
            case SETTINGS_SAVE_FAILED:
                return "Settings save failed";
            case ROUTINE_LIMIT_REACHED:
                return "Routine limit reached";
            case ROUTINE_NOT_FOUND:
                return "Routine not found";
            case ACTIVITY_STATE_SAVE_FAILED:
                return "Activity state save failed";
            case ACTIVITY_RESUME_FAILED:
                return "Activity resume failed";
            case ACTIVITY_SAVE_FAILED:
                return "Activity save failed";
            case ACTIVITY_RECORDING_FAILED_TO_START_STATE_SAVE_FAILED:
                return "Activity recording failed to start; state save failed";
            case ACTIVITY_RECORDING_FAILED_TO_START:
                return "Activity recording failed to start";
            case ACTIVITY_STATE_SAVE_AND_DISCARD_FAILED:
                return "Activity state save and discard failed";
            case SAVE_FAILED_RETRY_BEFORE_CONTINUING:
                return "Save failed. Retry before continuing.";
            case TIMED_SET_RECOVERY_FAILED:
                return "Timed set recovery failed";
            case RECOVERY_SAVE_FAILED:
                return "Recovery save failed";
            case HISTORY_NEEDS_NEWER_APP:
                return "History needs newer app";
            case HISTORY_SAVE_FAILED:
                return "History save failed";
            case PREVIOUS_PERFORMANCE_SAVE_FAILED:
                return "Previous performance save failed";
            case WORKOUT_ARCHIVE_SAVED_RETRY_FINISH:
                return "Workout not closed; retry finish";
            case ACTIVITY_RESULT_UNKNOWN:
                return "Activity result unknown";
            case ACTIVITY_DISCARD_FAILED:
                return "Activity discard failed";
            case WORKOUT_IS_ALREADY_STARTING:
                return "Workout is already starting";
            case WORKOUT_CANNOT_START:
                return "Workout cannot start";
            case ROUTINE_HAS_NO_EXERCISES:
                return "Routine has no exercises";
            case WORKOUT_COULD_NOT_BE_CREATED:
                return "Workout could not be created";
            case COULD_NOT_RESERVE_WORKOUT_ID:
                return "Could not reserve workout ID";
            case EXERCISE_CHOICE_INVALID:
                return "Exercise choice invalid";
            case FINISH_OR_PAUSE_THE_CURRENT_SET_FIRST:
                return "Finish or pause the current set first";
            case WORKOUT_IS_ALREADY_FINISHING:
                return "Workout is already finishing";
            case LOG_A_SET_BEFORE_SAVING:
                return "Log a set before saving";
            case ACTIVITY_SAVED_HISTORY_UPDATE_FAILED:
                return "Activity saved; history update failed";
            case LIFTOSAUR_KEY_REQUIRED:
                return "Set Liftosaur key in Settings";
            case ROUTINE_SYNC_REQUEST_FAILED:
                return "Could not reach Liftosaur";
            case LIFTOSAUR_UNAUTHORIZED:
                return "Liftosaur key was rejected";
            case ROUTINE_SYNC_INVALID_RESPONSE:
                return "Liftosaur routine data is invalid";
            case ROUTINE_SYNC_SAVE_FAILED:
                return "Could not save routines";
            case ROUTINE_SYNC_RESPONSE_TOO_LARGE:
                return "Liftosaur response too large; try later";
            case UPLOAD_QUEUE_FULL:
                return "Workout upload queue is full";
            case UPLOAD_QUEUE_DAMAGED:
                return "Workout upload queue is damaged";
            case WORKOUT_UPLOAD_FAILED:
                return "Workout upload failed; it will retry";
            case WORKOUT_UPLOAD_BLOCKED:
                return "Liftosaur has another workout open";
            case WORKOUT_UPLOAD_PROGRAM_ERROR:
                return "Fix the program in Liftosaur, then retry";
            case WORKOUT_UPLOAD_MAPPING:
                return "Program changed; skip the upload or re-sync";
            case PHONE_NOT_CONNECTED:
                return "Phone not connected";
            case NO_RESPONSE_WILL_RETRY:
                return "No response · will retry";
            case NO_ACTIVE_WORKOUT:
                return "No active workout";
        }
        return null;
    }

    // Home notice text; null when the code has no dedicated short text.
    function shortMessage(code as Number) as String? {
        switch (code) {
            case RECOVERED_EARLIER_CHECKPOINT:
                return "Recovered checkpoint";
            case RECOVERY_SAVE_FAILED:
                return "Recovery save failed";
            case TIMED_SET_RECOVERY_FAILED:
                return "Recovery save failed";
            case SAVE_FAILED_RETRY_BEFORE_CONTINUING:
                return "Save failed. Retry";
            case SAVED_WORKOUT_IS_DAMAGED:
                return "Workout data damaged";
            case SAVED_SETTINGS_ARE_DAMAGED:
                return "Settings data damaged";
            case UPDATE_APP_TO_RESUME:
                return "Update app to resume";
            case ROUTINE_NOT_FOUND:
                return "Routine not found";
            case WORKOUT_CANNOT_START:
                return "Workout cannot start";
            case COULD_NOT_RESERVE_WORKOUT_ID:
                return "Could not start workout";
            case WORKOUT_COULD_NOT_BE_CREATED:
                return "Workout creation failed";
            case ACTIVITY_RECORDING_FAILED_TO_START:
                return "Recording failed to start";
            case ACTIVITY_DISCARD_FAILED:
                return "Recording cleanup failed";
            case HISTORY_SAVE_FAILED:
                return "History save failed";
            case PREVIOUS_PERFORMANCE_SAVE_FAILED:
                return "Last time save failed";
            case WORKOUT_ARCHIVE_SAVED_RETRY_FINISH:
                return "Retry to finish";
            case LOG_A_SET_BEFORE_SAVING:
                return "Log one set first";
            case HISTORY_NEEDS_NEWER_APP:
                return "Update app to save history";
            case LIFTOSAUR_KEY_REQUIRED:
                return "Set Liftosaur key in Settings";
            case LIFTOSAUR_UNAUTHORIZED:
                return "Liftosaur key was rejected";
            case UPLOAD_QUEUE_FULL:
                return "Upload queue full · retry later";
            case UPLOAD_QUEUE_DAMAGED:
                return "Upload queue damaged · MENU to clear";
            case WORKOUT_UPLOAD_PROGRAM_ERROR:
                return "Fix program in Liftosaur";
            case WORKOUT_UPLOAD_MAPPING:
                return "Program changed · MENU skip/re-sync";
            case PHONE_NOT_CONNECTED:
                return "Phone not connected";
            case NO_RESPONSE_WILL_RETRY:
                return "No response · will retry";
            case WORKOUT_UPLOAD_BLOCKED:
                return "Finish open Liftosaur workout";
            case WORKOUT_UPLOAD_FAILED:
                return "Workout upload pending · MENU to retry";
            case ROUTINE_SYNC_REQUEST_FAILED:
                return message(code);
            case ROUTINE_SYNC_INVALID_RESPONSE:
                return message(code);
            case ROUTINE_SYNC_SAVE_FAILED:
                return message(code);
            case ROUTINE_SYNC_RESPONSE_TOO_LARGE:
                return message(code);
        }
        return null;
    }
}
