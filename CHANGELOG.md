# Changelog

NextSet is an unofficial companion for Liftosaur. It is not made or endorsed by Liftosaur and needs Liftosaur Premium for API access.

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
