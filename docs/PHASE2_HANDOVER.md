# Phase 2 handover — watch talks to Liftosaur directly

Audience: the next implementing agent (Codex). Written 2026-09-30 at the end of Phase 1. Read first: `AGENTS.md`, `CLAUDE.md`, `docs/LIFTOSAUR_PLAN.md` (esp. "Schema (observed)" and "Implemented matching rules" — the Python implementation in `tools/connect-sets/liftosaur.py` is the reference for the watch logic), `docs/DEVICE_TESTS.md`.

## Architecture decision (user, 2026-09-30)

NextSet on the FR965 calls the Liftosaur REST API itself over the phone connection (`Communications.makeWebRequest`). No NAS server, no Tailscale.

```
Liftosaur ──GET /workout/next──► NextSet (routine for a day)
    ▲                               │ workout (FIT still recorded → Connect: HR, duration)
    └── POST start / sets / finish ─┘ (progression runs in Liftosaur)
```

History and progression live in Liftosaur; Claude reads them through the Liftosaur connector. The NAS job from Phase 1 (`tools/connect-sets`, FIT via Garmin Connect → archive, optional Liftosaur write-back) stays as an optional backup archive; its Liftosaur write-back must stay OFF (`LIFTOSAUR_SYNC=0`) once the watch writes, otherwise workouts could be written twice (Liftosaur rejects a duplicate `startTime` with 409, but do not rely on it).

## Where things stand

- Branch `liftosaur-sync` (version 0.2.7, pushed; not merged to `main`). `main` has 0.2.6: compact Garmin catalog, sport Training / sub-sport GENERIC recording, START-twice set flow, lap developer fields (`exercise, set, reps, weight_kg, duration_s, active_s, garmin_category, garmin_code, void`), correction/undo laps.
- Private seeds already use the Liftosaur exercise names (Seated Row, Chest Press, …; ids unchanged).
- No real Liftosaur write has happened yet (only GETs and dry runs).
- Secrets: the user's Liftosaur key is in `tools/connect-sets/.env` (gitignored). Never print, copy into the repo, or commit it. The user should rotate it after setup.

## Binding user decisions

1. Liftosaur is the single source of routines, exercises and progression. Exercise names on the watch = Liftosaur entry `name`. No mapping.
2. Remove everything Garmin-exercise related: `resources/data/garmin.xml`, `private/resources/data/garmin.xml`, `scripts/generate_garmin_catalog.py`, the Garmin picker and "Category only", `garminCategory`/`garminCode` in seeds/routines/sessions/Model/Store, lap fields `garmin_category`/`garmin_code`. Breaking stored-data changes are fine (beta).
3. Keep the FIT recording (Training / GENERIC) so Connect gets an activity with duration, HR, calories, training load. Sets/reps in Connect are not needed.
4. Build the real thing, no throwaway test apps.
5. Work on a feature branch; merge to `main` only after the user's device check. Unit tests need `monkeydo ... -t`. Timer/web-request callbacks passed via `method(:x)` must be `public` (private ones crash on the watch).

## Liftosaur API facts (see LIFTOSAUR_PLAN.md for the full observed schema)

- Base `https://www.liftosaur.com/api/v1`, header `Authorization: Bearer lftsk_…`. Writes to `/workout/*` also need `X-Liftosaur-Device-Id` (generate once, persist) and `X-Liftosaur-Client: nextset-watch/<version>`.
- `GET /programs/current` → `{id, name, text}` (Liftoscript; days are `## <Name>` under `# Week N`). `GET /workout/next?programId&week&dayInWeek` → `{workout:{programId, dayName, dayData:{week,dayInWeek}, entries:[{entryId, name, equipment, superset, sets:[{reps, weight:"55kg", isUnilateral, timer, setTimer}], warmupSets:[…]}]}}`. ~15–17 KB JSON per day for the user's program (descriptions/notes ~2.5 KB of it). `setId`s and `startTime` are regenerated on every GET.
- `POST /workout/start {programId, week, dayInWeek, startTime(ms)}` returns the workout with the real `setId`s; `POST /workout/sets {sets:[{entryId, setId, completed:{reps, weight:"55kg", setTimer?, repsLeft?}, append?}]}`; `POST /workout/finish {startTime, endTime, notes}` → progression, history, next-day pointer; returns `nextDay`. Errors `{error:{code}}`: 409 `workout_already_active`, 409 `workout_start_time_taken`, 422 `program_error`, 401/403.
- The live API cannot add/remove/reorder exercises; extra sets via `append:true` with a generated 6-lowercase-letter id.
- Matching rules proven in Python: day by name; watch set i → planned working set i (warmups never filled); planned sets without a watch set stay incomplete; weight `"<abs kg>kg"` (assistance positive); timed set → `completed.setTimer` + planned `reps`; unilateral → `repsLeft = reps` (unverified); skip the whole write if no watch set matches.

