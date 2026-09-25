--[[
    HEIST CREW — JewelryBuilder
    ────────────────────────────────────────────────
    v1.0 "Neon Miami" (2026-09-25). Job 2: DIAMOND DOLLS JEWELERS — a glam
    art-deco jewelry boutique on the south side of Ocean Drive. The loud,
    fast counterpart to the villa: smash the cases, get the keycard, beat
    the laser, drill the back-room safe, go.

    FOOTPRINT x -70..-46, z -1..23 (Constants.WORLD.JEWELRY_*). Floor top
    y 0.5, ceiling y 14.5, roof y 15.5, parapet y 16.5, tall facade to ~25.
    The shopfront faces NORTH onto the street at z -1. Nothing is built on
    the south sidewalk (z -5.4..-1.4) except the awning overhead (y > 12,
    clear of the streetlight at x -56).

        z -1  ┌────────── glass ─── ENTRANCE (x -61..-55) ─── glass ──────────┐
              │  [case1][case2]                          [case3][case4]      │
              │  ···· guard A aisle (z 4.6) ···· chandelier ················ │
              │  [case5][case6]      central axis        [case7][case8]      │
              │  [COUNTER]  ···· guard B aisle (z 10.6) ····                 │
        z 13  ├── wall ──┬─ KEYCARD DOOR (x -61..-55) ─┬── CLOSET doorway ───┤
              │  SAFE    │  LASER corridor (z 13.5-15) │ CLOSET (breaker)    │
              │  ROOM    └────────┘                    ├── door ─────────────┤
              │  pedestal  easel   [ SAFE ]            │ OFFICE (desk)       │
        z 23  └────────────────────────────────────────┴─────────────────────┘
              x -70                                    x -54.5            x -46

    Geometry + props + refs ONLY. No gameplay logic, no Scripts, no prompts —
    JobService / SecurityService / LootService / GuardService wire the refs.

    PUBLIC API:
        JewelryBuilder:build(folder) -> JobRefs   (docs/V1_SPEC.md §4, id = "jewelry")
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local JewelryBuilder = {}

local M = Enum.Material
local W = Constants.WORLD

-- ── layout ──────────────────────────────────────────────────────────────
local FLOOR = W.FLOOR                                         -- 0.5
local CX, CZ = W.JEWELRY_CENTER.x, W.JEWELRY_CENTER.z         -- -58, 11
local X0, X1 = CX - W.JEWELRY_HALF_WIDTH, CX + W.JEWELRY_HALF_WIDTH   -- -70, -46
local Z0, Z1 = CZ - W.JEWELRY_HALF_DEPTH, CZ + W.JEWELRY_HALF_DEPTH   -- -1, 23
local IX0, IX1 = X0 + 1, X1 - 1        -- interior faces of the side walls: -69, -47
local IZ0, IZ1 = Z0 + 1, Z1 - 1        -- inner face of the shopfront 0, of the back wall 22
local CEIL = FLOOR + 14                -- 14.5
local TOP = FLOOR + 16                 -- 16.5 (parapet top)
local ZF = Z0 - 0.25                   -- -1.25, front face of the shopfront

local DOOR_X0, DOOR_X1 = CX - 3, CX + 3        -- entrance + keycard door, x -61..-55
local BACK_Z0, BACK_Z1 = 12.5, 13.5            -- showroom / back-rooms wall
local CLOSET_X0 = -53.5                         -- closet doorway x -53.5..-47.5 (6 wide)
local PART_X = -54.5                            -- partition centre (safe room | closet+office)
local OFFICE_Z = 17                             -- closet / office wall centre

-- showroom case rows (cases run along x, 3.2 long x 1.4 deep)
local CASE_HX, CASE_HZ = 1.6, 0.7
local FRONT_ROW_Z, MID_ROW_Z = 1.3, 7.9         -- z 0.6..2.0 and 7.2..8.6
local CASE_XS = { -67.0, -63.2, -52.8, -49.2 }  -- leaves x -61.6..-54.4 open: entrance → keycard door
local AISLE_A_Z = 4.6                            -- guard A walks here
local AISLE_B_Z = 10.6                           -- guard B walks here

-- the safe (floor safe, 5 wide x 6 tall x 2.8 deep, door facing the corridor)
local SAFE_X = -58.5
local SAFE_Z0, SAFE_Z1 = 19.2, 22               -- front face .. back
local SAFE_Y = FLOOR + 3                         -- door centre height (3.5)
local DISC_R, DISC_T = 1.75, 0.5

-- ── palette ─────────────────────────────────────────────────────────────
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local P = Constants.MIAMI
local PINK      = UITheme.rgb(P.PASTELS[1])      -- flamingo
local LILAC     = UITheme.rgb(P.PASTELS[3])
local STUCCO    = UITheme.rgb(P.STUCCO)
local HOT_PINK  = UITheme.rgb(P.NEONS[1])
local CYAN      = UITheme.rgb(P.NEONS[2])
local MAUVE     = rgb(78, 46, 86)                -- interior partitions
local VELVET    = rgb(112, 18, 70)
local VELVET_2  = rgb(38, 22, 70)                -- midnight velvet for alternate pads
local MIRROR    = rgb(206, 210, 224)
local BRASS     = rgb(212, 172, 92)
local GOLD      = rgb(240, 192, 64)
local STEEL     = rgb(58, 62, 70)
local STEEL_DK  = rgb(30, 32, 38)
local STEEL_LT  = rgb(158, 164, 174)
local WALNUT    = rgb(74, 46, 32)
local WARM      = rgb(255, 222, 186)
local LASER_RED = rgb(255, 40, 64)
local GEM_COLORS = { rgb(255, 92, 196), rgb(80, 232, 255), rgb(236, 244, 255) }

-- ── helpers (same style as SafehouseBuilder) ────────────────────────────
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
local function canLight(parent, x, z, color, brightness, angle)
    local can = box("CanLight", x - 0.4, CEIL - 0.3, z - 0.4, x + 0.4, CEIL, z + 0.4, STEEL_DK, M.Metal, parent, nc())
    box("CanLens", x - 0.25, CEIL - 0.34, z - 0.25, x + 0.25, CEIL - 0.3, z + 0.25, color or WARM, M.Neon, parent,
        nc({ CastShadow = false }))
    spot(can, Enum.NormalId.Bottom, color or WARM, brightness or 3.2, 16, angle or 42, true)
    return can
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: floors, walls, ceiling, roof
-- ──────────────────────────────────────────────
function JewelryBuilder:_shell(f)
    -- floors (split at wall centres so every room gets its own finish)
    box("FloorShowroom", X0, 0, Z0, X1, FLOOR, 13, rgb(34, 26, 40), M.Marble, f, { Reflectance = 0.08 })
    box("FloorSafeRoom", X0, 0, 13, PART_X, FLOOR, Z1, rgb(76, 79, 86), M.DiamondPlate, f)
    box("FloorCloset", PART_X, 0, 13, X1, FLOOR, OFFICE_Z, rgb(196, 198, 204), M.CeramicTiles, f)
    box("FloorOffice", PART_X, 0, OFFICE_Z, X1, FLOOR, Z1, rgb(78, 44, 66), M.Carpet, f)
    -- step between the sidewalk (ends z -1.4) and the shopfront
    box("Threshold", X0, 0, Z0 - 0.4, X1, FLOOR, Z0, rgb(214, 206, 198), M.Concrete, f)

    -- exterior walls (the front is the facade, built in _facade)
    box("WallWest", X0, FLOOR, Z0, IX0, TOP, Z1, LILAC, M.Plaster, f)
    box("WallEast", IX1, FLOOR, Z0, X1, TOP, Z1, LILAC, M.Plaster, f)
    box("WallSouth", IX0, FLOOR, IZ1, IX1, TOP, Z1, LILAC, M.Plaster, f)
    -- coping caps on the parapet
    box("CopingW", X0 - 0.15, TOP, Z0 - 0.45, IX0 + 0.05, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingE", IX1 - 0.05, TOP, Z0 - 0.45, X1 + 0.15, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingS", IX0, TOP, IZ1 - 0.05, IX1, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)

    -- ceiling (dark plum, seen from inside) + roof deck (seen from above)
    box("Ceiling", IX0, CEIL, IZ0, IX1, CEIL + 0.5, IZ1, rgb(50, 30, 58), M.Plaster, f)
    box("Roof", IX0, CEIL + 0.5, IZ0, IX1, CEIL + 1, IZ1, rgb(160, 158, 164), M.Concrete, f)
    box("RoofAC1", -66, CEIL + 1, 16, -63.5, CEIL + 2.6, 18.5, STEEL_LT, M.Metal, f)
    box("RoofAC2", -52, CEIL + 1, 18, -49.8, CEIL + 2.4, 20.2, STEEL_LT, M.Metal, f)
    box("RoofHatch", -60, CEIL + 1, 19, -58.5, CEIL + 1.4, 20.5, STEEL, M.Metal, f)

    -- ── interior walls (to the ceiling) ──
    -- showroom back wall at z 13: keycard door x -61..-55, closet doorway x -53.5..-47.5
    box("BackWallW", IX0, FLOOR, BACK_Z0, DOOR_X0, CEIL, BACK_Z1, MAUVE, M.Plaster, f)   -- also the door's slide pocket
    box("KeycardHeader", DOOR_X0, FLOOR + 9.5, BACK_Z0, DOOR_X1, CEIL, BACK_Z1, MAUVE, M.Plaster, f)
    box("BackWallMid", DOOR_X1, FLOOR, BACK_Z0, CLOSET_X0, CEIL, BACK_Z1, MAUVE, M.Plaster, f)
    box("ClosetHeader", CLOSET_X0, FLOOR + 9.5, BACK_Z0, IX1 - 0.5, CEIL, BACK_Z1, MAUVE, M.Plaster, f)
    box("BackWallE", IX1 - 0.5, FLOOR, BACK_Z0, IX1, CEIL, BACK_Z1, MAUVE, M.Plaster, f)
    -- laser corridor (x -61..-55, z 13.5..15): west wall; the east side is the partition
    box("CorridorWallW", DOOR_X0 - 1, FLOOR, BACK_Z1, DOOR_X0, CEIL, 15, MAUVE, M.Plaster, f)
    box("Partition", PART_X - 0.5, FLOOR, BACK_Z1, PART_X + 0.5, CEIL, IZ1, MAUVE, M.Plaster, f)
    -- closet | office wall with a 4-wide door x -52.5..-48.5
    box("OfficeWallW", PART_X + 0.5, FLOOR, OFFICE_Z - 0.5, -52.5, CEIL, OFFICE_Z + 0.5, MAUVE, M.Plaster, f)
    box("OfficeHeader", -52.5, FLOOR + 8.5, OFFICE_Z - 0.5, -48.5, CEIL, OFFICE_Z + 0.5, MAUVE, M.Plaster, f)
    box("OfficeWallE", -48.5, FLOOR, OFFICE_Z - 0.5, IX1, CEIL, OFFICE_Z + 0.5, MAUVE, M.Plaster, f)
end

-- ──────────────────────────────────────────────
-- 💎 FACADE: glass shopfront, awning, neon sign, deco fins, roofline
-- ──────────────────────────────────────────────
function JewelryBuilder:_facade(f)
    local fa = Instance.new("Folder")
    fa.Name = "Facade"
    fa.Parent = f

    -- piers: corner piers stand proud of the fascia, door piers frame the entrance
    box("PierW", X0, FLOOR, ZF - 0.2, X0 + 1.5, TOP, IZ0, PINK, M.Plaster, fa)
    box("PierE", X1 - 1.5, FLOOR, ZF - 0.2, X1, TOP, IZ0, PINK, M.Plaster, fa)
    box("DoorPierW", DOOR_X0 - 0.8, FLOOR, ZF, DOOR_X0, 12, IZ0, PINK, M.Plaster, fa)
    box("DoorPierE", DOOR_X1, FLOOR, ZF, DOOR_X1 + 0.8, 12, IZ0, PINK, M.Plaster, fa)
    -- deco ribs up the corner piers
    for _, rx in ipairs({ X0 + 0.35, X0 + 0.95, X1 - 0.95, X1 - 0.35 }) do
        box("PierRib", rx - 0.12, FLOOR + 0.6, ZF - 0.4, rx + 0.12, TOP - 0.4, ZF - 0.2, STUCCO, M.Plaster, fa, nc())
    end

    -- shop windows: floor-to-ceiling glass on a marble sill, brass mullion + transom
    local glassTint = rgb(168, 196, 232)
    for _, bay in ipairs({ { X0 + 1.5, DOOR_X0 - 0.8 }, { DOOR_X1 + 0.8, X1 - 1.5 } }) do
        local b0, b1 = bay[1], bay[2]
        box("Sill", b0, FLOOR, ZF + 0.15, b1, FLOOR + 0.6, IZ0, rgb(236, 226, 230), M.Marble, fa)
        box("ShopWindow", b0, FLOOR + 0.6, -0.7, b1, 12, -0.4, glassTint, M.Glass, fa,
            { Transparency = 0.55, Reflectance = 0.25 })
        local mid = (b0 + b1) / 2
        box("Mullion", mid - 0.08, FLOOR + 0.6, -0.8, mid + 0.08, 12, -0.3, BRASS, M.Metal, fa)
        box("Transom", b0, 9.6, -0.8, b1, 9.8, -0.3, BRASS, M.Metal, fa)
    end

    -- entrance: open doorway (6 wide) with a brass frame and a lettered header
    -- (frame sits on the pier faces, outside the 6-wide opening)
    box("DoorFrameW", DOOR_X0 - 0.3, FLOOR, ZF - 0.15, DOOR_X0, 10.25, ZF, BRASS, M.Metal, fa, nc())
    box("DoorFrameE", DOOR_X1, FLOOR, ZF - 0.15, DOOR_X1 + 0.3, 10.25, ZF, BRASS, M.Metal, fa, nc())
    box("DoorFrameTop", DOOR_X0 - 0.3, 10, ZF - 0.15, DOOR_X1 + 0.3, 10.25, ZF, BRASS, M.Metal, fa, nc())
    local header = box("DoorHeader", DOOR_X0, 10, ZF, DOOR_X1, 12, IZ0, PINK, M.Plaster, fa)
    local hg = surface(header, Enum.NormalId.Front, 40, 1.1)
    text({ Text = "FINE JEWELRY  ·  EST. 1986", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.25),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(120, 70, 20) }, hg)

    -- fascia band over the windows, with deco speed-lines
    box("Fascia", X0 + 1.5, 12, ZF, X1 - 1.5, TOP, IZ0, LILAC, M.Plaster, fa)
    for _, ly in ipairs({ 15.0, 15.45, 15.9 }) do
        box("SpeedLine", X0 + 1.5, ly - 0.06, ZF - 0.12, X1 - 1.5, ly + 0.06, ZF, STUCCO, M.Plaster, fa)
    end

    -- taller stepped facade (ziggurat) + spire
    box("TierA", -66, TOP, ZF, -50, 20.5, IZ0, LILAC, M.Plaster, fa)
    box("TierB", -63.5, 20.5, ZF, -52.5, 22.5, IZ0, PINK, M.Plaster, fa)
    box("Spire", CX - 1, 22.5, ZF + 0.25, CX + 1, 25, IZ0 - 0.2, STUCCO, M.Plaster, fa)
    local tip = part({ Name = "SpireTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7),
        Position = Vector3.new(CX, 25.35, ZF + 0.65), Color = CYAN, Material = M.Neon, CanCollide = false }, fa)
    point(tip, CYAN, 1.5, 10)
    -- deco fins flanking the sign
    for _, fx in ipairs({ -65.55, -64.75, -51.25, -50.45 }) do
        box("DecoFin", fx - 0.15, 13.6, ZF - 0.35, fx + 0.15, 20.2, ZF, STUCCO, M.Plaster, fa, nc())
    end

    -- ── the sign: DIAMOND DOLLS, hot-pink script + cyan diamond ──
    local sx0, sx1, sy0, sy1 = -63.5, -52.5, 17, 21.6
    local board = box("SignBoard", sx0, sy0, ZF - 0.25, sx1, sy1, ZF, rgb(24, 12, 32), M.Metal, fa)
    local sg = surface(board, Enum.NormalId.Front, 40, 2.4)
    -- cyan diamond icon (two rotated squares: outline + gem core)
    local icon = frame({ Size = UDim2.fromOffset(70, 70), Position = UDim2.fromOffset(28, 36), Rotation = 45,
        BackgroundTransparency = 1 }, sg)
    local st = Instance.new("UIStroke")
    st.Color = CYAN
    st.Thickness = 5
    st.Parent = icon
    frame({ Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(50, 58), Rotation = 45,
        BackgroundColor3 = rgb(170, 245, 255) }, sg)
    -- the name, in a handwritten-neon script
    local name = text({ Text = "Diamond Dolls", Size = UDim2.fromScale(0.74, 0.66), Position = UDim2.fromScale(0.245, 0.02),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = rgb(255, 150, 214) }, sg)
    local glow = Instance.new("UIStroke")
    glow.Color = HOT_PINK
    glow.Thickness = 3
    glow.Transparency = 0.15
    glow.Parent = name
    text({ Text = "J E W E L E R S", Size = UDim2.fromScale(0.6, 0.2), Position = UDim2.fromScale(0.315, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = CYAN }, sg)
    -- cyan tube outline around the board
    local oz = ZF - 0.33
    tube("SignTube", Vector3.new(sx0, sy1, oz), Vector3.new(sx1, sy1, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx1, sy0, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx0, sy1, oz), CYAN, fa)
    tube("SignTube", Vector3.new(sx1, sy0, oz), Vector3.new(sx1, sy1, oz), CYAN, fa)
    -- real pink light spilling onto the facade and awning
    point(lightAnchor("SignGlowW", Vector3.new(-61, 19.3, ZF - 1.8), fa), HOT_PINK, 3, 17)
    point(lightAnchor("SignGlowE", Vector3.new(-55, 19.3, ZF - 1.8), fa), HOT_PINK, 3, 17)

    -- ── neon roofline (hot pink, thin) ──
    local rz = ZF - 0.45
    tube("Roofline", Vector3.new(X0, TOP - 0.3, rz), Vector3.new(-66, TOP - 0.3, rz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-50, TOP - 0.3, rz), Vector3.new(X1, TOP - 0.3, rz), HOT_PINK, fa)
    local tz = ZF - 0.1
    tube("Roofline", Vector3.new(-66, TOP, tz), Vector3.new(-66, 20.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-50, TOP, tz), Vector3.new(-50, 20.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-66, 20.5, tz), Vector3.new(-63.5, 20.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-52.5, 20.5, tz), Vector3.new(-50, 20.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-63.5, 20.5, tz), Vector3.new(-63.5, 22.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-52.5, 20.5, tz), Vector3.new(-52.5, 22.5, tz), HOT_PINK, fa)
    tube("Roofline", Vector3.new(-63.5, 22.5, tz), Vector3.new(-52.5, 22.5, tz), HOT_PINK, fa)
    tube("SpireTube", Vector3.new(CX, 22.6, ZF + 0.15), Vector3.new(CX, 24.9, ZF + 0.15), HOT_PINK, fa, 0.14)
    -- down both side walls
    tube("Roofline", Vector3.new(X0 - 0.1, TOP - 0.3, Z0), Vector3.new(X0 - 0.1, TOP - 0.3, Z1), HOT_PINK, fa)
    tube("Roofline", Vector3.new(X1 + 0.1, TOP - 0.3, Z0), Vector3.new(X1 + 0.1, TOP - 0.3, Z1), HOT_PINK, fa)

    -- ── striped awning (deep pink / blush), sloping out over the sidewalk ──
    -- back edge on the fascia at y 13.4, front edge y 12.35 at z -3.25: stays
    -- above the streetlight pole (top y 12) and arm (y 11.6-11.9) at x -56.
    local ax0, ax1, n = X0 + 1.6, X1 - 1.6, 10
    local w = (ax1 - ax0) / n
    local back = Vector3.new(0, 13.4, ZF)
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
    local lamp = box("DoorLamp", CX - 0.4, 11.55, ZF - 0.35, CX + 0.4, 11.85, ZF, BRASS, M.Metal, fa, nc())
    box("DoorLampLens", CX - 0.3, 11.5, ZF - 0.3, CX + 0.3, 11.55, ZF - 0.05, WARM, M.Neon, fa, nc())
    spot(lamp, Enum.NormalId.Bottom, rgb(255, 204, 170), 1.6, 12, 110, true)
    for _, ux in ipairs({ DOOR_X0 - 0.4, DOOR_X1 + 0.4 }) do
        local up = box("Uplight", ux - 0.3, FLOOR, ZF - 0.15, ux + 0.3, FLOOR + 0.25, ZF, STEEL_DK, M.Metal, fa, nc())
        spot(up, Enum.NormalId.Top, CYAN, 1.6, 13, 28)
    end

    -- ── OPEN / CLOSED sign hanging in the east window ──
    local ox0, ox1, oy0, oy1 = -53.6, -51.5, 7.15, 8.25
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
        box("OpenChain", cx - 0.03, oy1 + 0.14, -0.3, cx + 0.03, 12, -0.24, BRASS, M.Metal, fa, nc())
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
-- ✨ SHOWROOM: walls, chandelier, counter, 8 display cases
-- ──────────────────────────────────────────────
function JewelryBuilder:_walls(f)
    -- velvet + mirror panels down both side walls, brass rails top and bottom
    local widths = { 2.2, 2.2, 2.2, 2.2, 2.2 }
    for _, side in ipairs({ -1, 1 }) do
        local xw = side < 0 and IX0 or IX1                  -- wall face
        local xa, xb = xw - side * 0.05, xw - side * 0.17   -- panel slab
        local z = 0.4
        for i, wd in ipairs(widths) do
            if i % 2 == 1 then
                box("VelvetPanel", xa, FLOOR + 0.7, z, xb, FLOOR + 10.3, z + wd, VELVET, M.Fabric, f)
            else
                box("MirrorPanel", xa, FLOOR + 0.7, z, xb, FLOOR + 10.3, z + wd, MIRROR, M.Glass, f,
                    { Reflectance = 0.6 })
            end
            z = z + wd
            if i < #widths then
                box("PanelFrame", xa, FLOOR + 0.7, z, xw - side * 0.22, FLOOR + 10.3, z + 0.2, BRASS, M.Metal, f)
                z = z + 0.2
            end
        end
        box("PanelRailTop", xa, FLOOR + 10.3, 0.4, xw - side * 0.22, FLOOR + 10.5, z, BRASS, M.Metal, f)
        box("PanelRailLow", xa, FLOOR + 0.5, 0.4, xw - side * 0.22, FLOOR + 0.7, z, BRASS, M.Metal, f)
        -- hot-pink neon line at the foot of the wall (+ a soft pink fill)
        local strip = box("BaseNeon", xw - side * 0.17, FLOOR, 0.3, xw - side * 0.29, FLOOR + 0.12, 12.2, HOT_PINK,
            M.Neon, f, nc({ CastShadow = false }))
        point(strip, HOT_PINK, 0.5, 9)
    end
    box("BaseNeonBack", IX0 + 0.3, FLOOR, BACK_Z0 - 0.24, DOOR_X0 - 0.4, FLOOR + 0.12, BACK_Z0 - 0.12, HOT_PINK, M.Neon, f,
        nc({ CastShadow = false }))

    -- brass cornice where the walls meet the ceiling, plaster medallion over the chandelier
    box("Cornice", IX0, CEIL - 0.3, IZ0, IX1, CEIL, IZ0 + 0.2, BRASS, M.Metal, f, nc())
    box("Cornice", IX0, CEIL - 0.3, BACK_Z0 - 0.2, IX1, CEIL, BACK_Z0, BRASS, M.Metal, f, nc())
    box("Cornice", IX0, CEIL - 0.3, IZ0, IX0 + 0.2, CEIL, BACK_Z0, BRASS, M.Metal, f, nc())
    box("Cornice", IX1 - 0.2, CEIL - 0.3, IZ0, IX1, CEIL, BACK_Z0, BRASS, M.Metal, f, nc())
    part({ Name = "CeilingMedallion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 4.4, 4.4),
        CFrame = CFrame.new(CX, CEIL - 0.05, AISLE_A_Z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STUCCO, Material = M.Plaster, CanCollide = false }, f)

    -- keycard door frame (showroom side) + closet doorway frame + plaque
    box("KeycardTrimW", DOOR_X0 - 0.3, FLOOR, BACK_Z0 - 0.2, DOOR_X0, 10.3, BACK_Z0, BRASS, M.Metal, f)
    box("KeycardTrimE", DOOR_X1, FLOOR, BACK_Z0 - 0.2, DOOR_X1 + 0.3, 10.3, BACK_Z0, BRASS, M.Metal, f)
    box("KeycardTrimTop", DOOR_X0 - 0.3, 10, BACK_Z0 - 0.2, DOOR_X1 + 0.3, 10.3, BACK_Z0, BRASS, M.Metal, f)
    box("ClosetTrimW", CLOSET_X0 - 0.2, FLOOR, BACK_Z0 - 0.2, CLOSET_X0, 10.2, BACK_Z0, BRASS, M.Metal, f)
    box("ClosetTrimE", IX1 - 0.5, FLOOR, BACK_Z0 - 0.2, IX1 - 0.3, 10.2, BACK_Z0, BRASS, M.Metal, f)
    box("ClosetTrimTop", CLOSET_X0 - 0.2, 10, BACK_Z0 - 0.2, IX1 - 0.3, 10.2, BACK_Z0, BRASS, M.Metal, f)
    local plaque = box("StaffPlaque", -52, 10.6, BACK_Z0 - 0.1, -49, 11.4, BACK_Z0, BRASS, M.Metal, f, nc())
    local pg = surface(plaque, Enum.NormalId.Front, 50, 1)
    text({ Text = "STAFF ONLY", Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(60, 36, 14) }, pg)
end

function JewelryBuilder:_chandelier(f)
    local c = Instance.new("Model")
    c.Name = "Chandelier"
    c.Parent = f
    local x, z = CX, AISLE_A_Z
    local crystal = rgb(236, 240, 255)
    local function ring(y, r, n, drop)
        for i = 0, n - 1 do
            local a0 = (i / n) * math.pi * 2
            local a1 = ((i + 1) / n) * math.pi * 2
            local p0 = Vector3.new(x + r * math.cos(a0), y, z + r * math.sin(a0))
            local p1 = Vector3.new(x + r * math.cos(a1), y, z + r * math.sin(a1))
            bar("Ring", p0, p1, 0.12, BRASS, M.Metal, c, nc({ CastShadow = false }))
            part({ Name = "Crystal", Size = Vector3.new(0.2, drop, 0.2),
                CFrame = CFrame.new(p0 + Vector3.new(0, -drop / 2 - 0.08, 0)) * CFrame.Angles(0, math.rad(45), 0),
                Color = crystal, Material = M.Glass, Transparency = 0.2, Reflectance = 0.4,
                CanCollide = false, CastShadow = false }, c)
        end
    end
    part({ Name = "Canopy", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.4, 1.4),
        CFrame = CFrame.new(x, CEIL - 0.15, z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = BRASS, Material = M.Metal, CanCollide = false }, c)
    bar("Rod", Vector3.new(x, CEIL - 0.3, z), Vector3.new(x, 11.2, z), 0.14, BRASS, M.Metal, c, nc())
    ring(12.2, 1.8, 12, 0.5)
    ring(11.4, 1.1, 8, 0.4)
    for i = 0, 3 do
        local a = i * math.pi / 2
        bar("Arm", Vector3.new(x, 12.2, z), Vector3.new(x + 1.8 * math.cos(a), 12.2, z + 1.8 * math.sin(a)),
            0.1, BRASS, M.Metal, c, nc())
    end
    for i = 0, 5 do
        local a = (i + 0.5) * math.pi / 3
        part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.26, 0.26, 0.26),
            Position = Vector3.new(x + 1.8 * math.cos(a), 12.4, z + 1.8 * math.sin(a)),
            Color = WARM, Material = M.Neon, CanCollide = false, CastShadow = false }, c)
    end
    local pendant = part({ Name = "Pendant", Size = Vector3.new(0.5, 0.5, 0.5),
        CFrame = CFrame.new(x, 10.9, z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
        Color = crystal, Material = M.Glass, Transparency = 0.15, Reflectance = 0.5,
        CanCollide = false, CastShadow = false }, c)
    point(pendant, rgb(255, 214, 170), 1.3, 22, true)
end

function JewelryBuilder:_counter(f)
    -- sales counter, back-west corner, facing the showroom
    local x0, x1, z0, z1 = IX0 + 0.2, -64.4, 10.8, 12.0
    box("CounterBody", x0, FLOOR, z0, x1, 3.1, z1, rgb(236, 214, 226), M.Marble, f)
    box("CounterKick", x0 + 0.1, FLOOR, z0 - 0.08, x1 - 0.1, FLOOR + 0.3, z0, BRASS, M.Metal, f)
    for k = 0, 4 do
        local fx = x0 + 0.6 + k * ((x1 - x0 - 1.2) / 4)
        box("CounterFlute", fx - 0.1, FLOOR + 0.5, z0 - 0.1, fx + 0.1, 2.9, z0, BRASS, M.Metal, f, nc())
    end
    box("CounterTop", x0 - 0.1, 3.1, z0 - 0.1, x1 + 0.1, 3.3, z1 + 0.05, BRASS, M.Metal, f, { Reflectance = 0.2 })
    -- cash register
    box("Register", -68.1, 3.3, 11.0, -66.9, 3.85, 11.9, rgb(34, 34, 40), M.Metal, f)
    box("RegisterDrawer", -68.0, 3.3, 10.9, -67.0, 3.5, 11.0, rgb(52, 52, 60), M.Metal, f)
    local screen = part({ Name = "RegisterScreen", Size = Vector3.new(1.0, 0.55, 0.08),
        CFrame = CFrame.new(-67.5, 4.2, 11.55) * CFrame.Angles(math.rad(18), 0, 0),
        Color = rgb(20, 22, 26), Material = M.Metal, CanCollide = false }, f)
    local sg = surface(screen, Enum.NormalId.Front, 80, 1.4)
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 24, 18) }, sg)
    text({ Text = "$0.00", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true, FontFace = UITheme.F.mono,
        TextColor3 = UITheme.C.money }, sg)

    -- mirror wall behind the counter (the keycard door slides into this wall
    -- section — the mirror is surface-mounted in front of it, so no clash)
    local mx0, mx1, my0, my1 = IX0 + 0.2, DOOR_X0 - 0.6, 3.8, 11
    local mirror = box("CounterMirror", mx0, my0, BACK_Z0 - 0.12, mx1, my1, BACK_Z0, MIRROR, M.Glass, f,
        { Reflectance = 0.6 })
    box("MirrorFrame", mx0 - 0.15, my1, BACK_Z0 - 0.18, mx1 + 0.15, my1 + 0.15, BACK_Z0, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx0 - 0.15, my0 - 0.15, BACK_Z0 - 0.18, mx1 + 0.15, my0, BACK_Z0, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx0 - 0.15, my0, BACK_Z0 - 0.18, mx0, my1, BACK_Z0, BRASS, M.Metal, f, nc())
    box("MirrorFrame", mx1, my0, BACK_Z0 - 0.18, mx1 + 0.15, my1, BACK_Z0, BRASS, M.Metal, f, nc())
    local mg = surface(mirror, Enum.NormalId.Front, 30, 1)
    local mirrorText = text({ Text = "Diamond Dolls", Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.06),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, TextTransparency = 0.15,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = rgb(222, 180, 96) }, mg)
    mirrorText.Name = "MirrorScript"
    canLight(f, -66.6, 11.4, WARM, 2.2, 55)

    -- keycard spot: east end of the counter top
    return CFrame.new(-65.1, 3.3, 11.4)
