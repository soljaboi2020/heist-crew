--[[
    HEIST CREW — BankBuilder
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Job 4: OCEAN BANK — the big, final heist.
    A grand art-deco Miami bank on the south side of Ocean Drive, facing
    NORTH onto the street. Marble banking hall, teller line, glass manager
    offices, security room, staff corridor + break room, a keycard door, a
    two-row laser corridor and a HUGE round vault door.

    GEOMETRY + PROPS + REFS ONLY. No Scripts, no ProximityPrompts, no gameplay
    logic — JobService / SecurityService / LootService / GuardService (and the
    v2 Hide / Feel / Vent services) wire everything from the JobRefs returned
    by build() (docs/V1_SPEC.md §4 + docs/V2_SPEC.md §4).

    FOOTPRINT x 84..140, z 1..55 (Constants.WORLD.BANK_*). The building is
    x 84..132; the STAFF ALLEY is the strip x 132..140 inside the lot.
    Raised floor: FLOOR = 2.0 (a real bank sits up on its steps). Ground and
    sidewalk are y 0 / 0.5; three steps climb from the sidewalk to the porch.
    Hall ceiling y 26 (24 tall), back rooms ceiling y 18 (16 tall),
    vault ceiling y 16, laser corridor ceiling y 14. Back roof top y 19,
    hall roof top y 27, front pylons to y 33.

        z 1  ┌PYLON─┐ steps · 4 columns · "OCEAN BANK" ┌─PYLON┐ │ ALLEY
             │84..96│ bronze doors x 104..112 (z 8)    │120.132│ │ x132..140
        z 9  ├──────┴──────────────────────────────────┴───────┤ │
             │[MANAGER]  G1 ········ z 11.5 ········  [LOANS]  │ │ (lamp,
             │ glass     benches        queue ropes    glass   │ │ dumpster)
             │ 85..97                                 119..131 │ │
        z 20 │ ══════════ TELLER COUNTER x 92..124 ═══════════ │ │
             │ closet  G2 ········ z 25.5 ········ (teller area)│ │
        z 28 ├──door 88..95──┬──────────────────door 121..128──┤ │
             │ SECURITY      │ STAFF CORRIDOR  G3 z 33.5       │ │ ladder
             │ breaker G4    door   (keypad)       [cart]      │ │ z 33..35
        z 39 ├───────────────┴─────┬KEYCARD┬─────┬─door 122..129┤ │
             │ VAULT               │LASERS │     │ BREAK ROOM   │ │
             │ gold·cash·diamonds (O)vault │     │ (sneakIn)  staff door
             │ deposit wall        │ door  │     │ lockers      │ z 44.5..51.5
        z 55 └─────────────────────┴───────┴─────┴──────────────┘ │
             x 84                 107     119                132    140

    3 WAYS IN: front doors (watched by cam 1 + guard 1) · staff door off the
    east alley into the break room (sneakIn — no guard, no camera) · the
    fire-escape ladder in the alley → roof → roof hatch (Vent pair) that
    drops into the security room beside the breaker.
    Crawl vent: manager office ↔ break room (skips the staff corridor).

    Guard routes are straight a↔b lines kept ≥ 2 studs from props, and none
    enters the break room. Interior doorways are all 7 wide, 10 tall.

    PUBLIC API
        BankBuilder:build(folder) -> JobRefs (id = "bank") — see the return
        table at the bottom of build() for every field.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local BankBuilder = {}

local M = Enum.Material

-- ── layout ──────────────────────────────────────────────────────────────
local FLOOR = 2.0          -- top of every floor inside the bank (raised on its steps)
local HALL_CEIL = 26       -- banking hall ceiling (24 tall)
local BACK_CEIL = 18       -- back rooms ceiling (16 tall)
local DOOR_TOP = FLOOR + 10  -- 12: top of every interior doorway
local GY = FLOOR + 2.5     -- guard / sneakIn height (root part)

-- ── palette ─────────────────────────────────────────────────────────────
local LIMESTONE  = Color3.fromRGB(226, 214, 190)
local SAND       = Color3.fromRGB(212, 196, 168)
local TEAL       = Color3.fromRGB(58, 170, 164)
local TEAL_DARK  = Color3.fromRGB(34, 110, 110)
local CYAN       = UITheme.rgb(Constants.MIAMI.NEONS[2])
local INTERIOR   = Color3.fromRGB(232, 222, 204)
local STAFF_WALL = Color3.fromRGB(196, 200, 196)
local STEEL      = Color3.fromRGB(52, 56, 64)
local STEEL_LITE = Color3.fromRGB(150, 156, 166)
local VSTEEL     = Color3.fromRGB(96, 100, 108)
local BRONZE     = Color3.fromRGB(150, 104, 58)
local BRASS      = Color3.fromRGB(196, 160, 90)
local GOLD       = Color3.fromRGB(236, 184, 60)
local WARM       = Color3.fromRGB(255, 206, 150)
local COOL       = Color3.fromRGB(215, 228, 255)
local MARBLE     = Color3.fromRGB(236, 230, 220)
local MARBLE_DK  = Color3.fromRGB(46, 44, 50)
local MARBLE_GRN = Color3.fromRGB(40, 78, 66)
local WOOD_DARK  = Color3.fromRGB(84, 52, 36)
local WOOD_MID   = Color3.fromRGB(128, 88, 58)
local VELVET     = Color3.fromRGB(150, 24, 40)
local LASER_RED  = Color3.fromRGB(255, 40, 50)
local SIGN_RED   = Color3.fromRGB(255, 60, 70)
local LEAF       = Color3.fromRGB(56, 118, 66)
local ASPHALT    = Color3.fromRGB(58, 58, 62)
local BRICK      = Color3.fromRGB(140, 78, 62)
local GLASS_TINT = Color3.fromRGB(200, 230, 235)

-- ──────────────────────────────────────────────
-- helpers (same style as VillaBuilder)
-- ──────────────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    if props.Shape then p.Shape = props.Shape end
    for k, v in pairs(props) do
        if k ~= "Shape" then p[k] = v end
    end
    p.Parent = parent
    return p
end

local function merge(a, b)
    local t = {}
    for k, v in pairs(a or {}) do t[k] = v end
    for k, v in pairs(b or {}) do t[k] = v end
    return t
end

-- A box described by its min/max corners
local function box(name, x0, y0, z0, x1, y1, z1, color, material, parent, extra)
    return part(merge({
        Name = name,
        Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
        Position = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Color = color,
        Material = material,
    }, extra), parent)
end

-- A part placed by CFrame
local function cpart(name, size, cf, color, material, parent, extra)
    return part(merge({ Name = name, Size = size, CFrame = cf, Color = color, Material = material }, extra), parent)
end

-- Vertical cylinder from y0 to y1
local function vcyl(name, x, y0, y1, z, dia, color, material, parent, extra)
    return cpart(name, Vector3.new(math.abs(y1 - y0), dia, dia),
        CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
        color, material, parent, merge({ Shape = Enum.PartType.Cylinder }, extra))
end

-- Cylinder whose round faces point along `normal` (a disc on a wall)
local function disc(name, pos, normal, thick, dia, color, material, parent, extra)
    return cpart(name, Vector3.new(thick, dia, dia),
        CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, math.rad(90), 0),
        color, material, parent, merge({ Shape = Enum.PartType.Cylinder }, extra))
end

-- Horizontal cylinder between two points (ropes, rails)
local function rod(name, a, b, dia, color, material, parent, extra)
    local mid = (a + b) / 2
    return cpart(name, Vector3.new((b - a).Magnitude, dia, dia),
        CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0),
        color, material, parent, merge({ Shape = Enum.PartType.Cylinder }, extra))
end

local function ball(name, pos, dia, color, material, parent, extra)
    return cpart(name, Vector3.new(dia, dia, dia), CFrame.new(pos), color, material, parent,
        merge({ Shape = Enum.PartType.Ball }, extra))
end

-- decoration players shouldn't snag on
local DECOR = { CanCollide = false }
local NOSHADOW = { CanCollide = false, CastShadow = false }

local function surface(p, face, pps, lightInfluence, brightness)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 50
    g.LightInfluence = lightInfluence or 0
    g.Brightness = brightness or 1.2
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

local function round(parent, scale)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(scale or 1, 0)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 2
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

local function pointLight(host, color, brightness, range, shadows)
    local l = Instance.new("PointLight")
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Shadows = shadows ~= false
    l.Parent = host
    return l
end

local function spotLight(host, face, color, brightness, range, angle, shadows)
    local l = Instance.new("SpotLight")
    l.Face = face
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Angle = angle
    l.Shadows = shadows ~= false
    l.Parent = host
    return l
end

-- invisible anchor for a light that has no visible fixture (Kenney lamps don't emit)
local function lightHolder(parent, pos)
    return cpart("LightSource", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), WARM, M.Glass, parent,
        { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
end

local function sub(parent, name)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

-- a plain sign: dark plate + one line of text, printed on `face`
local function signPlate(parent, name, x0, y0, z0, x1, y1, z1, face, msg, color, bg, pps)
    local p = box(name, x0, y0, z0, x1, y1, z1, bg or Color3.fromRGB(26, 26, 30), M.Metal, parent, DECOR)
    local g = surface(p, face, pps or 50, 0, 1.3)
    text({ Text = msg, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = color or Color3.fromRGB(240, 240, 240) }, g)
    return p
end

-- ── abstract art on a wall ─────────────────────────────────────────────
local ART_PALETTES = {
    { Color3.fromRGB(242, 160, 190), Color3.fromRGB(40, 60, 110), Color3.fromRGB(250, 200, 90), Color3.fromRGB(40, 190, 200) },
    { Color3.fromRGB(28, 34, 58), Color3.fromRGB(255, 90, 170), Color3.fromRGB(80, 220, 230), Color3.fromRGB(245, 235, 220) },
    { Color3.fromRGB(245, 232, 210), Color3.fromRGB(220, 80, 60), Color3.fromRGB(30, 30, 36), Color3.fromRGB(60, 150, 140) },
    { Color3.fromRGB(64, 150, 150), Color3.fromRGB(250, 210, 170), Color3.fromRGB(190, 90, 150), Color3.fromRGB(20, 40, 60) },
}

local function painting(parent, pos, normal, w, h, seed)
    local cf = CFrame.lookAt(pos, pos + normal)
    cpart("PaintingFrame", Vector3.new(w + 0.5, h + 0.5, 0.2), cf * CFrame.new(0, 0, -0.1), BRASS, M.Metal, parent, DECOR)
    local canvas = cpart("PaintingCanvas", Vector3.new(w, h, 0.06), cf * CFrame.new(0, 0, -0.23),
        Color3.fromRGB(240, 236, 228), M.Fabric, parent, NOSHADOW)
    local rng = Random.new(seed)
    local pal = ART_PALETTES[(seed % #ART_PALETTES) + 1]
    local g = surface(canvas, Enum.NormalId.Front, 30, 1, 1)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = pal[1], ClipsDescendants = true }, g)
    local aspect = h / w
    for i = 1, 4 do
        local s = rng:NextNumber(0.25, 0.7)
        local shape = frame({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85)),
            BackgroundColor3 = pal[(i % 3) + 2],
            BackgroundTransparency = rng:NextNumber(0, 0.25),
        }, bg)
        if i % 2 == 0 then
            shape.Size = UDim2.fromScale(s * aspect, s)
            round(shape)
        else
            shape.Size = UDim2.fromScale(s * 0.9, s * 0.35)
            shape.Rotation = rng:NextNumber(-35, 35)
        end
    end
    return canvas
end

-- ── fake window (no hole — frame + glass inset) ────────────────────────
local WARM_GLASS = Color3.fromRGB(255, 196, 130)
local DARK_GLASS = Color3.fromRGB(26, 34, 52)

local function fakeWindow(parent, pos, normal, w, h, lit, frameColor)
    local cf = CFrame.lookAt(pos, pos + normal)
    local fc = frameColor or BRONZE
    cpart("WindowFrame", Vector3.new(w + 0.6, h + 0.6, 0.2), cf * CFrame.new(0, 0, -0.1), fc, M.Metal, parent)
    local glass = cpart("WindowGlass", Vector3.new(w, h, 0.1), cf * CFrame.new(0, 0, -0.25),
        lit and WARM_GLASS or DARK_GLASS, M.Glass, parent, { Reflectance = 0.15 })
    cpart("Mullion", Vector3.new(0.14, h, 0.08), cf * CFrame.new(0, 0, -0.34), fc, M.Metal, parent, DECOR)
    cpart("Transom", Vector3.new(w, 0.14, 0.08), cf * CFrame.new(0, h * 0.25, -0.34), fc, M.Metal, parent, DECOR)
    if lit then
        local g = surface(glass, Enum.NormalId.Front, 8, 0, 0.8)
        local f = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WARM, BackgroundTransparency = 0.3 }, g)
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Transparency = NumberSequence.new(0.1, 0.65)
        grad.Parent = f
    end
    return glass
end

-- ── v2 gameplay markers ─────────────────────────────────────────────────
local function tagHide(p, label)
    CollectionService:AddTag(p, "HideSpot")
    p:SetAttribute("Label", label)
    return p
end

local function shadowZone(parent, list, x0, y0, z0, x1, y1, z1)
    local z = box("ShadowZone", x0, y0, z0, x1, y1, z1, Color3.new(0, 0, 0), M.Air, parent, {
        Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
    })
    CollectionService:AddTag(z, "ShadowZone")
    table.insert(list, z)
    return z
end

local function pairVents(a, b)
    CollectionService:AddTag(a, "Vent")
    CollectionService:AddTag(b, "Vent")
    a:SetAttribute("Pair", b.Name)
    b:SetAttribute("Pair", a.Name)
    return { a = a, b = b }
end

