# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NextSet: Monkey C Connect IQ strength-training watch app for Garmin Forerunner 965 (`fr965`, min API 5.2.0). `AGENTS.md` holds the canonical repo rules (style, commits, key handling); this file adds commands and architecture. README.md is stale (says no FIT recording, unsigned build) — trust AGENTS.md and `docs/TOOLCHAIN.md`.

## Commands

Needs Connect IQ SDK 9.2.0 `bin` on `PATH`. Always pass `-y ~/.garmin-keys/NextSetDeveloperKey.der` to `monkeyc`; this SDK exits 101 ("The private key was not specified") without it. Never commit/upload either key file.

```sh
mkdir -p bin
# App build + run in simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y ~/.garmin-keys/NextSetDeveloperKey.der
monkeydo bin/NextSet.prg fr965

# Unit tests (tests.jungle adds tests/ to sourcePath)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y ~/.garmin-keys/NextSetDeveloperKey.der
monkeydo bin/NextSet-tests.prg fr965
# Single test
monkeydo bin/NextSet-tests.prg fr965 -t testSeedCatalog
```

`monkeydo` may exit 1 even when all tests pass — read the PASS/FAIL summary, not the exit code. No linter; the compiler's type checking is the check.

Regenerate bundled Garmin exercise catalog (input must match the pinned SHA-256 in the script):

```sh
python3 scripts/generate_garmin_catalog.py /private/tmp/NextSet-Garmin-Exercises.json resources/data/garmin.xml
```

## Architecture

**Layering.** Pure logic modules operate on plain `Dictionary` session/config data and return new copies (or `null` on invalid input) — no storage or UI access, so they are unit-testable:
- `SessionLogic` — set completion, drafts, corrections, undo, timed sets, totals.
- `WorkoutClock` / `RestClock` — workout active/paused time and rest countdown, all computed from `now` epoch seconds passed in (never read the clock inside).
- `LastPerformance` — "last time" cache merge and prefill of new sessions.
- `Model` — schema validation and hard limits (`MAX_*` constants). Every stored record is validated through here on load and before commit.
- `Catalog` — seed exercises/templates from `resources/data/seeds.xml` and Garmin exercise catalog from `resources/data/garmin.xml` (split into `Garmin00..46` JSON resources, loaded one category at a time for memory).

`SessionController` is the single stateful owner: holds the active session, calls pure logic, persists every mutation via `commit()`, owns config/routine editing, history, and the `StrengthRecorder` (thin wrapper over `ActivityRecording` Strength session → FIT). `NextSetApp` owns the controller and all `Timer`s (1 s tick, staged start/finish). UI (`source/ui/`) is views + delegates; `Navigator` module centralizes all screen pushes/switches; menu delegates live in `RoutineEditor.mc` (routine editor, Garmin picker) and `WorkoutMenus.mc` (in-workout actions). `getApp().controller()` is how UI reaches state. Controller config is cached in memory (`readConfig()` returns a shallow copy — copy nested values before mutating). Errors are `Err` codes (`source/ErrorCodes.mc`); branch on `errorCode()`, never on message text.

**Storage (`Store`).** Each domain (`active`, `config`, `routine.<id>`, `last`, `recent`, `history<N>`) is stored as two generations `<domain>.a` / `<domain>.b` in envelopes `{v:1, rev, payload}`. `commitPair` validates then overwrites the older generation; `loadPair` picks the highest valid `rev` and flags corrupt/future-version/recovered records, which the controller surfaces as error messages and uses to block editing. Config `schemaVersion` is 3: `config` holds settings, sequence numbers and the ordered `routineIds`, and each routine is its own `routine.<id>` domain (ids are `Model.validId`: lowercase letters, digits, `-`; one routine stays far below the 32 KB per-value limit). The controller keeps a composite in memory (config plus `routines`) and `writeParts` writes only what changed: new routine before the config that references it, config before edits to an existing routine, removed routine keys last. v1/v2 configs migrate on load (routine keys first, v3 config last, so an interrupted migration is simply redone). A referenced routine that cannot be read is dropped with a "settings damaged" error. Bumping schemas means updating `Model`/`Store` validators and handling older versions.

**Lifecycle is staged across timer callbacks** to stay under the watchdog limit and survive crashes mid-save:
- Start: `requestWorkoutStart` → `prepareWorkoutStart` → `reserveWorkoutStart` → `commitWorkoutStart`, each on a 150 ms timer.
- Finish: session frozen with `finishOutcome`, then `advanceFinalization` runs step by step (FIT save tracked via `fitState`, archive to history slot, merge `last` cache, write tombstone to `active`). `onStart` resumes pending finalization if the app died mid-way; `getInitialView` shows `FinishingWorkoutView` in that case.
- `onStop` saves the recording segment; `onStart` re-attaches it (`ensureRecordingSegment`).

Keep new multi-write operations resumable in the same way. Timer/async callbacks passed via `method(:x)` must be `public` — private ones compile but crash on the physical watch.

## Testing and evidence

Tests are free functions marked `(:test)` in `tests/*.mc` taking `Test.Logger`, returning `Boolean`; `check()` helper in `WorkoutTests.mc`. Tests target pure modules; controller/UI/recording behavior needs simulator or device checks. Record simulator vs physical-watch results separately in `docs/DEVICE_TESTS.md`; Garmin Connect visibility and native per-set rendering are still unverified — don't claim them. Planning docs live in `docs/*_PLAN.md`, `IMPLEMENTATION_PLAN.md`, `UX_REVIEW.md`.
