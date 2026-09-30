# Routine editor crash and new routine plan

Plan, 2026-09-29. The watch reports an IQ! screen when opening **Edit Upper**, **Edit Lower**, or **Load increments**. Workout save and Garmin sync now work on the physical watch. Preserve its current app ID, signing key, saved routines, history, and activity recording behavior.

## What the current code does

- `Navigator.editTemplate()` gets the routine list once, then calls `SessionController.templateExercise()` for every entry. Each call runs `readConfig()`, which reads and validates the full saved configuration. Upper has eight entries and Lower has seven.
- `Navigator.editIncrements()` calls `numericConfigValue()` for every loadable seed exercise. That also runs `readConfig()` each time. The repeated storage reads, copies, and validation are a likely watchdog or memory cause shared by all three menu actions. This is a hypothesis until a simulator or device crash log confirms the failing stack.
- Only Upper and Lower can be edited from Home. `SessionController.saveRoutines()` rejects any routine count other than two, although `Model.MAX_TEMPLATES` is eight. There is no create or rename operation. Empty routines are valid in storage, but `Catalog.createSession()` rejects them when starting a workout.

## Target watch flow

`Home → MENU → Routines → Upper / Lower / custom routine / Create routine`

Selecting a routine opens its exercise list. **Create routine** opens Garmin's native text picker with a suggested name such as “Routine 3”; accepting it saves a blank routine and opens its editor with **Add exercise** prominent. Cancel creates nothing. The user can accept the suggested name without typing. An empty routine is shown as “Add an exercise” and cannot start a workout. BACK from the exercise editor returns to the routine list, then Home. Keep **Load increments** accessible from the Home menu; per-entry increments remain in each routine's exercise editor.

Garmin documents `WatchUi.TextPicker` and `TextPickerDelegate` for the Forerunner 965: [TextPicker](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/TextPicker.html), [TextPickerDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/TextPickerDelegate.html). Check the button flow in the FR965 simulator and on the watch.

## Implementation sequence for Luna 6 Max

1. **Confirm the crash path.** Reproduce each menu action with a persisted configuration in the FR965 simulator. Capture the exception or watchdog stack and memory/error output. Check the watch's Connect IQ log if available. Fix the cause shown by the stack; do not assume the earlier workout-save `Store.equal()` bug recurred.
2. **Build editor menus from one snapshot.** In `Navigator.editTemplate()`, use each already-loaded entry with `Catalog.exerciseForEntry()` instead of asking the controller to reload the configuration per row. Expose one read of increment overrides or an equivalent single controller snapshot for `editIncrements()`, then render all rows from it. Keep storage and catalog access bounded when opening either menu. Show a recoverable message if a saved entry cannot resolve instead of dereferencing null.
3. **Add routine creation to the existing config model.** Add `SessionController.createRoutine(name)` and accept 1–`Model.MAX_TEMPLATES` saved routines in `saveRoutines()`. Validate nonblank names within the existing 64-byte limit, unique routine IDs, routine count, and `Catalog.validRoutine()` before committing. Reuse the existing monotonic `routineNextEntrySeq` to allocate a stable custom routine ID and advance it only in the committed candidate; no new storage schema is needed. Save a new routine with `revision: 1` and `entries: []`. Leave existing Upper/Lower and their IDs intact. A failed write leaves the old list visible and reports the error.
4. **Wire one routine management path.** Replace the two fixed Home edit rows with a **Routines** menu listing all saved routines plus **Create routine**. Use `TextPicker` with a suggested unique name. On success, open `editTemplate(newId)`; on cancel, return to the list. Refresh the list/editor after add, replace, move, and remove without stacking stale menus. Keep the current Garmin category picker and exercise entry editor for adding exercises to the blank routine.
5. **Handle empty routines before recording.** Show “Add an exercise” and an Edit action for a selected empty routine. Do not offer it as a startable workout in `Navigator.templates()`; make `HomeDelegate` route START to its editor. In `startWorkout()`, validate that a session can be created before reserving a session ID or opening a FIT recording. Keep nonempty Upper/Lower and completed history behavior unchanged.
6. **Keep the routine limit usable.** Add a confirmed **Delete routine** action for custom routines, with at least Upper and Lower retained. Deleting a routine must not delete past history or an active workout snapshot. At eight routines, show a clear limit message instead of a selectable create action that fails silently.

## Completion checks

- All three reported menu actions open and can be used repeatedly without IQ!, including after a completed workout and app relaunch. Record the observed failure stack and the fixed path.
- A named blank routine survives relaunch, can accept Garmin catalog exercises, can be edited, and starts a Strength activity after it has at least one exercise. Canceling name entry or a failed save creates nothing.
- Existing Upper/Lower routines and prior local data survive an update. Creating, editing, and deleting custom routines preserve unrelated routines and history. Empty routines never consume a session ID or start recording.
- BACK works by buttons through Home → Routines → editor → exercise options → Garmin picker and returns to the current list without stale screens.
- Build the production `fr965` target with `-y /private/tmp/NextSetDeveloperKey.der` on the first attempt. Record simulator and physical-watch results separately in `docs/DEVICE_TESTS.md`; do not claim hardware acceptance from a simulator run.