end

-- One display case. Returns the smashCases entry.
function JewelryBuilder:_case(f, i, cx, cz, side)
    local c = Instance.new("Model")
    c.Name = "DisplayCase" .. i
    c.Parent = f
    local padTop = 2.95
    local body = (i % 2 == 0) and rgb(28, 22, 34) or rgb(36, 26, 44)
    box("CaseBase", cx - CASE_HX, FLOOR, cz - CASE_HZ, cx + CASE_HX, 2.7, cz + CASE_HZ, body, M.Marble, c,
        { Reflectance = 0.06 })
    box("CaseKick", cx - CASE_HX + 0.05, FLOOR, cz - CASE_HZ - 0.05, cx + CASE_HX - 0.05, FLOOR + 0.2,
        cz + CASE_HZ + 0.05, BRASS, M.Metal, c, nc())
    box("CaseRim", cx - CASE_HX - 0.05, 2.7, cz - CASE_HZ - 0.05, cx + CASE_HX + 0.05, 2.85, cz + CASE_HZ + 0.05,
        BRASS, M.Metal, c, { Reflectance = 0.2 })
    local pad = (i <= 4) and VELVET or VELVET_2
    box("VelvetPad", cx - CASE_HX + 0.15, 2.85, cz - CASE_HZ + 0.12, cx + CASE_HX - 0.15, padTop,
        cz + CASE_HZ - 0.12, pad, M.Fabric, c)
    local glass = box("CaseGlass", cx - CASE_HX, 2.85, cz - CASE_HZ, cx + CASE_HX, 3.95, cz + CASE_HZ,
        rgb(214, 236, 246), M.Glass, c, { Transparency = 0.6, Reflectance = 0.25, CastShadow = false })
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -1, 1 }) do
            local px, pz = cx + sx * (CASE_HX - 0.05), cz + sz * (CASE_HZ - 0.05)
            box("CasePost", px - 0.05, 2.85, pz - 0.05, px + 0.05, 3.95, pz + 0.05, BRASS, M.Metal, c, nc())
        end
    end

    -- the jewels (this is what LootService hides when the case is taken)
    local v = Instance.new("Model")
    v.Name = "Jewels"
    v.Parent = c
    local variant = (i - 1) % 4
    local front = cz + side * 0.25     -- nudge the showpiece toward the viewer
    if variant == 0 then
        -- rings standing in a row, each with a stone
        for k = 0, 4 do
            local x = cx - 1.0 + k * 0.5
            part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.07, 0.42, 0.42),
                CFrame = CFrame.new(x, padTop + 0.19, cz) * CFrame.Angles(0, math.rad(90), 0),
                Color = GOLD, Material = M.Metal, Reflectance = 0.35, CanCollide = false, CastShadow = false }, v)
            gem(v, Vector3.new(x, padTop + 0.45, cz), 0.16, GEM_COLORS[(k % 3) + 1], k % 2 == 0)
        end
    elseif variant == 1 then
        -- a necklace laid out on the velvet, pendant toward the aisle
        for k = 0, 11 do
            local a = (k / 12) * math.pi * 2
            part({ Name = "Bead", Shape = Enum.PartType.Ball, Size = Vector3.new(0.13, 0.13, 0.13),
                Position = Vector3.new(cx + 0.9 * math.cos(a), padTop + 0.06, cz + 0.3 * math.sin(a)),
                Color = GOLD, Material = M.Metal, Reflectance = 0.35, CanCollide = false, CastShadow = false }, v)
        end
        gem(v, Vector3.new(cx, padTop + 0.16, cz + side * 0.36), 0.28, GEM_COLORS[1], true)
        gem(v, Vector3.new(cx - 1.25, padTop + 0.1, front), 0.14, GEM_COLORS[2], true)
        gem(v, Vector3.new(cx + 1.25, padTop + 0.1, front), 0.14, GEM_COLORS[2], true)
    elseif variant == 2 then
        -- three loose stones on little gold stands, a few chips scattered
        for k = -1, 1 do
            local x = cx + k * 0.85
            part({ Name = "Stand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.26, 0.26),
                CFrame = CFrame.new(x, padTop + 0.15, cz) * CFrame.Angles(0, 0, math.rad(90)),
                Color = GOLD, Material = M.Metal, Reflectance = 0.3, CanCollide = false, CastShadow = false }, v)
            gem(v, Vector3.new(x, padTop + 0.48, cz), 0.3, GEM_COLORS[k + 2], k ~= 0)
        end
        for k = 0, 3 do
            gem(v, Vector3.new(cx - 1.1 + k * 0.73, padTop + 0.06, front), 0.12, GEM_COLORS[(k % 3) + 1], true)
        end
    else
        -- bracelets lying flat, studded
        for k = -1, 1 do
            local x = cx + k * 0.9
            part({ Name = "Bracelet", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.62, 0.62),
                CFrame = CFrame.new(x, padTop + 0.05, cz) * CFrame.Angles(0, 0, math.rad(90)),
                Color = GOLD, Material = M.Metal, Reflectance = 0.35, CanCollide = false, CastShadow = false }, v)
            gem(v, Vector3.new(x - 0.18, padTop + 0.16, cz), 0.12, GEM_COLORS[1], true)
            gem(v, Vector3.new(x + 0.18, padTop + 0.16, cz), 0.12, GEM_COLORS[2], true)
        end
    end

    canLight(f, cx, cz, WARM, 3.2, 42)

    local stand = Vector3.new(cx, FLOOR + 3, cz + side * 1.9)
    return {
        glass = glass,
        visual = v,
        cframe = CFrame.lookAt(stand, Vector3.new(cx, stand.Y, cz)),
        kind = "Jewels",
    }
