# connect-sets

Copies NextSet per-set FIT laps into Garmin Connect's native exercise sets (unofficial endpoint,
personal use only, may break any time). See the docstring in `sync.py`.

Setup (uid 1000 must own `./data`; the tokens grant full access to your Garmin account):

    mkdir -p data && chown 1000 data && chmod 700 data
    docker compose build
    docker compose run --rm connect-sets python sync.py login     # once
    docker compose run --rm connect-sets python sync.py run --dry-run
    docker compose run --rm connect-sets python sync.py run --only <activityId>

Open that activity in Garmin Connect and check the sets, weights (code assumes grams) and set
times before enabling the loop:

    docker compose up -d

`run --force` overwrites an activity that already has sets. Env: `INTERVAL_SEC`, `ACTIVE_SEC`
(assumed seconds per non-timed set), `LOOKBACK` (activities checked per run). Self-check:
`python test_sync.py`.

## Failure alerts (ntfy)

The loop runs every 10 minutes and restarts with the NAS (`restart: unless-stopped`). After
`FAIL_ALERT_AFTER` (default 3) consecutive failed runs it sends one ntfy message, then one
"recovered" message when a run succeeds again. A container restart resets the counter.

1. Install the ntfy app and subscribe to a hard-to-guess topic. Topics on ntfy.sh are public by name.
2. Create `.env` next to `compose.yaml` and lock it down:

       echo 'NTFY_URL=https://ntfy.sh/<topic>' > .env && chmod 600 .env

3. Test: `curl -d test "$NTFY_URL"`, then `docker compose up -d`.

`.env` may also set `INTERVAL_SEC`, `ACTIVE_SEC`, `LOOKBACK`, `FAIL_ALERT_AFTER`. Without `NTFY_URL`
failures are only logged.
