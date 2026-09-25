--[[
    HEIST CREW — JewelryBuilder
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Job: DIAMOND DOLLS JEWELERS — a glam art-deco
    jewelry boutique on the south side of Ocean Drive. Rebuilt at Roblox
    scale after Malachi's playtest ("cramped", "needs to be bigger").

    FOOTPRINT (v3.1) x -82..-46, z -1..44 + the ANNEX x -46..-40, z 22..44.
    Floor top y 0.5, ceiling y 15.5, roof deck y 16.5, parapet y 18.5, deco
    tower ~28. Doorways 7-8 wide, 11 tall. The shopfront faces NORTH (z -1).

        z -1 ┌──── glass ──── FRONT DOOR (x -68..-60) ──── glass ────┐
             │ [W1]   [I1][I1]         chandelier       [I3][I3] [E1]│  yard: car
             │ [W2]   [I2][I2]    SHOWROOM (34 x 16)    [I4][I4] [E2]│  (-42.4, 13)
             │ ···· guard A lane (z 11.5) ·························· │  nose at the
             │ [ COUNTER + mirror ]                sofa  vent  plant│  gate (z 2.6)
        z 16 ├─────────────────┬── ARCHWAY ──┬───────────────────────┤
             │ LASER CORRIDOR  K  BACK HALL  D  OFFICE   watch  cabs │
             │  (2 rows)       K  guard B    D           rug         └─────┐ z 22
        z 24 ├── laser 2 ──┬───┤  (N-S)      D                  bay: desk  ← roof ladder
             │ SAFE ROOM   │   │ lockers  $  │  ────── door ───────────────┤ z 29
             │  Duchess    │   ├─ doorway ───┤  BREAK ROOM (sneakIn)       ═ STAFF DOOR
             │  cabinets   │   │ CLOSET      │  kitchenette  table         ═ (z 31.5..39.5)
             │  [ SAFE ]   │   │ breaker sink│  vending  cooler  vent      │
        z 44 └─────────────┴───┴─────────────┴─────────────────────────────┘
            x -81        -68  -67         -57                       -41 -40
        K = keycard door (slides into the wall)   D = office door
        Roof: ladder on the annex's east wall (z 25, in the yard) → roof → hatch → closet.
        Crawl vent: break room (south wall) ↔ showroom (back wall, behind the sofa).

    v3.1 ROOMY BACK (2026-09-25, first Studio playtest: cramped back rooms —
    the camera jams and the E prompts crowd):
      • the back wall moved z 35 → z 44 (the old yard back strip) and an ANNEX
        (x -46..-40, z 22..44, south of the car's tail at z 19.1) widens the
        east column. OFFICE 9 × 12 + a 6 × 6 bay (was 9 × 8) · BREAK ROOM
        15 × 13 (was 9 × 8) · CLOSET 10 × 10 (was 10 × 5) · BACK HALL 10 × 15
        (was 10 × 11) · SAFE ROOM 13 × 18 (was 13 × 9: the safe moved 9 south).
        Doorways 8 wide / 11 tall (the keycard door + laser opening keep 7).
      • E prompts >= 6 apart in the back of house: keypad · courier case ·
        breaker · stash · keycard spots (office filing cabinets, closet shelf) ·
        watch · appraisal tray · Duchess · drill. Vents (V) / hide spots (H)
        >= 4 from every E prompt. The staff door + roof ladder moved to the
        annex's east wall; the back-strip props moved into the yard.

    v2.0.2 (2026-09-25, Malachi: "shouldn't be able to walk out the heist and see
    the ugly green terrain" + "the graphics are very simple / bad"):
      • WALLED SERVICE YARD x -46..-25.1, z 2.6..44 (v3.1: the strip behind the
        store is now inside the store): 12-tall brick all round, sliding chain-link
        vehicle gate x -46..-37.4 on the north side (z 2.6), the getaway car
        parked inside at (-42.4, 0, 13) facing north. Dumpsters, crates, drums,
        puddles, a shadowed key lamp over the car.
      • Graphics: contrast lighting (tight spotlit cases + a sparkle light in
        each, sconce pools, a desk lamp as the office key light, dimmer fill),
        room finishes (marble border, damask wallpaper, green wainscot +
        wallpaper in the office, diner checker + tile splashback in the break
        room, painted skirting instead of stripy wood), printed decals take the
        room light, and Kenney props are repainted after they load.

    v3.0 "THE SCORE" (2026-09-25, docs/V3_SPEC.md §2 — lootSpots v3):
      • SHOWROOM  4 necklaces on velvet busts in the shop windows, each under a
        screwed-down glass hood (Necklace, "unscrew"). The 8 smash cases keep
        Jewels but now hold real-looking pieces: ring trays, a necklace easel,
        earring cards + a ring cone, bracelets on a T-bar.
      • THE TARGET  the PINK DIAMOND, a big round-cut stone on a marble column
        in the middle of the showroom, under the chandelier, on a brass
        TURNTABLE (attribute Spin = deg/sec, tag "Spin" — the stone + prongs +
        cushion are welded to it, so spinning the turntable spins them), inside
        its OWN laser cage (refs.laserRows[3], same shape as the other rows).
      • OFFICE  the owner's watch collection in a glass-top cabinet (Watch) +
        a jeweller's appraisal tray of loose stones on the desk (Jewels).
      • BACK HALL  a courier case of ring repairs on the stock boxes (Jewels) +
        the SECRET STASH under a loose floor tile in the closet (hidden).
      • SAFE ROOM  "the Duchess" ruby necklace on a bust facing the laser
        doorway (Necklace, "unscrew"); in the safe: loose diamonds on a velvet
        tray + ring boxes and diamond parcel papers (Diamonds ×2). The old gold,
        painting and pedestal diamond are gone.
      Pools: showroom / office / backhall / saferoom (refs.poolNames).

    Geometry + props + refs ONLY. No gameplay logic, no Scripts, no prompts —
    JobService / SecurityService / LootService / GuardService / HideService
    wire the refs. Tags set here (V2_SPEC §2): HideSpot (+Label), ShadowZone,
    Vent (+Pair).

    Vent / hatch parts: each is a BasePart whose LookVector points at the
    open floor you should step out onto (i.e. away from the wall / hatch).

    PUBLIC API:
        JewelryBuilder:build(folder) -> JobRefs   (V1_SPEC §4 + V2_SPEC §4, id = "jewelry")
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local JewelryBuilder = {}

local M = Enum.Material
local W = Constants.WORLD

-- ── layout ──────────────────────────────────────────────────────────────
local FLOOR = W.FLOOR                                                  -- 0.5
local CX, CZ = W.JEWELRY_CENTER.x, W.JEWELRY_CENTER.z                  -- -64, 17
local X0, X1 = CX - W.JEWELRY_HALF_WIDTH, CX + W.JEWELRY_HALF_WIDTH    -- -82, -46
local Z0 = CZ - W.JEWELRY_HALF_DEPTH   -- -1 (Constants' z 35 back line is the OLD back wall)
-- (v3.1 ROOMY BACK) the back of house grew: the back wall moved from z 34..35
-- to z 43..44 (the old yard back-strip wall line), and an ANNEX pushes the
-- east wall out to x -40 south of the getaway car (z 22..44). All inside
-- MiamiBuilder.KEEP_CLEAR (x -90..-40, z <= 44); the car's run to the gate
-- (x -45.1..-39.7, z <= 19.1, northward) is untouched.
local Z1 = 44
local IX0, IX1 = X0 + 1, X1 - 1        -- -81, -47 (inner faces of the side walls, north of the annex)
local IZ0, IZ1 = Z0 + 1, Z1 - 1        -- 0, 43 (inner face of the shopfront / back wall)
local ANNEX_X1 = -40                   -- annex east wall x -41..-40 (outer face)
local AIX1 = ANNEX_X1 - 1              -- -41, its inner face
local ANNEX_Z0 = 22                    -- annex north wall z 22..23 (x -46..-40)
local CEIL = FLOOR + 15                -- 15.5
local ROOF_Y = CEIL + 1                -- 16.5 (walk on the roof here)
local TOP = ROOF_Y + 2                 -- 18.5 (parapet top)
local ZF = Z0 - 0.25                   -- -1.25, front face of the shopfront
local DOOR_H = FLOOR + 11              -- 11.5, top of the interior doorways (v3.1: 11 tall)

-- showroom (z 0..16) + back-of-house (z 17..34)
local SHOW_Z1 = 16                                -- showroom back wall z 16..17
local BOH_Z0 = 17
local ENT_X0, ENT_X1 = CX - 4, CX + 4             -- front entrance x -68..-60 (8 wide)
local ENT_TOP = FLOOR + 11                        -- 11.5
local ARCH_X0, ARCH_X1 = -66, -58                 -- archway showroom → back hall (8 wide)
local ARCH_TOP = FLOOR + 11
-- back hall (interior x -67..-57), walls x -68..-67 (W) and x -57..-56 (E)
local HALL_X0, HALL_X1 = -67, -57
local HALL_Z1 = 32                                -- closet wall z 32..33 (v3.1: hall 10 x 15, was 10 x 11)
local CLOSET_Z0 = 33                              -- closet 10 x 10 (was 10 x 5)
local CLOSET_DOOR_X0, CLOSET_DOOR_X1 = -66, -58     -- 8 wide
-- keycard door: in the hall's WEST wall, z 17..24, slides south into that wall
local KC_Z0, KC_Z1 = 17, 24
-- laser corridor x -81..-68, z 17..24; wall z 24..25 (opening x -80..-73); safe room z 25..43 (13 x 18, was 13 x 9)
local LC_WALL0, LC_WALL1 = 24, 25
local SR_OPEN_X0, SR_OPEN_X1 = -80, -73
local SR_Z0 = 25
-- east column: office x -56..-47, z 17..29 + the annex bay x -47..-41, z 23..29
-- (9 x 12 + 6 x 6 = 144, was 9 x 8); wall z 29..30; break room x -56..-41,
-- z 30..43 (15 x 13, was 9 x 8)
local EC_X0 = -56
local OFFICE_DOOR_Z0, OFFICE_DOOR_Z1 = 18, 26         -- office door in the hall's east wall (8 wide)
local OB_Z0, OB_Z1 = 29, 30                           -- office | break room wall
local OB_DOOR_X0, OB_DOOR_X1 = -54, -46               -- 8 wide
local BREAK_Z0 = 30
local SIDE_Z0, SIDE_Z1 = 31.5, 39.5                   -- staff door in the annex's east wall (8 wide)
-- (v3.1) the roof ladder moved to the annex's east wall (the old spot on the
-- store's east wall, z 21.5, is now the annex's north wall)
local NOTCH_Z0, NOTCH_Z1 = 23.5, 26.5                 -- parapet notch over the roof ladder
local LADDER_Z = 25

-- ── the walled SERVICE YARD (v2.0.2) ──
-- East of the store, wrapping round behind it. The staff door opens into it;
-- the getaway car parks in it, nose at a wide vehicle gate onto Ocean Drive.
-- Brick walls on every side: from the yard you see brick, the street and sky.
local YARD_X1 = -25.1                   -- east wall outer face (safehouse skin trim starts at -25.05)
local YARD_Z0 = 2.6                     -- north wall z 2.6..3.2 (just behind the bus stop)
local YARD_Z1 = Z1                      -- south wall z 43.4..44 (flush with the store's back wall)
local YWALL_T = 0.6                     -- yard wall thickness
local YWALL_H = 12                      -- yard wall height
local GATE_X0, GATE_X1 = -46, -37.4     -- vehicle gate opening (8.6 wide, store wall to gate post)
-- getaway parking spot (car faces north, at the gate). x -42.4 keeps the car's
-- 4.7-wide run clear of the bus-stop shelter posts (x -39) on the sidewalk.
local CAR_X, CAR_Z = -42.4, 13

-- showroom cases: 4.4 long x 2.2 deep, glass top at y ~4.8
local CASE_HX, CASE_HZ = 2.2, 1.1
local LANE_A_Z = 11.5                                 -- guard A walks here, x -76 .. -51.5

-- (v3.0) the pink diamond's laser cage, centre of the showroom under the
-- chandelier. Posts at x -66.6/-61.4, z 4.0/9.2 → 2.15 studs clear of guard A's
-- lane (z 11.5), 5 studs clear of both case islands, and it starts just past
-- the swung-open glass doors (z 4.1) so the front door stays open.
local CAGE_Z = 6.6
local CAGE_H = 2.6                                    -- half-size (the cage is 5.2 x 5.2)
local CAGE_TOP = FLOOR + 7.4
local SPIN_DEG_PER_SEC = 24                           -- the turntable's Spin attribute

-- the safe (against the safe room's south wall, door facing north)
local SAFE_X = -74.5
local SAFE_Z0, SAFE_Z1 = 39.5, 42.9                   -- front face .. back (v3.1: 9 further south)
local SAFE_HW = 3                                     -- x -77.5 .. -71.5
local SAFE_Y = FLOOR + 3.6                            -- door centre height
local SAFE_TOP = FLOOR + 7
local DISC_R, DISC_T = 2.1, 0.55

-- ── palette ─────────────────────────────────────────────────────────────
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local P = Constants.MIAMI
local PINK      = UITheme.rgb(P.PASTELS[1])      -- flamingo
local LILAC     = UITheme.rgb(P.PASTELS[3])
local STUCCO    = UITheme.rgb(P.STUCCO)
local HOT_PINK  = UITheme.rgb(P.NEONS[1])
local CYAN      = UITheme.rgb(P.NEONS[2])
local MAUVE     = rgb(78, 46, 86)                -- showroom-facing partitions
local BOH       = rgb(158, 150, 160)             -- back-of-house plaster
local BOH_DARK  = rgb(96, 90, 102)
local VELVET    = rgb(112, 18, 70)
local VELVET_2  = rgb(38, 22, 70)
local MIRROR    = rgb(206, 210, 224)
local BRASS     = rgb(212, 172, 92)
local GOLD      = rgb(240, 192, 64)
local STEEL     = rgb(58, 62, 70)
local STEEL_DK  = rgb(30, 32, 38)
local STEEL_LT  = rgb(158, 164, 174)
local WALNUT    = rgb(74, 46, 32)
local WARM      = rgb(255, 222, 186)
local COOL      = rgb(214, 228, 255)
local LASER_RED = rgb(255, 40, 64)
local GEM_COLORS = { rgb(255, 92, 196), rgb(80, 232, 255), rgb(236, 244, 255) }

-- ── helpers ─────────────────────────────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

-- A box described by its min/max corners
local function box(name, x0, y0, z0, x1, y1, z1, color, material, parent, extra)
    local props = {
        Name = name,
        Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
        Position = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Color = color,
        Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

-- decoration players shouldn't snag on
local function nc(extra)
    local t = { CanCollide = false }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

-- A square-section bar from point a to point b
local function bar(name, a, b, thick, color, material, parent, extra)
    local d = b - a
    local mid = (a + b) / 2
    local cf
    if math.abs(d.Unit.Y) > 0.999 then
        cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)   -- local Z → world Y
    else
        cf = CFrame.lookAt(mid, b)
    end
    local props = { Name = name, Size = Vector3.new(thick, thick, d.Magnitude), CFrame = cf,
        Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

-- thin neon tube (accent only — art rule #1)
local function tube(name, a, b, color, parent, thick)
    return bar(name, a, b, thick or 0.16, color, M.Neon, parent,
        { CanCollide = false, CastShadow = false })
end

-- tilted gem: a small rotated cube reads as a cut stone at this scale
local function gem(parent, pos, size, color, neon)
    return part({
        Name = "Gem", Size = Vector3.new(size, size, size),
        CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(45), math.rad(35), math.rad(20)),
        Color = color, Material = neon and M.Neon or M.Glass, Reflectance = neon and 0 or 0.45,
        Transparency = neon and 0 or 0.15, CanCollide = false, CastShadow = false,
    }, parent)
end

-- ── (v3.0) jewellery kit ──
local PLATINUM = rgb(222, 226, 234)
local ROSE     = rgb(226, 160, 138)
local PEARL    = rgb(240, 234, 222)
local BLACK_VELVET = rgb(22, 18, 28)
local STONE = {
    diamond  = rgb(236, 246, 255),
    ruby     = rgb(208, 18, 56),
    sapphire = rgb(34, 80, 212),
    emerald  = rgb(16, 164, 92),
    pink     = rgb(255, 128, 198),
    amethyst = rgb(150, 70, 220),
}

-- a princess-cut stone: a squat glass block turned 45°, catches the case light
local function stone(parent, pos, size, color)
    return part({ Name = "Stone", Size = Vector3.new(size, size * 0.62, size),
        CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(45), 0),
        Color = color, Material = M.Glass, Reflectance = 0.45, Transparency = 0.08,
        CanCollide = false, CastShadow = false }, parent)
end

-- a metal bead / pearl
local function bead(parent, pos, size, color, material)
    return part({ Name = "Bead", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Position = pos,
        Color = color, Material = material or M.Metal, Reflectance = (material == nil) and 0.35 or 0.1,
        CanCollide = false, CastShadow = false }, parent)
end

-- a cylinder standing upright (Roblox cylinders run along X)
local function vcyl(name, pos, dia, h, color, material, parent, extra)
    local props = { Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, dia, dia),
        CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

-- a finger ring standing on its edge. `cf` = the ring's centre, its LookVector
-- = the way the hole faces. A velvet disc fills the hole so it reads as a ring,
-- not a coin; the setting + stone sit on top.
local function standingRing(parent, cf, dia, metal, gemColor, holeColor)
    local axis = cf * CFrame.Angles(0, math.rad(90), 0)        -- cylinder X → cf's look
    part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, dia, dia), CFrame = axis,
        Color = metal, Material = M.Metal, Reflectance = 0.4, CanCollide = false, CastShadow = false }, parent)
    part({ Name = "Hole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, dia * 0.72, dia * 0.72), CFrame = axis,
        Color = holeColor or BLACK_VELVET, Material = M.Fabric, CanCollide = false, CastShadow = false }, parent)
    local top = cf.Position + cf.UpVector * (dia / 2)
    part({ Name = "Setting", Size = Vector3.new(0.1, 0.07, 0.1), CFrame = CFrame.new(top + cf.UpVector * 0.02),
        Color = metal, Material = M.Metal, Reflectance = 0.4, CanCollide = false, CastShadow = false }, parent)
    if gemColor then stone(parent, top + cf.UpVector * 0.09, dia * 0.42, gemColor) end
end

-- a closed loop of short bars (bangles, ring bands seen side-on). `cf` =
-- centre, the loop lies in cf's Right/Up plane.
local function hoop(parent, cf, radius, n, thick, color)
    local pts = {}
    for i = 0, n do
        local a = (i / n) * math.pi * 2
        table.insert(pts, cf.Position + cf.RightVector * (radius * math.cos(a)) + cf.UpVector * (radius * math.sin(a)))
    end
    for i = 1, n do
        local a, b = pts[i], pts[i + 1]
        local mid = (a + b) / 2
        part({ Name = "Link", Size = Vector3.new(thick, thick, (b - a).Magnitude + thick * 0.6),
            CFrame = CFrame.lookAt(mid, b), Color = color, Material = M.Metal, Reflectance = 0.4,
            CanCollide = false, CastShadow = false }, parent)
    end
    return pts
end

-- weld an UNanchored decoration to an anchored part, so it follows when a
-- service moves that part by CFrame (camera heads, the sliding door)
local function weldTo(anchor, p)
    p.Anchored = false
    p.Massless = true
    p.CanCollide = false
    local w = Instance.new("WeldConstraint")
    w.Part0 = anchor
    w.Part1 = p
    w.Parent = p
end

local function surface(p, face, pps, bright)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 50
    g.LightInfluence = 0
    g.Brightness = bright or 1.2
    g.Parent = p
    return g
end

-- (v2.0.2) painted / printed things (posters, panels, lockers, wallpaper) take
-- the room's light instead of glowing flat. Screens + neon signs stay unlit.
local function lit(g)
    g.LightInfluence = 1
    g.Brightness = 1
    return g
end

local function frame(props, parent)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props) do f[k] = v end
    f.Parent = parent
    return f
end

local function text(props, parent)
    local l = UITheme.label(props)
    l.Parent = parent
    return l
end

-- one line of text filling a part's face
local function printOn(p, face, str, color, font, pps, bright)
    local g = surface(p, face, pps or 50, bright or 1.1)
    return text({ Text = str, Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = font or UITheme.F.display,
        TextColor3 = color }, g)
end

local function spot(parent, face, color, brightness, range, angle, shadows)
    local s = Instance.new("SpotLight")
    s.Face = face
    s.Color = color
    s.Brightness = brightness
    s.Range = range
    s.Angle = angle
    s.Shadows = shadows == true
    s.Parent = parent
    return s
end

local function point(parent, color, brightness, range, shadows)
    local l = Instance.new("PointLight")
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Shadows = shadows == true
    l.Parent = parent
    return l
end

-- invisible anchor for a light that should sit in mid-air
local function lightAnchor(name, pos, parent)
    return part({ Name = name, Size = Vector3.new(0.2, 0.2, 0.2), Position = pos, Transparency = 1,
        CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
        Material = M.Metal }, parent)
end

-- ceiling can light: small black can + warm lens + a tight spotlight straight down
local function canLight(parent, x, z, color, brightness, angle, shadows)
    local can = box("CanLight", x - 0.45, CEIL - 0.3, z - 0.45, x + 0.45, CEIL, z + 0.45, STEEL_DK, M.Metal, parent, nc())
    box("CanLens", x - 0.3, CEIL - 0.34, z - 0.3, x + 0.3, CEIL - 0.3, z + 0.3, color or WARM, M.Neon, parent,
        nc({ CastShadow = false }))
    spot(can, Enum.NormalId.Bottom, color or WARM, brightness or 3, 19, angle or 44, shadows)
    return can
end

-- fluorescent tube fixture (back-of-house)
local function tubeLight(parent, x, z, alongX, brightness, range, color)
    local hx, hz = alongX and 1.8 or 0.35, alongX and 0.35 or 1.8
    local fx = box("TubeFixture", x - hx, CEIL - 0.25, z - hz, x + hx, CEIL, z + hz, STEEL_LT, M.Metal, parent, nc())
    box("TubeLens", x - hx + 0.15, CEIL - 0.3, z - hz + 0.1, x + hx - 0.15, CEIL - 0.25, z + hz - 0.1,
        color or COOL, M.Neon, parent, nc({ CastShadow = false }))
    point(fx, color or COOL, brightness or 0.9, range or 14, false)
    return fx
end

local function tag(p, tagName, attrs)
    CollectionService:AddTag(p, tagName)
    for k, v in pairs(attrs or {}) do p:SetAttribute(k, v) end
    return p
end

-- invisible dark area (V2_SPEC §2). Anything standing in the box is "in shadow".
local function shadowZone(name, x0, z0, x1, z1, parent)
    local p = box(name, x0, FLOOR, z0, x1, FLOOR + 9, z1, rgb(0, 0, 0), M.Concrete, parent, {
        Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
    return tag(p, "ShadowZone")
end

-- wall along Z (x from xa to xb) with doorway gaps { {z0, z1, topY}, ... } (sorted)
local function wallZ(name, xa, xb, z0, z1, gaps, color, material, parent, y1)
    y1 = y1 or CEIL
    local cur = z0
    for _, g in ipairs(gaps or {}) do
        if g[1] > cur then box(name, xa, FLOOR, cur, xb, y1, g[1], color, material, parent) end
        box(name .. "Header", xa, g[3], g[1], xb, y1, g[2], color, material, parent)
        cur = g[2]
    end
    if cur < z1 then box(name, xa, FLOOR, cur, xb, y1, z1, color, material, parent) end
end

-- wall along X (z from za to zb) with doorway gaps { {x0, x1, topY}, ... } (sorted)
local function wallX(name, za, zb, x0, x1, gaps, color, material, parent, y1)
    y1 = y1 or CEIL
    local cur = x0
    for _, g in ipairs(gaps or {}) do
        if g[1] > cur then box(name, cur, FLOOR, za, g[1], y1, zb, color, material, parent) end
        box(name .. "Header", g[1], g[3], za, g[2], y1, zb, color, material, parent)
        cur = g[2]
    end
    if cur < x1 then box(name, cur, FLOOR, za, x1, y1, zb, color, material, parent) end
end

-- a part whose LookVector points along `out` (vents / hatches: out = the side you step onto)
local function facingPart(name, centre, size, out, color, material, parent, extra)
    local props = { Name = name, Size = size, CFrame = CFrame.lookAt(centre, centre + out),
        Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

-- (v2.0.2) vertical-stripe wallpaper printed on one face of a thin panel
local function wallpaper(p, face, base, stripe, n)
    local g = lit(surface(p, face, 8, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = base }, g)
    for k = 0, n - 1 do
        frame({ Size = UDim2.fromScale(0.28 / n, 1), Position = UDim2.fromScale((k + 0.36) / n, 0),
            BackgroundColor3 = stripe, BackgroundTransparency = 0.25 }, g)
    end
    return g
end

-- (v2.0.2) Kenney furniture arrives as plain white / grey meshes (the importer
-- drops the kit's colours). After a prop is placed, repaint it: the biggest
-- part gets `main`, the rest get `accent`; `byName` (lower-case substring of the
-- MeshPart name → spec) wins when the kit's part names are descriptive.
-- A spec is { Color3, Material, reflectance? }. Textured meshes are left alone.
local function paintModel(model, paint)
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end
    table.sort(parts, function(a, b)
        return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
    end)
    for i, p in ipairs(parts) do
        local spec
        if paint.byName then
            local n = string.lower(p.Name)
            for pat, s in pairs(paint.byName) do
                if string.find(n, pat, 1, true) then
                    spec = s
                    break
                end
            end
        end
        spec = spec or ((i == 1 or not paint.accent) and paint.main or paint.accent)
        local textured = p:IsA("MeshPart") and p.TextureID ~= ""
        if spec and not textured then
            p.Color = spec[1]
            p.Material = spec[2]
            p.Reflectance = spec[3] or 0
        end
    end
end

-- place one Kenney prop (async, never errors) and repaint it
local function prop(kit, name, pos, facing, parent, paint, opts)
    task.spawn(function()
        local o = { parent = parent }
        for k, v in pairs(opts or {}) do o[k] = v end
        local ok, model = pcall(KenneyLoader.place, kit, name, pos, facing, o)
        if ok and model and paint then pcall(paintModel, model, paint) end
    end)
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: floors, walls, ceiling, roof
-- ──────────────────────────────────────────────
function JewelryBuilder:_shell(f)
    -- floors (one finish per room)
    box("FloorShowroom", X0, 0, Z0, X1, FLOOR, 16.5, rgb(34, 26, 40), M.Marble, f, { Reflectance = 0.08 })
    box("FloorSecure", X0, 0, 16.5, -67.5, FLOOR, Z1, rgb(76, 79, 86), M.DiamondPlate, f)
    box("FloorHall", -67.5, 0, 16.5, -56.5, FLOOR, Z1, rgb(132, 128, 124), M.Slate, f)
    box("FloorOffice", -56.5, 0, 16.5, X1, FLOOR, OB_Z0 + 0.5, rgb(78, 44, 66), M.Carpet, f)
    box("FloorOffice", X1, 0, ANNEX_Z0, ANNEX_X1, FLOOR, OB_Z0 + 0.5, rgb(78, 44, 66), M.Carpet, f)
    local fb = box("FloorBreak", -56.5, 0, OB_Z0 + 0.5, ANNEX_X1, FLOOR, Z1, rgb(200, 226, 216), M.CeramicTiles, f)
    -- (v2.0.2) diner checker on the break-room floor (2-stud tiles, lit by the room)
    local cg = lit(surface(fb, Enum.NormalId.Top, 6, 1))
    local nx, nz = 8, 7
    for i = 0, nx - 1 do
        for j = 0, nz - 1 do
            if (i + j) % 2 == 0 then
                frame({ Size = UDim2.fromScale(1 / nx, 1 / nz), Position = UDim2.fromScale(i / nx, j / nz),
                    BackgroundColor3 = rgb(40, 70, 72) }, cg)
            end
        end
    end
    -- step between the sidewalk (ends z -1.4) and the shopfront
    box("Threshold", X0, 0, Z0 - 0.4, X1, FLOOR, Z0, rgb(214, 206, 198), M.Concrete, f)

    -- exterior walls (the front is the facade, built in _facade). (v3.1) the
    -- back wall moved to z 43..44; the ANNEX (x -46..-40, z 22..44) replaces the
    -- store's east wall south of z 23, with the roof-ladder notch + staff door
    -- in its east wall.
    box("WallWest", X0, FLOOR, Z0, IX0, TOP, Z1, LILAC, M.Plaster, f)
    box("WallSouth", IX0, FLOOR, IZ1, AIX1, TOP, Z1, LILAC, M.Plaster, f)
    box("WallEast", IX1, FLOOR, Z0, X1, TOP, ANNEX_Z0 + 1, LILAC, M.Plaster, f)
    box("AnnexWallN", X1, FLOOR, ANNEX_Z0, ANNEX_X1, TOP, ANNEX_Z0 + 1, LILAC, M.Plaster, f)
    box("AnnexWallE", AIX1, FLOOR, ANNEX_Z0, ANNEX_X1, TOP, NOTCH_Z0, LILAC, M.Plaster, f)
    box("AnnexWallENotch", AIX1, FLOOR, NOTCH_Z0, ANNEX_X1, ROOF_Y, NOTCH_Z1, LILAC, M.Plaster, f)
    box("AnnexWallE", AIX1, FLOOR, NOTCH_Z1, ANNEX_X1, TOP, SIDE_Z0, LILAC, M.Plaster, f)
    box("StaffDoorHeader", AIX1, DOOR_H, SIDE_Z0, ANNEX_X1, TOP, SIDE_Z1, LILAC, M.Plaster, f)
    box("AnnexWallE", AIX1, FLOOR, SIDE_Z1, ANNEX_X1, TOP, Z1, LILAC, M.Plaster, f)
    -- coping caps on the parapet
    box("CopingW", X0 - 0.15, TOP, Z0 - 0.45, IX0 + 0.05, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingE", IX1 - 0.05, TOP, Z0 - 0.45, X1 + 0.15, TOP + 0.3, ANNEX_Z0 - 0.15, STUCCO, M.Plaster, f)
    box("CopingN", IX1 - 0.05, TOP, ANNEX_Z0 - 0.15, ANNEX_X1 + 0.15, TOP + 0.3, ANNEX_Z0 + 1.05, STUCCO, M.Plaster, f)
    box("CopingE", AIX1 - 0.05, TOP, ANNEX_Z0 + 1.05, ANNEX_X1 + 0.15, TOP + 0.3, NOTCH_Z0, STUCCO, M.Plaster, f)
    box("CopingE", AIX1 - 0.05, TOP, NOTCH_Z1, ANNEX_X1 + 0.15, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingS", IX0, TOP, IZ1 - 0.05, AIX1, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    -- a downpipe + pilasters down the yard side (moved off the gate post in v2.0.2)
    box("Downpipe", X1, FLOOR, 5.2, X1 + 0.35, TOP, 5.55, STEEL_LT, M.Metal, f)
    for _, pz in ipairs({ 4, 18 }) do
        box("PilasterE", X1, FLOOR, pz - 0.6, X1 + 0.25, TOP - 0.4, pz + 0.6, PINK, M.Plaster, f, nc())
    end

    -- ceiling (dark plum, seen from inside) + roof deck (walk on it)
    box("Ceiling", IX0, CEIL, IZ0, IX1, CEIL + 0.5, IZ1, rgb(50, 30, 58), M.Plaster, f)
    box("Ceiling", IX1, CEIL, ANNEX_Z0 + 1, AIX1, CEIL + 0.5, IZ1, rgb(50, 30, 58), M.Plaster, f)
    box("Roof", IX0, CEIL + 0.5, IZ0, IX1, ROOF_Y, IZ1, rgb(160, 158, 164), M.Concrete, f)
    box("Roof", IX1, CEIL + 0.5, ANNEX_Z0 + 1, AIX1, ROOF_Y, IZ1, rgb(160, 158, 164), M.Concrete, f)
    -- the notch: the roof deck runs out over the annex wall so you can step onto it
    box("RoofLip", AIX1, ROOF_Y - 0.5, NOTCH_Z0, ANNEX_X1, ROOF_Y, NOTCH_Z1, rgb(160, 158, 164), M.Concrete, f)
    box("RoofAC1", -76, ROOF_Y, 8, -72.5, ROOF_Y + 2.4, 11.5, STEEL_LT, M.Metal, f)
    box("RoofACFan", -75.3, ROOF_Y + 2.4, 8.7, -73.2, ROOF_Y + 2.5, 10.8, STEEL_DK, M.Metal, f, nc())
    box("RoofAC2", -55, ROOF_Y, 20, -51.5, ROOF_Y + 2.2, 23.5, STEEL_LT, M.Metal, f)
    box("RoofACFan", -54.3, ROOF_Y + 2.2, 20.7, -52.2, ROOF_Y + 2.3, 22.8, STEEL_DK, M.Metal, f, nc())
    for _, vx in ipairs({ -79, -60 }) do
        part({ Name = "VentStack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.8, 0.8),
            CFrame = CFrame.new(vx, ROOF_Y + 0.8, 3) * CFrame.Angles(0, 0, math.rad(90)),
            Color = STEEL_LT, Material = M.Metal }, f)
    end

    -- ── interior walls (to the ceiling) ──
    -- showroom back wall z 16..17 with the 8-wide archway into the back hall
    wallX("ShowroomBackWall", SHOW_Z1, BOH_Z0, IX0, IX1, { { ARCH_X0, ARCH_X1, ARCH_TOP } }, MAUVE, M.Plaster, f)
    -- hall west wall (x -68..-67): the keycard door opening z 17..24 (pane slides into z 24..31)
    wallZ("HallWallW", -68, -67, BOH_Z0, IZ1, { { KC_Z0, KC_Z1, DOOR_H } }, BOH, M.Plaster, f)
    -- hall east wall (x -57..-56): office door
    wallZ("HallWallE", -57, -56, BOH_Z0, IZ1, { { OFFICE_DOOR_Z0, OFFICE_DOOR_Z1, DOOR_H } }, BOH, M.Plaster, f)
    -- closet wall across the hall's south end
    wallX("ClosetWall", HALL_Z1, CLOSET_Z0, HALL_X0, HALL_X1, { { CLOSET_DOOR_X0, CLOSET_DOOR_X1, DOOR_H } },
        BOH, M.Plaster, f)
    -- laser corridor | safe room, with the 7-wide opening (laser row 2 sits in it)
    wallX("SafeRoomWall", LC_WALL0, LC_WALL1, IX0, -68, { { SR_OPEN_X0, SR_OPEN_X1, DOOR_H } }, STEEL, M.Metal, f)
    -- office | break room (runs out to the annex's east wall)
    wallX("BreakRoomWall", OB_Z0, OB_Z1, EC_X0, AIX1, { { OB_DOOR_X0, OB_DOOR_X1, DOOR_H } }, BOH, M.Plaster, f)
end

-- ──────────────────────────────────────────────
-- 💎 FACADE: glass shopfront, glass doors, awning, neon sign, deco tower
-- ──────────────────────────────────────────────
function JewelryBuilder:_facade(f)
    local fa = Instance.new("Folder")
    fa.Name = "Facade"
    fa.Parent = f
    local WIN_TOP = 13.2

    -- piers: corner piers stand proud of the fascia, door piers frame the entrance
    box("PierW", X0, FLOOR, ZF - 0.2, X0 + 1.5, TOP, IZ0, PINK, M.Plaster, fa)
    box("PierE", X1 - 1.5, FLOOR, ZF - 0.2, X1, TOP, IZ0, PINK, M.Plaster, fa)
    box("DoorPierW", ENT_X0 - 0.8, FLOOR, ZF, ENT_X0, WIN_TOP, IZ0, PINK, M.Plaster, fa)
    box("DoorPierE", ENT_X1, FLOOR, ZF, ENT_X1 + 0.8, WIN_TOP, IZ0, PINK, M.Plaster, fa)
    for _, rx in ipairs({ X0 + 0.35, X0 + 0.95, X1 - 0.95, X1 - 0.35 }) do
        box("PierRib", rx - 0.12, FLOOR + 0.6, ZF - 0.4, rx + 0.12, TOP - 0.4, ZF - 0.2, STUCCO, M.Plaster, fa, nc())
    end

    -- shop windows: floor-to-ceiling glass on a marble sill, brass mullions + transom
    local glassTint = rgb(168, 196, 232)
    for _, bay in ipairs({ { X0 + 1.5, ENT_X0 - 0.8 }, { ENT_X1 + 0.8, X1 - 1.5 } }) do
        local b0, b1 = bay[1], bay[2]
        box("Sill", b0, FLOOR, ZF + 0.15, b1, FLOOR + 0.6, IZ0, rgb(236, 226, 230), M.Marble, fa)
        box("ShopWindow", b0, FLOOR + 0.6, -0.7, b1, WIN_TOP, -0.4, glassTint, M.Glass, fa,
            { Transparency = 0.55, Reflectance = 0.25 })
        for k = 1, 2 do
            local mx = b0 + (b1 - b0) * k / 3
            box("Mullion", mx - 0.08, FLOOR + 0.6, -0.8, mx + 0.08, WIN_TOP, -0.3, BRASS, M.Metal, fa)
        end
        box("Transom", b0, 10.4, -0.8, b1, 10.6, -0.3, BRASS, M.Metal, fa)
        box("WindowHead", b0, WIN_TOP - 0.2, -0.8, b1, WIN_TOP, -0.3, BRASS, M.Metal, fa)
        -- window display plinths just inside the glass. (v3.0) The necklace
        -- busts + glass hoods on top are loot, built in _windowNecklaces.
        for k = 1, 2 do
            local px = b0 + (b1 - b0) * (k == 1 and 0.28 or 0.72)
            box("WindowPlinth", px - 0.9, FLOOR, 0.3, px + 0.9, FLOOR + 2.4, 1.5, rgb(236, 226, 230), M.Marble, fa)
            box("PlinthCap", px - 1.0, FLOOR + 2.4, 0.2, px + 1.0, FLOOR + 2.55, 1.6, BRASS, M.Metal, fa)
            spot(lightAnchor("PlinthLight", Vector3.new(px, WIN_TOP - 0.5, 0.9), fa), Enum.NormalId.Bottom,
                WARM, 1.6, 14, 30)
        end
    end

    -- entrance: open 8-wide doorway, brass frame, glass double doors swung inward
    box("DoorFrameW", ENT_X0 - 0.3, FLOOR, ZF - 0.15, ENT_X0, ENT_TOP + 0.25, ZF, BRASS, M.Metal, fa, nc())
    box("DoorFrameE", ENT_X1, FLOOR, ZF - 0.15, ENT_X1 + 0.3, ENT_TOP + 0.25, ZF, BRASS, M.Metal, fa, nc())
    box("DoorFrameTop", ENT_X0 - 0.3, ENT_TOP, ZF - 0.15, ENT_X1 + 0.3, ENT_TOP + 0.25, ZF, BRASS, M.Metal, fa, nc())
    for _, side in ipairs({ -1, 1 }) do
        local hx = side < 0 and ENT_X0 + 0.15 or ENT_X1 - 0.15
        box("GlassDoor", hx - 0.1, FLOOR + 0.1, 0.1, hx + 0.1, ENT_TOP - 0.3, 4.1, rgb(180, 214, 236), M.Glass, fa,
            nc({ Transparency = 0.5, Reflectance = 0.25 }))
        box("GlassDoorRail", hx - 0.14, FLOOR + 0.1, 0.1, hx + 0.14, FLOOR + 0.6, 4.1, BRASS, M.Metal, fa, nc())
        box("GlassDoorRail", hx - 0.14, ENT_TOP - 0.8, 0.1, hx + 0.14, ENT_TOP - 0.3, 4.1, BRASS, M.Metal, fa, nc())
        bar("DoorPull", Vector3.new(hx - side * 0.25, FLOOR + 3.4, 3.6), Vector3.new(hx - side * 0.25, FLOOR + 6.4, 3.6),
            0.12, BRASS, M.Metal, fa, nc())
    end
    local header = box("DoorHeader", ENT_X0, ENT_TOP, ZF, ENT_X1, WIN_TOP, IZ0, PINK, M.Plaster, fa)
    printOn(header, Enum.NormalId.Front, "FINE JEWELRY  ·  EST. 1986", rgb(120, 70, 20), UITheme.F.display, 40, 1.1)

    -- fascia band over the windows, with deco speed-lines either side of the sign
    box("Fascia", X0 + 1.5, WIN_TOP, ZF, X1 - 1.5, TOP, IZ0, LILAC, M.Plaster, fa)
    for _, ly in ipairs({ 15.6, 16.1, 16.6 }) do
        box("SpeedLine", X0 + 1.5, ly - 0.06, ZF - 0.12, CX - 9, ly + 0.06, ZF, STUCCO, M.Plaster, fa)
        box("SpeedLine", CX + 9, ly - 0.06, ZF - 0.12, X1 - 1.5, ly + 0.06, ZF, STUCCO, M.Plaster, fa)
    end

    -- stepped deco tower (ziggurat) + spire
    box("TierA", CX - 10, TOP, ZF, CX + 10, 23, IZ0, LILAC, M.Plaster, fa)
    box("TierB", CX - 6.5, 23, ZF, CX + 6.5, 25.5, IZ0, PINK, M.Plaster, fa)
    box("Spire", CX - 1, 25.5, ZF + 0.25, CX + 1, 28, IZ0 - 0.2, STUCCO, M.Plaster, fa)
    local tip = part({ Name = "SpireTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8),
        Position = Vector3.new(CX, 28.4, ZF + 0.65), Color = CYAN, Material = M.Neon, CanCollide = false }, fa)
    point(tip, CYAN, 1.5, 12)
    for _, fx in ipairs({ CX - 8.6, CX - 7.8, CX + 7.8, CX + 8.6 }) do
        box("DecoFin", fx - 0.15, 14, ZF - 0.35, fx + 0.15, 23, ZF, STUCCO, M.Plaster, fa, nc())
    end

    -- ── the sign: DIAMOND DOLLS, hot-pink script + cyan diamond ──
    local sx0, sx1, sy0, sy1 = CX - 7, CX + 7, 16.9, 22.5
    local board = box("SignBoard", sx0, sy0, ZF - 0.25, sx1, sy1, ZF, rgb(24, 12, 32), M.Metal, fa)
    local sg = surface(board, Enum.NormalId.Front, 40, 2.4)
    local icon = frame({ Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(34, 50), Rotation = 45,
        BackgroundTransparency = 1 }, sg)
    local st = Instance.new("UIStroke")
    st.Color = CYAN
    st.Thickness = 6
    st.Parent = icon
    frame({ Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(60, 76), Rotation = 45,
        BackgroundColor3 = rgb(170, 245, 255) }, sg)
    local name = text({ Text = "Diamond Dolls", Size = UDim2.fromScale(0.76, 0.66), Position = UDim2.fromScale(0.22, 0.02),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = rgb(255, 150, 214) }, sg)
    local glow = Instance.new("UIStroke")
    glow.Color = HOT_PINK
    glow.Thickness = 3
    glow.Transparency = 0.15
    glow.Parent = name
    text({ Text = "J E W E L E R S", Size = UDim2.fromScale(0.6, 0.2), Position = UDim2.fromScale(0.3, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = CYAN }, sg)
    local oz = ZF - 0.33
    tube("SignTube", Vector3.new(sx0, sy1, oz), Vector3.new(sx1, sy1, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx1, sy0, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx0, sy1, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx1, sy0, oz), Vector3.new(sx1, sy1, oz), CYAN, fa)
    point(lightAnchor("SignGlowW", Vector3.new(CX - 4, 19.7, ZF - 1.8), fa), HOT_PINK, 3, 18)
    point(lightAnchor("SignGlowE", Vector3.new(CX + 4, 19.7, ZF - 1.8), fa), HOT_PINK, 3, 18)

    -- ── neon roofline (hot pink, thin) ──
    local rz = ZF - 0.45
    local tz = ZF - 0.1
    tube("Roofline", Vector3.new(X0, TOP - 0.3, rz), Vector3.new(CX - 10, TOP - 0.3, rz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(CX + 10, TOP - 0.3, rz), Vector3.new(X1, TOP - 0.3, rz), HOT_PINK, fa)
    local steps = { { CX - 10, TOP }, { CX - 10, 23 }, { CX - 6.5, 23 }, { CX - 6.5, 25.5 },
        { CX + 6.5, 25.5 }, { CX + 6.5, 23 }, { CX + 10, 23 }, { CX + 10, TOP } }
    for k = 1, #steps - 1 do
        tube("Roofline", Vector3.new(steps[k][1], steps[k][2], tz), Vector3.new(steps[k + 1][1], steps[k + 1][2], tz),
            HOT_PINK, fa)
    end
    tube("SpireTube", Vector3.new(CX, 25.6, ZF + 0.15), Vector3.new(CX, 27.9, ZF + 0.15), HOT_PINK, fa, 0.14)
    tube("Roofline", Vector3.new(X0 - 0.1, TOP - 0.3, Z0), Vector3.new(X0 - 0.1, TOP - 0.3, Z1), HOT_PINK, fa)
    -- (v3.1) east side: along the store wall to the annex, round the annex's north face, down its east face
    tube("Roofline", Vector3.new(X1 + 0.1, TOP - 0.3, Z0), Vector3.new(X1 + 0.1, TOP - 0.3, ANNEX_Z0 - 0.1), HOT_PINK, fa)
    tube("Roofline", Vector3.new(X1 + 0.1, TOP - 0.3, ANNEX_Z0 - 0.1), Vector3.new(ANNEX_X1 + 0.1, TOP - 0.3, ANNEX_Z0 - 0.1), HOT_PINK, fa)
    tube("Roofline", Vector3.new(ANNEX_X1 + 0.1, TOP - 0.3, ANNEX_Z0 - 0.1), Vector3.new(ANNEX_X1 + 0.1, TOP - 0.3, NOTCH_Z0), HOT_PINK, fa)
    tube("Roofline", Vector3.new(ANNEX_X1 + 0.1, TOP - 0.3, NOTCH_Z1), Vector3.new(ANNEX_X1 + 0.1, TOP - 0.3, Z1), HOT_PINK, fa)

    -- ── striped awning over the entrance only ──
    -- (x -71..-57: clear of the palm at x -74 and the streetlight pole at x -56;
    -- front edge y 12.35 stays above the streetlight arm, y 11.6-11.9)
    local ax0, ax1, n = CX - 7, CX + 7, 7
    local w = (ax1 - ax0) / n
    local back = Vector3.new(0, WIN_TOP + 0.1, ZF)
    local front = Vector3.new(0, 12.35, -3.25)
    local dir = front - back
    for i = 1, n do
        local x = ax0 + (i - 0.5) * w
        local col = (i % 2 == 1) and rgb(214, 36, 120) or rgb(250, 196, 220)
        local mid = Vector3.new(x, (back.Y + front.Y) / 2, (back.Z + front.Z) / 2)
        part({ Name = "AwningStripe", Size = Vector3.new(w, 0.14, dir.Magnitude), CFrame = CFrame.lookAt(mid, mid + dir),
            Color = col, Material = M.Fabric, CanCollide = false }, fa)
        box("AwningValance", x - w / 2, 12.0, front.Z - 0.07, x + w / 2, 12.4, front.Z + 0.05, col, M.Fabric, fa, nc())
    end
    bar("AwningRod", Vector3.new(ax0, 12.4, front.Z), Vector3.new(ax1, 12.4, front.Z), 0.1, BRASS, M.Metal, fa, nc())

    -- warm downlight over the door, cyan uplights washing the door piers
    local lamp = box("DoorLamp", CX - 0.4, ENT_TOP + 0.05, ZF - 0.35, CX + 0.4, ENT_TOP + 0.35, ZF, BRASS, M.Metal, fa, nc())
    box("DoorLampLens", CX - 0.3, ENT_TOP, ZF - 0.3, CX + 0.3, ENT_TOP + 0.05, ZF - 0.05, WARM, M.Neon, fa, nc())
    spot(lamp, Enum.NormalId.Bottom, rgb(255, 204, 170), 1.6, 14, 110, true)
    for _, ux in ipairs({ ENT_X0 - 0.4, ENT_X1 + 0.4 }) do
        local up = box("Uplight", ux - 0.3, FLOOR, ZF - 0.15, ux + 0.3, FLOOR + 0.25, ZF, STEEL_DK, M.Metal, fa, nc())
        spot(up, Enum.NormalId.Top, CYAN, 1.6, 15, 28)
    end

    -- ── OPEN / CLOSED sign hanging in the east window ──
    local ox0, ox1, oy0, oy1 = -54.4, -51.6, 7.6, 8.9
    local oz0, oz1 = -0.34, -0.2
    local osign = box("OpenSign", ox0, oy0, oz0, ox1, oy1, oz1, rgb(16, 12, 22), M.Metal, fa, nc())
    local og = surface(osign, Enum.NormalId.Front, 60, 2)
    local olabel = text({ Text = "CLOSED", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display }, og)
    local ostroke = Instance.new("UIStroke")
    ostroke.Thickness = 2
    ostroke.Transparency = 0.2
    ostroke.Parent = olabel
    local oTubes = {
        box("OpenTube", ox0 - 0.14, oy1, oz0, ox1 + 0.14, oy1 + 0.14, oz1, CYAN, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.14, oy0 - 0.14, oz0, ox1 + 0.14, oy0, oz1, CYAN, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.14, oy0, oz0, ox0, oy1, oz1, CYAN, M.Neon, fa, nc()),
        box("OpenTube", ox1, oy0, oz0, ox1 + 0.14, oy1, oz1, CYAN, M.Neon, fa, nc()),
    }
    for _, cx in ipairs({ ox0 + 0.3, ox1 - 0.3 }) do
        box("OpenChain", cx - 0.03, oy1 + 0.14, -0.3, cx + 0.03, 10.4, -0.24, BRASS, M.Metal, fa, nc())
    end
    local oglow = point(osign, HOT_PINK, 1.4, 9)

    local function openSign(open)
        olabel.Text = open and "OPEN" or "CLOSED"
        olabel.TextColor3 = open and rgb(255, 120, 205) or rgb(150, 44, 56)
        ostroke.Color = open and HOT_PINK or rgb(70, 16, 26)
        for _, t in ipairs(oTubes) do
            t.Material = open and M.Neon or M.Metal
            t.Color = open and CYAN or rgb(40, 58, 68)
        end
        oglow.Enabled = open
    end
    openSign(false)
    return openSign
end

-- ──────────────────────────────────────────────
-- ✨ SHOWROOM: walls, chandelier, counter, lounge, 8 display cases
-- ──────────────────────────────────────────────
function JewelryBuilder:_walls(f)
    -- velvet + mirror panels down both side walls, brass rails top and bottom
    for _, side in ipairs({ -1, 1 }) do
        local xw = side < 0 and IX0 or IX1
        local xa, xb = xw - side * 0.05, xw - side * 0.17
        local z = 0.4
        local k = 0
        while z < 15.4 do
            k = k + 1
            local wd = math.min(2.6, 15.6 - z)
            if k % 2 == 1 then
                box("VelvetPanel", xa, FLOOR + 0.7, z, xb, FLOOR + 11, z + wd, VELVET, M.Fabric, f)
            else
                box("MirrorPanel", xa, FLOOR + 0.7, z, xb, FLOOR + 11, z + wd, MIRROR, M.Glass, f, { Reflectance = 0.6 })
            end
            z = z + wd
            box("PanelFrame", xa, FLOOR + 0.7, z, xw - side * 0.22, FLOOR + 11, z + 0.2, BRASS, M.Metal, f)
            z = z + 0.2
        end
        box("PanelRailTop", xa, FLOOR + 11, 0.4, xw - side * 0.22, FLOOR + 11.2, z, BRASS, M.Metal, f)
        box("PanelRailLow", xa, FLOOR + 0.5, 0.4, xw - side * 0.22, FLOOR + 0.7, z, BRASS, M.Metal, f)
        -- thin pink kick-strip (glow only — no light, so the floor stays dark between pools)
        box("BaseNeon", xw - side * 0.17, FLOOR, 0.3, xw - side * 0.29, FLOOR + 0.12, 15.7, HOT_PINK,
            M.Neon, f, nc({ CastShadow = false }))

        -- (v2.0.2) brass wall sconces between the wall cases: small warm pools up the walls
        for _, sz in ipairs({ 7.1, 13.2 }) do
            local sx = xw - side * 0.22
            local plate = box("SconcePlate", sx, FLOOR + 7.6, sz - 0.35, sx - side * 0.12, FLOOR + 9.4, sz + 0.35,
                BRASS, M.Metal, f, nc())
            box("SconceShade", sx - side * 0.12, FLOOR + 8.1, sz - 0.3, sx - side * 0.62, FLOOR + 8.9, sz + 0.3,
                rgb(255, 226, 190), M.Glass, f, nc({ Transparency = 0.2, CastShadow = false }))
            point(plate, rgb(255, 196, 150), 0.8, 9, false)
        end
    end

    -- (v2.0.2) light marble border + brass inlay round the showroom floor
    local BORDER = rgb(214, 200, 212)
    local fz1 = SHOW_Z1 - 0.1
    box("FloorBorder", IX0, FLOOR, IZ0, IX1, FLOOR + 0.02, IZ0 + 1.2, BORDER, M.Marble, f, nc({ Reflectance = 0.1 }))
    box("FloorBorder", IX0, FLOOR, fz1 - 1.2, IX1, FLOOR + 0.02, fz1, BORDER, M.Marble, f, nc({ Reflectance = 0.1 }))
    box("FloorBorder", IX0, FLOOR, IZ0 + 1.2, IX0 + 1.2, FLOOR + 0.02, fz1 - 1.2, BORDER, M.Marble, f, nc({ Reflectance = 0.1 }))
    box("FloorBorder", IX1 - 1.2, FLOOR, IZ0 + 1.2, IX1, FLOOR + 0.02, fz1 - 1.2, BORDER, M.Marble, f, nc({ Reflectance = 0.1 }))
    box("FloorInlay", IX0 + 1.2, FLOOR, IZ0 + 1.2, IX1 - 1.2, FLOOR + 0.03, IZ0 + 1.35, BRASS, M.Metal, f, nc())
    box("FloorInlay", IX0 + 1.2, FLOOR, fz1 - 1.35, IX1 - 1.2, FLOOR + 0.03, fz1 - 1.2, BRASS, M.Metal, f, nc())
    box("FloorInlay", IX0 + 1.2, FLOOR, IZ0 + 1.35, IX0 + 1.35, FLOOR + 0.03, fz1 - 1.35, BRASS, M.Metal, f, nc())
    box("FloorInlay", IX1 - 1.35, FLOOR, IZ0 + 1.35, IX1 - 1.2, FLOOR + 0.03, fz1 - 1.35, BRASS, M.Metal, f, nc())

    -- (v2.0.2) the back wall: black-marble skirting, damask wallpaper, brass rail
    -- (the counter mirror sits in front of the west half, the lounge the east half)
    for _, seg in ipairs({ { IX0, ARCH_X0 - 0.3 }, { ARCH_X1 + 0.3, IX1 } }) do
        box("Skirting", seg[1], FLOOR, SHOW_Z1 - 0.1, seg[2], FLOOR + 0.7, SHOW_Z1, rgb(20, 16, 24), M.Marble, f, nc())
        local wp = box("Wallpaper", seg[1], FLOOR + 0.7, SHOW_Z1 - 0.05, seg[2], FLOOR + 11, SHOW_Z1, rgb(60, 32, 70), M.Fabric, f, nc())
        wallpaper(wp, Enum.NormalId.Front, rgb(58, 30, 68), rgb(112, 60, 110), 9)
        box("WallRail", seg[1], FLOOR + 11, SHOW_Z1 - 0.12, seg[2], FLOOR + 11.2, SHOW_Z1, BRASS, M.Metal, f, nc())
    end

    -- (v2.0.2) two stucco ceiling beams (they break up the flat ceiling)
    for _, bz in ipairs({ 2.2, 12.9 }) do
        box("CeilingBeam", IX0, CEIL - 0.6, bz - 0.4, IX1, CEIL, bz + 0.4, rgb(70, 44, 80), M.Plaster, f, nc())
        box("BeamTrim", IX0, CEIL - 0.66, bz - 0.42, IX1, CEIL - 0.6, bz + 0.42, BRASS, M.Metal, f, nc())
    end

    -- brass cornice where the walls meet the ceiling
    box("Cornice", IX0, CEIL - 0.3, IZ0, IX1, CEIL, IZ0 + 0.2, BRASS, M.Metal, f, nc())
    box("Cornice", IX0, CEIL - 0.3, SHOW_Z1 - 0.2, IX1, CEIL, SHOW_Z1, BRASS, M.Metal, f, nc())
    box("Cornice", IX0, CEIL - 0.3, IZ0, IX0 + 0.2, CEIL, SHOW_Z1, BRASS, M.Metal, f, nc())
    box("Cornice", IX1 - 0.2, CEIL - 0.3, IZ0, IX1, CEIL, SHOW_Z1, BRASS, M.Metal, f, nc())
    part({ Name = "CeilingMedallion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 5.4, 5.4),
        CFrame = CFrame.new(CX, CEIL - 0.05, CAGE_Z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STUCCO, Material = M.Plaster, CanCollide = false }, f)

    -- archway to the back hall: brass frame + STAFF ONLY plaque
    box("ArchTrimW", ARCH_X0 - 0.3, FLOOR, SHOW_Z1 - 0.2, ARCH_X0, ARCH_TOP + 0.3, SHOW_Z1, BRASS, M.Metal, f)
    box("ArchTrimE", ARCH_X1, FLOOR, SHOW_Z1 - 0.2, ARCH_X1 + 0.3, ARCH_TOP + 0.3, SHOW_Z1, BRASS, M.Metal, f)
    box("ArchTrimTop", ARCH_X0 - 0.3, ARCH_TOP, SHOW_Z1 - 0.2, ARCH_X1 + 0.3, ARCH_TOP + 0.3, SHOW_Z1, BRASS, M.Metal, f)
    local plaque = box("StaffPlaque", -64, ARCH_TOP + 0.8, SHOW_Z1 - 0.14, -60, ARCH_TOP + 1.9, SHOW_Z1 - 0.04, BRASS, M.Metal, f, nc())
    lit(printOn(plaque, Enum.NormalId.Front, "STAFF ONLY", rgb(60, 36, 14), UITheme.F.display, 50, 1).Parent)
    -- velvet rope stanchions either side of the archway (a "keep out" feel, not a block)
    for _, sx in ipairs({ ARCH_X0 - 1.2, ARCH_X1 + 1.2 }) do
        part({ Name = "Stanchion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 0.3, 0.3),
            CFrame = CFrame.new(sx, FLOOR + 1.6, SHOW_Z1 - 0.9) * CFrame.Angles(0, 0, math.rad(90)),
            Color = BRASS, Material = M.Metal }, f)
        part({ Name = "StanchionTop", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
            Position = Vector3.new(sx, FLOOR + 3.3, SHOW_Z1 - 0.9), Color = BRASS, Material = M.Metal }, f)
    end
end

function JewelryBuilder:_chandelier(f, x, z)
    local c = Instance.new("Model")
    c.Name = "Chandelier"
    c.Parent = f
    local crystal = rgb(236, 240, 255)
    local y0 = CEIL - 2.6
    local function ring(y, r, n, drop)
        for i = 0, n - 1 do
            local a0 = (i / n) * math.pi * 2
            local a1 = ((i + 1) / n) * math.pi * 2
            local p0 = Vector3.new(x + r * math.cos(a0), y, z + r * math.sin(a0))
            local p1 = Vector3.new(x + r * math.cos(a1), y, z + r * math.sin(a1))
            bar("Ring", p0, p1, 0.14, BRASS, M.Metal, c, nc({ CastShadow = false }))
            part({ Name = "Crystal", Size = Vector3.new(0.22, drop, 0.22),
                CFrame = CFrame.new(p0 + Vector3.new(0, -drop / 2 - 0.08, 0)) * CFrame.Angles(0, math.rad(45), 0),
                Color = crystal, Material = M.Glass, Transparency = 0.2, Reflectance = 0.4,
                CanCollide = false, CastShadow = false }, c)
        end
    end
    part({ Name = "Canopy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6),
        CFrame = CFrame.new(x, CEIL - 0.15, z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = BRASS, Material = M.Metal, CanCollide = false }, c)
    bar("Rod", Vector3.new(x, CEIL - 0.3, z), Vector3.new(x, y0 - 1, z), 0.16, BRASS, M.Metal, c, nc())
    ring(y0, 2.4, 14, 0.6)
    ring(y0 - 0.9, 1.5, 10, 0.5)
    for i = 0, 3 do
        local a = i * math.pi / 2
        bar("Arm", Vector3.new(x, y0, z), Vector3.new(x + 2.4 * math.cos(a), y0, z + 2.4 * math.sin(a)),
            0.12, BRASS, M.Metal, c, nc())
    end
    for i = 0, 7 do
        local a = (i + 0.5) * math.pi / 4
        part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3),
            Position = Vector3.new(x + 2.4 * math.cos(a), y0 + 0.22, z + 2.4 * math.sin(a)),
            Color = WARM, Material = M.Neon, CanCollide = false, CastShadow = false }, c)
    end
    local pendant = part({ Name = "Pendant", Size = Vector3.new(0.6, 0.6, 0.6),
        CFrame = CFrame.new(x, y0 - 1.4, z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
        Color = crystal, Material = M.Glass, Transparency = 0.15, Reflectance = 0.5,
        CanCollide = false, CastShadow = false }, c)
    -- (v2.0.2) the one big key light in the showroom: shadows on, a bit dimmer
    -- so the case spots read as bright pools
    point(pendant, rgb(255, 214, 170), 1.0, 22, true)
end

function JewelryBuilder:_counter(f)
    -- sales counter along the back-west wall, facing the showroom
    local x0, x1, z0, z1 = -80, -70, 13.6, 15.3
    local topY = FLOOR + 3.2
    box("CounterBody", x0, FLOOR, z0, x1, topY, z1, rgb(236, 214, 226), M.Marble, f)
    box("CounterKick", x0 + 0.1, FLOOR, z0 - 0.08, x1 - 0.1, FLOOR + 0.3, z0, BRASS, M.Metal, f)
    for k = 0, 6 do
        local fx = x0 + 0.7 + k * ((x1 - x0 - 1.4) / 6)
        box("CounterFlute", fx - 0.1, FLOOR + 0.5, z0 - 0.1, fx + 0.1, topY - 0.2, z0, BRASS, M.Metal, f, nc())
    end
    box("CounterTop", x0 - 0.1, topY, z0 - 0.1, x1 + 0.1, topY + 0.2, z1 + 0.05, BRASS, M.Metal, f, { Reflectance = 0.2 })
    local ty = topY + 0.2
    -- cash register
    box("Register", -72.4, ty, 14.1, -70.8, ty + 0.6, 15.1, rgb(34, 34, 40), M.Metal, f)
    box("RegisterDrawer", -72.3, ty, 14.0, -70.9, ty + 0.22, 14.1, rgb(52, 52, 60), M.Metal, f)
    local screen = part({ Name = "RegisterScreen", Size = Vector3.new(1.2, 0.65, 0.08),
        CFrame = CFrame.new(-71.6, ty + 1.05, 14.7) * CFrame.Angles(math.rad(18), 0, 0),
        Color = rgb(20, 22, 26), Material = M.Metal, CanCollide = false }, f)
    local sg = surface(screen, Enum.NormalId.Front, 80, 1.4)
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 24, 18) }, sg)
    text({ Text = "$0.00", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true, FontFace = UITheme.F.mono,
        TextColor3 = UITheme.C.money }, sg)
    -- a ring tray + a gift box on the counter (decor)
    box("RingTray", -76.8, ty, 14.0, -75.2, ty + 0.15, 14.9, VELVET_2, M.Fabric, f, nc())
    for k = 0, 3 do
        gem(f, Vector3.new(-76.5 + k * 0.4, ty + 0.3, 14.45), 0.16, GEM_COLORS[(k % 3) + 1], true)
    end
    box("GiftBox", -74.3, ty, 14.2, -73.5, ty + 0.6, 15.0, rgb(250, 196, 220), M.Fabric, f, nc())
    box("GiftRibbon", -73.96, ty, 14.2, -73.84, ty + 0.62, 15.0, HOT_PINK, M.Fabric, f, nc())

    -- mirror wall behind the counter
    local mx0, mx1, my0, my1 = -80, -70, 4.8, 12
    local mirror = box("CounterMirror", mx0, my0, SHOW_Z1 - 0.12, mx1, my1, SHOW_Z1, MIRROR, M.Glass, f,
        { Reflectance = 0.6 })
    box("MirrorFrame", mx0 - 0.15, my1, SHOW_Z1 - 0.18, mx1 + 0.15, my1 + 0.15, SHOW_Z1, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx0 - 0.15, my0 - 0.15, SHOW_Z1 - 0.18, mx1 + 0.15, my0, SHOW_Z1, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx0 - 0.15, my0, SHOW_Z1 - 0.18, mx0, my1, SHOW_Z1, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx1, my0, SHOW_Z1 - 0.18, mx1 + 0.15, my1, SHOW_Z1, BRASS, M.Metal, f, nc())
    local mg = lit(surface(mirror, Enum.NormalId.Front, 30, 1))
    text({ Text = "Diamond Dolls", Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.06),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextTransparency = 0.15,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = rgb(222, 180, 96) }, mg)
    canLight(f, -77.5, 14.5, WARM, 2.4, 40)
    canLight(f, -72.5, 14.5, WARM, 2.4, 40)

    -- keycard spot: west end of the counter top
    return CFrame.new(-78.4, ty, 14.45)
end

-- the customer lounge in the back-east corner: velvet sofa, side table, big plant
-- (HideSpot), and the showroom end of the crawl vent (behind the sofa, low on the back wall)
function JewelryBuilder:_lounge(f, refs)
    -- velvet sofa facing the showroom
    local sx0, sx1, sz0, sz1 = -56.2, -52, 14.0, 15.8
    box("SofaBase", sx0, FLOOR, sz0, sx1, FLOOR + 1.5, sz1, VELVET, M.Fabric, f)
    box("SofaBack", sx0, FLOOR + 1.5, sz1 - 0.6, sx1, FLOOR + 3.4, sz1, VELVET, M.Fabric, f)
    box("SofaArm", sx0, FLOOR + 1.5, sz0, sx0 + 0.5, FLOOR + 2.5, sz1, VELVET, M.Fabric, f)
    box("SofaArm", sx1 - 0.5, FLOOR + 1.5, sz0, sx1, FLOOR + 2.5, sz1, VELVET, M.Fabric, f)
    box("SofaPiping", sx0, FLOOR + 3.3, sz1 - 0.65, sx1, FLOOR + 3.45, sz1, BRASS, M.Metal, f, nc())

    -- the big potted palm in the corner = a hiding spot
    local px, pz = -48.2, 13.9
    local pot = part({ Name = "BigPlant", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 2, 2),
        CFrame = CFrame.new(px, FLOOR + 1.1, pz) * CFrame.Angles(0, 0, math.rad(90)),
        Color = rgb(236, 226, 230), Material = M.Marble }, f)
    box("PotBand", px - 1.05, FLOOR + 1.7, pz - 1.05, px + 1.05, FLOOR + 1.9, pz + 1.05, BRASS, M.Metal, f, nc())
    bar("PalmTrunk", Vector3.new(px, FLOOR + 2, pz), Vector3.new(px - 0.2, FLOOR + 5.6, pz + 0.1), 0.35,
        rgb(110, 84, 58), M.Wood, f, nc())
    for k = 0, 6 do
        local a = k * math.pi * 2 / 7
        local tipP = Vector3.new(px + 2 * math.cos(a), FLOOR + 4.4 + (k % 2) * 0.6, pz + 2 * math.sin(a))
        bar("Frond", Vector3.new(px - 0.2, FLOOR + 5.6, pz + 0.1), tipP, 0.5, rgb(46, 120, 70), M.Grass, f,
            nc({ CastShadow = true }))
    end
    tag(pot, "HideSpot", { Label = "Big plant" })
    table.insert(refs.hideSpots, pot)

    -- crawl vent, showroom end (back wall, low, behind the sofa's east end)
    local vx = -50.2
    box("VentFrame", vx - 1.45, FLOOR, SHOW_Z1 - 0.2, vx + 1.45, FLOOR + 2.75, SHOW_Z1, BRASS, M.Metal, f, nc())
    local vent = facingPart("DD_VentShowroom", Vector3.new(vx, FLOOR + 1.3, SHOW_Z1 - 0.25), Vector3.new(2.5, 2.4, 0.12),
        Vector3.new(0, 0, -1), rgb(40, 40, 46), M.DiamondPlate, f)
    local vg = lit(surface(vent, Enum.NormalId.Front, 30, 1))
    for k = 0, 5 do
        frame({ Size = UDim2.fromScale(0.9, 0.06), Position = UDim2.fromScale(0.05, 0.1 + k * 0.14),
            BackgroundColor3 = rgb(16, 16, 20) }, vg)
    end

    -- a warm floor lamp glow over the sofa (the corner stays dim — it's a shadow zone)
    point(lightAnchor("LoungeGlow", Vector3.new(-54, FLOOR + 5, 15), f), WARM, 0.5, 8, false)
    return vent
end

-- One display case, built in its own frame: local X = long axis, local -Z = the
-- side the shoppers stand on (faceDir). centre is on the floor (y = FLOOR).
function JewelryBuilder:_case(f, i, centre, faceDir)
    local c = Instance.new("Model")
    c.Name = "DisplayCase" .. i
    c.Parent = f
    local cf = CFrame.lookAt(centre, centre + faceDir)
    local function lb(name, x0, y0, z0, x1, y1, z1, color, material, parent, extra)
        local props = {
            Name = name,
            Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
            CFrame = cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
            Color = color, Material = material,
        }
        for k, v in pairs(extra or {}) do props[k] = v end
        return part(props, parent)
    end
    local function lp(x, y, z) return cf:PointToWorldSpace(Vector3.new(x, y, z)) end

    local HX, HZ = CASE_HX, CASE_HZ
    local rim, padTop, glassTop = 3.1, 3.3, 4.8
    local body = (i % 2 == 0) and rgb(28, 22, 34) or rgb(36, 26, 44)
    lb("CaseBase", -HX, 0, -HZ, HX, rim, HZ, body, M.Marble, c, { Reflectance = 0.06 })
    lb("CaseKick", -HX + 0.05, 0, -HZ - 0.05, HX - 0.05, 0.25, HZ + 0.05, BRASS, M.Metal, c, nc())
    lb("CaseRim", -HX - 0.05, rim, -HZ - 0.05, HX + 0.05, rim + 0.15, HZ + 0.05, BRASS, M.Metal, c, { Reflectance = 0.2 })
    local pad = (i <= 4) and VELVET or VELVET_2
    lb("VelvetPad", -HX + 0.15, rim + 0.15, -HZ + 0.12, HX - 0.15, padTop, HZ - 0.12, pad, M.Fabric, c)
    local glass = lb("CaseGlass", -HX, rim + 0.15, -HZ, HX, glassTop, HZ, rgb(214, 236, 246), M.Glass, c,
        { Transparency = 0.6, Reflectance = 0.25, CastShadow = false })
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            local px, pz = sx * (HX - 0.05), sz * (HZ - 0.05)
            lb("CasePost", px - 0.05, rim + 0.15, pz - 0.05, px + 0.05, glassTop, pz + 0.05, BRASS, M.Metal, c, nc())
        end
    end

    -- the jewels (this is what LootService hides when the case is taken).
    -- (v3.0) real pieces on real display furniture; the stands stay behind.
    local v = Instance.new("Model")
    v.Name = "Jewels"
    v.Parent = c
    local METALS = { GOLD, PLATINUM, ROSE }
    local variant = (i - 1) % 4
    if variant == 0 then
        -- a ring tray: black velvet with two slotted rows, twelve rings on edge
        lb("RingTray", -1.85, padTop, -0.8, 1.85, padTop + 0.1, 0.8, BLACK_VELVET, M.Fabric, c, nc())
        lb("TrayEdge", -1.9, padTop, -0.85, 1.9, padTop + 0.13, -0.8, BRASS, M.Metal, c, nc())
        local gems = { STONE.diamond, STONE.ruby, STONE.sapphire, STONE.emerald, STONE.diamond, STONE.pink }
        for r, rz in ipairs({ -0.38, 0.32 }) do
            lb("RingSlot", -1.75, padTop + 0.1, rz - 0.04, 1.75, padTop + 0.12, rz + 0.04, rgb(8, 6, 12), M.Fabric, c, nc())
            for k = 0, 5 do
                local dia = (r == 1) and 0.34 or 0.4
                local ringCF = cf * CFrame.new(-1.5 + k * 0.6, padTop + 0.06 + dia / 2, rz)
                standingRing(v, ringCF, dia, METALS[(k + r) % 3 + 1], gems[(k + r * 2) % 6 + 1])
            end
        end
    elseif variant == 1 then
        -- a necklace easel: a tilted velvet board with a diamond necklace
        -- draped on it, a sapphire pendant in a halo, drop earrings in front
        local boardCF = cf * CFrame.new(0, padTop + 0.62, 0.25) * CFrame.Angles(math.rad(25), 0, 0)
        part({ Name = "NecklaceEasel", Size = Vector3.new(2.7, 1.2, 0.08), CFrame = boardCF,
            Color = (i <= 4) and VELVET or BLACK_VELVET, Material = M.Fabric, CanCollide = false }, c)
        part({ Name = "EaselLeg", Size = Vector3.new(0.12, 0.9, 0.12),
            CFrame = cf * CFrame.new(0, padTop + 0.45, 0.55) * CFrame.Angles(math.rad(-20), 0, 0),
            Color = BRASS, Material = M.Metal, CanCollide = false }, c)
        local function onBoard(x, y) return (boardCF * CFrame.new(x, y, -0.07)).Position end
        local n = 21
        for k = 0, n - 1 do
            local t = -1 + 2 * k / (n - 1)
            local p = onBoard(0.95 * t, 0.42 - 0.62 * (1 - t * t))
            if k % 2 == 0 then
                stone(v, p, 0.13, STONE.diamond)
            else
                bead(v, p, 0.08, PLATINUM)
            end
        end
        local pend = onBoard(0, -0.36)
        stone(v, pend, 0.3, STONE.sapphire)
        for k = 0, 7 do
            local a = k * math.pi / 4
            bead(v, onBoard(0.2 * math.cos(a), -0.36 + 0.2 * math.sin(a)), 0.07, STONE.diamond, M.Glass)
        end
        for _, ex in ipairs({ -1.45, 1.45 }) do
            for _, dx in ipairs({ -0.14, 0.14 }) do
                bead(v, lp(ex + dx, padTop + 0.34, -0.55), 0.07, GOLD)
                bar("EarDrop", lp(ex + dx, padTop + 0.3, -0.55), lp(ex + dx, padTop + 0.18, -0.55), 0.025, GOLD, M.Metal, v, nc())
                stone(v, lp(ex + dx, padTop + 0.12, -0.55), 0.12, STONE.emerald)
            end
            lb("EarStand", ex - 0.3, padTop, -0.62, ex + 0.3, padTop + 0.36, -0.52, BLACK_VELVET, M.Fabric, c, nc())
        end
    elseif variant == 2 then
        -- two earring cards and a ring cone with a big solitaire
        for side, ex in ipairs({ -1.25, 1.25 }) do
            local cardCF = cf * CFrame.new(ex, padTop + 0.45, 0) * CFrame.Angles(math.rad(12), 0, 0)
            part({ Name = "EarringCard", Size = Vector3.new(0.8, 0.9, 0.05), CFrame = cardCF,
                Color = BLACK_VELVET, Material = M.Fabric, CanCollide = false }, c)
            part({ Name = "CardClip", Size = Vector3.new(0.82, 0.06, 0.07), CFrame = cardCF * CFrame.new(0, 0.44, 0),
                Color = BRASS, Material = M.Metal, CanCollide = false }, c)
            local drop = side == 1 and STONE.diamond or STONE.ruby
            for _, dx in ipairs({ -0.2, 0.2 }) do
                local s0 = (cardCF * CFrame.new(dx, 0.2, -0.05)).Position
                local s1 = (cardCF * CFrame.new(dx, -0.12, -0.05)).Position
                bead(v, s0, 0.09, side == 1 and PLATINUM or GOLD)
                bar("EarDrop", s0, s1, 0.025, side == 1 and PLATINUM or GOLD, M.Metal, v, nc())
                stone(v, (cardCF * CFrame.new(dx, -0.2, -0.06)).Position, 0.17, drop)
            end
        end
        -- the ring cone: a stepped brass cone, the solitaire round it
        for k, d in ipairs({ 0.42, 0.34, 0.26, 0.18 }) do
            vcyl("RingCone", lp(0, padTop + 0.1 + (k - 1) * 0.18, 0), d, 0.18, BRASS, M.Metal, c, nc({ Reflectance = 0.2 }))
        end
        local ringY = padTop + 0.42
        vcyl("Band", lp(0, ringY, 0), 0.4, 0.07, PLATINUM, M.Metal, v, nc({ Reflectance = 0.4, CastShadow = false }))
        stone(v, lp(0, ringY + 0.05, -0.22), 0.26, STONE.diamond)
        bead(v, lp(-0.12, ringY + 0.04, -0.19), 0.07, STONE.diamond, M.Glass)
        bead(v, lp(0.12, ringY + 0.04, -0.19), 0.07, STONE.diamond, M.Glass)
    else
        -- bracelets hanging on a velvet T-bar: a diamond tennis bracelet, a rose
        -- gold bangle, a sapphire cuff
        local barY = padTop + 0.85
        for _, px in ipairs({ -1.15, 1.15 }) do
            bar("TBarPost", lp(px, padTop, 0.1), lp(px, barY, 0.1), 0.1, BRASS, M.Metal, c, nc())
            lb("TBarFoot", px - 0.2, padTop, -0.1, px + 0.2, padTop + 0.05, 0.3, BRASS, M.Metal, c, nc())
        end
        part({ Name = "TBar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 0.3, 0.3),
            CFrame = cf * CFrame.new(0, barY, 0.1), Color = BLACK_VELVET, Material = M.Fabric, CanCollide = false }, c)
        local looks = { { GOLD, STONE.diamond }, { ROSE, nil }, { PLATINUM, STONE.sapphire } }
        for k, bx in ipairs({ -0.75, 0, 0.75 }) do
            -- the hoop's plane is across the bar; it hangs from the bar's top
            local hcf = cf * CFrame.new(bx, barY - 0.15, 0.1) * CFrame.Angles(0, math.rad(90), 0)
            local pts = hoop(v, hcf, 0.3, 14, 0.07, looks[k][1])
            if looks[k][2] then
                -- stones round the front of the hoop (the side facing the shoppers)
                for s = 1, #pts - 1 do
                    if (pts[s] - hcf.Position):Dot(cf.LookVector) > 0.05 then
                        stone(v, pts[s], 0.1, looks[k][2])
                    end
                end
            end
        end
    end
    -- a tiny price tag on the front of every case (it stays when the case is emptied)
    local tagCF = cf * CFrame.new(-HX + 0.4, padTop + ((variant == 0) and 0.12 or 0.02), -HZ + 0.24)
        * CFrame.Angles(0, math.rad(-20), 0)
    local tagP = part({ Name = "PriceTag", Size = Vector3.new(0.42, 0.02, 0.24), CFrame = tagCF,
        Color = rgb(250, 246, 236), Material = M.Fabric, CanCollide = false, CastShadow = false }, c)
    local tg = lit(surface(tagP, Enum.NormalId.Top, 120, 1))
    text({ Text = ({ "$4,800", "$12,500", "$7,200", "$9,900" })[variant + 1], Size = UDim2.fromScale(0.9, 0.8),
        Position = UDim2.fromScale(0.05, 0.1), TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(60, 36, 14) }, tg)

    -- (v2.0.2) glam spotlighting: a tight, bright pool on every case (the four
    -- island faces cast shadows) + a cool glow inside the glass so the stones sparkle
    canLight(f, centre.X, centre.Z, rgb(255, 238, 220), 4.5, 26, i == 3 or i == 4)
    point(glass, rgb(226, 236, 255), 0.9, 4.5, false)

    local stand = lp(0, 3, -(HZ + 1.9))
    return {
        glass = glass,
        visual = v,
        cframe = CFrame.lookAt(stand, Vector3.new(centre.X, stand.Y, centre.Z)),
        kind = "Jewels",
    }
end

-- ──────────────────────────────────────────────
-- 💍 (v3.0) NECKLACE BUSTS + THE PINK DIAMOND
-- ──────────────────────────────────────────────
-- A velvet jewellery bust under a screwed-down glass hood, standing on a
-- plinth whose top is at p0. `face` = the way the necklace faces, `toPlayer` =
-- the side the thief works from (the 4 hood screws are on that side).
-- Returns the necklace Model (the loot visual; bust + hood stay behind).
local NECKLACE_STYLES = {
    -- { chain metal, chain material, stone on every other link, pendant stone, pendant size }
    { PLATINUM, M.Metal,  STONE.diamond,  STONE.diamond,  0.26 },  -- a diamond rivière
    { PEARL,    M.Marble, nil,            STONE.pink,     0.24 },  -- pearls + a pink drop
    { GOLD,     M.Metal,  STONE.emerald,  STONE.emerald,  0.28 },  -- emerald + gold
    { PLATINUM, M.Metal,  STONE.sapphire, STONE.sapphire, 0.28 },  -- sapphire + white gold
    { GOLD,     M.Metal,  STONE.diamond,  STONE.ruby,     0.36 },  -- "the Duchess": rubies + diamonds
}

function JewelryBuilder:_necklaceBust(f, name, p0, face, toPlayer, style)
    local m = Instance.new("Model")
    m.Name = name
    m.Parent = f
    local cf = CFrame.lookAt(p0, p0 + face)            -- local -Z = the necklace side
    local function lb(n, x0, y0, z0, x1, y1, z1, color, material, parent, extra)
        local props = { Name = n, Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
            CFrame = cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Color = color, Material = material }
        for k, v in pairs(extra or {}) do props[k] = v end
        return part(props, parent)
    end
    local function lp(x, y, z) return cf:PointToWorldSpace(Vector3.new(x, y, z)) end
    local S = NECKLACE_STYLES[style] or NECKLACE_STYLES[1]
    local skin = (style % 2 == 0) and BLACK_VELVET or VELVET_2

    -- the bust: brass foot + stem, velvet torso, round shoulders, neck
    vcyl("BustFoot", lp(0, 0.06, 0), 0.8, 0.12, BRASS, M.Metal, m, { Reflectance = 0.2 })
    bar("BustStem", lp(0, 0.12, 0), lp(0, 0.5, 0), 0.14, BRASS, M.Metal, m)
    lb("BustTorso", -0.5, 0.5, -0.22, 0.5, 1.42, 0.22, skin, M.Fabric, m)
    part({ Name = "BustShoulders", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.0, 0.44, 0.44),
        CFrame = cf * CFrame.new(0, 1.42, 0), Color = skin, Material = M.Fabric }, m)
    vcyl("BustNeck", lp(0, 1.85, 0), 0.4, 0.8, skin, M.Fabric, m)
    vcyl("BustCap", lp(0, 2.27, 0), 0.44, 0.05, BRASS, M.Metal, m, { CanCollide = false })

    -- the necklace (the loot)
    local nk = Instance.new("Model")
    nk.Name = "Necklace"
    nk.Parent = f
    local n = 17
    for k = 0, n - 1 do
        local t = -1 + 2 * k / (n - 1)
        local p = lp(0.3 * t, 1.66 - 0.4 * (1 - t * t), -0.25 - 0.02 * (1 - t * t))
        if S[3] and k % 2 == 0 then
            stone(nk, p, (style == 5) and 0.14 or 0.11, (style == 5 and k % 4 == 0) and STONE.ruby or S[3])
        else
            bead(nk, p, (S[2] == M.Marble) and 0.12 or 0.08, S[1], S[2] ~= M.Metal and S[2] or nil)
        end
    end
    -- the chain goes on round the back of the neck, with a clasp
    for k = 0, 6 do
        local a = math.rad(200 + k * 23.3)
        bead(nk, lp(0.23 * math.cos(a), 1.68, -0.23 * math.sin(a)), 0.06, S[1], S[2] ~= M.Metal and S[2] or nil)
    end
    bead(nk, lp(0, 1.68, 0.23), 0.08, GOLD)
    -- the pendant: a bezel, a bail and the big stone
    local pend = lp(0, 1.02, -0.29)
    bar("Bail", lp(0, 1.26, -0.27), lp(0, 1.16, -0.29), 0.04, S[1], M.Metal, nk, nc({ CastShadow = false }))
    part({ Name = "Bezel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, S[5] + 0.08, S[5] + 0.08),
        CFrame = cf * CFrame.new(0, 1.02, -0.26) * CFrame.Angles(0, math.rad(90), 0),
        Color = S[1], Material = M.Metal, Reflectance = 0.4, CanCollide = false, CastShadow = false }, nk)
    gem(nk, pend, S[5], S[4], false)
    if style == 5 then
        -- the Duchess: a second row of little diamonds under the collar
        for k = -3, 3 do
            stone(nk, lp(k * 0.08, 1.2 - 0.02 * math.abs(k), -0.27), 0.07, STONE.diamond)
        end
    end
    -- a glint inside the hood (goes dark with the necklace)
    point(lightAnchor("NecklaceGlint", lp(0, 1.2, -0.6), nk), rgb(255, 240, 250), 0.6, 4, false)

    -- the glass hood with a brass frame; 4 screws on the thief's side
    local hx, hz, top = 0.8, 0.6, 2.5
    lb("HoodGlass", -hx, 0, -hz, hx, top, hz, rgb(214, 236, 246), M.Glass, m,
        { Transparency = 0.72, Reflectance = 0.28, CastShadow = false })
    lb("HoodBase", -hx - 0.04, 0, -hz - 0.04, hx + 0.04, 0.16, hz + 0.04, BRASS, M.Metal, m, { Reflectance = 0.2 })
    lb("HoodCap", -hx - 0.04, top - 0.1, -hz - 0.04, hx + 0.04, top, hz + 0.04, BRASS, M.Metal, m, { Reflectance = 0.2 })
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            lb("HoodPost", sx * hx - 0.035, 0.16, sz * hz - 0.035, sx * hx + 0.035, top - 0.1, sz * hz + 0.035,
                BRASS, M.Metal, m, nc())
        end
    end
    local side = Vector3.new(toPlayer.X, 0, toPlayer.Z).Unit
    local sideRight = Vector3.new(0, 1, 0):Cross(side).Unit
    local faceDist = math.abs(side:Dot(cf.LookVector)) > 0.5 and hz or hx
    local halfW = math.abs(side:Dot(cf.LookVector)) > 0.5 and hx or hz
    for _, sy in ipairs({ 0.08, top - 0.05 }) do
        for _, sr in ipairs({ -1, 1 }) do
            local p = p0 + Vector3.new(0, sy, 0) + side * (faceDist + 0.05) + sideRight * (sr * (halfW - 0.12))
            part({ Name = "Screw", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.12, 0.12),
                CFrame = CFrame.lookAt(p, p + side) * CFrame.Angles(0, math.rad(90), 0),
                Color = STEEL_LT, Material = M.Metal, Reflectance = 0.3, CanCollide = false, CastShadow = false }, m)
        end
    end
    return nk
end

-- the 4 window busts (on the window plinths built in _facade), facing the street
function JewelryBuilder:_windowNecklaces(f, loot)
    local fo = Instance.new("Folder")
    fo.Name = "WindowNecklaces"
    fo.Parent = f
    local style = 0
    for _, bay in ipairs({ { X0 + 1.5, ENT_X0 - 0.8 }, { ENT_X1 + 0.8, X1 - 1.5 } }) do
        local b0, b1 = bay[1], bay[2]
        for k = 1, 2 do
            style = style + 1
            local px = b0 + (b1 - b0) * (k == 1 and 0.28 or 0.72)
            local nk = self:_necklaceBust(fo, "WindowBust" .. style, Vector3.new(px, FLOOR + 2.55, 0.9),
                Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), style)
            local stand = Vector3.new(px, FLOOR + 3, 2.7)
            table.insert(loot, { kind = "Necklace", cframe = CFrame.lookAt(stand, Vector3.new(px, stand.Y, 0.9)),
                visual = nk, interact = "unscrew", pool = "showroom", inVault = false })
        end
    end
end

-- 💖 THE TARGET: the pink diamond, spinning on a marble column inside its own
-- laser cage in the middle of the showroom, right under the chandelier.
-- Returns the laser row for the cage (same shape as _lasers' rows).
function JewelryBuilder:_pinkDiamond(f, loot)
    local g = Instance.new("Folder")
    g.Name = "PinkDiamond"
    g.Parent = f
    local x, z, H = CX, CAGE_Z, CAGE_H

    -- the floor: a black marble square with a brass border under the cage
    box("CageInlay", x - H, FLOOR, z - H, x + H, FLOOR + 0.03, z + H, rgb(16, 12, 20), M.Marble, g,
        nc({ Reflectance = 0.14 }))
    box("CageBorder", x - H - 0.2, FLOOR, z - H - 0.2, x + H + 0.2, FLOOR + 0.025, z + H + 0.2, BRASS, M.Metal, g, nc())

    -- the column
    local base = box("PedestalBase", x - 0.95, FLOOR, z - 0.95, x + 0.95, FLOOR + 0.4, z + 0.95, rgb(24, 18, 28), M.Marble, g,
        { Reflectance = 0.1 })
    vcyl("PedestalCollar", Vector3.new(x, FLOOR + 0.45, z), 1.45, 0.1, BRASS, M.Metal, g, { Reflectance = 0.2 })
    vcyl("PedestalColumn", Vector3.new(x, FLOOR + 1.75, z), 1.25, 2.6, rgb(238, 230, 234), M.Marble, g)
    vcyl("PedestalTop", Vector3.new(x, FLOOR + 3.0, z), 1.6, 0.14, BRASS, M.Metal, g, { Reflectance = 0.25 })
    local plaque = box("PedestalPlaque", x - 0.7, FLOOR + 0.07, z - 0.97, x + 0.7, FLOOR + 0.33, z - 0.95, BRASS, M.Metal, g, nc())
    lit(printOn(plaque, Enum.NormalId.Front, "THE PINK DOLL  ·  42 CARATS", rgb(60, 36, 14), UITheme.F.display, 90, 1).Parent)
    lit(printOn(box("PedestalPlaque", x - 0.7, FLOOR + 0.07, z + 0.95, x + 0.7, FLOOR + 0.33, z + 0.97, BRASS, M.Metal, g, nc()),
        Enum.NormalId.Back, "PLEASE DO NOT TOUCH", rgb(60, 36, 14), UITheme.F.display, 90, 1).Parent)
    local _ = base

    -- the turntable: THIS is what spins (attribute Spin = degrees/second). The
    -- cushion, the prongs and the stone are welded to it.
    local turn = vcyl("Turntable", Vector3.new(x, FLOOR + 3.13, z), 1.3, 0.12, BRASS, M.Metal, g, { Reflectance = 0.3 })
    turn:SetAttribute("Spin", SPIN_DEG_PER_SEC)
    CollectionService:AddTag(turn, "Spin")
    local cushion = vcyl("Cushion", Vector3.new(x, FLOOR + 3.27, z), 0.9, 0.16, VELVET, M.Fabric, g)
    weldTo(turn, cushion)

    -- the stone: a round brilliant built from stepped glass discs (crown up to
    -- the table, pavilion down to the point), pink, with a glowing heart
    local dm = Instance.new("Model")
    dm.Name = "PinkDiamond"
    dm.Parent = g
    local gy = FLOOR + 4.05                         -- the girdle (widest ring)
    local PINK_STONE = rgb(255, 120, 196)
    local tiers = {
        -- { dy (centre, from the girdle), diameter, height }
        { 0.05, 1.26, 0.1 }, { 0.15, 1.08, 0.1 }, { 0.24, 0.86, 0.08 },            -- crown + table
        { -0.08, 1.16, 0.12 }, { -0.2, 0.96, 0.12 }, { -0.32, 0.74, 0.12 },         -- pavilion
        { -0.44, 0.5, 0.12 }, { -0.55, 0.28, 0.1 }, { -0.62, 0.1, 0.06 },
    }
    for k, t in ipairs(tiers) do
        weldTo(turn, vcyl("Facet", Vector3.new(x, gy + t[1], z), t[2], t[3], PINK_STONE, M.Glass, dm,
            { Transparency = (k <= 3) and 0.18 or 0.1, Reflectance = 0.45, CastShadow = false }))
    end
    local heart = part({ Name = "Heart", Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34),
        Position = Vector3.new(x, gy - 0.1, z), Color = HOT_PINK, Material = M.Neon, CastShadow = false }, dm)
    weldTo(turn, heart)
    point(heart, rgb(255, 120, 200), 1.3, 9, false)
    -- four gold prongs from the cushion up to the girdle
    for k = 0, 3 do
        local a = k * math.pi / 2 + math.pi / 4
        local p0 = Vector3.new(x + 0.22 * math.cos(a), FLOOR + 3.35, z + 0.22 * math.sin(a))
        local p1 = Vector3.new(x + 0.6 * math.cos(a), gy + 0.08, z + 0.6 * math.sin(a))
        weldTo(turn, bar("Prong", p0, p1, 0.06, GOLD, M.Metal, dm, { Reflectance = 0.4, CastShadow = false }))
    end
    -- a tight pink-white spot from the ceiling (the chandelier hangs just above)
    canLight(g, x, z, rgb(255, 236, 246), 4, 22, true)

    -- stand at the column's north face (inside the cage: you have to go in)
    local stand = Vector3.new(x, FLOOR + 3, z - 1.95)
    table.insert(loot, { kind = "PinkDiamond", target = "PinkDiamond", cframe = CFrame.lookAt(stand, Vector3.new(x, stand.Y, z)),
        visual = dm, pool = "showroom", inVault = false,
        -- (for LOOT-CORE) the prompt should only reach from inside the cage
        promptRange = 2.5 })

    -- ── the laser cage ──
    local corners = {
        Vector3.new(x - H, 0, z - H), Vector3.new(x + H, 0, z - H),
        Vector3.new(x + H, 0, z + H), Vector3.new(x - H, 0, z + H),
    }
    for _, c in ipairs(corners) do
        box("CagePost", c.X - 0.16, FLOOR, c.Z - 0.16, c.X + 0.16, CAGE_TOP, c.Z + 0.16, rgb(20, 20, 26), M.Metal, g,
            { Reflectance = 0.15 })
        box("CagePostCap", c.X - 0.22, CAGE_TOP, c.Z - 0.22, c.X + 0.22, CAGE_TOP + 0.14, c.Z + 0.22, BRASS, M.Metal, g)
        box("CagePostFoot", c.X - 0.26, FLOOR, c.Z - 0.26, c.X + 0.26, FLOOR + 0.2, c.Z + 0.26, BRASS, M.Metal, g)
        box("CageLed", c.X - 0.06, CAGE_TOP - 0.4, c.Z - 0.17, c.X + 0.06, CAGE_TOP - 0.28, c.Z + 0.17, LASER_RED, M.Neon, g,
            nc({ CastShadow = false }))
    end
    local beams = {}
    local function beam(a, b)
        local d = (b - a).Unit
        local bm = bar("CageBeam" .. (#beams + 1), a + d * 0.17, b - d * 0.17, 0.08, LASER_RED, M.Neon, g,
            nc({ CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }))
        table.insert(beams, bm)
    end
    for s = 1, 4 do
        local a, b = corners[s], corners[s % 4 + 1]
        for _, h in ipairs({ 1.0, 2.4, 3.8, 5.2, 6.6 }) do
            beam(a + Vector3.new(0, FLOOR + h, 0), b + Vector3.new(0, FLOOR + h, 0))
        end
        -- a big X across every side, like in the movies
        beam(a + Vector3.new(0, FLOOR + 0.7, 0), b + Vector3.new(0, FLOOR + 6.9, 0))
        beam(b + Vector3.new(0, FLOOR + 0.7, 0), a + Vector3.new(0, FLOOR + 6.9, 0))
    end
    -- a warning plate on the front of the cage
    -- a low kick panel between the two front posts, with the warning printed on it
    local warn = box("CageSign", x - H + 0.16, FLOOR + 0.2, z - H - 0.04, x + H - 0.16, FLOOR + 0.62, z - H + 0.04,
        rgb(24, 20, 28), M.Metal, g, nc())
    lit(printOn(warn, Enum.NormalId.Front, "LASERS  ·  WAIT FOR THEM TO BLINK OFF", rgb(255, 90, 110), UITheme.F.bold, 60, 1).Parent)

    return {
        beams = beams,
        zoneCFrame = CFrame.new(x, FLOOR + 3.75, z),
        zoneSize = Vector3.new(2 * H, 7.5, 2 * H),
        -- a longer "off" than the corridor rows: step in, grab, step out
        onTime = 1.8, offTime = 2.6, phase = 0.4,
    }
end

function JewelryBuilder:_showroom(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "Showroom"
    s.Parent = f
    self:_walls(s)
    -- (v3.0) the chandelier hangs right over the pink diamond
    self:_chandelier(s, CX, CAGE_Z)
    self:_windowNecklaces(s, loot)
    local cageRow = self:_pinkDiamond(s, loot)
    local counterSpot = self:_counter(s)
    local vent = self:_lounge(s, refs)

    -- 8 cases: 2 wall cases per side wall + a back-to-back island each side
    local N, S, E, Wd = Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0)
    local layout = {
        { Vector3.new(IX0 + CASE_HZ, FLOOR, 4.2), E },        -- W1 (west wall)
        { Vector3.new(IX1 - CASE_HZ, FLOOR, 4.2), Wd },       -- E1 (east wall)
        { Vector3.new(-73.8, FLOOR, 6.1), N },                -- west island, north face
        { Vector3.new(-54.2, FLOOR, 6.1), N },                -- east island, north face
        { Vector3.new(IX0 + CASE_HZ, FLOOR, 10.0), E },       -- W2
        { Vector3.new(IX1 - CASE_HZ, FLOOR, 10.0), Wd },      -- E2
        { Vector3.new(-73.8, FLOOR, 8.3), S },                -- west island, south face
        { Vector3.new(-54.2, FLOOR, 8.3), S },                -- east island, south face
    }
    local cases = {}
    for i, l in ipairs(layout) do
        table.insert(cases, self:_case(s, i, l[1], l[2]))
    end
    -- brass divider down the middle of each island
    for _, ix in ipairs({ -73.8, -54.2 }) do
        box("IslandDivider", ix - CASE_HX - 0.05, FLOOR, 7.15, ix + CASE_HX + 0.05, 3.25, 7.25, BRASS, M.Metal, s, nc())
    end
    refs.smashCases = cases
    return counterSpot, vent, cageRow
end

-- ──────────────────────────────────────────────
-- 🔒 BACK OF HOUSE: hall, keycard door, lasers, closet, office, break room, safe room
-- ──────────────────────────────────────────────
function JewelryBuilder:_hall(f, refs, loot)
    local h = Instance.new("Folder")
    h.Name = "BackHall"
    h.Parent = f
    -- (v2.0.2) painted skirting (was stripy wood running across the doorways) +
    -- a teal wayfinding stripe, only on the solid stretches of wall
    local HALL_TEAL = rgb(56, 120, 128)
    for _, seg in ipairs({ { HALL_X0, 1, KC_Z1, HALL_Z1 }, { HALL_X1, -1, OFFICE_DOOR_Z1, HALL_Z1 } }) do
        local xw, s, z0, z1 = seg[1], seg[2], seg[3], seg[4]
        box("Skirting", xw, FLOOR, z0, xw + s * 0.12, FLOOR + 0.6, z1, BOH_DARK, M.Plaster, h, nc())
        box("WayStripe", xw, FLOOR + 3.4, z0, xw + s * 0.06, FLOOR + 3.8, z1, HALL_TEAL, M.Plaster, h, nc())
    end
    -- short return walls either side of the archway (hall side, z 17)
    for _, seg in ipairs({ { HALL_X0, ARCH_X0 - 0.3 }, { ARCH_X1 + 0.3, HALL_X1 } }) do
        box("Skirting", seg[1], FLOOR, BOH_Z0, seg[2], FLOOR + 0.6, BOH_Z0 + 0.12, BOH_DARK, M.Plaster, h, nc())
    end
    -- poster above the lockers (it used to sit behind them)
    local poster = box("Poster", HALL_X1 - 0.08, 8.2, 27.8, HALL_X1, 11.2, 30.2, rgb(250, 196, 220), M.Fabric, h, nc())
    local pg = lit(surface(poster, Enum.NormalId.Left, 40, 1))
    text({ Text = "EMPLOYEE\nOF THE\nMONTH", Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.05),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(120, 20, 70) }, pg)
    frame({ Size = UDim2.fromScale(0.5, 0.26), Position = UDim2.fromScale(0.25, 0.68), BackgroundColor3 = rgb(120, 20, 70) }, pg)

    -- staff lockers against the east wall, south of the office door (HideSpot)
    local lx0, lx1, lz0, lz1 = HALL_X1 - 1.5, HALL_X1, 27.6, 30.4
    local lockers = box("StaffLockers", lx0, FLOOR, lz0, lx1, FLOOR + 7.2, lz1, rgb(70, 110, 140), M.Metal, h)
    local lg = lit(surface(lockers, Enum.NormalId.Left, 30, 1))
    for k = 0, 1 do
        local door = frame({ Size = UDim2.fromScale(0.47, 0.96), Position = UDim2.fromScale(0.02 + k * 0.5, 0.02),
            BackgroundColor3 = rgb(80, 124, 156) }, lg)
        for s2 = 0, 3 do
            frame({ Size = UDim2.fromScale(0.6, 0.012), Position = UDim2.fromScale(0.2, 0.06 + s2 * 0.03),
                BackgroundColor3 = rgb(40, 60, 80) }, door)
        end
        frame({ Size = UDim2.fromScale(0.08, 0.1), Position = UDim2.fromScale(0.82, 0.45), BackgroundColor3 = STEEL_LT }, door)
    end
    tag(lockers, "HideSpot", { Label = "Lockers" })
    table.insert(refs.hideSpots, lockers)

    -- stock boxes on the west wall (cover), well south of the keypad (v3.1: the
    -- courier case's E prompt used to sit 3 studs from the keypad's)
    local SZ = 29.4 - 26.2                            -- shift vs the v3.0 spot
    box("StockShelf", HALL_X0, FLOOR, 26.2 + SZ, HALL_X0 + 1.4, FLOOR + 0.3, 27.9 + SZ, STEEL_LT, M.Metal, h)
    box("StockBox", HALL_X0 + 0.1, FLOOR + 0.3, 26.3 + SZ, HALL_X0 + 1.3, FLOOR + 1.6, 27.1 + SZ, rgb(176, 140, 96), M.Cardboard, h)
    box("StockBox", HALL_X0 + 0.1, FLOOR + 0.3, 27.1 + SZ, HALL_X0 + 1.3, FLOOR + 1.9, 27.8 + SZ, rgb(186, 150, 104), M.Cardboard, h)

    -- (v3.0) LOOT: an aluminium courier case of ring repairs, lid open, on top
    -- of the stock boxes — back from the workshop, waiting to go in the safe
    local cs = Instance.new("Model")
    cs.Name = "RepairCase"
    cs.Parent = h
    local ALU = rgb(196, 200, 208)
    local cx0, cx1, cz0, cz1 = HALL_X0 + 0.15, HALL_X0 + 1.25, 26.35 + SZ, 27.05 + SZ
    local cy0, cy1 = FLOOR + 1.6, FLOOR + 1.95
    box("CaseShell", cx0, cy0, cz0, cx1, cy1, cz1, ALU, M.DiamondPlate, cs, nc({ Reflectance = 0.1 }))
    box("CaseFoam", cx0 + 0.06, cy1, cz0 + 0.06, cx1 - 0.06, cy1 + 0.02, cz1 - 0.06, rgb(40, 40, 46), M.Fabric, cs, nc())
    box("CaseRim", cx0 - 0.02, cy1 - 0.05, cz0 - 0.02, cx1 + 0.02, cy1, cz1 + 0.02, rgb(90, 94, 102), M.Metal, cs, nc())
    -- the lid stands open against the wall, a job ticket taped inside it
    local lid = box("CaseLid", cx0 - 0.08, cy1, cz0, cx0, cy1 + 0.72, cz1, ALU, M.DiamondPlate, cs, nc())
    local lg = lit(surface(lid, Enum.NormalId.Right, 80, 1))
    local slip = frame({ Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.15),
        BackgroundColor3 = rgb(250, 246, 236) }, lg)
    text({ Text = "RING REPAIRS\nURGENT", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextColor3 = rgb(170, 30, 40) }, slip)
    -- two rows of rings stood in the foam, each with a paper repair tag
    local gems = { STONE.diamond, STONE.sapphire, STONE.ruby, STONE.diamond, STONE.emerald, STONE.pink }
    for r = 0, 1 do
        for k = 0, 2 do
            local rx, rz = cx0 + 0.45 + r * 0.42, cz0 + 0.16 + k * 0.19
            local ringCF = CFrame.lookAt(Vector3.new(rx, cy1 + 0.13, rz), Vector3.new(rx + 1, cy1 + 0.13, rz))
            standingRing(cs, ringCF, 0.22, ({ GOLD, PLATINUM, ROSE })[(r + k) % 3 + 1], gems[r * 3 + k + 1],
                rgb(40, 40, 46))
        end
    end
    box("RepairTag", cx1 - 0.2, cy1 + 0.02, cz1 - 0.2, cx1 - 0.05, cy1 + 0.03, cz1 - 0.08, rgb(250, 240, 180), M.Fabric, cs, nc())
    local cstand = Vector3.new(-63.6, FLOOR + 3, 30.2)
    table.insert(loot, { kind = "Jewels", cframe = CFrame.lookAt(cstand, Vector3.new(HALL_X0, cstand.Y, 30.2)),
        visual = cs, pool = "backhall", inVault = false })

    -- the key light of the hall casts shadows (the guard walks under it)
    local hallTube = tubeLight(h, -62, 19.5, false, 0.8, 14)
    for _, l in ipairs(hallTube:GetChildren()) do if l:IsA("PointLight") then l.Shadows = true end end
    tubeLight(h, -62, 28.5, false, 0.35, 9)      -- the dim end (shadow zone below)
    table.insert(refs.shadowZones, shadowZone("ShadowHallEnd", HALL_X0, 25.6, -63.8, HALL_Z1, h))
end

function JewelryBuilder:_keycardDoor(f)
    -- 7-wide frosted glass door in the hall's west wall; slides SOUTH into the
    -- wall (the wall is solid for z 24..34, the pane hides inside it)
    local pane = box("KeycardDoor", -67.65, FLOOR, KC_Z0, -67.35, DOOR_H, KC_Z1, rgb(150, 215, 232), M.Glass, f,
        { Transparency = 0.35, Reflectance = 0.2 })
    local dg = lit(surface(pane, Enum.NormalId.Right, 30, 1))
    frame({ Size = UDim2.fromScale(1, 0.12), Position = UDim2.fromScale(0, 0.42), BackgroundColor3 = rgb(240, 248, 255),
        BackgroundTransparency = 0.3 }, dg)
    text({ Text = "SAFE ROOM  ·  KEYCARD ONLY", Size = UDim2.fromScale(0.86, 0.08), Position = UDim2.fromScale(0.07, 0.44),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(40, 60, 80) }, dg)
    local handle = part({ Name = "DoorHandle", Size = Vector3.new(0.14, 2.8, 0.14),
        CFrame = CFrame.new(-67.2, FLOOR + 4.2, KC_Z0 + 0.8), Color = STEEL_LT, Material = M.Metal }, pane)
    weldTo(pane, handle)
    -- steel frame on the hall side
    box("KeycardFrameN", HALL_X0, FLOOR, KC_Z0, HALL_X0 + 0.2, DOOR_H + 0.3, KC_Z0 + 0.3, STEEL, M.Metal, f, nc())
    box("KeycardFrameS", HALL_X0, FLOOR, KC_Z1 - 0.3, HALL_X0 + 0.2, DOOR_H + 0.3, KC_Z1, STEEL, M.Metal, f, nc())
    box("KeycardFrameTop", HALL_X0, DOOR_H, KC_Z0, HALL_X0 + 0.2, DOOR_H + 0.3, KC_Z1, STEEL, M.Metal, f, nc())
    box("HazardSill", HALL_X0 - 1, FLOOR, KC_Z0, HALL_X0 + 0.4, FLOOR + 0.03, KC_Z1, rgb(230, 190, 40), M.Concrete, f, nc())

    -- keypad on the hall face, just south of the door, status LED above it
    local kz0, kz1 = KC_Z1 + 0.5, KC_Z1 + 1.5
    local panel = box("KeypadPanel", HALL_X0, FLOOR + 3.6, kz0, HALL_X0 + 0.25, FLOOR + 5.2, kz1, rgb(26, 28, 34), M.Metal, f)
    local kg = surface(panel, Enum.NormalId.Right, 60, 1.2)
    frame({ Size = UDim2.fromScale(0.7, 0.06), Position = UDim2.fromScale(0.15, 0.08), BackgroundColor3 = rgb(70, 76, 88) }, kg)
    for r = 0, 3 do
        for col = 0, 2 do
            local key = frame({ Size = UDim2.fromScale(0.2, 0.13), Position = UDim2.fromScale(0.14 + col * 0.25, 0.26 + r * 0.17),
                BackgroundColor3 = rgb(58, 62, 72) }, kg)
            UITheme.corner(key, 3)
        end
    end
    local status = box("KeypadStatus", HALL_X0, FLOOR + 5.4, (kz0 + kz1) / 2 - 0.13, HALL_X0 + 0.22, FLOOR + 5.62,
        (kz0 + kz1) / 2 + 0.13, rgb(255, 60, 60), M.Neon, f, nc())

    return { door = pane, openOffset = Vector3.new(0, 0, KC_Z1 - KC_Z0), panel = panel, status = status }
end

function JewelryBuilder:_lasers(f)
    local rows = {}
    local heights = { 1.1, 2.5, 3.9, 5.3, 6.7 }
    -- row 1: across the corridor, 2.5 studs inside the keycard door (plane x -70.5)
    local lx = -70.5
    local beams = {}
    for k, h in ipairs(heights) do
        local y = FLOOR + h
        box("LaserEmitter", lx - 0.2, y - 0.2, BOH_Z0, lx + 0.2, y + 0.2, BOH_Z0 + 0.25, STEEL_DK, M.Metal, f, nc())
        box("LaserEmitter", lx - 0.2, y - 0.2, LC_WALL0 - 0.25, lx + 0.2, y + 0.2, LC_WALL0, STEEL_DK, M.Metal, f, nc())
        table.insert(beams, box("LaserBeam" .. k, lx - 0.06, y - 0.06, BOH_Z0 + 0.25, lx + 0.06, y + 0.06, LC_WALL0 - 0.25,
            LASER_RED, M.Neon, f, nc({ CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 })))
    end
    for _, hx in ipairs({ lx - 0.5, lx + 0.5 }) do
        box("HazardStripe", hx - 0.08, FLOOR, BOH_Z0, hx + 0.08, FLOOR + 0.03, LC_WALL0, rgb(230, 190, 40), M.Concrete, f, nc())
    end
    table.insert(rows, {
        beams = beams,
        zoneCFrame = CFrame.new(lx, FLOOR + 3.75, (BOH_Z0 + LC_WALL0) / 2),
        zoneSize = Vector3.new(0.6, 7.5, LC_WALL0 - BOH_Z0),
        onTime = 1.4, offTime = 1.1, phase = 0,
    })

    -- row 2: across the 7-wide opening into the safe room (plane z 24.5)
    local lz = (LC_WALL0 + LC_WALL1) / 2
    local beams2 = {}
    for k, h in ipairs(heights) do
        local y = FLOOR + h
        box("LaserEmitter", SR_OPEN_X0, y - 0.2, lz - 0.2, SR_OPEN_X0 + 0.25, y + 0.2, lz + 0.2, STEEL_DK, M.Metal, f, nc())
        box("LaserEmitter", SR_OPEN_X1 - 0.25, y - 0.2, lz - 0.2, SR_OPEN_X1, y + 0.2, lz + 0.2, STEEL_DK, M.Metal, f, nc())
        table.insert(beams2, box("LaserBeamB" .. k, SR_OPEN_X0 + 0.25, y - 0.06, lz - 0.06, SR_OPEN_X1 - 0.25, y + 0.06, lz + 0.06,
            LASER_RED, M.Neon, f, nc({ CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 })))
    end
    table.insert(rows, {
        beams = beams2,
        zoneCFrame = CFrame.new((SR_OPEN_X0 + SR_OPEN_X1) / 2, FLOOR + 3.75, lz),
        zoneSize = Vector3.new(SR_OPEN_X1 - SR_OPEN_X0, 7.5, 0.6),
        onTime = 1.2, offTime = 1.3, phase = 1.1,
    })

    -- the corridor itself: bare concrete, one red emergency lamp — it's meant to feel wrong
    box("CorridorWallW", IX0, FLOOR, BOH_Z0, IX0 + 0.1, FLOOR + 8, LC_WALL0, STEEL, M.Metal, f)
    local red = box("EmergencyLamp", -76.5, CEIL - 0.5, 20, -75.5, CEIL, 21, rgb(120, 20, 24), M.Metal, f, nc())
    box("EmergencyLens", -76.3, CEIL - 0.55, 20.2, -75.7, CEIL - 0.5, 20.8, LASER_RED, M.Neon, f, nc())
    point(red, rgb(255, 60, 70), 0.9, 16, false)
    return rows
end

function JewelryBuilder:_closet(f, refs, loot)
    -- utility closet x -67..-57, z 33..43 (v3.1: 10 x 10, was 10 x 5): breaker,
    -- shelves, janitor cart, a mop sink, and the ladder up to the roof hatch
    -- (inside end of the roof "vent"). E prompts >= 6 apart: breaker (east
    -- wall, z 36.1) · stash (z 36.4, west half) · keycard shelf (south wall).
    local c = Instance.new("Folder")
    c.Name = "Closet"
    c.Parent = f

    -- breaker panel on the east wall (faces west into the closet)
    local bz0, bz1 = 35, 37.2
    local breaker = box("BreakerPanel", HALL_X1 - 0.45, FLOOR + 2.6, bz0, HALL_X1, FLOOR + 6.2, bz1, rgb(96, 102, 110), M.Metal, c)
    local bg = lit(surface(breaker, Enum.NormalId.Left, 50, 1.1))
    text({ Text = "SECURITY", Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 204, 21) }, bg)
    text({ Text = "CAMERAS · ALARM", Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, 0.21),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(30, 32, 38) }, bg)
    for r = 0, 2 do
        for col = 0, 3 do
            frame({ Size = UDim2.fromScale(0.14, 0.12), Position = UDim2.fromScale(0.12 + col * 0.2, 0.4 + r * 0.18),
                BackgroundColor3 = rgb(40, 42, 48) }, bg)
        end
    end
    for k, col in ipairs({ rgb(80, 255, 120), rgb(80, 255, 120), rgb(255, 180, 40) }) do
        local lz = bz0 + 0.4 + (k - 1) * 0.4
        box("BreakerLed", HALL_X1 - 0.52, FLOOR + 5.8, lz - 0.07, HALL_X1 - 0.45, FLOOR + 5.94, lz + 0.07, col, M.Neon, c, nc())
    end
    box("Conduit", HALL_X1 - 0.3, FLOOR + 6.2, 36, HALL_X1 - 0.12, CEIL, 36.2, STEEL_LT, M.Metal, c, nc())
    -- hazard sign over the panel
    local warn = box("HighVoltage", HALL_X1 - 0.08, FLOOR + 6.6, bz0 + 0.4, HALL_X1, FLOOR + 7.6, bz1 - 0.4, rgb(250, 204, 21), M.Metal, c, nc())
    lit(printOn(warn, Enum.NormalId.Left, "DANGER", rgb(30, 30, 30), UITheme.F.display, 50, 1).Parent)

    -- metal shelving on the south wall; the keycard can turn up on the middle shelf
    local shx0, shx1 = -62.2, -57.6
    for k, y in ipairs({ FLOOR + 0.3, FLOOR + 2.8, FLOOR + 5.3 }) do
        box("Shelf", shx0, y, IZ1 - 1.5, shx1, y + 0.15, IZ1, STEEL_LT, M.Metal, c)
        if k < 3 then
            box("ShelfStuff", shx0 + 0.3, y + 0.15, IZ1 - 1.3, shx0 + 1.6, y + 1.2, IZ1 - 0.2, rgb(60, 110, 200), M.Cardboard, c, nc())
            box("ShelfStuff", shx1 - 1.4, y + 0.15, IZ1 - 1.3, shx1 - 0.3, y + 0.9, IZ1 - 0.2, rgb(240, 240, 232), M.Cardboard, c, nc())
        end
    end
    for _, px in ipairs({ shx0 + 0.05, shx1 - 0.05 }) do
        box("ShelfPost", px - 0.08, FLOOR, IZ1 - 1.5, px + 0.08, FLOOR + 6.6, IZ1 - 1.35, STEEL, M.Metal, c, nc())
    end

    -- janitor cart (HideSpot) in the middle of the south wall
    local cx0, cx1, cz0, cz1 = -65.4, -62.6, IZ1 - 1.9, IZ1 - 0.05
    local cart = box("JanitorCart", cx0, FLOOR + 0.5, cz0, cx1, FLOOR + 3.6, cz1, rgb(240, 200, 40), M.Rubber, c)
    for _, wx in ipairs({ cx0 + 0.3, cx1 - 0.3 }) do
        for _, wz in ipairs({ cz0 + 0.3, cz1 - 0.3 }) do
            part({ Name = "CartWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.5, 0.5),
                CFrame = CFrame.new(wx, FLOOR + 0.25, wz), Color = STEEL_DK, Material = M.Rubber, CanCollide = false }, c)
        end
    end
    box("CartBag", cx0 + 0.2, FLOOR + 3.6, cz0 + 0.2, cx0 + 1.5, FLOOR + 5.0, cz1 - 0.2, rgb(40, 40, 44), M.Fabric, c, nc())
    bar("Mop", Vector3.new(cx1 - 0.5, FLOOR + 3.6, cz0 + 0.5), Vector3.new(cx1 - 0.3, FLOOR + 7.6, cz0 + 0.3), 0.12,
        WALNUT, M.Wood, c, nc())
    tag(cart, "HideSpot", { Label = "Janitor cart" })
    table.insert(refs.hideSpots, cart)

    -- ladder up the west wall to the ceiling hatch
    local lz0, lz1 = 38.5, 40.7
    for _, rz in ipairs({ lz0, lz1 }) do
        box("LadderRail", HALL_X0, FLOOR, rz - 0.1, HALL_X0 + 0.6, CEIL, rz + 0.1, STEEL_LT, M.Metal, c, nc())
    end
    for y = FLOOR + 1, CEIL - 1, 1.2 do
        box("LadderRung", HALL_X0 + 0.35, y, lz0, HALL_X0 + 0.5, y + 0.12, lz1, STEEL_LT, M.Metal, c, nc())
    end
    box("CeilingHatch", HALL_X0 + 0.2, CEIL - 0.12, lz0 - 0.3, HALL_X0 + 3, CEIL, lz1 + 0.3, STEEL, M.Metal, c, nc())
    local inside = facingPart("DD_RoofHatchInside", Vector3.new(HALL_X0 + 0.7, FLOOR + 3, (lz0 + lz1) / 2),
        Vector3.new(2.2, 5, 0.15), Vector3.new(1, 0, 0), rgb(250, 204, 21), M.Metal, c,
        { Transparency = 0.2, CanCollide = false })
    local ig = lit(surface(inside, Enum.NormalId.Front, 40, 1))
    text({ Text = "UP TO ROOF", Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.05),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(30, 30, 30) }, ig)

    -- two bare bulbs: one over the breaker end, one (dimmer) over the shelves
    for _, bl in ipairs({ { -60.5, 36.2, 0.55 }, { -61.5, 40.6, 0.35 } }) do
        local bulb = box("ClosetBulb", bl[1] - 0.3, CEIL - 0.3, bl[2] - 0.3, bl[1] + 0.3, CEIL, bl[2] + 0.3, STEEL_DK, M.Metal, c, nc())
        box("ClosetBulbLens", bl[1] - 0.2, CEIL - 0.34, bl[2] - 0.2, bl[1] + 0.2, CEIL - 0.3, bl[2] + 0.2, COOL, M.Neon, c, nc())
        point(bulb, COOL, bl[3], 10, false)
    end
    -- (v3.1) finish the bigger room: a utility sink + a mop on the east wall
    -- south of the breaker, a paint-can shelf by the door, BOH skirting
    local skx0, skx1, skz0, skz1 = HALL_X1 - 1.6, HALL_X1 - 0.05, 38.4, 40.4
    box("MopSink", skx0, FLOOR, skz0, skx1, FLOOR + 2.6, skz1, rgb(200, 204, 210), M.Metal, c)
    box("MopSinkBasin", skx0 + 0.15, FLOOR + 2.3, skz0 + 0.15, skx1 - 0.15, FLOOR + 2.62, skz1 - 0.15, rgb(120, 124, 130), M.Metal, c, nc())
    bar("Faucet", Vector3.new(skx1 - 0.2, FLOOR + 2.6, (skz0 + skz1) / 2), Vector3.new(skx1 - 0.2, FLOOR + 3.6, (skz0 + skz1) / 2),
        0.12, STEEL_LT, M.Metal, c, nc())
    bar("Mop", Vector3.new(skx0 + 0.3, FLOOR, skz1 + 0.4), Vector3.new(skx1 - 0.1, FLOOR + 5.2, skz1 + 0.2), 0.12,
        WALNUT, M.Wood, c, nc())
    box("PaintShelf", HALL_X1 - 1, FLOOR, CLOSET_Z0 + 0.1, HALL_X1 - 0.05, FLOOR + 3.4, CLOSET_Z0 + 1.3, STEEL_LT, M.Metal, c)
    for k = 0, 2 do
        vcyl("PaintCan", Vector3.new(HALL_X1 - 0.55, FLOOR + 3.6, CLOSET_Z0 + 0.4 + k * 0.35), 0.32, 0.4,
            ({ rgb(230, 57, 70), rgb(240, 240, 232), rgb(33, 158, 188) })[k + 1], M.Metal, c, nc())
    end
    box("Skirting", HALL_X0, FLOOR, IZ1 - 0.12, HALL_X1, FLOOR + 0.6, IZ1, BOH_DARK, M.Plaster, c, nc())

    -- (v3.0) 🤫 SECRET STASH (hidden: ~1 run in 20): a loose floor tile just
    -- inside the closet door is propped up — someone's rainy-day pouch is
    -- under it. Everything here is the visual, so on a normal run the floor
    -- just looks like floor.
    local st = Instance.new("Model")
    st.Name = "SecretStash"
    st.Parent = c
    local tx, tz = -63.5, 37.6          -- (v3.1) west half of the bigger closet, off the breaker
    box("StashHole", tx - 0.6, FLOOR + 0.004, tz - 0.6, tx + 0.6, FLOOR + 0.02, tz + 0.6, rgb(8, 8, 10), M.Concrete, st, nc())
    part({ Name = "LooseTile", Size = Vector3.new(1.3, 0.1, 1.3),
        CFrame = CFrame.new(tx, FLOOR + 0.62, tz - 0.62) * CFrame.Angles(math.rad(70), 0, 0),
        Color = rgb(132, 128, 124), Material = M.Slate, CanCollide = false }, st)
    part({ Name = "Pouch", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.36, 0.6),
        Position = Vector3.new(tx - 0.15, FLOOR + 0.16, tz + 0.1), Color = rgb(70, 20, 60), Material = M.Fabric,
        CanCollide = false, CastShadow = false }, st)
    bar("PouchString", Vector3.new(tx - 0.3, FLOOR + 0.3, tz + 0.05), Vector3.new(tx + 0.05, FLOOR + 0.25, tz + 0.3), 0.03,
        GOLD, M.Fabric, st, nc())
    box("CashRoll", tx + 0.12, FLOOR + 0.02, tz - 0.3, tx + 0.5, FLOOR + 0.2, tz + 0.1, rgb(118, 160, 108), M.Fabric, st, nc())
    box("CashBand", tx + 0.28, FLOOR + 0.02, tz - 0.31, tx + 0.34, FLOOR + 0.21, tz + 0.11, rgb(236, 206, 90), M.Fabric, st, nc())
    stone(st, Vector3.new(tx - 0.3, FLOOR + 0.1, tz + 0.4), 0.16, STONE.diamond)
    stone(st, Vector3.new(tx + 0.2, FLOOR + 0.08, tz + 0.35), 0.12, STONE.pink)
    point(lightAnchor("StashGlint", Vector3.new(tx, FLOOR + 0.5, tz), st), rgb(255, 236, 200), 0.5, 3, false)
    local sstand = Vector3.new(tx, FLOOR + 3, tz - 1.2)
    table.insert(loot, { kind = "SecretStash", cframe = CFrame.lookAt(sstand, Vector3.new(tx, sstand.Y, tz)),
        visual = st, hidden = true, pool = "backhall", inVault = false })

    return breaker, CFrame.new(-59.8, FLOOR + 2.95, IZ1 - 0.75), inside
