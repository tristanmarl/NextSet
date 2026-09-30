# NextSet stability audit and implementation plan (2026-09-29, second pass)

## Device evidence

Pulled from the FR965 (firmware 29.05, Connect IQ 6.0.2) over MTP on 2026-09-29.

| File | Content | Status |
| --- | --- | --- |
| `GARMIN/APPS/LOGS/CIQ_LOG.YML` | 3 × `Watchdog Tripped Error - Code Executed Too Long`, 14:26:32, 14:26:51, 14:27:36 UTC | **New, unfixed** |
| `GARMIN/APPS/LOGS/CIQ_LOG.BAK` | `Invalid Value` at `NextSetApp.retryPendingFinalization` (13:26 UTC) | Fixed in `10fe4ed` (public timer callback) |
| `GARMIN/DEBUG/err_log.bak` | Firmware 28.05 Bluetooth watchdog resets, Aug 23–27 | Not NextSet; predates app build |

Stack lines match `HEAD` (`10fe4ed`) exactly. All three new crashes end in the same frames:

```
SessionLogic.copyDictionary        SessionLogic.mc:8
Catalog.exerciseForEntry           Catalog.mc:141
Catalog.validRoutine               Catalog.mc:177
Store.validConfig                  Store.mc:50
Store.validPayload                 Store.mc:97
```

Entry points:

1. `DeleteRoutineDelegate.onSelect` (`Navigator.mc:873`) → `deleteRoutine` → `saveRoutines` → `saveConfig` → `Store.commitPair` → validation.
2. and 3. `RoutineSetupDelegate.onSelect` (`Navigator.mc:902`) → `routineEntryOptions` → `templateExercise` → `templateEntry` → `readConfig` → `Store.loadPair` → `readGeneration` → validation.

The workout-start and finish watchdogs were fixed earlier. The routine editor and settings paths still run config validation many times in each input callback, and custom routines now make that config large enough to hit the limit.

## Root cause: repeated full-config validation per callback

A single "full config validation" runs `Catalog.validRoutine` on every routine. For each entry, that does a linear scan of the seed exercises (`Catalog.exercise`), then `copyDictionary`, `Model.validExercise`, and field checks. The largest possible config has 8 routines × 12 entries = 96 entries.

The config is not cached. Every `readConfig()` does a fresh `Storage.getValue` of **both** generations. It validates each one, then runs `validRoutineList` a third time. `commitPair` validates the new payload, then reads and validates both existing generations only to learn their `rev`.

| Callback | `readConfig` calls | Full validations |
| --- | --- | --- |
| Open routine entry (`routineEntryOptions`) | 3 (`templateEntry`, `templateExercise` → `templateEntry`, `routineTemplates`) | 9 |
| Delete routine (`deleteRoutine` + `routineList`) | 2 + commit | 3 + 1 (`saveRoutines`) + 3 (commit) + 3 = 10 |
| Every redraw of `MappingDetailView.onUpdate` | 2 | 6 |
| Number editor open for template `startingLoad100` | 3 (+ `numericConfigValue` → `defaultRestSec`) | 9+ |
| Any routine edit (add/replace/move/remove/value) | 1 + commit + list refresh | 7–10 |

The same Store pattern applies to the `active` domain. Every set completion, draft edit, rest action and 30-second checkpoint calls `commitPair("active")`. That runs `Model.validStoredSession` three times (new payload plus both generations), with up to 60 slots each, and does two full `Storage.getValue` reads before the write. It has not crashed yet, but it is the next watchdog candidate for long sessions.

## Audit findings

