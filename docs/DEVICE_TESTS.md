# Device and simulator evidence

Status reflects evidence actually recorded in this thread. Simulator checks do not count as FR965 hardware acceptance. The catalog, seeded routines, Garmin exercise picker, and NAS write-back described in older entries are pre-0.2.8 behavior; they are retired and those results do not validate direct Liftosaur sync.

## Implementation status

The working tree now syncs routines from Liftosaur, caches per-set targets, and queues finalized workouts for direct upload. The API key is entered on the watch (Settings → Liftosaur key) and stored only in watch app storage. Upload work is persisted and capped at four pending jobs. Config schema v4 resets older routine/config data; sync the active Liftosaur program after upgrading. See [README.md](../README.md) for the user flow and [PHASE2_HANDOVER.md](archive/PHASE2_HANDOVER.md) for the architecture.

NextSet still records a Garmin FIT activity using sport `TRAINING` and sub-sport `GENERIC`. Local completed set details remain in watch history. Earlier physical checks of FIT activity recording and the Generic sub-sport are retained below, but the current-version FIT output, direct sync, upload queue, and Liftosaur progression have not yet been accepted on a watch.

## Direct Liftosaur integration — PENDING (2026-09-30)

No physical FR965 acceptance result is recorded yet (simulator unit tests: see the 2026-09-30 entry at the end). No real Liftosaur workout POST has been made, this work has not been merged to `main`, and no acceptance check should make a live write before explicit user approval.

- [ ] **PENDING** Enter the key via Settings → Liftosaur key (TextPicker); confirm it is shown only masked, Test key reports "Key OK · <program>", Clear key removes it, and a routine sync works on a paired phone.
- [ ] **PENDING** Sync a multi-day active program; check the day names, per-set reps/load, warmups, cached routines after relaunch, and whether Home's selected day matches Liftosaur's next-day pointer. Repeat a sync to confirm it replaces the routine snapshot cleanly.
- [ ] **PENDING** After syncing, log with the phone disconnected; confirm the watch uses cached targets and local history/FIT finalization still succeeds.
- [ ] **PENDING** With explicit approval for a real write, finish one controlled workout and verify Liftosaur history, progression, and substitution notes, including skipped sets, assistance, timed sets, and unilateral exercises. Confirm one upload only.
- [ ] **PENDING** Finish offline, relaunch, reconnect and retry; verify the durable queue uploads exactly once. Repeat with app exit between start, sets, and finish.
- [ ] **PENDING** Verify Settings shows pending upload count and retry; fill the four-job queue and confirm a new workout cannot start until it clears.
- [ ] **PENDING** Measure full-program response memory on the FR965 and check oversized/error responses leave the watch usable. Record peak memory separately from response parsing estimates.
- [ ] **PENDING** Inspect a current FIT after workout completion and after app stop/relaunch; check activity type, duration/HR, lap fields, and whether Connect displays custom fields. Do not claim native per-exercise strength rows.

Historical test and device entries below describe earlier builds. Items specifically about the retired Garmin picker, category codes, old seed routines, or NAS-to-Liftosaur write-back are retained as history and are not current acceptance checks.

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
- [ ] **PENDING** Delete Upper and Lower; the last routine cannot be deleted. New exercise uses the Settings default rest.
- [ ] **PENDING** Exercise menu: Edit last set > Delete set confirms and removes the set; Replace exercise swaps at 0 sets and adds an alternative otherwise.

## Set laps and FIT developer fields (`fit-set-laps`) — PENDING

- **0.2.1 build and simulator tests (2026-09-29):** signed debug, test and release builds succeeded for FR965 with SDK 9.2.0 and the current developer key. The release artifact is `bin/NextSet-0.2.1.prg` (310,988 bytes); `bin/NextSet-0.2.1.iq` was also exported for Monkey Graph. The simulator reported 37/37 tests passed, although `monkeydo` exited 1 after that summary. The generated FIT contribution metadata contains five lap and four summary fields. No 0.2.1 activity FIT file or Garmin Connect rendering was inspected. Garmin's developer guide says Connect IQ developer fields from a sideloaded app will not render in Garmin Connect; use the `.iq` package with a watch FIT file in Monkey Graph for local display testing.

- [ ] **PENDING** Log a session with weight, assistance, bodyweight and timed sets, finish it, then inspect the watch FIT file for one lap per logged set and developer fields for exercise, set, reps, weight, duration, total sets, volume, exercises and version. Garmin Connect will not render sideloaded Connect IQ developer fields; this is not a Connect display test.
- [ ] **PENDING** Inspect the first and trailing laps for repeated field values; fields are no longer cleared immediately because this can overwrite unwritten FIT data.
- [ ] **PENDING** Leave the app mid-workout and reopen: the second saved activity also carries laps and summary fields.
- [ ] **PENDING** Confirm logging a set stays instant (no visible delay from the lap calls) and that a 60-set workout still finishes without a watchdog error.
- [ ] **PENDING** If a FIT file can be pulled from `GARMIN/Activity`, parse its lap messages and developer field definitions to compare with the app's history.

