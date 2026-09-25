--[[
    HEIST CREW — MiamiBuilder
    ────────────────────────────────────────────────
    v1.0 "NEON MIAMI" world art (2026-09-25). Malachi's pick:
    "Vice City at midnight — pastel art-deco, pink/teal neon, palm trees,
    beach + ocean, neon reflecting on wet streets."

    What it builds (coordinates: docs/V1_SPEC.md §1):
      • Midnight lighting preset (moon, stars, purple/teal haze, neon bloom)
      • Lawn (Part, south of the beach) + Terrain beach, marina sand spit, ocean
      • Ocean Drive extension x -150..-120 / 120..150 (+ streetlights), and
        wet-street puddles that catch the neon
      • 7 art-deco buildings on the spec lots: pastel Plaster, white eyebrows,
        a fin with a vertical neon name, roofline neon tube, lit window grid
        (SurfaceGui, not parts), door + striped awning, facade uplights
      • Procedural palms along Ocean Drive, at the villa garden, the safehouse
        driveway, on the beach and the lawn
      • Beach: 2 lifeguard towers, striped umbrellas + loungers
      • Marina: pier on posts, an 80s speedboat, the DROP-OFF ring + sign
      • 4 parked pastel 80s cars along the kerbs
      • skinSafehouse(): pastel stucco + deco fins/bands/parapet over the brick
        warehouse, big "RIVERSIDE AUTO" neon sign, two neon wall lamps

    Art rules (docs/ART_DIRECTION.md): Neon only on thin tubes, bulbs, stripes
    and lenses. Every word is on a surface (SurfaceGui). Every part has a real
    Material. Everything anchored; decoration CanCollide=false.

    v2.0 "BIGGER" (2026-09-25, docs/V2_SPEC.md §1 + §8):
      • Re-laid out for the v2 map: villa x -42..42 z -96..-38, beach z -100..-120,
        ocean north of that, marina ring (106,-110), pier from z -114 north.
        Deco hotels moved onto the v2 lots only (north x -62 / 62 / west of
        -110, south x -116). Sunny's Mart + Ocean Bank lots are left EMPTY.
        No parked car sits in a traffic lane any more (AmbientService drives them).
      • MIAMI POLICE station + jail, x -104..-80 z -52..-28, front faces south:
        lobby + front desk, HOLDING CELLS corridor, 3 barred cells (sliding bar
        doors), 2 parked cruisers on pads either side.
      • City life: wayfinding signs (arrows to every heist + the marina), a
        MARINA gantry over the drive route, street-name blades, crosswalks, a
        bus stop, hydrants, newspaper boxes, alleys with dumpsters + crates,
        two parking lots, two deco rooftops you can climb (TrussPart ladders),
        beach promenade lamps.

    PUBLIC API:
        MiamiBuilder:applyLighting()
        MiamiBuilder:build(folder) -> {
            jail = {
                cells   = { { inside = CFrame, door = BasePart }, ... },  -- 3 cells
                release = CFrame,   -- on the sidewalk outside the station door, facing the street
            },
        }
            Each cell door is ONE BasePart (invisible collision slab, CanCollide
            true) with the visible bars parented under it. Attributes on the
            door: Cell (int), Open (bool), SlideX (studs it slides east to open).
        MiamiBuilder.setCellOpen(door, open, instant?)
            Slides the bar door (and its bars) east to open / back to close.
            Collision stays on — the slab simply moves out of the doorway.
        MiamiBuilder.palm(parent, position, height?, leanDir?, seed?) -> Model
            leanDir: horizontal direction of the lean. Its magnitude (0.3..2,
            default 1) scales how far the crown leans (~20% of height at 1).
        MiamiBuilder.buildCar(parent, cf, opts?) -> Model, rootPart?
            Low-poly 80s car. cf = ground-contact CFrame (local -Z = front).
            opts: paint, stripe, police (bool), taxi (bool), lights (bool),
            weld (bool: parts welded to an anchored invisible Root placed AT cf →
            move the car by setting Root.CFrame = new ground-contact CFrame),
            noQuery (bool: CanQuery/CanTouch off
            so vehicle probes + raycasts ignore it), name.
        MiamiBuilder.SIDEWALK = { northZ, southZ }   walking lines AmbientService uses
        MiamiBuilder:skinSafehouse(folder)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local okKenney, KenneyLoader = pcall(require, script.Parent:WaitForChild("KenneyLoader", 5))
if not okKenney then KenneyLoader = nil end

local MiamiBuilder = {}

-- Pedestrian walking lines (AmbientService). Chosen so a walker clears the
-- sidewalk palms, lamp poles and every sign/hydrant this file puts down —
-- all street furniture sits on the OUTER edge of each sidewalk.
MiamiBuilder.SIDEWALK = { northZ = -23.0, southZ = -4.8 }

local W = Constants.WORLD
local M = Constants.MIAMI

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.new(1, 1, 1)

local PASTEL = {}
for i, t in ipairs(M.PASTELS) do PASTEL[i] = rgb(t) end
local NEON = {}
for i, t in ipairs(M.NEONS) do NEON[i] = rgb(t) end
local PINK, CYAN, PURPLE, ORANGE = NEON[1], NEON[2], NEON[3], NEON[4]
local STUCCO = rgb(M.STUCCO)

local SIGN_DARK  = Color3.fromRGB(18, 16, 30)
local METAL_DARK = Color3.fromRGB(40, 42, 50)
local CHROME     = Color3.fromRGB(196, 200, 208)
local WARM_LIGHT = Color3.fromRGB(255, 200, 140)
local DARK_GLASS = Color3.fromRGB(24, 30, 56)
local PAVING     = Color3.fromRGB(176, 170, 162)

-- decoration that players / cars should never snag on
local DECO = { CanCollide = false }
local GLOW = { CanCollide = false, CastShadow = false }

-- ──────────────────────────────────────────────
-- helpers (same style as SafehouseBuilder)
-- ──────────────────────────────────────────────
local function inst(class, props, parent)
    local p = Instance.new(class)
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

local function part(props, parent)
    return inst("Part", props, parent)
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

-- CFrame at `pos` whose local X axis points along `xAxis` (cylinders run along X)
local function axisCF(pos, xAxis)
    local x = xAxis.Unit
    local helper = (math.abs(x.Y) < 0.9) and UP or Vector3.new(1, 0, 0)
    local y = (helper - x * helper:Dot(x)).Unit
    return CFrame.fromMatrix(pos, x, y)
end

-- Cylinder from point a to point b
local function cyl(name, a, b, diameter, color, material, parent, extra)
    local props = {
        Name = name,
        Shape = Enum.PartType.Cylinder,
        Size = Vector3.new((b - a).Magnitude, diameter, diameter),
        CFrame = axisCF((a + b) / 2, b - a),
        Color = color,
        Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function ball(name, pos, d, color, material, parent, extra)
    local props = {
        Name = name, Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d),
        Position = pos, Color = color, Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function gui(p, face, pps, brightness, lightInfluence)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 40
    g.LightInfluence = lightInfluence or 0
    g.Brightness = brightness or 1
    g.Parent = p
    return g
end

local function gframe(parent, x, y, w, h, color, transparency)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Position = UDim2.fromScale(x, y)
    f.Size = UDim2.fromScale(w, h)
    f.BackgroundColor3 = color or WHITE
    f.BackgroundTransparency = transparency or 0
    f.Parent = parent
    return f
end

-- Neon-tube text: a hot, near-white core with a coloured halo (UIStroke)
local function neonLabel(parent, str, color, props, strokePx)
    local l = UITheme.label({
        Text = str,
        TextColor3 = color:Lerp(WHITE, 0.35),
        FontFace = UITheme.F.display,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        Size = UDim2.fromScale(1, 1),
    })
    for k, v in pairs(props or {}) do l[k] = v end
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = strokePx or 3
    s.Transparency = 0.4
    s.Parent = l
    l.Parent = parent
    return l
end

local function pointLight(parent, color, brightness, range, shadows)
    local l = Instance.new("PointLight")
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Shadows = shadows or false
    l.Parent = parent
    return l
end

local function spotLight(parent, face, color, brightness, range, angle, shadows)
    local l = Instance.new("SpotLight")
    l.Face = face
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Angle = angle
    l.Shadows = shadows or false
    l.Parent = parent
    return l
end

-- Small ground fixture throwing a coloured cone straight up (palms, facades)
local function uplight(parent, pos, color, range, angle, brightness)
    local fx = box("Uplight", pos.X - 0.35, pos.Y, pos.Z - 0.35, pos.X + 0.35, pos.Y + 0.35, pos.Z + 0.35,
        METAL_DARK, Enum.Material.Metal, parent, DECO)
    spotLight(fx, Enum.NormalId.Top, color, brightness or 2.4, range or 20, angle or 40)
    return fx
end

-- Dark sign board with a glowing neon word + a real light in the same colour
local function neonBoard(parent, name, x0, y0, z0, x1, y1, z1, face, str, color, pps)
    local board = box(name, x0, y0, z0, x1, y1, z1, SIGN_DARK, Enum.Material.Metal, parent, DECO)
    local g = gui(board, face, pps or 40, 2.5, 0)
    neonLabel(g, str, color, { Size = UDim2.fromScale(0.9, 0.78), Position = UDim2.fromScale(0.05, 0.11) })
    pointLight(board, color, 1.1, 10)
    return board
end

local function folder(parent, name)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

-- ──────────────────────────────────────────────
-- 🌙 LIGHTING — midnight on Ocean Drive
-- ──────────────────────────────────────────────
function MiamiBuilder:applyLighting()
    Lighting.ClockTime = 0.3              -- just after midnight, moon up
    Lighting.GeographicLatitude = 25.8    -- Miami
    Lighting.Brightness = 1.4             -- moonlight strength
    -- Ambient = what reaches under roofs. Stays DARK so interiors are stealth
    -- spaces lit only by their own lamps. OutdoorAmbient keeps streets readable.
    Lighting.Ambient = Color3.fromRGB(22, 20, 34)
    Lighting.OutdoorAmbient = Color3.fromRGB(100, 70, 135)
    Lighting.ColorShift_Top = Color3.fromRGB(120, 100, 200)    -- lilac moonlight on top faces
    Lighting.ColorShift_Bottom = Color3.fromRGB(30, 16, 48)
    Lighting.ExposureCompensation = 0.15
    Lighting.GlobalShadows = true
    Lighting.ShadowSoftness = 0.25
    Lighting.EnvironmentDiffuseScale = 0.3
    Lighting.EnvironmentSpecularScale = 1   -- wet, glossy look on glass/water/puddles
    Lighting.FogColor = Color3.fromRGB(38, 20, 58)
    Lighting.FogStart = 180
    Lighting.FogEnd = 900

    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect")
            or child:IsA("ColorCorrectionEffect") then
            child:Destroy()
        end
    end

    -- Roblox default sky textures (left unset) + a big star field + moon
    local sky = Instance.new("Sky")
    sky.StarCount = 3000
    sky.CelestialBodiesShown = true
    sky.MoonAngularSize = 14
    sky.SunAngularSize = 8
    sky.Parent = Lighting

    -- Purple haze with a teal fall-off toward the horizon
    local atmo = Instance.new("Atmosphere")
    atmo.Density = 0.34
    atmo.Offset = 0.12
    atmo.Color = Color3.fromRGB(120, 80, 170)
    atmo.Decay = Color3.fromRGB(40, 140, 160)
    atmo.Glare = 0.25
    atmo.Haze = 1.8
    atmo.Parent = Lighting

    -- Only things brighter than white bloom: neon + lit signs glow, white
    -- stucco under a streetlight does not smear.
    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = 0.55
    bloom.Size = 26
    bloom.Threshold = 0.97
    bloom.Parent = Lighting

    local cc = Instance.new("ColorCorrectionEffect")
    cc.Brightness = 0
    cc.Contrast = 0.12
    cc.Saturation = 0.15
    cc.TintColor = Color3.fromRGB(255, 236, 252)   -- slight magenta
    cc.Parent = Lighting

    print("[MiamiBuilder] Midnight lighting applied 🌙")
end

-- ──────────────────────────────────────────────
-- 🌴 PALM TREE
-- ──────────────────────────────────────────────
local TRUNK_A = Color3.fromRGB(122, 94, 64)
local TRUNK_B = Color3.fromRGB(104, 80, 54)
local TRUNK_RING = Color3.fromRGB(84, 64, 44)
local LEAF_A = Color3.fromRGB(58, 122, 60)
local LEAF_B = Color3.fromRGB(80, 146, 68)
local LEAF_DEAD = Color3.fromRGB(128, 104, 64)
local CROWN = Color3.fromRGB(88, 96, 54)
local COCONUT = Color3.fromRGB(96, 72, 40)

function MiamiBuilder.palm(parent, position, height, leanDir, seed)
    height = height or 18
    local s = seed or (math.floor(math.abs(position.X * 7919 + position.Z * 104729 + height * 31)) % 2147483000)
    local rng = Random.new(s)

    local model = Instance.new("Model")
    model.Name = "Palm"

    -- how far (and which way) the crown drifts from the base
    local lean
    local flat = leanDir and Vector3.new(leanDir.X, 0, leanDir.Z) or nil
    if flat and flat.Magnitude > 0.01 then
        lean = flat.Unit * height * 0.2 * math.clamp(flat.Magnitude, 0.3, 2)
    else
        local a = rng:NextNumber(0, math.pi * 2)
        lean = Vector3.new(math.cos(a), 0, math.sin(a)) * height * rng:NextNumber(0.12, 0.24)
    end
    -- the bend grows toward the top, so the trunk curves instead of tilting
    local function trunkAt(t)
        return position + UP * (height * t) + lean * (t ^ 1.7)
    end

    -- Trunk: tapered segments in alternating browns, with a darker collar at
    -- each joint — reads as the ringed bark of a real palm.
    local SEGS = 6
    for i = 1, SEGS do
        local a, b = trunkAt((i - 1) / SEGS), trunkAt(i / SEGS)
        if i == 1 then a = a - UP * 0.6 end
        local dir = (b - a).Unit
        local d = 1.55 - 0.55 * ((i - 1) / (SEGS - 1))
        cyl("Trunk", a - dir * 0.12, b + dir * 0.12, d, (i % 2 == 0) and TRUNK_A or TRUNK_B,
            Enum.Material.Wood, model)
        if i < SEGS then
            cyl("TrunkRing", b - dir * 0.14, b + dir * 0.14, d + 0.14, TRUNK_RING, Enum.Material.Wood, model, DECO)
        end
    end

    local top = trunkAt(1)
    ball("Crown", top + UP * 0.1, 1.7, CROWN, Enum.Material.Grass, model, DECO)

    -- coconuts tucked under the crown
    local c0 = rng:NextNumber(0, math.pi * 2)
    for k = 0, 2 do
        local a = c0 + k * (math.pi * 2 / 3)
        ball("Coconut", top + Vector3.new(math.cos(a), 0, math.sin(a)) * 0.7 - UP * 0.75, 0.85,
            COCONUT, Enum.Material.Wood, model, DECO)
    end

    -- Fronds: 3 chained leaf segments each, arching up then drooping,
    -- tapering to a pointed tip. Upper/lower tiers alternate.
    local scale = math.clamp(height / 18, 0.8, 1.25)
    local nFronds = rng:NextInteger(8, 10)
    local phase = rng:NextNumber(0, math.pi * 2)
    for i = 1, nFronds do
        local yaw = phase + i * (math.pi * 2 / nFronds) + rng:NextNumber(-0.22, 0.22)
        local upper = (i % 2 == 1)
        local p1 = upper and rng:NextNumber(34, 50) or rng:NextNumber(10, 24)
        local p2 = p1 - rng:NextNumber(28, 38)
        local p3 = p2 - rng:NextNumber(30, 44)
        local pitches = { p1, p2, p3 }
        local k0 = upper and 0.85 or 1
        local lens = { 2.4 * scale * k0, 2.7 * scale * k0, 2.3 * scale * k0 }
        local widths = { 1.15, 1.55, 1.55 }
        local drift = rng:NextNumber(-0.09, 0.09)
        local col = upper and LEAF_B or LEAF_A
        local mat = upper and Enum.Material.LeafyGrass or Enum.Material.Grass

        local hd0 = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
        local start = top + UP * 0.35 + hd0 * 0.3
        for k = 1, 3 do
            local p = math.rad(pitches[k])
            local y = yaw + drift * (k - 1)
            local hd = Vector3.new(math.cos(y), 0, math.sin(y))
            local dir = hd * math.cos(p) + UP * math.sin(p)
            local len = lens[k]
            local c = start + dir * (len / 2)
            local look = CFrame.lookAt(c, c + dir)
            if k < 3 then
                part({
                    Name = "Frond", Size = Vector3.new(widths[k], 0.12, len + 0.25),
                    CFrame = look * CFrame.Angles(0, 0, (k == 1) and 0.18 or -0.14),
                    Color = col, Material = mat, CanCollide = false,
                }, model)
            else
                -- WedgePart turned on its side: a flat triangle = pointed leaf tip
                inst("WedgePart", {
                    Name = "FrondTip", Size = Vector3.new(0.12, widths[k], len),
                    CFrame = look * CFrame.Angles(0, 0, (i % 2 == 0) and math.rad(90) or math.rad(-90)),
                    Color = col, Material = mat, CanCollide = false,
                }, model)
            end
            start = start + dir * len
        end
    end

    -- two dead brown fronds hanging down the trunk
    for k = 1, 2 do
        local yaw = phase + k * math.pi + 0.6
        local p = math.rad(-66)
        local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * math.cos(p) + UP * math.sin(p)
        local c = top - UP * 0.2 + dir * 1.5
        part({
            Name = "DeadFrond", Size = Vector3.new(0.9, 0.1, 3),
            CFrame = CFrame.lookAt(c, c + dir), Color = LEAF_DEAD, Material = Enum.Material.Grass,
            CanCollide = false,
        }, model)
    end

    model.Parent = parent
    return model
end

-- ──────────────────────────────────────────────
-- 🌍 GROUND: lawn part + Terrain beach / ocean
-- ──────────────────────────────────────────────
function MiamiBuilder:_ground(f)
    -- v2: the sand starts at z -102 (WORLD.BEACH_Z0). Terrain boundaries sit on
    -- the 4-stud voxel grid, so the sand block runs z -100..-120 and the lawn
    -- part stops at -100 (a lawn part and sand both topping out at y 0 over
    -- the same strip would z-fight).
    local lawnNorth = -100
    box("Lawn", -300, -2, lawnNorth, 300, 0, 220, Color3.fromRGB(58, 112, 64), Enum.Material.Grass, f)

    local T = workspace.Terrain
    T.WaterColor = Color3.fromRGB(20, 110, 130)
    T.WaterReflectance = 1
    T.WaterTransparency = 0.35
    T.WaterWaveSize = 0.12
    T.WaterWaveSpeed = 8

    -- All boundaries except the water surface sit on the 4-stud voxel grid so
    -- FillBlocks overwrite each other cleanly. Order matters (later wins).
    -- 1. Ocean: z -120 .. -436, surface ≈ y -0.6
    T:FillBlock(CFrame.new(0, -6.3, -278), Vector3.new(800, 11.4, 316), Enum.Material.Water)
    -- 2. Seabed under it
    T:FillBlock(CFrame.new(0, -16, -278), Vector3.new(800, 8, 316), Enum.Material.Sand)
    -- 3. Shallow shelf just off the beach (shows through the clear water)
    T:FillBlock(CFrame.new(0, -8, -126), Vector3.new(600, 8, 12), Enum.Material.Sand)
    -- 4. The beach: z -100 .. -120, top at y 0
    T:FillBlock(CFrame.new(0, -8, -110), Vector3.new(600, 16, 20), Enum.Material.Sand)
    -- 5. Marina spit: the drop-off ring (radius 14 around z -110) reaches
    --    z -124, so the sand runs out to z -128 around it (x 88..124).
    T:FillBlock(CFrame.new(106, -8, -124), Vector3.new(36, 16, 8), Enum.Material.Sand)
end

-- ──────────────────────────────────────────────
-- 🛣 OCEAN DRIVE extension + streetlights + puddles
-- ──────────────────────────────────────────────
local function streetlight(f, x, side)
    local zc, hw = W.STREET_Z, W.STREET_HALF_WIDTH
    local z = zc + side * (hw + 3.8)
    box("LightPole", x - 0.25, 0.5, z - 0.25, x + 0.25, 12, z + 0.25, METAL_DARK, Enum.Material.Metal, f)
    local armEnd = z - side * 3
    box("LightArm", x - 0.15, 11.6, math.min(z, armEnd), x + 0.15, 11.9, math.max(z, armEnd), METAL_DARK, Enum.Material.Metal, f)
    local head = box("LightHead", x - 0.5, 11.3, armEnd - 0.9, x + 0.5, 11.8, armEnd + 0.9, METAL_DARK, Enum.Material.Metal, f)
    box("LightLens", x - 0.35, 11.2, armEnd - 0.7, x + 0.35, 11.3, armEnd + 0.7, WARM_LIGHT, Enum.Material.Neon, f, GLOW)
    spotLight(head, Enum.NormalId.Bottom, WARM_LIGHT, 2.2, 22, 115, true)
end

function MiamiBuilder:_streetExtension(f)
    local zc, hw = W.STREET_Z, W.STREET_HALF_WIDTH
    local asphalt = Color3.fromRGB(46, 48, 52)
    local walk = Color3.fromRGB(150, 150, 148)
    local yellow = Color3.fromRGB(230, 190, 60)

    for _, seg in ipairs({ { -150, -120 }, { 120, 150 } }) do
        local x0, x1 = seg[1], seg[2]
        box("Asphalt", x0, -0.2, zc - hw, x1, 0.2, zc + hw, asphalt, Enum.Material.Asphalt, f, { Reflectance = 0.04 })
        for _, side in ipairs({ -1, 1 }) do
            local edge = zc + side * hw
            box("Kerb", x0, 0, math.min(edge, edge + side * 0.6), x1, 0.55, math.max(edge, edge + side * 0.6),
                Color3.fromRGB(175, 175, 172), Enum.Material.Concrete, f)
            local w0, w1 = edge + side * 0.6, edge + side * 4.6
            box("Sidewalk", x0, 0, math.min(w0, w1), x1, 0.5, math.max(w0, w1), walk, Enum.Material.Concrete, f)
        end
        -- dashes continue the existing 10-stud rhythm (…106, 116 → 126, 136, 146)
        local sgn = (x0 < 0) and -1 or 1
        for _, ax in ipairs({ 126, 136, 146 }) do
            local x = sgn * ax
            box("CentreDash", x - 2, 0.2, zc - 0.18, x + 2, 0.23, zc + 0.18, yellow, Enum.Material.SmoothPlastic, f, DECO)
        end
    end

    -- Streetlights for the new stretches (existing ones stop at |x| = 84).
    -- None on the north side at x 112: that's the marina drive route.
    streetlight(f, -140, -1); streetlight(f, -140, 1)
    streetlight(f, -112, -1); streetlight(f, -112, 1)
    streetlight(f, 90, 1)   -- (v2.0) was 112: stood right in front of the bank steps
    streetlight(f, 140, -1); streetlight(f, 140, 1)
end

-- Rain-slick puddles: near-black glossy glass that catches the neon + lamp
-- highlights (Future lighting renders specular on Glass). Flat, no collision.
function MiamiBuilder:_puddles(f)
    local spots = {
        { -138, -17 }, { -112, -9.5 }, { -86, -18.5 }, { -64, -10 }, { -40, -19 }, { -17, -9 },
        { 14, -18 }, { 36, -10.5 }, { 63, -16.5 }, { 92, -8.5 }, { 116, -19 }, { 141, -12 },
    }
    local rng = Random.new(1985)
    for _, sp in ipairs(spots) do
        for k = 1, 2 do
            local d = rng:NextNumber(2.6, 4.6) * ((k == 1) and 1 or 0.7)
            local ox = (k == 1) and 0 or rng:NextNumber(-1.6, 1.6)
            local oz = (k == 1) and 0 or rng:NextNumber(-0.8, 0.8)
            part({
                Name = "Puddle", Shape = Enum.PartType.Cylinder,
                Size = Vector3.new(0.02 + k * 0.004, d, d * rng:NextNumber(0.6, 0.9)),
                CFrame = CFrame.new(sp[1] + ox, 0.205 + k * 0.003, sp[2] + oz)
                    * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(90)),
                Color = Color3.fromRGB(16, 18, 32), Material = Enum.Material.Glass,
                Transparency = 0.25, Reflectance = 0.3,
                CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false,
            }, f)
        end
    end
end

-- ──────────────────────────────────────────────
-- 🏨 ART-DECO BUILDING
-- ──────────────────────────────────────────────
local LIT_COLORS = {
    Color3.fromRGB(240, 190, 120), Color3.fromRGB(240, 190, 120), Color3.fromRGB(236, 172, 108),
    Color3.fromRGB(236, 172, 108), Color3.fromRGB(232, 150, 190), Color3.fromRGB(150, 195, 235),
}

local function windowPane(litRoot, darkRoot, fx, fy, fw, fh, isLit, rng)
    if isLit then
        local col = LIT_COLORS[rng:NextInteger(1, #LIT_COLORS)]
        local f = gframe(litRoot, fx, fy, fw, fh, col)
        local blind = rng:NextNumber(0, 0.5)
        if blind > 0.15 then
            gframe(f, 0, 0, 1, blind, col:Lerp(Color3.new(0, 0, 0), 0.45))
        end
        gframe(f, 0.47, 0, 0.06, 1, Color3.fromRGB(70, 56, 46))
    else
        local f = gframe(darkRoot, fx, fy, fw, fh, DARK_GLASS)
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(200, 205, 225)
        s.Transparency = 0.55
        s.Thickness = 1
        s.Parent = f
        gframe(f, 0.47, 0, 0.06, 1, Color3.fromRGB(70, 74, 92))
    end
end

-- Fit k windows of width `ww` (gap 0.8) centred inside [a, b]; append centres
local function fitCols(a, b, ww, out)
    local len = b - a
    local k = math.floor((len + 0.8) / (ww + 0.8))
    if k <= 0 then return end
    local total = k * ww + (k - 1) * 0.8
    local start = a + (len - total) / 2 + ww / 2
    for i = 0, k - 1 do
        table.insert(out, start + i * (ww + 0.8))
    end
end

--[[ spec fields:
    name, cx, frontZ, n (+1 = north lot facing south, -1 = south lot facing north),
    w, d, h, color (pastel), neon (fin letters / roof tube), neon2 (fin tubes),
    finU (0 = centre fin, else corner offset), apron (depth to sidewalk edge),
    sign = { kind = "band"|"side"|"window", text, color }, seed
--]]
function MiamiBuilder:_decoBuilding(parent, b)
    local model = Instance.new("Model")
    model.Name = "Deco_" .. string.gsub(b.name, " ", "")
    local n, w, d, h = b.n, b.w, b.d, b.h
    local hw = w / 2
    local rng = Random.new(b.seed)
    local body = b.color
    local trim = STUCCO
    local plinth = body:Lerp(Color3.fromRGB(60, 50, 70), 0.35)
    local face = (n > 0) and Enum.NormalId.Back or Enum.NormalId.Front   -- face toward the street
    local finU = b.finU

    -- local (u along x, y up, v = depth away from the street) → world
    local function X(u) return b.cx + u end
    local function Z(v) return b.frontZ - n * v end
    local function lb(name, u0, y0, v0, u1, y1, v1, color, mat, extra)
        return box(name, X(u0), y0, Z(v0), X(u1), y1, Z(v1), color, mat, model, extra)
    end
    -- fraction across the street-face GUI (left edge = 0) for local u
    local function gx(u: number): number
        if n > 0 then return (u + hw) / w end
        return (hw - u) / w
    end

    -- ── mass ──
    local bodyPart = lb("Body", -hw, 0, 0, hw, h, d, body, Enum.Material.Plaster)
    lb("Plinth", -hw - 0.15, 0, -0.15, hw + 0.15, 1.0, d + 0.15, plinth, Enum.Material.Concrete)
    lb("Forecourt", -hw, 0, -b.apron, hw, 0.5, 0, PAVING, Enum.Material.Concrete)
    lb("Cornice", -hw - 0.5, h - 0.7, -0.5, hw + 0.5, h, d + 0.5, trim, Enum.Material.Plaster)
    -- stepped (ziggurat) parapet
    lb("Step1", -w * 0.3, h, -0.4, w * 0.3, h + 2, 5, body, Enum.Material.Plaster)
    lb("Step1Cap", -w * 0.3 - 0.2, h + 2, -0.6, w * 0.3 + 0.2, h + 2.35, 5.2, trim, Enum.Material.Plaster)
    lb("Step2", -w * 0.15, h + 2.35, -0.3, w * 0.15, h + 4, 3.5, body, Enum.Material.Plaster)
    lb("Step2Cap", -w * 0.15 - 0.2, h + 4, -0.5, w * 0.15 + 0.2, h + 4.35, 3.7, trim, Enum.Material.Plaster)

    -- thin neon tube just under the cornice lip
    lb("RoofNeon", -hw + 0.3, h - 1.05, -0.62, hw - 0.3, h - 0.85, -0.42, b.neon, Enum.Material.Neon, GLOW)

    -- ── fin with a vertical neon name ──
    local finBottom, finTop = 9.6, h + 6.5
    lb("Fin", finU - 1.5, finBottom, -1.6, finU + 1.5, finTop, 3, trim, Enum.Material.Plaster)
    lb("FinCap", finU - 1.8, finTop, -1.9, finU + 1.8, finTop + 0.5, 3.3, body, Enum.Material.Plaster)
    cyl("FinMast", Vector3.new(X(finU), finTop + 0.5, Z(0.6)), Vector3.new(X(finU), finTop + 3.4, Z(0.6)), 0.22,
        CHROME, Enum.Material.Metal, model, DECO)
    ball("FinBeacon", Vector3.new(X(finU), finTop + 3.55, Z(0.6)), 0.45, b.neon2, Enum.Material.Neon, model, GLOW)
    local panelY0, panelY1 = finBottom + 0.8, finTop - 0.8
    local panel = lb("FinSign", finU - 1.05, panelY0, -1.78, finU + 1.05, panelY1, -1.6, SIGN_DARK, Enum.Material.Metal)
    for _, side in ipairs({ -1, 1 }) do
        lb("FinTube", finU + side * 1.22, finBottom + 0.4, -1.8, finU + side * 1.4, finTop - 0.4, -1.62,
            b.neon2, Enum.Material.Neon, GLOW)
    end
    do
        local PPS = 40
        local g = gui(panel, face, PPS, 2.6, 0)
        local chars = {}
        for c in string.gmatch(b.name, ".") do table.insert(chars, c) end
        local count = #chars
        local cellPx = (panelY1 - panelY0) / count * PPS
        -- one fixed size for every letter (TextScaled would size each differently)
        local size = math.floor(math.min(cellPx * 0.9, 2.1 * PPS * 0.9))
        local holder = Instance.new("Frame")
        holder.BackgroundTransparency = 1
        holder.Size = UDim2.fromScale(1, 1)
        holder.Parent = g
        local list = Instance.new("UIListLayout")
        list.FillDirection = Enum.FillDirection.Vertical
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.Parent = holder
        for i, c in ipairs(chars) do
            neonLabel(holder, c, b.neon, {
                Size = UDim2.new(1, 0, 1 / count, 0), TextScaled = false, TextSize = size, LayoutOrder = i,
            }, math.max(2, math.floor(size * 0.06)))
        end
    end
    pointLight(panel, b.neon, 1.5, 18)

    -- ── window rows: eyebrow ledges + lit/dark window grid (SurfaceGui) ──
    local rows = {}
    local base = 8.6
    while base + 4.5 <= h - 3.8 do
        table.insert(rows, base)
        base += 5.5
    end
    local winW = 2.0
    local cols = {}
    fitCols(-hw + 0.9, finU - 2.1, winW, cols)
    fitCols(finU + 2.1, hw - 0.9, winW, cols)

    local litGui = gui(bodyPart, face, 10, 1, 0)       -- warm windows ignore scene lighting
    local darkGui = gui(bodyPart, face, 10, 1, 1)      -- dark glass takes the scene lighting
    local litRoot = gframe(litGui, 0, 0, 1, 1, WHITE, 1)
    local darkRoot = gframe(darkGui, 0, 0, 1, 1, WHITE, 1)

    for _, rb in ipairs(rows) do
        local yTop = rb + 3.6
        for _, u in ipairs(cols) do
            local fx = math.min(gx(u - winW / 2), gx(u + winW / 2))
            windowPane(litRoot, darkRoot, fx, (h - yTop) / h, winW / w, 3.0 / h, rng:NextNumber() < 0.4, rng)
        end
        -- eyebrow ledge over the row, split around the fin
        local e0, e1 = finU - 1.5, finU + 1.5
        local a, c = -hw + 0.6, hw - 0.6
        if e0 - a > 0.5 then lb("Eyebrow", a, rb + 4.0, -1.1, e0, rb + 4.35, 0, trim, Enum.Material.Concrete) end
        if c - e1 > 0.5 then lb("Eyebrow", e1, rb + 4.0, -1.1, c, rb + 4.35, 0, trim, Enum.Material.Concrete) end
    end

    -- side windows (mostly dark) on both flanks
    local sideCols = {}
    fitCols(1.2, d - 1.2, winW, sideCols)
    for _, sideFace in ipairs({ Enum.NormalId.Right, Enum.NormalId.Left }) do
        local sl = gui(bodyPart, sideFace, 10, 1, 0)
        local sd = gui(bodyPart, sideFace, 10, 1, 1)
        local slRoot = gframe(sl, 0, 0, 1, 1, WHITE, 1)
        local sdRoot = gframe(sd, 0, 0, 1, 1, WHITE, 1)
        for _, rb in ipairs(rows) do
            for _, v in ipairs(sideCols) do
                windowPane(slRoot, sdRoot, (v - winW / 2) / d, (h - (rb + 3.6)) / h, winW / d, 3.0 / h,
                    rng:NextNumber() < 0.25, rng)
            end
        end
    end

    -- ── ground floor: display windows, door, awning, entrance light ──
    for _, span in ipairs({ { -hw + 1.0, -3.0 }, { 3.0, hw - 1.0 } }) do
        local a, c = span[1], span[2]
        if c - a > 1 then
            local fx = math.min(gx(a), gx(c))
            local pane = gframe(litRoot, fx, (h - 5.9) / h, (c - a) / w, 4.6 / h, Color3.fromRGB(226, 168, 112))
            local grad = Instance.new("UIGradient")
            grad.Rotation = 90
            grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 120, 110))
            grad.Parent = pane
            gframe(pane, 0.49, 0, 0.02, 1, Color3.fromRGB(60, 50, 44))
            gframe(pane, 0, 0.3, 1, 0.025, Color3.fromRGB(60, 50, 44))
        end
    end

    lb("DoorFrame", -2.6, 0, -0.25, 2.6, 7.2, 0, trim, Enum.Material.Concrete)
    local door = lb("Door", -2.0, 0.1, -0.32, 2.0, 6.6, -0.2, Color3.fromRGB(60, 44, 40), Enum.Material.Glass,
        { Reflectance = 0.2 })
    do
        local g = gui(door, face, 30, 0.9, 0)
        local lobby = gframe(g, 0, 0, 1, 1, Color3.fromRGB(232, 172, 110))
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 90, 80))
        grad.Parent = lobby
        gframe(lobby, 0.485, 0, 0.03, 1, Color3.fromRGB(190, 160, 110))   -- door split (brass)
        gframe(lobby, 0.4, 0.45, 0.02, 0.18, Color3.fromRGB(210, 180, 120))
        gframe(lobby, 0.58, 0.45, 0.02, 0.18, Color3.fromRGB(210, 180, 120))
    end

    -- striped awning, sloping down toward the street
    local awning = part({
        Name = "Awning", Size = Vector3.new(6, 0.2, 3.1),
        CFrame = CFrame.new(X(0), 7.1, Z(-1.5)) * CFrame.Angles(n * math.rad(15), 0, 0),
        Color = trim, Material = Enum.Material.Fabric, CanCollide = false,
    }, model)
    do
        local g = gui(awning, Enum.NormalId.Top, 20, 1, 1)
        for i = 0, 5 do
            gframe(g, i / 6 + 1 / 24, 0, 1 / 12, 1, b.neon2:Lerp(WHITE, 0.25))
        end
    end
    lb("Valance", -3, 6.1, -3.1, 3, 6.75, -2.95, b.neon2:Lerp(WHITE, 0.25), Enum.Material.Fabric, DECO)
    local lamp = lb("EntryLamp", -0.4, 6.6, -1.1, 0.4, 6.95, -0.6, METAL_DARK, Enum.Material.Metal, DECO)
    lb("EntryLens", -0.3, 6.55, -1.0, 0.3, 6.6, -0.7, WARM_LIGHT, Enum.Material.Neon, GLOW)
    pointLight(lamp, WARM_LIGHT, 1.3, 13)

    -- ── art-deco "speed lines" wrapping the corner opposite the fin ──
    local s = (finU > 0.1) and -1 or 1
    for k = 0, 2 do
        local y0 = h - 3.2 + k * 0.55
        lb("SpeedLine", s * (hw - 5.5), y0, -0.2, s * (hw + 0.2), y0 + 0.25, 0, trim, Enum.Material.Plaster)
        lb("SpeedLine", s * hw, y0, -0.2, s * (hw + 0.2), y0 + 0.25, 7, trim, Enum.Material.Plaster)
    end

    -- ── facade uplights (pools of coloured light washing up the wall) ──
    for i, su in ipairs({ -1, 1 }) do
        local u = su * (hw - 2.4)
        uplight(model, Vector3.new(X(u), 0.5, Z(-0.8)), (i == 1) and b.neon or b.neon2, 24, 38, 2.6)
    end

    -- ── roof clutter for the silhouette ──
    local acU = (finU > 0.1) and -hw * 0.45 or hw * 0.4
    lb("RoofAC", acU - 1.5, h, d * 0.55, acU + 1.5, h + 1.6, d * 0.55 + 2.4, CHROME, Enum.Material.Metal)
    if h >= 26 then
        local tv = Vector3.new(X(-acU), h, Z(d - 4))
        cyl("WaterTank", tv, tv + UP * 3.4, 3, Color3.fromRGB(150, 146, 140), Enum.Material.Metal, model)
    end

    -- ── extra neon sign ──
    local sg = b.sign
    if sg then
        local fz0, fz1
        if sg.kind == "band" then          -- "HOTEL" band above the awning
            fz0, fz1 = Z(-0.3), Z(0)
            neonBoard(model, "NeonSign", X(-4), 7.75, fz0, X(4), 9.35, fz1, face, sg.text, sg.color)
        elseif sg.kind == "side" then      -- "COCKTAILS" over the right display window
            fz0, fz1 = Z(-0.25), Z(0)
            neonBoard(model, "NeonSign", X(hw - 7.2), 6.1, fz0, X(hw - 1.0), 7.3, fz1, face, sg.text, sg.color)
        else                               -- "OPEN 24/7" hanging in the left display window
            fz0, fz1 = Z(-0.12), Z(-0.02)
            neonBoard(model, "NeonSign", X(-hw + 1.6), 2.8, fz0, X(-hw + 5.6), 4.2, fz1, face, sg.text, sg.color)
        end
    end

    -- ── v2: climbable rooftop (ladder = { side = ±1 (which flank), v = depth }) ──
    local ld = b.ladder
    if ld then
        -- a low safety rail round the roof edge, with a gap where the ladder lands
        local railH, t = 1.1, 0.3
        local lv0, lv1 = ld.v - 1.6, ld.v + 1.6
        lb("RoofRail", -hw, h, d - t, hw, h + railH, d, trim, Enum.Material.Concrete)
        lb("RoofRail", -hw, h, 0, hw, h + railH, t, trim, Enum.Material.Concrete)
        for _, su in ipairs({ -1, 1 }) do
            local u0, u1 = (su < 0) and -hw or hw - t, (su < 0) and -hw + t or hw
            if su == ld.side then
                if lv0 > t then lb("RoofRail", u0, h, t, u1, h + railH, lv0, trim, Enum.Material.Concrete) end
                if lv1 < d - t then lb("RoofRail", u0, h, lv1, u1, h + railH, d - t, trim, Enum.Material.Concrete) end
            else
                lb("RoofRail", u0, h, t, u1, h + railH, d - t, trim, Enum.Material.Concrete)
            end
        end
        -- TrussPart = Roblox's native climbable ladder (size snaps to 2 studs)
        local H = 2 * math.ceil((h + 2) / 2)
        local tx = X(ld.side * (hw + 1))
        inst("TrussPart", {
            Name = "RoofLadder", Size = Vector3.new(2, H, 2),
            CFrame = CFrame.new(tx, H / 2, Z(ld.v)),
            Color = Color3.fromRGB(70, 74, 86), Material = Enum.Material.Metal,
        }, model)
        -- roof hatch + a couple of loungers: somewhere worth climbing to
        lb("RoofHatch", ld.side * (hw - 3) - 1.2, h, ld.v - 1.2, ld.side * (hw - 3) + 1.2, h + 0.6, ld.v + 1.2,
            METAL_DARK, Enum.Material.DiamondPlate)
        for k = 0, 1 do
            local u = -ld.side * (hw * 0.35) + k * 2.6
            lb("RoofLounger", u - 0.8, h, d * 0.5 - 2, u + 0.8, h + 0.9, d * 0.5 + 2, b.neon2:Lerp(WHITE, 0.45), Enum.Material.Fabric)
        end
        local bulb = lb("RoofLamp", ld.side * (hw - 1.2) - 0.3, h + 3.2, ld.v - 0.3, ld.side * (hw - 1.2) + 0.3,
            h + 3.6, ld.v + 0.3, WARM_LIGHT, Enum.Material.Neon, GLOW)
        lb("RoofLampPole", ld.side * (hw - 1.2) - 0.1, h, ld.v - 0.1, ld.side * (hw - 1.2) + 0.1, h + 3.2, ld.v + 0.1,
            METAL_DARK, Enum.Material.Metal, DECO)
        pointLight(bulb, WARM_LIGHT, 1.2, 14)
    end

    model.Parent = parent
    return model
