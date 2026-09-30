# NextSet workout-flow fixes

Implementation plan, 2026-09-29. This follows the read-only flow audit of the
current FR965 app. Preserve the existing app ID, signing key, stored workouts,
routine migration, and in-progress session data.

## Target flow

1. Home offers the two routines and makes an active workout unmistakable.
2. The overview shows overall progress and the next unfinished exercise. START
   opens its next set; UP/DOWN still allow any exercise and supersets.
3. The set screen keeps its large exercise, set, and load/reps display. START
   logs one set. Rest remains visible and skippable. The last set leads to a
   clear Finish / Keep working choice.
4. Workout actions include Pause, Skip current exercise for today, Swap for
   today, Finish, and Cancel. Pause stays inside the app and resumes the same
   FIT session. Explicit exit from an unfinished workout explains that the
   current FIT segment is saved and a later resume may make another activity.
5. Finish reports **NextSet log** and **Garmin activity** separately. A known
   Garmin save failure offers Retry while the handle exists or Save locally
   and exit. An ambiguous result is shown as Unknown without automatic retry.

## Implementation sequence

### 1. Make pause and exit reachable

- Make Home show Upper and Lower as direct choices when idle, and make Resume
  the primary choice when a workout exists. Keep History and Edit in MENU.
- Wire the existing `SessionController.pauseWorkout()` / `resumeWorkout()` to
  an explicit workout action and paused view. Keep the recorder handle in
  memory during an ordinary pause so completion saves one activity.
- Make BACK/MENU from overview and set screens lead to one predictable action
  menu. Include Resume, Save segment and exit, Finish, and Cancel only when
  their meaning is valid. Preserve the existing confirmation for Cancel.
- Show a brief consequence before exiting an unfinished workout. On app stop,
  retain the existing recoverable local workout and record the FIT segment
  outcome; never imply that resumed segments form one Garmin activity.

### 2. Make save outcomes truthful and durable

- Keep local archive and FIT outcome as separate states. A completed local log
  must not be labeled simply "Workout saved" when the Garmin save failed.
- When FIT `save()` returns false and the handle is still available, keep the
  user on a result screen with **Retry Garmin save** and **Keep local log and
  exit**. Discard/close the failed handle only after the latter choice. BACK
  must use an explicit choice too, not silently abandon retry.
- Persist `saved`, `failed`, or `unknown` in history. Show that result in both
  the completion summary and history detail. Preserve the no-duplicate rule:
  after a process loss during `save()`, mark Unknown and never retry blindly.
- Keep earlier local sessions and history readable; this should be a small
  additive status/UI change, not another storage-schema migration.

### 3. Repair routine-editor navigation

- Give the editor one setup root. Add/Replace/Move/Remove should refresh that
  root and BACK should return to Home once. Do not leave stale setup or entry
  menus underneath the refreshed view. Inspect all `pushView`, `popView`, and
  `switchToView` paths from the Home menu through the Garmin picker.
- Show failed add, replace, move, remove, and config saves as nonselectable
  feedback. Do not put an error message in a menu as an action row.
- Rename "Upper setup" / "Lower setup" to "Edit Upper" / "Edit Lower" and
  display each entry's set/reps or duration summary in the list.

### 4. Support gym-day changes without editing the routine

- Expose **Skip for today** for an unfinished exercise using the existing
  `closedEarly` session state. Keep its completed sets, if any.
- Expose **Swap for today** for an exercise with no completed sets or running
  timed set. Replace only its active-session snapshot, using the Garmin picker
  and the same tracking-type choice as setup; preserve order and make the new
  exercise's prefill use its own stable exercise ID. If sets are already done,
  keep those sets and offer Skip remaining plus Add alternative for today.
- Keep routine configuration unchanged. Respect 12 exercises, 10 sets each,
  and 60 planned sets, and commit the entire changed session before updating
  the UI. A failed write leaves the old session visible.
- Keep active-session actions discoverable from the overview and exercise
  screen; setup remains for permanent future edits.

### 5. Make the Garmin picker usable on a watch

- Add **Recent** and **Used in routines** before Browse categories. Persist
  only a short recent-ID list; continue to load category resources lazily so
  all 1,531 catalog choices remain reachable offline.
- Show readable Garmin names instead of raw category/code strings. Keep the
  familiar NextSet label for approximate seed mappings; expose the mapped
  Garmin name in the entry details. Remove the selectable "Garmin choice" row
  that currently has no action, or make it open Replace.
- Default a replacement to the prior entry's tracking type. For a new entry,
  suggest a type from available metadata and allow changing it. Keep the
  category/code in the local routine/session snapshot.
- Be explicit in the UI: selecting a Garmin catalog name currently improves
  NextSet's local mapping; the Connect IQ recorder does not write native
  exercise/set rows to the Garmin FIT activity.

### 6. Finish the small workout-screen and editor details

- Add a compact overall progress cue to the overview (`6/19 sets`, exercise
  position) and a discoverable action hint without shrinking the main set
  value. Keep button-only navigation and long-name wrapping.
- Keep the exercise screen's existing visual order for a working set:
  exercise name, set number, large load/reps or timed value, then previous
  performance. During rest, make the remaining countdown and Skip action
  prominent while the next set value stays visible; collapse notes/messages
  before allowing them to push rest off the round display. For timed sets,
  distinguish target duration from elapsed time and keep Start/Finish/Resume
  cues unambiguous. Inspect weight, assistance, bodyweight, timed, resting,
  long-name, and completed states on the FR965 screen before claiming visual
  acceptance.
- Make weight increment a value of each editable routine entry, including
  newly added Garmin exercises. `NumberEditView` must obtain the entry from
  current saved routines, not `Catalog.template()` seeds. Use the same step in
  setup and live set editing.
- Distinguish invalid value, routine limit, and storage failure where the
  current number editor uses one generic error. Keep existing data on failure.

## Code and data touch points

- `source/NextSetApp.mc`, `source/ui/Navigator.mc`, `OverviewView.mc`, `ExerciseView.mc`,
  `SummaryView.mc`, `HistoryView.mc`, `NumberEditView.mc`: paths and copy.
- `source/SessionController.mc`, `SessionLogic.mc`, `Catalog.mc`: local-session
  edits, save outcomes, chosen exercise snapshots, increments and recent IDs.
- `source/StrengthRecorder.mc`: FIT pause, exit, retry and
  unknown-outcome transitions.
- `docs/DEVICE_TESTS.md`: record compiled versus observed behavior separately.

## Completion criteria

- BACK from any routine-edit subview reaches the current setup list and then
  Home; no stale menu or inert row appears.
- In-app Pause/Resume keeps one recording handle. Explicit unfinished exit
  says when a later resume can create a second Garmin activity.
- Skip/Swap for today does not alter the saved routine or any completed set;
  workout history reflects what was actually performed.
- A failed Garmin save cannot be abandoned accidentally from the result
  screen. Local history always distinguishes Garmin Saved, Failed, and Unknown.
- Recent/Used shortcuts work offline; Browse still reaches every bundled
  Garmin exercise. New entries use their configured load increment.
- The set value remains the main visual anchor; rest countdown and action are
  readable in their active state, including when the title wraps to two lines.
- Compile the production `fr965` target with
  `-y /private/tmp/NextSetDeveloperKey.der` on the first attempt. Record only
  direct simulator/device/Connect observations as evidence. Physical FR965
  recording and Garmin Connect rendering remain pending until directly seen.
