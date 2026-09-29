# NextSet UX audit (2026-09-29)

This is a code-based walkthrough of the current `main` plus the uncommitted stability work. Each flow was traced through views, delegates and menus. Press counts assume physical buttons (UP, DOWN, START, BACK, MENU). Menu2 focuses its first item, so selecting the n-th item costs (n−1) DOWN presses plus START. Simulator and watch confirmation is pending, and nothing here was tested with users.

Priority: the workout flow first, then routine editing and creation. Principle: during a set the watch should need one press. Anything done between most sets should be at most two presses away. Rare actions can sit deeper.

## 1. Workout logging (highest priority)

### Current flow

| Step | Screen shows | Input |
| --- | --- | --- |
| Home | `NextSet` · routine name · `24 planned sets` · `UP/DOWN select · START begin` · `MENU: History/Edit` | UP/DOWN picks the routine, START starts it |
| Starting | `Starting workout…` | – |
| Overview (one exercise at a time) | Exercise name · `0/3 sets` (large) · `0/24 SETS · EX 1/8` · `MENU actions` | UP/DOWN browses exercises, START opens one, MENU/BACK opens the Workout menu |
| Exercise | Name · `Set 1/3` · `60 kg × 10` (load underlined, tappable) · `LAST 60 kg x 10` · notes · `ADJUST · START LOG` | UP/DOWN changes reps, START logs the set, tap the load to edit it, MENU/BACK opens the Workout menu |
| After logging | Same screen, next set · yellow `REST 1:30` · cue changes to `MENU SKIP REST` | START logs the next set, which also restarts rest |
| Last set of exercise | Pops back to Overview, which moves to the next unfinished exercise | – |
| All sets done | `Workout complete` menu: Save workout / Keep working | START saves |
| Summary | `NextSet log saved` · `24/24 sets` · ELAPSED · ACTIVE · `GARMIN ACTIVITY SAVED` · `START: EXIT` | START exits |

These parts are already good:
- Logging is one press, with an 800 ms guard against double presses.
- The next set is prefilled from last time, and that value stays visible.
- The app moves to the next exercise on its own.
- The timed-set cues change with state (`START begin`, `finish`, `resume`, `log`).
- The finish flow is short.

### Frequent actions: press counts

The Workout menu reached from the Exercise screen currently lists, in order:

1. Pause
2. Save segment & exit
3. Exercise options
4. Back to overview
5. Skip rest (when rest is running)
6. Skip for today
7. Swap for today / Add alternative today
8. Finish workout
9. Cancel workout

| Action (how often) | Path today | Presses |
| --- | --- | --- |
| Log a set (every set) | START | **1** |
| Change reps (most sets) | UP/DOWN | 1–3 |
| Go back to Overview / switch exercise (every exercise) | BACK → Workout menu → 3 DOWN → START | **5** |
| Change load (often) | MENU → 2 DOWN → Exercise options → START on Change load → editor | **5** + editing (or a small touch target) |
| Skip rest (occasionally; START already overrides it) | MENU → 4 DOWN → START | **6** |
| Edit or undo last set (occasionally) | MENU → Exercise options → DOWN… | 5–7 |
| Finish early (once) | MENU → 7 DOWN → START | 9 |

### Findings

