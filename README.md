# NextSet

NextSet is an offline strength-training log for the Garmin Forerunner 965 (Connect IQ watch app, version 0.2.1, FR965 only). It logs sets with button-only navigation and records a Garmin Strength activity while you train. No phone connection is needed.

## Features

- Routines: Upper and Lower are built in. Create, rename, and delete routines (up to 8, at least one kept), with up to 12 exercises and 60 sets per routine. Edit sets, rep range, starting load, load increment, and rest per exercise; reorder, replace, and remove exercises. Exercises come from the Garmin exercise list (category browser, plus Recent and Used shortcuts) with weight, assistance, bodyweight, or timed tracking.
- Workout: one press logs a set; UP/DOWN adjusts reps and the load can be edited. Sets are prefilled from your last performance. A rest timer vibrates when rest ends, and timed sets have their own timer. You can correct or delete the last set, add a set, skip or replace an exercise for the day, then finish (or cancel) the workout.
- Safety: workout state is checkpointed to storage, so a workout survives leaving the app or a crash and resumes on the next launch.
- History: the last four finished workouts, with per-set details.
- Garmin activity: a Strength activity is recorded for the workout and saved when it finishes. Each logged set is also written as a lap with the exercise, set number, reps, weight and duration, and the activity summary carries total sets, volume and exercise count (Connect IQ developer fields; see docs/GARMIN_STRENGTH_PLAN.md). Leaving the app saves the segment so far; reopening starts a new recording.
- Settings: default rest for new exercises, vibration on or off.

## Install (sideload)

NextSet is distributed on GitHub only, as a `.prg` file attached to each release (`NextSet-<version>.prg`, for example `NextSet-0.2.1.prg`). It only supports the Forerunner 965.

1. Download the `.prg` from GitHub Releases.
2. Connect the FR965 to your computer by USB. On macOS use OpenMTP (or Android File Transfer); on Windows the watch shows up as a normal drive.
3. Copy the file to `GARMIN/APPS` on the watch.
4. Unplug the watch. NextSet appears in the apps list.
5. To update, copy the new file over the old one. Your routines and history stay on the watch.

## Build, test, release

Install Connect IQ SDK 9.2.0 and put its `bin` directory on `PATH`. Every `monkeyc` call needs the developer key (keep it out of the repository; reuse the same key for every release):

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# Debug build for the simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Unit tests (the runner may exit 1 even when every test passes; read the summary)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t

# Release build; publish it as the GitHub release asset NextSet-<version>.prg
monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet-release.prg -y "$KEY"
```

See [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) for details.

## Known limitations

- Connect IQ cannot write native strength set rows. Garmin Connect does not display developer fields from this sideloaded app, so its activity can look empty even when the FIT file contains set laps. Lap values are not rewritten when a set is corrected or deleted afterwards. NextSet's own history is the complete record.
- The 0.2.1 FIT lap and summary values have not yet been verified on a physical watch.
- Only the FR965 is supported, and device testing is still pending; see [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
- The simulator does not enforce the 32 KB storage limit per value, so size is checked by estimate; each routine is stored separately to stay under it (see [docs/STABILITY_AUDIT_PLAN.md](docs/STABILITY_AUDIT_PLAN.md)).
