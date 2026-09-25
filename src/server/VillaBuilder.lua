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

    v2.1 ART PASS (2026-09-25, from Malachi's Future-lighting playtest video):
      • THE GROUNDS: the villa sits inside an 11-tall garden wall + iron
        railings (x -50.9..54, z -103..-26.8, inside MiamiBuilder.KEEP_CLEAR),
        a closed front gate, and invisible ClimbGuards on every wall top. The
        only way out is the SERVICE YARD (east, outside the staff door) and its
        open VEHICLE GATE x 42.6..50.2 at z -27.2 onto Ocean Drive.
      • getawayCFrame = (45.6, 0, -72) facing +Z (south): parked in the yard,
        nose at the gate, a straight clear run down the driveway lane.
      • every room has its own wallpaper / dado / skirting (_paintWalls:
        SurfaceGui colour on each wall face + thin relief parts), patterned
        floors, clean painted door trim (no more stripy wood grain),
        per-room lighting (warm vs cool, shadowed key lamps, moonlight in the
        bedroom), and Kenney props recoloured on arrival (tintProp).

    v3.0 "THE SCORE" LOOT (2026-09-25, docs/V3_SPEC.md §2) — no more loose
    cash on tables. refs.lootSpots is lootSpots v3; pool = room:
      hall     2 Painting (cut) either side of the front door (under Camera_Hall)
      gallery  5 Painting (cut): 4 on the walls + the unframed canvas on the easel
      office   2 GoldRecord (framed, over the hi-fi console) · 1 Painting (cut,
               dark SE corner) · SecretStash (hidden): wall safe behind the
               painting over the sideboard — the painting swings open
      cellar   3 Wine (fragile): RESERVE niches in the pantry wine wall (kitchen NE)
      bedroom  JewelryBox (dial) in the green floor safe · 1 Painting (cut) ·
               SecretStash (hidden): floor safe under the rug by the closet
      vault    3 Cash (shrink-wrapped pallets) · 2 GoldBars (heavy) · Diamonds
               (velvet tray) · 🦩 GoldFlamingo — THE TARGET (heavy, target =
               "GoldFlamingo") on a spot-lit plinth dead centre, facing the door
      "cut" leaves the empty gilt frame on the wall (visual = the canvas only).
      Hidden stashes build INVISIBLE; spot.reveal(true/false) shows the stash
      and its cover (painting swing / rug fold). refs.poolNames names each room.

    THE THREE WAYS IN (refs.entrances)
        front  — the obvious one. Camera_Hall watches it, Guard A walks the hall.
        side   — STAFF ONLY door on the east wall (opens onto the service yard)
                 → staff room (= sneakIn). No guard route and no camera covers
                 the staff room or the door.
        roof   — steel ladder (a climbable TrussPart) on the WEST wall at z -84
                 (in the walled west garden strip) →
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
-- v2.1 art pass
local WALNUT     = Color3.fromRGB(88, 56, 38)
local WALNUT_DK  = Color3.fromRGB(52, 34, 24)
local IRON       = Color3.fromRGB(28, 30, 34)
local WALL_PINK  = Color3.fromRGB(226, 170, 176)     -- garden wall stucco (a shade deeper than the villa)
local MOON       = Color3.fromRGB(130, 160, 230)
local LAMP_WARM  = Color3.fromRGB(255, 190, 120)     -- table / floor lamps: warmer + more orange than WARM
local YARD_LIGHT = Color3.fromRGB(255, 214, 160)

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

-- Every wall segment wallRun makes is recorded here (v2.1) so _paintWalls can
-- give each room its own wallpaper / dado / skirting on its side of the wall.
-- Reset at the start of every build.
local SEGMENTS = {}

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
            local p = abox(nm or name, axis, c, a0, y0, a1, y1, 1, color, mat, parent)
            if not opts.noPaint then
                table.insert(SEGMENTS, { part = p, axis = axis, c = c, a0 = a0, a1 = a1, y0 = y0, y1 = y1 })
            end
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
            -- v2.1: clean painted trim. (Wood grain on a 0.35-wide strip rendered as
            -- glitchy stripes in Malachi's video.) 1.7 thick so it caps the skirting.
            local trim = opts.trim or TRIM
            local ct = 0.45
            abox("Casing", axis, c, a0 - ct, FLOOR, a0, y1 + ct, 1.7, trim, M.Plaster, parent)
            abox("Casing", axis, c, a1, FLOOR, a1 + ct, y1 + ct, 1.7, trim, M.Plaster, parent)
            abox("Casing", axis, c, a0 - ct, y1, a1 + ct, y1 + ct, 1.7, trim, M.Plaster, parent)
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

-- ── v3 PAINTED CANVASES ────────────────────────────────────────────────
-- Every painting is a gilt frame + backing board (static) and a separate
-- canvas Model (the loot visual: "cut" takes the canvas, the empty frame
-- stays on the wall). The picture is drawn with Frames + UIGradients — no
-- image assets. Five styles, all seeded, so a wall never repeats:
--   sunset (Miami seascape + palm) · fields (soft colour blocks)
--   grid (primary-colour lines) · orbits (circles on dark) · waves
-- pos = point on the wall surface, normal = direction out of the wall into the room
local ART_PALETTES = {
    { Color3.fromRGB(242, 160, 190), Color3.fromRGB(40, 60, 110), Color3.fromRGB(250, 200, 90), Color3.fromRGB(40, 190, 200) },
    { Color3.fromRGB(28, 34, 58), Color3.fromRGB(255, 90, 170), Color3.fromRGB(80, 220, 230), Color3.fromRGB(245, 235, 220) },
    { Color3.fromRGB(245, 232, 210), Color3.fromRGB(220, 80, 60), Color3.fromRGB(30, 30, 36), Color3.fromRGB(60, 150, 140) },
    { Color3.fromRGB(64, 150, 150), Color3.fromRGB(250, 210, 170), Color3.fromRGB(190, 90, 150), Color3.fromRGB(20, 40, 60) },
    { Color3.fromRGB(180, 150, 230), Color3.fromRGB(250, 240, 150), Color3.fromRGB(240, 110, 120), Color3.fromRGB(40, 36, 70) },
}
local ART_STYLES = { "sunset", "fields", "grid", "orbits", "waves" }
local GILT    = Color3.fromRGB(184, 146, 72)
local GILT_DK = Color3.fromRGB(120, 90, 44)
local WHITE   = Color3.new(1, 1, 1)
local BLACK   = Color3.new(0, 0, 0)

local function gradient(parent, colors, rotation, transparency)
    local g = Instance.new("UIGradient")
    local kps = {}
    for i, c in ipairs(colors) do
        table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
    end
    g.Color = ColorSequence.new(kps)
    g.Rotation = rotation or 90
    if transparency then g.Transparency = transparency end
    g.Parent = parent
    return g
end

local function nseq(points)
    local kps = {}
    for _, p in ipairs(points) do table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2])) end
    return NumberSequence.new(kps)
end

-- draws one picture into SurfaceGui g. aspect = height / width of the canvas.
local function paintArt(g, style, seed, aspect)
    local rng = Random.new(seed)
    local pal = ART_PALETTES[(seed % #ART_PALETTES) + 1]
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = pal[1], ClipsDescendants = true }, g)
    local function blob(x, y, w, h, color, z, extra)
        local b = frame({ Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), BackgroundColor3 = color, ZIndex = z or 2 }, bg)
        for k, v in pairs(extra or {}) do b[k] = v end
        return b
    end
    local MID = Vector2.new(0.5, 0.5)

    if style == "sunset" then
        local horizon = rng:NextNumber(0.56, 0.66)
        local sky = blob(0, 0, 1, horizon, WHITE, 1)
        gradient(sky, { Color3.fromRGB(46, 34, 90), Color3.fromRGB(200, 76, 128), Color3.fromRGB(252, 164, 92) }, 90)
        local sx, sd = rng:NextNumber(0.35, 0.65), rng:NextNumber(0.26, 0.36)
        local sun = blob(sx, horizon, sd, sd / aspect, WHITE, 2, { AnchorPoint = MID })
        round(sun)
        gradient(sun, { Color3.fromRGB(255, 238, 160), Color3.fromRGB(255, 120, 76) }, 90)
        local sea = blob(0, horizon, 1, 1 - horizon, WHITE, 3)
        gradient(sea, { Color3.fromRGB(44, 96, 128), Color3.fromRGB(14, 26, 52) }, 90)
        for i = 0, 5 do   -- the sun's glitter path on the water
            blob(sx, horizon + 0.03 + i * 0.05, sd * (0.9 - i * 0.13), 0.012, Color3.fromRGB(255, 196, 128), 4,
                { AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 0.2 + i * 0.12 })
        end
        for _ = 1, 4 do   -- wispy clouds
            blob(rng:NextNumber(-0.1, 0.6), rng:NextNumber(0.1, horizon - 0.18), rng:NextNumber(0.25, 0.5), 0.016,
                Color3.fromRGB(255, 206, 196), 2, { BackgroundTransparency = 0.45 })
        end
        -- a palm silhouette leaning in from one side
        local left = rng:NextNumber() < 0.5
        local px = left and 0.17 or 0.83
        local SIL = Color3.fromRGB(24, 16, 32)
        blob(px, 0.66, 0.028, 0.72, SIL, 5, { AnchorPoint = MID, Rotation = left and 7 or -7 })
        local tx, ty = px + (left and 0.04 or -0.04), 0.3
        for _, r in ipairs({ -32, 28, -62, 58, 4 }) do
            blob(tx, ty, 0.34, 0.022, SIL, 5, { AnchorPoint = MID, Rotation = r })
        end
        blob(0, 0.985, 1, 0.015, SIL, 5)
    elseif style == "fields" then
        bg.BackgroundColor3 = pal[4]:Lerp(BLACK, 0.35)
        local n = rng:NextInteger(2, 3)
        local gap = 0.06
        local bh = (1 - gap * (n + 1)) / n
        for i = 0, n - 1 do
            local c = pal[((i + seed) % 3) + 1]
            local b = blob(0.07, gap + i * (bh + gap), 0.86, bh, WHITE, 2 + i)
            gradient(b, { c, c:Lerp(BLACK, 0.18) }, 90, nseq({ { 0, 0.4 }, { 0.1, 0.02 }, { 0.9, 0.02 }, { 1, 0.4 } }))
            local cr = Instance.new("UICorner")
            cr.CornerRadius = UDim.new(0.06, 0)
            cr.Parent = b
        end
    elseif style == "grid" then
        bg.BackgroundColor3 = Color3.fromRGB(240, 234, 220)
        local xs = { 0, rng:NextNumber(0.2, 0.4), rng:NextNumber(0.55, 0.8), 1 }
        local ys = { 0, rng:NextNumber(0.18, 0.4), rng:NextNumber(0.55, 0.8), 1 }
        local fills = { Color3.fromRGB(206, 44, 40), Color3.fromRGB(30, 60, 150), Color3.fromRGB(246, 200, 40) }
        for k = 1, 3 do
            local i, j = rng:NextInteger(1, 3), rng:NextInteger(1, 3)
            blob(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j], fills[k], 2)
        end
        local t = 0.028
        for i = 2, 3 do
            blob(xs[i] - t / 2, 0, t, 1, Color3.fromRGB(22, 22, 26), 4)
            blob(0, ys[i] - t / aspect / 2, 1, t / aspect, Color3.fromRGB(22, 22, 26), 4)
        end
    elseif style == "orbits" then
        bg.BackgroundColor3 = WHITE
        gradient(bg, { Color3.fromRGB(20, 22, 48), Color3.fromRGB(58, 30, 70) }, 120)
        for i = 1, 6 do
            local d = rng:NextNumber(0.12, 0.42)
            local c = blob(rng:NextNumber(0.15, 0.85), rng:NextNumber(0.15, 0.85), d, d / aspect, WHITE, 2 + i, { AnchorPoint = MID })
            round(c)
            if i % 3 == 0 then   -- a bare ring
                c.BackgroundTransparency = 1
                local s = Instance.new("UIStroke")
                s.Color = pal[(i % 4) + 1]
                s.Thickness = 3
                s.Parent = c
            else
                c.BackgroundTransparency = 0.08
                gradient(c, { pal[(i % 4) + 1], pal[((i + 1) % 4) + 1] }, rng:NextNumber(0, 180))
            end
        end
        for _ = 1, 3 do
            blob(rng:NextNumber(0.3, 0.7), rng:NextNumber(0.3, 0.7), rng:NextNumber(0.5, 0.9), 0.01,
                Color3.fromRGB(236, 230, 214), 10, { AnchorPoint = MID, Rotation = rng:NextNumber(-70, 70) })
        end
    else -- waves
        bg.BackgroundColor3 = WHITE
        gradient(bg, { Color3.fromRGB(246, 228, 200), Color3.fromRGB(236, 196, 170) }, 90)
        local sun = blob(rng:NextNumber(0.6, 0.8), 0.2, 0.16, 0.16 / aspect, Color3.fromRGB(214, 70, 60), 2, { AnchorPoint = MID })
        round(sun)
        local blues = { Color3.fromRGB(70, 130, 170), Color3.fromRGB(34, 80, 128), Color3.fromRGB(18, 44, 84) }
        for row = 1, 3 do
            local y = 0.35 + row * 0.16
            for k = 0, 3 do
                local w = blob(-0.12 + k * 0.36 + (row % 2) * 0.16, y, 0.46, 0.5 / aspect, blues[row], 2 + row, { AnchorPoint = Vector2.new(0, 0) })
                round(w)
                local s = Instance.new("UIStroke")
                s.Color = Color3.fromRGB(244, 240, 228)
                s.Thickness = 2
                s.Transparency = 0.15
                s.Parent = w
            end
        end
    end

    -- varnish + canvas: soft vignette, a few lighter brush drags
    local v1 = blob(0, 0, 1, 1, BLACK, 20)
    gradient(v1, { BLACK, BLACK }, 0, nseq({ { 0, 0.55 }, { 0.18, 1 }, { 0.82, 1 }, { 1, 0.55 } }))
    local v2 = blob(0, 0, 1, 1, BLACK, 20)
    gradient(v2, { BLACK, BLACK }, 90, nseq({ { 0, 0.6 }, { 0.2, 1 }, { 0.8, 1 }, { 1, 0.5 } }))
    for _ = 1, 6 do
        blob(rng:NextNumber(0, 0.7), rng:NextNumber(0.05, 0.95), rng:NextNumber(0.15, 0.4), 0.006, WHITE, 21,
            { BackgroundTransparency = 0.86, Rotation = rng:NextNumber(-6, 6) })
    end
end