-- a floor-level crawl-vent grille on a wall. pos = centre on the wall face,
-- normal = out of the wall into the room
local function ventGrille(parent, name, pos, normal)
    local cf = CFrame.lookAt(pos, pos + normal)
    local g = cpart(name, Vector3.new(2.6, 1.8, 0.25), cf * CFrame.new(0, 0, -0.12), STEEL_LITE, M.DiamondPlate, parent)
    local sg = surface(g, Enum.NormalId.Front, 40, 1, 1)
    for i = 0, 5 do
        frame({ Size = UDim2.fromScale(0.86, 0.07), Position = UDim2.fromScale(0.07, 0.1 + i * 0.14),
            BackgroundColor3 = Color3.fromRGB(20, 22, 26) }, sg)
    end
    cpart(name .. "Frame", Vector3.new(3.0, 2.2, 0.12), cf * CFrame.new(0, 0, -0.02), STEEL, M.Metal, parent, DECOR)
    return g
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: slab, floors, walls, ceilings, roofs
-- ──────────────────────────────────────────────
function BankBuilder:_shell(f)
    -- structural slab under the whole building, then finished floors split at wall centres
    box("BaseSlab", 85, 0, 9, 131, FLOOR - 0.2, 54, Color3.fromRGB(110, 106, 102), M.Concrete, f)
    local floors = {
        { "HallFloor",     85,  9,  131, 28, MARBLE,                        M.Marble },
        { "SecurityFloor", 85,  28, 100, 39, Color3.fromRGB(56, 58, 64),    M.Slate },
        { "CorridorFloor", 100, 28, 131, 39, Color3.fromRGB(188, 190, 186), M.CeramicTiles },
        { "VaultFloor",    85,  39, 107, 54, Color3.fromRGB(84, 88, 96),    M.DiamondPlate },
        { "LaserFloor",    107, 39, 119, 54, Color3.fromRGB(44, 46, 52),    M.Metal },
        { "BreakFloor",    119, 39, 131, 54, Color3.fromRGB(214, 206, 188), M.CeramicTiles },
    }
    for _, fl in ipairs(floors) do
        box(fl[1], fl[2], FLOOR - 0.2, fl[3], fl[4], FLOOR, fl[5], fl[6], fl[7], f)
    end
    -- hall floor: black marble border + gold compass rose in the middle of the public area
    box("HallBorderN", 85, FLOOR, 9, 131, FLOOR + 0.02, 9.8, MARBLE_DK, M.Marble, f, NOSHADOW)
    box("HallBorderW", 85, FLOOR, 9, 85.8, FLOOR + 0.02, 28, MARBLE_DK, M.Marble, f, NOSHADOW)
    box("HallBorderE", 130.2, FLOOR, 9, 131, FLOOR + 0.02, 28, MARBLE_DK, M.Marble, f, NOSHADOW)
    box("TellerCarpet", 85.8, FLOOR, 22.4, 130.2, FLOOR + 0.02, 27.5, Color3.fromRGB(40, 58, 62), M.Fabric, f, NOSHADOW)
    vcyl("CompassRing", 108, FLOOR, FLOOR + 0.03, 15, 7.6, BRASS, M.Metal, f, NOSHADOW)
    vcyl("CompassRose", 108, FLOOR, FLOOR + 0.04, 15, 7, MARBLE_DK, M.Marble, f, NOSHADOW)
    local roseTop = box("CompassStar", 105.2, FLOOR + 0.04, 12.2, 110.8, FLOOR + 0.05, 17.8, MARBLE_DK, M.Marble, f,
        merge(NOSHADOW, { Transparency = 1 }))
    local rg = surface(roseTop, Enum.NormalId.Top, 30, 1, 1)
    for k = 0, 3 do
        frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.09, 0.95),
            Rotation = k * 45, BackgroundColor3 = (k % 2 == 0) and GOLD or Color3.fromRGB(210, 200, 180) }, rg)
    end

    -- porch + the doorway threshold
    box("Porch", 96, 0, 3, 120, FLOOR, 8, LIMESTONE, M.Limestone, f)
    box("Threshold", 104, 0, 8, 112, FLOOR, 9, BRONZE, M.Metal, f)

    -- ── exterior walls ──
    box("WallWestHall", 84, 0, 9, 85, HALL_CEIL, 28.5, SAND, M.Plaster, f)
    box("WallWestBack", 84, 0, 28.5, 85, BACK_CEIL, 55, SAND, M.Plaster, f)
    box("WallEastHall", 131, 0, 9, 132, HALL_CEIL, 28.5, SAND, M.Plaster, f)
    box("WallEastBack", 131, 0, 28.5, 132, BACK_CEIL, 44.5, SAND, M.Plaster, f)
    box("WallEastBack", 131, 0, 51.5, 132, BACK_CEIL, 55, SAND, M.Plaster, f)
    box("StaffDoorHeader", 131, FLOOR + 9, 44.5, 132, BACK_CEIL, 51.5, SAND, M.Plaster, f)
    box("WallSouth", 85, 0, 54, 131, BACK_CEIL, 55, SAND, M.Plaster, f)
    -- hall front wall (behind the portico), bronze doors x 104..112, 11 tall
    box("WallFront", 96, 0, 8, 104, HALL_CEIL, 9, LIMESTONE, M.Limestone, f)
    box("WallFront", 112, 0, 8, 120, HALL_CEIL, 9, LIMESTONE, M.Limestone, f)
    box("FrontDoorHeader", 104, FLOOR + 11, 8, 112, HALL_CEIL, 9, LIMESTONE, M.Limestone, f)

    -- ── interior walls (1 thick, centred on the lines) ──
    -- hall south wall z 28 — rises to the hall roof; doorways x 88..95 and 121..128
    box("HallSouthWall", 85, FLOOR, 27.5, 88, HALL_CEIL, 28.5, INTERIOR, M.Plaster, f)
    box("HallSouthWall", 95, FLOOR, 27.5, 121, HALL_CEIL, 28.5, INTERIOR, M.Plaster, f)
    box("HallSouthWall", 128, FLOOR, 27.5, 131, HALL_CEIL, 28.5, INTERIOR, M.Plaster, f)
    box("HallSouthHeader", 88, DOOR_TOP, 27.5, 95, HALL_CEIL, 28.5, INTERIOR, M.Plaster, f)
    box("HallSouthHeader", 121, DOOR_TOP, 27.5, 128, HALL_CEIL, 28.5, INTERIOR, M.Plaster, f)
    -- z 39: corridor | vault / lasers / break room — keycard door x 109.5..116.5, break door x 122..129
    box("Wall39", 85, FLOOR, 38.5, 109.5, BACK_CEIL, 39.5, STAFF_WALL, M.Plaster, f)
    box("Wall39", 116.5, FLOOR, 38.5, 122, BACK_CEIL, 39.5, STAFF_WALL, M.Plaster, f)
    box("Wall39", 129, FLOOR, 38.5, 131, BACK_CEIL, 39.5, STAFF_WALL, M.Plaster, f)
    box("Wall39Header", 109.5, DOOR_TOP, 38.5, 116.5, BACK_CEIL, 39.5, STAFF_WALL, M.Plaster, f)
    box("Wall39Header", 122, DOOR_TOP, 38.5, 129, BACK_CEIL, 39.5, STAFF_WALL, M.Plaster, f)
    -- x 100: security | staff corridor, doorway z 30.5..37.5
    box("Wall100", 99.5, FLOOR, 28.5, 100.5, BACK_CEIL, 30.5, STAFF_WALL, M.Plaster, f)
    box("Wall100", 99.5, FLOOR, 37.5, 100.5, BACK_CEIL, 38.5, STAFF_WALL, M.Plaster, f)
    box("Wall100Header", 99.5, DOOR_TOP, 30.5, 100.5, BACK_CEIL, 37.5, STAFF_WALL, M.Plaster, f)
    -- x 107: vault | laser corridor — round opening behind the vault door
    box("VaultWallE", 106.5, FLOOR, 39.5, 107.5, BACK_CEIL, 45.2, VSTEEL, M.Metal, f)
    box("VaultWallE", 106.5, FLOOR, 52.8, 107.5, BACK_CEIL, 54, VSTEEL, M.Metal, f)
    box("VaultSill", 106.5, FLOOR, 45.2, 107.5, FLOOR + 0.8, 52.8, STEEL, M.Metal, f)
    box("VaultHeader", 106.5, FLOOR + 9.8, 45.2, 107.5, BACK_CEIL, 52.8, VSTEEL, M.Metal, f)
    -- x 119: laser corridor | break room
    box("Wall119", 118.5, FLOOR, 39.5, 119.5, BACK_CEIL, 54, STAFF_WALL, M.Plaster, f)

    -- wainscot: dark green marble band round the banking hall
    box("WainscotW", 85, FLOOR, 9, 85.15, FLOOR + 3, 27.5, MARBLE_GRN, M.Marble, f, DECOR)
    box("WainscotE", 130.85, FLOOR, 9, 131, FLOOR + 3, 27.5, MARBLE_GRN, M.Marble, f, DECOR)
    box("WainscotS", 85, FLOOR, 27.35, 131, FLOOR + 3, 27.5, MARBLE_GRN, M.Marble, f, DECOR)
    box("WainscotN", 85, FLOOR, 9, 104, FLOOR + 3, 9.15, MARBLE_GRN, M.Marble, f, DECOR)
    box("WainscotN", 112, FLOOR, 9, 131, FLOOR + 3, 9.15, MARBLE_GRN, M.Marble, f, DECOR)

    -- ── ceilings + roofs ──
    box("HallRoof", 84, HALL_CEIL, 8, 132, HALL_CEIL + 1, 28.5, Color3.fromRGB(196, 188, 176), M.Concrete, f)
    box("BackRoof", 84, BACK_CEIL, 28.5, 132, BACK_CEIL + 1, 55, Color3.fromRGB(176, 170, 162), M.Concrete, f)
    box("VaultCeiling", 85, FLOOR + 14, 39.5, 106.5, FLOOR + 14.5, 54, STEEL, M.Metal, f)
    box("LaserCeiling", 107.5, FLOOR + 12, 39.5, 118.5, FLOOR + 12.5, 54, STEEL, M.Metal, f)
    -- coffered hall ceiling: beams + gold trim
    for _, z in ipairs({ 14.5, 21.5 }) do
        box("CeilingBeam", 85, HALL_CEIL - 1, z - 0.5, 131, HALL_CEIL, z + 0.5, LIMESTONE, M.Plaster, f, DECOR)
    end
    for _, x in ipairs({ 96, 108, 120 }) do
        box("CeilingBeam", x - 0.5, HALL_CEIL - 1, 9, x + 0.5, HALL_CEIL, 27.5, LIMESTONE, M.Plaster, f, DECOR)
    end
    box("CorniceGoldN", 85, HALL_CEIL - 1.2, 9, 131, HALL_CEIL - 1, 9.4, GOLD, M.Metal, f, NOSHADOW)
    box("CorniceGoldS", 85, HALL_CEIL - 1.2, 27.1, 131, HALL_CEIL - 1, 27.5, GOLD, M.Metal, f, NOSHADOW)

    -- ── parapets ──
    box("HallParapetW", 84, HALL_CEIL + 1, 9, 85, HALL_CEIL + 2.5, 28.5, SAND, M.Plaster, f)
    box("HallParapetE", 131, HALL_CEIL + 1, 9, 132, HALL_CEIL + 2.5, 28.5, SAND, M.Plaster, f)
    box("HallParapetS", 85, HALL_CEIL + 1, 27.5, 131, HALL_CEIL + 2.5, 28.5, SAND, M.Plaster, f)
    box("BackParapetW", 84, BACK_CEIL + 1, 28.5, 85, BACK_CEIL + 2.5, 55, SAND, M.Plaster, f)
    box("BackParapetS", 85, BACK_CEIL + 1, 54, 131, BACK_CEIL + 2.5, 55, SAND, M.Plaster, f)
    -- east parapet has a gap at z 33..35 where the fire-escape ladder tops out
    box("BackParapetE", 131, BACK_CEIL + 1, 28.5, 132, BACK_CEIL + 2.5, 33, SAND, M.Plaster, f)
    box("BackParapetE", 131, BACK_CEIL + 1, 35, 132, BACK_CEIL + 2.5, 55, SAND, M.Plaster, f)

    -- exterior plinth band (granite)
    box("PlinthW", 83.8, 0, 9, 84, 1.6, 55.2, MARBLE_DK, M.Granite, f)
    box("PlinthS", 84, 0, 55, 132, 1.6, 55.2, MARBLE_DK, M.Granite, f)
    box("PlinthE", 132, 0, 9, 132.2, 1.6, 44.5, MARBLE_DK, M.Granite, f)
    box("PlinthE", 132, 0, 51.5, 132.2, 1.6, 55.2, MARBLE_DK, M.Granite, f)
    -- teal speed lines under the back parapet (west + south faces)
    for i, y in ipairs({ 15.6, 16.3, 17.0 }) do
        box("SpeedLineW" .. i, 83.8, y, 28.5, 84, y + 0.35, 55.2, TEAL, M.Plaster, f, DECOR)
        box("SpeedLineS" .. i, 84, y, 55, 132, y + 0.35, 55.2, TEAL, M.Plaster, f, DECOR)
    end

    -- fake windows on the outer faces
    for _, z in ipairs({ 13, 19, 25 }) do
        fakeWindow(f, Vector3.new(84, 17, z), Vector3.new(-1, 0, 0), 3, 9, z == 19)
        fakeWindow(f, Vector3.new(132, 17, z), Vector3.new(1, 0, 0), 3, 9, false)
    end
    for _, z in ipairs({ 33, 44, 50 }) do
        fakeWindow(f, Vector3.new(84, 8, z), Vector3.new(-1, 0, 0), 3, 5, false)
    end
    for _, x in ipairs({ 92, 100, 124 }) do
        fakeWindow(f, Vector3.new(x, 8, 55), Vector3.new(0, 0, 1), 3, 5, x == 124)
    end
end

