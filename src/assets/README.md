# src/assets — hand-built and downloaded models

Everything in here syncs into **`ReplicatedStorage.Assets`** in Studio (see
`default.project.json`). Code clones from there at runtime; nothing in this folder
is live in the world by itself.

## The loop

1. **Find it** — Studio → Toolbox → Models, or the Creator Store.
2. **Drop it in the workspace**, look at it, check the scale against a character (a
   Roblox character is about 5 studs tall).
3. **Right-click the model → Save to File…** → choose **`.rbxmx`** (XML, *not* `.rbxm`) →
   save it into this folder.
4. **Vet it** before it goes anywhere near a playtest:
   ```
   cd D:\Projects\source\personal\heist-crew
   python3 tools/vet_model.py src/assets/
   ```
5. **Tell Claude it's here** and he writes the code that places it.

## Naming

Name the file what the thing *is*, in PascalCase with underscores between words:
`Mansion_Door.rbxmx`, `Office_Desk.rbxmx`, `Getaway_Van.rbxmx`. That name becomes the
instance name in `ReplicatedStorage.Assets`, so code refers to it directly.

## ⚠️ Why the vetting step is not optional

Free Toolbox models are one of the best-known malware vectors on Roblox. People hide
scripts inside ordinary-looking props that steal the game, spam players, prompt fake
purchases, or beacon out to a Discord webhook. They bury them several instances deep
under boring names — the test case that built this tool hid inside a chair cushion in a
script called `Weld`.

`tools/vet_model.py` reads the XML and reports every script in the model plus what it
does. It **changes nothing** — it only looks. A clean report means "nothing matched the
known patterns", not "guaranteed safe". **A decorative prop should contain no scripts at
all**; if one does, that alone is worth a hard look.

## Why `.rbxmx` and not `.rbxm`

`.rbxmx` is XML — diffable, greppable, committable, and readable by the vetting tool.
`.rbxm` is binary: git can't merge it, and nobody can see what's inside. `.gitignore` is
set up to keep `.rbxmx` and reject `.rbxm`.