## Scope

### 1. Settings and identity
- Connect IQ app properties (edited in the phone app): `liftosaurKey` (string). Not in the package, not logged, never shown in full on the watch.
- Device id generated once and stored; client header with the app version.

### 2. Routine sync
- "Sync routines" action (Home and Settings): `GET /programs/current` (parse day names/week/dayInWeek from the Liftoscript headers — only headers, not the full DSL), then `GET /workout/next?programId&week&dayInWeek` per day, sequentially (one request in flight). Also call plain `GET /workout/next` once to learn the next day.
- Convert each response immediately into the compact NextSet routine and drop the raw dictionary (memory). Ignore `description`, `notes`, `imageUrl`, `plates`, `promptedVars`. If a response exceeds memory (`NETWORK_RESPONSE_OUT_OF_MEMORY` / -403), show a clear error; do not crash. Consider `:responseType` JSON and measure peak memory in the simulator with the user's program (fixture in `tools/connect-sets/data/liftosaur-discovery/`, gitignored — copy a sanitized version into `tests/`).
- Routine model v4 (config `schemaVersion` bump; older stored configs reset to defaults): per exercise: name, equipment, loadType (timed if `setTimer`, bodyweight if all weights 0, else weight), unilateral, superset label, restSec (`timer`), per-set targets (reps, load100, durationSec), warmups (display only), Liftosaur `entryId`; per routine: programId, week, dayInWeek, name. Home marks the next day. Store via the existing two-generation `Store`, validated by `Model`, written in staged, resumable steps (watchdog).
- Prefill of a set = the plan target for that set; "last time" stays visible.
- Add/replace exercise during a workout: pick from exercises of the synced program (replaces the Garmin picker). Substituted exercises are not in the Liftosaur day; they are listed in the finish notes, not logged as sets.

### 3. Write-back (upload queue)
- After a workout is finalized, persist an upload record (bounded queue, e.g. max 8; small JSON: routine day ids, start/end epoch, sets per exercise with set index, reps, load, duration, corrections applied, undone sets removed). Workouts from routines without Liftosaur ids are not queued.
- Process the queue when the phone is reachable (after finish, on app start, after sync): `start` (with the real start time) → map sets by exercise name + set index to the `setId`s from the start response → `sets` (one call) → `finish`. Chain callbacks; one request at a time; persist progress per step so a crash or app exit resumes (a repeated `start` with the same startTime is the retry path; handle `workout_start_time_taken` as already done, `workout_already_active` as blocked → show a notice, never discard the app workout).
- Show queue state on Home (e.g. "1 workout not synced") and the last error.

### 4. Remove the Garmin catalog and codes
- As in decision 2. Update tests, docs (README, CLAUDE.md, GARMIN_STRENGTH_PLAN.md note), manifest permissions (`Communications` added, remove unused ones).

### 5. NAS job adjustments (small)
- `tools/connect-sets`: keep archive; default `LIFTOSAUR_SYNC=0`; README states the watch is the Liftosaur writer. No NAS HTTP server.

## Tests

- Unit (pure modules): Liftoscript day-header parsing; conversion from a sanitized `/workout/next` fixture to a v4 routine; v4 Model validation and v3 → reset; upload-queue state machine (enqueue, step progress, retry, 409 handling, bound); set-to-setId mapping incl. extra sets, missing sets, timed, unilateral, assistance.
- Simulator: sync with the full program; memory peak; queue processing with simulated failures.
- Record simulator vs device results separately in `docs/DEVICE_TESTS.md`.

## Acceptance (user, physical FR965)

1. Enter the key in the phone app, sync routines: Upper/Lower appear with plan weights; Home shows the next day.
2. Real workout ≥ 5 min: finishes, uploads; Liftosaur history shows it; next weights reflect progression; Connect shows the activity with HR/duration.
3. Airplane mode at finish: uploads later exactly once.
4. App exit mid-upload: resumes without duplicates.

## Known risks

- Response size / memory on bigger programs (mitigation: per-day requests, immediate conversion).
- Key stored in Connect IQ settings (also on Garmin's servers) with full Liftosaur access — accepted by the user for the beta.
- Unilateral `repsLeft`, assistance sign, skipped sets' effect on progression — verify on the first real write and adjust.
- `makeWebRequest` needs the phone connection (or Wi-Fi); requests can take seconds — never block the UI, never call from a watchdog-sensitive path.