end

function MiamiBuilder:_buildings(f)
    local P = PASTEL
    local northApron = -26.6 - (-28)   -- building front → outer edge of north sidewalk
    local southApron = 1 - (-1.4)      -- building front → outer edge of south sidewalk
    -- v2 lots (docs/V2_SPEC.md §1). North: centres x -62 (w 22), 62 (w 22),
    -- plus anything west of x -110. South: centre x -116 (w 24). The police
    -- station took FLAMINGO's old lot; the mart + bank took MIRAGE's/SUNSET's.
    local specs = {
        -- north side (front face z -28, facing south onto the street)
        { name = "FLAMINGO", north = true, cx = -130, w = 24, d = 20, h = 30, color = P[1], neon = CYAN, neon2 = PINK, finU = 0,
          sign = { kind = "band", text = "HOTEL", color = PINK } },
        { name = "NEPTUNE", north = true, cx = -62, w = 22, d = 18, h = 22, color = P[2], neon = PINK, neon2 = PURPLE,
          finU = -(22 / 2 - 1.8), sign = { kind = "side", text = "COCKTAILS", color = CYAN },
          ladder = { side = 1, v = 12 } },      -- ladder in the alley toward the villa (x -51)
        { name = "CORAL", north = true, cx = 62, w = 22, d = 18, h = 24, color = P[4], neon = CYAN, neon2 = ORANGE,
          finU = 22 / 2 - 1.8, sign = { kind = "window", text = "OPEN 24/7", color = PINK },
          ladder = { side = -1, v = 12 } },     -- ladder in the alley toward the villa (x 51)
        -- south side (front face z 1, facing north onto the street)
        { name = "LUNA", north = false, cx = -116, w = 24, d = 20, h = 28, color = P[5], neon = PURPLE, neon2 = PINK, finU = 0,
          sign = { kind = "side", text = "COCKTAILS", color = PINK } },
    }
    for i, sp in ipairs(specs) do
        sp.n = sp.north and 1 or -1
        sp.frontZ = sp.north and -28 or 1
        sp.apron = sp.north and northApron or southApron
        sp.seed = 1000 + i * 37
        self:_decoBuilding(f, sp)
    end