-- painting(parent, pos, normal, w, h, seed, opts) -> canvas Model
--   opts.frame = false  : bare stretched canvas (the easel) — no frame/backing
--   opts.style          : force a style (else picked from the seed)
--   opts.canvasParent   : where the canvas Model goes (default parent)
local function painting(parent, pos, normal, w, h, seed, opts)
    opts = opts or {}
    local cf = CFrame.lookAt(pos, pos + normal)
    if opts.frame ~= false then
        -- backing board: what's left on the wall once the canvas is cut out
        cpart("PaintingBacking", Vector3.new(w + 0.05, h + 0.05, 0.08), cf * CFrame.new(0, 0, -0.05),
            Color3.fromRGB(56, 44, 34), M.Wood, parent, NOSHADOW)
        local fw = math.clamp(math.min(w, h) * 0.09, 0.28, 0.46)
        local rails = {
            { 0, (h + fw) / 2, w + 2 * fw, fw }, { 0, -(h + fw) / 2, w + 2 * fw, fw },
            { -(w + fw) / 2, 0, fw, h }, { (w + fw) / 2, 0, fw, h },
        }
        for _, r in ipairs(rails) do
            cpart("PaintingFrame", Vector3.new(r[3], r[4], 0.34), cf * CFrame.new(r[1], r[2], -0.17), GILT, M.Metal, parent,
                merge(DECOR, { Reflectance = 0.06 }))
        end
        -- inner lip: a darker gilt bead, a step proud of the canvas
        local lp = 0.1
        local lips = {
            { 0, (h - lp) / 2, w, lp }, { 0, -(h - lp) / 2, w, lp },
            { -(w - lp) / 2, 0, lp, h - 2 * lp }, { (w - lp) / 2, 0, lp, h - 2 * lp },
        }
        for _, r in ipairs(lips) do
            cpart("PaintingLip", Vector3.new(r[3], r[4], 0.1), cf * CFrame.new(r[1], r[2], -0.2), GILT_DK, M.Metal, parent, NOSHADOW)
        end
    end
    local m = Instance.new("Model")
    m.Name = "PaintingCanvas"
    local depth = (opts.frame == false) and 0.12 or 0.05
    local canvas = cpart("Canvas", Vector3.new(w, h, depth), cf * CFrame.new(0, 0, -(0.11 + depth / 2)),
        Color3.fromRGB(240, 236, 228), M.Fabric, m, NOSHADOW)
    -- LightInfluence 1: art sits in the dark like everything else and only
    -- reads where a lamp reaches it
    local g = surface(canvas, Enum.NormalId.Front, 30, 1, 1)
    paintArt(g, opts.style or ART_STYLES[(seed % #ART_STYLES) + 1], seed, h / w)
    m.PrimaryPart = canvas
    m.Parent = opts.canvasParent or parent
    return m
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
    { -42, -96, -18, -70, Color3.fromRGB(118, 96, 104), M.Carpet, "Bedroom" },
    { -18, -82, -6, -70, Color3.fromRGB(150, 112, 80), M.WoodPlanks, "Closet" },
    { -6, -82, 6, -70, Color3.fromRGB(80, 84, 92), M.DiamondPlate, "Lasers" },
    { 6, -82, 18, -70, Color3.fromRGB(48, 50, 56), M.Slate, "Security" },
    { 18, -80, 42, -70, Color3.fromRGB(128, 126, 120), M.Concrete, "Service" },
    { 18, -96, 28, -80, Color3.fromRGB(200, 214, 220), M.CeramicTiles, "Laundry" },
    { 28, -96, 42, -80, Color3.fromRGB(150, 158, 140), M.CeramicTiles, "Staff" },
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
        win(-36, -32), win(-24, -20),                                -- office
        win(-12.8, -9.4), win(9.4, 12.8),                            -- hall
        win(20, 24), win(32, 36),                                    -- kitchen
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
-- 🎨 v2.1 ROOM FINISHES — Malachi: "the graphics are very simple". Every room
-- used to be the same peach plaster (and the outer rooms the pink stucco of
-- the outside). Now each room gets its own wallpaper (+ stripes), a dado
-- (panelled / tiled / painted lower wall) and real skirting + chair rail.
--
-- The colour is a SurfaceGui on the wall part's face (zero extra parts); the
-- skirting and rail are thin non-collide parts so the wall has relief.
-- GUI X runs toward the viewer's right: Back(+Z)→+X, Front(-Z)→-X,
-- Right(+X)→-Z, Left(-X)→+Z. That's what `flip` below encodes.
-- ──────────────────────────────────────────────
local DADO_TOP = FLOOR + 3.1      -- y 3.6: below every window sill, so windows never cut the dado

local STYLES = {
    Hall = { paper = Color3.fromRGB(232, 222, 200), stripe = Color3.fromRGB(214, 194, 150), every = 1.8, sw = 0.22,
        dado = Color3.fromRGB(206, 198, 186), kind = "panel", rail = GOLD, railMat = M.Metal, base = MARBLE_DK, baseMat = M.Marble },
    Office = { paper = Color3.fromRGB(44, 70, 56), stripe = Color3.fromRGB(52, 80, 64), every = 1.2, sw = 0.5,
        dado = WALNUT, kind = "panel", rail = WALNUT_DK, railMat = M.WoodPlanks, base = WALNUT_DK, baseMat = M.WoodPlanks },
    Kitchen = { paper = Color3.fromRGB(214, 230, 222),
        dado = Color3.fromRGB(242, 242, 236), kind = "tile", grout = Color3.fromRGB(190, 196, 196),
        base = Color3.fromRGB(40, 70, 72), baseMat = M.Plaster },
    Corridor = { paper = Color3.fromRGB(30, 66, 72),
        dado = Color3.fromRGB(40, 40, 46), kind = "panel", rail = BRASS, railMat = M.Metal, base = Color3.fromRGB(26, 26, 30), baseMat = M.Marble },
    Bedroom = { paper = Color3.fromRGB(206, 160, 168), stripe = Color3.fromRGB(236, 214, 206), every = 1.5, sw = 0.16,
        dado = Color3.fromRGB(236, 228, 218), kind = "panel", rail = TRIM, railMat = M.Plaster, base = TRIM, baseMat = M.Plaster },
    Closet = { paper = Color3.fromRGB(228, 214, 190), base = WOOD_MID, baseMat = M.WoodPlanks },
    Security = { paper = Color3.fromRGB(58, 62, 72), dado = Color3.fromRGB(40, 43, 50), kind = "paint",
        base = Color3.fromRGB(26, 28, 32), baseMat = M.Rubber },
    Service = { paper = Color3.fromRGB(176, 176, 166), dado = Color3.fromRGB(104, 110, 104), kind = "paint",
        base = Color3.fromRGB(52, 54, 56), baseMat = M.Rubber },
    Laundry = { paper = Color3.fromRGB(196, 216, 224), dado = Color3.fromRGB(240, 244, 244), kind = "tile",
        grout = Color3.fromRGB(170, 190, 198), base = Color3.fromRGB(90, 110, 120), baseMat = M.Rubber },
    Staff = { paper = Color3.fromRGB(222, 212, 184), dado = Color3.fromRGB(96, 128, 112), kind = "paint",
        base = Color3.fromRGB(50, 56, 52), baseMat = M.Rubber },
    -- Lasers + Vault keep their bare steel (no entry = untouched)
}

local function roomAt(x, z)
    for _, r in ipairs(ROOMS) do
        if x > r[1] and x < r[3] and z > r[2] and z < r[4] then return r end
    end
    return nil
end

function VillaBuilder:_paintWalls(f)
    local E = 0.01
    for _, seg in ipairs(SEGMENTS) do
        local L, H = seg.a1 - seg.a0, seg.y1 - seg.y0
        for _, side in ipairs({ -1, 1 }) do
            -- split the segment's span at room edges and find the room on this side
            local cuts = { seg.a0, seg.a1 }
            for _, r in ipairs(ROOMS) do
                local e0, e1 = (seg.axis == "x") and r[1] or r[2], (seg.axis == "x") and r[3] or r[4]
                for _, e in ipairs({ e0, e1 }) do
                    if e > seg.a0 + E and e < seg.a1 - E then table.insert(cuts, e) end
                end
            end
            table.sort(cuts)
            local pieces = {}
            for i = 1, #cuts - 1 do
                local a0, a1 = cuts[i], cuts[i + 1]
                if a1 - a0 > E then
                    local m = (a0 + a1) / 2
                    local off = seg.c + side * 0.75
                    local r = (seg.axis == "x") and roomAt(m, off) or roomAt(off, m)
                    local st = r and STYLES[r[7]]
                    if st then
                        local last = pieces[#pieces]
                        if last and last.room == r and math.abs(last.a1 - a0) < E then
                            last.a1 = a1
                        else
                            table.insert(pieces, { a0 = a0, a1 = a1, room = r, style = st })
                        end
                    end
                end
            end

            if #pieces > 0 then
                local face, flip
                if seg.axis == "x" then
                    face, flip = (side > 0) and Enum.NormalId.Back or Enum.NormalId.Front, side < 0
                else
                    face, flip = (side > 0) and Enum.NormalId.Right or Enum.NormalId.Left, side > 0
                end
                local g = surface(seg.part, face, 8, 1, 1)
                g.Name = "RoomFinish"
                for _, pc in ipairs(pieces) do
                    local st = pc.style
                    local u0, u1 = (pc.a0 - seg.a0) / L, (pc.a1 - seg.a0) / L
                    if flip then u0, u1 = 1 - u1, 1 - u0 end
                    local plen = pc.a1 - pc.a0
                    local holder = frame({ Position = UDim2.fromScale(u0, 0), Size = UDim2.fromScale(u1 - u0, 1),
                        BackgroundColor3 = st.paper, BackgroundTransparency = 0.04, ClipsDescendants = true, ZIndex = 1 }, g)
                    -- wallpaper stripes (only where there's paper above the dado)
                    if st.stripe and seg.y1 > DADO_TOP then
                        local n = math.floor(plen / st.every)
                        for i = 0, n do
                            local a = i * st.every + (st.every - st.sw) / 2
                            frame({ Position = UDim2.fromScale(a / plen, 0), Size = UDim2.fromScale(st.sw / plen, 1),
                                BackgroundColor3 = st.stripe, ZIndex = 2 }, holder)
                        end
                    end
                    -- the dado: panelled / tiled / painted lower wall
                    if st.dado and seg.y0 < DADO_TOP - E then
                        local top = math.min(seg.y1, DADO_TOP)
                        local vTop = (seg.y1 - top) / H
                        local dh = top - seg.y0
                        local d = frame({ Position = UDim2.fromScale(0, vTop), Size = UDim2.fromScale(1, 1 - vTop),
                            BackgroundColor3 = st.dado, ZIndex = 3, ClipsDescendants = true }, holder)
                        if st.kind == "panel" and dh > 1.4 then
                            local n = math.max(1, math.floor(plen / 2.6))
                            local w = plen / n
                            local inset = st.dado:Lerp(Color3.new(0, 0, 0), 0.14)
                            for i = 0, n - 1 do
                                frame({ Position = UDim2.fromScale((i * w + 0.35) / plen, 0.22), Size = UDim2.fromScale((w - 0.7) / plen, 0.56),
                                    BackgroundColor3 = inset, ZIndex = 4 }, d)
                            end
                        elseif st.kind == "tile" then
                            local rows = math.floor(dh / 0.55)
                            for i = 1, rows do
                                frame({ Position = UDim2.fromScale(0, 1 - (i * 0.55) / dh), Size = UDim2.new(1, 0, 0, 1),
                                    BackgroundColor3 = st.grout, ZIndex = 4 }, d)
                            end
                            local cols = math.floor(plen / 1.1)
                            for i = 1, cols do
                                frame({ Position = UDim2.fromScale((i * 1.1) / plen, 0), Size = UDim2.new(0, 1, 1, 0),
                                    BackgroundColor3 = st.grout, ZIndex = 4 }, d)
                            end
                        end
                    end

                    -- relief: skirting + chair rail, clipped to the room's interior
                    local r = pc.room
                    local i0 = ((seg.axis == "x") and r[1] or r[2]) + 0.5
                    local i1 = ((seg.axis == "x") and r[3] or r[4]) - 0.5
                    local b0, b1 = math.max(pc.a0, i0), math.min(pc.a1, i1)
                    if b1 - b0 > 0.3 and seg.y0 <= FLOOR + E then
                        local rel = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
                        abox("Skirting", seg.axis, seg.c + side * 0.6, b0, FLOOR, b1, FLOOR + 0.55, 0.2,
                            st.base, st.baseMat or M.Plaster, f, rel)
                        if st.rail and seg.y1 >= DADO_TOP + 0.2 then
                            abox("ChairRail", seg.axis, seg.c + side * 0.58, b0, DADO_TOP - 0.12, b1, DADO_TOP + 0.12, 0.16,
                                st.rail, st.railMat or M.Plaster, f, rel)
                        end
                    end
                end
            end
        end
    end
end

-- ── floors with pattern (v2.1): kitchen checkerboard, hall inlay border ──
function VillaBuilder:_floorDetail(f)
    -- kitchen: black + white checkerboard (drawn on a thin top sheet, 2-stud tiles)
    local kx0, kz0, kx1, kz1 = 14.5, -57.5, 41.5, -38.5
    local sheet = box("KitchenChecker", kx0, FLOOR, kz0, kx1, FLOOR + 0.02, kz1, Color3.fromRGB(236, 234, 228), M.CeramicTiles, f, NOSHADOW)
    sheet.CanQuery = false
    local g = surface(sheet, Enum.NormalId.Top, 6, 1, 1)
    local nx, nz = math.floor((kx1 - kx0) / 2.25), math.floor((kz1 - kz0) / 2.25)
    for i = 0, nx - 1 do
        for j = 0, nz - 1 do
            if (i + j) % 2 == 0 then
                frame({ Position = UDim2.fromScale(i / nx, j / nz), Size = UDim2.fromScale(1 / nx, 1 / nz),
                    BackgroundColor3 = Color3.fromRGB(34, 34, 38), BackgroundTransparency = 0.05 }, g)
            end
        end
    end
    -- hall: dark marble border band + a brass compass star under the chandelier
    local hx0, hz0, hx1, hz1 = -13.5, -57.5, 13.5, -38.5
    local bw = 1.2
    local B = MARBLE_DK
    box("HallBorder", hx0, FLOOR, hz0, hx1, FLOOR + 0.03, hz0 + bw, B, M.Marble, f, NOSHADOW)
    box("HallBorder", hx0, FLOOR, hz1 - bw, hx1, FLOOR + 0.03, hz1, B, M.Marble, f, NOSHADOW)
    box("HallBorder", hx0, FLOOR, hz0 + bw, hx0 + bw, FLOOR + 0.03, hz1 - bw, B, M.Marble, f, NOSHADOW)
    box("HallBorder", hx1 - bw, FLOOR, hz0 + bw, hx1, FLOOR + 0.03, hz1 - bw, B, M.Marble, f, NOSHADOW)
    local star = cpart("HallMedallion", Vector3.new(0.04, 7, 7), CFrame.new(0, FLOOR + 0.02, -47) * CFrame.Angles(0, 0, math.rad(90)),
        B, M.Marble, f, merge(NOSHADOW, { Shape = Enum.PartType.Cylinder, CanQuery = false }))
    star.Name = "HallMedallion"
    for k = 0, 3 do
        cpart("MedallionRay", Vector3.new(0.5, 0.04, 6.2), CFrame.new(0, FLOOR + 0.045, -47) * CFrame.Angles(0, math.rad(k * 45), 0),
            BRASS, M.Metal, f, merge(NOSHADOW, { CanQuery = false }))
    end
    -- office: dark border around the planks
    box("OfficeBorder", -41.5, FLOOR, -57.5, -14.5, FLOOR + 0.03, -56.7, WALNUT_DK, M.WoodPlanks, f, NOSHADOW)
    box("OfficeBorder", -41.5, FLOOR, -39.3, -14.5, FLOOR + 0.03, -38.5, WALNUT_DK, M.WoodPlanks, f, NOSHADOW)
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

    -- rounded corner towers at the two front corners. v2.1: pulled in to x ±40
    -- (Ø5.4 → outer edge x ±42.7, flush with the side wall) so the east one no
    -- longer pokes into the service driveway the getaway car drives down.
    for _, sx in ipairs({ -1, 1 }) do
        local cx, cz = sx * 40, -37.5
        vcyl("CornerTower", cx, 0, 19.5, cz, 5.4, PINK, M.Plaster, f)
        for i, y in ipairs({ 14.0, 14.7, 15.4 }) do
            vcyl("CornerBand" .. i, cx, y, y + 0.35, cz, 5.7, TEAL, M.Plaster, f)
        end
        vcyl("CornerNeonRing", cx, 19.3, 19.42, cz, 5.65, HOT_PINK, M.Neon, f, NOSHADOW)
        vcyl("CornerCap", cx, 19.5, 19.9, cz, 6.0, TEAL, M.Plaster, f)
        vcyl("CornerFinial", cx, 19.9, 21.2, cz, 0.5, STEEL_LITE, M.Metal, f, DECOR)
        local d = Vector3.new(sx, 0, 1).Unit
        for k = 0, 5 do
            local p = Vector3.new(cx, 3.2 + k * 1.5, cz) + d * 2.65
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
    for _, x in ipairs({ -34, -22, 22, 34 }) do
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
    -- v2.1: a downward spot, not a point light — the old one shone pink straight
    -- through the front wall and tinted the whole grand hall
    spotLight(strip, Enum.NormalId.Bottom, HOT_PINK, 1.1, 12, 110, false)
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
    spotLight(sign, Enum.NormalId.Back, HOT_PINK, 2.5, 18, 120, false)   -- faces the garden only (was a point light leaking indoors)

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
    -- a downward pool (unrotated holder: a vcyl's local axes are turned 90°)
    spotLight(lightHolder(parent, Vector3.new(x, 2.2, z)), Enum.NormalId.Bottom, WARM, 1.2, 9, 150, false)
end

function VillaBuilder:_garden(f)
    local rng = Random.new(1958)
    local flowerCols = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(250, 240, 240), Color3.fromRGB(220, 60, 140) }
    for _, sx in ipairs({ -1, 1 }) do
        -- lawn up to the garden wall (z -27.6); the old sidewalk hedge is now the wall itself
        box("Lawn", sx * 6.4, 0, -37.5, sx * 42.6, 0.12, -27.6, Color3.fromRGB(46, 102, 58), M.Grass, f)
        box("Flowerbed", sx * 10.4, 0, -37.5, sx * 36.8, 0.6, -36, Color3.fromRGB(70, 48, 36), M.Ground, f)
        for k = 0, 11 do
            local x = sx * (11.2 + k * 2.2)
            local z = -36.75 + rng:NextNumber(-0.3, 0.3)
            if k % 3 == 1 then
                ball("Shrub", Vector3.new(x, 1.0, z), 1.4, LEAF, M.Grass, f, DECOR)
            else
                ball("Flowers", Vector3.new(x, 0.85, z), 0.8, flowerCols[(k % 3) + 1], M.Fabric, f, DECOR)
            end
        end
        -- a clipped hedge bed along the inside of the garden wall
        box("WallHedge", sx * 10, 0, -29.4, sx * 34, 2.6, -27.6, Color3.fromRGB(40, 86, 48), M.LeafyGrass, f)
        palm(f, sx * 27, -31, sx * 1.4)
        bollard(f, sx * 7.4, -34.5)
        -- v2.1 facade uplights: tight pink / cyan washes up the stucco. SHADOWED —
        -- the old unshadowed ones lit the office + kitchen from outside.
        local fixture = cpart("Uplight", Vector3.new(0.6, 0.3, 0.6),
            CFrame.new(sx * 28, 0.75, -36.2) * CFrame.Angles(math.rad(-8), 0, 0), STEEL, M.Metal, f, DECOR)
        spotLight(fixture, Enum.NormalId.Top, sx < 0 and HOT_PINK or CYAN, 2.8, 18, 38, true)
    end
end

-- ──────────────────────────────────────────────
-- 🏖 BACK TERRACE (z -102..-96): pool, loungers, lamps
-- ──────────────────────────────────────────────
function VillaBuilder:_terrace(f)
    local STONE = Color3.fromRGB(226, 214, 192)
    box("TerraceDeck", -42.5, 0, -102.4, 42.6, FLOOR, -96.5, STONE, M.Limestone, f)   -- v2.1: runs to the beach railing

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

-- ──────────────────────────────────────────────
-- 💰 v3 LOOT "THE SCORE" (docs/V3_SPEC.md §2). Every lootSpot:
--   { kind, pool, cframe = where you STAND (looking at the loot), visual = what
--     LootService hides when it's bagged, interact, heavy, fragile, hidden,
--     target, inVault }
-- pools = rooms, so the shuffle + jackpot read as places:
--   "hall" · "gallery" · "office" · "bedroom" · "cellar" · "vault"
-- The furniture a thing sits on (frames, pallets, dollies, plinths, the rack)
-- is static; only the valuable itself is in `visual`.
-- ──────────────────────────────────────────────
local function lootCF(stand, pile)
    return CFrame.lookAt(stand, Vector3.new(pile.X, stand.Y, pile.Z))
end

-- stand / at are floor points (x, z); at = the loot itself
local function addLoot(list, kind, pool, sx, sz, ax, az, visual, flags)
    local e = {
        kind = kind, pool = pool, visual = visual,
        cframe = lootCF(Vector3.new(sx, FLOOR, sz), Vector3.new(ax, 0, az)),
        heavy = false, fragile = false, hidden = false, inVault = false,
    }
    for k, v in pairs(flags or {}) do e[k] = v end
    if visual then
        visual:SetAttribute("LootKind", kind)
        visual:SetAttribute("LootPool", pool)
    end
    table.insert(list, e)
    return e
end

-- ── secret-stash plumbing ──
-- Every BasePart / Light / SurfaceGui under `instances` starts HIDDEN (it only
-- exists on the ~1-in-20 runs the stash is out). reveal(true|false) shows or
-- hides it and runs cover(show) — the painting swings open, the rug folds back.
-- Each part's real look is kept in attributes StashT / StashC / StashQ.
local function stashReveal(instances, cover)
    local parts, fx = {}, {}
    local function add(p)
        p:SetAttribute("StashT", p.Transparency)
        p:SetAttribute("StashC", p.CanCollide)
        p:SetAttribute("StashQ", p.CanQuery)
        table.insert(parts, p)
    end
    for _, inst in ipairs(instances) do
        if inst:IsA("BasePart") then add(inst) end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                add(d)
            elseif d:IsA("Light") or d:IsA("SurfaceGui") then
                table.insert(fx, d)
            end
        end
    end
    local shown = nil
    local function reveal(show)
        show = show == true
        if shown == show then return end
        shown = show
        for _, p in ipairs(parts) do
            p.Transparency = show and p:GetAttribute("StashT") or 1
            p.CanCollide = show and p:GetAttribute("StashC") or false
            p.CanQuery = show and p:GetAttribute("StashQ") or false
        end
        for _, d in ipairs(fx) do d.Enabled = show end
        if cover then cover(show) end
    end
    reveal(false)
    return reveal
end

-- swing a set of parts about a vertical hinge: returns function(open)
local function hinged(inst, hinge, angle)
    local orig = {}
    local list = inst:IsA("BasePart") and { inst } or {}
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(list, d) end
    end
    for _, p in ipairs(list) do orig[p] = p.CFrame end
    local h = CFrame.new(hinge)
    local swing = h * CFrame.Angles(0, angle, 0) * h:Inverse()
    return function(open)
        for p, cf in pairs(orig) do
            p.CFrame = open and (swing * cf) or cf
        end
    end
end

local CASH_A, CASH_B = Color3.fromRGB(94, 148, 96), Color3.fromRGB(112, 164, 106)
local BAND = Color3.fromRGB(236, 230, 208)
local GOLD_LITE = Color3.fromRGB(250, 208, 96)
local GOLD_DEEP = Color3.fromRGB(176, 128, 36)
local GOLD_M = { Reflectance = 0.25 }

-- a banded bundle of notes (loose cash in the stashes)
local function cashBundle(parent, cf, w, h, d)
    w, h, d = w or 0.95, h or 0.3, d or 0.45
    cpart("CashBundle", Vector3.new(w, h, d), cf, CASH_A, M.Fabric, parent, NOSHADOW)
    cpart("CashBand", Vector3.new(0.16, h + 0.02, d + 0.02), cf, BAND, M.Fabric, parent, NOSHADOW)
end

-- ── 🎵 GOLD RECORD: a framed shadow box (the whole box comes off the wall) ──
local function goldRecord(parent, pos, normal, info)
    local cf = CFrame.lookAt(pos, pos + normal)
    local m = Instance.new("Model")
    m.Name = "GoldRecord"
    local W, H, D, fw = 2.7, 3.3, 0.36, 0.2
    local LACQ = Color3.fromRGB(22, 20, 24)
    cpart("RecordBack", Vector3.new(W, H, 0.08), cf * CFrame.new(0, 0, -0.04), Color3.fromRGB(14, 14, 18), M.Fabric, m, NOSHADOW)
    for _, r in ipairs({ { 0, (H - fw) / 2, W, fw }, { 0, -(H - fw) / 2, W, fw },
        { -(W - fw) / 2, 0, fw, H - 2 * fw }, { (W - fw) / 2, 0, fw, H - 2 * fw } }) do
        cpart("RecordFrame", Vector3.new(r[3], r[4], D), cf * CFrame.new(r[1], r[2], -D / 2), LACQ, M.Wood, m,
            merge(DECOR, { Reflectance = 0.12 }))
    end
    local c = (cf * CFrame.new(0, 0.32, -0.14)).Position
    disc("RecordDisc", c, normal, 0.05, 2.1, GOLD, M.Metal, m, merge(NOSHADOW, { Reflectance = 0.35 }))
    for i, dia in ipairs({ 1.8, 1.4 }) do   -- groove bands catch the light differently
        disc("RecordGroove", c + normal * (0.026 + i * 0.002), normal, 0.01, dia, GOLD_DEEP, M.Metal, m,
            merge(NOSHADOW, { Reflectance = 0.3 }))
        disc("RecordGroove", c + normal * (0.027 + i * 0.002), normal, 0.01, dia - 0.12, GOLD, M.Metal, m,
            merge(NOSHADOW, { Reflectance = 0.35 }))
    end
    disc("RecordLabel", c + normal * 0.036, normal, 0.012, 0.72, info.label, M.Fabric, m, NOSHADOW)
    disc("RecordSpindle", c + normal * 0.04, normal, 0.012, 0.09, Color3.fromRGB(20, 20, 22), M.Metal, m, NOSHADOW)
    local plq = cpart("RecordPlaque", Vector3.new(1.9, 0.6, 0.04), cf * CFrame.new(0, -1.1, -0.1), BRASS, M.Metal, m, NOSHADOW)
    local g = surface(plq, Enum.NormalId.Front, 60, 1, 1)
    text({ Text = info.title, Size = UDim2.fromScale(0.9, 0.42), Position = UDim2.fromScale(0.05, 0.08),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(46, 34, 16) }, g)
    text({ Text = info.sub, Size = UDim2.fromScale(0.9, 0.28), Position = UDim2.fromScale(0.05, 0.6),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.medium,
        TextColor3 = Color3.fromRGB(70, 54, 28) }, g)
    cpart("RecordGlass", Vector3.new(W - 2 * fw, H - 2 * fw, 0.03), cf * CFrame.new(0, 0, -(D - 0.05)),
        Color3.fromRGB(220, 232, 238), M.Glass, m, merge(NOSHADOW, { Transparency = 0.88, Reflectance = 0.18 }))
    m.Parent = parent
    return m
end

-- walnut hi-fi console under the records (decor). Against a wall at z = zb,
-- front faces +Z. Open middle bay full of record sleeves, turntable on top.
local function recordConsole(parent, x0, x1, zb, zf)
    local top = FLOOR + 2.4
    local mid0, mid1 = x0 + 1.6, x1 - 1.6
    for _, c in ipairs({ { x0, mid0 }, { mid1, x1 } }) do
        box("ConsoleCab", c[1], FLOOR + 0.4, zb, c[2], top, zf, WALNUT, M.Wood, parent)
        box("SpeakerCloth", c[1] + 0.2, FLOOR + 0.6, zf, c[2] - 0.2, top - 0.2, zf + 0.03,
            Color3.fromRGB(150, 128, 98), M.Fabric, parent, NOSHADOW)
    end
    box("ConsoleBack", mid0, FLOOR + 0.4, zb, mid1, top, zb + 0.1, WALNUT_DK, M.Wood, parent)
    box("ConsoleShelf", mid0, FLOOR + 0.4, zb, mid1, FLOOR + 0.55, zf, WALNUT_DK, M.Wood, parent)
    box("ConsoleTop", x0 - 0.06, top, zb, x1 + 0.06, top + 0.14, zf + 0.06, WALNUT_DK, M.WoodPlanks, parent)
    for _, x in ipairs({ x0 + 0.3, x1 - 0.3 }) do
        for _, z in ipairs({ zb + 0.3, zf - 0.3 }) do
            vcyl("ConsoleLeg", x, FLOOR, FLOOR + 0.4, z, 0.16, BRASS, M.Metal, parent, DECOR)
        end
    end
    local sleeves = { Color3.fromRGB(200, 60, 80), Color3.fromRGB(30, 30, 36), Color3.fromRGB(240, 200, 80),
        Color3.fromRGB(60, 140, 170), Color3.fromRGB(236, 226, 206), Color3.fromRGB(120, 50, 130) }
    local n = math.floor((mid1 - mid0 - 0.3) / 0.2)
    for k = 0, n - 1 do
        local x = mid0 + 0.2 + k * 0.2
        box("RecordSleeve", x, FLOOR + 0.55, zb + 0.2, x + 0.05, FLOOR + 1.95 - (k % 3) * 0.06, zf - 0.1,
            sleeves[(k % #sleeves) + 1], M.Fabric, parent, NOSHADOW)
    end
    -- turntable
    local tx, tz = x0 + 1.0, (zb + zf) / 2
    local t2 = top + 0.14
    box("TurntablePlinth", tx - 0.8, t2, tz - 0.65, tx + 0.8, t2 + 0.18, tz + 0.65, WALNUT_DK, M.Wood, parent, DECOR)
    vcyl("Platter", tx - 0.12, t2 + 0.18, t2 + 0.24, tz, 1.1, Color3.fromRGB(18, 18, 20), M.Rubber, parent, DECOR)
    vcyl("PlatterSpindle", tx - 0.12, t2 + 0.24, t2 + 0.34, tz, 0.06, STEEL_LITE, M.Metal, parent, DECOR)
    cpart("Tonearm", Vector3.new(0.05, 0.05, 0.9), CFrame.new(tx + 0.55, t2 + 0.34, tz + 0.05) * CFrame.Angles(0, math.rad(18), 0),
        STEEL_LITE, M.Metal, parent, NOSHADOW)
end

-- ── 🍷 WINE (fragile): three RESERVE niches in the pantry wine wall ──
local BOTTLE = { Color3.fromRGB(30, 56, 36), Color3.fromRGB(46, 28, 24), Color3.fromRGB(22, 38, 30) }
local FOILS = { GOLD, Color3.fromRGB(128, 24, 40), Color3.fromRGB(26, 26, 30), Color3.fromRGB(210, 206, 196) }

-- an upright bottle standing on y0 (visual parts go in `parent`)
local function uprightBottle(parent, x, y0, z, glass, foil)
    local bh, bd = 0.95, 0.4
    vcyl("BottleBody", x, y0, y0 + bh, z, bd, glass, M.Glass, parent, { Transparency = 0.12, Reflectance = 0.15 })
    ball("BottleShoulder", Vector3.new(x, y0 + bh, z), bd, glass, M.Glass, parent, { Transparency = 0.12, Reflectance = 0.15 })
    vcyl("BottleNeck", x, y0 + bh + 0.15, y0 + bh + 0.5, z, 0.16, foil, M.Metal, parent, merge(NOSHADOW, { Reflectance = 0.2 }))
    cpart("BottleLabel", Vector3.new(0.34, 0.42, 0.02), CFrame.new(x, y0 + 0.45, z + bd / 2 + 0.005),
        Color3.fromRGB(240, 230, 204), M.Fabric, parent, NOSHADOW)
    cpart("BottleLabelBand", Vector3.new(0.34, 0.07, 0.022), CFrame.new(x, y0 + 0.55, z + bd / 2 + 0.006),
        foil, M.Metal, parent, NOSHADOW)
end

function VillaBuilder:_wineWall(f, loot)
    local w = sub(f, "WineWall")
    local x0, x1, zb, zf = 32.6, 41.5, -57.5, -56.0
    local yt = 9.1
    local bandLo, bandHi = 3.55, 5.35       -- the RESERVE band (loot niches)
    box("RackBack", x0, FLOOR, zb, x1, yt, zb + 0.12, WALNUT_DK, M.Wood, w)
    box("RackSide", x0 - 0.16, FLOOR, zb, x0, yt, zf, WALNUT, M.Wood, w)
    box("RackPlinth", x0 - 0.16, FLOOR, zb, x1, FLOOR + 0.35, zf + 0.04, WALNUT_DK, M.Wood, w)
    box("RackCornice", x0 - 0.3, yt, zb, x1, yt + 0.4, zf + 0.18, WALNUT, M.Wood, w)
    local shelves = { 0.85, 1.75, 2.65, bandLo, bandHi, 6.25, 7.15, 8.05, yt - 0.02 }
    for _, y in ipairs(shelves) do
        box("RackShelf", x0, y - 0.1, zb, x1, y, zf, WALNUT, M.Wood, w)
    end
    local cols = 8
    local cw = (x1 - x0) / cols
    for i = 1, cols - 1 do
        local x = x0 + i * cw
        box("RackPost", x - 0.06, FLOOR + 0.35, zb, x + 0.06, bandLo - 0.1, zf, WALNUT, M.Wood, w)
        box("RackPost", x - 0.06, bandHi, zb, x + 0.06, yt, zf, WALNUT, M.Wood, w)
    end
    -- decor bottles lying in the cubbies, necks out (not every hole is full)
    local rng = Random.new(1961)
    local rows = { { 0.85, 1.75 }, { 1.75, 2.65 }, { 2.65, bandLo }, { bandHi, 6.25 }, { 6.25, 7.15 }, { 7.15, 8.05 }, { 8.05, yt } }
    for _, r in ipairs(rows) do
        for i = 0, cols - 1 do
            if rng:NextNumber() < 0.72 then
                local x, y = x0 + (i + 0.5) * cw, (r[1] + r[2]) / 2 - 0.05
                local glass = BOTTLE[rng:NextInteger(1, #BOTTLE)]
                cpart("RackBottle", Vector3.new(1.0, 0.4, 0.4), CFrame.new(x, y, zb + 0.72) * CFrame.Angles(0, math.rad(90), 0),
                    glass, M.Glass, w, merge(NOSHADOW, { Shape = Enum.PartType.Cylinder, Transparency = 0.12, Reflectance = 0.12 }))
                cpart("RackBottleNeck", Vector3.new(0.5, 0.16, 0.16), CFrame.new(x, y, zb + 1.43) * CFrame.Angles(0, math.rad(90), 0),
                    FOILS[rng:NextInteger(1, #FOILS)], M.Metal, w, merge(NOSHADOW, { Shape = Enum.PartType.Cylinder }))
            end
        end
    end
    -- the RESERVE niches: velvet back, brass dividers, a warm LED strip, a plaque each
    local vint = { { "CHÂTEAU ROSA", "1961" }, { "VIÑA DEL MAR", "1978" }, { "GRAN RESERVA", "1985" } }
    local nw = (x1 - x0) / 3
    box("ReserveVelvet", x0, bandLo, zb + 0.12, x1, bandHi - 0.1, zb + 0.16, Color3.fromRGB(96, 20, 36), M.Fabric, w, NOSHADOW)
    for i = 1, 2 do
        local x = x0 + i * nw
        box("ReserveDivider", x - 0.08, bandLo, zb, x + 0.08, bandHi - 0.1, zf, WALNUT_DK, M.Wood, w)
        box("ReserveTrim", x - 0.1, bandLo, zf - 0.02, x + 0.1, bandHi - 0.1, zf + 0.02, BRASS, M.Metal, w, NOSHADOW)
    end
    local strip = box("ReserveLED", x0 + 0.1, bandHi - 0.16, zf - 0.3, x1 - 0.1, bandHi - 0.12, zf - 0.22, WARM, M.Neon, w, NOSHADOW)
    pointLight(strip, LAMP_WARM, 0.55, 6, false)
    for i = 0, 2 do
        local nx = x0 + (i + 0.5) * nw
        local m = Instance.new("Model")
        m.Name = "WineReserve"
        for k = -1, 1 do
            uprightBottle(m, nx + k * 0.72, bandLo, zb + 0.75 + math.abs(k) * 0.12, BOTTLE[(i + k + 3) % 3 + 1], (i == 1) and FOILS[2] or GOLD)
        end
        m.Parent = w
        local plq = box("ReservePlaque", nx - 0.7, bandLo - 0.34, zf, nx + 0.7, bandLo - 0.1, zf + 0.04, BRASS, M.Metal, w, NOSHADOW)
        local g = surface(plq, Enum.NormalId.Back, 60, 1, 1)
        text({ Text = vint[i + 1][1] .. "  " .. vint[i + 1][2], Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1),
            TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
            TextColor3 = Color3.fromRGB(46, 34, 16) }, g)
        addLoot(loot, "Wine", "cellar", nx, -53.9, nx, zb + 0.8, m, { fragile = true })
    end
    -- a warm wall light over the nook (the pantry corner stays mostly dark)
    box("WineSconce", 36.7, 10.3, zb, 37.4, 10.9, zb + 0.35, BRASS, M.Metal, w, DECOR)
    local b = ball("WineSconceBulb", Vector3.new(37.05, 10.2, zb + 0.4), 0.28, LAMP_WARM, M.Neon, w, NOSHADOW)
    spotLight(b, Enum.NormalId.Bottom, LAMP_WARM, 0.9, 12, 80, true)
end

-- ── 🔐 BEDROOM SAFE: an old green floor safe; the JewelryBox is inside ──
-- (visual = the door + the box, so once it's cracked the safe stands open + empty)
function VillaBuilder:_bedroomSafe(f, loot)
    local s = sub(f, "Safe")
    local x0, x1 = -22.6, -20.0
    local zb, zf = -70.5, -72.9          -- back against the south wall, door faces north (-Z)
    local y0, y1 = FLOOR, FLOOR + 3.4
    local BODY = Color3.fromRGB(40, 62, 54)
    box("SafeBase", x0 - 0.1, y0, zf - 0.1, x1 + 0.1, y0 + 0.3, zb, Color3.fromRGB(26, 28, 30), M.Metal, s)
    box("SafeBack", x0, y0 + 0.3, zb - 0.25, x1, y1, zb, BODY, M.Metal, s)
    box("SafeSide", x0, y0 + 0.3, zf, x0 + 0.25, y1, zb, BODY, M.Metal, s)
    box("SafeSide", x1 - 0.25, y0 + 0.3, zf, x1, y1, zb, BODY, M.Metal, s)
    box("SafeTop", x0, y1 - 0.25, zf, x1, y1, zb, BODY, M.Metal, s)
    box("SafeFloor", x0, y0 + 0.3, zf, x1, y0 + 0.55, zb, BODY, M.Metal, s)
    box("SafeLining", x0 + 0.25, y0 + 0.55, zb - 0.28, x1 - 0.25, y1 - 0.25, zb - 0.25, Color3.fromRGB(120, 24, 40), M.Fabric, s, NOSHADOW)
    box("SafeShelf", x0 + 0.25, 2.05, zf + 0.1, x1 - 0.25, 2.15, zb - 0.25, STEEL_LITE, M.Metal, s)
    box("SafeTrim", x0 - 0.02, y1 - 0.12, zf - 0.02, x1 + 0.02, y1 - 0.02, zb, BRASS, M.Metal, s, NOSHADOW)
    local maker = box("SafeMaker", (x0 + x1) / 2 - 0.7, y1 - 0.55, zf - 0.03, (x0 + x1) / 2 + 0.7, y1 - 0.3, zf, BRASS, M.Metal, s, NOSHADOW)
    signText(maker, Enum.NormalId.Front, "ROSA & CO · 1924", Color3.fromRGB(46, 34, 16), 60, 1)
    for _, y in ipairs({ 1.4, 3.0 }) do
        vcyl("SafeHinge", x0 + 0.08, y, y + 0.45, zf - 0.08, 0.18, BRASS, M.Metal, s, DECOR)
    end

    local m = Instance.new("Model")
    m.Name = "JewelryBox"
    local cx, cy = (x0 + x1) / 2, (y0 + 0.55 + y1 - 0.25) / 2
    box("SafeDoor", x0 + 0.05, y0 + 0.58, zf - 0.14, x1 - 0.05, y1 - 0.28, zf + 0.02, BODY, M.Metal, m)
    -- recessed panel line + gold pinstripe (painted safes of the 1920s)
    local pd = box("SafeDoorPanel", x0 + 0.3, y0 + 0.85, zf - 0.16, x1 - 0.3, y1 - 0.55, zf - 0.14, BODY:Lerp(BLACK, 0.12), M.Metal, m, NOSHADOW)
    local pg = surface(pd, Enum.NormalId.Front, 40, 1, 1)
    local stripe = frame({ Size = UDim2.fromScale(0.9, 0.92), Position = UDim2.fromScale(0.05, 0.04), BackgroundTransparency = 1 }, pg)
    local st = Instance.new("UIStroke")
    st.Color = GOLD
    st.Thickness = 2
    st.Parent = stripe
    local dc = Vector3.new(cx, cy + 0.35, zf - 0.17)
    disc("DialFace", dc, NZ, 0.05, 0.9, Color3.fromRGB(20, 20, 22), M.Metal, m, NOSHADOW)
    disc("DialRing", dc + NZ * 0.03, NZ, 0.03, 0.82, STEEL_LITE, M.Metal, m, NOSHADOW)
    disc("DialKnob", dc + NZ * 0.1, NZ, 0.16, 0.46, BRASS, M.Metal, m, merge(NOSHADOW, { Reflectance = 0.2 }))
    local hc = Vector3.new(cx, cy - 0.55, zf - 0.2)
    disc("HandleHub", hc, NZ, 0.12, 0.26, STEEL_LITE, M.Metal, m, NOSHADOW)
    for k = 0, 2 do
        cpart("HandleSpoke", Vector3.new(0.08, 0.7, 0.08), CFrame.new(hc + NZ * 0.1) * CFrame.Angles(0, 0, math.rad(k * 120)),
            STEEL_LITE, M.Metal, m, NOSHADOW)
    end
    -- the jewellery box on the shelf inside (burgundy leather, lid up, pearls + stones)
    local jz = (zf + zb) / 2 - 0.1
    box("JewelBoxBody", cx - 0.6, 2.15, jz - 0.4, cx + 0.6, 2.6, jz + 0.4, Color3.fromRGB(110, 26, 48), M.Leather, m)
    box("JewelBoxVelvet", cx - 0.52, 2.6, jz - 0.32, cx + 0.52, 2.62, jz + 0.32, Color3.fromRGB(30, 22, 40), M.Fabric, m, NOSHADOW)
    cpart("JewelBoxLid", Vector3.new(1.2, 0.8, 0.08), CFrame.new(cx, 2.95, jz + 0.44) * CFrame.Angles(math.rad(-12), 0, 0),
        Color3.fromRGB(110, 26, 48), M.Leather, m, NOSHADOW)
    for k = 0, 6 do
        ball("Pearl", Vector3.new(cx - 0.45 + k * 0.15, 2.7, jz - 0.15 + math.sin(k * 0.9) * 0.08), 0.13,
            Color3.fromRGB(246, 240, 232), M.SmoothPlastic, m, NOSHADOW)
    end
    local gems = { Color3.fromRGB(220, 30, 70), Color3.fromRGB(40, 190, 110), Color3.fromRGB(60, 110, 240), Color3.fromRGB(230, 240, 255) }
    for k, c in ipairs(gems) do
        cpart("Gem", Vector3.new(0.16, 0.16, 0.16), CFrame.new(cx - 0.35 + k * 0.17, 2.72, jz + 0.12) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
            c, M.Glass, m, merge(NOSHADOW, { Transparency = 0.1, Reflectance = 0.45 }))
    end
    m.Parent = s
    addLoot(loot, "JewelryBox", "bedroom", cx, -75.6, cx, (zf + zb) / 2, m, { interact = "dial" })
end

-- ── 🕳 SECRET STASH #1: the wall safe behind the office painting ──
function VillaBuilder:_officeStash(f, loot)
    local s = sub(f, "WallStash")
    local px, py = -28, 8.3
    local wz = -38.5                         -- the wall's interior face; room is -Z
    local art = Instance.new("Model")
    art.Name = "StashPainting"
    painting(art, Vector3.new(px, py, wz), NZ, 3.4, 2.6, 24, { style = "fields" })
    art.Parent = s
    -- the hidden safe: 2 x 2 steel box set into the wall, door swung open
    local x0, x1, y0, y1, z0 = px - 1.0, px + 1.0, py - 1.0, py + 1.0, wz - 0.6
    local shell = Instance.new("Model")
    shell.Name = "WallSafe"
    local SAFE = Color3.fromRGB(58, 62, 68)
    box("WallSafeBack", x0, y0, wz - 0.08, x1, y1, wz, Color3.fromRGB(30, 30, 34), M.Metal, shell)
    box("WallSafeSide", x0, y0, z0, x0 + 0.12, y1, wz, SAFE, M.Metal, shell)
    box("WallSafeSide", x1 - 0.12, y0, z0, x1, y1, wz, SAFE, M.Metal, shell)
    box("WallSafeTop", x0, y1 - 0.12, z0, x1, y1, wz, SAFE, M.Metal, shell)
    box("WallSafeBottom", x0, y0, z0, x1, y0 + 0.12, wz, SAFE, M.Metal, shell)
    -- door: hinged on the east edge (x1), swung 110° out into the room
    local hinge = Vector3.new(x1, py, z0)
    local dcf = CFrame.new(hinge) * CFrame.Angles(0, math.rad(-110), 0) * CFrame.new(-1.0, 0, -0.07)
    cpart("WallSafeDoor", Vector3.new(2.0, 2.0, 0.14), dcf, SAFE, M.Metal, shell, NOSHADOW)
    disc("WallSafeDial", (dcf * CFrame.new(0, 0.1, -0.1)).Position, dcf.LookVector, 0.06, 0.55, BRASS, M.Metal, shell, NOSHADOW)
    shell.Parent = s
    -- the stash: bundles of cash, a stack of gold coins, a velvet pouch
    local m = Instance.new("Model")
    m.Name = "SecretStash"
    local fy = y0 + 0.12
    for k = 0, 2 do
        cashBundle(m, CFrame.new(px - 0.4, fy + 0.15 + k * 0.3, wz - 0.3), 0.95, 0.28, 0.42)
    end
    for k = 0, 5 do
        vcyl("GoldCoin", px + 0.45, fy + k * 0.07, fy + k * 0.07 + 0.06, wz - 0.3, 0.42, GOLD, M.Metal, m,
            merge(NOSHADOW, { Reflectance = 0.3 }))
    end
    ball("VelvetPouch", Vector3.new(px + 0.4, fy + 0.72, wz - 0.28), 0.42, Color3.fromRGB(90, 30, 110), M.Fabric, m, NOSHADOW)
    m.Parent = s
    -- the painting swings off the wall on its east edge to show the safe
    local swing = hinged(art, Vector3.new(px + 1.9, py, wz), math.rad(-95))
    local e = addLoot(loot, "SecretStash", "office", px, -41.6, px, wz, m, { hidden = true })
    e.reveal = stashReveal({ shell, m }, swing)
end

-- ── 🕳 SECRET STASH #2: a floor safe under the bedroom rug ──
local function rugPattern(p, face, field, border, accent)
    local g = surface(p, face, 12, 1, 1)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = border }, g)
    local fld = frame({ Position = UDim2.fromScale(0.08, 0.08), Size = UDim2.fromScale(0.84, 0.84), BackgroundColor3 = field }, bg)
    local st = Instance.new("UIStroke")
    st.Color = accent
    st.Thickness = 3
    st.Parent = fld
    for i, sz in ipairs({ 0.46, 0.32, 0.16 }) do
        frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(sz, sz),
            Rotation = 45, BackgroundColor3 = (i % 2 == 1) and accent or border, ZIndex = 2 + i }, fld)
    end
    for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
        frame({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(c[1], c[2]), Size = UDim2.fromScale(0.26, 0.26),
            Rotation = 45, BackgroundColor3 = accent, ZIndex = 2 }, fld)
    end
    return g
end

function VillaBuilder:_rugStash(f, loot)
    local s = sub(f, "RugStash")
    local x0, x1, z0, z1 = -25.2, -20.4, -82.6, -77.2
    local fold = -79.9
    local FIELD, BORDER, ACCENT = Color3.fromRGB(128, 34, 44), Color3.fromRGB(34, 36, 62), Color3.fromRGB(214, 176, 110)
    local RUG = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
    -- the whole rug, lying flat (what you see on 19 runs out of 20)
    local full = box("BedroomRug", x0, FLOOR, z0, x1, FLOOR + 0.06, z1, FIELD, M.Carpet, s, RUG)
    local fullGui = rugPattern(full, Enum.NormalId.Top, FIELD, BORDER, ACCENT)
    -- revealed: the rug is pulled back — a shorter rug + the folded-over flap (jute side up)
    local short = box("BedroomRugShort", x0, FLOOR, fold, x1, FLOOR + 0.06, z1, FIELD, M.Carpet, s, RUG)
    rugPattern(short, Enum.NormalId.Top, FIELD, BORDER, ACCENT)
    local flap = box("RugFlap", x0 + 0.05, FLOOR + 0.06, fold, x1 - 0.05, FLOOR + 0.12, fold + (fold - z0), Color3.fromRGB(176, 150, 110), M.Fabric, s, RUG)
    cpart("RugCurl", Vector3.new(x1 - x0 - 0.1, 0.22, 0.22), CFrame.new((x0 + x1) / 2, FLOOR + 0.1, fold) * CFrame.Angles(0, 0, 0),
        FIELD, M.Carpet, s, merge(RUG, { Shape = Enum.PartType.Cylinder }))
    -- the floor safe (flush steel rim, lid standing open against the flap)
    local hx0, hx1, hz0, hz1 = -23.8, -21.8, -82.2, -80.2
    local RIM = Color3.fromRGB(70, 74, 80)
    box("FloorSafeRim", hx0, FLOOR, hz0, hx1, FLOOR + 0.1, hz0 + 0.15, RIM, M.Metal, s, DECOR)
    box("FloorSafeRim", hx0, FLOOR, hz1 - 0.15, hx1, FLOOR + 0.1, hz1, RIM, M.Metal, s, DECOR)
    box("FloorSafeRim", hx0, FLOOR, hz0, hx0 + 0.15, FLOOR + 0.1, hz1, RIM, M.Metal, s, DECOR)
    box("FloorSafeRim", hx1 - 0.15, FLOOR, hz0, hx1, FLOOR + 0.1, hz1, RIM, M.Metal, s, DECOR)
    box("FloorSafeWell", hx0 + 0.15, FLOOR, hz0 + 0.15, hx1 - 0.15, FLOOR + 0.02, hz1 - 0.15, Color3.fromRGB(16, 16, 18), M.Metal, s, DECOR)
    local lid = cpart("FloorSafeLid", Vector3.new(2.0, 0.12, 2.0),
        CFrame.new((hx0 + hx1) / 2, FLOOR + 0.1, hz0) * CFrame.Angles(math.rad(-100), 0, 0) * CFrame.new(0, 0, 1.0),
        RIM, M.DiamondPlate, s, DECOR)
    disc("FloorSafeDial", (lid.CFrame * CFrame.new(0, 0.08, 0)).Position, lid.CFrame.UpVector, 0.05, 0.5, BRASS, M.Metal, s, DECOR)
    local m = Instance.new("Model")
    m.Name = "SecretStash"
    local cx, cz = (hx0 + hx1) / 2, (hz0 + hz1) / 2
    for k = 0, 3 do
        cashBundle(m, CFrame.new(cx - 0.38 + (k % 2) * 0.76, FLOOR + 0.17 + math.floor(k / 2) * 0.3, cz - 0.3) * CFrame.Angles(0, math.rad(90), 0), 0.95, 0.28, 0.42)
    end
    -- a gold watch on top
    local wcf = CFrame.new(cx + 0.35, FLOOR + 0.12, cz + 0.5)
    cpart("WatchStrap", Vector3.new(0.9, 0.04, 0.2), wcf, GOLD, M.Metal, m, merge(NOSHADOW, GOLD_M))
    cpart("WatchCase", Vector3.new(0.08, 0.36, 0.36), wcf * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, M.Metal, m,
        merge(NOSHADOW, { Shape = Enum.PartType.Cylinder, Reflectance = 0.3 }))
    cpart("WatchFace", Vector3.new(0.02, 0.28, 0.28), wcf * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(236, 232, 220), M.Glass, m,
        merge(NOSHADOW, { Shape = Enum.PartType.Cylinder, Reflectance = 0.2 }))
    m.Parent = s
    local function cover(show)
        full.Transparency = show and 1 or 0
        fullGui.Enabled = not show
    end
    local e = addLoot(loot, "SecretStash", "bedroom", cx, -78.4, cx, cz, m, { hidden = true })
    e.reveal = stashReveal({ short, flap, s:FindFirstChild("RugCurl"), lid, m }, cover)
    -- the rim/well/dial are part of the reveal too (they'd poke through the rug)
    local extra = {}
    for _, c in ipairs(s:GetChildren()) do
        if c.Name == "FloorSafeRim" or c.Name == "FloorSafeWell" or c.Name == "FloorSafeDial" then table.insert(extra, c) end
    end
    local r1, r2 = e.reveal, stashReveal(extra)
    e.reveal = function(show) r1(show); r2(show) end
end

-- ── 🏦 VAULT: shrink-wrapped cash pallets ──
local PALLET_WOOD = Color3.fromRGB(168, 132, 88)
local function cashPallet(parent, cx, cz)
    for i = -1, 1 do
        box("PalletRunner", cx - 1.3, FLOOR, cz + i * 0.95 - 0.22, cx + 1.3, FLOOR + 0.35, cz + i * 0.95 + 0.22,
            PALLET_WOOD:Lerp(BLACK, 0.15), M.WoodPlanks, parent)
    end
    for i = 0, 4 do
        local x = cx - 1.04 + i * 0.52
        box("PalletDeck", x - 0.22, FLOOR + 0.35, cz - 1.2, x + 0.22, FLOOR + 0.47, cz + 1.2, PALLET_WOOD, M.WoodPlanks, parent)
    end
    local m = Instance.new("Model")
    m.Name = "CashPallet"
    local y0 = FLOOR + 0.47
    for layer = 0, 3 do
        local y = y0 + layer * 0.48
        for ix = 0, 1 do
            local x = cx - 0.62 + ix * 1.24
            for iz = 0, 2 do
                local z = cz - 0.8 + iz * 0.8
                box("CashBrick", x - 0.6, y, z - 0.38, x + 0.6, y + 0.46, z + 0.38,
                    ((ix + iz + layer) % 2 == 0) and CASH_A or CASH_B, M.Fabric, m, NOSHADOW)
            end
            -- a paper strap round each column of bricks
            box("CashStrap", x - 0.12, y - 0.01, cz - 1.2, x + 0.12, y + 0.47, cz + 1.2, BAND, M.Fabric, m, NOSHADOW)
        end
    end
    local top = y0 + 4 * 0.48
    -- the shrink-wrap film (the solid part of the load) + two black plastic straps
    box("ShrinkWrap", cx - 1.28, y0 - 0.02, cz - 1.22, cx + 1.28, top + 0.04, cz + 1.22,
        Color3.fromRGB(226, 238, 244), M.Glass, m, { Transparency = 0.6, Reflectance = 0.25, CastShadow = false })
    for _, z in ipairs({ cz - 0.55, cz + 0.55 }) do
        box("PalletStrap", cx - 1.3, top + 0.04, z - 0.07, cx + 1.3, top + 0.08, z + 0.07, Color3.fromRGB(24, 24, 26), M.Plastic, m, NOSHADOW)
        box("PalletStrap", cx - 1.32, FLOOR + 0.35, z - 0.07, cx - 1.28, top + 0.08, z + 0.07, Color3.fromRGB(24, 24, 26), M.Plastic, m, NOSHADOW)
        box("PalletStrap", cx + 1.28, FLOOR + 0.35, z - 0.07, cx + 1.32, top + 0.08, z + 0.07, Color3.fromRGB(24, 24, 26), M.Plastic, m, NOSHADOW)
    end
    m.Parent = parent
    return m
end

-- ── 🏦 VAULT: a neat cross-stacked pile of gold bars on a steel dolly ──
local function goldStack(parent, cx, cz)
    box("GoldDolly", cx - 1.35, FLOOR + 0.25, cz - 0.95, cx + 1.35, FLOOR + 0.45, cz + 0.95, STEEL, M.DiamondPlate, parent)
    for _, dx in ipairs({ -1.1, 1.1 }) do
        for _, dz in ipairs({ -0.7, 0.7 }) do
            ball("DollyCaster", Vector3.new(cx + dx, FLOOR + 0.13, cz + dz), 0.26, Color3.fromRGB(30, 30, 34), M.Rubber, parent, DECOR)
        end
    end
    local m = Instance.new("Model")
    m.Name = "GoldBars"
    local base = FLOOR + 0.45
    local last
    local function bar(x, layer, z, alongX)
        local y = base + (layer - 1) * 0.27
        local L, W, H = 1.0, 0.46, 0.2
        cpart("GoldBar", alongX and Vector3.new(L, H, W) or Vector3.new(W, H, L), CFrame.new(cx + x, y + H / 2, cz + z),
            GOLD, M.Metal, m, { Reflectance = 0.28 })
        last = cpart("GoldBarTop", alongX and Vector3.new(L - 0.16, 0.07, W - 0.12) or Vector3.new(W - 0.12, 0.07, L - 0.16),
            CFrame.new(cx + x, y + H + 0.035, cz + z), GOLD_LITE, M.Metal, m, merge(NOSHADOW, { Reflectance = 0.32 }))
    end
    for _, x in ipairs({ -0.52, 0.52 }) do for _, z in ipairs({ -0.5, 0, 0.5 }) do bar(x, 1, z, true) end end
    for _, x in ipairs({ -0.75, -0.25, 0.25, 0.75 }) do bar(x, 2, 0, false) end
    for _, x in ipairs({ -0.52, 0.52 }) do for _, z in ipairs({ -0.25, 0.25 }) do bar(x, 3, z, true) end end
    for _, x in ipairs({ -0.25, 0.25 }) do bar(x, 4, 0, false) end
    bar(0, 5, 0, true)
    local g = surface(last, Enum.NormalId.Top, 60, 1, 1)
    text({ Text = "999.9", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = GOLD_DEEP }, g)
    m.Parent = parent
    return m
end

-- ── 🏦 VAULT: a velvet tray of cut diamonds on a marble display stand ──
local function diamondTray(parent, cx, cz)
    box("TrayStand", cx - 0.85, FLOOR, cz - 0.65, cx + 0.85, FLOOR + 2.6, cz + 0.65, MARBLE_DK, M.Marble, parent)
    box("TrayStandCap", cx - 1.05, FLOOR + 2.6, cz - 0.85, cx + 1.05, FLOOR + 2.75, cz + 0.85, BRASS, M.Metal, parent)
    local m = Instance.new("Model")
    m.Name = "DiamondTray"
    local top = FLOOR + 2.75
    box("Tray", cx - 0.9, top, cz - 0.7, cx + 0.9, top + 0.08, cz + 0.7, Color3.fromRGB(18, 18, 24), M.Fabric, m)
    box("TrayRim", cx - 0.95, top, cz - 0.75, cx + 0.95, top + 0.14, cz - 0.7, BRASS, M.Metal, m, NOSHADOW)
    box("TrayRim", cx - 0.95, top, cz + 0.7, cx + 0.95, top + 0.14, cz + 0.75, BRASS, M.Metal, m, NOSHADOW)
    box("TrayRim", cx - 0.95, top, cz - 0.7, cx - 0.9, top + 0.14, cz + 0.7, BRASS, M.Metal, m, NOSHADOW)
    box("TrayRim", cx + 0.9, top, cz - 0.7, cx + 0.95, top + 0.14, cz + 0.7, BRASS, M.Metal, m, NOSHADOW)
    local ICE = Color3.fromRGB(214, 240, 255)
    local rng = Random.new(58)
    for i = 0, 4 do
        for j = 0, 3 do
            if not (i == 2 and (j == 1 or j == 2)) then
                cpart("Diamond", Vector3.new(0.18, 0.18, 0.18),
                    CFrame.new(cx - 0.64 + i * 0.32, top + 0.18, cz - 0.45 + j * 0.3) * CFrame.Angles(math.rad(45), math.rad(rng:NextNumber(0, 90)), math.rad(35)),
                    ICE, M.Glass, m, merge(NOSHADOW, { Transparency = 0.12, Reflectance = 0.55 }))
            end
        end
    end
    -- the centre stone on a little brass claw
    vcyl("CentreClaw", cx, top + 0.08, top + 0.2, cz, 0.22, BRASS, M.Metal, m, NOSHADOW)
    local big = cpart("CentreDiamond", Vector3.new(0.34, 0.34, 0.34), CFrame.new(cx, top + 0.38, cz) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
        ICE, M.Glass, m, merge(NOSHADOW, { Transparency = 0.08, Reflectance = 0.6 }))
    pointLight(big, Color3.fromRGB(200, 230, 255), 0.9, 7, false)
    m.Parent = parent
    return m
end

-- ── 🦩 THE TARGET: the solid-gold flamingo on a lit plinth, dead centre of the
-- vault so it's the first thing you see when the round door swings open ──
function VillaBuilder:_flamingo(f, loot)
    local pf = sub(f, "FlamingoPlinth")
    local cx, cz = 0, -91.2
    -- art-deco backdrop on the north lining: pink marble panel + a brass sunburst
    box("NicheBack", -3.6, FLOOR, -95.3, 3.6, 12.3, -95.05, Color3.fromRGB(214, 160, 170), M.Marble, pf)
    box("NicheFrame", -3.9, FLOOR, -95.3, -3.6, 12.5, -94.9, BRASS, M.Metal, pf)
    box("NicheFrame", 3.6, FLOOR, -95.3, 3.9, 12.5, -94.9, BRASS, M.Metal, pf)
    box("NicheFrame", -3.9, 12.2, -95.3, 3.9, 12.5, -94.9, BRASS, M.Metal, pf)
    local sc = Vector3.new(0, 6.2, -94.98)
    for k = 0, 8 do
        local a = math.rad(-60 + k * 15)
        local len = (k % 2 == 0) and 4.3 or 3.1
        local mid = sc + Vector3.new(math.sin(a), math.cos(a), 0) * (1.3 + len / 2)
        cpart("SunRay", Vector3.new(0.14, len, 0.06), CFrame.new(mid) * CFrame.Angles(0, 0, -a), BRASS, M.Metal, pf,
            merge(NOSHADOW, { Reflectance = 0.1 }))
    end
    -- the plinth: black marble drum, brass bands, a hairline of pink under the lip
    vcyl("PlinthStep", cx, FLOOR, FLOOR + 0.35, cz, 4.2, MARBLE_DK, M.Marble, pf)
    vcyl("PlinthBand", cx, FLOOR + 0.35, FLOOR + 0.5, cz, 3.4, BRASS, M.Metal, pf)
    vcyl("PlinthDrum", cx, FLOOR + 0.5, 2.8, cz, 3.0, MARBLE_DK, M.Marble, pf)
    vcyl("PlinthBand", cx, 2.8, 2.95, cz, 3.2, BRASS, M.Metal, pf)
    vcyl("PlinthGlow", cx, 2.86, 2.9, cz, 3.26, HOT_PINK, M.Neon, pf, NOSHADOW)
    local top = vcyl("PlinthTop", cx, 2.95, 3.2, cz, 3.5, MARBLE_DK, M.Marble, pf)
    pointLight(lightHolder(pf, Vector3.new(cx, 2.7, cz + 1.9)), HOT_PINK, 0.35, 4, false)
    local plq = cpart("PlinthPlaque", Vector3.new(1.4, 0.55, 0.06), CFrame.lookAt(Vector3.new(cx, 1.9, cz + 1.58), Vector3.new(cx, 1.9, cz + 5)),
        BRASS, M.Metal, pf, NOSHADOW)
    local g = surface(plq, Enum.NormalId.Front, 60, 1, 1)
    text({ Text = "EL FLAMENCO DE ORO", Size = UDim2.fromScale(0.92, 0.45), Position = UDim2.fromScale(0.04, 0.08),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(46, 34, 16) }, g)
    text({ Text = "SOLID GOLD · 1926", Size = UDim2.fromScale(0.8, 0.28), Position = UDim2.fromScale(0.1, 0.6),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.medium,
        TextColor3 = Color3.fromRGB(70, 54, 28) }, g)
    -- one tight, shadowed spot from the ceiling: the only bright thing in the room
    local spotPos = Vector3.new(cx, 12.3, cz + 3.6)
    local fx = cpart("TargetSpot", Vector3.new(0.6, 0.6, 0.9), CFrame.lookAt(spotPos, Vector3.new(cx, 6.2, cz)), STEEL, M.Metal, pf, DECOR)
    spotLight(fx, Enum.NormalId.Front, Color3.fromRGB(255, 238, 212), 3, 18, 28, true)

    -- the flamingo: side-on to the door, standing on one leg, beak to the east
    local m = Instance.new("Model")
    m.Name = "GoldFlamingo"
    local y0 = top.Position.Y + top.Size.X / 2
    local base = CFrame.lookAt(Vector3.new(cx, y0, cz), Vector3.new(cx + 1, y0, cz))   -- local -Z = east (beak), +X = south (to the door)
    local function at(x, y, z) return (base * CFrame.new(x, y, z)).Position end
    local function limb(a, b, dia, col)
        local mid, len = (a + b) / 2, (b - a).Magnitude
        cpart("FlamingoLimb", Vector3.new(len, dia, dia), CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0),
            col or GOLD, M.Metal, m, { Shape = Enum.PartType.Cylinder, Reflectance = 0.25 })
    end
    local function knob(p, dia, col)
        ball("FlamingoJoint", p, dia, col or GOLD, M.Metal, m, GOLD_M)
    end
    vcyl("FlamingoBase", cx, y0, y0 + 0.18, cz, 1.9, GOLD, M.Metal, m, GOLD_M)
    -- standing leg + webbed foot
    local foot, knee, hip = at(0, 0.18, 0.15), at(0, 1.4, 0.08), at(0, 2.6, 0.2)
    limb(foot, knee, 0.13); knob(knee, 0.22); limb(knee, hip, 0.15)
    cpart("FlamingoFoot", Vector3.new(0.34, 0.06, 0.5), base * CFrame.new(0, 0.21, -0.05), GOLD, M.Metal, m, GOLD_M)
    -- tucked leg: down-forward to the joint, then folded back up under the belly
    local hip2, knee2, foot2 = at(0.2, 2.55, 0.25), at(0.2, 1.85, -0.3), at(0.2, 2.35, 0.6)
    limb(hip2, knee2, 0.13); knob(knee2, 0.2); limb(knee2, foot2, 0.12)
    -- body: overlapping ovals + wings + a tail
    knob(at(0, 3.25, 0.05), 1.55)
    knob(at(0, 3.3, 0.55), 1.4)
    knob(at(0, 3.42, 1.0), 1.05)
    for _, sx in ipairs({ -1, 1 }) do
        knob(at(sx * 0.3, 3.42, 0.5), 1.15)
        cpart("FlamingoWing", Vector3.new(0.14, 0.34, 1.0), base * CFrame.new(sx * 0.66, 3.55, 0.75) * CFrame.Angles(math.rad(-14), sx * math.rad(8), 0),
            GOLD, M.Metal, m, GOLD_M)
    end
    cpart("FlamingoTail", Vector3.new(0.46, 0.26, 0.8), base * CFrame.new(0, 3.62, 1.45) * CFrame.Angles(math.rad(24), 0, 0),
        GOLD, M.Metal, m, GOLD_M)
    -- the S-curved neck
    local neck = { at(0, 3.6, -0.55), at(0, 4.25, -0.9), at(0, 4.95, -0.82), at(0, 5.55, -0.45), at(0, 6.1, -0.35), at(0, 6.5, -0.62) }
    for i = 1, #neck - 1 do
        local dia = 0.38 - i * 0.025
        limb(neck[i], neck[i + 1], dia)
        if i > 1 then knob(neck[i], dia) end
    end
    knob(at(0, 6.62, -0.8), 0.54)                                   -- head
    limb(at(0, 6.6, -1.0), at(0, 6.34, -1.38), 0.2)                -- beak
    limb(at(0, 6.34, -1.38), at(0, 6.12, -1.34), 0.14, GOLD_DEEP)  -- the bent black tip, in darker gold
    for _, sx in ipairs({ -1, 1 }) do
        ball("FlamingoEye", at(sx * 0.24, 6.7, -0.86), 0.09, GOLD_DEEP, M.Metal, m, NOSHADOW)
    end
    m.Parent = pf
    addLoot(loot, "GoldFlamingo", "vault", cx, cz + 3.8, cx, cz, m,
        { heavy = true, target = "GoldFlamingo", inVault = true })
end

-- ──────────────────────────────────────────────
-- 🏛 GRAND HALL  interior x -13.5..13.5, z -57.5..-38.5
-- Guard A walks z = -47 between x -9 and 9 → nothing in z -49.5..-44.5 there.
-- ──────────────────────────────────────────────
function VillaBuilder:_hall(f, props, spots, hides, loot)
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
    pointLight(drop, Color3.fromRGB(255, 200, 140), 1.5, 24, true)   -- the one big warm pool; corners stay dim

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
        pointLight(b, WARM, 0.9, 7, false)   -- short: an unshadowed light shines through the wall behind it
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
    pointLight(lightHolder(f, Vector3.new(12.3, 7.3, -56.6)), LAMP_WARM, 0.7, 9, false)
    prop(props, "pottedPlant", 12.2, FLOOR, -53.2, nil, 1.5)

    -- benches under the front windows, plants beside the door
    for _, sx in ipairs({ -1, 1 }) do
        prop(props, "benchCushion", sx * 9.9, FLOOR, -39.9, NZ, 1.0)
        prop(props, "pottedPlant", sx * 6.3, FLOOR, -40.2, nil, 1.3)
    end

    -- velvet curtains on the front windows
    curtains(f, "x", -38.6, -12.8, -9.4, Color3.fromRGB(120, 30, 44))
    curtains(f, "x", -38.6, 9.4, 12.8, Color3.fromRGB(120, 30, 44))

    -- paintings on the side walls. v3: two of them are LOOT (cut from the frame);
    -- both flank the front door, right under the hall camera's sweep.
    painting(f, Vector3.new(-13.5, 8, -55), PX, 3.2, 3.6, 11)
    local c1 = painting(f, Vector3.new(-13.5, 7.8, -41.2), PX, 3.2, 3.4, 13)
    pictureLight(f, Vector3.new(-13.5, 10.1, -41.2), PX, 2.6)
    addLoot(loot, "Painting", "hall", -11.4, -42.6, -13.5, -41.2, c1, { interact = "cut" })
    painting(f, Vector3.new(13.5, 8, -55), NX, 3.2, 3.6, 12)
    local c2 = painting(f, Vector3.new(13.5, 7.8, -41.2), NX, 3.2, 3.4, 14)
    pictureLight(f, Vector3.new(13.5, 10.1, -41.2), NX, 2.6)
    addLoot(loot, "Painting", "hall", 11.4, -42.6, 13.5, -41.2, c2, { interact = "cut" })
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

    -- v3 MUSIC CORNER (north wall, west of the door): the owner's hi-fi console
    -- with two framed GOLD RECORDS above it (loot — the whole frame comes off)
    recordConsole(f, -38.8, -33.2, -57.5, -55.9)
    local records = {
        { x = -37.6, title = "NEON NIGHTS", sub = "ROSA · 1,000,000 SOLD", label = Color3.fromRGB(196, 40, 70) },
        { x = -34.4, title = "OCEAN DRIVE", sub = "ROSA & THE FLAMINGOS · GOLD", label = Color3.fromRGB(236, 226, 206) },
    }
    for _, r in ipairs(records) do
        local rec = goldRecord(f, Vector3.new(r.x, 7.3, -57.5), PZ, r)
        addLoot(loot, "GoldRecord", "office", r.x, -54.6, r.x, -57.5, rec)
    end
    local spot = box("RecordSpot", -36.4, TOP - 0.3, -56.4, -35.6, TOP, -55.6, STEEL, M.Metal, f, DECOR)
    spotLight(spot, Enum.NormalId.Bottom, Color3.fromRGB(255, 230, 196), 0.9, 12, 60, true)

    -- lounge corner (NE): sofa, glass coffee table, armchair, floor lamp
    prop(props, "loungeSofa", -19.5, FLOOR, -55.7, PZ)
    prop(props, "tableCoffeeGlass", -19.5, FLOOR, -51.3, PZ, 1.0)
    prop(props, "loungeChair", -23.4, FLOOR, -51.3, PX, 1.0)
    prop(props, "lampSquareFloor", -24.6, FLOOR, -56.8)
    pointLight(lightHolder(f, Vector3.new(-24.6, 7.3, -56.8)), LAMP_WARM, 0.8, 12, true)

    -- south wall: sideboard with a lamp + a globe
    prop(props, "sideTableDrawers", -29, FLOOR, -39.45, NZ)
    prop(props, "lampSquareTable", -30, 3.76, -39.4, nil, 1.0)
    pointLight(lightHolder(f, Vector3.new(-30, 5.8, -39.6)), LAMP_WARM, 0.6, 8, false)
    vcyl("GlobeStand", -35.5, FLOOR, 2.6, -41.5, 0.3, BRASS, M.Metal, f)
    ball("Globe", Vector3.new(-35.5, 3.5, -41.5), 1.8, Color3.fromRGB(70, 120, 170), M.SmoothPlastic, f)
    prop(props, "ceilingFan", -28, TOP - 1.15, -48)

    curtains(f, "z", -41.4, -50, -46, Color3.fromRGB(110, 30, 40))
    painting(f, Vector3.new(-14.5, 8, -55.3), NX, 3.4, 2.6, 21)
    painting(f, Vector3.new(-37.5, 8, -38.5), NZ, 1.8, 2.6, 23)
    -- v3 LOOT painting in the dark SE corner, above the crawl vent
    local c = painting(f, Vector3.new(-14.5, 8.2, -41.4), NX, 3.0, 3.4, 22)
    addLoot(loot, "Painting", "office", -16.9, -41.4, -14.5, -41.4, c, { interact = "cut" })
    -- v3 SECRET STASH: a wall safe behind the painting over the sideboard
    self:_officeStash(f, loot)
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
    -- v3: the dark NE corner is the PANTRY WINE WALL (Wine loot, fragile)
    self:_wineWall(f, loot)

    -- marble island (part-built — cash + keycard spot on top)
    local top = 3.9
    box("IslandBase", 25.2, FLOOR, -49.8, 32.8, top - 0.3, -46.2, Color3.fromRGB(40, 70, 72), M.Wood, f)
    box("IslandTop", 25, top - 0.3, -50, 33, top, -46, MARBLE, M.Marble, f)
    box("IslandKick", 25.3, FLOOR, -49.7, 32.7, 0.9, -46.3, TEAL_DARK, M.Metal, f, DECOR)
    table.insert(spots, CFrame.new(32, top + 0.01, -47.2))
    -- (v3: the loose cash that sat here is gone — the kitchen's loot is the wine)
    box("FruitBowl", 26.0, top, -48.6, 27.4, top + 0.25, -47.4, Color3.fromRGB(236, 232, 224), M.Marble, f, DECOR)
    for k, c in ipairs({ Color3.fromRGB(250, 170, 40), Color3.fromRGB(230, 60, 50), Color3.fromRGB(250, 210, 60), Color3.fromRGB(120, 180, 60) }) do
        ball("Fruit", Vector3.new(26.3 + (k % 2) * 0.7, top + 0.42 + math.floor(k / 3) * 0.2, -48.3 + math.floor((k - 1) / 2) * 0.55), 0.46, c, M.Plastic, f, NOSHADOW)
    end
    prop(props, "kitchenCoffeeMachine", 29.5, top, -49.2, PZ, 1.0)
    for _, x in ipairs({ 27, 29, 31 }) do
        prop(props, "stoolBar", x, FLOOR, -43.9, NZ, 1.0)
    end
    for _, x in ipairs({ 27, 31 }) do
        box("PendantCable", x - 0.05, 9.8, -48.05, x + 0.05, TOP, -47.95, STEEL, M.Metal, f, DECOR)
        vcyl("PendantShade", x, 9.1, 9.8, -48, 1.3, STEEL, M.Metal, f, DECOR)
        local b = ball("PendantBulb", Vector3.new(x, 9.0, -48), 0.3, Color3.fromRGB(240, 244, 255), M.Neon, f, NOSHADOW)
        pointLight(b, Color3.fromRGB(236, 242, 255), 1.0, 10, x == 27)
    end

    -- dining table by the front windows
    prop(props, "tableCloth", 20.5, FLOOR, -41.2, PZ)
    for _, x in ipairs({ 18.8, 22.2 }) do
        prop(props, "chairCushion", x, FLOOR, -44.6, PZ)
    end
    ceilingLamp(f, 20.5, -41.2, LAMP_WARM, 0.8, 11, true, 10)

    prop(props, "trashcan", 22.5, FLOOR, -56.6, nil, 1.0)
    prop(props, "pottedPlant", 15.8, FLOOR, -39.8, nil, 1.3)
    painting(f, Vector3.new(14.5, 8, -40.5), PX, 2.4, 2.4, 41)
    painting(f, Vector3.new(19, 8, -57.5), PZ, 3, 2.4, 42)
    -- window curtains on the front
    curtains(f, "x", -38.6, 20, 24, Color3.fromRGB(240, 220, 170))
    curtains(f, "x", -38.6, 32, 36, Color3.fromRGB(240, 220, 170))
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
    -- v3 LOOT: the canvas on the easel (a work in progress — unframed)
    local c0 = painting(f, Vector3.new(ex, 4.6, ez + 0.35), PZ, 3.2, 3.4, 61, { frame = false, style = "sunset" })
    c0.Name = "EaselCanvas"
    addLoot(loot, "Painting", "gallery", ex, -65.4, ex, ez, c0, { interact = "cut" })
    pictureLight(f, Vector3.new(ex, 9.2, -69.5), PZ, 3)

    -- a marble bust on the east pedestal (decor — the gold one lives in the vault now)
    pedestal(f, 16, -59.6, F, "ROSA II", "CARRARA MARBLE")
    sculpture(f, 16, -59.6, "bust")
    local fx = box("GallerySpot", 15.6, TOP - 0.3, -60, 16.4, TOP, -59.2, STEEL, M.Metal, f, DECOR)
    spotLight(fx, Enum.NormalId.Bottom, Color3.fromRGB(255, 236, 214), 1.0, 18, 30, true)

    -- wall paintings (+ picture lights on the middle ones only; the ends stay dark).
    -- v3: four of them are LOOT — the dark west-end one is the risky grab
    -- (Camera_Gallery sweeps that end).
    local wall = {
        { -37, 8, -69.5, PZ, 3.6, 2.8, 62, true },
        { -20, 8, -69.5, PZ, 3.0, 2.8, 63, true },
        { 12, 8, -69.5, PZ, 4.0, 3.0, 64, true },
        { -15, 8, -58.5, NZ, 4.0, 3.0, 65, true },
        { 15, 8.6, -58.5, NZ, 3.0, 2.4, 66, false },
        { 37, 8, -58.5, NZ, 3.0, 2.8, 67, false },
    }
    for _, p in ipairs(wall) do
        local c = painting(f, Vector3.new(p[1], p[2], p[3]), p[4], p[5], p[6], p[7])
        if p[8] then
            local standZ = p[3] + p[4].Z * 2.8
            addLoot(loot, "Painting", "gallery", p[1], standZ, p[1], p[3], c, { interact = "cut" })
        end
    end
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
    box("CupboardTop", cx0, 8.2, cz0, cx1, 8.5, cz1, TRIM, M.Plaster, f)
    box("CupboardSide", cx0, FLOOR, cz0, cx1, 8.2, cz0 + 0.25, TRIM, M.Plaster, f)
    box("CupboardSide", cx0, FLOOR, cz1 - 0.25, cx1, 8.2, cz1, TRIM, M.Plaster, f)
    box("CupboardShelf", cx0 + 0.3, 6.5, cz0 + 0.25, cx1, 6.7, cz1 - 0.25, TRIM, M.Plaster, f)
    for k = 0, 3 do   -- folded towels on the top shelf
        box("Towels", cx0 + 0.6, 6.7, cz0 + 0.5 + k * 1.1, cx1 - 0.3, 7.5, cz0 + 1.4 + k * 1.1,
            (k % 2 == 0) and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(150, 205, 210), M.Fabric, f, NOSHADOW)
    end
    local doors = cpart("LinenCupboardDoors", Vector3.new(cz1 - cz0, 7.7, 0.2),
        CFrame.lookAt(Vector3.new(cx0 - 0.1, FLOOR + 3.85, (cz0 + cz1) / 2), Vector3.new(cx0 - 5, FLOOR + 3.85, (cz0 + cz1) / 2)),
        Color3.fromRGB(226, 214, 196), M.Plaster, f)
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
    -- v3: two dimmer side lights; the centre is the flamingo's own spot (_flamingo)
    for _, x in ipairs({ -10, 10 }) do
        local fx = box("VaultLight", x - 0.8, 12.35, -89.5, x + 0.8, 12.5, -88.5, BRASS, M.Metal, f, DECOR)
        pointLight(fx, Color3.fromRGB(255, 200, 110), 0.95, 15, true)   -- shadowed: gold must not bleed into the rooms round the vault
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
    local V = { inVault = true }
    -- west wall: three shrink-wrapped pallets of cash
    for _, z in ipairs({ -86.0, -89.5, -93.0 }) do
        local m = cashPallet(f, -15.7, z)
        addLoot(loot, "Cash", "vault", -12.3, z, -15.7, z, m, V)
    end
    -- north wall, either side of the flamingo niche: gold bars (heavy) on dollies.
    -- The open door sweeps x 4.5..6.1 / z -81..-90 — nothing east-side sits there.
    for _, x in ipairs({ -9.5, 13.2 }) do
        local m = goldStack(f, x, -93.6)
        addLoot(loot, "GoldBars", "vault", x, -90.5, x, -93.6, m, { inVault = true, heavy = true })
    end
    -- the diamond tray on its marble stand
    local d = diamondTray(f, 8.6, -93.9)
    addLoot(loot, "Diamonds", "vault", 8.6, -90.9, 8.6, -93.9, d, V)
    -- 🦩 the target, dead centre
    self:_flamingo(f, loot)
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
    -- dresser + mirror on the south wall (v3: the jewels moved into the safe)
    box("Dresser", -40.5, FLOOR, -72.5, -35.5, 3.25, -70.5, WOOD_MID, M.Wood, f)
    box("DresserTop", -40.6, 3.25, -72.6, -35.4, 3.4, -70.5, MARBLE, M.Marble, f)
    for k = 0, 2 do
        box("DrawerLine", -40.3, 1.1 + k * 0.75, -72.55, -35.7, 1.15 + k * 0.75, -72.5, WOOD_DARK, M.Wood, f, NOSHADOW)
    end
    box("Mirror", -39.8, 4.2, -70.7, -36.2, 9, -70.5, Color3.fromRGB(200, 212, 218), M.Glass, f, { Reflectance = 0.45 })
    box("MirrorFrame", -40, 4.0, -70.6, -36, 9.2, -70.5, BRASS, M.Metal, f, DECOR)
    -- perfume bottles + a brush on the dresser (decor)
    for k, c in ipairs({ Color3.fromRGB(250, 190, 210), Color3.fromRGB(190, 220, 240), Color3.fromRGB(250, 220, 150) }) do
        local x = -39.6 + k * 0.55
        vcyl("Perfume", x, 3.4, 3.4 + 0.45 + (k % 2) * 0.15, -71.4, 0.34, c, M.Glass, f, merge(NOSHADOW, { Transparency = 0.25, Reflectance = 0.2 }))
        vcyl("PerfumeCap", x, 3.85 + (k % 2) * 0.15, 4.0 + (k % 2) * 0.15, -71.4, 0.16, GOLD, M.Metal, f, NOSHADOW)
    end
    box("HairBrush", -37.2, 3.4, -71.7, -36.2, 3.52, -71.35, WALNUT, M.Wood, f, NOSHADOW)

    -- TV corner on the east wall, armchair facing it
    prop(props, "cabinetTelevision", -19.56, FLOOR, -86, NX)
    prop(props, "televisionModern", -19.6, FLOOR + 2.63, -86, NX)
    local tvGlow = lightHolder(f, Vector3.new(-21, 4.5, -86))
    pointLight(tvGlow, Color3.fromRGB(120, 150, 255), 0.5, 6, false)
    prop(props, "loungeChairRelax", -23.2, FLOOR, -86, PX, 1.0)
    prop(props, "lampSquareFloor", -20, FLOOR, -94.5)
    pointLight(lightHolder(f, Vector3.new(-20, 7.3, -94.5)), LAMP_WARM, 0.6, 7, false)
    -- brass sconces either side of the bed (visible bulbs)
    for _, z in ipairs({ -86.8, -79.2 }) do
        box("BedSconce", -41.5, 6.6, z - 0.25, -41.15, 7.2, z + 0.25, BRASS, M.Metal, f, DECOR)
        local sb = ball("BedSconceBulb", Vector3.new(-40.95, 7.35, z), 0.3, LAMP_WARM, M.Neon, f, NOSHADOW)
        pointLight(sb, LAMP_WARM, 0.5, 7, false)
    end
    -- MOONLIGHT through the sea-view windows: a cold shadowed spot outside, so
    -- the floor gets two window-shaped pools of blue and the rest stays dark
    local moon = lightHolder(f, Vector3.new(-30, 15, -101))
    moon.CFrame = CFrame.lookAt(moon.Position, Vector3.new(-30, FLOOR, -85))
    spotLight(moon, Enum.NormalId.Front, MOON, 1.3, 30, 55, true)
    prop(props, "pottedPlant", -23.5, FLOOR, -94.6, nil, 1.3)
    prop(props, "ceilingFan", -30, TOP - 1.15, -83)

    -- curtains on the sea-view windows + the west windows
    curtains(f, "x", -95.4, -38.5, -33.5, Color3.fromRGB(230, 200, 210))
    curtains(f, "x", -95.4, -26.5, -21.5, Color3.fromRGB(230, 200, 210))
    curtains(f, "z", -41.4, -94, -90, Color3.fromRGB(230, 200, 210))
    curtains(f, "z", -41.4, -76, -72, Color3.fromRGB(230, 200, 210))
    painting(f, Vector3.new(-41.5, 8, -83), PX, 5, 3, 31)
    -- v3 LOOT painting on the east wall (north of the TV), with a picture light
    local c = painting(f, Vector3.new(-18.5, 8.4, -91.2), NX, 3.4, 2.8, 32)
    pictureLight(f, Vector3.new(-18.5, 10.2, -91.2), NX, 2.8)
    addLoot(loot, "Painting", "bedroom", -21.3, -91.2, -18.5, -91.2, c, { interact = "cut" })
    -- v3: the bedroom SAFE (JewelryBox, dial) in the SE corner + the rug stash
    self:_bedroomSafe(f, loot)
    self:_rugStash(f, loot)
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
    box("ShoeShelf", -8.4, FLOOR, -80.5, -6.5, 1.4, -72.5, TRIM, M.Plaster, f)

    -- vanity shelf (keycard spot) in the NW corner
    box("Vanity", -17.3, FLOOR, -81.3, -15, 3.4, -79.8, TRIM, M.Plaster, f)
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

    local l = ceilingLamp(f, -11.5, -75.5, WARM, 0.6, 16, true)
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
    spotLight(tube, Enum.NormalId.Bottom, COOL, 0.8, 17, 70, false)   -- a downward cone: keeps it in the hall
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
    box("FoldTable", 22.5, 3.0, -95.3, 27.3, 3.3, -93.3, TRIM, M.Plaster, f)
    for _, x in ipairs({ 22.7, 27.0 }) do
        box("FoldTableLeg", x - 0.1, FLOOR, -95.1, x + 0.1, 3.0, -93.5, STEEL, M.Metal, f)
    end
    for k = 0, 2 do
        box("TowelStack", 23.2 + k * 1.3, 3.3, -94.9, 24.2 + k * 1.3, 3.9 + (k % 2) * 0.3, -93.8,
            (k % 2 == 0) and Color3.fromRGB(245, 245, 240) or Color3.fromRGB(240, 170, 190), M.Fabric, f)
    end
    box("WallShelf", 22.5, 6.2, -95.5, 27.3, 6.4, -94.7, TRIM, M.Plaster, f)
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

    ceilingLamp(f, 23, -88.5, COOL, 0.6, 16, true)
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

    -- (v2.1) the yard itself — paving, bins, the getaway parking bay and the
    -- vehicle gate — is built by _grounds below.
end

-- ──────────────────────────────────────────────
-- 🧱 v2.1 THE GROUNDS — Malachi: "shouldn't be able to just walk out the heist
-- to the outside and see the ugly green terrain". The villa now sits inside a
-- walled property; the only way out is the getaway car through the yard gate.
--
--   Enclosure (outer faces) x -50.9..54.0, z -103.0..-26.8, minus the notch
--   x 50.9..54.0 / z -47.8..-26.8 (that's CORAL's lot). Stays inside
--   MiamiBuilder.KEEP_CLEAR (x ±54, z -106..-25).
--     street  z -27.6..-26.8   stucco base + iron railing, CLOSED front gate x -4..4
--     beach   z -103.0..-102.4 stucco base + iron railing (sea view)
--     west    x -50.9..-50.1   solid stucco, 11 tall
--     lane    x 50.2..50.9 (z -48.6..-26.8), yard south z -48.6..-47.8,
--     yard E  x 53.2..54.0     solid stucco, 11 tall
--   SERVICE YARD x 42.6..53.2, z -102.4..-48.6 (concrete) + DRIVEWAY LANE
--   x 42.6..50.2 down the east side of the villa to the street.
--   VEHICLE GATE: stands OPEN, clear opening x 42.6..50.2 at z -27.2.
--   GETAWAY PARKING: car centre (45.6, 0, -72) facing south (+Z) at the gate;
--   footprint x 43.25..47.95, z -77.6..-66.4. Straight line to the gate —
--   nothing solid in x 43.0..48.3 from z -78 to the street.
--   Invisible ClimbGuards stand on every wall top up to y 45 (nobody jumps off
--   the villa roof over a wall), except over the vehicle gate.
-- ──────────────────────────────────────────────
local WALL_H = 11
local GETAWAY_POS = Vector3.new(45.6, 0, -72)
local GUARD = { Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false }

-- bx: a box along a wall line. axis "x" = runs along X (t = z thickness span)
local function lineBox(parent, axis, name, t0, t1, b0, b1, y0, y1, col, mat, extra)
    if axis == "x" then
        return box(name, b0, y0, t0, b1, y1, t1, col, mat, parent, extra)
    end
    return box(name, t0, y0, b0, t1, y1, b1, col, mat, parent, extra)
end

local PIER_COL = WALL_PINK:Lerp(TRIM, 0.4)

-- solid 11-tall stucco garden wall with piers every ~10 studs
local function gardenWall(parent, axis, t0, t1, a0, a1)
    lineBox(parent, axis, "GardenWall", t0, t1, a0, a1, 0, WALL_H, WALL_PINK, M.Plaster)
    lineBox(parent, axis, "WallPlinth", t0 - 0.15, t1 + 0.15, a0, a1, 0, 1.1, PLINTH, M.Concrete)
    lineBox(parent, axis, "WallCoping", t0 - 0.2, t1 + 0.2, a0, a1, WALL_H, WALL_H + 0.35, TRIM, M.Plaster)
    local n = math.max(1, math.floor((a1 - a0) / 10))
    for i = 0, n do
        local a = a0 + (a1 - a0) * i / n
        lineBox(parent, axis, "WallPier", t0 - 0.3, t1 + 0.3, math.max(a0, a - 0.8), math.min(a1, a + 0.8), 0, WALL_H + 0.8, PIER_COL, M.Plaster)
    end
    lineBox(parent, axis, "ClimbGuard", t0, t1, a0, a1, WALL_H, 45, Color3.new(0, 0, 0), M.SmoothPlastic, GUARD)
end

-- stucco base + wrought-iron railing between piers (you see out, you can't get out)
local function railing(parent, axis, t0, t1, a0, a1, baseH)
    local tc = (t0 + t1) / 2
    lineBox(parent, axis, "RailBase", t0, t1, a0, a1, 0, baseH, WALL_PINK, M.Plaster)
    lineBox(parent, axis, "RailBaseCap", t0 - 0.2, t1 + 0.2, a0, a1, baseH, baseH + 0.3, TRIM, M.Plaster)
    -- one invisible collider for the whole run (bars stay decor = cheap physics)
    lineBox(parent, axis, "RailCollider", tc - 0.2, tc + 0.2, a0, a1, baseH, 45, Color3.new(0, 0, 0), M.SmoothPlastic, GUARD)
    local n = math.max(1, math.floor((a1 - a0) / 11))
    local bay = (a1 - a0) / n
    local yb, yt = baseH + 0.3, WALL_H - 0.3
    for i = 0, n do
        local a = a0 + bay * i
        local p0, p1 = math.max(a0, a - 0.8), math.min(a1, a + 0.8)
        lineBox(parent, axis, "RailPier", t0 - 0.35, t1 + 0.35, p0, p1, 0, WALL_H + 0.6, PIER_COL, M.Plaster)
        lineBox(parent, axis, "RailPierCap", t0 - 0.5, t1 + 0.5, p0 - 0.15, p1 + 0.15, WALL_H + 0.6, WALL_H + 0.9, TRIM, M.Plaster, DECOR)
        if i < n then
            local s0, s1 = p1, math.min(a1, a + bay - 0.8)
            lineBox(parent, axis, "RailTop", tc - 0.12, tc + 0.12, s0, s1, yt - 0.3, yt, IRON, M.Metal, DECOR)
            local nb = math.floor((s1 - s0) / 1.9)
            for k = 1, nb do
                local b = s0 + (s1 - s0) * k / (nb + 1)
                lineBox(parent, axis, "RailBar", tc - 0.09, tc + 0.09, b - 0.09, b + 0.09, yb, yt + 0.5, IRON, M.Metal, DECOR)
            end
        end
    end
end

-- a caged wall lantern with a visible bulb. out = unit direction away from the wall
local function wallLantern(parent, pos, out, color, brightness, range, shadows, down)
    local cf = CFrame.lookAt(pos, pos + out)
    cpart("LanternBracket", Vector3.new(0.3, 0.3, 0.9), cf * CFrame.new(0, 0.9, -0.3), IRON, M.Metal, parent, DECOR)
    cpart("LanternGlass", Vector3.new(0.7, 1.1, 0.7), cf * CFrame.new(0, 0.1, -0.75), Color3.fromRGB(255, 226, 170), M.Glass, parent,
        merge(NOSHADOW, { Transparency = 0.45 }))
    local bulb = ball("LanternBulb", (cf * CFrame.new(0, 0.15, -0.75)).Position, 0.32, color, M.Neon, parent, NOSHADOW)
    if down then
        spotLight(lightHolder(parent, bulb.Position - Vector3.new(0, 0.3, 0)), Enum.NormalId.Bottom, color, brightness, range, 120, shadows)
    else
        pointLight(bulb, color, brightness, range, shadows)
    end
    return bulb
end

local function wheelieBin(parent, bx, bz, color, label)
    box("BinBody", bx - 0.9, 0.1, bz - 1, bx + 0.9, 3.6, bz + 1, color, M.Plastic, parent)
    box("BinLid", bx - 1.0, 3.6, bz - 1.1, bx + 1.0, 3.8, bz + 1.1, color:Lerp(Color3.new(0, 0, 0), 0.2), M.Plastic, parent)
    local lab = box("BinLabel", bx - 0.8, 2.2, bz + 1, bx + 0.8, 3.0, bz + 1.02, Color3.fromRGB(240, 240, 240), M.SmoothPlastic, parent, NOSHADOW)
    signText(lab, Enum.NormalId.Back, label, Color3.fromRGB(30, 30, 34), 40, 1)
end

local function gatePier(parent, x0, x1, z0, z1, h)
    box("GatePier", x0, 0, z0, x1, h, z1, PIER_COL, M.Plaster, parent)
    box("GatePierBand", x0 - 0.1, h - 1.6, z0 - 0.1, x1 + 0.1, h - 1.2, z1 + 0.1, TEAL, M.Plaster, parent, DECOR)
    box("GatePierCap", x0 - 0.25, h, z0 - 0.25, x1 + 0.25, h + 0.4, z1 + 0.25, TRIM, M.Plaster, parent)
    local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    -- lantern on top
    box("PierLanternBase", cx - 0.4, h + 0.4, cz - 0.4, cx + 0.4, h + 0.6, cz + 0.4, IRON, M.Metal, parent, DECOR)
    box("PierLanternGlass", cx - 0.35, h + 0.6, cz - 0.35, cx + 0.35, h + 1.7, cz + 0.35, Color3.fromRGB(255, 226, 170), M.Glass, parent,
        merge(NOSHADOW, { Transparency = 0.45 }))
    box("PierLanternRoof", cx - 0.5, h + 1.7, cz - 0.5, cx + 0.5, h + 1.95, cz + 0.5, IRON, M.Metal, parent, DECOR)
    local bulb = ball("PierLanternBulb", Vector3.new(cx, h + 1.15, cz), 0.35, WARM, M.Neon, parent, NOSHADOW)
    pointLight(bulb, WARM, 1.1, 12, false)
end

-- one iron gate leaf in the X-Z plane from p0 to p1 (bottom y0 → top y1)
local function gateLeaf(parent, p0, p1, y0, y1, bars, collide)
    local mid = (p0 + p1) / 2
    local len = (p1 - p0).Magnitude
    local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(mid.X, 0, mid.Z) + (p1 - p0).Unit) * CFrame.Angles(0, math.rad(90), 0)
    -- cf: local X runs along the leaf
    local extra = collide and nil or DECOR
    local function piece(name, x0, x1, ya, yb, w)
        cpart(name, Vector3.new(x1 - x0, yb - ya, w or 0.22), cf * CFrame.new((x0 + x1) / 2, (ya + yb) / 2, 0), IRON, M.Metal, parent, extra)
    end
    local h = len / 2
    piece("GateStile", -h, -h + 0.25, y0, y1)
    piece("GateStile", h - 0.25, h, y0, y1)
    piece("GateRail", -h, h, y0, y0 + 0.25)
    piece("GateRail", -h, h, y1 - 0.25, y1)
    piece("GateRail", -h, h, y0 + 2.2, y0 + 2.4)
    for k = 1, bars do
        local x = -h + len * k / (bars + 1)
        piece("GateBar", x - 0.08, x + 0.08, y0, y1 + 0.45, 0.16)
    end
    return cf
end

function VillaBuilder:_grounds(f, props)
    local walls = sub(f, "Walls")
    local yard = sub(f, "Yard")

    -- ── the enclosure ──
    gardenWall(walls, "z", -50.9, -50.1, -103.0, -26.8)          -- west
    gardenWall(walls, "z", 50.2, 50.9, -48.6, -26.8)             -- driveway lane (along CORAL)
    gardenWall(walls, "x", -48.6, -47.8, 50.2, 54.0)             -- yard south (behind CORAL)
    gardenWall(walls, "z", 53.2, 54.0, -103.0, -47.8)            -- yard east
    railing(walls, "x", -103.0, -102.4, -50.9, 54.0, 3)          -- beach
    railing(walls, "x", -27.6, -26.8, -50.9, -5.4, 3.4)          -- street, west of the front gate
    railing(walls, "x", -27.6, -26.8, 5.4, 41.4, 3.4)            -- street, east of the front gate

    -- ── FRONT GATE (x -4..4): closed, locked, pretty ──
    for _, sx in ipairs({ -1, 1 }) do
        gatePier(walls, math.min(sx * 4, sx * 5.4), math.max(sx * 4, sx * 5.4), -28.0, -26.7, 12.5)
        gateLeaf(walls, Vector3.new(sx * 4, 0, -27.2), Vector3.new(0, 0, -27.2), 0.5, 9.2, 4, false)
    end
    box("GateLock", -0.35, 4.4, -27.45, 0.35, 5.2, -26.95, BRASS, M.Metal, walls, DECOR)
    -- one collider over the leaves AND the piers (the entrance canopy is close
    -- enough to hop from onto a pier top otherwise)
    box("GateCollider", -5.4, 0.45, -27.4, 5.4, 45, -27.0, Color3.new(0, 0, 0), M.SmoothPlastic, walls, GUARD)
    box("GateArch", -5.4, 11.6, -27.5, 5.4, 12.1, -26.9, IRON, M.Metal, walls, DECOR)
    local nameplate = box("GateNameplate", -3.2, 12.1, -27.3, 3.2, 13.5, -27.1, IRON, M.Metal, walls, DECOR)
    signText(nameplate, Enum.NormalId.Back, "VILLA ROSA", Color3.fromRGB(236, 200, 120), 40, 1)
    signText(nameplate, Enum.NormalId.Front, "VILLA ROSA", Color3.fromRGB(236, 200, 120), 40, 1)
    local plaque = box("PrivateProperty", 5.5, 5, -26.7, 7.5, 6.2, -26.6, Color3.fromRGB(26, 20, 30), M.Metal, walls, DECOR)
    signText(plaque, Enum.NormalId.Back, "PRIVATE", Color3.fromRGB(236, 200, 120), 50, 1)

    -- ── VEHICLE GATE (x 42.6..50.2): open, leaves folded back inside ──
    gatePier(walls, 41.4, 42.6, -28.0, -26.7, 12.5)
    gatePier(walls, 50.2, 51.0, -28.0, -26.7, 12.5)
    gateLeaf(walls, Vector3.new(42.7, 0, -27.8), Vector3.new(42.7, 0, -31.6), 0.1, 9.0, 4, false)
    gateLeaf(walls, Vector3.new(50.1, 0, -27.8), Vector3.new(50.1, 0, -31.6), 0.1, 9.0, 4, false)
    box("GateBeam", 41.4, 13.0, -27.6, 51.0, 13.5, -26.9, IRON, M.Metal, walls, DECOR)
    local vsign = box("DeliveriesSign", 43.4, 13.5, -27.35, 49.4, 15.1, -27.15, IRON, M.Metal, walls, DECOR)
    signText(vsign, Enum.NormalId.Back, "DELIVERIES", Color3.fromRGB(250, 204, 21), 40, 1)
    signText(vsign, Enum.NormalId.Front, "EXIT", Color3.fromRGB(80, 230, 140), 40, 1)

    -- ── ground cover: nothing inside the walls is bare terrain ──
    box("YardPaving", 42.6, 0, -102.4, 53.2, 0.1, -48.6, Color3.fromRGB(128, 126, 120), M.Concrete, yard)
    box("Driveway", 42.6, 0, -48.6, 50.2, 0.1, -26.7, Color3.fromRGB(56, 58, 62), M.Asphalt, yard)
    box("WestPath", -50.1, 0, -102.4, -42.5, 0.1, -27.6, Color3.fromRGB(176, 166, 150), M.Pebble, yard)
    box("WestHedge", -50.1, 0, -100.5, -48.7, 3.4, -29.5, Color3.fromRGB(40, 86, 48), M.LeafyGrass, yard)

    -- driveway markings: parking bay round the getaway car + a centre dash to the gate
    local Y = Color3.fromRGB(236, 196, 60)
    local paint = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
    box("BayLine", 42.9, 0.1, -78.8, 43.1, 0.12, -65.2, Y, M.SmoothPlastic, yard, paint)
    box("BayLine", 48.3, 0.1, -78.8, 48.5, 0.12, -65.2, Y, M.SmoothPlastic, yard, paint)
    box("BayLine", 42.9, 0.1, -78.8, 48.5, 0.12, -78.6, Y, M.SmoothPlastic, yard, paint)
    for z = -60, -32, 7 do
        box("LaneDash", 46.3, 0.1, z, 46.5, 0.12, z + 3, Color3.fromRGB(226, 224, 214), M.SmoothPlastic, yard, paint)
    end
    -- hatched no-parking box outside the staff door (keeps the doorway readable)
    for k = 0, 3 do
        cpart("Hatch", Vector3.new(0.25, 0.02, 3.2), CFrame.new(46.8, 0.11, -91.5 + k * 1.9) * CFrame.Angles(0, math.rad(45), 0),
            Y, M.SmoothPlastic, yard, paint)
    end

    -- ── yard dressing: north of the car, or east of x 49 beside it — the car's
    --    path (x 43.0..48.3, z -78 → street) stays clear ──
    wheelieBin(yard, 44.4, -100.9, Color3.fromRGB(40, 110, 60), "TRASH")
    wheelieBin(yard, 46.8, -100.9, Color3.fromRGB(40, 90, 180), "RECYCLE")
    -- dumpster in the NE corner
    box("Dumpster", 49.2, 0.1, -102.2, 53.0, 3.4, -99.4, Color3.fromRGB(38, 92, 70), M.Metal, yard)
    box("DumpsterLid", 49.1, 3.4, -102.3, 53.1, 3.6, -99.3, Color3.fromRGB(28, 70, 54), M.Metal, yard)
    box("DumpsterStripe", 49.2, 2.4, -99.42, 53.0, 2.8, -99.38, Color3.fromRGB(236, 196, 60), M.SmoothPlastic, yard, NOSHADOW)
    -- staff smoking bench against the east wall (cover near the door)
    box("YardBenchSeat", 51.4, 1.8, -97.2, 53.1, 2.1, -92.8, Color3.fromRGB(150, 110, 72), M.WoodPlanks, yard)
    for _, z in ipairs({ -96.8, -93.2 }) do
        box("YardBenchLeg", 51.6, 0.1, z - 0.15, 52.9, 1.8, z + 0.15, IRON, M.Metal, yard)
    end
    -- pallets + crates by the east wall (Kenney factory kit — it arrives textured)
    for k = 0, 2 do
        box("Pallet", 49.6, 0.1 + k * 0.5, -90.8, 53.0, 0.5 + k * 0.5, -87.2, Color3.fromRGB(160, 124, 84), M.WoodPlanks, yard)
    end
    prop(props, "box-large", 51.3, 1.6, -89, NX, nil, "factory")
    prop(props, "trashcan", 49.6, 0.1, -84.6)
    prop(props, "box-large", 51.6, 0.1, -82.2, NX, nil, "factory")
    prop(props, "box-wide", 51.7, 0.1, -78.2, NX, nil, "factory")
    prop(props, "cardboardBoxOpen", 51.7, 0.1, -74.6)
    -- AC condensers against the east wall (moved off the villa wall: that's the lane now)
    for _, z in ipairs({ -64.5, -60.5 }) do
        box("ACUnit", 51.0, 0.1, z - 1.6, 53.2, 3.1, z + 1.6, Color3.fromRGB(200, 200, 196), M.Metal, yard)
        disc("ACFan", Vector3.new(50.95, 1.7, z), NX, 0.1, 2.2, Color3.fromRGB(40, 40, 44), M.Metal, yard, DECOR)
    end
    -- a planter at the lane mouth (inside the yard)
    for _, pz in ipairs({ -52.5 }) do
        box("Planter", 50.6, 0.1, pz - 1.3, 53.2, 1.6, pz + 1.3, Color3.fromRGB(176, 100, 70), M.Brick, yard)
        box("PlanterSoil", 50.8, 1.6, pz - 1.1, 53.0, 1.7, pz + 1.1, Color3.fromRGB(60, 42, 30), M.Ground, yard, DECOR)
        ball("PlanterShrub", Vector3.new(51.9, 2.8, pz), 2.6, LEAF, M.LeafyGrass, yard, DECOR)
    end

    -- ── lights: pools, not floodlit everywhere ──
    -- the floodlight over the parking bay (shadowed: it points at the villa)
    local fl = cpart("Floodlight", Vector3.new(1.4, 0.9, 0.6), CFrame.lookAt(Vector3.new(52.6, 10.5, -72), Vector3.new(45, 0, -72)),
        IRON, M.Metal, yard, DECOR)
    box("FloodlightArm", 52.8, 10.2, -72.3, 53.2, 10.8, -71.7, IRON, M.Metal, yard, DECOR)
    local lens = cpart("FloodlightLens", Vector3.new(1.2, 0.7, 0.05), fl.CFrame * CFrame.new(0, 0, -0.32), Color3.fromRGB(255, 240, 210), M.Neon, yard, NOSHADOW)
    spotLight(lens, Enum.NormalId.Front, YARD_LIGHT, 2.2, 30, 70, true)
    -- lantern pools along the walls (spots pointing down so none shine into the villa)
    wallLantern(yard, Vector3.new(53.1, 8, -95), NX, YARD_LIGHT, 1.3, 12, false, true)
    wallLantern(yard, Vector3.new(53.1, 8, -57), NX, YARD_LIGHT, 1.3, 12, false, true)
    wallLantern(yard, Vector3.new(50.1, 8, -44), NX, YARD_LIGHT, 1.2, 12, false, true)
    wallLantern(yard, Vector3.new(50.1, 8, -34), NX, YARD_LIGHT, 1.2, 12, false, true)
    wallLantern(yard, Vector3.new(-50.0, 8, -90), PX, YARD_LIGHT, 1.1, 11, false, true)
    wallLantern(yard, Vector3.new(-50.0, 8, -64), PX, YARD_LIGHT, 1.1, 11, false, true)
    wallLantern(yard, Vector3.new(-50.0, 8, -38), PX, YARD_LIGHT, 1.1, 11, false, true)
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
-- 🪑 v2.1 KENNEY RECOLOUR — in Malachi's video the furniture rendered as plain
-- white blocks (the importer dropped the colours, and KenneyLoader only fixes
-- parts that come in pure white). Every furniture model we place is recoloured
-- here as it arrives: biggest part = body colour, the rest = trim colour,
-- `top` (optional) = the highest part (plant leaves, lamp shades).
-- Factory-kit crates carry their own texture atlas and are left alone.
-- ──────────────────────────────────────────────
local APPLIANCE  = Color3.fromRGB(214, 218, 222)
local APPL_DARK  = Color3.fromRGB(52, 56, 64)
local CABINET    = Color3.fromRGB(40, 70, 72)
local SHADE      = Color3.fromRGB(246, 232, 204)
local LEAVES     = Color3.fromRGB(56, 118, 66)
local TERRACOTTA = Color3.fromRGB(176, 96, 64)

local TINTS = {
    washer              = { APPLIANCE, M.Metal, APPL_DARK, M.Metal },
    dryer               = { APPLIANCE, M.Metal, APPL_DARK, M.Metal },
    washerDryerStacked  = { APPLIANCE, M.Metal, APPL_DARK, M.Metal },
    kitchenFridgeLarge  = { Color3.fromRGB(196, 200, 206), M.Metal, APPL_DARK, M.Metal },
    kitchenFridgeSmall  = { Color3.fromRGB(196, 200, 206), M.Metal, APPL_DARK, M.Metal },
    kitchenStove        = { APPL_DARK, M.Metal, APPLIANCE, M.Metal },
    kitchenSink         = { CABINET, M.Wood, APPLIANCE, M.Metal },
    kitchenCabinet      = { CABINET, M.Wood, BRASS, M.Metal },
    kitchenCabinetUpper = { CABINET, M.Wood, BRASS, M.Metal },
    kitchenCoffeeMachine = { Color3.fromRGB(40, 42, 48), M.Metal, APPLIANCE, M.Metal },
    kitchenMicrowave    = { Color3.fromRGB(40, 42, 48), M.Metal, APPLIANCE, M.Metal },
    bookcaseOpen        = { WALNUT, M.WoodPlanks, WALNUT_DK, M.Wood },
    bookcaseClosedWide  = { WALNUT, M.WoodPlanks, WALNUT_DK, M.Wood },
    bedDouble           = { Color3.fromRGB(236, 228, 214), M.Fabric, WALNUT, M.Wood },
    loungeSofa          = { Color3.fromRGB(38, 92, 96), M.Fabric, WALNUT_DK, M.Wood },
    loungeChair         = { Color3.fromRGB(196, 150, 64), M.Fabric, WALNUT_DK, M.Wood },
    loungeChairRelax    = { Color3.fromRGB(150, 60, 76), M.Fabric, WALNUT, M.Wood },
    benchCushion        = { Color3.fromRGB(160, 70, 86), M.Fabric, WALNUT, M.Wood },
    chairDesk           = { Color3.fromRGB(34, 32, 34), M.Leather, Color3.fromRGB(120, 124, 130), M.Metal },
    chairCushion        = { WALNUT, M.Wood, Color3.fromRGB(236, 226, 206), M.Fabric },
    stoolBar            = { Color3.fromRGB(34, 32, 34), M.Leather, BRASS, M.Metal },
    tableCloth          = { Color3.fromRGB(226, 208, 176), M.Fabric, WALNUT, M.Wood },
    tableCoffeeGlass    = { Color3.fromRGB(170, 200, 200), M.Glass, BRASS, M.Metal },
    sideTableDrawers    = { WALNUT, M.Wood, BRASS, M.Metal },
    cabinetTelevision   = { WALNUT, M.Wood, BRASS, M.Metal },
    televisionModern    = { Color3.fromRGB(18, 18, 22), M.Metal, Color3.fromRGB(40, 40, 46), M.Metal },
    laptop              = { Color3.fromRGB(48, 50, 56), M.Metal, Color3.fromRGB(20, 20, 24), M.Metal },
    computerKeyboard    = { Color3.fromRGB(48, 50, 56), M.Metal, Color3.fromRGB(20, 20, 24), M.Metal },
    pottedPlant         = { LEAVES, M.LeafyGrass, TERRACOTTA, M.Plaster, top = { LEAVES, M.LeafyGrass } },
    rugRound            = { Color3.fromRGB(150, 46, 56), M.Carpet, Color3.fromRGB(214, 180, 110), M.Carpet },
    rugRectangle        = { Color3.fromRGB(110, 44, 52), M.Carpet, Color3.fromRGB(214, 180, 110), M.Carpet },
    bear                = { Color3.fromRGB(150, 105, 70), M.Fabric, Color3.fromRGB(40, 30, 24), M.Fabric },
    lampSquareFloor     = { SHADE, M.Fabric, BRASS, M.Metal, top = { SHADE, M.Fabric } },
    lampSquareTable     = { SHADE, M.Fabric, BRASS, M.Metal, top = { SHADE, M.Fabric } },
    lampRoundTable      = { SHADE, M.Fabric, BRASS, M.Metal, top = { SHADE, M.Fabric } },
    ceilingFan          = { WALNUT, M.Wood, BRASS, M.Metal },
    trashcan            = { Color3.fromRGB(60, 64, 70), M.Metal, Color3.fromRGB(40, 42, 46), M.Metal },
    cardboardBoxClosed  = { Color3.fromRGB(176, 138, 92), M.Cardboard, Color3.fromRGB(150, 116, 76), M.Cardboard },
    cardboardBoxOpen    = { Color3.fromRGB(176, 138, 92), M.Cardboard, Color3.fromRGB(150, 116, 76), M.Cardboard },
}

local function tintProp(m)
    if not m or not m.Parent then return end
    local t = TINTS[m.Name]
    if not t then return end
    local parts = {}
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end
    if #parts == 0 then return end
    local main, best, top, topY = nil, -1, nil, -math.huge
    for _, p in ipairs(parts) do
        local v = p.Size.X * p.Size.Y * p.Size.Z
        if v > best then main, best = p, v end
        local y = p.Position.Y + p.Size.Y / 2
        if y > topY then top, topY = p, y end
    end
    for _, p in ipairs(parts) do
        local col, mat = t[3], t[4]
        if p == main then col, mat = t[1], t[2] end
        if t.top and p == top then col, mat = t.top[1], t.top[2] end
        pcall(function()
            -- a MeshPart with a texture ignores Color; the furniture kit is flat-colour
            if p:IsA("MeshPart") and p.TextureID ~= "" then p.TextureID = "" end
        end)
        p.Color = col
        p.Material = mat
    end
end

-- ──────────────────────────────────────────────
-- BUILD
-- ──────────────────────────────────────────────
function VillaBuilder:build(folder)
    local root = Instance.new("Folder")
    root.Name = "VillaRosa"
    root.Parent = folder

    SEGMENTS = {}
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
    self:_hall(sub(root, "GrandHall"), props, keycardSpots, hideSpots, lootSpots)
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
    self:_grounds(sub(root, "Grounds"), props)
    self:_roof(roofF)
    local cameras = self:_cameras(sub(root, "Cameras"))

    -- dark corners + unlit corridor ends (no lamp reaches these)
    local sz = sub(root, "ShadowZones")
    shadowZone(sz, shadowZones, "Shadow_CorridorWest", -41.5, -69.5, -33, -58.5)
    shadowZone(sz, shadowZones, "Shadow_CorridorEast", 33, -69.5, 41.5, -58.5)
    shadowZone(sz, shadowZones, "Shadow_BedroomNW", -41.5, -95.5, -34, -88.8)
    shadowZone(sz, shadowZones, "Shadow_OfficeSE", -20, -43.5, -14.5, -38.5)
    shadowZone(sz, shadowZones, "Shadow_Pantry", 33.5, -55.3, 41.5, -52)

    -- v2.1 finishes: per-room wallpaper / dado / skirting + patterned floors
    local finishes = sub(root, "Finishes")
    self:_paintWalls(finishes)
    self:_floorDetail(finishes)

    -- Kenney props load async and never error. v2.1: every furniture model is
    -- recoloured as it arrives (they were rendering as plain white blocks).
    local propsF = sub(root, "Props")
    propsF.ChildAdded:Connect(function(m)
        task.defer(tintProp, m)
    end)
    KenneyLoader.placeMany(props, propsF)

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

    print("[VillaBuilder] Villa Rosa v3 built 🌴🦩")

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
        -- v2.1: parked INSIDE the walled service yard, nose to the open vehicle
        -- gate (x 42.6..50.2, z -27.2). Drive straight ahead (south) to the street.
        getawayCFrame = CFrame.lookAt(GETAWAY_POS, GETAWAY_POS + PZ * 10),
        openSign = openSign,

        vault = vault,
        keycardDoors = { keycardDoor },
        keycardSpots = keycardSpots,
        breaker = breaker,
        cameras = cameras,
        laserRows = laserRows,
        -- v3 (docs/V3_SPEC.md §2.1): every spot has kind/pool/visual + flags.
        -- Hidden SecretStash spots also carry reveal(show) — see _officeStash.
        lootSpots = lootSpots,
        poolNames = {
            hall = "Grand Hall", gallery = "Art Gallery", office = "Office",
            bedroom = "Master Bedroom", cellar = "Wine Cellar", vault = "Vault",
        },
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