-- ──────────────────────────────────────────────
-- 🏛 FACADE: steps, pylons, columns, entablature + "OCEAN BANK" sign, doors
-- ──────────────────────────────────────────────
function BankBuilder:_facade(f, refs)
    -- apron between the sidewalk and the lot, then three broad steps up to the porch
    box("Apron", 95, 0, -1.4, 121, 0.5, 1, LIMESTONE, M.Limestone, f)
    box("Step1", 96, 0, 1, 120, 1.0, 2, LIMESTONE, M.Limestone, f)
    box("Step2", 96, 0, 2, 120, 1.5, 3, LIMESTONE, M.Limestone, f)
    box("StepNosing1", 96, 0.95, 1, 120, 1.05, 1.15, BRONZE, M.Metal, f, NOSHADOW)
    box("StepNosing2", 96, 1.45, 2, 120, 1.55, 2.15, BRONZE, M.Metal, f, NOSHADOW)
    box("StepNosing3", 96, 1.95, 3, 120, 2.05, 3.15, BRONZE, M.Metal, f, NOSHADOW)
    -- uplights on the bottom step washing the columns + sign
    for _, x in ipairs({ 97.2, 118.8 }) do
        local up = cpart("Uplight", Vector3.new(0.6, 0.3, 0.6),
            CFrame.new(x, 1.15, 1.5) * CFrame.Angles(math.rad(18), 0, 0), STEEL, M.Metal, f, DECOR)
        spotLight(up, Enum.NormalId.Top, WARM, 2.2, 26, 40, false)
    end
    box("PorchInlay", 104, FLOOR, 5, 112, FLOOR + 0.02, 8, VELVET, M.Fabric, f, NOSHADOW)

    -- ── the two corner pylons (x 84..96 and 120..132) ──
    for _, cx in ipairs({ 90, 126 }) do
        local x0, x1 = cx - 6, cx + 6
        box("Pylon", x0, 0, 1.3, x1, 30, 9, LIMESTONE, M.Limestone, f)
        box("PylonPlinth", x0 - 0.2, 0, 1, x1 + 0.2, 2.2, 1.3, MARBLE_DK, M.Granite, f)
        box("PylonCrown1", x0 + 0.5, 30, 1.8, x1 - 0.5, 31, 8.5, SAND, M.Limestone, f)
        box("PylonCrown2", x0 + 1.5, 31, 2.8, x1 - 1.5, 32, 7.5, LIMESTONE, M.Limestone, f)
        box("PylonCrown3", x0 + 3, 32, 3.8, x1 - 3, 33, 6.5, SAND, M.Limestone, f)
        vcyl("PylonFinial", cx, 33, 37, 5.2, 0.4, STEEL_LITE, M.Metal, f, DECOR)
        local tip = ball("PylonBeacon", Vector3.new(cx, 37.3, 5.2), 0.6, CYAN, M.Neon, f, NOSHADOW)
        pointLight(tip, CYAN, 0.8, 8, false)
        -- vertical deco fins with glass-block strips between them
        for _, dx in ipairs({ -3.6, 0, 3.6 }) do
            box("PylonFin", cx + dx - 0.4, 3, 1.0, cx + dx + 0.4, 29, 1.3, SAND, M.Limestone, f)
        end
        for _, dx in ipairs({ -1.8, 1.8 }) do
            local gb = box("GlassBlock", cx + dx - 1.1, 5, 1.2, cx + dx + 1.1, 27, 1.3, Color3.fromRGB(255, 214, 160), M.Glass, f,
                { Transparency = 0.1, Reflectance = 0.1 })
            local g = surface(gb, Enum.NormalId.Front, 6, 0, 0.7)
            local grid = Instance.new("UIGridLayout")
            grid.CellSize = UDim2.fromScale(0.44, 0.04)
            grid.CellPadding = UDim2.fromScale(0.06, 0.006)
            grid.Parent = g
            for _ = 1, 44 do
                frame({ BackgroundColor3 = Color3.fromRGB(255, 226, 180), BackgroundTransparency = 0.35 }, g)
            end
        end
        -- teal speed lines round the pylon
        for i, y in ipairs({ 23.0, 23.7, 24.4 }) do
            box("PylonBand" .. i, x0 - 0.1, y, 1.2, x1 + 0.1, y + 0.35, 9, TEAL, M.Plaster, f, DECOR)
        end
        -- flag on the pylon top
        vcyl("FlagPole", cx + 4.5, 30, 38, 3, 0.25, STEEL_LITE, M.Metal, f, DECOR)
        box("Flag", cx + 4.6, 35.5, 3, cx + 4.7, 37.8, 6.6, TEAL, M.Fabric, f, NOSHADOW)
    end

    -- ── four columns on the porch (clear gap x 103.6..112.4 for the doors) ──
    for _, x in ipairs({ 98.5, 102.4, 113.6, 117.5 }) do
        box("ColumnBase", x - 1.4, FLOOR, 4.1, x + 1.4, FLOOR + 0.8, 6.9, LIMESTONE, M.Limestone, f)
        vcyl("ColumnShaft", x, FLOOR + 0.8, 15.4, 5.5, 2.0, LIMESTONE, M.Limestone, f)
        vcyl("ColumnRing", x, FLOOR + 1.0, FLOOR + 1.3, 5.5, 2.2, BRONZE, M.Metal, f, DECOR)
        vcyl("ColumnRing", x, 14.8, 15.1, 5.5, 2.2, BRONZE, M.Metal, f, DECOR)
        box("ColumnCapital", x - 1.4, 15.4, 4.1, x + 1.4, 16, 6.9, BRONZE, M.Metal, f)
    end

    -- ── entablature over the porch ──
    box("Entablature", 96, 16, 3, 120, 19, 8, LIMESTONE, M.Limestone, f)
    box("Cornice", 95.6, 19, 2.6, 120.4, 19.5, 8, SAND, M.Limestone, f)
    box("Architrave", 96, 16, 2.85, 120, 16.3, 3, BRONZE, M.Metal, f, DECOR)
    -- soffit downlights over the door
    for _, x in ipairs({ 104, 112 }) do
        local fx = box("SoffitLight", x - 0.4, 15.85, 5.1, x + 0.4, 16, 5.9, BRASS, M.Metal, f, DECOR)
        spotLight(fx, Enum.NormalId.Bottom, WARM, 1.4, 18, 80, true)
    end

    -- THE SIGN: "OCEAN BANK" in bronze letters on the frieze, cyan neon tube under it
    local sign = box("BankSign", 98.5, 16.45, 2.7, 117.5, 18.85, 2.85, Color3.fromRGB(26, 28, 34), M.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 40, 0, 2.2)
    local signText = text({
        Text = "OCEAN  BANK", Size = UDim2.fromScale(0.96, 0.72), Position = UDim2.fromScale(0.02, 0.06),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(246, 206, 120),
    }, sg)
    local signStroke = stroke(signText, CYAN, 3, 1)
    text({ Text = "EST. 1926  ·  MIAMI BEACH", Size = UDim2.fromScale(0.5, 0.16), Position = UDim2.fromScale(0.25, 0.8),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.medium,
        TextColor3 = Color3.fromRGB(200, 186, 150) }, sg)
    local tube = box("SignTube", 98.5, 16.3, 2.6, 117.5, 16.42, 2.72, Color3.fromRGB(50, 60, 64), M.Metal, f, NOSHADOW)
    local signLight = pointLight(sign, CYAN, 0, 18, false)

    -- ── above the entablature: tall deco window, fins, stepped crown ──
    fakeWindow(f, Vector3.new(108, 22.6, 8), Vector3.new(0, 0, -1), 9, 6, true)
    for _, sx in ipairs({ -1, 1 }) do
        box("CrownFin", 108 + sx * 5.6 - 0.35, 19.5, 7.4, 108 + sx * 5.6 + 0.35, 29.5, 8, SAND, M.Limestone, f)
        box("CrownFin", 108 + sx * 7.2 - 0.35, 19.5, 7.4, 108 + sx * 7.2 + 0.35, 28.5, 8, SAND, M.Limestone, f)
    end
    box("CrownStep1", 96, HALL_CEIL + 1, 8, 120, 28.5, 9, LIMESTONE, M.Limestone, f)
    box("CrownStep2", 100, 28.5, 8, 116, 29.5, 9, SAND, M.Limestone, f)
    box("CrownStep3", 104, 29.5, 8, 112, 30.8, 9, LIMESTONE, M.Limestone, f)
    local clockHost = box("CrownPlaque", 104.6, 29.6, 7.85, 111.4, 30.7, 8, Color3.fromRGB(30, 30, 34), M.Metal, f, DECOR)
    local cg = surface(clockHost, Enum.NormalId.Front, 40, 0, 1.4)
    text({ Text = "SAVINGS · TRUST · 1926", Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = GOLD }, cg)

    -- ── bronze door surround + transom grille ──
    box("DoorJamb", 103.4, FLOOR, 7.8, 104, FLOOR + 11.6, 8, BRONZE, M.Metal, f)
    box("DoorJamb", 112, FLOOR, 7.8, 112.6, FLOOR + 11.6, 8, BRONZE, M.Metal, f)
    box("DoorHead", 103.4, FLOOR + 11, 7.8, 112.6, FLOOR + 11.6, 8, BRONZE, M.Metal, f)
    local grille = box("TransomGrille", 104, FLOOR + 11.6, 7.85, 112, 15.8, 8, BRONZE, M.Metal, f, DECOR)
    local tg = surface(grille, Enum.NormalId.Front, 20, 1, 1)
    for k = 0, 6 do
        frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.03, 0.95),
            Rotation = (k - 3) * 22, BackgroundColor3 = Color3.fromRGB(90, 60, 30) }, tg)
    end
    -- the big bronze doors, standing open flat against the inside of the front wall
    for _, x0 in ipairs({ 100, 112 }) do
        local leaf = box("BronzeDoor", x0, FLOOR, 9, x0 + 4, FLOOR + 11, 9.25, BRONZE, M.Metal, f, { Reflectance = 0.05 })
        local lg = surface(leaf, Enum.NormalId.Back, 12, 1, 1)
        for r = 0, 2 do
            local pnl = frame({ Size = UDim2.fromScale(0.76, 0.26), Position = UDim2.fromScale(0.12, 0.05 + r * 0.31),
                BackgroundColor3 = Color3.fromRGB(128, 86, 46) }, lg)
            stroke(pnl, Color3.fromRGB(200, 150, 90), 2, 0.2)
        end
        box("DoorPull", x0 + (x0 < 108 and 0.3 or 3.4), FLOOR + 4.5, 9.25, x0 + (x0 < 108 and 0.6 or 3.7), FLOOR + 7.5, 9.45,
            BRASS, M.Metal, f, DECOR)
    end

    -- wall lanterns either side of the doors
    for _, x in ipairs({ 101.2, 114.8 }) do
        box("LanternBracket", x - 0.15, 9.2, 7.5, x + 0.15, 9.5, 8, BRONZE, M.Metal, f, DECOR)
        box("LanternCage", x - 0.4, 8.2, 7.0, x + 0.4, 9.8, 7.8, BRONZE, M.Metal, f, DECOR)
        local bulb = ball("LanternBulb", Vector3.new(x, 9, 7.4), 0.5, WARM, M.Neon, f, NOSHADOW)
        pointLight(bulb, WARM, 1.1, 14, true)
    end

    -- ── OPEN/CLOSED plaques either side of the doors ──
    refs.plaques = {}
    for _, x0 in ipairs({ 97.2, 116.3 }) do
        local plaque = box("HoursPlaque", x0, 6.2, 7.75, x0 + 2.5, 7.6, 8, Color3.fromRGB(24, 22, 26), M.Metal, f)
        local g = surface(plaque, Enum.NormalId.Front, 60, 0, 2)
        local label = text({
            Text = "CLOSED", Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
            TextColor3 = Color3.fromRGB(96, 96, 106),
        }, g)
        local st = stroke(label, SIGN_RED, 2, 1)
        local pt = box("PlaqueTube", x0 + 0.2, 6.0, 7.7, x0 + 2.3, 6.12, 7.82, Color3.fromRGB(60, 50, 56), M.Metal, f, NOSHADOW)
        local light = pointLight(pt, SIGN_RED, 1, 7, false)
        light.Enabled = false
        table.insert(refs.plaques, { label = label, stroke = st, tube = pt, light = light })
    end
    refs.sign = { stroke = signStroke, tube = tube, light = signLight }
end

-- ──────────────────────────────────────────────
-- 🏦 BANKING HALL (x 85..131, z 9..27.5)
--   G1 walks z 11.5, x 99.5..116.5 · G2 walks z 25.5, x 90..127
-- ──────────────────────────────────────────────
local function smallCash(f, loot, cx, y, cz, standPos)
    local m = Instance.new("Model")
    m.Name = "TellerCash"
    for i = 0, 2 do
        box("CashStack", cx - 0.9 + i * 0.62, y, cz - 0.3, cx - 0.35 + i * 0.62, y + 0.25 + (i % 2) * 0.12, cz + 0.3,
            Color3.fromRGB(96, 170, 104), M.Fabric, m)
        box("CashBand", cx - 0.9 + i * 0.62, y + 0.1, cz - 0.31, cx - 0.35 + i * 0.62, y + 0.16, cz + 0.31,
            Color3.fromRGB(236, 220, 150), M.Fabric, m, NOSHADOW)
    end
    m.Parent = f
    table.insert(loot, { kind = "Cash", cframe = CFrame.lookAt(standPos, Vector3.new(cx, standPos.Y, cz)), visual = m, inVault = false })
end

local function tellerStations()
    local list = {}
    for i = 0, 5 do
        table.insert(list, 92 + (i + 0.5) * (32 / 6))   -- 94.67, 100, 105.33, 110.67, 116, 121.33
    end
    return list
end

