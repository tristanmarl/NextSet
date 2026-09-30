#!/bin/bash
# Usage: scripts/bump-version.sh X.Y.Z — sets the app version in both manifests and both AppVersion strings.
set -eu
[[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 X.Y.Z" >&2; exit 1; }
cd "$(dirname "$0")/.."
for f in manifest.xml manifest.beta.xml; do
    sed -i.bak -E "s/^([[:space:]]+version=\")[0-9.]+(\")/\1$1\2/" "$f"
done
for f in resources/strings/strings.xml private/resources/strings/strings.xml; do
    sed -i.bak -E "s#(<string id=\"AppVersion\">)[0-9.]+(</string>)#\1$1\2#" "$f"
done
rm -f manifest.xml.bak manifest.beta.xml.bak resources/strings/strings.xml.bak private/resources/strings/strings.xml.bak
grep -n 'version="' manifest.xml manifest.beta.xml | grep -v 'version="1"'
grep -n AppVersion resources/strings/strings.xml private/resources/strings/strings.xml
