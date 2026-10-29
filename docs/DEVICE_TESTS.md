# Device and simulator evidence

Status reflects evidence actually recorded. Simulator checks are not hardware acceptance; marks are only upgraded from recorded device results.

## Current state

NextSet 0.3.4 syncs routines from Liftosaur, caches per-set targets and uploads finished workouts directly. The API key is entered on the watch (Settings → Liftosaur key) and stored only in watch app storage. The app also records a Garmin FIT activity (sport `TRAINING`, sub-sport `GENERIC`). The unit tests pass in the simulator (`PASSED (passed=51, failed=0, errors=0)`, 2026-09-30); that is build evidence only.

**Earlier device evidence that still applies:** a saved FIT activity was inspected from the watch (File Id type Activity, sport Training); with sub-sport `GENERIC` the firmware's native "Set 1" screen does not appear and Garmin Connect lists the activity as Strength Training. Garmin Connect showed heart rate and duration for a 0.3.0 activity.

## Direct Liftosaur integration — PARTIAL (2026-09-30)

**Physical FR965, 0.3.0, reported by the user on 2026-09-30:** key entry on the watch and routine sync worked; the superset flow worked; a real workout uploaded to Liftosaur; a workout finished offline uploaded after reconnecting the phone and reopening NextSet; Liftosaur progression applied after the upload; Garmin Connect showed heart rate and duration for the activity. **0.3.1:** warmups were tracked on the watch and shown as completed in Liftosaur. Not reported: Test key/Clear key, masking, per-set target details, unilateral/timed upload details, exactly-once checks, app exit mid-upload, the 2/5/10-min automatic retry, FIT lap fields, and on-device memory.

- [ ] **PARTIAL** (key entry and sync confirmed 2026-09-30) Enter the key via Settings → Liftosaur key (TextPicker); confirm it is shown only masked, Test key reports "Key OK · <program>", Clear key removes it, and a routine sync works on a paired phone.
- [ ] **PARTIAL** (sync confirmed 2026-09-30; details below not individually reported) Sync a multi-day active program; check the day names, per-set reps/load, warmups, cached routines after relaunch, and whether Home's selected day matches Liftosaur's next-day pointer. Repeat a sync to confirm it replaces the routine snapshot cleanly.
- [ ] **PENDING** After syncing, log with the phone disconnected; confirm the watch uses cached targets and local history/FIT finalization still succeeds.
- [ ] **PARTIAL** (real upload reached Liftosaur 2026-09-30; progression, notes, skipped/assisted/timed/unilateral and one-upload-only not individually reported) With explicit approval for a real write, finish one controlled workout and verify Liftosaur history, progression, and substitution notes, including skipped sets, assistance, timed sets, and unilateral exercises. Confirm one upload only.
- [ ] **PARTIAL** (offline finish → reconnect → reopen uploaded, 2026-09-30; exactly-once and mid-upload app exit not reported) Finish offline, relaunch, reconnect and retry; verify the durable queue uploads exactly once. Repeat with app exit between start, sets, and finish.
- [ ] **PENDING** Verify Settings shows pending upload count and retry; fill the four-job queue and confirm a new workout cannot start until it clears.
- [ ] **PENDING** Measure full-program response memory on the FR965 and check oversized/error responses leave the watch usable. Record peak memory separately from response parsing estimates.
- [ ] **PENDING** Inspect a current FIT after workout completion and after app stop/relaunch; check activity type, duration/HR, lap fields, and whether Connect displays custom fields. Do not claim native per-exercise strength rows.

## Firmware crash during a workout — INFO (2026-10-29)

**Physical FR965, firmware 29.05, NextSet 0.3.4, "Full Body A".** The watch rebooted mid-workout. Evidence pulled over MTP: `/GARMIN/DEBUG/err_log.bak`, `/GARMIN/DEBUG/dump/RAM.zip` and the two FITs `2026-10-29-07-01-37.fit` and `2026-10-29-07-16-05.fit` (kept locally, not committed).

- Firmware fault: `err_log.bak` reports `error_cause` "RTL Trap", RTL error `0x035`, at 07:14:19 local (06:14:19 UTC), pageStack `1857,1674,1860`, uptime about 13.4 days. No `CIQ_LOG.YML` was written (only `CIQ_LOG.BAK` from 2026-10-07), so the Connect IQ VM recorded no NextSet error. `RAM.zip` is an encrypted Garmin dump (`dump2(kfp=…)` header, 8.0 bits/byte), so only Garmin can read it. The backtrace cannot be symbolized here.
- Timing: Chest Press set 2 was logged at about 07:12:49–50 and started a rest; the crash came 89–90 s later, in the same second a 90 s rest would expire. At expiry `NextSetApp.onTick` commits the session, vibrates for 1 s and redraws. The exact rest length for that exercise was not checked. The same expiry path ran about 18 more times in the resumed workout without a fault. Working conclusion: a firmware fault, possibly triggered by NextSet's storage/vibration/redraw at rest expiry, not a NextSet code error. If a second crash also lands on a rest expiry, report it to Garmin with `err_log.bak` and `RAM.zip` and consider spacing the commit and the vibration apart.
- [x] **CONFIRMED** (2026-10-29) Crash-resume after a watch reboot: the firmware recovered the open activity (power-up event 07:14:42, closed 07:15:47; 6 set laps with developer fields, no NextSet session fields). NextSet relaunched and resumed at Chest Press set 3 with set 2 kept, recording a new activity at 07:16:05 that finished normally at 07:49:17 (session fields: 20 sets, 8 exercises, version 0.3.4). The workout appears as two Garmin activities. Upload of the resumed workout to Liftosaur was not checked.


