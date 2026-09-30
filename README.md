# NextSet

NextSet is a button-operated strength workout logger for Garmin watches. The FR965 is the primary device; the manifest also targets several fēnix 8 and 9 models. The working tree reports version 0.2.8. Direct Liftosaur sync is still under validation; see [device and simulator evidence](docs/DEVICE_TESTS.md).

## Set up and sync

1. In the Garmin Connect IQ phone app, open NextSet's settings and enter your Liftosaur API key. Treat it like a password: it grants account access, and Connect IQ settings may be stored by Garmin.
2. Pair the phone with the watch and make sure the phone has internet access. On the watch, open **Menu → Settings → Sync routines**. NextSet downloads the days of the program's current week (up to eight) and caches their per-set targets on the watch. Sync always restarts from scratch and Home shows "Syncing…" and then "Synced N days".
3. On Home, use UP/DOWN to choose a synced day and press START. The planned reps and load are prefilled for each set; the previous performance remains visible. You can add or replace an exercise from the synced program while working out.

After routines are cached, the workout can be logged without a phone connection. Syncing routines and uploading completed workouts need a phone connection and internet. Requests run asynchronously and may take several seconds.

## Workouts and uploads

Exercises that share a Liftosaur superset label alternate automatically: after a set is logged the watch opens the next member with an open set (Overview shows "A1 Pull Up", "A2 Triceps Dip"), and the rest timer runs only when the round ends. "Edit last set" targets the exercise where the set was logged. During rest the exercise screen shows "Next: <exercise> <load> × <reps>", and a short vibration warns 10 s before a rest of 20 s or more ends. Sets with a rep range from Liftosaur (both `minReps` and `reps` present) show it as "8–10". Weight exercises step 1 kg by default; **Menu → Weight step** (0.5/1/2.5/5 kg) is stored per exercise name and survives re-sync. History shows "Liftosaur ✓", "pending" or "skipped" for each workout.

START twice logs a weight set: the first press starts its timer and the next records it. Timed sets use their own start/finish timer. You can adjust actual reps and load, correct or undo a set, and skip or replace an exercise. Completed sets and recent workouts are also kept in local watch history.

After a completed workout, NextSet queues its Liftosaur upload. Up to four workouts can wait in the queue. If a request fails, the saved job can retry on app launch, after routine sync, or from **Settings → Retry workout upload**. Settings shows the pending count; a full queue blocks starting another workout until uploads clear. Routines refresh after a successful upload (never during a workout). Before opening a workout in Liftosaur, the watch checks that the saved sets still match the program; if not, the upload is marked "Program changed" instead of starting. A stuck upload can be removed with **Skip this upload** (Home menu or Settings, with confirmation); a damaged queue with **Clear upload queue**. Local history is kept either way, and a damaged queue no longer prevents starting workouts.

The watch also records a Garmin FIT activity (sport Training, sub-sport Generic). FIT laps carry NextSet exercise and set details; this is an activity fallback and does not create native Garmin planned workouts or strength sets. Garmin Connect may not display custom developer fields from a sideloaded build.

Exercise alternatives are drawn from the synced program. NextSet is intended to list substitutions in Liftosaur finish notes; verify this in the pending device check. The current API mapping for unilateral repetitions and some timed-set progression behavior also needs a controlled live check. The watch does not collect prompt-variable answers, so prompt-driven plans are not yet supported. Unsupported program/API data can make routine sync fail; correct the program in Liftosaur and retry.

## Build and test

Install Connect IQ SDK 9.2.0 and put its `bin` directory on `PATH`. This SDK requires a developer key on simulator and test builds too.

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# Build and launch in the FR965 simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Build and run the unit tests
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t
```

The SDK test runner has returned exit code 1 in earlier runs after printing a fully passing summary. Check its PASS/FAIL lines and see [DEVICE_TESTS.md](docs/DEVICE_TESTS.md); do not infer a result from the exit code alone. Do not trigger real Liftosaur POST requests during development or tests. The first live write requires an explicitly approved device check.

Keep the signing key outside the repository. Never commit, upload, or package it. Continue using the same key when updating an installed app; a different key requires reinstalling the app.

## NAS archive

The optional [tools/connect-sets](tools/connect-sets/README.md) job can archive Garmin FIT activities on a NAS. The watch is the Liftosaur writer, so keep `LIFTOSAUR_SYNC=0` on the NAS to avoid duplicate uploads. The watch does not use a NAS HTTP endpoint or Tailscale.

## Development status and limits

The direct Liftosaur path is awaiting simulator and physical FR965 acceptance. No live workout write has been made, and this work has not been merged to `main`. The Home indicator for Liftosaur's next-day pointer and the post-upload refresh still need current UI validation. Older catalog, seeded routine, and NAS-write results in [DEVICE_TESTS.md](docs/DEVICE_TESTS.md) describe earlier versions and are not evidence for direct sync.

The synced program is cached locally, but changing its plan requires another routine sync. Config schema v4 resets older manually edited or seeded routines; sync again to load the active program. Network calls need a connected phone or watch Wi-Fi. The Liftosaur key is stored as a Connect IQ app property, so protect and rotate it if exposed.

See [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md) for repository conventions and implementation notes.
