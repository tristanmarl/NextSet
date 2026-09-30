# CLAUDE.md

NextSet is a Monkey C Connect IQ strength-training app, primarily for the Garmin Forerunner 965 (`fr965`, minimum API 5.2.0). `AGENTS.md` contains repository rules; this file records build commands and current architecture.

## Commands

Use Connect IQ SDK 9.2.0 with its `bin` directory on `PATH`. This SDK requires `-y` even for simulator and test builds.

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# Production app and simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Unit tests (tests.jungle includes source and tests)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t
```

The runner has previously exited 1 after reporting all tests passed; inspect its PASS/FAIL summary and record the result in `docs/DEVICE_TESTS.md`. A build or simulator result is not a physical-watch result.

## Architecture

Liftosaur is the source of routines and progression. The watch talks directly to `https://www.liftosaur.com/api/v1` through `Communications.makeWebRequest`; there is no NAS HTTP transport.

- `LiftosaurLogic` parses bounded `# Week N` and `## Day` headers from the current Liftoscript program.
- `Catalog` validates `/workout/next` replies and projects each day immediately into compact cached routines, including per-set targets and warmups. Exercise add/replace choices come from the synced program.
- `Model` validates API data and persisted records. Config schema v4 has per-routine storage; older config schemas reset to defaults and need a fresh routine sync.
- `SessionController` owns routine sync and upload callbacks. Only one request is in flight. Sync uses a persisted journal and replaces the active routine snapshot after successful downloads.
- `UploadLogic` converts completed local sets into a job. Upload starts a workout with its explicit program/week/day and start time, maps to the returned set IDs, posts completed sets, then finishes with substitution notes. The persisted queue holds at most four workouts and retries across launches. The queue being full blocks a new workout.
- Upload of a job in state `start` first does a non-mutating `GET /workout/next` and only POSTs `/workout/start` if `UploadLogic.previewMaps` passes; a mismatch stores `lastError=program_changed` (Err.WORKOUT_UPLOAD_MAPPING), not `blocked`. `workout_already_active` triggers `GET /workout/current`, and a workout with our startTime is adopted. Home menu and Settings offer confirmed "Skip this upload" and "Clear upload queue". Sync fetches only the week `/workout/next` reports (program days parsed up to 48, eight per week), restarts on manual sync, and runs its pivot from a 150 ms one-shot timer (`continueAsyncWork`, public).
- `Store` uses two generations for persisted state and journals; preserve staged commits and retry safety when changing upload or sync state. `NextSetApp` owns timers and resumes pending work on launch.
- `StrengthRecorder` still records a Training / Generic FIT activity with per-set lap fields and session summary fields. It is a Garmin activity fallback, not a native planned workout.
- `source/ui/` contains button-operated views and delegates. `Navigator` owns screen transitions. Keep callbacks passed to `method(:callback)` public; private timer or web callbacks can compile but fail at runtime.

Requests need the phone or watch Wi-Fi, so they must remain asynchronous and outside watchdog-sensitive work. A response that does not fit device memory should produce a recoverable error; convert large workout responses immediately and do not retain the raw response. The Liftoscript parser is capped at 16 KiB.

The `liftosaurKey` value comes from the masked Connect IQ app setting. Never hard-code, print, commit, or place it in fixtures. It grants Liftosaur account access. Tests must use sanitized fixtures and fakes; do not make live POST requests unless the user explicitly approves the first real workout write.

Prompt-variable answers are not collected by the watch. Unilateral `repsLeft` and timed-set progression have not been verified by a real Liftosaur workout write. Keep these limitations visible until the approved device check confirms behavior.

## Testing and evidence

Pure logic tests are free functions marked `(:test)` in `tests/*.mc`, accepting `Test.Logger` and returning `Boolean`; `check()` is in `WorkoutTests.mc`. Keep fixtures sanitized under `tests/resources/`. Simulator, physical FR965, and Garmin Connect evidence are recorded separately in `docs/DEVICE_TESTS.md`. Direct Liftosaur sync acceptance is pending until a controlled phone-connected FR965 check is recorded.

The old Garmin catalog and manual Upper/Lower routine editor have been removed. Do not regenerate or restore them. The historical plan is retained with a superseded notice in `docs/GARMIN_STRENGTH_PLAN.md`; the direct architecture decisions are in `docs/PHASE2_HANDOVER.md`.
