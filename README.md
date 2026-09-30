# NextSet

NextSet is a button-operated strength workout app for the Garmin Forerunner 965 (version 0.3.3). [Liftosaur](https://www.liftosaur.com) is the source of routines and progression: the watch downloads the current week of your program, you log sets on the watch, and the finished workout is uploaded to Liftosaur directly over the phone connection. Garmin Connect still gets an activity with duration and heart rate.

## Install

- **Beta (Connect IQ developer beta):** `monkeyc -e -r -f monkey.beta.jungle -d fr965 -o bin/NextSet-beta.iq -y "$KEY"`, upload the `.iq` to the Connect IQ developer dashboard and install it from there.
- **Sideload:** `monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"` and copy the `.prg` to `GARMIN/Apps` on the watch.

Use the same signing key for every update of an installed app; a different key needs a reinstall. Keep the key outside the repository.

## Set up

1. **Key.** On the watch open **Menu → Settings → Liftosaur key** and type your Liftosaur API key (the field starts empty; the key is shown only masked, `lftsk_…ab12`). **Test key** checks it, **Clear key** removes it. The key lives only in the watch's app storage, not in Connect IQ phone settings. It grants account access: rotate it in Liftosaur if it is ever exposed.
2. **Sync.** With the phone connected, **Menu → Settings → Sync routines** (or START on Home when nothing is synced) downloads the days of your program's current week, up to eight. Home shows "Syncing…" and then "Synced N days". A sync always restarts from scratch; routines refresh again after an upload (never during a workout).
3. **Workout.** Choose a day on Home (UP/DOWN) and press START. After routines are cached you can log without the phone; syncing and uploading need the phone connection.

## Logging a workout

- **One press logs a set.** UP/DOWN adjust reps first (tap the load to edit it), then START logs the displayed weight or bodyweight set and starts the rest. Timed sets start a countdown on the first START and log on the second; BACK pauses a running timed set. A fast second press within 800 ms is ignored.
- **Feedback.** Logging shows a short check confirmation ("Set 2 · 65 kg × 8") and a brief vibration. After the rest runs out a green clock counts overtime ("+0:35") until the next set. A short buzz warns 10 s before a rest of 20 s or more ends. During rest the screen shows "Next: …". The Overview shows the exercise position and elapsed workout time.
- **Warmups** from the program are tracked: an exercise opens on "Warmup 1/2" with the planned load, logged like a working set with its own rest (the warmup's timer, else 60 s). **Menu → Skip warmups** goes straight to the working sets. Warmups never count in the set totals or "last time", and upload into Liftosaur's warmup sets.
- **Supersets** (shared Liftosaur label) alternate automatically (A1, A2, A1 …) with one rest per round and a double vibration at the switch. A member does its warmups before joining the rotation.
- **Corrections and changes.** Edit or delete the last set, add a set, skip or replace an exercise from the synced program, change the **Weight step** (0.5, 1, 2.5, 5 kg; saved per exercise name). Rep ranges appear when the program defines them.
- **Buttons** are marked by small icons at the physical keys: START upper right (play, log check or stop), BACK lower right, UP/DOWN left, three dots = hold UP for the menu.
- **Finish or cancel.** The summary shows the Liftosaur upload state live (uploading, uploaded, pending, error). Cancelling discards the workout: no history entry, no "last time" change, no upload; you return to Home.
- **History** keeps the last four workouts with "Liftosaur ✓ / pending / skipped" and warmups as "W1 …".

## Uploads, offline and errors

A finished workout is queued (up to four) and uploaded start → sets → finish. Before opening a workout in Liftosaur the watch checks that the logged sets still match the program; if not, the job is marked "Program changed" instead of starting. Nothing is sent while the phone is not connected (Home: "Phone not connected"). While the app is open, uploads and syncs that failed for lack of connection or response retry after 2, 5, then 10 minutes (not during a workout, not after a rejected key, program error or mapping problem); pending uploads also resume at launch or from **Settings → Retry workout upload**. **Skip this upload** (with confirmation) retires a stuck job and **Clear upload queue** resets a damaged queue; local history is kept either way. **Settings → Diagnostics** shows the longest session save, the last sync parse time and free memory.

## Device status and limits

Confirmed on an FR965 (see [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md) for the exact record): key entry and routine sync, supersets, a real upload with Liftosaur progression applied, an offline workout uploaded after reconnecting, warmups shown as completed in Liftosaur, and Garmin Connect showing heart rate and duration for the activity. Everything newer than 0.3.1 and the remaining checks are listed there as pending.

Still true: the watch records a Garmin activity (Training, Generic) whose laps carry NextSet set fields; it does not create native Garmin strength sets, and Connect may not show the custom fields. Prompt-variable answers are not collected, so prompt-driven programs are not supported. Unilateral `repsLeft` and timed-set progression are not verified against Liftosaur. Unsupported program data can make a sync fail; fix the program in Liftosaur and retry.

## Build and test

Install Connect IQ SDK 9.2.0 and put its `bin` directory on `PATH`; every build needs `-y` with your developer key. `scripts/test.sh` builds and runs the unit tests in the simulator. Commands, conventions and architecture notes are in [CLAUDE.md](CLAUDE.md), [AGENTS.md](AGENTS.md) and [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md). Never trigger real Liftosaur POST requests from development or tests.
