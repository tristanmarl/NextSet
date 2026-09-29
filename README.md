# NextSet

NextSet is an offline strength-training log for the Garmin Forerunner 965 (Connect IQ watch app, version 1.0.0). It logs sets with button-only navigation and records a Garmin Strength activity while you train. No phone connection is needed.

## Features

- Routines: Upper and Lower are built in. Create, rename, and delete routines (up to 8, at least one kept), with up to 12 exercises and 60 sets per routine. Edit sets, rep range, starting load, load increment, and rest per exercise; reorder, replace, and remove exercises. Exercises come from the Garmin exercise list (category browser, plus Recent and Used shortcuts) with weight, assistance, bodyweight, or timed tracking.
- Workout: one press logs a set; UP/DOWN adjusts reps and the load can be edited. Sets are prefilled from your last performance. A rest timer vibrates when rest ends, and timed sets have their own timer. You can correct or delete the last set, add a set, skip or replace an exercise for the day, then finish (or cancel) the workout.
- Safety: workout state is checkpointed to storage, so a workout survives leaving the app or a crash and resumes on the next launch.
- History: the last four finished workouts, with per-set details.
- Garmin activity: a Strength activity is recorded for the workout and saved when it finishes. Leaving the app saves the segment so far; reopening starts a new recording.
- Settings: default rest for new exercises, vibration on or off.

## Build, test, package

Install Connect IQ SDK 9.2.0 and put its `bin` directory on `PATH`. Every `monkeyc` call needs the developer key (keep it out of the repository):

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# Debug build for the simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Unit tests (the runner may exit 1 even when every test passes; read the summary)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t

# Release sideload build and store package
monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet-release.prg -y "$KEY"
monkeyc -e -r -f monkey.jungle -o bin/NextSet.iq -y "$KEY"
```

See [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) for details.

## Sideload

Connect the watch by USB and copy `bin/NextSet-release.prg` to `GARMIN/APPS/`, renamed to `NextSet.prg`. Sideloaded builds must be signed with the same key each time. The first install of a build signed with a new key needs the old NextSet removed first.

## Known limitations

- The recorded FIT file has no per-exercise or per-set rows. Set details stay in NextSet's own history.
- How the activity appears in Garmin Connect (activity type, duration, heart rate, exercise names) has not been verified on a physical watch.
- Only the FR965 is supported, and device testing is still pending; see [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md).
- The simulator does not enforce the 32 KB storage limit per value. A routine config at the 8 x 12 limit can exceed it on a real watch; see [docs/STABILITY_AUDIT_PLAN.md](docs/STABILITY_AUDIT_PLAN.md).