end

function JewelryBuilder:_showroom(f, refs)
    local s = Instance.new("Folder")
    s.Name = "Showroom"
    s.Parent = f
    self:_walls(s)
    self:_chandelier(s)
    local counterSpot = self:_counter(s)

    local cases = {}
    local i = 0
    for _, row in ipairs({ { z = FRONT_ROW_Z, side = 1 }, { z = MID_ROW_Z, side = -1 } }) do
        for _, x in ipairs(CASE_XS) do
            i = i + 1
            table.insert(cases, self:_case(s, i, x, row.z, row.side))
        end
    end
    refs.smashCases = cases
    return counterSpot
end

-- ──────────────────────────────────────────────
-- 🔒 BACK ROOMS: keycard door, laser corridor, closet, office, safe room
-- ──────────────────────────────────────────────
function JewelryBuilder:_keycardDoor(f)
    -- 6-wide sliding glass door in the z 13 wall; slides WEST into the wall
    -- section x -67..-61 (behind the counter mirror), so openOffset = (-6,0,0)
    local pane = box("KeycardDoor", DOOR_X0, FLOOR, 12.85, DOOR_X1, FLOOR + 9.5, 13.15, rgb(150, 215, 232), M.Glass, f,
        { Transparency = 0.45, Reflectance = 0.2 })
    local dg = surface(pane, Enum.NormalId.Front, 30, 1)
    frame({ Size = UDim2.fromScale(1, 0.1), Position = UDim2.fromScale(0, 0.42), BackgroundColor3 = rgb(240, 248, 255),
        BackgroundTransparency = 0.45 }, dg)
    text({ Text = "PRIVATE  ·  STAFF ONLY", Size = UDim2.fromScale(0.8, 0.06), Position = UDim2.fromScale(0.1, 0.44),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(40, 60, 80) }, dg)
    -- brass pull bar, welded so it slides with the door
    local handle = part({ Name = "DoorHandle", Size = Vector3.new(0.12, 2.4, 0.12),
        CFrame = CFrame.new(DOOR_X1 - 0.7, FLOOR + 3.7, 12.7), Color = BRASS, Material = M.Metal }, pane)
    weldTo(pane, handle)

    -- keypad on the showroom side, east of the door, status LED above it
    local panel = box("KeypadPanel", DOOR_X1 + 0.35, FLOOR + 3.4, BACK_Z0 - 0.25, DOOR_X1 + 1.15, FLOOR + 4.7, BACK_Z0,
        rgb(26, 28, 34), M.Metal, f)
    local kg = surface(panel, Enum.NormalId.Front, 60, 1.2)
    frame({ Size = UDim2.fromScale(0.7, 0.06), Position = UDim2.fromScale(0.15, 0.08), BackgroundColor3 = rgb(70, 76, 88) }, kg)
    for r = 0, 3 do
        for col = 0, 2 do
            local key = frame({ Size = UDim2.fromScale(0.2, 0.13), Position = UDim2.fromScale(0.14 + col * 0.25, 0.26 + r * 0.17),
                BackgroundColor3 = rgb(58, 62, 72) }, kg)
            UITheme.corner(key, 3)
        end
    end
    local status = box("KeypadStatus", DOOR_X1 + 0.63, FLOOR + 4.85, BACK_Z0 - 0.2, DOOR_X1 + 0.87, FLOOR + 5.05, BACK_Z0,
        rgb(255, 60, 60), M.Neon, f, nc())

    return { door = pane, openOffset = Vector3.new(-(DOOR_X1 - DOOR_X0), 0, 0), panel = panel, status = status }
