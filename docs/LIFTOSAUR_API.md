# Liftosaur API notes

How NextSet uses the [Liftosaur REST API](https://www.liftosaur.com/doc/api). The API needs a Liftosaur premium account and an API key (`lftsk_…`). Schema notes were observed with GET requests on 2026-09-30; values below are examples.

## Requests

Base URL `https://www.liftosaur.com/api/v1`, header `Authorization: Bearer <key>`. Every write also sends `X-Liftosaur-Device-Id` (generated once per install, `nextset-` + 24 random characters, kept in app storage) and `X-Liftosaur-Client: nextset-watch/<version>`. Replies use the envelope `{"data": …}`; errors are `{"error": {code, message}}`. Only one request is in flight at a time.

| Purpose | Request |
| --- | --- |
| Test key | `GET /programs/current` (read-only) |
| Program text | `GET /programs/current` → `{id, name, text}`; `text` is Liftoscript (`# Week N`, `## Day`, one line per exercise) |
| Day to sync | `GET /workout/next[?programId&week&dayInWeek]` |
| Upload check | `GET /workout/next` for the job's day (no write) |
| Upload | `POST /workout/start`, `POST /workout/sets`, `POST /workout/finish` |
| Crash resume | `GET /workout/current` after `409 workout_already_active` |

## Schema notes

- `GET /workout/next` → `{workout: {programId, programName, dayName, dayData: {day, week, dayInWeek}, startTime, entries: [...]}}`. `startTime` is "now" and every `setId` is regenerated on each GET, so preview ids are only illustrative; the upload takes the ids from the `/workout/start` reply.
- Entry: `{entryId, exerciseId, equipment, name, superset, notes, description, hasUpdateScript, promptedVars, warmupSets: [...], sets: [...]}`. `name` is the display name without equipment (`"Leg Press"`); a custom exercise has a random id and `equipment: null`.
- Set: `{setId, index, isWarmup, reps, minReps, isAmrap, weight: "100kg", isUnilateral, timer (rest s), setTimer (timed set s or null), completed}`. A timed set is `reps: 1, weight: "0kg", setTimer: 35`; bodyweight is `weight: "0kg"`. Weights arrive already rounded to the gym's plates. Warmups are in `warmupSets`.
- `GET /history` returns Liftohistory text: `// note` lines, then `date / program: "…" / dayName: "…" / week / dayInWeek / duration: Ns / exercises: {`, one line per exercise, `}`.

## Upload rules

A finished workout becomes an upload job (`UploadLogic.makeJob`), persisted in a queue of at most four:

1. **Check.** `GET /workout/next` for the job's program, week and day; `UploadLogic.previewMaps` must map every logged set. A mismatch marks the job `program_changed` and sends nothing.
2. **Start.** `POST /workout/start {programId, week, dayInWeek, startTime}` starts that day explicitly, independent of Liftosaur's next-day pointer. `409 workout_already_active` leads to `GET /workout/current`; a live workout with our `startTime` is adopted.
3. **Sets.** `POST /workout/sets {sets: [{entryId, setId, completed: {reps, weight, setTimer?, repsLeft?}, append?}]}`. Watch set *n* maps to planned working set *n*; extra sets go out with `append: true` and a stable six-letter id. Logged warmups map by position onto the start reply's `warmupSets`; extras are listed in the notes. Timed sets send `setTimer`; unilateral sets send `repsLeft = reps`. Exercise names must equal the Liftosaur entry `name`.
4. **Finish.** `POST /workout/finish {startTime, endTime, intervals: [[startTime, endTime]], notes?}`. `intervals` carries the real duration (without it Liftosaur recorded `duration: 2s`). `notes` is sent only for substitutions and extra warmups, because it becomes a `//` line above the history record.

Writes are idempotent by `startTime`, so a job interrupted at any step retries safely after a relaunch.

## Unverified

- Unilateral `repsLeft` and timed-set progression have not been confirmed by a real workout write.
- Assistance weights are negative in NextSet and sent as positive weights.
- Prompted variables (`promptedVars`) are not collected; programs that need them are not supported.
- Liftosaur's acceptance of `intervals` from NextSet awaits the next real upload (see `DEVICE_TESTS.md`).