function BankBuilder:_hall(f, props, spots, loot, hides, shadows)
    -- ── chandeliers: three art-deco pendants down the hall ──
    for _, x in ipairs({ 96, 108, 120 }) do
        local cz = 15.5
        box("PendantRod", x - 0.08, 20.5, cz - 0.08, x + 0.08, HALL_CEIL - 1, cz + 0.08, BRASS, M.Metal, f, DECOR)
        vcyl("PendantTier1", x, 20.2, 20.5, cz, 3.6, BRASS, M.Metal, f, DECOR)
        vcyl("PendantTier2", x, 19.2, 20.2, cz, 2.6, Color3.fromRGB(255, 236, 214), M.Glass, f, merge(NOSHADOW, { Transparency = 0.15 }))
        vcyl("PendantTier3", x, 18.6, 19.2, cz, 1.6, BRASS, M.Metal, f, DECOR)
        local bulb = ball("PendantBulb", Vector3.new(x, 19.6, cz), 0.8, WARM, M.Neon, f, NOSHADOW)
        pointLight(bulb, WARM, 1.1, 30, true)
    end

    -- pilasters on the long walls
    for _, z in ipairs({ 12, 18, 24 }) do
        box("PilasterW", 85, FLOOR, z - 0.7, 85.5, HALL_CEIL - 1, z + 0.7, MARBLE_DK, M.Marble, f)
        box("PilasterE", 130.5, FLOOR, z - 0.7, 131, HALL_CEIL - 1, z + 0.7, MARBLE_DK, M.Marble, f)
    end
    -- inside faces of the tall windows (night blue)
    for _, z in ipairs({ 15, 21 }) do
        fakeWindow(f, Vector3.new(85, 17, z), Vector3.new(1, 0, 0), 3, 9, false)
        fakeWindow(f, Vector3.new(131, 17, z), Vector3.new(-1, 0, 0), 3, 9, false)
    end

    -- ── TELLER COUNTER (x 92..124, z 20..22.4) with six glass windows ──
    local top = FLOOR + 3.6
    box("CounterBase", 92, FLOOR, 20.2, 124, top - 0.2, 22.2, WOOD_DARK, M.WoodPlanks, f)
    box("CounterTop", 91.8, top - 0.2, 20, 124.2, top, 22.4, MARBLE, M.Marble, f)
    box("CounterKick", 92, FLOOR, 20.1, 124, FLOOR + 0.6, 20.2, BRASS, M.Metal, f, DECOR)
    box("CounterBand", 92, FLOOR + 1.6, 20.1, 124, FLOOR + 1.8, 20.2, BRASS, M.Metal, f, DECOR)
    for i = 0, 6 do
        local x = 92 + i * (32 / 6)
        box("TellerPost", x - 0.15, top, 20.8, x + 0.15, FLOOR + 8.6, 21.1, BRASS, M.Metal, f)
    end
    box("TellerHeader", 91.8, FLOOR + 8.6, 20.6, 124.2, FLOOR + 9.6, 21.3, WOOD_DARK, M.Wood, f)
    local header = box("TellerSigns", 91.8, FLOOR + 8.7, 20.5, 124.2, FLOOR + 9.5, 20.6, WOOD_DARK, M.Wood, f, DECOR)
    local hg = surface(header, Enum.NormalId.Front, 30, 0, 1.3)
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = hg
    for i = 1, 6 do
        text({ Text = "TELLER " .. i, LayoutOrder = i, Size = UDim2.fromScale(1 / 6, 1),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
            TextColor3 = GOLD }, hg)
    end
    local stations = tellerStations()
    for i, x in ipairs(stations) do
        -- glass screen with a pass-through slot at the bottom
        box("TellerGlass", x - 2.5, top + 1.1, 20.9, x + 2.5, FLOOR + 8.6, 21.0, GLASS_TINT, M.Glass, f,
            { Transparency = 0.6, Reflectance = 0.1 })
        -- teller's screen on the worktop, facing the teller side (south)
        table.insert(props, { kit = "furniture", name = "computerScreen", pos = Vector3.new(x + 1.1, top, 21.8), facing = Vector3.new(0, 0, 1), opts = { scale = 1.0 } })
        -- green banker's lamp on every other window
        if i % 2 == 1 then
            box("LampBase", x - 1.9, top, 21.5, x - 1.4, top + 0.12, 22, BRASS, M.Metal, f, DECOR)
            local shade = box("LampShade", x - 2.1, top + 0.6, 21.45, x - 1.2, top + 0.85, 22.05, Color3.fromRGB(40, 120, 70), M.Glass, f, DECOR)
            box("LampStem", x - 1.7, top + 0.12, 21.7, x - 1.6, top + 0.6, 21.8, BRASS, M.Metal, f, DECOR)
            pointLight(shade, Color3.fromRGB(255, 214, 150), 0.7, 10, true)
        end
        -- cash drawers under the worktop, teller side
        box("TellerDrawer", x - 1.2, FLOOR + 2.3, 22.2, x + 1.2, FLOOR + 2.9, 22.5, WOOD_MID, M.Wood, f, DECOR)
    end
    -- two drawers left open with cash in them (small loot — grab it any time)
    for _, i in ipairs({ 2, 5 }) do
        local x = stations[i]
        box("OpenDrawer", x - 1.2, FLOOR + 2.3, 22.5, x + 1.2, FLOOR + 2.5, 23.2, WOOD_MID, M.Wood, f)
        smallCash(f, loot, x, FLOOR + 2.5, 22.85, Vector3.new(x, FLOOR, 24))
    end
    -- keycard spots on the teller worktop (station 1 + station 6)
    table.insert(spots, CFrame.new(stations[1] - 0.6, top + 0.01, 21.9))
    table.insert(spots, CFrame.new(stations[6] - 0.6, top + 0.01, 21.9))

    -- ── teller back wall: big clock + bank crest + rope-free "vault" mural ──
    local clock = box("WallClock", 105.5, 14.5, 27.3, 110.5, 19.5, 27.5, BRASS, M.Metal, f, DECOR)
    local clg = surface(clock, Enum.NormalId.Front, 40, 1, 1)
    local dial = frame({ Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05),
        BackgroundColor3 = Color3.fromRGB(246, 240, 226) }, clg)
    round(dial)
    for k = 0, 11 do
        frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + 0.4 * math.sin(k * math.pi / 6), 0.5 - 0.4 * math.cos(k * math.pi / 6)),
            Size = UDim2.fromScale(0.03, 0.08), Rotation = k * 30, BackgroundColor3 = Color3.fromRGB(40, 36, 30) }, dial)
    end
    frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.035, 0.28),
        Rotation = 60, BackgroundColor3 = Color3.fromRGB(30, 26, 22) }, dial)
    frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.02, 0.4),
        Rotation = -20, BackgroundColor3 = Color3.fromRGB(30, 26, 22) }, dial)
    local crest = box("BankCrest", 96, 20.8, 27.35, 120, 22.6, 27.5, Color3.fromRGB(30, 32, 36), M.Metal, f, DECOR)
    local crg = surface(crest, Enum.NormalId.Front, 30, 0, 1.3)
    text({ Text = "OCEAN BANK  ·  YOUR MONEY IS SAFE WITH US", Size = UDim2.fromScale(0.96, 0.7), Position = UDim2.fromScale(0.02, 0.15),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = GOLD }, crg)
    painting(f, Vector3.new(97, 14.5, 27.5), Vector3.new(0, 0, -1), 5, 3.4, 71)
    painting(f, Vector3.new(119, 14.5, 27.5), Vector3.new(0, 0, -1), 5, 3.4, 72)

    -- supply closet at the west end of the teller area (HIDE SPOT)
    local closet = box("SupplyCloset", 85, FLOOR, 22.6, 87.5, FLOOR + 8, 27.5, WOOD_MID, M.Wood, f)
    local csg = surface(closet, Enum.NormalId.Right, 20, 1, 1)
    frame({ Size = UDim2.fromScale(0.012, 0.9), Position = UDim2.fromScale(0.494, 0.05), BackgroundColor3 = Color3.fromRGB(60, 40, 26) }, csg)
    frame({ Size = UDim2.fromScale(0.03, 0.05), Position = UDim2.fromScale(0.45, 0.5), BackgroundColor3 = BRASS }, csg)
    frame({ Size = UDim2.fromScale(0.03, 0.05), Position = UDim2.fromScale(0.52, 0.5), BackgroundColor3 = BRASS }, csg)
    table.insert(hides, tagHide(closet, "Closet"))
    shadowZone(f, shadows, 85, FLOOR, 22.4, 89.5, FLOOR + 8, 27.5)

    -- ── velvet-rope queue (x 110..118, z 14.5..18.5) — posts + ropes don't snag ──
    local rows = { 14.5, 16.5, 18.5 }
    for r, z in ipairs(rows) do
        local xs = { 110.5, 113, 115.5, 118 }
        for _, x in ipairs(xs) do
            vcyl("Stanchion", x, FLOOR, FLOOR + 3, z, 0.3, BRASS, M.Metal, f, DECOR)
            vcyl("StanchionBase", x, FLOOR, FLOOR + 0.15, z, 1.0, BRASS, M.Metal, f, DECOR)
            ball("StanchionTop", Vector3.new(x, FLOOR + 3.1, z), 0.45, BRASS, M.Metal, f, DECOR)
        end
        -- rope along the row, gap alternating ends so the line snakes
        local x0, x1 = 110.5, 118
        if r == 2 then x0 = 113 end
        if r ~= 2 then x1 = (r == 1) and 118 or 115.5 end
        rod("VelvetRope", Vector3.new(x0, FLOOR + 2.6, z), Vector3.new(x1, FLOOR + 2.6, z), 0.18, VELVET, M.Fabric, f, NOSHADOW)
    end
    local qs = box("QueueSign", 108.1, FLOOR + 2.4, 14.45, 110.3, FLOOR + 3.8, 14.55, Color3.fromRGB(26, 24, 30), M.Metal, f, DECOR)
    local qg = surface(qs, Enum.NormalId.Front, 60, 1, 1)
    text({ Text = "PLEASE WAIT HERE", Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = GOLD }, qg)
    vcyl("QueueSignPost", 109.2, FLOOR, FLOOR + 2.4, 14.5, 0.25, BRASS, M.Metal, f, DECOR)

    -- waiting benches (facing the tellers) + side tables
    table.insert(props, { kit = "furniture", name = "benchCushion", pos = Vector3.new(101.5, FLOOR, 16.5), facing = Vector3.new(0, 0, 1) })
    table.insert(props, { kit = "furniture", name = "benchCushion", pos = Vector3.new(105.5, FLOOR, 16.5), facing = Vector3.new(0, 0, 1) })
    table.insert(props, { kit = "furniture", name = "trashcan", pos = Vector3.new(107.8, FLOOR, 17.5), opts = { scale = 1.0 } })

    -- big potted palm in the east passage, under the lobby camera (HIDE SPOT)
    local pot = vcyl("BigPlanter", 129.7, FLOOR, FLOOR + 2.2, 18.4, 2.2, Color3.fromRGB(196, 110, 80), M.Slate, f)
    ball("PlanterLeaves", Vector3.new(129.7, FLOOR + 4.2, 18.4), 3.4, LEAF, M.Grass, f, DECOR)
    ball("PlanterLeaves", Vector3.new(129.4, FLOOR + 5.8, 18.2), 2.4, Color3.fromRGB(70, 140, 80), M.Grass, f, DECOR)
    table.insert(hides, tagHide(pot, "Big plant"))
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(86.2, FLOOR, 18.8) })

    -- ── glass manager offices (hall front corners) ──
    local function glassOffice(name, x0, x1, doorX0, doorX1, glassX, title)
        local gz0, gz1 = 15.3, 15.7
        box(name .. "GlassS", x0, FLOOR, gz0, doorX0, FLOOR + 8, gz1, GLASS_TINT, M.Glass, f, { Transparency = 0.55, Reflectance = 0.1 })
        box(name .. "GlassS", doorX1, FLOOR, gz0, x1, FLOOR + 8, gz1, GLASS_TINT, M.Glass, f, { Transparency = 0.55, Reflectance = 0.1 })
        box(name .. "GlassSide", glassX - 0.2, FLOOR, 9.25, glassX + 0.2, FLOOR + 8, gz0, GLASS_TINT, M.Glass, f, { Transparency = 0.55, Reflectance = 0.1 })
        box(name .. "RailS", x0, FLOOR + 8, gz0 - 0.05, x1, FLOOR + 8.4, gz1 + 0.05, BRASS, M.Metal, f)
        box(name .. "RailSide", glassX - 0.25, FLOOR + 8, 9.25, glassX + 0.25, FLOOR + 8.4, gz1, BRASS, M.Metal, f)
        box(name .. "Mullion", doorX0 - 0.15, FLOOR, gz0 - 0.05, doorX0, FLOOR + 8, gz1 + 0.05, BRASS, M.Metal, f, DECOR)
        box(name .. "Mullion", doorX1, FLOOR, gz0 - 0.05, doorX1 + 0.15, FLOOR + 8, gz1 + 0.05, BRASS, M.Metal, f, DECOR)
        -- gold lettering on the glass above the door
        local lp = box(name .. "Lettering", doorX0 - 1.5, FLOOR + 6.6, gz1, doorX1 + 1.5, FLOOR + 7.6, gz1 + 0.02, GLASS_TINT, M.Glass, f,
            merge(NOSHADOW, { Transparency = 1 }))
        local lg = surface(lp, Enum.NormalId.Back, 50, 1, 1)
        text({ Text = title, Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
            TextColor3 = GOLD }, lg)
    end
    glassOffice("MgrOffice", 85, 97, 88, 92, 97, "BRANCH MANAGER")
    glassOffice("LoanOffice", 119, 131, 124, 128, 119, "LOANS")

    -- manager office furniture (desk part-built so the keycard spot is exact)
    local function officeDesk(x0, x1, z0, z1)
        local dtop = FLOOR + 3.1
        box("OfficeDesk", x0, dtop - 0.3, z0, x1, dtop, z1, WOOD_DARK, M.WoodPlanks, f)
        box("OfficeDeskPanel", x0 + 0.1, FLOOR, z1 - 0.3, x1 - 0.1, dtop - 0.3, z1 - 0.1, WOOD_DARK, M.Wood, f)
        box("OfficeDeskLeg", x0 + 0.1, FLOOR, z0 + 0.1, x0 + 0.5, dtop - 0.3, z1 - 0.1, WOOD_DARK, M.Wood, f)
        box("OfficeDeskLeg", x1 - 0.5, FLOOR, z0 + 0.1, x1 - 0.1, dtop - 0.3, z1 - 0.1, WOOD_DARK, M.Wood, f)
        box("DeskBlotter", x0 + 1.2, dtop, z0 + 0.4, x1 - 1.2, dtop + 0.02, z1 - 0.4, Color3.fromRGB(40, 70, 52), M.Fabric, f, NOSHADOW)
        return dtop
    end
    local mTop = officeDesk(89, 94, 11.6, 13.4)
    table.insert(spots, CFrame.new(92.8, mTop + 0.03, 12.5))
    table.insert(props, { kit = "furniture", name = "laptop", pos = Vector3.new(90.6, mTop, 12.5), facing = Vector3.new(0, 0, -1), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "chairDesk", pos = Vector3.new(91.5, FLOOR, 10.3), facing = Vector3.new(0, 0, 1) })
    table.insert(props, { kit = "furniture", name = "lampSquareFloor", pos = Vector3.new(86, FLOOR, 10) })
    pointLight(lightHolder(f, Vector3.new(86, FLOOR + 7, 10)), WARM, 0.7, 12, true)
    painting(f, Vector3.new(91.5, 9, 9), Vector3.new(0, 0, 1), 3.2, 2.4, 73)
    -- side cabinet with the manager's jewellery box on it (small loot)
    box("SideCabinet", 94.9, FLOOR, 9.3, 96.6, FLOOR + 2.6, 11.3, WOOD_MID, M.Wood, f)
    box("SideCabinetTop", 94.85, FLOOR + 2.6, 9.25, 96.65, FLOOR + 2.75, 11.35, MARBLE, M.Marble, f)
    local jb = Instance.new("Model")
    jb.Name = "JewelBox"
    box("JewelBoxBase", 95.2, FLOOR + 2.75, 9.8, 96.3, FLOOR + 3.25, 10.8, Color3.fromRGB(90, 20, 40), M.Fabric, jb)
    box("JewelBoxLid", 95.2, FLOOR + 3.25, 9.75, 96.3, FLOOR + 3.95, 9.85, Color3.fromRGB(90, 20, 40), M.Fabric, jb)
    ball("Pearl", Vector3.new(95.5, FLOOR + 3.35, 10.3), 0.3, Color3.fromRGB(245, 240, 230), M.Glass, jb, NOSHADOW)
    local gem = ball("Ruby", Vector3.new(95.95, FLOOR + 3.4, 10.4), 0.35, Color3.fromRGB(255, 60, 110), M.Neon, jb, NOSHADOW)
    pointLight(gem, Color3.fromRGB(255, 90, 140), 0.6, 6, false)
    jb.Parent = f
    table.insert(loot, { kind = "Jewels", cframe = CFrame.lookAt(Vector3.new(95.7, FLOOR, 13.0), Vector3.new(95.7, FLOOR, 10.3)), visual = jb, inVault = false })
    shadowZone(f, shadows, 85, FLOOR, 9.2, 88.5, FLOOR + 8, 15.3)

    -- loans office
    local lTop = officeDesk(122, 127, 11.6, 13.4)
    table.insert(spots, CFrame.new(123.2, lTop + 0.03, 12.5))
    table.insert(props, { kit = "furniture", name = "computerScreen", pos = Vector3.new(125.4, lTop, 12.1), facing = Vector3.new(0, 0, 1), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "chairDesk", pos = Vector3.new(124.5, FLOOR, 10.3), facing = Vector3.new(0, 0, 1) })
    table.insert(props, { kit = "furniture", name = "chair", pos = Vector3.new(121.2, FLOOR, 14.2), facing = Vector3.new(0, 0, -1) })
    painting(f, Vector3.new(124.5, 9, 9), Vector3.new(0, 0, 1), 3.2, 2.4, 74)
    box("LoanCabinet", 128.9, FLOOR, 9.3, 130.6, FLOOR + 2.6, 11.3, WOOD_MID, M.Wood, f)
    box("LoanCabinetTop", 128.85, FLOOR + 2.6, 9.25, 130.65, FLOOR + 2.75, 11.35, MARBLE, M.Marble, f)
    smallCash(f, loot, 129.75, FLOOR + 2.75, 10.3, Vector3.new(129.0, FLOOR, 13.0))
    local lamp = box("LoanLampShade", 125.9, lTop + 0.9, 12.7, 126.8, lTop + 1.2, 13.2, Color3.fromRGB(40, 120, 70), M.Glass, f, DECOR)
    box("LoanLampStem", 126.3, lTop, 12.9, 126.4, lTop + 0.9, 13.0, BRASS, M.Metal, f, DECOR)
    pointLight(lamp, Color3.fromRGB(255, 214, 150), 0.8, 11, true)

    -- crawl vent in the manager's office (west wall, floor level) — pairs with the break room
    local vent = ventGrille(f, "Bank_VentOffice", Vector3.new(85, FLOOR + 1.1, 13.6), Vector3.new(1, 0, 0))
    return vent
end

