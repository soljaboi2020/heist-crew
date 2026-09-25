#!/usr/bin/env python3
"""Fail if any Luau file uses an Enum.Material name Roblox doesn't have.
The list was read from a live Studio (Enum.Material:GetEnumItems()) on 2026-09-25.
Both CorrugatedMetal and CorrugatedSteel look plausible and are NOT real."""
import glob, re, sys, os
VALID = set("""Plastic SmoothPlastic Neon Wood WoodPlanks Marble Basalt Slate CrackedLava Concrete Limestone
Granite Pavement Brick Pebble Cobblestone Rock Sandstone CorrodedMetal DiamondPlate Foil Metal Grass LeafyGrass
Sand Fabric Snow Mud Ground Asphalt Salt Ice Glacier Glass ForceField Air Water Cardboard Carpet CeramicTiles
ClayRoofTiles RoofShingles Leather Plaster Rubber""".split())
root = os.path.join(os.path.dirname(__file__), "..", "src")
bad = []
for f in glob.glob(os.path.join(root, "**", "*.lua"), recursive=True):
    s = open(f, encoding="utf-8", errors="ignore").read()
    aliases = set(re.findall(r"local\s+(\w+)\s*=\s*Enum\.Material\b", s)) | {"Enum.Material"}
    for a in aliases:
        for m in re.finditer(re.escape(a) + r"\.([A-Za-z]+)", s):
            n = m.group(1)
            if n not in VALID and n not in ("GetEnumItems", "FromName", "FromValue"):
                bad.append("%s: %s.%s" % (os.path.relpath(f, root), a, n))
    for m in re.finditer(r'Material\s*=\s*"(\w+)"', s):
        if m.group(1) not in VALID:
            bad.append("%s: Material = \"%s\"" % (os.path.relpath(f, root), m.group(1)))
for b in sorted(set(bad)):
    print("BAD MATERIAL", b)
sys.exit(1 if bad else 0)
