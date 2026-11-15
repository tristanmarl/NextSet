import Toybox.Lang;

// Stored and wire strings of the Liftosaur sync. The values are persisted (upload job states,
// sync journal phases, last-error codes): never change them.
module Liftosaur {
    // Upload job "state".
    const STATE_START = "start";
    const STATE_SETS = "sets";
    const STATE_FINISH = "finish";
    const STATE_BLOCKED = "blocked";
    const STATE_DONE = "done";

    // History upload status (besides STATE_DONE).
    const STATUS_SKIPPED = "skipped";
    const STATUS_PENDING = "pending";

    // Routine sync journal "phase".
    // Written by versions up to 0.6.x (program text parsed for the day names). They still load,
    // but a journal in one of them restarts the sync from PHASE_FIRST: the routines it already
    // committed are rewritten under the same ids.
    const PHASE_PROGRAM = "program";
    const PHASE_NEXT = "next";
    const PHASE_DAYS = "days";
    const PHASE_WEEK = "week";
    // Current flow: PHASE_FIRST (the first /workout/next gives program, name, week and next day),
    // PHASE_PROBE (day 1, 2, ... of that week one request each; "index" days are done), PHASE_PROBED
    // (the week's last day was seen: only the pivot is left).
    const PHASE_FIRST = "first";
    const PHASE_PROBE = "probe";
    const PHASE_PROBED = "probed";

    // Request purposes (in memory only).
    const REQ_SYNC_NEXT = "sync_next";
    const REQ_SYNC_DAY = "sync_day";
    const REQ_KEY_TEST = "key_test";
    const REQ_UPLOAD_PREVIEW = "upload_preview";
    const REQ_UPLOAD_START = "upload_start";
    const REQ_UPLOAD_RESUME_SETS = "upload_resume_sets";
    const REQ_UPLOAD_SETS = "upload_sets";
    const REQ_UPLOAD_FINISH = "upload_finish";

    // Job "lastError" values and Liftosaur error codes.
    const ERR_PROGRAM_CHANGED = "program_changed";
    const ERR_PROGRAM_ERROR = "program_error";
    const ERR_ALREADY_ACTIVE = "workout_already_active";
    const ERR_START_TIME_TAKEN = "workout_start_time_taken";
    const ERR_DAY_NOT_FOUND = "day_not_found";
}
