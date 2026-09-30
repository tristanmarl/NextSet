# FIT set breakdown in Garmin Connect (B + G) — plan, 2026-09-29

## Evidence (physical FR965, beta 0.2.1, `2026-09-29-21-11-22.fit`)

- Session developer fields render in Garmin Connect, including the STRING field `nextset_version`
  ("NextSet version 0.2.1"). So session-level string fields display.
- Lap developer fields are in the FIT and correct (exercise, set, reps, weight incl. -30 kg
  assistance, duration), but Connect shows no per-set breakdown for a
  `SPORT_TRAINING` / `SUB_SPORT_STRENGTH_TRAINING` activity.
- Only 16 distinct sets appear in 17 laps while the session summary says 19 sets
  (Machine Lateral Raise starts at set 2, Machine Shoulder Press has only set 1). Sets were logged
  <1 s apart in a test run. The last lap repeats the final set (lap closed at save).
- Connect showed volume as "65256 kg" per the user; the FIT holds 6525.0 (precision 1).
  Probably a rendering or reporting artifact of the decimal.
- Connect IQ cannot write native FIT `set` messages; that is out of scope.

## B. Per-exercise text lines in the session summary — DROPPED

Implemented, then removed: at 20 bytes per line the exercise names were cut too short to be useful.

### Original proposal

Add session STRING fields, one per exercise in session order, each labelled "Ex 1" … "Ex 12"
(sessions hold at most `Model.MAX_ENTRIES` = 12 exercises, validated in `Model`).

- Budget: 256 bytes per message type per app. Session already uses 15 bytes
  (total_sets 2, volume 4, exercises 1, version 8). 12 fields × `:count => 20` = 240 → 255 total.
  **First verify** in the SDK `createField` docs (`$SDK/doc` or developer.garmin.com) that
  21 total fields per app is allowed. If there is a field-count limit that 21 exceeds, fall back to
  6 fields × 40 bytes labelled "Sets 1" … "Sets 6", packing exercise lines greedily with " · ".
- Field ids 9–20, `displayInActivitySummary="true"`, `sortOrder` after the existing ones, labels via
  new strings `FitEx1` … `FitEx12`.
- Line format (pure function in `SessionLogic`, e.g. `fitExerciseLines(session) as Array<String>`,
  only exercises with ≥1 completed set, max 19 bytes each so the terminator fits):
  - weight / assistance, same load on all sets: `Row 55kg 9/9/9`; assistance `Dip -30kg 10/10`.
  - mixed loads: `Row 9@55 8@60` (kg omitted per set).
  - bodyweight: `Push-up 15/12/10`.
  - timed: `Plank 45s/40s`.
  - Load formatting: drop `.0`, keep up to 2 decimals (load100 / 100).
  - Build the numbers suffix first; truncate the **name** (on whole characters, reuse
    `SessionLogic.truncateBytes`) to fit the remaining bytes. If the suffix alone exceeds the
    budget, truncate the whole line.
- Written in `StrengthRecorder.setSummaryFields` from the summary dictionary (extend
  `SessionLogic.fitSummary` to include `"lines"`). Unused fields are left unset.
- Also set volume `precision="0"` to avoid the odd "65256" rendering (whole kg is enough).

## G. Optional "Training" activity type — DROPPED

Connect imports of patched FITs (generic sub sport, Cardio, sport Generic with stretched laps) showed no lap developer fields; the user decided the activity type stays Strength. Not implemented.

### Original proposal

- New optional boolean setting `fitLapsMode` in `config.settings` (absent ⇒ `false`), following the
  `vibrationEnabled` pattern exactly: default in `SessionController` (lines ~82, ~200–207),
  accessor + setter + toggle, `Store` settings validator (~line 88), Settings menu item
  "Activity: Strength" / "Activity: Training+laps" in `Navigator.settings()` and handler in
  `SettingsMenuDelegate` (~line 783). No schema version bump (optional field, old builds ignore it —
  verify `Store`/`Model` accept unknown keys for the older build; if not, note it).
- `StrengthRecorder.start(name, lapsMode)`: `:subSport` is `SUB_SPORT_GENERIC` when `lapsMode`,
  else `SUB_SPORT_STRENGTH_TRAINING`; sport stays `SPORT_TRAINING`. Read the setting at every
  `_recorder.start` call site (SessionController ~1147 and ~1670). Changing the setting mid-workout
  only affects the next recording segment; that is fine.
- Default stays Strength until a Connect import proves the lap table renders
  (test file: patched copy with sub_sport 0, see DEVICE_TESTS).

## Lap fixes (both B and G depend on complete laps)

1. **Dropped sets.** Investigate before fixing: decode lap `start_time` (field 2), `timestamp`
   (253) and `total_elapsed_time` (7) from the FIT. Decoder and file:
   `/private/tmp/claude-501/-Users-manuelarebel-Projects-NextSet/7ebc7edd-98a1-4b18-8868-292d44148df0/scratchpad/fitdump2.py`
   and `.../scratchpad/dl/2026-09-29-21-11-22.fit`. Hypothesis: when two sets are logged before
   the firmware writes the previous lap (same second), the second `setData` overwrites the first
   lap's pending values, or the firmware merges laps. Also confirm every set-completion path calls
   `recordSetLap` (`completeSet` ~1737, `completeTimed` ~1256; check correction/"complete all"/
   undo-redo paths too). Fix at the root; if it is a firmware same-second limitation, document it and
   consider deferring the lap (queue the payload and `addLap` on the next 1 s tick) rather than
   guessing.
2. **Trailing duplicate lap.** In `StrengthRecorder.save`, before stopping, set lap fields to an
   empty name and zeros (set 0) so the closing lap is recognisable as "rest/end" instead of a
   repeated set. Clearing is safe here because the previous lap was written long before save.

## Tests (tests/WorkoutTests.mc, next to the existing lapPayload/fitSummary tests)

- `fitExerciseLines`: uniform weight, mixed loads, assistance negative, bodyweight, timed,
  long name truncation within 19 bytes (multi-byte name), exercise with 0 sets omitted, 12 exercises.
- Setting default/validation if logic lands in a pure module.

## Resources

Both resource trees must change identically: `resources/` (public) and `private/resources/`
(beta, used by `monkey.beta.jungle`): `fitcontributions/fitcontributions.xml` and
`strings/strings.xml`. Bump version to 0.2.3 in `manifest.xml`, `manifest.beta.xml` and the
`AppVersion` string in both strings files; widen the `nextset_version` count only if needed.

## Verification

- `monkeyc` app build (public and beta jungle) and unit tests; report the PASS/FAIL summary.
- Update `StrengthRecorder` header comment (byte budget) and `docs/GARMIN_STRENGTH_PLAN.md` field
  table; add PENDING device checks to `docs/DEVICE_TESTS.md`: Connect shows Ex lines; Training mode
  shows lap table; all sets appear as laps with fast logging; no duplicate trailing set.
- Do not claim Connect rendering; it requires a store beta upload and a physical workout.