end

-- ──────────────────────────────────────────────
-- 🌴 PALM PLACEMENT
-- ──────────────────────────────────────────────
function MiamiBuilder:_palms(f)
    local zc, hw = W.STREET_Z, W.STREET_HALF_WIDTH
    local northZ = zc - hw - 3.2    -- -25.2: outer edge of the north sidewalk
    local southZ = zc + hw + 3.4    -- -2.6: outer edge of the south sidewalk
    local toStreetN = Vector3.new(0, 0, 1)     -- lean over the road, away from facades
    local toStreetS = Vector3.new(0, 0, -1)

    local lit = 0
    local function sidewalkPalm(x, z, lean)
        local rng = Random.new(math.floor(x * 13 + z * 7 + 5000))
        local h = rng:NextNumber(16, 19)
        MiamiBuilder.palm(f, Vector3.new(x, 0.5, z), h, lean * rng:NextNumber(0.95, 1.15))
        lit += 1
        uplight(f, Vector3.new(x, 0.5, z) + lean.Unit * 1.3, (lit % 2 == 0) and PINK or CYAN, 20, 34, 2.2)
    end

    -- Ocean Drive: between streetlights (+ the extension), outer edge.
    -- North skips x 94..122 (marina route) and the police cruiser pads
    -- (x -110..-104, -80..-73). South skips x 28..48 (car alley mouth).
    for _, x in ipairs({ -130, -70, -49, 49, 76, 128, 146 }) do sidewalkPalm(x, northZ, toStreetN) end
    for _, x in ipairs({ -132, -98, -74, 70, 98, 126 }) do sidewalkPalm(x, southZ, toStreetS) end

    -- Villa Rosa front garden pair — at the garden's outer corners, well clear
    -- of the villa itself (x -42..42, z -96..-38) and its front path.
    for _, sx in ipairs({ -1, 1 }) do
        local pos = Vector3.new(sx * 38, 0, -31)
        local lean = Vector3.new(sx * 0.4, 0, 0.8)
        MiamiBuilder.palm(f, pos, 21, lean, 700 + sx)
        uplight(f, pos + lean.Unit * 1.3, PINK, 22, 34, 2.4)
    end

    -- Safehouse driveway pair — tall, leaning out so they frame the sign
    for _, sx in ipairs({ -1, 1 }) do
        local pos = Vector3.new(sx * 13, 0, 1)
        local lean = Vector3.new(sx * 1, 0, -0.55)
        MiamiBuilder.palm(f, pos, 20, lean, 800 + sx)
        uplight(f, pos + lean.Unit * 1.3, CYAN, 22, 34, 2.4)
    end

    -- Beach scatter (on the sand, clear of the towers, umbrellas and marina)
    -- (v2: sand is z -100..-120; the villa's back terrace ends at z -102)
    local beach = {
        { -150, -112, 17 }, { -138, -105, 20 }, { -120, -111, 16 }, { -92, -106, 19 }, { -36, -106, 21 },
        { -4, -115, 18 }, { 40, -106, 19 }, { 86, -106, 17 }, { 132, -108, 20 }, { 146, -104, 16 },
    }
    for i, p in ipairs(beach) do
        MiamiBuilder.palm(f, Vector3.new(p[1], 0, p[2]), p[3], nil, 900 + i)
    end

    -- A few on the lawns behind the lots (clear of the villa, the station,
    -- the bank lot and the marina route x 94..122)
    for i, p in ipairs({ { -148, -60 }, { -120, -66 }, { -60, -68 }, { 70, -66 }, { 138, -60 }, { -146, 30 }, { 146, 30 } }) do
        MiamiBuilder.palm(f, Vector3.new(p[1], 0, p[2]), 18 + (i % 3) * 1.5, nil, 950 + i)
    end
end

-- ──────────────────────────────────────────────
-- 🏖 BEACH: lifeguard towers, umbrellas, loungers
-- ──────────────────────────────────────────────
function MiamiBuilder:_lifeguardTower(parent, x, z, hut, stripeA, stripeB)
    local m = Instance.new("Model")
    m.Name = "LifeguardTower"
    local wood = Color3.fromRGB(150, 112, 78)
    local woodDark = Color3.fromRGB(112, 82, 58)
    -- stilts (sunk into the sand)
    for _, dx in ipairs({ -2.2, 2.2 }) do
        for _, dz in ipairs({ -2.2, 2.2 }) do
            cyl("Stilt", Vector3.new(x + dx, -1.5, z + dz), Vector3.new(x + dx, 6.1, z + dz), 0.6, woodDark,
                Enum.Material.Wood, m)
        end
    end
    -- platform with a deck out front (the tower looks out to sea, north)
    box("Platform", x - 3, 6, z - 4.6, x + 3, 6.4, z + 3, wood, Enum.Material.WoodPlanks, m)
    -- hut
    box("Hut", x - 2.2, 6.4, z - 1.8, x + 2.2, 10.2, z + 2.6, hut, Enum.Material.Plaster, m)
    box("HutStripe", x - 2.26, 7.2, z - 1.86, x + 2.26, 7.65, z + 2.66, stripeA, Enum.Material.Plaster, m, DECO)
    box("HutStripe", x - 2.26, 7.85, z - 1.86, x + 2.26, 8.1, z + 2.66, stripeB, Enum.Material.Plaster, m, DECO)
    local window = box("Window", x - 1.5, 8.35, z - 1.92, x + 1.5, 9.7, z - 1.78, Color3.fromRGB(30, 40, 60),
        Enum.Material.Glass, m, { Reflectance = 0.2 })
    pointLight(window, WARM_LIGHT, 0.8, 10)
    -- striped roof: four bands across
    local roofCols = { stripeA, STUCCO, stripeB, STUCCO }
    for i = 0, 3 do
        local x0 = x - 2.8 + i * 1.4
        box("RoofStripe", x0, 10.2, z - 2.6, x0 + 1.4, 10.65, z + 3.2, roofCols[i + 1], Enum.Material.Plaster, m)
    end
    -- front railing
    box("Rail", x - 3, 7.5, z - 4.55, x + 3, 7.7, z - 4.35, STUCCO, Enum.Material.Wood, m, DECO)
    for _, dx in ipairs({ -2.9, 2.9 }) do
        box("RailPost", x + dx - 0.1, 6.4, z - 4.55, x + dx + 0.1, 7.5, z - 4.35, STUCCO, Enum.Material.Wood, m, DECO)
    end
    -- ramp down the east side
    local rise, run = 6.4, 9.6
    local len = math.sqrt(rise * rise + run * run)
    part({
        Name = "Ramp", Size = Vector3.new(len, 0.3, 2.4),
        CFrame = CFrame.new(x + 3 + run / 2, rise / 2 - 0.1, z + 1.6) * CFrame.Angles(0, 0, -math.atan2(rise, run)),
        Color = wood, Material = Enum.Material.WoodPlanks,
    }, m)
    -- flag
    cyl("FlagPole", Vector3.new(x + 2.5, 10.65, z - 2.3), Vector3.new(x + 2.5, 14.2, z - 2.3), 0.15, CHROME,
        Enum.Material.Metal, m, DECO)
    box("Flag", x + 2.55, 13, z - 2.33, x + 4.15, 14, z - 2.27, Color3.fromRGB(210, 40, 50), Enum.Material.Fabric, m, DECO)
    m.Parent = parent
end

function MiamiBuilder:_umbrellaSet(parent, x, z, col)
    local m = Instance.new("Model")
    m.Name = "BeachUmbrella"
    local apex = Vector3.new(x, 7.2, z)
    cyl("Pole", Vector3.new(x, -0.8, z), apex, 0.2, STUCCO, Enum.Material.Metal, m)
    for i = 0, 5 do
        local yaw = i * (math.pi / 3)
        local p = math.rad(-18)
        local dir = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * math.cos(p) + UP * math.sin(p)
        local c = apex + dir * 1.6
        part({
            Name = "Canopy", Size = Vector3.new(1.95, 0.08, 3.2),
            CFrame = CFrame.lookAt(c, c + dir),
            Color = (i % 2 == 0) and col or Color3.fromRGB(245, 240, 235), Material = Enum.Material.Fabric,
            CanCollide = false,
        }, m)
    end
    ball("Finial", apex + UP * 0.2, 0.35, STUCCO, Enum.Material.Metal, m, DECO)

    -- two loungers facing the ocean (north), backrests to the south
    for _, dx in ipairs({ -2.3, 2.3 }) do
        local lx = x + dx
        box("LoungerFrame", lx - 0.9, 0.7, z - 2.2, lx + 0.9, 1.0, z + 2.2, Color3.fromRGB(236, 232, 226),
            Enum.Material.Wood, m)
        box("LoungerLeg", lx - 0.8, -0.3, z - 2.0, lx + 0.8, 0.7, z - 1.7, CHROME, Enum.Material.Metal, m, DECO)
        box("LoungerLeg", lx - 0.8, -0.3, z + 1.7, lx + 0.8, 0.7, z + 2.0, CHROME, Enum.Material.Metal, m, DECO)
        box("Cushion", lx - 0.8, 1.0, z - 2.1, lx + 0.8, 1.25, z + 0.8, col, Enum.Material.Fabric, m, DECO)
        part({
            Name = "Backrest", Size = Vector3.new(1.6, 0.25, 1.8),
            CFrame = CFrame.new(lx, 1.75, z + 1.55) * CFrame.Angles(math.rad(-50), 0, 0),
            Color = col, Material = Enum.Material.Fabric, CanCollide = false,
        }, m)
    end
    m.Parent = parent
end

function MiamiBuilder:_beach(f)
    -- v2: sand z -100..-120 (towers look out to sea, ramps run east)
    self:_lifeguardTower(f, -72, -111, PASTEL[2], PINK:Lerp(WHITE, 0.2), CYAN:Lerp(WHITE, 0.2))
    self:_lifeguardTower(f, 54, -112, PASTEL[4], CYAN:Lerp(WHITE, 0.2), PURPLE:Lerp(WHITE, 0.3))
    local cols = { Color3.fromRGB(240, 120, 175), Color3.fromRGB(70, 200, 210), Color3.fromRGB(250, 170, 90),
        Color3.fromRGB(170, 120, 230) }
    for i, p in ipairs({ { -110, -108 }, { -52, -107 }, { 20, -108 }, { 76, -108 } }) do
        self:_umbrellaSet(f, p[1], p[2], cols[i])
    end

    -- promenade lamps along the top of the beach: pools of warm light on the sand
    for _, x in ipairs({ -130, -90, 62, 136 }) do
        local z = -101.5
        box("PromenadePost", x - 0.2, 0, z - 0.2, x + 0.2, 8, z + 0.2, METAL_DARK, Enum.Material.Metal, f)
        local head = box("PromenadeLamp", x - 0.55, 8, z - 0.55, x + 0.55, 8.9, z + 0.55, METAL_DARK, Enum.Material.Metal, f, DECO)
        box("PromenadeGlow", x - 0.4, 7.8, z - 0.4, x + 0.4, 8.0, z + 0.4, WARM_LIGHT, Enum.Material.Neon, f, GLOW)
        spotLight(head, Enum.NormalId.Bottom, WARM_LIGHT, 1.6, 18, 110)
    end
end

-- ──────────────────────────────────────────────
-- ⚓ MARINA: pier, speedboat, drop-off ring + sign
-- ──────────────────────────────────────────────
function MiamiBuilder:_speedboat(parent, cf)
    local m = Instance.new("Model")
    m.Name = "Speedboat"
    local HULL = Color3.fromRGB(244, 244, 248)
    -- local: forward = -Z, hull centre y = 0 (≈ waterline at -0.3 below)
    local function bp(class, name, size, offset, color, mat, extra)
        local props = { Name = name, Size = size, CFrame = cf * offset, Color = color, Material = mat }
        for k, v in pairs(extra or {}) do props[k] = v end
        return inst(class, props, m)
    end
    bp("Part", "Hull", Vector3.new(5, 2.2, 11), CFrame.new(0, 0, 2.5), HULL, Enum.Material.Metal)
    -- pointed bow: two side-lying wedges meeting on the centreline
    bp("WedgePart", "BowR", Vector3.new(2.2, 2.5, 5), CFrame.new(1.25, 0, -5.5) * CFrame.Angles(0, 0, math.rad(-90)),
        HULL, Enum.Material.Metal)
    bp("WedgePart", "BowL", Vector3.new(2.2, 2.5, 5), CFrame.new(-1.25, 0, -5.5) * CFrame.Angles(0, 0, math.rad(90)),
        HULL, Enum.Material.Metal)
    bp("Part", "Deck", Vector3.new(4.4, 0.15, 7.2), CFrame.new(0, 1.17, 3.7), Color3.fromRGB(150, 100, 64),
        Enum.Material.WoodPlanks)
    -- hot-pink go-faster stripe down both sides and along the bow
    for _, sx in ipairs({ -1, 1 }) do
        bp("Part", "Stripe", Vector3.new(0.12, 0.3, 11), CFrame.new(sx * 2.55, 0.25, 2.5), PINK, Enum.Material.Neon, GLOW)
        bp("Part", "RubRail", Vector3.new(0.22, 0.22, 11), CFrame.new(sx * 2.56, 1.05, 2.5), METAL_DARK,
            Enum.Material.Metal, DECO)
        local a = Vector3.new(sx * 2.5, 0.25, -3)
        local tip = Vector3.new(0, 0.25, -8)
        local mid = (a + tip) / 2
        local normal = Vector3.new(sx * 5, 0, -2.5).Unit
        mid = mid + normal * 0.06
        bp("Part", "BowStripe", Vector3.new(0.12, 0.3, (tip - a).Magnitude), CFrame.lookAt(mid, mid + (tip - a)),
            PINK, Enum.Material.Neon, GLOW)
    end
    -- raked windshield
    bp("Part", "Windshield", Vector3.new(4.2, 1.3, 0.12), CFrame.new(0, 1.9, -1.2) * CFrame.Angles(math.rad(30), 0, 0),
        Color3.fromRGB(170, 220, 255), Enum.Material.Glass, { Transparency = 0.4, CanCollide = false })
    bp("Part", "ShieldFrame", Vector3.new(4.3, 0.12, 0.2),
        CFrame.new(0, 1.9 + 0.65 * math.cos(math.rad(30)), -1.2 + 0.65 * math.sin(math.rad(30)))
            * CFrame.Angles(math.rad(30), 0, 0), CHROME, Enum.Material.Metal, DECO)
    -- seats
    for _, sx in ipairs({ -1, 1 }) do
        bp("Part", "Seat", Vector3.new(1.5, 0.8, 1.4), CFrame.new(sx * 1.1, 1.65, 1.5), STUCCO, Enum.Material.Fabric, DECO)
        bp("Part", "SeatBack", Vector3.new(1.5, 1.1, 0.3), CFrame.new(sx * 1.1, 2.2, 2.3), PINK:Lerp(WHITE, 0.4),
            Enum.Material.Fabric, DECO)
    end
    bp("Part", "RearBench", Vector3.new(4, 0.8, 1.2), CFrame.new(0, 1.6, 6.9), STUCCO, Enum.Material.Fabric, DECO)
    bp("Part", "Outboard", Vector3.new(1.4, 2.6, 1.2), CFrame.new(0, 0.9, 8.6), METAL_DARK, Enum.Material.Metal)
    -- nav lights (port red, starboard green)
    bp("Part", "NavPort", Vector3.new(0.3, 0.3, 0.3), CFrame.new(-2.3, 1.3, -2.6), Color3.fromRGB(255, 40, 60),
        Enum.Material.Neon, GLOW)
    bp("Part", "NavStarboard", Vector3.new(0.3, 0.3, 0.3), CFrame.new(2.3, 1.3, -2.6), Color3.fromRGB(40, 255, 120),
        Enum.Material.Neon, GLOW)
    m.Parent = parent
    return m
end

function MiamiBuilder:_marina(f)
    local wood = Color3.fromRGB(150, 112, 78)
    local woodDark = Color3.fromRGB(96, 70, 50)
    local pier = folder(f, "Pier")
    -- v2: deck x 100..106, z -114 .. -150 (starts at the north edge of the
    -- drop-off sand, runs out over the water)
    local Z0, Z1 = -114, -150
    box("PierDeck", 100, 0.6, Z1, 106, 1.0, Z0, wood, Enum.Material.WoodPlanks, pier)
    box("PierBeam", 100, 0.2, Z1, 100.4, 0.6, Z0, woodDark, Enum.Material.Wood, pier)
    box("PierBeam", 105.6, 0.2, Z1, 106, 0.6, Z0, woodDark, Enum.Material.Wood, pier)
    -- step up from the sand
    inst("WedgePart", {
        Name = "PierRamp", Size = Vector3.new(6, 1.0, 2.5),
        CFrame = CFrame.new(103, 0.5, Z0 + 1.25) * CFrame.Angles(0, math.pi, 0),
        Color = wood, Material = Enum.Material.WoodPlanks,
    }, pier)
    for _, z in ipairs({ -114.5, -120, -126, -132, -138, -144, -149.5 }) do
        for _, x in ipairs({ 100.3, 105.7 }) do
            cyl("PierPost", Vector3.new(x, -10, z), Vector3.new(x, 1.4, z), 0.7, woodDark, Enum.Material.Wood, pier)
        end
    end
    -- two lamps: warm pools on the boards and a reflection on the water
    for _, z in ipairs({ -126, -147 }) do
        cyl("PierLampPole", Vector3.new(100.6, 1, z), Vector3.new(100.6, 7, z), 0.25, METAL_DARK, Enum.Material.Metal, pier)
        local lantern = box("PierLantern", 100.2, 7, z - 0.4, 101.0, 7.9, z + 0.4, METAL_DARK, Enum.Material.Metal, pier, DECO)
        box("PierLanternGlow", 100.3, 6.8, z - 0.3, 100.9, 7.0, z + 0.3, WARM_LIGHT, Enum.Material.Neon, pier, GLOW)
        pointLight(lantern, WARM_LIGHT, 1.3, 16, true)
    end
    -- cleats + mooring lines to the boat
    local boatCF = CFrame.new(109, -0.3, -141)
    for _, z in ipairs({ -134, -145 }) do
        box("Cleat", 105.3, 1.0, z - 0.4, 105.8, 1.25, z + 0.4, CHROME, Enum.Material.Metal, pier, DECO)
    end
    cyl("MooringLine", Vector3.new(105.6, 1.2, -134), (boatCF * CFrame.new(-2.3, 1.1, 5)).Position, 0.1,
        Color3.fromRGB(220, 210, 180), Enum.Material.Fabric, pier, DECO)
    cyl("MooringLine", Vector3.new(105.6, 1.2, -145), (boatCF * CFrame.new(-2.2, 1.1, -3.5)).Position, 0.1,
        Color3.fromRGB(220, 210, 180), Enum.Material.Fabric, pier, DECO)
    self:_speedboat(pier, boatCF)

    -- ── DROP-OFF ring: dashed neon outline on the sand (not a disc) ──
    local ring = folder(f, "DropoffRing")
    local c = Vector3.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z)
    local R = W.DROPOFF_RADIUS
    local N = 40
    for i = 0, N - 1 do
        local a = i * (math.pi * 2 / N)
        local pos = c + Vector3.new(math.cos(a) * R, 0.06, math.sin(a) * R)
        local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
        local seg = part({
            Name = "RingSegment", Size = Vector3.new(0.35, 0.12, 1.5),
            CFrame = CFrame.lookAt(pos, pos + tangent),
            Color = CYAN, Material = Enum.Material.Neon,
            CanCollide = false, CastShadow = false, CanTouch = false, CanQuery = false,
        }, ring)
        if i % 10 == 0 then pointLight(seg, CYAN, 0.9, 10) end
    end
    -- soft cyan pool inside the ring from an invisible panel overhead
    local glow = box("DropoffGlow", c.X - 12, 9, c.Z - 12, c.X + 12, 9.2, c.Z + 12, CYAN, Enum.Material.SmoothPlastic, ring,
        { Transparency = 1, CanCollide = false, CastShadow = false, CanTouch = false, CanQuery = false })
    local sl = Instance.new("SurfaceLight")
    sl.Face = Enum.NormalId.Bottom
    sl.Color = CYAN
    sl.Brightness = 0.6
    sl.Range = 12
    sl.Angle = 70
    sl.Parent = glow

    -- ── DROP-OFF sign, post-mounted, facing south toward the street.
    --    Sits just east of the marina route (x 94..122 stays clear). ──
    local signF = folder(f, "DropoffSign")
    local sz = -94
    for _, x in ipairs({ 124.6, 129.4 }) do
        box("SignPost", x - 0.15, 0, sz - 0.15, x + 0.15, 4.6, sz + 0.15, METAL_DARK, Enum.Material.Metal, signF)
    end
    local board = box("SignBoard", 124, 4.4, sz - 0.3, 130, 7.3, sz + 0.15, SIGN_DARK, Enum.Material.Metal, signF)
    local g = gui(board, Enum.NormalId.Back, 40, 2.5, 0)
    neonLabel(g, "DROP-OFF", CYAN, { Size = UDim2.fromScale(0.9, 0.55), Position = UDim2.fromScale(0.05, 0.08) }, 4)
    neonLabel(g, "DRIVE IN  ·  CASH OUT", PINK, { Size = UDim2.fromScale(0.8, 0.22), Position = UDim2.fromScale(0.1, 0.68),
        FontFace = UITheme.F.bold }, 2)
    box("SignTube", 124.2, 4.15, sz + 0.15, 129.8, 4.3, sz + 0.3, CYAN, Enum.Material.Neon, signF, GLOW)
    pointLight(board, CYAN, 1.2, 12)
