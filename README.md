# NextSet

NextSet is a Connect IQ watch app for logging strength training with buttons only, no phone needed. The primary device is the Garmin Forerunner 965 (`fr965`). The public package also targets the fēnix 8 47 mm, fēnix 8 Pro 47 mm, fēnix 9 47 mm, fēnix 9 Pro 47 mm and fēnix 9 Pro 51 mm (see `manifest.xml`); their UI has been checked only where [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md) says so. Current version: 0.2.6. Minimum API 5.2.0.

## Features

- **Routines.** Create, rename and delete routines and edit them on the watch: exercises, sets, rep range, starting load, load increment and rest per exercise. Exercises come from a bundled offline Garmin exercise catalog (47 categories, 1,531 exercises, about 38 KB of resources) via a category picker. Entries whose exact Garmin exercise code is not valid are marked "Category only" (Connect shows them under the category group only). Production installs start with one empty routine.
- **Workout flow.** On a weight exercise, START starts the set (a `SET m:ss` timer counts up) and the next START logs it and starts the rest timer, which vibrates when rest ends. Timed sets have their own timer. UP/DOWN adjusts reps and the load can be edited. You can correct or undo the last set, add a set, and skip or replace an exercise for the day. Sets are prefilled from your last performance for that exercise.
- **Local history.** Recent finished workouts with per-set details are kept in watch storage. Workout state is checkpointed, so a workout survives leaving the app or a crash and resumes on the next launch.
- **Settings.** Default rest for new exercises, vibration on or off.

## Garmin recording

A FIT activity is recorded through `ActivityRecording` as sport Training / sub-sport Generic. Garmin Connect still shows it as Strength Training; Generic avoids the firmware's native "Set 1" overlay at start (A/B-tested on an FR965, 2026-09-30). Details are in [docs/GARMIN_STRENGTH_PLAN.md](docs/GARMIN_STRENGTH_PLAN.md).

Each logged set is one FIT lap with developer fields:

| Lap field | Meaning |
| --- | --- |
| `exercise`, `set`, `reps` | Exercise name, set number, reps (0 for timed) |
| `weight_kg`, `duration_s` | Load (negative for assistance) and timed-set seconds |
| `active_s` | Start-to-log seconds (measured duration for timed sets, 0 if no start press) |
| `garmin_category`, `garmin_code` | Garmin exercise category and code (code empty for category-only exercises) |
| `void` | 1 on the lap that retracts an undone set; corrections add a lap with the new values |

Session summary fields: `total_sets`, `volume_kg`, `exercises`, `nextset_version`. Leaving the app saves the segment so far, and reopening starts a new recording.

### Archive and Liftosaur sync