-- ──────────────────────────────────────────────
-- 🖥 SECURITY ROOM (x 85..99.5, z 28.5..38.5) — breaker, roof hatch drop
--   G4 walks z 31.3, x 88.5..97
-- ──────────────────────────────────────────────
local function camFeed(p, face, label, seed)
    local g = surface(p, face, 60, 0, 1.3)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 26, 30), ClipsDescendants = true }, g)
    local rng = Random.new(seed)
    frame({ Size = UDim2.fromScale(1, 0.38), Position = UDim2.fromScale(0, 0.62), BackgroundColor3 = Color3.fromRGB(34, 54, 56) }, bg)
    for _ = 1, 3 do
        frame({
            AnchorPoint = Vector2.new(0.5, 1),
            Size = UDim2.fromScale(rng:NextNumber(0.08, 0.24), rng:NextNumber(0.15, 0.4)),
            Position = UDim2.fromScale(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.66, 0.82)),
            BackgroundColor3 = Color3.fromRGB(52, 76, 78),
        }, bg)
    end
    for i = 0, 11 do
        frame({ Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, i / 12),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7 }, bg)
    end
    text({ Text = label, Size = UDim2.fromScale(0.5, 0.13), Position = UDim2.fromScale(0.05, 0.05),
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(190, 255, 220) }, bg)
    local dot = frame({ Size = UDim2.fromScale(0.05, 0.07), Position = UDim2.fromScale(0.73, 0.08),
        BackgroundColor3 = Color3.fromRGB(255, 60, 60) }, bg)
    round(dot)
    text({ Text = "REC", Size = UDim2.fromScale(0.16, 0.11), Position = UDim2.fromScale(0.8, 0.06),
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(255, 120, 120) }, bg)
end

function BankBuilder:_security(f, props, spots, hides, shadows)
    -- monitor desk along the south wall, screens facing north (the operator's chair)
    local top = FLOOR + 3.1
    box("SecDesk", 88, top - 0.3, 36.2, 97.5, top, 38.5, Color3.fromRGB(58, 60, 66), M.Metal, f)
    box("SecDeskFront", 88, FLOOR, 36.2, 97.5, top - 0.3, 36.4, STEEL, M.Metal, f)
    local mid
    for i, x in ipairs({ 89.8, 92.75, 95.7 }) do
        box("MonitorStand", x - 0.3, top, 37.6, x + 0.3, top + 0.45, 38.1, STEEL, M.Metal, f)
        local mon = box("Monitor", x - 1.3, top + 0.45, 37.5, x + 1.3, top + 2.2, 37.75, Color3.fromRGB(20, 22, 26), M.Metal, f)
        camFeed(mon, Enum.NormalId.Front, string.format("CAM 0%d", i), i + 10)
        if i == 2 then mid = mon end
    end
    pointLight(mid, Color3.fromRGB(120, 170, 255), 0.9, 12, true)
    table.insert(spots, CFrame.new(94.2, top + 0.01, 36.9))
    table.insert(props, { kit = "furniture", name = "computerKeyboard", pos = Vector3.new(92.75, top, 36.9), facing = Vector3.new(0, 0, -1), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "chairDesk", pos = Vector3.new(92.75, FLOOR, 35.0), facing = Vector3.new(0, 0, 1) })

    -- BREAKER: grey electrical panel on the north wall (x 96..98.5), facing into the room
    local breaker = box("Breaker", 96, FLOOR + 2, 28.5, 98.5, FLOOR + 6, 29, Color3.fromRGB(122, 126, 132), M.Metal, f)
    local bg = surface(breaker, Enum.NormalId.Back, 40, 1, 1)
    text({ Text = "MAIN · CCTV", Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(30, 32, 36) }, bg)
    local sw = frame({ Size = UDim2.fromScale(0.8, 0.62), Position = UDim2.fromScale(0.1, 0.28), BackgroundTransparency = 1 }, bg)
    local swGrid = Instance.new("UIGridLayout")
    swGrid.CellSize = UDim2.fromScale(0.28, 0.14)
    swGrid.CellPadding = UDim2.fromScale(0.06, 0.03)
    swGrid.Parent = sw
    for _ = 1, 12 do
        local s = frame({ BackgroundColor3 = Color3.fromRGB(40, 42, 48) }, sw)
        frame({ Size = UDim2.fromScale(0.35, 0.8), Position = UDim2.fromScale(0.1, 0.1), BackgroundColor3 = Color3.fromRGB(210, 210, 214) }, s)
    end
    for i, x in ipairs({ 96.6, 97.25, 97.9 }) do
        box("BreakerLED", x - 0.1, FLOOR + 5.55, 29.0, x + 0.1, FLOOR + 5.75, 29.07,
            i == 3 and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(80, 240, 120), M.Neon, f, NOSHADOW)
    end
    box("BreakerConduit", 97.1, FLOOR + 6, 28.55, 97.4, BACK_CEIL, 28.8, STEEL, M.Metal, f, DECOR)
    signPlate(f, "DangerSign", 96.2, FLOOR + 6.4, 28.5, 98.3, FLOOR + 7.2, 28.55, Enum.NormalId.Back, "DANGER · HIGH VOLTAGE",
        Color3.fromRGB(30, 28, 20), Color3.fromRGB(250, 200, 40))

    -- server rack in the NE corner (east of the breaker, clear of the doorway z 30.5..37.5)
    local rack = box("ServerRack", 97.6, FLOOR, 36.4, 99.5, FLOOR + 7, 38.5, Color3.fromRGB(28, 30, 36), M.Metal, f)
    local rg = surface(rack, Enum.NormalId.Left, 20, 0, 1.2)
    local rng = Random.new(91)
    for r = 0, 8 do
        local unit = frame({ Size = UDim2.fromScale(0.9, 0.08), Position = UDim2.fromScale(0.05, 0.05 + r * 0.1),
            BackgroundColor3 = Color3.fromRGB(44, 48, 56) }, rg)
        for k = 0, 3 do
            frame({ Size = UDim2.fromScale(0.05, 0.35), Position = UDim2.fromScale(0.08 + k * 0.08, 0.32),
                BackgroundColor3 = (rng:NextNumber() < 0.75) and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(250, 180, 60) }, unit)
        end
    end

    -- ceiling lamp (dim, cool)
    box("SecLampCable", 92.7, 15.5, 33.2, 92.8, BACK_CEIL, 33.3, STEEL, M.Metal, f, DECOR)
    vcyl("SecLampShade", 92.75, 14.9, 15.5, 33.25, 1.6, STEEL, M.Metal, f, DECOR)
    local b = ball("SecLampBulb", Vector3.new(92.75, 14.8, 33.25), 0.35, COOL, M.Neon, f, NOSHADOW)
    pointLight(b, COOL, 0.6, 14, true)

    -- coat closet in the SW corner (HIDE SPOT)
    local closet = box("CoatCloset", 85, FLOOR, 35.8, 87.6, FLOOR + 8, 38.5, Color3.fromRGB(110, 116, 124), M.Metal, f)
    local csg = surface(closet, Enum.NormalId.Right, 20, 1, 1)
    for i = 0, 5 do
        frame({ Size = UDim2.fromScale(0.5, 0.012), Position = UDim2.fromScale(0.25, 0.08 + i * 0.03),
            BackgroundColor3 = Color3.fromRGB(60, 64, 70) }, csg)
    end
    table.insert(hides, tagHide(closet, "Closet"))

    -- roof hatch (ceiling) with a steel ladder down the west wall — inside end of the roof vent
    box("CeilingHatchFrame", 85.2, BACK_CEIL - 0.15, 29.5, 88, BACK_CEIL, 32, STEEL, M.Metal, f, DECOR)
    box("CeilingHatch", 85.4, BACK_CEIL - 0.2, 29.7, 87.8, BACK_CEIL - 0.1, 31.8, Color3.fromRGB(80, 84, 92), M.DiamondPlate, f, DECOR)
    for _, z in ipairs({ 30.1, 31.4 }) do
        box("LadderRail", 85, FLOOR, z - 0.1, 85.5, BACK_CEIL, z + 0.1, STEEL_LITE, M.Metal, f, DECOR)
    end
    for y = FLOOR + 1, BACK_CEIL - 1, 1.2 do
        box("LadderRung", 85.1, y, 30.1, 85.4, y + 0.15, 31.4, STEEL_LITE, M.Metal, f, DECOR)
    end
    -- (LookVector points into the room = where a player should appear)
    local hatchIn = cpart("Bank_RoofHatchInside", Vector3.new(1.7, 3.2, 0.55),
        CFrame.lookAt(Vector3.new(85.33, FLOOR + 1.8, 30.75), Vector3.new(90, FLOOR + 1.8, 30.75)),
        Color3.fromRGB(90, 96, 104), M.DiamondPlate, f)
    shadowZone(f, shadows, 85, FLOOR, 28.5, 88.3, FLOOR + 10, 33.2)

    table.insert(props, { kit = "furniture", name = "trashcan", pos = Vector3.new(86.3, FLOOR, 34.6), opts = { scale = 1.0 } })
    return breaker, hatchIn
end

-- ──────────────────────────────────────────────
-- 🚪 STAFF CORRIDOR (x 100.5..131, z 28.5..38.5) + keycard door
--   G3 walks z 33.5, x 103.5..127.5
-- ──────────────────────────────────────────────
function BankBuilder:_corridor(f, props, hides, shadows)
    -- fluorescent panels (dim — this is after hours)
    for _, x in ipairs({ 106, 116, 126 }) do
        local panel = box("CeilingPanel", x - 1.6, BACK_CEIL - 0.12, 33, x + 1.6, BACK_CEIL, 34, Color3.fromRGB(236, 240, 245), M.Glass, f, NOSHADOW)
        local sl = Instance.new("SurfaceLight")
        sl.Face = Enum.NormalId.Bottom
        sl.Color = COOL
        sl.Brightness = 0.7
        sl.Range = 14
        sl.Angle = 110
        sl.Parent = panel
    end
    -- dado rail + skirting
    box("DadoN", 100.5, FLOOR + 3.4, 28.5, 121, FLOOR + 3.6, 28.65, TEAL_DARK, M.Wood, f, DECOR)
    box("DadoS", 100.5, FLOOR + 3.4, 38.35, 109.5, FLOOR + 3.6, 38.5, TEAL_DARK, M.Wood, f, DECOR)

    -- water cooler + noticeboard on the north wall, well clear of G3's line (z 33.5)
    box("WaterCooler", 103.6, FLOOR, 28.6, 104.9, FLOOR + 3, 29.8, Color3.fromRGB(230, 232, 236), M.Metal, f)
    vcyl("WaterBottle", 104.25, FLOOR + 3, FLOOR + 4.6, 29.2, 1.0, Color3.fromRGB(140, 200, 240), M.Glass, f,
        merge(DECOR, { Transparency = 0.3 }))
    local nb = box("NoticeBoard", 106, FLOOR + 3.8, 28.5, 111, FLOOR + 7, 28.65, Color3.fromRGB(150, 110, 70), M.Wood, f, DECOR)
    local ng = surface(nb, Enum.NormalId.Back, 30, 1, 1)
    text({ Text = "STAFF NOTICES", Size = UDim2.fromScale(0.9, 0.16), Position = UDim2.fromScale(0.05, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(40, 28, 18) }, ng)
    local rng = Random.new(5)
    for _ = 1, 6 do
        frame({ Size = UDim2.fromScale(rng:NextNumber(0.16, 0.24), rng:NextNumber(0.22, 0.32)),
            Position = UDim2.fromScale(rng:NextNumber(0.03, 0.75), rng:NextNumber(0.26, 0.62)),
            Rotation = rng:NextNumber(-6, 6),
            BackgroundColor3 = (rng:NextNumber() < 0.5) and Color3.fromRGB(250, 246, 230) or Color3.fromRGB(255, 236, 140) }, ng)
    end
    -- wayfinding signs
    signPlate(f, "SignSecurity", 100.55, FLOOR + 10.4, 32.5, 100.65, FLOOR + 11.4, 35.5, Enum.NormalId.Right, "SECURITY",
        Color3.fromRGB(230, 230, 230))
    signPlate(f, "SignVault", 110, FLOOR + 10.3, 38.35, 116, FLOOR + 11.5, 38.5, Enum.NormalId.Front, "VAULT · AUTHORISED STAFF ONLY",
        Color3.fromRGB(255, 90, 90))
    signPlate(f, "SignBreak", 122.5, FLOOR + 10.3, 38.35, 128.5, FLOOR + 11.5, 38.5, Enum.NormalId.Front, "BREAK ROOM",
        Color3.fromRGB(230, 230, 230), Color3.fromRGB(34, 80, 76))
    painting(f, Vector3.new(118.5, 8, 28.5), Vector3.new(0, 0, 1), 3.2, 2.2, 75)
    -- fire extinguisher
    vcyl("Extinguisher", 130.4, FLOOR + 1.2, FLOOR + 3, 30.2, 0.6, Color3.fromRGB(200, 30, 30), M.Metal, f, DECOR)

    -- janitor cart (HIDE SPOT) tucked into the east end
    local cart = box("JanitorCart", 129.3, FLOOR + 0.4, 35.9, 131, FLOOR + 3.4, 38.4, Color3.fromRGB(230, 190, 40), M.Metal, f)
    box("CartBag", 129.4, FLOOR + 3.4, 36.1, 130.9, FLOOR + 4.3, 37.3, Color3.fromRGB(40, 40, 44), M.Fabric, f, DECOR)
    vcyl("MopHandle", 130.5, FLOOR + 3.4, FLOOR + 7, 37.9, 0.15, WOOD_MID, M.Wood, f, DECOR)
    for _, z in ipairs({ 36.2, 38.1 }) do
        for _, x in ipairs({ 129.6, 130.7 }) do
            ball("CartWheel", Vector3.new(x, FLOOR + 0.2, z), 0.4, STEEL, M.Metal, f, DECOR)
        end
    end
    table.insert(hides, tagHide(cart, "Cleaning cart"))

    shadowZone(f, shadows, 100.5, FLOOR, 28.5, 103, FLOOR + 10, 38.5)

    -- ── KEYCARD DOOR (z 39, x 109.5..116.5) — heavy steel, slides WEST into the wall ──
    local door = box("KeycardDoor", 109.5, FLOOR, 38.8, 116.5, DOOR_TOP, 39.2, Color3.fromRGB(96, 102, 112), M.DiamondPlate, f)
    local dg = surface(door, Enum.NormalId.Front, 30, 1, 1)
    frame({ Size = UDim2.fromScale(1, 0.08), Position = UDim2.fromScale(0, 0.46), BackgroundColor3 = Color3.fromRGB(230, 180, 40) }, dg)
    text({ Text = "SECURE AREA", Size = UDim2.fromScale(0.8, 0.07), Position = UDim2.fromScale(0.1, 0.2),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(240, 240, 240) }, dg)
    box("KeycardJamb", 109.2, FLOOR, 38.3, 109.5, DOOR_TOP + 0.3, 38.5, STEEL_LITE, M.Metal, f)
    box("KeycardJamb", 116.5, FLOOR, 38.3, 116.8, DOOR_TOP + 0.3, 38.5, STEEL_LITE, M.Metal, f)
    box("KeycardHead", 109.2, DOOR_TOP, 38.3, 116.8, DOOR_TOP + 0.3, 38.5, STEEL_LITE, M.Metal, f)
    -- hazard stripe on the floor in front of it
    local hz = box("HazardStripe", 109.5, FLOOR, 36.9, 116.5, FLOOR + 0.02, 38.3, Color3.fromRGB(230, 180, 40), M.Concrete, f, NOSHADOW)
    local hzg = surface(hz, Enum.NormalId.Top, 20, 1, 1)
    for k = 0, 9 do
        frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.05 + k * 0.1, 0.5), Size = UDim2.fromScale(0.04, 2),
            Rotation = 35, BackgroundColor3 = Color3.fromRGB(30, 30, 30) }, hzg)
    end

    -- keypad on the corridor side, east of the door
    local panel = box("Keypad", 117.1, FLOOR + 3.7, 38.25, 118.3, FLOOR + 5.5, 38.5, Color3.fromRGB(34, 37, 44), M.Metal, f)
    local kg = surface(panel, Enum.NormalId.Front, 80, 0, 1.2)
    local screen = frame({ Size = UDim2.fromScale(0.8, 0.12), Position = UDim2.fromScale(0.1, 0.24),
        BackgroundColor3 = Color3.fromRGB(12, 30, 36) }, kg)
    text({ Text = "INSERT CARD", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(110, 230, 240) }, screen)
    local keys = frame({ Size = UDim2.fromScale(0.8, 0.52), Position = UDim2.fromScale(0.1, 0.42), BackgroundTransparency = 1 }, kg)
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.fromScale(0.28, 0.2)
    grid.CellPadding = UDim2.fromScale(0.06, 0.05)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = keys
    for i, k in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }) do
        local key = frame({ BackgroundColor3 = Color3.fromRGB(70, 76, 88), LayoutOrder = i }, keys)
        round(key, 0.2)
        text({ Text = k, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            TextScaled = true, FontFace = UITheme.F.bold, TextColor3 = Color3.fromRGB(220, 226, 235) }, key)
    end
    local status = box("KeypadStatus", 117.55, FLOOR + 5.15, 38.17, 117.85, FLOOR + 5.35, 38.25, SIGN_RED, M.Neon, f, NOSHADOW)
    box("CardSlot", 117.4, FLOOR + 3.85, 38.2, 118.0, FLOOR + 3.95, 38.25, Color3.fromRGB(10, 10, 12), M.Metal, f, NOSHADOW)
    local kl = ball("KeypadLamp", Vector3.new(117.7, FLOOR + 6.3, 38.3), 0.3, WARM, M.Neon, f, NOSHADOW)
    pointLight(kl, WARM, 0.7, 9, true)

    return { door = door, openOffset = Vector3.new(-7.2, 0, 0), panel = panel, status = status }
