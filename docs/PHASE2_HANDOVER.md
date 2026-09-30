# Phase 2 handover — Liftosaur plan to watch, workout upload, Garmin catalog removal

Audience: the next implementing agent (Codex). Written 2026-09-30 at the end of Phase 1. Read first: `AGENTS.md`, `CLAUDE.md`, `docs/LIFTOSAUR_PLAN.md` (esp. "Schema (observed)" and "Implemented matching rules"), `tools/connect-sets/README.md`, `docs/DEVICE_TESTS.md`.

## Where things stand

- Branch `liftosaur-sync` (Phase 1, version 0.2.7). `main` has 0.2.6 (compact Garmin catalog, Training/Generic recording, START-twice set flow, lap developer fields incl. `active_s`, `void`, `garmin_category/code`).
- NAS job `tools/connect-sets/` (Docker on the user's Debian 13 NAS, managed by a separate NAS agent): Garmin login → lists strength activities → downloads original FIT → archive (`data/archive/<id>.json` + `nextset.db`) → Liftosaur write-back (`/workout/start` → `/workout/sets` → `/workout/finish`, which runs progression) behind `LIFTOSAUR_SYNC=0|1`, `LIFTOSAUR_SINCE`, `LIFTOSAUR_MIN_SEC`. Writing Garmin Connect exercise sets was removed (user decision). ntfy alerts on repeated failures (`NTFY_URL=https://ntfy.sh/nextset-7f3k9q2x`).
- The first real Liftosaur write has NOT happened yet. It needs explicit user OK on one real workout (`python sync.py liftosaur-sync --only <activityId>` after a `--dry-run`).
- Secrets: `tools/connect-sets/.env` (gitignored) holds `LIFTOSAUR_API_KEY` (premium key; user should rotate it after the setup because it appeared in a chat transcript) and `NTFY_URL`; `data/tokens` holds Garmin tokens. Never print, copy or commit them.

## User decisions (binding)

1. Liftosaur is the single source of routines, exercises and progression. Exercise names on the watch are exactly the Liftosaur entry `name`. No mapping file.
2. Drop everything Garmin-exercise related: the Garmin catalog (`resources/data/garmin.xml`, `private/resources/data/garmin.xml`, `scripts/generate_garmin_catalog.py`, the picker, "Category only"), `garminCategory`/`garminCode` in seeds/routines/sessions, the lap fields `garmin_category`/`garmin_code`. Breaking stored-data changes are fine (beta).
3. Keep the FIT recording (sport Training, sub-sport GENERIC) so Garmin Connect still gets an activity with duration, heart rate, calories, training load. It does not need sets/reps.
4. No transport test app; build the real thing. Transport: Tailscale (`tailscale serve`, tailnet-only HTTPS `https://<nas>.<tailnet>.ts.net`, valid cert). If the watch cannot reach the tailnet (the request goes through the phone's Garmin Connect app; FR965 may use Wi-Fi), fall back to `tailscale funnel` with the same token. Only a URL change.
5. Code is implemented by a Sonnet-class agent; the architect reviews. Commit only on a feature branch; merge to `main` after user OK. `monkeydo ... -t` is required for unit tests.

## Phase 2 scope

### NAS (Python, `tools/connect-sets`, stdlib HTTP is fine)

- HTTP server in the same container (second process or thread), bound to a port that `tailscale serve` proxies. Bearer token `NEXTSET_TOKEN` from `.env`.
- `GET /routines` → all days of the active Liftosaur program, built per day from `GET /workout/next?programId&week&dayInWeek` (never persists anything on Liftosaur). Compact JSON, e.g.:
  ```json
  {"v":1,"programId":"okhaddnh","programName":"Machine UL Simple","next":{"week":1,"dayInWeek":2},
   "days":[{"week":1,"dayInWeek":1,"name":"Upper","exercises":[
     {"name":"Seated Row","equipment":"leverageMachine","superset":null,"unilateral":false,
      "restSec":120,"sets":[{"reps":9,"kg":55,"timeSec":null}],"warmups":[{"reps":10,"kg":26}]}]}]}
  ```
  Timed sets (`setTimer`) → `timeSec`, `reps` 1. Bodyweight → `kg` 0. Keep the payload small (watch memory); no set ids (they change on every GET).
- `POST /workouts` ← completed workout uploaded by the watch (see contract below). Stores it in the archive (same normalization/DB as the FIT path; key by start time + session id) and runs the existing Liftosaur write-back for it. Idempotent: re-upload of the same workout returns 200 without a second Liftosaur write (Liftosaur itself also rejects a duplicate `startTime` with 409 `workout_start_time_taken`).
- The FIT/Connect path stays as a fallback for archive and HR/duration; both paths must dedupe on workout start time so a workout is written to Liftosaur once.
- Tests (plain asserts in `test_sync.py`): routine building from a sanitized `/workout/next` fixture, auth, idempotent upload, dedupe with the FIT path.
- NAS agent handoff (write it into `tools/connect-sets/README.md`): expose the port with `tailscale serve --https=443 localhost:<port>`, add `NEXTSET_TOKEN` to `.env`, rebuild.

### Watch app (Monkey C)

- Settings via Connect IQ app properties (edited in the phone app): NAS base URL, token. Not in the package.
- "Sync routines" action (Home / Settings): `Communications.makeWebRequest` GET `/routines` with the token; callbacks passed via `method(:x)` must be `public` (private ones crash on the watch). Validate through `Model` before storing; replace all routines atomically using the existing two-generation `Store` + staged, resumable writes; show errors (no phone, 401, invalid data) as `Err` codes. Home marks the `next` day.
- Routine model v4 (config `schemaVersion` bump; older data may reset): exercises defined inline from Liftosaur (name, equipment, loadType derived: timed if `timeSec`, bodyweight if all kg 0, else weight; unilateral, superset, restSec), per-set targets (reps, load100, durationSec), warmups displayed but not logged as working sets (decide: optional). Prefill uses the plan target for the set; "last time" stays visible.
- Add/replace exercise during a workout: picker lists the exercises of the synced program instead of the Garmin catalog.
- Workout upload: after finalization, queue the finished workout (persisted, bounded) and POST it to `/workouts` when the phone is reachable (on finish, on app start, on sync). Mark uploaded on 2xx. Payload per workout: session id, routine day (programId, week, dayInWeek, name), start/end epoch seconds, exercises in performed order with sets `{set, reps, kg, timeSec, activeSec, completedAt}`, corrections already applied, undone sets removed, substitutions noted. Keep the watch-side JSON small.
- FIT laps: keep `exercise`, `set`, `reps`, `weight_kg`, `duration_s`, `active_s`, `void` as the fallback data path; remove `garmin_category`/`garmin_code`. Keep the session summary fields.
- Remove the Garmin catalog and everything listed in decision 2; expect the release `.prg` to drop well below the current ~158 KB.
- Tests: Model validation of v4 routines and upload payloads, routine parsing from a fixture, upload queue logic (pure), stored-data reset from v3. Record simulator vs device results separately in `docs/DEVICE_TESTS.md`.

## Acceptance (device, by the user)

1. Sync routines on the FR965 over the phone; Upper/Lower appear with plan weights; Home shows the next day.
2. Log a real workout; it uploads; the NAS archives it; Liftosaur shows the workout in history and the next weights reflect progression; Connect shows the activity with HR and duration.
3. Airplane mode during finish: the workout uploads later without duplicates.
4. If the tailnet is unreachable from the watch, switch to `tailscale funnel` and repeat 1–2.

## Known risks

- `/workout/start` with a past `startTime`: ids differ from previews; real runs take ids from the start response (implemented in `liftosaur.py`, untested live).
- Unilateral sets (`repsLeft`), assistance weight sign (sent positive), skipped sets' effect on progression — confirm on the first real write.
- Watch memory for the `/routines` response: keep it compact; test with the full program.
- Connect IQ `makeWebRequest` needs valid HTTPS; `tailscale serve` certs are valid, reachability from the phone path is the open question.
