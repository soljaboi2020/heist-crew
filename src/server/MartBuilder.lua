--[[
    HEIST CREW — MartBuilder
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Job: SUNNY'S MART — the warm-up heist that
    teaches the game. A Miami corner convenience store at night: bright
    fluorescent aisles, glowing drink fridges, a checkout with two registers,
    a stock room out back and an office with a floor safe.

    FOOTPRINT x 50..74, z 1..25 (Constants.WORLD.MART_*). Floor top y 0.5,
    ceiling y 14.5, roof deck y 15.5, parapet y 17.5, sign tower to ~20.
    The storefront faces NORTH onto Ocean Drive (z 1). No keycard, no lasers,
    no display cases: 1 guard, 1 camera, 1 breaker, 1 safe.

        z 1  ┌── glass ─── FRONT DOOR (x 58..66) ─── glass ──┐
             │ ··· guard lane (z 3.6, x 58.5..69) ··········· │
             │ CLERK │COUNTER│  [G1]  dark  [G2]    FRIDGES   │
             │ lotto │ $  $  │  [G1]  aisle [G2]    FRIDGES   │
             │ area  │       │  [G1]        [G2]    FRIDGES   │
             │  ice freezer   BIG BOX   CAM        (drinks)   │
        z 15 ├──────────────┬─────────── STRIP CURTAIN ──────┤
             │ OFFICE       D  STOCK ROOM  pallet   (sneakIn)═ BACK DOOR
             │ ladder↑ desk D  breaker     shelves   closet  ═ (east alley)
             │  [ SAFE ]    │                                │
        z 24 └──────────────┴────────────────────────────────┘
            x 51           59 60                             73
        Roof: ladder on the back wall (x 70, in the yard) → roof → hatch → office.

    v2.0.2 (2026-09-25, Malachi: "shouldn't be able to walk out the heist and see
    the ugly green terrain" + "the graphics are very simple / bad"):
      • WALLED SERVICE YARD x 74..83.7, z 1..33.5 (+ a strip behind the store,
        x 50..74, z 25..33.5): 12-tall brick all round, a roll-up vehicle gate
        x 74..82.5 on the street line (z 1), the getaway car parked inside at
        (78.25, 0, 10) facing north. Dumpster, propane cage, crates, pallet,
        puddles, a shadowed key lamp over the car. The roof ladder moved to the
        back wall so the car has a clear lane.
      • Graphics: three rows of troffers (no overlapping lenses; two key tubes
        cast shadows), tile runners down the aisles + a teal band at the
        fridges, cove base + promo posters, painted cinder block + safety lines
        in the stock room, a caged work lamp, navy wainscot + wallpaper and a
        desk lamp in the office, product rows shaded by the room, painted
        instead of stripy wood, Kenney props repainted after they load.

    Geometry + props + refs ONLY (no Scripts / prompts / gameplay). Tags set
    here (V2_SPEC §2): HideSpot (+Label), ShadowZone, Vent (+Pair). Vent /
    hatch parts face (LookVector) the open floor you step out onto.

    PUBLIC API:
        MartBuilder:build(folder) -> JobRefs   (V1_SPEC §4 + V2_SPEC §4, id = "mart")
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local MartBuilder = {}

local M = Enum.Material
local W = Constants.WORLD

-- ── layout ──────────────────────────────────────────────────────────────
local FLOOR = W.FLOOR                                             -- 0.5
local CX, CZ = W.MART_CENTER.x, W.MART_CENTER.z                   -- 62, 13
local X0, X1 = CX - W.MART_HALF_WIDTH, CX + W.MART_HALF_WIDTH     -- 50, 74
local Z0, Z1 = CZ - W.MART_HALF_DEPTH, CZ + W.MART_HALF_DEPTH     -- 1, 25
local IX0, IX1 = X0 + 1, X1 - 1        -- 51, 73
local IZ0, IZ1 = Z0 + 1, Z1 - 1        -- 2, 24
local CEIL = FLOOR + 14                -- 14.5
local ROOF_Y = CEIL + 1                -- 15.5
local TOP = ROOF_Y + 2                 -- 17.5
local ZF = Z0 - 0.25                   -- 0.75, front face of the storefront
local DOOR_H = FLOOR + 10.5            -- 11

local ENT_X0, ENT_X1 = CX - 4, CX + 4           -- front door x 58..66 (8 wide)
local ENT_TOP = FLOOR + 10.5
local WIN_TOP = FLOOR + 10.3
local SALES_Z1 = 15                             -- back wall z 15..16
local BACK_Z0 = 16
local CURTAIN_X0, CURTAIN_X1 = 63, 70           -- strip-curtain doorway into the stock room
local OFFICE_X1 = 59                            -- office | stock wall x 59..60
local STOCK_X0 = 60
local SIDE_DOOR_Z0, SIDE_DOOR_Z1 = 16.5, 23.5   -- doors in the x 59..60 wall and the east wall
-- (v2.0.2) the roof ladder moved off the east wall (the getaway car parks
-- there now) onto the BACK wall, inside the walled service yard
local LADDER_X = 70                             -- truss on the south wall, x 69..71
local NOTCH_X0, NOTCH_X1 = 68.5, 71.5           -- parapet notch over the roof ladder

-- ── the walled SERVICE YARD (v2.0.2) ──
-- East of the store (between it and the bank) + a strip behind it. The back
-- door opens into it; the getaway car parks in it, nose at a roll-up vehicle
-- gate onto Ocean Drive. Brick on every side: you see brick, street and sky.
local YARD_X1 = 83.7                            -- east wall outer face (bank plinth starts at 83.8)
local YARD_Z1 = 33.5                            -- south wall z 32.9..33.5
local YWALL_T, YWALL_H = 0.6, 12
local GATE_X0, GATE_X1 = X1, 82.5               -- vehicle gate opening x 74..82.5 (8.5 wide), line z 1
local CAR_X, CAR_Z = 78.25, 10                  -- getaway parking spot (faces north, at the gate)

-- sales floor fixtures
local COUNTER_X0, COUNTER_X1, COUNTER_Z0, COUNTER_Z1 = 54.5, 56.5, 3.5, 10
local GONDOLAS = { { 60, 61.8 }, { 65.2, 67 } }  -- x ranges; both run z 5.6..12.4
local GOND_Z0, GOND_Z1 = 5.6, 12.4
local FRIDGE_X0 = 71.2                          -- fridges x 71.2..73, z 3..13
local GUARD_Z = 3.6

-- the floor safe (office, against the south wall, door facing north)
local SAFE_X = 55.5
local SAFE_Z0, SAFE_Z1 = 21, 23.9
local SAFE_HW = 2.5
local SAFE_Y = FLOOR + 2.7
local SAFE_TOP = FLOOR + 5.5
local DISC_R, DISC_T = 1.6, 0.45

-- ── palette ─────────────────────────────────────────────────────────────
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local P = Constants.MIAMI
local LEMON     = UITheme.rgb(P.PASTELS[6])
local MINT      = UITheme.rgb(P.PASTELS[2])
local STUCCO    = UITheme.rgb(P.STUCCO)
local SUN       = rgb(255, 176, 40)
local SUN_DEEP  = rgb(255, 110, 40)
local TEAL      = rgb(20, 150, 150)
local CYAN      = UITheme.rgb(P.NEONS[2])
local HOT_PINK  = UITheme.rgb(P.NEONS[1])
local CREAM     = rgb(238, 232, 218)
local STEEL     = rgb(58, 62, 70)
local STEEL_DK  = rgb(30, 32, 38)
local STEEL_LT  = rgb(170, 176, 186)
local WALNUT    = rgb(96, 64, 44)
local COOL      = rgb(226, 238, 255)
local WARM      = rgb(255, 222, 186)
local CASH_GREEN = rgb(96, 170, 96)
local PRODUCT = {
    rgb(230, 57, 70), rgb(255, 183, 3), rgb(33, 158, 188), rgb(106, 176, 76), rgb(244, 114, 182),
    rgb(251, 133, 0), rgb(142, 202, 230), rgb(155, 93, 229), rgb(241, 250, 238), rgb(2, 48, 71),
}

-- ── helpers (same style as JewelryBuilder) ──────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

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

local function nc(extra)
    local t = { CanCollide = false }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function bar(name, a, b, thick, color, material, parent, extra)
    local d = b - a
    local mid = (a + b) / 2
    local cf
    if math.abs(d.Unit.Y) > 0.999 then
        cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)
    else
        cf = CFrame.lookAt(mid, b)
    end
    local props = { Name = name, Size = Vector3.new(thick, thick, d.Magnitude), CFrame = cf,
        Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function tube(name, a, b, color, parent, thick)
    return bar(name, a, b, thick or 0.16, color, M.Neon, parent, { CanCollide = false, CastShadow = false })
end

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

-- (v2.0.2) painted / printed things (posters, panels, signs on walls) take the
-- room's light instead of glowing flat. Screens + backlit signs stay unlit.
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

local function lightAnchor(name, pos, parent)
    return part({ Name = name, Size = Vector3.new(0.2, 0.2, 0.2), Position = pos, Transparency = 1,
        CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
        Material = M.Metal }, parent)
end

-- fluorescent ceiling fixture. on = false → a dead tube (dark, no light).
-- len = fixture length (default 4.4); shadows = this tube is a key light
local function tubeLight(parent, x, z, alongX, brightness, range, on, len, shadows)
    local half = (len or 4.4) / 2
    local hx, hz = alongX and half or 0.4, alongX and 0.4 or half
    local fx = box("TubeFixture", x - hx, CEIL - 0.25, z - hz, x + hx, CEIL, z + hz, STEEL_LT, M.Metal, parent, nc())
    box("TubeLens", x - hx + 0.15, CEIL - 0.3, z - hz + 0.1, x + hx - 0.15, CEIL - 0.25, z + hz - 0.1,
        on == false and rgb(120, 124, 130) or COOL, on == false and M.Glass or M.Neon, parent, nc({ CastShadow = false }))
    if on ~= false then point(fx, COOL, brightness or 1, range or 16, shadows == true) end
    return fx
end

local function tag(p, tagName, attrs)
    CollectionService:AddTag(p, tagName)
    for k, v in pairs(attrs or {}) do p:SetAttribute(k, v) end
    return p
end

local function shadowZone(name, x0, z0, x1, z1, parent)
    local p = box(name, x0, FLOOR, z0, x1, FLOOR + 9, z1, rgb(0, 0, 0), M.Concrete, parent, {
        Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
    return tag(p, "ShadowZone")
end

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
            for pat, sp in pairs(paint.byName) do
                if string.find(n, pat, 1, true) then
                    spec = sp
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

-- a row of products on a shelf: ONE part with the boxes painted on (cheap,
-- and it reads as a full shelf from any distance)
local function productRow(name, x0, y0, z0, x1, y1, z1, face, seed, parent, wide)
    local p = box(name, x0, y0, z0, x1, y1, z1, rgb(60, 60, 64), M.Cardboard, parent, nc())
    local g = surface(p, face, 24, 1)
    g.LightInfluence = 0.45     -- (v2.0.2) shaded by the room, still punchy
    g.Brightness = 1.5
    local n = wide and 7 or 10
    for k = 0, n - 1 do
        local col = PRODUCT[((seed * 7 + k * 3) % #PRODUCT) + 1]
        local h = 0.72 + ((seed + k) % 3) * 0.09
        local item = frame({ Size = UDim2.fromScale(0.86 / n, h), Position = UDim2.fromScale(0.02 + k / n, 1 - h),
            BackgroundColor3 = col }, g)
        frame({ Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.1, 0.3),
            BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.25 }, item)
    end
    return p
end

-- a stack of banded cash (loot visuals)
local function cashStack(parent, x, y, z, nx, nz, layers)
    for l = 0, layers - 1 do
        for i = 0, nx - 1 do
            for j = 0, nz - 1 do
                local bx = x + (i - (nx - 1) / 2) * 0.72
                local bz = z + (j - (nz - 1) / 2) * 0.36
                box("CashBrick", bx - 0.34, y + l * 0.26, bz - 0.16, bx + 0.34, y + l * 0.26 + 0.24, bz + 0.16,
                    CASH_GREEN, M.Fabric, parent, nc({ CastShadow = false }))
                box("CashBand", bx - 0.06, y + l * 0.26, bz - 0.17, bx + 0.06, y + l * 0.26 + 0.25, bz + 0.17,
                    rgb(236, 230, 200), M.Fabric, parent, nc({ CastShadow = false }))
            end
        end
    end
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL
-- ──────────────────────────────────────────────
function MartBuilder:_shell(f)
    -- sidewalk apron in front (the south sidewalk ends at z -1.4)
    box("Apron", X0, 0, -1.4, X1, FLOOR, Z0, rgb(170, 168, 162), M.Concrete, f)
    -- floors
    box("FloorSales", X0, 0, Z0, X1, FLOOR, 15.5, rgb(226, 226, 220), M.CeramicTiles, f)
    box("FloorOffice", X0, 0, 15.5, 59.5, FLOOR, Z1, rgb(70, 84, 104), M.Carpet, f)
    box("FloorStock", 59.5, 0, 15.5, X1, FLOOR, Z1, rgb(140, 138, 132), M.Concrete, f)

    -- exterior walls (the front is the facade)
    box("WallWest", X0, FLOOR, Z0, IX0, TOP, Z1, LEMON, M.Plaster, f)
    -- back wall: notched parapet over the roof ladder (x 68.5..71.5)
    box("WallSouth", IX0, FLOOR, IZ1, NOTCH_X0, TOP, Z1, LEMON, M.Plaster, f)
    box("WallSouthNotch", NOTCH_X0, FLOOR, IZ1, NOTCH_X1, ROOF_Y, Z1, LEMON, M.Plaster, f)
    box("WallSouth", NOTCH_X1, FLOOR, IZ1, IX1, TOP, Z1, LEMON, M.Plaster, f)
    box("WallEast", IX1, FLOOR, Z0, X1, TOP, SIDE_DOOR_Z0, LEMON, M.Plaster, f)
    box("BackDoorHeader", IX1, DOOR_H, SIDE_DOOR_Z0, X1, TOP, SIDE_DOOR_Z1, LEMON, M.Plaster, f)
    box("WallEast", IX1, FLOOR, SIDE_DOOR_Z1, X1, TOP, Z1, LEMON, M.Plaster, f)
    -- teal base band + coping
    box("BaseBand", X0 - 0.1, 0, Z0, X0, 2.2, Z1 + 0.1, TEAL, M.Plaster, f, nc())
    box("BaseBand", X0, 0, Z1, X1, 2.2, Z1 + 0.1, TEAL, M.Plaster, f, nc())
    box("BaseBand", X1, 0, Z0, X1 + 0.1, 2.2, SIDE_DOOR_Z0 - 0.3, TEAL, M.Plaster, f, nc())
    box("BaseBand", X1, 0, SIDE_DOOR_Z1 + 0.3, X1 + 0.1, 2.2, Z1 + 0.1, TEAL, M.Plaster, f, nc())
    box("CopingW", X0 - 0.15, TOP, Z0 - 0.4, IX0 + 0.05, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingE", IX1 - 0.05, TOP, Z0 - 0.4, X1 + 0.15, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingS", IX0, TOP, IZ1 - 0.05, NOTCH_X0, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)
    box("CopingS", NOTCH_X1, TOP, IZ1 - 0.05, IX1, TOP + 0.3, Z1 + 0.15, STUCCO, M.Plaster, f)

    -- the west wall faces the car alley: a big painted sun mural
    local mural = box("Mural", X0 - 0.06, 3, 5, X0, 14.5, 21, rgb(255, 214, 120), M.Plaster, f, nc())
    local mg = surface(mural, Enum.NormalId.Left, 12, 1)
    mg.LightInfluence = 0.7
    local sky = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, mg)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, rgb(255, 120, 150)),
        ColorSequenceKeypoint.new(0.6, rgb(255, 190, 110)),
        ColorSequenceKeypoint.new(1, rgb(255, 230, 150)),
    })
    grad.Parent = sky
    local sun = frame({ Size = UDim2.fromScale(0.36, 0.5), Position = UDim2.fromScale(0.32, 0.18), BackgroundColor3 = SUN }, mg)
    UITheme.corner(sun, 999)
    text({ Text = "SUNNY'S", Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.72),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(200, 40, 80) }, mg)

    -- ceiling + roof deck
    box("Ceiling", IX0, CEIL, IZ0, IX1, CEIL + 0.5, IZ1, rgb(214, 214, 208), M.Plaster, f)
    box("Roof", IX0, CEIL + 0.5, IZ0, IX1, ROOF_Y, IZ1, rgb(150, 150, 150), M.Concrete, f)
    box("RoofLip", NOTCH_X0, ROOF_Y - 0.5, IZ1, NOTCH_X1, ROOF_Y, Z1, rgb(150, 150, 150), M.Concrete, f)
    box("RoofAC", 63, ROOF_Y, 10, 67, ROOF_Y + 2.6, 13.5, STEEL_LT, M.Metal, f)
    box("RoofACFan", 63.8, ROOF_Y + 2.6, 10.7, 66.2, ROOF_Y + 2.7, 12.8, STEEL_DK, M.Metal, f, nc())
    part({ Name = "VentStack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.8, 0.8),
        CFrame = CFrame.new(70, ROOF_Y + 0.8, 20) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STEEL_LT, Material = M.Metal }, f)

    -- interior walls
    wallX("SalesBackWall", SALES_Z1, BACK_Z0, IX0, IX1, { { CURTAIN_X0, CURTAIN_X1, DOOR_H } }, CREAM, M.Plaster, f)
    wallZ("OfficeWall", OFFICE_X1, STOCK_X0, BACK_Z0, IZ1, { { SIDE_DOOR_Z0, SIDE_DOOR_Z1, DOOR_H } }, CREAM, M.Plaster, f)
    -- mint wainscot round the sales floor
    box("Wainscot", IX0, FLOOR, IZ0, IX0 + 0.1, FLOOR + 3, SALES_Z1, MINT, M.Plaster, f, nc())
    box("Wainscot", IX0, FLOOR, SALES_Z1 - 0.1, IX1, FLOOR + 3, SALES_Z1, MINT, M.Plaster, f, nc())
end

-- ──────────────────────────────────────────────
-- ☀️ FACADE: glass front, SUNNY'S neon sign, awning, OPEN sign
-- ──────────────────────────────────────────────
function MartBuilder:_facade(f)
    local fa = Instance.new("Folder")
    fa.Name = "Facade"
    fa.Parent = f

    box("PierW", X0, FLOOR, ZF - 0.2, X0 + 1.5, TOP, IZ0, TEAL, M.Plaster, fa)
    box("PierE", X1 - 1.5, FLOOR, ZF - 0.2, X1, TOP, IZ0, TEAL, M.Plaster, fa)
    box("DoorPierW", ENT_X0 - 0.8, FLOOR, ZF, ENT_X0, WIN_TOP + 0.5, IZ0, TEAL, M.Plaster, fa)
    box("DoorPierE", ENT_X1, FLOOR, ZF, ENT_X1 + 0.8, WIN_TOP + 0.5, IZ0, TEAL, M.Plaster, fa)

    -- windows with a few sale posters stuck on the inside of the glass
    local posters = {
        { "ICE COLD\nDRINKS", CYAN }, { "2 FOR $3", rgb(255, 80, 80) }, { "LOTTO", SUN }, { "HOT\nSNACKS", SUN_DEEP },
    }
    local pi = 0
    for _, bay in ipairs({ { X0 + 1.5, ENT_X0 - 0.8 }, { ENT_X1 + 0.8, X1 - 1.5 } }) do
        local b0, b1 = bay[1], bay[2]
        box("Sill", b0, FLOOR, ZF + 0.15, b1, FLOOR + 1.2, IZ0, TEAL, M.Plaster, fa)
        box("ShopWindow", b0, FLOOR + 1.2, 1.3, b1, WIN_TOP, 1.6, rgb(190, 220, 236), M.Glass, fa,
            { Transparency = 0.5, Reflectance = 0.2 })
        local mx = (b0 + b1) / 2
        box("Mullion", mx - 0.1, FLOOR + 1.2, 1.2, mx + 0.1, WIN_TOP, 1.7, STEEL_LT, M.Metal, fa)
        box("WindowHead", b0, WIN_TOP, 1.2, b1, WIN_TOP + 0.5, 1.7, STEEL_LT, M.Metal, fa)
        for k = 0, 1 do
            pi = pi + 1
            local px = b0 + (b1 - b0) * (k == 0 and 0.27 or 0.73)
            local pst = box("Poster", px - 1.1, 5.2, 1.62, px + 1.1, 7.6, 1.68, rgb(250, 250, 244), M.Fabric, fa, nc())
            local pg = surface(pst, Enum.NormalId.Front, 40, 1)
            text({ Text = posters[pi][1], Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
                TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
                TextColor3 = posters[pi][2] }, pg)
        end
    end

    -- entrance: automatic sliding glass doors, parked open behind the window glass
    box("DoorFrameTop", ENT_X0, ENT_TOP, ZF, ENT_X1, WIN_TOP + 0.5, IZ0, STEEL_LT, M.Metal, fa)
    box("DoorTrack", ENT_X0 - 4.2, ENT_TOP - 0.5, 1.95, ENT_X1 + 4.2, ENT_TOP, 2.2, STEEL_LT, M.Metal, fa, nc())
    for _, side in ipairs({ -1, 1 }) do
        local a0 = side < 0 and ENT_X0 - 4 or ENT_X1
        local a1 = side < 0 and ENT_X0 or ENT_X1 + 4
        -- parked over the window sill (top y FLOOR + 1.2)
        box("SlidingDoor", a0, FLOOR + 1.2, 2.02, a1, ENT_TOP - 0.5, 2.12, rgb(190, 220, 236), M.Glass, fa,
            nc({ Transparency = 0.55, Reflectance = 0.2 }))
        box("SlidingDoorRail", a0, FLOOR + 1.2, 2.0, a1, FLOOR + 1.6, 2.14, STEEL_LT, M.Metal, fa, nc())
    end
    box("DoorSensor", CX - 0.6, ENT_TOP - 0.4, 1.7, CX + 0.6, ENT_TOP - 0.1, 2, STEEL_DK, M.Metal, fa, nc())
    box("SensorLed", CX + 0.3, ENT_TOP - 0.45, 1.75, CX + 0.45, ENT_TOP - 0.4, 1.9, rgb(80, 255, 120), M.Neon, fa, nc())
    box("DoorMat", ENT_X0 + 0.5, FLOOR, IZ0, ENT_X1 - 0.5, FLOOR + 0.06, IZ0 + 2.6, rgb(40, 40, 44), M.Fabric, fa, nc())

    -- fascia band
    box("Fascia", X0 + 1.5, WIN_TOP + 0.5, ZF, X1 - 1.5, TOP, IZ0, LEMON, M.Plaster, fa)
    box("FasciaStripe", X0 + 1.5, WIN_TOP + 0.5, ZF - 0.1, X1 - 1.5, WIN_TOP + 1, ZF, TEAL, M.Plaster, fa)
    -- sign tower in the middle of the parapet
    box("SignTower", CX - 7.5, TOP, ZF, CX + 7.5, 20.5, IZ0, LEMON, M.Plaster, fa)
    box("TowerCap", CX - 7.8, 20.5, ZF - 0.3, CX + 7.8, 20.9, IZ0, STUCCO, M.Plaster, fa)

    -- ── the sign: SUNNY'S ──
    local sx0, sx1, sy0, sy1 = CX - 7, CX + 7, 12.4, 20
    local board = box("SignBoard", sx0, sy0, ZF - 0.25, sx1, sy1, ZF, rgb(28, 20, 40), M.Metal, fa)
    local sg = surface(board, Enum.NormalId.Front, 36, 2.4)
    local sunIcon = frame({ Size = UDim2.fromOffset(110, 110), Position = UDim2.fromOffset(30, 70),
        BackgroundColor3 = SUN }, sg)
    UITheme.corner(sunIcon, 55)
    for r = 0, 7 do
        local a = r * math.pi / 4
        frame({ Size = UDim2.fromOffset(12, 40), Position = UDim2.fromOffset(79 + 78 * math.sin(a), 119 - 78 * math.cos(a)),
            AnchorPoint = Vector2.new(0.5, 0.5), Rotation = math.deg(a), BackgroundColor3 = SUN_DEEP }, sg)
    end
    local name = text({ Text = "Sunny's", Size = UDim2.fromScale(0.64, 0.64), Position = UDim2.fromScale(0.33, 0.02),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = rgb(255, 214, 120) }, sg)
    local glow = Instance.new("UIStroke")
    glow.Color = SUN_DEEP
    glow.Thickness = 3
    glow.Transparency = 0.1
    glow.Parent = name
    text({ Text = "M A R T  ·  24 / 7", Size = UDim2.fromScale(0.6, 0.18), Position = UDim2.fromScale(0.35, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = CYAN }, sg)
    local oz = ZF - 0.33
    tube("SignTube", Vector3.new(sx0, sy1, oz), Vector3.new(sx1, sy1, oz), SUN_DEEP, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx1, sy0, oz), SUN_DEEP, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx0, sy1, oz), SUN_DEEP, fa)
    tube("SignTube", Vector3.new(sx1, sy0, oz), Vector3.new(sx1, sy1, oz), SUN_DEEP, fa)
    point(lightAnchor("SignGlowW", Vector3.new(CX - 4, 16, ZF - 1.8), fa), SUN, 2.6, 16)
    point(lightAnchor("SignGlowE", Vector3.new(CX + 4, 16, ZF - 1.8), fa), SUN_DEEP, 2.6, 16)

    -- thin neon roofline in teal/cyan
    local rz = ZF - 0.45
    tube("Roofline", Vector3.new(X0, TOP - 0.3, rz), Vector3.new(CX - 7.5, TOP - 0.3, rz), CYAN, fa)
    tube("Roofline", Vector3.new(CX + 7.5, TOP - 0.3, rz), Vector3.new(X1, TOP - 0.3, rz), CYAN, fa)

    -- striped awning over the door only (x 57..67: clear of the streetlight at
    -- x 56 and the palm at x 70). Front edge y 10.7, under the sign.
    local ax0, ax1, n = CX - 5, CX + 5, 5
    local w = (ax1 - ax0) / n
    local back = Vector3.new(0, 11.5, ZF)
    local front = Vector3.new(0, 10.7, ZF - 2)
    local dir = front - back
    for i = 1, n do
        local x = ax0 + (i - 0.5) * w
        local col = (i % 2 == 1) and TEAL or rgb(244, 244, 236)
        local mid = Vector3.new(x, (back.Y + front.Y) / 2, (back.Z + front.Z) / 2)
        part({ Name = "AwningStripe", Size = Vector3.new(w, 0.14, dir.Magnitude), CFrame = CFrame.lookAt(mid, mid + dir),
            Color = col, Material = M.Fabric, CanCollide = false }, fa)
        box("AwningValance", x - w / 2, 10.3, front.Z - 0.07, x + w / 2, 10.75, front.Z + 0.05, col, M.Fabric, fa, nc())
    end

    -- entrance downlight
    local lamp = box("DoorLamp", CX - 0.5, ENT_TOP - 0.3, ZF - 0.4, CX + 0.5, ENT_TOP, ZF, STEEL_DK, M.Metal, fa, nc())
    spot(lamp, Enum.NormalId.Bottom, WARM, 1.6, 14, 110, true)

    -- outside: ice chest + trash can + a newspaper box
    local ice = box("IceChest", X0 + 0.6, 0.5, -1.2, X0 + 4, 4, 0.5, rgb(236, 244, 250), M.Metal, fa)
    printOn(ice, Enum.NormalId.Front, "ICE", rgb(40, 120, 220), UITheme.F.display, 40, 1.2)
    part({ Name = "TrashCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.6, 1.6),
        CFrame = CFrame.new(ENT_X1 + 2, 2, -0.4) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STEEL, Material = M.Metal }, fa)
    local paper = box("NewsBox", ENT_X0 - 3, 0.5, -1, ENT_X0 - 1.4, 3.6, 0.3, rgb(40, 90, 170), M.Metal, fa)
    printOn(paper, Enum.NormalId.Front, "NEWS", rgb(240, 240, 240), UITheme.F.bold, 50, 1)

    -- ── OPEN / CLOSED sign in the east window ──
    local ox0, ox1, oy0, oy1 = 68.2, 71.2, 8.3, 9.6
    local oz0, oz1 = 1.66, 1.8
    local osign = box("OpenSign", ox0, oy0, oz0, ox1, oy1, oz1, rgb(16, 12, 22), M.Metal, fa, nc())
    local og = surface(osign, Enum.NormalId.Front, 60, 2)
    local olabel = text({ Text = "CLOSED", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display }, og)
    local ostroke = Instance.new("UIStroke")
    ostroke.Thickness = 2
    ostroke.Transparency = 0.2
    ostroke.Parent = olabel
    local oTubes = {
        box("OpenTube", ox0 - 0.14, oy1, oz0, ox1 + 0.14, oy1 + 0.14, oz1, HOT_PINK, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.14, oy0 - 0.14, oz0, ox1 + 0.14, oy0, oz1, HOT_PINK, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.14, oy0, oz0, ox0, oy1, oz1, HOT_PINK, M.Neon, fa, nc()),
        box("OpenTube", ox1, oy0, oz0, ox1 + 0.14, oy1, oz1, HOT_PINK, M.Neon, fa, nc()),
    }
    local oglow = point(osign, HOT_PINK, 1.4, 9)

    local function openSign(open)
        olabel.Text = open and "OPEN" or "CLOSED"
        olabel.TextColor3 = open and rgb(255, 120, 205) or rgb(150, 44, 56)
        ostroke.Color = open and HOT_PINK or rgb(70, 16, 26)
        for _, t in ipairs(oTubes) do
            t.Material = open and M.Neon or M.Metal
            t.Color = open and HOT_PINK or rgb(58, 40, 52)
        end
        oglow.Enabled = open
    end
    openSign(false)
    return openSign
