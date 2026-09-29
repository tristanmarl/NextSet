# Device and simulator evidence

Status reflects evidence actually recorded in this thread. Simulator checks do not count as FR965 hardware acceptance.

## Implementation status

The app keeps NextSet workout state and set details in local app storage. The working tree includes editable Upper/Lower routines, the bundled 47-category/1,531-exercise Garmin catalog, seeded mappings, set logging and correction, rest and timed-set clocks, workout pause/resume and checkpoint recovery, overview navigation, a bounded read-only history, and last-performance prefill.

Routine management now lists saved routines, creates blank routines through Garmin's native TextPicker, opens the empty routine editor, and permits confirmed deletion of custom routines while retaining Upper and Lower. Editor lists use one saved-config snapshot; starting an empty routine is rejected before the session sequence is reserved or recording begins.

The production code creates a `Toybox.ActivityRecording.Session` using sport `TRAINING` and sub-sport `STRENGTH_TRAINING`; a completed routine calls `save()`. Explicit pause/resume stops and restarts the same session handle, then completion saves it once. A controlled app stop saves the current segment because the SDK handle cannot be restored after process loss; a later resume may create another activity. A crash or ambiguous save cannot be reliably queried, so the app marks that result unknown and does not retry it automatically. NextSet's detailed completed sets remain in its local history. A short physical-watch activity was inspected on 2026-09-29; Garmin Connect presentation and native per-exercise set rendering remain unverified.

Workout finalization now persists a `finalizing` boundary, then advances one durable step per timer callback: resolve the FIT save marker, archive history, update prefill cache, and write an active-session tombstone. The compact history keeps the fields used by History and cache reconstruction, plus completed set actuals; it drops drafts and unused exercise snapshot fields. Store validates saved payload structure before recovery and preserves a valid older generation when the newer one is invalid. Failed settings migration, recorder state, history, cache, and tombstone writes leave the in-memory session at the last successfully committed state and expose a retryable error. The last-performance cache is capped at 32 entries; malformed entries are omitted individually when loading.

## Evidence recorded

- **Finish timer callback crash (FR965, 2026-09-29):** after the reliability build, the reconnected watch's new `GARMIN/Apps/LOGS/CIQ_LOG.BAK` recorded `Invalid Value / Failed invoking <symbol>` at 13:26:02 UTC. The stack points to `NextSetApp.retryPendingFinalization` line 140 while handling the confirmed abort action, where `Timer.start(method(:advanceFinalization), 150, false)` referenced a private callback. The callback is now public, as required for invocation by the timer outside the app object. The signed FR965 production build succeeded and the new 496,444-byte `bin/NextSet.prg` appeared in `GARMIN/Apps` through OpenMTP. After disconnecting, the user reported that the app "seems good now." The exact actions exercised and a fresh post-fix log were not captured, so completion of the pending finalization remains unverified. No automated tests were run for this one-line fix.

- **Workout-start watchdog (FR965, 2026-09-29):** copied `GARMIN/Apps/LOGS/CIQ_LOG.YML` from the watch. Three crashes at 11:44–11:45 UTC report `Watchdog Tripped Error - Code Executed Too Long` during `Catalog.createSession`, with stacks in `Catalog.dictionaryValue` and `LastPerformance.prefill`. Luna 6 Max changed override lookup to `Dictionary.hasKey()`, removed seed-wide validation from workout creation while keeping selected-routine validation, and bounded cached set tuple scanning. The signed FR965 build succeeded and was copied to `GARMIN/Apps/NextSet.prg` via OpenMTP. Starting a workout with this build remains unverified on the watch.

- **Workout-start storage watchdog follow-up (FR965, 2026-09-29):** the subsequent `CIQ_LOG.BAK` copied from the reconnected watch records watchdog trips at 11:54:43 and 11:55:09 UTC in recursive `Store.equal()` during the active-session `commitPair`. `Store.commitPair` now reads each generation once, writes the older or invalid generation once, and treats a successful `Storage.setValue()` as the commit result; storage read exceptions are marked damaged. Home and Select Workout now share a staged start flow (prepare, reserve sequence, then start FIT recording and save active state), with repeat START ignored while pending. Home reuses one routine snapshot for rendering, totals, and selection. The signed FR965 build succeeded and was copied to `GARMIN/Apps/NextSet.prg` via OpenMTP. The user reported the requested start, log-set, and save smoke path worked. On reconnection, `CIQ_LOG.BAK` was byte-identical to the prior crash log, so no new exception was recorded there. No automated tests were run.