end

function JewelryBuilder:_lasers(f)
    -- one row across the corridor right behind the keycard door (x -61..-55, z 14.25)
    local lz = 14.25
    local beams = {}
    for k, h in ipairs({ 1.2, 2.6, 4.0 }) do
        local y = FLOOR + h
        box("LaserEmitter", DOOR_X0, y - 0.2, lz - 0.2, DOOR_X0 + 0.25, y + 0.2, lz + 0.2, STEEL_DK, M.Metal, f, nc())
        box("LaserEmitter", DOOR_X1 - 0.25, y - 0.2, lz - 0.2, DOOR_X1, y + 0.2, lz + 0.2, STEEL_DK, M.Metal, f, nc())
        local b = box("LaserBeam" .. k, DOOR_X0 + 0.25, y - 0.06, lz - 0.06, DOOR_X1 - 0.25, y + 0.06, lz + 0.06,
            LASER_RED, M.Neon, f, nc({ CanTouch = false, CanQuery = false, CastShadow = false, Transparency = 1 }))
        table.insert(beams, b)
    end
    -- hazard stripes on the floor either side of the beam line
    for _, hz in ipairs({ 13.75, 14.75 }) do
        box("HazardStripe", DOOR_X0, FLOOR, hz - 0.08, DOOR_X1, FLOOR + 0.03, hz + 0.08, rgb(230, 190, 40), M.Concrete, f, nc())
    end
    return {
        beams = beams,
        zoneCFrame = CFrame.new(CX, FLOOR + 2.5, lz),
        zoneSize = Vector3.new(DOOR_X1 - DOOR_X0, 5, 0.6),
        onTime = 1.4, offTime = 1.1, phase = 0,
    }
