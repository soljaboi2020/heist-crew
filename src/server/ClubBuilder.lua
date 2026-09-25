--[[
    HEIST CREW — ClubBuilder  (v1.2 "THE VAULT")
    ────────────────────────────────────────────────
    The crew's underground HQ: a two-storey neon nightclub hidden under the
    Riverside Auto Body shop. This is where you SPAWN. (Malachi picked option A,
    2026-09-25: "a huge inside center where the heist spawns you".)

    Footprint x -44..44, z 0..64, floor top y -27.5 (Constants.WORLD.HUB_*),
    ceiling y -3.5 — safely under the street-level lawn (y -2..0).

      NORTH  DJ stage + LED wall ("THE VAULT") + moving truss spots
             dance floor (glass tiles the client animates — ClubFX)
      CENTRE holo planning table: blueprint + Boss + READY UP / change job
             job screen hanging above it (next job · top earners · crew)
      WEST   the bar, VIP mezzanine above it (stairs by the stage)
             mask wall (real catalog masks on display heads) → opens the shop
      EAST   crew-role pads + signs
      SOUTH  spawn · freight elevator up to the auto shop ·
             garage bay with the ramp the getaway car rolls up at launch ·
             trophy room (fills in as the crew pulls off heists)

    Returns refs in the SAME shape SafehouseBuilder used to (pads / tv /
    blueprint) so CrewService + SafehouseBuilder:showJob work unchanged, plus
    trophies / bay / prompts. Geometry only — services add the behaviour.
    Tagged for ClubFX (client): DanceTile, ClubLight, ClubSpot, ClubEQ.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local ClubBuilder = {}

local W = Constants.WORLD
local T = UITheme.C
local F = W.HUB_FLOOR                         -- -27.5 (floor top)
local HW, HD, H = W.HUB_HALF_WIDTH, W.HUB_HALF_DEPTH, W.HUB_HEIGHT
local CZ = W.HUB_CENTER.z
local X0, X1 = -HW, HW                        -- -44 .. 44
local Z0, Z1 = CZ - HD, CZ + HD               -- 0 .. 64
local TOP = F + H                             -- -3.5 ceiling
local MEZZ = F + 11                           -- -16.5 mezzanine floor top

local PINK = Color3.fromRGB(255, 70, 180)
local CYAN = Color3.fromRGB(40, 230, 255)
local PURPLE = Color3.fromRGB(170, 90, 255)
local WALL = Color3.fromRGB(34, 30, 44)
local PANEL = Color3.fromRGB(24, 22, 32)
local STEEL = Color3.fromRGB(44, 47, 56)
local WOOD = Color3.fromRGB(70, 46, 34)

-- ── helpers (same style as SafehouseBuilder) ─────────────────────────
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
        Color = color, Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function neon(name, x0, y0, z0, x1, y1, z1, color, parent)
    return box(name, x0, y0, z0, x1, y1, z1, color, Enum.Material.Neon, parent, { CanCollide = false })
end

local function surface(p, face, pps)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 40
    g.LightInfluence = 0
    g.Brightness = 1.4
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

local function light(class, parent, props)
    local l = Instance.new(class)
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function sub(parent, name)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function prompt(parent, name, action, object, key, hold)
    local p = Instance.new("ProximityPrompt")
    p.Name = name
    p.ActionText = action
    p.ObjectText = object
    p.HoldDuration = hold or 0.3
    p.MaxActivationDistance = 10
    p.RequiresLineOfSight = false
    p.KeyboardKeyCode = key or Enum.KeyCode.E
    p.Parent = parent
    return p
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL
-- ──────────────────────────────────────────────
function ClubBuilder:_shell(f)
    -- polished dark floor
    box("Floor", X0, F - 1, Z0, X1, F, Z1, Color3.fromRGB(26, 24, 32), Enum.Material.Marble, f, { Reflectance = 0.08 })
    box("Ceiling", X0 - 1, TOP, Z0 - 1, X1 + 1, TOP + 1, Z1 + 1, Color3.fromRGB(18, 18, 24), Enum.Material.Metal, f)
    -- walls
    box("WallN", X0 - 1, F, Z0 - 1, X1 + 1, TOP, Z0, WALL, Enum.Material.Concrete, f)
    box("WallS", X0 - 1, F, Z1, X1 + 1, TOP, Z1 + 1, WALL, Enum.Material.Concrete, f)
    box("WallW", X0 - 1, F, Z0, X0, TOP, Z1, WALL, Enum.Material.Concrete, f)
    box("WallE", X1, F, Z0, X1 + 1, TOP, Z1, WALL, Enum.Material.Concrete, f)
    -- acoustic panels (fabric) in a band around the room
    box("PanelsW", X0, F + 3, Z0 + 1, X0 + 0.3, F + 9, Z1 - 1, PANEL, Enum.Material.Fabric, f)
    box("PanelsE", X1 - 0.3, F + 3, Z0 + 1, X1, F + 9, Z1 - 1, PANEL, Enum.Material.Fabric, f)
    box("PanelsS", X0 + 1, F + 3, Z1 - 0.3, X1 - 1, F + 9, Z1, PANEL, Enum.Material.Fabric, f)
    -- ceiling trusses
    for z = Z0 + 8, Z1 - 4, 12 do
        box("Truss", X0, TOP - 1.4, z - 0.4, X1, TOP - 0.6, z + 0.4, STEEL, Enum.Material.Metal, f)
    end
    -- neon: pink along the long walls up top, cyan along the short walls, purple at the base
    neon("NeonW", X0 + 0.05, TOP - 2.2, Z0 + 1, X0 + 0.3, TOP - 2, Z1 - 1, PINK, f)
    neon("NeonE", X1 - 0.3, TOP - 2.2, Z0 + 1, X1 - 0.05, TOP - 2, Z1 - 1, PINK, f)
    neon("NeonN", X0 + 1, TOP - 2.2, Z0 + 0.05, X1 - 1, TOP - 2, Z0 + 0.3, CYAN, f)
    neon("NeonS", X0 + 1, TOP - 2.2, Z1 - 0.3, X1 - 1, TOP - 2, Z1 - 0.05, CYAN, f)
    neon("BaseW", X0 + 0.3, F + 0.1, Z0 + 1, X0 + 0.45, F + 0.25, Z1 - 1, PURPLE, f)
    neon("BaseE", X1 - 0.45, F + 0.1, Z0 + 1, X1 - 0.3, F + 0.25, Z1 - 1, PURPLE, f)
    -- four big columns with neon rings
    for _, c in ipairs({ { -22, 24 }, { 22, 24 }, { -22, 40 }, { 22, 40 } }) do
        part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(H, 3, 3),
            CFrame = CFrame.new(c[1], F + H / 2, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(40, 38, 50), Material = Enum.Material.Concrete }, f)
        for _, y in ipairs({ F + 3, TOP - 4 }) do
            part({ Name = "ColumnRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 3.3, 3.3),
                CFrame = CFrame.new(c[1], y, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
                Color = (c[2] < 30) and CYAN or PINK, Material = Enum.Material.Neon, CanCollide = false }, f)
        end
    end
    -- soft fill so it's moody, not pitch black
    local fill = box("Fill", -1, TOP - 3, CZ - 1, 1, TOP - 2.5, CZ + 1, STEEL, Enum.Material.Metal, f, { Transparency = 1, CanCollide = false })
    light("PointLight", fill, { Brightness = 0.5, Range = 60, Color = Color3.fromRGB(150, 120, 200) })
end

-- ──────────────────────────────────────────────
-- 🎧 DJ STAGE + LED WALL + truss spots
-- ──────────────────────────────────────────────
function ClubBuilder:_stage(f)
    local sy = F + 2.5
    box("Stage", -14, F, Z0, 14, sy, Z0 + 9, Color3.fromRGB(30, 30, 36), Enum.Material.DiamondPlate, f)
    neon("StageEdge", -14, sy - 0.25, Z0 + 9, 14, sy - 0.05, Z0 + 9.2, CYAN, f)
    for i = 1, 3 do
        box("StageStep", -4, F, Z0 + 9 + (i - 1) * 0.9, 4, sy - i * 0.8, Z0 + 9.9 + (i - 1) * 0.9,
            Color3.fromRGB(34, 34, 40), Enum.Material.DiamondPlate, f)
    end
    -- DJ desk + decks
    box("DJDesk", -5, sy, Z0 + 4.5, 5, sy + 3, Z0 + 6.5, Color3.fromRGB(16, 16, 20), Enum.Material.Metal, f)
    neon("DJDeskGlow", -5, sy + 0.3, Z0 + 6.5, 5, sy + 0.45, Z0 + 6.6, PINK, f)
    for _, dx in ipairs({ -2.6, 2.6 }) do
        part({ Name = "Turntable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.2, 2.2),
            CFrame = CFrame.new(dx, sy + 3.1, Z0 + 5.5) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(12, 12, 14), Material = Enum.Material.Metal }, f)
    end
    KenneyLoader.placeMany({
        { kit = "furniture", name = "speaker", pos = Vector3.new(-11, sy, Z0 + 5), facing = Vector3.new(0, 0, 1), opts = { scale = 2.4 } },
        { kit = "furniture", name = "speaker", pos = Vector3.new(11, sy, Z0 + 5), facing = Vector3.new(0, 0, 1), opts = { scale = 2.4 } },
        { kit = "furniture", name = "laptop", pos = Vector3.new(0, sy + 3, Z0 + 5.4), facing = Vector3.new(0, 0, -1) },
    }, f)

    -- LED wall (the client animates the EQ bars — ClubFX)
    local led = box("LEDWall", -18, F + 3, Z0, 18, F + 19, Z0 + 0.4, Color3.fromRGB(6, 6, 10), Enum.Material.Glass, f)
    local g = surface(led, Enum.NormalId.Back, 22)
    g.Brightness = 2
    CollectionService:AddTag(g, "ClubEQ")
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 6, 16) }, g)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.fromRGB(60, 10, 70), Color3.fromRGB(8, 20, 60))
    grad.Parent = bg
    local eq = frame({ Name = "EQ", Size = UDim2.new(1, -60, 0.55, 0), Position = UDim2.new(0, 30, 0.42, 0),
        BackgroundTransparency = 1 }, bg)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, 6)
    layout.Parent = eq
    for i = 1, 28 do
        local b = frame({ Name = "Bar", Size = UDim2.new(1 / 28, -6, 0.3, 0), BackgroundColor3 = (i % 2 == 0) and PINK or CYAN }, eq)
        b.LayoutOrder = i
        UITheme.corner(b, 3)
    end
    text({ Text = "THE VAULT", Position = UDim2.fromScale(0, 0.06), Size = UDim2.fromScale(1, 0.32),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(255, 240, 250), TextStrokeColor3 = PINK, TextStrokeTransparency = 0.2 }, bg)
    light("SurfaceLight", led, { Face = Enum.NormalId.Back, Brightness = 1.2, Range = 22, Angle = 90, Color = PURPLE })

    -- truss with moving spots (ClubSpot — rotated by ClubFX on each client)
    box("StageTruss", -16, TOP - 5, Z0 + 10, 16, TOP - 4.4, Z0 + 10.6, STEEL, Enum.Material.Metal, f)
    local cols = { PINK, CYAN, PURPLE, Color3.fromRGB(255, 170, 60) }
    for i, x in ipairs({ -12, -4, 4, 12 }) do
        local head = part({ Name = "MovingHead", Size = Vector3.new(1.2, 1.2, 1.6), Color = Color3.fromRGB(20, 20, 24),
            Material = Enum.Material.Metal, CanCollide = false,
            CFrame = CFrame.lookAt(Vector3.new(x, TOP - 5.6, Z0 + 10.3), Vector3.new(x, F, Z0 + 20)) }, f)
        head:SetAttribute("Seed", i)
        CollectionService:AddTag(head, "ClubSpot")
        light("SpotLight", head, { Face = Enum.NormalId.Front, Angle = 28, Brightness = 5, Range = 40, Color = cols[i], Shadows = false })
    end
