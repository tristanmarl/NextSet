#!/bin/bash
# Builds the unit-test target and runs it in the FR965 simulator.
# Exit 0 only when the summary reads "PASSED (passed=N, failed=0, errors=0)".
# monkeydo may exit 1 after a passing run, so the summary line, not its exit code, decides.
# The script restarts the simulator itself (a stale one hangs monkeydo) and retries once.
set -u
cd "$(dirname "$0")/.."
SDK="${CIQ_SDK:-$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2}"
KEY="${CIQ_KEY:-$HOME/.garmin-keys/NextSetDeveloperKey.der}"
TIMEOUT="${TEST_TIMEOUT:-120}"
export PATH="$SDK/bin:$PATH"
mkdir -p bin
LOG="$(mktemp)"

if ! monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY" 2>&1 | tee "$LOG" | grep -q "BUILD SUCCESSFUL"; then
    cat "$LOG"
    echo "test build failed" >&2
    exit 1
fi

# A stale simulator from an earlier run can hang monkeydo: restart it, and retry once if needed.
for attempt in 1 2; do
    pkill -f "ConnectIQ.app/Contents/MacOS/simulator" 2>/dev/null
    pkill -f MonkeyDoDeux 2>/dev/null
    sleep 2
    open "$SDK/bin/ConnectIQ.app"
    sleep 8
    monkeydo bin/NextSet-tests.prg fr965 -t > "$LOG" 2>&1 &
    PID=$!
    for ((i = 0; i < TIMEOUT; i++)); do
        grep -q "PASSED (\|FAILED (" "$LOG" && break
        kill -0 "$PID" 2>/dev/null || break
        sleep 1
    done
    kill "$PID" 2>/dev/null
    pkill -f MonkeyDoDeux 2>/dev/null
    grep -q "PASSED (\|FAILED (" "$LOG" && break
done

SUMMARY="$(grep -E "^(PASSED|FAILED) \(" "$LOG" | tail -1)"
if [ -z "$SUMMARY" ]; then
    grep -E "FAIL|ERROR|Exception" "$LOG" | head -20
    echo "no test summary within ${TIMEOUT}s" >&2
    exit 1
fi
grep -E "FAIL|ERROR \(|Exception" "$LOG" | head -20
echo "$SUMMARY"
[[ "$SUMMARY" =~ ^PASSED\ \(passed=([0-9]+),\ failed=0,\ errors=0\)$ ]]