## Pending device checks by version

- [ ] **PENDING** Device: Sync/Retry show "Syncing…"/"Uploading…" and the menu closes; "Skip this upload" and "Clear upload queue" confirmations; last-day sync pivot does not trip the watchdog; crash-resume with `workout_already_active` adopts our workout via `/workout/current` (endpoint behavior unverified).
- [ ] **PARTIAL** (superset flow worked on the FR965 per user, 2026-09-30; sub-checks not individually reported) Superset flow on the watch (Pull Up + Triceps Dip "A"): the view alternates after each logged set, BACK returns to Overview once, no rest between members and rest after the round, finishing or skipping one member lets the other continue with its own rest, "Edit last set" edits the set just logged on the other member, the "Next:" line fits the round screen.
- [ ] **PENDING** 10 s pre-rest vibration fires once per rest of 20 s or more (not after resume, not with vibration off) and the end-of-rest alert is unchanged.
- [ ] **PENDING** Menu → Weight step changes the +/- step of the next load edit and is still applied after a routine re-sync; "Liftosaur ✓" glyph renders in History (fallback: plain text).
- [ ] **PENDING** Rep ranges: the fixture's sets have `minReps: null`, so a range is unverified against real Liftosaur data.
- [ ] **PENDING** (0.3.0) Offline: with the phone disconnected, Sync/Retry/Test key show "Phone not connected" and change no queue or journal; a timeout shows "No response · will retry"; reconnecting lets the automatic retry (2, 5, 10 min backoff, app open, not during a workout) complete the upload once.
- [ ] **PENDING** (0.3.0) Onboarding: fresh install shows "No Liftosaur key / START: Enter key"; START opens the key field, and after saving a sync starts by itself. "Test key" shows "Testing…" then the result; "Clear key" returns to Settings.
- [ ] **INFO** Simulator memory with the user's real day responses (local measurement, not committed): raw dictionary about 21-23 KB, peak during conversion about 39-43 KB, converted routine about 18-20 KB; device heap limit and firmware JSON conversion may differ.
- [ ] **PENDING** (0.3.1) Warmup flow on the watch: exercise opens on "Warmup 1/N" with planned load/reps, START twice logs it, rest uses the warmup timer or 60 s, UP/DOWN edit, "Edit last set"/delete works on a warmup, "Skip warmups" goes to Set 1/N, set totals and "Last time" ignore warmups, a superset member does its warmups before joining the A1/A2 rotation.
- [ ] **PENDING** (0.3.1) Liftosaur shows the completed warmup sets after an upload (API acceptance of completed `warmupSets` is unverified) and the workout notes list extra warmups.
- [ ] **PENDING** (0.3.1) Garmin Connect/FIT: warmup laps appear with lap field `set` = 0; working laps unchanged. History detail shows "W1 …" lines.
- [ ] **PENDING** (0.3.2) One-press logging: START logs the displayed weight, bodyweight or warmup set immediately and starts the rest; a fast second press within 800 ms is ignored; timed sets still start on the first press and log on the second; no "SET m:ss" clock is shown; resuming a workout saved by 0.3.1 loads normally.
- [ ] **PENDING** (0.3.2) Cancel workout shows "Cancelling workout…" (not "Saving workout…"), leaves no history entry, changes no "Last time" values and queues no upload; the Garmin activity is discarded.
- [ ] **PENDING** (0.3.3) Icons and edge hints on the FR965: START/BACK/UP/DOWN/menu markers sit at the physical keys on Home, Overview and the set screen and are readable without colliding with text; set screen, Overview and Home no longer show "START/UP/DOWN/MENU" text hints.
- [ ] **PENDING** (0.3.3) Set confirmation: after logging, a check icon with "Set 2 · 65 kg × 8" shows about 2 s (or until the next UP/DOWN) and a short vibration fires (off with vibration disabled); the superset switch gives a distinct double pulse; the A1/A2 label shows next to the exercise name.
- [ ] **PENDING** (0.3.3) Rest overtime: when the rest ends the green clock "+m:ss" counts up on the set screen and Overview until the next set is logged.
- [ ] **PENDING** (0.3.3) Overview shows "n/m" and elapsed workout time; exercise menu title is the exercise name; finished exercise shows the BACK/menu hint.
- [ ] **PENDING** (0.3.3) Summary shows the Liftosaur status live (Uploading… / Uploaded / Pending · next launch / error) and "Upload resumes next launch" while uploading; Cancel returns to Home with "Workout cancelled".
- [ ] **PENDING** (0.3.3) UP/DOWN edits feel instant and survive a set log, a menu and leaving the app (an edit made within 2 s of a crash may be lost).
- [ ] **PENDING** (0.3.3) After a long workout read Settings → Diagnostics (max commit ms, last sync parse ms, free KB) and record the numbers here.