Connect IQ cannot write native strength sets, and Connect does not display developer fields from a sideloaded build. The optional job in [tools/connect-sets](tools/connect-sets/README.md) runs on a home server (read-only against Garmin), reads these laps from your synced activities, archives every workout (JSON + SQLite) and can log it into the matching [Liftosaur](https://www.liftosaur.com) workout via its REST API (see docs/LIFTOSAUR_PLAN.md). It writes nothing to Garmin Connect.

## Build and test

Install Connect IQ SDK 9.2.0 and put its `bin` directory on `PATH`. Every `monkeyc` call needs the developer key, including simulator and test builds (SDK 9.2.0 exits 101 without it).

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# Simulator build and run
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Unit tests (without -t it launches as an app and hangs)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t
monkeydo bin/NextSet-tests.prg fr965 -t testSeedCatalog   # single test
```

`monkeydo` may exit 1 even when every test passes; read the PASS/FAIL summary. There is no linter; the compiler's type checking is the check.

### Packages

```sh
# Public package (all manifest.xml devices, no personal routines)
monkeyc -e -r -f monkey.jungle -o bin/NextSet-public.iq -y "$KEY"

# Private FR965-only beta (Upper/Lower seeds, separate app ID)
monkeyc -e -r -f monkey.beta.jungle -o bin/NextSet-private-beta.iq -y "$KEY"

# FR965 sideload builds
monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet-release.prg -y "$KEY"        # public resources
monkeyc -f monkey.local.jungle -d fr965 -o bin/NextSet-local.prg -y "$KEY"       # private seeds
```

To sideload, copy the `.prg` to `GARMIN/APPS` on the watch over USB. Never use the private jungles for the public `.iq`; see [docs/PRIVATE_ROUTINE_RELEASE_PLAN.md](docs/PRIVATE_ROUTINE_RELEASE_PLAN.md).

### Signing key

The key is `~/.garmin-keys/NextSetDeveloperKey.der` (PEM beside it). Keep it outside the repository, never commit, upload or package either file, and keep an offline backup. Reuse the same key for every build of an installed app; a build signed with a different key requires reinstalling on the watch.

### Garmin catalog generator

`scripts/generate_garmin_catalog.py` builds `resources/data/garmin.xml` from a pinned Garmin Connect exercise snapshot (the input must match the SHA-256 in the script). Codes are validated against the FIT profile of `garmin-fit-sdk==21.217.0` (`pip install`); invalid codes are marked `!` (category only). Format: one string per category, entries `CODE`, `CODE*` (bodyweight) or `CODE!` (category only); names and ids are derived at runtime (see CLAUDE.md).

```sh
python3 scripts/generate_garmin_catalog.py /private/tmp/NextSet-Garmin-Exercises.json resources/data/garmin.xml
python3 scripts/generate_garmin_catalog.py --convert old.xml original.xml resources/data/garmin.xml  # one-off: old per-row format -> compact
python3 scripts/generate_garmin_catalog.py --seeds resources/data/seeds.xml private/resources/data/seeds.xml  # validate seed codes
```

Copy a regenerated catalog to `private/resources/data/garmin.xml` too.

## Repository layout

- `source/`: pure logic (`SessionLogic`, `WorkoutClock`, `RestClock`, `LastPerformance`, `Model`, `Catalog`), `Store` (two-generation storage), `SessionController` (state owner), `StrengthRecorder` (FIT), `NextSetApp`.
- `source/ui/`: views, menu delegates, `Navigator`.
- `tests/`: unit tests for the pure modules, included via `tests.jungle`.
- `resources/`: public strings, drawables, seeds (no routines), Garmin catalog, FIT contribution fields.
- `private/resources/`: same plus the private Upper/Lower seeds; used by beta, local and test builds only.
- `scripts/`: catalog generator.
- `tools/connect-sets/`: optional NextSet archive + Liftosaur sync job (Docker, Python; directory name is historical).
- `docs/`: toolchain, device evidence, plans. See also `AGENTS.md` and `CLAUDE.md`.

## Status and limitations

Verified on a physical FR965 ([docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md)): a short start, log and save path; a saved FIT with sport Training (Strength sub-sport at that time); fixes for the finish-timer callback crash and workout-start/save watchdog trips; the Generic sub-sport avoiding the "Set 1" overlay, with Connect showing Strength Training; Garmin Connect showing the session summary fields for the store beta; native exercise sets written by the NAS job appearing in Connect (2026-09-30).

Simulator only: layout of Home, overview and exercise screens; persistence across relaunch; unit tests pass in the simulator. The fēnix targets compile; only the fēnix 9 Pro 51 mm empty starter routine was checked in the simulator, with no physical check.

Not yet verified (marked PENDING in DEVICE_TESTS.md): the 0.2.3 to 0.2.6 changes on a watch (lap queue, `active_s`, category/code fields, correction and undo laps, "Category only" label, upgrade over 0.2.4), the full acceptance list (long sessions, touch-off, pause, recovery), watch history label and training load for a Generic recording, and Garmin Connect rendering of the lap developer fields.

Known limits: lap values are recorded when a set is logged, so corrections and undo add extra laps instead of rewriting; the firmware keeps at most one lap per second, so simultaneous laps are queued and may collapse if written in the final second before save. NextSet's own history is the complete record. The simulator does not enforce the 32 KB per-value storage limit, so each routine is stored separately and sized by estimate.
