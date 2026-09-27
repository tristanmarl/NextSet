# 1. Executive technical recommendation

**Build a standalone Monkey C watch app for the Forerunner 965. The core MVP is feasible.** Use local storage as the authority for sets, templates, previous performance, and recovery. Use Garmin ActivityRecording as a separate, best-effort activity recorder. Exercise selection is unrestricted; a rest timer belongs to the session, not to a screen.

This is an implementation plan, not an app implementation. Working project name: **NextSet**. Documentation checked on **27 September 2026**. No simulator or physical-watch experiments were performed while preparing this plan.

Decisions for v1:

- Target only `fr965`; set manifest `minSdkVersion="5.2.0"`, compiling with Connect IQ SDK **9.2.0**, currently listed by Garmin. The FR965's listed API level is **5.2**; SDK version and watch API level are different version systems. Validate on firmware exposing API 5.2. Pin the SDK and device definition used in the build record. [Garmin SDK](https://developer.garmin.com/connect-iq/sdk/), [Compatible devices](https://developer.garmin.com/connect-iq/compatible-devices/)
- Supply Upper and Lower as compiled, on-watch seed templates. Allow adjustment of exercise weight increments and template numeric defaults on the watch. New names, exercises, ordering, and templates are edited in the development seed resource and rebuilt for the internal MVP.
- Support weight, assistance, bodyweight, and timed exercises. Use kilograms only in v1, represented as integer hundredths of a kilogram. No progression rules.
- Log a normal set with one START press. Persist it immediately, start rest, and show the next draft with a nonmodal saved-set message. Correction and undo are explicit actions; rest expiry never changes input meaning.
- Retain four recent ended sessions plus an independent last-performance cache for up to 32 exercise identities. History is intentionally bounded.
- Persist every accepted workout mutation; keep two generations of critical records. Never acknowledge a set as saved when persistence failed.
- Do not implement a background service for short rest alarms. Alerts work while the app remains operational; leaving the app preserves the deadline but does not promise an alarm outside the app.
- Record training/strength FIT activity with heart rate. No promise of native Garmin strength-set tables, muscle maps, training effect, or training load.

**Required pre-implementation gates:** storage capacity/durability, physical input dispatch, screen-off timer behavior, and ActivityRecording interruption behavior. Section 16 specifies tiny probes and predetermined fallbacks; the coding agent must run them before depending on unverified behavior.

# 2. Verified Garmin constraints

Labels used throughout: **V** = verified in official documentation; **D** = architecture/product decision; **P** = requires a simulator or device probe. A documented capability is not evidence that this particular implementation has been tested.