## 0.2.2 beta and fēnix build (2026-09-29)

- **Signed packages:** public `bin/NextSet-0.2.2-public.iq` built all seven Garmin hardware entries from the FR965 and selected fēnix 8/9 manifest targets. Private `bin/NextSet-0.2.2-private-beta.iq` built for FR965 only with a separate beta app ID. A scan of every packaged `.prg` found `upper-row` and `lower-leg-press` only in the beta binary; neither package contains the test markers checked. No signing key was packaged.
- **Simulator tests:** signed FR965 target reported 37/37 passed, 0 failures, 0 errors. `monkeydo` returned 1 after the passing summary. The initial simulator connection failed; quitting and relaunching the simulator resolved it.
- **Startup UI:** public FR965 showed `Routine 1`, `0 ex · 0 sets`, and an add-exercise prompt. Private beta FR965 showed Upper with 8 exercises and 19 sets. Public fēnix 9 Pro 51 mm showed the empty starter routine on its 466×466 display without visible clipping. Screenshots: `NextSet-public-fr965-0.2.2.png`, `NextSet-private-beta-fr965-0.2.2.png`, `NextSet-public-fenix9pro51mm-0.2.2.png` in this directory. Other fēnix targets compiled but have no UI or physical-watch check yet.
- **Pending physical beta check:** install the beta through Connect IQ Store, log a short workout, sync, and inspect the developer fields in Garmin Connect. The simulator and package inspection do not establish Connect rendering.

## 0.2.3 FIT set breakdown — PENDING

- **Build and simulator tests (2026-09-29):** signed public, beta and test builds succeeded for FR965; simulator reported 37/37 passed (after removing the summary lines). The simulator only connected after quitting and relaunching it. Lap queue, closing-lap blanking and Connect rendering are not verified on a watch.
- [ ] **PENDING** Log sets less than 1 s apart: every set appears as its own lap in the FIT file (0.2.1 lost 2 of 19; queued laps are written on the 1 s tick).
- [ ] **PENDING** No trailing lap that repeats the last set (the closing lap has an empty exercise name and zeros).
- [ ] **PENDING** Garmin Connect shows volume as a whole number (0.2.1 was reported as "65256 kg" for 6525.0).

## 0.2.4 explicit set start — PENDING

- **Build and simulator tests:** only the pure logic is unit-tested; nothing below is verified on a watch.
- [ ] **PENDING** Press flow on the watch: on a weight exercise the first START shows `SET 0:00` counting up and the cue `START log`; the second START logs the set and starts rest; a START within 800 ms of the first is ignored.
- [ ] **PENDING** The `SET m:ss` line and cue fit the round FR965 screen without clipping (long exercise names, two-line titles).
- [ ] **PENDING** BACK while a set runs keeps it running and returns to the overview; reopening the exercise still shows `SET m:ss` and `START log`.
- [ ] **PENDING** Starting a set during rest ends the rest countdown.
- [ ] **PENDING** Inspect the FIT lap developer field `active_s` (id 9): start-to-log seconds for started sets, measured duration for timed sets, 0 for sets logged without a start.

## 0.2.5 group-only Garmin codes — PENDING

- [ ] **PENDING** In the Garmin exercise picker, "Category only" is readable under entries such as Bench Press (Bench Press category) without clipping, and selecting one adds it to the routine.
- [ ] **PENDING** Existing routines and history still load after installing 0.2.5 over 0.2.4.
- [ ] **PENDING** Inspect a 0.2.5 FIT: every set lap carries lap developer fields `garmin_category` (id 10) and `garmin_code` (id 11) (code empty for group-only exercises), even without `fitContributions` entries for them.

## Review fixes on fit-set-breakdown — PENDING

- [ ] **PENDING** Correcting a set and undoing a set each produce an extra lap (developer field `void` id 12: 0 for the correction, 1 for the undo); after NAS sync Connect shows the corrected values and no undone set.
- [ ] **PENDING** Time the last workout-start stage (`commitWorkoutStart`) on the watch; compare with the 150 ms timer budget and the watchdog limit.
- [ ] **PENDING** The "Set 1" overlay shown at workout start comes from the firmware; compare with the main build to confirm it is not new.

## Sub-sport A/B (physical FR965, 2026-09-30)

- **A/B sideload test:** with `STRENGTH_TRAINING` the native Strength UI still showed a "Set 1" screen for a few seconds at start, even with `createField` moved before `session.start`. With `GENERIC` (sport `TRAINING`) it did not appear, and Garmin Connect shows the activity as Strength Training. Production now uses `GENERIC`.
- [ ] **PENDING** Watch activity history label for a Generic recording.
- [ ] **PENDING** Training load / recovery effect for a Generic recording.

