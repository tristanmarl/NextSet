# CLAUDE.md

NextSet is a Monkey C Connect IQ strength-training app for five-button Garmin watches on Connect IQ 5+ (53 products in `manifest.xml`, minimum API 5.0.0), developed and device-tested on the Forerunner 965 (`fr965`). Guard any API that some targets lack with `has` (MIP watches such as the fr255 family have no `Graphics.getVectorFont`); `scripts/pack-devices.sh` packs the device files CI needs. All jungles use `resources/` (the former `private/resources` copy is gone). Liftosaur API usage is in `docs/LIFTOSAUR_API.md`; contributor and release steps are in `CONTRIBUTING.md`. `AGENTS.md` contains repository rules; this file records build commands and current architecture.

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

# Or: build + run + summary check with a timeout; exits 0 only on "PASSED (passed=N, failed=0, errors=0)"
scripts/test.sh
```

The runner has previously exited 1 after reporting all tests passed; inspect its PASS/FAIL summary and record the result in `docs/DEVICE_TESTS.md`. A build or simulator result is not a physical-watch result.

## Architecture

Liftosaur is the source of routines and progression. The watch talks directly to `https://www.liftosaur.com/api/v1` through `Communications.makeWebRequest`; there is no NAS HTTP transport.

- `LiftosaurLogic` parses bounded `# Week N` and `## Day` headers from the current Liftoscript program.
- `Catalog` validates `/workout/next` replies and projects each day immediately into compact cached routines, including per-set targets and warmups. Exercise add/replace choices come from the synced program.
- `Model` validates API data and persisted records. Config schema v4 has per-routine storage; older config schemas reset to defaults and need a fresh routine sync.
- `SessionController` owns the workout session and config, and owns a `LiftosaurSync` (`source/LiftosaurSync.mc`) that holds routine sync, the upload queue, key storage/test and the API request plumbing. The controller forwards the UI calls and gives the sync class a narrow host surface (`errorCode`/`setErrorCode`, `hasActiveSession`, `hasPendingFinalization`, `syncConfig`, `routineIds`, `settleRoutineSync`, `applyRoutineSync`). Only one request is in flight. Sync uses a persisted journal and replaces the active routine snapshot after successful downloads. Stored/wire strings (job states, journal phases, request purposes, error codes) are constants in `module Liftosaur` (`source/Liftosaur.mc`); the values are persisted, never change them.
- `UploadLogic` converts completed local sets into a job. Upload starts a workout with its explicit program/week/day and start time, maps to the returned set IDs, posts completed sets, then finishes with `intervals: [[startTime, endTime]]` (without it Liftosaur recorded `duration: 2s`) and `notes` only for substitutions or extra warmups. Notes become a `//` line above the Liftosaur history record; liftosaur2garmin up to `dda3034` fails on any such line, so do not add routine notes. The persisted queue holds at most four workouts and retries across launches. The queue being full blocks a new workout.
- Upload of a job in state `start` first does a non-mutating `GET /workout/next` and only POSTs `/workout/start` if `UploadLogic.previewMaps` passes; a mismatch stores `lastError=program_changed` (Err.WORKOUT_UPLOAD_MAPPING), not `blocked`. `workout_already_active` triggers `GET /workout/current`, and a workout with our startTime is adopted. Home menu and Settings offer confirmed "Skip this upload" and "Clear upload queue". Sync fetches only the week `/workout/next` reports (program days parsed up to 48, eight per week), restarts on manual sync, and runs its pivot from a 150 ms one-shot timer (`continueAsyncWork`, public).
- `Err` (`source/ErrorCodes.mc`) holds every error code with its long text (`message`) and Home notice (`shortMessage`) in two switch functions. Add a code in all places there, not in the UI.
- `Store` uses two generations for persisted state and journals and validates each unchanged generation once per launch (cache dropped on commit/delete); preserve staged commits and retry safety when changing upload or sync state. `active` commits reuse the revisions from the previous commit instead of reading both stored sessions back (dropped on delete or a failed write). The 30 s workout clock checkpoint writes only the small `ckpt` key (`[sessionId, time]`); recovery uses it when it is newer than the session's own `lastCheckpointAt` and not in the future.
- Rest expiry and the timed-set target alert change the session in memory and are saved ~2 s later by the draft timer, so no storage write runs in the same tick as the 1 s vibration and redraw (a firmware crash on 2026-10-29 came in that second; see `docs/DEVICE_TESTS.md`). Keep heavy work (commits, FIT laps, requests) out of the alert tick. `NextSetApp` owns timers and resumes pending work on launch.
- Warmups: each session exercise has optional `warmupSlots` (max 4, from the routine's warmups) addressed as slot `Model.WARMUP_BASE + i` (100+); use `Model.slotAt` and `SessionLogic.activeSlot` (warmups first, then working sets) rather than indexing `slots`. `nextSlot`, totals, prefill and superset rotation stay working-sets-only. Warmup FIT laps use lap field `set` = 0. Upload rows `warmups` map by position onto the start reply's `warmupSets`; extras go to `extraWarmups` (finish notes).
- Plain (weight/bodyweight) sets and warmups log in one START press (`completeDraft`); there is no set clock, and a `setRun` saved by 0.3.1 is ignored and dropped on load. FIT `active_s` is the measured duration for timed sets and 0 otherwise. A cancelled workout runs only the finalizing commit, the FIT discard and the tombstone commit (no history, last-performance or upload steps).
- UI hints are icons drawn with Dc primitives (`source/ui/Icons.mc`; button angles come from the fr965 simulator layout and live in one place). UP/DOWN draft edits go through `SessionController.updateDraft` into memory only; `flushDraft` (2 s timer, app stop) persists them and any other commit includes them. `commit` records the longest save time for Settings → Diagnostics. After a cancelled workout `Navigator.finalized` returns to Home with a notice instead of exiting.
- `StrengthRecorder` still records a Training / Generic FIT activity with per-set lap fields and session summary fields. The exercise lap field is 64 bytes; `fitText` cuts names at whole characters to fit. It is a Garmin activity fallback, not a native planned workout.
- Set screen input: keys act on press (0.3.4 behaviour). On the FR965 only hold UP (menu) reaches an app; hold START, DOWN and LIGHT are firmware shortcuts (hold DOWN opens music controls), so do not use holds. The reps/load switch is the first exercise menu item ("Change load" / "Change reps"), toggling `ExerciseView` in place (yellow highlight); from the Overview it opens `SetEditView`. `RapidPress` (`source/ui/SetEditView.mc`) speeds up fast same-direction load presses (x2 from the 4th, x4 from the 8th). `SetEditView` edits load and reps of the next or a logged set together (MENU switches the field); `NumberEditView` remains for timed durations and settings. Edit last set and Delete set N follow in the menu.
- `source/ui/` contains button-operated views and delegates. `Navigator` owns screen transitions. Keep callbacks passed to `method(:callback)` public; private timer or web callbacks can compile but fail at runtime.

Requests need the phone or watch Wi-Fi, so they must remain asynchronous and outside watchdog-sensitive work. A response that does not fit device memory should produce a recoverable error; convert large workout responses immediately and do not retain the raw response. The Liftoscript parser is capped at 16 KiB.

The Liftosaur key is entered on the watch (Settings → Liftosaur key, `TextPicker` via `NextSetApp.afterKeyEntry`) and stored only in watch app storage (`Store` domain `apikey`); there is no Connect IQ app setting. It is shown only masked, and Settings has Test key (`key_test`, read-only `GET /programs/current`) and Clear key. Never hard-code, print, commit, or place it in fixtures. It grants Liftosaur account access. Tests must use sanitized fixtures and fakes; do not make live POST requests unless the user explicitly approves the first real workout write.

Prompt-variable answers are not collected by the watch. Unilateral `repsLeft` and timed-set progression have not been verified by a real Liftosaur workout write. Keep these limitations visible until the approved device check confirms behavior.

## Testing and evidence

Keep long boolean chains in tests split into named variables and sequential `check` calls: a single huge `&&` expression of mixed-type calls made the compiler run out of memory (`OutOfMemoryError` in the typechecker). Pure logic tests are free functions marked `(:test)` in `tests/*.mc`, accepting `Test.Logger` and returning `Boolean`; `check()` is in `WorkoutTests.mc`. Keep fixtures sanitized under `tests/resources/`. Simulator, physical FR965, and Garmin Connect evidence are recorded separately in `docs/DEVICE_TESTS.md`. Device status (what is confirmed and what is pending) is in `docs/DEVICE_TESTS.md`.

The old Garmin catalog and manual Upper/Lower routine editor have been removed. Do not regenerate or restore them; superseded plans are only in git history.