| Pri | Finding | Why it matters | Recommendation |
| --- | --- | --- | --- |
| **P0** | BACK on the Exercise screen does not go back. It opens the Workout menu, where "Back to overview" is the 4th item. | Switching exercise happens every exercise and costs 5 presses. It breaks the most basic expectation on a watch. | BACK = go to Overview in one press. Keep the automatic pause for a running timed set that the Overview item does today. |
| **P0** | MENU on the Exercise screen opens the *Workout* menu. Exercise actions (Change load, Add set, Edit last set, Undo) sit one level deeper, behind "Exercise options". | Changing the load is the most common adjustment after reps and costs 5 presses. The touch target is small and unreliable with sweaty hands. | MENU on Exercise opens the **Exercise menu** directly. Order: Change load, Edit last set, Add set, Undo, Skip rest (while resting), Skip/Swap for today, then a last item **Workout…** that opens the Workout menu. |
| **P0** | While rest runs, the cue changes to `MENU SKIP REST`. START still logs, but the main action is no longer shown, and "Skip rest" is 6 presses away, not 1 as the cue implies. | The cue is misleading, and a user may think they must skip rest before logging. | Keep the cue `START log` during rest. The yellow `REST 1:15` line is enough. Skipping rest is almost never needed, because logging the next set replaces it. |
| **P1** | The Workout menu is ordered by rarity: Pause and "Save segment & exit" come first. | Every other item costs 2+ extra presses. | Order: context items (Skip rest, Skip/Swap exercise), **Finish workout**, Pause/Resume, Exit and resume later, Cancel workout. |
| **P1** | Overview shows only the set count for the focused exercise. There is no next-set target and no rest timer. | When choosing the next exercise, the user can't see the next load or how much rest is left. | Below `1/3 sets`, add `Next: 60 kg × 10`. Show a yellow `REST 1:15` line while rest runs. Drop `MENU actions`, which is a standard button meaning. |
| **P1** | Overview gives no hint that UP/DOWN browses exercises, and it shows one exercise at a time. | Users may not realise they can switch exercise. | Add a small `▲▼ 1/8` indicator, or render the previous/next exercise names faintly above and below. |
| **P1** | The Exercise cue `ADJUST · START LOG` doesn't say what ADJUST changes. It changes reps only. | Users may try to adjust the load with UP/DOWN. | `UP/DOWN reps · START log`. |
| **P1** | Home during a workout says `MENU: Actions`, but MENU opens the Home menu (Resume / History) and BACK opens Actions. | The label is wrong. | Label `MENU: Menu`, or make MENU open Actions. Simpler still: START resumes, and nothing else is needed on Home during a workout. |
| **P2** | The words for ending a workout vary: Finish workout / Save workout / "NextSet log saved" / "Partial NextSet log" for saving, and Cancel workout / "ABORTED" (History) / "Workout ended" for discarding. | Mixed terms make the user wonder what gets saved. | Use *Finish workout* → "Workout saved" / "Workout saved (partial)", and *Cancel workout* → "Cancelled" in History. |
| **P2** | "Save segment & exit" (subtitle "Resume may split activity") and the Summary's "N GARMIN SEGMENTS" / "PRIOR SEGMENT UNKNOWN" use internal jargon. | A user doesn't know what a segment is. | Use "Exit, continue later", with the explanation kept on the confirm screen (done). On Summary, show "Saved as N Garmin activities" and only when N > 1. |
| **P2** | The number editor title reads `EDIT NEXT 2` / `EDIT SET 2`. | It is ambiguous: 2 of what? | Use `Set 2 · load` / `Set 2 (done) · reps`. |
| **P2** | The first workout with a new exercise starts at 0 kg, because a new routine entry defaults `startingLoad100 = 0`. Prefill only kicks in from the second session. | The user must edit the load for every exercise in the first session. | Ask for the starting load when adding an exercise (see §2). |
| **P3** | Summary shows ELAPSED and ACTIVE with the same weight. | Minor. | One line: `42:10 · 38:05 active`. |

### Target workout flow (after fixes)

```
Home ─START→ Overview ─START→ Exercise
                ▲   UP/DOWN browse   │ START log (rest starts, next set shown)
                │                    │ UP/DOWN reps
                └──────── BACK ──────┤ MENU → Exercise menu (Change load first, … , Workout…)
                                     │ last set → auto back to Overview, next exercise selected
Overview MENU → Workout menu (Finish first) → Summary → START exit
```

Per-set cost: 1 press. Switching exercise: 1 (BACK) + UP/DOWN + 1. Changing load: 2 presses to the editor.

## 2. Creating and editing routines

### Current flows

**Create:**
1. Home MENU → Routines (4th item) → Create routine.
2. Enter the name in the TextPicker.
3. The empty routine opens → Add exercise → Choose category 1/4. Recent and Used are listed first, then 14 categories per page.
4. Pick the category → pick the exercise (20 per page) → pick the tracking type (suggested type first).
5. Back in the routine list, the new entry reads `3 × 10 reps` at **0 kg**.
6. To set the real values: entry → Mapping details / **Edit values** / … → field → number editor → back to the field list.

Adding a finished exercise takes about 12–15 presses plus one editor session per field.