end

-- ──────────────────────────────────────────────
-- 💃 DANCE FLOOR (tiles animated client-side)
-- ──────────────────────────────────────────────
function ClubBuilder:_danceFloor(f)
    local x0, z0 = -12, 12
    local cols, rows = 12, 8
    local palette = { PINK, CYAN, PURPLE }
    for c = 0, cols - 1 do
        for r = 0, rows - 1 do
            local t = part({ Name = "DanceTile", Size = Vector3.new(1.9, 0.2, 1.9),
                Position = Vector3.new(x0 + c * 2 + 1, F + 0.1, z0 + r * 2 + 1),
                Color = palette[(c + r) % 3 + 1], Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.1 }, f)
            t:SetAttribute("Col", c)
            t:SetAttribute("Row", r)
            CollectionService:AddTag(t, "DanceTile")
        end
    end
    neon("FloorFrameN", x0 - 0.3, F, z0 - 0.3, x0 + cols * 2 + 0.3, F + 0.25, z0, CYAN, f)
    neon("FloorFrameS", x0 - 0.3, F, z0 + rows * 2, x0 + cols * 2 + 0.3, F + 0.25, z0 + rows * 2 + 0.3, CYAN, f)
    neon("FloorFrameW", x0 - 0.3, F, z0, x0, F + 0.25, z0 + rows * 2, CYAN, f)
    neon("FloorFrameE", x0 + cols * 2, F, z0, x0 + cols * 2 + 0.3, F + 0.25, z0 + rows * 2, CYAN, f)
    for i, p in ipairs({ { -6, 16 }, { 6, 16 }, { -6, 24 }, { 6, 24 } }) do
        local anchor = box("FloorLight", p[1] - 0.2, TOP - 3, p[2] - 0.2, p[1] + 0.2, TOP - 2.6, p[2] + 0.2, STEEL,
            Enum.Material.Metal, f, { Transparency = 1, CanCollide = false })
        anchor:SetAttribute("Seed", i)
        CollectionService:AddTag(anchor, "ClubLight")
        light("PointLight", anchor, { Brightness = 2.2, Range = 26, Color = palette[(i - 1) % 3 + 1] })
    end