end

-- ──────────────────────────────────────────────
-- 🛒 SALES FLOOR
-- ──────────────────────────────────────────────
function MartBuilder:_gondola(f, x0, x1, idx, label)
    local g = Instance.new("Model")
    g.Name = "Aisle" .. idx
    g.Parent = f
    local z0, z1 = GOND_Z0, GOND_Z1
    local mid = (x0 + x1) / 2
    local H = FLOOR + 6.2
    box("Kick", x0, FLOOR, z0, x1, FLOOR + 0.5, z1, rgb(60, 64, 72), M.Metal, g)
    box("Spine", mid - 0.12, FLOOR + 0.5, z0, mid + 0.12, H, z1, rgb(196, 200, 204), M.DiamondPlate, g)
    local levels = { FLOOR + 0.5, FLOOR + 2, FLOOR + 3.5, FLOOR + 5 }
    for li, y in ipairs(levels) do
        box("Shelf", x0, y - 0.1, z0, x1, y, z1, rgb(236, 236, 230), M.Metal, g)
        productRow("ProductsW", x0 + 0.05, y, z0 + 0.1, mid - 0.12, y + 1.2, z1 - 0.1, Enum.NormalId.Left, idx * 4 + li, g)
        productRow("ProductsE", mid + 0.12, y, z0 + 0.1, x1 - 0.05, y + 1.2, z1 - 0.1, Enum.NormalId.Right, idx * 4 + li + 2, g)
        box("PriceStrip", x0 - 0.02, y - 0.3, z0, x0, y - 0.1, z1, rgb(255, 236, 120), M.Metal, g, nc())
        box("PriceStrip", x1, y - 0.3, z0, x1 + 0.02, y - 0.1, z1, rgb(255, 236, 120), M.Metal, g, nc())
    end
    -- end cap sign facing the front of the store
    local cap = box("EndCap", x0, H - 0.8, z0 - 0.1, x1, H + 0.6, z0, SUN_DEEP, M.Metal, g, nc())
    lit(printOn(cap, Enum.NormalId.Front, label, rgb(255, 250, 235), UITheme.F.display, 40, 1.2).Parent)
    -- hanging aisle sign
    local sign = box("AisleSign", mid - 1.6, CEIL - 3.2, (z0 + z1) / 2 - 0.05, mid + 1.6, CEIL - 2, (z0 + z1) / 2 + 0.05,
        TEAL, M.Metal, g, nc())
    printOn(sign, Enum.NormalId.Front, "AISLE " .. idx, rgb(255, 255, 255), UITheme.F.display, 40, 1.2)
    printOn(sign, Enum.NormalId.Back, label, rgb(255, 255, 255), UITheme.F.display, 40, 1.2)
    bar("SignWire", Vector3.new(mid - 1.4, CEIL - 2, (z0 + z1) / 2), Vector3.new(mid - 1.4, CEIL, (z0 + z1) / 2), 0.05,
        STEEL_DK, M.Metal, g, nc())
    bar("SignWire", Vector3.new(mid + 1.4, CEIL - 2, (z0 + z1) / 2), Vector3.new(mid + 1.4, CEIL, (z0 + z1) / 2), 0.05,
        STEEL_DK, M.Metal, g, nc())