**Edit:**
1. Home MENU → Routines → routine → exercise.
2. The entry menu lists: Mapping details, Edit values, Replace, Move up/down, Remove.
3. Edit values → Set count / Min reps / Max reps / Starting load / Load increment / Rest → number editor.

That is 6 levels deep.

These parts are already good:
- The routine list shows the exercise count.
- The routine view shows `3 × 8–12 reps` per exercise.
- Recent and Used shortcuts in the picker.
- The tracking type is pre-selected.
- Delete and remove ask for confirmation.
- Routines can't be edited while a workout is active.

### Findings

| Pri | Finding | Recommendation |
| --- | --- | --- |
| **P1** | After you pick an exercise and its tracking type, the app drops you back in the routine list with defaults (3 × 10, 0 kg, 90 s). Setting real values is 3 levels away. | After adding (and after replacing), open that entry's **Edit values** list directly. BACK from it returns to the routine. |
| **P1** | The first entry menu item is **Mapping details**, a technical screen ("Local exercise mapping only", "FIT contains no native set rows"). | Order: Edit values, Move up, Move down, Replace exercise, Remove exercise. Drop Mapping details, or move it to the bottom as "Garmin name". |
| **P1** | There is no way to rename a routine. | Add "Rename" to the routine menu, reusing the TextPicker. |
| **P2** | "Load increments" is a top-level menu listing only the built-in seed exercises. The same setting also exists per exercise under Edit values. | Remove the global menu. Keep the per-exercise field. Fewer Home menu items. |
| **P2** | The routine view shows sets and reps but not the load or rest. | Sublabel `3 × 8–12 · 60 kg`. |
| **P2** | Min and max reps are two separate fields and editor trips. | Keep them, but label the entry `Reps 8–12` and edit min then max in one flow (START on min moves on to max). |
| **P2** | The Home menu has "New workout" next to START on Home. Both start a workout, but they show different lists (the menu hides empty routines). | Remove "New workout" from the menu. Home START is the one way to start. |
| **P3** | Category paging is 4 pages of 14 with Prev/More at the bottom. | Fine for a watch. Consider putting the most used strength categories (Bench Press, Squat, Row, Curl, …) on page 1. |

## 3. Information on each screen

| Screen | Must show | Currently extra or noisy | Currently missing |
| --- | --- | --- | --- |
| Home | Routine name, size, how to start | `MENU: History/Edit` (fine) | Exercise count and when it was last done (`8 ex · 24 sets · last Mon`), which helps pick the routine for today. |
| Overview | Focused exercise, its progress, next target, overall progress | `MENU actions` | Next set (`60 kg × 10`), rest timer, browse hint |
| Exercise | Name, set n/N, value to log, last time | Notes and the message line both compete for one caption line | Rep range target (`target 8–12`) when it differs from the prefill. Keep it small. |
| Number editor | Field, value, step | Two cue lines | – |
| Workout menu | Frequent actions first | Pause and Exit at the top | – |
| Summary | Saved?, sets done, duration, Garmin status | Segment jargon, two duration lines | Volume or PRs are optional later ideas; not needed now |
| Routine view | Exercises with sets × reps | – | Load |
| Entry menu | Edit values | Mapping details first | Rename (routine level) |
| Mapping details | – | Developer text | Candidate for removal |

## 4. Recommended implementation order

1. **Workout controls (P0):**
   - Exercise BACK goes to Overview.
   - Exercise MENU opens the Exercise menu, with "Workout…" as its last item.
   - Rest cue keeps `START log`.
   - Exercise cue reads `UP/DOWN reps · START log`.
2. **Workout menu order and Overview info (P1):**
   - Reorder the Workout menu.
   - Add the next set and the rest timer to Overview, plus a browse hint.
   - Fix the Home label.
3. **Routine editing (P1):**
   - Go straight to Edit values after adding or replacing an exercise.
   - Reorder the entry menu and demote Mapping details.
   - Add Rename.
4. **Wording (P2):** unify the vocabulary for finishing and cancelling, and remove the segment jargon.
5. **Cleanup (P2):** remove Load increments and "New workout" from the Home menu, and add the load to the routine view sublabels.

