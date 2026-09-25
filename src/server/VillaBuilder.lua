--[[
    HEIST CREW — VillaBuilder
    ────────────────────────────────────────────────
    v1.0 "Neon Miami" (2026-09-25). Job 1: VILLA ROSA — a beachfront art-deco
    villa at night. Replaces the old HeistBuilder mansion + vault.

    GEOMETRY + PROPS + REFS ONLY. No Scripts, no ProximityPrompts, no gameplay
    logic — JobService / SecurityService / LootService / GuardService add all
    of that from the JobRefs this returns (docs/V1_SPEC.md §4).

    LAYOUT (world studs, +Z = south / street, -Z = north / beach, floor top y 0.5)
        footprint x -30..30, z -82..-38, walls 1 thick centred on the edges,
        walls up to y 16.5, flat roof slab y 16.5..17.5
        front door x -5..5 on the south face (z -38), 10 tall
        ┌──────────── north (beach) z -82 ─────────────┐
        │ BEDROOM      │ VAULT x -10..10  │ GALLERY     │
        │ x -30..-10   │ z -82..-72       │ z -82..-66  │
        │ z -82..-52   ├──LASERS x -4..4──┼─────────────┤
        │              │  z -72..-60      │ SECURITY    │
        ├──door x -20──┼─glass keycard────┤ z -66..-52  │
        │ OFFICE       │  door x -3..3    ├──door x 20──┤
        │ z -52..-38   │ GRAND HALL       │ KITCHEN     │
        │     door z -45 ↔  x -10..10  ↔ door z -45    │
        └────────────── front door x 0, z -38 ─────────┘
        front garden z -38..-26.6 · back terrace + pool z -88..-82

    Interior doorways are all ≥ 6 wide (guard pathfinding, agent radius 2), and
    the three guard routes are kept clear of furniture by ≥ 2 studs.

    PUBLIC API
        VillaBuilder:build(folder) -> JobRefs (id = "villa")   — see the return
        table at the bottom of build() for every field.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local VillaBuilder = {}

local FLOOR = 0.5          -- top of every floor in the villa
local TOP = 16.5           -- top of the walls / underside of the roof slab
local DOOR_TOP = 10.5      -- top of every doorway (10 tall)

local M = Enum.Material

-- ── palette ─────────────────────────────────────────────────────────────
local STUCCO     = UITheme.rgb(Constants.MIAMI.STUCCO)
local PINK       = Color3.fromRGB(240, 188, 200)
local TEAL       = Color3.fromRGB(58, 170, 164)
local TEAL_DARK  = Color3.fromRGB(34, 110, 110)
local HOT_PINK   = UITheme.rgb(Constants.MIAMI.NEONS[1])
local CYAN       = UITheme.rgb(Constants.MIAMI.NEONS[2])
local INTERIOR   = Color3.fromRGB(204, 188, 178)
local PLINTH     = Color3.fromRGB(150, 142, 136)
local STEEL      = Color3.fromRGB(52, 56, 64)
local STEEL_LITE = Color3.fromRGB(150, 156, 166)
local BRASS      = Color3.fromRGB(196, 160, 90)
local GOLD       = Color3.fromRGB(236, 184, 60)
local WARM       = Color3.fromRGB(255, 206, 150)
local MARBLE     = Color3.fromRGB(232, 226, 216)
local MARBLE_DK  = Color3.fromRGB(62, 58, 66)
local WOOD_DARK  = Color3.fromRGB(84, 52, 36)
local WOOD_MID   = Color3.fromRGB(128, 88, 58)
local CARPET     = UITheme.rgb(Constants.COLORS.CARPET_RED)
local LASER_RED  = Color3.fromRGB(255, 40, 50)
local SIGN_RED   = Color3.fromRGB(255, 60, 70)
local LEAF       = Color3.fromRGB(56, 118, 66)

-- ──────────────────────────────────────────────
-- helpers (same style as SafehouseBuilder)
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

local function round(parent)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = parent
    return c
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

-- ── abstract art on a wall ─────────────────────────────────────────────
-- pos = point on the wall surface, normal = direction out of the wall into the room
local ART_PALETTES = {
    { Color3.fromRGB(242, 160, 190), Color3.fromRGB(40, 60, 110), Color3.fromRGB(250, 200, 90), Color3.fromRGB(40, 190, 200) },
    { Color3.fromRGB(28, 34, 58), Color3.fromRGB(255, 90, 170), Color3.fromRGB(80, 220, 230), Color3.fromRGB(245, 235, 220) },
    { Color3.fromRGB(245, 232, 210), Color3.fromRGB(220, 80, 60), Color3.fromRGB(30, 30, 36), Color3.fromRGB(60, 150, 140) },
    { Color3.fromRGB(64, 150, 150), Color3.fromRGB(250, 210, 170), Color3.fromRGB(190, 90, 150), Color3.fromRGB(20, 40, 60) },
    { Color3.fromRGB(180, 150, 230), Color3.fromRGB(250, 240, 150), Color3.fromRGB(240, 110, 120), Color3.fromRGB(40, 36, 70) },
}

local function painting(parent, pos, normal, w, h, seed)
    local cf = CFrame.lookAt(pos, pos + normal)
    cpart("PaintingFrame", Vector3.new(w + 0.5, h + 0.5, 0.2), cf * CFrame.new(0, 0, -0.1), BRASS, M.Metal, parent, DECOR)
    local canvas = cpart("PaintingCanvas", Vector3.new(w, h, 0.06), cf * CFrame.new(0, 0, -0.23),
        Color3.fromRGB(240, 236, 228), M.Fabric, parent, NOSHADOW)

    local rng = Random.new(seed)
    local pal = ART_PALETTES[(seed % #ART_PALETTES) + 1]
    -- LightInfluence 1: art sits in the dark like everything else and only
    -- reads where a lamp reaches it
    local g = surface(canvas, Enum.NormalId.Front, 30, 1, 1)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = pal[1], ClipsDescendants = true }, g)
    local aspect = h / w
    for i = 1, 5 do
        local s = rng:NextNumber(0.25, 0.7)
        local shape = frame({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85)),
            BackgroundColor3 = pal[(i % 3) + 2],
            BackgroundTransparency = rng:NextNumber(0, 0.25),
        }, bg)
        local kind = rng:NextInteger(1, 3)
        if kind == 1 then          -- circle
            shape.Size = UDim2.fromScale(s * aspect, s)
            round(shape)
        elseif kind == 2 then      -- slab
            shape.Size = UDim2.fromScale(s * 0.9, s * 0.35)
            shape.Rotation = rng:NextNumber(-35, 35)
        else                       -- bar
            shape.Size = UDim2.fromScale(0.06, s * 1.3)
            shape.Rotation = rng:NextNumber(-60, 60)
        end
    end
    return canvas
end

-- ── fake window on an outer face (no hole — frame + glass inset) ────────
local WARM_GLASS = Color3.fromRGB(255, 196, 130)
local DARK_GLASS = Color3.fromRGB(26, 34, 52)