end

-- ──────────────────────────────────────────────
-- ☕ BREAK ROOM / LOCKER ROOM (x 119.5..131, z 39.5..54) — the sneakIn room
--   Staff door on the east wall z 44.5..51.5. The crew lands at x 128..130.5,
--   z 46.2..49.8 — keep that clear of furniture.
-- ──────────────────────────────────────────────
function BankBuilder:_breakRoom(f, props)
    -- warm ceiling lamp — a friendly, finished room
    box("BreakLampCable", 125.2, 15.6, 46.9, 125.3, BACK_CEIL, 47.0, STEEL, M.Metal, f, DECOR)
    vcyl("BreakLampShade", 125.25, 15.0, 15.6, 46.95, 2.0, TEAL, M.Metal, f, DECOR)
    local b = ball("BreakLampBulb", Vector3.new(125.25, 14.9, 46.95), 0.4, WARM, M.Neon, f, NOSHADOW)
    pointLight(b, WARM, 0.9, 18, true)
    -- two-tone walls: teal dado
    box("BreakDadoW", 119.5, FLOOR, 39.5, 119.65, FLOOR + 3.5, 54, TEAL, M.Plaster, f, DECOR)
    box("BreakDadoS", 119.5, FLOOR, 53.85, 131, FLOOR + 3.5, 54, TEAL, M.Plaster, f, DECOR)

    -- lockers along the south wall
    local lockers = box("Lockers", 123.5, FLOOR, 52.4, 131, FLOOR + 7.4, 54, Color3.fromRGB(70, 110, 140), M.Metal, f)
    local lg = surface(lockers, Enum.NormalId.Front, 20, 1, 1)
    local holder = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, lg)
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.fromScale(0.118, 0.97)
    grid.CellPadding = UDim2.fromScale(0.008, 0)
    grid.Parent = holder
    for i = 1, 8 do
        local door = frame({ BackgroundColor3 = Color3.fromRGB(84, 128, 160) }, holder)
        for s = 0, 3 do
            frame({ Size = UDim2.fromScale(0.6, 0.012), Position = UDim2.fromScale(0.2, 0.06 + s * 0.025),
                BackgroundColor3 = Color3.fromRGB(40, 60, 80) }, door)
        end
        frame({ Size = UDim2.fromScale(0.12, 0.05), Position = UDim2.fromScale(0.78, 0.48), BackgroundColor3 = STEEL_LITE }, door)
        text({ Text = tostring(i), Size = UDim2.fromScale(0.4, 0.05), Position = UDim2.fromScale(0.3, 0.2),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
            TextColor3 = Color3.fromRGB(220, 230, 240) }, door)
    end
    box("LockerBench", 124, FLOOR + 1.3, 51.4, 131, FLOOR + 1.6, 52.3, WOOD_MID, M.WoodPlanks, f)
    box("LockerBenchLeg", 124.3, FLOOR, 51.6, 124.6, FLOOR + 1.3, 52.1, STEEL, M.Metal, f, DECOR)
    box("LockerBenchLeg", 130.4, FLOOR, 51.6, 130.7, FLOOR + 1.3, 52.1, STEEL, M.Metal, f, DECOR)

    -- kitchenette on the west wall
    table.insert(props, { kit = "furniture", name = "kitchenFridge", pos = Vector3.new(120.7, FLOOR, 40.9), facing = Vector3.new(1, 0, 0) })
    local ctop = FLOOR + 3.4
    box("Kitchenette", 119.5, FLOOR, 42.2, 121.6, ctop - 0.2, 47.2, Color3.fromRGB(236, 232, 224), M.Wood, f)
    box("KitchenetteTop", 119.5, ctop - 0.2, 42.1, 121.8, ctop, 47.3, Color3.fromRGB(60, 62, 66), M.Granite, f)
    table.insert(props, { kit = "furniture", name = "kitchenCoffeeMachine", pos = Vector3.new(120.4, ctop, 43.2), facing = Vector3.new(1, 0, 0), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "kitchenMicrowave", pos = Vector3.new(120.5, ctop, 45.8), facing = Vector3.new(1, 0, 0), opts = { scale = 1.0 } })
    box("MugRow", 121.0, ctop, 44.3, 121.3, ctop + 0.4, 44.9, Color3.fromRGB(240, 120, 150), M.Glass, f, DECOR)

    -- table + chairs (west half, clear of the landing strip)
    table.insert(props, { kit = "furniture", name = "tableRound", pos = Vector3.new(124, FLOOR, 48), opts = { scale = 0.7 } })
    table.insert(props, { kit = "furniture", name = "chair", pos = Vector3.new(124, FLOOR, 44.4), facing = Vector3.new(0, 0, 1), opts = { scale = 1.1 } })
    table.insert(props, { kit = "furniture", name = "chair", pos = Vector3.new(121.4, FLOOR, 49.4), facing = Vector3.new(1, 0, -1), opts = { scale = 1.1 } })

    -- vending machine in the NE corner
    local vend = box("VendingMachine", 129.2, FLOOR, 39.6, 131, FLOOR + 7, 42.4, Color3.fromRGB(200, 40, 60), M.Metal, f)
    local vg = surface(vend, Enum.NormalId.Left, 30, 0, 1.1)
    local glass = frame({ Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.06, 0.08),
        BackgroundColor3 = Color3.fromRGB(30, 34, 40) }, vg)
    local gg = Instance.new("UIGridLayout")
    gg.CellSize = UDim2.fromScale(0.22, 0.16)
    gg.CellPadding = UDim2.fromScale(0.03, 0.04)
    gg.Parent = glass
    local snack = { Color3.fromRGB(250, 200, 60), Color3.fromRGB(80, 200, 120), Color3.fromRGB(240, 110, 60), Color3.fromRGB(90, 150, 240) }
    for i = 1, 20 do
        frame({ BackgroundColor3 = snack[(i % 4) + 1] }, glass)
    end
    text({ Text = "SNACKS", Size = UDim2.fromScale(0.62, 0.1), Position = UDim2.fromScale(0.06, 0.74),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(255, 240, 240) }, vg)
    local vl = box("VendGlow", 129.15, FLOOR + 2.5, 40, 129.2, FLOOR + 6.5, 41.2, Color3.fromRGB(200, 230, 255), M.Glass, f, NOSHADOW)
    pointLight(vl, Color3.fromRGB(200, 230, 255), 0.5, 7, false)

    -- wall details: clock, poster, trash
    local clk = box("BreakClock", 124.5, FLOOR + 9, 53.85, 126.5, FLOOR + 11, 54, Color3.fromRGB(240, 240, 236), M.Metal, f, DECOR)
    local cg = surface(clk, Enum.NormalId.Front, 40, 1, 1)
    local face = frame({ Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), BackgroundColor3 = Color3.fromRGB(250, 250, 246) }, cg)
    round(face)
    stroke(face, Color3.fromRGB(30, 30, 30), 3, 0)
    frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.04, 0.3), Rotation = 100, BackgroundColor3 = Color3.fromRGB(20, 20, 20) }, face)
    frame({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.03, 0.42), Rotation = 10, BackgroundColor3 = Color3.fromRGB(20, 20, 20) }, face)
    signPlate(f, "SafetyPoster", 119.55, FLOOR + 5, 48.5, 119.65, FLOOR + 8, 51, Enum.NormalId.Right, "WASH YOUR MUG!",
        Color3.fromRGB(40, 40, 40), Color3.fromRGB(250, 230, 150), 40)
    table.insert(props, { kit = "furniture", name = "trashcan", pos = Vector3.new(122.5, FLOOR, 52.8), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "coatRackStanding", pos = Vector3.new(130, FLOOR, 43.6), opts = { scale = 1.0 } })

    -- crawl vent on the west wall (floor level) — pairs with the manager's office
    return ventGrille(f, "Bank_VentBreakRoom", Vector3.new(119.5, FLOOR + 1.1, 50.9), Vector3.new(1, 0, 0))
end

-- ──────────────────────────────────────────────
-- 🔴 LASER CORRIDOR (x 107.5..118.5, z 39.5..54) — two rows, then the vault door
-- ──────────────────────────────────────────────
function BankBuilder:_lasers(f, shadows)
    local fixture = box("CorridorLight", 112.4, FLOOR + 11.85, 47.5, 113.6, FLOOR + 12, 48.5, STEEL, M.Metal, f, DECOR)
    pointLight(fixture, Color3.fromRGB(255, 70, 70), 0.6, 14, true)
    -- steel wall panels
    box("LaserPanelE", 118.35, FLOOR, 39.5, 118.5, FLOOR + 12, 54, Color3.fromRGB(70, 72, 78), M.Metal, f, DECOR)
    box("LaserPanelS", 107.5, FLOOR, 53.85, 118.5, FLOOR + 12, 54, Color3.fromRGB(70, 72, 78), M.Metal, f, DECOR)

    local rows = {}
    local zs = { 41.0, 43.4 }
    local heights = { 1.3, 2.8, 4.3 }
    for i, z in ipairs(zs) do
        local beams = {}
        for _, h in ipairs(heights) do
            local b = box("LaserBeam", 107.6, FLOOR + h - 0.06, z - 0.06, 118.4, FLOOR + h + 0.06, z + 0.06,
                LASER_RED, M.Neon, f, { CanCollide = false, CastShadow = false, CanQuery = false })
            table.insert(beams, b)
        end
        for _, ex in ipairs({ { 107.5, 107.72 }, { 118.28, 118.5 } }) do
            box("LaserEmitter", ex[1], FLOOR + 0.8, z - 0.25, ex[2], FLOOR + 4.8, z + 0.25, STEEL, M.Metal, f)
        end
        table.insert(rows, {
            beams = beams,
            zoneCFrame = CFrame.new(113, FLOOR + 2.5, z),
            zoneSize = Vector3.new(11, 5, 0.6),
            onTime = 1.4, offTime = 1.1,
            phase = (i - 1) * 0.6,
        })
    end
    signPlate(f, "LaserWarning", 118.2, FLOOR + 7.2, 39.8, 118.35, FLOOR + 8.2, 42.8, Enum.NormalId.Left, "DANGER · LASERS",
        Color3.fromRGB(30, 28, 20), Color3.fromRGB(250, 200, 40))
    shadowZone(f, shadows, 115, FLOOR, 48, 118.5, FLOOR + 10, 54)
    return rows
end