end

function JewelryBuilder:_office(f, loot)
    -- (v3.1 ROOMY BACK) back office x -56..-47, z 17..29 + the annex bay
    -- x -47..-41, z 23..29 (was 9 x 8). The crew walks through here from the
    -- break room to the hall. E prompts >= 6 apart: the watch cabinet (north
    -- wall, west) · the keycard spot on the filing cabinets (north wall, east)
    -- · the appraisal tray on the desk in the bay.
    local o = Instance.new("Folder")
    o.Name = "Office"
    o.Parent = f
    local BAY_Z0 = ANNEX_Z0 + 1                       -- 23
    local dx0, dx1, dz0, dz1 = AIX1 - 2.6, AIX1, BAY_Z0 + 0.4, OB_Z0 - 1.4   -- desk in the bay, against the annex wall
    local topY = FLOOR + 2.9

    -- (v2.0.2) walls: bottle-green painted wainscot + white rail + striped
    -- wallpaper on the north wall, the store's old east wall and the bay's east wall
    local WAINSCOT = rgb(34, 70, 58)
    local RAIL = rgb(226, 222, 210)
    box("Wainscot", EC_X0, FLOOR, BOH_Z0, IX1, FLOOR + 4, BOH_Z0 + 0.08, WAINSCOT, M.Plaster, o, nc())
    box("ChairRail", EC_X0, FLOOR + 4, BOH_Z0, IX1, FLOOR + 4.25, BOH_Z0 + 0.14, RAIL, M.Plaster, o, nc())
    local wpN = box("Wallpaper", EC_X0, FLOOR + 4.25, BOH_Z0, IX1, CEIL, BOH_Z0 + 0.05, rgb(214, 196, 160), M.Fabric, o, nc())
    wallpaper(wpN, Enum.NormalId.Back, rgb(206, 190, 152), rgb(150, 110, 70), 7)
    for _, w in ipairs({ { IX1, BOH_Z0, BAY_Z0 }, { AIX1, BAY_Z0, OB_Z0 } }) do
        box("Wainscot", w[1] - 0.08, FLOOR, w[2], w[1], FLOOR + 4, w[3], WAINSCOT, M.Plaster, o, nc())
        box("ChairRail", w[1] - 0.14, FLOOR + 4, w[2], w[1], FLOOR + 4.25, w[3], RAIL, M.Plaster, o, nc())
        local wpE = box("Wallpaper", w[1] - 0.05, FLOOR + 4.25, w[2], w[1], CEIL, w[3], rgb(214, 196, 160), M.Fabric, o, nc())
        wallpaper(wpE, Enum.NormalId.Left, rgb(206, 190, 152), rgb(150, 110, 70), math.max(2, math.floor((w[3] - w[2]) / 1.2)))
    end
    -- the bay's north face (the annex's north wall, inside)
    box("Wainscot", IX1, FLOOR, BAY_Z0, AIX1, FLOOR + 4, BAY_Z0 + 0.08, WAINSCOT, M.Plaster, o, nc())
    box("ChairRail", IX1, FLOOR + 4, BAY_Z0, AIX1, FLOOR + 4.25, BAY_Z0 + 0.14, RAIL, M.Plaster, o, nc())
    box("WallLining", IX1, FLOOR + 4.25, BAY_Z0, AIX1, CEIL, BAY_Z0 + 0.05, rgb(206, 190, 152), M.Plaster, o, nc())
    box("Skirting", EC_X0, FLOOR, OB_Z0 - 0.1, OB_DOOR_X0, FLOOR + 0.6, OB_Z0, rgb(26, 30, 28), M.Plaster, o, nc())
    box("Skirting", OB_DOOR_X1, FLOOR, OB_Z0 - 0.1, AIX1, FLOOR + 0.6, OB_Z0, rgb(26, 30, 28), M.Plaster, o, nc())
    -- a rug in the middle of the main room
    box("Rug", -54.6, FLOOR, 20.4, -48.6, FLOOR + 0.04, 27.2, rgb(40, 58, 52), M.Fabric, o, nc({ CastShadow = false }))
    box("RugBorder", -54.3, FLOOR + 0.04, 20.7, -48.9, FLOOR + 0.05, 26.9, rgb(196, 160, 90), M.Fabric, o,
        nc({ CastShadow = false, Transparency = 0.55 }))

    -- desk in the bay, against the annex's east wall (satin walnut)
    box("DeskTop", dx0, topY - 0.25, dz0, dx1, topY, dz1, WALNUT, M.Wood, o)
    box("DeskSide", dx0 + 0.05, FLOOR, dz0, dx1, topY - 0.25, dz0 + 0.2, WALNUT, M.Wood, o)
    box("DeskSide", dx0 + 0.05, FLOOR, dz1 - 0.2, dx1, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskModesty", dx0 + 0.05, FLOOR + 0.8, dz0, dx0 + 0.25, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskBlotter", dx0 + 0.4, topY, dz0 + 1.6, dx1 - 0.3, topY + 0.03, dz1 - 0.4, rgb(30, 60, 44), M.Fabric, o, nc())
    point(lightAnchor("MonitorGlow", Vector3.new(dx0 + 1, topY + 1.2, (dz0 + dz1) / 2 + 0.6), o), rgb(150, 200, 255), 0.6, 8)

    -- banker's lamp: the office's key light (shadows on), everything else stays dim
    local lx, lz = dx1 - 0.7, dz1 - 0.55
    box("LampBase", lx - 0.3, topY, lz - 0.2, lx + 0.3, topY + 0.12, lz + 0.2, BRASS, M.Metal, o, nc())
    bar("LampStem", Vector3.new(lx, topY + 0.12, lz), Vector3.new(lx, topY + 1.1, lz), 0.08, BRASS, M.Metal, o, nc())
    local shade = box("LampShade", lx - 0.45, topY + 1.05, lz - 0.2, lx + 0.45, topY + 1.35, lz + 0.2, rgb(20, 110, 60),
        M.Glass, o, nc({ Transparency = 0.1 }))
    spot(shade, Enum.NormalId.Bottom, rgb(255, 214, 160), 1.8, 10, 80, true)

    -- CCTV monitor on the bay wall above the desk
    local mon = box("CctvMonitor", AIX1 - 0.25, FLOOR + 5, dz0 + 0.8, AIX1, FLOOR + 7.4, dz1 - 0.3, rgb(20, 20, 24), M.Metal, o)
    local mg = surface(mon, Enum.NormalId.Left, 50, 1.1)
    local feeds = { "CAM 1 · SHOWROOM", "CAM 2 · SAFE ROOM", "CAM 3 · —", "NO SIGNAL" }
    for k, label in ipairs(feeds) do
        local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
        local cell = frame({ Size = UDim2.fromScale(0.47, 0.44), Position = UDim2.fromScale(0.02 + col * 0.49, 0.04 + row * 0.49),
            BackgroundColor3 = rgb(18, 34, 40) }, mg)
        text({ Text = label, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05),
            TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = rgb(140, 220, 200) }, cell)
    end

    -- filing cabinets along the north wall, east end (cover). The keycard can
    -- turn up on top of the east one (refs.keycardSpots).
    local cabTop = FLOOR + 4.6
    for k = 0, 1 do
        local x0 = IX1 - 3.9 + k * 1.95
        local cab = box("FilingCabinet", x0, FLOOR, BOH_Z0, x0 + 1.8, cabTop, BOH_Z0 + 1.6, rgb(120, 126, 136), M.Metal, o)
        local cg = lit(surface(cab, Enum.NormalId.Back, 30, 1))
        for d = 0, 2 do
            frame({ Size = UDim2.fromScale(0.9, 0.28), Position = UDim2.fromScale(0.05, 0.04 + d * 0.32),
                BackgroundColor3 = rgb(140, 146, 156) }, cg)
            frame({ Size = UDim2.fromScale(0.3, 0.04), Position = UDim2.fromScale(0.35, 0.16 + d * 0.32),
                BackgroundColor3 = STEEL_DK }, cg)
        end
    end
    local keySpot = CFrame.new(IX1 - 1.05, cabTop, BOH_Z0 + 0.8)
    -- cork board with notes (sits proud of the wallpaper), over the watch cabinet
    local cork = box("CorkBoard", -55.7, 5.6, BOH_Z0 + 0.05, -52.2, 8.6, BOH_Z0 + 0.17, rgb(180, 140, 96), M.Wood, o, nc())
    local ng = lit(surface(cork, Enum.NormalId.Back, 40, 1))
    for k, col in ipairs({ rgb(250, 240, 140), rgb(250, 196, 220), rgb(170, 230, 255), rgb(250, 240, 140) }) do
        frame({ Size = UDim2.fromScale(0.2, 0.3), Position = UDim2.fromScale(0.06 + (k - 1) * 0.23, 0.12 + (k % 2) * 0.35),
            Rotation = (k % 2 == 0) and 6 or -5, BackgroundColor3 = col }, ng)
    end

    -- the ceiling tube is dimmed right down: the desk lamp does the work
    tubeLight(o, -51.5, 22.5, true, 0.35, 12, WARM)

    local METAL_DK = { rgb(36, 38, 44), M.Metal, 0.05 }
    prop("furniture", "computerScreen", Vector3.new(dx1 - 0.9, topY, (dz0 + dz1) / 2 + 0.6), Vector3.new(-1, 0, 0), o,
        { main = METAL_DK, byName = { screen = { rgb(40, 90, 140), M.Glass, 0.2 } } })
    prop("furniture", "chairDesk", Vector3.new(dx0 - 1.3, FLOOR, (dz0 + dz1) / 2 + 1), Vector3.new(1, 0, 0), o,
        { main = { rgb(28, 26, 30), M.Fabric }, accent = { rgb(150, 154, 162), M.Metal } }, { collide = false })
    prop("furniture", "pottedPlant", Vector3.new(EC_X0 + 0.9, FLOOR, OB_Z0 - 1), Vector3.new(1, 0, 0), o,
        { main = { rgb(52, 120, 70), M.Grass }, accent = { rgb(176, 96, 64), M.Concrete },
          byName = { pot = { rgb(176, 96, 64), M.Concrete }, leaf = { rgb(52, 120, 70), M.Grass }, plant = { rgb(52, 120, 70), M.Grass } } },
        { collide = false })
    prop("furniture", "trashcan", Vector3.new(dx0 - 0.6, FLOOR, dz1 + 0.6), Vector3.new(1, 0, 0), o,
        { main = { rgb(60, 64, 72), M.Metal, 0.05 } }, { collide = false })

    -- (v3.0) LOOT 1: the owner's watch collection — a walnut cabinet with a
    -- glass top against the north wall (west end), six watches on velvet pillows
    local wx0, wx1, wz0, wz1 = -55.6, -53.4, BOH_Z0 + 0.05, BOH_Z0 + 1.15
    local wmid = (wx0 + wx1) / 2
    local wTop = FLOOR + 2.9
    box("WatchCabinet", wx0, FLOOR, wz0, wx1, wTop - 0.1, wz1, WALNUT, M.Wood, o)
    box("WatchCabinetKick", wx0 + 0.05, FLOOR, wz1, wx1 - 0.05, FLOOR + 0.3, wz1 + 0.03, BRASS, M.Metal, o, nc())
    box("WatchCabinetRim", wx0 - 0.03, wTop - 0.1, wz0 - 0.03, wx1 + 0.03, wTop, wz1 + 0.03, BRASS, M.Metal, o, { Reflectance = 0.2 })
    box("WatchPad", wx0 + 0.08, wTop, wz0 + 0.08, wx1 - 0.08, wTop + 0.04, wz1 - 0.08, BLACK_VELVET, M.Fabric, o, nc())
    box("WatchGlass", wx0, wTop, wz0, wx1, wTop + 0.75, wz1, rgb(214, 236, 246), M.Glass, o,
        { Transparency = 0.7, Reflectance = 0.25, CastShadow = false })
    box("WatchLock", wmid - 0.1, wTop - 0.08, wz1 + 0.03, wmid + 0.1, wTop + 0.12, wz1 + 0.06, BRASS, M.Metal, o, nc())
    local plaque = box("WatchPlaque", wmid - 0.65, FLOOR + 1.8, wz1 + 0.03, wmid + 0.65, FLOOR + 2.2, wz1 + 0.05, BRASS, M.Metal, o, nc())
    lit(printOn(plaque, Enum.NormalId.Back, "PRIVATE COLLECTION", rgb(60, 36, 14), UITheme.F.display, 80, 1).Parent)
    point(lightAnchor("WatchCaseGlow", Vector3.new(wmid, wTop + 0.6, (wz0 + wz1) / 2), o), rgb(255, 236, 214), 0.7, 4, false)
    local wv = Instance.new("Model")
    wv.Name = "Watches"
    wv.Parent = o
    local looks = {
        -- { case metal, dial colour, strap colour }
        { GOLD, rgb(250, 246, 236), GOLD },            { PLATINUM, rgb(20, 40, 90), PLATINUM },
        { ROSE, rgb(30, 26, 30), rgb(70, 40, 26) },    { PLATINUM, rgb(20, 80, 60), PLATINUM },
        { GOLD, rgb(20, 20, 24), rgb(30, 24, 20) },    { PLATINUM, rgb(236, 238, 242), rgb(20, 30, 70) },
    }
    for k, lk in ipairs(looks) do
        local col, row = (k - 1) % 3, math.floor((k - 1) / 3)
        local c = Vector3.new(wx0 + 0.42 + col * 0.68, wTop + 0.04, wz0 + 0.33 + row * 0.46)
        box("WatchPillow", c.X - 0.2, c.Y, c.Z - 0.13, c.X + 0.2, c.Y + 0.16, c.Z + 0.13, rgb(240, 232, 220), M.Fabric, wv, nc())
        -- strap wrapped round the pillow (two ends), then the case, dial and crown
        box("Strap", c.X - 0.21, c.Y + 0.02, c.Z - 0.07, c.X + 0.21, c.Y + 0.17, c.Z + 0.07, lk[3],
            (lk[3] == GOLD or lk[3] == PLATINUM) and M.Metal or M.Fabric, wv, nc({ Reflectance = 0.2 }))
        vcyl("WatchCase", c + Vector3.new(0, 0.2, 0), 0.3, 0.07, lk[1], M.Metal, wv, nc({ Reflectance = 0.4, CastShadow = false }))
        vcyl("Dial", c + Vector3.new(0, 0.24, 0), 0.23, 0.02, lk[2], M.Glass, wv, nc({ Reflectance = 0.3, CastShadow = false }))
        bar("Hand", c + Vector3.new(0, 0.255, 0), c + Vector3.new(0.07, 0.255, -0.04), 0.015, lk[1], M.Metal, wv, nc())
        bar("Hand", c + Vector3.new(0, 0.255, 0), c + Vector3.new(-0.03, 0.255, -0.09), 0.015, lk[1], M.Metal, wv, nc())
        box("Crown", c.X + 0.15, c.Y + 0.18, c.Z - 0.02, c.X + 0.19, c.Y + 0.22, c.Z + 0.02, lk[1], M.Metal, wv, nc())
    end
    local wstand = Vector3.new(wmid, FLOOR + 3, 19.3)
    table.insert(loot, { kind = "Watch", cframe = CFrame.lookAt(wstand, Vector3.new(wmid, wstand.Y, (wz0 + wz1) / 2)),
        visual = wv, pool = "office", inVault = false })

    -- (v3.0) LOOT 2: the jeweller's appraisal tray on the desk — loose stones,
    -- a loupe, tweezers and an open diamond paper (north end of the desk)
    local ax0, ax1, az0, az1 = dx0 + 0.6, dx0 + 1.5, dz0 + 0.3, dz0 + 1.2
    box("AppraisalTray", ax0, topY, az0, ax1, topY + 0.05, az1, BLACK_VELVET, M.Fabric, o, nc())
    box("TrayRim", ax0 - 0.03, topY, az0 - 0.03, ax1 + 0.03, topY + 0.07, az0, BRASS, M.Metal, o, nc())
    local tv = Instance.new("Model")
    tv.Name = "LooseStones"
    tv.Parent = o
    local cols = { STONE.diamond, STONE.diamond, STONE.sapphire, STONE.diamond, STONE.ruby, STONE.diamond,
        STONE.emerald, STONE.diamond, STONE.pink }
    for k = 0, 8 do
        local gx = ax0 + 0.18 + (k % 3) * 0.27
        local gz = az0 + 0.18 + math.floor(k / 3) * 0.27
        stone(tv, Vector3.new(gx, topY + 0.1, gz), (k % 4 == 0) and 0.17 or 0.12, cols[k + 1])
    end
    box("DiamondPaper", ax0 - 0.05, topY + 0.03, az1 + 0.05, ax0 + 0.45, topY + 0.05, az1 + 0.47, rgb(250, 250, 246), M.Fabric, tv, nc())
    box("PaperLining", ax0, topY + 0.05, az1 + 0.1, ax0 + 0.4, topY + 0.055, az1 + 0.42, rgb(120, 170, 230), M.Fabric, tv, nc())
    stone(tv, Vector3.new(ax0 + 0.2, topY + 0.11, az1 + 0.26), 0.15, STONE.diamond)
    vcyl("Loupe", Vector3.new(ax1 + 0.35, topY + 0.13, az0 + 0.2), 0.22, 0.2, rgb(20, 20, 24), M.Metal, o, nc())
    vcyl("LoupeLens", Vector3.new(ax1 + 0.35, topY + 0.24, az0 + 0.2), 0.18, 0.02, rgb(200, 230, 250), M.Glass, o,
        nc({ Transparency = 0.3, Reflectance = 0.4 }))
    bar("Tweezers", Vector3.new(ax1 + 0.2, topY + 0.06, az1 + 0.1), Vector3.new(ax1 + 0.6, topY + 0.06, az1 + 0.5), 0.03,
        STEEL_LT, M.Metal, o, nc())
    local tstand = Vector3.new(dx0 - 2.2, FLOOR + 3, (az0 + az1) / 2)
    table.insert(loot, { kind = "Jewels", cframe = CFrame.lookAt(tstand, Vector3.new(ax0, tstand.Y, (az0 + az1) / 2)),
        visual = tv, pool = "office", inVault = false })

    return keySpot