local function fakeWindow(parent, pos, normal, w, h, lit)
    local cf = CFrame.lookAt(pos, pos + normal)
    cpart("WindowFrame", Vector3.new(w + 0.6, h + 0.6, 0.2), cf * CFrame.new(0, 0, -0.1), TEAL_DARK, M.Metal, parent)
    local glass = cpart("WindowGlass", Vector3.new(w, h, 0.1), cf * CFrame.new(0, 0, -0.25),
        lit and WARM_GLASS or DARK_GLASS, M.Glass, parent, { Reflectance = 0.15 })
    cpart("Mullion", Vector3.new(0.14, h, 0.08), cf * CFrame.new(0, 0, -0.34), TEAL_DARK, M.Metal, parent, DECOR)
    cpart("Transom", Vector3.new(w, 0.14, 0.08), cf * CFrame.new(0, h * 0.2, -0.34), TEAL_DARK, M.Metal, parent, DECOR)
    cpart("Sill", Vector3.new(w + 1, 0.25, 0.55), cf * CFrame.new(0, -h / 2 - 0.42, -0.27), PLINTH, M.Plaster, parent)
    if lit then
        -- a dim warm "someone left a lamp on" glow, drawn on the glass
        local g = surface(glass, Enum.NormalId.Front, 8, 0, 0.8)
        local f = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = WARM, BackgroundTransparency = 0.3 }, g)
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Transparency = NumberSequence.new(0.1, 0.65)
        grad.Parent = f
    end
    return glass
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: floors, walls, roof
-- ──────────────────────────────────────────────
function VillaBuilder:_shell(f)
    -- base slab under everything, then a finished floor per room (y 0.3..0.5)
    box("BaseSlab", -30.5, -0.5, -82.5, 30.5, 0.3, -37.5, Color3.fromRGB(110, 106, 102), M.Concrete, f)
    local floors = {
        { "HallFloor",     -10,   -60,   10,   -37.5, MARBLE,                        M.Marble },
        { "OfficeFloor",   -30.5, -52,   -10,  -37.5, Color3.fromRGB(92, 62, 44),    M.WoodPlanks },
        { "BedroomFloor",  -30.5, -82.5, -10,  -52,   Color3.fromRGB(104, 66, 80),   M.Fabric },
        { "KitchenFloor",  10,    -52,   30.5, -37.5, Color3.fromRGB(214, 212, 204), M.CeramicTiles },
        { "SecurityFloor", 10,    -66,   30.5, -52,   Color3.fromRGB(48, 50, 56),    M.Slate },
        { "GalleryFloor",  10,    -82.5, 30.5, -66,   MARBLE_DK,                     M.Marble },
        { "VaultFloor",    -10,   -82.5, 10,   -60,   Color3.fromRGB(80, 84, 92),    M.DiamondPlate },
    }
    for _, fl in ipairs(floors) do
        box(fl[1], fl[2], 0.3, fl[3], fl[4], FLOOR, fl[5], fl[6], fl[7], f)
    end
    -- red runner from the front door to the glass door
    box("CarpetRunner", -2, FLOOR, -59.4, 2, FLOOR + 0.05, -38.6, CARPET, M.Fabric, f, NOSHADOW)

    -- ── exterior walls (stucco) ──
    box("WallSouthW", -30.5, FLOOR, -38.5, -5, TOP, -37.5, STUCCO, M.Plaster, f)
    box("WallSouthE", 5, FLOOR, -38.5, 30.5, TOP, -37.5, STUCCO, M.Plaster, f)
    box("DoorHeader", -5, DOOR_TOP, -38.5, 5, TOP, -37.5, STUCCO, M.Plaster, f)
    box("WallNorth", -30.5, FLOOR, -82.5, 30.5, TOP, -81.5, STUCCO, M.Plaster, f)
    box("WallWest", -30.5, FLOOR, -82.5, -29.5, TOP, -37.5, STUCCO, M.Plaster, f)
    box("WallEast", 29.5, FLOOR, -82.5, 30.5, TOP, -37.5, STUCCO, M.Plaster, f)

    -- ── interior walls ──
    for _, sx in ipairs({ -1, 1 }) do
        local x0, x1 = sx * 9.5, sx * 10.5
        -- hall side walls, doorway z -48..-42 into the wings
        box("HallWall", x0, FLOOR, -82, x1, TOP, -48, INTERIOR, M.Plaster, f)
        box("HallWall", x0, FLOOR, -42, x1, TOP, -38, INTERIOR, M.Plaster, f)
        box("HallWallHeader", x0, DOOR_TOP, -48, x1, TOP, -42, INTERIOR, M.Plaster, f)
    end
    -- west wing divider (office | bedroom), doorway x -23..-17
    box("DividerW52", -29.5, FLOOR, -52.5, -23, TOP, -51.5, INTERIOR, M.Plaster, f)
    box("DividerW52", -17, FLOOR, -52.5, -10.5, TOP, -51.5, INTERIOR, M.Plaster, f)
    box("DividerW52Header", -23, DOOR_TOP, -52.5, -17, TOP, -51.5, INTERIOR, M.Plaster, f)
    -- east wing dividers (kitchen | security | gallery), doorways x 17..23
    for _, z in ipairs({ -52, -66 }) do
        box("DividerE", 10.5, FLOOR, z - 0.5, 17, TOP, z + 0.5, INTERIOR, M.Plaster, f)
        box("DividerE", 23, FLOOR, z - 0.5, 29.5, TOP, z + 0.5, INTERIOR, M.Plaster, f)
        box("DividerEHeader", 17, DOOR_TOP, z - 0.5, 23, TOP, z + 0.5, INTERIOR, M.Plaster, f)
    end
    -- grand hall north wall, opening x -3..3 for the glass keycard door
    box("HallNorthW", -9.5, FLOOR, -60.5, -3, TOP, -59.5, INTERIOR, M.Plaster, f)
    box("HallNorthE", 3, FLOOR, -60.5, 9.5, TOP, -59.5, INTERIOR, M.Plaster, f)
    box("HallNorthHeader", -3, DOOR_TOP, -60.5, 3, TOP, -59.5, INTERIOR, M.Plaster, f)

    -- ── roof ──
    box("Roof", -31, TOP, -83, 31, TOP + 1, -37, Color3.fromRGB(190, 182, 174), M.Concrete, f)
end