| Pri | Area | Finding | Consequence |
| --- | --- | --- | --- |
| P0 | Performance | Config is re-read and re-validated 3× per `readConfig()` and 3× per `commitPair("config")`. `readConfig()` has 17 uncached call sites in the controller. | **Current crashes** in routine delete and entry options. Scales with custom routines. |
| P0 | Performance | `commitPair` reads and validates both existing generations only to get `rev`. | 3× validation and 2 extra full reads per write, in every domain, on every set. |
| P1 | Performance | `MappingDetailView.onUpdate` and `NumberEditView.loadValue` call config readers on draw or open. | Redraw-driven watchdog risk. Slow UI. |
| P1 | Performance | `Catalog.exerciseForEntry` copies the whole seed dict and scans seeds linearly for every entry, only to validate. | Constant-factor waste inside the hot loop. |
| P1 | Performance | Finalization `historySlot` loads 4 history pairs (8 reads, 8 `validStoredSession`). `readLastCache` can load all 4 again. Then `commitPair` re-validates. | Heavy finish stages. Each is its own callback, but they are unmeasured at 60 sets. |
| P1 | Resilience | `finish("aborted")` discards the FIT recorder **before** the durable commit. If `commit` fails, the workout stays active with its activity already gone. | Lost recording on a storage failure. |
| P1 | Resilience | `pauseWorkout` and `resumeWorkout` do 2–3 durable writes plus recorder calls in one input callback. | A partial failure leaves `fitState` and the recorder out of sync. Also adds watchdog load. |
| P1 | Process | The signing key `/private/tmp/NextSetDeveloperKey.der` and its PEM are **gone** (tmp was cleared). No backup was found under `~`. | Cannot produce a build signed with the installed app's key. A new key needs a reinstall on the watch, and `AGENTS.md`/`CLAUDE.md` point at a missing path. |
| P2 | Resilience | `onStop` saves a FIT segment on every app exit. `onStart` then starts a new recording. | One workout can become several Garmin activities. Documented in `DEVICE_TESTS.md` as pending, not yet decided. |
| P2 | Quality | Error state is a free-form `_error` string. UI branches on exact text (`HomeView.getHomeNotice` has 19 `sameString` comparisons; `finishWorkoutStart` also matches text). | Changing a message breaks behavior silently. |
| P2 | Quality | Two copies of `copyDictionary` (`SessionLogic` and `LastPerformance`). `Navigator.mc` is 1,725 lines. `HomeView` lives in `NextSetApp.mc`. | Harder to review. Low risk. |
| P2 | Storage | Worst-case `active`/`history` value size against the 32 KB per-key limit is still unmeasured (carried over from the previous plan). | A save can fail on large routines. |
| P3 | Tests | 21/21 simulator tests pass (re-run 2026-09-29). None covers controller or Store call counts, or config size and time. | The watchdog regression was not catchable by the suite. |

## Implementation plan

Order is by crash impact. Steps 1–3 fix the reported crashes and should ship together. Keep changes inside `Store`, `SessionController`, and the three call sites named below. Do not change stored schemas; no migration is needed.

### 1. Cache the validated config in `SessionController` (fixes crashes 2 and 3; most of 1)

- Add `private var _config as Dictionary? = null`. `readConfig()` returns `_config` when set. Otherwise it runs the existing load, migrate and validate path once and stores the result.
- `saveConfig()` and the other successful config commits (`reserveWorkoutStart`, and migration inside `readConfig`) set `_config = next` after `commitPair` succeeds. A failed commit leaves the cache unchanged.
- Callers that mutate must keep copying first (`copyRoutines`, `copyDictionary`). Audit them for in-place mutation of the cached dict: `readConfig` currently returns a copy, and some callers may rely on that. Where in doubt, return `SessionLogic.copyDictionary(_config)`. That is a shallow copy and cheap.
- Result: `routineEntryOptions` drops from 9 full validations to 0 after the first read.

### 2. Stop validating on the Store write path

- Add `Store.readRevision(domain, gen)`. It returns `record["rev"]` when the envelope is `{v:1, rev:Number, payload:Dictionary}`, and flags `_futureRecord` on `v > 1`, without calling `validPayload`. Use it in `commitPair` in place of `readGeneration`.
- Keep `validPayload` on the payload being written (one validation), or skip it when the caller already validated. `saveRoutines` already runs `validRoutineList`; pass a flag or split `commitPair` into validated and pre-validated variants. Pick the smaller diff.
- `loadPair` keeps full validation. It runs only on a cold read now that config and session are cached in memory.
- Result: every `commitPair` goes from 3 validations + 2 full reads to at most 1 validation + 2 envelope reads. This is the same payoff for `active` writes on every set.

### 3. Remove config reads from render paths

- `MappingDetailView`: fetch `entry` and `exercise` once in `initialize` (or `onShow`), not in `onUpdate`.
- `routineEntryOptions`: use a single `routineTemplates()` result for the entry, its definition, and its index. Drop the separate `templateEntry` and `templateExercise` calls.
- `NumberEditView.loadValue`: one `numericConfigValue` call. Pass the exercise ID in instead of calling `templateEntry` again.

### 4. Make `validRoutine` cheap

- In `Catalog.validRoutine`, validate the entry fields directly instead of building a merged definition with `exerciseForEntry`, which runs `copyDictionary` for each entry. For seeded IDs, look up the seed once through a lazily built `id → index` dictionary. That replaces the linear `exercise()` scan, which also speeds up `exercise()` elsewhere.