-- ──────────────────────────────────────────────
-- 🏦 VAULT: HUGE round door (east wall x 107) + steel room (x 85..106.5, z 39.5..54)
-- ──────────────────────────────────────────────
function BankBuilder:_vault(f)
    local east = Vector3.new(1, 0, 0)
    local c = Vector3.new(108.35, FLOOR + 5.3, 49)   -- centre of the disc (in the corridor, flush on the wall)
    local R = 4.8                                      -- Ø 9.6

    -- static steel frame round the opening + hinge knuckles (don't swing)
    box("VaultFrameN", 107.5, FLOOR + 0.8, 44.9, 107.75, FLOOR + 9.8, 45.2, STEEL, M.Metal, f)
    box("VaultFrameS", 107.5, FLOOR + 0.8, 52.8, 107.75, FLOOR + 9.8, 53.1, STEEL, M.Metal, f)
    box("VaultFrameTop", 107.5, FLOOR + 9.8, 44.9, 107.75, FLOOR + 10.1, 53.1, STEEL, M.Metal, f)
    for _, y in ipairs({ FLOOR + 2.2, FLOOR + 5.3, FLOOR + 8.4 }) do
        vcyl("VaultHinge", 108.35, y - 0.8, y + 0.8, 43.9, 0.7, STEEL, M.Metal, f, DECOR)
    end
    local plate = box("VaultNamePlate", 109, FLOOR + 10.4, 45.5, 109.1, FLOOR + 11.4, 52.5, Color3.fromRGB(30, 30, 34), M.Metal, f, DECOR)
    local pg = surface(plate, Enum.NormalId.Right, 40, 0, 1.3)
    text({ Text = "OCEAN BANK · MAIN VAULT", Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = GOLD }, pg)
    box("VaultPlateArm", 107.5, FLOOR + 10.8, 48.8, 109, FLOOR + 11, 49.2, STEEL, M.Metal, f, DECOR)

    -- ── the door (every part below swings) ──
    local swing = {}
    local function add(p)
        table.insert(swing, p)
        return p
    end
    add(disc("VaultDoorRim", c - east * 0.35, east, 0.5, R * 2 + 0.3, STEEL, M.Metal, f))
    local diskPart = add(disc("VaultDoorDisc", c, east, 1.2, R * 2, STEEL_LITE, M.Metal, f, { Reflectance = 0.08 }))
    add(disc("VaultDoorRing", c + east * 0.62, east, 0.1, R * 2 - 1.2, VSTEEL, M.Metal, f, NOSHADOW))
    add(disc("VaultDoorFace", c + east * 0.66, east, 0.1, R * 2 - 1.6, STEEL_LITE, M.Metal, f, NOSHADOW))
    -- `door` must be a part whose LookVector faces the corridor (JobService sits the
    -- drill at door.CFrame * (0,0,-1.6)), so it's the square boss plate at the centre.
    local bossPos = c + east * 0.8
    local door = add(cpart("VaultDoor", Vector3.new(3.6, 3.6, 0.3), CFrame.lookAt(bossPos, bossPos + east),
        Color3.fromRGB(120, 124, 134), M.DiamondPlate, f))
    add(disc("VaultHub", c + east * 1.0, east, 0.5, 2.2, STEEL, M.Metal, f))
    add(disc("VaultHubCap", c + east * 1.3, east, 0.2, 1.0, BRASS, M.Metal, f))
    for k = 0, 2 do
        add(cpart("VaultSpoke", Vector3.new(0.3, 6.6, 0.4),
            CFrame.new(c + east * 1.35) * CFrame.Angles(math.rad(k * 60), 0, 0), STEEL, M.Metal, f))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60)
        add(ball("VaultHandle", c + east * 1.35 + Vector3.new(0, math.cos(a) * 3.3, math.sin(a) * 3.3),
            0.6, BRASS, M.Metal, f))
    end
    for k = 0, 13 do
        local a = math.rad(k * (360 / 14) + 12)
        add(disc("VaultBolt", c + east * 0.7 + Vector3.new(0, math.cos(a) * 4.15, math.sin(a) * 4.15),
            east, 0.25, 0.6, STEEL, M.Metal, f))
    end
    -- the combination dial + little "OB" crest
    add(disc("VaultDial", c + east * 0.72 + Vector3.new(0, 2.2, -2.2), east, 0.2, 1.2, Color3.fromRGB(30, 30, 34), M.Metal, f))

    -- ── steel room ──
    box("VaultLiningN", 85, FLOOR, 39.5, 106.5, FLOOR + 14, 39.7, VSTEEL, M.Metal, f, DECOR)
    box("VaultLiningS", 85, FLOOR, 53.8, 106.5, FLOOR + 14, 54, VSTEEL, M.Metal, f, DECOR)
    for _, x in ipairs({ 90, 101 }) do
        local fx = box("VaultLight", x - 1, FLOOR + 13.85, 46.3, x + 1, FLOOR + 14, 47.7, BRASS, M.Metal, f, DECOR)
        pointLight(fx, Color3.fromRGB(255, 200, 110), 1.2, 18, true)
    end
    -- safe-deposit wall: the whole west wall + the west half of the north wall
    local function depositWall(p, face, cols, rows)
        local g = surface(p, face, 16, 1, 1)
        local holder = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, g)
        local grid = Instance.new("UIGridLayout")
        grid.CellSize = UDim2.fromScale(1 / cols - 0.008, 1 / rows - 0.01)
        grid.CellPadding = UDim2.fromScale(0.008, 0.01)
        grid.Parent = holder
        for _ = 1, cols * rows do
            local cell = frame({ BackgroundColor3 = Color3.fromRGB(176, 150, 98) }, holder)
            frame({ Size = UDim2.fromScale(0.16, 0.2), Position = UDim2.fromScale(0.42, 0.4),
                BackgroundColor3 = Color3.fromRGB(40, 32, 20) }, cell)
        end
    end
    local dw = box("DepositBoxesW", 85, FLOOR + 0.5, 40, 85.5, FLOOR + 11, 53.5, Color3.fromRGB(150, 130, 90), M.Metal, f)
    depositWall(dw, Enum.NormalId.Right, 12, 9)
    local dn = box("DepositBoxesN", 85.5, FLOOR + 5, 39.7, 97, FLOOR + 11, 40.1, Color3.fromRGB(150, 130, 90), M.Metal, f)
    depositWall(dn, Enum.NormalId.Back, 10, 5)
    -- one deposit box hanging open (gold glints inside)
    box("OpenDepositBox", 90, FLOOR + 7.1, 40.1, 91.1, FLOOR + 7.9, 40.9, Color3.fromRGB(190, 164, 110), M.Metal, f, DECOR)
    box("DepositGlint", 90.1, FLOOR + 7.15, 40.12, 91, FLOOR + 7.45, 40.5, GOLD, M.Metal, f, DECOR)

    return {
        door = door,
        -- hinge at the NORTH edge of the disc: -100° swings it west, into the vault
        hinge = CFrame.new(c.X, c.Y, c.Z - R),
        openAngle = math.rad(-100),
        parts = swing,
        disc = diskPart,
    }
end

-- ── vault loot (visual = just the pile; pallets/shelves/plinths stay) ────
local function lootCF(stand, pile)
    return CFrame.lookAt(stand, Vector3.new(pile.X, stand.Y, pile.Z))
end

local function cashPile(f, loot, cx, cz, standPos)
    box("CashPallet", cx - 1.2, FLOOR, cz - 1.1, cx + 1.2, FLOOR + 0.45, cz + 1.1, Color3.fromRGB(150, 118, 78), M.WoodPlanks, f)
    local m = Instance.new("Model")
    m.Name = "CashPile"
    local bw, bh, bd = 1.05, 0.42, 0.62
    for layer = 0, 2 do
        for ix = 0, 1 do
            for iz = 0, 2 do
                if not (layer == 2 and ix == 1 and iz == 2) then
                    local x = cx - 0.55 + ix * 1.1
                    local z = cz - 0.68 + iz * 0.68
                    local y0 = FLOOR + 0.45 + layer * bh
                    box("CashBrick", x - bw / 2, y0, z - bd / 2, x + bw / 2, y0 + bh, z + bd / 2,
                        ((ix + iz + layer) % 2 == 0) and Color3.fromRGB(86, 160, 96) or Color3.fromRGB(104, 176, 110),
                        M.Fabric, m)
                end
            end
        end
    end
    m.Parent = f
    table.insert(loot, { kind = "Cash", cframe = lootCF(standPos, Vector3.new(cx, 0, cz)), visual = m })
end

local function goldPile(f, loot, cx, cz, standPos)
    box("GoldShelf", cx - 1.2, FLOOR, cz - 1.0, cx + 1.2, FLOOR + 0.6, cz + 1.0, STEEL, M.Metal, f)
    local m = Instance.new("Model")
    m.Name = "GoldPile"
    local base = FLOOR + 0.6
    local layers = {
        { xs = { -0.55, 0.55 }, zs = { -0.6, 0, 0.6 } },
        { xs = { -0.55, 0.55 }, zs = { -0.3, 0.3 } },
        { xs = { 0 },           zs = { -0.3, 0.3 } },
        { xs = { 0 },           zs = { 0 } },
    }
    for li, L in ipairs(layers) do
        local y0 = base + (li - 1) * 0.36
        for _, dx in ipairs(L.xs) do
            for _, dz in ipairs(L.zs) do
                box("GoldBar", cx + dx - 0.5, y0, cz + dz - 0.25, cx + dx + 0.5, y0 + 0.36, cz + dz + 0.25,
                    GOLD, M.Metal, m, { Reflectance = 0.25 })
            end
        end
    end
    m.Parent = f
    table.insert(loot, { kind = "Gold", cframe = lootCF(standPos, Vector3.new(cx, 0, cz)), visual = m })
end

local function diamondCase(f, loot, cx, cz, standPos)
    box("DiamondPlinth", cx - 1.1, FLOOR, cz - 0.9, cx + 1.1, FLOOR + 1.4, cz + 0.9, MARBLE_DK, M.Marble, f)
    box("DiamondCase", cx - 1.0, FLOOR + 1.4, cz - 0.8, cx + 1.0, FLOOR + 2.9, cz + 0.8, Color3.fromRGB(210, 235, 240), M.Glass, f,
        { Transparency = 0.7, Reflectance = 0.15 })
    local m = Instance.new("Model")
    m.Name = "DiamondPile"
    box("Cushion", cx - 0.85, FLOOR + 1.4, cz - 0.65, cx + 0.85, FLOOR + 1.6, cz + 0.65, Color3.fromRGB(36, 34, 86), M.Fabric, m)
    local gems = {
        { 0, 0, 0.5 }, { -0.5, -0.3, 0.32 }, { 0.5, -0.25, 0.34 }, { -0.45, 0.35, 0.3 }, { 0.45, 0.35, 0.3 },
    }
    local big
    for i, g in ipairs(gems) do
        local p = ball("Diamond", Vector3.new(cx + g[1], FLOOR + 1.6 + g[3] / 2, cz + g[2]), g[3],
            Color3.fromRGB(120, 235, 255), M.Neon, m, NOSHADOW)
        if i == 1 then big = p end
    end
    pointLight(big, Color3.fromRGB(110, 220, 255), 1.2, 8, false)
    m.Parent = f
    table.insert(loot, { kind = "Diamonds", cframe = lootCF(standPos, Vector3.new(cx, 0, cz)), visual = m })
end

function BankBuilder:_vaultLoot(f, loot)
    -- The door swings west through x ≈ 97.8..107, z ≈ 42.5..54 — nothing sits there.
    -- north row: diamonds on plinths (stand south of them, facing north)
    diamondCase(f, loot, 88.5, 41.4, Vector3.new(88.5, FLOOR, 43.6))
    diamondCase(f, loot, 93.0, 41.4, Vector3.new(93.0, FLOOR, 43.6))
    -- middle row: cash pallets (stand north of them, facing south)
    cashPile(f, loot, 88.8, 46.8, Vector3.new(88.8, FLOOR, 44.4))
    cashPile(f, loot, 92.4, 46.8, Vector3.new(92.4, FLOOR, 44.4))
    cashPile(f, loot, 96.0, 46.8, Vector3.new(96.0, FLOOR, 44.4))
    -- south row: gold stacks against the south wall (stand north of them)
    goldPile(f, loot, 88.5, 52.4, Vector3.new(88.5, FLOOR, 49.9))
    goldPile(f, loot, 92.0, 52.4, Vector3.new(92.0, FLOOR, 49.9))
    goldPile(f, loot, 95.5, 52.4, Vector3.new(95.5, FLOOR, 49.9))
    -- a spare gold trolley for looks (not loot)
    box("TrolleyBase", 98.5, FLOOR + 0.6, 39.9, 101.5, FLOOR + 0.9, 41.5, STEEL, M.Metal, f)
    for _, x in ipairs({ 98.8, 101.2 }) do
        ball("TrolleyWheel", Vector3.new(x, FLOOR + 0.3, 40.7), 0.55, STEEL, M.Metal, f, DECOR)
    end
    for i = 0, 3 do
        box("TrolleyBar", 98.8 + i * 0.7, FLOOR + 0.9, 40.2, 99.4 + i * 0.7, FLOOR + 1.25, 41.2, GOLD, M.Metal, f, { Reflectance = 0.25 })
    end
end