-- ──────────────────────────────────────────────
-- 🌴 FACADE: deco details, tower, sign, canopy, windows
-- ──────────────────────────────────────────────
function VillaBuilder:_facade(f, refs)
    -- plinth band around the base
    box("PlinthS", -30.6, 0, -37.5, -5, 1, -37.3, PLINTH, M.Concrete, f)
    box("PlinthS", 5, 0, -37.5, 30.6, 1, -37.3, PLINTH, M.Concrete, f)
    box("PlinthN", -30.7, 0, -82.7, 30.7, 1, -82.5, PLINTH, M.Concrete, f)
    box("PlinthW", -30.7, 0, -82.5, -30.5, 1, -37.5, PLINTH, M.Concrete, f)
    box("PlinthE", 30.5, 0, -82.5, 30.7, 1, -37.5, PLINTH, M.Concrete, f)

    -- teal speed lines, three bands wrapping the building
    for i, y in ipairs({ 14.0, 14.7, 15.4 }) do
        local y1 = y + 0.35
        box("SpeedLineS" .. i, -30.6, y, -37.5, 30.6, y1, -37.3, TEAL, M.Plaster, f)
        box("SpeedLineN" .. i, -30.7, y, -82.7, 30.7, y1, -82.5, TEAL, M.Plaster, f)
        box("SpeedLineW" .. i, -30.7, y, -82.5, -30.5, y1, -37.5, TEAL, M.Plaster, f)
        box("SpeedLineE" .. i, 30.5, y, -82.5, 30.7, y1, -37.5, TEAL, M.Plaster, f)
    end

    -- rounded corner towers at the two front corners
    for _, sx in ipairs({ -1, 1 }) do
        local cx, cz = sx * 30.5, -37.5
        vcyl("CornerTower", cx, 0, 19.5, cz, 6, PINK, M.Plaster, f)
        for i, y in ipairs({ 14.0, 14.7, 15.4 }) do
            vcyl("CornerBand" .. i, cx, y, y + 0.35, cz, 6.3, TEAL, M.Plaster, f)
        end
        vcyl("CornerNeonRing", cx, 19.3, 19.42, cz, 6.25, HOT_PINK, M.Neon, f, NOSHADOW)
        vcyl("CornerCap", cx, 19.5, 19.9, cz, 6.6, TEAL, M.Plaster, f)
        vcyl("CornerFinial", cx, 19.9, 21.2, cz, 0.5, STEEL_LITE, M.Metal, f, DECOR)
        -- glass-block strip facing out diagonally toward the street
        local d = Vector3.new(sx, 0, 1).Unit
        for k = 0, 5 do
            local p = Vector3.new(cx, 3.2 + k * 1.5, cz) + d * 2.95
            cpart("GlassBlock", Vector3.new(1.1, 1.1, 0.4), CFrame.lookAt(p, p + d),
                Color3.fromRGB(190, 230, 235), M.Glass, f, { Transparency = 0.15, Reflectance = 0.1 })
        end
    end

    -- ── fake windows ──
    -- south (street) face: tall windows + portholes above
    for i, x in ipairs({ -24.5, -19, -13, 13, 19, 24.5 }) do
        fakeWindow(f, Vector3.new(x, 5.6, -37.5), Vector3.new(0, 0, 1), 3, 6, i % 3 ~= 0)
        local p = Vector3.new(x, 11.3, -37.5)
        disc("PortholeRim", p + Vector3.new(0, 0, 0.1), Vector3.new(0, 0, 1), 0.2, 2, TEAL_DARK, M.Metal, f)
        disc("PortholeGlass", p + Vector3.new(0, 0, 0.22), Vector3.new(0, 0, 1), 0.1, 1.6,
            Color3.fromRGB(250, 205, 150), M.Glass, f, { Transparency = 0.25, CanCollide = false })
    end
    -- side faces
    for _, zc in ipairs({ -46, -57, -67, -76.5 }) do
        fakeWindow(f, Vector3.new(-30.5, 5.6, zc), Vector3.new(-1, 0, 0), 3, 6, zc == -57)
        fakeWindow(f, Vector3.new(30.5, 5.6, zc), Vector3.new(1, 0, 0), 3, 6, zc == -46)
    end
    -- north (beach) face: windows + fake sliding glass doors onto the terrace
    for _, sx in ipairs({ -1, 1 }) do
        fakeWindow(f, Vector3.new(sx * 25, 5.6, -82.5), Vector3.new(0, 0, -1), 3, 6, sx > 0)
        fakeWindow(f, Vector3.new(sx * 16, FLOOR + 4.3, -82.5), Vector3.new(0, 0, -1), 4, 8, false)
    end

    -- ── entrance: landing, jambs, deco fins, canopy ──
    box("EntryLanding", -4.8, 0, -37.5, 4.8, FLOOR, -35.3, MARBLE, M.Marble, f)
    box("EntryInlay", -4.8, FLOOR, -35.55, 4.8, FLOOR + 0.02, -35.35, TEAL, M.Marble, f, NOSHADOW)
    for _, sx in ipairs({ -1, 1 }) do
        box("DoorJamb", sx * 5, FLOOR, -37.5, sx * 5.3, DOOR_TOP + 0.3, -37.2, STEEL_LITE, M.Metal, f)
        -- two vertical fins each side (start above the owner's hedges, top y 2)
        box("DecoFin", sx * 5.3, 2, -37.5, sx * 5.8, 18.5, -36.2, PINK, M.Plaster, f)
        box("DecoFin", sx * 6.6, 2, -37.5, sx * 7.1, 17.5, -36.2, PINK, M.Plaster, f)
    end
    box("DoorHeadTrim", -5.3, DOOR_TOP, -37.5, 5.3, DOOR_TOP + 0.3, -37.2, STEEL_LITE, M.Metal, f)

    -- cantilevered canopy with a thin pink neon strip underneath
    box("Canopy", -7, 10.6, -37.5, 7, 11.3, -32.6, STUCCO, M.Plaster, f)
    box("CanopyFascia", -7.05, 10.55, -32.6, 7.05, 11.35, -32.4, TEAL, M.Plaster, f)
    local strip = box("CanopyNeon", -6.5, 10.48, -33.2, 6.5, 10.6, -32.95, HOT_PINK, M.Neon, f, NOSHADOW)
    pointLight(strip, HOT_PINK, 0.9, 10, false)
    for _, sx in ipairs({ -1, 1 }) do
        local fix = box("CanopyDownlight", sx * 3 - 0.35, 10.45, -35.85, sx * 3 + 0.35, 10.6, -35.15, STEEL, M.Metal, f, DECOR)
        spotLight(fix, Enum.NormalId.Bottom, WARM, 1.2, 14, 90, true)
    end

    -- frontispiece above the canopy + the central tower rising above the roof
    box("Frontispiece", -4.5, 11.3, -37.5, 4.5, TOP, -36.5, PINK, M.Plaster, f)
    box("Tower", -4.5, TOP, -41, 4.5, 31, -36.5, PINK, M.Plaster, f)
    box("TowerCrown1", -3.8, 31, -40.65, 3.8, 32, -36.85, PINK, M.Plaster, f)
    box("TowerCrown2", -2.8, 32, -40.15, 2.8, 33, -37.35, TEAL, M.Plaster, f)
    box("TowerCrown3", -1.8, 33, -39.65, 1.8, 34, -37.85, PINK, M.Plaster, f)
    vcyl("Spire", 0, 34, 39, -38.75, 0.4, STEEL_LITE, M.Metal, f)
    local tip = ball("SpireTip", Vector3.new(0, 39.3, -38.75), 0.7, HOT_PINK, M.Neon, f, NOSHADOW)
    pointLight(tip, HOT_PINK, 1, 8, false)
    -- tower fins either side of the sign
    for _, sx in ipairs({ -1, 1 }) do
        box("TowerFin", sx * 2.4, 17, -36.5, sx * 2.8, 31, -36.0, TEAL, M.Plaster, f)
        box("TowerFin", sx * 3.6, 17, -36.5, sx * 4.0, 30, -36.0, TEAL, M.Plaster, f)
    end

    -- VERTICAL "VILLA ROSA" neon sign on the tower face
    local sign = box("VillaSign", -1.7, 17.4, -36.5, 1.7, 30.6, -36.2, Color3.fromRGB(30, 18, 34), M.Metal, f)
    local sg = surface(sign, Enum.NormalId.Back, 40, 0, 3)
    local holder = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, sg)
    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Vertical
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.VerticalAlignment = Enum.VerticalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = holder
    local letters = { "V", "I", "L", "L", "A", "", "R", "O", "S", "A" }
    for i, ch in ipairs(letters) do
        local l = text({
            Text = ch, LayoutOrder = i,
            Size = UDim2.new(1, 0, 1 / #letters, 0),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextScaled = true, FontFace = UITheme.F.display,
            TextColor3 = Color3.fromRGB(255, 150, 215),
        }, holder)
        local s = Instance.new("UIStroke")
        s.Color = HOT_PINK
        s.Thickness = 3
        s.Transparency = 0.2
        s.Parent = l
    end
    -- neon tube border around the sign
    box("SignTube", -1.85, 17.25, -36.45, -1.7, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", 1.7, 17.25, -36.45, 1.85, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", -1.85, 30.6, -36.45, 1.85, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", -1.85, 17.25, -36.45, 1.85, 17.4, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    -- the real pink light that spills on the tower + facade
    pointLight(sign, HOT_PINK, 3, 16, false)

    -- ── stepped parapet + neon roofline ──
    box("ParapetS", -30.5, TOP + 1, -38.5, 30.5, 19, -37.5, STUCCO, M.Plaster, f)
    box("ParapetN", -30.5, TOP + 1, -82.5, 30.5, 18.6, -81.5, STUCCO, M.Plaster, f)
    box("ParapetW", -30.5, TOP + 1, -81.5, -29.5, 18.6, -38.5, STUCCO, M.Plaster, f)
    box("ParapetE", 29.5, TOP + 1, -81.5, 30.5, 18.6, -38.5, STUCCO, M.Plaster, f)
    for _, sx in ipairs({ -1, 1 }) do
        box("ParapetStep1", sx * 4.5, 19, -38.5, sx * 11, 19.9, -37.5, STUCCO, M.Plaster, f)
        box("ParapetStep2", sx * 4.5, 19.9, -38.5, sx * 7.5, 20.8, -37.5, PINK, M.Plaster, f)
    end
    box("RooflineNeonS", -30.5, 18.65, -37.5, 30.5, 18.8, -37.35, CYAN, M.Neon, f, NOSHADOW)
    box("RooflineNeonN", -30.5, 18.2, -82.65, 30.5, 18.35, -82.5, HOT_PINK, M.Neon, f, NOSHADOW)

    -- ── OPEN/CLOSED: small "PRIVATE" plaques either side of the door ──
    refs.plaques = {}
    for _, sx in ipairs({ -1, 1 }) do
        local x0, x1 = sx * 7.6, sx * 10.2
        local plaque = box("PrivatePlaque", x0, 6, -37.5, x1, 7.4, -37.3, Color3.fromRGB(26, 20, 30), M.Metal, f)
        local g = surface(plaque, Enum.NormalId.Back, 60, 0, 2)
        local label = text({
            Text = "CLOSED", Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
            TextColor3 = Color3.fromRGB(96, 96, 106),
        }, g)
        local stroke = Instance.new("UIStroke")
        stroke.Color = SIGN_RED
        stroke.Thickness = 2
        stroke.Transparency = 1
        stroke.Parent = label
        local tube = box("PrivateTube", x0 + sx * 0.2, 5.8, -37.45, x1 - sx * 0.2, 5.92, -37.33,
            Color3.fromRGB(60, 50, 56), M.Metal, f, NOSHADOW)
        local light = pointLight(tube, SIGN_RED, 1, 7, false)
        light.Enabled = false
        table.insert(refs.plaques, { label = label, stroke = stroke, tube = tube, light = light })
    end
end

-- ──────────────────────────────────────────────
-- 🌺 FRONT GARDEN (z -38..-26.6) — owner already built the path x -4..4
-- and hedges x ±5..6.4; we keep x -5..5 and z > -26.6 clear.
-- ──────────────────────────────────────────────
local function palm(parent, x, z, lean)
    local base = Vector3.new(x, 0, z)
    local height = 11
    local n = 6
    local function at(s) return base + Vector3.new(lean * s * s, height * s, 0) end
    for i = 1, n do
        local a, c = at((i - 1) / n), at(i / n)
        local mid = (a + c) / 2
        local len = (c - a).Magnitude + 0.2
        local dia = 1.0 - (i - 1) * 0.05
        cpart("PalmTrunk", Vector3.new(len, dia, dia), CFrame.lookAt(mid, c) * CFrame.Angles(0, math.rad(90), 0),
            Color3.fromRGB(122, 98, 72), M.Wood, parent, merge({ Shape = Enum.PartType.Cylinder }, nil))
    end
    local top = at(1)
    ball("PalmCrown", top, 1.1, Color3.fromRGB(70, 110, 60), M.Grass, parent, DECOR)
    for k = 0, 6 do
        local az = math.rad(k * 360 / 7 + 10)
        cpart("PalmFrond", Vector3.new(1.1, 0.12, 5),
            CFrame.new(top) * CFrame.Angles(0, az, 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -2.4),
            LEAF, M.Grass, parent, DECOR)
    end
    for k = 0, 2 do
        local az = math.rad(k * 120)
        ball("Coconut", top + Vector3.new(math.cos(az) * 0.5, -0.6, math.sin(az) * 0.5), 0.55,
            Color3.fromRGB(96, 70, 40), M.Wood, parent, DECOR)
    end
end

local function bollard(parent, x, z)
    vcyl("Bollard", x, 0, 2.4, z, 0.55, STEEL, M.Metal, parent)
    local lens = vcyl("BollardLens", x, 2.0, 2.3, z, 0.6, WARM, M.Neon, parent, NOSHADOW)
    vcyl("BollardCap", x, 2.4, 2.55, z, 0.7, STEEL, M.Metal, parent, DECOR)
    pointLight(lens, WARM, 1, 10, true)
end

function VillaBuilder:_garden(f)
    local rng = Random.new(1958)
    for _, sx in ipairs({ -1, 1 }) do
        -- lawn either side of the owner's hedges
        box("Lawn", sx * 6.4, 0, -37.5, sx * 30.5, 0.12, -26.8, Color3.fromRGB(46, 102, 58), M.Grass, f)
        -- low hedge along the sidewalk
        box("SidewalkHedge", sx * 7.2, 0, -27.8, sx * 30.5, 1.8, -26.8, Color3.fromRGB(40, 86, 48), M.Grass, f)
        -- flowerbed along the facade
        box("Flowerbed", sx * 8.4, 0, -37.5, sx * 26.4, 0.6, -36, Color3.fromRGB(70, 48, 36), M.Ground, f)
        local flowerCols = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(250, 240, 240), Color3.fromRGB(220, 60, 140) }
        for k = 0, 11 do
            local x = sx * (9.2 + k * 1.5)
            local z = -36.75 + rng:NextNumber(-0.3, 0.3)
            if k % 3 == 1 then
                ball("Shrub", Vector3.new(x, 1.0, z), 1.3, LEAF, M.Grass, f, DECOR)
            else
                ball("Flowers", Vector3.new(x, 0.85, z), 0.8, flowerCols[(k % 3) + 1], M.Fabric, f, DECOR)
            end
        end
        -- palms
        palm(f, sx * 21.5, -31, sx * 1.4)
        -- bollard lamps along the path
        bollard(f, sx * 7.4, -29.5)
        bollard(f, sx * 7.4, -34.5)
        -- pink / cyan uplights washing the facade (tilted back toward the wall)
        for i, x in ipairs({ 16, 21.7 }) do
            local fx = sx * x
            local fixture = cpart("Uplight", Vector3.new(0.6, 0.3, 0.6),
                CFrame.new(fx, 0.3, -35.6) * CFrame.Angles(math.rad(-12), 0, 0), STEEL, M.Metal, f, DECOR)
            spotLight(fixture, Enum.NormalId.Top, i == 1 and HOT_PINK or CYAN, 3, 20, 50, false)
        end
    end
end

-- ──────────────────────────────────────────────
-- 🏖 BACK TERRACE (z -88..-82): pool, loungers, lamps
-- ──────────────────────────────────────────────
function VillaBuilder:_terrace(f)
    local STONE = Color3.fromRGB(226, 214, 192)
    box("TerraceDeck", -30.5, 0, -88, 30.5, FLOOR, -82.5, STONE, M.Limestone, f)

    -- pool (shallow, raised coping so the water reads as a basin)
    local poolFloor = box("PoolFloor", -9, FLOOR, -87.2, 9, FLOOR + 0.02, -83.4, Color3.fromRGB(120, 215, 225), M.CeramicTiles, f)
    local pg = surface(poolFloor, Enum.NormalId.Top, 4, 0, 1)
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 220, 235), BackgroundTransparency = 0.25 }, pg)
    box("PoolCoping", -9.5, FLOOR, -83.4, 9.5, 1.2, -82.9, MARBLE, M.Marble, f)
    box("PoolCoping", -9.5, FLOOR, -87.7, 9.5, 1.2, -87.2, MARBLE, M.Marble, f)
    box("PoolCoping", -9.5, FLOOR, -87.2, -9, 1.2, -83.4, MARBLE, M.Marble, f)
    box("PoolCoping", 9, FLOOR, -87.2, 9.5, 1.2, -83.4, MARBLE, M.Marble, f)
    local water = box("PoolWater", -9, FLOOR + 0.02, -87.2, 9, 1.0, -83.4, Color3.fromRGB(60, 200, 214), M.Glass, f,
        { Transparency = 0.35, CanCollide = false, CastShadow = false })
    local sl = Instance.new("SurfaceLight")
    sl.Face = Enum.NormalId.Top
    sl.Color = Color3.fromRGB(90, 225, 235)
    sl.Brightness = 1.5
    sl.Range = 10
    sl.Angle = 90
    sl.Parent = water

    -- loungers, heads pointing away from the pool
    for _, sx in ipairs({ -1, 1 }) do
        for _, ax in ipairs({ 13.5, 19.5 }) do
            local cx, z = sx * ax, -85.3
            box("LoungerFrame", cx - 2.5, 0.8, z - 0.9, cx + 2.5, 1.0, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            box("LoungerLeg", cx - 2.4, FLOOR, z - 0.9, cx - 2.1, 0.8, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            box("LoungerLeg", cx + 2.1, FLOOR, z - 0.9, cx + 2.4, 0.8, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            local c0, c1 = cx - sx * 2.4, cx + sx * 1.0
            box("LoungerCushion", math.min(c0, c1), 1.0, z - 0.8, math.max(c0, c1), 1.25, z + 0.8, PINK, M.Fabric, f)
            cpart("LoungerBack", Vector3.new(2.0, 0.25, 1.6),
                CFrame.new(cx + sx * 1.75, 1.75, z) * CFrame.Angles(0, 0, sx * math.rad(35)), PINK, M.Fabric, f)
        end
        -- terrace lamp posts
        local lx, lz = sx * 26, -85.3
        vcyl("TerraceLampPost", lx, FLOOR, 5.5, lz, 0.35, STEEL, M.Metal, f)
        ball("TerraceLampGlobe", Vector3.new(lx, 5.9, lz), 0.8, Color3.fromRGB(255, 236, 210), M.Glass, f,
            { Transparency = 0.35, CanCollide = false })
        local bulb = ball("TerraceLampBulb", Vector3.new(lx, 5.9, lz), 0.35, WARM, M.Neon, f, NOSHADOW)
        pointLight(bulb, WARM, 1.2, 16, true)
    end
end

-- ──────────────────────────────────────────────
-- 🏛 GRAND HALL (x -10..10, z -60..-38)
-- ──────────────────────────────────────────────
function VillaBuilder:_hall(f, props)
    -- chandelier
    local cz = -49
    box("ChandelierChain", -0.08, 13.4, cz - 0.08, 0.08, TOP, cz + 0.08, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier1", 0, 13.1, 13.4, cz, 4.2, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier2", 0, 12.3, 12.55, cz, 3.0, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier3", 0, 11.5, 11.7, cz, 1.8, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierRod", 0, 11.2, 13.1, cz, 0.25, GOLD, M.Metal, f, DECOR)
    for k = 0, 9 do
        local a = math.rad(k * 36)
        ball("Crystal", Vector3.new(math.cos(a) * 2.0, 12.7, cz + math.sin(a) * 2.0), 0.45,
            Color3.fromRGB(230, 240, 255), M.Glass, f, merge(NOSHADOW, { Transparency = 0.2 }))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60 + 30)
        ball("ChandelierBulb", Vector3.new(math.cos(a) * 1.3, 12.75, cz + math.sin(a) * 1.3), 0.35, WARM, M.Neon, f, NOSHADOW)
    end
    local drop = ball("ChandelierDrop", Vector3.new(0, 10.9, cz), 0.9, Color3.fromRGB(255, 236, 214), M.Glass, f,
        merge(NOSHADOW, { Transparency = 0.1 }))
    pointLight(drop, WARM, 1.1, 22, true)

    -- sconces flanking the glass door (these light the keypad)
    for _, sx in ipairs({ -1, 1 }) do
        local x = sx * 6.5
        box("Sconce", x - 0.3, 7.8, -59.5, x + 0.3, 8.3, -59.15, BRASS, M.Metal, f, DECOR)
        local b = ball("SconceBulb", Vector3.new(x, 8.45, -59.3), 0.3, WARM, M.Neon, f, NOSHADOW)
        pointLight(b, WARM, 0.8, 11, true)
    end

    -- paintings
    painting(f, Vector3.new(-9.5, 7.6, -54), Vector3.new(1, 0, 0), 5, 3.2, 11)
    painting(f, Vector3.new(9.5, 7.2, -54), Vector3.new(-1, 0, 0), 4, 3.4, 12)
    painting(f, Vector3.new(-7.6, 6.6, -38.5), Vector3.new(0, 0, -1), 2.6, 3.4, 13)
    painting(f, Vector3.new(7.6, 6.6, -38.5), Vector3.new(0, 0, -1), 2.6, 3.4, 14)

    -- Kenney: sofa on the west wall (clear of guard A's diagonal), rug, plants
    table.insert(props, { kit = "furniture", name = "loungeDesignSofa", pos = Vector3.new(-7.6, FLOOR, -54), facing = Vector3.new(1, 0, 0) })
    table.insert(props, { kit = "furniture", name = "rugRound", pos = Vector3.new(-3.2, FLOOR, -54), opts = { scale = 0.8 } })
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(-8.2, FLOOR, -40) })
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(8.2, FLOOR, -40) })
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(8.2, FLOOR, -51) })
end