end

-- ──────────────────────────────────────────────
-- 🚗 80s CARS — parked decoration + the AmbientService traffic
-- ──────────────────────────────────────────────
local CAR_GLASS = Color3.fromRGB(26, 34, 52)
local TIRE = Color3.fromRGB(24, 24, 26)
local COP_BLACK = Color3.fromRGB(22, 24, 30)
local COP_RED = Color3.fromRGB(255, 40, 50)
local COP_BLUE = Color3.fromRGB(40, 90, 255)

function MiamiBuilder.buildCar(parent, cf, opts)
    opts = opts or {}
    local police = opts.police == true
    local paint = police and COP_BLACK or (opts.paint or PASTEL[1])
    local stripe = opts.stripe or WHITE
    local m = Instance.new("Model")
    m.Name = opts.name or (police and "ParkedCruiser" or "Car")

    local root = nil
    if opts.weld then
        root = part({
            -- sits exactly on the ground-contact CFrame, so movers just set Root.CFrame = cf
            Name = "Root", Size = Vector3.new(4.6, 1, 10), CFrame = cf,
            Color = paint, Material = Enum.Material.Metal, Transparency = 1,
            CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
        }, m)
        m.PrimaryPart = root
    end

    local function cp(class, name, size, offset, color, mat, extra)
        local props = { Name = name, Size = size, CFrame = cf * offset, Color = color, Material = mat }
        for k, v in pairs(extra or {}) do props[k] = v end
        if opts.noQuery then
            props.CanQuery = false
            props.CanTouch = false
        end
        local p = inst(class, props, m)
        if root then
            p.Anchored = false
            p.Massless = true
            local w = Instance.new("WeldConstraint")
            w.Part0 = root
            w.Part1 = p
            w.Parent = p
        end
        return p
    end

    local body = cp("Part", "Body", Vector3.new(4.6, 1.4, 10), CFrame.new(0, 1.5, 0), paint, Enum.Material.Metal,
        { Reflectance = 0.08 })
    cp("Part", "Cabin", Vector3.new(4.0, 1.4, 4.6), CFrame.new(0, 2.9, 0.6), CAR_GLASS, Enum.Material.Glass,
        { Reflectance = 0.25, Transparency = 0.1 })
    cp("WedgePart", "Windshield", Vector3.new(4.0, 1.4, 1.2), CFrame.new(0, 2.9, -2.3), CAR_GLASS, Enum.Material.Glass,
        { Reflectance = 0.25, Transparency = 0.1 })
    cp("WedgePart", "RearWindow", Vector3.new(4.0, 1.4, 1.0), CFrame.new(0, 2.9, 3.4) * CFrame.Angles(0, math.pi, 0),
        CAR_GLASS, Enum.Material.Glass, { Reflectance = 0.25, Transparency = 0.1 })
    cp("Part", "Roof", Vector3.new(4.1, 0.25, 4.0), CFrame.new(0, 3.72, 0.7), police and WHITE or paint, Enum.Material.Metal)
    for _, sx in ipairs({ -1, 1 }) do
        for _, sz in ipairs({ -3.3, 3.3 }) do
            cp("Part", "Wheel", Vector3.new(0.9, 2, 2), CFrame.new(sx * 2.05, 1.0, sz), TIRE,
                Enum.Material.Rubber, { Shape = Enum.PartType.Cylinder })
            cp("Part", "Hubcap", Vector3.new(0.12, 1.1, 1.1), CFrame.new(sx * 2.52, 1.0, sz), CHROME, Enum.Material.Metal,
                { Shape = Enum.PartType.Cylinder, CanCollide = false })
        end
        if police then
            -- classic black-and-white: white doors with POLICE on them
            local door = cp("Part", "DoorPanel", Vector3.new(0.06, 1.15, 4.6), CFrame.new(sx * 2.33, 1.55, 0.3), WHITE,
                Enum.Material.Metal, DECO)
            local g = gui(door, (sx > 0) and Enum.NormalId.Right or Enum.NormalId.Left, 40, 1, 1)
            UITheme.label({
                Text = "POLICE", TextColor3 = Color3.fromRGB(18, 36, 90), FontFace = UITheme.F.display, TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.86, 0.7),
                Position = UDim2.fromScale(0.07, 0.15),
            }).Parent = g
        else
            cp("Part", "SideStripe", Vector3.new(0.08, 0.25, 9), CFrame.new(sx * 2.32, 1.85, 0), stripe, Enum.Material.Metal, DECO)
        end
        cp("Part", "Headlight", Vector3.new(0.9, 0.35, 0.1), CFrame.new(sx * 1.5, 1.8, -5.02),
            Color3.fromRGB(235, 232, 210), opts.lights and Enum.Material.Neon or Enum.Material.Glass, GLOW)
        cp("Part", "Taillight", Vector3.new(0.9, 0.3, 0.1), CFrame.new(sx * 1.5, 1.8, 5.02), Color3.fromRGB(200, 30, 50),
            Enum.Material.Neon, GLOW)
    end
    for _, sz in ipairs({ -5.1, 5.1 }) do
        cp("Part", "Bumper", Vector3.new(4.7, 0.5, 0.35), CFrame.new(0, 1.1, sz), CHROME, Enum.Material.Metal)
    end
    if opts.lights then
        spotLight(body, Enum.NormalId.Front, WARM_LIGHT, 1.4, 22, 50)
    end
    if police then
        cp("Part", "PushBar", Vector3.new(3.4, 1.0, 0.3), CFrame.new(0, 1.3, -5.4), METAL_DARK, Enum.Material.Metal)
        cp("Part", "LightBar", Vector3.new(3.2, 0.3, 0.8), CFrame.new(0, 3.99, 0.7), METAL_DARK, Enum.Material.Metal, DECO)
        local red = cp("Part", "LightRed", Vector3.new(1.4, 0.3, 0.6), CFrame.new(-0.8, 4.29, 0.7), COP_RED,
            Enum.Material.Neon, GLOW)
        local blue = cp("Part", "LightBlue", Vector3.new(1.4, 0.3, 0.6), CFrame.new(0.8, 4.29, 0.7), COP_BLUE,
            Enum.Material.Neon, GLOW)
        pointLight(red, COP_RED, 0.8, 9)
        pointLight(blue, COP_BLUE, 0.8, 9)
    end
    if opts.taxi then
        local sign = cp("Part", "TaxiSign", Vector3.new(1.8, 0.6, 0.7), CFrame.new(0, 4.15, 0.7),
            Color3.fromRGB(250, 220, 90), Enum.Material.Metal, DECO)
        for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
            local g = gui(sign, face, 40, 1.4, 0)
            UITheme.label({
                Text = "TAXI", TextColor3 = Color3.fromRGB(30, 26, 20), FontFace = UITheme.F.display, TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.9, 0.8),
                Position = UDim2.fromScale(0.05, 0.1),
            }).Parent = g
        end
    end
    m.Parent = parent
    return m, root
