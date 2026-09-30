# Garmin strength activity and routine editor

Implementation plan, 2026-09-29. Keep the existing app ID and signing key so an
installed NextSet can update without losing its local data.

## Outcome

> Update 2026-09-30: the recording now uses sub-sport `GENERIC` (sport `TRAINING` unchanged). A/B sideload on a physical FR965: `STRENGTH_TRAINING` shows the native "Set 1" screen for a few seconds at start (also when `createField` precedes `session.start`); `GENERIC` does not, and Garmin Connect still shows it as Strength Training. The text below describes the original plan.

- Finishing a NextSet workout records a Garmin FIT **Activity** with sport
  `TRAINING` and sub-sport `STRENGTH_TRAINING`. Verify that it appears as Strength
  in the FR965 activity history and in Garmin Connect after sync.
- Upper and Lower remain the initial routines. Between workouts, their ordered
  exercise lists can be edited: add, replace, remove, and move entries. Existing
  set count, reps, load, duration, and rest editing remains available.
- The picker contains a bundled snapshot of Garmin's published exercise
  catalog, with category and exercise selection. The app works without a phone
  or network connection. Every selected entry retains its Garmin category and
  exercise code in the routine and completed session.
- Existing local sessions, history, numeric overrides, and last-performance
  prefills survive the upgrade.

An Activity file is a completed recording. A FIT Workout file is a separate
planned workout; this task does not require NextSet routines to appear in
Garmin's native planned-workout list. The documented Connect IQ recorder can
start, stop, save, and add laps, while FIT Contributor writes developer fields
on session/lap/record messages. It does not document writing native strength
`set` messages. Treat native exercise-by-exercise rendering in Garmin Connect
as a feasibility question. Do not describe custom fields or laps as native
Garmin strength sets without observing them on a device and in Connect.

## Sources and present constraints

- Garmin Connect publishes `https://connect.garmin.com/web-data/exercises/Exercises.json`.
  The 2026-09-29 snapshot contains 47 categories and 1,531 exercises; the raw
  download SHA-256 is
  `3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c`.
  Pin a generated compact snapshot and record its source/date. The catalog may
  change; Garmin Connect's string codes are not necessarily FIT numeric IDs.
- `Catalog` currently loads 15 seed exercises in one resource and validates at
  most 32. Keep the large Garmin picker in separate, category-sized resources
  or generated code, loading only the viewed portion. Cap the number of menu
  items per page; the largest Garmin category has 131 entries.
- Current limits are 12 entries per routine, 10 sets per entry, and 60 planned
  sets per workout. Check these before each edit and before saving config.
- Config is schema version 1 with numeric template overrides; `Store` writes
  two generations. Session snapshots and last-performance data use stable
  `exerciseId` values. Preserve the original IDs for the 15 seeded movements.
- `manifest.xml` has no Fit permission and there is no recorder. Add only the
  permissions actually used. `ActivityRecording` supports watch apps and
  `TRAINING` / `STRENGTH_TRAINING` and requires `Fit` permission.

