# UX Review and Implementation Plan

## Implementation status

Implemented in source and built for the FR965 on 2026-09-27. The simulator smoke review covered resume, exercise selection, the set screen, and long-name wrapping. Full workout-path checks and physical-watch button and vibration checks remain outstanding.

## Target workout flow

`Begin/Resume → choose workout → choose exercise → adjust if needed → log sets → choose next exercise → save.` Stay on the exercise while it has sets left. After its last set, return to exercise selection. A completed exercise must remain accessible for adding a set or correcting the last one, without showing an otherwise idle “Exercise complete” screen. Switching exercises remains possible for supersets and other changes of order.

## Implemented changes

### 1. Simplify workout flow

- Final sets no longer start rest. Expired rest disappears after its alert.
- Finishing an exercise returns to the overview and selects the next unfinished exercise. All-done workouts offer **Save workout** or **Keep working**; completed exercises open **Add set**, **Edit last set**, and **Undo** actions directly.
- The workout menu only offers Save after a set is logged. Save is direct; Cancel keeps its confirmation. Failed saves expose a retry from Home.

### 2. Clarify editing and timed sets

- Load editing leads the exercise menu, remains available by tapping the underlined value, and updates later draft sets. **Add set** follows it. Irrelevant rest adjustments and completed-exercise screens were removed.
- Timed-set cues reflect begin, finish, resume, or log actions. Paused measurements can be logged from the existing exercise menu.

### 3. Rebalance screens and hints

- The set screen centers readable, wrapping exercise names, set number, and load/reps value; the load is visibly tappable. Rest, prior performance, and notes follow the main values.
- Persistent navigation hints were trimmed. The number editor has one adjust/save cue; history has no footer; the saved summary has a clear exit cue. Existing fonts and a restrained accent mark editable load and active rest.

### 4. Tidy secondary surfaces

Home keeps direct Begin/Resume access and the two-workout picker. Setup labels are clearer, while settings and history remain secondary. Recovery and save-failure messages remain available.

## Remaining acceptance checks

- Complete both template workouts with buttons only, then verify touch load editing, add-set, correction/undo, partial save, and all-done flow in the simulator.
- Verify timed begin/finish/pause/resume and logging paused time; check failed-save retry and Back behavior from every menu.
- Check rest alerts with the physical FR965 screen dimmed. Simulator vibration does not establish hardware haptic behavior.
- Inspect longest exercise names, assistance/bodyweight/timed values, last-performance text, rest status, and notes on the round display.