end

-- Parked cars live OFF the street now (v2): the lanes belong to traffic and
-- the getaway spots. Two small lots + the police cruiser pads.
function MiamiBuilder:_cars(f)
    local P = PASTEL
    local lotColor = Color3.fromRGB(52, 54, 58)
    local lineColor = Color3.fromRGB(226, 224, 214)
    local function carAt(x, y, z, facing, opts)
        local pos = Vector3.new(x, y, z)
        return MiamiBuilder.buildCar(f, CFrame.lookAt(pos, pos + facing), opts)
    end
    local function bayLine(x, z0, z1)
        box("BayLine", x - 0.12, 0.5, z0, x + 0.12, 0.52, z1, lineColor, Enum.Material.SmoothPlastic, f, GLOW)
    end

    -- South lot (between LUNA and Diamond Dolls): x -104..-86, z -1.4..22.
    -- Keeps 4 studs off the jewelry store's west wall (x -82).
    box("LotSouth", -104, 0, -1.4, -86, 0.5, 22, lotColor, Enum.Material.Asphalt, f)
    for _, x in ipairs({ -98, -92 }) do bayLine(x, 6, 17) end
    carAt(-101, 0.5, 11.5, Vector3.new(0, 0, 1), { paint = P[3], stripe = WHITE, name = "ParkedCar" })
    carAt(-95, 0.5, 11.5, Vector3.new(0, 0, 1), { paint = Color3.fromRGB(245, 225, 140), stripe = CYAN, name = "ParkedCar" })

    -- North lot (east of CORAL, west of the marina route): x 74..92, z -46..-26.6
    box("LotNorth", 74, 0, -46, 92, 0.5, -26.6, lotColor, Enum.Material.Asphalt, f)
    for _, x in ipairs({ 75, 81, 87 }) do bayLine(x, -43, -32) end
    carAt(78, 0.5, -37.5, Vector3.new(0, 0, -1), { paint = Color3.fromRGB(240, 150, 185), stripe = WHITE, name = "ParkedCar" })
    carAt(84, 0.5, -37.5, Vector3.new(0, 0, -1), { paint = WHITE, stripe = PINK, name = "ParkedCar" })
end

-- ──────────────────────────────────────────────
-- 🚓 MIAMI POLICE — station + holding cells
--    x -104..-80, z -52..-28 (WORLD.POLICE_STATION_*), front faces SOUTH
-- ──────────────────────────────────────────────
local POLICE_BLUE = Color3.fromRGB(24, 58, 150)
local STATION_WHITE = Color3.fromRGB(232, 232, 226)
local BAR_METAL = Color3.fromRGB(92, 96, 108)
local CELL_SLIDE = 3.3          -- how far a bar door slides east to open

local closedCF = setmetatable({}, { __mode = "k" })   -- part -> CFrame when the door is shut

function MiamiBuilder.setCellOpen(door, open, instant)
    if typeof(door) ~= "Instance" or not door:IsA("BasePart") then return end
    open = (open == true)
    if (door:GetAttribute("Open") == true) == open then return end
    local parts = { door }
    for _, d in ipairs(door:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end
    for _, p in ipairs(parts) do
        if not closedCF[p] then closedCF[p] = p.CFrame end   -- first call happens while shut
    end
    door:SetAttribute("Open", open)
    local offset = Vector3.new(open and (door:GetAttribute("SlideX") or CELL_SLIDE) or 0, 0, 0)
    local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, p in ipairs(parts) do
        local goal = closedCF[p] + offset
        if instant then
            p.CFrame = goal
        else
            TweenService:Create(p, info, { CFrame = goal }):Play()
        end
    end
end

-- A dark SurfaceGui text panel (words on a surface, never floating)
local function plate(p, face, text, color, pps, props)
    local g = gui(p, face, pps or 40, 1.3, 0)
    local l = UITheme.label({
        Text = text, TextColor3 = color or WHITE, FontFace = UITheme.F.display, TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.9, 0.76),
        Position = UDim2.fromScale(0.05, 0.12),
    })
    for k, v in pairs(props or {}) do l[k] = v end
    l.Parent = g
    return g, l
end

-- Vertical bars between x0..x1 at plane z (y from yb to yt), into `parent`
local function barRow(parent, x0, x1, z, yb, yt, extra)
    local n = math.max(1, math.floor((x1 - x0) / 0.55))
    local step = (x1 - x0) / n
    for i = 0, n - 1 do
        local x = x0 + step * (i + 0.5)
        cyl("Bar", Vector3.new(x, yb, z), Vector3.new(x, yt, z), 0.22, BAR_METAL, Enum.Material.Metal, parent, extra)
    end
    for _, y in ipairs({ yb, (yb + yt) / 2 - 0.12, yt - 0.3 }) do
        box("BarRail", x0, y, z - 0.15, x1, y + 0.3, z + 0.15, BAR_METAL, Enum.Material.Metal, parent, extra)
    end
end

