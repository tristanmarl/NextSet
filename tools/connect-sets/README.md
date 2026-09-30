# connect-sets (NextSet FIT archive)

The directory name is historical: the job no longer writes to Garmin Connect. It reads NextSet's per-set FIT
laps from synced Garmin activities (read-only) and archives workouts. The watch app writes directly to
Liftosaur.

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

The watch app reads routines from and writes workouts directly to Liftosaur. This NAS job remains an
optional FIT archive backup. Keep `LIFTOSAUR_SYNC=0` in `.env` (the Compose default) to prevent duplicate
writes. No NAS HTTP service or Tailscale setup is used.

Do not enable NAS write-back or run a real `liftosaur-sync` command while the watch writes directly.
`liftosaur-discover` is still available as a GET-only diagnostic and needs `LIFTOSAUR_API_KEY` in `.env`
(chmod 600, never commit). The observed API schema is in `docs/LIFTOSAUR_PLAN.md`.

    python sync.py liftosaur-discover                 # GET only; raw JSON to data/liftosaur-discovery/
    python sync.py liftosaur-sync --dry-run [--only ID]   # optional backup-path preview; sends nothing

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