-- ──────────────────────────────────────────────
-- 🔐 GLASS KEYCARD DOOR (hall north wall, x -3..3, z -60)
-- ──────────────────────────────────────────────
function VillaBuilder:_keycardDoor(f)
    local door = box("KeycardDoor", -3, FLOOR, -60.2, 3, DOOR_TOP, -59.8, Color3.fromRGB(170, 225, 235), M.Glass, f,
        { Transparency = 0.45, Reflectance = 0.1 })
    -- etched lettering (moves with the door)
    local dg = surface(door, Enum.NormalId.Back, 30, 1, 1)
    text({
        Text = "PRIVATE  ·  AUTHORISED ACCESS ONLY", Size = UDim2.fromScale(0.8, 0.035),
        Position = UDim2.fromScale(0.1, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
        TextScaled = true, FontFace = UITheme.F.medium, TextColor3 = Color3.fromRGB(240, 250, 255),
        TextTransparency = 0.35,
    }, dg)

    -- static frame trim on the hall face (the door slides east into the wall behind it)
    box("GlassDoorJamb", -3.3, FLOOR, -59.5, -3, DOOR_TOP + 0.3, -59.3, STEEL_LITE, M.Metal, f)
    box("GlassDoorJamb", 3, FLOOR, -59.5, 3.3, DOOR_TOP + 0.3, -59.3, STEEL_LITE, M.Metal, f)
    box("GlassDoorHead", -3.3, DOOR_TOP, -59.5, 3.3, DOOR_TOP + 0.3, -59.3, STEEL_LITE, M.Metal, f)

    -- keypad on the hall side, west of the door
    local panel = box("Keypad", -5.2, 4.2, -59.5, -4.0, 6.0, -59.25, Color3.fromRGB(34, 37, 44), M.Metal, f)
    local kg = surface(panel, Enum.NormalId.Back, 80, 0, 1.2)
    local screen = frame({ Size = UDim2.fromScale(0.8, 0.12), Position = UDim2.fromScale(0.1, 0.24),
        BackgroundColor3 = Color3.fromRGB(12, 30, 36) }, kg)
    text({ Text = "INSERT CARD", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(110, 230, 240) }, screen)
    local keys = frame({ Size = UDim2.fromScale(0.8, 0.52), Position = UDim2.fromScale(0.1, 0.42),
        BackgroundTransparency = 1 }, kg)
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.fromScale(0.28, 0.2)
    grid.CellPadding = UDim2.fromScale(0.06, 0.05)
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = keys
    for i, k in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }) do
        local key = frame({ BackgroundColor3 = Color3.fromRGB(70, 76, 88), LayoutOrder = i }, keys)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.2, 0)
        c.Parent = key
        text({ Text = k, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            TextScaled = true, FontFace = UITheme.F.bold, TextColor3 = Color3.fromRGB(220, 226, 235) }, key)
    end
    local status = box("KeypadStatus", -4.75, 5.65, -59.25, -4.45, 5.85, -59.17, SIGN_RED, M.Neon, f, NOSHADOW)
    box("CardSlot", -4.9, 4.35, -59.25, -4.3, 4.45, -59.2, Color3.fromRGB(10, 10, 12), M.Metal, f, NOSHADOW)

    return { door = door, openOffset = Vector3.new(6.2, 0, 0), panel = panel, status = status }