function MiamiBuilder:_policeStation(st)
    local S = W.POLICE_STATION_CENTER
    local hw, hd = W.POLICE_STATION_HALF_WIDTH, W.POLICE_STATION_HALF_DEPTH
    local cx = S.x
    local x0, x1 = cx - hw, cx + hw            -- -104, -80
    local zB, zF = S.z - hd, S.z + hd          -- -52 (back), -28 (front, facing the street)
    local FY = W.FLOOR                         -- 0.5
    local TOP = 15                             -- wall top / ceiling
    local WALL = STATION_WHITE
    local CONC = Enum.Material.Concrete
    local glass = Color3.fromRGB(40, 60, 80)
    local black = Color3.new(0, 0, 0)

    -- zones (front → back): lobby | divider | corridor | bars | cells
    local lobbyBack = zF - 9                   -- -37 (divider front face)
    local divZ0, divZ1 = zF - 10, zF - 9       -- -38..-37
    local cellFront = zF - 16                  -- -44 (bar line)
    local cellBack = zB + 1                    -- -51 (inner face of the back wall)

    -- ── shell ──
    box("StationFloor", x0, 0, zB, x1, FY, zF, Color3.fromRGB(196, 198, 202), Enum.Material.Marble, st)
    box("CellBlockFloor", x0 + 1, FY, zB + 1, x1 - 1, FY + 0.02, divZ0, Color3.fromRGB(120, 122, 126), CONC, st, GLOW)
    box("Forecourt", x0, 0, zF, x1, FY, -26.6, PAVING, CONC, st)
    box("WallBack", x0, FY, zB, x1, TOP, zB + 1, WALL, CONC, st)
    local wallW = box("WallWest", x0, FY, zB + 1, x0 + 1, TOP, zF - 1, WALL, CONC, st)
    local wallE = box("WallEast", x1 - 1, FY, zB + 1, x1, TOP, zF - 1, WALL, CONC, st)

    -- front wall (z zF-1..zF): windows either side of an 8-wide glass door
    local fz0, fz1 = zF - 1, zF
    local dx0, dx1 = cx - 4, cx + 4            -- door opening -96..-88
    local winL = { x0 + 2, cx - 5 }            -- -102..-97
    local winR = { cx + 5, x1 - 2 }            -- -87..-82
    box("FrontWall", x0, FY, fz0, winL[1], TOP, fz1, WALL, CONC, st)
    box("FrontWall", winL[2], FY, fz0, dx0, TOP, fz1, WALL, CONC, st)
    box("FrontWall", dx1, FY, fz0, winR[1], TOP, fz1, WALL, CONC, st)
    box("FrontWall", winR[2], FY, fz0, x1, TOP, fz1, WALL, CONC, st)
    box("DoorHeader", dx0, 10.5, fz0, dx1, TOP, fz1, WALL, CONC, st)
    for _, w in ipairs({ winL, winR }) do
        box("Sill", w[1], FY, fz0, w[2], 3, fz1, WALL, CONC, st)
        box("WinHead", w[1], 8, fz0, w[2], TOP, fz1, WALL, CONC, st)
        box("Window", w[1], 3, zF - 0.65, w[2], 8, zF - 0.35, glass, Enum.Material.Glass, st,
            { Transparency = 0.35, Reflectance = 0.15 })
        local mid = (w[1] + w[2]) / 2
        box("Mullion", mid - 0.1, 3, zF - 0.7, mid + 0.1, 8, zF - 0.3, METAL_DARK, Enum.Material.Metal, st, DECO)
        box("SillCap", w[1] - 0.2, 2.8, zF - 0.2, w[2] + 0.2, 3.05, zF + 0.3, POLICE_BLUE, CONC, st)
    end

    -- plinth + the blue/white stripes wrapping the building
    local function wrap(name, y0, y1, color, mat, t)
        t = t or 0.12
        box(name, x0 - t, y0, zF, x1 + t, y1, zF + t, color, mat, st)             -- front
        box(name, x0 - t, y0, zB - t, x1 + t, y1, zB, color, mat, st)             -- back
        box(name, x0 - t, y0, zB, x0, y1, zF, color, mat, st)                     -- west
        box(name, x1, y0, zB, x1 + t, y1, zF, color, mat, st)                     -- east
    end
    wrap("Plinth", 0, 1.2, Color3.fromRGB(70, 74, 84), CONC, 0.15)
    wrap("BlueStripe", 11.6, 12.6, POLICE_BLUE, Enum.Material.Plaster)
    wrap("BlueStripeThin", 13.1, 13.4, POLICE_BLUE, Enum.Material.Plaster)

    -- roof, parapet, blue coping, antenna, AC
    box("Roof", x0 - 0.4, TOP, zB - 0.4, x1 + 0.4, TOP + 1, zF + 0.4, Color3.fromRGB(180, 180, 176), CONC, st)
    local pt = 0.6
    box("Parapet", x0 - 0.4, TOP + 1, zF + 0.4 - pt, x1 + 0.4, TOP + 2.2, zF + 0.4, WALL, CONC, st)
    box("Parapet", x0 - 0.4, TOP + 1, zB - 0.4, x1 + 0.4, TOP + 2.2, zB - 0.4 + pt, WALL, CONC, st)
    box("Parapet", x0 - 0.4, TOP + 1, zB - 0.4, x0 - 0.4 + pt, TOP + 2.2, zF + 0.4, WALL, CONC, st)
    box("Parapet", x1 + 0.4 - pt, TOP + 1, zB - 0.4, x1 + 0.4, TOP + 2.2, zF + 0.4, WALL, CONC, st)
    box("Coping", x0 - 0.5, TOP + 2.2, zF + 0.5 - pt - 0.2, x1 + 0.5, TOP + 2.45, zF + 0.5, POLICE_BLUE, CONC, st)
    cyl("Antenna", Vector3.new(x0 + 3, TOP + 1, zB + 3), Vector3.new(x0 + 3, TOP + 10, zB + 3), 0.25, CHROME,
        Enum.Material.Metal, st)
    local beacon = ball("AntennaBeacon", Vector3.new(x0 + 3, TOP + 10.2, zB + 3), 0.45, COP_RED, Enum.Material.Neon, st, GLOW)
    pointLight(beacon, COP_RED, 0.8, 8)
    box("RoofAC", x1 - 8, TOP + 1, zB + 3, x1 - 4, TOP + 2.8, zB + 6.5, CHROME, Enum.Material.Metal, st)

    -- ── the MIAMI POLICE sign (SurfaceGui, lit) ──
    local sign = box("PoliceSign", cx - 5.5, 10.9, zF, cx + 5.5, 14.1, zF + 0.35, POLICE_BLUE, Enum.Material.Metal, st)
    do
        local g = gui(sign, Enum.NormalId.Back, 40, 1.4, 0)
        gframe(g, 0.015, 0.03, 0.97, 0.94, POLICE_BLUE, 1)
        local border = Instance.new("UIStroke")
        border.Color = WHITE
        border.Thickness = 4
        border.Parent = g:FindFirstChildOfClass("Frame")
        UITheme.label({
            Text = "MIAMI POLICE", TextColor3 = WHITE, FontFace = UITheme.F.display, TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.9, 0.56),
            Position = UDim2.fromScale(0.05, 0.08),
        }).Parent = g
        UITheme.label({
            Text = "DEPARTMENT  ·  DISTRICT 1", TextColor3 = Color3.fromRGB(190, 210, 255), FontFace = UITheme.F.bold,
            TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.7, 0.22),
            Position = UDim2.fromScale(0.15, 0.68),
        }).Parent = g
    end
    local signLamp = box("SignLamp", cx - 0.5, 14.3, zF + 0.4, cx + 0.5, 14.6, zF + 1.1, METAL_DARK, Enum.Material.Metal, st, DECO)
    spotLight(signLamp, Enum.NormalId.Bottom, WHITE, 1.2, 8, 100)

    -- door canopy with a blue fascia + downlight
    local canopy = box("DoorCanopy", cx - 6, 10.2, zF, cx + 6, 10.6, zF + 1.2, WALL, CONC, st)
    box("CanopyFascia", cx - 6, 10.1, zF + 1.2, cx + 6, 10.7, zF + 1.35, POLICE_BLUE, Enum.Material.Plaster, st)
    spotLight(canopy, Enum.NormalId.Bottom, Color3.fromRGB(235, 240, 255), 1.4, 14, 110)

    -- the classic blue lanterns either side of the door
    for _, sx in ipairs({ -1, 1 }) do
        local lx = cx + sx * 4.5
        box("LanternBracket", lx - 0.1, 8.6, zF, lx + 0.1, 8.8, zF + 0.6, METAL_DARK, Enum.Material.Metal, st, DECO)
        local lan = box("Lantern", lx - 0.35, 7.4, zF + 0.3, lx + 0.35, 8.6, zF + 1.0, METAL_DARK, Enum.Material.Metal, st, DECO)
        box("LanternGlass", lx - 0.28, 7.55, zF + 0.37, lx + 0.28, 8.45, zF + 0.93, Color3.fromRGB(60, 120, 255),
            Enum.Material.Neon, st, GLOW)
        pointLight(lan, Color3.fromRGB(70, 120, 255), 1.1, 11)
    end

    -- glass doors, swung open into the lobby (the doorway stays clear)
    for _, sx in ipairs({ -1, 1 }) do
        local hx = cx + sx * 3.85
        box("DoorLeaf", hx - 0.1, FY + 0.1, zF - 5, hx + 0.1, 10.2, zF - 1, Color3.fromRGB(150, 200, 230),
            Enum.Material.Glass, st, { Transparency = 0.5, Reflectance = 0.2 })
        box("DoorLeafRail", hx - 0.14, FY + 0.1, zF - 5, hx + 0.14, FY + 0.6, zF - 1, CHROME, Enum.Material.Metal, st)
        box("DoorLeafRail", hx - 0.14, 9.7, zF - 5, hx + 0.14, 10.2, zF - 1, CHROME, Enum.Material.Metal, st)
        box("DoorLeafRail", hx - 0.14, FY + 0.1, zF - 5.2, hx + 0.14, 10.2, zF - 4.8, CHROME, Enum.Material.Metal, st)
    end
    box("DoorMat", cx - 3, FY, zF - 3, cx + 3, FY + 0.03, zF - 1, Color3.fromRGB(34, 36, 44), Enum.Material.Fabric, st, DECO)
    box("LobbyRug", cx - 3.5, FY, lobbyBack + 1.5, cx + 3.5, FY + 0.03, zF - 3, POLICE_BLUE:Lerp(black, 0.35),
        Enum.Material.Fabric, st, DECO)

    -- ── LOBBY ──
    -- front desk along the west half, public side facing the door
    local dz0, dz1 = zF - 6, zF - 5            -- -34..-33
    box("DeskCounter", x0 + 3, FY, dz0, cx - 4.5, 3.8, dz1, WALL, Enum.Material.Plaster, st)
    box("DeskTop", x0 + 2.9, 3.8, dz0 - 0.2, cx - 4.4, 4.1, dz1 + 0.15, Color3.fromRGB(60, 62, 70), Enum.Material.Marble, st)
    local deskFront = box("DeskFront", x0 + 3, 0.9, dz1, cx - 4.5, 3.4, dz1 + 0.1, POLICE_BLUE, Enum.Material.Metal, st)
    plate(deskFront, Enum.NormalId.Back, "FRONT DESK", WHITE, 40, { Size = UDim2.fromScale(0.6, 0.56),
        Position = UDim2.fromScale(0.2, 0.22) })
    local deskLamp = box("DeskLamp", cx - 6.2, 4.1, dz0 + 0.1, cx - 5.6, 4.9, dz0 + 0.7, METAL_DARK, Enum.Material.Metal, st, DECO)
    pointLight(deskLamp, WARM_LIGHT, 0.9, 10)
    -- filing cabinets against the divider, behind the desk
    for i = 0, 0 do
        local fx = x0 + 1.2 + i * 2.2
        local cab = box("FileCabinet", fx, FY, lobbyBack, fx + 2, 5.2, lobbyBack + 1.4, Color3.fromRGB(130, 136, 146),
            Enum.Material.Metal, st)
        local g = gui(cab, Enum.NormalId.Back, 20, 1, 1)
        for k = 0, 3 do
            local drawer = gframe(g, 0.06, 0.04 + k * 0.24, 0.88, 0.2, Color3.fromRGB(150, 156, 166))
            gframe(drawer, 0.4, 0.4, 0.2, 0.14, Color3.fromRGB(60, 62, 70))
        end
    end
    -- WANTED board on the divider, above the cabinets
    local board = box("WantedBoard", x0 + 1.5, 6, lobbyBack, x0 + 8, 10, lobbyBack + 0.15, Color3.fromRGB(150, 110, 70),
        Enum.Material.Fabric, st)
    do
        local g = gui(board, Enum.NormalId.Back, 30, 1, 1)
        for k = 0, 2 do
            local poster = gframe(g, 0.05 + k * 0.32, 0.1, 0.26, 0.8, Color3.fromRGB(236, 228, 206))
            UITheme.label({ Text = "WANTED", TextColor3 = Color3.fromRGB(170, 30, 30), FontFace = UITheme.F.display,
                TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.9, 0.2),
                Position = UDim2.fromScale(0.05, 0.04) }).Parent = poster
            local mug = gframe(poster, 0.2, 0.28, 0.6, 0.46, Color3.fromRGB(40, 40, 46))
            gframe(mug, 0.3, 0.12, 0.4, 0.4, Color3.fromRGB(90, 90, 96))       -- head silhouette
            gframe(mug, 0.15, 0.6, 0.7, 0.4, Color3.fromRGB(90, 90, 96))       -- shoulders
            UITheme.label({ Text = "$" .. tostring(5 + k * 5) .. ",000", TextColor3 = Color3.fromRGB(40, 40, 46),
                FontFace = UITheme.F.bold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.1, 0.8) }).Parent = poster
        end
    end
    -- waiting bench under the east window
    local bx0, bx1 = winR[1] + 0.2, winR[2] - 0.2
    box("WaitBenchSeat", bx0, 1.8, zF - 2.6, bx1, 2.2, zF - 1.2, Color3.fromRGB(150, 112, 78), Enum.Material.WoodPlanks, st)
    box("WaitBenchBack", bx0, 2.2, zF - 1.35, bx1, 4.0, zF - 1.15, Color3.fromRGB(150, 112, 78), Enum.Material.WoodPlanks, st)
    for _, lx in ipairs({ bx0 + 0.4, bx1 - 0.6 }) do
        box("WaitBenchLeg", lx, FY, zF - 2.5, lx + 0.2, 1.8, zF - 1.3, METAL_DARK, Enum.Material.Metal, st)
    end
    -- lobby ceiling panels
    for _, sx in ipairs({ -1, 1 }) do
        local lx = cx + sx * 6
        local fixture = box("CeilingPanel", lx - 1.6, TOP - 0.35, zF - 6, lx + 1.6, TOP, zF - 3.5, Color3.fromRGB(210, 212, 216),
            Enum.Material.Metal, st, DECO)
        box("CeilingPanelGlow", lx - 1.4, TOP - 0.4, zF - 5.8, lx + 1.4, TOP - 0.35, zF - 3.7, Color3.fromRGB(230, 240, 255),
            Enum.Material.Neon, st, GLOW)
        pointLight(fixture, Color3.fromRGB(225, 235, 255), 1.3, 20)
    end

    -- ── divider wall with a 7-wide doorway (x -89..-82) into the cell block ──
    local ddx0, ddx1 = cx + 3, x1 - 2
    box("Divider", x0 + 1, FY, divZ0, ddx0, TOP, divZ1, WALL, CONC, st)
    box("Divider", ddx1, FY, divZ0, x1 - 1, TOP, divZ1, WALL, CONC, st)
    box("DividerHeader", ddx0, 10.5, divZ0, ddx1, TOP, divZ1, WALL, CONC, st)
    local cellsSign = box("CellsSign", ddx0 + 0.5, 11, divZ1, ddx1 - 0.5, 12.6, divZ1 + 0.12, SIGN_DARK, Enum.Material.Metal, st)
    plate(cellsSign, Enum.NormalId.Back, "HOLDING CELLS", Color3.fromRGB(255, 210, 90))
    box("DoorwayTrimL", ddx0 - 0.25, FY, divZ1, ddx0, 10.5, divZ1 + 0.2, POLICE_BLUE, Enum.Material.Metal, st)
    box("DoorwayTrimR", ddx1, FY, divZ1, ddx1 + 0.25, 10.5, divZ1 + 0.2, POLICE_BLUE, Enum.Material.Metal, st)

    -- ── corridor: yellow line, two caged lamps ──
    box("StayBackLine", x0 + 1, FY + 0.02, cellFront + 0.9, x1 - 1, FY + 0.05, cellFront + 1.2,
        Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, st, GLOW)
    for _, sx in ipairs({ -1, 1 }) do
        local lx = cx + sx * 6
        local lamp = box("CorridorLamp", lx - 0.6, TOP - 0.6, cellFront + 2.4, lx + 0.6, TOP, cellFront + 3.6, METAL_DARK,
            Enum.Material.Metal, st, DECO)
        box("CorridorLampGlow", lx - 0.4, TOP - 0.7, cellFront + 2.6, lx + 0.4, TOP - 0.6, cellFront + 3.4,
            Color3.fromRGB(220, 235, 255), Enum.Material.Neon, st, GLOW)
        pointLight(lamp, Color3.fromRGB(200, 220, 255), 1.1, 16)
    end

    -- ── the cells ──
    local inX0, inX1 = x0 + 1, x1 - 1          -- -103..-81 (22 wide)
    local divT = 0.6
    local cw = ((inX1 - inX0) - 2 * divT) / 3  -- ≈ 6.93 each
    local DW = 3.4                             -- bar door width
    local barTop = 10.5
    box("CellHeader", inX0, barTop, cellFront - 0.3, inX1, TOP, cellFront + 0.3, WALL, CONC, st)
    box("DoorTrack", inX0, 10.2, cellFront + 0.3, inX1, barTop, cellFront + 0.65, METAL_DARK, Enum.Material.Metal, st)

    local cells = {}
    local kenney = {}
    for i = 1, 3 do
        local L = inX0 + (i - 1) * (cw + divT)
        local R = L + cw
        local mid = (L + R) / 2
        local cf = folder(st, "Cell" .. i)
        if i < 3 then
            box("CellWall", R, FY, cellBack, R + divT, TOP, cellFront, WALL, CONC, cf)
        end
        -- fixed bars (east part of the front) + an invisible collision slab
        barRow(cf, L + DW + 0.1, R, cellFront, FY, barTop, DECO)
        box("BarsCollision", L + DW + 0.1, FY, cellFront - 0.15, R, barTop, cellFront + 0.15, BAR_METAL,
            Enum.Material.Metal, cf, { Transparency = 1, CanQuery = false })

        -- the DOOR: one invisible BasePart (collision), bars parented under it
        local doorX0, doorX1 = L + 0.1, L + 0.1 + DW
        local dz = cellFront + 0.45
        local door = box("CellDoor" .. i, doorX0, FY, dz - 0.15, doorX1, 10.2, dz + 0.15, BAR_METAL, Enum.Material.Metal, cf,
            { Transparency = 1, CanCollide = true, CanQuery = true, CastShadow = false })
        door:SetAttribute("Cell", i)
        door:SetAttribute("Open", false)
        door:SetAttribute("SlideX", CELL_SLIDE)
        barRow(door, doorX0 + 0.05, doorX1 - 0.05, dz, FY, 10.2, { CanCollide = false, CanQuery = false })
        box("DoorStile", doorX0, FY, dz - 0.16, doorX0 + 0.25, 10.2, dz + 0.16, BAR_METAL, Enum.Material.Metal, door,
            { CanCollide = false, CanQuery = false })
        box("DoorStile", doorX1 - 0.25, FY, dz - 0.16, doorX1, 10.2, dz + 0.16, BAR_METAL, Enum.Material.Metal, door,
            { CanCollide = false, CanQuery = false })
        box("LockBox", doorX0 + 0.1, 4.6, dz + 0.1, doorX0 + 0.8, 5.8, dz + 0.45, Color3.fromRGB(60, 62, 70),
            Enum.Material.DiamondPlate, door, { CanCollide = false, CanQuery = false })

        -- CELL n label on the header, facing the corridor
        local label = box("CellLabel", L + 0.4, 11.2, cellFront + 0.3, L + 3.2, 12.5, cellFront + 0.36, SIGN_DARK,
            Enum.Material.Metal, cf, DECO)
        plate(label, Enum.NormalId.Back, "CELL " .. i, WHITE)

        -- steel bench along the back wall + a high barred window + a dim bulb
        box("CellBench", L + 0.4, 1.8, cellBack, R - 0.4, 2.2, cellBack + 1.6, Color3.fromRGB(150, 154, 162),
            Enum.Material.Metal, cf)
        for _, bx in ipairs({ L + 0.8, R - 1.0 }) do
            box("CellBenchLeg", bx, FY, cellBack + 0.2, bx + 0.2, 1.8, cellBack + 1.4, BAR_METAL, Enum.Material.Metal, cf)
        end
        box("CellWindow", mid - 1.2, 10, cellBack - 0.05, mid + 1.2, 12, cellBack + 0.05, Color3.fromRGB(30, 36, 60),
            Enum.Material.Glass, cf, DECO)
        for k = -1, 1 do
            cyl("WindowBar", Vector3.new(mid + k * 0.6, 10, cellBack + 0.12), Vector3.new(mid + k * 0.6, 12, cellBack + 0.12),
                0.14, BAR_METAL, Enum.Material.Metal, cf, DECO)
        end
        local bulb = box("CellLamp", mid - 0.4, TOP - 0.5, -48, mid + 0.4, TOP, -47.2, METAL_DARK, Enum.Material.Metal, cf, DECO)
        box("CellLampGlow", mid - 0.25, TOP - 0.6, -47.85, mid + 0.25, TOP - 0.5, -47.35, WARM_LIGHT, Enum.Material.Neon, cf, GLOW)
        pointLight(bulb, WARM_LIGHT, 0.7, 10)
        table.insert(kenney, { kit = "furniture", name = "toilet", pos = Vector3.new(R - 1.0, FY, cellFront - 1.4),
            facing = Vector3.new(-1, 0, 0) })

        local inside = Vector3.new(mid, FY + 3, (cellFront + cellBack) / 2 + 0.5)
        table.insert(cells, {
            inside = CFrame.lookAt(inside, inside + Vector3.new(0, 0, 1)),   -- facing the bars
            door = door,
        })
    end

    -- side-wall windows (dark glass, SurfaceGui — symmetric, so face orientation doesn't matter)
    for _, pair in ipairs({ { wallW, Enum.NormalId.Left }, { wallE, Enum.NormalId.Right } }) do
        local g = gui(pair[1], pair[2], 10, 1, 1)
        for k = 0, 3 do
            local fr = gframe(g, 0.08 + k * 0.23, 0.3, 0.12, 0.2, DARK_GLASS)
            local s = Instance.new("UIStroke")
            s.Color = Color3.fromRGB(200, 205, 225)
            s.Transparency = 0.5
            s.Parent = fr
        end
    end

    -- ── cruiser pads + two parked cruisers (decoration, NOT the chasing cops) ──
    local padColor = Color3.fromRGB(56, 58, 62)
    local pads = {
        { x0 = x0 - 6, x1 = x0, cx = x0 - 3 },       -- west: x -110..-104
        { x0 = x1, x1 = x1 + 7, cx = x1 + 3.5 },     -- east: x -80..-73
    }
    for i, pd in ipairs(pads) do
        box("CruiserPad", pd.x0, 0, zF - 16, pd.x1, FY, -26.6, padColor, Enum.Material.Asphalt, st)
        for _, lx in ipairs({ pd.x0 + 0.3, pd.x1 - 0.5 }) do
            box("PadLine", lx, FY, zF - 14, lx + 0.2, FY + 0.02, zF - 1, Color3.fromRGB(240, 200, 40), Enum.Material.SmoothPlastic, st, GLOW)
        end
        local pos = Vector3.new(pd.cx, FY, zF - 7.5)
        MiamiBuilder.buildCar(st, CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)),
            { police = true, name = "ParkedCruiser" .. i })
        -- POLICE PARKING ONLY plate on a short post at the back of the pad
        local px = pd.cx
        box("PadSignPost", px - 0.1, FY, zF - 15.4, px + 0.1, 4.4, zF - 15.2, METAL_DARK, Enum.Material.Metal, st)
        local ps = box("PadSign", px - 1.2, 3.2, zF - 15.2, px + 1.2, 4.6, zF - 15.1, WHITE, Enum.Material.Metal, st, DECO)
        plate(ps, Enum.NormalId.Back, "POLICE ONLY", POLICE_BLUE, 40)
    end

    -- Kenney props (async; a failed load is just skipped)
    table.insert(kenney, { kit = "furniture", name = "chairDesk", pos = Vector3.new(cx - 6.5, FY, dz0 - 1.6), facing = Vector3.new(0, 0, 1) })
    table.insert(kenney, { kit = "furniture", name = "chairDesk", pos = Vector3.new(cx - 4, FY, dz0 - 1.6), facing = Vector3.new(0, 0, 1) })
    table.insert(kenney, { kit = "furniture", name = "computerScreen", pos = Vector3.new(cx - 8, 4.1, dz0 + 0.3), facing = Vector3.new(0, 0, -1) })
    table.insert(kenney, { kit = "furniture", name = "computerScreen", pos = Vector3.new(cx - 11, 4.1, dz0 + 0.3), facing = Vector3.new(0, 0, -1) })
    table.insert(kenney, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(x0 + 2, FY, zF - 2), facing = Vector3.new(0, 0, 1) })
    table.insert(kenney, { kit = "furniture", name = "pottedPlant", pos = Vector3.new(x1 - 2, FY, lobbyBack + 1.2), facing = Vector3.new(0, 0, 1) })
    table.insert(kenney, { kit = "furniture", name = "trashcan", pos = Vector3.new(x0 + 2.2, FY, dz1 + 0.6), facing = Vector3.new(0, 0, 1) })
    if KenneyLoader then KenneyLoader.placeMany(kenney, st) end

    local rel = Vector3.new(cx, FY + 3, -25.2)
    print("[MiamiBuilder] Police station + " .. #cells .. " cells built 🚓")
    return {
        cells = cells,
        release = CFrame.lookAt(rel, rel + Vector3.new(0, 0, 1)),   -- on the sidewalk, facing the street
    }
end

-- ──────────────────────────────────────────────
-- 🏙 CITY LIFE — signs, crosswalks, bus stop, alleys, hydrants…
-- ──────────────────────────────────────────────
local DEST = {
    villa   = { "VILLA ROSA", PINK },
    jewelry = { "DIAMOND DOLLS", CYAN },
    mart    = { "SUNNY'S MART", ORANGE },
    bank    = { "OCEAN BANK", Color3.fromRGB(90, 220, 140) },
    marina  = { "MARINA", Color3.fromRGB(70, 200, 210) },
    police  = { "POLICE", Color3.fromRGB(90, 140, 255) },
}

-- Board whose readable (Front) face points along faceDir. rows = {{dest, arrow}}
local function wayfinder(parent, center, faceDir, w, h, rows)
    local board = part({
        Name = "WaySign", Size = Vector3.new(w, h, 0.3), CFrame = CFrame.lookAt(center, center + faceDir),
        Color = Color3.fromRGB(16, 40, 56), Material = Enum.Material.Metal,
    }, parent)
    local g = gui(board, Enum.NormalId.Front, 40, 1.3, 0)
    local n = #rows
    for i, r in ipairs(rows) do
        local d = DEST[r[1]]
        local arrow = r[2]
        local row = gframe(g, 0.03, (i - 1) / n + 0.06 / n, 0.94, 0.88 / n, Color3.fromRGB(8, 22, 34))
        UITheme.corner(row, 6)
        gframe(row, 0, 0, 0.02, 1, d[2])
        local left = (arrow == "←")
        UITheme.label({
            Text = d[1], TextColor3 = WHITE, FontFace = UITheme.F.display, TextScaled = true,
            TextXAlignment = left and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
            Size = UDim2.fromScale(0.7, 0.72), Position = UDim2.fromScale(left and 0.25 or 0.05, 0.14),
        }).Parent = row
        UITheme.label({
            Text = arrow, TextColor3 = d[2], FontFace = UITheme.F.display, TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(0.18, 0.86), Position = UDim2.fromScale(left and 0.04 or 0.78, 0.07),
        }).Parent = row
    end
    pointLight(board, Color3.fromRGB(200, 230, 255), 0.7, 9)
    return board
end

local function pole(parent, x, z, y1, d, color)
    return cyl("SignPole", Vector3.new(x, 0.5, z), Vector3.new(x, y1, z), d or 0.35, color or METAL_DARK,
        Enum.Material.Metal, parent)
end

-- Green street-name blades crossing at the top of a pole
local function streetName(parent, x, z, alongX, alongZ)
    local green = Color3.fromRGB(26, 104, 66)
    pole(parent, x, z, 11.9, 0.3, green)
    local a = box("StreetBlade", x - 2.6, 10, z - 0.08, x + 2.6, 10.8, z + 0.08, green, Enum.Material.Metal, parent, DECO)
    local b = box("StreetBlade", x - 0.08, 10.95, z - 2.6, x + 0.08, 11.75, z + 2.6, green, Enum.Material.Metal, parent, DECO)
    for _, pair in ipairs({ { a, Enum.NormalId.Front, alongX }, { a, Enum.NormalId.Back, alongX },
        { b, Enum.NormalId.Left, alongZ }, { b, Enum.NormalId.Right, alongZ } }) do
        local g = gui(pair[1], pair[2], 40, 1.1, 0.4)
        UITheme.label({
            Text = pair[3], TextColor3 = WHITE, FontFace = UITheme.F.bold, TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(0.92, 0.72),
            Position = UDim2.fromScale(0.04, 0.14),
        }).Parent = g
        local s = Instance.new("UIStroke")
        s.Color = WHITE
        s.Thickness = 2
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = gframe(g, 0.01, 0.06, 0.98, 0.88, WHITE, 1)
    end
end

local function hydrant(parent, x, z, color)
    local m = Instance.new("Model")
    m.Name = "FireHydrant"
    local y = 0.5
    cyl("Flange", Vector3.new(x, y, z), Vector3.new(x, y + 0.2, z), 1.0, color, Enum.Material.Metal, m)
    cyl("Barrel", Vector3.new(x, y, z), Vector3.new(x, y + 1.8, z), 0.75, color, Enum.Material.Metal, m)
    ball("Cap", Vector3.new(x, y + 1.8, z), 0.8, color, Enum.Material.Metal, m)
    cyl("Nut", Vector3.new(x, y + 2.05, z), Vector3.new(x, y + 2.35, z), 0.25, CHROME, Enum.Material.Metal, m, DECO)
    cyl("Nozzles", Vector3.new(x - 0.6, y + 1.3, z), Vector3.new(x + 0.6, y + 1.3, z), 0.32, CHROME, Enum.Material.Metal, m, DECO)
    cyl("Pumper", Vector3.new(x, y + 1.1, z), Vector3.new(x, y + 1.1, z + 0.55), 0.42, CHROME, Enum.Material.Metal, m, DECO)
    m.Parent = parent
end

local function newsBox(parent, x, z, faceDir)
    local m = Instance.new("Model")
    m.Name = "NewspaperBox"
    local cf = CFrame.lookAt(Vector3.new(x, 0.5, z), Vector3.new(x, 0.5, z) + faceDir)
    local function np(name, size, off, color, mat, extra)
        local props = { Name = name, Size = size, CFrame = cf * off, Color = color, Material = mat }
        for k, v in pairs(extra or {}) do props[k] = v end
        return part(props, m)
    end
    for _, sx in ipairs({ -0.45, 0.45 }) do
        np("Leg", Vector3.new(0.12, 0.8, 0.9), CFrame.new(sx, 0.4, 0), METAL_DARK, Enum.Material.Metal)
    end
    local body = np("Box", Vector3.new(1.3, 2.0, 1.1), CFrame.new(0, 1.8, 0), Color3.fromRGB(40, 90, 180), Enum.Material.Metal)
    np("Lid", Vector3.new(1.4, 0.15, 1.2), CFrame.new(0, 2.87, 0), Color3.fromRGB(30, 70, 150), Enum.Material.Metal)
    local g = gui(body, Enum.NormalId.Front, 60, 1, 1)
    local win = gframe(g, 0.1, 0.08, 0.8, 0.55, Color3.fromRGB(230, 226, 214))
    UITheme.label({ Text = "MIAMI HERALD", TextColor3 = Color3.fromRGB(20, 20, 24), FontFace = UITheme.F.display,
        TextScaled = true, Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center }).Parent = win
    UITheme.label({ Text = "HEIST CREW STRIKES AGAIN?", TextColor3 = Color3.fromRGB(150, 20, 20), FontFace = UITheme.F.bold,
        TextScaled = true, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.36),
        TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true }).Parent = win
    UITheme.label({ Text = "25¢", TextColor3 = WHITE, FontFace = UITheme.F.bold, TextScaled = true,
        Size = UDim2.fromScale(0.4, 0.16), Position = UDim2.fromScale(0.3, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center }).Parent = g
    m.Parent = parent
end

local function litterBin(parent, x, z)
    cyl("LitterBin", Vector3.new(x, 0.5, z), Vector3.new(x, 2.6, z), 1.1, Color3.fromRGB(40, 110, 100), Enum.Material.Metal, parent)
    cyl("LitterBinRim", Vector3.new(x, 2.6, z), Vector3.new(x, 2.8, z), 1.2, CHROME, Enum.Material.Metal, parent, DECO)
end

-- Dumpster, long side along the local X axis; front (lid hinge side) faces `facing`
local function dumpster(parent, x, y, z, facing, color)
    local m = Instance.new("Model")
    m.Name = "Dumpster"
    local cf = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + facing)
    local function dp(name, size, off, col, mat, extra)
        local props = { Name = name, Size = size, CFrame = cf * off, Color = col, Material = mat }
        for k, v in pairs(extra or {}) do props[k] = v end
        return part(props, m)
    end
    dp("Bin", Vector3.new(5, 2.8, 3.2), CFrame.new(0, 1.8, 0), color, Enum.Material.DiamondPlate)
    dp("Rim", Vector3.new(5.2, 0.25, 3.4), CFrame.new(0, 3.25, 0), color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
    -- one lid shut, one propped open
    dp("Lid", Vector3.new(2.5, 0.15, 3.3), CFrame.new(-1.25, 3.42, 0), Color3.fromRGB(30, 32, 36), Enum.Material.Metal, DECO)
    dp("Lid", Vector3.new(2.5, 0.15, 3.3), CFrame.new(1.25, 3.9, 0.9) * CFrame.Angles(math.rad(-35), 0, 0),
        Color3.fromRGB(30, 32, 36), Enum.Material.Metal, DECO)
    for _, sx in ipairs({ -2, 2 }) do
        for _, sz in ipairs({ -1.2, 1.2 }) do
            dp("Caster", Vector3.new(0.4, 0.8, 0.8), CFrame.new(sx, 0.4, sz), TIRE, Enum.Material.Rubber,
                { Shape = Enum.PartType.Cylinder, CanCollide = false })
        end
    end
    local g = gui(m:FindFirstChild("Bin"), Enum.NormalId.Front, 30, 1, 1)
    UITheme.label({ Text = "NO PARKING", TextColor3 = Color3.fromRGB(240, 230, 200), FontFace = UITheme.F.bold,
        TextScaled = true, Size = UDim2.fromScale(0.5, 0.18), Position = UDim2.fromScale(0.25, 0.3),
        TextXAlignment = Enum.TextXAlignment.Center }).Parent = g
    m.Parent = parent
end

local CRATE = Color3.fromRGB(168, 128, 84)
local function crate(parent, x, y, z, s, yaw)
    local cf = CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0)
    local m = Instance.new("Model")
    m.Name = "Crate"
    part({ Name = "Crate", Size = Vector3.new(s, s, s), CFrame = cf, Color = CRATE, Material = Enum.Material.WoodPlanks }, m)
    -- darker edge battens so it reads as a crate, not a box
    local e, h = 0.18, s / 2
    for _, a in ipairs({ -1, 1 }) do
        for _, b in ipairs({ -1, 1 }) do
            part({ Name = "Batten", Size = Vector3.new(e, s + 0.02, e), CFrame = cf * CFrame.new(a * (h - e / 2 + 0.03), 0, b * (h - e / 2 + 0.03)),
                Color = CRATE:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Wood, CanCollide = false }, m)
        end
        part({ Name = "Batten", Size = Vector3.new(s + 0.02, e, e), CFrame = cf * CFrame.new(0, a * (h - e / 2 + 0.03), h - e / 2 + 0.03),
            Color = CRATE:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Wood, CanCollide = false }, m)
        part({ Name = "Batten", Size = Vector3.new(s + 0.02, e, e), CFrame = cf * CFrame.new(0, a * (h - e / 2 + 0.03), -(h - e / 2 + 0.03)),
            Color = CRATE:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Wood, CanCollide = false }, m)
    end
    m.Parent = parent