end

function JewelryBuilder:_closet(f)
    -- utility closet x -54..-47, z 13.5..16.5, opens onto the showroom (6-wide doorway)
    local c = Instance.new("Folder")
    c.Name = "Closet"
    c.Parent = f
    local breaker = box("BreakerPanel", IX1 - 0.4, FLOOR + 2.4, 14.3, IX1, FLOOR + 5.2, 15.9, rgb(96, 102, 110), M.Metal, c)
    local bg = surface(breaker, Enum.NormalId.Left, 50, 1.1)
    text({ Text = "SECURITY", Size = UDim2.new(1, 0, 0.18, 0), Position = UDim2.fromScale(0, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 204, 21) }, bg)
    text({ Text = "CCTV · ALARM · DOORS", Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, 0.22),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(30, 32, 38) }, bg)
    for r = 0, 2 do
        for col = 0, 3 do
            frame({ Size = UDim2.fromScale(0.14, 0.12), Position = UDim2.fromScale(0.12 + col * 0.2, 0.4 + r * 0.18),
                BackgroundColor3 = rgb(40, 42, 48) }, bg)
        end
    end
    for k, col in ipairs({ rgb(80, 255, 120), rgb(80, 255, 120), rgb(255, 180, 40) }) do
        local lz = 14.55 + (k - 1) * 0.35
        box("BreakerLed", IX1 - 0.46, FLOOR + 4.85, lz - 0.06, IX1 - 0.4, FLOOR + 4.97, lz + 0.06, col, M.Neon, c, nc())
    end
    box("Conduit", IX1 - 0.3, FLOOR + 5.2, 15.0, IX1 - 0.15, CEIL, 15.2, STEEL_LT, M.Metal, c, nc())
    box("Pipe", IX1 - 0.45, FLOOR, 16.05, IX1 - 0.15, CEIL, 16.35, STEEL_LT, M.Metal, c)

    -- shelving on the partition side
    box("ShelfLow", PART_X + 0.5, FLOOR + 3.1, 13.7, PART_X + 1.5, FLOOR + 3.25, 16.3, WALNUT, M.WoodPlanks, c)
    box("ShelfHigh", PART_X + 0.5, FLOOR + 5.6, 13.7, PART_X + 1.5, FLOOR + 5.75, 16.3, WALNUT, M.WoodPlanks, c)
    for _, bz in ipairs({ 13.9, 16.1 }) do
        box("ShelfBracket", PART_X + 0.5, FLOOR + 2.8, bz - 0.05, PART_X + 1.2, FLOOR + 3.1, bz + 0.05, STEEL, M.Metal, c, nc())
    end
    for k, col in ipairs({ rgb(200, 60, 60), rgb(60, 110, 200), rgb(230, 230, 220) }) do
        part({ Name = "PaintCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.55, 0.55),
            CFrame = CFrame.new(PART_X + 1.0, FLOOR + 6.05, 13.9 + k * 0.6) * CFrame.Angles(0, 0, math.rad(90)),
            Color = col, Material = M.Metal, CanCollide = false }, c)
    end
    -- mop bucket by the door
    part({ Name = "MopBucket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.9, 0.9),
        CFrame = CFrame.new(IX1 - 0.9, FLOOR + 0.45, 13.95) * CFrame.Angles(0, 0, math.rad(90)),
        Color = rgb(240, 200, 40), Material = M.Rubber }, c)
    bar("Mop", Vector3.new(IX1 - 0.9, FLOOR + 0.7, 13.95), Vector3.new(IX1 - 0.3, FLOOR + 4.6, 13.75), 0.1, WALNUT,
        M.WoodPlanks, c, nc())

    local bulb = box("ClosetBulb", -50.8, CEIL - 0.3, 14.7, -50.2, CEIL, 15.3, STEEL_DK, M.Metal, c, nc())
    box("ClosetBulbLens", -50.7, CEIL - 0.34, 14.8, -50.3, CEIL - 0.3, 15.2, rgb(220, 232, 255), M.Neon, c, nc())
    point(bulb, rgb(220, 232, 255), 0.7, 10, true)

    return breaker, CFrame.new(PART_X + 1.0, FLOOR + 3.25, 15.7)
