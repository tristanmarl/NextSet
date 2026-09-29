# Device and simulator evidence

Status reflects evidence actually recorded in this thread. Simulator checks do not count as FR965 hardware acceptance.

## Implementation status

The app keeps NextSet workout state and set details in local app storage. The working tree includes editable Upper/Lower routines, the bundled 47-category/1,531-exercise Garmin catalog, seeded mappings, set logging and correction, rest and timed-set clocks, workout pause/resume and checkpoint recovery, overview navigation, a bounded read-only history, and last-performance prefill.

The production code creates a `Toybox.ActivityRecording.Session` using sport `TRAINING` and sub-sport `STRENGTH_TRAINING`; a completed routine calls `save()`. Explicit pause/resume stops and restarts the same session handle, then completion saves it once. A controlled app stop saves the current segment because the SDK handle cannot be restored after process loss; a later resume may create another activity. A crash or ambiguous save cannot be reliably queried, so the app marks that result unknown and does not retry it automatically. NextSet's detailed completed sets remain in its local history. No FIT file or physical-watch activity was inspected in this implementation pass, and native Garmin per-exercise set rendering is unverified.

## Evidence recorded

- **Workout-save watchdog fix (2026-09-29):** reproduced the IQ! crash in the FR965 simulator while finishing a workout with 9 logged sets. The watchdog stack pointed to quadratic dictionary key matching in `Store.equal()` during the history `commitPair`. Replaced the nested key scan with `Dictionary.hasKey()` and direct recursive value comparison. The signed production build succeeded; finishing a one-set workout then showed `GARMIN ACTIVITY SAVED` and exited cleanly. Physical-watch retest remains pending; OpenMTP reported the watch disconnected.
- **Workout-flow pass (2026-09-29):** signed `fr965` production build completed with `BUILD SUCCESSFUL` after the Home, editor, workout-action, picker, and save-result changes. The rebuilt app was launched in the FR965 simulator. Home, overview progress, a weighted set, and a running rest countdown were inspected. The rest screen initially hid its action cue, and a long title was truncated; both were fixed and then visually rechecked with `Machine Shoulder Press`, `Set 2/2`, `45 kg × 8`, `REST 0:19`, and `MENU SKIP REST` all visible. Two sets were logged in the simulator's existing Upper workout during this review. Timed, completed, error, and physical-watch states remain visually unverified. No automated tests were run in this pass.
- **UX implementation build and smoke review (2026-09-27):** signed `fr965` production build compiled and relaunched in the API 5.2.0 simulator. Home, exercise overview, and a two-line long exercise title were inspected; the active workout was left intact. This did not exercise complete workout paths or physical haptics.
- **Simulator launch and UI (2026-09-27):** the fresh production build launched against the FR965 simulator definition (Connect IQ SDK 9.2.0, API 5.2.0). Home, overview, and exercise screens were inspected. Overview labels and the exercise screen fit without visible clipping, including long exercise names. This is simulator-only visual evidence.
- **Persistence smoke check:** an active Upper workout with one completed set survived an app relaunch in the simulator. This does not establish capacity, corruption recovery, forced-restart behavior, or hardware reliability.
- **Automated tests (2026-09-27):** the expanded simulator test target reported 17/17 passing, with 0 failures and 0 errors. `monkeydo` returned exit code 1 after printing the passing summary, including for an isolated passing test; investigate the runner status before relying on its exit code in CI.
- **Storage fix:** readback equality compares string contents; an earlier save failure was traced to string equality.
- **Production build:** the integrated tree compiled successfully for `fr965` with Connect IQ SDK 9.2.0. This is build evidence only; it does not establish simulator test or physical-watch acceptance.
- **Strength recording and routine editor build (2026-09-29):** signed production compilation succeeded for `fr965` with Connect IQ SDK 9.2.0 after adding `ActivityRecording`, Fit permission, the offline Garmin catalog, and editable routines. The test-target simulator attempt returned `Unable to connect to simulator.` A later production launch displayed NextSet Home on the FR965 simulator (`START: Resume`), but `monkeydo` stayed attached without output and was interrupted; I did not exercise a workout. No FIT file was inspected, so watch and Garmin Connect checks remain pending.

## Physical FR965 acceptance — PENDING

No physical-watch acceptance has been recorded. Run on API 5.2-capable firmware and record firmware, app build, settings, elapsed time, and result for each item.

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

## Activity/FIT recording — DEVICE VALIDATION PENDING

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
