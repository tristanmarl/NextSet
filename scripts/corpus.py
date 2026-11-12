#!/usr/bin/env python3
"""Regenerates the Liftosaur built-in program corpus used by tests/CorpusTests.mc.

Fetches the public built-in programs (programs/builtin/*.md in github.com/astashov/liftosaur,
nothing from any account), extracts only the ```liftoscript block, computes the expected
LiftosaurLogic.parseDays result with an independent Python model of its rules and writes
  tests/resources/data/corpus1.xml ... corpusN.xml   (JSON data resources, ~100 KB each)
  tests/CorpusData.mc                                (resource id list)
  docs/CORPUS.md                                     (result table)
Usage: scripts/corpus.py [cache_dir]   (cache_dir keeps the downloaded .md files)
"""
import json, os, re, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "astashov/liftosaur"
MAX_BYTES, MAX_DAYS, MAX_WEEKS, MAX_NAME, MAX_TEMPLATES = 16384, 160, 104, 64, 8
FILE_BUDGET = 100_000
SPACE = " \t\r"


def get(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode("utf-8")


def program_ids():
    tree = json.loads(get(f"https://api.github.com/repos/{REPO}/git/trees/master?recursive=1"))
    return sorted(t["path"][len("programs/builtin/"):-3] for t in tree["tree"]
                  if t["path"].startswith("programs/builtin/") and t["path"].endswith(".md"))


def liftoscript(markdown):
    blocks = re.findall(r"^```liftoscript\n(.*?)^```", markdown, re.S | re.M)
    assert len(blocks) == 1, "expected one liftoscript block"
    return blocks[0].rstrip("\n")


def parse_days(text):
    """Mirror of LiftosaurLogic.parseDays (ideal semantics, no chunk effects).
    Returns (weeks, None) or (None, problem)."""
    if len(text.encode("utf-8")) > MAX_BYTES:
        return None, "Program over 16 KB"
    weeks, current, implicit, total = [], None, False, 0
    for raw in text.split("\n"):
        line = raw.strip(SPACE)
        if not line or line[0] != "#":
            continue
        def problem(why):
            return None, f'Line "{line[:24]}": {why}'
        if line[1:2] == "#":
            if len(line) < 3 or line[2] != " ":
                return problem("day header needs a space")
            name = line[3:].strip(" \t\r\n")
            nb = name.encode("utf-8")
            if len(nb) > MAX_NAME or not any(b > 32 and b != 127 for b in nb):
                return problem("bad day name")
            if current is None:
                current, implicit = [], True
                weeks.append(current)
            current.append(name)
            total += 1
            if total > MAX_DAYS:
                return None, f"Program over {MAX_DAYS} days"
        else:
            if implicit:
                return problem("week header after days")
            if len(weeks) >= MAX_WEEKS:
                return None, f"Program over {MAX_WEEKS} weeks"
            current = []
            weeks.append(current)
    if total == 0:
        return None, "No days (## Name) in program"
    return weeks, None


def main():
    cache = sys.argv[1] if len(sys.argv) > 1 else None
    if cache:
        os.makedirs(cache, exist_ok=True)
    programs = []
    for pid in program_ids():
        path = os.path.join(cache, pid + ".md") if cache else None
        if path and os.path.exists(path):
            md = open(path, encoding="utf-8").read()
        else:
            md = get(f"https://raw.githubusercontent.com/{REPO}/master/programs/builtin/{pid}.md")
            if path:
                open(path, "w", encoding="utf-8").write(md)
        text = liftoscript(md)
        assert "]]>" not in text
        weeks, why = parse_days(text)
        longest = max((len(l) for l in text.split("\n")), default=0)
        programs.append({"id": pid, "text": text, "weeks": weeks, "problem": why, "longest": longest})

    # fixtures, grouped by size
    groups, cur, size = [], [], 0
    for p in programs:
        n = len(json.dumps(p["text"])) + 600
        if cur and size + n > FILE_BUDGET:
            groups.append(cur)
            cur, size = [], 0
        cur.append(p)
        size += n
    groups.append(cur)
    data_dir = os.path.join(ROOT, "tests/resources/data")
    for f in os.listdir(data_dir):
        if re.fullmatch(r"corpus\d+\.xml", f):
            os.remove(os.path.join(data_dir, f))
    ids, index = [], 0
    head = ('<jsonDataResources xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">\n')
    for g, group in enumerate(groups, 1):
        out = [head]
        for p in group:
            rid = "Corpus%02d" % index
            index += 1
            ids.append((rid, p["id"]))
            doc = {"id": p["id"], "text": p["text"],
                   "weeks": p["weeks"] if p["weeks"] is not None else [], "problem": p["problem"]}
            out.append(f'  <jsonData id="{rid}"><![CDATA[\n{json.dumps(doc, ensure_ascii=False)}\n]]></jsonData>\n')
        out.append("</jsonDataResources>\n")
        open(os.path.join(data_dir, f"corpus{g}.xml"), "w", encoding="utf-8").write("".join(out))
    with open(os.path.join(ROOT, "tests/CorpusData.mc"), "w") as f:
        f.write("// Generated by scripts/corpus.py; do not edit.\nimport Toybox.Lang;\nimport Toybox.WatchUi;\n\n"
                "function corpusIds() as Array {\n    return [\n")
        f.write(",\n".join(f"        Rez.JsonData.{rid}" for rid, _ in ids))
        f.write("\n    ];\n}\n")

    rows = ["# Liftosaur built-in program corpus", "",
            "Generated by `scripts/corpus.py` from the public programs in github.com/astashov/liftosaur. "
            "Expected values come from a Python model of `LiftosaurLogic.parseDays`; "
            "`tests/CorpusTests.mc` checks the watch parser against them.", "",
            "| Program | Bytes | Weeks | Days | Max days/week | Longest line | Result |", "|---|---|---|---|---|---|---|"]
    for p in programs:
        b = len(p["text"].encode("utf-8"))
        if p["weeks"] is None:
            w = d = m = "-"
            res = "REJECTED: " + p["problem"]
        else:
            w, d, m = len(p["weeks"]), sum(map(len, p["weeks"])), max(map(len, p["weeks"]))
            res = "ok" + (f" (a week over {MAX_TEMPLATES} days)" if m > MAX_TEMPLATES else "")
        rows.append(f"| {p['id']} | {b} | {w} | {d} | {m} | {p['longest']} | {res} |")
    open(os.path.join(ROOT, "docs/CORPUS.md"), "w").write("\n".join(rows) + "\n")
    print("\n".join(rows))


main()