end

-- ──────────────────────────────────────────────
-- 🍸 BAR (west) + VIP MEZZANINE above it
-- ──────────────────────────────────────────────
function ClubBuilder:_bar(f)
    local bx = X0 + 8     -- counter front face x -36
    box("BarBase", bx - 2, F, 12, bx, F + 3.4, 34, WOOD, Enum.Material.WoodPlanks, f)
    box("BarTop", bx - 2.3, F + 3.4, 11.7, bx + 0.3, F + 3.7, 34.3, Color3.fromRGB(230, 225, 235), Enum.Material.Marble, f)
    neon("BarGlow", bx + 0.02, F + 0.3, 12, bx + 0.12, F + 0.45, 34, PINK, f)
    -- back bar: shelves + bottles against the wall
    for i, y in ipairs({ F + 4, F + 6.5, F + 9 }) do
        box("Shelf" .. i, X0 + 0.3, y, 13, X0 + 2.2, y + 0.25, 33, Color3.fromRGB(30, 26, 28), Enum.Material.Metal, f)
        neon("ShelfGlow" .. i, X0 + 2.15, y - 0.05, 13, X0 + 2.25, y, 33, i % 2 == 0 and CYAN or PURPLE, f)
        local bottleCols = { Color3.fromRGB(60, 180, 90), Color3.fromRGB(200, 120, 40), Color3.fromRGB(80, 140, 220), Color3.fromRGB(220, 60, 90) }
        for z = 13.8, 32.4, 1.25 do
            local hgt = 1.1 + ((z * 7) % 3) * 0.25
            part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hgt, 0.45, 0.45),
                CFrame = CFrame.new(X0 + 1.2, y + 0.25 + hgt / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
                Color = bottleCols[math.floor(z) % 4 + 1], Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false }, f)
        end
    end
    -- BAR sign
    local sign = box("BarSign", X0 + 0.3, F + 12, 18, X0 + 0.6, F + 15, 28, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local g = surface(sign, Enum.NormalId.Right, 30)
    g.Brightness = 2.5
    text({ Text = "COCKTAILS", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 200, 235),
        TextStrokeColor3 = PINK, TextStrokeTransparency = 0 }, g)
    light("PointLight", sign, { Brightness = 1.5, Range = 14, Color = PINK })
    local props = {}
    for z = 14, 32, 3 do
        table.insert(props, { kit = "furniture", name = "stoolBar", pos = Vector3.new(bx + 1.6, F, z), facing = Vector3.new(-1, 0, 0) })
    end
    KenneyLoader.placeMany(props, f)
    for _, z in ipairs({ 16, 23, 30 }) do
        local lamp = box("BarPendant", bx - 1.2, MEZZ - 3, z - 0.4, bx - 0.4, MEZZ - 2.6, z + 0.4, Color3.fromRGB(230, 180, 120),
            Enum.Material.Neon, f, { CanCollide = false })
        light("PointLight", lamp, { Brightness = 1.2, Range = 10, Color = Color3.fromRGB(255, 190, 130) })
    end

    -- VIP mezzanine above the bar: x -44..-32, z 2..38, with glass railing
    local mx1 = X0 + 12
    box("Mezzanine", X0, MEZZ - 0.6, Z0 + 2, mx1, MEZZ, 38, Color3.fromRGB(30, 28, 36), Enum.Material.DiamondPlate, f)
    box("MezzRailGlass", mx1 - 0.15, MEZZ, Z0 + 5.5, mx1, MEZZ + 3, 38, Color3.fromRGB(170, 200, 255), Enum.Material.Glass, f, { Transparency = 0.6 })
    box("MezzRailTop", mx1 - 0.25, MEZZ + 3, Z0 + 5.5, mx1 + 0.1, MEZZ + 3.25, 38, STEEL, Enum.Material.Metal, f)
    box("MezzRailGlassS", X0, MEZZ, 37.85, mx1, MEZZ + 3, 38, Color3.fromRGB(170, 200, 255), Enum.Material.Glass, f, { Transparency = 0.6 })
    neon("MezzGlow", mx1 - 0.3, MEZZ - 0.7, Z0 + 2, mx1, MEZZ - 0.55, 38, CYAN, f)
    -- stairs along the north wall, from the stage's west side up to the mezzanine
    -- stairs along the north wall: from the floor at x -16 climbing WEST to the
    -- mezzanine edge at x -32 (22 steps of 0.5 up, ~0.73 across)
    local steps = 22
    local run = (-16) - mx1          -- 16 studs
    for i = 1, steps do
        local xa = -16 - (i - 1) * run / steps
        local xb = xa - run / steps
        local y = F + i * (MEZZ - F) / steps
        box("Step", xb, F, Z0 + 1, xa, y, Z0 + 5, Color3.fromRGB(34, 32, 40), Enum.Material.DiamondPlate, f)
    end
    KenneyLoader.placeMany({
        { kit = "furniture", name = "loungeDesignSofa", pos = Vector3.new(X0 + 3, MEZZ, 14), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "loungeDesignSofa", pos = Vector3.new(X0 + 3, MEZZ, 26), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "tableCoffeeGlass", pos = Vector3.new(X0 + 7, MEZZ, 14), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "tableCoffeeGlass", pos = Vector3.new(X0 + 7, MEZZ, 26), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(X0 + 2, MEZZ, 36), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(X0 + 2, MEZZ, 6), facing = Vector3.new(1, 0, 0) },
    }, f)
    local vip = box("VIPSign", X0 + 0.3, MEZZ + 4, 18, X0 + 0.6, MEZZ + 6.5, 24, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local vg = surface(vip, Enum.NormalId.Right, 30)
    vg.Brightness = 2.5
    text({ Text = "VIP", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextScaled = true, TextColor3 = Color3.fromRGB(255, 235, 180), TextStrokeColor3 = Color3.fromRGB(255, 170, 60), TextStrokeTransparency = 0 }, vg)
end

-- ──────────────────────────────────────────────
-- 🗺 HOLO TABLE + JOB SCREEN
-- ──────────────────────────────────────────────
local function drawTV(bg, refs)
    UITheme.padding(bg, 28, 22)
    local left = frame({ Size = UDim2.fromScale(0.52, 0.72), BackgroundTransparency = 1 }, bg)
    text({ Text = "NEXT JOB", Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.gold, FontFace = UITheme.F.bold, TextSize = 22 }, left)
    local jobName = text({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 70),
        TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, left)
    local jobTag = text({ Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 26),
        TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 24 }, left)
    local statCells = {}
    for i, s in ipairs({ "DIFFICULTY", "GUARDS", "TAKE" }) do
        local cell = frame({ Size = UDim2.new(0.31, 0, 0, 74), Position = UDim2.new((i - 1) * 0.345, 0, 0, 150),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, left)
        UITheme.corner(cell, 10)
        text({ Text = s, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), TextColor3 = T.muted,
            FontFace = UITheme.F.bold, TextSize = 15 }, cell)
        statCells[i] = text({ Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 34),
            TextColor3 = (i == 3) and T.money or T.text, FontFace = UITheme.F.display, TextScaled = true }, cell)
    end
    local right = frame({ Size = UDim2.fromScale(0.42, 0.72), Position = UDim2.fromScale(0.58, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.95 }, bg)
    UITheme.corner(right, 12)
    UITheme.padding(right, 16, 12)
    text({ Text = "TOP EARNERS", Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.gold, FontFace = UITheme.F.bold, TextSize = 22 }, right)
    local rows = {}
    for r = 1, 5 do
        local y = 34 + (r - 1) * 44
        local rank = text({ Text = tostring(r), Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(30, 36),
            TextColor3 = (r == 1) and T.gold or T.faint, FontFace = UITheme.F.display, TextSize = 28 }, right)
        local name = text({ Text = "—", Position = UDim2.fromOffset(36, y), Size = UDim2.new(0.6, -36, 0, 36),
            TextColor3 = T.text, FontFace = UITheme.F.bold, TextSize = 26, TextTruncate = Enum.TextTruncate.AtEnd }, right)
        local cash = text({ Position = UDim2.new(0.6, 0, 0, y), Size = UDim2.new(0.4, 0, 0, 36),
            TextColor3 = T.money, FontFace = UITheme.F.display, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right }, right)
        rows[r] = { rank = rank, name = name, cash = cash }
    end
    local crewRow = frame({ Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.78), BackgroundTransparency = 1 }, bg)
    local crew = {}
    for i, role in ipairs(Constants.ROLES) do
        local chip = frame({ Size = UDim2.new(0.235, 0, 1, 0), Position = UDim2.fromScale((i - 1) * 0.255, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, crewRow)
        UITheme.corner(chip, 10)
        frame({ Size = UDim2.new(0, 6, 1, -20), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = UITheme.rgb(role.color) }, chip)
        text({ Text = string.upper(role.id), Position = UDim2.fromOffset(26, 8), Size = UDim2.new(1, -34, 0.4, 0),
            TextColor3 = UITheme.rgb(role.color), FontFace = UITheme.F.bold, TextScaled = true }, chip)
        crew[role.id] = text({ Text = "open", Position = UDim2.new(0, 26, 0.45, 0), Size = UDim2.new(1, -34, 0.45, 0),
            TextColor3 = T.muted, FontFace = UITheme.F.bold, TextScaled = true, TextTruncate = Enum.TextTruncate.AtEnd }, chip)
    end
    refs.tv = { rows = rows, crew = crew, jobName = jobName, jobTag = jobTag, stats = statCells }
end

function ClubBuilder:_holoTable(f, refs)
    local c = W.HUB_TABLE
    local top = F + 3.4
    part({ Name = "HoloBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.1, 8, 8),
        CFrame = CFrame.new(c.x, F + 1.55, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Color3.fromRGB(20, 20, 26), Material = Enum.Material.Metal }, f)
    local ring = part({ Name = "HoloRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 12.4, 12.4),
        CFrame = CFrame.new(c.x, top - 0.15, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Color3.fromRGB(14, 14, 18), Material = Enum.Material.Metal }, f)
    part({ Name = "HoloRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 12.7, 12.7),
        CFrame = CFrame.new(c.x, top - 0.25, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = CYAN, Material = Enum.Material.Neon, CanCollide = false }, f)
    -- the blueprint, drawn in glowing cyan (SafehouseBuilder:showJob fills it in)
    local sheet = box("HoloSheet", c.x - 4.6, top, c.z - 3.3, c.x + 4.6, top + 0.04, c.z + 3.3,
        Color3.fromRGB(6, 20, 30), Enum.Material.Glass, f, { CanCollide = false })
    local g = surface(sheet, Enum.NormalId.Top, 60)
    g.Brightness = 2
    local PAPER, INK = Color3.fromRGB(6, 22, 34), Color3.fromRGB(90, 235, 255)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER }, g)
    for i = 1, 15 do
        frame({ Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(i / 16, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.9 }, bg)
    end
    for i = 1, 11 do
        frame({ Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 12), BackgroundColor3 = INK, BackgroundTransparency = 0.9 }, bg)
    end
    local title = text({ Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 30), TextColor3 = INK,
        FontFace = UITheme.F.display, TextSize = 26 }, bg)
    local subT = text({ Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 18), TextColor3 = INK,
        TextTransparency = 0.3, FontFace = UITheme.F.bold, TextSize = 14 }, bg)
    local plan = frame({ Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.08, 0.28), BackgroundTransparency = 1 }, bg)
    local notes = frame({ Size = UDim2.fromScale(0.24, 0.62), Position = UDim2.fromScale(0.74, 0.28), BackgroundTransparency = 1 }, bg)
    refs.blueprint = { title = title, sub = subT, plan = plan, notes = notes, ink = INK, paper = PAPER }
    -- hologram column
    part({ Name = "Hologram", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 7, 7),
        CFrame = CFrame.new(c.x, top + 2.5, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = CYAN, Material = Enum.Material.ForceField, Transparency = 0.2, CanCollide = false, CanQuery = false }, f)
    light("PointLight", sheet, { Brightness = 2, Range = 16, Color = CYAN })

    refs.readyPart = ring
    local r = prompt(ring, "ReadyUp", "Ready up", "Holo table", Enum.KeyCode.E, 0.3)
    r.Triggered:Connect(function(player) if ClubBuilder.onReadyUp then ClubBuilder.onReadyUp(player) end end)
    local n = prompt(ring, "NextJob", "Change job", "Holo table", Enum.KeyCode.R, 0.4)
    n.GamepadKeyCode = Enum.KeyCode.ButtonY
    n.Triggered:Connect(function(player) if ClubBuilder.onNextJob then ClubBuilder.onNextJob(player) end end)

    local stools = {}
    for i = 0, 5 do
        local a = math.rad(30 + i * 60)
        if i ~= 0 then   -- leave a gap on the east side (30°) for the Boss
            table.insert(stools, { kit = "furniture", name = "stoolBar",
                pos = Vector3.new(c.x + math.cos(a) * 7.6, F, c.z + math.sin(a) * 7.6),
                facing = Vector3.new(-math.cos(a), 0, -math.sin(a)) })
        end
    end
    KenneyLoader.placeMany(stools, f)

    -- job screen hanging north of the table, facing the spawn
    local sw, sh = 20, 11.25
    local sz = c.z - 9
    local tv = box("JobScreen", c.x - sw / 2, TOP - 5 - sh, sz - 0.2, c.x + sw / 2, TOP - 5, sz + 0.2,
        Color3.fromRGB(8, 9, 12), Enum.Material.Glass, f)
    box("JobScreenBezel", c.x - sw / 2 - 0.3, TOP - 5.3 - sh, sz - 0.3, c.x + sw / 2 + 0.3, TOP - 4.7, sz - 0.15,
        Color3.fromRGB(18, 18, 20), Enum.Material.Metal, f)
    for _, dx in ipairs({ -sw / 2 + 1, sw / 2 - 1 }) do
        box("ScreenCable", c.x + dx - 0.06, TOP - 4.7, sz - 0.06, c.x + dx + 0.06, TOP, sz + 0.06, STEEL, Enum.Material.Metal, f, { CanCollide = false })
    end
    local tg = surface(tv, Enum.NormalId.Back, 40)
    tg.Brightness = 1.3
    local tbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 18) }, tg)
    local tgr = Instance.new("UIGradient")
    tgr.Rotation = 35
    tgr.Color = ColorSequence.new(Color3.fromRGB(40, 30, 72), Color3.fromRGB(12, 14, 20))
    tgr.Parent = tbg
    drawTV(tbg, refs)
    light("SurfaceLight", tv, { Face = Enum.NormalId.Back, Brightness = 0.8, Range = 16, Angle = 90, Color = Color3.fromRGB(150, 170, 255) })
