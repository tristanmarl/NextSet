# Liftosaur loop — plan (2026-09-30)

Goal: Liftosaur owns the plan and progression, NextSet on the watch logs, the NAS moves data both ways, Claude coaches on top. History must stay available outside the watch.

```
Liftosaur program ─①─► NAS (routine for next day) ─②─► NextSet on watch
      ▲                                                     │ workout
      └──④ start/sets/finish (progression) ── NAS ◄──③── FIT via Connect
```

Facts (research 2026-09-30, https://www.liftosaur.com/doc/api):
- REST API `https://www.liftosaur.com/api/v1`, `Authorization: Bearer lftsk_…` (premium; user has it). Writes to `/workout/*` also need `X-Liftosaur-Device-Id` (stable, generated once) and `X-Liftosaur-Client` (`nextset-nas/<version>`).
- `GET /workout/next` previews the next day (entries → sets with `setId`, weight string like `"100kg"`). `POST /workout/start {startTime}` → `POST /workout/sets` → `POST /workout/finish {startTime,endTime,notes}` runs progression, 1RM update, history, next-day pointer, "as if done in the app". Writes are idempotent. 409 `workout_already_active` / `workout_start_time_taken`.
- The live API cannot add/remove/reorder exercises; extra sets via `append:true`. `POST /history` (Liftohistory text) is history only, presumably no progression.
- Unverified until a real key is used: full `/workout/next` schema (exercise names, target reps per set, timed sets), how skipped sets affect progression.

## Phase 1 — archive and write-back (NAS only)

Extends `tools/connect-sets` (now "NextSet archive + Liftosaur sync"; the Garmin Connect exerciseSets write path was dropped 2026-09-30, the job is read-only on Garmin). Implemented 2026-09-30 behind `LIFTOSAUR_SYNC=0|1` (default 0); only GET was exercised so far, the write path only via `--dry-run`.
1. Archive: every NextSet activity the job sees is stored as JSON (one file per activity) plus a SQLite table of sets under `data/archive/`. Backfill once with a larger lookback.
2. Discovery (read-only): script prints `/workout/next` and `/settings` for the active program; the schema gets recorded in this doc.
3. Exercise names: no mapping file. Liftosaur owns the exercise list; NextSet exercise names equal the Liftosaur entry `name` (exact, case-sensitive). An exercise Liftosaur does not know is left out of the write and listed in the finish notes + ntfy.
4. Write-back after each new NextSet activity (after Connect sets): match the workout to the Liftosaur day (Phase 1: the current `/workout/next` day, when the watch routine name matches the Liftosaur day name, else skip with notice), `start` with the FIT start time, `sets` mapped by exercise + set order (unmatched planned sets stay incomplete, extra sets `append`), `finish` with FIT end time and a note listing substitutions. State per activity in `state.json` (`liftosaur: done|skipped|failed`) so reruns never double-post.
5. Safety: `--dry-run` prints the calls; first real write only with user OK on one activity; 409 handling (active workout in the app → skip and notify, never auto-discard).

## Phase 2 — plan to watch

1. Transport test first: a throwaway Connect IQ app GETs `https://<nas>.<tailnet>.ts.net/ping` over the phone connection and over Wi-Fi. Tailnet-only `tailscale serve` preferred; fall back to `tailscale funnel` + secret token if the watch cannot reach the tailnet.
2. NAS endpoint `GET /routine/next` (token) returns a compact NextSet routine built from `/workout/next` + mapping, including Liftosaur `entryId`/`setId`s.
3. NextSet: "Sync routine" action (`Communications.makeWebRequest`, callback public), routine model extended with per-set targets (load/reps per set) and Liftosaur ids; a lap field `entry` so Phase 1 matching uses ids instead of names.

## Phase 3 — coaching

Claude reads Liftosaur (MCP/API) and the NAS archive, proposes program changes, applies them in Liftosaur after user OK. Optional read-only archive MCP server on the NAS.

## Open

- Custom/timed exercise handling in Liftosaur (Dead Bug, machine variants) — confirm with the real schema.
- Workouts done in another order or with substitutions: progression semantics for incomplete sets.

## Schema (observed 2026-09-30, real key, GET only)

Envelope `{"data": ...}`; errors `{"error": {code, message}}`. Fake-safe abbreviated values.

- `GET /settings` -> `{units:"kg", timers:{warmup:60, workout:120, superset:null}}`. Units are kg.
- `GET /programs` -> `{programs:[{id, name, isCurrent}]}` (here "Machine UL Simple" is current, "Foundation" is not).
- `GET /programs/current` -> `{id, name, text}`; `text` is Liftoscript: `# Week 1`, `## Upper`, `## Lower`, one line per exercise (`Seated Row, Leverage Machine / 3x9 / 55kg 120s / warmup: 1x10 50% / progress: dp(5kg, 8, 10)`), `// ...` comment lines are the exercise description. Supersets via `superset: A`. Timed set: `Dead Bug / 3x1 / 0kg 35s+|60s` (reps 1, 35 s, progression `custom(maxTime: 60)`). Only one week in the program; the day `dayInWeek` is 1 = Upper, 2 = Lower.
- `GET /workout/current` -> `{workout: null}` when nothing is live (same shape as next otherwise).
- `GET /workout/next[?programId&week&dayInWeek]` -> `{workout: {programId, programName, dayName, dayData:{day,week,dayInWeek}, startTime, entries:[...]}}`. **`startTime` is "now" and every `setId` is regenerated on every GET**, so ids from a preview are only illustrative; real runs take the ids from the `/workout/start` response.
  Entry: `{entryId, exerciseId, equipment, name, imageUrl, superset, notes, description, hasUpdateScript, promptedVars, warmupSets:[...], sets:[...]}`.
  `name` is the display name WITHOUT equipment (`"Leg Press"`, equipment `"leverageMachine"`; the Liftoscript/history text says `Leg Press` or `Seated Row, Leverage Machine`). Built-in `entryId == exerciseId == "<camelName>_<equipment>"` (`legPress_leverageMachine`); a custom exercise has a random id and `equipment: null` (`rzrshgtr`, "Dead Bug").
  Set: `{setId, index, isWarmup, reps, minReps, isAmrap, weight:"213kg", originalWeight, plates:[{weight,num}], rpe, logRpe, askWeight, isUnilateral, timer:150 (rest s), setTimer:null|35 (timed set, seconds), completed:null}`. Timed set: `reps:1, weight:"0kg", setTimer:35`. Bodyweight: `weight:"0kg"`. Weights are already rounded (`weight:"106kg"`, `originalWeight:"106.5kg"`). Warmups are in `warmupSets`, not in `sets`.
- `GET /history?limit=N` -> `{records:[{id (=start ms), text}], hasMore, nextCursor}`; `text` is Liftoscript Workouts (`2026-09-27 07:43:08 +00:00 / program: ... / dayName: "Upper" / ... / exercises: {` lines `Seated Row, Leverage Machine / 3x8 55kg / warmup: 1x10 26kg / target: 3x8 55kg 120s`).
- Writes (not yet exercised): `POST /workout/start {programId, week, dayInWeek, startTime}`, `POST /workout/sets {sets:[{entryId,setId,completed:{reps,weight:"55kg",setTimer?,repsLeft?}, append?}]}`, `POST /workout/finish {startTime,endTime,notes}`; headers `X-Liftosaur-Device-Id`, `X-Liftosaur-Client: nextset-nas/0.1.0`.

### The user's program "Machine UL Simple" (id okhaddnh)

Upper (dayInWeek 1): Seated Row 3x9 55kg, Chest Press 3x8 65kg, Reverse Fly 2x11 40kg, Shoulder Press 2x8 45kg, Pull Up 2x10 25kg (superset A, assistance), Triceps Dip 2x10 25kg (superset A, assistance), Lateral Raise 2x10 40kg, Preacher Curl 3x12 30kg. All `leverageMachine`.
Lower (dayInWeek 2): Leg Press 4x9 213kg (2 warmups, custom progression script), Lying Leg Curl 2x10 50kg, Single Leg Hip Thrust 2x10 60kg (`isUnilateral: true`), Leg Extension 2x10 55kg, Hip Abductor 2x10 75kg, Back Extension 2x10 bodyweight (`bodyweight`), Dead Bug 3 x 35 s timed (custom exercise, no equipment). All `leverageMachine` except the last two.

### Implemented matching rules

- Day: the activity name is resolved against all days of the active program (parsed from `/programs/current`, case-insensitive exact `dayName`; none or several matches -> skipped with reason) and that day is started explicitly (`/workout/start {programId, week, dayInWeek, startTime}`), independent of the next-day pointer. Loop cut-off: only activities started >= `LIFTOSAUR_SINCE` and >= `LIFTOSAUR_MIN_SEC` (300) long; `LIFTOSAUR_SINCE` unset = write nothing; `--only` bypasses both. Current `/workout/current` must be null (or our own start time, for a retry), else blocked + ntfy.
- Sets: NextSet exercise name == entry `name` exactly; watch set i (by set number) -> planned working set i (warmups never filled); extra sets `append:true` with a generated 6-letter id; planned sets without a watch set stay incomplete. Weight `"<abs kg>kg"` (assistance is negative in NextSet, positive in Liftosaur; unverified). Planned timed set (`setTimer`) needs the watch `duration_s` -> `completed.setTimer` (+ `reps` as planned); unilateral non-timed sets also send `repsLeft = reps` (unverified: API contract for a non-AMRAP unilateral set).
- NextSet's own seeds (private Upper/Lower) were renamed to the exact `name`s above (0.2.7).
- FIT quirk seen: the FIT session `start_time` equals its stop time in 0.2.5 files, so the archive derives start/end from the laps (first lap start, last lap end); the activity is the actual logging span, not the Garmin timer.
