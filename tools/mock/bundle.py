import os, sys, glob
HERE = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(HERE, "..", ".."))
out = ["SOURCES = {}"]
for path in sorted(glob.glob(root + "/src/**/*.lua", recursive=True)):
    rel = os.path.relpath(path, root)
    src = open(path, encoding="utf-8").read().replace("\r\n", "\n").replace("\r", "\n")
    lvl = 1
    while ("]" + "=" * lvl + "]") in src: lvl += 1
    eq = "=" * lvl
    out.append(f'SOURCES["{rel}"] = [{eq}[\n{src}]{eq}]')
parts = ["\n".join(out)]
for f in ["mock_types.luau", "mock_core.luau", "mock_game.luau"] + sys.argv[2:]:
    parts.append(open(os.path.join(HERE, f)).read())
open(sys.argv[1], "w").write("\n".join(parts))
