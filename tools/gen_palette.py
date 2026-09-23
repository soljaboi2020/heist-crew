#!/usr/bin/env python3
"""
gen_palette.py — regenerate src/shared/KenneyPalette.lua from the furniture kit.

WHY
    Kenney's furniture-kit ships no texture images. It colours models with named
    flat materials whose RGB lives in the .mtl files, and Roblox's FBX importer
    drops them — every piece imports white.

    This parses all 140 .mtl files for their real Kd values, and COUNTS FACES per
    material in the matching .obj so the "dominant" material is measured rather
    than assumed. Output is a Lua table the placement code uses to tint each
    imported MeshPart back to its intended colour.

    The dungeon and factory kits don't need this — they ship texture atlases.

USAGE
    python3 tools/fetch_packs.py      # packs must be on disk first
    python3 tools/gen_palette.py
"""
import collections
import glob
import os
import sys

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "src", "assets", "_kenney", "kenney_furniture-kit", "Models", "OBJ format")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "src", "shared", "KenneyPalette.lua")

# 'lamp' -> Neon is deliberate: a bulb is the small emissive accent Neon is for.
ROBLOX_MAT = {
    "wood": "Wood", "woodDark": "Wood", "metal": "Metal", "metalDark": "Metal",
    "metalLight": "Metal", "metalMedium": "Metal", "carpet": "Fabric",
    "carpetBlue": "Fabric", "carpetWhite": "Fabric", "carpetDarker": "Fabric",
    "fur": "Fabric", "glass": "Glass", "plant": "Grass", "lamp": "Neon",
    "_defaultMat": "SmoothPlastic",
}


def parse_mtl(path):
    cols, cur = {}, None
    for line in open(path, errors="ignore"):
        line = line.strip()
        if line.startswith("newmtl "):
            cur = line.split(None, 1)[1].strip()
        elif line.startswith("Kd ") and cur:
            r, g, b = (float(x) for x in line.split()[1:4])
            cols[cur] = (round(r * 255), round(g * 255), round(b * 255))
    return cols


def dominant(obj_path):
    counts, cur = collections.Counter(), None
    for line in open(obj_path, errors="ignore"):
        if line.startswith("usemtl "):
            cur = line.split(None, 1)[1].strip()
        elif line.startswith("f ") and cur:
            counts[cur] += 1
    return (counts.most_common(1)[0][0] if counts else None), dict(counts)


def main():
    if not os.path.isdir(BASE):
        print(f"Pack not found at {BASE}\nRun: python3 tools/fetch_packs.py")
        return 1
    rows, mats = [], {}
    for obj in sorted(glob.glob(os.path.join(BASE, "*.obj"))):
        name = os.path.splitext(os.path.basename(obj))[0]
        mtl = obj[:-4] + ".mtl"
        if not os.path.exists(mtl):
            continue
        cols = parse_mtl(mtl)
        dom, _ = dominant(obj)
        if dom and dom in cols:
            rows.append((name, dom))
            mats[dom] = cols[dom]
    print(f"{len(rows)} models, {len(mats)} materials -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