end

-- 🚪 the staff break room + the sneaky yard door (sneakIn lives here).
-- (v3.1 ROOMY BACK) x -56..-41, z 30..43 (15 x 13, was 9 x 8): kitchenette on
-- the west wall, a table in the middle, vending machine + crawl vent on the
-- south wall, the staff door in the annex's east wall.
function JewelryBuilder:_breakRoom(f, refs)
    local b = Instance.new("Folder")
    b.Name = "BreakRoom"
    b.Parent = f

    -- mint wainscot on the west + south + east walls, soft grey-green paint above
    local MINT_W = rgb(150, 225, 200)
    local PAINT = rgb(150, 160, 156)
    box("Wainscot", EC_X0, FLOOR, BREAK_Z0, EC_X0 + 0.1, FLOOR + 4, IZ1, MINT_W, M.Plaster, b, nc())
    box("Wainscot", EC_X0, FLOOR, IZ1 - 0.1, AIX1, FLOOR + 4, IZ1, MINT_W, M.Plaster, b, nc())
    box("WallLining", EC_X0 + 0.1, FLOOR + 4, IZ1 - 0.06, AIX1, CEIL, IZ1, PAINT, M.Plaster, b, nc())
    for _, zz in ipairs({ { BREAK_Z0, SIDE_Z0 }, { SIDE_Z1, IZ1 } }) do
        box("Wainscot", AIX1 - 0.1, FLOOR, zz[1], AIX1, FLOOR + 4, zz[2], MINT_W, M.Plaster, b, nc())
        box("WallLining", AIX1 - 0.06, FLOOR + 4, zz[1], AIX1, CEIL, zz[2], PAINT, M.Plaster, b, nc())
    end
    box("WallLining", AIX1 - 0.06, DOOR_H, SIDE_Z0, AIX1, CEIL, SIDE_Z1, PAINT, M.Plaster, b, nc())
    box("WainscotCap", EC_X0, FLOOR + 4, IZ1 - 0.16, AIX1, FLOOR + 4.2, IZ1, rgb(40, 110, 100), M.Plaster, b, nc())

    -- fridge in the north-west corner
    local fz0, fz1 = BREAK_Z0 + 0.2, BREAK_Z0 + 2.6
    box("Fridge", EC_X0, FLOOR, fz0, EC_X0 + 2.3, FLOOR + 7.4, fz1, rgb(236, 238, 240), M.Metal, b)
    box("FridgeSplit", EC_X0 + 2.3, FLOOR + 4.8, fz0, EC_X0 + 2.34, FLOOR + 4.9, fz1, STEEL, M.Metal, b, nc())
    bar("FridgeHandle", Vector3.new(EC_X0 + 2.45, FLOOR + 5.2, fz1 - 0.35), Vector3.new(EC_X0 + 2.45, FLOOR + 6.8, fz1 - 0.35),
        0.12, STEEL_LT, M.Metal, b, nc())
    bar("FridgeHandle", Vector3.new(EC_X0 + 2.45, FLOOR + 2.2, fz1 - 0.35), Vector3.new(EC_X0 + 2.45, FLOOR + 4.4, fz1 - 0.35),
        0.12, STEEL_LT, M.Metal, b, nc())
    local note = box("FridgeNote", EC_X0 + 2.3, FLOOR + 5.6, fz0 + 0.5, EC_X0 + 2.32, FLOOR + 6.6, fz0 + 1.5,
        rgb(250, 240, 140), M.Fabric, b, nc())
    local ng = lit(surface(note, Enum.NormalId.Right, 60, 1))
    text({ Text = "DON'T EAT\nMY LUNCH\n- TONY", Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextColor3 = rgb(40, 40, 60) }, ng)

    -- kitchenette counter along the west wall
    local kz0, kz1 = 34.6, IZ1 - 0.1
    local topY = FLOOR + 3.3
    -- (v2.0.2) painted cabinets (not stripy wood), door seams, a white tile splashback
    local CAB = rgb(70, 140, 134)
    box("Kitchenette", EC_X0, FLOOR, kz0, EC_X0 + 1.9, topY - 0.2, kz1, CAB, M.Plaster, b)
    box("KitchenetteTop", EC_X0, topY - 0.2, kz0, EC_X0 + 2.05, topY, kz1, rgb(236, 232, 226), M.Marble, b)
    box("UpperCabinet", EC_X0, FLOOR + 6.2, kz0, EC_X0 + 1.3, FLOOR + 8.8, kz1, CAB, M.Plaster, b)
    for sz = kz0 + 1.7, kz1 - 0.5, 1.7 do
        box("CabinetSeam", EC_X0 + 1.9, FLOOR + 0.3, sz - 0.04, EC_X0 + 1.93, topY - 0.4, sz + 0.04, rgb(40, 90, 86), M.Plaster, b, nc())
        box("CabinetSeam", EC_X0 + 1.3, FLOOR + 6.4, sz - 0.04, EC_X0 + 1.33, FLOOR + 8.6, sz + 0.04, rgb(40, 90, 86), M.Plaster, b, nc())
    end
    box("Sink", EC_X0 + 0.5, topY - 0.25, 37.6, EC_X0 + 1.7, topY + 0.01, 38.9, rgb(180, 186, 194), M.Metal, b, nc())
    bar("SinkTap", Vector3.new(EC_X0 + 0.3, topY, 38.25), Vector3.new(EC_X0 + 0.3, topY + 0.8, 38.25), 0.1, STEEL_LT, M.Metal, b, nc())
    box("Splashback", EC_X0, topY, kz0, EC_X0 + 0.06, FLOOR + 6.2, kz1, rgb(240, 240, 234), M.CeramicTiles, b, nc())
    box("Skirting", EC_X0 + 0.1, FLOOR, IZ1 - 0.16, AIX1, FLOOR + 0.6, IZ1 - 0.1, rgb(40, 70, 66), M.Plaster, b, nc())

    -- the table: a diner table + two chairs in the middle of the room (cover
    -- between the office door and the kitchenette; the drop-in stays clear)
    local tx0, tx1, tz0, tz1 = -51.4, -48.4, 35, 38
    local tcx, tcz = (tx0 + tx1) / 2, (tz0 + tz1) / 2
    local TT = rgb(226, 90, 90)
    box("TableTop", tx0, FLOOR + 2.7, tz0, tx1, FLOOR + 2.95, tz1, TT, M.Plastic, b)
    box("TableEdge", tx0 - 0.05, FLOOR + 2.62, tz0 - 0.05, tx1 + 0.05, FLOOR + 2.72, tz1 + 0.05, STEEL_LT, M.Metal, b, nc())
    bar("TableLeg", Vector3.new((tx0 + tx1) / 2, FLOOR, (tz0 + tz1) / 2), Vector3.new((tx0 + tx1) / 2, FLOOR + 2.62, (tz0 + tz1) / 2),
        0.3, STEEL_LT, M.Metal, b)
    box("TableFoot", (tx0 + tx1) / 2 - 0.8, FLOOR, (tz0 + tz1) / 2 - 0.8, (tx0 + tx1) / 2 + 0.8, FLOOR + 0.1,
        (tz0 + tz1) / 2 + 0.8, STEEL_LT, M.Metal, b, nc())
    for _, cz in ipairs({ tz0 - 1.1, tz1 + 1.1 }) do
        local cx = (tx0 + tx1) / 2
        box("ChairSeat", cx - 0.7, FLOOR + 1.6, cz - 0.6, cx + 0.7, FLOOR + 1.85, cz + 0.6, rgb(40, 110, 100), M.Fabric, b, nc())
        local back = cz < tz0 and cz - 0.6 or cz + 0.45
        box("ChairBack", cx - 0.7, FLOOR + 1.85, back, cx + 0.7, FLOOR + 3.6, back + 0.15, rgb(40, 110, 100), M.Fabric, b, nc())
        bar("ChairLeg", Vector3.new(cx, FLOOR, cz), Vector3.new(cx, FLOOR + 1.6, cz), 0.14, STEEL_LT, M.Metal, b, nc())
    end
    -- a napkin holder + two mugs on the table
    box("NapkinHolder", tcx - 0.3, FLOOR + 2.95, tcz - 0.2, tcx + 0.3, FLOOR + 3.4, tcz + 0.2, STEEL_LT, M.Metal, b, nc())
    for k, m in ipairs({ { tcx - 0.8, tcz - 0.8 }, { tcx + 0.9, tcz + 0.7 } }) do
        vcyl("Mug", Vector3.new(m[1], FLOOR + 3.15, m[2]), 0.35, 0.4, k == 1 and HOT_PINK or CYAN, M.Plastic, b, nc())
    end

    -- vending machine against the south wall — glowing front, readable at a glance
    local vx0, vx1, vz0 = -53, -50.6, IZ1 - 2.2
    box("VendingMachine", vx0, FLOOR, vz0, vx1, FLOOR + 7.2, IZ1, rgb(200, 30, 60), M.Metal, b)
    local vw = box("VendingWindow", vx0 + 0.25, FLOOR + 2.4, vz0 - 0.05, vx1 - 0.7, FLOOR + 6.6, vz0, rgb(200, 230, 255),
        M.Glass, b, nc({ Transparency = 0.35 }))
    local vg = surface(vw, Enum.NormalId.Front, 30, 1.4)
    for r = 0, 4 do
        for col = 0, 3 do
            frame({ Size = UDim2.fromScale(0.18, 0.12), Position = UDim2.fromScale(0.05 + col * 0.24, 0.05 + r * 0.19),
                BackgroundColor3 = GEM_COLORS[((r + col) % 3) + 1] }, vg)
        end
    end
    point(vw, rgb(200, 230, 255), 0.7, 9, false)
    box("VendingSlot", vx0 + 0.4, FLOOR + 0.6, vz0 - 0.05, vx1 - 0.9, FLOOR + 1.4, vz0, STEEL_DK, M.Metal, b, nc())
    -- a water cooler beside it
    box("WaterCooler", vx1 + 0.5, FLOOR, IZ1 - 1.2, vx1 + 1.6, FLOOR + 3.4, IZ1 - 0.1, rgb(236, 238, 240), M.Plastic, b)
    part({ Name = "WaterBottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 0.9, 0.9),
        CFrame = CFrame.new(vx1 + 1.05, FLOOR + 4.1, IZ1 - 0.65) * CFrame.Angles(0, 0, math.rad(90)),
        Color = rgb(150, 200, 240), Material = M.Glass, Transparency = 0.3, CanCollide = false }, b)

    -- crawl vent, break-room end: low on the south wall, east of the vending machine
    local ventX = -46.5
    box("VentFrame", ventX - 1.4, FLOOR, IZ1 - 0.2, ventX + 1.4, FLOOR + 2.7, IZ1, STEEL_LT, M.Metal, b, nc())
    local vent = facingPart("DD_VentBreakRoom", Vector3.new(ventX, FLOOR + 1.3, IZ1 - 0.25), Vector3.new(2.4, 2.4, 0.12),
        Vector3.new(0, 0, -1), rgb(60, 62, 70), M.DiamondPlate, b)
    local ventG = lit(surface(vent, Enum.NormalId.Front, 30, 1))
    for k = 0, 5 do
        frame({ Size = UDim2.fromScale(0.9, 0.06), Position = UDim2.fromScale(0.05, 0.1 + k * 0.14),
            BackgroundColor3 = rgb(20, 20, 24) }, ventG)
    end

    -- staff notice board + clock over the kitchenette
    local board = box("NoticeBoard", EC_X0, FLOOR + 9.6, 36, EC_X0 + 0.12, FLOOR + 12, 40, rgb(40, 60, 70), M.Slate, b, nc())
    local bg = lit(surface(board, Enum.NormalId.Right, 40, 1))
    text({ Text = "BREAK ROOM", Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 240, 220) }, bg)
    text({ Text = "Wash your mug!", Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.5),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextColor3 = rgb(250, 196, 220) }, bg)
    local clock = part({ Name = "Clock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.6, 1.6),
        CFrame = CFrame.new(-50.7, FLOOR + 10, IZ1 - 0.08), Color = rgb(250, 250, 244), Material = M.Plastic,
        CanCollide = false }, b)
    clock.CFrame = CFrame.new(-50.7, FLOOR + 10, IZ1 - 0.08) * CFrame.Angles(0, math.rad(90), 0)
    bar("ClockHand", Vector3.new(-50.7, FLOOR + 10, IZ1 - 0.16), Vector3.new(-50.7, FLOOR + 10.6, IZ1 - 0.16), 0.06,
        rgb(30, 30, 30), M.Metal, b, nc())

    -- lights: a warm pendant over the table (the key light) + a dim tube by the door
    bar("PendantCord", Vector3.new(tcx, CEIL, tcz), Vector3.new(tcx, CEIL - 4, tcz), 0.06, STEEL_DK, M.Rubber, b, nc())
    local lamp = box("BreakLight", tcx - 0.7, CEIL - 4.6, tcz - 0.7, tcx + 0.7, CEIL - 4, tcz + 0.7, rgb(40, 110, 100), M.Metal, b, nc())
    box("BreakLightLens", tcx - 0.5, CEIL - 4.66, tcz - 0.5, tcx + 0.5, CEIL - 4.6, tcz + 0.5, WARM, M.Neon, b, nc())
    spot(lamp, Enum.NormalId.Bottom, WARM, 1.4, 14, 110, true)
    tubeLight(b, -45, 36.5, false, 0.3, 11, WARM)

    prop("furniture", "kitchenMicrowave", Vector3.new(EC_X0 + 1, topY, 35.6), Vector3.new(1, 0, 0), b,
        { main = { rgb(232, 232, 228), M.Metal, 0.05 }, accent = { rgb(30, 32, 36), M.Glass, 0.2 } })
    prop("furniture", "kitchenCoffeeMachine", Vector3.new(EC_X0 + 1, topY, 40.6), Vector3.new(1, 0, 0), b,
        { main = { rgb(26, 26, 30), M.Metal, 0.05 }, accent = { rgb(170, 174, 182), M.Metal, 0.1 } })
    prop("furniture", "coatRackStanding", Vector3.new(AIX1 - 0.8, FLOOR, BREAK_Z0 + 0.8), Vector3.new(-1, 0, 0), b,
        { main = { rgb(70, 50, 40), M.Wood } }, { collide = false })

    -- ── the staff door in the annex's east wall (open double doors onto the yard) ──
    local x = ANNEX_X1
    local STEELC = rgb(70, 74, 82)
    box("StaffDoorFrameN", x, 0, SIDE_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, SIDE_Z0, STEELC, M.Metal, b)
    box("StaffDoorFrameS", x, 0, SIDE_Z1, x + 0.25, DOOR_H + 0.3, SIDE_Z1 + 0.3, STEELC, M.Metal, b)
    box("StaffDoorFrameTop", x, DOOR_H, SIDE_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, SIDE_Z1 + 0.3, STEELC, M.Metal, b)
    -- both leaves propped open flat against the outside wall
    box("StaffDoorLeaf", x + 0.25, FLOOR, SIDE_Z0 - 3.5, x + 0.45, DOOR_H - 0.1, SIDE_Z0 - 0.3, rgb(96, 100, 110), M.DiamondPlate, b, nc())
    box("StaffDoorLeaf", x + 0.25, FLOOR, SIDE_Z1 + 0.3, x + 0.45, DOOR_H - 0.1, SIDE_Z1 + 3.5, rgb(96, 100, 110), M.DiamondPlate, b, nc())
    box("StaffDoorStep", x, 0, SIDE_Z0, x + 2, FLOOR, SIDE_Z1, rgb(150, 146, 140), M.Concrete, b)
    local plate = box("StaffDoorPlate", x + 0.25, DOOR_H + 0.6, SIDE_Z0 + 1.6, x + 0.35, DOOR_H + 1.8, SIDE_Z1 - 1.6,
        rgb(26, 26, 30), M.Metal, b)
    printOn(plate, Enum.NormalId.Right, "STAFF ONLY", rgb(240, 70, 70), UITheme.F.bold, 60, 1.3)
    local mid = (SIDE_Z0 + SIDE_Z1) / 2
    local wallLamp = box("AlleyLamp", x + 0.25, DOOR_H + 2.3, mid - 0.5, x + 0.9, DOOR_H + 2.7, mid + 0.5, STEEL_DK, M.Metal, b, nc())
    box("AlleyLampLens", x + 0.3, DOOR_H + 2.2, mid - 0.4, x + 0.85, DOOR_H + 2.3, mid + 0.4, rgb(255, 214, 150), M.Neon, b, nc())
    spot(wallLamp, Enum.NormalId.Bottom, rgb(255, 200, 140), 1.3, 16, 100, true)

    return vent
