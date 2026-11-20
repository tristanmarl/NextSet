# Liftosaur API notes

How NextSet uses the [Liftosaur REST API](https://www.liftosaur.com/doc/api). The API needs a Liftosaur premium account and an API key (`lftsk_…`). Schema notes were observed with GET requests on 2026-09-30; values below are examples.

## Requests

Base URL `https://www.liftosaur.com/api/v1`, header `Authorization: Bearer <key>`. Writes (POST) also send `Content-Type` as `Communications.REQUEST_CONTENT_TYPE_JSON` (GETs send none; the string "application/json" made fenix 7 / fenix 8 firmware fail every request with CIQ -200). Every write also sends `X-Liftosaur-Device-Id` (generated once per install, `nextset-` + 24 random characters, kept in app storage) and `X-Liftosaur-Client: nextset-watch/<version>`. Replies use the envelope `{"data": …}`; errors are `{"error": {code, message}}`. Only one request is in flight at a time.

| Purpose | Request |
| --- | --- |
| Test key | `GET /programs/current` (read-only) |
| Day to sync | `GET /workout/next` (names program, week and next day), then `GET /workout/next?programId&week=W&dayInWeek=N` for N = 1, 2, … until `404 day_not_found` (at most 8 days; a ninth is only noted). Day names come from each reply's `dayName`. A day skipped because it has no exercises NextSet can run keeps a short reason (Settings → Diagnostics → "Last sync") |
| Upload check | `GET /workout/next` for the job's day (no write) |
| Upload | `POST /workout/start`, `POST /workout/sets`, `POST /workout/finish` |

## Schema notes

- `GET /workout/next` → `{workout: {programId, programName, dayName, dayData: {day, week, dayInWeek}, startTime, entries: [...]}}`. `startTime` is "now" and every `setId` is regenerated on each GET, so preview ids are only illustrative; the upload takes the ids from the `/workout/start` reply.
- Entry: `{entryId, exerciseId, equipment, name, superset, notes, description, hasUpdateScript, promptedVars, warmupSets: [...], sets: [...]}`. `name` is the display name without equipment (`"Leg Press"`); a custom exercise has a random id and `equipment: null`.
- Set: `{setId, index, isWarmup, reps, minReps, isAmrap, weight: "100kg", isUnilateral, timer (rest s, per set: `3x5 20s, 2x5 120s` gives each set its own), setTimer (timed set s or null), completed}`. A timed set is `reps: 1, weight: "0kg", setTimer: 35`; a set timer with more than one rep (EMOM, `5x5 60kg 60s|0s auto`) is synced and uploaded as a weight/reps set without `setTimer` (not yet confirmed by a real write); bodyweight is `weight: "0kg"`. Weights arrive already rounded to the gym's plates. A set the program gives no weight has `weight: null` (`Pull Up / 3x8`); NextSet treats it as bodyweight (load 0, no unit). A hold with a weight (`Plank / 3x1 30s / 20kg`) keeps `weight: "20kg"` and the upload sends that plan weight with `setTimer`. Warmups are in `warmupSets`.
- `GET /history` returns Liftohistory text: `// note` lines, then `date / program: "…" / dayName: "…" / week / dayInWeek / duration: Ns / exercises: {`, one line per exercise, `}`.

## Upload rules

A finished workout becomes an upload job (`UploadLogic.makeJob`), persisted in a queue of at most four:

1. **Check.** `GET /workout/next` for the job's program, week and day; `UploadLogic.previewMaps` must map every logged set. A mismatch marks the job `program_changed` and sends nothing.
2. **Start.** `POST /workout/start {programId, week, dayInWeek, startTime}` starts that day explicitly, independent of Liftosaur's next-day pointer. If a workout with the same program, week, day and `startTime` is already live (a retry, a crash-resume), the server answers 200 with it (`ApiV1_startWorkout`); `409 workout_already_active` therefore means a different workout is open: the job is blocked until it is finished or discarded in Liftosaur.
3. **Sets.** `POST /workout/sets {sets: [{entryId, setId, completed: {reps, weight, setTimer?, repsLeft?}, append?}]}`. Watch set *n* maps to planned working set *n*; extra sets go out with `append: true` and a stable six-letter id. Logged warmups map by position onto the start reply's `warmupSets`; extras are listed in the notes. Timed sets send `setTimer`; unilateral sets send `repsLeft = reps`. A saved exercise maps to the reply entry with the same `name` and the same `entryId` it was synced with (first one not yet claimed); without that, to the entry with its `name` only when exactly one reply entry has it and it is unclaimed; otherwise it is skipped. Liftosaur source (`lambda/utils/apiv1Workout.ts`, `src/models/progress.ts`): `entryId` = `Progress_getEntryId(exerciseType, label)` = `[label, exerciseKey].join("_")`, deterministic per program exercise (same in `/workout/next` and a later `/workout/start`; changes only if the label or exercise is edited); `name` is the plain exercise name and there is no label field, so labeled duplicates (`heavy: Squat` / `light: Squat`) differ only by `entryId`. Two entries with the same label and exercise share an `entryId`; they are then claimed in order (`setId` is the real address on the server).
4. **Finish.** `POST /workout/finish {startTime, endTime, intervals: [[startTime, endTime]], notes?}`. `intervals` carries the real duration (without it Liftosaur recorded `duration: 2s`). `notes` is sent only for substitutions and extra warmups, because it becomes a `//` line above the history record; it is cut at 2000 characters (the server rejects more than 2500 with a permanent 400). A replayed finish for a finished `startTime` returns the original summary.

Writes are idempotent by `startTime`, so a job interrupted at any step retries safely after a relaunch. A reply the watch cannot read because it is too large or out of memory (`-402` / `-403`) to `sets` or `finish` counts as applied; to `start` (the set ids come from its reply) it is an error that asks to skip the upload.

## Failures

| Code | NextSet |
| --- | --- |
| HTTP 408, 429, 500-599; CIQ -1, -2, -3, -4, -5, -101, -103, -300, -1003, -1004 | retried later (2, 5, 10 minutes while the app is open, and on the next launch) |
| -104 (no phone link) | "Phone not connected", retried the same way |
| HTTP 400, 401, 403, 404, 409, 422; CIQ -102, -200..-202, -400, -401, -402, -403, -1000..-1002 | final (the server or the request would answer the same); 404 `day_not_found` after day 1 ends the sync probe, 409 `workout_already_active` blocks an upload |

Verify with the server source (`lambda/utils/apiv1Workout.ts`, `docs/content/api.md` "Workout error codes").

## Unverified

- Unilateral `repsLeft` and timed-set progression have not been confirmed by a real workout write.
- Sets that ask for a value (API "Sets that ask for a value"): `logRpe` sets send `completed.rpe`, entries with `promptedVars` send `completed.userVars` on every set, one-sided timed sets send `setTimerLeft` with `setTimer`. Values the lifter did not answer fall back to the program's own suggestion (the set's `rpe`, the advertised variable value, the right-side hold). Not yet confirmed by a real write.
- Weights keep the account's unit: `"135lb"` syncs and uploads as lb; FIT weight fields are converted to kg. Not yet confirmed by a real write.
- Assistance weights are negative in NextSet and sent as positive weights.
- Liftosaur's acceptance of `intervals` from NextSet awaits the next real upload (see `DEVICE_TESTS.md`).