end

-- ──────────────────────────────────────────────
-- 🎭 CREW PADS (east wall)
-- ──────────────────────────────────────────────
function ClubBuilder:_crewPads(f, refs)
    refs.pads = {}
    for i, role in ipairs(Constants.ROLES) do
        local z = 12 + (i - 1) * 7
        local x = X1 - 7
        local col = UITheme.rgb(role.color)
        local rim = part({ Name = role.id .. "PadRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 5.6, 5.6),
            Color = col, Material = Enum.Material.SmoothPlastic,
            CFrame = CFrame.new(x, F + 0.12, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        part({ Name = role.id .. "Pad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.8, 4.8),
            Color = Color3.fromRGB(30, 32, 38), Material = Enum.Material.DiamondPlate,
            CFrame = CFrame.new(x, F + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        local label = box(role.id .. "PadLabel", x - 0.8, F + 0.31, z - 2.1, x + 0.8, F + 0.32, z + 2.1,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        local lg = surface(label, Enum.NormalId.Top, 40)
        text({ Text = string.upper(role.id), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = col }, lg)
        local pl = light("PointLight", rim, { Color = col, Brightness = 0.6, Range = 9 })
        local hitbox = box(role.id .. "PadTrigger", x - 2.4, F + 0.3, z - 2.4, x + 2.4, F + 5, z + 2.4,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        hitbox:SetAttribute("Role", role.id)

        local sign = box(role.id .. "Sign", X1 - 0.8, F + 4, z - 2.8, X1 - 0.6, F + 9, z + 2.8,
            Color3.fromRGB(16, 18, 24), Enum.Material.SmoothPlastic, f)
        local sg = surface(sign, Enum.NormalId.Left, 60)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, sg)
        frame({ Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = col }, bg)
        text({ Text = string.format("0%d", i), Position = UDim2.fromOffset(22, 26), Size = UDim2.fromOffset(80, 28),
            TextColor3 = T.faint, FontFace = UITheme.F.mono, TextSize = 24 }, bg)
        text({ Text = string.upper(role.id), Position = UDim2.fromOffset(20, 56), Size = UDim2.new(1, -40, 0, 70),
            TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, bg)
        text({ Text = role.blurb, Position = UDim2.fromOffset(22, 130), Size = UDim2.new(1, -44, 0, 50),
            TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 26, TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top }, bg)
        local statusBar = frame({ Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 1, -76), BackgroundColor3 = T.bgRaised }, bg)
        UITheme.corner(statusBar, 10)
        local status = text({ Text = "OPEN", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6),
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.muted, FontFace = UITheme.F.bold, TextScaled = true }, statusBar)
        local cap = Instance.new("UITextSizeConstraint")
        cap.MaxTextSize = 30
        cap.Parent = status
        refs.pads[role.id] = { hitbox = hitbox, rim = rim, light = pl, status = status, statusBar = statusBar, color = col }
    end
    local head = box("CrewSign", X1 - 0.8, F + 11, 12, X1 - 0.6, F + 13.5, 33, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local hg = surface(head, Enum.NormalId.Left, 30)
    hg.Brightness = 2.5
    text({ Text = "PICK YOUR ROLE", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(220, 250, 255),
        TextStrokeColor3 = CYAN, TextStrokeTransparency = 0 }, hg)
    light("PointLight", head, { Brightness = 1.2, Range = 14, Color = CYAN })
end

-- ──────────────────────────────────────────────
-- 😷 MASK WALL (west, south of the bar) → opens the shop
-- ──────────────────────────────────────────────
local ATTACH = {   -- where each accessory attachment sits on a 1.2-stud R15-ish head
    FaceFrontAttachment = CFrame.new(0, 0, -0.6),
    FaceCenterAttachment = CFrame.new(0, 0, 0),
    HatAttachment = CFrame.new(0, 0.6, 0),
    HairAttachment = CFrame.new(0, 0.6, 0),
}

function ClubBuilder:_maskWall(f)
    local wx = X0 + 0.3
    local board = box("MaskBoard", wx, F + 2, 40, wx + 0.3, F + 13, 58, Color3.fromRGB(20, 18, 26), Enum.Material.Fabric, f)
    local title = box("MaskSign", wx + 0.3, F + 13.5, 42, wx + 0.6, F + 16, 56, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local tg = surface(title, Enum.NormalId.Right, 30)
    tg.Brightness = 2.5
    text({ Text = "MASKS & GEAR", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 225, 245),
        TextStrokeColor3 = PINK, TextStrokeTransparency = 0 }, tg)
    light("PointLight", title, { Brightness = 1.2, Range = 14, Color = PINK })

    for i, m in ipairs(Constants.MASKS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local z = 43 + col * 4.2
        local y = F + 9.5 - row * 5
        -- little shelf + display head facing into the room (+X)
        box("MaskShelf", wx + 0.3, y - 1.2, z - 1.2, wx + 2.2, y - 1, z + 1.2, Color3.fromRGB(34, 32, 40), Enum.Material.Metal, f)
        local headPart = part({ Name = "DisplayHead", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2),
            CFrame = CFrame.lookAt(Vector3.new(wx + 1.3, y - 0.4, z), Vector3.new(wx + 10, y - 0.4, z)),
            Color = Color3.fromRGB(58, 56, 66), Material = Enum.Material.SmoothPlastic }, f)
        local plate = box("MaskPlate", wx + 0.3, y - 2.6, z - 1.4, wx + 0.4, y - 1.6, z + 1.4, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
        local pg = surface(plate, Enum.NormalId.Right, 40)
        text({ Text = string.upper(m.name), Size = UDim2.fromScale(1, 0.55), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.text }, pg)
        text({ Text = m.price == 0 and "FREE" or UITheme.money(m.price), Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
            TextColor3 = m.price == 0 and T.money or T.gold }, pg)
        local spot = box("MaskSpot", wx + 3.6, y + 1.8, z - 0.2, wx + 4, y + 2.1, z + 0.2, STEEL, Enum.Material.Metal, f, { CanCollide = false })
        light("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 50, Brightness = 2, Range = 6, Color = Color3.fromRGB(255, 230, 240) })
        -- load the real mask onto the head (async; skipped silently if it won't load)
        task.spawn(function()
            local ok, container = pcall(function() return InsertService:LoadAsset(m.assetId) end)
            local acc = ok and container and container:FindFirstChildWhichIsA("Accessory", true)
            local handle = acc and acc:FindFirstChild("Handle")
            if not handle then return end
            local att = handle:FindFirstChildWhichIsA("Attachment")
            local offset = att and ATTACH[att.Name] or CFrame.new(0, 0, -0.55)
            handle = handle:Clone()
            for _, d in ipairs(handle:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Weld") or d:IsA("WeldConstraint") then d:Destroy() end
            end
            handle.Anchored = true
            handle.CanCollide = false
            local a2 = att and handle:FindFirstChild(att.Name)
            handle.CFrame = headPart.CFrame * offset * (a2 and a2.CFrame:Inverse() or CFrame.new())
            handle.Name = "Mask_" .. m.id
            handle.Parent = f
        end)
    end

    -- shop counter in front of the wall
    local counter = box("ShopCounter", wx + 6, F, 44, wx + 8, F + 3.4, 54, WOOD, Enum.Material.WoodPlanks, f)
    box("ShopCounterTop", wx + 5.8, F + 3.4, 43.8, wx + 8.2, F + 3.7, 54.2, Color3.fromRGB(230, 225, 235), Enum.Material.Marble, f)
    neon("ShopCounterGlow", wx + 8.02, F + 0.3, 44, wx + 8.12, F + 0.45, 54, CYAN, f)
    local p = prompt(counter, "OpenShop", "Open shop", "Masks & gear", Enum.KeyCode.E, 0)
    p.MaxActivationDistance = 11
end

-- ──────────────────────────────────────────────
-- 🏆 TROPHY ROOM (south-east)
-- ──────────────────────────────────────────────
local function trophyVisual(i, cf, parent)
    local fo = Instance.new("Model")
    fo.Name = "Trophy" .. i
    fo.Parent = parent
    local gold = Color3.fromRGB(240, 190, 60)
    if i == 1 then
        part({ Name = "GoldBar", Size = Vector3.new(1.6, 0.6, 0.8), CFrame = cf * CFrame.new(0, 0.3, 0),
            Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 }, fo)
    elseif i == 2 then
        for k = 0, 5 do
            part({ Name = "Cash", Size = Vector3.new(1.2, 0.35, 0.6),
                CFrame = cf * CFrame.new((k % 2) * 0.65 - 0.3, 0.2 + math.floor(k / 2) * 0.36, 0),
                Color = Color3.fromRGB(90, 170, 90), Material = Enum.Material.Fabric }, fo)
        end
    elseif i == 3 then
        part({ Name = "Diamond", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(0, 0.9, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
            Color = Color3.fromRGB(150, 230, 255), Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.4 }, fo)
        local glow = part({ Name = "Core", Size = Vector3.new(0.35, 0.35, 0.35), CFrame = cf * CFrame.new(0, 0.9, 0),
            Color = CYAN, Material = Enum.Material.Neon, CanCollide = false }, fo)
        light("PointLight", glow, { Brightness = 1.5, Range = 6, Color = CYAN })
    elseif i == 4 then
        part({ Name = "Frame", Size = Vector3.new(0.2, 2.2, 2.8), CFrame = cf * CFrame.new(0, 1.3, 0),
            Color = gold, Material = Enum.Material.Metal }, fo)
        local canvas = part({ Name = "Canvas", Size = Vector3.new(0.1, 1.8, 2.4), CFrame = cf * CFrame.new(-0.12, 1.3, 0),
            Color = Color3.fromRGB(40, 60, 110), Material = Enum.Material.Fabric }, fo)
        local g = surface(canvas, Enum.NormalId.Left, 60)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 50, 100) }, g)
        frame({ Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.2), BackgroundColor3 = Color3.fromRGB(240, 180, 60), Rotation = 12 }, bg)
        frame({ Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.55, 0.5), BackgroundColor3 = Color3.fromRGB(230, 80, 120) }, bg)
    else
        task.spawn(function()
            local bear = KenneyLoader.place("furniture", "bear", cf.Position, Vector3.new(-1, 0, 0), { parent = fo, scale = 1.6 })
            if bear then
                for _, d in ipairs(bear:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d:SetAttribute("BaseT", 0)
                        d.Color = gold
                        d.Material = Enum.Material.Metal
                        d.Reflectance = 0.25
                        if d:IsA("MeshPart") then d.TextureID = "" end
                    end
                end
                bear:SetAttribute("Hidden", fo:GetAttribute("Hidden"))
                for _, d in ipairs(bear:GetDescendants()) do
                    if d:IsA("BasePart") and fo:GetAttribute("Hidden") then d.Transparency = 1 end
                end
            end
        end)
    end
    return fo
end

local function setModelVisible(m, visible)
    m:SetAttribute("Hidden", not visible)
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            if d:GetAttribute("BaseT") == nil then d:SetAttribute("BaseT", d.Transparency) end
            d.Transparency = visible and d:GetAttribute("BaseT") or 1
        elseif d:IsA("Light") or d:IsA("SurfaceGui") then
            d.Enabled = visible
        end
    end
end

function ClubBuilder:_trophyRoom(f, refs)
    local rx0, rz0 = 26, 46
    -- partition walls with an opening facing the room
    box("TrophyWallN", rx0, F, rz0 - 0.4, X1, F + 9, rz0, WALL, Enum.Material.Concrete, f)
    box("TrophyWallW", rx0 - 0.4, F, rz0, rx0, F + 9, rz0 + 6, WALL, Enum.Material.Concrete, f)
    box("TrophyFloor", rx0, F, rz0, X1, F + 0.06, Z1, Color3.fromRGB(60, 20, 30), Enum.Material.Fabric, f)
    local sign = box("TrophySign", rx0 + 2, F + 9.2, rz0 - 0.5, X1 - 2, F + 11.6, rz0 - 0.3, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 30)
    sg.Brightness = 2.5
    text({ Text = "TROPHY ROOM", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 240, 200),
        TextStrokeColor3 = Color3.fromRGB(255, 170, 60), TextStrokeTransparency = 0 }, sg)
    light("PointLight", sign, { Brightness = 1.2, Range = 12, Color = Color3.fromRGB(255, 190, 90) })

    refs.trophies = {}
    for i, tr in ipairs(Constants.TROPHIES) do
        local z = rz0 + 3 + (i - 1) * 3.4
        local x = X1 - 3
        box("Pedestal", x - 1.2, F, z - 1.2, x + 1.2, F + 3, z + 1.2, Color3.fromRGB(30, 28, 34), Enum.Material.Marble, f)
        box("CaseGlass", x - 1.15, F + 3, z - 1.15, x + 1.15, F + 5.8, z + 1.15, Color3.fromRGB(200, 220, 255), Enum.Material.Glass, f,
            { Transparency = 0.75, CanCollide = false })
        local plate = box("TrophyPlate", x - 1.25, F + 1.2, z - 1.1, x - 1.2, F + 2.6, z + 1.1, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
        local pg = surface(plate, Enum.NormalId.Left, 50)
        local name = text({ Size = UDim2.fromScale(1, 0.55), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = T.gold }, pg)
        local info = text({ Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.muted }, pg)
        local spot = box("TrophySpot", x - 0.2, F + 8.6, z - 0.2, x + 0.2, F + 8.9, z + 0.2, STEEL, Enum.Material.Metal, f, { CanCollide = false })
        local sl = light("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 40, Brightness = 3, Range = 9, Color = Color3.fromRGB(255, 225, 170) })
        local vis = trophyVisual(i, CFrame.new(x, F + 3, z), f)
        refs.trophies[i] = { at = tr.at, name = tr.name, blurb = tr.blurb, visual = vis, label = name, info = info, light = sl }
    end
    refs.setTrophies = function(best)
        for _, t in ipairs(refs.trophies) do
            local unlocked = best >= t.at
            setModelVisible(t.visual, unlocked)
            t.light.Enabled = unlocked
            t.label.Text = unlocked and t.name or "LOCKED"
            t.info.Text = unlocked and t.blurb or string.format("%d heist%s", t.at, t.at == 1 and "" or "s")
        end
    end
    refs.setTrophies(0)
end

-- ──────────────────────────────────────────────
-- 🚗 GARAGE BAY + RAMP (south-west)
-- ──────────────────────────────────────────────
function ClubBuilder:_garageBay(f, refs)
    local bx0, bx1 = -26, -8                 -- south-centre-west, clear of the mask wall
    local cx = (bx0 + bx1) / 2               -- -17
    box("BayFloor", bx0, F, 44, bx1, F + 0.05, Z1, Color3.fromRGB(60, 60, 64), Enum.Material.Concrete, f)
    for _, x in ipairs({ bx0 + 1, bx1 - 1 }) do
        box("BayLine", x - 0.15, F + 0.05, 44, x + 0.15, F + 0.08, Z1 - 16, Color3.fromRGB(212, 168, 44), Enum.Material.SmoothPlastic, f, { CanCollide = false })
    end
    box("BayWallE", bx1, F, 44, bx1 + 0.5, F + 8, Z1 - 17, WALL, Enum.Material.Concrete, f)
    -- the ramp: from the bay floor (z 48) up to a roll-up door high in the south wall
    local a = Vector3.new(cx, F, Z1 - 16)
    local b = Vector3.new(cx, F + 10, Z1 - 0.5)
    local mid = (a + b) / 2
    local len = (b - a).Magnitude
    part({ Name = "Ramp", Size = Vector3.new(14, 0.8, len), CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -0.4, 0),
        Color = Color3.fromRGB(54, 54, 58), Material = Enum.Material.DiamondPlate }, f)
    for _, sx in ipairs({ -7.2, 7.2 }) do
        part({ Name = "RampRail", Size = Vector3.new(0.3, 1, len), CFrame = CFrame.lookAt(mid + Vector3.new(sx, 0.5, 0), b + Vector3.new(sx, 0.5, 0)),
            Color = Color3.fromRGB(212, 168, 44), Material = Enum.Material.Metal }, f)
    end
    -- roll-up door where the ramp meets the wall (slats)
    for i = 0, 4 do
        box("BayDoorSlat", cx - 8, F + 10 + i * 2, Z1 - 0.6, cx + 8, F + 12 + i * 2, Z1 - 0.2,
            (i % 2 == 0) and Color3.fromRGB(96, 102, 110) or Color3.fromRGB(84, 90, 98), Enum.Material.Metal, f)
    end
    local warn = box("BaySign", cx - 6, F + 20.5, Z1 - 0.6, cx + 6, F + 22.5, Z1 - 0.4, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local wg = surface(warn, Enum.NormalId.Front, 30)
    wg.Brightness = 2
    text({ Text = "GETAWAY BAY", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 220, 120) }, wg)
    for _, x in ipairs({ bx0 + 3, bx1 - 3 }) do
        local l = box("BayLamp", x - 0.5, TOP - 2, 50 - 0.5, x + 0.5, TOP - 1.5, 50 + 0.5, STEEL, Enum.Material.Metal, f)
        light("SpotLight", l, { Face = Enum.NormalId.Bottom, Angle = 90, Brightness = 2.5, Range = 30, Color = Color3.fromRGB(235, 240, 255) })
    end
    KenneyLoader.placeMany({
        { kit = "factory", name = "cone", pos = Vector3.new(bx0 + 2, F, 46), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "cone", pos = Vector3.new(bx1 - 2, F, 46), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-large", pos = Vector3.new(bx0 + 2.5, F, Z1 - 3), facing = Vector3.new(1, 0, 0) },
    }, f)
    -- where the launch cut-scene parks a copy of the getaway car, and where it drives to
    refs.bay = {
        start = CFrame.lookAt(Vector3.new(cx, F, Z1 - 20), Vector3.new(cx, F, Z1)),
        rampFoot = CFrame.lookAt(Vector3.new(cx, F, Z1 - 16), b),
        rampTop = CFrame.lookAt(b - (b - a).Unit * 3, b),
        camFrom = Vector3.new(cx + 16, F + 7, 40),
        camTo = Vector3.new(cx, F + 3, Z1 - 12),
    }
end

-- ──────────────────────────────────────────────
-- 🛗 FREIGHT ELEVATOR (up to the auto shop)
-- ──────────────────────────────────────────────
function ClubBuilder:_elevator(f, refs)
    local e = W.HUB_ELEVATOR
    local x0, x1, z0, z1 = e.x - 4, e.x + 4, Z1 - 7, Z1
    box("LiftFloor", x0, F, z0, x1, F + 0.3, z1, Color3.fromRGB(70, 72, 78), Enum.Material.DiamondPlate, f)
    for _, p in ipairs({ { x0, z0 }, { x1, z0 } }) do
        box("LiftPost", p[1] - 0.25, F, p[2] - 0.25, p[1] + 0.25, F + 10, p[2] + 0.25, Color3.fromRGB(212, 168, 44), Enum.Material.Metal, f)
    end
    box("LiftTop", x0 - 0.25, F + 10, z0 - 0.25, x1 + 0.25, F + 10.5, z1, Color3.fromRGB(212, 168, 44), Enum.Material.Metal, f)
    box("LiftSideW", x0 - 0.1, F + 0.3, z0, x0 + 0.1, F + 10, z1, Color3.fromRGB(80, 80, 88), Enum.Material.DiamondPlate, f, { Transparency = 0.3 })
    box("LiftSideE", x1 - 0.1, F + 0.3, z0, x1 + 0.1, F + 10, z1, Color3.fromRGB(80, 80, 88), Enum.Material.DiamondPlate, f, { Transparency = 0.3 })
    local panel = box("LiftPanel", x1 - 0.6, F + 3.5, z0 + 0.4, x1 - 0.2, F + 5.5, z0 + 1.4, Color3.fromRGB(20, 20, 24), Enum.Material.Metal, f)
    neon("LiftButton", x1 - 0.7, F + 4.3, z0 + 0.7, x1 - 0.6, F + 4.7, z0 + 1.1, Color3.fromRGB(60, 240, 140), f)
    local sign = box("LiftSign", x0 + 0.5, F + 10.6, z0 - 0.3, x1 - 0.5, F + 12.2, z0 - 0.1, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 30)
    sg.Brightness = 2
    text({ Text = "▲ STREET", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(120, 255, 180) }, sg)
    light("PointLight", panel, { Brightness = 1, Range = 10, Color = Color3.fromRGB(120, 255, 180) })
    local p = prompt(panel, "ElevatorUp", "Up to the street", "Freight lift", Enum.KeyCode.E, 0.5)
    p.MaxActivationDistance = 8
    p.Triggered:Connect(function(player) if ClubBuilder.onElevator then ClubBuilder.onElevator(player, "up") end end)
end

-- ──────────────────────────────────────────────
function ClubBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "TheVault"
    f.Parent = folder
    local refs = {}
    local steps = {
        { "shell", function() self:_shell(sub(f, "Shell")) end },
        { "stage", function() self:_stage(sub(f, "Stage")) end },
        { "dance floor", function() self:_danceFloor(sub(f, "DanceFloor")) end },
        { "bar", function() self:_bar(sub(f, "Bar")) end },
        { "holo table", function() self:_holoTable(sub(f, "HoloTable"), refs) end },
        { "crew pads", function() self:_crewPads(sub(f, "CrewPads"), refs) end },
        { "mask wall", function() self:_maskWall(sub(f, "MaskWall")) end },
        { "trophy room", function() self:_trophyRoom(sub(f, "TrophyRoom"), refs) end },
        { "garage bay", function() self:_garageBay(sub(f, "GarageBay"), refs) end },
        { "elevator", function() self:_elevator(sub(f, "Elevator"), refs) end },
    }
    for _, s in ipairs(steps) do
        local ok, err = pcall(s[2])
        if not ok then warn("[ClubBuilder] " .. s[1] .. " failed: " .. tostring(err)) end
    end
    print("[ClubBuilder] The Vault is open 🪩")
    return refs
end

return ClubBuilder