## 0.2.6 compact catalog

- **Simulator (2026-09-30):** unit tests cover the entry parser, catalog id uniqueness over all 47 categories, old-style id fallback and old-schema-to-defaults.
- **Physical FR965, store beta 0.2.6 (2026-09-30, user report):** upgrade from 0.2.5 kept the Upper/Lower routines; the Garmin picker browsed several categories including large ones with correct names, "Category only" markers and no noticeable delay; a catalog exercise was added to a routine and logged in a workout; the NAS job wrote it to Garmin Connect. A catalog exercise is not in `exercises.json`, so that write implies the lap `garmin_category`/`garmin_code` fields reached the FIT (not inspected directly).
- [ ] **PENDING** Browse all 47 categories and the largest (131 entries) end to end; recent and "Used in routines" lists with old `g-<hex>` ids.

## Phase 2 direct Liftosaur sync (simulator unit tests, 2026-09-30)

- **Simulator only, not a device result:** signed production and unit-test builds succeeded for FR965 (SDK 9.2.0); `monkeydo bin/NextSet-tests.prg fr965 -t` reported `PASSED (passed=42, failed=0, errors=0)` (after the UX/stability fixes: upload pre-check, skip/clear queue, week-only sync, implicit week, program-changed notice). Covers Liftoscript day-header parsing, sanitized `/workout/next` fixture to v4 routine conversion, v4 Model validation and v3 reset, upload-queue state machine (409 start-time-taken done, already-active blocked, retry, four-workout bound) and set-to-setId mapping (extra/append, missing, timed, unilateral, assistance). No live Liftosaur request was made; a real sync, memory peak with the user's program and upload are not verified.
- [ ] **PENDING** Enter the key on the watch, sync routines on a physical FR965 (acceptance 1).
- [ ] **PENDING** Real workout of 5+ min uploads; Liftosaur history and progression reflect it (acceptance 2).
- [ ] **PENDING** Airplane mode at finish uploads later exactly once (acceptance 3).
- [ ] **PENDING** App exit mid-upload resumes without duplicates (acceptance 4).
- [ ] **PENDING** Device: Sync/Retry show "Syncing…"/"Uploading…" and the menu closes; "Skip this upload" and "Clear upload queue" confirmations; last-day sync pivot does not trip the watchdog; crash-resume with `workout_already_active` adopts our workout via `/workout/current` (endpoint behavior unverified).
- [ ] **PENDING** Superset flow on the watch (Pull Up + Triceps Dip "A"): the view alternates after each logged set, BACK returns to Overview once, no rest between members and rest after the round, finishing or skipping one member lets the other continue with its own rest, "Edit last set" edits the set just logged on the other member, the "Next:" line fits the round screen.
- [ ] **PENDING** 10 s pre-rest vibration fires once per rest of 20 s or more (not after resume, not with vibration off) and the end-of-rest alert is unchanged.
- [ ] **PENDING** Menu → Weight step changes the +/- step of the next load edit and is still applied after a routine re-sync; "Liftosaur ✓" glyph renders in History (fallback: plain text).
- [ ] **PENDING** Rep ranges: the fixture's sets have `minReps: null`, so a range is unverified against real Liftosaur data.
- [ ] **PENDING** (0.3.0) Offline: with the phone disconnected, Sync/Retry/Test key show "Phone not connected" and change no queue or journal; a timeout shows "No response · will retry"; reconnecting lets the automatic retry (2, 5, 10 min backoff, app open, not during a workout) complete the upload once.
- [ ] **PENDING** (0.3.0) Onboarding: fresh install shows "No Liftosaur key / START: Enter key"; START opens the key field, and after saving a sync starts by itself. "Test key" shows "Testing…" then the result; "Clear key" returns to Settings.
- [ ] **INFO** Simulator memory with the user's real day responses (local measurement, not committed): raw dictionary about 21-23 KB, peak during conversion about 39-43 KB, converted routine about 18-20 KB; device heap limit and firmware JSON conversion may differ.
- [ ] **PENDING** (0.3.1) Warmup flow on the watch: exercise opens on "Warmup 1/N" with planned load/reps, START twice logs it, rest uses the warmup timer or 60 s, UP/DOWN edit, "Edit last set"/delete works on a warmup, "Skip warmups" goes to Set 1/N, set totals and "Last time" ignore warmups, a superset member does its warmups before joining the A1/A2 rotation.
- [ ] **PENDING** (0.3.1) Liftosaur shows the completed warmup sets after an upload (API acceptance of completed `warmupSets` is unverified) and the workout notes list extra warmups.
- [ ] **PENDING** (0.3.1) Garmin Connect/FIT: warmup laps appear with lap field `set` = 0; working laps unchanged. History detail shows "W1 …" lines.