end

local function trashBags(parent, x, y, z)
    for i, off in ipairs({ { 0, 0 }, { 1.1, 0.4 }, { 0.4, 1.0 } }) do
        ball("TrashBag", Vector3.new(x + off[1], y + 0.6, z + off[2]), 1.3 - i * 0.1, Color3.fromRGB(22, 22, 26),
            Enum.Material.Fabric, parent, DECO)
    end
end

-- Caged wall lamp sticking out from a wall along `out`
local function wallLamp(parent, pos, out)
    local head = box("WallLamp", pos.X - 0.35, pos.Y - 0.35, pos.Z - 0.35, pos.X + 0.35, pos.Y + 0.35, pos.Z + 0.35,
        METAL_DARK, Enum.Material.Metal, parent, DECO)
    local g = pos + out * 0.3 - Vector3.new(0, 0.4, 0)
    box("WallLampGlow", g.X - 0.2, g.Y - 0.1, g.Z - 0.2, g.X + 0.2, g.Y + 0.1, g.Z + 0.2, WARM_LIGHT, Enum.Material.Neon, parent, GLOW)
    pointLight(head, WARM_LIGHT, 1.1, 15)
end

local function lotLight(parent, x, z)
    cyl("LotLightPole", Vector3.new(x, 0.5, z), Vector3.new(x, 13, z), 0.35, METAL_DARK, Enum.Material.Metal, parent)
    local head = box("LotLightHead", x - 0.8, 13, z - 0.5, x + 0.8, 13.5, z + 0.5, METAL_DARK, Enum.Material.Metal, parent, DECO)
    box("LotLightLens", x - 0.6, 12.9, z - 0.35, x + 0.6, 13, z + 0.35, WARM_LIGHT, Enum.Material.Neon, parent, GLOW)
    spotLight(head, Enum.NormalId.Bottom, WARM_LIGHT, 1.8, 24, 120)
end

