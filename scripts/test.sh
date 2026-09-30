#!/bin/bash
# Builds the unit-test target and runs it in the FR965 simulator.
# Exit 0 only when the summary reads "PASSED (passed=N, failed=0, errors=0)".
# monkeydo may exit 1 after a passing run, so the summary line, not its exit code, decides.
# If the simulator hangs (no summary before TIMEOUT), quit ConnectIQ.app and start it again.
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

monkeydo bin/NextSet-tests.prg fr965 -t > "$LOG" 2>&1 &
PID=$!
for ((i = 0; i < TIMEOUT; i++)); do
    grep -q "PASSED (\|FAILED (" "$LOG" && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 1
done
kill "$PID" 2>/dev/null
pkill -f MonkeyDoDeux 2>/dev/null

SUMMARY="$(grep -E "^(PASSED|FAILED) \(" "$LOG" | tail -1)"
if [ -z "$SUMMARY" ]; then
    grep -E "FAIL|ERROR|Exception" "$LOG" | head -20
    echo "no test summary within ${TIMEOUT}s" >&2
    exit 1
fi
grep -E "FAIL|ERROR \(|Exception" "$LOG" | head -20
echo "$SUMMARY"
[[ "$SUMMARY" =~ ^PASSED\ \(passed=([0-9]+),\ failed=0,\ errors=0\)$ ]]