end

-- ──────────────────────────────────────────────
-- 🔴 LASER CORRIDOR (x -4..4, z -72..-60)
-- ──────────────────────────────────────────────
function VillaBuilder:_lasers(f)
    -- solid wall mass either side of the corridor
    local MASS = Color3.fromRGB(70, 72, 78)
    box("CorridorMassW", -9.5, FLOOR, -71.5, -4, TOP, -60.5, MASS, M.Concrete, f)
    box("CorridorMassE", 4, FLOOR, -71.5, 9.5, TOP, -60.5, MASS, M.Concrete, f)
    box("CorridorCeiling", -4, DOOR_TOP, -71.5, 4, DOOR_TOP + 0.5, -60.5, STEEL, M.Metal, f)
    local fixture = box("CorridorLight", -0.6, DOOR_TOP - 0.15, -65.9, 0.6, DOOR_TOP, -65.1, STEEL, M.Metal, f, DECOR)
    pointLight(fixture, Color3.fromRGB(255, 70, 70), 0.6, 12, true)

    local rows = {}
    local zs = { -62.4, -64.6, -66.8, -69.0 }   -- ≈ -62.5/-65/-67.5/-70, nudged so the
    local heights = { 1.3, 2.8, 4.3 }           -- driller has a safe spot at the vault door
    for i, z in ipairs(zs) do
        local beams = {}
        for _, h in ipairs(heights) do
            local b = box("LaserBeam", -3.8, FLOOR + h - 0.06, z - 0.06, 3.8, FLOOR + h + 0.06, z + 0.06,
                LASER_RED, M.Neon, f, { CanCollide = false, CastShadow = false, CanQuery = false })
            table.insert(beams, b)
        end
        for _, sx in ipairs({ -1, 1 }) do
            box("LaserEmitter", sx * 4, FLOOR + 0.8, z - 0.25, sx * 3.78, FLOOR + 4.8, z + 0.25, STEEL, M.Metal, f)
            for _, h in ipairs(heights) do
                box("LaserLens", sx * 3.78, FLOOR + h - 0.1, z - 0.1, sx * 3.72, FLOOR + h + 0.1, z + 0.1,
                    LASER_RED, M.Neon, f, NOSHADOW)
            end
        end
        table.insert(rows, {
            beams = beams,
            zoneCFrame = CFrame.new(0, FLOOR + 2.5, z),
            zoneSize = Vector3.new(8, 5, 0.6),
            onTime = 1.4, offTime = 1.1,
            phase = (i - 1) * 0.6,
        })
    end
    return rows
end

-- ──────────────────────────────────────────────
-- 🏦 VAULT: round door + steel room (x -10..10, z -82..-72)
-- ──────────────────────────────────────────────
function VillaBuilder:_vault(f)
    local VSTEEL = Color3.fromRGB(96, 100, 108)
    -- vault front wall at z -72, opening x -2..2 above a low sill (y 0.8..6.8)
    box("VaultWall", -9.5, FLOOR, -72.5, -2, TOP, -71.5, VSTEEL, M.Metal, f)
    box("VaultWall", 2, FLOOR, -72.5, 9.5, TOP, -71.5, VSTEEL, M.Metal, f)
    box("VaultWallHeader", -2, 6.8, -72.5, 2, TOP, -71.5, VSTEEL, M.Metal, f)
    box("VaultSill", -2, FLOOR, -72.5, 2, 0.8, -71.5, STEEL, M.Metal, f)
    -- static hinge knuckles on the east side
    vcyl("VaultHinge", 3.8, 1.6, 3.2, -70.7, 0.6, STEEL, M.Metal, f, DECOR)
    vcyl("VaultHinge", 3.8, 5.2, 6.8, -70.7, 0.6, STEEL, M.Metal, f, DECOR)

    -- the door: disc Ø8 sitting against the corridor face, centre (0, 4.2, -71)
    local c = Vector3.new(0, 4.2, -71)
    local south = Vector3.new(0, 0, 1)
    local swing = {}
    local diskPart = disc("VaultDoorDisc", c, south, 1, 8, STEEL_LITE, M.Metal, f, { Reflectance = 0.08 })
    table.insert(swing, diskPart)
    -- `door` must be a part whose LookVector faces the corridor (JobService sits the
    -- drill at door.CFrame * (0,0,-1.6)); a Cylinder's round face is its local X, so the
    -- door ref is this square steel boss plate at the centre of the disc instead.
    local bossPos = c + south * 0.65
    local door = cpart("VaultDoor", Vector3.new(3.2, 3.2, 0.3), CFrame.lookAt(bossPos, bossPos + south),
        Color3.fromRGB(120, 124, 134), M.DiamondPlate, f)
    table.insert(swing, door)
    table.insert(swing, disc("VaultHub", c + south * 0.7, south, 0.4, 1.8, STEEL, M.Metal, f))
    for k = 0, 2 do
        local spoke = cpart("VaultSpoke", Vector3.new(5, 0.35, 0.3),
            CFrame.new(c + south * 1.05) * CFrame.Angles(0, 0, math.rad(k * 60)), STEEL, M.Metal, f)
        table.insert(swing, spoke)
    end
    for k = 0, 5 do
        local a = math.rad(k * 60)
        table.insert(swing, ball("VaultHandle", c + south * 1.05 + Vector3.new(math.cos(a) * 2.5, math.sin(a) * 2.5, 0),
            0.55, BRASS, M.Metal, f))
    end
    for k = 0, 9 do
        local a = math.rad(k * 36 + 18)
        table.insert(swing, disc("VaultBolt", c + south * 0.6 + Vector3.new(math.cos(a) * 3.35, math.sin(a) * 3.35, 0),
            south, 0.25, 0.55, STEEL, M.Metal, f))
    end

    -- steel room: lining, low ceiling, gold light
    box("VaultLiningW", -9.5, FLOOR, -81.5, -9.3, DOOR_TOP, -72.5, VSTEEL, M.Metal, f)
    box("VaultLiningE", 9.3, FLOOR, -81.5, 9.5, DOOR_TOP, -72.5, VSTEEL, M.Metal, f)
    box("VaultLiningN", -9.5, FLOOR, -81.5, 9.5, DOOR_TOP, -81.3, VSTEEL, M.Metal, f)
    box("VaultCeiling", -9.5, DOOR_TOP, -81.5, 9.5, DOOR_TOP + 0.5, -72.5, STEEL, M.Metal, f)
    for _, x in ipairs({ -4.5, 3 }) do
        local fx = box("VaultLight", x - 0.8, DOOR_TOP - 0.15, -77.5, x + 0.8, DOOR_TOP, -76.5, BRASS, M.Metal, f, DECOR)
        pointLight(fx, Color3.fromRGB(255, 200, 110), 1.1, 15, true)
    end
    -- safe-deposit wall on the east side (behind where the door swings)
    local boxes = box("DepositBoxes", 8.9, 1, -80.5, 9.3, 9.5, -73.5, Color3.fromRGB(150, 130, 90), M.Metal, f)
    local bg = surface(boxes, Enum.NormalId.Left, 20, 1, 1)
    local holder = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, bg)
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.fromScale(0.13, 0.11)
    grid.CellPadding = UDim2.fromScale(0.012, 0.01)
    grid.Parent = holder
    for _ = 1, 56 do
        local cell = frame({ BackgroundColor3 = Color3.fromRGB(176, 150, 98) }, holder)
        frame({ Size = UDim2.fromScale(0.16, 0.2), Position = UDim2.fromScale(0.42, 0.4),
            BackgroundColor3 = Color3.fromRGB(40, 32, 20) }, cell)
    end

    return {
        door = door,
        hinge = CFrame.new(4, c.Y, c.Z),     -- east edge of the disc
        openAngle = math.rad(-100),          -- swings north, into the vault
        parts = swing,
        disc = diskPart,
    }
