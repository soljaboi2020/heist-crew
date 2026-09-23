#!/usr/bin/env python3
"""
fetch_packs.py — re-download the CC0 art packs into src/assets/_kenney/.

WHY THIS EXISTS INSTEAD OF COMMITTING THE FILES
    The three packs are 68 MB across 2,485 files. Committing that would bloat the
    repo for art that is freely re-downloadable. So `src/assets/_kenney/` is
    gitignored and this script rebuilds it.

    What IS committed is the small set of .rbxmx models Malachi actually exports
    from Studio — the ones the game uses. See src/assets/README.md.

LICENCE
    All three packs are Kenney (kenney.nl), released CC0 / public domain.
    Free for personal, educational AND commercial use, no attribution required.
    Crediting Kenney is still the decent thing to do.

USAGE
    python3 tools/fetch_packs.py           # download anything missing
    python3 tools/fetch_packs.py --list    # show what's configured, download nothing
"""

import sys
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen

DEST = Path(__file__).resolve().parent.parent / "src" / "assets" / "_kenney"

PACKS = [
    (
        "kenney_modular-dungeon-kit_1.0.zip",
        "https://kenney.nl/media/pages/assets/modular-dungeon-kit/7bed87605b-1771926065/kenney_modular-dungeon-kit_1.0.zip",
        "39 models — corridor / corridor-corner / -intersection / -junction, room-small / -large / "
        "-wide, gate-door, gate-door-window, gate-metal-bars, stairs. The modular grid geometry the "
        "procedural-generation spec wants. ⚠️ Themed as a MEDIEVAL dungeon (purple stone, arched "
        "gates) — right shapes, wrong period for a mansion heist.",
    ),
    (
        "kenney_furniture-kit.zip",
        "https://kenney.nl/media/pages/assets/furniture-kit/440e0608a4-1677580847/kenney_furniture-kit.zip",
        "140 models — desk, deskCorner, bookcase*, cabinet*, chair*, computerScreen/Keyboard/Mouse, "
        "lamp*, rug*, table*, television*, cardboardBox*. Mansion interior dressing, plus the cover "
        "objects and keycard spawn points the heist design needs. Best thematic fit of the three.",
    ),
    (
        "kenney_factory-kit_3.0.zip",
        "https://kenney.nl/media/pages/assets/factory-kit/edaac9d4f6-1777639602/kenney_factory-kit_3.0.zip",
        "143 models — button-floor-round/-square (pressure plates), lever-single/-double, "
        "door-wide-closed/-half/-open, catwalk*, conveyor*, pipe*, crane, machine*, box*. The "
        "escape-game mechanics vocabulary. Modern industrial.",
    ),
]

# Every pack ships Models/ in FBX, OBJ, GLB (+ DAE/STL on some) with Textures/.
# FBX is what Studio's 3D Importer and the Roblox Open Cloud Assets API both take,
# so no format conversion is needed anywhere in this pipeline.
PREFERRED_FORMAT = "FBX format"


def fetch(name, url):
    zip_path = DEST / name
    out_dir = DEST / name.replace(".zip", "")
    if out_dir.is_dir():
        print(f"  ✓ {name} — already extracted, skipping")
        return
    DEST.mkdir(parents=True, exist_ok=True)
    print(f"  ↓ {name}")
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urlopen(req, timeout=180) as r:
        zip_path.write_bytes(r.read())
    with zipfile.ZipFile(zip_path) as z:
        z.extractall(out_dir)
    zip_path.unlink()
    n = sum(1 for _ in out_dir.rglob("*.fbx"))
    print(f"    extracted, {n} FBX models")


def main(argv):
    listing = "--list" in argv
    print(f"Kenney CC0 packs -> {DEST}\n")
    for name, url, desc in PACKS:
        print(f"• {name}")
        for line in (desc[i:i + 92] for i in range(0, len(desc), 92)):
            print(f"    {line}")
        if not listing:
            fetch(name, url)
        print()
    if listing:
        print("(--list given, nothing downloaded)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