-- ──────────────────────────────────────────────
-- 🗑 STAFF ALLEY (x 132..140) + staff door + fire escape + roof
-- ──────────────────────────────────────────────
function BankBuilder:_alley(f, props, shadows)
    box("AlleyPaving", 132, 0, 1, 140, 0.25, 55, ASPHALT, M.Asphalt, f)
    box("AlleyDrain", 135.6, 0.25, 1, 136.4, 0.27, 55, Color3.fromRGB(40, 40, 44), M.Concrete, f, NOSHADOW)
    -- neighbour's brick wall closes the alley on the east
    box("NeighbourWall", 139.4, 0, 1, 140, 11, 55, BRICK, M.Brick, f)
    box("NeighbourCoping", 139.3, 11, 1, 140, 11.3, 55, Color3.fromRGB(150, 146, 140), M.Concrete, f)

    -- ── staff door (east wall z 44.5..51.5): stoop + steps, doors propped open ──
    box("Stoop", 131, 0, 40.5, 134.5, FLOOR, 55, Color3.fromRGB(150, 146, 140), M.Concrete, f)
    box("StoopStep", 134.5, 0, 44.5, 135.5, 1.35, 51.5, Color3.fromRGB(150, 146, 140), M.Concrete, f)
    box("StoopStep", 135.5, 0, 44.5, 136.5, 0.7, 51.5, Color3.fromRGB(150, 146, 140), M.Concrete, f)
    for _, z in ipairs({ 40.6, 54.9 }) do
        box("StoopRailPost", 134.3, FLOOR, z - 0.08, 134.45, FLOOR + 3, z + 0.08, STEEL, M.Metal, f, DECOR)
    end
    box("StoopRail", 134.3, FLOOR + 2.9, 40.6, 134.45, FLOOR + 3.05, 44.5, STEEL, M.Metal, f, DECOR)
    box("StoopRail", 134.3, FLOOR + 2.9, 51.5, 134.45, FLOOR + 3.05, 54.9, STEEL, M.Metal, f, DECOR)
    local top = FLOOR + 9
    box("StaffDoorFrame", 132, FLOOR, 44.2, 132.25, top + 0.3, 44.5, STEEL, M.Metal, f)
    box("StaffDoorFrame", 132, FLOOR, 51.5, 132.25, top + 0.3, 51.8, STEEL, M.Metal, f)
    box("StaffDoorFrame", 132, top, 44.2, 132.25, top + 0.3, 51.8, STEEL, M.Metal, f)
    -- two steel leaves swung back flat against the outside wall
    box("StaffDoorLeaf", 132.25, FLOOR, 40.7, 132.45, top - 0.1, 44.2, Color3.fromRGB(92, 98, 108), M.DiamondPlate, f)
    box("StaffDoorLeaf", 132.25, FLOOR, 51.8, 132.45, top - 0.1, 55, Color3.fromRGB(92, 98, 108), M.DiamondPlate, f)
    signPlate(f, "StaffOnly", 132.25, top + 0.6, 45.6, 132.35, top + 1.8, 50.4, Enum.NormalId.Right, "STAFF ONLY",
        Color3.fromRGB(240, 70, 70), Color3.fromRGB(26, 26, 30), 60)
    -- caged lamp over the door
    box("DoorLampCage", 132.25, top + 2.2, 47.6, 132.85, top + 2.9, 48.4, STEEL, M.Metal, f, DECOR)
    local lamp = box("DoorLamp", 132.3, top + 2.3, 47.7, 132.75, top + 2.8, 48.3, Color3.fromRGB(255, 214, 150), M.Neon, f, NOSHADOW)
    pointLight(lamp, Color3.fromRGB(255, 200, 140), 0.9, 14, true)

    -- dumpster + trash + crates (up the alley, toward the street)
    local dx0, dx1, dz0, dz1 = 136.2, 139.3, 18, 23.5
    box("Dumpster", dx0, 0.6, dz0, dx1, 4.2, dz1, Color3.fromRGB(40, 92, 60), M.Metal, f)
    box("DumpsterLid", dx0 - 0.1, 4.2, dz0 - 0.1, dx1 + 0.1, 4.45, dz1 + 0.1, Color3.fromRGB(30, 30, 34), M.Fabric, f)
    box("DumpsterRim", dx0 - 0.1, 3.9, dz0 - 0.1, dx1 + 0.1, 4.2, dz1 + 0.1, Color3.fromRGB(36, 78, 52), M.Metal, f, DECOR)
    for _, z in ipairs({ dz0 + 0.5, dz1 - 0.5 }) do
        for _, x in ipairs({ dx0 + 0.4, dx1 - 0.4 }) do
            ball("DumpsterWheel", Vector3.new(x, 0.55, z), 0.6, STEEL, M.Metal, f, DECOR)
        end
    end
    local dsg = surface(box("DumpsterLabel", dx0 - 0.05, 2, dz0 + 1.2, dx0, 3.2, dz1 - 1.2, Color3.fromRGB(40, 92, 60), M.Metal, f, NOSHADOW),
        Enum.NormalId.Left, 40, 1, 1)
    text({ Text = "OCEAN WASTE CO.", Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(230, 230, 220) }, dsg)
    ball("TrashBag", Vector3.new(135.6, 0.9, 24.6), 1.5, Color3.fromRGB(24, 24, 28), M.Fabric, f, DECOR)
    ball("TrashBag", Vector3.new(136.6, 0.8, 25.4), 1.3, Color3.fromRGB(24, 24, 28), M.Fabric, f, DECOR)
    table.insert(props, { kit = "factory", name = "box-large", pos = Vector3.new(137.6, 0.25, 29), facing = Vector3.new(-1, 0, 0) })
    table.insert(props, { kit = "factory", name = "box-small", pos = Vector3.new(137.9, 0.25, 31.8), facing = Vector3.new(-1, 0, 0) })
    table.insert(props, { kit = "factory", name = "box-small", pos = Vector3.new(137.9, 2.25, 29.4), facing = Vector3.new(-1, 0, 0) })
    shadowZone(f, shadows, 132.3, 0, 16, 139.4, 8, 27)

    -- alley light halfway up (on the neighbour's wall)
    box("AlleyLampArm", 138.2, 9, 35.8, 139.4, 9.2, 36.2, STEEL, M.Metal, f, DECOR)
    local al = box("AlleyLamp", 137.8, 8.6, 35.6, 138.6, 9.0, 36.4, WARM, M.Neon, f, NOSHADOW)
    pointLight(al, WARM, 0.8, 16, true)

    -- ── fire-escape ladder (TrussPart = climbable) from the alley to the back roof ──
    local truss = Instance.new("TrussPart")
    truss.Name = "FireEscapeLadder"
    truss.Anchored = true
    truss.Size = Vector3.new(2, 20, 2)
    truss.CFrame = CFrame.new(133, 10, 34)
    truss.Color = Color3.fromRGB(46, 50, 56)
    truss.Material = M.Metal
    truss.Style = Enum.Style.AlternatingSupports
    truss.Parent = f
    -- safety cage hoops (decoration, no collision)
    for y = 8, 18, 3.3 do
        box("LadderHoop", 133.9, y, 32.9, 134.9, y + 0.2, 35.1, STEEL, M.Metal, f, DECOR)
    end
    signPlate(f, "FireEscapeSign", 132.05, 3.4, 35.6, 132.15, 4.4, 38.2, Enum.NormalId.Right, "FIRE ESCAPE",
        Color3.fromRGB(240, 240, 240), Color3.fromRGB(40, 110, 60), 40)
    -- landing on the roof where the ladder tops out
    box("RoofLanding", 128, BACK_CEIL + 1, 32.8, 131, BACK_CEIL + 1.15, 35.2, STEEL, M.DiamondPlate, f)
end

function BankBuilder:_roof(f)
    local R = BACK_CEIL + 1   -- 19: back roof top
    -- AC units, vents and a skylight-less roof so it reads as a real rooftop
    for i, pos in ipairs({ { 112, 45 }, { 120, 45 } }) do
        local x, z = pos[1], pos[2]
        box("ACUnit", x - 2, R, z - 1.6, x + 2, R + 2.6, z + 1.6, Color3.fromRGB(190, 194, 198), M.Metal, f)
        vcyl("ACFan", x, R + 2.6, R + 2.7, z, 2.4, Color3.fromRGB(40, 42, 46), M.Metal, f, DECOR)
        if i == 1 then
            box("ACDuct", x + 2, R + 0.6, z - 0.5, x + 6, R + 1.6, z + 0.5, STEEL_LITE, M.Metal, f)
        end
    end
    for _, pos in ipairs({ { 104, 50 }, { 124, 32 }, { 96, 50 } }) do
        vcyl("VentStack", pos[1], R, R + 2.2, pos[2], 0.8, STEEL_LITE, M.Metal, f)
        vcyl("VentCap", pos[1], R + 2.2, R + 2.5, pos[2], 1.3, STEEL, M.Metal, f, DECOR)
    end
    -- red aircraft light on the hall roof
    local red = ball("AircraftLight", Vector3.new(130, HALL_CEIL + 3, 27), 0.4, SIGN_RED, M.Neon, f, NOSHADOW)
    pointLight(red, SIGN_RED, 0.8, 8, false)
    -- the roof hatch above the security room (outside end of the roof vent)
    box("HatchCurb", 85.5, R, 29.3, 88.5, R + 0.6, 32.2, Color3.fromRGB(120, 124, 132), M.Metal, f)
    -- (LookVector points east, at the open roof where a player should appear)
    local hatch = cpart("Bank_RoofHatch", Vector3.new(2.5, 0.2, 2.6),
        CFrame.lookAt(Vector3.new(87, R + 0.7, 30.75), Vector3.new(90, R + 0.7, 30.75)),
        Color3.fromRGB(90, 96, 104), M.DiamondPlate, f)
    local hg = surface(hatch, Enum.NormalId.Top, 30, 1, 1)
    frame({ Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), BackgroundTransparency = 1 }, hg)
    text({ Text = "ACCESS", Size = UDim2.fromScale(0.8, 0.3), Position = UDim2.fromScale(0.1, 0.35),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(240, 200, 60) }, hg)
    box("HatchHandle", 87.8, R + 0.8, 30.4, 88.0, R + 1.1, 31.1, BRASS, M.Metal, f, DECOR)
    local hl = ball("HatchLamp", Vector3.new(86, R + 1.2, 29.4), 0.3, WARM, M.Neon, f, NOSHADOW)
    pointLight(hl, WARM, 0.6, 8, false)
    return hatch
end

-- ──────────────────────────────────────────────
-- 📹 SECURITY CAMERAS (same structure as the villa's)
-- ──────────────────────────────────────────────
local function securityCamera(parent, name, mountPos, normal, headPos, target, yawRange, period)
    local m = Instance.new("Model")
    m.Name = name
    m.Parent = parent
    cpart("Mount", Vector3.new(0.9, 0.9, 0.2), CFrame.lookAt(mountPos + normal * 0.1, mountPos + normal * 2),
        STEEL, M.Metal, m, NOSHADOW)
    local armFrom = mountPos + normal * 0.2
    cpart("Arm", Vector3.new(0.25, 0.25, (headPos - armFrom).Magnitude), CFrame.lookAt((armFrom + headPos) / 2, headPos),
        STEEL, M.Metal, m, NOSHADOW)
    local head = cpart("Head", Vector3.new(0.8, 0.8, 1.8), CFrame.lookAt(headPos, target),
        Color3.fromRGB(228, 228, 224), M.Metal, m, NOSHADOW)
    local lg = surface(head, Enum.NormalId.Front, 60, 1, 1)
    local lens = frame({ Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2),
        BackgroundColor3 = Color3.fromRGB(12, 14, 20) }, lg)
    round(lens)
    local led = ball("LED", mountPos + normal * 0.3 + Vector3.new(0, 0.42, 0), 0.22, Color3.fromRGB(255, 50, 50), M.Neon, m, NOSHADOW)
    local light = Instance.new("SpotLight")
    light.Face = Enum.NormalId.Front
    light.Color = Color3.fromRGB(255, 60, 60)
    light.Angle = 48
    light.Range = 32
    light.Brightness = 2
    light.Parent = head
    m.PrimaryPart = head
    return { model = m, head = head, light = light, led = led, yawRange = yawRange, period = period }
end

function BankBuilder:_cameras(f)
    return {
        -- C1: banking hall, high on the east wall, watching the front doors
        securityCamera(f, "Camera_Lobby", Vector3.new(130.5, FLOOR + 13, 18), Vector3.new(-1, 0, 0),
            Vector3.new(129.4, FLOOR + 12.4, 18), Vector3.new(106, FLOOR + 1, 10.5), 60, 8),
        -- C2: teller line, high on the hall's south wall (east end), looking west behind the counter
        securityCamera(f, "Camera_Tellers", Vector3.new(130, FLOOR + 12, 27.5), Vector3.new(0, 0, -1),
            Vector3.new(130, FLOOR + 11.4, 26.4), Vector3.new(96, FLOOR + 1, 24), 40, 7),
        -- C3: staff corridor, on the north wall, watching the keycard door
        securityCamera(f, "Camera_Corridor", Vector3.new(113, FLOOR + 12, 28.5), Vector3.new(0, 0, 1),
            Vector3.new(113, FLOOR + 11.4, 29.6), Vector3.new(113, FLOOR + 1, 37.5), 60, 7),
        -- C4: laser corridor, on the south wall, looking back up at the lasers
        securityCamera(f, "Camera_Vault", Vector3.new(117.5, FLOOR + 10, 53.85), Vector3.new(0, 0, -1),
            Vector3.new(117.2, FLOOR + 9.4, 52.75), Vector3.new(112, FLOOR + 1, 41), 40, 6),
    }
end

-- ──────────────────────────────────────────────
-- BUILD
-- ──────────────────────────────────────────────
function BankBuilder:build(folder)
    local root = Instance.new("Folder")
    root.Name = "OceanBank"
    root.Parent = folder

    local props = {}
    local keycardSpots = {}
    local lootSpots = {}
    local hideSpots = {}
    local shadowZones = {}
    local facadeRefs = {}

    self:_shell(sub(root, "Shell"))
    self:_facade(sub(root, "Facade"), facadeRefs)
    local ventOffice = self:_hall(sub(root, "BankingHall"), props, keycardSpots, lootSpots, hideSpots, shadowZones)
    local breaker, hatchInside = self:_security(sub(root, "Security"), props, keycardSpots, hideSpots, shadowZones)
    local keycardDoor = self:_corridor(sub(root, "StaffCorridor"), props, hideSpots, shadowZones)
    local ventBreak = self:_breakRoom(sub(root, "BreakRoom"), props)
    local laserRows = self:_lasers(sub(root, "Lasers"), shadowZones)
    local vault = self:_vault(sub(root, "Vault"))
    self:_vaultLoot(sub(root, "VaultLoot"), lootSpots)
    self:_alley(sub(root, "Alley"), props, shadowZones)
    local hatch = self:_roof(sub(root, "Roof"))
    local cameras = self:_cameras(sub(root, "Cameras"))

    local vents = {
        pairVents(hatch, hatchInside),      -- roof hatch ↔ ladder foot in the security room
        pairVents(ventOffice, ventBreak),   -- manager's office ↔ break room (crawl vent)
    }

    -- Kenney props load async and never error
    KenneyLoader.placeMany(props, sub(root, "Props"))

    local plaques = facadeRefs.plaques or {}
    local sign = facadeRefs.sign
    local function openSign(open)
        for _, pq in ipairs(plaques) do
            pq.label.Text = open and "OPEN" or "CLOSED"
            pq.label.TextColor3 = open and Color3.fromRGB(120, 255, 170) or Color3.fromRGB(96, 96, 106)
            pq.stroke.Color = open and Color3.fromRGB(60, 220, 120) or SIGN_RED
            pq.stroke.Transparency = open and 0.3 or 1
            pq.tube.Material = open and M.Neon or M.Metal
            pq.tube.Color = open and Color3.fromRGB(60, 220, 120) or Color3.fromRGB(60, 50, 56)
            pq.light.Color = open and Color3.fromRGB(60, 220, 120) or SIGN_RED
            pq.light.Enabled = open == true
        end
        if sign then
            sign.stroke.Transparency = open and 0.2 or 1
            sign.tube.Material = open and M.Neon or M.Metal
            sign.tube.Color = open and CYAN or Color3.fromRGB(50, 60, 64)
            sign.light.Brightness = open and 2 or 0
        end
    end
    openSign(false)

    print("[BankBuilder] Ocean Bank built 🏦")

    return {
        id = "bank",
        root = root,
        entryPoint = Vector3.new(108, 3, 1.5),
        policeStop = Vector3.new(62, 0, -18),
        getawayCFrame = CFrame.lookAt(Vector3.new(80, 0, -10), Vector3.new(90, 0, -10)),
        openSign = openSign,

        -- v2: the crew drops into the break room, just inside the staff door.
        -- No guard route enters it and no camera can see into it.
        sneakIn = { at = Vector3.new(128, GY, 48), face = Vector3.new(118, GY, 48), spread = Vector3.new(0, 0, 0.6) },
        entrances = {
            { kind = "front", at = Vector3.new(108, 2.5, 2), label = "Front doors" },
            { kind = "side",  at = Vector3.new(136, 1.5, 48), label = "Staff door" },
            { kind = "roof",  at = Vector3.new(135.5, 1.5, 34), label = "Roof ladder" },
        },
        hideSpots = hideSpots,
        shadowZones = shadowZones,
        vents = vents,

        vault = vault,
        keycardDoors = { keycardDoor },
        keycardSpots = keycardSpots,
        breaker = breaker,
        cameras = cameras,
        laserRows = laserRows,
        lootSpots = lootSpots,
        smashCases = {},
        guardRoutes = {
            -- G1: the public side of the banking hall, right past the front doors
            { name = "Guard_A", spawn = Vector3.new(99.5, GY, 11.5), a = Vector3.new(99.5, GY, 11.5), b = Vector3.new(116.5, GY, 11.5) },
            -- G2: behind the teller counter
            { name = "Guard_B", spawn = Vector3.new(127, GY, 25.5), a = Vector3.new(90, GY, 25.5), b = Vector3.new(127, GY, 25.5) },
            -- G3: the staff corridor, past the keycard door (never into the break room)
            { name = "Guard_C", spawn = Vector3.new(103.5, GY, 33.5), a = Vector3.new(103.5, GY, 33.5), b = Vector3.new(127.5, GY, 33.5) },
            -- G4: the security room, pacing in front of the monitors
            { name = "Guard_D", spawn = Vector3.new(97, GY, 31.3), a = Vector3.new(88.5, GY, 31.3), b = Vector3.new(97, GY, 31.3) },
        },
        plan = {
            bounds = { 84, 1, 140, 55 },
            rooms = {
                { 85, 9, 131, 28, "BANKING HALL" },
                { 85, 9, 97, 15.5, "MANAGER" },
                { 119, 9, 131, 15.5, "LOANS" },
                { 85, 28, 100, 39, "SECURITY" },
                { 100, 28, 131, 39, "STAFF" },
                { 107, 39, 119, 54, "LASERS" },
                { 85, 39, 107, 54, "VAULT" },
                { 119, 39, 131, 54, "BREAK ROOM" },
                { 132, 1, 140, 55, "ALLEY" },
            },
            vault = { 96, 47 },
            entry = { 108, 1 },
        },
    }
end

return BankBuilder