Each step is UI-only. No storage or schema change is needed. For verification, run the simulator walkthrough of both seed routines and one custom routine after each step. Also run one watch session in the gym, recording in `docs/DEVICE_TESTS.md` the press counts for the four frequent actions in §1.

## Housekeeping

`UX_REVIEW.md` has an uncommitted stray line: an `[text](data:image/svg+xml;base64,…)` file-icon link, apparently pasted by accident, before "API level correction". Revert that hunk before committing.

## Implementation (2026-09-29)

All rows above were implemented; no stored schema changed. Build and unit tests pass (27/27). The app launches in the simulator without a crash; buttons were not driven, so the flows below are unverified on screen.

Workout (section 1)
- Exercise BACK pops to Overview in one press and pauses a running timed set first; if the pause save fails it shows feedback and stays.
- Exercise MENU opens the Exercise menu: Change load/assistance or Edit duration, Edit last set, Add set, Undo set n, Log paused set, Skip rest (only while running), Skip for today, Swap/Add alternative today, Reopen exercise, then "Workout...". "Exercise options" and "Back to overview" are gone.
- Cue is `UP/DOWN reps · START log` for non-timed exercises; the timed cues are unchanged. The rest cue no longer changes; the yellow REST line stays.
- Workout menu order: Skip rest (running), Skip/Swap/Add alternative (Overview context), Finish, Pause/Resume, "Exit, continue later" (no subtitle), Cancel. Opened from the Exercise menu it omits the items the Exercise menu already has.
- Overview shows `Next: 60 kg × 10` (omitted when complete), a yellow REST m:ss line while rest runs (the existing per-second `requestUpdate` refreshes it), and a `UP/DOWN · EX 1/8` hint. Plain text was used because arrow-glyph font coverage could not be checked. `MENU actions` is removed.
- Home during a workout now reads `MENU: Menu` (which is what MENU opens).
- Wording: "Workout saved" / "Workout saved (partial)" / "Workout cancelled"; History shows CANCELLED; "Saved as N Garmin activities" (only when N > 1); "One Garmin part unknown"; the "NextSet log saved" menu title is "Workout saved"; the exit confirm reads "START: EXIT". Err message texts contained none of these terms and are unchanged.
- Number editor title: `Set 2 · load` / `Set 2 (done) · reps`. Summary shows one line `42:10 · 38:05 active`.
- First-session 0 kg is handled by the routine add flow (below).

Routines (section 2)
- After adding or replacing an exercise, that entry's Edit values list opens; BACK returns to the routine. `addRoutineExercise` now returns the new entry ID.
- Entry menu order: Edit values, Move up, Move down, Replace exercise, Remove exercise, Garmin name. The Garmin name screen shows only the NextSet name and Garmin name.
- Rename routine added before Delete (TextPicker prefilled; nonblank, at most 64 bytes, unique name; saved through `saveRoutines`).
- Removed the Home menu's "Load increments" and "New workout", plus `editIncrements`, `IncrementMenuDelegate`, `TemplateMenuDelegate`, `Navigator.templates`, `incrementValues` and the "increment" config kind. The per-exercise increment field stays.
- Routine view sublabel includes the starting load for weight and assistance (`3 × 8–12 · 60 kg`).
- Edit values shows one `Reps 8–12` row; START edits the minimum, then opens the maximum. Raising the minimum above the maximum raises the maximum with it; lowering the maximum below the minimum is still rejected (INVALID VALUE).
- Category pages list Bench Press, Squat, Deadlift, Row, Shoulder Press, Pull Up, Curl, Triceps Extension, Lunge, Plank, Core, Lateral Raise, Leg Curl first, then the rest as before. Recent and Used stay on top.

Information (section 3)
- Home shows `8 ex · 24 sets · last Mon` (weekday within 6 days, else month and day; omitted when unknown). It is computed once in `HomeView.initialize` from `Store.peekSession`, which now also returns templateId, endedAt and status (envelope only); only completed sessions count.
- Exercise shows a small `target 8–12` caption when the range differs from the prefilled reps. It is dropped when notes, a message, or rest occupy the space, so LAST always wins.

Housekeeping
- `UX_REVIEW.md`: replaced the stray data-URI line with the original blank line; `git diff` for the file is now empty.
- Removed `NumberEditView`'s private `copyDictionary` duplicate.
