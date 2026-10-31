# Changelog

NextSet is an unofficial companion for Liftosaur. It is not made or endorsed by Liftosaur and needs Liftosaur Premium for API access.

## 0.4.2
- **Finish is the last item of the menu.** The "Workout…" submenu and "Cancel workout" are gone. Hold UP and choose **Finish workout** (last item): START saves, BACK asks Keep working or Discard, with the same fonts as the review. With no set logged the review still opens, so a workout can be discarded. BACK on the Overview opens the same review.
- **Change weight.** The first hold-UP item is now **Change weight** (**Change time** for a timed set, nothing for bodyweight). It opens the weight directly, yellow and underlined: UP/DOWN change it, START saves and closes, BACK closes without saving. **Edit last set** keeps the two-level editor. The set-screen hint reads "Hold UP: change weight".
- **Shorter exercise menu.** "Skip exercise" and "Replace exercise" are gone; follow the program, or finish the workout early.
- **The weight step is automatic: 2.5 kg or 5 lb.** The "Weight step" menu is gone (Liftosaur's data has no rounding value to follow). Routines synced before keep working: the old 1 kg step becomes 2.5 kg, and any step you set earlier is still applied.

## 0.4.1
- **Buttons only.** Every NextSet screen now ignores touch, so sweat or a brush against the screen can no longer select a weight with no way back. UP/DOWN on the set screen always change the reps (the duration for a timed set); START logs the set, one press per set as before.
- **New "Edit set" editor.** Hold UP and choose **Edit set** (the first item) for the next set, or **Edit last set** for the one before. The weight and reps are shown big and the selected one has a white frame: UP/DOWN pick a field, START enters it (yellow and underlined), UP/DOWN change it, START keeps it, BACK undoes that field. BACK from the choice saves and closes. Bodyweight sets edit reps only, timed sets the duration. "Change load" / "Change reps" are gone; the set screen shows the hint "Hold UP: edit set" once.
- **Overview uses the whole screen:** the exercise name, "Exercise 2/8", the sets done big ("2/3") and the next set ("55 kg × 9", in kg or lb), plus heart rate.
- **Easier to see set dots:** bigger, open sets have a light-gray outline, done sets are green, the current set is white with a ring. Exercises with more than six sets show "4/8" instead.
- **"Starting…", "Saving…" and "Cancelling…"** are short and wrap instead of being cut off ("Starting workout…" lost its end on small watches). After a failed save, START retries.

## 0.4.0
- **New screens.** Every workout screen keeps the same places: the exercise at the top, set dots below it, weight and reps as big numbers in the middle, heart rate at the bottom. Long exercise names wrap onto two lines instead of being cut off, and button help, capitals and "all is well" texts are gone (a check icon says it instead).
- **Rest you can read from the rack.** A blue ring runs around the screen with the time left, and the centre already shows the next set's weight, so you can load the bar or move the pin. The ring turns green in overtime.
- **Live heart rate** on the set and rest screens; the summary shows average and max.
- **Pounds.** Liftosaur accounts in lb now sync; weights show and upload in lb, with 1 / 2.5 / 5 / 10 lb steps.
- **Programs that ask for values.** Sets that log an RPE ask for it after the set, and exercises with prompted variables ask for each value after the last set, starting at the program's suggestion. One-sided timed sets now sync and record the left and the right hold.
- **Simpler finish.** "Finish workout" opens a short review: START saves, BACK asks Keep working or Discard. Discard, Delete set and the upload-queue confirmations work only with the buttons, never with a tap.
- **Vibrations told apart by length:** set logged short, 10 s before the rest ends medium, rest over long. The superset cue is two single buzzes (the FR965 ignored the old pattern).
- Overview, history, editors and Home were trimmed to what you need at a glance.

## 0.3.7
- **New app icon:** a T-rex with tiny arms gripping a barbell, in NextSet's own green. There is a 40 px version for watches with smaller launcher icons, and a new 500 px store icon.
- No changes to workouts, sync or uploads.

## 0.3.6
- **More watches:** NextSet now builds for 53 five-button Garmin watches on Connect IQ 5 or later. It no longer crashes on Home on MIP watches such as the Forerunner 255, which lack vector fonts.
- **Steadier during workouts:**
  - A rest that runs out no longer saves to storage in the same moment as its vibration. On 2026-10-29 that moment crashed the firmware.
  - The 30 s workout checkpoint now writes a small key instead of the whole session.
  - Exercise names in the Garmin activity are shortened to fit their field.
- **Editing load and reps:**
  - Hold UP for the menu. Its first item, "Change load" / "Change reps", switches the set screen between the two fields in place.
  - Fast presses step the load faster (x2 from the 4th press, x4 from the 8th).
  - The menu has "Edit last set" (load and reps together) and "Delete set N".
  - Holds other than UP were dropped, because on the Forerunner 965 they are firmware shortcuts.
- **Better Liftosaur uploads:** workouts are sent with their intervals, so Liftosaur records the real duration. A note is added only for substitutions or extra warmups.
