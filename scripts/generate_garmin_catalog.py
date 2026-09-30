#!/usr/bin/env python3
"""Generate category-sized resources from the pinned Garmin Connect snapshot.

Source: https://connect.garmin.com/web-data/exercises/Exercises.json
Snapshot date: 2026-09-29
SHA-256: 3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c

Offline regeneration:
  python3 scripts/generate_garmin_catalog.py \
    /private/tmp/NextSet-Garmin-Exercises.json resources/data/garmin.xml

Codes are validated against the FIT profile of the pinned garmin-fit-sdk (pip install
garmin-fit-sdk==21.217.0). A code that is not a `<category>_exercise_name` value (generic code ==
category, newer names missing from the profile) becomes null: group-only in Connect.

The 2026-09-29 input snapshot is no longer available locally. The checked-in catalog was
revalidated in place (only the code fields changed) with:
  python3 scripts/generate_garmin_catalog.py --revalidate resources/data/garmin.xml
Copy the result to private/resources/data/garmin.xml.

Seeds (fail on an invalid garminCode) and tools/connect-sets/exercises.json (name -> category/name):
  python3 scripts/generate_garmin_catalog.py --seeds tools/connect-sets/exercises.json \
    resources/data/seeds.xml private/resources/data/seeds.xml
"""

import hashlib
import html
import json
import re
import sys
import xml.sax.saxutils as xml

from garmin_fit_sdk import Profile

SDK_VERSION = "21.217.0"
TYPES = Profile["types"]
CATEGORIES = {v.upper() for v in TYPES["exercise_category"].values()}


PINNED_SHA256 = "3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c"


def readable(code):
    return " ".join(word.capitalize() for word in code.lower().split("_"))


def valid_code(category, code):
    """The profile spelling of `code`, or None when Connect would reject it (group-only)."""
    if category not in CATEGORIES:
        raise ValueError("unknown exercise category: " + category)
    if code is None:
        return None
    names = {v.upper() for v in TYPES.get(category.lower() + "_exercise_name", {}).values()}
    # The profile spells `3_way_calf_raise` where Connect's JSON has `_3_way_calf_raise`.
    for candidate in (code, code.lstrip("_")):
        if candidate in names:
            return candidate
    return None


def write_xml(output, names, resources):
    with open(output, "w", encoding="utf-8") as out:
        out.write('<jsonDataResources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                  'xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">\n')
        out.write('  <jsonData id="GarminCategories">' + xml.escape(json.dumps(names, separators=(",", ":"))) + '</jsonData>\n')
        for index, rows in enumerate(resources):
            payload = json.dumps(rows, separators=(",", ":"))
            out.write('  <jsonData id="Garmin%02d">%s</jsonData>\n' %
                      (index, xml.escape(payload)))
        out.write('</jsonDataResources>\n')


def report(rows):
    group_only = [r["category"] + "/" + r["name"] for r in rows if r["code"] is None]
    print("valid=%d group-only=%d" % (len(rows) - len(group_only), len(group_only)))
    for entry in group_only:
        print("  group-only: " + entry)


def revalidate(path):
    text = open(path, encoding="utf-8").read()
    names = json.loads(html.unescape(re.search(r'id="GarminCategories">(.*)</jsonData>', text).group(1)))
    resources = [json.loads(html.unescape(m)) for m in
                 re.findall(r'id="Garmin\d\d">(.*)</jsonData>', text)]
    rows = [row for group in resources for row in group]
    for row in rows:
        row["code"] = valid_code(row["category"], row["code"])
    write_xml(path, names, resources)
    report(rows)


def seed_exercises(paths):
    exercises = {}
    for path in paths:
        text = open(path, encoding="utf-8").read()
        for e in json.loads(re.search(r'<jsonData id="Seeds">(.*)</jsonData>', text, re.S).group(1))["exercises"]:
            if valid_code(e["garminCategory"], e.get("garminCode")) != e.get("garminCode"):
                raise SystemExit("%s: %s has invalid garminCode %s/%s" %
                                 (path, e["name"], e["garminCategory"], e.get("garminCode")))
            exercises[e["name"]] = {"category": e["garminCategory"], "name": e.get("garminCode")}
    return exercises


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
                "code": valid_code(category, code),
                "isBodyWeight": metadata.get("isBodyWeight"),
            })
        resources.append(rows)
        total += len(rows)

    write_xml(output, names, resources)
    report([r for rows in resources for r in rows])
    print("categories=%d exercises=%d sha256=%s" %
          (len(categories), total, digest))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--revalidate":
        revalidate(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "--seeds":
        with open(sys.argv[2], "w") as out:
            json.dump(seed_exercises(sys.argv[3:]), out, indent=2)
            out.write("\n")
    elif len(sys.argv) == 3:
        main(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit("usage: generate_garmin_catalog.py Exercises.json output.xml | "
                         "--revalidate garmin.xml | --seeds exercises.json seeds.xml...")
