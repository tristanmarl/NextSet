#!/bin/bash
# Packs the Connect IQ device definitions for every product in manifest.xml and manifest.beta.xml
# into bin/ciq-devices.zip (unzips to <device>/...). CI needs it because the Linux SDK has no
# device files: upload it as the asset "ciq-devices.zip" of the draft release tagged "ci-devices".
# Re-run after adding a product or updating devices in the SDK Manager.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICES="${CIQ_DEVICES:-$HOME/Library/Application Support/Garmin/ConnectIQ/Devices}"
OUT="$PWD/bin/ciq-devices.zip"
ids=$(grep -ho '<iq:product id="[^"]*"' manifest.xml manifest.beta.xml | sed -E 's/.*id="([^"]*)"/\1/' | sort -u)
for d in $ids; do
    test -f "$DEVICES/$d/compiler.json" || { echo "missing device files for $d in $DEVICES" >&2; exit 1; }
done
mkdir -p bin
rm -f "$OUT"
# shellcheck disable=SC2086
(cd "$DEVICES" && zip -q -r "$OUT" $ids)
echo "$(echo $ids | wc -w | tr -d ' ') devices -> $OUT ($(du -h "$OUT" | cut -f1))"
echo "Upload: gh release upload ci-devices \"$OUT\" --clobber"