- **Physical Strength FIT smoke check (FR965, 2026-09-29):** copied `GARMIN/Activity/2026-09-29-14-21-41.fit` (6,023 bytes) after the successful user test. Its FIT File Id type is `4` (Activity), and its Session message has sport `10` (Training) and sub-sport `20` (Strength Training). This confirms a saved Strength activity file on the watch. Garmin Connect display, detailed sets, HR, and longer-session behavior were not inspected.

- **Reliability and performance follow-ups (2026-09-29):** signed FR965 production and test targets both compiled successfully with SDK 9.2.0 and `/private/tmp/NextSetDeveloperKey.der`. Finalization is staged across timer callbacks, FIT/history/cache steps are replay-safe by session ID and sequence, and archived history is compacted while retaining History UI and prefill fields. Migration and recording/finalization state advance in memory only after the corresponding write succeeds. Saved active/history/config/recent payloads are bounded and validated before use; invalid newer generations fall back to valid older ones. Malformed last-performance entries are filtered individually, and new cache writes retain the latest 32 exercise records. No explicit serialized-byte estimate or FR965 32 KB headroom measurement has been recorded; the 60-set workout ceiling and caught Storage write failures remain the safety bounds. The signed test target reported **21/21 passed**, including `testNumericTemplateOverrides` and corrupt-prefill filtering; `monkeydo` nevertheless exited 1 after printing the passing summary. The production `bin/NextSet.prg` (496,540 bytes) was then copied through OpenMTP to `GARMIN/Apps/NextSet.prg`; the file appeared in the watch pane. Installation and behavior after disconnect remain unverified.

- **Routine editor and creation implementation (2026-09-29):** the signed `fr965` production build and signed test-target build completed successfully. In that earlier run, the test runner passed 17/18 tests; the new routine-name/empty-routine test passed, while `testNumericTemplateOverrides` failed its “valid row overrides” assertion. The follow-up below identified and fixed the v1 migration regression, and the full current suite now passes. The production app launched in the FR965 simulator and Home rendered. Menu navigation and the reported IQ! stack were not reproduced: the available simulator control sent short button presses, while the FR965 Home menu requires a held UP press. No physical-watch files or saved watch data were changed. Physical-watch exercise of routine creation, cancellation, editing, deletion, and repeated menu opens remains pending.

- **Workout-save watchdog fix (2026-09-29):** reproduced the IQ! crash in the FR965 simulator while finishing a workout with 9 logged sets. The watchdog stack pointed to quadratic dictionary key matching in `Store.equal()` during the history `commitPair`. Replaced the nested key scan with `Dictionary.hasKey()` and direct recursive value comparison. The signed production build succeeded; finishing a one-set workout then showed `GARMIN ACTIVITY SAVED` and exited cleanly. The later physical smoke check is recorded above.
- **Workout-flow pass (2026-09-29):** signed `fr965` production build completed with `BUILD SUCCESSFUL` after the Home, editor, workout-action, picker, and save-result changes. The rebuilt app was launched in the FR965 simulator. Home, overview progress, a weighted set, and a running rest countdown were inspected. The rest screen initially hid its action cue, and a long title was truncated; both were fixed and then visually rechecked with `Machine Shoulder Press`, `Set 2/2`, `45 kg × 8`, `REST 0:19`, and `MENU SKIP REST` all visible. Two sets were logged in the simulator's existing Upper workout during this review. Timed, completed, error, and physical-watch states remain visually unverified. No automated tests were run in this pass.
- **UX implementation build and smoke review (2026-09-27):** signed `fr965` production build compiled and relaunched in the API 5.2.0 simulator. Home, exercise overview, and a two-line long exercise title were inspected; the active workout was left intact. This did not exercise complete workout paths or physical haptics.
- **Simulator launch and UI (2026-09-27):** the fresh production build launched against the FR965 simulator definition (Connect IQ SDK 9.2.0, API 5.2.0). Home, overview, and exercise screens were inspected. Overview labels and the exercise screen fit without visible clipping, including long exercise names. This is simulator-only visual evidence.
- **Persistence smoke check:** an active Upper workout with one completed set survived an app relaunch in the simulator. This does not establish capacity, corruption recovery, forced-restart behavior, or hardware reliability.
- **Automated tests (2026-09-27):** the expanded simulator test target reported 17/17 passing, with 0 failures and 0 errors. `monkeydo` returned exit code 1 after printing the passing summary, including for an isolated passing test; investigate the runner status before relying on its exit code in CI.
- **Storage fix:** readback equality compares string contents; an earlier save failure was traced to string equality.
- **Production build:** the integrated tree compiled successfully for `fr965` with Connect IQ SDK 9.2.0. This is build evidence only; it does not establish simulator test or physical-watch acceptance.
- **Strength recording and routine editor build (2026-09-29):** signed production compilation succeeded for `fr965` with Connect IQ SDK 9.2.0 after adding `ActivityRecording`, Fit permission, the offline Garmin catalog, and editable routines. The test-target simulator attempt returned `Unable to connect to simulator.` A later production launch displayed NextSet Home on the FR965 simulator (`START: Resume`), but `monkeydo` stayed attached without output and was interrupted; I did not exercise a workout. The later physical FIT check is recorded above; Garmin Connect remains unverified.

