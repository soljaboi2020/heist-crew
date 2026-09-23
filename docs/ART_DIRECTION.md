# Heist Crew — Art Direction

> Written 2026-09-22 after Malachi said *"it just dosent look like a real good roblox game."*
> He was right. This is the plan for fixing it, and the rules that stop it regressing.

---

## The references he picked

| Game | What we take from it |
|---|---|
| **Jailbreak** | The ceiling. Real architecture, believable buildings, restrained realistic palette. This is the only one of the four that needs modelled art. |
| **Steal a Brainrot** | Bright, saturated, instantly readable. Big obvious interactables. Clean screen UI. |
| **Cheese Escape** | Darkness as a tool. Tension from *not* being able to see. Simple geometry, strong mood. |
| **Flood Escape 2** | Colour-coding. You always know what a thing does by looking at it. Clean shapes, good lighting. |

**The important observation: three of those four are simple geometry.** They don't look good
because of an art budget — they look good because of lighting, palette discipline and clean UI.
All three of those are things code can do. That's the bulk of the gap, and it's free.

---

## The five rules

These are what the 2026-09-22 screenshot broke. Check any new build against them.

### 1. Neon is an accent, never a surface
Neon is fully emissive — no shading, no shadow, no depth. A large neon surface reads as a flat
blob and tints everything near it.

- ✅ Lamp bulbs, vault gems, headlights, alarm strips, small trim
- ❌ Floors, walls, paths, plazas, anything a player walks on

*What went wrong:* the plaza "ring" was a 56-stud solid neon cylinder and the path edging was
two full-length neon strips. Together they lit the entire level yellow.

### 2. Light comes from light sources, not from the floor
If something looks lit, it should be because a `PointLight`/`SpotLight` put light there. Keep
lamps dim and tight (`Brightness ~1.4`, `Range ~17`) so there are **pools of light with dark
between them**. Bright everywhere is the same as flat.

### 3. Text goes on surfaces or on the screen — never floating in the world
`BillboardGui` floating in midair is the single clearest "unfinished Roblox game" tell, and the
screenshot had five at once, overlapping.

- ✅ `SurfaceGui` printed on a wall, a sign, a pedestal face
- ✅ Screen-space HUD (see the v1.0 vision board in `docs/mockups/`)
- ❌ Floating labels — with one exception: a short NPC speech bubble is fine

### 4. Everything gets a real Material
`SmoothPlastic` is why untextured boxes look like untextured boxes. Roblox's built-in materials
carry genuine surface detail and cost nothing.

Brick · Concrete · Slate · WoodPlanks · Marble · Metal · Fabric · Grass · Sand · Pebble

### 5. Contrast between spaces is the cheapest tension there is
**Lobby = bright, safe, clean** (Brainrot / FE2). **Mansion interior = dim, tense, dangerous**
(Cheese Escape). Walking from one into the other should feel like something.

This also fixes gameplay: the guards' vision cones are currently invisible against a blown-out
yellow world. In a dim room, those cones become the whole stealth game.

---

## Two tracks

### Track A — code (Claude, no assets needed)
Gets it from "clearly unfinished" to "looks deliberate". Maybe 60–70% of the way.

- [x] **Lobby pass 1** — killed the neon plaza + path strips, removed floating labels, rebalanced
      bloom/saturation/lamps (v0.5.0, commit `1b4effd`)
- [ ] Mansion exterior — real materials, window openings, framed doorway, steps, roof trim
- [ ] Mansion interior — drop the light level hard, lamp pools, make the guard cones matter
- [ ] Layout spacing — the mansion moved from z=-160 to z=-55 in May and overcorrected; there's
      no sense of approach now
- [ ] Screen-space HUD matching the vision board, replacing the last of the world text
- [ ] Colour-code every interactable so its function is readable at a glance (FE2 rule)

### Track B — art (Malachi in Studio, or bought/free models)
The rest. Needed for the Jailbreak tier.

**This is now unblocked:** `.rbxmx` was being gitignored, so any model saved into the repo would
have vanished silently. Fixed in commit `7dd8369`. The workflow is:

> Studio → build the model → right-click → **Save to File** → `.rbxmx` → save into `src/assets/`
> → Claude adds the Rojo mapping and writes the placement logic.

`.rbxmx` is XML, so it diffs and commits like code. `.rbxm` (binary) stays ignored.

#### The room kit, when we get to procedural generation
Four modules, each built to a **32 × 32 stud** footprint with walls meeting the edges cleanly:

| Model name | Purpose |
|---|---|
| `North_South_Hall` | Corridor running N↔S |
| `East_West_Hall` | Corridor running E↔W |
| `Dead_End_Office` | One entrance, decoy room, good keycard spawn |
| `Vault_Room` | Always placed furthest from the entrance |

Each needs `Attachment`s named `Door_North`, `Door_South`, `Door_East`, `Door_West` at the exact
wall midpoints — that's what the generator snaps together. Props (desks, crates, pillars) go in a
flat folder and get scattered at runtime; they double as guard patrol waypoints and player cover.

⚠️ **Toolbox free models:** a well-known vector for malicious scripts. Anything pulled from the
Toolbox gets inspected before it goes in the repo — no exceptions.

---

## Known limit, stated plainly

Steal a Brainrot's look leans heavily on lots of distinct, recognisable **character models**.
Claude builds characters out of primitive Parts, so they will read as blocky assemblies no matter
how good the lighting gets. If that specific look matters, it's a modelling job on Track B.
