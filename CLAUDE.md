# CLAUDE.md — Heist Crew (Roblox Game)

> **Purpose:** Per-project context document. Read this at the start of every Heist Crew session so future Claude knows exactly where we are.

---

## 📛 Project Name & Goal

**Heist Crew** — a 4-player coop PvE Roblox game where crews execute heists on AI-guarded mansions, banks, and casinos. Inspired by Money Heist / Payday 2 / GTA V Heists, but **Roblox-native** with the viral hooks that actually move players (cash that goes up, gear unlocks, gamepasses, codes, FOMO heist events).

**Why we picked it:**
- The "Steal a [X]" genre on Roblox is saturated — Malachi's instinct to differentiate was correct.
- Heists give us a *narrative* hook (plan → infiltrate → crack → escape) competitors don't have.
- Coop multiplayer = friend-pull-in factor (one person joins, brings 3 friends).
- Monetizable in 6+ ways without feeling pay-to-win (cosmetics, crew slots, gear catalog, VIP, dev products for getaway boosts, etc.).
- Name "Heist Crew" verified **available** on Roblox (Malachi checked 2026-05-05).

## 📅 Date Created
- **2026-05-05** — Project scaffolded. Smoke-test phase ("Hello world" Rojo → Studio sync).

## 👤 Malachi's Roblox account
- **Username:** `Soljaboi1919` (confirmed 2026-05-05 via Studio Output: `[HEIST CREW] Soljaboi1919 joined the crew 💼`)

## 🗂️ Folder Structure

```
heist-crew/
├── CLAUDE.md                    ← this file (project context)
├── README.md                    ← public-facing setup + run guide
├── .gitignore                   ← excludes *.rbxl, sourcemap.json, OS junk
├── default.project.json         ← Rojo config (filesystem ↔ Studio mapping)
└── src/
    ├── server/
    │   └── init.server.lua      ← server bootstrap (runs on Roblox server)
    ├── client/
    │   └── init.client.lua      ← client bootstrap (runs on each player's device)
    └── shared/
        └── Constants.lua        ← single-source-of-truth game settings
```

**Rojo mapping (from `default.project.json`):**
| Filesystem path | Roblox service |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

## 🛠️ Tech Stack