## Physical FR965 acceptance — PARTIAL

A short start/log/save path and saved Strength FIT were recorded on the FR965. The remaining cases below need dedicated device checks with firmware, app build, settings, elapsed time, and result.

- [ ] **PENDING** Install/update with the same app ID; confirm local records survive update.
- [ ] **PENDING** Complete the common workout path with touch disabled, phone disconnected, and no network.
- [ ] **PENDING** Check short, held, repeated, and double START; editing must not complete a set.
- [ ] **PENDING** Check held UP, LIGHT, music controls, and BACK behavior.
- [ ] **PENDING** Verify saved, draft, and last values remain distinct; check long names and assistance/bodyweight labels.
- [ ] **PENDING** Exercise A→B→A, early close/reopen, out-of-order slots, and explicit undo.
- [ ] **PENDING** Correct a set before and after rest expiry; confirm the correction target stays fixed.
- [ ] **PENDING** Leave and resume a timed set; confirm measurement pauses and resumes correctly.
- [ ] **PENDING** Check rest display and haptics with screen dim/off, wake, LIGHT, menus, lists, editor, notification, and music overlay.
- [ ] **PENDING** Pause/resume in one app instance and confirm the same activity is saved once. Exit/relaunch with an active routine and inspect the saved segment, unknown-state notice, and any later activity separately.
- [ ] **PENDING** Measure storage, peak memory, write latency, and a 90-minute session with repeated navigation/corrections.
- [ ] **PENDING** Complete two offline Upper/Lower sessions with different exercise orders, correction, pause, timeout, early close/reopen, and recovery; verify 19/17 totals and next-session prefills.

## Activity/FIT recording — PARTIAL DEVICE VALIDATION

- [ ] **PENDING** On an FR965, record ten minutes with HR, pause/resume, complete, sync, and inspect the activity type and FIT duration/HR.
- [ ] **PENDING** Test controlled app exit and interruption; inspect whether a partial saved segment and a later resumed activity are created. Record unknown outcomes without automatically retrying a possibly saved file.
- [ ] **PENDING** Check whether calories, training effect, and training load appear; report absent metrics as absent.
- [ ] **PENDING** Inspect Garmin Connect's exercise/set detail. Do not claim native strength set rows; the current code does not encode per-exercise set messages in FIT.

## Remaining simulator regression — PENDING

- [ ] **PENDING** Run arbitrary-order logging, correction, partial completion, and cross-template last-performance prefill.
- [ ] **PENDING** Run Dead Bug actuals and next-session prefill; verify Hyperextension has no kg editor.
- [ ] **PENDING** Stop/relaunch with committed sets; verify recovery notice, quiet expired rest, and paused timed measurement.
- [ ] **PENDING** Inject finalization storage failures and verify replay creates one archive and does not regress cache.
- [ ] **PENDING** Verify four-session history eviction while the independent last-performance cache retains older exercise results.
- [ ] **PENDING** Finish a 60-set routine on device; record callback latency, storage headroom, and memory use. Inject or reproduce write failures at the FIT marker, history, cache, and tombstone stages, then restart between stages and confirm one archive, preserved set actuals, and idempotent prefill.

## Stability steps 4-6 (2026-09-29) — PENDING

