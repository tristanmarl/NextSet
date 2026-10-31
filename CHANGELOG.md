# Changelog

NextSet is an unofficial companion for Liftosaur. It is not made or endorsed by Liftosaur and needs Liftosaur Premium for API access.

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