end

-- 🧱 (v2.0.2) the walled SERVICE YARD: east of the store + a strip behind it.
-- Brick walls all round (no gaps), a wide sliding vehicle gate onto Ocean
-- Drive, the getaway car parked nose-to-the-gate, dumpsters / crates / drums /
-- puddles / lamps. Replaces the open v2.0 alley (you could walk out onto lawn).
function JewelryBuilder:_yard(f, refs)
    local a = Instance.new("Folder")
    a.Name = "ServiceYard"
    a.Parent = f
    local BRICK = rgb(122, 66, 56)
    local CAP = rgb(188, 180, 170)
    local PLINTH = rgb(74, 70, 70)
    local H, T = YWALL_H, YWALL_T
    local EX0 = YARD_X1 - T                 -- inner face of the east wall (-25.6)
    local NZ1 = YARD_Z0 + T                 -- inner face of the north wall (3.2)
    local SZ0 = YARD_Z1 - T                 -- inner face of the south wall (43.4)

    -- ── ground: asphalt yard, concrete strip behind the store, concrete driveway ──
    box("YardFloor", X1, 0, YARD_Z0, EX0, 0.1, SZ0, rgb(52, 52, 58), M.Asphalt, a)
    box("Driveway", X1, 0, -1.4, GATE_X1 + 0.8, 0.1, YARD_Z0, rgb(150, 148, 142), M.Concrete, a)
    box("GateTrack", GATE_X0, 0.1, YARD_Z0 + 0.2, GATE_X1, 0.14, YARD_Z0 + 0.4, STEEL, M.Metal, a, nc())
    -- painted parking bay round the getaway spot
    local LINE = rgb(236, 196, 48)
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z - 6.2, CAR_X - 3.2, 0.12, CAR_Z + 6.4, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X + 3.2, 0.1, CAR_Z - 6.2, CAR_X + 3.4, 0.12, CAR_Z + 6.4, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z + 6.2, CAR_X + 3.4, 0.12, CAR_Z + 6.4, LINE, M.Plaster, a, nc())

    -- ── brick walls (CanCollide, meet the store walls exactly) ──
    box("YardGatePostE", GATE_X1, 0, YARD_Z0 - 0.2, GATE_X1 + 0.8, H + 1, NZ1 + 0.2, BRICK, M.Brick, a)
    box("YardWallN", GATE_X1 + 0.8, 0, YARD_Z0, EX0, H, NZ1, BRICK, M.Brick, a)
    box("YardWallE", EX0, 0, YARD_Z0, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    -- (v3.1) the back strip is gone (the store fills it): the south wall runs from
    -- the annex's east wall to the yard's east wall, flush with the store's back wall
    box("YardWallS", ANNEX_X1, 0, SZ0, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    -- concrete coping + a dark plinth on the inside faces
    box("YardCoping", GATE_X1 + 0.8, H, YARD_Z0 - 0.1, YARD_X1 + 0.1, H + 0.35, NZ1 + 0.1, CAP, M.Concrete, a)
    box("YardCoping", EX0 - 0.1, H, NZ1, YARD_X1 + 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("YardCoping", ANNEX_X1, H, SZ0 - 0.1, EX0 - 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("PostCap", GATE_X1 - 0.1, H + 1, YARD_Z0 - 0.3, GATE_X1 + 0.9, H + 1.4, NZ1 + 0.3, CAP, M.Concrete, a)
    box("Plinth", GATE_X1 + 0.8, 0.1, NZ1, EX0, 1.1, NZ1 + 0.08, PLINTH, M.Concrete, a, nc())
    box("Plinth", EX0 - 0.08, 0.1, NZ1, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())
    box("Plinth", ANNEX_X1, 0.1, SZ0 - 0.08, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())

    -- ── the vehicle gate: chain-link slider parked open along the north wall ──
    local gx0, gx1, gz, gy0, gy1 = GATE_X1 + 1.0, GATE_X1 + 9.4, NZ1 + 0.15, 0.5, 9.2
    local GATE_STEEL = rgb(150, 156, 166)
    bar("GateRail", Vector3.new(gx0, gy1, gz), Vector3.new(gx1, gy1, gz), 0.18, GATE_STEEL, M.Metal, a, nc())
    bar("GateRail", Vector3.new(gx0, gy0, gz), Vector3.new(gx1, gy0, gz), 0.18, GATE_STEEL, M.Metal, a, nc())
    for _, vx in ipairs({ gx0, (gx0 + gx1) / 2, gx1 }) do
        bar("GateStile", Vector3.new(vx, gy0, gz), Vector3.new(vx, gy1, gz), 0.18, GATE_STEEL, M.Metal, a, nc())
    end
    local mesh = box("GateMesh", gx0, gy0, gz - 0.02, gx1, gy1, gz + 0.02, GATE_STEEL, M.Metal, a,
        nc({ Transparency = 1, CastShadow = false, CanQuery = false }))
    local mg = lit(surface(mesh, Enum.NormalId.Back, 12, 1))
    local holder = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true }, mg)
    for k = -6, 14 do
        for _, rot in ipairs({ 45, -45 }) do
            frame({ Size = UDim2.new(0, 2, 2, 0), Position = UDim2.fromScale(k / 8, -0.5), Rotation = rot,
                BackgroundColor3 = GATE_STEEL }, holder)
        end
    end
    for _, wx in ipairs({ gx0 + 0.6, gx1 - 0.6 }) do
        part({ Name = "GateWheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.7, 0.7),
            CFrame = CFrame.new(wx, 0.45, gz) * CFrame.Angles(0, math.rad(90), 0),
            Color = STEEL_DK, Material = M.Metal, CanCollide = false }, a)
    end
    local plate = box("GateSign", gx0 + 2.6, 4.2, gz + 0.1, gx0 + 5.8, 5.8, gz + 0.16, rgb(236, 230, 214), M.Metal, a, nc())
    lit(printOn(plate, Enum.NormalId.Back, "KEEP CLEAR · GATE", rgb(170, 30, 40), UITheme.F.bold, 40, 1).Parent)
    -- lantern on the gate post
    local lantern = box("PostLantern", GATE_X1 + 0.1, H + 1.4, YARD_Z0 + 0.1, GATE_X1 + 0.7, H + 2.3, NZ1 - 0.1,
        STEEL_DK, M.Metal, a, nc())
    box("PostLanternGlass", GATE_X1 + 0.18, H + 1.55, YARD_Z0 + 0.18, GATE_X1 + 0.62, H + 2.15, NZ1 - 0.18,
        rgb(255, 214, 150), M.Neon, a, nc({ CastShadow = false }))
    point(lantern, rgb(255, 196, 130), 0.9, 12, false)

    -- ── lamps: the yard's key light (shadows) over the car + one on the back strip ──
    local key = box("YardLamp", EX0 - 0.7, 9.6, CAR_Z - 0.7, EX0, 10.3, CAR_Z + 0.7, STEEL_DK, M.Metal, a, nc())
    box("YardLampLens", EX0 - 0.65, 9.52, CAR_Z - 0.6, EX0 - 0.05, 9.6, CAR_Z + 0.6, rgb(255, 196, 120), M.Neon, a,
        nc({ CastShadow = false }))
    spot(key, Enum.NormalId.Bottom, rgb(255, 180, 110), 1.7, 26, 120, true)
    local back = box("YardLamp", -32.7, 9.6, SZ0 - 0.7, -31.3, 10.3, SZ0, STEEL_DK, M.Metal, a, nc())
    box("YardLampLens", -32.6, 9.52, SZ0 - 0.65, -31.4, 9.6, SZ0 - 0.05, rgb(255, 196, 120), M.Neon, a,
        nc({ CastShadow = false }))
    spot(back, Enum.NormalId.Bottom, rgb(255, 180, 110), 1.3, 18, 110, false)

    -- ── props (all hard against a wall, well clear of the car and its run to the gate) ──
    -- green dumpster on the east wall
    local dx0, dx1, dz0, dz1 = EX0 - 3.9, EX0 - 0.3, 20, 23.8
    box("Dumpster", dx0, 0.4, dz0, dx1, 4.2, dz1, rgb(40, 110, 70), M.Metal, a)
    box("DumpsterLid", dx0 - 0.1, 4.2, dz0 - 0.1, dx1 + 0.1, 4.45, dz1 + 0.1, rgb(30, 80, 52), M.Metal, a)
    box("DumpsterSkid", dx0 + 0.2, 0.1, dz0 + 0.2, dx1 - 0.2, 0.4, dz1 - 0.2, STEEL_DK, M.Metal, a)
    local dl = box("DumpsterLabel", dx0 - 0.05, 1.6, dz0 + 1, dx0, 2.8, dz1 - 1, rgb(40, 110, 70), M.Metal, a, nc())
    lit(printOn(dl, Enum.NormalId.Left, "NO DUMPING", rgb(236, 236, 230), UITheme.F.bold, 40, 1).Parent)
    for k = 0, 2 do
        part({ Name = "BinBag", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.3, 1.5),
            Position = Vector3.new(EX0 - 1.1 - (k % 2) * 1.2, 0.75, dz1 + 1 + k * 1.1), Color = rgb(24, 24, 28),
            Material = M.Rubber }, a)
    end
    -- blue recycling dumpster against the south wall (v3.1: was behind the store)
    local rx0, rx1 = -37.4, -33.6
    box("Dumpster", rx0, 0.4, SZ0 - 3.8, rx1, 4.2, SZ0 - 0.3, rgb(34, 84, 150), M.Metal, a)
    box("DumpsterLid", rx0 - 0.1, 4.2, SZ0 - 3.9, rx1 + 0.1, 4.45, SZ0 - 0.2, rgb(24, 60, 110), M.Metal, a)
    box("DumpsterSkid", rx0 + 0.2, 0.1, SZ0 - 3.6, rx1 - 0.2, 0.4, SZ0 - 0.5, STEEL_DK, M.Metal, a)
    -- crates stacked in the far corner + two pallets leaning on the wall
    local cx, cz = EX0 - 2.6, SZ0 - 2.6
    box("Crate", cx - 1.1, 0.1, cz - 1.1, cx + 1.1, 2.3, cz + 1.1, rgb(150, 110, 70), M.WoodPlanks, a)
    box("Crate", cx - 3.5, 0.1, cz - 0.9, cx - 1.3, 2.3, cz + 1.3, rgb(140, 102, 64), M.WoodPlanks, a)
    box("Crate", cx - 0.9, 2.3, cz - 0.9, cx + 0.9, 4.1, cz + 0.9, rgb(160, 120, 78), M.WoodPlanks, a)
    -- oil drums against the east wall (v3.1: were on the back strip)
    for k, d in ipairs({ { -27, 33 }, { -28.4, 34.3 }, { -26.8, 35.6 } }) do
        part({ Name = "Drum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 1.6, 1.6),
            CFrame = CFrame.new(d[1], 1.4, d[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = (k == 2) and rgb(200, 60, 40) or rgb(40, 90, 150), Material = M.Metal }, a)
    end
    -- AC condenser humming against the east wall (v3.1: was on the back strip)
    box("Condenser", EX0 - 2.3, 0.1, 36.7, EX0, 3.1, 39.4, rgb(190, 192, 188), M.Metal, a)
    part({ Name = "CondenserFan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.9, 1.9),
        CFrame = CFrame.new(EX0 - 1.15, 3.12, 38.05) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STEEL_DK, Material = M.DiamondPlate, CanCollide = false }, a)
    bar("CondenserPipe", Vector3.new(EX0 - 0.2, 2.4, 37), Vector3.new(EX0 - 0.2, 9, 37), 0.2, STEEL_LT, M.Metal, a, nc())
    -- flattened boxes leaning on the east wall
    part({ Name = "FlatBoxes", Size = Vector3.new(0.3, 3.4, 2.6),
        CFrame = CFrame.new(EX0 - 0.5, 1.8, 30) * CFrame.Angles(0, 0, math.rad(10)),
        Color = rgb(186, 150, 104), Material = M.Cardboard, CanCollide = false }, a)
    -- puddles: flat, reflective, catch the lamps (no collision)
    for _, pd in ipairs({ { -40, 23.4, 3.2, 2 }, { -32.6, 10.5, 2.4, 3.8 }, { -36, 36.4, 4, 1.8 }, { -31, 31.5, 2, 2.6 } }) do
        box("Puddle", pd[1] - pd[3] / 2, 0.1, pd[2] - pd[4] / 2, pd[1] + pd[3] / 2, 0.13, pd[2] + pd[4] / 2,
            rgb(40, 43, 50), M.SmoothPlastic, a, nc({ Reflectance = 0.4, Transparency = 0.35, CastShadow = false }))   -- (v3.0.1) was near-black glass = looked like a hole
    end

    -- painted words on the walls (they take the lamp light)
    local sign = box("WallPaint", EX0 - 0.06, 4.4, 5.5, EX0, 6.6, 12.5, rgb(122, 66, 56), M.Brick, a, nc({ Transparency = 1 }))
    lit(printOn(sign, Enum.NormalId.Left, "DELIVERIES ONLY", rgb(236, 230, 214), UITheme.F.display, 30, 1).Parent)
    local tag1 = box("Graffiti", -39.4, 5, SZ0 - 0.06, -29.4, 9.4, SZ0, rgb(122, 66, 56), M.Brick, a, nc({ Transparency = 1 }))
    local tg = lit(surface(tag1, Enum.NormalId.Front, 20, 1))
    local tl = text({ Text = "DOLLZ", Size = UDim2.fromScale(0.96, 0.9), Position = UDim2.fromScale(0.02, 0.05),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Rotation = -4,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold), TextColor3 = rgb(255, 110, 200) }, tg)
    local ts = Instance.new("UIStroke")
    ts.Color = rgb(40, 220, 240)
    ts.Thickness = 4
    ts.Parent = tl

    -- ── roof ladder: a steel truss you can climb, on the annex's east wall ──
    -- Top at y 18; the parapet is notched (NOTCH_Z0..Z1) so you step onto the roof deck.
    local truss = Instance.new("TrussPart")
    truss.Name = "RoofLadder"
    truss.Anchored = true
    truss.Size = Vector3.new(2, 18, 2)
    truss.CFrame = CFrame.new(ANNEX_X1 + 1, 9, LADDER_Z)
    truss.Color = STEEL_LT
    truss.Material = M.Metal
    truss.Parent = a
    local rs = box("RoofSign", ANNEX_X1 + 0.02, 2.4, ANNEX_Z0 + 0.2, ANNEX_X1 + 0.12, 3.6, LADDER_Z - 1.2, rgb(250, 204, 21), M.Metal, a, nc())
    lit(printOn(rs, Enum.NormalId.Right, "ROOF", rgb(30, 30, 30), UITheme.F.display, 50, 1).Parent)

    -- the dark corner by the dumpster (sneak here from the gate)
    table.insert(refs.shadowZones, shadowZone("ShadowAlley", EX0 - 6.5, 17, EX0, 28.5, a))
end

-- the roof: hatch (outside end of the roof "vent") above the closet
function JewelryBuilder:_roof(f)
    local r = Instance.new("Folder")
    r.Name = "RoofAccess"
    r.Parent = f
    local hx, hz = -64.8, 39.6                  -- (v3.1) over the closet ladder
    box("HatchCurb", hx - 1.9, ROOF_Y, hz - 1.9, hx + 1.9, ROOF_Y + 0.6, hz + 1.9, STEEL, M.Metal, r)
    local lid = facingPart("DD_RoofHatch", Vector3.new(hx, ROOF_Y + 0.75, hz), Vector3.new(3.2, 0.3, 3.2),
        Vector3.new(1, 0, 0), rgb(250, 204, 21), M.DiamondPlate, r)
    bar("HatchHandle", Vector3.new(hx + 0.8, ROOF_Y + 1.0, hz - 0.8), Vector3.new(hx + 0.8, ROOF_Y + 1.0, hz + 0.8), 0.14,
        STEEL_DK, M.Metal, r, nc())
    -- hazard paint around the hatch so it's findable from the ladder
    box("HatchPaint", hx - 2.6, ROOF_Y, hz - 2.6, hx + 2.6, ROOF_Y + 0.03, hz + 2.6, rgb(230, 190, 40), M.Concrete, r, nc())
    return lid
end

-- The safe room: steel-clad, the Duchess necklace, and the safe itself.
function JewelryBuilder:_safeRoom(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "SafeRoom"
    s.Parent = f

    -- steel cladding (to y 8) + safe-deposit boxes on the west wall
    box("CladW", IX0, FLOOR, SR_Z0, IX0 + 0.1, FLOOR + 7.5, IZ1, STEEL, M.Metal, s)
    box("CladS", IX0, FLOOR, IZ1 - 0.1, -68, FLOOR + 7.5, IZ1, STEEL, M.Metal, s)
    local dep = box("DepositBoxes", IX0 + 0.1, FLOOR + 0.6, SR_Z0 + 1, IX0 + 0.4, FLOOR + 7.2, IZ1 - 1, STEEL_LT, M.Metal, s)
    local dg = lit(surface(dep, Enum.NormalId.Right, 20, 1))
    for r = 0, 7 do
        for col = 0, 7 do
            local cell = frame({ Size = UDim2.fromScale(0.115, 0.11), Position = UDim2.fromScale(0.006 + col * 0.124, 0.01 + r * 0.124),
                BackgroundColor3 = rgb(120, 126, 136) }, dg)
            frame({ Size = UDim2.fromScale(0.2, 0.1), Position = UDim2.fromScale(0.4, 0.45), BackgroundColor3 = rgb(60, 62, 70) }, cell)
        end
    end

    -- ── the safe ──
    local sx0, sx1 = SAFE_X - SAFE_HW, SAFE_X + SAFE_HW
    local fz0, fz1 = SAFE_Z0, SAFE_Z0 + 0.45
    local oy0, oy1 = SAFE_Y - 1.4, SAFE_Y + 1.4
    local ox0, ox1 = SAFE_X - 1.4, SAFE_X + 1.4
    local topY = SAFE_TOP
    local body = Instance.new("Model")
    body.Name = "Safe"
    body.Parent = s
    box("SafeBack", sx0, FLOOR, SAFE_Z1 - 0.45, sx1, topY, SAFE_Z1, STEEL, M.Metal, body)
    box("SafeSide", sx0, FLOOR, fz1, sx0 + 0.45, topY, SAFE_Z1 - 0.45, STEEL, M.Metal, body)
    box("SafeSide", sx1 - 0.45, FLOOR, fz1, sx1, topY, SAFE_Z1 - 0.45, STEEL, M.Metal, body)
    box("SafeTop", sx0, topY - 0.45, fz0, sx1, topY, SAFE_Z1, STEEL, M.Metal, body)
    box("SafeFloor", sx0 + 0.45, FLOOR, fz1, sx1 - 0.45, FLOOR + 0.45, SAFE_Z1 - 0.45, STEEL, M.Metal, body)
    box("SafeFront", sx0, FLOOR, fz0, ox0, topY - 0.45, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox1, FLOOR, fz0, sx1, topY - 0.45, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox0, oy1, fz0, ox1, topY - 0.45, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox0, FLOOR, fz0, ox1, oy0, fz1, STEEL, M.Metal, body)
    box("SafeBand", sx0 - 0.03, topY - 1.0, fz0 - 0.03, sx1 + 0.03, topY - 0.82, SAFE_Z1, BRASS, M.Metal, body, nc())
    box("SafeLining", sx0 + 0.45, FLOOR + 0.45, SAFE_Z1 - 0.55, sx1 - 0.45, topY - 0.45, SAFE_Z1 - 0.45, rgb(120, 20, 36), M.Fabric, body)
    box("SafeShelfLow", sx0 + 0.45, oy0 - 0.1, fz1, sx1 - 0.45, oy0, SAFE_Z1 - 0.55, STEEL_LT, M.Metal, body)
    box("SafeShelfHigh", sx0 + 0.45, SAFE_Y - 0.25, fz1, sx1 - 0.45, SAFE_Y - 0.15, SAFE_Z1 - 0.55, STEEL_LT, M.Metal, body)
    local plate = box("SafeNameplate", SAFE_X - 1, topY - 0.8, fz0 - 0.04, SAFE_X + 1, topY - 0.5, fz0, BRASS, M.Metal, body, nc())
    lit(printOn(plate, Enum.NormalId.Front, "D.D. SAFE CO.  ·  1986", rgb(60, 36, 14), UITheme.F.display, 60, 1).Parent)

    -- ── the round door (everything below swings about the hinge) ──
    local dz = fz0 - DISC_T / 2
    local faceZ = fz0 - DISC_T
    local door = Instance.new("Model")
    door.Name = "SafeDoor"
    door.Parent = s
    local swing = {}
    local function add(p)
        table.insert(swing, p)
        return p
    end
    add(part({ Name = "DoorDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(DISC_T, DISC_R * 2, DISC_R * 2),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, dz) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(166, 170, 180), Material = M.Metal, Reflectance = 0.15 }, door))
    -- lock plate at the centre: this is the `door` ref. A Block whose LookVector
    -- faces north, so JobService's drill sits on the door face.
    local lock = add(box("LockPlate", SAFE_X - 0.6, SAFE_Y - 0.6, faceZ - 0.16, SAFE_X + 0.6, SAFE_Y + 0.6, faceZ,
        BRASS, M.Metal, door, { Reflectance = 0.2 }))
    add(part({ Name = "Dial", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.8, 0.8),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, faceZ - 0.23) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(28, 28, 32), Material = M.Metal, CanCollide = false }, door))
    add(box("DialTick", SAFE_X - 0.03, SAFE_Y + 0.26, faceZ - 0.32, SAFE_X + 0.03, SAFE_Y + 0.38, faceZ - 0.28,
        rgb(240, 240, 240), M.Metal, door, nc()))
    local hub = Vector3.new(SAFE_X - 1.2, SAFE_Y, faceZ - 0.2)
    add(part({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.34, 0.34),
        CFrame = CFrame.new(hub) * CFrame.Angles(0, math.rad(90), 0), Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    for k = 0, 2 do
        add(part({ Name = "WheelSpoke", Size = Vector3.new(0.1, 1.25, 0.1), CFrame = CFrame.new(hub) * CFrame.Angles(0, 0, math.rad(k * 60)),
            Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60 + 90)
        add(part({ Name = "WheelKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18),
            Position = hub + Vector3.new(0.62 * math.cos(a), 0.62 * math.sin(a), 0),
            Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    end
    for k = 0, 7 do
        if k ~= 4 then
            local a = k * math.pi / 4
            add(part({ Name = "Rivet", Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18),
                Position = Vector3.new(SAFE_X + 1.75 * math.cos(a), SAFE_Y + 1.75 * math.sin(a), faceZ - 0.02),
                Color = STEEL_LT, Material = M.Metal, CanCollide = false }, door))
        end
    end
    local hx = SAFE_X + DISC_R
    for _, ky in ipairs({ SAFE_Y - 1.2, SAFE_Y + 1.2 }) do
        part({ Name = "HingeKnuckle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.38, 0.38),
            CFrame = CFrame.new(hx, ky, faceZ + 0.1) * CFrame.Angles(0, 0, math.rad(90)),
            Color = STEEL_DK, Material = M.Metal }, body)
    end
    -- Hinge on the EAST edge: with openAngle -100° the door swings north-east
    -- and ends up standing at x ≈ -72..-71.7, z 34.8..39 — clear of the loot.
    refs.vault = {
        door = lock,
        parts = swing,
        hinge = CFrame.new(hx, SAFE_Y, faceZ),
        openAngle = math.rad(-100),
    }

    -- ── loot (v3.0) ──
    local function stand(x, z, lookZ)
        local p = Vector3.new(x, FLOOR + 3, z)
        return CFrame.lookAt(p, Vector3.new(x, p.Y, lookZ))
    end
    local innerZ = (fz1 + SAFE_Z1 - 0.55) / 2

    -- 1) Diamonds, upper shelf: loose stones in rows on a velvet tray, with two
    --    folded diamond papers (how dealers really carry them)
    box("DiamondTray", SAFE_X - 1.2, SAFE_Y - 0.15, innerZ - 0.5, SAFE_X + 1.2, SAFE_Y - 0.05, innerZ + 0.5, rgb(20, 16, 26), M.Fabric, body)
    local dA = Instance.new("Model")
    dA.Name = "Diamonds"
    dA.Parent = s
    for k = 0, 11 do
        local gx = SAFE_X - 0.95 + (k % 6) * 0.38
        local gz = innerZ - 0.2 + math.floor(k / 6) * 0.4
        stone(dA, Vector3.new(gx, SAFE_Y + 0.02, gz), (k % 5 == 0) and 0.26 or 0.19,
            (k == 4) and STONE.pink or ((k == 9) and STONE.sapphire or STONE.diamond))
    end
    for _, px in ipairs({ SAFE_X - 0.8, SAFE_X + 0.75 }) do
        box("DiamondPaper", px - 0.22, SAFE_Y - 0.05, innerZ + 0.12, px + 0.22, SAFE_Y + 0.03, innerZ + 0.42,
            rgb(250, 250, 246), M.Fabric, dA, nc({ CastShadow = false }))
        box("PaperFold", px - 0.22, SAFE_Y + 0.03, innerZ + 0.12, px + 0.22, SAFE_Y + 0.035, innerZ + 0.2,
            rgb(120, 170, 230), M.Fabric, dA, nc({ CastShadow = false }))
    end
    point(lightAnchor("SafeSparkle", Vector3.new(SAFE_X, SAFE_Y + 0.5, innerZ - 0.4), dA), rgb(230, 240, 255), 0.6, 4, false)
    table.insert(loot, { kind = "Diamonds", cframe = stand(SAFE_X + 0.8, SAFE_Z0 - 2.7, SAFE_Z0), visual = dA, pool = "saferoom" })

    -- 2) Diamonds, lower shelf: a stack of open ring boxes + a velvet pouch
    --    spilling stones
    local dB = Instance.new("Model")
    dB.Name = "RingBoxes"
    dB.Parent = s
    local ly = oy0
    local boxes = {
        { SAFE_X - 1.1, 0, STONE.diamond, GOLD }, { SAFE_X - 0.55, 0, STONE.ruby, PLATINUM },
        { SAFE_X, 0, STONE.sapphire, GOLD },
    }
    for _, b in ipairs(boxes) do
        local bx, by = b[1], ly + b[2]
        box("RingBox", bx - 0.22, by, innerZ - 0.2, bx + 0.22, by + 0.3, innerZ + 0.2, VELVET, M.Fabric, dB, nc())
        box("RingBoxLid", bx - 0.22, by + 0.3, innerZ + 0.16, bx + 0.22, by + 0.62, innerZ + 0.22, VELVET, M.Fabric, dB, nc())
        box("RingBoxSatin", bx - 0.19, by + 0.3, innerZ + 0.15, bx + 0.19, by + 0.58, innerZ + 0.16, rgb(245, 240, 236), M.Fabric, dB, nc())
        standingRing(dB, CFrame.lookAt(Vector3.new(bx, by + 0.42, innerZ - 0.02), Vector3.new(bx, by + 0.42, innerZ - 1)),
            0.2, b[4], b[3], VELVET)
    end
    part({ Name = "Pouch", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.45, 0.55),
        Position = Vector3.new(SAFE_X + 0.9, ly + 0.2, innerZ + 0.15), Color = rgb(40, 24, 70), Material = M.Fabric,
        CanCollide = false }, dB)
    for k = 0, 4 do
        stone(dB, Vector3.new(SAFE_X + 0.45 + k * 0.14, ly + 0.07, innerZ - 0.4 + (k % 2) * 0.12), 0.13, STONE.diamond)
    end
    table.insert(loot, { kind = "Diamonds", cframe = stand(SAFE_X - 1.2, SAFE_Z0 - 2.7, SAFE_Z0), visual = dB, pool = "saferoom" })

    -- 3) "the Duchess": a ruby + diamond collar on a bust on a tall plinth,
    --    facing the laser doorway so you see it through the beams (grab it any time).
    --    (v3.1) tucked west of the doorway line, ~9 studs from the safe
    local px, pz = -78.8, 30
    box("DuchessPlinth", px - 0.85, FLOOR, pz - 0.85, px + 0.85, FLOOR + 2.4, pz + 0.85, rgb(236, 226, 230), M.Marble, s)
    box("DuchessCap", px - 0.95, FLOOR + 2.4, pz - 0.95, px + 0.95, FLOOR + 2.55, pz + 0.95, BRASS, M.Metal, s)
    local dplq = box("DuchessPlaque", px - 0.6, FLOOR + 1.7, pz - 0.87, px + 0.6, FLOOR + 2.1, pz - 0.85, BRASS, M.Metal, s, nc())
    lit(printOn(dplq, Enum.NormalId.Front, "THE DUCHESS", rgb(60, 36, 14), UITheme.F.display, 80, 1).Parent)
    local duchess = self:_necklaceBust(s, "DuchessBust", Vector3.new(px, FLOOR + 2.55, pz), Vector3.new(0, 0, -1),
        Vector3.new(0, 0, -1), 5)
    table.insert(loot, { kind = "Necklace", cframe = stand(px, pz - 2.1, pz), visual = duchess, interact = "unscrew",
        pool = "saferoom", inVault = false })
    canLight(s, px, pz, rgb(255, 236, 246), 3, 36, true)

    -- (v3.1) the longer room: steel evidence cabinets down the east wall (cover
    -- on the walk to the safe), a dim caged lamp half way
    for k = 0, 2 do
        local cz0 = 28.2 + k * 2.6
        local cab = box("SteelCabinet", -69.6, FLOOR, cz0, -68.05, FLOOR + 5.2, cz0 + 2.4, rgb(88, 94, 104), M.Metal, s)
        local cg = lit(surface(cab, Enum.NormalId.Left, 30, 1))
        for d = 0, 3 do
            local drw = frame({ Size = UDim2.fromScale(0.9, 0.21), Position = UDim2.fromScale(0.05, 0.03 + d * 0.24),
                BackgroundColor3 = rgb(104, 110, 120) }, cg)
            frame({ Size = UDim2.fromScale(0.3, 0.1), Position = UDim2.fromScale(0.35, 0.4), BackgroundColor3 = BRASS }, drw)
        end
    end
    local mid = box("CageLampMid", -73.4, CEIL - 0.4, 32.6, -72.6, CEIL, 33.4, STEEL_DK, M.Metal, s, nc())
    box("CageLampBulb", -73.25, CEIL - 0.5, 32.75, -72.75, CEIL - 0.4, 33.25, COOL, M.Neon, s, nc())
    point(mid, rgb(200, 215, 255), 0.35, 11, false)
    box("HazardLine", SAFE_X - SAFE_HW - 0.5, FLOOR, SAFE_Z0 - 3.4, SAFE_X + SAFE_HW + 0.5, FLOOR + 0.03, SAFE_Z0 - 3.2,
        rgb(230, 190, 40), M.Concrete, s, nc())

    -- light over the safe + a caged work lamp
    canLight(s, SAFE_X, SAFE_Z0 - 1.9, WARM, 2.8, 55, true)
    local cage = box("CageLamp", -75.4, CEIL - 0.4, 26.2, -74.6, CEIL, 27, STEEL_DK, M.Metal, s, nc())
    box("CageLampBulb", -75.25, CEIL - 0.5, 26.35, -74.75, CEIL - 0.4, 26.85, COOL, M.Neon, s, nc())
    point(cage, rgb(200, 215, 255), 0.45, 12, false)
end

-- ──────────────────────────────────────────────
-- 📹 CAMERAS
-- ──────────────────────────────────────────────
-- mount = point on the wall face, out = unit vector away from the wall
function JewelryBuilder:_camera(f, name, mount, out, target, yawRange, period)
    local m = Instance.new("Model")
    m.Name = name
    m.Parent = f
    part({ Name = "Bracket", Size = Vector3.new(0.9, 0.9, 0.2), CFrame = CFrame.lookAt(mount + out * 0.1, mount + out * 2),
        Color = STEEL_DK, Material = M.Metal, CanCollide = false }, m)
    local armEnd = mount + out * 1.1
    bar("Body", mount + out * 0.2, armEnd, 0.22, STEEL_DK, M.Metal, m, nc())
    part({ Name = "Knuckle", Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34), Position = armEnd,
        Color = STEEL_DK, Material = M.Metal, CanCollide = false }, m)
    local headPos = armEnd + Vector3.new(0, -0.45, 0)
    local head = part({ Name = "Head", Size = Vector3.new(0.7, 0.6, 1.3), CFrame = CFrame.lookAt(headPos, target),
        Color = rgb(226, 228, 232), Material = M.Metal, CanCollide = false }, m)
    local lens = part({ Name = "Lens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.42, 0.42),
        CFrame = head.CFrame * CFrame.new(0, 0, -0.68) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(12, 12, 16), Material = M.Glass }, m)
    weldTo(head, lens)
    local led = part({ Name = "Led", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16),
        CFrame = head.CFrame * CFrame.new(0.22, 0.2, -0.6), Color = rgb(255, 50, 50), Material = M.Neon }, m)
    weldTo(head, led)
    local light = spot(head, Enum.NormalId.Front, rgb(255, 60, 60), 1.4, 30, 48)
    return { model = m, head = head, light = light, led = led, yawRange = yawRange, period = period }
end

-- ──────────────────────────────────────────────
function JewelryBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "DiamondDolls"
    f.Parent = folder

    local refs = {
        id = "jewelry",
        root = f,
        entryPoint = Vector3.new(CX, 3, -4),
        -- the crew drops in INSIDE the staff break room, just past the alley
        -- door. No guard route and no camera covers it; the office next door
        -- leads to the back hall.
        -- (v3.1) the bigger break room: drop in by the staff door, facing the office door
        sneakIn = { at = Vector3.new(-45, 3.5, 34.5), face = Vector3.new(-45, 3.5, 30),
            spread = Vector3.new(0.6, 0, 0) },
        entrances = {
            { kind = "front", at = Vector3.new(CX, 3, -3.5), label = "Front door" },
            { kind = "side", at = Vector3.new(ANNEX_X1 + 3, 3, (SIDE_Z0 + SIDE_Z1) / 2), label = "Staff door (yard)" },
            { kind = "roof", at = Vector3.new(ANNEX_X1 + 3.2, 3, LADDER_Z), label = "Roof ladder" },
        },
        hideSpots = {},
        shadowZones = {},
        vents = {},
        policeStop = Vector3.new(CX - 20, 0, -14),   -- west of the store, clear of the gate
        -- (v2.0.2) parked INSIDE the walled service yard, nose at the vehicle gate
        -- (x -45.6..-37.4, z 2.6). Straight run north: gate → driveway → Ocean Drive.
        getawayCFrame = CFrame.lookAt(Vector3.new(CAR_X, 0, CAR_Z), Vector3.new(CAR_X, 0, CAR_Z - 10)),
    }

    self:_shell(f)
    refs.openSign = self:_facade(f)
    -- (v3.0) lootSpots v3: every room adds its own (see the header for the list)
    local loot = {}
    refs.lootSpots = loot
    refs.poolNames = { showroom = "SHOWROOM", office = "OFFICE", backhall = "BACK HALL", saferoom = "SAFE ROOM" }
    local counterSpot, showroomVent, cageRow = self:_showroom(f, refs, loot)

    local back = Instance.new("Folder")
    back.Name = "BackRooms"
    back.Parent = f
    self:_hall(back, refs, loot)
    refs.keycardDoors = { self:_keycardDoor(back) }
    refs.laserRows = self:_lasers(back)
    -- (v3.0) row 3 = the pink diamond's cage (rows 1-2 stay the corridor + safe door)
    table.insert(refs.laserRows, cageRow)
    local breaker, shelfSpot, hatchInside = self:_closet(back, refs, loot)
    refs.breaker = breaker
    local deskSpot = self:_office(back, loot)      -- (v3.1) on top of the office filing cabinets
    local breakVent = self:_breakRoom(back, refs)
    self:_yard(f, refs)
    local hatchRoof = self:_roof(f)
    self:_safeRoom(back, refs, loot)
    refs.keycardSpots = { counterSpot, deskSpot, shelfSpot }

    -- vents: a = the end you start from, b = where it comes out (both directions work)
    -- Exit = the floor spot VentService stands you on when you come out of THIS end
    tag(breakVent, "Vent", { Pair = showroomVent.Name, Label = "Crawl through",
        Exit = Vector3.new(-46.5, FLOOR, IZ1 - 2) })
    tag(showroomVent, "Vent", { Pair = breakVent.Name, Label = "Crawl through",
        Exit = Vector3.new(-50.6, FLOOR, 13.2) })
    tag(hatchRoof, "Vent", { Pair = hatchInside.Name, Label = "Climb down",
        Exit = Vector3.new(-61.8, ROOF_Y, 39.6) })
    tag(hatchInside, "Vent", { Pair = hatchRoof.Name, Label = "Climb to the roof",
        Exit = Vector3.new(-63.8, FLOOR, 39.6) })
    refs.vents = {
        { a = breakVent, b = showroomVent },
        { a = hatchRoof, b = hatchInside },
    }

    -- shadow zones inside (the hall end + alley were added by their builders)
    table.insert(refs.shadowZones, shadowZone("ShadowLounge", -57.5, 13, IX1, SHOW_Z1, f))
    table.insert(refs.shadowZones, shadowZone("ShadowLaserCorridor", IX0, BOH_Z0, -74, LC_WALL0, f))
    table.insert(refs.shadowZones, shadowZone("ShadowWindowCorner", IX0, IZ0, -77, 2, f))

    local cams = Instance.new("Folder")
    cams.Name = "Cameras"
    cams.Parent = f
    refs.cameras = {
        -- showroom: high in the front-east corner, sweeping the cases + front door.
        -- (the lounge / vent corner behind it is its blind spot)
        self:_camera(cams, "Camera_Showroom", Vector3.new(IX1, 13.4, 0.9), Vector3.new(-1, 0, 0),
            Vector3.new(-66, FLOOR, 9), 80, 8),
        -- safe room: north-east corner, watching the laser opening and the safe
        self:_camera(cams, "Camera_SafeRoom", Vector3.new(-68, 12.8, SR_Z0 + 0.8), Vector3.new(-1, 0, 0),
            Vector3.new(-75, FLOOR, 35), 50, 7),
    }

    -- patrols: straight lines, >= 2 studs clear of every case / counter / wall.
    -- Neither route can see into the break room (sneakIn).
    refs.guardRoutes = {
        { name = "Guard_A", spawn = Vector3.new(-76, 3.5, LANE_A_Z),
            a = Vector3.new(-76, 3.5, LANE_A_Z), b = Vector3.new(-51.5, 3.5, LANE_A_Z) },
        { name = "Guard_B", spawn = Vector3.new(-62, 3.5, 28),
            a = Vector3.new(-62, 3.5, 19), b = Vector3.new(-62, 3.5, 29.5) },
    }

    refs.plan = {
        bounds = { X0, Z0, ANNEX_X1, Z1 },
        rooms = {
            { X0, Z0, X1, SHOW_Z1, "SHOWROOM" },
            { IX0, BOH_Z0, -68, LC_WALL0, "LASERS" },
            { IX0, SR_Z0, -68, IZ1, "SAFE" },
            { HALL_X0, BOH_Z0, HALL_X1, HALL_Z1, "HALL" },
            { HALL_X0, CLOSET_Z0, HALL_X1, IZ1, "CLOSET" },
            { EC_X0, BOH_Z0, AIX1, OB_Z0, "OFFICE" },
            { EC_X0, BREAK_Z0, AIX1, IZ1, "BREAK" },
        },
        vault = { SAFE_X, (SAFE_Z0 + SAFE_Z1) / 2 },
        entry = { CX, Z0 },
    }

    -- soft props (async, never errors) — repainted, they import plain white
    prop("furniture", "rugDoormat", Vector3.new(CX, FLOOR + 0.03, 1.4), Vector3.new(0, 0, -1), f,
        { main = { rgb(30, 26, 32), M.Fabric } }, { collide = false })
    -- (v3.0) the round rug is gone: the pink diamond's cage stands there now

    print("[JewelryBuilder] Diamond Dolls v3 built 💎")
    return refs
end

return JewelryBuilder
