#!/bin/bash
# Usage: scripts/clean-bin.sh — slims bin/ down to what is worth keeping: the store package of the
# newest release (bin/release-X.Y.Z/NextSet-X.Y.Z.iq; older ones are already in the store),
# ciq-devices.zip, and device logs (*.YML, *.BAK, *.fit).
# Everything else in bin/ is a rebuildable build output (test, demo and scratch builds, compiler
# intermediates, debug and FIT-description files) and is deleted.
set -eu
cd "$(dirname "$0")/../bin"
newest="$(ls -d release-* 2>/dev/null | sort -V | tail -1 || true)"
for entry in * .[!.]*; do
    [ -e "$entry" ] || continue
    case "$entry" in
        ciq-devices.zip|*.YML|*.BAK|*.fit) ;;
        release-*)
            if [ "$entry" = "$newest" ]; then
                find "$entry" -mindepth 1 ! -name '*.iq' -exec rm -rf {} + 2>/dev/null || true
            else
                rm -rf -- "$entry"
            fi ;;
        *) rm -rf -- "$entry" ;;
    esac
done
du -sh .