end

-- ── loot piles (visual = just the pile; pallets/plinths stay) ───────────
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
        { 0, 0, 0.5 }, { -0.5, -0.3, 0.32 }, { 0.5, -0.25, 0.34 }, { -0.45, 0.35, 0.3 }, { 0.45, 0.35, 0.3 }, { 0.05, 0.45, 0.26 },
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

function VillaBuilder:_loot(f)
    local loot = {}
    -- west wall: three cash pallets (players stand at x -5.6, facing west)
    for _, z in ipairs({ -74.2, -77.2, -80.2 }) do
        cashPile(f, loot, -8.1, z, Vector3.new(-5.6, FLOOR, z))
    end
    -- north wall: two gold stacks + the diamond case. The door swings open along
    -- x ≈ 3.5..6 (z -71..-79), so nothing sits east of x 3.7.
    goldPile(f, loot, -3.8, -80.3, Vector3.new(-3.8, FLOOR, -77.4))
    goldPile(f, loot, -0.6, -80.3, Vector3.new(-0.6, FLOOR, -77.4))
    diamondCase(f, loot, 2.6, -80.3, Vector3.new(2.6, FLOOR, -77.4))
    return loot
end

-- ──────────────────────────────────────────────
-- 📚 WEST WING: OFFICE (z -52..-38) + BEDROOM (z -82..-52)
-- Guard C walks x = -20 from z -44 to -76 — keep x -22..-18 clear.
-- ──────────────────────────────────────────────
function VillaBuilder:_westWing(f, props, spots)
    -- ── office desk (part-built so the keycard spot height is exact) ──
    local deskTop = 3.3
    box("DeskTop", -25.2, deskTop - 0.3, -47.5, -22.6, deskTop, -42.5, WOOD_DARK, M.WoodPlanks, f)
    box("DeskPedestal", -25.1, FLOOR, -47.4, -22.7, deskTop - 0.3, -46, WOOD_DARK, M.Wood, f)
    box("DeskPedestal", -25.1, FLOOR, -44, -22.7, deskTop - 0.3, -42.6, WOOD_DARK, M.Wood, f)
    box("DeskInlay", -25.0, deskTop, -47.2, -22.8, deskTop + 0.02, -42.8, Color3.fromRGB(40, 70, 52), M.Fabric, f, NOSHADOW)
    table.insert(spots, CFrame.new(-23.6, deskTop + 0.03, -46.0))
    -- green banker's lamp
    box("DeskLampBase", -24.9, deskTop, -47.2, -24.3, deskTop + 0.15, -46.8, BRASS, M.Metal, f, DECOR)
    box("DeskLampStem", -24.65, deskTop + 0.15, -47.05, -24.55, deskTop + 0.95, -46.95, BRASS, M.Metal, f, DECOR)
    local shade = box("DeskLampShade", -25.1, deskTop + 0.95, -47.25, -24.1, deskTop + 1.25, -46.75,
        Color3.fromRGB(40, 120, 70), M.Glass, f, DECOR)
    pointLight(shade, Color3.fromRGB(255, 210, 150), 0.9, 12, true)

    table.insert(props, { kit = "furniture", name = "laptop", pos = Vector3.new(-23.9, deskTop, -44.2), facing = Vector3.new(-1, 0, 0), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "chairDesk", pos = Vector3.new(-27, FLOOR, -45), facing = Vector3.new(1, 0, 0) })
    table.insert(props, { kit = "furniture", name = "bookcaseClosedWide", pos = Vector3.new(-24.8, FLOOR, -39.4), facing = Vector3.new(0, 0, -1), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "bookcaseClosedWide", pos = Vector3.new(-14.2, FLOOR, -39.4), facing = Vector3.new(0, 0, -1), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "lampSquareFloor", pos = Vector3.new(-28.5, FLOOR, -50.5) })
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(-12.2, FLOOR, -50.2) })
    table.insert(props, { kit = "furniture", name = "rugRectangle", pos = Vector3.new(-25, FLOOR, -45), facing = Vector3.new(1, 0, 0), opts = { scale = 0.6 } })
    pointLight(lightHolder(f, Vector3.new(-28.5, 7.2, -50.5)), WARM, 0.6, 12, true)
    painting(f, Vector3.new(-10.5, 7, -50), Vector3.new(-1, 0, 0), 2.4, 2.6, 21)
    painting(f, Vector3.new(-14, 7, -51.5), Vector3.new(0, 0, 1), 3.5, 2.6, 22)

    -- ── bedroom ──
    -- bed head against the west wall (scaled to 0.9 so its foot stays 2.6 from guard C)
    table.insert(props, { kit = "furniture", name = "bedDouble", pos = Vector3.new(-26.07, FLOOR, -76), facing = Vector3.new(1, 0, 0), opts = { scale = 0.9 } })
    table.insert(props, { kit = "furniture", name = "rugRectangle", pos = Vector3.new(-24, FLOOR, -76), facing = Vector3.new(1, 0, 0), opts = { scale = 0.9 } })
    -- nightstands (part-built — keycard spot on the north one)
    local nsTop = 2.85
    for i, z0 in ipairs({ -81.3, -72.7 }) do
        box("Nightstand", -29.4, FLOOR, z0, -27.9, nsTop - 0.15, z0 + 2, WOOD_MID, M.Wood, f)
        box("NightstandTop", -29.45, nsTop - 0.15, z0 - 0.05, -27.85, nsTop, z0 + 2.05, WOOD_DARK, M.WoodPlanks, f)
        box("NightstandKnob", -27.9, 1.9, z0 + 0.9, -27.8, 2.1, z0 + 1.1, BRASS, M.Metal, f, DECOR)
        if i == 1 then
            table.insert(spots, CFrame.new(-28.65, nsTop + 0.01, -79.7))
            table.insert(props, { kit = "furniture", name = "lampRoundTable", pos = Vector3.new(-28.65, nsTop, -80.7), opts = { scale = 1.0 } })
            pointLight(lightHolder(f, Vector3.new(-28.65, nsTop + 1.9, -80.7)), Color3.fromRGB(255, 190, 140), 0.8, 12, true)
        end
    end
    -- dresser + mirror on the east strip
    box("Dresser", -12.3, FLOOR, -64, -10.5, 3.4, -58, WOOD_MID, M.Wood, f)
    box("DresserTop", -12.4, 3.4, -64.1, -10.5, 3.55, -57.9, MARBLE, M.Marble, f)
    box("Mirror", -10.7, 4.2, -63.2, -10.5, 8.2, -58.8, Color3.fromRGB(200, 212, 218), M.Glass, f, { Reflectance = 0.45 })
    box("MirrorFrame", -10.65, 4.0, -63.4, -10.5, 8.4, -58.6, BRASS, M.Metal, f, DECOR)
    table.insert(props, { kit = "furniture", name = "lampRoundTable", pos = Vector3.new(-11.4, 3.55, -62.9), opts = { scale = 1.0 } })
    pointLight(lightHolder(f, Vector3.new(-11.4, 5.4, -62.9)), Color3.fromRGB(255, 190, 140), 0.7, 12, true)
    table.insert(props, { kit = "furniture", name = "loungeChairRelax", pos = Vector3.new(-13.8, FLOOR, -71), facing = Vector3.new(-1, 0, 0), opts = { scale = 0.9 } })
    table.insert(props, { kit = "furniture", name = "lampSquareFloor", pos = Vector3.new(-12, FLOOR, -80) })
    pointLight(lightHolder(f, Vector3.new(-12, 7.2, -80)), WARM, 0.6, 12, true)
    painting(f, Vector3.new(-29.5, 7.5, -76), Vector3.new(1, 0, 0), 5, 3, 31)
    painting(f, Vector3.new(-14, 7, -52.5), Vector3.new(0, 0, -1), 3, 2.4, 32)
end