end

function MartBuilder:_fridges(f)
    local fr = Instance.new("Folder")
    fr.Name = "Fridges"
    fr.Parent = f
    local x0, x1 = FRIDGE_X0, IX1
    local z0, z1 = 3, 13
    local H = FLOOR + 7.4
    box("FridgeBody", x0 + 0.3, FLOOR, z0, x1, H, z1, rgb(40, 44, 52), M.Metal, fr)
    box("FridgeHeader", x0, H, z0, x1, H + 1.3, z1, rgb(20, 120, 200), M.Metal, fr)
    local hdr = box("FridgeHeaderFace", x0 - 0.02, H, z0, x0, H + 1.3, z1, rgb(20, 120, 200), M.Metal, fr, nc())
    printOn(hdr, Enum.NormalId.Left, "COLD DRINKS", rgb(255, 255, 255), UITheme.F.display, 30, 1.4)
    local doors = 5
    local dw = (z1 - z0) / doors
    for d = 0, doors - 1 do
        local dz0, dz1 = z0 + d * dw, z0 + (d + 1) * dw
        -- drinks behind the glass: 5 shelves painted as bottle rows
        for s = 0, 4 do
            local y = FLOOR + 0.6 + s * 1.3
            productRow("Drinks", x0 + 0.35, y, dz0 + 0.15, x0 + 1.2, y + 1.05, dz1 - 0.15, Enum.NormalId.Left, d * 5 + s, fr, true)
            box("FridgeShelf", x0 + 0.35, y - 0.06, dz0 + 0.1, x1 - 0.2, y, dz1 - 0.1, rgb(200, 206, 214), M.Metal, fr, nc())
        end
        box("FridgeGlass", x0, FLOOR + 0.3, dz0 + 0.08, x0 + 0.1, H - 0.1, dz1 - 0.08, rgb(200, 230, 245), M.Glass, fr,
            { Transparency = 0.6, Reflectance = 0.15 })
        box("FridgeMullion", x0 - 0.05, FLOOR + 0.3, dz1 - 0.08, x0 + 0.15, H - 0.1, dz1 + 0.08, STEEL_LT, M.Metal, fr, nc())
        bar("FridgeHandle", Vector3.new(x0 - 0.15, FLOOR + 2.6, dz1 - 0.4), Vector3.new(x0 - 0.15, FLOOR + 5.2, dz1 - 0.4),
            0.1, STEEL_LT, M.Metal, fr, nc())
        -- LED strip down each door (thin neon) + the cold glow
        box("FridgeLed", x0 + 0.12, FLOOR + 0.4, dz0 + 0.12, x0 + 0.2, H - 0.2, dz0 + 0.2, COOL, M.Neon, fr, nc({ CastShadow = false }))
    end
    point(lightAnchor("FridgeGlowN", Vector3.new(x0 - 0.5, FLOOR + 4, 5.5), fr), rgb(190, 225, 255), 1.1, 12)
    point(lightAnchor("FridgeGlowS", Vector3.new(x0 - 0.5, FLOOR + 4, 10.5), fr), rgb(190, 225, 255), 1.1, 12)
