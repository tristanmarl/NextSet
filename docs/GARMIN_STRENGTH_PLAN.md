# Garmin strength activity and routine editor

Implementation plan, 2026-09-29. Keep the existing app ID and signing key so an
installed NextSet can update without losing its local data.

## Outcome

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
- Each logged set (normal or timed) closes one lap while the recording is active. The lap fields are set first, then `Session.addLap()` closes the lap (a lap field's value is written when the lap closes, so setting them afterwards would land in the next lap). Afterwards the lap fields are reset to empty/0 so the trailing lap (rest after the last set, or the time before the first set) does not repeat the previous set.
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
| 5 | session | total_sets | UINT16 | 2 | Completed sets |
| 6 | session | volume_kg | FLOAT | 4 | Sum of weight x reps over weight exercises (assistance and bodyweight excluded) |
| 7 | session | exercises | UINT8 | 1 | Exercises with at least one completed set |
| 8 | session | nextset_version | STRING, count 8 | 8 | App version (string resource `AppVersion`; keep equal to `manifest.xml`) |

Limits from the `createField` docs: apps get 256 bytes per message type (lap fields use 74, session fields 15); field names need at least 64 bytes and units at least 16. The `Fit` permission is not enough for `FitContributor`; `manifest.xml` now also declares `FitContributor` (the compiler requires it).

Verification so far: unit tests cover the lap payload and summary calculation. A simulator probe created all nine fields, set maximum-length values, closed laps and saved without exceptions. The simulator's FIT file could not be located or parsed, so field values in the file are not verified. Whether Garmin Connect shows the lap table and summary fields, and how it treats a strength activity's laps, is unverified until a real session is inspected (see `docs/DEVICE_TESTS.md`).