-- ──────────────────────────────────────────────
-- 🍸 EAST WING: KITCHEN · SECURITY · GALLERY
-- Guard B walks x = 20 from z -44 to -76 — keep x 18..22 clear.
-- ──────────────────────────────────────────────
function VillaBuilder:_kitchen(f, props, spots)
    -- appliances along the east wall (stop at z -41 — the corner tower bulges in)
    table.insert(props, { kit = "furniture", name = "kitchenFridgeLarge", pos = Vector3.new(27.78, FLOOR, -49.25), facing = Vector3.new(-1, 0, 0) })
    table.insert(props, { kit = "furniture", name = "kitchenStove", pos = Vector3.new(27.97, FLOOR, -45.54), facing = Vector3.new(-1, 0, 0), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "kitchenCabinet", pos = Vector3.new(27.97, FLOOR, -42.57), facing = Vector3.new(-1, 0, 0), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "kitchenCabinetUpper", pos = Vector3.new(28.75, 6.5, -42.57), facing = Vector3.new(-1, 0, 0), opts = { scale = 1.0 } })

    -- bar counter against the front wall (part-built — keycard spot on top)
    local top = 3.9
    box("BarBase", 11.1, FLOOR, -40.1, 15.9, top - 0.3, -38.5, WOOD_DARK, M.Wood, f)
    box("BarTop", 11, top - 0.3, -40.6, 16, top, -38.5, MARBLE, M.Marble, f)
    box("BarKick", 11.1, FLOOR, -40.2, 15.9, 0.9, -40.1, TEAL_DARK, M.Metal, f, DECOR)
    table.insert(spots, CFrame.new(12.2, top + 0.01, -39.4))
    table.insert(props, { kit = "furniture", name = "kitchenCoffeeMachine", pos = Vector3.new(15.2, top, -39.3), facing = Vector3.new(0, 0, -1), opts = { scale = 1.0 } })
    for _, x in ipairs({ 12.3, 14.7 }) do
        table.insert(props, { kit = "furniture", name = "stoolBar", pos = Vector3.new(x, FLOOR, -41.5), facing = Vector3.new(0, 0, 1), opts = { scale = 1.0 } })
        -- pendant light over the bar
        box("PendantCable", x - 0.05, 9.8, -39.6, x + 0.05, TOP, -39.5, STEEL, M.Metal, f, DECOR)
        vcyl("PendantShade", x, 9.1, 9.8, -39.55, 1.3, STEEL, M.Metal, f, DECOR)
        local b = ball("PendantBulb", Vector3.new(x, 9.0, -39.55), 0.3, WARM, M.Neon, f, NOSHADOW)
        pointLight(b, WARM, 0.9, 12, true)
    end
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(12.2, FLOOR, -50.2) })
    painting(f, Vector3.new(10.5, 7.5, -50), Vector3.new(1, 0, 0), 2.4, 2.4, 41)
end

-- A fake camera feed on a monitor face
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
    for i = 0, 23 do
        frame({ Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, i / 24),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7 }, bg)
    end
    text({ Text = label, Size = UDim2.fromScale(0.5, 0.13), Position = UDim2.fromScale(0.05, 0.05),
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(190, 255, 220) }, bg)
    local dot = frame({ Size = UDim2.fromScale(0.05, 0.07), Position = UDim2.fromScale(0.73, 0.08),
        BackgroundColor3 = Color3.fromRGB(255, 60, 60) }, bg)
    round(dot)
    text({ Text = "REC", Size = UDim2.fromScale(0.16, 0.11), Position = UDim2.fromScale(0.8, 0.06),
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(255, 120, 120) }, bg)
    text({ Text = string.format("02:14:%02d", (seed * 17) % 60), Size = UDim2.fromScale(0.4, 0.1),
        Position = UDim2.fromScale(0.56, 0.86), TextXAlignment = Enum.TextXAlignment.Right,
        TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(190, 255, 220) }, bg)
end

function VillaBuilder:_security(f, props)
    -- desk along the west wall with three monitors facing east
    local top = 3.3
    box("SecDesk", 10.5, top - 0.3, -62, 13.5, top, -55, Color3.fromRGB(58, 60, 66), M.Metal, f)
    box("SecDeskSide", 10.5, FLOOR, -62, 13.5, top - 0.3, -61.8, STEEL, M.Metal, f)
    box("SecDeskSide", 10.5, FLOOR, -55.2, 13.5, top - 0.3, -55, STEEL, M.Metal, f)
    local mid
    for i, zc in ipairs({ -60.6, -58.5, -56.4 }) do
        box("MonitorStand", 11.1, top, zc - 0.3, 11.6, 3.75, zc + 0.3, STEEL, M.Metal, f)
        local mon = box("Monitor", 11.2, 3.75, zc - 1.0, 11.45, 5.45, zc + 1.0, Color3.fromRGB(20, 22, 26), M.Metal, f)
        camFeed(mon, Enum.NormalId.Right, string.format("CAM 0%d", i), i)
        if i == 2 then mid = mon end
    end
    pointLight(mid, Color3.fromRGB(120, 170, 255), 0.8, 11, true)
    table.insert(props, { kit = "furniture", name = "computerKeyboard", pos = Vector3.new(12.9, top, -58.5), facing = Vector3.new(1, 0, 0), opts = { scale = 1.0 } })
    table.insert(props, { kit = "furniture", name = "chairDesk", pos = Vector3.new(15.2, FLOOR, -58.5), facing = Vector3.new(-1, 0, 0) })

    -- server rack in the NE corner
    local rack = box("ServerRack", 26.5, FLOOR, -65.3, 29.3, 7.5, -63.5, Color3.fromRGB(28, 30, 36), M.Metal, f)
    local rg = surface(rack, Enum.NormalId.Back, 20, 0, 1.2)
    local rng = Random.new(77)
    for r = 0, 9 do
        local unit = frame({ Size = UDim2.fromScale(0.9, 0.08), Position = UDim2.fromScale(0.05, 0.04 + r * 0.095),
            BackgroundColor3 = Color3.fromRGB(44, 48, 56) }, rg)
        for k = 0, 3 do
            frame({ Size = UDim2.fromScale(0.05, 0.35), Position = UDim2.fromScale(0.08 + k * 0.08, 0.32),
                BackgroundColor3 = (rng:NextNumber() < 0.75) and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(250, 180, 60) }, unit)
        end
    end

    -- ceiling lamp (dim, cool)
    box("SecLampCable", 19.95, 13, -59.05, 20.05, TOP, -58.95, STEEL, M.Metal, f, DECOR)
    vcyl("SecLampShade", 20, 12.4, 13, -59, 1.6, STEEL, M.Metal, f, DECOR)
    local b = ball("SecLampBulb", Vector3.new(20, 12.3, -59), 0.35, Color3.fromRGB(220, 228, 255), M.Neon, f, NOSHADOW)
    pointLight(b, Color3.fromRGB(220, 228, 255), 0.6, 14, true)

    -- BREAKER: grey electrical panel on the east wall, facing into the room
    local breaker = box("Breaker", 29.0, 2.5, -60, 29.5, 6.5, -57, Color3.fromRGB(122, 126, 132), M.Metal, f)
    local bg = surface(breaker, Enum.NormalId.Left, 40, 1, 1)
    text({ Text = "MAIN · CCTV", Size = UDim2.fromScale(0.9, 0.1), Position = UDim2.fromScale(0.05, 0.12),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(30, 32, 36) }, bg)
    local sw = frame({ Size = UDim2.fromScale(0.8, 0.6), Position = UDim2.fromScale(0.1, 0.3), BackgroundTransparency = 1 }, bg)
    local swGrid = Instance.new("UIGridLayout")
    swGrid.CellSize = UDim2.fromScale(0.28, 0.14)
    swGrid.CellPadding = UDim2.fromScale(0.06, 0.03)
    swGrid.Parent = sw
    for _ = 1, 12 do
        local s = frame({ BackgroundColor3 = Color3.fromRGB(40, 42, 48) }, sw)
        frame({ Size = UDim2.fromScale(0.35, 0.8), Position = UDim2.fromScale(0.1, 0.1), BackgroundColor3 = Color3.fromRGB(210, 210, 214) }, s)
    end
    for i, z in ipairs({ -59.4, -58.5, -57.6 }) do
        box("BreakerLED", 28.93, 6.05, z - 0.1, 29.0, 6.25, z + 0.1,
            i == 3 and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(80, 240, 120), M.Neon, f, NOSHADOW)
    end
    box("BreakerConduit", 29.1, 6.5, -58.6, 29.35, TOP, -58.35, STEEL, M.Metal, f, DECOR)
    return breaker
end

local SCULPTURE_NAMES = { "ROSA I", "L'OEUF D'OR", "VASE ROSE", "TORSION", "OCEAN EYE" }