- [ ] **PENDING** Abort a workout with an injected storage failure at the `finalizing`/`discarding` commit; confirm the FIT recording is not discarded before the commit succeeds, then that discard runs in the finalization stage. Restart while `fitState` is `discarding` and confirm the workout closes as discarded.
- [ ] **PENDING** Pause and resume with an active FIT recording; confirm one write on pause, and that a failed `pause()` returns `fitState` to `recording` with an error notice.
- [ ] **PENDING** Open, edit, reorder, and delete routines in an 8-routine x 12-entry config (mixed seed and Garmin exercises) with no watchdog trip.
- [ ] **PENDING** Finish a 60-set workout; confirm each finalization stage (history slot choice, cache, tombstone) completes within the watchdog limit.

## Exit guard and error codes (2026-09-29) — PENDING

- [ ] **PENDING** During an active and a paused workout, press BACK from Home and from Overview: confirm BACK opens the Actions menu (no direct exit), and that "Exit workout" shows the confirm screen ("Workout continues next time. Garmin activity so far is saved separately."). Confirm exit ends the app and a reopened workout starts a separate activity segment. Confirm BACK with no active workout still exits normally.
- [ ] **PENDING** Spot-check the Home notices for recovery, save-failure, and routine-with-no-exercises errors after the error-code change; text should be unchanged.

## UX audit changes (2026-09-29) — PENDING

- [ ] **PENDING** Press counts: log a set (1), back to Overview from Exercise (1 BACK), change load (MENU, START on the first item, then edit), skip rest from the Exercise menu. Record actual counts.
- [ ] **PENDING** Overview: yellow REST m:ss counts down each second while resting; `Next:` line and `UP/DOWN · EX n/N` hint are not clipped on the round 454 px screen, with long exercise names and with rest running.
- [ ] **PENDING** Exercise screen: BACK during a running timed set pauses it and returns to Overview; MENU opens the Exercise menu in the specified order; "Workout..." reaches Finish/Pause/Exit; Pause from there returns to Overview.
- [ ] **PENDING** Routines: add and replace an exercise open Edit values; rename a routine (duplicate and blank names rejected); `Reps 8–12` edits min then max, and raising min above max raises max.
- [ ] **PENDING** Home shows `N ex · M sets · last Day`; check the caption is not clipped with long routine names. Exercise `target 8–12` caption appears only when there is room.
- [ ] **PENDING** Summary and History wording (Workout saved, cancelled, Garmin activities count).

## Second UX pass (2026-09-29) — PENDING

- [ ] **PENDING** Create a routine, then rename it: after the picker closes you land on the editor, and BACK shows the new or renamed name in the Routines list; a single BACK from Home exits.
- [ ] **PENDING** Reorder: START on Move down/up repeatedly keeps moving the same entry with the move item focused; the routine view shows the new order after BACK.
- [ ] **PENDING** Cancel a workout: the recording is discarded, History gets no new entry, and last-time prefills are unchanged. Kill the app mid-cancel and reopen to check it finishes discarding.
- [ ] **PENDING** Skip the last unfinished exercise with at least one set logged: the Workout complete prompt appears.
- [ ] **PENDING** Load a session that was saved as paused (from the previous build) and confirm it resumes as an active workout with rest and timed set intact.
- [ ] **PENDING** Delete Upper and Lower; the last routine cannot be deleted. New exercise uses the Settings default rest.
- [ ] **PENDING** Exercise menu: Edit last set > Delete set confirms and removes the set; Replace exercise swaps at 0 sets and adds an alternative otherwise.

## Set laps and FIT developer fields (`fit-set-laps`) — PENDING

- [ ] **PENDING** Log a session with weight, assistance, bodyweight and timed sets, finish it, sync, then open the activity in the Garmin Connect app and on the web. Check: one lap per logged set with Exercise, Set, Reps, Weight (- = assist) and Duration columns; the activity summary shows Sets, Volume, Exercises and NextSet version; values match what was logged (including the assistance sign).
- [ ] **PENDING** Check the first lap (before the first set) and the last lap (after the last set) are empty/zero rather than repeating a set.
- [ ] **PENDING** Leave the app mid-workout and reopen: the second saved activity also carries laps and summary fields.
- [ ] **PENDING** Confirm logging a set stays instant (no visible delay from the lap calls) and that a 60-set workout still finishes without a watchdog error.
- [ ] **PENDING** If a FIT file can be pulled from `GARMIN/Activity`, parse its lap messages and developer field definitions to compare with the app's history.