function MiamiBuilder:_cityLife(f)
    local zc, hw = W.STREET_Z, W.STREET_HALF_WIDTH
    local NORTH_EDGE = -26.2   -- outer edge of the north sidewalk (street furniture line)
    local SOUTH_EDGE = -1.9    -- outer edge of the south sidewalk

    -- ── wayfinding ──
    local signs = folder(f, "Signs")
    -- A) right across from the auto shop garage — the first thing you see on the street
    pole(signs, 13.2, NORTH_EDGE, 14)
    pole(signs, 20.8, NORTH_EDGE, 14)
    wayfinder(signs, Vector3.new(17, 11, NORTH_EDGE + 0.25), Vector3.new(0, 0, 1), 8, 5.6, {
        { "villa", "↑" }, { "mart", "→" }, { "bank", "→" }, { "marina", "→" }, { "jewelry", "←" }, { "police", "←" },
    })
    -- B) for eastbound traffic, just before the marina turn (left = north)
    pole(signs, 88, -26.4, 12.4)
    wayfinder(signs, Vector3.new(87.6, 10, -24.9), Vector3.new(-1, 0, 0), 4.6, 3.0, {
        { "marina", "←" }, { "bank", "→" },
    })
    -- C) for westbound traffic (left = south)
    pole(signs, -20, SOUTH_EDGE, 12.4)
    wayfinder(signs, Vector3.new(-19.6, 10, -3.6), Vector3.new(1, 0, 0), 4.6, 4.2, {
        { "jewelry", "←" }, { "police", "→" }, { "villa", "→" },
    })
    -- D) the MARINA gantry over the drive route (poles just outside x 94..122)
    for _, x in ipairs({ 93.2, 122.8 }) do
        cyl("GantryPole", Vector3.new(x, 0, -27.5), Vector3.new(x, 16, -27.5), 0.6, METAL_DARK, Enum.Material.Metal, signs)
    end
    box("GantryBeam", 93.2, 15.2, -27.8, 122.8, 15.8, -27.2, METAL_DARK, Enum.Material.Metal, signs)
    local gb = box("MarinaSign", 101, 11.4, -27.6, 115, 15.2, -27.3, SIGN_DARK, Enum.Material.Metal, signs)
    do
        local g = gui(gb, Enum.NormalId.Back, 40, 2.5, 0)
        neonLabel(g, "MARINA  ↑", CYAN, { Size = UDim2.fromScale(0.9, 0.58), Position = UDim2.fromScale(0.05, 0.06) }, 4)
        neonLabel(g, "DROP-OFF  ·  CASH OUT", PINK, { Size = UDim2.fromScale(0.7, 0.24), Position = UDim2.fromScale(0.15, 0.7),
            FontFace = UITheme.F.bold }, 2)
    end
    box("MarinaSignTube", 101.2, 11.15, -27.3, 114.8, 11.3, -27.15, CYAN, Enum.Material.Neon, signs, GLOW)
    pointLight(gb, CYAN, 1.2, 14)

    -- street-name blades at the corners
    streetName(signs, 49.5, SOUTH_EDGE, "OCEAN DR", "COLLINS AVE")
    streetName(signs, -43.8, NORTH_EDGE, "OCEAN DR", "ESPANOLA WAY")
    streetName(signs, -108, SOUTH_EDGE, "OCEAN DR", "WASHINGTON AVE")

    -- ── crosswalks (police station, jewelry, mart) ──
    local paint = Color3.fromRGB(226, 224, 214)
    for _, x in ipairs({ -92, -64, 62 }) do
        for z = zc - hw + 1, zc + hw - 1.5, 2 do
            box("Zebra", x - 5, 0.2, z, x + 5, 0.23, z + 1, paint, Enum.Material.SmoothPlastic, f, GLOW)
        end
    end

    -- ── bus stop (south side, between the jewelry store and the auto shop) ──
    local bus = folder(f, "BusStop")
    local bx0, bx1 = -39.5, -30.5
    box("BusStopPad", bx0, 0, -1.4, bx1, 0.5, 2.4, PAVING, Enum.Material.Concrete, bus)
    for _, px in ipairs({ bx0 + 0.5, bx1 - 0.5 }) do
        for _, pz in ipairs({ -1.0, 2.0 }) do
            cyl("ShelterPost", Vector3.new(px, 0.5, pz), Vector3.new(px, 7.2, pz), 0.25, CHROME, Enum.Material.Metal, bus)
        end
    end
    local roof = box("ShelterRoof", bx0 + 0.1, 7.2, -1.5, bx1 - 0.1, 7.5, 2.4, Color3.fromRGB(60, 170, 180), Enum.Material.Metal, bus)
    box("ShelterNeon", bx0 + 0.1, 7.05, -1.55, bx1 - 0.1, 7.15, -1.45, CYAN, Enum.Material.Neon, bus, GLOW)
    pointLight(roof, Color3.fromRGB(220, 240, 255), 1.1, 12)
    box("ShelterGlass", bx0 + 0.5, 0.9, 1.95, bx1 - 0.5, 6.8, 2.05, Color3.fromRGB(170, 210, 230), Enum.Material.Glass, bus,
        { Transparency = 0.55 })
    local ad = box("ShelterAd", bx0 + 0.4, 1.0, -0.8, bx0 + 0.6, 6.4, 1.8, SIGN_DARK, Enum.Material.Metal, bus)
    for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
        local g = gui(ad, face, 30, 1.6, 0)
        local bg = gframe(g, 0.04, 0.03, 0.92, 0.94, ORANGE)
        local grad = Instance.new("UIGradient")
        grad.Rotation = 90
        grad.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(240, 90, 150))
        grad.Parent = bg
        UITheme.label({ Text = "SUNNY'S MART", TextColor3 = WHITE, FontFace = UITheme.F.display, TextScaled = true,
            Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.1),
            TextXAlignment = Enum.TextXAlignment.Center }).Parent = bg
        UITheme.label({ Text = "OPEN LATE", TextColor3 = Color3.fromRGB(40, 20, 40), FontFace = UITheme.F.bold, TextScaled = true,
            Size = UDim2.fromScale(0.7, 0.12), Position = UDim2.fromScale(0.15, 0.38),
            TextXAlignment = Enum.TextXAlignment.Center }).Parent = bg
        UITheme.label({ Text = "SODA · SNACKS · ICE", TextColor3 = WHITE, FontFace = UITheme.F.bold, TextScaled = true,
            Size = UDim2.fromScale(0.8, 0.1), Position = UDim2.fromScale(0.1, 0.75),
            TextXAlignment = Enum.TextXAlignment.Center }).Parent = bg
    end
    box("ShelterBench", bx0 + 2, 1.7, 0.9, bx1 - 2, 2.1, 1.9, Color3.fromRGB(150, 112, 78), Enum.Material.WoodPlanks, bus)
    for _, lx in ipairs({ bx0 + 2.3, bx1 - 2.5 }) do
        box("ShelterBenchLeg", lx, 0.5, 1.0, lx + 0.2, 1.7, 1.8, METAL_DARK, Enum.Material.Metal, bus)
    end
    cyl("BusSignPole", Vector3.new(bx0 - 1.1, 0.5, SOUTH_EDGE), Vector3.new(bx0 - 1.1, 9, SOUTH_EDGE), 0.2, CHROME,
        Enum.Material.Metal, bus)
    local bs = box("BusSign", bx0 - 1.9, 7.0, SOUTH_EDGE - 0.05, bx0 - 0.3, 8.8, SOUTH_EDGE + 0.05, WHITE, Enum.Material.Metal, bus, DECO)
    for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
        local g = gui(bs, face, 60, 1, 0.5)
        UITheme.label({ Text = "BUS", TextColor3 = Color3.fromRGB(20, 70, 160), FontFace = UITheme.F.display, TextScaled = true,
            Size = UDim2.fromScale(0.9, 0.5), Position = UDim2.fromScale(0.05, 0.06),
            TextXAlignment = Enum.TextXAlignment.Center }).Parent = g
        UITheme.label({ Text = "ROUTE 7 · SOUTH BEACH", TextColor3 = Color3.fromRGB(40, 40, 46), FontFace = UITheme.F.bold,
            TextScaled = true, Size = UDim2.fromScale(0.9, 0.26), Position = UDim2.fromScale(0.05, 0.64),
            TextXAlignment = Enum.TextXAlignment.Center }).Parent = g
    end

    -- ── street furniture on the OUTER edge of each sidewalk ──
    local furn = folder(f, "StreetFurniture")
    local RED = Color3.fromRGB(200, 40, 40)
    local YEL = Color3.fromRGB(235, 190, 40)
    hydrant(furn, -53, NORTH_EDGE, RED)
    hydrant(furn, 53.5, NORTH_EDGE, YEL)
    hydrant(furn, 134, NORTH_EDGE, RED)
    hydrant(furn, -16, SOUTH_EDGE, RED)
    hydrant(furn, 104, SOUTH_EDGE, YEL)
    hydrant(furn, -136, SOUTH_EDGE, RED)
    newsBox(furn, -24.5, SOUTH_EDGE, Vector3.new(0, 0, -1))
    newsBox(furn, -67, NORTH_EDGE, Vector3.new(0, 0, 1))
    litterBin(furn, 8, NORTH_EDGE)
    litterBin(furn, 32, NORTH_EDGE)
    litterBin(furn, -29.2, SOUTH_EDGE)
    litterBin(furn, 60, SOUTH_EDGE)

    -- ── alleys: dumpsters, crates, bags, wall lamps ──
    local alley = folder(f, "Alleys")
    local GREEN = Color3.fromRGB(40, 92, 64)
    local BLUE = Color3.fromRGB(40, 70, 120)
    -- NEPTUNE ↔ villa (x -51..-42). The villa side (x -47..-42) stays open.
    dumpster(alley, -49.3, 0, -47, Vector3.new(1, 0, 0), GREEN)
    crate(alley, -49.8, 0, -34.5, 2.2, 0.1)
    crate(alley, -49.9, 0, -32.1, 1.8, -0.2)
    crate(alley, -49.8, 2.2, -34.4, 1.5, 0.4)
    trashBags(alley, -47.6, 0, -50.5)
    wallLamp(alley, Vector3.new(-50.6, 9, -44), Vector3.new(1, 0, 0))
    -- CORAL ↔ villa (x 42..51)
    dumpster(alley, 49.3, 0, -47, Vector3.new(-1, 0, 0), BLUE)
    crate(alley, 49.8, 0, -34.5, 2.2, -0.15)
    crate(alley, 49.6, 0, -32.2, 1.6, 0.3)
    trashBags(alley, 46.6, 0, -50.5)
    wallLamp(alley, Vector3.new(50.6, 9, -44), Vector3.new(-1, 0, 0))
    -- behind the police station
    dumpster(alley, -98, 0, -53.9, Vector3.new(0, 0, -1), GREEN)
    crate(alley, -86, 0, -54, 2.2, 0.2)
    crate(alley, -83.6, 0, -54.2, 1.8, -0.3)
    trashBags(alley, -94.5, 0, -54.5)
    wallLamp(alley, Vector3.new(-92, 9, -52.4), Vector3.new(0, 0, -1))
    -- south lot (back corner)
    dumpster(alley, -89.5, 0.5, 20, Vector3.new(0, 0, -1), BLUE)
    crate(alley, -102.4, 0.5, 20.4, 2.2, 0.3)
    crate(alley, -100, 0.5, 20.6, 1.6, -0.2)
    trashBags(alley, -89.2, 0.5, 16.2)
    lotLight(alley, -86.6, 21.4)
    -- north lot (back corner, west of the marina route)
    dumpster(alley, 89.4, 0.5, -44.3, Vector3.new(0, 0, 1), GREEN)
    crate(alley, 78, 0.5, -44.6, 2, 0.25)
    lotLight(alley, 75, -45.4)
end

-- ──────────────────────────────────────────────
-- 🏚 SAFEHOUSE SKIN — pastel stucco over the brick warehouse
-- ──────────────────────────────────────────────
function MiamiBuilder:skinSafehouse(parentFolder)
    local f = folder(parentFolder, "SafehouseSkin")
    local SKIN = Color3.fromRGB(172, 228, 212)       -- mint stucco
    local BASE = Color3.fromRGB(112, 160, 152)
    local BAND = PASTEL[1]
    local TRIM = STUCCO
    local P = Enum.Material.Plaster
    -- outer faces: x ±24.5, z 3.5 (north), z 40.5 (south); roof top y 17.5
    local N0, N1 = 3.2, 3.5
    local S0, S1 = 40.5, 40.8
    local top = 17.5
    local gx0, gx1, gy1 = -9, 9, 12.5    -- garage opening (keep clear)

    -- stucco shell, 0.3 thick, corners wrapped
    box("SkinNorthW", -24.8, 0, N0, gx0, top, N1, SKIN, P, f)
    box("SkinNorthE", gx1, 0, N0, 24.8, top, N1, SKIN, P, f)
    box("SkinHeader", gx0, gy1, N0, gx1, top, N1, SKIN, P, f)
    box("SkinSouth", -24.8, 0, S0, 24.8, top, S1, SKIN, P, f)
    box("SkinWest", -24.8, 0, N0, -24.5, top, S1, SKIN, P, f)
    box("SkinEast", 24.5, 0, N0, 24.8, top, S1, SKIN, P, f)

    -- plinth band
    box("PlinthNW", -24.95, 0, N0 - 0.15, gx0, 1.2, N0, BASE, Enum.Material.Concrete, f)
    box("PlinthNE", gx1, 0, N0 - 0.15, 24.95, 1.2, N0, BASE, Enum.Material.Concrete, f)
    box("PlinthS", -24.95, 0, S1, 24.95, 1.2, S1 + 0.15, BASE, Enum.Material.Concrete, f)
    box("PlinthW", -24.95, 0, N0 - 0.15, -24.8, 1.2, S1 + 0.15, BASE, Enum.Material.Concrete, f)
    box("PlinthE", 24.8, 0, N0 - 0.15, 24.95, 1.2, S1 + 0.15, BASE, Enum.Material.Concrete, f)

    -- pink band under the parapet, all the way round
    box("BandN", -24.95, 16.7, N0 - 0.25, 24.95, 17.3, N0, BAND, P, f)
    box("BandS", -24.95, 16.7, S1, 24.95, 17.3, S1 + 0.25, BAND, P, f)
    box("BandW", -25.05, 16.7, N0 - 0.25, -24.8, 17.3, S1 + 0.25, BAND, P, f)
    box("BandE", 24.8, 16.7, N0 - 0.25, 25.05, 17.3, S1 + 0.25, BAND, P, f)

    -- parapet + white coping around the roof edge
    box("ParapetN", -24.8, 16.5, N0, 24.8, 19, N0 + 1, SKIN, P, f)
    box("ParapetS", -24.8, 16.5, S1 - 1, 24.8, 19, S1, SKIN, P, f)
    box("ParapetW", -24.8, 16.5, N0, -23.8, 19, S1, SKIN, P, f)
    box("ParapetE", 23.8, 16.5, N0, 24.8, 19, S1, SKIN, P, f)
    box("CopingN", -24.95, 19, N0 - 0.15, 24.95, 19.3, N0 + 1.15, TRIM, P, f)
    box("CopingS", -24.95, 19, S1 - 1.15, 24.95, 19.3, S1 + 0.15, TRIM, P, f)
    box("CopingW", -24.95, 19, N0 - 0.15, -23.65, 19.3, S1 + 0.15, TRIM, P, f)
    box("CopingE", 23.65, 19, N0 - 0.15, 24.95, 19.3, S1 + 0.15, TRIM, P, f)

    -- stepped deco crown over the sign
    box("StepA", -13, 19, N0, 13, 20.6, N0 + 2, SKIN, P, f)
    box("StepACap", -13.2, 20.6, N0 - 0.15, 13.2, 20.85, N0 + 2.15, TRIM, P, f)
    box("StepB", -7, 20.85, N0, 7, 22.2, N0 + 1.4, BAND, P, f)
    box("StepBCap", -7.2, 22.2, N0 - 0.15, 7.2, 22.45, N0 + 1.55, TRIM, P, f)
    box("StepC", -2.5, 22.45, N0, 2.5, 23.8, N0 + 1, SKIN, P, f)
    box("StepCCap", -2.7, 23.8, N0 - 0.15, 2.7, 24.05, N0 + 1.15, TRIM, P, f)

    -- vertical fins: both north corners + flanking the garage, rising past the roof
    for _, sx in ipairs({ -1, 1 }) do
        box("CornerFin", sx * 23.4, 0, N0 - 0.9, sx * 24.8, 21.2, N0, TRIM, P, f)
        box("CornerFinCap", sx * 23.25, 21.2, N0 - 1.05, sx * 24.95, 21.5, N0 + 0.2, BAND, P, f)
        box("GarageFin", sx * 11.3, 0, N0 - 0.9, sx * 12.5, 21.8, N0, TRIM, P, f)
        box("GarageFinCap", sx * 11.15, 21.8, N0 - 1.05, sx * 12.65, 22.1, N0 + 0.2, BAND, P, f)
        -- three speed lines between the fins, wrapping onto the side wall
        for k = 0, 2 do
            local y = 9.8 + k * 0.7
            box("SpeedLine", sx * 12.5, y, N0 - 0.25, sx * 23.4, y + 0.3, N0, TRIM, P, f)
            box("SpeedLine", sx * 24.8, y, N0, sx * 25.05, y + 0.3, 14, TRIM, P, f)
        end
    end

    -- eyebrow canopy over the garage + a warm downlight onto the driveway
    local canopy = box("GarageCanopy", -11.2, 12.5, 1.6, 11.2, 12.8, N0, TRIM, Enum.Material.Concrete, f)
    spotLight(canopy, Enum.NormalId.Bottom, WARM_LIGHT, 1.5, 16, 100, true)

    -- ── the big neon sign ──
    local board = box("NeonShopSign", -11, 13, 2.8, 11, 16.4, N0, SIGN_DARK, Enum.Material.Metal, f)
    local g = gui(board, Enum.NormalId.Front, 30, 2.6, 0)
    neonLabel(g, "RIVERSIDE AUTO", PINK, { Size = UDim2.fromScale(0.94, 0.58), Position = UDim2.fromScale(0.03, 0.07) }, 4)
    neonLabel(g, "BODY SHOP", CYAN, { Size = UDim2.fromScale(0.44, 0.24), Position = UDim2.fromScale(0.28, 0.7) }, 2)
    for _, x in ipairs({ 0.06, 0.74 }) do
        local line = gframe(g, x, 0.815, 0.2, 0.025, CYAN:Lerp(WHITE, 0.3))
        local st = Instance.new("UIStroke")
        st.Color = CYAN
        st.Transparency = 0.4
        st.Thickness = 2
        st.Parent = line
    end
    -- neon tube border around the board
    box("SignTubeTop", -11.2, 16.4, 2.6, 11.2, 16.6, 2.8, CYAN, Enum.Material.Neon, f, GLOW)
    box("SignTubeBottom", -11.2, 12.8, 2.6, 11.2, 13.0, 2.8, CYAN, Enum.Material.Neon, f, GLOW)
    box("SignTubeLeft", -11.2, 13.0, 2.6, -11.0, 16.4, 2.8, CYAN, Enum.Material.Neon, f, GLOW)
    box("SignTubeRight", 11.0, 13.0, 2.6, 11.2, 16.4, 2.8, CYAN, Enum.Material.Neon, f, GLOW)
    -- real light: pink spill on the stucco around it + a wash down the driveway
    pointLight(board, PINK, 1.6, 14)
    local wash = Instance.new("SurfaceLight")
    wash.Face = Enum.NormalId.Front
    wash.Color = PINK
    wash.Brightness = 1.2
    wash.Range = 16
    wash.Angle = 110
    wash.Parent = board

    -- two neon wall lamps either side of the garage (between opening and fins)
    for _, sx in ipairs({ -1, 1 }) do
        local x0, x1 = sx * 9.8, sx * 10.8
        box("WallLampPlate", x0, 7, 2.95, x1, 9.6, N0, METAL_DARK, Enum.Material.Metal, f, DECO)
        box("WallLampShade", x0 - sx * 0.1, 9.3, 2.6, x1 + sx * 0.1, 9.6, N0, CHROME, Enum.Material.Metal, f, DECO)
        local tube = box("WallLampTube", sx * 10.15, 7.3, 2.7, sx * 10.45, 9.3, 2.95, CYAN, Enum.Material.Neon, f, GLOW)
        pointLight(tube, CYAN, 1.2, 10)
    end

    print("[MiamiBuilder] Safehouse skinned in pastel stucco 🎨")
end

-- ──────────────────────────────────────────────
-- 🚀 BUILD
-- ──────────────────────────────────────────────
function MiamiBuilder:build(parentFolder)
    local root = folder(parentFolder, "NeonMiami")
    self:_ground(folder(root, "Ground"))
    local street = folder(root, "OceanDriveExt")
    self:_streetExtension(street)
    self:_puddles(folder(root, "Puddles"))
    self:_buildings(folder(root, "DecoBuildings"))
    self:_palms(folder(root, "Palms"))
    self:_beach(folder(root, "Beach"))
    self:_marina(folder(root, "Marina"))
    self:_cars(folder(root, "ParkedCars"))

    -- v2: the station is what JailService needs, so it's isolated — a bug in
    -- the city dressing must never cost us the jail (and vice versa).
    local okJail, jail = pcall(self._policeStation, self, folder(root, "PoliceStation"))
    if not okJail then
        warn("[MiamiBuilder] ❌ police station failed: " .. tostring(jail))
        jail = nil
    end
    local okCity, err = pcall(self._cityLife, self, folder(root, "CityLife"))
    if not okCity then warn("[MiamiBuilder] ❌ city life failed: " .. tostring(err)) end

    print("[MiamiBuilder] Neon Miami built 🌴")
    return { jail = jail }
end

return MiamiBuilder
