# Changelog

NextSet is an unofficial companion for Liftosaur. It is not made or endorsed by Liftosaur and needs Liftosaur Premium for API access.

## 0.6.0
- **AMRAP sets show "3+".** Sets marked as many-reps-as-possible in Liftosaur (`1x3+`) show their reps with a "+" on the set screen, the exercise list and the routine preview, so you remember to enter what you really did. Logging is still one START press.
- **Rest per set.** Each set keeps the rest time Liftosaur gives it (`3x5 20s, 2x5 120s` rests 20 s, then 120 s); before, every set used the first set's rest.
- **Forerunner 255 sync crash.** Garmin's crash reports showed the app being stopped for running too long ("code executed too long") while syncing a heavy day. A day reply is now handled in four short steps instead of one long one and checked once instead of three times. Tested in the simulator; not yet confirmed on a real Forerunner 255.
- **Routine sync uses much less memory.** On low-memory watches (Forerunner 255 family) the peak during sync is much lower: a reply is converted and dropped before anything is saved, only the current week's days are kept, saves no longer read the old copies back, and the loaded routines are released while a sync runs. When free memory is still too low the sync stops with "Low memory · retry sync" and a reason under Settings → Diagnostics.
- **Diagnostics you can read and paste.** Settings → Diagnostics starts with one line to copy into a bug report: app version, watch, the step the app was in if it stopped unexpectedly last time ("Stopped in: day reply W1 D3, 38 KB free") and the reason of the last failed sync. Long text wraps and scrolls with UP/DOWN instead of being cut off. A failed sync now says "Sync failed: Settings > Diagnostics".
- Fixed a crash when a sync reply arrived after the sync had already moved on.

## 0.5.0
- **Connect IQ 3.4 watches.** The minimum is Connect IQ 3.4 instead of 5, adding the fēnix 6 Pro / 6S Pro / 6X Pro, Forerunner 945 LTE, Descent Mk2 / Mk2S and the eight MARQ Gen 1 editions (67 watches in all). Tested in the simulator only on these.
- **Any Liftoscript week header.** Any `# …` line opens the next week, so programs with headers like "# Week 4 - Deload" or "# #29 Preparation - Week 1" (5/3/1 BBB, Juggernaut, Sheiko) sync instead of failing with "Liftosaur routine data is invalid".
- **Long programs.** Up to 160 program days (was 48: Calgary 16-Week, Bullmastiff); the synced week is still capped at eight days, the rest count as skipped.
- **Skipped days.** A day with no exercises or with exercises NextSet cannot run is skipped instead of failing the sync ("Synced N days, K skipped"); when Liftosaur's next day was skipped, the next synced day is offered. A set timer with more than one rep (EMOM) is a weight/reps set.
- Settings → Diagnostics shows the reason of the last rejected or skipped sync.

## 0.4.7
- **Set dots on the exercise list.** The Overview shows the same dots row as the set screen for the shown exercise (warmups small and gray, then the sets) instead of the big "2/3 sets"; "Exercise 2/8" moves below it and the next set ("55 kg × 9") is a little larger.

## 0.4.6
- **Continue in the last-set editor.** BACK on the set screen opens the last set with a new first row, **Continue** (green when selected, preselected on opening). START on it saves anything you changed and returns to the set screen, so an accidental BACK costs one press: BACK, START. The other rows are unchanged (weight, reps, Delete; BACK still saves and goes to the Overview). The START icon is a play triangle on Continue and a check on the other rows.
- The set dots stay visible during the rest, with the rest time below them.
- **Set progress is always dots.** Warmups are their own small gray dots in front of the working sets (done gray, up next white, open an outline); the "Warmup 1/2" text and the "4/8" counter for long exercises are gone. Long rows shrink their gaps and dots to fit the round screen. A one-sided timed set shows its side in a small line under the dots.

## 0.4.5
- **Resume / Save / Discard.** BACK on the Overview, BACK on Home during a workout and the prompt after the last set open one screen like a native Garmin activity: **Resume** (selected first), **Save**, **Discard** (UP/DOWN move, START confirms, BACK resumes). It shows the workout time and sets in a small line. **Save** finishes the workout ("Log a set before saving" when nothing is logged); **Discard** asks "Discard workout?" (Keep / Discard) first. The old "Finish?" review is gone.
- **Hold-UP icon shows what it changes.** On the set screen the ring holds a small dumbbell (Change weight) or a clock (Change time); the Overview keeps the plus and Home the dots.
- **Sync to Liftosaur from the summary.** While the saved workout's upload is waiting or failed, the summary shows "START: Sync to Liftosaur" (green, bottom) and START uploads now; the Liftosaur row shows an arrow while uploading, a check when done and a red short error on failure. Once uploaded START exits; BACK always exits. Nothing is shown without a Liftosaur key. If the Garmin activity needs its retry choice, that comes first (START opens it) and it has a **Sync to Liftosaur** item too.

## 0.4.4
- The hold-UP icon sits beside the UP button, in an open ring that signals "hold" (dots on the set screen, plus on the Overview).

## 0.4.3
- **BACK steps back in time.** On the set screen BACK opens the last set you logged for that exercise (**Set N**) with the weight and reps and a new **Delete** row; BACK again saves what you changed and shows the Overview; BACK on the Overview opens the Finish review. An exercise with nothing logged goes straight to the Overview. **Delete** asks "Delete set N?" (Keep is selected first) and returns to the set screen with that set open again.
- **No more hold-UP menu on the set screen.** Hold UP now opens **Change weight** directly (**Change time** for a timed set; bodyweight sets have nothing to change, so no icon is drawn): UP/DOWN change it, START saves, BACK cancels. "Edit last set", "Delete set", "Add set", "Skip warmups", "Skip rest", "Log paused set", "Reopen exercise" and "Finish workout" are gone from the menu: finish with BACK on the Overview.
- **Hold UP on the Overview adds a set** to the shown exercise (a short buzz, the count updates; "Max sets reached" at the limit). The edge icons on these screens now match the real buttons.
- **Finish workout is BACK on the Overview.** The review opens with START to save and BACK for Keep working or Discard, with the same fonts as the review. With no set logged the review still opens, so a workout can be discarded.
- **The weight step is automatic: 2.5 kg or 5 lb.** The "Weight step" menu is gone (Liftosaur's data has no rounding value to follow). Routines synced before keep working: the old 1 kg step becomes 2.5 kg, and any step you set earlier is still applied.
- "Skip exercise" and "Replace exercise" are gone; follow the program, or finish the workout early. An exercise closed early by an older version is reopened by START on the Overview.
- The set-screen hint reads "Hold UP: change weight".

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