end

function JewelryBuilder:_office(f)
    -- back office x -54..-47, z 17.5..22 — reached through the closet
    local o = Instance.new("Folder")
    o.Name = "Office"
    o.Parent = f
    local dx0, dx1, dz0, dz1 = PART_X + 0.5, -52.2, 17.7, 21.9
    box("DeskTop", dx0, FLOOR + 2.45, dz0, dx1, FLOOR + 2.7, dz1, WALNUT, M.WoodPlanks, o)
    box("DeskSide", dx0 + 0.05, FLOOR, dz0 + 0.05, dx1 - 0.1, FLOOR + 2.45, dz0 + 0.25, WALNUT, M.WoodPlanks, o)
    box("DeskSide", dx0 + 0.05, FLOOR, dz1 - 0.25, dx1 - 0.1, FLOOR + 2.45, dz1 - 0.05, WALNUT, M.WoodPlanks, o)
    box("DeskBack", dx0, FLOOR, dz0 + 0.25, dx0 + 0.2, FLOOR + 2.45, dz1 - 0.25, WALNUT, M.WoodPlanks, o)
    point(lightAnchor("MonitorGlow", Vector3.new(-53.2, FLOOR + 3.6, 19.6), o), rgb(150, 200, 255), 0.6, 7)

    -- CCTV monitor on the south wall
    local mon = box("CctvMonitor", -51.8, FLOOR + 4.2, IZ1 - 0.2, -49.4, FLOOR + 5.8, IZ1, rgb(20, 20, 24), M.Metal, o)
    local mg = surface(mon, Enum.NormalId.Front, 60, 1.1)
    local feeds = { "CAM 1 · SHOWROOM", "CAM 2 · SAFE", "CAM 3 · —", "NO SIGNAL" }
    for k, label in ipairs(feeds) do
        local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
        local cell = frame({ Size = UDim2.fromScale(0.47, 0.44), Position = UDim2.fromScale(0.02 + col * 0.49, 0.04 + row * 0.49),
            BackgroundColor3 = rgb(18, 34, 40) }, mg)
        text({ Text = label, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.05),
            TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = rgb(140, 220, 200) }, cell)
    end

    local lamp = box("OfficeLight", -51, CEIL - 0.2, 19.2, -49.8, CEIL, 20.4, STEEL_DK, M.Metal, o, nc())
    box("OfficeLightLens", -50.9, CEIL - 0.24, 19.3, -49.9, CEIL - 0.2, 20.3, WARM, M.Neon, o, nc())
    point(lamp, WARM, 0.8, 12, true)

    KenneyLoader.placeMany({
        { kit = "furniture", name = "computerScreen", pos = Vector3.new(-53.4, FLOOR + 2.7, 19.6), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "chairDesk", pos = Vector3.new(-50.9, FLOOR, 19.6), facing = Vector3.new(-1, 0, 0) },
        { kit = "furniture", name = "bookcaseOpenLow", pos = Vector3.new(-48.1, FLOOR, 20.3), facing = Vector3.new(-1, 0, 0) },
    }, o)

    return CFrame.new(-52.8, FLOOR + 2.7, 21.3)
end