- [ ] **PENDING** (unreleased, after 0.3.4) Resilience changes: the rest-end vibration still fires once when a rest runs out, and the expired rest survives leaving the app 3 s later; a crash or app exit within ~2 s of a rest ending repeats the alert on resume at most once. Elapsed workout time after a forced app exit excludes only the time since the last 30 s checkpoint. Settings → Diagnostics max commit ms is not higher than in 0.3.4.
- [ ] **PENDING** (unreleased, after 0.3.4; needs the next real workout upload) Liftosaur history shows the real duration (not `duration: 2s`) and no `// NextSet session …` line; liftosaur2garmin without the NAS parser patch processes the workout. Until a real write confirms it, the API acceptance of `intervals` from NextSet is unverified.

- [ ] **PENDING** (unreleased) Other watches: 53 five-button Connect IQ 5+ products build (2026-10-29), and the Home screen starts without a crash in the simulator on fr255s, fenix7s, fr255, fenix7x, fr265s, instinct3amoled45mm, descentg2, epix2, fr965, fenix9pro51mm and fr170. Before that fix, fr255s crashed on Home (`Graphics.getVectorFont` missing on MIP watches). Not checked: layouts beyond Home on small screens (218-280 px), and any physical watch other than the FR965.

- [ ] **PENDING** (0.3.6) Load/reps editing on the FR965: hold UP → first item "Change load · 65 kg" turns the load yellow on the set screen; UP/DOWN change it by the weight step and fast presses speed up (x2, x4); the item then reads "Change reps" and switches back; logging a set returns to reps; START, UP and DOWN act on press as in 0.3.4. Menu: "Edit last set · Set N · …" opens the editor (hold UP switches load/reps, START saves, BACK cancels); "Delete set N" asks before deleting. Check whether opening the menu with hold UP adds one rep first. Simulator: builds and Home starts; key handling not exercised here.
- [x] **FAILED** (0.3.5, 2026-10-29, user on FR965) Holds other than UP do not reach the app: hold DOWN opened the music controls and hold START did nothing. Only hold UP (menu) works. 0.3.6 drops all holds and puts the reps/load switch in the menu.

## General device checks (still open)

- [ ] **PENDING** Install/update with the same app ID; confirm local records survive the update.
- [ ] **PENDING** Complete the common workout path with touch disabled, phone disconnected and no network.
- [ ] **PENDING** Check short, held and repeated START and UP/DOWN edits; editing must not complete a set; check held UP, LIGHT, music controls and BACK.
- [ ] **PENDING** Exercise A→B→A, early close/reopen and explicit undo; correct a set before and after rest expiry.
- [ ] **PENDING** Leave and resume a timed set; measurement pauses and resumes correctly.
- [ ] **PENDING** Check rest display and haptics with screen dim/off, wake, LIGHT, menus, notification and music overlay.
- [ ] **PENDING** Pause/resume in one app instance and confirm the same activity is saved once; exit/relaunch with an active workout and inspect the saved segment and unknown-state notice.
- [ ] **PENDING** BACK from Home and Overview during an active workout opens the Actions menu (no direct exit); "Exit workout" shows the confirm screen and a reopened workout starts a separate activity segment.
- [ ] **PENDING** Measure storage, peak memory, write latency and a 90-minute / 60-set session with repeated navigation and corrections; no watchdog error.
- [ ] **PENDING** Record ten minutes with HR, pause/resume, complete, sync, and inspect the activity type and FIT duration/HR; check calories, training effect and training load (report absent metrics as absent); watch activity history label for a Generic recording.
- [ ] **PENDING** Inspect a current FIT for one lap per logged set and the developer fields (exercise, set, reps, weight, duration, active_s, void); garmin Connect does not render sideloaded developer fields, so this is a file check, not a Connect display test. Do not claim native per-exercise strength rows.
- [ ] **PENDING** (0.3.4) Cancel workout → Home with "Workout cancelled" → BACK exits the app (no "Workout could not be finished", no way back into the cancelled workout's menus); finish → summary → START/BACK exits; after a relaunch with an active workout, resume → finish/cancel behaves the same.
