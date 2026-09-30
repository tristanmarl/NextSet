# connect-sets (NextSet archive + Liftosaur sync)

The directory name is historical: the job no longer writes anything to Garmin Connect. It reads NextSet's
per-set FIT laps from your synced Garmin activities (read-only), archives every workout and, when enabled,
logs it into the matching Liftosaur workout. Docstring in `sync.py` lists the commands.

Setup (uid 1000 must own `./data`; the tokens grant full access to your Garmin account):

    mkdir -p data && chown 1000 data && chmod 700 data
    docker compose build
    docker compose run --rm connect-sets python sync.py login     # once
    docker compose run --rm connect-sets python sync.py run --dry-run
    docker compose up -d

## Archive

Every NextSet activity the job sees is stored as `data/archive/<activityId>.json` (start/end, routine name =
activity name, sets with exercise, set, reps, weight_kg, duration_s, active_s, Garmin codes; corrections and
undos merged the same way the watch app treats them) and upserted into `data/archive/nextset.db`
(tables `workouts`, `sets`). Backfill (read-only on Garmin, skips archived ones):

    docker compose run --rm connect-sets python sync.py archive-backfill --lookback 200

## Liftosaur

`.env` (chmod 600, never commit): `LIFTOSAUR_API_KEY=lftsk_...`, `LIFTOSAUR_SYNC=0|1` (default 0: nothing is
written to Liftosaur). Details and the observed API schema: `docs/LIFTOSAUR_PLAN.md`.

    python sync.py liftosaur-discover                 # GET only; raw JSON to data/liftosaur-discovery/
    python sync.py liftosaur-sync --dry-run [--only ID]   # prints the start/sets/finish calls, sends nothing
    python sync.py liftosaur-sync --only ID           # real write of one workout (first time: check the dry run)

Liftosaur owns the exercise list: a NextSet exercise name must equal the Liftosaur entry `name` exactly
(case-sensitive). The routine name must equal exactly one day name of the active program (case-insensitive);
that day is started explicitly with the FIT start time, whatever Liftosaur's "next day" is. No match or an
ambiguous name: skipped with a notice. Status per activity is kept in `state.json` (`done`/`skipped` final,
`blocked`/`failed` retried). An active workout in the Liftosaur app is never touched (blocked + ntfy).
With `LIFTOSAUR_SYNC=1` the loop writes archived workouts that started at or after `LIFTOSAUR_SINCE` (ISO
datetime or unix seconds, e.g. `2026-10-01T00:00:00Z`) and are at least `LIFTOSAUR_MIN_SEC` (default 300) long
(shorter ones are skipped with a notice). If `LIFTOSAUR_SINCE` is unset nothing is written (a warning is
logged); there is no default window. `liftosaur-sync --only ID` bypasses both limits.

Env: `INTERVAL_SEC`, `LOOKBACK` (activities checked per run). Self-check: `python test_sync.py` (offline).

## Failure alerts (ntfy)

The loop runs every 10 minutes and restarts with the NAS (`restart: unless-stopped`). After
`FAIL_ALERT_AFTER` (default 3) consecutive failed runs it sends one ntfy message, then one
"recovered" message when a run succeeds again. A container restart resets the counter. Liftosaur skips,
blocks and notes also go to ntfy.

1. Install the ntfy app and subscribe to a hard-to-guess topic. Topics on ntfy.sh are public by name.
2. Add `NTFY_URL=https://ntfy.sh/<topic>` to `.env`.
3. Test: `curl -d test "$NTFY_URL"`, then `docker compose up -d`.

Without `NTFY_URL` failures are only logged.