function VillaBuilder:_gallery(f, props, spots)
    local peds = {
        { 13.5, -70, Enum.NormalId.Right, "bust" },
        { 13.5, -75, Enum.NormalId.Right, "egg" },
        { 13.5, -79.5, Enum.NormalId.Right, "vase" },
        { 26.5, -70, Enum.NormalId.Left, "twist" },
        { 26.5, -80, Enum.NormalId.Left, "orb" },
    }
    for i, p in ipairs(peds) do
        local x, z, face, kind = p[1], p[2], p[3], p[4]
        local ped = box("Pedestal", x - 0.9, FLOOR, z - 0.9, x + 0.9, 3.5, z + 0.9, MARBLE, M.Marble, f)
        box("PedestalCap", x - 1.0, 3.5, z - 1.0, x + 1.0, 3.7, z + 1.0, BRASS, M.Metal, f)
        local g = surface(ped, face, 40, 1, 1)
        text({ Text = SCULPTURE_NAMES[i], Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.12),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
            TextColor3 = Color3.fromRGB(150, 118, 50) }, g)
        text({ Text = "PRICELESS", Size = UDim2.fromScale(0.9, 0.05), Position = UDim2.fromScale(0.05, 0.2),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.medium,
            TextColor3 = Color3.fromRGB(110, 104, 96) }, g)
        local y = 3.7
        if kind == "bust" then
            vcyl("SculptNeck", x, y, y + 0.5, z, 0.6, MARBLE, M.Marble, f)
            ball("SculptHead", Vector3.new(x, y + 1.05, z), 1.2, MARBLE, M.Marble, f)
        elseif kind == "egg" then
            vcyl("SculptStand", x, y, y + 0.3, z, 0.7, BRASS, M.Metal, f)
            ball("SculptEgg", Vector3.new(x, y + 0.85, z), 1.1, GOLD, M.Metal, f, { Reflectance = 0.3 })
        elseif kind == "vase" then
            ball("SculptVaseBody", Vector3.new(x, y + 0.55, z), 1.1, Color3.fromRGB(255, 150, 200), M.Glass, f, { Transparency = 0.2 })
            vcyl("SculptVaseNeck", x, y + 0.9, y + 1.8, z, 0.5, Color3.fromRGB(255, 150, 200), M.Glass, f, { Transparency = 0.2 })
        elseif kind == "twist" then
            for k = 0, 2 do
                cpart("SculptTwist", Vector3.new(0.55, 0.6, 0.55),
                    CFrame.new(x, y + 0.3 + k * 0.6, z) * CFrame.Angles(0, math.rad(k * 30), 0), TEAL, M.Metal, f)
            end
        else
            ball("SculptOrb", Vector3.new(x, y + 0.7, z), 1.3, Color3.fromRGB(120, 210, 230), M.Glass, f, { Transparency = 0.3 })
            ball("SculptOrbCore", Vector3.new(x, y + 0.7, z), 0.35, CYAN, M.Neon, f, NOSHADOW)
        end
        -- gallery spot from the ceiling
        local fx = box("GallerySpot", x - 0.4, TOP - 0.3, z - 0.4, x + 0.4, TOP, z + 0.4, STEEL, M.Metal, f, DECOR)
        spotLight(fx, Enum.NormalId.Bottom, Color3.fromRGB(255, 236, 214), 1.2, 18, 32, true)
    end

    -- bench (part-built — keycard spot on the seat)
    box("BenchBase", 26, FLOOR, -76.6, 27, 1.9, -73.4, WOOD_DARK, M.Wood, f)
    box("BenchSeat", 25.8, 1.9, -77, 27.2, 2.3, -73, Color3.fromRGB(40, 38, 48), M.Fabric, f)
    table.insert(spots, CFrame.new(26.5, 2.31, -75))

    -- paintings (+ picture lights on the two big ones)
    for i, x in ipairs({ 14.5, 25.5 }) do
        painting(f, Vector3.new(x, 7.5, -81.5), Vector3.new(0, 0, 1), 4.5, 3.2, 50 + i)
        local pl = box("PictureLight", x - 1.5, 9.6, -81.5, x + 1.5, 9.8, -81.1, BRASS, M.Metal, f, DECOR)
        spotLight(pl, Enum.NormalId.Bottom, WARM, 0.8, 7, 90, true)
    end
    painting(f, Vector3.new(10.5, 7.5, -72.5), Vector3.new(1, 0, 0), 3, 3.6, 53)
    painting(f, Vector3.new(10.5, 7.5, -77.5), Vector3.new(1, 0, 0), 3, 3.6, 54)
    painting(f, Vector3.new(29.5, 7.5, -71), Vector3.new(-1, 0, 0), 3.5, 2.8, 55)
    painting(f, Vector3.new(29.5, 7.5, -79.5), Vector3.new(-1, 0, 0), 3.5, 2.8, 56)
    table.insert(props, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(28.3, FLOOR, -67.8) })
end

-- ──────────────────────────────────────────────
-- 📹 SECURITY CAMERAS
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

function VillaBuilder:_cameras(f)
    return {
        -- C1: grand hall, high in the NW corner, watching the front door
        securityCamera(f, "Camera_Hall", Vector3.new(-9.5, 12.6, -58.9), Vector3.new(1, 0, 0),
            Vector3.new(-8.5, 12.0, -58.4), Vector3.new(0, 1.5, -41), 70, 7),
        -- C2: end of the laser corridor above the vault door, looking south
        securityCamera(f, "Camera_Corridor", Vector3.new(0, 9.9, -71.5), Vector3.new(0, 0, 1),
            Vector3.new(0, 9.3, -70.5), Vector3.new(0, 1.5, -61), 40, 7),
        -- C3: office, high in the NW corner, across the desk to the hall doorway
        securityCamera(f, "Camera_Office", Vector3.new(-29.5, 12.6, -51.0), Vector3.new(1, 0, 0),
            Vector3.new(-28.5, 12.0, -50.5), Vector3.new(-16, 1.5, -43), 70, 7),
    }
end

-- ──────────────────────────────────────────────
-- BUILD
-- ──────────────────────────────────────────────
function VillaBuilder:build(folder)
    local root = Instance.new("Folder")
    root.Name = "VillaRosa"
    root.Parent = folder

    local props = {}
    local keycardSpots = {}
    local facadeRefs = {}

    self:_shell(sub(root, "Shell"))
    self:_facade(sub(root, "Facade"), facadeRefs)
    self:_garden(sub(root, "Garden"))
    self:_terrace(sub(root, "Terrace"))
    self:_hall(sub(root, "GrandHall"), props)
    local keycardDoor = self:_keycardDoor(sub(root, "KeycardDoor"))
    local laserRows = self:_lasers(sub(root, "Lasers"))
    local vault = self:_vault(sub(root, "Vault"))
    local lootSpots = self:_loot(sub(root, "Loot"))
    self:_westWing(sub(root, "WestWing"), props, keycardSpots)
    self:_kitchen(sub(root, "Kitchen"), props, keycardSpots)
    local breaker = self:_security(sub(root, "Security"), props)
    self:_gallery(sub(root, "Gallery"), props, keycardSpots)
    local cameras = self:_cameras(sub(root, "Cameras"))

    -- Kenney props load async and never error
    KenneyLoader.placeMany(props, sub(root, "Props"))

    local plaques = facadeRefs.plaques or {}
    local function openSign(open)
        for _, pq in ipairs(plaques) do
            pq.label.Text = open and "PRIVATE" or "CLOSED"
            pq.label.TextColor3 = open and SIGN_RED or Color3.fromRGB(96, 96, 106)
            pq.stroke.Transparency = open and 0.3 or 1
            pq.tube.Material = open and M.Neon or M.Metal
            pq.tube.Color = open and SIGN_RED or Color3.fromRGB(60, 50, 56)
            pq.light.Enabled = open == true
        end
    end
    openSign(false)

    print("[VillaBuilder] Villa Rosa built 🌴")

    return {
        id = "villa",
        root = root,
        entryPoint = Vector3.new(0, 3, -34),
        policeStop = Vector3.new(0, 0, -18),
        getawayCFrame = CFrame.lookAt(Vector3.new(-40, 0, -18), Vector3.new(-30, 0, -18)),
        openSign = openSign,

        vault = vault,
        keycardDoors = { keycardDoor },
        keycardSpots = keycardSpots,
        breaker = breaker,
        cameras = cameras,
        laserRows = laserRows,
        lootSpots = lootSpots,
        smashCases = {},
        guardRoutes = {
            { name = "Guard_A", spawn = Vector3.new(-6, 3, -44), a = Vector3.new(-6, 3, -44), b = Vector3.new(6, 3, -56) },
            { name = "Guard_B", spawn = Vector3.new(20, 3, -44), a = Vector3.new(20, 3, -44), b = Vector3.new(20, 3, -76) },
            { name = "Guard_C", spawn = Vector3.new(-20, 3, -44), a = Vector3.new(-20, 3, -44), b = Vector3.new(-20, 3, -76) },
        },
        plan = {
            bounds = { -30, -82, 30, -38 },
            rooms = {
                { -10, -60, 10, -38, "HALL" },
                { -30, -52, -10, -38, "OFFICE" },
                { -30, -82, -10, -52, "BEDROOM" },
                { 10, -52, 30, -38, "KITCHEN" },
                { 10, -66, 30, -52, "SECURITY" },
                { 10, -82, 30, -66, "GALLERY" },
                { -4, -72, 4, -60, "LASERS" },
                { -10, -82, 10, -72, "VAULT" },
            },
            vault = { 0, -77 },
            entry = { 0, -38 },
        },
    }
end

return VillaBuilder
