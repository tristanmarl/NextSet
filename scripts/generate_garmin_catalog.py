#!/usr/bin/env python3
"""Generate the compact Garmin exercise catalog resources.

Source: https://connect.garmin.com/web-data/exercises/Exercises.json
Snapshot date: 2026-09-29
SHA-256: 3b634d28d83c44183c323a16a6c62d1b0d6e93b1b128b7338c5e50ceed61af1c

Output format (resources/data/garmin.xml):
  GarminCategories  one JSON string: category codes, comma separated, sorted (index = resource number)
  Garmin00..46      one JSON string per category: comma separated entries CODE[*][!]
                    CODE  FIT exercise-name code (leading "_" stripped) or, with "!", the Connect code
                    *     bodyweight exercise
                    !     Connect knows only the category for this exercise (FIT code null)
Names are derived at runtime (title case of CODE, "_" -> space); ids are
"g" + 2-digit category index + "-" + lowercase CODE with "_" -> "-"; a slug over 36
characters keeps its first 16 and last 20 (see catalog_id). ids must be unique and valid for Model.validId; this script asserts it.

Offline regeneration:
  python3 scripts/generate_garmin_catalog.py \
    /private/tmp/NextSet-Garmin-Exercises.json resources/data/garmin.xml
Copy the result to private/resources/data/garmin.xml.

Codes are validated against the FIT profile of the pinned garmin-fit-sdk (pip install
garmin-fit-sdk==21.217.0). A code that is not a `<category>_exercise_name` value (generic code ==
category, newer names missing from the profile) is marked "!".

The 2026-09-29 input snapshot is no longer available locally. The checked-in catalog was converted
from the previous per-row JSON format with:
  python3 scripts/generate_garmin_catalog.py --convert old-garmin.xml original-garmin.xml resources/data/garmin.xml
where old-garmin.xml is the previous format (git show 0640a4c:resources/data/garmin.xml) and
original-garmin.xml carries the unvalidated Connect codes (git show 513e7cb^:resources/data/garmin.xml).

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


def catalog_id(index, code):
    slug = code.lstrip("_").lower().replace("_", "-")
    if len(slug) > 36:
        slug = slug[:16] + slug[-20:]  # keep in sync with Catalog.garminId; the split is collision-free
    return "g%02d-%s" % (index, slug)


def write_xml(output, categories):
    """categories: sorted list of (category, [(code, bodyweight, group_only)])."""
    seen = set()
    with open(output, "w", encoding="utf-8") as out:
        out.write('<jsonDataResources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                  'xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">\n')
        out.write('  <jsonData id="GarminCategories">"%s"</jsonData>\n' % ",".join(c for c, _ in categories))
        for index, (category, rows) in enumerate(categories):
            entries = []
            for code, bodyweight, group_only in rows:
                if not re.fullmatch(r"[A-Z0-9_]+", code) or code.startswith("_") and not group_only:
                    raise ValueError("unexpected code: " + code)
                exercise_id = catalog_id(index, code)
                if exercise_id in seen or not re.fullmatch(r"[a-z0-9-]{1,40}", exercise_id):
                    raise ValueError("exercise ID collision or invalid: " + exercise_id)
                seen.add(exercise_id)
                entries.append(code + ("*" if bodyweight else "") + ("!" if group_only else ""))
            out.write('  <jsonData id="Garmin%02d">"%s"</jsonData>\n' % (index, ",".join(entries)))
        out.write('</jsonDataResources>\n')
    group_only = ["%s/%s" % (c, r[0]) for c, rows in categories for r in rows if r[2]]
    print("categories=%d exercises=%d group-only=%d" %
          (len(categories), len(seen), len(group_only)))
    for entry in group_only:
        print("  group-only: " + entry)


def load_rows(path):
    text = open(path, encoding="utf-8").read()
    return [row for m in re.findall(r'id="Garmin\d\d">(.*)</jsonData>', text)
            for row in json.loads(html.unescape(m))]


def convert(old, original, output):
    originals = {row["id"]: row["code"] for row in load_rows(original)}
    by_category = {}
    for row in load_rows(old):
        code = row["code"]
        group_only = code is None
        if group_only:
            code = originals[row["id"]]
        else:
            assert valid_code(row["category"], code) == code, code
        if readable(code.lstrip("_")) != row["name"].strip():
            raise ValueError("derived name differs: %s vs %s" % (code, row["name"]))
        by_category.setdefault(row["category"], []).append((code, bool(row["isBodyWeight"]), group_only))
    write_xml(output, sorted(by_category.items()))


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
    categories = []
    for category, details in sorted(json.loads(raw)["categories"].items()):
        rows = []
        for code, metadata in sorted(details["exercises"].items()):
            fit = valid_code(category, code)
            rows.append((fit or code, metadata.get("isBodyWeight") is True, fit is None))
        categories.append((category, rows))
    write_xml(output, categories)
    print("sha256=" + digest)


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--convert":
        convert(*sys.argv[2:])
    elif len(sys.argv) >= 4 and sys.argv[1] == "--seeds":
        with open(sys.argv[2], "w") as out:
            json.dump(seed_exercises(sys.argv[3:]), out, indent=2)
            out.write("\n")
    elif len(sys.argv) == 3:
        main(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit("usage: generate_garmin_catalog.py Exercises.json output.xml | "
                         "--convert old.xml original.xml output.xml | --seeds exercises.json seeds.xml...")