### 5. Resilience fixes on workout state transitions

- `finish("aborted")`: commit the `finalizing` state with `fitState = "discarding"` first, then discard in the finalization stage, the same pattern as `saving`. Add `"discarding"` to `Model.validStoredSession`'s `fitState` list and handle it in `advanceFinalization`.
- `pauseWorkout`: fold `fitState = "paused"` into the first commit when `_recorder.hasSession()`. If `_recorder.pause()` then fails, commit the correction. That makes one write on the success path.
- `resumeWorkout`: the same, for `fitState = "recording"` before `ensureRecordingSegment`.

### 6. Finalization stage cost

- `historySlot`: read only the envelope `rev`, `id` and `sessionSeq` for slot choice through a lightweight Store read (step 2's envelope reader plus two payload fields). Do not load and validate 4 full sessions.
- `readLastCache` rebuild: keep it, but it only runs when the `last` cache is missing.

### 7. Signing key — resolved 2026-09-29

A new 4096-bit key was generated at `~/.garmin-keys/NextSetDeveloperKey.der` (PEM beside it, mode 600), and `AGENTS.md` and `CLAUDE.md` now point there. The first watch install of a build signed with this key needs NextSet removed and reinstalled. Original options, kept for the record:

- The user must decide one of two options:
  - (a) Restore the original key from a backup, if one exists.
  - (b) Generate a new durable key outside `/private/tmp`, reinstall NextSet on the watch, and accept that the app's `Storage` (routines, history) may reset on the watch.
- Then update the key path in `AGENTS.md`, `CLAUDE.md` and `docs/TOOLCHAIN.md`.

### 8. Follow-up quality (after the device gate passes)

- Replace `_error` strings with a small set of constants, or an error code plus message. Switch `getHomeNotice` and `finishWorkoutStart` to the codes.
- Delete the duplicate `LastPerformance.copyDictionary` and call `SessionLogic.copyDictionary`.
- Move `HomeView` into `source/ui/`. Split `Navigator.mc` along its menu groups (routine editor, workout actions) only if it is being edited anyway.
- Decide the FIT segment policy on app exit (P2 above) with the user.

## Tests to add

- `testConfigCacheSurvivesEdit` (in `WorkoutTests.mc`): create a controller on a fresh `Store`, add a routine and an exercise, and read `templateEntry` twice. Assert that the second read reflects the edit. This protects cache invalidation.
- `testCommitPairIgnoresExistingPayloadValidity`: write a generation whose payload is invalid but whose envelope is valid, then `commitPair` a valid payload. Assert that it targets the older generation and bumps `rev`. This protects step 2 semantics.
- `testValidRoutineMaxConfig`: build 8 routines × 12 entries and assert that `validRoutine` holds. Log `System.getTimer()` deltas for `readConfig` and `commitPair("config")` as a simulator timing baseline. This is not a pass/fail gate, because simulator speed ≠ device speed.

## Device gate (record in `docs/DEVICE_TESTS.md`)

On the FR965 with a new signed build:

1. Create 8 routines with 12 entries each.
2. Open each routine entry, view mapping details, edit values, move, replace, remove and delete a routine. Expect no CIQ log entry.
3. Start a 60-set routine, log all sets, pause, resume and finish. Also abort a second session.
4. Pull `CIQ_LOG.YML` and confirm that no new entries appeared.
5. If anything comes close to the limit, add a diagnostic build with `System.getTimer()` around `readConfig`, `commitPair` and each finalization stage, logged through an app-named `.TXT` in `GARMIN/APPS/LOGS`.

## Reading watch logs without OpenMTP's UI

OpenMTP bundles the `kalam` MTP library (`/Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib`). It can be driven from Python `ctypes` through its exported `Initialize`, `FetchStorages`, `Walk`, `DownloadFiles` and `Dispose` functions, which take JSON strings and C callbacks. OpenMTP must be quit first, because it holds the USB session. The storage ID seen on this watch is `131073`. Log paths: `/GARMIN/APPS/LOGS/CIQ_LOG.YML`, `/GARMIN/APPS/LOGS/CIQ_LOG.BAK`, `/GARMIN/DEBUG/err_log.*`.

## Implementation (steps 1-3), 2026-09-29

- `SessionController`: `readConfig()` now caches the validated config (`_config`) and returns a shallow copy; `saveConfig` and `reserveWorkoutStart` refresh the cache after a successful commit, failed commits leave it alone.
- `Store.commitPair`: uses a new envelope-only `readRevision` instead of `readGeneration`; one `validPayload` remains (the payload being written). `loadPair` still fully validates.
- `Navigator.routineEntryOptions` uses one `routineTemplates()` result; `MappingDetailView` resolves entry/exercise once in `initialize`; `NumberEditView.loadValue` no longer calls `templateEntry` for the exercise ID.
- Tests added: `testConfigCacheReflectsEdits`, `testCommitPairEnvelopeOnlyRevision`.
- Build (`monkeyc` fr965, app and unit-test) succeeded; simulator run: 23/23 passed.
- Device verification pending: routine delete and routine entry open on the FR965 have not been re-run.

## Implementation (steps 4-6), 2026-09-29

- Step 4: `Catalog.validRoutine` validates a small merged field set directly (same merge rules as `exerciseForEntry`) instead of copying the seed per entry; `Catalog.exercise` uses a lazily built id-to-index dictionary.
- Step 5: `finish("aborted")` commits `fitState = "discarding"` first; `advanceFinalization` performs the discard (no recorder session after a restart is treated as discarded) and commits `discarded` or `discard_failed`. `"discarding"` added to `Model.validStoredSession`. `pauseWorkout` folds `fitState = "paused"` into the single commit and commits a correction to `recording` if `_recorder.pause()` fails. `resumeWorkout` is unchanged: `ensureRecordingSegment` already owns that state change.
- Step 6: `Store.peekSession` reads history envelopes only (id and sessionSeq); `historySlot` uses it. A record with a future version is still skipped, and the already-written check is unchanged.
- Step 8 (partial): removed `LastPerformance.copyDictionary` in favour of `SessionLogic.copyDictionary`.
- Tests added: max 8x12 routine validation plus rejections, `discarding` validation, `peekSession`. Result: build successful (app and tests), 26/26 pass. Device verification is pending (see `docs/DEVICE_TESTS.md`).

## Implementation (step 8), 2026-09-29

- Error codes: new `source/ErrorCodes.mc` (`module Err`: constants plus a `MESSAGES` table and `Err.message`). `SessionController` stores `_errorCode`, `errorMessage()` returns the same text as before and `errorCode()` is new. `HomeView.getHomeNotice`, `finishWorkoutStart` and `NumberEditView` compare codes; no UI string comparisons remain.
- Structure (verbatim class moves): `HomeView`, `StartingWorkoutView`, `FinishingWorkoutView`, `FinishingWorkoutDelegate` to `source/ui/HomeView.mc`; routine-editor, Garmin-picker and mapping classes to `source/ui/RoutineEditor.mc`; workout action/exercise/undo/correction menus to `source/ui/WorkoutMenus.mc`. `module Navigator` and the confirm/feedback/home classes stay in `Navigator.mc`.
- Exit guard: root BACK during a workout already opens the Actions menu (no direct exit), and its exit item goes through `ExitConfirmView`. No new routing was needed; the confirm text now says the workout continues next time and the Garmin activity so far is saved separately. FIT behaviour (`onStop` saves the segment) is unchanged.
- Results: app and test builds successful, 26/26 tests pass. Device verification pending (see `docs/DEVICE_TESTS.md`).

## Storage headroom (2026-09-29)

The simulator does not enforce the 32 KB per-value limit (`testStorageValueLimitProbe` stored about 1 MB in one value), so `testWorstCaseStorageCommits` builds worst-case payloads through the real code path and compares a rough serialized-size estimate (type and length headers included) with 32,768 bytes. Estimates:

| Domain | Estimate |
| --- | --- |
| `active` (finalizing, 60 sets all completed, prefilled from a full cache) | about 24.4 KB |
| `history0` (archived session) | about 10.2 KB |
| `last` (cache) | about 3.2 KB |
| `routine.<id>`, 12 entries with 64-byte names, 160-byte notes, Garmin strings at maximum length | about 7.9 KB |
| `config` v3 with 8 maximum-length routine ids | about 0.5 KB |

Before this change one `config` holding 8 x 12 entries was estimated at about 38 KB (typical strings) to 63.5 KB (maximum strings), over the limit. Config `schemaVersion` 3 fixes that by storing each routine in its own `routine.<id>` domain. Migration from v1/v2 runs on load: routine keys first, v3 config last, so an interrupted run is redone. The total storage available to the app has not been verified (8 routines at worst case with two generations each is about 127 KB), and typical use is far smaller.
