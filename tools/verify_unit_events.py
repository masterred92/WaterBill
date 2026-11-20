#!/usr/bin/env python3
"""Frost Suite: every event the addon registers with RegisterUnitEvent("EVENT", ...) or lists in an EVENTS table must exist
in Blizzard's API docs. (verify_api.py and test_blizzard_docs.lua only see RegisterEvent("...").)
usage: tools/verify_unit_events.py <wow-ui-source checkout>"""
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
doc = pathlib.Path(sys.argv[1]) / "Interface/AddOns/Blizzard_APIDocumentationGenerated"
alldocs = "\n".join(p.read_text(errors="ignore") for p in doc.glob("*.lua"))
events = set(re.findall(r'LiteralName = "(\w+)"', alldocs))
toc = next(root.glob("*.toc"))
files = [root / l.strip().replace("\\", "/") for l in toc.read_text().splitlines() if l.strip().endswith(".lua") and not l.startswith("#")]
code = "\n".join(re.sub(r"--[^\n]*", "", f.read_text()) for f in files)
found = set(re.findall(r'RegisterUnitEvent\("(\w+)"', code))
for m in re.finditer(r'EVENTS\s*=\s*\{(.*?)\}', code, re.S): found |= set(re.findall(r'"([A-Z_]+)"', m.group(1)))
ok, bad = 0, []
for e in sorted(found):
    if e in events: ok += 1
    else: bad.append(e)
for b in bad: print("MISS event", b)
print(f"{ok}/{len(found)} unit/table events verified")
sys.exit(1 if bad else 0)