Garmin references:
[ActivityRecording](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html),
[recording session](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html),
[FIT Contributor](https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html),
[FIT Activity](https://developer.garmin.com/fit/articles/file-types/activity.html),
[FIT Workout](https://developer.garmin.com/fit/articles/file-types/workout.html).

## Initial Garmin mappings

Keep the familiar NextSet label when Garmin has only an approximate exercise.
Store the Garmin category/code alongside it, and show the Garmin choice in the
editor so the approximation is visible and can be replaced. The table is a
starting set of choices from the published catalog, not a claim that Garmin
recognizes the machine variant exactly.

| Existing label | Garmin category.exercise | Match |
| --- | --- | --- |
| Seated Row Machine | `ROW.SEATED_CABLE_ROW` | approximate |
| Machine Chest Press | `BENCH_PRESS.BENCH_PRESS` | approximate |
| Reverse Pec Deck | `FLYE.INCLINE_REVERSE_FLYE` | approximate |
| Machine Shoulder Press | `SHOULDER_PRESS.SMITH_MACHINE_OVERHEAD_PRESS` | approximate |
| Assisted Pull-up | `PULL_UP.BAND_ASSISTED_PULL_UP` | approximate |
| Assisted Dip | `TRICEPS_EXTENSION.BODY_WEIGHT_DIP` | approximate |
| Machine Lateral Raise | `LATERAL_RAISE.SEATED_LATERAL_RAISE` | approximate |
| Machine Preacher Curl | `CURL.PREACHER_CURL_WITH_CABLE` | approximate |
| Leg Press | `SQUAT.LEG_PRESS` | exact |
| Lying Leg Curl | `LEG_CURL.WEIGHTED_LEG_CURL` | approximate |
| Single-leg Machine Hip Thrust | `HIP_RAISE.WEIGHTED_SINGLE_LEG_HIP_RAISE_WITH_FOOT_ON_BENCH` | approximate |
| Leg Extension | `BANDED_EXERCISES.LEG_EXTENSION` | approximate |
| Hip Abduction Machine | `HIP_STABILITY.STANDING_HIP_ABDUCTION` | approximate |
| Hyperextension | `HYPEREXTENSION.HYPEREXTENSION` | exact |
| Dead Bug | `HIP_STABILITY.DEAD_BUG` | exact |

## Build sequence

1. **Prove the recorder path.** Add a small `ActivityRecording.Session` wrapper
   and Fit permission. Start with an uninterrupted workout, stop and save it on
   successful NextSet completion, and discard it on explicit cancel. Check
   return values and keep local save errors visible. Use `TRAINING` and
   `STRENGTH_TRAINING`; do not claim HR, calories, training effect, or native
   sets before inspecting the FIT and Garmin Connect result. Investigate
   pause/resume, app exit, and relaunch. Save a controlled partial segment if a
   single resumed recording is unsupported; never silently lose recorded data.
2. **Bundle the Garmin picker.** Generate a compact, reproducible offline
   catalog from the pinned Garmin JSON: category, exercise code, readable name,
   and useful `isBodyWeight` metadata. Avoid bundling unused muscle metadata.
   Provide category pages and exercise pages that work with buttons and touch.
   Measure compiled size and free memory before and after browsing the largest
   category. Keep all 1,531 entries reachable.
3. **Make the two routines editable.** Move Upper and Lower to a versioned,
   persisted ordered entry list. Migrate v1 numeric overrides into the v2
   entries without dropping them. Keep old active sessions and history
   readable. Use stable new IDs for added Garmin exercises; changing an entry
   to a different exercise must not reuse the previous exercise's prefill.
   Store only selected entry data in config, not the whole Garmin catalog.
4. **Expose routine editing.** Home menu -> Upper/Lower setup -> ordered list
   with Add exercise. Selecting an entry offers its existing numeric fields
   plus Replace, Move up, Move down, and Remove. Add/replace opens the category
   picker; then choose tracking type (weight, assistance, bodyweight, timed),
   using the Garmin metadata for a sensible default. Confirm Remove. Edits are
   disabled during an active or pending workout. Respect 12-entry and 60-set
   limits and handle failed config writes without changing the displayed list.
5. **Connect set data only as proven.** Keep Garmin category/code and completed
   reps/load/duration in NextSet's local session snapshot. If the public APIs
   and a device check show a useful FIT lap/developer-field representation,
   add it; document exactly how it renders. Native Garmin strength set rows
   require separate proof and must not be inferred from an Activity label.
6. **Validate and document.** Add focused checks for catalog reachability,
   mapping IDs, v1 migration, edit invariants, and recorder failure/retry
   behavior. Build with `-y /private/tmp/NextSetDeveloperKey.der` as required by
   `AGENTS.md`. Run simulator checks for both routines and inspect the produced
   FIT with Garmin's FIT tools. Update `DEVICE_TESTS.md` with observed results.
   The FR965 and Garmin Connect sync checks remain pending until performed on
   a physical watch and account.

## Completion checks

- Existing installed data survives the update; prior history and active
  workouts still open. The default Upper/Lower counts remain 19/17 sets unless
  the user edits them.
- Every Garmin catalog entry is reachable in the offline picker; selected
  category/code survives app restart and appears in the session snapshot.
- Add, replace, remove, move, and numeric editing persist, while invalid edits
  and failed writes leave the previous routine intact.
- An uninterrupted completed workout saves one local history entry and one
  Strength FIT recording, without duplicate recordings on retry. Cancel and
  failed FIT saves have explicit outcomes. Physical watch and Connect visibility
  are reported only after direct verification.

## Garmin Connect data: set laps and summary fields (branch `fit-set-laps`, 2026-09-29)

Connect IQ cannot write native strength set messages (only session, lap and record messages through FitContributor), so a real session showed an empty strength workout in Garmin Connect. This build writes the sets as lap and session developer fields instead.

Behaviour
- Each logged set (normal or timed) sets the lap fields, then calls `Session.addLap()`. Fields are not cleared immediately: Garmin documents that another `setData()` before the FIT write can replace the pending value. The firmware keeps at most one lap per second (0.2.1 FIT: lap start times were consecutive seconds and 2 of 19 sets were missing), so a set logged in the same second as the previous lap is queued in `StrengthRecorder` and written by `flush()` on the 1 s tick. `stop()` closes a final lap; before it `save()` blanks the lap fields (empty name, zeros) so it is not a copy of the last set.
- Before `save()` the session fields are set from the workout so far, so every saved segment carries totals for the workout up to that point.
- Corrections, set deletion and skipped exercises do not rewrite laps that are already recorded; the lap table shows the set as it was logged. Rest time lands in the lap of the next set.
- Any FitContributor exception is swallowed; logging a set never depends on it. Fields are created once per `ActivityRecording.Session` in `StrengthRecorder.start()`, so a new segment after an app restart gets its own fields.

Fields (ids match `resources/fitcontributions/fitcontributions.xml`; labels are in `resources/strings/strings.xml`)

| id | Message | Name | Type | Bytes | Meaning |
| --- | --- | --- | --- | --- | --- |
| 0 | lap | exercise | STRING, count 65 | 65 | Exercise name, at most 64 bytes plus terminator (names are validated to 64 bytes and truncated on whole characters otherwise) |
| 1 | lap | set | UINT8 | 1 | Set number within the exercise, from 1 |
| 2 | lap | reps | UINT16 | 2 | Reps; 0 for timed sets |
| 3 | lap | weight_kg | FLOAT | 4 | kg; negative for assistance exercises (the assistance offset), 0 for bodyweight and timed |
| 4 | lap | duration_s | UINT16 | 2 | Seconds for timed sets; 0 otherwise |
| 9 | lap | active_s | UINT16 | 2 | Set time in seconds (0.2.4): start press to log press for non-timed sets, measured duration for timed sets; 0 when the set was logged without a start press (unknown) |
| 10 | lap | garmin_category | STRING, count 24 | 24 | Garmin exercise category (0.2.5), e.g. `ROW`; longest catalog category is 18 bytes; `""` when the exercise has no Garmin mapping |
| 11 | lap | garmin_code | STRING, count 65 | 65 | Garmin exercise code (0.2.5), at most 64 bytes plus terminator; `""` for group-only exercises or no mapping |
| 12 | lap | void | UINT8 | 1 | 1 on the lap that retracts an undone set, else 0 (0.2.5); no `fitContributions` entry, like ids 10 and 11 |
| 5 | session | total_sets | UINT16 | 2 | Completed sets |
| 6 | session | volume_kg | FLOAT | 4 | Sum of weight x reps over weight exercises (assistance and bodyweight excluded); shown with precision 0 |
| 7 | session | exercises | UINT8 | 1 | Exercises with at least one completed set |
| 8 | session | nextset_version | STRING, count 8 | 8 | App version (string resource `AppVersion`; keep equal to `manifest.xml`) |

Limits from the `createField` docs: apps get 256 bytes per message type (lap fields use 166, session fields 15); field names need at least 64 bytes and units at least 16. The `Fit` permission is not enough for `FitContributor`; `manifest.xml` now also declares `FitContributor` (the compiler requires it).

Corrections and undo (0.2.5): after a successful correction of a completed set the controller records another lap for that set with the corrected values (`void` 0); after an undo it records a lap with the removed set's name, set number and values with `void` 1. Both use the same queue as normal set laps. The closing lap blanks `void` to 0. `sync.py` groups laps by (exercise name, set), keeps the last lap per key, drops keys whose last lap has `void` 1 and sorts the sets by the kept lap's start time; REST entries come from the existing per-lap logic (lap start to set start), so a correction lap, which is short, yields no rest. Old FITs without `void` behave as before except last-wins. Limit: two laps written within the same second right before save can still collapse into one lap (firmware keeps one lap per second), so a correction or undo logged in the same second as the final save may be lost.

Verification so far: unit tests cover the lap payload and summary calculation. A simulator probe created all nine fields, set maximum-length values, closed laps and saved without exceptions. The simulator's FIT file could not be located or parsed, so field values in the file are not verified. Garmin Connect does not render Connect IQ developer fields for a sideloaded app; the app must be approved and published in the Connect IQ store for those fields to display. The FIT lap and summary values still need inspection on a physical watch (see `docs/DEVICE_TESTS.md`).

Activity type (2026-09-29, Connect web imports of a patched copy of a 0.2.1 beta FIT): sub sport generic still showed as Strength Training with no set breakdown; Training/Cardio showed as Cardio; sport Generic showed as Other with a Laps tab that stayed empty, also with laps stretched to 1.5-2.5 min. No tested type shows the lap developer fields, so the activity stays Strength Training.

Explicit set start (0.2.4): on the Exercise screen of a non-timed exercise the first START stores `setRun = {entryId, slot, startedAt}` in the session (validated by `Model.validSetRun`, optional so older sessions stay valid) and ends any running or expired rest; the screen shows `SET m:ss` and the cue `START log`. The second START logs the set as before, stores `activeSec = completedAt - startedAt` in the completed set and clears `setRun`. BACK keeps the started set running (like a paused-but-timing set); starting a set on another slot or exercise replaces it, starting a timed set clears it, and undo clears it. `SET m:ss` shows only while the run matches the exercise and its next slot. A timed run still blocks starting a plain set. Switching exercise (BACK), finishing, aborting, closing the exercise, replacing it or adding an alternative clear `setRun`. There is no workout pause any more (0.2.6 also drops the legacy paused-session recovery); a running set otherwise survives an app restart and keeps counting wall-clock time. Menu, correction or any other logging without a start has `activeSec` 0 (unknown). `tools/connect-sets/sync.py` uses lap `active_s` as the set duration when it is at least 3 s, else its `ACTIVE_SEC` fallback (older FITs have no such field).

Per-exercise summary lines (0.2.3 draft, removed): twelve 20-byte `Ex N` session string fields fit the 256-byte budget but forced exercise names to be cut to a few characters, which was not acceptable; removed before release.

## Exercise codes and Connect validation (0.2.5)

- **Source of truth:** the FIT profile of Garmin's `garmin-fit-sdk` 21.217.0 (PyPI). Connect's exerciseSets API validates `category`/`name` against its `<category>_exercise_name` enums and rejected `BENCH_PRESS`/`BENCH_PRESS`.
- **Group-only rule:** a catalog or seed exercise whose code is not a valid enum value (generic code equal to its category, or names missing from the profile such as `ruck_*`) keeps its category and has `garminCode` null. Connect then shows the exercise under its category group only, not a specific exercise. Connect's `_3_way...` codes are normalised to the profile spelling `3_way...`. Result: 1494 valid, 37 group-only.
- **Snapshot:** the 2026-09-29 `Exercises.json` input is no longer available locally, so `resources/data/garmin.xml` was revalidated in place (`generate_garmin_catalog.py --revalidate`; only `code` fields changed) and copied to `private/resources/data/garmin.xml`. Exercise ids are unchanged.
- **Seeds and sync:** `generate_garmin_catalog.py --seeds` fails on an invalid seed code and writes `tools/connect-sets/exercises.json`; `sync.py` validates against the same pinned profile and falls back to name None / UNKNOWN.
- **Stored routines:** `garminCode` is only displayed on the watch, never sent to Connect (the sync job maps exercise names via `exercises.json`), so old stored codes need no migration. From 0.2.5 the session exercise snapshot carries `garminCategory`/`garminCode` (optional strings in `Model.validStoredSession`) and every lap records them as fields 10 and 11; `sync.py` uses them when `garmin_category` is non-empty and falls back to `exercises.json` by name for older FITs. Fields 10 and 11 have no `fitContributions` entry (machine data, not for display).
- The picker labels group-only entries "Group only in Connect". Which sets Connect actually renders is still unverified.

## Compact catalog (0.2.6)

The catalog was 186 KB of per-row JSON (`{"id","name","category","code","isBodyWeight"}`, 1,531 rows). 0.2.6 stores one string per category, `Garmin00..46`, and one string of category codes in `GarminCategories`. Entries are comma separated: `CODE`, `CODE*` (bodyweight, 378 entries) or `CODE!` (Connect knows only the category; FIT code null, 37 entries, `CODE` is then Connect's original code). Example, `Garmin02` (Bench Press): `ALTERNATING_DUMBBELL_CHEST_PRESS,...,BARBELL_BENCH_PRESS,...,BENCH_PRESS!,...`; `Garmin29` (Push Up): `ALTERNATING_HANDS_MEDICINE_BALL_PUSH_UP*,...,BICEPS_PUSH_UP,...`.

- **Name:** title case of CODE with `_` as space and leading underscores dropped (`3_WAY_CALF_RAISE` -> `3 Way Calf Raise`); it reproduces every previous name (the converter asserts this; nine names lost a stray leading space).
- **Id:** `g<NN>-<slug>`: NN is the two-digit category index, slug is the lowercase code with `-` for `_`. A slug longer than 36 characters keeps its first 16 and last 20 so the id fits `Model.validId` (40 bytes); plain truncation collided in HIP_RAISE. `generate_garmin_catalog.py` asserts uniqueness and validity and `testGarminIdsUniqueAndValid` checks the loaded catalog. The category index is part of the id, so adding a category before the last one shifts ids: regenerate deliberately.
- **Old ids (`g-<12 hex>`):** no migration. Stored routine entries, `recent` and last-performance keep working through their stored name/category/code (`exerciseForEntry` only refreshes new-style ids); picking the same exercise again creates a new id, so its last-performance prefill starts empty.
- **Removed in 0.2.6:** v1/v2 config migration (an older schema starts from defaults), legacy paused-session recovery (status `paused` is no longer a valid stored session), `templateTotalSets`, `setElapsed`, `hasRest`.
- **Converted** from the old catalog with `--convert` (the 37 category-only entries need Connect's original codes from `git show 513e7cb^:resources/data/garmin.xml`). Regeneration from the pinned snapshot uses the same writer.