-- The safe: hollow steel box with a round door. Returns vault ref + loot spots.
function JewelryBuilder:_safeRoom(f, refs)
    local s = Instance.new("Folder")
    s.Name = "SafeRoom"
    s.Parent = f

    -- steel cladding on the safe-room walls (to y 8)
    box("CladW", IX0, FLOOR, BACK_Z1, IX0 + 0.1, FLOOR + 7.5, IZ1, STEEL, M.Metal, s)
    box("CladS", IX0, FLOOR, IZ1 - 0.1, PART_X - 0.5, FLOOR + 7.5, IZ1, STEEL, M.Metal, s)
    -- safe-deposit boxes on the partition (east wall of the room)
    local dep = box("DepositBoxes", PART_X - 0.8, FLOOR + 0.6, 15.6, PART_X - 0.5, FLOOR + 7.2, 21.7, STEEL_LT, M.Metal, s)
    local dg = surface(dep, Enum.NormalId.Left, 20, 1)
    for r = 0, 7 do
        for col = 0, 7 do
            local cell = frame({ Size = UDim2.fromScale(0.115, 0.11), Position = UDim2.fromScale(0.006 + col * 0.124, 0.01 + r * 0.124),
                BackgroundColor3 = rgb(120, 126, 136) }, dg)
            frame({ Size = UDim2.fromScale(0.2, 0.1), Position = UDim2.fromScale(0.4, 0.45), BackgroundColor3 = rgb(60, 62, 70) }, cell)
        end
    end

    -- ── the safe ──
    local sx0, sx1 = SAFE_X - 2.5, SAFE_X + 2.5          -- -61 .. -56
    local fz0, fz1 = SAFE_Z0, SAFE_Z0 + 0.4             -- front plate
    local oy0, oy1 = SAFE_Y - 1.2, SAFE_Y + 1.2         -- door opening 2.4 x 2.4
    local ox0, ox1 = SAFE_X - 1.2, SAFE_X + 1.2
    local topY = FLOOR + 6
    local body = Instance.new("Model")
    body.Name = "Safe"
    body.Parent = s
    box("SafeBack", sx0, FLOOR, SAFE_Z1 - 0.4, sx1, topY, SAFE_Z1, STEEL, M.Metal, body)
    box("SafeSide", sx0, FLOOR, fz1, sx0 + 0.4, topY, SAFE_Z1 - 0.4, STEEL, M.Metal, body)
    box("SafeSide", sx1 - 0.4, FLOOR, fz1, sx1, topY, SAFE_Z1 - 0.4, STEEL, M.Metal, body)
    box("SafeTop", sx0, topY - 0.4, fz0, sx1, topY, SAFE_Z1, STEEL, M.Metal, body)
    box("SafeFloor", sx0 + 0.4, FLOOR, fz1, sx1 - 0.4, FLOOR + 0.4, SAFE_Z1 - 0.4, STEEL, M.Metal, body)
    box("SafeFront", sx0, FLOOR, fz0, ox0, topY - 0.4, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox1, FLOOR, fz0, sx1, topY - 0.4, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox0, oy1, fz0, ox1, topY - 0.4, fz1, STEEL, M.Metal, body)
    box("SafeFront", ox0, FLOOR, fz0, ox1, oy0, fz1, STEEL, M.Metal, body)
    box("SafeBand", sx0 - 0.03, topY - 0.9, fz0 - 0.03, sx1 + 0.03, topY - 0.75, SAFE_Z1, BRASS, M.Metal, body, nc())
    box("SafeLining", sx0 + 0.4, FLOOR + 0.4, SAFE_Z1 - 0.5, sx1 - 0.4, topY - 0.4, SAFE_Z1 - 0.4, rgb(120, 20, 36), M.Fabric, body)
    box("SafeShelfLow", sx0 + 0.4, oy0 - 0.1, fz1, sx1 - 0.4, oy0, SAFE_Z1 - 0.5, STEEL_LT, M.Metal, body)
    box("SafeShelfHigh", sx0 + 0.4, SAFE_Y - 0.25, fz1, sx1 - 0.4, SAFE_Y - 0.15, SAFE_Z1 - 0.5, STEEL_LT, M.Metal, body)
    local plate = box("SafeNameplate", SAFE_X - 0.8, topY - 0.7, fz0 - 0.04, SAFE_X + 0.8, topY - 0.45, fz0, BRASS, M.Metal, body, nc())
    local ng = surface(plate, Enum.NormalId.Front, 60, 1)
    text({ Text = "D.D. SAFE CO.  ·  1986", Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(60, 36, 14) }, ng)

    -- ── the round door (everything below swings about the hinge) ──
    local dz = fz0 - DISC_T / 2                          -- disc centre z (18.95)
    local faceZ = fz0 - DISC_T                           -- disc outer face (18.7)
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
    -- faces the corridor (north), so JobService's drill sits on the door face.
    local lock = add(box("LockPlate", SAFE_X - 0.55, SAFE_Y - 0.55, faceZ - 0.16, SAFE_X + 0.55, SAFE_Y + 0.55, faceZ,
        BRASS, M.Metal, door, { Reflectance = 0.2 }))
    add(part({ Name = "Dial", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.7, 0.7),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, faceZ - 0.23) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(28, 28, 32), Material = M.Metal, CanCollide = false }, door))
    add(box("DialTick", SAFE_X - 0.025, SAFE_Y + 0.22, faceZ - 0.32, SAFE_X + 0.025, SAFE_Y + 0.33, faceZ - 0.28,
        rgb(240, 240, 240), M.Metal, door, nc()))
    -- spoked handle wheel, west of centre
    local hub = Vector3.new(SAFE_X - 1.05, SAFE_Y, faceZ - 0.2)
    add(part({ Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.3, 0.3),
        CFrame = CFrame.new(hub) * CFrame.Angles(0, math.rad(90), 0), Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    for k = 0, 2 do
        local a = math.rad(k * 60)
        add(part({ Name = "WheelSpoke", Size = Vector3.new(0.09, 1.1, 0.09), CFrame = CFrame.new(hub) * CFrame.Angles(0, 0, a),
            Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60 + 90)
        add(part({ Name = "WheelKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16),
            Position = hub + Vector3.new(0.55 * math.cos(a), 0.55 * math.sin(a), 0),
            Color = BRASS, Material = M.Metal, CanCollide = false }, door))
    end
    -- rivets round the rim (skipping the one under the wheel)
    for k = 0, 7 do
        if k ~= 4 then
            local a = k * math.pi / 4
            add(part({ Name = "Rivet", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16),
                Position = Vector3.new(SAFE_X + 1.45 * math.cos(a), SAFE_Y + 1.45 * math.sin(a), faceZ - 0.02),
                Color = STEEL_LT, Material = M.Metal, CanCollide = false }, door))
        end
    end
    -- hinge knuckles (static, on the frame at the hinge axis)
    local hx = SAFE_X + DISC_R
    for _, ky in ipairs({ SAFE_Y - 1.0, SAFE_Y + 1.0 }) do
        part({ Name = "HingeKnuckle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 0.34, 0.34),
            CFrame = CFrame.new(hx, ky, faceZ + 0.1) * CFrame.Angles(0, 0, math.rad(90)),
            Color = STEEL_DK, Material = M.Metal }, body)
    end
    -- Hinge on the EAST edge at the outer face: with openAngle -100° the door
    -- swings north-east, away from the corridor mouth (x -61..-55), so the
    -- open door never blocks the way to the loot. Swept door stays x < -55.8.
    refs.vault = {
        door = lock,
        parts = swing,
        hinge = CFrame.new(hx, SAFE_Y, faceZ),
        openAngle = math.rad(-100),
    }

    -- ── loot ──
    local loot = {}
    local function stand(x, z, lookZ)
        local p = Vector3.new(x, FLOOR + 3, z)
        return CFrame.lookAt(p, Vector3.new(x, p.Y, lookZ))
    end
    local innerZ = (fz1 + SAFE_Z1 - 0.5) / 2

    -- 1) Diamonds, upper shelf of the safe
    box("DiamondTray", SAFE_X - 1.0, SAFE_Y - 0.15, innerZ - 0.4, SAFE_X + 1.0, SAFE_Y - 0.05, innerZ + 0.4, rgb(20, 16, 26), M.Fabric, body)
    local dA = Instance.new("Model")
    dA.Name = "Diamonds"
    dA.Parent = s
    for k = 0, 6 do
        local gx = SAFE_X - 0.8 + (k % 4) * 0.53
        local gz = innerZ - 0.18 + math.floor(k / 4) * 0.36
        gem(dA, Vector3.new(gx, SAFE_Y + 0.1, gz), 0.26, (k % 3 == 1) and GEM_COLORS[2] or GEM_COLORS[3], k % 3 == 1)
    end
    table.insert(loot, { kind = "Diamonds", cframe = stand(-58.4, 17.3, SAFE_Z0), visual = dA })

    -- 2) Gold, lower shelf of the safe (a stacked pyramid of bars)
    local gold = Instance.new("Model")
    gold.Name = "Gold"
    gold.Parent = s
    local barSize = Vector3.new(0.9, 0.3, 0.45)
    local rows = { { -0.95, 0, 0.95 }, { -0.475, 0.475 }, { 0 } }
    for r, xs in ipairs(rows) do
        for _, bx in ipairs(xs) do
            part({ Name = "GoldBar", Size = barSize,
                Position = Vector3.new(SAFE_X + bx, oy0 + 0.15 + (r - 1) * 0.3, innerZ),
                Color = GOLD, Material = M.Metal, Reflectance = 0.35, CanCollide = false }, gold)
        end
    end
    table.insert(loot, { kind = "Gold", cframe = stand(-60.0, 17.3, SAFE_Z0), visual = gold })

    -- 3) Diamonds, the big pink stone on a pedestal under a glass cloche
    local px, pz = -67.0, 20.2
    box("Pedestal", px - 0.7, FLOOR, pz - 0.7, px + 0.7, FLOOR + 2.7, pz + 0.7, rgb(236, 226, 230), M.Marble, s)
    box("PedestalCap", px - 0.8, FLOOR + 2.7, pz - 0.8, px + 0.8, FLOOR + 2.8, pz + 0.8, BRASS, M.Metal, s)
    box("PedestalCushion", px - 0.4, FLOOR + 2.8, pz - 0.4, px + 0.4, FLOOR + 3.0, pz + 0.4, VELVET, M.Fabric, s)
    box("Cloche", px - 0.55, FLOOR + 2.8, pz - 0.55, px + 0.55, FLOOR + 4.1, pz + 0.55, rgb(214, 236, 246), M.Glass, s,
        { Transparency = 0.65, Reflectance = 0.25, CastShadow = false })
    local dB = Instance.new("Model")
    dB.Name = "PinkDiamond"
    dB.Parent = s
    gem(dB, Vector3.new(px, FLOOR + 3.45, pz), 0.55, rgb(255, 150, 214), false)
    gem(dB, Vector3.new(px, FLOOR + 3.45, pz), 0.24, HOT_PINK, true)
    gem(dB, Vector3.new(px - 0.25, FLOOR + 3.08, pz + 0.2), 0.12, CYAN, true)
    gem(dB, Vector3.new(px + 0.25, FLOOR + 3.08, pz - 0.2), 0.12, CYAN, true)
    table.insert(loot, { kind = "Diamonds", cframe = stand(px, 18.0, pz), visual = dB, inVault = false })
    canLight(s, px, pz, rgb(255, 236, 246), 3, 36)

    -- 4) Art: a framed Miami sunset on a wooden easel
    local ex, ez = -63.4, 20.4
    bar("EaselLeg", Vector3.new(ex - 1.0, FLOOR, ez - 0.3), Vector3.new(ex - 0.35, FLOOR + 5.6, ez + 0.1), 0.14, WALNUT, M.WoodPlanks, s)
    bar("EaselLeg", Vector3.new(ex + 1.0, FLOOR, ez - 0.3), Vector3.new(ex + 0.35, FLOOR + 5.6, ez + 0.1), 0.14, WALNUT, M.WoodPlanks, s)
    bar("EaselLeg", Vector3.new(ex, FLOOR, ez + 1.1), Vector3.new(ex, FLOOR + 5.4, ez + 0.25), 0.14, WALNUT, M.WoodPlanks, s)
    box("EaselLedge", ex - 1.3, FLOOR + 2.55, ez - 0.35, ex + 1.3, FLOOR + 2.7, ez + 0.05, WALNUT, M.WoodPlanks, s)
    local art = Instance.new("Model")
    art.Name = "Painting"
    art.Parent = s
    local cx0, cx1, cy0, cy1 = ex - 1.2, ex + 1.2, FLOOR + 2.7, FLOOR + 4.5
    local canvas = box("Canvas", cx0, cy0, ez - 0.2, cx1, cy1, ez - 0.1, rgb(250, 180, 120), M.Fabric, art, nc())
    box("ArtFrame", cx0 - 0.12, cy1, ez - 0.25, cx1 + 0.12, cy1 + 0.12, ez - 0.05, GOLD, M.Metal, art, nc())
    box("ArtFrame", cx0 - 0.12, cy0 - 0.12, ez - 0.25, cx1 + 0.12, cy0, ez - 0.05, GOLD, M.Metal, art, nc())
    box("ArtFrame", cx0 - 0.12, cy0, ez - 0.25, cx0, cy1, ez - 0.05, GOLD, M.Metal, art, nc())
    box("ArtFrame", cx1, cy0, ez - 0.25, cx1 + 0.12, cy1, ez - 0.05, GOLD, M.Metal, art, nc())
    local ag = surface(canvas, Enum.NormalId.Front, 60, 1)
    ag.LightInfluence = 0.6
    local sky = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, ag)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, rgb(70, 30, 120)),
        ColorSequenceKeypoint.new(0.55, rgb(255, 90, 150)),
        ColorSequenceKeypoint.new(1, rgb(255, 180, 90)),
    })
    grad.Parent = sky
    local sun = frame({ Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0.5, -28, 0.4, 0),
        BackgroundColor3 = rgb(255, 214, 110) }, ag)
    UITheme.corner(sun, 28)
    for k = 0, 3 do
        frame({ Size = UDim2.new(1, 0, 0, 3 + k), Position = UDim2.fromScale(0, 0.58 + k * 0.07),
            BackgroundColor3 = rgb(70, 30, 120) }, ag)
    end
    frame({ Size = UDim2.fromScale(1, 0.18), Position = UDim2.fromScale(0, 0.82), BackgroundColor3 = rgb(40, 120, 160) }, ag)
    table.insert(loot, { kind = "Art", cframe = stand(ex, 18.1, ez), visual = art, inVault = false })
    canLight(s, ex, ez - 0.8, rgb(255, 232, 210), 2.6, 40)

    -- light over the safe + a caged work lamp for the room
    canLight(s, SAFE_X, 18.4, WARM, 2.8, 55)
    local cage = box("CageLamp", -63, CEIL - 0.35, 16.6, -62.2, CEIL, 17.4, STEEL_DK, M.Metal, s, nc())
    box("CageLampBulb", -62.85, CEIL - 0.45, 16.75, -62.35, CEIL - 0.35, 17.25, rgb(210, 222, 255), M.Neon, s, nc())
    point(cage, rgb(200, 215, 255), 0.7, 16, true)

    refs.lootSpots = loot
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
        policeStop = Vector3.new(CX - 20, 0, -14),   -- (v1.1: moved west so parked cruisers sit well clear of the getaway spot)
        getawayCFrame = CFrame.lookAt(Vector3.new(-40, 0, -10), Vector3.new(-30, 0, -10)),
    }

    self:_shell(f)
    refs.openSign = self:_facade(f)
    local counterSpot = self:_showroom(f, refs)

    local back = Instance.new("Folder")
    back.Name = "BackRooms"
    back.Parent = f
    refs.keycardDoors = { self:_keycardDoor(back) }
    refs.laserRows = { self:_lasers(back) }
    local breaker, shelfSpot = self:_closet(back)
    refs.breaker = breaker
    local deskSpot = self:_office(back)
    self:_safeRoom(back, refs)
    refs.keycardSpots = { counterSpot, deskSpot, shelfSpot }

    local cams = Instance.new("Folder")
    cams.Name = "Cameras"
    cams.Parent = f
    refs.cameras = {
        -- showroom: high in the front-east corner, sweeping the cases
        self:_camera(cams, "Camera_Showroom", Vector3.new(IX1, 12.6, 0.9), Vector3.new(-1, 0, 0),
            Vector3.new(-60, FLOOR, 7), 80, 8),
        -- safe room: south-west corner, watching the corridor mouth and the safe
        self:_camera(cams, "Camera_SafeRoom", Vector3.new(IX0, 11.8, 21.2), Vector3.new(1, 0, 0),
            Vector3.new(-58, FLOOR, 15.2), 40, 7),
    }

    -- patrols: straight lines kept clear of every case / counter / wall
    refs.guardRoutes = {
        { name = "Guard_A", spawn = Vector3.new(-66, 3.5, AISLE_A_Z),
            a = Vector3.new(-66, 3.5, AISLE_A_Z), b = Vector3.new(-50, 3.5, AISLE_A_Z) },
        { name = "Guard_B", spawn = Vector3.new(-62.5, 3.5, AISLE_B_Z),
            a = Vector3.new(-62.5, 3.5, AISLE_B_Z), b = Vector3.new(-50.5, 3.5, AISLE_B_Z) },
    }

    refs.plan = {
        bounds = { X0, Z0, X1, Z1 },
        rooms = {
            { X0, Z0, X1, 13, "SHOWROOM" },
            { PART_X, 13, X1, OFFICE_Z, "CLOSET" },
            { PART_X, OFFICE_Z, X1, Z1, "OFFICE" },
            { DOOR_X0, 13, DOOR_X1, 15, "LASER" },
            { X0, 15, PART_X, Z1, "SAFE" },
        },
        vault = { SAFE_X, (SAFE_Z0 + SAFE_Z1) / 2 },
        entry = { CX, Z0 },
    }

    -- soft props (async, never errors)
    KenneyLoader.placeMany({
        { kit = "furniture", name = "rugDoormat", pos = Vector3.new(CX, FLOOR, 1.2), facing = Vector3.new(0, 0, -1),
            opts = { collide = false } },
        { kit = "furniture", name = "rugRound", pos = Vector3.new(CX, FLOOR, AISLE_A_Z), facing = Vector3.new(0, 0, -1),
            opts = { collide = false } },
        { kit = "furniture", name = "cardboardBoxClosed", pos = Vector3.new(PART_X + 1.35, FLOOR, 14.5),
            facing = Vector3.new(1, 0, 0) },
    }, f)

    print("[JewelryBuilder] Diamond Dolls built 💎")
    return refs
end

return JewelryBuilder
