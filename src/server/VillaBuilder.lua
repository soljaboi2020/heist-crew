--[[
    HEIST CREW — VillaBuilder
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Job: VILLA ROSA — a beachfront art-deco
    mansion at night. Rebuilt from the v1 villa after Malachi's playtest
    ("cramped", "isn't playable", "needs to be bigger").

    GEOMETRY + PROPS + REFS ONLY. No Scripts, no ProximityPrompts, no gameplay
    logic — the services add all of that from the JobRefs this returns
    (docs/V1_SPEC.md §4 + docs/V2_SPEC.md §4).

    LAYOUT (world studs, +Z = south / street, -Z = north / beach, floor top y 0.5)
        footprint x -42..42, z -96..-38. Walls 1 thick CENTRED on the grid lines,
        up to y 16.5 (16-stud ceilings), flat roof slab y 16.5..17.5.
        Doorways 7-8 wide x 10 tall. Every room is lit by lamps, not by the floor.

        z -96 ┌──────────────┬──────────────────────────┬────────┬───────────┐ (beach)
              │ BEDROOM      │ VAULT  x -18..18         │LAUNDRY │ STAFF ROOM│
              │ x -42..-18   │ z -96..-82 (round door)  │x 18..28│ x 28..42  │◄ SIDE DOOR
              │ z -96..-70   ├───────┬────────┬─────────┤        │  sneakIn  │  (east wall
              │         door │CLOSET │ LASERS │SECURITY ├──door──┴──door─────┤   z -92..-85)
              │  (roof hatch►│-18..-6│ -6..6  │ 6..18   │ SERVICE HALL      │
        z -70 ├────door──────┴───────┴─GLASS──┴─────────┴──x 18..42────door─┤
              │           GALLERY CORRIDOR  x -42..42, z -70..-58 (12 wide)  │
        z -58 ├────door──────┬────────── arch ─────────┬──────door──────────┤
              │ OFFICE       │ GRAND HALL x -14..14    │ KITCHEN x 14..42   │
              │ x -42..-14   ◄─door─ z -58..-38 ─door──►                    │
        z -38 └──────────────┴────── FRONT DOOR x -5..5 ┴───────────────────┘ (street)
        front garden z -38..-26.6 · back terrace + pool z -102..-96

    THE THREE WAYS IN (refs.entrances)
        front  — the obvious one. Camera_Hall watches it, Guard A walks the hall.
        side   — STAFF ONLY door on the east wall → staff room (= sneakIn). No
                 guard route and no camera covers the staff room or the door.
        roof   — steel ladder (a climbable TrussPart) on the WEST wall at z -84 →
                 roof hatch. The hatch is a Vent pair: roof lid `Vent_RoofHatch` ↔
                 `Vent_ClosetLadder` in the bedroom's walk-in closet.

    LOOPS: office → hall → kitchen → corridor → office, and each wing room has
    two ways out, so a guard can be circled. Guard routes are straight lines kept
    ≥ 2 studs from props (checked with a mock-Roblox harness, see the report):
        Guard_A  hall       z -47, x -9 ↔ 9
        Guard_B  corridor   z -64, x -20 ↔ 28
        Guard_C  west wing  x -28, z -44 (office) ↔ -86 (bedroom), through both doors

    TAG CONVENTIONS (for FeelService / HideService — see V2_SPEC §2)
        HideSpot  attrs Label (string), Inside (Vector3 = free space to park a
                  hidden player). Part LookVector points OUT of the hiding place.
        Vent      attrs Pair (other end's Name), Label, Exit (Vector3 = where a
                  player arriving at THIS end should stand). LookVector = out.
        ShadowZone invisible, CanCollide/CanQuery/CanTouch = false.

    PUBLIC API
        VillaBuilder:build(folder) -> JobRefs (id = "villa") — see the return table.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local VillaBuilder = {}

local FLOOR = 0.5          -- top of every floor in the villa
local TOP = 16.5           -- top of the walls / underside of the roof slab
local DOOR_TOP = 10.5      -- top of every doorway (10 tall)
local ROOF = TOP + 1       -- walkable roof top

local M = Enum.Material

-- ── palette ─────────────────────────────────────────────────────────────
local STUCCO     = UITheme.rgb(Constants.MIAMI.STUCCO)
local PINK       = Color3.fromRGB(240, 188, 200)
local TEAL       = Color3.fromRGB(58, 170, 164)
local TEAL_DARK  = Color3.fromRGB(34, 110, 110)
local HOT_PINK   = UITheme.rgb(Constants.MIAMI.NEONS[1])
local CYAN       = UITheme.rgb(Constants.MIAMI.NEONS[2])
local INTERIOR   = Color3.fromRGB(204, 188, 178)
local TRIM       = Color3.fromRGB(236, 226, 210)
local PLINTH     = Color3.fromRGB(150, 142, 136)
local STEEL      = Color3.fromRGB(52, 56, 64)
local STEEL_LITE = Color3.fromRGB(150, 156, 166)
local VSTEEL     = Color3.fromRGB(96, 100, 108)
local BRASS      = Color3.fromRGB(196, 160, 90)
local GOLD       = Color3.fromRGB(236, 184, 60)
local WARM       = Color3.fromRGB(255, 206, 150)
local COOL       = Color3.fromRGB(215, 226, 255)
local MARBLE     = Color3.fromRGB(232, 226, 216)
local MARBLE_DK  = Color3.fromRGB(62, 58, 66)
local WOOD_DARK  = Color3.fromRGB(84, 52, 36)
local WOOD_MID   = Color3.fromRGB(128, 88, 58)
local CARPET     = UITheme.rgb(Constants.COLORS.CARPET_RED)
local LASER_RED  = Color3.fromRGB(255, 40, 50)
local SIGN_RED   = Color3.fromRGB(255, 60, 70)
local LEAF       = Color3.fromRGB(56, 118, 66)
local HATCH      = Color3.fromRGB(232, 170, 40)     -- "you can use this" amber (FE2 colour rule)
local NIGHT_GLASS = Color3.fromRGB(70, 96, 130)

-- ──────────────────────────────────────────────
-- helpers
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

-- a full-surface text sign: one centred line
local function signText(p, face, str, color, pps, lightInfluence)
    local g = surface(p, face, pps or 50, lightInfluence or 0, 1.3)
    text({ Text = str, Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = color }, g)
    return g
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

-- a ceiling lamp: short rod + shade + bulb at (x, z), hanging from the ceiling
local function ceilingLamp(parent, x, z, color, brightness, range, shadows, low)
    local y = low or (TOP - 1.4)
    vcyl("LampRod", x, y + 0.5, TOP, z, 0.12, STEEL, M.Metal, parent, DECOR)
    vcyl("LampShade", x, y, y + 0.5, z, 1.6, BRASS, M.Metal, parent, DECOR)
    local b = ball("LampBulb", Vector3.new(x, y - 0.1, z), 0.4, color, M.Neon, parent, NOSHADOW)
    pointLight(b, color, brightness, range, shadows)
    return b
end

local function sub(parent, name)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function prop(list, name, x, y, z, facing, scale, kit)
    table.insert(list, {
        kit = kit or "furniture", name = name, pos = Vector3.new(x, y, z),
        facing = facing, opts = scale and { scale = scale } or nil,
    })
end

local PX, NX, PZ, NZ = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)

-- ── walls ───────────────────────────────────────────────────────────────
-- abox: a box along a wall line. axis "x" = the wall runs along X at z = c;
-- axis "z" = it runs along Z at x = c. a0..a1 along the wall, thick across it.
local function abox(name, axis, c, a0, y0, a1, y1, thick, color, mat, parent, extra)
    local h = thick / 2
    if axis == "x" then
        return box(name, a0, y0, c - h, a1, y1, c + h, color, mat, parent, extra)
    end
    return box(name, c - h, y0, a0, c + h, y1, a1, color, mat, parent, extra)
end

-- A 1-thick wall from `from` to `to` with openings cut in it.
-- ops = { {a0, a1, y0, y1, kind} } kind = "door" (casing) | "arch" | "window" | "open" (bare hole)
local function wallRun(parent, name, axis, c, from, to, ops, color, mat, opts)
    opts = opts or {}
    local yb, yt = FLOOR, opts.top or TOP
    local list = {}
    for _, o in ipairs(ops or {}) do table.insert(list, o) end
    table.sort(list, function(p, q) return p[1] < q[1] end)
    local function seg(a0, a1, y0, y1, nm)
        if a1 - a0 > 0.01 and y1 - y0 > 0.01 then
            abox(nm or name, axis, c, a0, y0, a1, y1, 1, color, mat, parent)
        end
    end
    local cur = from
    for _, o in ipairs(list) do
        local a0, a1 = o[1], o[2]
        local y0, y1, kind = o[3] or yb, o[4] or DOOR_TOP, o[5] or "door"
        seg(cur, a0, yb, yt)
        seg(a0, a1, yb, y0, name .. "Below")
        seg(a0, a1, y1, yt, name .. "Header")
        if kind == "window" then
            abox("WindowGlass", axis, c, a0, y0, a1, y1, 0.2, opts.glass or NIGHT_GLASS, M.Glass, parent,
                { Transparency = 0.45, Reflectance = 0.2, CastShadow = false })
            local mid = (a0 + a1) / 2
            local fr = opts.frame or TEAL_DARK
            abox("WindowMullion", axis, c, mid - 0.12, y0, mid + 0.12, y1, 1.15, fr, M.Metal, parent)
            local ty = y0 + (y1 - y0) * 0.72
            abox("WindowTransom", axis, c, a0, ty - 0.1, a1, ty + 0.1, 1.15, fr, M.Metal, parent)
            abox("WindowSill", axis, c, a0 - 0.3, y0 - 0.25, a1 + 0.3, y0, 1.6, opts.sill or PLINTH, M.Plaster, parent)
        elseif kind == "door" or kind == "arch" then
            local trim = opts.trim or TRIM
            abox("Casing", axis, c, a0 - 0.35, FLOOR, a0, y1 + 0.35, 1.2, trim, M.Wood, parent)
            abox("Casing", axis, c, a1, FLOOR, a1 + 0.35, y1 + 0.35, 1.2, trim, M.Wood, parent)
            abox("Casing", axis, c, a0 - 0.35, y1, a1 + 0.35, y1 + 0.35, 1.2, trim, M.Wood, parent)
        end
        cur = a1
    end
    seg(cur, to, yb, yt)
end

-- crown moulding + skirting around a room's interior (x0..x1, z0..z1 = interior faces).
-- The crown sits above every doorway so it can run the full perimeter.
local function crown(parent, x0, z0, x1, z1, color)
    color = color or TRIM
    local y0, y1 = TOP - 0.7, TOP
    box("Crown", x0, y0, z0, x1, y1, z0 + 0.3, color, M.Plaster, parent, NOSHADOW)
    box("Crown", x0, y0, z1 - 0.3, x1, y1, z1, color, M.Plaster, parent, NOSHADOW)
    box("Crown", x0, y0, z0, x0 + 0.3, y1, z1, color, M.Plaster, parent, NOSHADOW)
    box("Crown", x1 - 0.3, y0, z0, x1, y1, z1, color, M.Plaster, parent, NOSHADOW)
end

-- ── tagged gameplay parts ───────────────────────────────────────────────
local function shadowZone(parent, list, name, x0, z0, x1, z1)
    local p = box(name, x0, FLOOR, z0, x1, FLOOR + 8.5, z1, Color3.new(0, 0, 0), M.SmoothPlastic, parent,
        { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
    CollectionService:AddTag(p, "ShadowZone")
    table.insert(list, p)
    return p
end

local function tagHide(p, list, label, inside)
    CollectionService:AddTag(p, "HideSpot")
    p:SetAttribute("Label", label)
    p:SetAttribute("Inside", inside)
    table.insert(list, p)
    return p
end

local function tagVent(p, pairName, label, exit)
    CollectionService:AddTag(p, "Vent")
    p:SetAttribute("Pair", pairName)
    p:SetAttribute("Label", label)
    p:SetAttribute("Exit", exit)
    return p
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

-- picture light above a painting (a small brass bar with a soft downward spot)
local function pictureLight(parent, pos, normal, w)
    local cf = CFrame.lookAt(pos, pos + normal)
    local bar = cpart("PictureLight", Vector3.new(w, 0.2, 0.4), cf * CFrame.new(0, 0, -0.2), BRASS, M.Metal, parent, DECOR)
    spotLight(bar, Enum.NormalId.Bottom, WARM, 0.8, 8, 90, false)
    return bar
end

-- curtains either side of a window (interior side). a0..a1 along the wall, face = interior plane
local function curtains(parent, axis, face, a0, a1, color)
    local y0, y1 = FLOOR + 1.2, 12.2
    for _, a in ipairs({ a0 - 0.9, a1 + 0.1 }) do
        abox("Curtain", axis, face, a, y0, a + 0.8, y1, 0.3, color, M.Fabric, parent, DECOR)
    end
    abox("CurtainRod", axis, face, a0 - 1.2, y1, a1 + 1.2, y1 + 0.15, 0.2, BRASS, M.Metal, parent, DECOR)
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: floors, walls, roof, ceilings
-- ──────────────────────────────────────────────
local ROOMS = {   -- wall-centre rectangles: x0, z0, x1, z1, floor colour, floor material, name
    { -14, -58, 14, -38, MARBLE, M.Marble, "Hall" },
    { -42, -58, -14, -38, Color3.fromRGB(92, 62, 44), M.WoodPlanks, "Office" },
    { 14, -58, 42, -38, Color3.fromRGB(214, 212, 204), M.CeramicTiles, "Kitchen" },
    { -42, -70, 42, -58, MARBLE_DK, M.Marble, "Corridor" },
    { -42, -96, -18, -70, Color3.fromRGB(104, 66, 80), M.Fabric, "Bedroom" },
    { -18, -82, -6, -70, Color3.fromRGB(150, 112, 80), M.WoodPlanks, "Closet" },
    { -6, -82, 6, -70, Color3.fromRGB(80, 84, 92), M.DiamondPlate, "Lasers" },
    { 6, -82, 18, -70, Color3.fromRGB(48, 50, 56), M.Slate, "Security" },
    { 18, -80, 42, -70, Color3.fromRGB(128, 126, 120), M.Concrete, "Service" },
    { 18, -96, 28, -80, Color3.fromRGB(200, 214, 220), M.CeramicTiles, "Laundry" },
    { 28, -96, 42, -80, Color3.fromRGB(96, 104, 100), M.Slate, "Staff" },
    { -18, -96, 18, -82, Color3.fromRGB(80, 84, 92), M.DiamondPlate, "Vault" },
}

function VillaBuilder:_shell(f)
    box("BaseSlab", -42.5, -0.5, -96.5, 42.5, 0.3, -37.5, Color3.fromRGB(110, 106, 102), M.Concrete, f)
    for _, r in ipairs(ROOMS) do
        box(r[7] .. "Floor", r[1], 0.3, r[2], r[3], FLOOR, r[4], r[5], r[6], f)
    end
    -- red runner from the front door to the corridor arch
    box("CarpetRunner", -2, FLOOR, -57.5, 2, FLOOR + 0.05, -38.5, CARPET, M.Fabric, f, NOSHADOW)
    box("CorridorRunner", -30, FLOOR, -65.2, 30, FLOOR + 0.05, -62.8, CARPET, M.Fabric, f, NOSHADOW)

    -- ── exterior walls (stucco) with REAL window openings ──
    local win = function(a0, a1, y0, y1) return { a0, a1, y0 or 3.5, y1 or 11, "window" } end
    wallRun(f, "WallSouth", "x", -38, -42.5, 42.5, {
        { -5, 5, FLOOR, DOOR_TOP, "open" },                          -- front door
        win(-38, -34), win(-24, -20),                                -- office
        win(-12.8, -9.4), win(9.4, 12.8),                            -- hall
        win(20, 24), win(34, 38),                                    -- kitchen
    }, STUCCO, M.Plaster)
    wallRun(f, "WallNorth", "x", -96, -42.5, 42.5, {
        win(-38.5, -33.5, 3.5, 12), win(-26.5, -21.5, 3.5, 12),      -- bedroom (sea view)
        win(21.5, 24.5, 7, 11),                                      -- laundry (small, high)
    }, STUCCO, M.Plaster)
    wallRun(f, "WallWest", "z", -42, -96.5, -37.5, {
        win(-94, -90), win(-76, -72),                                -- bedroom
        win(-50, -46),                                               -- office
    }, STUCCO, M.Plaster)
    wallRun(f, "WallEast", "z", 42, -96.5, -37.5, {
        { -92, -85, FLOOR, DOOR_TOP, "open" },                       -- STAFF ONLY service door
        win(-77, -73, 4, 10),                                        -- service hall
        win(-47, -43, 4.5, 10.5),                                    -- kitchen (above the counters)
    }, STUCCO, M.Plaster)

    -- ── interior walls ──
    local P = M.Plaster
    wallRun(f, "HallWallW", "z", -14, -58, -38, { { -52, -44 } }, INTERIOR, P)
    wallRun(f, "HallWallE", "z", 14, -58, -38, { { -52, -44 } }, INTERIOR, P)
    wallRun(f, "CorridorWallS", "x", -58, -42, 42, {
        { -32, -24 }, { -6, 6, FLOOR, 12.5, "arch" }, { 24, 32 },
    }, INTERIOR, P)
    wallRun(f, "CorridorWallN", "x", -70, -42, 42, {
        { -32, -24 }, { -4, 4, FLOOR, DOOR_TOP, "open" }, { 30, 38 },
    }, INTERIOR, P)
    wallRun(f, "BedroomWallE", "z", -18, -96, -70, { { -79, -72 } }, INTERIOR, P)
    wallRun(f, "LaserWallW", "z", -6, -82, -70, {}, INTERIOR, P)
    wallRun(f, "LaserWallE", "z", 6, -82, -70, { { -79, -73, 3.5, 8.5, "window" } }, INTERIOR, P,
        { glass = Color3.fromRGB(150, 180, 190), frame = STEEL })
    wallRun(f, "VaultWallClosetSide", "x", -82, -18, -6, {}, INTERIOR, P)
    wallRun(f, "VaultWallSecuritySide", "x", -82, 6, 18, {}, INTERIOR, P)
    wallRun(f, "ServiceWallW", "z", 18, -96, -70, { { -78.5, -71.5 } }, INTERIOR, P)
    wallRun(f, "ServiceWallN", "x", -80, 18, 42, { { 20, 27 }, { 32, 40 } }, INTERIOR, P)
    wallRun(f, "LaundryWallE", "z", 28, -96, -80, { { -94, -87 } }, INTERIOR, P)

    -- crown moulding in the finished rooms
    crown(f, -13.5, -57.5, 13.5, -38.5, GOLD)
    crown(f, -41.5, -57.5, -14.5, -38.5)
    crown(f, 14.5, -57.5, 41.5, -38.5)
    crown(f, -41.5, -69.5, 41.5, -58.5)
    crown(f, -41.5, -95.5, -18.5, -70.5)

    -- hall ceiling: coffers (dark wood beams) so the big room reads as grand
    for _, x in ipairs({ -7, 0, 7 }) do
        box("CofferBeam", x - 0.4, TOP - 0.9, -57.5, x + 0.4, TOP, -38.5, WOOD_DARK, M.Wood, f, NOSHADOW)
    end
    for _, z in ipairs({ -52, -44 }) do
        box("CofferBeam", -13.5, TOP - 0.9, z - 0.4, 13.5, TOP, z + 0.4, WOOD_DARK, M.Wood, f, NOSHADOW)
    end

    -- ── roof ──
    box("Roof", -43, TOP, -97, 43, ROOF, -37, Color3.fromRGB(190, 182, 174), M.Concrete, f)
end

-- ──────────────────────────────────────────────
-- 🌴 FACADE: deco details, tower, sign, canopy, parapets
-- ──────────────────────────────────────────────
function VillaBuilder:_facade(f, refs)
    local XW, XE, ZS, ZN = -42.5, 42.5, -37.5, -96.5   -- outer faces
    -- plinth band around the base
    box("PlinthS", XW - 0.1, 0, ZS, -5, 1, ZS + 0.2, PLINTH, M.Concrete, f)
    box("PlinthS", 5, 0, ZS, XE + 0.1, 1, ZS + 0.2, PLINTH, M.Concrete, f)
    box("PlinthN", XW - 0.2, 0, ZN - 0.2, XE + 0.2, 1, ZN, PLINTH, M.Concrete, f)
    box("PlinthW", XW - 0.2, 0, ZN, XW, 1, ZS, PLINTH, M.Concrete, f)
    box("PlinthE", XE, 0, ZN, XE + 0.2, 1, -92, PLINTH, M.Concrete, f)
    box("PlinthE", XE, 0, -85, XE + 0.2, 1, ZS, PLINTH, M.Concrete, f)

    -- teal speed lines, three bands wrapping the building
    for i, y in ipairs({ 14.0, 14.7, 15.4 }) do
        local y1 = y + 0.35
        box("SpeedLineS" .. i, XW - 0.1, y, ZS, XE + 0.1, y1, ZS + 0.2, TEAL, M.Plaster, f)
        box("SpeedLineN" .. i, XW - 0.2, y, ZN - 0.2, XE + 0.2, y1, ZN, TEAL, M.Plaster, f)
        box("SpeedLineW" .. i, XW - 0.2, y, ZN, XW, y1, ZS, TEAL, M.Plaster, f)
        box("SpeedLineE" .. i, XE, y, ZN, XE + 0.2, y1, ZS, TEAL, M.Plaster, f)
    end

    -- rounded corner towers at the two front corners
    for _, sx in ipairs({ -1, 1 }) do
        local cx, cz = sx * 42.5, -37.5
        vcyl("CornerTower", cx, 0, 19.5, cz, 6, PINK, M.Plaster, f)
        for i, y in ipairs({ 14.0, 14.7, 15.4 }) do
            vcyl("CornerBand" .. i, cx, y, y + 0.35, cz, 6.3, TEAL, M.Plaster, f)
        end
        vcyl("CornerNeonRing", cx, 19.3, 19.42, cz, 6.25, HOT_PINK, M.Neon, f, NOSHADOW)
        vcyl("CornerCap", cx, 19.5, 19.9, cz, 6.6, TEAL, M.Plaster, f)
        vcyl("CornerFinial", cx, 19.9, 21.2, cz, 0.5, STEEL_LITE, M.Metal, f, DECOR)
        local d = Vector3.new(sx, 0, 1).Unit
        for k = 0, 5 do
            local p = Vector3.new(cx, 3.2 + k * 1.5, cz) + d * 2.95
            cpart("GlassBlock", Vector3.new(1.1, 1.1, 0.4), CFrame.lookAt(p, p + d),
                Color3.fromRGB(190, 230, 235), M.Glass, f, { Transparency = 0.15, Reflectance = 0.1 })
        end
    end
    -- rear corners: pink pilasters so the back isn't a flat box
    for _, sx in ipairs({ -1, 1 }) do
        box("RearPilaster", sx * 42.5 - 1, 0, -97, sx * 42.5 + 1, 18.6, -95.8, PINK, M.Plaster, f)
    end
    -- glass-block strips on the blank vault wall facing the pool
    for _, x in ipairs({ -12, -4, 4, 12 }) do
        for k = 0, 6 do
            box("VaultGlassBlock", x - 0.55, 2.5 + k * 1.4, ZN - 0.25, x + 0.55, 3.6 + k * 1.4, ZN,
                Color3.fromRGB(190, 230, 235), M.Glass, f, { Transparency = 0.2, Reflectance = 0.1 })
        end
    end
    -- portholes above the front windows
    for _, x in ipairs({ -36, -22, 22, 36 }) do
        local p = Vector3.new(x, 13, ZS)
        disc("PortholeRim", p + Vector3.new(0, 0, 0.1), PZ, 0.2, 2, TEAL_DARK, M.Metal, f)
        disc("PortholeGlass", p + Vector3.new(0, 0, 0.22), PZ, 0.1, 1.6,
            Color3.fromRGB(250, 205, 150), M.Glass, f, { Transparency = 0.25, CanCollide = false })
    end

    -- ── entrance: landing, jambs, deco fins, open double doors, canopy ──
    box("EntryLanding", -4.8, 0, ZS, 4.8, FLOOR, -35.3, MARBLE, M.Marble, f)
    box("EntryInlay", -4.8, FLOOR, -35.55, 4.8, FLOOR + 0.02, -35.35, TEAL, M.Marble, f, NOSHADOW)
    for _, sx in ipairs({ -1, 1 }) do
        box("DoorJamb", sx * 5, FLOOR, ZS, sx * 5.3, DOOR_TOP + 0.3, ZS + 0.3, STEEL_LITE, M.Metal, f)
        box("DecoFin", sx * 5.3, 2, ZS, sx * 5.8, 18.5, ZS + 1.3, PINK, M.Plaster, f)
        box("DecoFin", sx * 6.6, 2, ZS, sx * 7.1, 17.5, ZS + 1.3, PINK, M.Plaster, f)
        -- the front doors stand open, folded back against the inside wall
        box("FrontDoorLeaf", sx * 5.05, FLOOR, -38.9, sx * 9.3, DOOR_TOP - 0.1, -38.55, WOOD_DARK, M.Wood, f)
        box("FrontDoorGlass", sx * 5.8, 4, -38.95, sx * 8.6, 9.4, -38.9,
            Color3.fromRGB(160, 200, 210), M.Glass, f, { Transparency = 0.4, CanCollide = false })
    end
    box("DoorHeadTrim", -5.3, DOOR_TOP, ZS, 5.3, DOOR_TOP + 0.3, ZS + 0.3, STEEL_LITE, M.Metal, f)

    box("Canopy", -7, 10.6, ZS, 7, 11.3, -32.6, STUCCO, M.Plaster, f)
    box("CanopyFascia", -7.05, 10.55, -32.6, 7.05, 11.35, -32.4, TEAL, M.Plaster, f)
    local strip = box("CanopyNeon", -6.5, 10.48, -33.2, 6.5, 10.6, -32.95, HOT_PINK, M.Neon, f, NOSHADOW)
    pointLight(strip, HOT_PINK, 0.9, 10, false)
    for _, sx in ipairs({ -1, 1 }) do
        local fix = box("CanopyDownlight", sx * 3 - 0.35, 10.45, -35.85, sx * 3 + 0.35, 10.6, -35.15, STEEL, M.Metal, f, DECOR)
        spotLight(fix, Enum.NormalId.Bottom, WARM, 1.2, 14, 90, true)
    end

    -- frontispiece above the canopy + the central tower rising above the roof
    box("Frontispiece", -4.5, 11.3, ZS, 4.5, TOP, ZS + 1, PINK, M.Plaster, f)
    box("Tower", -4.5, TOP, -41, 4.5, 31, -36.5, PINK, M.Plaster, f)
    box("TowerCrown1", -3.8, 31, -40.65, 3.8, 32, -36.85, PINK, M.Plaster, f)
    box("TowerCrown2", -2.8, 32, -40.15, 2.8, 33, -37.35, TEAL, M.Plaster, f)
    box("TowerCrown3", -1.8, 33, -39.65, 1.8, 34, -37.85, PINK, M.Plaster, f)
    vcyl("Spire", 0, 34, 39, -38.75, 0.4, STEEL_LITE, M.Metal, f)
    local tip = ball("SpireTip", Vector3.new(0, 39.3, -38.75), 0.7, HOT_PINK, M.Neon, f, NOSHADOW)
    pointLight(tip, HOT_PINK, 1, 8, false)
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
    box("SignTube", -1.85, 17.25, -36.45, -1.7, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", 1.7, 17.25, -36.45, 1.85, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", -1.85, 30.6, -36.45, 1.85, 30.75, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    box("SignTube", -1.85, 17.25, -36.45, 1.85, 17.4, -36.15, HOT_PINK, M.Neon, f, NOSHADOW)
    pointLight(sign, HOT_PINK, 3, 16, false)

    -- ── parapets + neon roofline (gap in the west parapet where the ladder arrives) ──
    box("ParapetS", XW, ROOF, -38.5, XE, 19, ZS, STUCCO, M.Plaster, f)
    box("ParapetN", XW, ROOF, ZN, XE, 18.6, -95.5, STUCCO, M.Plaster, f)
    box("ParapetW", XW, ROOF, -95.5, XW + 1, 18.6, -86, STUCCO, M.Plaster, f)
    box("ParapetW", XW, ROOF, -82, XW + 1, 18.6, -38.5, STUCCO, M.Plaster, f)
    box("ParapetE", XE - 1, ROOF, -95.5, XE, 18.6, -38.5, STUCCO, M.Plaster, f)
    for _, sx in ipairs({ -1, 1 }) do
        box("ParapetStep1", sx * 4.5, 19, -38.5, sx * 11, 19.9, ZS, STUCCO, M.Plaster, f)
        box("ParapetStep2", sx * 4.5, 19.9, -38.5, sx * 7.5, 20.8, ZS, PINK, M.Plaster, f)
    end
    box("RooflineNeonS", XW, 18.65, ZS, XE, 18.8, ZS + 0.15, CYAN, M.Neon, f, NOSHADOW)
    box("RooflineNeonN", XW, 18.2, ZN - 0.15, XE, 18.35, ZN, HOT_PINK, M.Neon, f, NOSHADOW)

    -- ── OPEN/CLOSED: small "PRIVATE" plaques either side of the door ──
    refs.plaques = {}
    for _, sx in ipairs({ -1, 1 }) do
        local x0, x1 = sx * 7.3, sx * 9.1
        local plaque = box("PrivatePlaque", x0, 6, ZS, x1, 7.2, ZS + 0.2, Color3.fromRGB(26, 20, 30), M.Metal, f)
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
        local tube = box("PrivateTube", x0 + sx * 0.15, 5.8, ZS + 0.05, x1 - sx * 0.15, 5.92, ZS + 0.17,
            Color3.fromRGB(60, 50, 56), M.Metal, f, NOSHADOW)
        local light = pointLight(tube, SIGN_RED, 1, 7, false)
        light.Enabled = false
        table.insert(refs.plaques, { label = label, stroke = stroke, tube = tube, light = light })
    end
end

-- ──────────────────────────────────────────────
-- 🌺 FRONT GARDEN (z -38..-26.6). SafehouseBuilder already lays the path
-- x -4..4 + hedges x ±5..6.4, MiamiBuilder plants palms at (±9, -30):
-- keep x -9.6..9.6 free of anything tall.
-- ──────────────────────────────────────────────
local function palm(parent, x, z, lean)
    local base = Vector3.new(x, 0, z)
    local height = 12
    local n = 6
    local function at(s) return base + Vector3.new(lean * s * s, height * s, 0) end
    for i = 1, n do
        local a, c = at((i - 1) / n), at(i / n)
        local mid = (a + c) / 2
        local len = (c - a).Magnitude + 0.2
        local dia = 1.0 - (i - 1) * 0.05
        cpart("PalmTrunk", Vector3.new(len, dia, dia), CFrame.lookAt(mid, c) * CFrame.Angles(0, math.rad(90), 0),
            Color3.fromRGB(122, 98, 72), M.Wood, parent, { Shape = Enum.PartType.Cylinder })
    end
    local top = at(1)
    ball("PalmCrown", top, 1.1, Color3.fromRGB(70, 110, 60), M.Grass, parent, DECOR)
    for k = 0, 6 do
        local az = math.rad(k * 360 / 7 + 10)
        cpart("PalmFrond", Vector3.new(1.1, 0.12, 5),
            CFrame.new(top) * CFrame.Angles(0, az, 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -2.4),
            LEAF, M.Grass, parent, DECOR)
    end
end

local function bollard(parent, x, z)
    vcyl("Bollard", x, 0, 2.4, z, 0.55, STEEL, M.Metal, parent)
    local lens = vcyl("BollardLens", x, 2.0, 2.3, z, 0.6, WARM, M.Neon, parent, NOSHADOW)
    vcyl("BollardCap", x, 2.4, 2.55, z, 0.7, STEEL, M.Metal, parent, DECOR)
    pointLight(lens, WARM, 1, 10, false)
end

function VillaBuilder:_garden(f)
    local rng = Random.new(1958)
    local flowerCols = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(250, 240, 240), Color3.fromRGB(220, 60, 140) }
    for _, sx in ipairs({ -1, 1 }) do
        box("Lawn", sx * 6.4, 0, -37.5, sx * 42.5, 0.12, -26.8, Color3.fromRGB(46, 102, 58), M.Grass, f)
        box("SidewalkHedge", sx * 10, 0, -27.8, sx * 42.5, 1.8, -26.8, Color3.fromRGB(40, 86, 48), M.Grass, f)
        box("Flowerbed", sx * 10.4, 0, -37.5, sx * 39, 0.6, -36, Color3.fromRGB(70, 48, 36), M.Ground, f)
        for k = 0, 12 do
            local x = sx * (11.2 + k * 2.2)
            local z = -36.75 + rng:NextNumber(-0.3, 0.3)
            if k % 3 == 1 then
                ball("Shrub", Vector3.new(x, 1.0, z), 1.4, LEAF, M.Grass, f, DECOR)
            else
                ball("Flowers", Vector3.new(x, 0.85, z), 0.8, flowerCols[(k % 3) + 1], M.Fabric, f, DECOR)
            end
        end
        palm(f, sx * 27, -31, sx * 1.4)
        bollard(f, sx * 7.4, -34.5)
        -- pink / cyan uplights washing the facade (tilted back toward the wall)
        for i, x in ipairs({ 29, 39 }) do   -- kept away from the office/kitchen dark corners (unshadowed light leaks through walls)
            local fixture = cpart("Uplight", Vector3.new(0.6, 0.3, 0.6),
                CFrame.new(sx * x, 0.3, -35.6) * CFrame.Angles(math.rad(-12), 0, 0), STEEL, M.Metal, f, DECOR)
            spotLight(fixture, Enum.NormalId.Top, i == 1 and HOT_PINK or CYAN, 3, 20, 50, false)
        end
    end
end

-- ──────────────────────────────────────────────
-- 🏖 BACK TERRACE (z -102..-96): pool, loungers, lamps
-- ──────────────────────────────────────────────
function VillaBuilder:_terrace(f)
    local STONE = Color3.fromRGB(226, 214, 192)
    box("TerraceDeck", -42.5, 0, -102, 42.5, FLOOR, -96.5, STONE, M.Limestone, f)

    local poolFloor = box("PoolFloor", -12, FLOOR, -101.2, 12, FLOOR + 0.02, -97.6, Color3.fromRGB(120, 215, 225), M.CeramicTiles, f)
    local pg = surface(poolFloor, Enum.NormalId.Top, 4, 0, 1)
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 220, 235), BackgroundTransparency = 0.25 }, pg)
    box("PoolCoping", -12.5, FLOOR, -97.6, 12.5, 1.2, -97.1, MARBLE, M.Marble, f)
    box("PoolCoping", -12.5, FLOOR, -101.7, 12.5, 1.2, -101.2, MARBLE, M.Marble, f)
    box("PoolCoping", -12.5, FLOOR, -101.2, -12, 1.2, -97.6, MARBLE, M.Marble, f)
    box("PoolCoping", 12, FLOOR, -101.2, 12.5, 1.2, -97.6, MARBLE, M.Marble, f)
    local water = box("PoolWater", -12, FLOOR + 0.02, -101.2, 12, 1.0, -97.6, Color3.fromRGB(60, 200, 214), M.Glass, f,
        { Transparency = 0.35, CanCollide = false, CastShadow = false })
    local sl = Instance.new("SurfaceLight")
    sl.Face = Enum.NormalId.Top
    sl.Color = Color3.fromRGB(90, 225, 235)
    sl.Brightness = 1.5
    sl.Range = 10
    sl.Angle = 90
    sl.Parent = water

    for _, sx in ipairs({ -1, 1 }) do
        for _, ax in ipairs({ 17, 23, 29 }) do
            local cx, z = sx * ax, -99.4
            box("LoungerFrame", cx - 2.5, 0.8, z - 0.9, cx + 2.5, 1.0, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            box("LoungerLeg", cx - 2.4, FLOOR, z - 0.9, cx - 2.1, 0.8, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            box("LoungerLeg", cx + 2.1, FLOOR, z - 0.9, cx + 2.4, 0.8, z + 0.9, Color3.fromRGB(236, 236, 232), M.Metal, f)
            local c0, c1 = cx - sx * 2.4, cx + sx * 1.0
            box("LoungerCushion", math.min(c0, c1), 1.0, z - 0.8, math.max(c0, c1), 1.25, z + 0.8, PINK, M.Fabric, f)
            cpart("LoungerBack", Vector3.new(2.0, 0.25, 1.6),
                CFrame.new(cx + sx * 1.75, 1.75, z) * CFrame.Angles(0, 0, sx * math.rad(35)), PINK, M.Fabric, f)
        end
        -- parasol between the loungers
        local px = sx * 20
        vcyl("ParasolPole", px, FLOOR, 7, -99.4, 0.2, WOOD_MID, M.Wood, f)
        cpart("ParasolTop", Vector3.new(0.6, 6, 6), CFrame.new(px, 7, -99.4) * CFrame.Angles(0, 0, math.rad(90)),
            Color3.fromRGB(245, 240, 230), M.Fabric, f, merge(DECOR, { Shape = Enum.PartType.Cylinder }))
        -- terrace lamp posts
        local lx, lz = sx * 36, -99.4
        vcyl("TerraceLampPost", lx, FLOOR, 5.5, lz, 0.35, STEEL, M.Metal, f)
        ball("TerraceLampGlobe", Vector3.new(lx, 5.9, lz), 0.8, Color3.fromRGB(255, 236, 210), M.Glass, f,
            { Transparency = 0.35, CanCollide = false })
        local bulb = ball("TerraceLampBulb", Vector3.new(lx, 5.9, lz), 0.35, WARM, M.Neon, f, NOSHADOW)
        pointLight(bulb, WARM, 1.2, 16, true)   -- shadows ON: an unshadowed lamp shines through the wall into the bedroom
    end
end

-- ── loot piles (visual = just the pile; pallets/plinths stay) ───────────
local function lootCF(stand, pile)
    return CFrame.lookAt(stand, Vector3.new(pile.X, stand.Y, pile.Z))
end

local CASH_A, CASH_B = Color3.fromRGB(86, 160, 96), Color3.fromRGB(104, 176, 110)

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
                        ((ix + iz + layer) % 2 == 0) and CASH_A or CASH_B, M.Fabric, m)
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

-- small cash stack on any surface (outer-room loot — grabbable without the vault)
local function cashStack(f, loot, pos, standPos, n)
    local m = Instance.new("Model")
    m.Name = "CashStack"
    for i = 0, n - 1 do
        local lx = (i % 2) * 1.1 - 0.55
        local ly = math.floor(i / 2) * 0.42
        box("CashBrick", pos.X + lx - 0.5, pos.Y + ly, pos.Z - 0.3, pos.X + lx + 0.5, pos.Y + ly + 0.4, pos.Z + 0.3,
            (i % 2 == 0) and CASH_A or CASH_B, M.Fabric, m)
        box("CashBand", pos.X + lx - 0.12, pos.Y + ly - 0.01, pos.Z - 0.31, pos.X + lx + 0.12, pos.Y + ly + 0.41, pos.Z + 0.31,
            Color3.fromRGB(240, 236, 220), M.Fabric, m, NOSHADOW)
    end
    m.Parent = f
    table.insert(loot, { kind = "Cash", cframe = lootCF(standPos, pos), visual = m, inVault = false })
    return m
end

-- ──────────────────────────────────────────────
-- 🏛 GRAND HALL  interior x -13.5..13.5, z -57.5..-38.5
-- Guard A walks z = -47 between x -9 and 9 → nothing in z -49.5..-44.5 there.
-- ──────────────────────────────────────────────
function VillaBuilder:_hall(f, props, spots, hides)
    -- chandelier (the room's main light)
    local cz = -47
    box("ChandelierChain", -0.08, 13.4, cz - 0.08, 0.08, TOP - 0.9, cz + 0.08, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier1", 0, 13.1, 13.4, cz, 5.0, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier2", 0, 12.3, 12.55, cz, 3.6, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierTier3", 0, 11.5, 11.7, cz, 2.2, GOLD, M.Metal, f, DECOR)
    vcyl("ChandelierRod", 0, 11.2, 13.1, cz, 0.25, GOLD, M.Metal, f, DECOR)
    for k = 0, 11 do
        local a = math.rad(k * 30)
        ball("Crystal", Vector3.new(math.cos(a) * 2.4, 12.7, cz + math.sin(a) * 2.4), 0.45,
            Color3.fromRGB(230, 240, 255), M.Glass, f, merge(NOSHADOW, { Transparency = 0.2 }))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60 + 30)
        ball("ChandelierBulb", Vector3.new(math.cos(a) * 1.5, 12.75, cz + math.sin(a) * 1.5), 0.35, WARM, M.Neon, f, NOSHADOW)
    end
    local drop = ball("ChandelierDrop", Vector3.new(0, 10.9, cz), 0.9, Color3.fromRGB(255, 236, 214), M.Glass, f,
        merge(NOSHADOW, { Transparency = 0.1 }))
    pointLight(drop, WARM, 1.2, 24, true)

    -- marble columns flanking the corridor arch
    for _, sx in ipairs({ -1, 1 }) do
        local x, z = sx * 9, -55
        vcyl("Column", x, FLOOR, TOP, z, 2, MARBLE, M.Marble, f)
        vcyl("ColumnBase", x, FLOOR, 1.3, z, 2.6, GOLD, M.Metal, f)
        vcyl("ColumnCapital", x, TOP - 1.4, TOP - 0.6, z, 2.6, GOLD, M.Metal, f)
        -- sconces either side of the arch
        local sx7 = sx * 7.1
        box("Sconce", sx7 - 0.3, 7.8, -57.5, sx7 + 0.3, 8.3, -57.15, BRASS, M.Metal, f, DECOR)
        local b = ball("SconceBulb", Vector3.new(sx7, 8.45, -57.3), 0.3, WARM, M.Neon, f, NOSHADOW)
        pointLight(b, WARM, 0.7, 10, false)
    end

    -- round foyer table with a big vase (part-built: keycard spot height is exact)
    local tz, top = -52.5, 3.35
    vcyl("TableBase", 0, FLOOR, 0.8, tz, 2.4, BRASS, M.Metal, f)
    vcyl("TablePedestal", 0, 0.8, 3.0, tz, 1.0, WOOD_DARK, M.Wood, f)
    vcyl("TableTop", 0, 3.0, top, tz, 5, MARBLE, M.Marble, f)
    vcyl("Vase", 0, top, 5.0, tz, 1.0, Color3.fromRGB(240, 150, 190), M.Glass, f, { Transparency = 0.15 })
    for k = 0, 6 do
        local a = math.rad(k * 51)
        ball("VaseFlower", Vector3.new(math.cos(a) * 0.6, 5.3 + (k % 2) * 0.35, tz + math.sin(a) * 0.6), 0.7,
            (k % 2 == 0) and Color3.fromRGB(255, 120, 190) or Color3.fromRGB(250, 240, 240), M.Fabric, f, DECOR)
    end
    table.insert(spots, CFrame.new(1.4, top + 0.01, tz + 0.8))
    prop(props, "rugRound", 0, FLOOR, tz, nil, 1.0)

    -- BIG PLANT hide spot in the NW corner (under the hall camera). You stand in the
    -- planter among the leaves; the soil is the tagged part.
    local px, pz = -12.0, -55.8
    box("PlanterWall", px - 1.6, FLOOR, pz - 1.6, px + 1.6, 1.8, pz - 1.4, TEAL_DARK, M.Concrete, f)
    box("PlanterWall", px - 1.6, FLOOR, pz + 1.4, px + 1.6, 1.8, pz + 1.6, TEAL_DARK, M.Concrete, f)
    box("PlanterWall", px - 1.6, FLOOR, pz - 1.4, px - 1.4, 1.8, pz + 1.4, TEAL_DARK, M.Concrete, f)
    box("PlanterWall", px + 1.4, FLOOR, pz - 1.4, px + 1.6, 1.8, pz + 1.4, TEAL_DARK, M.Concrete, f)
    local soil = cpart("PlanterSoil", Vector3.new(2.8, 0.3, 2.8), CFrame.lookAt(Vector3.new(px, 1.35, pz), Vector3.new(px + 1, 1.35, pz)),
        Color3.fromRGB(60, 42, 30), M.Ground, f)
    tagHide(soil, hides, "Big plant", Vector3.new(px, 4.2, pz))
    vcyl("PlantTrunk", px, 1.5, 7, pz, 0.4, Color3.fromRGB(110, 84, 60), M.Wood, f, DECOR)
    for k = 0, 8 do
        local a = math.rad(k * 40)
        local r = (k % 2 == 0) and 1.1 or 0.6
        ball("PlantLeaves", Vector3.new(px + math.cos(a) * r, 3.2 + (k % 3) * 1.5, pz + math.sin(a) * r), 2.4,
            LEAF, M.Grass, f, NOSHADOW)
    end

    -- NE corner: floor lamp + plant (mirror of the planter, so the room balances)
    prop(props, "lampSquareFloor", 12.3, FLOOR, -56.6)
    pointLight(lightHolder(f, Vector3.new(12.3, 7.3, -56.6)), WARM, 0.6, 11, false)
    prop(props, "pottedPlant", 12.2, FLOOR, -53.2, nil, 1.5)

    -- benches under the front windows, plants beside the door
    for _, sx in ipairs({ -1, 1 }) do
        prop(props, "benchCushion", sx * 9.9, FLOOR, -39.9, NZ, 1.0)
        prop(props, "pottedPlant", sx * 6.3, FLOOR, -40.2, nil, 1.3)
    end

    -- paintings on the side walls
    painting(f, Vector3.new(-13.5, 8, -55), PX, 3.2, 3.6, 11)
    painting(f, Vector3.new(-13.5, 7.6, -41), PX, 3.2, 3.2, 13)
    painting(f, Vector3.new(13.5, 8, -55), NX, 3.2, 3.6, 12)
    painting(f, Vector3.new(13.5, 7.6, -41), NX, 3.2, 3.2, 14)
end

-- ──────────────────────────────────────────────
-- 📚 OFFICE  interior x -41.5..-14.5, z -57.5..-38.5
-- Guard C walks x = -28 → keep x -30.5..-25.5 clear.
-- ──────────────────────────────────────────────
function VillaBuilder:_office(f, props, spots, loot)
    -- executive desk facing east (part-built so the keycard spot height is exact)
    local deskTop = 3.3
    box("DeskTop", -35.2, deskTop - 0.3, -53, -31.8, deskTop, -47, WOOD_DARK, M.WoodPlanks, f)
    box("DeskPedestal", -35.1, FLOOR, -52.9, -31.9, deskTop - 0.3, -51.5, WOOD_DARK, M.Wood, f)
    box("DeskPedestal", -35.1, FLOOR, -48.5, -31.9, deskTop - 0.3, -47.1, WOOD_DARK, M.Wood, f)
    box("DeskModesty", -32.1, FLOOR + 0.6, -51.5, -31.9, deskTop - 0.3, -48.5, WOOD_MID, M.Wood, f)
    box("DeskInlay", -35.0, deskTop, -52.7, -32.0, deskTop + 0.02, -47.3, Color3.fromRGB(40, 70, 52), M.Fabric, f, NOSHADOW)
    table.insert(spots, CFrame.new(-33.2, deskTop + 0.03, -48.3))
    -- green banker's lamp
    box("DeskLampBase", -34.9, deskTop, -52.6, -34.3, deskTop + 0.15, -52.2, BRASS, M.Metal, f, DECOR)
    box("DeskLampStem", -34.65, deskTop + 0.15, -52.45, -34.55, deskTop + 0.95, -52.35, BRASS, M.Metal, f, DECOR)
    local shade = box("DeskLampShade", -35.1, deskTop + 0.95, -52.65, -34.1, deskTop + 1.25, -52.15,
        Color3.fromRGB(40, 120, 70), M.Glass, f, DECOR)
    pointLight(shade, Color3.fromRGB(255, 210, 150), 0.9, 12, true)
    prop(props, "laptop", -33.6, deskTop, -50.2, NX, 1.0)
    prop(props, "chairDesk", -37.2, FLOOR, -50, PX)
    prop(props, "rugRectangle", -36, FLOOR, -50, PX, 0.7)

    -- bookcases on the west wall either side of the window
    prop(props, "bookcaseClosedWide", -40.45, FLOOR, -54, PX)
    prop(props, "bookcaseClosedWide", -40.45, FLOOR, -42, PX)

    -- open floor safe with cash in it (small loot, no vault needed)
    local sx0, sx1, sz0, sz1 = -39, -36, -57.3, -55.1
    box("SafeBack", sx0, FLOOR, sz0, sx1, 3.5, sz0 + 0.3, STEEL, M.Metal, f)
    box("SafeSide", sx0, FLOOR, sz0, sx0 + 0.3, 3.5, sz1, STEEL, M.Metal, f)
    box("SafeSide", sx1 - 0.3, FLOOR, sz0, sx1, 3.5, sz1, STEEL, M.Metal, f)
    box("SafeTop", sx0, 3.2, sz0, sx1, 3.5, sz1, STEEL, M.Metal, f)
    box("SafeFloor", sx0, FLOOR, sz0, sx1, 0.9, sz1, STEEL, M.Metal, f)
    box("SafeDoor", sx1, FLOOR + 0.1, sz1 - 0.1, sx1 + 0.25, 3.4, sz1 + 2.2, VSTEEL, M.DiamondPlate, f)
    disc("SafeDial", Vector3.new(sx1 + 0.3, 2.2, sz1 + 1.2), PX, 0.1, 0.8, BRASS, M.Metal, f, DECOR)
    cashStack(f, loot, Vector3.new(-37.5, 0.9, -56.1), Vector3.new(-37.5, FLOOR, -53.2), 4)

    -- lounge corner (NE): sofa, glass coffee table, armchair, floor lamp
    prop(props, "loungeSofa", -19.5, FLOOR, -55.7, PZ)
    prop(props, "tableCoffeeGlass", -19.5, FLOOR, -51.3, PZ, 1.0)
    prop(props, "loungeChair", -23.4, FLOOR, -51.3, PX, 1.0)
    prop(props, "lampSquareFloor", -24.6, FLOOR, -56.8)
    pointLight(lightHolder(f, Vector3.new(-24.6, 7.3, -56.8)), WARM, 0.6, 12, false)

    -- south wall: sideboard with a lamp + a globe
    prop(props, "sideTableDrawers", -29, FLOOR, -39.45, NZ)
    prop(props, "lampSquareTable", -30, 3.76, -39.4, nil, 1.0)
    pointLight(lightHolder(f, Vector3.new(-30, 5.8, -39.6)), WARM, 0.5, 9, false)
    vcyl("GlobeStand", -35.5, FLOOR, 2.6, -41.5, 0.3, BRASS, M.Metal, f)
    ball("Globe", Vector3.new(-35.5, 3.5, -41.5), 1.8, Color3.fromRGB(70, 120, 170), M.SmoothPlastic, f)
    prop(props, "ceilingFan", -28, TOP - 1.15, -48)

    painting(f, Vector3.new(-14.5, 8, -55.3), NX, 3.4, 2.6, 21)
    painting(f, Vector3.new(-35, 8, -57.5), PZ, 3.5, 2.6, 22)
    painting(f, Vector3.new(-37.5, 8, -38.5), NZ, 1.8, 2.6, 23)
end

-- ──────────────────────────────────────────────
-- 🍸 KITCHEN  interior x 14.5..41.5, z -57.5..-38.5 (no guard — easy room)
-- ──────────────────────────────────────────────
function VillaBuilder:_kitchen(f, props, spots, loot)
    -- appliances along the east wall (the window sits above the stove)
    prop(props, "kitchenFridgeLarge", 39.78, FLOOR, -49.5, NX)
    prop(props, "kitchenStove", 39.6, FLOOR, -45, NX)
    prop(props, "kitchenSink", 39.6, FLOOR, -41.35, NX)
    prop(props, "kitchenCabinetUpper", 40.57, 7.2, -41.35, NX)
    -- pantry shelves in the dark NE corner
    prop(props, "bookcaseOpen", 36, FLOOR, -56.44, PZ)
    prop(props, "bookcaseOpen", 39.5, FLOOR, -56.44, PZ)
    prop(props, "cardboardBoxClosed", 33, FLOOR, -56.6, nil, 1.0)

    -- marble island (part-built — cash + keycard spot on top)
    local top = 3.9
    box("IslandBase", 25.2, FLOOR, -49.8, 32.8, top - 0.3, -46.2, Color3.fromRGB(40, 70, 72), M.Wood, f)
    box("IslandTop", 25, top - 0.3, -50, 33, top, -46, MARBLE, M.Marble, f)
    box("IslandKick", 25.3, FLOOR, -49.7, 32.7, 0.9, -46.3, TEAL_DARK, M.Metal, f, DECOR)
    table.insert(spots, CFrame.new(32, top + 0.01, -47.2))
    cashStack(f, loot, Vector3.new(26.3, top, -48), Vector3.new(22.8, FLOOR, -48), 3)
    prop(props, "kitchenCoffeeMachine", 29.5, top, -49.2, PZ, 1.0)
    for _, x in ipairs({ 27, 29, 31 }) do
        prop(props, "stoolBar", x, FLOOR, -43.9, NZ, 1.0)
    end
    for _, x in ipairs({ 27, 31 }) do
        box("PendantCable", x - 0.05, 9.8, -48.05, x + 0.05, TOP, -47.95, STEEL, M.Metal, f, DECOR)
        vcyl("PendantShade", x, 9.1, 9.8, -48, 1.3, STEEL, M.Metal, f, DECOR)
        local b = ball("PendantBulb", Vector3.new(x, 9.0, -48), 0.3, WARM, M.Neon, f, NOSHADOW)
        pointLight(b, WARM, 0.9, 9, x == 27)
    end

    -- dining table by the front windows
    prop(props, "tableCloth", 20.5, FLOOR, -41.2, PZ)
    for _, x in ipairs({ 18.8, 22.2 }) do
        prop(props, "chairCushion", x, FLOOR, -44.6, PZ)
    end
    ceilingLamp(f, 20.5, -41.2, WARM, 0.7, 12, false, 10)

    prop(props, "trashcan", 22.5, FLOOR, -56.6, nil, 1.0)
    prop(props, "pottedPlant", 15.8, FLOOR, -39.8, nil, 1.3)
    painting(f, Vector3.new(14.5, 8, -40.5), PX, 2.4, 2.4, 41)
    painting(f, Vector3.new(19, 8, -57.5), PZ, 3, 2.4, 42)
    -- window curtains on the front
    curtains(f, "x", -38.6, 20, 24, Color3.fromRGB(240, 220, 170))
    curtains(f, "x", -38.6, 34, 38, Color3.fromRGB(240, 220, 170))
end

-- ──────────────────────────────────────────────
-- 🖼 GALLERY CORRIDOR  interior x -41.5..41.5, z -69.5..-58.5
-- Guard B walks z = -64 from x -20 to 28. Props only in z > -61 / z < -67.
-- Both ends are unlit on purpose (shadow zones).
-- ──────────────────────────────────────────────
local SCULPTURE_NAMES = { "ROSA I", "L'OEUF D'OR", "VASE ROSE", "TORSION" }

local function sculpture(parent, x, z, kind)
    local y = 3.7
    if kind == "bust" then
        vcyl("SculptNeck", x, y, y + 0.5, z, 0.6, MARBLE, M.Marble, parent)
        ball("SculptHead", Vector3.new(x, y + 1.05, z), 1.2, MARBLE, M.Marble, parent)
    elseif kind == "egg" then
        vcyl("SculptStand", x, y, y + 0.3, z, 0.7, BRASS, M.Metal, parent)
        ball("SculptEgg", Vector3.new(x, y + 0.85, z), 1.1, GOLD, M.Metal, parent, { Reflectance = 0.3 })
    elseif kind == "vase" then
        ball("SculptVaseBody", Vector3.new(x, y + 0.55, z), 1.1, Color3.fromRGB(255, 150, 200), M.Glass, parent, { Transparency = 0.2 })
        vcyl("SculptVaseNeck", x, y + 0.9, y + 1.8, z, 0.5, Color3.fromRGB(255, 150, 200), M.Glass, parent, { Transparency = 0.2 })
    else
        for k = 0, 2 do
            cpart("SculptTwist", Vector3.new(0.55, 0.6, 0.55),
                CFrame.new(x, y + 0.3 + k * 0.6, z) * CFrame.Angles(0, math.rad(k * 30), 0), TEAL, M.Metal, parent)
        end
    end
end

local function pedestal(parent, x, z, face, title, subtitle)
    local ped = box("Pedestal", x - 0.9, FLOOR, z - 0.9, x + 0.9, 3.5, z + 0.9, MARBLE, M.Marble, parent)
    box("PedestalCap", x - 1.0, 3.5, z - 1.0, x + 1.0, 3.7, z + 1.0, BRASS, M.Metal, parent)
    local g = surface(ped, face, 40, 1, 1)
    text({ Text = title, Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.12),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = Color3.fromRGB(150, 118, 50) }, g)
    text({ Text = subtitle or "PRICELESS", Size = UDim2.fromScale(0.9, 0.05), Position = UDim2.fromScale(0.05, 0.2),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.medium,
        TextColor3 = Color3.fromRGB(110, 104, 96) }, g)
    return ped
end

function VillaBuilder:_corridor(f, props, loot, hides)
    local F, B = Enum.NormalId.Front, Enum.NormalId.Back
    -- decor pedestals (south strip faces north = Front, north strip faces south = Back)
    pedestal(f, -19, -59.6, F, SCULPTURE_NAMES[1]); sculpture(f, -19, -59.6, "bust")
    pedestal(f, -10, -59.6, F, SCULPTURE_NAMES[2]); sculpture(f, -10, -59.6, "egg")
    pedestal(f, 10, -59.6, F, SCULPTURE_NAMES[3]); sculpture(f, 10, -59.6, "vase")
    pedestal(f, 22, -68.4, B, SCULPTURE_NAMES[4]); sculpture(f, 22, -68.4, "twist")
    for _, p in ipairs({ { -19, -59.6 }, { -10, -59.6 }, { 10, -59.6 }, { 22, -68.4 } }) do
        local fx = box("GallerySpot", p[1] - 0.4, TOP - 0.3, p[2] - 0.4, p[1] + 0.4, TOP, p[2] + 0.4, STEEL, M.Metal, f, DECOR)
        spotLight(fx, Enum.NormalId.Bottom, Color3.fromRGB(255, 236, 214), 1.0, 18, 30, false)
    end

    -- ART loot #1: a painting on an easel (north strip)
    local ex, ez = -14, -68.2
    box("EaselLeg", ex - 1.3, FLOOR, ez - 0.1, ex - 1.1, 7, ez + 0.1, WOOD_MID, M.Wood, f)
    box("EaselLeg", ex + 1.1, FLOOR, ez - 0.1, ex + 1.3, 7, ez + 0.1, WOOD_MID, M.Wood, f)
    box("EaselLeg", ex - 0.1, FLOOR, ez - 1.1, ex + 0.1, 6.5, ez - 0.9, WOOD_MID, M.Wood, f)
    box("EaselLedge", ex - 1.5, 2.6, ez - 0.1, ex + 1.5, 2.8, ez + 0.5, WOOD_MID, M.Wood, f)
    local art1 = Instance.new("Model")
    art1.Name = "ArtEasel"
    painting(art1, Vector3.new(ex, 4.6, ez + 0.5), PZ, 3.2, 3.4, 61)
    art1.Parent = f
    table.insert(loot, { kind = "Art", cframe = lootCF(Vector3.new(ex, FLOOR, -65.2), Vector3.new(ex, 0, ez)), visual = art1, inVault = false })
    pictureLight(f, Vector3.new(ex, 9.2, -69.5), PZ, 3)

    -- ART loot #2: a gold statue on a pedestal (south strip)
    pedestal(f, 16, -59.6, F, "LA DORADA", "ON LOAN")
    local art2 = Instance.new("Model")
    art2.Name = "ArtStatue"
    vcyl("StatueBase", 16, 3.7, 4.0, -59.6, 1.3, GOLD, M.Metal, art2, { Reflectance = 0.3 })
    box("StatueBody", 15.65, 4.0, -59.85, 16.35, 5.6, -59.35, GOLD, M.Metal, art2, { Reflectance = 0.3 })
    ball("StatueHead", Vector3.new(16, 6.0, -59.6), 0.7, GOLD, M.Metal, art2, { Reflectance = 0.3 })
    cpart("StatueArm", Vector3.new(0.25, 1.4, 0.25), CFrame.new(16.55, 5.5, -59.6) * CFrame.Angles(0, 0, math.rad(-30)), GOLD, M.Metal, art2)
    art2.Parent = f
    table.insert(loot, { kind = "Art", cframe = lootCF(Vector3.new(16, FLOOR, -62.8), Vector3.new(16, 0, -59.6)), visual = art2, inVault = false })
    local fx = box("GallerySpot", 15.6, TOP - 0.3, -60, 16.4, TOP, -59.2, STEEL, M.Metal, f, DECOR)
    spotLight(fx, Enum.NormalId.Bottom, Color3.fromRGB(255, 236, 214), 1.2, 18, 30, true)

    -- wall paintings (+ picture lights on the middle ones only; the ends stay dark)
    painting(f, Vector3.new(-37, 8, -69.5), PZ, 3.6, 2.8, 62)
    painting(f, Vector3.new(-20, 8, -69.5), PZ, 3.0, 2.8, 63)
    painting(f, Vector3.new(12, 8, -69.5), PZ, 4.0, 3.0, 64)
    painting(f, Vector3.new(-15, 8, -58.5), NZ, 4.0, 3.0, 65)
    painting(f, Vector3.new(15, 8.6, -58.5), NZ, 3.0, 2.4, 66)
    painting(f, Vector3.new(37, 8, -58.5), NZ, 3.0, 2.8, 67)
    pictureLight(f, Vector3.new(-20, 9.9, -69.5), PZ, 3)
    pictureLight(f, Vector3.new(12, 10.1, -69.5), PZ, 3.5)
    pictureLight(f, Vector3.new(-15, 10.1, -58.5), NZ, 3.5)

    -- cover along the walls
    prop(props, "benchCushion", -37, FLOOR, -59.4, NZ)                 -- dark west end
    prop(props, "sideTableDrawers", -37, FLOOR, -68.55, PZ)
    prop(props, "sideTableDrawers", -20, FLOOR, -68.55, PZ)
    prop(props, "pottedPlant", -9.5, FLOOR, -68.3, nil, 1.6)            -- next to the keypad
    prop(props, "pottedPlant", 8, FLOOR, -68.3, nil, 1.6)
    prop(props, "benchCushion", 16, FLOOR, -68.6, PZ)
    prop(props, "pottedPlant", 7.2, FLOOR, -59.4, nil, 1.4)             -- flanking the hall arch
    prop(props, "pottedPlant", -7.2, FLOOR, -59.4, nil, 1.4)
    prop(props, "pottedPlant", 39.8, FLOOR, -59.9, nil, 1.6)            -- dark east end

    -- LINEN CUPBOARD hide spot on the east end wall (built-in, doors face west)
    local cx0, cx1, cz0, cz1 = 38.8, 41.5, -66.2, -61.4
    box("CupboardTop", cx0, 8.2, cz0, cx1, 8.5, cz1, TRIM, M.Wood, f)
    box("CupboardSide", cx0, FLOOR, cz0, cx1, 8.2, cz0 + 0.25, TRIM, M.Wood, f)
    box("CupboardSide", cx0, FLOOR, cz1 - 0.25, cx1, 8.2, cz1, TRIM, M.Wood, f)
    box("CupboardShelf", cx0 + 0.3, 6.5, cz0 + 0.25, cx1, 6.7, cz1 - 0.25, TRIM, M.Wood, f)
    for k = 0, 3 do   -- folded towels on the top shelf
        box("Towels", cx0 + 0.6, 6.7, cz0 + 0.5 + k * 1.1, cx1 - 0.3, 7.5, cz0 + 1.4 + k * 1.1,
            (k % 2 == 0) and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(150, 205, 210), M.Fabric, f, NOSHADOW)
    end
    local doors = cpart("LinenCupboardDoors", Vector3.new(cz1 - cz0, 7.7, 0.2),
        CFrame.lookAt(Vector3.new(cx0 - 0.1, FLOOR + 3.85, (cz0 + cz1) / 2), Vector3.new(cx0 - 5, FLOOR + 3.85, (cz0 + cz1) / 2)),
        Color3.fromRGB(226, 214, 196), M.Wood, f)
    local dg = surface(doors, Enum.NormalId.Front, 20, 1, 1)
    for i = 0, 1 do
        local d = frame({ Size = UDim2.fromScale(0.46, 0.92), Position = UDim2.fromScale(0.03 + i * 0.5, 0.04),
            BackgroundColor3 = Color3.fromRGB(214, 200, 180) }, dg)
        frame({ Size = UDim2.fromScale(0.06, 0.1), Position = UDim2.fromScale(i == 0 and 0.88 or 0.06, 0.48),
            BackgroundColor3 = BRASS }, d)
    end
    tagHide(doors, hides, "Linen cupboard", Vector3.new(40.2, FLOOR + 3, (cz0 + cz1) / 2))

    -- two dim sconces flanking the glass door (they light the keypad)
    for _, sx in ipairs({ -1, 1 }) do
        local x = sx * 6.6
        box("Sconce", x - 0.3, 7.8, -69.5, x + 0.3, 8.3, -69.15, BRASS, M.Metal, f, DECOR)
        local b = ball("SconceBulb", Vector3.new(x, 8.45, -69.3), 0.3, WARM, M.Neon, f, NOSHADOW)
        pointLight(b, WARM, 0.8, 11, true)
    end
end

-- ──────────────────────────────────────────────
-- 🔐 GLASS KEYCARD DOOR (corridor north wall, x -4..4, z -70)
-- ──────────────────────────────────────────────
function VillaBuilder:_keycardDoor(f)
    local door = box("KeycardDoor", -4, FLOOR, -70.2, 4, DOOR_TOP, -69.8, Color3.fromRGB(170, 225, 235), M.Glass, f,
        { Transparency = 0.45, Reflectance = 0.1 })
    local dg = surface(door, Enum.NormalId.Back, 30, 1, 1)
    text({
        Text = "PRIVATE  ·  AUTHORISED ACCESS ONLY", Size = UDim2.fromScale(0.8, 0.035),
        Position = UDim2.fromScale(0.1, 0.5), TextXAlignment = Enum.TextXAlignment.Center,
        TextScaled = true, FontFace = UITheme.F.medium, TextColor3 = Color3.fromRGB(240, 250, 255),
        TextTransparency = 0.35,
    }, dg)

    -- static frame trim on the corridor face (the door slides east into the wall)
    box("GlassDoorJamb", -4.3, FLOOR, -69.5, -4, DOOR_TOP + 0.3, -69.3, STEEL_LITE, M.Metal, f)
    box("GlassDoorJamb", 4, FLOOR, -69.5, 4.3, DOOR_TOP + 0.3, -69.3, STEEL_LITE, M.Metal, f)
    box("GlassDoorHead", -4.3, DOOR_TOP, -69.5, 4.3, DOOR_TOP + 0.3, -69.3, STEEL_LITE, M.Metal, f)
    -- red floor stripe: "this is the locked door"
    box("DoorStripe", -4, FLOOR, -69.4, 4, FLOOR + 0.04, -69.0, SIGN_RED, M.SmoothPlastic, f, NOSHADOW)

    -- keypad on the corridor side, west of the door
    local panel = box("Keypad", -6.2, 4.2, -69.5, -5.0, 6.0, -69.25, Color3.fromRGB(34, 37, 44), M.Metal, f)
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
    local status = box("KeypadStatus", -5.75, 5.65, -69.25, -5.45, 5.85, -69.17, SIGN_RED, M.Neon, f, NOSHADOW)
    box("CardSlot", -5.9, 4.35, -69.25, -5.3, 4.45, -69.2, Color3.fromRGB(10, 10, 12), M.Metal, f, NOSHADOW)

    return { door = door, openOffset = Vector3.new(8.2, 0, 0), panel = panel, status = status }
end

-- ──────────────────────────────────────────────
-- 🔴 LASER CORRIDOR  interior x -5.5..5.5, z -81.5..-70.5 (low ceiling, red light)
-- ──────────────────────────────────────────────
function VillaBuilder:_lasers(f)
    box("CorridorCeiling", -6, 12.5, -82, 6, 13, -70, STEEL, M.Metal, f)
    local fixture = box("CorridorLight", -0.6, 12.35, -76.4, 0.6, 12.5, -75.6, STEEL, M.Metal, f, DECOR)
    pointLight(fixture, Color3.fromRGB(255, 70, 70), 0.6, 13, true)
    -- hazard stripes on the side walls at ankle height
    for _, sx in ipairs({ -1, 1 }) do
        box("HazardStripe", sx * 5.5 - 0.05, FLOOR, -81.5, sx * 5.5 + 0.05, FLOOR + 0.4, -70.5, Color3.fromRGB(240, 190, 40), M.SmoothPlastic, f, NOSHADOW)
    end

    local rows = {}
    local zs = { -72.4, -74.6, -76.8, -79.0 }   -- same spacing as v1 (safe spot at the vault door)
    local heights = { 1.3, 2.8, 4.3 }
    for i, z in ipairs(zs) do
        local beams = {}
        for _, h in ipairs(heights) do
            local b = box("LaserBeam", -5.3, FLOOR + h - 0.06, z - 0.06, 5.3, FLOOR + h + 0.06, z + 0.06,
                LASER_RED, M.Neon, f, { CanCollide = false, CastShadow = false, CanQuery = false })
            table.insert(beams, b)
        end
        for _, sx in ipairs({ -1, 1 }) do
            box("LaserEmitter", sx * 5.5, FLOOR + 0.8, z - 0.25, sx * 5.28, FLOOR + 4.8, z + 0.25, STEEL, M.Metal, f)
            for _, h in ipairs(heights) do
                box("LaserLens", sx * 5.28, FLOOR + h - 0.1, z - 0.1, sx * 5.22, FLOOR + h + 0.1, z + 0.1,
                    LASER_RED, M.Neon, f, NOSHADOW)
            end
        end
        table.insert(rows, {
            beams = beams,
            zoneCFrame = CFrame.new(0, FLOOR + 2.5, z),
            zoneSize = Vector3.new(11, 5, 0.6),
            onTime = 1.4, offTime = 1.1,
            phase = (i - 1) * 0.6,
        })
    end
    return rows
end

-- ──────────────────────────────────────────────
-- 🏦 VAULT: round door (z -82) + steel room x -18..18, z -96..-82
-- ──────────────────────────────────────────────
function VillaBuilder:_vault(f)
    -- the corridor end of the vault wall, with the round opening (x -3..3, y 1..8)
    wallRun(f, "VaultWall", "x", -82, -6, 6, { { -3, 3, 1, 8, "open" } }, VSTEEL, M.Metal)
    vcyl("VaultHinge", 4.3, 2.3, 4.1, -80.7, 0.6, STEEL, M.Metal, f, DECOR)
    vcyl("VaultHinge", 4.3, 5.7, 7.5, -80.7, 0.6, STEEL, M.Metal, f, DECOR)

    -- the door: disc Ø9 against the corridor face, centre (0, 4.8, -81)
    local c = Vector3.new(0, 4.8, -81)
    local south = PZ
    local swing = {}
    local diskPart = disc("VaultDoorDisc", c, south, 1, 9, STEEL_LITE, M.Metal, f, { Reflectance = 0.08 })
    table.insert(swing, diskPart)
    -- `door` must be a part whose LookVector faces the corridor (JobService sits the
    -- drill at door.CFrame * (0,0,-1.6)); a Cylinder's round face is its local X, so the
    -- door ref is this square steel boss plate at the centre of the disc instead.
    local bossPos = c + south * 0.65
    local door = cpart("VaultDoor", Vector3.new(3.4, 3.4, 0.3), CFrame.lookAt(bossPos, bossPos + south),
        Color3.fromRGB(120, 124, 134), M.DiamondPlate, f)
    table.insert(swing, door)
    table.insert(swing, disc("VaultHub", c + south * 0.7, south, 0.4, 2, STEEL, M.Metal, f))
    for k = 0, 2 do
        table.insert(swing, cpart("VaultSpoke", Vector3.new(5.6, 0.35, 0.3),
            CFrame.new(c + south * 1.05) * CFrame.Angles(0, 0, math.rad(k * 60)), STEEL, M.Metal, f))
    end
    for k = 0, 5 do
        local a = math.rad(k * 60)
        table.insert(swing, ball("VaultHandle", c + south * 1.05 + Vector3.new(math.cos(a) * 2.8, math.sin(a) * 2.8, 0),
            0.55, BRASS, M.Metal, f))
    end
    for k = 0, 9 do
        local a = math.rad(k * 36 + 18)
        table.insert(swing, disc("VaultBolt", c + south * 0.6 + Vector3.new(math.cos(a) * 3.8, math.sin(a) * 3.8, 0),
            south, 0.25, 0.55, STEEL, M.Metal, f))
    end

    -- steel room: lining, lower ceiling, gold light
    box("VaultLiningW", -17.5, FLOOR, -95.5, -17.3, 12.5, -82.5, VSTEEL, M.Metal, f)
    box("VaultLiningE", 17.3, FLOOR, -95.5, 17.5, 12.5, -82.5, VSTEEL, M.Metal, f)
    box("VaultLiningN", -17.5, FLOOR, -95.5, 17.5, 12.5, -95.3, VSTEEL, M.Metal, f)
    box("VaultLiningS", -17.5, FLOOR, -82.7, -3, 12.5, -82.5, VSTEEL, M.Metal, f)
    box("VaultLiningS", 3, FLOOR, -82.7, 17.5, 12.5, -82.5, VSTEEL, M.Metal, f)
    box("VaultCeiling", -18, 12.5, -96, 18, 13, -82, STEEL, M.Metal, f)
    for _, x in ipairs({ -10, 0, 10 }) do
        local fx = box("VaultLight", x - 0.8, 12.35, -89.5, x + 0.8, 12.5, -88.5, BRASS, M.Metal, f, DECOR)
        pointLight(fx, Color3.fromRGB(255, 200, 110), 1.1, 15, x == 0)
    end
    -- safe-deposit wall on the east side
    local boxes = box("DepositBoxes", 16.9, 1, -93, 17.3, 10, -84, Color3.fromRGB(150, 130, 90), M.Metal, f)
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
        hinge = CFrame.new(4.5, c.Y, c.Z),   -- east edge of the disc
        openAngle = math.rad(-100),          -- swings north into the vault (sweeps x 4.5..6, z -81..-90)
        parts = swing,
        disc = diskPart,
    }
end

function VillaBuilder:_vaultLoot(f)
    local loot = {}
    -- west wall: three cash pallets
    for _, z in ipairs({ -86, -89.5, -93 }) do
        cashPile(f, loot, -15.8, z, Vector3.new(-12.6, FLOOR, z))
    end
    -- north wall: three gold stacks + two diamond cases. The open door sweeps
    -- x 4.5..6.1 / z -81..-90, so nothing sits in x 3..8 south of z -91.
    for _, x in ipairs({ -10, -6, -2 }) do
        goldPile(f, loot, x, -94.3, Vector3.new(x, FLOOR, -91.3))
    end
    for _, x in ipairs({ 9.5, 13.5 }) do
        diamondCase(f, loot, x, -94.1, Vector3.new(x, FLOOR, -91.1))
    end
    return loot
end

-- ──────────────────────────────────────────────
-- 🛏 MASTER BEDROOM  interior x -41.5..-18.5, z -95.5..-70.5
-- Guard C walks x = -28 to z -86 → keep x -30.5..-25.5 clear.
-- ──────────────────────────────────────────────
function VillaBuilder:_bedroom(f, props, spots, loot)
    prop(props, "bedDouble", -36.75, FLOOR, -83, PX)
    prop(props, "rugRectangle", -34, FLOOR, -83, PX, 1.0)
    prop(props, "bear", -39.6, 3.6, -83, PX, 0.6)
    -- nightstands (part-built). North one is in the dark corner and holds a keycard spot.
    local nsTop = 2.85
    for i, z0 in ipairs({ -90.4, -77.6 }) do
        box("Nightstand", -41.4, FLOOR, z0, -39.5, nsTop - 0.15, z0 + 2, WOOD_MID, M.Wood, f)
        box("NightstandTop", -41.45, nsTop - 0.15, z0 - 0.05, -39.45, nsTop, z0 + 2.05, WOOD_DARK, M.WoodPlanks, f)
        box("NightstandKnob", -39.5, 1.9, z0 + 0.9, -39.4, 2.1, z0 + 1.1, BRASS, M.Metal, f, DECOR)
        if i == 1 then
            table.insert(spots, CFrame.new(-40.4, nsTop + 0.01, -89.8))
        else
            prop(props, "lampRoundTable", -40.4, nsTop, -76.6, nil, 1.0)
            pointLight(lightHolder(f, Vector3.new(-40.4, nsTop + 1.9, -76.6)), Color3.fromRGB(255, 190, 140), 0.8, 12, true)
        end
    end
    -- dresser + mirror on the south wall, with the jewellery box (Jewels loot)
    box("Dresser", -40.5, FLOOR, -72.5, -35.5, 3.25, -70.5, WOOD_MID, M.Wood, f)
    box("DresserTop", -40.6, 3.25, -72.6, -35.4, 3.4, -70.5, MARBLE, M.Marble, f)
    for k = 0, 2 do
        box("DrawerLine", -40.3, 1.1 + k * 0.75, -72.55, -35.7, 1.15 + k * 0.75, -72.5, WOOD_DARK, M.Wood, f, NOSHADOW)
    end
    box("Mirror", -39.8, 4.2, -70.7, -36.2, 9, -70.5, Color3.fromRGB(200, 212, 218), M.Glass, f, { Reflectance = 0.45 })
    box("MirrorFrame", -40, 4.0, -70.6, -36, 9.2, -70.5, BRASS, M.Metal, f, DECOR)
    local jewels = Instance.new("Model")
    jewels.Name = "JewelleryBox"
    box("JewelBox", -38.6, 3.4, -71.8, -37.4, 3.9, -71.0, Color3.fromRGB(120, 30, 60), M.Fabric, jewels)
    cpart("JewelBoxLid", Vector3.new(1.2, 0.08, 0.8), CFrame.new(-38, 4.2, -70.95) * CFrame.Angles(math.rad(70), 0, 0),
        Color3.fromRGB(120, 30, 60), M.Fabric, jewels)
    for k = 0, 5 do
        ball("Pearl", Vector3.new(-38.9 + k * 0.28, 3.5, -72.2 + math.sin(k) * 0.1), 0.22,
            Color3.fromRGB(245, 240, 235), M.SmoothPlastic, jewels, NOSHADOW)
    end
    ball("Ruby", Vector3.new(-37.9, 4.0, -71.4), 0.3, Color3.fromRGB(255, 60, 110), M.Neon, jewels, NOSHADOW)
    ball("Emerald", Vector3.new(-38.2, 4.0, -71.3), 0.25, Color3.fromRGB(60, 240, 150), M.Neon, jewels, NOSHADOW)
    jewels.Parent = f
    table.insert(loot, { kind = "Jewels", cframe = lootCF(Vector3.new(-38, FLOOR, -75), Vector3.new(-38, 0, -71.4)), visual = jewels, inVault = false })

    -- TV corner on the east wall, armchair facing it
    prop(props, "cabinetTelevision", -19.56, FLOOR, -86, NX)
    prop(props, "televisionModern", -19.6, FLOOR + 2.63, -86, NX)
    local tvGlow = lightHolder(f, Vector3.new(-21, 4.5, -86))
    pointLight(tvGlow, Color3.fromRGB(120, 150, 255), 0.5, 10, false)
    prop(props, "loungeChairRelax", -23.2, FLOOR, -86, PX, 1.0)
    prop(props, "lampSquareFloor", -20, FLOOR, -94.5)
    pointLight(lightHolder(f, Vector3.new(-20, 7.3, -94.5)), WARM, 0.6, 12, false)
    prop(props, "pottedPlant", -23.5, FLOOR, -94.6, nil, 1.3)
    prop(props, "ceilingFan", -30, TOP - 1.15, -83)

    -- curtains on the sea-view windows + the west windows
    curtains(f, "x", -95.4, -38.5, -33.5, Color3.fromRGB(230, 200, 210))
    curtains(f, "x", -95.4, -26.5, -21.5, Color3.fromRGB(230, 200, 210))
    curtains(f, "z", -41.4, -94, -90, Color3.fromRGB(230, 200, 210))
    curtains(f, "z", -41.4, -76, -72, Color3.fromRGB(230, 200, 210))
    painting(f, Vector3.new(-41.5, 8, -83), PX, 5, 3, 31)
    painting(f, Vector3.new(-18.5, 8.5, -91), NX, 3, 2.4, 32)
end

-- ──────────────────────────────────────────────
-- 👗 WALK-IN CLOSET  interior x -17.5..-6.5, z -81.5..-70.5 — the roof hatch lands here
-- ──────────────────────────────────────────────
function VillaBuilder:_closet(f, spots, hides)
    -- clothes rail along the east wall
    box("ClothesRail", -7.3, 7, -80.5, -7.1, 7.15, -72.5, STEEL_LITE, M.Metal, f, DECOR)
    local cols = { Color3.fromRGB(30, 30, 36), Color3.fromRGB(230, 225, 215), Color3.fromRGB(170, 40, 70),
        Color3.fromRGB(60, 90, 150), Color3.fromRGB(200, 160, 110) }
    for k = 0, 9 do
        local z = -80 + k * 0.8
        box("Garment", -8.2, 3.5 - (k % 3) * 0.4, z - 0.12, -6.7, 7, z + 0.12, cols[(k % #cols) + 1], M.Fabric, f, DECOR)
    end
    box("ShoeShelf", -8.4, FLOOR, -80.5, -6.5, 1.4, -72.5, TRIM, M.Wood, f)

    -- vanity shelf (keycard spot) in the NW corner
    box("Vanity", -17.3, FLOOR, -81.3, -15, 3.4, -79.8, TRIM, M.Wood, f)
    box("VanityTop", -17.4, 3.4, -81.4, -14.9, 3.55, -79.7, MARBLE, M.Marble, f)
    table.insert(spots, CFrame.new(-16.2, 3.56, -80.5))

    -- WARDROBE hide spot on the south wall (hollow; doors face north into the room)
    local wx0, wx1, wz0, wz1 = -16.5, -12.5, -73, -70.5
    box("WardrobeBack", wx0, FLOOR, wz1 - 0.2, wx1, 9, wz1, WOOD_DARK, M.Wood, f)
    box("WardrobeSide", wx0, FLOOR, wz0, wx0 + 0.2, 9, wz1, WOOD_DARK, M.Wood, f)
    box("WardrobeSide", wx1 - 0.2, FLOOR, wz0, wx1, 9, wz1, WOOD_DARK, M.Wood, f)
    box("WardrobeTop", wx0, 8.8, wz0, wx1, 9, wz1, WOOD_DARK, M.Wood, f)
    local wdoors = cpart("WardrobeDoors", Vector3.new(wx1 - wx0 - 0.4, 8, 0.2),
        CFrame.lookAt(Vector3.new((wx0 + wx1) / 2, 4.8, wz0 + 0.1), Vector3.new((wx0 + wx1) / 2, 4.8, wz0 - 5)),
        WOOD_MID, M.Wood, f)
    local wg = surface(wdoors, Enum.NormalId.Front, 20, 1, 1)
    for i = 0, 1 do
        local d = frame({ Size = UDim2.fromScale(0.46, 0.94), Position = UDim2.fromScale(0.03 + i * 0.5, 0.03),
            BackgroundColor3 = Color3.fromRGB(110, 76, 50) }, wg)
        frame({ Size = UDim2.fromScale(0.07, 0.08), Position = UDim2.fromScale(i == 0 and 0.86 or 0.07, 0.48),
            BackgroundColor3 = BRASS }, d)
    end
    tagHide(wdoors, hides, "Closet", Vector3.new((wx0 + wx1) / 2, FLOOR + 3, -71.7))

    local l = ceilingLamp(f, -11.5, -75.5, WARM, 0.55, 14, false)
    return l
end

-- the roof hatch pair: lid on the roof (a) ↔ ladder foot in the closet (b)
function VillaBuilder:_roofHatch(f, roofF)
    local hx, hz = -12, -76
    -- roof side: a raised curb with an amber lid
    box("HatchCurb", hx - 2, ROOF, hz - 2, hx + 2, ROOF + 0.5, hz + 2, STEEL, M.Metal, roofF)
    local lidPos = Vector3.new(hx, ROOF + 0.6, hz)
    local a = cpart("Vent_RoofHatch", Vector3.new(3.4, 0.2, 3.4), CFrame.lookAt(lidPos, lidPos + PZ), HATCH, M.DiamondPlate, roofF)
    a.Name = "Vent_RoofHatch"
    box("HatchHandle", hx - 0.6, ROOF + 0.7, hz + 1.2, hx + 0.6, ROOF + 0.85, hz + 1.35, STEEL_LITE, M.Metal, roofF, DECOR)
    tagVent(a, "Vent_ClosetLadder", "Roof hatch", Vector3.new(hx, ROOF + 3, hz + 4.5))

    -- inside: a dark square in the ceiling, a fixed ladder down the north wall (decor
    -- only — non-collide so nobody climbs it into a ceiling), and the ladder-foot plate
    box("CeilingHatch", hx - 1.6, TOP - 0.15, -81.5, hx + 1.6, TOP, -78.3, Color3.fromRGB(30, 30, 34), M.DiamondPlate, f, NOSHADOW)
    for _, dx in ipairs({ -0.8, 0.8 }) do
        box("LadderRail", hx + dx - 0.1, FLOOR, -81.5, hx + dx + 0.1, TOP, -81.3, STEEL_LITE, M.Metal, f, NOSHADOW)
    end
    for k = 1, 7 do
        local y = FLOOR + k * 2.1
        box("LadderRung", hx - 0.8, y, -81.45, hx + 0.8, y + 0.15, -81.35, STEEL_LITE, M.Metal, f, NOSHADOW)
    end
    local bPos = Vector3.new(hx, 3.2, -81.2)
    local b = cpart("Vent_ClosetLadder", Vector3.new(2.4, 2.4, 0.2), CFrame.lookAt(bPos, bPos + PZ), HATCH, M.DiamondPlate, f)
    b.Name = "Vent_ClosetLadder"
    local g = surface(b, Enum.NormalId.Front, 60, 0, 1.2)
    text({ Text = "ROOF", Size = UDim2.fromScale(0.9, 0.4), Position = UDim2.fromScale(0.05, 0.3),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(30, 26, 20) }, g)
    tagVent(b, "Vent_RoofHatch", "Roof hatch", Vector3.new(hx, FLOOR + 3, -78.2))
    return { a = a, b = b }
end

-- the crawl vent pair: kitchen (under the hall) ↔ office. Skips the hall camera + Guard A.
function VillaBuilder:_crawlVent(f)
    local function grille(name, pos, normal)
        local p = cpart(name, Vector3.new(3.2, 2.2, 0.2), CFrame.lookAt(pos, pos + normal), Color3.fromRGB(70, 74, 80), M.Metal, f)
        p.Name = name
        local g = surface(p, Enum.NormalId.Front, 40, 1, 1)
        frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 20, 24) }, g)
        for i = 0, 5 do
            frame({ Size = UDim2.fromScale(0.9, 0.08), Position = UDim2.fromScale(0.05, 0.08 + i * 0.15),
                BackgroundColor3 = Color3.fromRGB(120, 126, 134) }, g)
        end
        local edge = cpart(name .. "Frame", Vector3.new(3.6, 2.6, 0.12), CFrame.lookAt(pos, pos + normal) * CFrame.new(0, 0, 0.1),
            HATCH, M.Metal, f, DECOR)
        edge.Name = "VentFrame"
        return p
    end
    local a = grille("Vent_Kitchen", Vector3.new(14.6, 1.9, -55), PX)
    local b = grille("Vent_Office", Vector3.new(-14.6, 1.9, -41), NX)
    tagVent(a, "Vent_Office", "Air vent", Vector3.new(17.5, FLOOR + 3, -55))
    tagVent(b, "Vent_Kitchen", "Air vent", Vector3.new(-17.5, FLOOR + 3, -41))
    return { a = a, b = b }
end

-- ──────────────────────────────────────────────
-- 🖥 SECURITY ROOM  interior x 6.5..17.5, z -81.5..-70.5 — THE BREAKER
-- Window onto the laser corridor so you can watch the beams blink.
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
    -- desk along the north wall with three monitors facing south
    local top = 3.3
    box("SecDesk", 7, top - 0.3, -81.5, 14, top, -79, Color3.fromRGB(58, 60, 66), M.Metal, f)
    box("SecDeskSide", 7, FLOOR, -81.5, 7.2, top - 0.3, -79, STEEL, M.Metal, f)
    box("SecDeskSide", 13.8, FLOOR, -81.5, 14, top - 0.3, -79, STEEL, M.Metal, f)
    local mid
    for i, xc in ipairs({ 8.4, 10.5, 12.6 }) do
        box("MonitorStand", xc - 0.3, top, -80.9, xc + 0.3, 3.75, -80.4, STEEL, M.Metal, f)
        local mon = box("Monitor", xc - 1.0, 3.75, -80.8, xc + 1.0, 5.45, -80.55, Color3.fromRGB(20, 22, 26), M.Metal, f)
        camFeed(mon, Enum.NormalId.Back, string.format("CAM 0%d", i), i)
        if i == 2 then mid = mon end
    end
    pointLight(mid, Color3.fromRGB(120, 170, 255), 0.8, 11, true)
    prop(props, "computerKeyboard", 10.5, top, -79.6, PZ, 1.0)
    prop(props, "chairDesk", 10.5, FLOOR, -77.3, NZ)

    -- server rack in the NE corner
    local rack = box("ServerRack", 15, FLOOR, -81.5, 17.5, 7.5, -79.7, Color3.fromRGB(28, 30, 36), M.Metal, f)
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

    ceilingLamp(f, 12, -75.5, COOL, 0.6, 14, true)

    -- BREAKER: grey electrical panel on the south wall, facing into the room (north)
    local breaker = box("Breaker", 12.5, 2.5, -71, 15.5, 6.5, -70.5, Color3.fromRGB(122, 126, 132), M.Metal, f)
    local bg = surface(breaker, Enum.NormalId.Front, 40, 1, 1)
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
    for i, x in ipairs({ 13.1, 14.0, 14.9 }) do
        box("BreakerLED", x - 0.1, 6.05, -71.07, x + 0.1, 6.25, -71.0,
            i == 3 and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(80, 240, 120), M.Neon, f, NOSHADOW)
    end
    box("BreakerConduit", 13.9, 6.5, -70.85, 14.1, TOP, -70.6, STEEL, M.Metal, f, DECOR)
    -- yellow warning plate above it so a kid spots it from the door
    local warn = box("BreakerWarning", 12.8, 7, -70.62, 15.2, 7.9, -70.5, Color3.fromRGB(250, 204, 21), M.Metal, f)
    signText(warn, Enum.NormalId.Front, "CAMERAS", Color3.fromRGB(30, 26, 20), 40, 1)

    -- sign outside the door (service hall side)
    local plate = box("SecuritySign", 18.5, 11, -77, 18.6, 12, -73, Color3.fromRGB(26, 26, 30), M.Metal, f)
    signText(plate, Enum.NormalId.Right, "SECURITY", Color3.fromRGB(120, 200, 255), 50, 0)
    return breaker
end

-- ──────────────────────────────────────────────
-- 🧺 SERVICE WING: service hall, laundry, staff room (sneakIn) + the side door
-- ──────────────────────────────────────────────
function VillaBuilder:_serviceHall(f, props)
    -- crates along the south wall (cover), a shelf, a utility sink
    prop(props, "box-large", 25, FLOOR, -72.3, PZ, nil, "factory")
    prop(props, "box-small", 25, FLOOR + 1.96, -72.3, PZ, nil, "factory")
    prop(props, "box-long", 28.5, FLOOR, -71.4, PZ, nil, "factory")
    prop(props, "bookcaseOpen", 29.5, FLOOR, -78.44, PZ)
    prop(props, "kitchenSink", 39.97, FLOOR, -75, NX, 1.0)
    -- cool fluorescent tube (thin neon accent + a dim light)
    local tube = box("FluoroTube", 28, TOP - 0.3, -75.2, 32, TOP - 0.15, -74.8, COOL, M.Neon, f, NOSHADOW)
    pointLight(tube, COOL, 0.6, 16, false)
    -- signs above the doors (on the hall side of the north wall)
    local s1 = box("StaffSign", 33.5, 11, -79.5, 38.5, 12, -79.4, Color3.fromRGB(26, 26, 30), M.Metal, f)
    signText(s1, Enum.NormalId.Back, "STAFF ROOM", Color3.fromRGB(250, 204, 21), 50, 0)
    local s2 = box("LaundrySign", 21.5, 11, -79.5, 25.5, 12, -79.4, Color3.fromRGB(26, 26, 30), M.Metal, f)
    signText(s2, Enum.NormalId.Back, "LAUNDRY", Color3.fromRGB(150, 220, 240), 50, 0)
end

function VillaBuilder:_laundry(f, props, hides)
    prop(props, "washer", 20.15, FLOOR, -93.8, PX)
    prop(props, "dryer", 20.15, FLOOR, -90.4, PX)
    prop(props, "washerDryerStacked", 20.15, FLOOR, -87.0, PX)
    -- folding table with towels + a wall shelf of detergent
    box("FoldTable", 22.5, 3.0, -95.3, 27.3, 3.3, -93.3, TRIM, M.Wood, f)
    for _, x in ipairs({ 22.7, 27.0 }) do
        box("FoldTableLeg", x - 0.1, FLOOR, -95.1, x + 0.1, 3.0, -93.5, STEEL, M.Metal, f)
    end
    for k = 0, 2 do
        box("TowelStack", 23.2 + k * 1.3, 3.3, -94.9, 24.2 + k * 1.3, 3.9 + (k % 2) * 0.3, -93.8,
            (k % 2 == 0) and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(240, 170, 190), M.Fabric, f)
    end
    box("WallShelf", 22.5, 6.2, -95.5, 27.3, 6.4, -94.7, TRIM, M.Wood, f)
    for k = 0, 3 do
        box("Detergent", 22.9 + k * 1.1, 6.4, -95.3, 23.6 + k * 1.1, 7.4, -94.9,
            ({ Color3.fromRGB(240, 120, 40), Color3.fromRGB(60, 140, 230), Color3.fromRGB(240, 240, 240), Color3.fromRGB(90, 200, 120) })[k + 1],
            M.SmoothPlastic, f, NOSHADOW)
    end

    -- LAUNDRY CART hide spot (hollow canvas bin on wheels; you climb in)
    local cx, cz = 23.6, -84.5
    local x0, x1, z0, z1 = cx - 1.5, cx + 1.5, cz - 1.5, cz + 1.5
    local CANVAS = Color3.fromRGB(96, 110, 128)
    box("CartFrame", x0, 0.9, z0, x1, 1.2, z1, STEEL, M.Metal, f)
    box("CartSide", x0, 1.2, z0, x1, 3.8, z0 + 0.15, CANVAS, M.Fabric, f)
    box("CartSide", x0, 1.2, z0, x0 + 0.15, 3.8, z1, CANVAS, M.Fabric, f)
    box("CartSide", x1 - 0.15, 1.2, z0, x1, 3.8, z1, CANVAS, M.Fabric, f)
    for _, p in ipairs({ { x0 + 0.3, z0 + 0.3 }, { x1 - 0.3, z0 + 0.3 }, { x0 + 0.3, z1 - 0.3 }, { x1 - 0.3, z1 - 0.3 } }) do
        ball("CartWheel", Vector3.new(p[1], 0.7, p[2]), 0.45, Color3.fromRGB(30, 30, 34), M.Rubber, f, DECOR)
    end
    for k = 0, 3 do
        ball("DirtyLaundry", Vector3.new(cx - 0.6 + (k % 2) * 1.2, 3.4, cz - 0.5 + math.floor(k / 2)), 1.2,
            ({ Color3.fromRGB(245, 245, 240), Color3.fromRGB(150, 205, 210), Color3.fromRGB(240, 170, 190), Color3.fromRGB(220, 220, 200) })[k + 1],
            M.Fabric, f, NOSHADOW)
    end
    local front = cpart("LaundryCart", Vector3.new(3, 2.6, 0.15),
        CFrame.lookAt(Vector3.new(cx, 2.5, z1 - 0.075), Vector3.new(cx, 2.5, z1 + 5)), CANVAS, M.Fabric, f)
    signText(front, Enum.NormalId.Front, "LAUNDRY", Color3.fromRGB(230, 236, 245), 30, 1)
    tagHide(front, hides, "Laundry cart", Vector3.new(cx, 3.2, cz))

    ceilingLamp(f, 23, -88.5, COOL, 0.55, 14, false)
end

function VillaBuilder:_staffRoom(f, props)
    -- lockers along the north wall (4 blocks × 2 doors)
    local names = { "MARIA", "JOSÉ", "KEV", "DANA", "LUIS", "ROSA", "TONY", "IVY" }
    for i = 0, 3 do
        local x0 = 29 + i * 3
        local lk = box("Lockers", x0, FLOOR, -95.5, x0 + 2.95, 7.5, -94, Color3.fromRGB(70, 110, 130), M.Metal, f)
        local g = surface(lk, Enum.NormalId.Back, 30, 1, 1)
        for d = 0, 1 do
            local door = frame({ Size = UDim2.fromScale(0.47, 0.96), Position = UDim2.fromScale(0.02 + d * 0.5, 0.02),
                BackgroundColor3 = Color3.fromRGB(84, 128, 150) }, g)
            for v = 0, 3 do
                frame({ Size = UDim2.fromScale(0.6, 0.012), Position = UDim2.fromScale(0.2, 0.08 + v * 0.025),
                    BackgroundColor3 = Color3.fromRGB(40, 60, 72) }, door)
            end
            local tag = frame({ Size = UDim2.fromScale(0.6, 0.05), Position = UDim2.fromScale(0.2, 0.22),
                BackgroundColor3 = Color3.fromRGB(240, 236, 220) }, door)
            text({ Text = names[i * 2 + d + 1], Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
                TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = Color3.fromRGB(40, 40, 44) }, tag)
            frame({ Size = UDim2.fromScale(0.1, 0.06), Position = UDim2.fromScale(0.82, 0.45),
                BackgroundColor3 = STEEL_LITE }, door)
        end
    end
    -- bench in front of the lockers
    box("LockerBench", 31, 1.9, -93.3, 39, 2.2, -92.4, WOOD_MID, M.WoodPlanks, f)
    for _, x in ipairs({ 31.5, 38.5 }) do
        box("LockerBenchLeg", x - 0.15, FLOOR, -93.1, x + 0.15, 1.9, -92.6, STEEL, M.Metal, f)
    end
    -- coat hooks + coats beside the door (east wall, south of the door)
    box("CoatRail", 41.2, 6.2, -84.4, 41.5, 6.45, -81.4, WOOD_DARK, M.Wood, f, DECOR)
    for k, z in ipairs({ -83.8, -82.8, -81.9 }) do
        box("CoatHook", 40.9, 6.1, z - 0.05, 41.2, 6.25, z + 0.05, BRASS, M.Metal, f, DECOR)
        box("Coat", 40.7, 3.6, z - 0.4, 41.2, 6.1, z + 0.4,
            ({ Color3.fromRGB(40, 44, 60), Color3.fromRGB(150, 40, 40), Color3.fromRGB(200, 190, 170) })[k], M.Fabric, f, DECOR)
    end
    -- mop bucket (yellow) with the mop leaning in it
    vcyl("MopBucket", 39.9, FLOOR, 1.8, -83.6, 1.4, Color3.fromRGB(250, 204, 21), M.SmoothPlastic, f)
    box("MopWringer", 39.4, 1.8, -84.0, 40.4, 2.1, -83.2, Color3.fromRGB(60, 60, 64), M.Metal, f, DECOR)
    cpart("MopHandle", Vector3.new(0.18, 5.6, 0.18), CFrame.new(40.4, 3.9, -83.6) * CFrame.Angles(0, 0, math.rad(-12)),
        Color3.fromRGB(180, 150, 110), M.Wood, f, DECOR)
    -- break counter: cabinet + coffee + microwave, and a small fridge
    prop(props, "kitchenCabinet", 30.4, FLOOR, -85.3, PX)
    prop(props, "kitchenCoffeeMachine", 30.4, FLOOR + 3.82, -85.9, PX, 1.0)
    prop(props, "kitchenMicrowave", 30.5, FLOOR + 3.82, -84.2, PX, 1.0)
    prop(props, "kitchenFridgeSmall", 29.5, FLOOR, -81.9, PX, 1.0)
    -- noticeboard on the south wall
    local nb = box("Noticeboard", 29, 5.5, -80.7, 31.8, 8, -80.5, Color3.fromRGB(170, 130, 90), M.Fabric, f)
    local g = surface(nb, Enum.NormalId.Front, 40, 1, 1)
    local notes = { "ROTA", "NO PETS\nIN POOL", "BOSS AWAY\nTIL SUN", "WIFI:\nrosa1958" }
    for i, n in ipairs(notes) do
        local p = frame({ Size = UDim2.fromScale(0.42, 0.4), Position = UDim2.fromScale(0.05 + ((i - 1) % 2) * 0.5, 0.06 + math.floor((i - 1) / 2) * 0.48),
            BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(255, 240, 150) or Color3.fromRGB(245, 245, 240), Rotation = (i % 2 == 0) and 3 or -2 }, g)
        text({ Text = n, Size = UDim2.fromScale(0.9, 0.9), Position = UDim2.fromScale(0.05, 0.05), TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.mono,
            TextColor3 = Color3.fromRGB(40, 40, 44) }, p)
    end
    -- wall clock on the west wall
    disc("Clock", Vector3.new(28.6, 9.5, -83.8), PX, 0.15, 1.6, Color3.fromRGB(245, 245, 240), M.SmoothPlastic, f, DECOR)
    disc("ClockRim", Vector3.new(28.55, 9.5, -83.8), PX, 0.12, 1.8, STEEL, M.Metal, f, DECOR)
    -- warm ceiling light (lived-in, not scary)
    local tube = box("StaffLight", 33, TOP - 0.3, -88.7, 37, TOP - 0.15, -88.3, WARM, M.Neon, f, NOSHADOW)
    pointLight(tube, WARM, 0.8, 16, true)
end

function VillaBuilder:_sideDoor(f, props)
    local x = 42.5   -- outer face of the east wall
    local z0, z1, top = -92, -85, DOOR_TOP
    -- steel frame
    box("DoorFrameN", x, 0, z0 - 0.3, x + 0.25, top + 0.3, z0, STEEL, M.Metal, f)
    box("DoorFrameS", x, 0, z1, x + 0.25, top + 0.3, z1 + 0.3, STEEL, M.Metal, f)
    box("DoorFrameTop", x, top, z0 - 0.3, x + 0.25, top + 0.3, z1 + 0.3, STEEL, M.Metal, f)
    -- double steel doors propped open flat against the outside wall
    box("DoorLeaf", x, FLOOR, -95.8, x + 0.2, top - 0.1, z0 - 0.35, Color3.fromRGB(92, 98, 108), M.DiamondPlate, f)
    box("DoorLeaf", x, FLOOR, z1 + 0.35, x + 0.2, top - 0.1, -81.4, Color3.fromRGB(92, 98, 108), M.DiamondPlate, f)
    box("DoorStep", x, 0, z0, x + 2.5, FLOOR, z1, Color3.fromRGB(120, 116, 110), M.Concrete, f)
    -- awning, STAFF ONLY sign, caged lamp
    box("Awning", x, top + 0.45, z0 - 1, x + 3, top + 0.7, z1 + 1, STEEL, M.Metal, f)
    local plate = box("StaffOnlySign", x, top + 1, z0 + 0.8, x + 0.1, top + 2.2, z1 - 0.8, Color3.fromRGB(26, 26, 30), M.Metal, f)
    signText(plate, Enum.NormalId.Right, "STAFF ONLY", Color3.fromRGB(240, 70, 70), 60, 0)
    local lz = (z0 + z1) / 2
    box("LampCage", x, top + 2.6, lz - 0.45, x + 0.7, top + 3.5, lz + 0.45, STEEL, M.Metal, f, DECOR)
    local lamp = box("DoorLamp", x + 0.1, top + 2.75, lz - 0.3, x + 0.55, top + 3.3, lz + 0.3, Color3.fromRGB(255, 214, 150), M.Neon, f, NOSHADOW)
    pointLight(lamp, Color3.fromRGB(255, 200, 140), 0.9, 14, true)

    -- service yard: concrete pad + a path back to the street
    box("ServicePad", x, 0, -97, 50, 0.12, -79, Color3.fromRGB(130, 128, 122), M.Concrete, f)
    box("ServicePath", 44.5, 0, -79, 48.5, 0.12, -26.8, Color3.fromRGB(150, 146, 138), M.Concrete, f)

    -- wheelie bins (trash + recycling) and a Kenney trash can
    local function bin(bx, bz, color, label)
        box("BinBody", bx - 0.9, 0.3, bz - 1, bx + 0.9, 3.6, bz + 1, color, M.SmoothPlastic, f)
        box("BinLid", bx - 1.0, 3.6, bz - 1.1, bx + 1.0, 3.8, bz + 1.1, color, M.SmoothPlastic, f)
        for _, dz in ipairs({ -0.7, 0.7 }) do
            disc("BinWheel", Vector3.new(bx + 1.0, 0.35, bz + dz), PX, 0.3, 0.7, Color3.fromRGB(24, 24, 26), M.Rubber, f, DECOR)
        end
        local lab = box("BinLabel", bx - 0.8, 2.2, bz + 1, bx + 0.8, 3.0, bz + 1.02, Color3.fromRGB(240, 240, 240), M.SmoothPlastic, f, NOSHADOW)
        signText(lab, Enum.NormalId.Back, label, Color3.fromRGB(30, 30, 34), 40, 1)
    end
    bin(45.2, -95.3, Color3.fromRGB(40, 110, 60), "TRASH")
    bin(47.6, -95.3, Color3.fromRGB(40, 90, 180), "RECYCLE")
    bin(45.2, -81.2, Color3.fromRGB(40, 90, 180), "RECYCLE")
    prop(props, "trashcan", 48, 0.12, -81.5)
    prop(props, "cardboardBoxOpen", 48.2, 0.12, -84.5)
    -- AC condenser against the wall outside the corridor
    box("ACUnit", 42.5, 0, -70, 44.3, 3, -66.5, Color3.fromRGB(200, 200, 196), M.Metal, f)
    disc("ACFan", Vector3.new(44.35, 1.6, -68.25), PX, 0.1, 2.2, Color3.fromRGB(40, 40, 44), M.Metal, f, DECOR)
end

-- ──────────────────────────────────────────────
-- 🪜 ROOF: ladder (west wall), AC units, vent stacks
-- ──────────────────────────────────────────────
function VillaBuilder:_roof(f)
    -- the ladder: a TrussPart (Roblox players read a truss as "climb me")
    local truss = Instance.new("TrussPart")
    truss.Name = "RoofLadder"
    truss.Size = Vector3.new(2, 20, 2)
    truss.CFrame = CFrame.new(-43.7, 10, -84)
    truss.Anchored = true
    truss.Style = Enum.Style.NoSupports
    truss.Material = M.Metal
    truss.Color = STEEL_LITE
    truss.Parent = f
    for _, y in ipairs({ 3, 10, 16 }) do
        box("LadderBracket", -42.7, y, -85.2, -42.5, y + 0.3, -82.8, STEEL, M.Metal, f, DECOR)
    end
    -- grab-rail posts at the top, either side of the parapet gap
    for _, z in ipairs({ -86.2, -81.8 }) do
        vcyl("GrabRail", -42, ROOF, ROOF + 3.2, z, 0.25, HATCH, M.Metal, f)
    end
    -- a hedge partly hides the bottom of the ladder (it's the secret way in)
    ball("LadderBush", Vector3.new(-45.5, 1.2, -86.8), 3, LEAF, M.Grass, f, DECOR)
    ball("LadderBush", Vector3.new(-45.2, 1.0, -81.4), 2.4, LEAF, M.Grass, f, DECOR)

    -- rooftop clutter so it reads as a real roof
    for _, p in ipairs({ { 18, -64 }, { 26, -64 } }) do
        box("RoofAC", p[1] - 2, ROOF, p[2] - 2, p[1] + 2, ROOF + 2.8, p[2] + 2, Color3.fromRGB(196, 196, 192), M.Metal, f)
        disc("RoofACFan", Vector3.new(p[1], ROOF + 2.85, p[2]), Vector3.new(0, 1, 0), 0.1, 3, Color3.fromRGB(40, 40, 44), M.Metal, f, DECOR)
    end
    for _, p in ipairs({ { 30, -86 }, { 33, -86 }, { -30, -60 } }) do
        vcyl("VentStack", p[1], ROOF, ROOF + 2.5, p[2], 0.7, STEEL_LITE, M.Metal, f)
        vcyl("VentCap", p[1], ROOF + 2.5, ROOF + 2.8, p[2], 1.1, STEEL_LITE, M.Metal, f, DECOR)
    end
    box("RoofSkylightFrame", -8, ROOF, -54, 8, ROOF + 0.4, -42, STEEL, M.Metal, f)
    box("RoofSkylight", -7.6, ROOF + 0.4, -53.6, 7.6, ROOF + 0.5, -42.4, Color3.fromRGB(150, 190, 210), M.Glass, f, { Transparency = 0.3 })
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
        -- C1: grand hall, high in the NW corner, watching the FRONT DOOR
        securityCamera(f, "Camera_Hall", Vector3.new(-13.5, 13, -56.8), PX,
            Vector3.new(-12.5, 12.4, -56.3), Vector3.new(0, 1.5, -40), 60, 7),
        -- C2: above the vault door, looking down the laser corridor
        securityCamera(f, "Camera_Corridor", Vector3.new(0, 11.3, -81.5), PZ,
            Vector3.new(0, 10.7, -80.5), Vector3.new(0, 1.5, -71), 40, 7),
        -- C3: west end of the gallery corridor, sweeping toward the office + bedroom doors
        securityCamera(f, "Camera_Gallery", Vector3.new(-41.5, 13, -64), PX,
            Vector3.new(-40.5, 12.4, -64), Vector3.new(-20, 1.5, -64), 50, 8),
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
    local lootSpots = {}
    local hideSpots = {}
    local shadowZones = {}
    local facadeRefs = {}

    self:_shell(sub(root, "Shell"))
    self:_facade(sub(root, "Facade"), facadeRefs)
    self:_garden(sub(root, "Garden"))
    self:_terrace(sub(root, "Terrace"))
    self:_hall(sub(root, "GrandHall"), props, keycardSpots, hideSpots)
    self:_office(sub(root, "Office"), props, keycardSpots, lootSpots)
    self:_kitchen(sub(root, "Kitchen"), props, keycardSpots, lootSpots)
    self:_corridor(sub(root, "Gallery"), props, lootSpots, hideSpots)
    local keycardDoor = self:_keycardDoor(sub(root, "KeycardDoor"))
    local laserRows = self:_lasers(sub(root, "Lasers"))
    local vault = self:_vault(sub(root, "Vault"))
    for _, l in ipairs(self:_vaultLoot(sub(root, "Loot"))) do table.insert(lootSpots, l) end
    self:_bedroom(sub(root, "Bedroom"), props, keycardSpots, lootSpots)
    local closetF = sub(root, "Closet")
    self:_closet(closetF, keycardSpots, hideSpots)
    prop(props, "rugRound", -11.5, FLOOR, -75.5, nil, 0.9)
    local roofF = sub(root, "Roof")
    local roofVent = self:_roofHatch(closetF, roofF)
    local crawlVent = self:_crawlVent(sub(root, "Vents"))
    local breaker = self:_security(sub(root, "Security"), props)
    local serviceF = sub(root, "Service")
    self:_serviceHall(serviceF, props)
    self:_laundry(serviceF, props, hideSpots)
    self:_staffRoom(sub(root, "StaffRoom"), props)
    self:_sideDoor(sub(root, "SideDoor"), props)
    self:_roof(roofF)
    local cameras = self:_cameras(sub(root, "Cameras"))

    -- dark corners + unlit corridor ends (no lamp reaches these)
    local sz = sub(root, "ShadowZones")
    shadowZone(sz, shadowZones, "Shadow_CorridorWest", -41.5, -69.5, -33, -58.5)
    shadowZone(sz, shadowZones, "Shadow_CorridorEast", 33, -69.5, 41.5, -58.5)
    shadowZone(sz, shadowZones, "Shadow_BedroomNW", -41.5, -95.5, -34, -88.8)
    shadowZone(sz, shadowZones, "Shadow_OfficeSE", -20, -43.5, -14.5, -38.5)
    shadowZone(sz, shadowZones, "Shadow_Pantry", 33.5, -55.3, 41.5, -52)

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

    print("[VillaBuilder] Villa Rosa v2 built 🌴")

    return {
        id = "villa",
        root = root,
        entryPoint = Vector3.new(0, 3, -34),
        -- v2: the crew drops in INSIDE the staff room, just past the STAFF ONLY
        -- side door (east wall). No guard route and no camera covers this room.
        sneakIn = { at = Vector3.new(36, 3, -88.5), face = Vector3.new(28, 3, -88.5), spread = Vector3.new(0, 0, 0.75) },
        entrances = {
            { kind = "front", at = Vector3.new(0, 3, -34), label = "Front door" },
            { kind = "side", at = Vector3.new(46, 3, -88.5), label = "Staff door" },
            { kind = "roof", at = Vector3.new(-46.5, 3, -84), label = "Roof ladder" },
        },
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
        hideSpots = hideSpots,
        shadowZones = shadowZones,
        vents = { crawlVent, roofVent },
        guardRoutes = {
            -- hall: walks across in front of the arch, turns at the side doors
            { name = "Guard_A", spawn = Vector3.new(-9, 3, -47), a = Vector3.new(-9, 3, -47), b = Vector3.new(9, 3, -47) },
            -- gallery corridor: past the keycard door; turns before the service door
            { name = "Guard_B", spawn = Vector3.new(-20, 3, -64), a = Vector3.new(-20, 3, -64), b = Vector3.new(28, 3, -64) },
            -- west wing: office → across the corridor → bedroom, through both doors
            { name = "Guard_C", spawn = Vector3.new(-28, 3, -44), a = Vector3.new(-28, 3, -44), b = Vector3.new(-28, 3, -86) },
        },
        plan = {
            bounds = { -42, -96, 42, -38 },
            rooms = {
                { -14, -58, 14, -38, "HALL" },
                { -42, -58, -14, -38, "OFFICE" },
                { 14, -58, 42, -38, "KITCHEN" },
                { -42, -70, 42, -58, "GALLERY" },
                { -42, -96, -18, -70, "BEDROOM" },
                { -18, -82, -6, -70, "CLOSET" },
                { -6, -82, 6, -70, "LASERS" },
                { 6, -82, 18, -70, "SECURITY" },
                { 18, -80, 42, -70, "SERVICE" },
                { 18, -96, 28, -80, "LAUNDRY" },
                { 28, -96, 42, -80, "STAFF" },
                { -18, -96, 18, -82, "VAULT" },
            },
            vault = { 0, -89 },
            entry = { 0, -38 },
        },
    }
end

return VillaBuilder