end

function MartBuilder:_checkout(f, refs, loot)
    local c = Instance.new("Folder")
    c.Name = "Checkout"
    c.Parent = f
    local topY = FLOOR + 3.3
    -- counter (customer side faces east)
    box("CounterBody", COUNTER_X0, FLOOR, COUNTER_Z0, COUNTER_X1, topY - 0.2, COUNTER_Z1, TEAL, M.Plaster, c)
    box("CounterTop", COUNTER_X0 - 0.1, topY - 0.2, COUNTER_Z0 - 0.1, COUNTER_X1 + 0.15, topY, COUNTER_Z1 + 0.1,
        rgb(236, 232, 226), M.Marble, c)
    local front = box("CounterFront", COUNTER_X1, FLOOR + 0.6, COUNTER_Z0 + 0.3, COUNTER_X1 + 0.05, topY - 0.5, COUNTER_Z1 - 0.3,
        SUN, M.Plaster, c, nc())
    lit(printOn(front, Enum.NormalId.Right, "THANK YOU!", rgb(200, 40, 80), UITheme.F.display, 30, 1).Parent)
    -- candy rack on the customer side
    box("CandyRack", COUNTER_X1 + 0.05, FLOOR, COUNTER_Z0 + 2.6, COUNTER_X1 + 0.9, FLOOR + 2.4, COUNTER_Z0 + 4, STEEL_LT, M.Metal, c)
    productRow("Candy", COUNTER_X1 + 0.1, FLOOR + 0.6, COUNTER_Z0 + 2.65, COUNTER_X1 + 0.85, FLOOR + 1.6, COUNTER_Z0 + 3.95,
        Enum.NormalId.Right, 11, c, true)

    -- two registers (Register loot = the cash drawer)
    for k, rz in ipairs({ 5, 8.6 }) do
        local rx = (COUNTER_X0 + COUNTER_X1) / 2
        box("Register", rx - 0.7, topY, rz - 0.55, rx + 0.5, topY + 0.7, rz + 0.55, rgb(34, 34, 40), M.Metal, c)
        local screen = part({ Name = "RegisterScreen", Size = Vector3.new(0.08, 0.7, 1.1),
            CFrame = CFrame.new(rx - 0.4, topY + 1.25, rz) * CFrame.Angles(0, 0, math.rad(-15)),
            Color = rgb(20, 22, 26), Material = M.Metal, CanCollide = false }, c)
        local sg = surface(screen, Enum.NormalId.Left, 80, 1.4)
        frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 24, 18) }, sg)
        text({ Text = "$0.00", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
            TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true, FontFace = UITheme.F.mono,
            TextColor3 = UITheme.C.money }, sg)
        -- the open drawer full of cash, sticking out toward the customer side
        local drawer = Instance.new("Model")
        drawer.Name = "RegisterCash" .. k
        drawer.Parent = c
        box("Drawer", rx + 0.5, topY + 0.05, rz - 0.5, rx + 1.2, topY + 0.3, rz + 0.5, rgb(52, 52, 60), M.Metal, drawer, nc())
        for b = 0, 3 do
            box("Bills", rx + 0.6, topY + 0.3, rz - 0.45 + b * 0.24, rx + 1.1, topY + 0.38, rz - 0.27 + b * 0.24,
                CASH_GREEN, M.Fabric, drawer, nc({ CastShadow = false }))
        end
        local stand = Vector3.new(COUNTER_X1 + 2, FLOOR + 3, rz)
        table.insert(loot, { kind = "Register", cframe = CFrame.lookAt(stand, Vector3.new(rx, stand.Y, rz)),
            visual = drawer, inVault = false })
    end

    -- behind the clerk: product wall + the lottery ticket case (Lottery loot)
    box("BackShelf", IX0, FLOOR, IZ0 + 0.3, IX0 + 1, FLOOR + 7.5, 5.6, WALNUT, M.Wood, c)
    box("BackShelf", IX0, FLOOR, 8.2, IX0 + 1, FLOOR + 7.5, 11.4, WALNUT, M.Wood, c)
    for s = 0, 3 do
        local y = FLOOR + 1 + s * 1.6
        productRow("WallProducts", IX0 + 1, y, IZ0 + 0.4, IX0 + 1.05, y + 1.2, 5.5, Enum.NormalId.Right, 20 + s, c)
        productRow("WallProducts", IX0 + 1, y, 8.3, IX0 + 1.05, y + 1.2, 11.3, Enum.NormalId.Right, 24 + s, c)
    end
    box("LottoCase", IX0, FLOOR + 2.4, 5.8, IX0 + 0.9, FLOOR + 6.6, 8, rgb(40, 20, 60), M.Metal, c)
    local tickets = Instance.new("Model")
    tickets.Name = "LottoTickets"
    tickets.Parent = c
    local tk = box("Tickets", IX0 + 0.9, FLOOR + 2.7, 5.95, IX0 + 1, FLOOR + 6.3, 7.85, rgb(255, 214, 120), M.Fabric, tickets, nc())
    local tg = lit(surface(tk, Enum.NormalId.Right, 30, 1.3))
    for r = 0, 3 do
        for col = 0, 2 do
            frame({ Size = UDim2.fromScale(0.28, 0.2), Position = UDim2.fromScale(0.04 + col * 0.32, 0.03 + r * 0.245),
                BackgroundColor3 = PRODUCT[((r * 3 + col) % #PRODUCT) + 1] }, tg)
        end
    end
    local lotto = box("LottoSign", IX0 + 0.9, FLOOR + 6.6, 5.8, IX0 + 1, FLOOR + 7.5, 8, SUN, M.Metal, c, nc())
    lit(printOn(lotto, Enum.NormalId.Right, "LOTTO", rgb(120, 20, 60), UITheme.F.display, 40, 1.2).Parent)
    local lstand = Vector3.new(IX0 + 2.8, FLOOR + 3, 6.9)
    table.insert(loot, { kind = "Lottery", cframe = CFrame.lookAt(lstand, Vector3.new(IX0, lstand.Y, 6.9)),
        visual = tickets, inVault = false })

    -- clerk's stool + a little TV
    part({ Name = "Stool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.4, 1.4),
        CFrame = CFrame.new(53.2, FLOOR + 2.4, 9.2) * CFrame.Angles(0, 0, math.rad(90)),
        Color = rgb(200, 40, 60), Material = M.Fabric }, c)
    bar("StoolLeg", Vector3.new(53.2, FLOOR, 9.2), Vector3.new(53.2, FLOOR + 2.25, 9.2), 0.2, STEEL_LT, M.Metal, c, nc())

    -- ice-cream chest freezer in the back-west corner
    box("IceCreamFreezer", IX0 + 0.1, FLOOR, 13.4, 56, FLOOR + 3, SALES_Z1, rgb(236, 244, 250), M.Metal, c)
    box("FreezerLid", IX0 + 0.2, FLOOR + 3, 13.5, 55.9, FLOOR + 3.1, SALES_Z1 - 0.1, rgb(200, 230, 245), M.Glass, c,
        { Transparency = 0.4 })
    lit(printOn(box("FreezerLabel", IX0 + 0.5, FLOOR + 1, 13.38, 55.5, FLOOR + 2.4, 13.4, HOT_PINK, M.Metal, c, nc()),
        Enum.NormalId.Front, "ICE CREAM", rgb(255, 255, 255), UITheme.F.display, 40, 1.2).Parent)
end

function MartBuilder:_salesFloor(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "SalesFloor"
    s.Parent = f
    self:_gondola(s, GONDOLAS[1][1], GONDOLAS[1][2], 1, "SNACKS")
    self:_gondola(s, GONDOLAS[2][1], GONDOLAS[2][2], 2, "CANDY")
    self:_fridges(s)
    self:_checkout(s, refs, loot)

    -- the BIG BOX: a giant soda-case display you can hide inside (HideSpot)
    local bx0, bx1, bz0, bz1 = 57.2, 59.8, 13.1, SALES_Z1 - 0.05
    local bigBox = box("BigBox", bx0, FLOOR, bz0, bx1, FLOOR + 4.2, bz1, rgb(186, 146, 96), M.Cardboard, s)
    local bg = lit(surface(bigBox, Enum.NormalId.Front, 30, 1))
    text({ Text = "SUNNY\nSODA", Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.08),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(200, 40, 80) }, bg)
    text({ Text = "24 PACK", Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.65),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold,
        TextColor3 = rgb(40, 40, 44) }, bg)
    box("BigBoxFlap", bx0, FLOOR + 4.2, bz0, bx1, FLOOR + 4.3, bz0 + 0.8, rgb(170, 132, 86), M.Cardboard, s, nc())
    tag(bigBox, "HideSpot", { Label = "Big box" })
    table.insert(refs.hideSpots, bigBox)

    -- ceiling tubes: three long rows of troffers down the aisles (v2.0.2: they
    -- no longer overlap). Bright over the aisles, dimmer at the back, aisle 2's
    -- dead tube = the dark aisle. Two tubes are key lights (shadows).
    for _, tx in ipairs({ 57.5, 63.5, 69 }) do
        for _, tz in ipairs({ 4.2, 8.6, 13.0 }) do
            local dead = (tx == 63.5 and tz == 8.6)
            local key = (tz == 8.6 and tx ~= 63.5)
            tubeLight(s, tx, tz, false, (tz == 13.0) and 0.55 or 0.85, 14, not dead, 4.0, key)
        end
    end

    -- (v2.0.2) floor: darker tile runners down the aisles + a teal band at the fridges
    local RUNNER = rgb(170, 172, 176)
    box("AisleRunner", COUNTER_X1 + 0.6, FLOOR, GOND_Z0, GONDOLAS[1][1] - 0.4, FLOOR + 0.02, GOND_Z1, RUNNER, M.CeramicTiles, s, nc())
    box("AisleRunner", GONDOLAS[1][2] + 0.4, FLOOR, GOND_Z0, GONDOLAS[2][1] - 0.4, FLOOR + 0.02, GOND_Z1, rgb(120, 122, 128),
        M.CeramicTiles, s, nc())
    box("AisleRunner", GONDOLAS[2][2] + 0.4, FLOOR, GOND_Z0, FRIDGE_X0 - 2.2, FLOOR + 0.02, GOND_Z1, RUNNER, M.CeramicTiles, s, nc())
    box("FridgeBand", FRIDGE_X0 - 2, FLOOR, 3, FRIDGE_X0, FLOOR + 0.02, 13, TEAL, M.CeramicTiles, s, nc())

    -- (v2.0.2) back wall: black cove base on the mint wainscot + two promo posters
    box("CoveBase", IX0, FLOOR, SALES_Z1 - 0.16, CURTAIN_X0, FLOOR + 0.5, SALES_Z1 - 0.1, rgb(26, 26, 30), M.Rubber, s, nc())
    box("CoveBase", CURTAIN_X1, FLOOR, SALES_Z1 - 0.16, IX1, FLOOR + 0.5, SALES_Z1 - 0.1, rgb(26, 26, 30), M.Rubber, s, nc())
    box("WainscotCap", IX0, FLOOR + 3, SALES_Z1 - 0.18, CURTAIN_X0, FLOOR + 3.2, SALES_Z1, TEAL, M.Plaster, s, nc())
    box("WainscotCap", CURTAIN_X1, FLOOR + 3, SALES_Z1 - 0.18, IX1, FLOOR + 3.2, SALES_Z1, TEAL, M.Plaster, s, nc())
    for _, pp in ipairs({ { 52.2, 57, "HOT DOGS\n$1.99", SUN_DEEP }, { 70.6, 72.8, "SLUSH!", CYAN } }) do
        local po = box("PromoPoster", pp[1], FLOOR + 5.6, SALES_Z1 - 0.06, pp[2], FLOOR + 9.4, SALES_Z1, rgb(250, 248, 240), M.Fabric, s, nc())
        local pg = lit(surface(po, Enum.NormalId.Front, 30, 1))
        frame({ Size = UDim2.fromScale(1, 0.18), BackgroundColor3 = pp[4] }, pg)
        text({ Text = pp[3], Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.24),
            TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
            TextColor3 = rgb(40, 30, 50) }, pg)
    end
    table.insert(refs.shadowZones, shadowZone("ShadowDarkAisle", GONDOLAS[1][2], 6.2, GONDOLAS[2][1], 11.8, s))
    table.insert(refs.shadowZones, shadowZone("ShadowFreezerCorner", IX0, 11.4, 57, SALES_Z1, s))

    -- a mop bucket + wet floor sign (cover in the front aisle's east end)
    local sign = part({ Name = "WetFloorSign", Size = Vector3.new(1.2, 2.2, 0.2),
        CFrame = CFrame.new(70.2, FLOOR + 1.1, 13.9) * CFrame.Angles(math.rad(-12), math.rad(20), 0),
        Color = rgb(255, 214, 40), Material = M.Rubber, CanCollide = false }, s)
    lit(printOn(sign, Enum.NormalId.Front, "WET\nFLOOR", rgb(30, 30, 30), UITheme.F.display, 50, 1).Parent)
    return bigBox
end

-- ──────────────────────────────────────────────
-- 📦 STOCK ROOM (sneakIn) + back door
-- ──────────────────────────────────────────────
function MartBuilder:_stockRoom(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "StockRoom"
    s.Parent = f

    -- strip curtain in the doorway to the sales floor: you walk through it,
    -- but it blocks the guard's view into the stock room
    local n = 10
    local sw = (CURTAIN_X1 - CURTAIN_X0) / n
    for k = 0, n - 1 do
        local x = CURTAIN_X0 + (k + 0.5) * sw
        box("CurtainStrip", x - sw / 2 + 0.03, FLOOR + 0.2, 15.45, x + sw / 2 - 0.03, DOOR_H, 15.55,
            rgb(200, 222, 230), M.Glass, s, nc({ Transparency = 0.45, CastShadow = false }))
    end
    box("CurtainRail", CURTAIN_X0, DOOR_H - 0.2, 15.35, CURTAIN_X1, DOOR_H, 15.65, STEEL_LT, M.Metal, s, nc())
    local emp = box("EmployeesOnly", 65, DOOR_H + 0.5, SALES_Z1 - 0.1, 68, DOOR_H + 1.5, SALES_Z1, rgb(200, 40, 60), M.Metal, s, nc())
    lit(printOn(emp, Enum.NormalId.Front, "EMPLOYEES ONLY", rgb(255, 255, 255), UITheme.F.bold, 50, 1.2).Parent)

    -- (v2.0.2) painted cinder-block walls, yellow forklift lines on the concrete
    local BLOCK = rgb(196, 198, 190)
    box("BlockWall", STOCK_X0, FLOOR, IZ1 - 0.08, IX1, CEIL, IZ1, BLOCK, M.Brick, s, nc())
    box("BlockWall", STOCK_X0, FLOOR, BACK_Z0, CURTAIN_X0, CEIL, BACK_Z0 + 0.06, BLOCK, M.Brick, s, nc())
    box("BlockWall", CURTAIN_X1, FLOOR, BACK_Z0, IX1, CEIL, BACK_Z0 + 0.06, BLOCK, M.Brick, s, nc())
    box("BumpStripe", STOCK_X0, FLOOR + 0.9, IZ1 - 0.12, IX1, FLOOR + 1.5, IZ1 - 0.08, rgb(240, 196, 40), M.Plaster, s, nc())
    local SAFETY = rgb(236, 196, 48)
    box("FloorLine", STOCK_X0 + 0.4, FLOOR, 17.2, IX1 - 2.2, FLOOR + 0.02, 17.45, SAFETY, M.Plaster, s, nc())
    box("FloorLine", STOCK_X0 + 0.4, FLOOR, IZ1 - 2.45, IX1 - 2.2, FLOOR + 0.02, IZ1 - 2.2, SAFETY, M.Plaster, s, nc())

    -- breaker panel on the north wall (faces into the stock room)
    local bx0, bx1 = 60.6, 62.6
    local breaker = box("BreakerPanel", bx0, FLOOR + 2.8, BACK_Z0, bx1, FLOOR + 6.2, BACK_Z0 + 0.45, rgb(96, 102, 110), M.Metal, s)
    local bg = lit(surface(breaker, Enum.NormalId.Back, 50, 1.1))
    text({ Text = "SECURITY", Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 204, 21) }, bg)
    text({ Text = "CAMERA · ALARM", Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, 0.21),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(30, 32, 38) }, bg)
    for r = 0, 2 do
        for col = 0, 3 do
            frame({ Size = UDim2.fromScale(0.14, 0.12), Position = UDim2.fromScale(0.12 + col * 0.2, 0.4 + r * 0.18),
                BackgroundColor3 = rgb(40, 42, 48) }, bg)
        end
    end
    for k, col in ipairs({ rgb(80, 255, 120), rgb(255, 180, 40) }) do
        local lx = bx0 + 0.6 + (k - 1) * 0.6
        box("BreakerLed", lx - 0.07, FLOOR + 5.8, BACK_Z0 + 0.45, lx + 0.07, FLOOR + 5.94, BACK_Z0 + 0.52, col, M.Neon, s, nc())
    end
    box("Conduit", 61.5, FLOOR + 6.2, BACK_Z0, 61.7, CEIL, BACK_Z0 + 0.2, STEEL_LT, M.Metal, s, nc())

    -- metal racking along the south wall, full of stock (cover)
    local rx0, rx1, rz0 = 63, 70.5, IZ1 - 1.8
    for _, y in ipairs({ FLOOR + 0.3, FLOOR + 2.8, FLOOR + 5.3 }) do
        box("RackShelf", rx0, y, rz0, rx1, y + 0.15, IZ1, rgb(60, 90, 160), M.Metal, s)
    end
    for _, px in ipairs({ rx0 + 0.05, (rx0 + rx1) / 2, rx1 - 0.05 }) do
        box("RackPost", px - 0.08, FLOOR, rz0, px + 0.08, FLOOR + 7.4, rz0 + 0.15, rgb(230, 120, 40), M.Metal, s, nc())
    end
    for k = 0, 5 do
        local bxa = rx0 + 0.2 + k * 1.2
        local y = (k % 2 == 0) and FLOOR + 0.45 or FLOOR + 2.95
        box("StockBox", bxa, y, rz0 + 0.2, bxa + 1.05, y + 1.3 + (k % 3) * 0.3, IZ1 - 0.1,
            rgb(176 + (k % 3) * 8, 140 + (k % 2) * 10, 96), M.Cardboard, s)
    end
    -- a box of lotto tickets on the top shelf (Lottery loot)
    local lot = Instance.new("Model")
    lot.Name = "LottoBox"
    lot.Parent = s
    local lb = box("LottoBox", 68.2, FLOOR + 5.45, rz0 + 0.2, 70.1, FLOOR + 6.6, IZ1 - 0.1, rgb(255, 214, 120), M.Cardboard, lot, nc())
    lit(printOn(lb, Enum.NormalId.Front, "LOTTO", rgb(160, 30, 80), UITheme.F.display, 40, 1).Parent)
    local ls = Vector3.new(69.1, FLOOR + 3, rz0 - 2.2)
    table.insert(loot, { kind = "Lottery", cframe = CFrame.lookAt(ls, Vector3.new(69.1, ls.Y, IZ1)), visual = lot, inVault = false })

    -- pallet of shrink-wrapped soda with tonight's cash deposit bag on top (Cash loot)
    local px0, px1, pz0, pz1 = 63.5, 66.5, 18, 20.6
    box("Pallet", px0, FLOOR, pz0, px1, FLOOR + 0.5, pz1, rgb(170, 130, 80), M.WoodPlanks, s)
    box("PalletLoad", px0 + 0.1, FLOOR + 0.5, pz0 + 0.1, px1 - 0.1, FLOOR + 2.8, pz1 - 0.1, rgb(220, 60, 60), M.Cardboard, s)
    box("ShrinkWrap", px0 + 0.05, FLOOR + 0.5, pz0 + 0.05, px1 - 0.05, FLOOR + 2.85, pz1 - 0.05, rgb(230, 240, 250), M.Glass, s,
        nc({ Transparency = 0.7 }))
    local bag = Instance.new("Model")
    bag.Name = "DepositBag"
    bag.Parent = s
    part({ Name = "Bag", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.1, 1.2),
        Position = Vector3.new(65, FLOOR + 3.3, 19.3), Color = rgb(110, 116, 110), Material = M.Fabric, CanCollide = false }, bag)
    box("BagZip", 64.4, FLOOR + 3.8, 19.25, 65.6, FLOOR + 3.9, 19.35, rgb(220, 190, 60), M.Metal, bag, nc())
    local bs = Vector3.new(65, FLOOR + 3, 16.9)
    table.insert(loot, { kind = "Cash", cframe = CFrame.lookAt(bs, Vector3.new(65, bs.Y, 19.3)), visual = bag, inVault = false })

    -- tall steel broom closet in the south-east corner (HideSpot)
    local closet = box("BroomCloset", 70.8, FLOOR, IZ1 - 1.8, IX1 - 0.05, FLOOR + 7.4, IZ1, rgb(120, 150, 170), M.Metal, s)
    local cg = lit(surface(closet, Enum.NormalId.Front, 30, 1))
    frame({ Size = UDim2.fromScale(0.02, 0.96), Position = UDim2.fromScale(0.49, 0.02), BackgroundColor3 = rgb(60, 80, 96) }, cg)
    for k = 0, 1 do
        frame({ Size = UDim2.fromScale(0.06, 0.12), Position = UDim2.fromScale(0.4 + k * 0.14, 0.45), BackgroundColor3 = STEEL_LT }, cg)
        for v = 0, 3 do
            frame({ Size = UDim2.fromScale(0.3, 0.012), Position = UDim2.fromScale(0.08 + k * 0.5, 0.06 + v * 0.03),
                BackgroundColor3 = rgb(60, 80, 96) }, cg)
        end
    end
    tag(closet, "HideSpot", { Label = "Closet" })
    table.insert(refs.hideSpots, closet)

    -- hand truck leaning by the office door + a couple of loose boxes
    bar("HandTruck", Vector3.new(61, FLOOR, 23.2), Vector3.new(60.6, FLOOR + 4.4, 23.6), 0.14, rgb(230, 60, 40), M.Metal, s, nc())

    -- (v2.0.2) one dim tube + a caged work lamp on a cord (the key light, shadows)
    tubeLight(s, 66, 20, true, 0.4, 12)
    bar("LampCord", Vector3.new(66.5, CEIL, 18.2), Vector3.new(66.5, CEIL - 2.6, 18.2), 0.06, STEEL_DK, M.Rubber, s, nc())
    local cage = box("CageLamp", 66.1, CEIL - 3.2, 17.8, 66.9, CEIL - 2.6, 18.6, STEEL_DK, M.Metal, s, nc())
    box("CageLampBulb", 66.25, CEIL - 3.35, 17.95, 66.75, CEIL - 3.2, 18.45, WARM, M.Neon, s, nc({ CastShadow = false }))
    point(cage, rgb(255, 210, 160), 0.9, 13, true)
    table.insert(refs.shadowZones, shadowZone("ShadowStockCorner", STOCK_X0, 20.5, 63, IZ1, s))

    -- ── the back door: open steel double doors onto the east alley ──
    local x = X1
    local STEELC = rgb(70, 74, 82)
    box("BackDoorFrameN", x, 0, SIDE_DOOR_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, SIDE_DOOR_Z0, STEELC, M.Metal, s)
    box("BackDoorFrameS", x, 0, SIDE_DOOR_Z1, x + 0.25, DOOR_H + 0.3, SIDE_DOOR_Z1 + 0.3, STEELC, M.Metal, s)
    box("BackDoorFrameTop", x, DOOR_H, SIDE_DOOR_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, SIDE_DOOR_Z1 + 0.3, STEELC, M.Metal, s)
    box("BackDoorLeaf", x + 0.25, FLOOR, SIDE_DOOR_Z0 - 3.8, x + 0.45, DOOR_H - 0.1, SIDE_DOOR_Z0 - 0.3, rgb(96, 100, 110), M.DiamondPlate, s, nc())
    box("BackDoorLeaf", x + 0.25, FLOOR, SIDE_DOOR_Z1 + 0.3, x + 0.45, DOOR_H - 0.1, SIDE_DOOR_Z1 + 3.8, rgb(96, 100, 110), M.DiamondPlate, s, nc())
    box("BackDoorStep", x, 0, SIDE_DOOR_Z0, x + 2, FLOOR, SIDE_DOOR_Z1, rgb(150, 146, 140), M.Concrete, s)
    local plate = box("BackDoorPlate", x + 0.25, DOOR_H + 0.6, SIDE_DOOR_Z0 + 1.2, x + 0.35, DOOR_H + 1.9, SIDE_DOOR_Z1 - 1.2,
        rgb(26, 26, 30), M.Metal, s)
    lit(printOn(plate, Enum.NormalId.Right, "DELIVERIES", rgb(255, 200, 60), UITheme.F.bold, 60, 1.3).Parent)
    local mid = (SIDE_DOOR_Z0 + SIDE_DOOR_Z1) / 2
    local lamp = box("AlleyLamp", x + 0.25, DOOR_H + 2.4, mid - 0.5, x + 0.9, DOOR_H + 2.8, mid + 0.5, STEEL_DK, M.Metal, s, nc())
    box("AlleyLampLens", x + 0.3, DOOR_H + 2.3, mid - 0.4, x + 0.85, DOOR_H + 2.4, mid + 0.4, rgb(255, 214, 150), M.Neon, s, nc())
    spot(lamp, Enum.NormalId.Bottom, rgb(255, 200, 140), 1.3, 16, 100, true)

    return breaker
end

-- ──────────────────────────────────────────────
-- 🗄 OFFICE: desk, CCTV, ladder to the roof, the floor safe (= the vault)
-- ──────────────────────────────────────────────
function MartBuilder:_office(f, refs, loot)
    local o = Instance.new("Folder")
    o.Name = "Office"
    o.Parent = f

    -- (v2.0.2) walls: navy painted wainscot + white rail + striped wallpaper on
    -- the north (desk) and south (safe) walls
    local WAINSCOT = rgb(34, 46, 74)
    local RAIL = rgb(226, 222, 210)
    for _, w in ipairs({ { BACK_Z0, BACK_Z0 + 0.06, Enum.NormalId.Back }, { IZ1 - 0.06, IZ1, Enum.NormalId.Front } }) do
        box("Wainscot", IX0, FLOOR, w[1], OFFICE_X1, FLOOR + 3.6, w[2], WAINSCOT, M.Plaster, o, nc())
        local rz0 = (w[3] == Enum.NormalId.Back) and w[1] or w[2] - 0.12
        box("ChairRail", IX0, FLOOR + 3.6, rz0, OFFICE_X1, FLOOR + 3.85, rz0 + 0.12, RAIL, M.Plaster, o, nc())
        local wp = box("Wallpaper", IX0, FLOOR + 3.85, w[1], OFFICE_X1, CEIL, w[2], rgb(232, 214, 170), M.Fabric, o, nc())
        wallpaper(wp, w[3], rgb(228, 210, 166), rgb(214, 120, 60), 6)
    end

    -- desk along the north wall (satin wood — the old WoodPlanks read as stripes)
    local dx0, dx1, dz0, dz1 = 54.3, 58.6, BACK_Z0, BACK_Z0 + 2.2
    local topY = FLOOR + 2.9
    box("DeskTop", dx0, topY - 0.25, dz0, dx1, topY, dz1, WALNUT, M.Wood, o)
    box("DeskSide", dx0, FLOOR, dz0, dx0 + 0.2, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskSide", dx1 - 0.2, FLOOR, dz0, dx1, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskBack", dx0, FLOOR + 0.8, dz0, dx1, topY - 0.25, dz0 + 0.2, WALNUT, M.Wood, o)
    -- desk lamp: the office's key light (shadows); the ceiling light is dim
    local lx, lz = 54.65, dz0 + 1.5     -- west end of the desk, clear of the monitor
    box("LampBase", lx - 0.25, topY, lz - 0.25, lx + 0.25, topY + 0.1, lz + 0.25, STEEL_DK, M.Metal, o, nc())
    bar("LampArm", Vector3.new(lx, topY + 0.1, lz), Vector3.new(lx - 0.4, topY + 1.3, lz + 0.2), 0.07, STEEL_DK, M.Metal, o, nc())
    local shade = box("LampShade", lx - 0.8, topY + 1.1, lz - 0.1, lx - 0.1, topY + 1.45, lz + 0.5, SUN_DEEP, M.Metal, o, nc())
    spot(shade, Enum.NormalId.Bottom, rgb(255, 214, 160), 1.6, 10, 80, true)
    -- papers + a mug
    box("Papers", 57, topY, dz0 + 0.6, 58, topY + 0.1, dz0 + 1.4, rgb(250, 250, 244), M.Fabric, o, nc())
    part({ Name = "Mug", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 0.35, 0.35),
        CFrame = CFrame.new(54.9, topY + 0.23, dz0 + 1.6) * CFrame.Angles(0, 0, math.rad(90)),
        Color = SUN, Material = M.Glass, CanCollide = false }, o)

    -- CCTV monitor on the wall over the desk (faces south into the office)
    local mon = box("CctvMonitor", 55, FLOOR + 5.2, BACK_Z0, 58, FLOOR + 7.4, BACK_Z0 + 0.25, rgb(20, 20, 24), M.Metal, o)
    local mg = surface(mon, Enum.NormalId.Back, 50, 1.1)
    local feeds = { "CAM 1 · REGISTER", "NO SIGNAL" }
    for k, label in ipairs(feeds) do
        local cell = frame({ Size = UDim2.fromScale(0.47, 0.9), Position = UDim2.fromScale(0.02 + (k - 1) * 0.49, 0.05),
            BackgroundColor3 = rgb(18, 34, 40) }, mg)
        text({ Text = label, Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.05),
            TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = rgb(140, 220, 200) }, cell)
    end
    point(lightAnchor("MonitorGlow", Vector3.new(56.5, FLOOR + 5.5, BACK_Z0 + 1.2), o), rgb(150, 200, 255), 0.5, 7)

    -- calendar + "SAFE CODE? NICE TRY" note
    local cal = box("Calendar", 52, 5.5, BACK_Z0 + 0.06, 53.6, 7.6, BACK_Z0 + 0.14, rgb(250, 250, 244), M.Fabric, o, nc())
    local calg = lit(surface(cal, Enum.NormalId.Back, 40, 1))
    frame({ Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = SUN_DEEP }, calg)
    text({ Text = "SEPT", Size = UDim2.fromScale(0.9, 0.25), Position = UDim2.fromScale(0.05, 0.03),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(255, 255, 255) }, calg)

    -- ladder up the west wall to the roof hatch (inside end of the roof "vent")
    local lz0, lz1 = 18.7, 20.9
    for _, rz in ipairs({ lz0, lz1 }) do
        box("LadderRail", IX0, FLOOR, rz - 0.1, IX0 + 0.6, CEIL, rz + 0.1, STEEL_LT, M.Metal, o, nc())
    end
    for y = FLOOR + 1, CEIL - 1, 1.2 do
        box("LadderRung", IX0 + 0.35, y, lz0, IX0 + 0.5, y + 0.12, lz1, STEEL_LT, M.Metal, o, nc())
    end
    box("CeilingHatch", IX0 + 0.2, CEIL - 0.12, lz0 - 0.3, IX0 + 3, CEIL, lz1 + 0.3, STEEL, M.Metal, o, nc())
    local inside = facingPart("SM_RoofHatchInside", Vector3.new(IX0 + 0.7, FLOOR + 3, (lz0 + lz1) / 2),
        Vector3.new(2, 5, 0.15), Vector3.new(1, 0, 0), rgb(250, 204, 21), M.Metal, o,
        { Transparency = 0.2, CanCollide = false })
    local ig = lit(surface(inside, Enum.NormalId.Front, 40, 1))
    text({ Text = "UP TO ROOF", Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.05),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(30, 30, 30) }, ig)

    local lamp = box("OfficeLight", 54.5, CEIL - 0.25, 19.3, 57.5, CEIL, 20.1, STEEL_LT, M.Metal, o, nc())
    box("OfficeLightLens", 54.6, CEIL - 0.3, 19.4, 57.4, CEIL - 0.25, 20, WARM, M.Neon, o, nc())
    point(lamp, WARM, 0.45, 11, false)

    -- ── the floor safe ──
    local sx0, sx1 = SAFE_X - SAFE_HW, SAFE_X + SAFE_HW
    local fz0, fz1 = SAFE_Z0, SAFE_Z0 + 0.4
    local oy0, oy1 = SAFE_Y - 1.1, SAFE_Y + 1.1
    local ox0, ox1 = SAFE_X - 1.1, SAFE_X + 1.1
    local topS = SAFE_TOP
    local SAFE_COL = rgb(52, 70, 64)
    local body = Instance.new("Model")
    body.Name = "Safe"
    body.Parent = o
    box("SafeBack", sx0, FLOOR, SAFE_Z1 - 0.4, sx1, topS, SAFE_Z1, SAFE_COL, M.Metal, body)
    box("SafeSide", sx0, FLOOR, fz1, sx0 + 0.4, topS, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeSide", sx1 - 0.4, FLOOR, fz1, sx1, topS, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeTop", sx0, topS - 0.4, fz0, sx1, topS, SAFE_Z1, SAFE_COL, M.Metal, body)
    box("SafeFloor", sx0 + 0.4, FLOOR, fz1, sx1 - 0.4, FLOOR + 0.4, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeFront", sx0, FLOOR, fz0, ox0, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox1, FLOOR, fz0, sx1, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox0, oy1, fz0, ox1, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox0, FLOOR, fz0, ox1, oy0, fz1, SAFE_COL, M.Metal, body)
    box("SafeLining", sx0 + 0.4, FLOOR + 0.4, SAFE_Z1 - 0.5, sx1 - 0.4, topS - 0.4, SAFE_Z1 - 0.4, rgb(120, 20, 36), M.Fabric, body)
    box("SafeShelf", sx0 + 0.4, SAFE_Y - 0.1, fz1, sx1 - 0.4, SAFE_Y, SAFE_Z1 - 0.5, STEEL_LT, M.Metal, body)
    box("SafePinstripe", sx0 - 0.02, topS - 0.9, fz0 - 0.02, sx1 + 0.02, topS - 0.78, SAFE_Z1, rgb(220, 190, 110), M.Metal, body, nc())
    local plate = box("SafeNameplate", SAFE_X - 1, topS - 0.7, fz0 - 0.04, SAFE_X + 1, topS - 0.45, fz0, rgb(220, 190, 110), M.Metal, body, nc())
    lit(printOn(plate, Enum.NormalId.Front, "SUNNY'S", rgb(60, 36, 14), UITheme.F.display, 60, 1).Parent)

    -- round door, hinged on the WEST edge, swings open north-west (+100°),
    -- ending up at x ≈ 53.1..53.9, z 17.4..20.6 — clear of the ladder and desk
    local dz = fz0 - DISC_T / 2
    local faceZ = fz0 - DISC_T
    local door = Instance.new("Model")
    door.Name = "SafeDoor"
    door.Parent = o
    local swing = {}
    local function add(p)
        table.insert(swing, p)
        return p
    end
    add(part({ Name = "DoorDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(DISC_T, DISC_R * 2, DISC_R * 2),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, dz) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(150, 160, 156), Material = M.Metal, Reflectance = 0.12 }, door))
    local lock = add(box("LockPlate", SAFE_X - 0.5, SAFE_Y - 0.5, faceZ - 0.14, SAFE_X + 0.5, SAFE_Y + 0.5, faceZ,
        rgb(220, 190, 110), M.Metal, door, { Reflectance = 0.2 }))
    add(part({ Name = "Dial", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.7, 0.7),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, faceZ - 0.21) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(28, 28, 32), Material = M.Metal, CanCollide = false }, door))
    local hub = Vector3.new(SAFE_X + 0.95, SAFE_Y, faceZ - 0.2)
    add(part({ Name = "Handle", Size = Vector3.new(0.14, 1.1, 0.14), CFrame = CFrame.new(hub),
        Color = STEEL_LT, Material = M.Metal, CanCollide = false }, door))
    local hx = SAFE_X - DISC_R
    for _, ky in ipairs({ SAFE_Y - 0.9, SAFE_Y + 0.9 }) do
        part({ Name = "HingeKnuckle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.32, 0.32),
            CFrame = CFrame.new(hx, ky, faceZ + 0.08) * CFrame.Angles(0, 0, math.rad(90)),
            Color = STEEL_DK, Material = M.Metal }, body)
    end
    refs.vault = {
        door = lock,
        parts = swing,
        hinge = CFrame.new(hx, SAFE_Y, faceZ),
        openAngle = math.rad(100),
        -- (v2.1) "Place drill" at head height (the desk + chair crowd the lock plate)
        drillOffset = Vector3.new(0, 2, -1),
    }

    -- safe contents: cash on the shelf, cash on the floor of the safe
    local innerZ = (fz1 + SAFE_Z1 - 0.5) / 2
    local c1 = Instance.new("Model")
    c1.Name = "SafeCashTop"
    c1.Parent = o
    cashStack(c1, SAFE_X, SAFE_Y, innerZ, 2, 2, 3)
    local c2 = Instance.new("Model")
    c2.Name = "SafeCashLow"
    c2.Parent = o
    cashStack(c2, SAFE_X, FLOOR + 0.4, innerZ, 3, 2, 2)
    local function stand(x)
        local p = Vector3.new(x, FLOOR + 3, 19.2)
        return CFrame.lookAt(p, Vector3.new(x, p.Y, SAFE_Z0))
    end
    table.insert(loot, { kind = "Cash", cframe = stand(SAFE_X + 0.9), visual = c1 })
    table.insert(loot, { kind = "Cash", cframe = stand(SAFE_X - 0.9), visual = c2 })

    -- (v2.0 fix) chair nudged east, off the safe line: at x 56.4 it sat right where the drill goes and blocked the "Place drill" prompt's line of sight
    -- (v2.0.2) both repainted after they load — they import as plain white blocks
    prop("furniture", "chairDesk", Vector3.new(57.6, FLOOR, dz1 + 0.6), Vector3.new(0, 0, -1), o,
        { main = { rgb(28, 26, 30), M.Fabric }, accent = { rgb(150, 154, 162), M.Metal } }, { collide = false })
    prop("furniture", "computerScreen", Vector3.new(56.4, topY, dz0 + 0.7), Vector3.new(0, 0, 1), o,
        { main = { rgb(36, 38, 44), M.Metal, 0.05 }, byName = { screen = { rgb(40, 90, 140), M.Glass, 0.2 } } })

    return inside
end

-- ──────────────────────────────────────────────
-- 🗑 EAST ALLEY + ROOF
-- ──────────────────────────────────────────────
-- (v2.0.2) the walled SERVICE YARD: the strip between the store and the bank
-- + a strip behind the store. Brick walls all round (no gaps), a roll-up
-- vehicle gate onto Ocean Drive, the getaway car parked nose-to-the-gate,
-- dumpster / crates / pallets / propane cage / puddles / lamps. Replaces the
-- open v2.0 alley (you could walk out of the back door onto the lawn).
function MartBuilder:_yard(f, refs)
    local a = Instance.new("Folder")
    a.Name = "ServiceYard"
    a.Parent = f
    local BRICK = rgb(150, 84, 62)
    local CAP = rgb(196, 188, 176)
    local PLINTH = rgb(78, 74, 72)
    local H, T = YWALL_H, YWALL_T
    local EX0 = YARD_X1 - T               -- inner face of the east wall (83.1)
    local SZ0 = YARD_Z1 - T               -- inner face of the south wall (32.9)
    local WX1 = X0 + T                    -- inner face of the back strip's west wall (50.6)

    -- ── ground ──
    box("YardFloor", X1, 0, Z0, EX0, 0.1, SZ0, rgb(52, 52, 58), M.Asphalt, a)
    box("BackStripFloor", WX1, 0, Z1, X1, 0.1, SZ0, rgb(120, 118, 112), M.Concrete, a)
    box("Driveway", X1, 0, -1.4, EX0, 0.1, Z0, rgb(150, 148, 142), M.Concrete, a)
    local LINE = rgb(236, 196, 48)
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z - 6.2, CAR_X - 3.2, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X + 3.2, 0.1, CAR_Z - 6.2, CAR_X + 3.4, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z + 6.4, CAR_X + 3.4, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    -- hatched "keep clear" box in front of the back door
    for k = 0, 3 do
        local z = SIDE_DOOR_Z0 + 0.6 + k * 1.7
        part({ Name = "KeepClearHatch", Size = Vector3.new(0.2, 0.02, 2.4),
            CFrame = CFrame.new(X1 + 2.6, 0.11, z) * CFrame.Angles(0, math.rad(45), 0),
            Color = LINE, Material = M.Plaster, CanCollide = false, CastShadow = false }, a)
    end

    -- ── brick walls (CanCollide, meet the store walls exactly) ──
    box("YardGatePost", GATE_X1, 0, Z0 - 0.3, EX0, H + 1, Z0 + 0.7, BRICK, M.Brick, a)
    box("YardWallE", EX0, 0, Z0 - 0.3, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    box("YardWallS", X0, 0, SZ0, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    box("YardWallW", X0, 0, Z1, WX1, H, SZ0, BRICK, M.Brick, a)
    box("YardCoping", EX0 - 0.1, H, Z0 - 0.4, YARD_X1 + 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("YardCoping", X0 - 0.1, H, SZ0 - 0.1, EX0 - 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("YardCoping", X0 - 0.1, H, Z1, WX1 + 0.1, H + 0.35, SZ0 - 0.1, CAP, M.Concrete, a)
    box("PostCap", GATE_X1 - 0.1, H + 1, Z0 - 0.4, EX0, H + 1.4, Z0 + 0.8, CAP, M.Concrete, a)
    box("Plinth", EX0 - 0.08, 0.1, Z0 + 0.7, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())
    box("Plinth", WX1, 0.1, SZ0 - 0.08, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())

    -- ── the vehicle gate: roll-up shutter, rolled up (clear height 10.6) ──
    local SHUT = rgb(150, 156, 166)
    local gz0, gz1 = Z0 - 0.2, Z0 + 0.4
    local beam = box("GateHeader", GATE_X0, 11.4, gz0, GATE_X1, 12.2, gz1, BRICK, M.Brick, a)
    box("ShutterDrum", GATE_X0 + 0.1, 10.9, gz0 + 0.05, GATE_X1 - 0.1, 11.4, gz1 + 0.35, SHUT, M.Metal, a, nc())
    box("ShutterBottomBar", GATE_X0 + 0.2, 10.6, gz1 - 0.05, GATE_X1 - 0.2, 10.9, gz1 + 0.15, STEEL, M.Metal, a, nc())
    for _, gx in ipairs({ GATE_X0 + 0.05, GATE_X1 - 0.2 }) do
        box("ShutterGuide", gx, 0.1, gz0 + 0.1, gx + 0.15, 11.4, gz1, STEEL, M.Metal, a, nc())
    end
    lit(printOn(beam, Enum.NormalId.Front, "DELIVERIES · NO PARKING", rgb(250, 240, 220), UITheme.F.bold, 30, 1).Parent)
    -- lantern on the gate post
    local lantern = box("PostLantern", GATE_X1 + 0.1, H + 1.4, Z0 - 0.2, EX0 - 0.1, H + 2.3, Z0 + 0.5, STEEL_DK, M.Metal, a, nc())
    box("PostLanternGlass", GATE_X1 + 0.18, H + 1.55, Z0 - 0.12, EX0 - 0.18, H + 2.15, Z0 + 0.42, rgb(255, 214, 150), M.Neon, a,
        nc({ CastShadow = false }))
    point(lantern, rgb(255, 196, 130), 0.9, 12, false)

    -- ── lamps: the yard's key light (shadows) over the car + one on the back strip ──
    local key = box("YardLamp", EX0 - 0.7, 9.6, CAR_Z - 0.7, EX0, 10.3, CAR_Z + 0.7, STEEL_DK, M.Metal, a, nc())
    box("YardLampLens", EX0 - 0.65, 9.52, CAR_Z - 0.6, EX0 - 0.05, 9.6, CAR_Z + 0.6, rgb(255, 196, 120), M.Neon, a,
        nc({ CastShadow = false }))
    spot(key, Enum.NormalId.Bottom, rgb(255, 180, 110), 1.7, 26, 120, true)
    local back = box("YardLamp", 57.3, 9.6, SZ0 - 0.7, 58.7, 10.3, SZ0, STEEL_DK, M.Metal, a, nc())
    box("YardLampLens", 57.4, 9.52, SZ0 - 0.65, 58.6, 9.6, SZ0 - 0.05, rgb(255, 196, 120), M.Neon, a, nc({ CastShadow = false }))
    spot(back, Enum.NormalId.Bottom, rgb(255, 180, 110), 1.3, 18, 110, false)

    -- ── props (hard against the walls, clear of the car and its run to the gate) ──
    -- blue dumpster behind the store
    local dx0, dx1 = 53.4, 57.2
    box("Dumpster", dx0, 0.4, SZ0 - 3.8, dx1, 4.2, SZ0 - 0.3, rgb(30, 90, 150), M.Metal, a)
    box("DumpsterLid", dx0 - 0.1, 4.2, SZ0 - 3.9, dx1 + 0.1, 4.45, SZ0 - 0.2, rgb(22, 66, 110), M.Metal, a)
    box("DumpsterSkid", dx0 + 0.2, 0.1, SZ0 - 3.6, dx1 - 0.2, 0.4, SZ0 - 0.5, STEEL_DK, M.Metal, a)
    for k = 0, 1 do
        part({ Name = "BinBag", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.3, 1.5),
            Position = Vector3.new(dx1 + 1 + k * 1.3, 0.75, SZ0 - 1 - k * 0.6), Color = rgb(24, 24, 28), Material = M.Rubber }, a)
    end
    -- used-oil drum
    part({ Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 1.6, 1.6),
        CFrame = CFrame.new(51.8, 1.4, SZ0 - 1.1) * CFrame.Angles(0, 0, math.rad(90)),
        Color = rgb(200, 60, 40), Material = M.Metal }, a)
    -- propane exchange cage against the back of the store
    local px0, px1 = 60.4, 64.2
    box("PropaneCage", px0, 0.1, Z1 + 0.1, px1, 4.2, Z1 + 1.9, rgb(200, 206, 214), M.DiamondPlate, a,
        { Transparency = 0.35 })
    box("PropaneCageTop", px0 - 0.05, 4.2, Z1 + 0.05, px1 + 0.05, 4.35, Z1 + 1.95, rgb(40, 90, 170), M.Metal, a)
    for k = 0, 2 do
        part({ Name = "PropaneTank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.7, 1.1, 1.1),
            CFrame = CFrame.new(px0 + 0.8 + k * 1.1, 1.0, Z1 + 1) * CFrame.Angles(0, 0, math.rad(90)),
            Color = rgb(236, 236, 230), Material = M.Metal, CanCollide = false }, a)
    end
    local ps = box("PropaneSign", px0 + 0.6, 2.8, Z1 + 1.92, px1 - 0.6, 3.8, Z1 + 1.96, rgb(40, 90, 170), M.Metal, a, nc())
    lit(printOn(ps, Enum.NormalId.Back, "PROPANE", rgb(255, 255, 255), UITheme.F.display, 40, 1).Parent)
    -- milk crates by the east wall (north of the bank's z 29.2..30 gap wall, which
    -- stands inside this yard) + a shrink-wrapped soda pallet in the nook behind it
    box("MilkCrate", EX0 - 1.8, 0.1, 26.9, EX0 - 0.2, 1.5, 28.5, rgb(220, 60, 60), M.Rubber, a)
    box("MilkCrate", EX0 - 1.8, 1.5, 26.9, EX0 - 0.2, 2.9, 28.5, rgb(60, 120, 220), M.Rubber, a)
    box("MilkCrate", EX0 - 3.8, 0.1, 27.1, EX0 - 2.2, 1.5, 28.7, rgb(220, 60, 60), M.Rubber, a)
    local sx0, sx1 = EX0 - 3.4, EX0 - 0.3
    box("Pallet", sx0, 0.1, 30.3, sx1, 0.55, SZ0 - 0.3, rgb(170, 130, 80), M.WoodPlanks, a)
    box("PalletLoad", sx0 + 0.1, 0.55, 30.4, sx1 - 0.1, 2.9, SZ0 - 0.4, rgb(230, 57, 70), M.Cardboard, a)
    box("ShrinkWrap", sx0 + 0.05, 0.55, 30.35, sx1 - 0.05, 2.95, SZ0 - 0.35, rgb(230, 240, 250), M.Glass, a,
        nc({ Transparency = 0.7 }))
    -- flattened boxes leaning on the east wall
    part({ Name = "FlatBoxes", Size = Vector3.new(0.3, 3.4, 2.6),
        CFrame = CFrame.new(EX0 - 0.5, 1.8, 21.5) * CFrame.Angles(0, 0, math.rad(10)),
        Color = rgb(186, 150, 104), Material = M.Cardboard, CanCollide = false }, a)
    -- puddles: flat, reflective, catch the lamps (no collision)
    for _, pd in ipairs({ { 80.6, 20.5, 2.6, 3.4 }, { 76.2, 2.8, 2.2, 1.6 }, { 66, 30, 3.6, 1.8 } }) do
        box("Puddle", pd[1] - pd[3] / 2, 0.1, pd[2] - pd[4] / 2, pd[1] + pd[3] / 2, 0.13, pd[2] + pd[4] / 2,
            rgb(22, 24, 34), M.Glass, a, nc({ Reflectance = 0.45, Transparency = 0.15, CastShadow = false }))
    end
    -- painted sun on the back wall of the yard (it takes the lamp light)
    local mural = box("YardMural", 60, 2, SZ0 - 0.06, 68, 9, SZ0, BRICK, M.Brick, a, nc({ Transparency = 1 }))
    local mg = lit(surface(mural, Enum.NormalId.Front, 16, 1))
    local sun = frame({ Size = UDim2.fromScale(0.34, 0.5), Position = UDim2.fromScale(0.33, 0.08), BackgroundColor3 = SUN }, mg)
    UITheme.corner(sun, 999)
    text({ Text = "SUNNY SIDE UP", Size = UDim2.fromScale(0.96, 0.26), Position = UDim2.fromScale(0.02, 0.66),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(255, 120, 150) }, mg)

    -- ── roof ladder: a climbable steel truss on the store's back wall ──
    local truss = Instance.new("TrussPart")
    truss.Name = "RoofLadder"
    truss.Anchored = true
    truss.Size = Vector3.new(2, 18, 2)
    truss.CFrame = CFrame.new(LADDER_X, 9, Z1 + 1.15)
    truss.Color = STEEL_LT
    truss.Material = M.Metal
    truss.Parent = a
    local sign = box("RoofSign", LADDER_X + 1.4, 2.4, Z1 + 0.1, LADDER_X + 2.8, 3.6, Z1 + 0.2, rgb(250, 204, 21), M.Metal, a, nc())
    lit(printOn(sign, Enum.NormalId.Back, "ROOF", rgb(30, 30, 30), UITheme.F.display, 50, 1).Parent)

    -- a dark corner past the back door (sneak here from the gate)
    table.insert(refs.shadowZones, shadowZone("ShadowYard", EX0 - 4.5, 17.5, EX0, 26, a))
end

function MartBuilder:_roof(f)
    local r = Instance.new("Folder")
    r.Name = "RoofAccess"
    r.Parent = f
    local hx, hz = 53.6, 19.8
    box("HatchPaint", hx - 2.4, ROOF_Y, hz - 2.4, hx + 2.4, ROOF_Y + 0.03, hz + 2.4, rgb(230, 190, 40), M.Concrete, r, nc())
    box("HatchCurb", hx - 1.7, ROOF_Y, hz - 1.7, hx + 1.7, ROOF_Y + 0.6, hz + 1.7, STEEL, M.Metal, r)
    local lid = facingPart("SM_RoofHatch", Vector3.new(hx, ROOF_Y + 0.75, hz), Vector3.new(2.9, 0.3, 2.9),
        Vector3.new(1, 0, 0), rgb(250, 204, 21), M.DiamondPlate, r)
    bar("HatchHandle", Vector3.new(hx + 0.7, ROOF_Y + 1.0, hz - 0.7), Vector3.new(hx + 0.7, ROOF_Y + 1.0, hz + 0.7), 0.14,
        STEEL_DK, M.Metal, r, nc())
    return lid
end

-- ──────────────────────────────────────────────
-- 📹 CAMERA (same build as JewelryBuilder)
-- ──────────────────────────────────────────────
function MartBuilder:_camera(f, name, mount, out, target, yawRange, period)
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
function MartBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "SunnysMart"
    f.Parent = folder

    local refs = {
        id = "mart",
        root = f,
        entryPoint = Vector3.new(CX, 3, -2),
        -- the crew drops in INSIDE the stock room, just past the alley door.
        -- No guard route and no camera covers it (the strip curtain blocks the view).
        sneakIn = { at = Vector3.new(69, 3.5, 19.8), face = Vector3.new(62, 3.5, 19.8),
            spread = Vector3.new(0, 0, 0.45) },
        entrances = {
            { kind = "front", at = Vector3.new(CX, 3, -2.5), label = "Front door" },
            { kind = "side", at = Vector3.new(X1 + 3, 3, (SIDE_DOOR_Z0 + SIDE_DOOR_Z1) / 2), label = "Back door (yard)" },
            { kind = "roof", at = Vector3.new(LADDER_X, 3, Z1 + 3.4), label = "Roof ladder" },
        },
        hideSpots = {},
        shadowZones = {},
        vents = {},
        -- cruisers park WEST of the yard gate (the car drives east to the marina)
        policeStop = Vector3.new(28, 0, -14),
        -- (v2.0.2) parked INSIDE the walled service yard, nose at the roll-up gate
        -- (x 74..82.5, z 1). Straight run north: gate → driveway → Ocean Drive.
        getawayCFrame = CFrame.lookAt(Vector3.new(CAR_X, 0, CAR_Z), Vector3.new(CAR_X, 0, CAR_Z - 10)),
        -- the warm-up has none of these (V2_SPEC §4)
        keycardDoors = {},
        keycardSpots = {},
        laserRows = {},
        smashCases = {},
    }
    local loot = {}

    self:_shell(f)
    refs.openSign = self:_facade(f)
    self:_salesFloor(f, refs, loot)
    refs.breaker = self:_stockRoom(f, refs, loot)
    local hatchInside = self:_office(f, refs, loot)
    self:_yard(f, refs)
    local hatchRoof = self:_roof(f)
    refs.lootSpots = loot

    -- Exit = the floor spot VentService stands you on when you come out of THIS end
    tag(hatchRoof, "Vent", { Pair = hatchInside.Name, Label = "Climb down",
        Exit = Vector3.new(56.6, ROOF_Y, 19.8) })
    tag(hatchInside, "Vent", { Pair = hatchRoof.Name, Label = "Climb to the roof",
        Exit = Vector3.new(55.6, FLOOR, 19.6) })
    refs.vents = { { a = hatchRoof, b = hatchInside } }

    local cams = Instance.new("Folder")
    cams.Name = "Cameras"
    cams.Parent = f
    -- high on the back wall, looking at the registers and the front door.
    -- The strip-curtain doorway to its east is behind it (blind spot).
    local cam = self:_camera(cams, "Camera_Register", Vector3.new(61.5, 12, SALES_Z1), Vector3.new(0, 0, -1),
        Vector3.new(57, FLOOR, 6), 70, 8)
    refs.cameras = { cam }
    local sticker = box("CameraSticker", 60.3, 9.6, SALES_Z1 - 0.06, 62.7, 10.6, SALES_Z1, rgb(250, 204, 21), M.Metal, cams, nc())
    printOn(sticker, Enum.NormalId.Front, "SMILE! YOU'RE ON CAMERA", rgb(30, 30, 30), UITheme.F.bold, 50, 1)

    -- one security guard walking the front of the store (>= 2 studs clear of the
    -- counter, the fridges and the shelves). Never goes near the stock room.
    refs.guardRoutes = {
        { name = "Guard_Sunny", spawn = Vector3.new(69, 3.5, GUARD_Z),
            a = Vector3.new(58.8, 3.5, GUARD_Z), b = Vector3.new(69, 3.5, GUARD_Z) },
    }

    refs.plan = {
        bounds = { X0, Z0, X1, Z1 },
        rooms = {
            { X0, Z0, X1, SALES_Z1, "STORE" },
            { IX0, BACK_Z0, OFFICE_X1, IZ1, "OFFICE" },
            { STOCK_X0, BACK_Z0, IX1, IZ1, "STOCK" },
        },
        vault = { SAFE_X, (SAFE_Z0 + SAFE_Z1) / 2 },
        entry = { CX, Z0 },
    }

    print("[MartBuilder] Sunny's Mart built ☀️")
    return refs
end

return MartBuilder