- **Language:** Luau (Roblox's Lua dialect)
- **Engine:** Roblox Studio
- **Sync tool:** [Rojo](https://rojo.space/) v7.6.1 (CLI + Studio plugin)
- **Version control:** Git + GitHub (`soljaboi2020/heist-crew`)
- **Cross-machine workflow:** Laptop (Claude edits) → push to GitHub → Gaming PC (Studio) → pull → `rojo serve` → Studio Rojo plugin → Connect

## ▶️ How to run / preview

### On the **gaming PC** (where Roblox Studio runs):

**One-time setup:**
```powershell
# 1. Install Rojo CLI (skip if already installed — verify with `rojo --version`)
winget install Rojo.Rojo

# 2. Install Rojo plugin in Studio (skip if already installed)
#    https://create.roblox.com/store/asset/13916111004/Rojo
#    Or in Studio: Toolbox → Marketplace → Plugins → search "Rojo" → Get

# 3. Clone the repo
cd C:\Users\malac\Projects\source\personal
git clone https://github.com/soljaboi2020/heist-crew.git
cd heist-crew
```

**Daily workflow:**
```powershell
# 1. Pull latest from GitHub (whenever Claude has pushed new code from the laptop)
cd C:\Users\malac\Projects\source\personal\heist-crew
git pull

# 2. Start Rojo server
rojo serve
# (leave this PowerShell window open — it watches files and feeds Studio)

# 3. Open Roblox Studio → File → New Place
# 4. Plugins tab → Rojo → Connect (uses default port 34872)
# 5. Hit Play (F5) — should see in the Output window:
#       [HEIST CREW] Server online ✅
#       [HEIST CREW] Version 0.0.1 — Hello world phase
#       [HEIST CREW] <YourUsername> joined the crew 💼
#       [HEIST CREW] Client online ✅ — playing as <YourUsername>
```

**To stop:** `Ctrl+C` in the Rojo PowerShell window, then close Studio.

### On the **laptop** (where Claude edits):

Claude edits files in `/src/source/personal/heist-crew/` (which is `C:\Users\malac\Projects\source\personal\heist-crew\` on Windows). After each meaningful change, Claude auto-commits + pushes to GitHub per Rule #6. Malachi just runs `git pull` on the gaming PC to receive the changes.

## ✏️ How to edit / customize

| Want to change... | Edit this file |
|---|---|
| Game name, version, max crew size, payout limits | `src/shared/Constants.lua` |
| Server-side game logic (heists, AI, economy) | `src/server/init.server.lua` (currently a stub — services will be added as separate ModuleScripts) |
| Client-side UI, input, camera, effects | `src/client/init.client.lua` |
| What folders sync to which Studio services | `default.project.json` |
| Files git ignores | `.gitignore` |

**Convention:** any new server systems go in `src/server/<ServiceName>.lua` as ModuleScripts. Same for client (`src/client/<UIName>.lua`) and shared (`src/shared/<ModuleName>.lua`). The bootstrap files (`init.server.lua` / `init.client.lua`) just `require()` and start the modules.

## 🎯 Active Tasks / TODO

### Phase 0 — Smoke test ✅ DONE 2026-05-05
- [x] Scaffold project structure
- [x] Write Rojo config
- [x] Write server + client + shared bootstrap files
- [x] Initialize git + push to GitHub
- [x] Malachi clones on gaming PC + runs `rojo serve`
- [x] Malachi connects Studio's Rojo plugin → hits Play → confirms "[HEIST CREW] Server online ✅" in Output

### Phase 1 — Core framework ✅ DONE 2026-05-05
- [x] `PlayerDataService.lua` — DataStore wrapper for cash, level, owned gear, completed heists
- [x] `Remotes.lua` — central RemoteEvent / RemoteFunction registry
- [x] First spawn-and-greet flow (player joins → spawns in lobby with $100 starting cash visible on HUD)

### Phase 2 — First playable heist ✅ SHIPPED 2026-05-05 (we are here 🟢 — pending in-Studio verification)
- [x] Procedural mansion (60×40 stud building, walls + roof + door + signs)
- [x] Vault (gold DiamondPlate cube with ProximityPrompt, hold E for 8 sec)
- [x] Two patrolling AI guards (block-character build, vision cones, raycast LOS)
- [x] Getaway car (activates green/Neon when alarm fires, Touched = win)
- [x] State machine: IDLE → CRACKING → ESCAPING → COMPLETE/FAILED
- [x] Alarm system (red flashing border + screen-wide pulse)
- [x] Toast notifications (top-center sliding messages, color-coded)
- [x] Heist HUD (vault progress bar + state banner + countdown)
- [x] Stealth bonus payout (+$500 if escape without being spotted)

### Phase 3 — Multi-heist + economy
- [ ] 5 heist locations: small mansion, big mansion, bank, casino, museum
- [ ] Tool catalog: lockpick, EMP, silenced pistol, drill, thermal scope
- [ ] Shop UI for spending cash on tools
- [ ] Crew lobby — match with friends, ready-up, vote on heist
- [ ] Multiplayer crew system (multiple players sharing one heist instance)
- [ ] Lockpicking mini-game (the dial-tolerance system from Constants) — currently replaced with hold-E-on-vault, will revisit

### Phase 4 — Monetization
- [ ] Gamepass: VIP Crew (cosmetic vault, +10% payout)
- [ ] Gamepass: Extra Crew Slot (5-player crews)
- [ ] Dev products: Getaway Boost, Skip Lockpick, Extra Loot Roll
- [ ] Daily login rewards + login streak

### Phase 5 — Polish + launch
- [ ] Sound FX + ambient audio + music stings on alarm trigger
- [ ] Cinematic camera on heist start ("the briefing")
- [ ] Notification system + toasts
- [ ] Codes system (Twitter / TikTok promo codes)
- [ ] Soft launch to friends — iterate on feedback
- [ ] Public launch + `@heistcrewroblox` TikTok push

## ✅ Completed
- [x] **2026-05-05** — Picked the game concept (Heist Crew, after rejecting "Steal a Drip" for being in a saturated genre)
- [x] **2026-05-05** — Verified name available on Roblox
- [x] **2026-05-05** — Set up cross-machine workflow (laptop → GitHub → gaming PC) using Malachi's existing GitHub Desktop install
- [x] **2026-05-05** — Installed Rojo CLI v7.6.1 + Rojo Studio plugin on gaming PC
- [x] **2026-05-05** — Project scaffolded: Rojo config + 3 bootstrap scripts + Constants module + .gitignore

## 📌 Decisions & Notes

### Game design choices
- **4-player crews** (not 5 or 6) — small enough that everyone has a role, big enough to feel like a heist movie.
- **PvE not PvP** — coop = friend recruitment. PvP = matchmaking nightmare for a solo dev.
- **Stealth-first** — guards use vision cones (90° FOV, 30 stud range, 8 sec alert duration). Player can choose to go loud, but stealth bonuses payout +50%.
- **Cash > XP** — Malachi confirmed players come back for "numbers go up." Cash is the main progression loop; cosmetics are the prestige loop.
- **Procedural rooms** — heists must feel different every run, otherwise it's a one-and-done game. Hand-placed environments for hub/lobby only.

### Code conventions
- **Use `init.server.lua` / `init.client.lua` as bootstraps**, not as the actual logic dump. Real systems go in ModuleScripts.
- **Constants in `Shared`** so client UI can show the same "$10M MAX PAYOUT" the server enforces.
- **Print statements use `[HEIST CREW]` prefix** so they're greppable in the Studio Output window.
- **Always `require(game:GetService("X"))`** — never trust `script.Parent.Parent.Parent` indirection (breaks when files move).

### Workflow notes
- **Laptop = code, gaming PC = run.** Bridge is GitHub. Same flow as `malachi-builds` and `shine-pro-exterior`.
- **Auto-deploy enabled** (Rule #6) — Claude pushes to `main` directly via `/src/.git-credentials`. Malachi just pulls.
- **`.rbxl` / `.rbxlx` files are git-ignored** — the source of truth is the Lua + JSON files. The Studio place file is rebuilt on each session via Rojo.

### Things to NOT do
- ❌ Don't hand-edit code inside Studio — Studio is for **previewing**, not for editing. Claude edits files on disk; Rojo syncs them in.
- ❌ Don't commit `*.rbxl` files — bloats the repo and can't be merged.
- ❌ Don't put game logic in `init.server.lua` — keep that file as a 30-line bootstrap.

## 📅 Change Log
- **2026-05-05** — Project created. Rojo config + bootstrap scripts + Constants module written. Smoke test phase started. Initial commit pushed to GitHub.
- **2026-05-05** — **🎉 PHASE 0 SMOKE TEST PASSED.** Malachi cloned the repo on his gaming PC via GitHub Desktop, ran `rojo serve` from VS Code's integrated terminal, connected the Rojo plugin in Studio, and hit Play. All 3 print statements (Server online / Player joined / Client online) appeared in the Output window. Confirmed Roblox username: `Soljaboi1919`. Full pipeline (laptop → GitHub → gaming PC → Rojo → Studio) verified working. Phase 1 (core framework) starts next.
- **2026-05-05** — **🎉 PHASE 1 SHIPPED + VERIFIED.** Pushed commit `c78c39f`: 5 new modules (Remotes, PlayerDataService, EconomyService, TestPad, CashHud) + bumped version to 0.1.0. Malachi pulled via GitHub Desktop, Rojo hot-reloaded, hit Play in Studio. Verified: green cash HUD appears top-right showing $100, glowing green pad spawned at (20, 0, 0), stepping on pad triggered 3 successful touches (100→150→200→250), HUD bounce animation fired on each, EconomyService server-side prints confirmed. Full gameplay loop (touch → server → DataStore → remote → HUD animation) verified end-to-end. Ready for Phase 2 (first heist room).
- **2026-05-05** — **🎉 PHASE 2 MEGA-PUSH — FULL PLAYABLE HEIST.** Bumped version to 0.2.0. Per Malachi's request "add everything to make playable," shipped one giant push containing:
  - **`HeistBuilder.lua`** — procedural mansion (60×40 floor, 4 walls split around 12-stud doorway, translucent roof, "🏛 MANSION HEIST" sign), gold DiamondPlate vault with PointLight, dark metal getaway car (body + roof + 4 wheels), decorative green Neon spawn ring, mansion centered at (0, 0, -160), vault at (0, 5, -185), getaway at (0, 2, -70).
  - **`GuardService.lua`** — 2 patrolling guards (block-character: body + head + hat + SpotLight vision cone). 90° FOV cone check via dot-product, line-of-sight via raycast, 35-stud vision range. PATROL state walks waypoint A↔B; CHASE state activates on alarm and beelines to last-known player position. Touched event = caught.
  - **`HeistService.lua`** — state machine (IDLE / CRACKING / ESCAPING / COMPLETE / FAILED). Vault uses ProximityPrompt with `HoldDuration=8`, `KeyCode=E`. On full hold: pays $1500, fires alarm to all clients, activates getaway car (green Neon glow), starts 90s escape timer. Getaway car Touched = $1000 escape + $500 stealth bonus if not spotted. Caught/spotted while CRACKING/ESCAPING = fail + teleport back to spawn. After 30s cooldown, vault re-arms.
  - **`Notifications.lua`** (client) — top-center sliding toast system. Color map (green/red/gold/white) feeds UIStroke + label color. Tweens in from above, auto-fades after duration.
  - **`HeistHud.lua`** (client) — three UI elements: (1) full-screen alarm border with 4 red bars + "🚨 ALARM TRIGGERED" text pulsing via sine wave, (2) vault progress bar bottom-center with gold fill + "🔧 CRACKING... X%" label, (3) state banner top-center with live ESCAPE countdown.
  - **`Constants.lua`** updated with Guard AI / Vault / Heist Payout / World coordinate / Color sections.
  - **`Remotes.lua`** added: `HeistState`, `VaultProgress`, `AlarmTriggered`, `Notify`.
  - **`init.server.lua`** wires it all together: `HeistBuilder:build()` → `GuardService:spawnPatrols(callbacks)` → `HeistService:init(refs, GuardService, EconomyService)` → `TestPad:spawn()`.
  - **`init.client.lua`** mounts `Notifications` + `HeistHud` alongside `CashHud`.
  - **Pending verification** — Malachi needs to pull, hit F5, walk to mansion (~150 studs north), sneak past guards (yellow vision cones), hold E on vault, escape to getaway car within 90s. Stealth run = $3,000 total payout.

## 📑 Reference docs
*(none yet — will add as project grows)*

When sections of this file balloon past ~40 lines, split them into `docs/`:
- `docs/HEIST_DESIGN.md` — detailed level design / loot tables / guard behaviors
- `docs/MONETIZATION.md` — gamepass + dev product price math
- `docs/SOUND_DESIGN.md` — music stings, ambient layers, alarm SFX
- `docs/LAUNCH_PLAYBOOK.md` — TikTok + Discord + soft-launch sequencing
