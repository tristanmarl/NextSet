# NextSet quality, resilience, and performance plan

## Evidence and diagnosis

On the FR965 (firmware 29.05, Connect IQ 6.0.2), the latest `GARMIN/Apps/LOGS/CIQ_LOG.BAK` contains two workout-start watchdog crashes at 2026-09-29 11:54:43 and 11:55:09 UTC. Both stacks end in recursive `Store.equal()` from `Store.commitPair("active", ...)`, called by `SessionController.startWorkout`. The preceding three crashes at 11:44–11:45 UTC ended earlier in session creation. The previous lookup and catalog changes let execution reach the active-session save, but the workout still cannot start on the watch. The stack identifies where the time limit was reached; it does not prove that only that one function consumed the time budget.

The current START callback reads and validates saved routines more than once, loads last-performance data, builds the full session, writes the next session sequence, starts Garmin recording, writes the full active session, and opens the overview. Every `Store.commitPair` currently reads both generations multiple times, writes one, then recursively compares the entire read-back payload; on a failed comparison it reads and compares again. The same shared save path is used for every set, timed checkpoint, recovery, history, and finish. `HomeView.onUpdate` also reloads and revalidates config while drawing, including a second read for set totals.

Garmin documents a watchdog for functions that execute too long, `Application.Storage.setValue()` throwing on storage exhaustion, and a 32 KB limit per stored value. Device timing and memory headroom have not been measured. Sources: [watchdog errors](https://developer.garmin.com/connect-iq/monkey-c/exceptions-and-errors/), [Storage API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html), [timer API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Timer/Timer.html), [system timer and memory API](https://developer.garmin.com/connect-iq/api-docs/Toybox/System.html).

| Priority | Finding | Consequence |
| --- | --- | --- |
| P0 | `Store.commitPair` recursively compares a full saved workout after every write; the new watch log lands in that comparison. | START crashes now; set edits, checkpoints, and finish use the same path. |
| P0 | START performs preparation, two durable writes, Garmin recording start, and navigation in one input callback. | Removing one bottleneck may only move the timeout to the next operation. |
| P1 | Home drawing and START repeatedly call `readConfig()`, which reads storage and validates all routines. | Slow input and redraws that scale with custom routines. |
| P1 | `Store.readGeneration` treats a read exception as an absent record; `loadPair` checks only the envelope shape. | A damaged saved value can be mistaken for missing data or a malformed active payload can reach casts in recovery. |
| P1 | `readConfig` ignores the result of its v1-to-v2 migration write. | A migration can appear successful in memory yet repeat after restart. |
| P2 | Active and history snapshots can reach 60 sets, while one Storage value is limited to 32 KB. | Large custom routines may fail to save; actual headroom is unknown. |
| P2 | The existing simulator suite recorded 17/18 passing after routine-editor changes; `testNumericTemplateOverrides` still fails. | Regression evidence is incomplete until the v2 override expectation is reconciled. |

## Implementation order for Luna 6 Max

### 1. Remove the shared save bottleneck and keep crash recovery

- Refactor `Store.commitPair` to inspect the two generation envelopes once, reject future records and a pair with no usable generation but corrupt data, choose the older/invalid generation, and call `Storage.setValue` once. Remove recursive full-payload equality and the fallback full read/compare. A successful native write is the commit result; if it throws, report failure and retain the previous generation. If handling an ambiguous thrown write, inspect only the target envelope revision, never the full payload.
- Make `readGeneration` mark a storage read exception as a damaged record instead of silently treating it as absent. Preserve the ability to load the older valid generation when one envelope is damaged. Never initialize default config over an unsupported or damaged saved config.
- Keep `SessionController.commit` updating `_session` only after `Store.commitPair` succeeds. Preserve the existing start ordering: reserve sequence, start recorder, save active state; discard the recorder on a known active-save failure. A sequence gap after failure is acceptable. Do not delete or rewrite current watch data for this change.

### 2. Put a bound on the START event

- Route Home START and the Select Workout menu through one start entry point. Capture the routine ID once, show a short `Starting workout…` state, and ignore repeat START while it is pending.
- Use a one-shot watch-app timer to separate preparation (one config read, last-performance read, session creation) from durable sequence reservation and recording/active save. Keep each phase free of repeated config reads and full payload comparisons. Only show the workout overview after active save succeeds. On failure, return to Home with a specific error; do not leave the UI stuck on Starting.
- Retain checks for empty routines, unsupported/corrupt saved state, activity recording failure, and a failed active save. Re-entry after a process crash must use the saved active generation and existing recovery path without automatically saving a possibly duplicated FIT activity.

### 3. Trim recurring work and protect saved data

- In Home rendering and routine selection, reuse the routine snapshot for the current display pass and compute set totals from it. Avoid calling `readConfig()` again solely to draw the set total. Refresh after edits so routine creation and changes remain visible.
- Audit all `commitPair` callers, especially 30-second checkpoints, set edits, `finalizePending`, and boot recovery, for more than one large write in a single callback. Split a confirmed over-budget path at a safe persisted boundary; do not add a general job framework.
- Keep persisted array counts bounded before loops and casts. A malformed last-performance entry should lose only its prefill. An invalid active or config record should show a recoverable error rather than crashing or replacing the last known good generation. Do not silently reset routines or history.
- After the start path is stable, make migration write failure visible and keep the previous config generation; investigate worst-case active/history value size before raising the 60-set ceiling. Reconcile the existing numeric-override test with v2 routine persistence as separate quality work.

### 4. Evidence and release gate

- Build the signed FR965 target using `-y /private/tmp/NextSetDeveloperKey.der`; preserve all current uncommitted routine-editor work. Record the resulting build and changed behavior in `docs/DEVICE_TESTS.md`.
- For a physical retest, start Upper, Lower, and a custom routine from both Home and the workout menu; log sets, pause/resume, finish, reconnect, and inspect the fresh CIQ log and Garmin activity. Confirm that a failed save does not show a successful workout or lose the prior active generation. Record simulator and watch evidence separately.
- If the new watch build still approaches the watchdog, measure phase durations with `System.getTimer()` and memory with `System.getSystemStats()` on the FR965 before further refactoring. Garmin's `System.println()` can write device diagnostics when an app-named `.TXT` file is created under `GARMIN/Apps/LOGS`; use this only for a diagnostic build. [Garmin developer FAQ](https://forums.garmin.com/developer/connect-iq/w/wiki/4/new-developer-faq).

The initial handoff should implement steps 1 and 2, plus the Home read reduction in step 3. The remaining audit findings are follow-up work after device timing establishes where the watch spends time. Do not change workout data semantics, Garmin exercise mappings, or the editor flow.

## Handoff status (2026-09-29)

Luna 6 Max implemented the initial scope: the shared Store write path, three-stage workout start, a pending screen and repeat guard, and Home routine snapshot reuse. The signed FR965 build succeeded and was copied to the watch through OpenMTP. The user reported that the requested start/log/save smoke path worked. The reconnected watch's `CIQ_LOG.BAK` is unchanged from the prior crash log, and the newly saved `2026-09-29-14-21-41.fit` has FIT File Id type Activity and Session sport Training / sub-sport Strength Training. This establishes a short device smoke check, not Garmin Connect presentation or full-session resilience. Migration, domain payload validation, storage headroom, and the existing numeric-override test remain follow-up items.

## Follow-up implementation (2026-09-29)

The follow-up now stages finish into separate timer callbacks for FIT result resolution, history archive, last-performance cache, and active tombstone. History archives retain the fields used by History and prefill rebuild while omitting drafts and unrelated exercise snapshot fields. Session and recorder state advance only after durable writes; a failed stage leaves the prior finalizing state available for retry. Session, history, config, recent exercise, and prefill payloads are validated before recovery/casts, and the Store continues to read the older good generation when a newer one is malformed. Malformed prefill records are omitted individually. New prefill writes keep the latest 32 exercise entries, while reads accept older bounded caches up to 128 entries. The 60-set and per-domain count bounds plus caught `Storage.setValue()` failures provide a bounded/save-failure-safe path; exact 32 KB headroom remains unmeasured.

The v1 numeric-template override failure was a code defect: migration materialized seed defaults as per-routine increments, shadowing v1's global override. Seed defaults are no longer saved as explicit per-routine increments; explicit row values remain authoritative. `testNumericTemplateOverrides` now passes with its fixture marked schema v1.

Signed `fr965` production and unit-test builds succeeded with `/private/tmp/NextSetDeveloperKey.der`. The simulator test target reported 21/21 passing, including the numeric override regression and stored-session/prefill checks. `monkeydo` returned exit 1 after printing the passing summary. The new 496,540-byte `bin/NextSet.prg` was copied through OpenMTP to `GARMIN/Apps/NextSet.prg` and appeared in the watch pane. Device checks remain for installation after disconnect, injected failures at every finalization write, restart between stages, a 60-set finish, and FR965 write latency, memory, and 32 KB storage headroom.

## Finish callback device follow-up (2026-09-29)

The next FR965 log captured `Invalid Value / Failed invoking <symbol>` at `NextSetApp.retryPendingFinalization` when the confirmed abort action scheduled `method(:advanceFinalization)`. That timer callback was private; it is now public. The signed production build succeeded and the 496,444-byte `NextSet.prg` was copied to the watch. The user then reported that the app "seems good now." No post-fix log or exact abort/save sequence was captured, so longer-session and interrupted-finish checks remain open.
