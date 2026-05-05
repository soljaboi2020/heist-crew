# Heist Crew 🎭💰

A 4-player coop heist game on Roblox. Crack vaults, dodge guards, escape with the bag.

> **Status:** 🟢 Phase 0 — smoke test. Just the bootstrap scaffold so far. Real game logic comes next.

---

## 🚀 Quick start (gaming PC)

### One-time setup

```powershell
# 1. Install Rojo CLI (skip if already installed)
winget install Rojo.Rojo

# 2. Install the Rojo plugin in Roblox Studio
#    https://create.roblox.com/store/asset/13916111004/Rojo

# 3. Clone this repo
cd C:\Users\malac\Projects\source\personal
git clone https://github.com/soljaboi2020/heist-crew.git
cd heist-crew
```

### Daily workflow

```powershell
# 1. Pull the latest code
cd C:\Users\malac\Projects\source\personal\heist-crew
git pull

# 2. Start Rojo (leave this window open)
rojo serve
```

Then in Roblox Studio:
1. **File → New Place**
2. **Plugins** tab → **Rojo** → **Connect** (default port 34872)
3. Hit **Play (F5)**

You should see this in the Output window:

```
══════════════════════════════════════════
[HEIST CREW] Server online ✅
[HEIST CREW] Version 0.0.1 — Hello world phase
══════════════════════════════════════════
[HEIST CREW] <YourName> joined the crew 💼
══════════════════════════════════════════
[HEIST CREW] Client online ✅ — playing as <YourName>
══════════════════════════════════════════
```

That's it — Rojo is syncing and the smoke test passed. 🎉

---

## 🗂️ Project structure

```
heist-crew/
├── default.project.json   ← Rojo file→service mapping
├── src/
│   ├── server/            → ServerScriptService.Server
│   ├── client/            → StarterPlayer.StarterPlayerScripts.Client
│   └── shared/            → ReplicatedStorage.Shared
├── CLAUDE.md              ← project context / TODO / decisions
└── README.md              ← you're reading it
```

---

## 🛠️ Tech

- **Language:** Luau (Roblox Lua)
- **Sync:** Rojo 7.x
- **Source of truth:** the Lua + JSON files in this repo. Studio `.rbxl` files are NOT committed (git-ignored).

---

## 🎮 Game concept

You and up to 3 friends form a crew. Pick a target (mansion → bank → casino → museum), gear up in the lobby, infiltrate, crack the vault, escape before guards lock down the perimeter. Stealth bonus pays +50%. Loud also works but expect lead.

Progression is cash + gear + cosmetic prestige. No PvP. No pay-to-win. Just heist after heist after heist.

---

## 📜 License

Private. All rights reserved (for now). © 2026 Malachi Builds.