| Topic | Verified fact and implementation consequence |
|---|---|
| App type | **V:** Device/watch apps provide interactive UI and ActivityRecording. Data fields live inside a native activity and are unsuitable for owning this workflow. **D:** manifest type `watch-app`. [App types](https://developer.garmin.com/connect-iq/connect-iq-basics/app-types/) |
| FR965 display/input | **V:** `fr965`, round 454 × 454 screen, touch support, logical enter/up/menu/down/esc inputs; launcher icon 65 × 65. **V:** watch-app memory limit is **786,432 bytes = 768 KiB**, not the device's music/file capacity. Background memory is 65,536 bytes. [FR965 device reference](https://developer.garmin.com/connect-iq/articles/device-reference/fr965.html) |
| API compatibility | **V:** Garmin currently lists FR965 API level **5.2**. **D:** target minimum API **5.2.0** for this FR965-only build; do not assume every API in SDK 9.2.0 exists on the watch or every older firmware version. [Compatible devices](https://developer.garmin.com/connect-iq/compatible-devices/) |
| Persistence | **V:** `Application.Storage` stores values across app executions. Current API reference limits individual values to **32 KB**, says aggregate capacity can vary, and documents `StorageFullException`. Symbols are unsuitable as persistent keys/values. [Storage API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Storage.html) |
| Conflicting storage guidance | **V:** the older core article describes 128 KB total and 8 KB per entry. Prefer the current API's 32 KB per-value limit, treat 128 KiB aggregate as a budget hypothesis, and measure on FR965. The core article confirms writes occur when `setValue()` is called. Neither source promises power-failure atomicity or multi-key transactions. [Persisting data](https://developer.garmin.com/connect-iq/articles/core-topics/Persisting_Data.html) |
| Lifecycle | **V:** `onStart`, `getInitialView`, and `onStop` are app lifecycle hooks. `onStop` may receive `:suspend`; suspension can be cleared by reboot/update. FR965 is absent from the documented `onActive`/`onInactive` supported-device lists. **D:** do not depend on newer multitasking callbacks or suspension as durable recovery. [AppBase](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/AppBase.html) |
| Timers | **V:** `Timer.Timer` is a callback scheduler, not a persisted alarm. Missed repeating callbacks are skipped; timer count and minimum interval are device-dependent. **D:** one app-owned repeating timer, deadlines rather than decrementing counters. [Timer](https://developer.garmin.com/connect-iq/api-docs/Toybox/Timer/Timer.html) |
| Background work | **V:** temporal events normally cannot occur within five minutes of the previous temporal event; a watch-app startup exception exists for Moment scheduling. Only one temporal event is registered at once. **D:** this is not a dependable general solution for repeated 60–150 second rests; omit Background permission and service. [Background](https://developer.garmin.com/connect-iq/api-docs/Toybox/Background.html) |
| Haptics | **V:** `Attention.vibrate()` accepts VibeProfile values. Garmin warns Forerunners do not support variable vibration patterns/duty cycles as other devices do. **D:** use one simple 500 ms vibration; verify perceptibility. [Attention](https://developer.garmin.com/connect-iq/api-docs/Toybox/Attention.html) |
| UI/input | **V:** BehaviorDelegate maps behaviors to buttons/gestures and can consume events before raw InputDelegate handling. Menu2 is available; ActionMenu is available on FR965. The newer `onActionMenu()` shortcut callback does not list FR965. **D:** use Menu2 opened through `onMenu()`, no dependency on that shortcut. [BehaviorDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/BehaviorDelegate.html), [InputDelegate](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/InputDelegate.html), [Menu2](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/Menu2.html), [ActionMenu](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/ActionMenu.html) |
| Recording | **V:** ActivityRecording requires `Fit`; a session supports start, stop, save and discard. Only one session object may exist; `createSession()` can return an existing unclosed object. That statement alone does not establish cross-reboot restoration. [ActivityRecording](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html), [Session](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html) |
| Sensor recording | **V:** Garmin's workflow enables sensors, creates a recording, starts it, stops it, then saves/discards. Enabled sensor data is recorded in FIT. **D:** enable heart rate explicitly; no GPS. [Activity recording guide](https://developer.garmin.com/connect-iq/articles/core-topics/Activity_Recording.html), [Sensor](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html) |
| Strength metadata | **V:** documented FIT contributions are developer fields on record, lap, or session messages. There is no documented CIQ API here to emit arbitrary native strength `set` messages. **Inference:** native strength tables cannot be a supported MVP deliverable. `nativeNum` metadata is not an arbitrary native-message writer. [FitContributor](https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html), [Session.createField](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording/Session.html) |
| Fitness metrics | **V:** a sport classification is not guaranteed to change device behavior or unlock native algorithms. **P:** inspect actual heart-rate, calorie, training-effect and training-load results on FR965. **D:** promise duration and available sensor recording only after validation. [ActivityRecording sport semantics](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html) |
| Simulator/testing | **V:** simulator can record simulated activity data; Run No Evil tests run in the simulator, using `(:test)` methods and `Toybox.Test`. Tests do not establish hardware haptics, firmware lifecycle, or Garmin Connect presentation. [Unit testing](https://developer.garmin.com/connect-iq/articles/core-topics/Unit_Testing.html), [Recording simulation](https://developer.garmin.com/connect-iq/articles/core-topics/Activity_Recording.html) |
| Packaging | **V:** export a signed `.iq` containing declared products, submit it with store description/screenshots, and undergo Garmin review. Signing uses a developer key; retain that key for updates. **D:** prepare packaging, do not publish as part of internal MVP. [Submission](https://developer.garmin.com/connect-iq/submit-an-app/), [Getting started/signing](https://developer.garmin.com/connect-iq/articles/connect-iq-basics/Getting_Started.html) |

# 3. Proposed architecture

Use small concrete modules and classes. No framework, dependency injection container, observer bus, database library, generic repository layer, or phone communications.

| Module/class | Owns and does |
|---|---|
| `NextSetApp extends Application.AppBase` | Creates the objects below; implements lifecycle and best-effort shutdown; starts/stops the single timer. |
| `SessionController` | Sole owner of mutable session data. Validates commands, builds a candidate state, persists, then publishes it to the UI. Coordinates recorder side effects separately. |
| `SessionLogic` module | Pure calculations: validation, totals, status, next unfinished slot, completing/correcting/undoing a set, closing/reopening an exercise. Accepts `now` explicitly. |
| `Catalog` module | Loads seed resources and persisted numeric overrides, validates stable IDs and limits; builds session snapshots. No architecture tied to Upper/Lower. |
| `Store` class | Storage access, schema validation, two-generation writes, history slots, finalization recovery. Owns persistence revisions, not UI state. |
| `LastPerformance` module | Cache merge and prefill selection. No progression, tonnage recommendations or exercise-name matching. |
| `RestClock` module | Pure deadline/expiry/adjustment calculations. No WatchUi or storage calls. |
| `Recorder` class | The only owner of `ActivityRecording.Session` and sensor enablement. Start/pause/resume/save/discard, return structured outcomes; never modifies completed sets. |
| `Navigator` class | Builds/pops/replaces WatchUi views; retains overview selection in RAM. Maximum app route depth five. |
| UI classes in section 12 | Render controller data, collect input, call commands. They cannot directly mutate records or call Storage/ActivityRecording. |

Data flow: **button/touch → delegate → controller command → pure logic → Store commit → live state swap → redraw**, followed by nonessential haptic or recorder updates. Persistence failure leaves the old live state intact and shows a retryable error. Completion retries address the same slot, preventing duplicate sets.

Concrete Monkey C interface sketch; this is a contract, not code to paste unmodified:

```monkeyc
class SessionController {
    function startWorkout(templateId as String, now as Number) as Boolean;
    function completeSet(entryId as String, slot as Number,
                         actual as Dictionary, now as Number) as Boolean;
    function correctSet(entryId as String, slot as Number,
                        actual as Dictionary, now as Number) as Boolean;
    function undoSet(entryId as String, slot as Number, now as Number) as Boolean;
    function closeExercise(entryId as String, closed as Boolean) as Boolean;
    function saveDraft(entryId as String, slot as Number, draft as Dictionary) as Boolean;
    function pauseWorkout(now as Number) as Boolean;
    function resumeWorkout(now as Number) as Boolean;
    function finishWorkout(outcome as String, now as Number) as Boolean;
}
class Store {
    function loadPair(domain as String) as Dictionary or Null;
    function commitPair(domain as String, payload as Dictionary) as Boolean;
    function writeHistory(session as Dictionary) as Boolean;
    function resumeFinalization() as Boolean;
}
class Recorder {
    function startSegment(name as String) as Dictionary;
    function pause() as Dictionary;
    function resume() as Dictionary;
    function closeSegment(save as Boolean) as Dictionary;
}
```

Use string-keyed dictionaries for durable records, arrays for lists, and named helper functions. Runtime constants may be symbols; persisted enums must be strings or numbers. Clone the affected nested records when building a candidate; do not mutate shared arrays behind a committed snapshot.

Permissions: `Fit`, `Sensor`. Add `FitContributor` only if the optional summary-field task is undertaken. Storage and basic WatchUi/Timer use do not justify additional permissions. No Communications, Positioning or Background permission.

# 4. Data model

All structures below are logical storage shapes. `?` means nullable; arrays preserve presentation or set-slot order. Timestamps are UTC epoch seconds from `Time.now().value()`; milliseconds from `System.getTimer()` are runtime-only and never persisted as a reboot-stable clock. Represent money-like load arithmetic with integers: `6525` = 65.25 kg. The unit is explicit even though v1 supports only `kg`.

**Exercise**

```text
id: String                    stable ASCII slug, max 40 bytes
name: String                  max 64 UTF-8 bytes
loadType: String              weight | assistance | bodyweight | timed
loadUnit: String?             kg for weight/assistance; null otherwise
weightIncrement100: Number?   default adjustment; positive for loaded types
defaultRestSec: Number?       null falls back to settings
notes: String?                max 160 UTF-8 bytes
```

An identity includes its semantics. Renaming retains an ID. Changing load type, unit, machine interpretation, or whether a value means one dumbbell versus a pair requires a new exercise ID. For weight/assistance the entered number is the equipment load as labelled; do not infer body mass, sled weight, plate totals, side multipliers, or effective resistance. Assistance remains nonnegative and is labelled “kg assist”; less assistance is harder but v1 does not calculate difficulty. Bodyweight has no editable load. Added-weight bodyweight exercises use a separate `weight` identity. Timed v1 has duration only, no concurrent load dimension.

**WorkoutTemplate**

```text
id: String; revision: Number; name: String
entries: Array<WorkoutExercise>
```

**WorkoutExercise**

```text
entryId: String               stable within template
exerciseId: String
workingSetCount: Number
targetRepsMin: Number?; targetRepsMax: Number?
targetDurationSec: Number?
restSec: Number?              entry > exercise > app default
startingLoad100: Number?
notes: String?
supersetGroupId: String?      accepted in seed schema, ignored in MVP navigation
```

For v1 reject duplicate exercise IDs inside a template; the same identity can appear in many different templates. This avoids an ambiguous previous-performance merge without restricting exercise order. Later repeated blocks can be a deliberate schema extension.

**WorkoutSession**

```text
id: String                   persistent installation ID + monotonic session sequence
sessionSeq: Number           locally increasing; use to order cache/history
templateId: String; templateRevision: Number; templateName: String
startedAt: Number; endedAt: Number?
status: String               active | paused | finalizing | completed | aborted
completionKind: String?      full | partial, only for completed sessions
exercises: Array<SessionExercise>
rest: ActiveRestTimer?
timedRun: Dictionary?         entryId, slot, startedAt, accumulatedSec
pauseStartedAt: Number?; pausedSec: Number
lastCheckpointAt: Number
recoveryGapSec: Number        informational, excluded from active duration
elapsedSec: Number?           endedAt - startedAt, nonnegative
activeSec: Number?            elapsed excluding explicit pauses/recovery gaps
nextSetSequence: Number       actual chronological order across exercises
lastCompleted: Dictionary?    entryId + slot, for receipt/undo targeting
recording: Dictionary         enabled, phase, segmentCount, interrupted, lastError
finalization: Dictionary?     outcome, targetHistorySlot, cacheApplied, archiveWritten
```

`recording.phase`: `off | starting | recording | paused | closing | saved | failed | unknown`. Persisted phase describes intent/last observed outcome, never proves an OS recording object survived. Do not serialize that object. No HR time series in local history.

**SessionExercise**

```text
entryId: String; exerciseId: String
name: String; loadType: String; loadUnit: String?
weightIncrement100: Number?; restSec: Number
plannedSetCount: Number; targetRepsMin: Number?; targetRepsMax: Number?
targetDurationSec: Number?; notes: String?
closedEarly: Boolean
slots: Array<Dictionary>      exactly plannedSetCount slots
last: Dictionary?            source sessionSeq/id/date + prior performed set tuples
```

Each slot contains `draft {load100?, reps?, durationSec?, measuredSec?, targetAlertConsumed?}` and `completed: CompletedSet?`. `measuredSec` is accumulated paused stopwatch time, never a completed set. The last-performance snapshot is frozen at session creation, so finishing another session or editing templates cannot change “Last” mid-workout. The session owns display snapshots; template edits affect future workouts only.

**CompletedSet**

```text
slot: Number                 zero-based planned slot
sequence: Number             chronological sequence within this session
completedAt: Number; updatedAt: Number
load100: Number?; reps: Number?; durationSec: Number?
durationSource: String?      measured | manual for timed sets
```

Only completed sets count toward progress. A non-null draft is not proof a set was performed. Normal/bodyweight/assistance sets require actual reps ≥ 1. Failed attempts with zero reps are outside v1; undo mistaken logging. Timed completion requires actual duration ≥ 1 second. Zero loaded weight or assistance is valid. Null and zero are not interchangeable.

**ActiveRestTimer**

```text
id: Number                   generation counter
entryId: String; slot: Number
startedAt: Number; durationSec: Number; endsAt: Number
state: String                running | expired | dismissed | paused
remainingWhenPausedSec: Number?
alertConsumed: Boolean
```

**AppSettings**

```text
schemaVersion: Number        1
unit: String                 kg
defaultRestSec: Number        90
vibrationEnabled: Boolean    true
recordGarminActivity: Boolean true
touchLoggingEnabled: Boolean false
```

**Last-performance cache entry:** exercise ID, load type, unit, source session ID/sequence/end time, and ordered performed tuples `[slot, load100?, reps?, durationSec?]`. At most one source session per exercise. Never synthesize a session from different historical days.

**Storage representation:** persist dictionaries/primitive arrays, no custom class instances, Date/Moment, timers, methods, symbols, or circular references. `Store` packs repeated CompletedSet and last-performance tuples into fixed-order arrays documented next to encode/decode functions; higher-level code uses named dictionaries. No custom binary codec or compression.

**Product limits, validated at boundaries:** 32 exercises; 8 templates; 12 exercises per template; 10 sets per exercise; 60 sets per workout; 1–100 reps; 1–3,600 seconds per timed set; 0–1,800 seconds rest; load 0–999.75 kg; increments 0.25–100 kg in 0.25 kg steps. Names/notes must satisfy byte and rendered-width handling separately. These are deliberate MVP ceilings, not Garmin API limits. Catalog plus overrides must also pass the measured storage budgets in section 7.

**Seed fixtures** — kg unless stated. Missing lower-workout increments are a product default of 5 kg, adjustable on-watch.

| Template / exercise | Sets × target | Initial load | Rest | Increment |
|---|---:|---:|---:|---:|
| Upper / Seated Row Machine | 3 × 9 | 55 | 120 s | 5 |
| Upper / Machine Chest Press | 3 × 8 | 65 | 120 s | 5 |
| Upper / Reverse Pec Deck | 2 × 11 | 40 | 60 s | 5 |
| Upper / Machine Shoulder Press | 2 × 8 | 45 | 120 s | 5 |
| Upper / Assisted Pull-up | 2 × 10 | 30 assistance | 120 s | 5 |
| Upper / Assisted Dip | 2 × 10 | 30 assistance | 75 s | 5 |
| Upper / Machine Lateral Raise | 2 × 10 | 40 | 60 s | 5 |
| Upper / Machine Preacher Curl | 3 × 12 | 30 | 75 s | 5 |
| Lower / Leg Press | 4 × 9 | 213 | 150 s | 5 |
| Lower / Lying Leg Curl | 2 × 10 | 50 | 90 s | 5 |
| Lower / Single-leg Machine Hip Thrust | 2 × 10 | 60 | 90 s | 5 |
| Lower / Leg Extension | 2 × 10 | 55 | 60 s | 5 |
| Lower / Hip Abduction Machine | 2 × 10 | 75 | 60 s | 5 |
| Lower / Hyperextension | 2 × 10 | bodyweight | 60 s | — |
| Lower / Dead Bug | 3 × 35 s | timed | 60 s | — |

Upper totals **19** sets; Lower totals **17**. Seed hip-thrust notes: “One logged set means both sides completed; load is the machine setting.” Other unilateral conventions can use notes or separate left/right exercise IDs, not exercise-name conditionals. Add a rep-range case only in tests; seed targets remain exactly as supplied.

# 5. App/navigation state model

Separate three state domains:

1. **Session lifecycle:** absent → active ↔ paused → finalizing → completed/aborted. A restored active session first goes through a recovery decision. Finalizing cannot resume training or accept edits.
2. **Route:** HOME, TEMPLATE_LIST, TEMPLATE_DETAIL, WORKOUT_OVERVIEW, EXERCISE_ACTIVE, SET_EDIT, EXERCISE_SETS, ACTIONS, PAUSED, RECOVERY, WORKOUT_SUMMARY, HISTORY_LIST, HISTORY_DETAIL, SETTINGS, TEMPLATE_DEFAULTS, ERROR. A saved-set receipt is an inline message, not a route.
3. **Orthogonal clocks:** session rest and optional timed set. RESTING is not a route or workout-order state.

Main transitions:

```text
HOME → TEMPLATE_LIST → TEMPLATE_DETAIL → WORKOUT_OVERVIEW
WORKOUT_OVERVIEW → any EXERCISE_ACTIVE
EXERCISE_ACTIVE → next draft in EXERCISE_ACTIVE on successful completion
EXERCISE_ACTIVE → SET_EDIT → EXERCISE_ACTIVE for explicit correction
EXERCISE_ACTIVE → WORKOUT_OVERVIEW on BACK
Any workout view → ACTIONS → PAUSED / finish confirmation
Finish confirmation → finalizing → WORKOUT_SUMMARY
Launch with saved active state → RECOVERY → WORKOUT_OVERVIEW
Launch with finalizing state → finish pending writes → WORKOUT_SUMMARY
```

Every screen's BACK behavior is explicit. BACK at active overview opens session actions with Continue selected; it never pops the app root and accidentally ends a workout. Home BACK exits only when no unresolved session exists. Confirmation menus default to Cancel/Continue, not a destructive action.

Pause freezes rest, suspends any running timed set, and stops FIT recording without closing its in-memory object. Resume restarts deadlines from saved remaining values and resumes recording only if its object is known valid. Rest itself is part of activity time; it does not pause FIT.

Only the controller changes session lifecycle. Navigating between exercises does not change workout status, workout pause time, mark sets complete, stop FIT, or start a new rest. Leaving a running timed exercise for the overview automatically checkpoints and pauses that exercise's stopwatch, visibly labelled; it never blocks switching. Opening that exercise's own menu does not pause it.

# 6. Detailed screen/interaction specification

**Button policy:** START selects/completes; BACK returns; short UP/DOWN scroll or adjust the field explicitly labelled on screen; held UP opens the native Menu2 actions menu. LIGHT and held DOWN retain system behavior. Do not repurpose system music/control shortcuts. Physical locations and hold behavior follow the FR965 manual. [FR965 controls](https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-AU/GUID-F04730B5-B214-4E08-AA64-61D1C197F35F.html)

Input implementation: one consumed behavior event produces one command. For the exercise screen, handle raw ENTER separately from taps: `onSelect()` returns false and `onKey()` consumes `KEY_ENTER`; `onTap()` checks actual hit targets and the touch logging setting. Consume UP/DOWN/menu/back at one level only. Verify the exact dispatch in spike S2 before committing bindings. Never map an arbitrary screen tap to completing a set.

| Screen | Purpose/content | Physical controls and transitions | Touch and edge cases |
|---|---|---|---|
| HOME | App name; New workout, Recent workouts, Settings; Resume if applicable | UP/DOWN select, START open, BACK exit only if no pending workout | Native menu tap/scroll. Only one active workout; New is unavailable until it ends. |
| TEMPLATE_LIST | Template names and planned set totals | START → detail; BACK → Home | Native menu. Invalid templates disabled with reason; never silently drop entries. |
| TEMPLATE_DETAIL | Name, exercises, totals, Start workout, Edit defaults | START on Start creates/persists session, then attempts FIT, opens overview; BACK → list | Tap selected menu action. Start recording failure offers Retry or Continue without Garmin recording. Local session already exists and remains recoverable. |
| WORKOUT_OVERVIEW | Name, done/planned total, ordered exercise rows, per-row progress, rest banner and small recording indicator | UP/DOWN select, START opens any row, BACK or MENU → workout actions | Tap row; swipe scroll. Preserve selection on return. Complete and closed exercises remain selectable. No automatic list reorder. |
| EXERCISE_ACTIVE, reps types | Two-line title; explicitly labelled next set n/N; prior corresponding set; large draft load/reps; “UP/DOWN reps”; rest banner; compact saved-set acknowledgment | START immediately logs draft and prepares next pending slot; UP/DOWN always edit that next draft. MENU order is fixed: Edit last set, Edit next load, Set list, Last performance, Finish exercise, Rest actions. BACK → overview | Default taps select fields/open edit, never log. Optional labelled Complete target requires setting. Assistance explicitly says “assist”; bodyweight hides load. Edit last set targets this exercise and shows its slot/actual values; disable it until a set exists. |
| EXERCISE_ACTIVE, timed | Target, last actual duration, current stopwatch or paused measurement | START starts/resumes timed measurement; START again stops and logs whole seconds. MENU permits manual duration. BACK checkpoints and pauses stopwatch, then opens overview with “Timer paused” message | Switching never requires a modal confirmation. Per-slot paused measurement allows returning later. Opening this exercise's menu keeps timing; entering manual duration explicitly pauses it. Navigation never logs a set. |
| Inline set receipt | “Saved #n: 65 kg × 8”, while next set is explicitly labelled separately | No separate input mode: START logs the displayed next draft; UP/DOWN changes that draft; MENU → Edit last set corrects the labelled completed set | Message may fade after two seconds, but input meaning never changes with time. After the final planned slot show “Exercise complete / START: overview”, retain review/correction. Rest expiry only changes the rest banner/haptic. |
| SET_EDIT | Context label “Next set” or “Completed set #n”; one editable reps/weight/duration field, original value and step | UP/DOWN changes local buffer; START saves; BACK cancels; MENU switches field (reps/load for completed loaded sets) or chooses normal/×5/fine step | Edit last set initially focuses reps, or duration for timed work. Tap explicit +/−/Save targets. No all-weights picker. Corrections never restart rest. Bounds clamp visibly; invalid input cannot commit. |
| EXERCISE_SETS | Planned rows with actual completed values or draft; Last performance submenu shows all previous performed sets/date | START completed row → edit fields/undo action; START empty row → that slot; BACK → exercise | Selecting a later empty slot is allowed. Undo requires confirmation and applies to the identified slot, not an ambiguous global previous exercise. |
| Last performance detail | Date, source workout status “saved partial” when relevant, all performed set values with slot numbers | UP/DOWN scroll; START/BACK returns | Read-only. No previous → “No previous performance.” Long list scrolls; no overflow. Implement using existing detail/menu view, not another controller. |
| Workout ACTIONS | Continue workout, Pause workout, Finish & save, End without updating last performance, Resume later; rest actions when applicable | START executes or opens confirmation; BACK returns | The fourth choice is internally `aborted`; its confirmation explains local retention and exclusion from next-workout prefills. Resume later preserves progress and explains that leaving may split Garmin activity. Only abort confirmation exposes the separate Garmin save/discard choice, default Save. |
| Exercise ACTIONS | Edit load, Set list, Last performance, Finish early/Reopen, Rest actions | Finish early marks only the exercise closed; never invents completed sets. Reopen restores selection of pending slots | Same Menu2 interaction. If all slots done, show completed state and set review; no implicit extra set. |
| Rest actions | Remaining, Skip rest, +30 s, −30 s, Dismiss finished alert | START chosen operation, BACK returns | Accessible from overview and exercise menus. Skip clears current timer, not a set. No separate blocking rest screen. |
| PAUSED | Elapsed/active time, Resume, Finish, Save progress & exit | START selected action; BACK → same pause menu, no hidden resume | Rest and timed stopwatch frozen. Wall elapsed still grows; active duration excludes pause. |
| Finish/abort confirmation | Done/planned count, incomplete exercises, selected save/abort outcome | Cancel initially selected; START confirms | Partial finish says “Save 8 of 19 sets?” All sets done still requires explicit finish. Rest cleared after confirmed finalization. |
| RECOVERY | Template, completed count, last checkpoint, interruption notice, Resume, Finish saved progress, Abort | START chosen action; BACK returns to recovery menu without discarding | Missing recording continuity stated separately. Running timed set restored paused at last checkpoint, never credited with unattended time. Unknown schema/corruption shows protected error instead of blank new session. |
| WORKOUT_SUMMARY | Saved/aborted, set count, elapsed/active time, recording status including partial/unknown; Done | START Done → Home; BACK also Home after durable finalization | A failed archive/cache write remains on retryable finalization screen; “Workout saved” is not shown prematurely. |
| HISTORY_LIST / DETAIL | Four ended sessions, date/outcome/set count; one loaded detail at a time | START opens session/exercise details, UP/DOWN scroll, BACK returns | Read-only in v1. Corrupt record shown unavailable; do not misrepresent it as an empty workout. |
| SETTINGS | Haptics, recording toggle, touch logging toggle, default rest, exercise increment list | Native menu; numeric values reuse SET_EDIT | Available outside active workouts. Changes use configuration commit; kg displayed read-only. |
| TEMPLATE_DEFAULTS | Pick entry, then sets/rep bounds or duration/rest/start load; exercise increment opens exercise settings | Native menus + numeric editor; Save/Cancel | Future sessions only. Structural template creation/import is a development operation in v1. Invalid min/max or >60 sets rejected. |
| ERROR | Specific failure, retained set count, Retry and safe Return | START Retry, BACK returns only if safe | Storage failure must leave unsaved buffer visible. No infinite dialogs on each clock tick; disable further mutations until retry succeeds. |

Layout: black background, system fonts, explicit focus highlight, high contrast, no color-only progress. Display approximately three or four exercise rows rather than trying to fit all eight. Fit text using measured font width; wrap exercise title to two lines and elide only after that. Keep content inside the circular safe region. Set values take visual priority over hints. Render common banner with small text; if native menus cannot live-update it, expiry still vibrates and the banner refreshes on returning. Never add a full-screen rest takeover.

Interaction targets: one START to log unchanged values, including zero-rest sessions; BACK then row selection switches exercise. Draft reps use direct UP/DOWN. MENU + START opens Edit last set; corrections explicitly identify the completed slot and save once. Next-load editing uses MENU + DOWN + START, then ±increment and Save; touch may open the load field directly. Keep this menu order stable. Swapping these first two actions is a usability-probe decision only if evidence shows load changes dominate corrections.

Suppress activation repeats until button release and for 800 ms after a successful completion; show the saved acknowledgment immediately. Per-slot completion is idempotent. Test rapid double presses: the second must not complete the newly displayed next set. Do not introduce a rest-length lockout or block early logging.

# 7. Persistence/recovery design

## Keys and capacity

Use three independent two-generation domains and four bounded history slots. Keys are fixed strings, so no key enumeration API is needed.

| Keys | Contents | Maximum budget including record envelope |
|---|---|---:|
| `active.a`, `active.b` | Active session or terminal tombstone, packed drafts/actuals/last snapshot, clocks, recording status | 16 KiB each; 32 KiB total |
| `config.a`, `config.b` | Installation ID, next session sequence, AppSettings, exercise/template numeric overrides keyed by stable IDs and seed revision | 8 KiB each; 16 KiB total |
| `last.a`, `last.b` | Up to 32 last-performance cache entries, packed tuples | 12 KiB each; 24 KiB total |
| `history.0` … `history.3` | One compact ended session per slot, completed values and display/semantic snapshots; no unused drafts or frozen last-performance copies | 8 KiB each; 32 KiB total |
| Reserve | Storage encoding overhead and migration/operational headroom | 24 KiB of the provisional 128 KiB total |

Maximum planned payload/envelope budgets total **104 KiB**. These are capacity targets to validate, not a claim that dictionary JSON length equals Garmin's storage encoding size. S1 must measure actual persisted size with worst-case fixtures and both generations present. All values stay below the current 32 KB API limit. If the measured device cannot hold these budgets with margin, use the S1 fallback before implementing retention.

Templates/exercises live in the compiled local `seeds.xml` JSON resource. Only numeric overrides are written to `config`; do not duplicate the entire catalog in each generation. This still works with no phone/network. A future importer must validate and materialize a local catalog, but is not implemented now.

Every generation envelope is `{ "v": 1, "rev": Number, "payload": Dictionary }`. Validate envelope types, supported version, required fields, list lengths, IDs, references, enum values, bounds and inter-field invariants before use. No ad hoc object serialization, generic JSON stringify roundtrip, or undocumented object-store file editing.

## Commit protocol

```text
commitPair(domain, candidate):
    validate candidate and supported schema
    choose inactive/older valid generation; never overwrite the sole valid copy
    write envelope(version=1, revision=current+1, payload=candidate)
    read it back and validate; compare expected revision and logical payload
    only then return success and publish candidate to live controller
```

Readback is an application-level verification, not proof of flash atomicity. The protocol assumes a failed/interrupted write to one key does not destroy the other key; S1 must test that assumption. No separate head pointer or multi-key transaction is required. On load, select the highest valid revision. If only the older copy validates, recover it and show “Recovered earlier checkpoint.”

Catch type/storage exceptions. A `StorageFullException` does not justify deleting active data or cache. On active-write failure, offer Retry and retain the old persisted state plus the user's attempted values in RAM. Do not log additional sets until the failure resolves. History retention cleanup is done outside a set's critical commit, not speculatively in its error handler.

If a write may have succeeded but readback failed, reload both generations before retrying. If the candidate is now the newest valid payload, adopt it and acknowledge the existing completion; otherwise retry against the recovered revision. Never blindly overwrite a possibly newer generation or issue a second completion for the same slot. If neither outcome can be established, remain on the error screen with mutations disabled.

### What is persisted for each action

| Action | Durable changes before acknowledgment |
|---|---|
| Start workout | Allocate unique sequence in config first; then session snapshot, all prefills, timestamps and initial recording intent in active. Sequence gaps are harmless. |
| Complete set | Actual values, slot and chronological sequence, timestamps, next sequence, last-completed pointer, matching draft, new rest deadline/generation, checkpoint. Candidate includes all these changes in one active-record commit. |
| Correct set | Actual values and update timestamp; correction never changes completion time, sequence or rest deadline. |
| Undo | Remove actual, preserve its values as draft, clear `closedEarly`, and cancel rest only if sourced from this set. Recompute progress; no fabricated decrement counter. |
| UP/DOWN quick draft edit | Commit each accepted value change. Editor-buffer changes commit only on Save. Failed changes keep the buffer and old durable value. |
| Close/reopen exercise | `closedEarly`; no changes to performed sets or planned denominator. |
| Rest skip/adjust/expiry | New deadline/state/alert flag; no per-second writes. |
| Pause/resume | Pause timestamps/accumulated time, frozen or resumed rest, timed-run state, recording intent. |
| Running timed set | Start/pause/cancel/complete immediately; checkpoint measured elapsed every 30 seconds along with session checkpoint. |
| Active workout idle | Checkpoint at most once every 30 seconds, only while active; provides a bounded recovery point for duration accounting. |
| Navigation | No storage writes for selection/scrolling except checkpointing a timed measurement when leaving its exercise. Uncommitted editor buffer requires Save or Cancel before leaving. Restore to overview instead of rebuilding an old UI stack. |

## Boot and interruption recovery

1. Load config and active/cache generations independently. Missing keys on first install are normal; invalid existing values are not first install.
2. An unsupported newer schema is read-protected: show “Update app to resume”; do not overwrite either generation or seed a new active workout.
3. If a supported record has one corrupt generation, use the other and display the fallback warning. If both active copies fail, preserve them and offer explicit Reset active workout, with confirmation; history remains readable. No silent reset.
4. Resume a `finalizing` record idempotently before offering New workout.
5. For active/paused state show RECOVERY, not immediate automatic logging or recording. Session snapshots mean seed/template changes do not break recovery.
6. Resume local session from stored values. Treat the interval from `lastCheckpointAt` to recovery as an interruption gap excluded from active duration. Show that assumption; elapsed wall duration still includes it. Explicitly paused time must not be counted twice as a recovery gap.
7. Rest retains its absolute deadline across interruption. Future deadline → remaining time; past deadline → expired banner. No stale vibration on cold restart. A running timed set resumes **paused** at its last checkpoint, requiring explicit restart or manual correction.
8. On controlled “Save progress & exit,” persist paused local state, stop/save the current FIT segment, persist its outcome, then exit. On resume, a new segment is allowed. Show that multiple Garmin activities can result.
9. `onStop()` is best-effort cleanup, never the only persistence path. Check `:suspend` in S3/S4; v1 still uses its saved local checkpoint. Do not claim every forced termination calls `onStop()`.

## Finalization and history

Finalization must tolerate process death between any two writes:

```text
confirm Finish/Abort:
    commit active.status=finalizing, frozen outcome/end time/counts
    clear clocks; disallow training edits
    attempt close FIT segment; persist observed outcome (or unknown)
    build ended-session archive from frozen active data
    select history slot: existing same session ID, else empty, else oldest sequence
    persist target slot in active finalization state
    write/read-validate history slot
    merge eligible exercise performances into last-cache candidate
    commit last cache using two-generation protocol
    write active terminal tombstone(session ID, sessionSeq, final outcome)
    show summary
```

The active frozen session remains the retry source until archive and cache succeed. Re-running finalization replaces the same archive ID and applies cache entries only if their source sequence is older, or the same source is being replayed. It never appends duplicate history. A FIT save with an uncertain result is not automatically replayed on boot; mark it unknown and continue local finalization.

Archive eviction affects the oldest ended record only, never active state. Four slots are scanned on launch for summaries; load details one at a time. Aborted workouts occupy history slots but never update last performance. A completed partial workout does update cache for exercises with performed sets. Untouched exercises leave cache entries unchanged. Cache survives history eviction.

After a tombstone commit, replicate the tombstone to the other active generation when possible. If interrupted, the newer valid tombstone wins. If recovery falls back to an old finalizing snapshot, the archive ID/cache sequence checks make replay safe. A corrupt history slot is reported and can be reused on a later finalization; it must not erase a still-valid cache.

## Schema/update strategy

Start at schema 1; implement version dispatch and rejection now, not imaginary historical migrations. Fixture tests cover unsupported versions and malformed v1. For a future v2, add exactly one v1→v2 pure converter, write the new generation first, validate it, and preserve the old valid generation until success. A migration that cannot fit fails read-only; it does not wipe data.

Seed revision is distinct from storage schema. Existing sessions preserve snapshots. Match config overrides by stable IDs; ignore removed-entry overrides with a visible configuration notice. Cache IDs are never repurposed. Adding exercises beyond the 32-identity ceiling requires an explicit catalog revision and removal of unused identities or a future capacity change; do not silently evict last performance for an exercise still in the catalog.

# 8. Activity recording design

## Normal recording

At confirmed workout start, first persist local session creation. Then `Recorder` enables the HR sensor and creates/starts the recording. Check Boolean results and catch API exceptions. API option symbols are runtime-only and valid here:

```monkeyc
Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
_session = ActivityRecording.createSession({
    :name => "NextSet",
    :sport => Activity.SPORT_TRAINING,
    :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
});
var started = _session.start();
```

Use `Activity` constants; the corresponding older ActivityRecording constants are deprecated. Keep the recording name within Garmin's suggested 15-character limit. Do not enable GPS. Missing HR does not block set logging; expose “HR unavailable” and let Garmin record available metrics. [Activity constants](https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity.html), [Sensor API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html)

Transitions:

| Event | Recording action |
|---|---|
| Start workout | Start once, after local creation is durable. Failure → Retry or explicit local-only continuation. |
| Complete/edit/undo set; switch exercise; rest | Keep recording continuously. No automatic laps and no stop/start per set. |
| Explicit pause | Call `stop()`; retain session object, do not save. |
| Resume in same live process | Call `start()` on that known object, only if pause succeeded. |
| Finish | Freeze local end state, `stop()`, then `save()`; release object and disable owned sensor use only after successful closure. |
| Abort | Local aborted record remains. User explicitly chooses Save Garmin activity or Discard Garmin activity. |
| Controlled exit | Pause local session, stop/save current segment, mark segment count. Resumption creates a new segment. |
| Unexpected stop/reboot | Preserve local checkpoint; recording outcome becomes unknown unless verified otherwise. Never claim seamless FIT continuity. |

No external recorder objects are serializable. `createSession()` returning an existing object cannot be used as proof that a recovered FIT session belongs to the saved local workout. S4 must establish the FR965 behavior and provide a safe closure/recovery path.

**Fixed conservative fallback after cold interruption:** resume local logging with Garmin recording disabled for this session. Explain “Garmin recording was interrupted.” Do not call `createSession()` automatically to make a fresh segment until S4 proves it will not accidentally reuse an unclosed recording. If S4 exposes a safe save/recover procedure, expose it as a user action. If an unresolved OS session blocks later recordings, keep local mode available and give the verified device cleanup instruction from S4. Never discard an unknown recording silently.

**Failure semantics:** persist `starting`/`closing` intent before external calls and store observed result afterward. A crash between OS success and persistence creates an explicitly unknown result; there is no cross-system transaction. Do not retry an ambiguous save on reboot merely because local status says closing. In the same process, a documented false return can offer Retry. Local finish remains possible regardless of FIT failure; report “Workout saved locally; Garmin activity not confirmed.”

## What Garmin Connect should show

Target normal-case output: training/strength activity classification, elapsed/timer duration, HR samples and available summary metrics. Firmware/user profile may provide calories. Training load/effect must be observed, not invented or promised. No backfilling HR during app downtime, and no retrospectively constructing a complete Garmin activity from local sets.

The local session is the authority for names, sets, reps, weights, assistance and durations. Garmin FIT is a parallel recording. A local undo/correction does not rewrite previously emitted native data; this is another reason not to map sets to laps in v1.

**MVP FIT strategy: standard activity only.** Optional follow-up task: one `MESG_TYPE_SESSION` developer field `completed_sets` with field ID 0, integer data, `FitContributor` permission, and `fitContributions` resource metadata. Update it from committed totals. Verify extracted FIT independently; store/Connect rendering is a separate check. Do not ship custom exercise-string payloads, one developer field per set, arbitrary native message numbers, or `nativeNum` hacks as a substitute for native strength support.

# 9. Rest timer design

`NextSetApp` owns one `Timer.Timer` started at 1,000 ms while a workout is active and the app is running. It calls `controller.onTick(now, monotonicMs)` and requests redraw only when displayed time/status changes. Views never own the timer; `onHide()` does not cancel rest.

On normal set completion, include a new rest record in the same active commit as the completed set. The deadline starts at actual completion, so correction time counts as rest. `restSec == 0` creates no rest. Completing another set replaces the current rest with a new generation; no queue of simultaneous rests.

```text
remaining(rest, now) = clamp(rest.endsAt - now, 0, rest.durationSec)

tick:
    if running and remaining == 0 and not alertConsumed:
        commit state=expired, alertConsumed=true
        if commit succeeds and app can alert and not a cold recovery:
            vibrate once if enabled
        request redraw; do not navigate or change input meaning
```

Persisting consumption before vibration favors avoiding repeated alerts. A crash between the two can omit one alert; exactly-once external haptics across power loss is not guaranteed. Storage failure shows a warning and suppresses an uncommitted alert rather than producing repeated vibrations.

- **Changing screens/exercises:** countdown continues. The current visible workout view displays the session rest regardless of selected exercise. Origin exercise name appears in the rest actions menu.
- **While a numeric editor/menu is open:** vibrate on expiry, do not change focus, discard edits or pop views. Show updated status when the view redraws/returns.
- **Skip/dismiss:** persist dismissed state; no completion event is generated.
- **±30 seconds:** set a new deadline relative to current remaining time, clamp total remaining to 0–1,800; a zero result expires on the next tick. Clear the consumed flag only for a new positive running interval; increment timer generation.
- **Pause:** save remaining seconds and freeze; resume creates a new deadline. Explicit pause wins over wall-clock expiry.
- **App exit:** no claim that Timer callbacks or vibration continue. Deadline is restored on launch; expired rest displays a quiet “Rest finished while away.”
- **Display off:** distinguish this from process termination. S3 must demonstrate screen timeout, LIGHT, wrist gesture, notifications and music/system overlays. Normal display timeout must not erase session data; audible/haptic delivery under every system overlay is not guaranteed.
- **Clock changes:** during a live process compare wall-clock progression to monotonic progression. A discrepancy >5 seconds rebases the deadline from the last known remaining time, persists once, and shows a time-adjustment notice. Handle monotonic counter wrap/reset by reinitializing the runtime anchor. Cold recovery uses wall time with remaining clamped to the configured duration.

Timed exercises use the same one-second tick, but a separate `timedRun`, not the rest record. START begins/resumes timing; reaching target duration vibrates once while running but does **not** auto-complete. START stops and saves actual whole seconds. Leaving the exercise for overview checkpoints accumulated time into that slot's `draft.measuredSec`, clears `timedRun`, and visibly reports “Timer paused.” It does not open a blocking dialog. Returning permits START to resume the accumulated measurement. Each slot retains its own paused measurement, but only the displayed timed exercise can have a running anchor. This permits free exercise switching without concurrent stopwatches or unattended timing.

Manual duration override is labelled manual and pauses timing before entering its editor. Starting a timed run dismisses existing rest. Persist `targetAlertConsumed` in the slot draft so pausing/reopening does not repeat the target cue. Menus for the same exercise keep timing until an explicit edit/pause; exiting the exercise, pausing the workout or leaving the app checkpoints and pauses it.

# 10. Previous-performance/prefill algorithm

**Definition of “last”:** latest locally finalized `completed` session by monotonic session sequence, containing at least one performed set for the same stable exercise ID and matching load semantics. It can be from another template. A saved partial workout qualifies; an active, finalizing, aborted, discarded, or corrupted workout does not. A finalizing session becomes eligible only as part of successful local finalization; recovery completes that operation before New workout is available.

Lookup uses the independent last cache, not a scan of only four retained sessions. Session sequence is the primary ordering key so a watch-clock adjustment does not reverse training history. Date/time is display metadata.

At session creation, snapshot previous performance and prefill every planned slot:

```text
prior = cache[exercise.id] if id/type/unit all match, else null
performed = prior.sets ordered by original slot

for slot in 0 .. plannedSetCount-1:
    source = prior set with this slot, if any
    if source absent and performed nonempty:
        source = last performed set in prior session

    load = source.load100 if valid else entry.startingLoad100 else 0
    reps = source.reps if valid else entry.targetRepsMin else 1
    seconds = source.durationSec if valid else entry.targetDurationSec

    choose only fields appropriate to exercise loadType
    create uncompleted draft; do not mark any set performed
```

Rules:

- A rep range prefills its lower bound when there is no history. Show the whole target range separately. Prior actual reps may fall outside the current target range; preserve them, display the target, and let the user decide.
- If the plan grows from three to five sets, use prior sets 1–3 for the corresponding slots and repeat prior set 3 for slots 4–5. If it shrinks to two, use prior sets 1–2. Never average values.
- If a saved partial workout performed only slots 1 and 3, preserve those slot mappings; an unmatched slot uses the last performed set, here slot 3. Show full prior history with slot labels so this is visible.
- For assistance, carry the actual assistance value unchanged. Never negate it, subtract body mass, or automatically lower it.
- For bodyweight, copy reps only. For timed work, copy actual duration only; countdown target is still displayed separately.
- “No previous” must be distinguishable from 0 kg. A missing default loaded weight becomes 0 kg and is labelled “Set load” until edited or intentionally confirmed by START.
- Completing or correcting today's set does not alter the stored baseline or auto-change later prefilled slots. The next slot already has its own prefill. This preserves heterogeneous prior sets and avoids hidden propagation rules.
- Exercise display-name change retains history. Semantic change requires a new ID. Unknown or mismatched cache entries do not prefill anything.

At finalization, for every exercise with at least one completed set, replace its cache entry with that session's performed values. A partial current session replaces the whole prior performance for that exercise; do not append old sets to make the new one look complete. Zero performed sets leave prior data unchanged. Do not update cache after each set or on abort.

For a missing/corrupt entire cache, reconstruct the most recent eligible values from retained history as a best effort and state that older context is unavailable. This is a repair fallback, not the normal lookup strategy.

# 11. Exercise-order behavior

The session contains an array in template presentation order and a UI-selected `entryId`; there is no workout-wide “current exercise index” that determines what is allowed.

- Every row is selectable at all times unless finalization is in progress. Opening a row chooses its lowest uncompleted slot, or its set list if complete/closed.
- Completing Chest Press set 2 does not advance another exercise or make Seated Row mandatory.
- Leaving an exercise preserves actuals and accepted drafts. Returning chooses its next uncompleted slot. Slot identity remains stable even when another exercise is performed in between.
- An explicitly selected later empty slot can be logged. The global `sequence` records actual chronology independently of slot order and template order.
- Undo opens that slot again; it does not undo anything from a subsequently visited exercise.
- Finish exercise early only sets `closedEarly=true`. Reopen allows more planned sets. No fake zero-rep sets, no denominator reduction.

Progress is derived:

```text
completedCount(ex) = number of non-null completed slots
plannedCount(ex)   = plannedSetCount
workoutDone       = sum completedCount
workoutPlanned    = sum plannedCount
```

Row presentation:

| Condition | Row label/status |
|---|---|
| 0 completed, not closed | Hollow circle + `0/N` / Untouched |
| 1…N−1 completed, not closed | Filled dot + `k/N` / Partial |
| N completed | Check mark + `N/N` / Complete |
| closed early with k < N | Dash/closed icon + `k/N closed`; never the complete check mark |

Reaching all planned sets or closing every exercise offers Finish but does not auto-save/end the workout. The user must explicitly Finish. Status `completed` means the user saved the workout; `completionKind=full` only when every planned slot was performed, otherwise `partial`. A zero-set workout offers Abort instead of saving a completed empty workout.

Supersets are deferred from the core MVP. If added later, `supersetGroupId` selects a suggested next row only. It cannot restrict the overview, completion, rest ownership, or cache identity. No implicit rest-after-round semantics in v1.

# 12. Project directory/file layout

Files below are the intended implementation, not files created by this planning task. Keep test/spike code out of release source paths.

```text
NextSet/
  IMPLEMENTATION_PLAN.md
  README.md
  manifest.xml
  monkey.jungle
  tests.jungle
  .gitignore
  resources/
    strings/strings.xml
    drawables/drawables.xml
    drawables/launcher.png
    data/seeds.xml
  source/
    NextSetApp.mc
    Catalog.mc
    Model.mc                 enums, limits, validators, compact-record codecs
    SessionLogic.mc
    SessionController.mc
    Store.mc
    LastPerformance.mc
    RestClock.mc
    Recorder.mc
    ui/
      Navigator.mc
      Menus.mc               home/templates/actions/history/settings + delegates
      OverviewView.mc        custom scrolling view + delegate
      ExerciseView.mc        ready/timed rendering, inline receipt + delegate
      NumberEditView.mc      numeric editor + delegate
      SummaryView.mc         workout/history summaries and recovery/error content
      UiFormat.mc            shared load/time/text/status formatting
  tests/
    ModelTests.mc
    SessionTests.mc
    StoreTests.mc
    PrefillTests.mc
    ClockTests.mc
    Fixtures.mc
  spikes/
    README.md
    probe.jungle
    manifest.xml
    resources/strings.xml
    ProbeApp.mc
  docs/
    TOOLCHAIN.md
    SPIKES.md
    DEVICE_TESTS.md
    RELEASE.md
  bin/                       ignored
```

Combine each view and its delegate in one file. `Menus.mc` may contain several small native-menu builders/delegates; do not create one file per menu item. Do not add a separate class for every model record. Do not add extra dependencies.

Seed resource uses Garmin JSON data resources, loaded once by `Catalog` and validated at launch; no runtime network or filesystem import. [Resource definitions](https://developer.garmin.com/connect-iq/articles/core-topics/Resources.html)

Toolchain record must contain SDK version, FR965 device package revision, simulator version, host OS/Java, watch firmware used for validation, and exact build/test commands. Example command shapes, verified/adjusted against installed SDK help in T001:

```sh
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y /secure/path/developer_key.der
connectiq
monkeydo bin/NextSet.prg fr965
monkeyc -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y /secure/path/developer_key.der --unit-test
monkeydo bin/NextSet-tests.prg fr965 -t
```

The documented test switch varies by host (`/t` on Windows); record the actual macOS invocation from installed help instead of guessing when a command fails. VS Code Test Explorer is an equally valid test runner. Build from the repository root, make `bin/` before compilation, and retain full failure output. [Garmin unit-test workflow](https://developer.garmin.com/connect-iq/articles/core-topics/Unit_Testing.html)

Developer workflow: install SDK Manager and Garmin Monkey C extension; verify installation; obtain FR965 device definition; generate or configure the signing key **outside the repository**; build for `fr965`; run simulator; copy the device-specific `.prg` to the watch's `GARMIN/APPS` directory using the available USB/MTP transfer workflow; disconnect safely and launch from activities/apps. Verify that transfer path and method in T001 on the actual host/watch. Keep one stable application UUID and key across updates to preserve app identity. Never commit signing keys or device diagnostic dumps containing unrelated user data.

Store preparation is a later packaging step: manifest declares only tested `fr965`, correct name/entry point/icon/minSdkVersion/permissions, English strings, signed `.iq`, screenshots, accurate offline/storage/recording limitations, version/release notes, and required listing/contact/privacy information. Check the current submission form and Garmin review requirements at release time. Export and validate the package in the MVP; public submission is outside this task. [Garmin submission workflow](https://developer.garmin.com/connect-iq/submit-an-app/)

# 13. Milestones

Execute sequentially. “Pass” includes an actual test result or clearly recorded hardware block; do not replace a required device test with an architectural assertion. Every milestone compiles for FR965 and retains previous passing checks.

| Milestone | Tasks / dependencies | Files created or modified | Acceptance and verification |
|---|---|---|---|
| M0 — Platform evidence | T001–T005; no dependencies | Build/manifest/resources skeleton, `source/NextSetApp.mc`, `spikes/*`, `docs/TOOLCHAIN.md`, `docs/SPIKES.md`, `README.md`, `.gitignore` | Simulator launches; device sideload works; storage/input/screen-off/recording probes documented. Run separate probe app so destructive storage experiments cannot touch user workouts. Required failures select the prescribed fallback before continuing. |
| M1 — Domain and seed truth | T006–T008; M0 | `Model.mc`, `Catalog.mc`, `SessionLogic.mc`, seed resource, `tests/ModelTests.mc`, `tests/SessionTests.mc`, `tests/Fixtures.mc`, `tests.jungle` | Exact 19/17 set seeds; semantic validation; arbitrary selection, sparse slots, correction and undo pass pure tests. Simulator test runner reports pass. |
| M2 — Durable commands and recovery | T009–T011; M1 | `Store.mc`, `SessionController.mc`, `NextSetApp.mc`, `tests/StoreTests.mc`, session tests | Restart after every accepted set restores actuals. Inject storage failures and damaged generations. No false success/duplicate sets. Basic recovery screen may use native menus. |
| M3 — Gym interaction | T012–T016; M2 | `ui/Navigator.mc`, `Menus.mc`, `OverviewView.mc`, `ExerciseView.mc`, `NumberEditView.mc`, `UiFormat.mc`, strings and controller | Buttons alone start, switch, log, correct, undo and close/reopen. Simulate A1→B1→A2. Device probe verifies input and legibility. No timers/recording required yet. |
| M4 — Ended sessions and context | T017–T019; M3 | `LastPerformance.mc`, `Store.mc`, controller, `SummaryView.mc`, `Menus.mc`, prefill/store tests | Partial completed versus aborted distinction, idempotent finalization, four-session eviction, independent cache. Two sessions in different templates prefill correctly on simulator. |
| M5 — Clocks and interrupted workouts | T020–T023; M4 | `RestClock.mc`, app/controller/session logic and workout UI, clock/session/store tests | Navigation-safe rest, exactly one foreground alert attempt, no stale restart alert, timed logging, pause/recovery behavior. Run screen-off/haptic device checklist. |
| M6 — Garmin activity | T024–T026; M5 and S4 evidence | `Recorder.mc`, app/controller/menus/summary, manifest, device test record | HR FIT with duration in normal case; graceful local-only failures; pause/finish/exit verified. Extract FIT and inspect Garmin Connect after one device sync. No native set-table claim. |
| M7 — Configuration and delivery | T027–T031; M6 | Menus/editor/catalog/store/settings resources, tests, documentation and release assets | Watch numeric settings persist, capacity and interruption suite passes, full Upper/Lower workouts offline, `.prg`/`.iq` reproducible. No release signing key in repo. |

First usable internal workout build: M3 with seeded values, set logging and durability. Do not call it the full MVP until M7 passes, because previous performance, timers and real-device recording are core validation goals.

# 14. Coding-agent task list T001…

**Execution rules for every task:** read this plan and repository instructions first; execute IDs in order; modify only listed files plus a necessary existing string resource; do not add dependencies or refactor unrelated modules. Compile before marking complete. Record command/result in the task's documentation or commit description. If a platform gate fails, use section 16's fallback; report the evidence instead of inventing an API. All application behavior is defined above. No task authorizes cloud/phone work, publishing, or a progression engine.

**T001 — Create and verify the FR965 skeleton.** Dependency: none. Create `manifest.xml`, `monkey.jungle`, `.gitignore`, `README.md`, `source/NextSetApp.mc`, `resources/strings/strings.xml`, `resources/drawables/drawables.xml`, `resources/drawables/launcher.png`, `docs/TOOLCHAIN.md`. Use watch-app/FR965/minimum API 5.2.0, stable app UUID, 65 × 65 simple icon, and a Home placeholder. Configure SDK 9.2.0 and external signing key. Do not add workout logic. Acceptance/test: compile, simulator launch/exit, device sideload/launch; record actual commands and firmware. Key and `bin/` ignored.

**T002 — Probe storage before selecting retention.** Dependency: T001. Create `spikes/probe.jungle`, `spikes/manifest.xml`, `spikes/resources/strings.xml`, `spikes/ProbeApp.mc`, `spikes/README.md`, `docs/SPIKES.md`. Give probe a different UUID. Implement S1 only: size/write/read/restart, alternate keys, forced interruption, all proposed records loaded/written at maximum. No production Store yet. Acceptance/test: evidence for aggregate capacity, maximum entry, measured encoded bytes and memory, two-key fallback behavior; explicitly select standard budget or S1 fallback. Production data untouched.

**T003 — Probe input and display lifecycle.** Dependency: T002. Modify only `spikes/ProbeApp.mc`, `docs/SPIKES.md`. Implement S2 and S3: log consumed behavior/raw/touch events and lifecycle callbacks; display one deadline and issue one vibration. Do not modify production bindings. Acceptance/test: one ENTER yields one action; menu hold has no preceding value increment; background/display/notification cases documented; screen-off rest checked on device. Adopt native Menu2 bindings if event shortcuts fail.

**T004 — Probe Garmin recording and recovery.** Dependency: T003. Modify `spikes/ProbeApp.mc`, `spikes/manifest.xml`, `docs/SPIKES.md`. Implement S4: HR enablement; training/strength recording; start/stop/start/save; normal exit, suspension, kill/reboot; observe `createSession()` existing-object behavior and save outcomes. No native FIT-message experiments or production recovery guesses. Acceptance/test: inspect one exported FIT; record duration/HR/calories and actual Connect result; establish safe cold-recovery behavior or enforce local-only fallback.

**T005 — Freeze platform gates and build exclusions.** Dependency: T004. Modify `docs/SPIKES.md`, `docs/TOOLCHAIN.md`, `monkey.jungle`, `README.md`. Complete S5 memory/layout probe results using `spikes/ProbeApp.mc` if necessary. List verified versus still blocked hardware cases. Ensure spikes and tests are excluded from release builds. Do not change domain policy. Acceptance/test: clean production build, probe build, documented budget/input/recording decisions. If normal screen-off reliability or storage recovery fails without its specified fallback passing, stop platform-dependent implementation and report the blocker.

**T006 — Define validated records and fixtures.** Dependency: T005. Create `source/Model.mc`, `tests/ModelTests.mc`, `tests/Fixtures.mc`, `tests.jungle`. Implement enum constants, limits, field validation and explicit encode/decode of only the repeated record tuples. No persistence API/UI. Acceptance/test: valid four load types roundtrip; null versus zero preserved; wrong types, unknown enums, oversized lists/strings, semantic mismatches and invalid numeric ranges rejected. Use Garmin's existing Test module, no framework.

**T007 — Load exact seed catalog and numeric overlays.** Dependency: T006. Create `resources/data/seeds.xml`, `source/Catalog.mc`; extend `tests/ModelTests.mc`. Implement the supplied 15 exercises and two templates, stable IDs, entry IDs, revisions, default-rest resolution and validated numeric overrides. No hardcoded exercise conditionals. Acceptance/test: Upper=19 and Lower=17, 213 kg preserved, assistance distinct, Dead Bug timed, hip-thrust note present, duplicate exercise IDs within a template rejected. Verify resource loads in simulator.

**T008 — Implement pure session commands.** Dependency: T007. Create `source/SessionLogic.mc`, `tests/SessionTests.mc`; modify `tests/Fixtures.mc` as needed. Build independent session snapshots; complete/correct/undo/close/reopen and compute status/totals using explicit IDs, slots and supplied time. No Storage, UI or recorder. Acceptance/test: A1→B1→A2, slot 3 before slot 2, double completion refused, undo of A after visiting B, early close/reopen, candidate changes do not mutate original nested values.

**T009 — Implement two-generation persistence.** Dependency: T008. Create `source/Store.mc`, `tests/StoreTests.mc`; extend `Model.mc` only for envelope validation. Implement fixed-key read/validate/write/readback, generation selection, future-version protection, tombstones, and error results. Isolate the few storage calls behind overridable Store methods for test injection; no generic storage framework. Acceptance/test: first write, corrupt newest, both corrupt, write failure, ambiguous readback/retry, unsupported schema, cold reload. Match S1's actual budgets.

**T010 — Add transactional controller commands.** Dependency: T009. Create `source/SessionController.mc`; extend `tests/SessionTests.mc`, `tests/StoreTests.mc`. Wrap T008 operations with candidate commit and acknowledgment. Add sequence allocation/config initialization, set retry reconciliation and no-second-session guard. No FIT or timer callbacks yet. Acceptance/test: injected failed write leaves live state/counts unchanged; successful retry creates one set; restarting controller yields same completed values and snapshots.

**T011 — Add boot and basic recovery routing.** Dependency: T010. Modify `source/NextSetApp.mc`, `source/SessionController.mc`; create minimal `source/ui/Navigator.mc`, `source/ui/Menus.mc`, `source/ui/SummaryView.mc`. Wire startup validation and Recovery with Resume/Finish later/Abort choices; unsupported/corrupt state error is protected. Finish remains disabled until T018. Do not silently seed over invalid records. Acceptance/test: force simulator stop after two sets, relaunch, Resume shows two; future-schema fixture cannot start a replacement workout; one valid generation recovers visibly.

**T012 — Build start flow and flexible overview.** Dependency: T011. Modify `Navigator.mc`, `Menus.mc`; create `source/ui/OverviewView.mc`, `source/ui/UiFormat.mc`. Add Home/templates/detail/start and overview in template order. No new session semantics. Acceptance/test: 19/17 totals, all rows reachable with buttons, round-screen clipping handled, selected row retained, active overview BACK opens actions and cannot exit. Device screenshot/inspection verifies readable partial/closed statuses.

**T013 — Build normal set and receipt input.** Dependency: T012. Create `source/ui/ExerciseView.mc`; modify Navigator and controller only to wire existing commands. Implement ready views with inline receipts for weight, assistance and bodyweight; START logs durably and shows next draft; UP/DOWN always edits the displayed draft. No timer-driven navigation. Acceptance/test: one START/one set, including zero rest; activation repeats until release and within 800 ms cannot log another; default touch cannot complete; 0 assistance displays correctly; BACK preserves data.

**T014 — Implement numeric editing.** Dependency: T013. Create `source/ui/NumberEditView.mc`; modify ExerciseView, Menus, UiFormat. Implement editor buffer, normal/×5/fine increments, bounds, Save/Cancel, and explicit completed-set corrections. No scrolling weight picker or unit conversion. Acceptance/test: 65→70 in one increment; 213→218 preserves offset; 2.5 kg step uses exact integer arithmetic; BACK cancels; failed Save retains editor; changing actuals preserves completion timestamp and count.

**T015 — Implement set review, undo and early close.** Dependency: T014. Modify Menus, ExerciseView, Navigator, controller; extend session tests only for previously untested wiring invariants. Add per-slot set list, explicit undo confirmation, lowest-empty return behavior, close/reopen. No additional sets beyond planned count. Acceptance/manual: A1→B1→A2, undo A1, review B untouched, refill A1, close A partial, reopen and complete. Check selection with touch off.

**T016 — Verify interaction budget and navigation safety.** Dependency: T015. Create `docs/DEVICE_TESTS.md`; modify only UI files with defects revealed by testing. Exercise full Upper/Lower button paths, names/notes, long rows, menu cancel and system shortcuts. Do not add features. Acceptance/test: unchanged set one press; last-set correction MENU+START; next-load editor MENU+DOWN+START; all rows accessible; no double dispatch or accidental root exit; documented device observations, not simulator-only claims.

**T017 — Implement last-performance selection and prefill.** Dependency: T016. Create `source/LastPerformance.mc`, `tests/PrefillTests.mc`; modify Catalog/session creation/controller for frozen baselines. Implement section 10 literally. No progression or propagation to future drafts. Acceptance/test: cross-template match; partial replacement; aborted exclusion; increased/decreased set count; sparse prior slots; types/units mismatch; assistance unchanged; timed actual copied; no history lower rep bound. Fixture-driven tests run in simulator.

**T018 — Implement durable finalization and bounded history.** Dependency: T017. Modify Store, controller, Model, Menus, SummaryView and store tests. Implement frozen finalizing state, fixed target history slot, cache commit, tombstone, and idempotent recovery; recording is still off. Acceptance/test: inject failure/restart after every write; one archive ID only; no lost pending finalization; four-slot eviction leaves cache; aborted sets never prefill; zero-set save redirects to abort. Finish summary requires durable completion.

**T019 — Expose history and previous-performance detail.** Dependency: T018. Modify Menus, SummaryView, ExerciseView, Navigator. Add recent list, per-session exercise/set detail and all prior sets/date within an exercise. No history editing/deletion feature. Acceptance/manual: fifth ended session evicts oldest; cache still prefills an exercise absent from the four records; saved partial clearly labelled; one corrupt history record does not break the list; load one detail at a time.

**T020 — Implement pure clocks.** Dependency: T019. Create `source/RestClock.mc`, `tests/ClockTests.mc`; update Model for timed-run state. Implement remaining/expiry/skip/adjust/pause/resume and monotonic-discontinuity policy, taking times as arguments. No Timer or vibration in pure module. Acceptance/test: delayed callback, zero duration, ±30 bounds, replacement generation, clock jump, pause during rest, expired restore, integer overflow/reset anchor handling.

**T021 — Wire rest timer and foreground alert.** Dependency: T020. Modify app, controller, ExerciseView, OverviewView, Menus, clock/store tests. Own exactly one timer; persist set+rest together and alert consumption before haptic; render shared rest status; rest expiry never transitions screens or changes edit targets. No Background service. Acceptance/manual: 60-second rest survives A→B navigation, one vibration while editor open without losing edits, no stale alert after restart, skip and replacement work; S3 screen-off checklist repeated with actual app.

**T022 — Implement timed exercises.** Dependency: T021. Modify SessionLogic, controller, ExerciseView, OverviewView, Model, session/clock tests. Add start/pause/resume/cancel/complete timed run, checkpointed elapsed, target cue and manual-duration edit. No auto-completion at target; no simultaneous running timed sets. Acceptance/test: Dead Bug target35, stop38 saves38; restart restores paused checkpoint; BACK to overview automatically pauses measured time without blocking; another exercise can be opened/logged immediately; returning resumes the stored measurement; target cue is consumed once.

**T023 — Complete pause, elapsed time and recovery behavior.** Dependency: T022. Modify app/controller/menus/summary/store/session/clock tests. Add explicit workout pause, 30-second checkpoints, recovery-gap accounting, saved paused rest and controlled local exit. Recording remains a no-op until T024. Acceptance/test: elapsed ≥ active, no double subtraction for previously paused recovery, wall rest expiry while away, timed set gains no unattended seconds, completed sets survive forced termination at each action boundary.

**T024 — Implement isolated Recorder.** Dependency: T023 and passing S4 normal recording. Create `source/Recorder.mc`; modify manifest only for Fit/Sensor and app ownership. Implement enable/start/stop/resume/save/discard, Boolean/exception checking, known-object tracking, and cleanup. Do not write sets or add FitContributor. Acceptance/manual: short simulator recording and physical FR965 recording with HR; save success verified by FIT extraction, pause gap present, object released after success. Failed HR still permits local workflow.

**T025 — Integrate recording outcomes with session lifecycle.** Dependency: T024. Modify controller, app, Menus, SummaryView, store tests using a small fake Recorder object. Wire intent-before-call/outcome-after-call, local-only choices, finalization, controlled-exit segments and unknown cold-interruption fallback. Do not assume cross-process object restoration. Acceptance/test: start/save failure cannot lose local sets; crash between OS save and outcome write does not auto-save twice; Resume after cold interruption remains local-only unless S4 established safe behavior.

**T026 — Validate FIT and Garmin Connect presentation.** Dependency: T025. Modify `docs/DEVICE_TESTS.md`, `docs/SPIKES.md`; fix only Recorder/integration defects found. Perform a real 10-minute session with HR, pause, rest and final save; inspect extracted FIT and synced Connect activity. No developer field/native set-table work. Acceptance: duration and HR evidenced; calories/load/effect reported as observed or absent; unrelated activities unaffected; controlled exit documents resulting segments. Store listing claims match evidence.

**T027 — Add watch settings and numeric template editing.** Dependency: T026. Modify Menus, NumberEditView, Catalog, Store, controller, Model tests. Implement settings, per-exercise increments, per-entry counts/reps/rest/default-load/duration; config generation commits; edits available only outside active workouts. No text-entry template builder. Acceptance/test: restart retains edits, existing history unchanged, invalid rep range/61st planned set rejected, 0 rest valid, increment can be 2 or 2.5 kg, source seed changes do not overwrite compatible overrides.

**T028 — Run corruption, retention and memory regression.** Dependency: T027. Modify test files and `docs/DEVICE_TESTS.md`; fix only demonstrated defects in owning modules. Fill permitted catalog/overrides/active/cache/history with worst-case values and long UTF-8 text. Acceptance: all encoded budgets from S1 respected, at least 25% runtime-memory headroom at peak including candidate copies, recording and UI; failure paths preserve active records; no repeated navigation leak; all automated tests pass. No extra abstractions as a cleanup pass.

**T029 — Complete two offline gym-style acceptance sessions.** Dependency: T028. Modify `docs/DEVICE_TESTS.md`, plus narrow UI/logic defect fixes and corresponding tests. Run Upper and Lower entirely with phone disconnected; touch disabled. Deliberately use different exercise orders, early close/reopen, correction, pause, screen timeout and one exit/recovery. Acceptance: every set accounted for, 19/17 totals when fully completed, timed35+/assistance correct, next workout prefills saved actuals; no phone required during sessions.

**T030 — Prepare reproducible internal release package.** Dependency: T029. Create `docs/RELEASE.md`; update README, TOOLCHAIN, manifest version, launcher/strings only as required. Clean debug and release builds; export signed `.iq` and device `.prg`; document installation/update, limitations and test evidence. Do not publish or change app ID/key. Acceptance: package declares FR965 only, permissions minimal, tests/spikes/keys excluded; install update over previous build without losing saved sessions/config/cache; unsigned secrets absent.

**T031 — Definition-of-Done audit.** Dependency: T030. Modify `docs/RELEASE.md` and `docs/DEVICE_TESTS.md` only, unless a named blocking defect requires a narrow fix plus rerun of its tests. Check every item in section 18. Record unresolved device-dependent limitations plainly. Acceptance: all required evidence linked, deterministic fallback choices documented, no unperformed hardware checks marked passed, no scope additions. Deliver artifacts and instructions for the next agent/user.

**Optional after MVP, not in the critical sequence:** add `resources/fitcontributions/fitcontributions.xml` and a single completed-sets summary field in Recorder, with FitContributor permission and extracted-FIT validation. A separate future task may implement superset suggestions. Neither is needed to satisfy T031.

# 15. Testing plan

## Automated simulator tests

Use Run No Evil with `(:test)` global functions and `Toybox.Test.assert`. Pass explicit wall/monotonic time into pure functions. For failure tests, subclass Store and override only its read/write/delete boundary methods to inject failures; use a small fake recorder with the concrete Recorder method surface. No production DI framework is needed.

| Test group | Required cases |
|---|---|
| Model/catalog | All four types; invalid IDs/references; null/zero; byte-length limits with Unicode; load bounds; reps range validation; 19/17 seed totals; explicit defaults; catalog/config capacity rejection. |
| Session behavior | Arbitrary exercise order; partial return; sparse slots; chronological sequence; no duplicate slot completion; correction preserves original completion time; undo/reopen; early close does not lower denominator; no false completed status; frozen template/history snapshots. |
| Persistence | Both generations missing; one/both corrupt; newer unsupported schema; failed write; successful write/failed readback; retry adoption; full store; malformed nested arrays; interrupted config sequence allocation; no mutation of old in-memory snapshot. |
| Finalization | Stop/relaunch after each finalization write; same history ID only once; cache source sequence never regresses; terminal tombstone replay; full/partial/aborted outcomes; fifth-history eviction; untouched cache preserved; corrupt-cache bounded reconstruction. |
| Prefill | Same exercise across templates; changed name; changed semantics/new ID; aborted exclusion; saved partial replacement; zero-performed no update; extra/fewer planned slots; sparse prior slots; historical reps outside new target; timed duration and assistance copied exactly. |
| Clocks | Delayed/missed callback; zero rest; replacement; skip/adjust; foreground single consumed alert; past deadline restart; pause/resume; wall-clock jump; monotonic wrap/reset; timed target cue; interrupted timed measurement; no automatic set completion. |
| Duration | Explicit pauses; recovery gaps; already-paused cold recovery; finish while paused; clock discontinuity nonnegative clamp; elapsed never less than active; rest included in active time. |
| Recorder coordination | Start/save false; thrown exception; successful OS call before interrupted outcome write; no automatic ambiguous save replay; local completion retained regardless; sensor unavailable; controlled exit versus unknown cold restart. |

Use real simulator Storage in addition to fakes for at least the write/reload/generation tests. Tests touching Storage use the isolated test application identity/data; they must not clear a normal user's store. The release build must exclude test methods and test-only failure hooks.

## Simulator integration sequences

1. Start Upper → Row set1 → Chest set1 → Row set2 → edit Row set1 → reopen Chest → confirm totals and actuals. Finish partial; start a different template referencing Row; confirm Row's last performance comes from the saved partial session.
2. Complete Lower with Dead Bug actuals 35/38/32 seconds. Start Lower again; targets remain35 but drafts show previous actuals per slot. Hyperextension shows bodyweight, no kg editor.
3. Log sets, stop simulator without normal cleanup, relaunch; restore committed sets, show recovery notice, suppress stale rest vibration and restore timed measurement paused.
4. Force each storage operation in finalization to fail in turn. Relaunch until it succeeds; verify one archive, correct cache, no new workout permitted while finalization is unresolved.
5. Generate at least six ended sessions with exercises used only in the first. After oldest sessions are evicted, those exercise prefills still exist in independent cache.
6. Inject HR/activity data and inspect generated FIT using Garmin FIT SDK tools; verify timer start/stop structure and HR values. FIT is an activity stream, not the app's strength database. [FIT activity structure](https://developer.garmin.com/fit/articles/file-types/activity.html), [FIT decoding tools](https://developer.garmin.com/fit/articles/cookbook/decoding_activity_files.html)

## Real-device FR965 validation checklist

Record firmware/API level, app build, settings, elapsed time and observed result for each case:

- API 5.2-capable firmware accepts installation and update with the same app ID; local records survive update.
- Run the complete common path with touchscreen disabled, phone disconnected and no network.
- Short START logs one set; held/repeated/double START cannot accidentally log the next set; editing values does not cause a completion.
- Held UP opens actions without incrementing reps; LIGHT and music controls retain system behavior; BACK never abandons active progress.
- Last, next draft and saved acknowledgment remain visually distinct. Test longer exercise names and assistance/bodyweight wording.
- Switch A→B→A while partially completed; early-close/reopen; use a later set slot; undo the explicitly selected set.
- Edit last set during and after rest expiry. The correction target must never change underneath the user.
- Leave a timed exercise via BACK: immediately see paused status; log another exercise; return and resume measurement. Confirm no extra navigation dialog.
- Rest haptic with display dim/off, wrist wake, LIGHT, exercise list, editor, menu, system notification and music overlay. Record any firmware limitations by case.
- Exit with Resume later, relaunch and resume all sets. Check the separate recorded FIT segment outcome.
- Force restart during workout using only test data; verify last acknowledged values. Force restart around recording finish and document unknown/saved outcome honestly.
- Run a normal ten-minute recorded workout, sync afterward, inspect duration/HR and actual calories/load/effect availability. Workout operation before sync remains offline.
- Exercise worst-case catalog, active state and history; measure peak runtime memory and write latency. Target at least 25% memory headroom and a median durable set acknowledgment under 250 ms; p95 under 500 ms. If unmet, profile storage/layout and reduce copying before adding asynchronous machinery.
- Run a 90-minute active session with repeated menus and corrections; compare memory at start/end and validate all actual values. Record battery usage as an observation, not an unmeasured marketing claim.

## UX acceptance study

Use at least three people for a small formative test if available; include one experienced Garmin-button user and one unfamiliar with this app. This is a validation exercise, not a statistical study. If only the owner is available, label the evidence as single-user testing.

Give tasks, not instructions: start Upper, skip occupied Row, log Chest, correct reps after saving, change next load by two increments, return to Row, skip rest, finish early, resume a timed exercise, recover a paused workout. Observe errors and button presses. Ask which set the displayed numbers belong to before and after logging.

Pass criteria: no mistaken saved-versus-draft interpretation after the first two sets; no unintended completed sets; switch exercises without assistance; correct a just-saved set without searching multiple menu levels; understand that Finish partial saves performed work. If correction is repeatedly missed, change its label/prominence before adding shortcuts. Prototype next-load versus last-correction menu order, then freeze one order; never make menu order depend on elapsed time.

# 16. Technical spikes

The following are future executable probes, not completed research results. Run them in a throwaway app with a separate UUID. Store evidence in `docs/SPIKES.md`: question, SDK/firmware, procedure, observed output, pass/fail, chosen fallback.

| Spike | Question / tiny prototype | Success criterion | Predetermined fallback |
|---|---|---|---|
| **S1 — Storage and recovery** | Write maximum active/config/cache/history fixtures to fixed keys with two generations. Measure serialized footprint and runtime peak. Force exit/reboot after writes; corrupt a generation in isolated fixtures; fill storage to exception. | Both generations plus history fit with measured margin; accepted values reload; invalid newest can fall back; maximum record <32 KB; independent-key behavior supports recovery assumption. | First reduce history from four to two records and cache/catalog ceiling from 32 to 24 identities; measure again. Keep the two active generations. If active snapshot cannot fit or failure damages both copies, block reliability claims and re-evaluate record layout; never silently switch to onStop-only persistence. Record revised constants before T006. |
| **S2 — Physical/touch dispatch** | Screen with event log, numeric field, native menu, timed completion counter. Press/hold UP, START, BACK, music/LIGHT, tap/swipe with touch on/off. | One activation per input; menu hold does not edit field; no arbitrary-tap logging; rapid double START filtered; every operation available by button. | Retain native Menu2 navigation and raw ENTER input. If hold-UP generates an unavoidable preceding increment, move numeric adjustment into explicit NumberEditView and retain UP/DOWN navigation on ready view; publish revised interaction count rather than accepting phantom edits. |
| **S3 — Timer/lifecycle** | One 60-second deadline, one 500 ms haptic, lifecycle/event log and persistent count. Exercise display timeout, LIGHT, palm-cover, notifications, music, Home, normal exit and relaunch. | Data survives all exits; rest continues/alerts during ordinary active-app screen timeout; screen changes preserve deadline; expired cold launch is quiet. | For genuine app exit use persisted deadline with no background alarm promise. If ordinary screen timeout breaks timers, test the SDK-supported display-mode behavior without forcing constant full brightness. If no supported solution works, mark active-workout rest reliability blocked; do not substitute five-minute background scheduling. |
| **S4 — Recording/recovery** | Enable HR, record ten minutes, pause/resume, save; repeat with app exit/suspend/reboot and interrupted save. Observe existing session returned by createSession and whether association/closure is safely known. | Normal FIT contains correct sport/duration/HR; pause and save verified; controlled exit closure works; unknown cold cases clearly identified. | Default local-only resumption after unexpected restart; controlled exits save separate segments. If normal recording cannot work, keep recorder disabled and label build as local-only prototype, not the full recording-validated MVP. No native strength metadata requirement. |
| **S5 — Memory and layout** | Render longest names and max-slot fixtures at 454×454, with active candidate copies, cache and Recorder allocations. Repeatedly push/pop menus. | All screen content legible/unclipped; at least 25% memory headroom at measured peak; no increasing allocations after navigation cycle. | Load one history detail at a time, remove duplicated strings/unused baseline data, reduce visible rows and assets. Apply documented catalog/history ceilings before considering a custom codec. Never reduce font readability merely to fit the original mockup. |
| **S6 — Workout usability** | Interactive prototype: unchanged sets, correction after log, zero-rest sets, switching while timed, partial finish/recovery; physical FR965 buttons. | Stable button meaning; no accidental extra sets; last/next values distinguished; tasks completed without a phone or lengthy explanations. | Keep inline acknowledgment, explicit correction, and overview access. If direct logging's double-press guard is insufficient, add a deliberate ready action after logging and document the extra press as a measured safety tradeoff; do not silently change START meaning on a timer. |
| **S7 — Optional FIT developer field** | After MVP, one session-level completed-sets field with resource metadata. Inspect FIT and preview/actual Connect rendering. | Numeric field present in FIT; presentation claims verified independently of side-loaded metadata limitations. | Omit field. Core local history and normal activity recording are unchanged. |

No spike should expand into a backend, phone app, binary FIT writer, or architecture rewrite without reporting the concrete blocker. API 5.2 alone does not prove support for every device-specific method; check each supported-device list and compile for `fr965`.

# 17. Known limitations / deferred features

- **Platform boundary:** local sets can recover from an interruption; uninterrupted Garmin recording and rest haptics after leaving the app are not guaranteed. Normal active-app display timeout must be validated separately.
- **Garmin strength UI:** no supported native exercise/set table or muscle-map integration in MVP; no promise of training effect/load. Standard FIT activity and local strength history serve different purposes.
- **History:** four ended workouts and last performance per catalog exercise, subject to measured capacity. No unlimited archive, export, automatic backup, or cross-device sync. Uninstall/device reset can lose local data; explain that in Settings/About and release notes. Do not build a cloud service to mask it.
- **Template creation:** on-watch numeric defaults/increments are editable; new exercise names, structural template creation and reordering require the seed-development workflow in the internal MVP. A fully standalone consumer template builder is a later product decision.
- **Exercise scope:** kg only; no kg/lb conversion, RPE/RIR, warm-up/drop-set taxonomy, per-side execution engine, added-load/body-mass combination, or duplicate identity blocks within one template. Equipment-specific load conventions are explicit notes/IDs.
- **Progression:** no double/linear progression, 5/3/1, formulas, deloads, DSL, recommendations, auto-increases, or heuristics that reinterpret past performance.
- **Interaction:** touch is optional; system overlays may affect attention. Most configuration happens outside a workout. No animations/custom font stack needed.
- **Supersets:** grouping field reserved in seed schema; no mandatory alternating workflow or round-aware rest in MVP.
- **Integrations/business scope:** no cloud accounts, social features, friends, leaderboards, AI coaching, Liftosaur/Hevy/LiftTrack integration, Garmin Training API, Android/iOS companion, web app, subscription, exercise videos, advanced analytics, workout discovery, public sharing, or automatic Store publication.

# 18. Definition of Done for MVP

The MVP is done only when all required items below have evidence. Plan completeness does not mean these implementation checks have already passed.

- A reproducible signed build runs on FR965 firmware supporting **API 5.2**, using manifest **`minSdkVersion="5.2.0"`** and the pinned SDK/device package.
- Both supplied templates are exact and fully usable offline. Architecture also passes synthetic templates with rep ranges, altered counts, and cross-template exercise identities.
- All four exercise types log valid actuals; assistance and bodyweight are unambiguous; timed sets require actual completion and preserve paused measurement across switching.
- The user can select any exercise, leave partial work, return, select an empty slot out of order, correct or undo a specific set, close/reopen an exercise and save a partial workout.
- The common unchanged normal set takes one START press, or a documented usability-test-driven fallback; button-only operation is complete. No timer changes screen focus or the target of an input.
- Overview accurately distinguishes untouched, partial, full and closed-early; Upper 19/Lower 17 denominators never count unperformed sets.
- Accepted sets/drafts and settings survive normal exit and tested forced interruption. Storage errors are visible, recoverable and cannot produce false “saved” acknowledgments. Unsupported schemas never reset silently.
- History retention and last-performance cache are bounded, independently useful, and validated under maximum storage/memory load. Finalization replay cannot duplicate sessions or regress context.
- Last performance matches the defined same-ID/type/unit algorithm across templates; saved partials qualify, aborted/active sessions do not; prefills never implement progression.
- Rest runs across in-app screens and ordinary screen timeout, can be skipped/adjusted, vibrates as tested, and restores deadlines without claiming background guarantees. Timed measurement and pause/recovery accounting pass their cases.
- Normal Garmin recording has verified duration and HR when the sensor is available. Save/start failures preserve local sets. Unknown interrupted FIT state is honestly labelled. Any unavailable calorie/load/effect metric is not advertised.
- Numeric template defaults, per-exercise increments and app settings are editable on-watch and persist; existing active/history snapshots do not change retroactively.
- Simulator automated tests, corruption/failure injection, maximum-capacity profiling and the FR965 manual checklist pass. Required hardware checks not performed remain release blockers, not assumed successes.
- Two complete gym-style acceptance sessions finish without a phone; next-session prefills match the performed values.
- `.prg`, `.iq`, install/update instructions, toolchain record, test evidence and limitations are ready. Signing key remains outside the repository. Store submission is not performed automatically.

The next coding agent begins at **T001**. This plan authorizes no implementation during the planning/review task itself.
