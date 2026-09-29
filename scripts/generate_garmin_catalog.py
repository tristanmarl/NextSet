#!/usr/bin/env python3
"""Generate category-sized resources from the pinned Garmin Connect snapshot.

Source: https://connect.garmin.com/web-data/exercises/Exercises.json
Snapshot date: 2026-09-29
SHA-256: 3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c

Offline regeneration:
  python3 scripts/generate_garmin_catalog.py \
    /private/tmp/NextSet-Garmin-Exercises.json resources/data/garmin.xml
"""

import hashlib
import json
import sys
import xml.sax.saxutils as xml


PINNED_SHA256 = "3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c"


def readable(code):
    return " ".join(word.capitalize() for word in code.lower().split("_"))


def main(source, output):
    raw = open(source, "rb").read()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != PINNED_SHA256:
        raise ValueError("input does not match the pinned 2026-09-29 catalog snapshot")
    data = json.loads(raw)
    categories = data["categories"]
    seen = set()
    resources = []
    names = []
    total = 0
    for category, details in sorted(categories.items()):
        names.append({"code": category, "name": readable(category)})
        rows = []
        for code, metadata in sorted(details["exercises"].items()):
            exercise_id = "g-" + hashlib.sha256((category + "." + code).encode()).hexdigest()[:12]
            if exercise_id in seen:
                raise ValueError("exercise ID collision: " + exercise_id)
            seen.add(exercise_id)
            rows.append({
                "id": exercise_id,
                "name": readable(code),
                "category": category,
                "code": code,
                "isBodyWeight": metadata.get("isBodyWeight"),
            })
        resources.append(rows)
        total += len(rows)

    with open(output, "w", encoding="utf-8") as out:
        out.write('<jsonDataResources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                  'xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">\n')
        out.write('  <jsonData id="GarminCategories">' + xml.escape(json.dumps(names, separators=(",", ":"))) + '</jsonData>\n')
        for index, rows in enumerate(resources):
            payload = json.dumps(rows, separators=(",", ":"))
            out.write('  <jsonData id="Garmin%02d">%s</jsonData>\n' %
                      (index, xml.escape(payload)))
        out.write('</jsonDataResources>\n')

    print("categories=%d exercises=%d sha256=%s" %
          (len(categories), total, digest))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: generate_garmin_catalog.py Exercises.json output.xml")
    main(sys.argv[1], sys.argv[2])
