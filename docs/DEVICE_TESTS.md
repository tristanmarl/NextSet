# Device and simulator evidence

Status reflects evidence actually recorded in this thread. Simulator checks do not count as FR965 hardware acceptance.

## Implementation status

The app currently keeps workouts in local app storage. The working tree includes seeded Upper/Lower templates (19/17 planned sets), set logging and correction, rest and timed-set clocks, workout pause/resume and checkpoint recovery, overview navigation, a bounded read-only history, and last-performance prefill.

`ActivityRecording`/`Recorder`, sensor capture, activity/FIT output, and recording-segment recovery are **not implemented**. This is a local-only prototype; it does not create a Garmin activity or promise HR, calories, training effect, training load, or FIT files. On-watch settings and numeric template, default, and increment editing are implemented; persistence/restart and physical-watch validation remain pending.

## Evidence recorded

- **UX implementation build and smoke review (2026-09-27):** signed `fr965` production build compiled and relaunched in the API 5.2.0 simulator. Home, exercise overview, and a two-line long exercise title were inspected; the active workout was left intact. This did not exercise complete workout paths or physical haptics.
- **Simulator launch and UI (2026-09-27):** the fresh production build launched against the FR965 simulator definition (Connect IQ SDK 9.2.0, API 5.2.0). Home, overview, and exercise screens were inspected. Overview labels and the exercise screen fit without visible clipping, including long exercise names. This is simulator-only visual evidence.
- **Persistence smoke check:** an active Upper workout with one completed set survived an app relaunch in the simulator. This does not establish capacity, corruption recovery, forced-restart behavior, or hardware reliability.
- **Automated tests (2026-09-27):** the expanded simulator test target reported 17/17 passing, with 0 failures and 0 errors. `monkeydo` returned exit code 1 after printing the passing summary, including for an isolated passing test; investigate the runner status before relying on its exit code in CI.
- **Storage fix:** readback equality compares string contents; an earlier save failure was traced to string equality.
- **Production build:** the integrated tree compiled successfully for `fr965` with Connect IQ SDK 9.2.0. This is build evidence only; it does not establish simulator test or physical-watch acceptance.

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
- [ ] **PENDING** Exit with Resume later and relaunch; verify local sets and recovery. Recording-segment behavior cannot be checked until S4 and Recorder implementation are complete.
- [ ] **PENDING** Measure storage, peak memory, write latency, and a 90-minute session with repeated navigation/corrections.
- [ ] **PENDING** Complete two offline Upper/Lower sessions with different exercise orders, correction, pause, timeout, early close/reopen, and recovery; verify 19/17 totals and next-session prefills.

## Activity/FIT recording — NOT IMPLEMENTED; S4 PENDING

- [ ] **PENDING** Implement and validate the S4 recording probe before claiming Garmin activity support: record ten minutes with HR, pause/resume/save, exercise controlled exit and interruption, then inspect the resulting FIT. No Recorder, activity, or FIT evidence is currently available.
- [ ] **PENDING** After recording is implemented, inspect duration and HR, plus whether calories, training effect, and training load are present. Report absent metrics as absent.

## Remaining simulator regression — PENDING

- [ ] **PENDING** Run arbitrary-order logging, correction, partial completion, and cross-template last-performance prefill.
- [ ] **PENDING** Run Dead Bug actuals and next-session prefill; verify Hyperextension has no kg editor.
- [ ] **PENDING** Stop/relaunch with committed sets; verify recovery notice, quiet expired rest, and paused timed measurement.
- [ ] **PENDING** Inject finalization storage failures and verify replay creates one archive and does not regress cache.
- [ ] **PENDING** Verify four-session history eviction while the independent last-performance cache retains older exercise results.
