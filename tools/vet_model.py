#!/usr/bin/env python3
"""
vet_model.py — scan a Roblox .rbxmx model for hidden/malicious scripts.

WHY THIS EXISTS
    Free Toolbox models are a well-known malware vector on Roblox. People hide
    scripts inside furniture that steal the game, spam players, or phone home to
    a Discord webhook. The scripts are usually buried several instances deep
    where nobody clicks, and often obfuscated.

    .rbxmx is XML, so the whole model — including every script's source — is
    readable text. This reads it and reports what's in there.

WHAT IT DOES *NOT* DO
    It changes nothing. It only reads and reports. It is a flashlight, not a
    cleaner — removing a script is a decision for a human looking at the model.

    It is also NOT a guarantee. A clean report means "nothing matched the known
    patterns", not "this model is definitely safe". A decorative model that
    contains ANY script at all is already odd and worth a hard look.

USAGE
    python3 tools/vet_model.py src/assets/SomeModel.rbxmx
    python3 tools/vet_model.py src/assets/          # whole folder
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}

# (label, regex, severity) — severity: 'high' is near-certainly bad in a prop model
PATTERNS = [
    ("remote require() by asset id", r"require\s*\(\s*\d{6,}", "high"),
    ("loadstring", r"\bloadstring\s*\(", "high"),
    ("getfenv / setfenv", r"\b(get|set)fenv\s*\(", "high"),
    ("Discord webhook", r"discord(app)?\.com/api/webhooks", "high"),
    ("HTTP request out", r"(HttpService|HttpGet|GetAsync|PostAsync|RequestAsync)", "high"),
    ("hex-escaped string blob", r"(\\x[0-9A-Fa-f]{2}){8,}", "high"),
    ("decimal-escaped blob", r"(\\\d{2,3}){12,}", "high"),
    ("prompts a purchase", r"PromptPurchase|PromptProductPurchase|MarketplaceService", "high"),
    ("bans / kicks players", r":Kick\s*\(|:Ban", "high"),
    ("touches DataStores", r"DataStoreService|GetDataStore", "high"),
    ("grabs LocalPlayer", r"LocalPlayer", "low"),
    ("creates a RemoteEvent", r"RemoteEvent|RemoteFunction", "low"),
    ("run-time instance creation", r"Instance\.new", "low"),
]


def iter_instances(elem, path=""):
    """Walk the .rbxmx tree yielding (class_name, name, element, path)."""
    for item in elem.findall("Item"):
        cls = item.get("class", "?")
        name = "?"
        props = item.find("Properties")
        if props is not None:
            for tag in ("string", "ProtectedString"):
                for node in props.findall(tag):
                    if node.get("name") == "Name":
                        name = (node.text or "?").strip()
        here = f"{path}/{name}"
        yield cls, name, item, here
        yield from iter_instances(item, here)


def source_of(item):
    props = item.find("Properties")
    if props is None:
        return ""
    for node in list(props.findall("ProtectedString")) + list(props.findall("string")):
        if node.get("name") == "Source":
            return node.text or ""
    return ""


def vet(path: Path) -> int:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        print(f"  ⚠️  could not parse as XML ({e}).")
        print("      If this is a .rbxm it's BINARY — re-save it from Studio as .rbxmx.")
        return 1

    total = scripts = 0
    findings = []

    for cls, name, item, where in iter_instances(root):
        total += 1
        if cls not in SCRIPT_CLASSES:
            continue
        scripts += 1
        src = source_of(item)
        hits = [(label, sev) for label, rx, sev in PATTERNS
                if re.search(rx, src, re.IGNORECASE)]
        findings.append((cls, where, len(src), hits, src))

    print(f"  {total} instances, {scripts} script(s)")

    if scripts == 0:
        print("  ✅ No scripts at all — for a decorative model this is what you want.")
        return 0

    worst = 0
    for cls, where, size, hits, src in findings:
        high = [h for h, s in hits if s == "high"]
        low = [h for h, s in hits if s == "low"]
        mark = "🚨" if high else ("⚠️" if low else "❓")
        worst = max(worst, 2 if high else 1)
        print(f"\n  {mark} {cls} at {where}  ({size} chars)")
        for h in high:
            print(f"       HIGH  {h}")
        for h in low:
            print(f"       note  {h}")
        if not hits:
            print("       no known-bad patterns, but a prop containing a script is still odd")
        preview = " ".join(src.split())[:200]
        if preview:
            print(f"       source: {preview}{'…' if len(preview) == 200 else ''}")

    print()
    if worst == 2:
        print("  🚨 DO NOT USE AS-IS. Delete the flagged scripts in Studio, re-save, re-run.")
    elif worst == 1:
        print("  ⚠️  Scripts present. A chair does not need code — look before shipping it.")
    else:
        print("  ❓ Scripts present but nothing matched. Read them yourself before shipping.")
    return worst


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    target = Path(argv[1])
    files = sorted(target.glob("*.rbxmx")) if target.is_dir() else [target]
    if not files:
        print(f"No .rbxmx files found in {target}")
        return 0
    worst = 0
    for f in files:
        print(f"\n=== {f.name} ===")
        worst = max(worst, vet(f))
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv))
