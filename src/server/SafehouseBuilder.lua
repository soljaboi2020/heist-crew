--[[
    HEIST CREW — SafehouseBuilder
    ────────────────────────────────────────────────
    v0.7.0 (2026-09-25). Replaces the open marble plaza with a place that
    feels like a crew's HQ, and gives the level a real street.

    SAFEHOUSE (x -24..24, z 4..40, 16 tall) — a brick warehouse:
      • roll-up GARAGE DOOR in the north wall — opens by itself when anyone
        walks up to it, closes behind them
      • PLANNING TABLE in the middle with a live blueprint of the mansion job,
        and the Boss standing at it
      • 4 CREW PADS on the west wall — Hacker / Muscle / Driver / Lookout
        (CrewService wires them up)
      • GEAR WALL + workbench on the east wall (shop teaser — shop not built)
      • LOUNGE on the south wall: sofa, rug and a big TV showing the next job,
        the top earners in the server, and the crew roster (CrewService updates it)
      • hanging industrial lamps, skylights, steel columns, roof trusses
      • Kenney props (crates, sofa, laptop, speakers...) via KenneyLoader

    STREET (z -22..-6, runs east-west) between the safehouse and the mansion:
      asphalt, dashed centre line, kerbs, sidewalks, a zebra crossing lined up
      with the garage, streetlights, and a short garden path up to the mansion.

    Everything is Parts + built-in Materials + Kenney meshes. No Neon surfaces
    (art rule #1) — Neon only on bulbs. No floating text (rule #3) — every
    word is printed on a surface.

    PUBLIC API:
        SafehouseBuilder:build(folder) -> refs
            refs.pads[roleId] = { hitbox, rim, light, status, statusBar }
            refs.tv = { jobPayout, leaders = {rows}, crew = {[roleId] = label} }
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local SafehouseBuilder = {}

local W = Constants.WORLD
local T = UITheme.C
local FLOOR = 0.5   -- top of the safehouse floor slab

local CX, CZ = W.SAFEHOUSE_CENTER.x, W.SAFEHOUSE_CENTER.z
local HW, HD, H = W.SAFEHOUSE_HALF_WIDTH, W.SAFEHOUSE_HALF_DEPTH, W.SAFEHOUSE_HEIGHT
local NORTH, SOUTH = CZ - HD, CZ + HD          -- z 4 / z 40
local WEST, EAST = CX - HW, CX + HW            -- x -24 / x 24
local GW, GH = W.GARAGE_WIDTH, W.GARAGE_HEIGHT

-- palette for the building itself
local BRICK      = Color3.fromRGB(116, 64, 48)
local CONCRETE   = Color3.fromRGB(88, 88, 90)
local STEEL      = Color3.fromRGB(44, 47, 54)
local STEEL_LITE = Color3.fromRGB(96, 102, 110)
local WOOD_DARK  = Color3.fromRGB(86, 60, 42)
local WARM_LIGHT = Color3.fromRGB(255, 212, 168)

-- ──────────────────────────────────────────────
-- helpers
-- ──────────────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

-- A box described by its min/max corners — much easier to lay out walls with
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

local function surface(p, face, pps)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 50
    g.LightInfluence = 0
    g.Brightness = 1.2
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

-- Hanging industrial lamp: cable, dark shade, small bulb, spotlight down
local function hangingLamp(parent, x, z, y, brightness, range, color)
    local top = FLOOR + H
    box("LampCable", x - 0.08, y + 0.6, z - 0.08, x + 0.08, top, z + 0.08, STEEL, Enum.Material.Metal, parent,
        { CanCollide = false })
    local shade = part({
        Name = "LampShade", Shape = Enum.PartType.Cylinder,
        Size = Vector3.new(1, 2.8, 2.8), Color = STEEL, Material = Enum.Material.Metal,
        CFrame = CFrame.new(x, y + 0.3, z) * CFrame.Angles(0, 0, math.rad(90)),
        CanCollide = false,
    }, parent)
    part({
        Name = "LampBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7),
        Position = Vector3.new(x, y - 0.25, z), Color = WARM_LIGHT, Material = Enum.Material.Neon,
        CanCollide = false,
    }, parent)
    local light = Instance.new("SpotLight")
    light.Face = Enum.NormalId.Left          -- the cylinder is rotated; Left now points down
    light.Angle = 100
    light.Brightness = brightness or 2.4
    light.Range = range or 24
    light.Color = color or WARM_LIGHT
    light.Shadows = true
    light.Parent = shade
    return shade
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL: floor, walls, roof, garage door
-- ──────────────────────────────────────────────
function SafehouseBuilder:_shell(f)
    local top = FLOOR + H

    -- Floor: sealed concrete, plus a painted safety line around the garage bay
    box("Floor", WEST, -0.5, NORTH, EAST, FLOOR, SOUTH, CONCRETE, Enum.Material.Concrete, f)
    local yellow = Color3.fromRGB(212, 168, 44)
    box("BayLineW", -GW / 2 - 1, FLOOR, NORTH + 0.5, -GW / 2 - 0.6, FLOOR + 0.02, NORTH + 11, yellow, Enum.Material.SmoothPlastic, f, { CanCollide = false })
    box("BayLineE", GW / 2 + 0.6, FLOOR, NORTH + 0.5, GW / 2 + 1, FLOOR + 0.02, NORTH + 11, yellow, Enum.Material.SmoothPlastic, f, { CanCollide = false })

    -- Walls (1 stud thick, centred on the footprint edge)
    box("WallSouth", WEST, FLOOR, SOUTH - 0.5, EAST, top, SOUTH + 0.5, BRICK, Enum.Material.Brick, f)
    box("WallWest", WEST - 0.5, FLOOR, NORTH, WEST + 0.5, top, SOUTH, BRICK, Enum.Material.Brick, f)
    box("WallEast", EAST - 0.5, FLOOR, NORTH, EAST + 0.5, top, SOUTH, BRICK, Enum.Material.Brick, f)
    -- North wall, split around the garage opening
    box("WallNorthW", WEST, FLOOR, NORTH - 0.5, -GW / 2, top, NORTH + 0.5, BRICK, Enum.Material.Brick, f)
    box("WallNorthE", GW / 2, FLOOR, NORTH - 0.5, EAST, top, NORTH + 0.5, BRICK, Enum.Material.Brick, f)
    box("GarageHeader", -GW / 2, FLOOR + GH, NORTH - 0.5, GW / 2, top, NORTH + 0.5, BRICK, Enum.Material.Brick, f)

    -- Concrete wainscot along the inside of the walls (breaks up the brick)
    local ws = 3
    box("WainscotS", WEST + 0.5, FLOOR, SOUTH - 0.6, EAST - 0.5, FLOOR + ws, SOUTH - 0.5, CONCRETE, Enum.Material.Concrete, f)
    box("WainscotW", WEST + 0.5, FLOOR, NORTH + 0.5, WEST + 0.6, FLOOR + ws, SOUTH - 0.5, CONCRETE, Enum.Material.Concrete, f)
    box("WainscotE", EAST - 0.6, FLOOR, NORTH + 0.5, EAST - 0.5, FLOOR + ws, SOUTH - 0.5, CONCRETE, Enum.Material.Concrete, f)

    -- Steel columns. Placed in the gaps between the crew signs (west) and
    -- clear of the gear board (east) so nothing clips through them.
    local cols = {
        { WEST + 1, NORTH + 1 }, { WEST + 1, NORTH + 10.5 }, { WEST + 1, NORTH + 17.5 },
        { WEST + 1, NORTH + 24.5 }, { WEST + 1, SOUTH - 1 },
        { EAST - 1, NORTH + 1 }, { EAST - 1, NORTH + 8 }, { EAST - 1, SOUTH - 6 }, { EAST - 1, SOUTH - 1 },
    }
    for _, c in ipairs(cols) do
        box("Column", c[1] - 0.5, FLOOR, c[2] - 0.5, c[1] + 0.5, top, c[2] + 0.5, STEEL, Enum.Material.Metal, f)
    end

    -- Roof: metal sheet in bands with two glass skylight strips between them
    local bands = {
        { NORTH, NORTH + 10, false }, { NORTH + 10, NORTH + 13, true },
        { NORTH + 13, NORTH + 23, false }, { NORTH + 23, NORTH + 26, true },
        { NORTH + 26, SOUTH, false },
    }
    for i, b in ipairs(bands) do
        if b[3] then
            box("Skylight" .. i, WEST, top, b[1], EAST, top + 0.3, b[2], Color3.fromRGB(150, 180, 200),
                Enum.Material.Glass, f, { Transparency = 0.55 })
        else
            box("Roof" .. i, WEST - 0.5, top, b[1], EAST + 0.5, top + 1, b[2], Color3.fromRGB(64, 66, 72),
                Enum.Material.CorrodedMetal, f)
        end
    end
    -- Trusses under the roof
    for z = NORTH + 5, SOUTH - 3, 9 do
        box("Truss", WEST + 0.5, top - 1.2, z - 0.35, EAST - 0.5, top - 0.5, z + 0.35, STEEL, Enum.Material.Metal, f)
    end

    -- ── Exterior: shop sign over the garage + a wall light on the driveway ──
    local sign = box("ShopSign", -11, FLOOR + GH + 0.6, NORTH - 0.9, 11, FLOOR + GH + 3.4, NORTH - 0.5,
        Color3.fromRGB(26, 28, 34), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 40)
    text({ Text = "RIVERSIDE AUTO BODY", Size = UDim2.fromScale(1, 0.62), Position = UDim2.fromScale(0, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = Color3.fromRGB(236, 226, 206) }, sg)
    text({ Text = "COLLISION  ·  PAINT  ·  NO QUESTIONS", Size = UDim2.fromScale(1, 0.24), Position = UDim2.fromScale(0, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = T.gold }, sg)
    -- a wall light either side of the garage, lighting the driveway
    for _, sx in ipairs({ -1, 1 }) do
        local lx = sx * (GW / 2 + 2)
        local wallLamp = box("WallLamp", lx - 0.6, FLOOR + 9, NORTH - 1.4, lx + 0.6, FLOOR + 9.5, NORTH - 0.5, STEEL, Enum.Material.Metal, f)
        box("WallLampLens", lx - 0.45, FLOOR + 8.9, NORTH - 1.3, lx + 0.45, FLOOR + 9, NORTH - 0.6, WARM_LIGHT, Enum.Material.Neon, f, { CanCollide = false })
        local wl = Instance.new("SpotLight")
        wl.Face = Enum.NormalId.Bottom
        wl.Angle = 120
        wl.Brightness = 1.8
        wl.Range = 18
        wl.Color = WARM_LIGHT
        wl.Shadows = true
        wl.Parent = wallLamp
    end
end

-- Roll-up door: horizontal slats that slide up into the header when anyone
-- is near, and back down when nobody is.
function SafehouseBuilder:_garageDoor(f)
    local door = Instance.new("Folder")
    door.Name = "GarageDoor"
    door.Parent = f
    local slats = {}
    local n = GH / 2
    for i = 1, n do
        local y = FLOOR + (i - 0.5) * 2
        local s = box("Slat" .. i, -GW / 2, y - 1, NORTH - 0.2, GW / 2, y + 1, NORTH + 0.2,
            (i % 2 == 0) and STEEL_LITE or Color3.fromRGB(84, 90, 98), Enum.Material.Metal, door)
        -- open = stacked inside the brick header above the opening (y 12.5-16.5),
        -- so the raised door is hidden in the wall, never poking through the roof
        local openY = FLOOR + GH + 1 + (i - 1) * 0.4
        slats[i] = { part = s, closed = s.CFrame, open = CFrame.new(s.Position.X, openY, s.Position.Z) }
    end
    -- housing on the inside that the slats disappear into
    box("DoorHousing", -GW / 2 - 0.6, FLOOR + GH, NORTH + 0.5, GW / 2 + 0.6, FLOOR + GH + 2, NORTH + 1.8, STEEL, Enum.Material.Metal, f)

    local isOpen = false
    local centre = Vector3.new(0, FLOOR + 3, NORTH)
    task.spawn(function()
        while door.Parent do
            local near = false
            for _, p in ipairs(Players:GetPlayers()) do
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if hrp and (hrp.Position - centre).Magnitude < 17 then near = true break end
            end
            if near ~= isOpen then
                isOpen = near
                for _, s in ipairs(slats) do
                    TweenService:Create(s.part, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                        { CFrame = near and s.open or s.closed }):Play()
                end
            end
            task.wait(0.25)
        end
    end)
end

-- ──────────────────────────────────────────────
-- 🗺 PLANNING TABLE + live blueprint
-- ──────────────────────────────────────────────
function SafehouseBuilder:_planningTable(f, refs)
    local x, z = 0, 18
    local topY = FLOOR + 3.3
    box("TableTop", x - 6, topY - 0.5, z - 3.5, x + 6, topY, z + 3.5, WOOD_DARK, Enum.Material.WoodPlanks, f)
    box("TableApron", x - 5.6, topY - 1.2, z - 3.1, x + 5.6, topY - 0.5, z + 3.1, STEEL, Enum.Material.Metal, f)
    for _, dx in ipairs({ -5.2, 5.2 }) do
        for _, dz in ipairs({ -2.7, 2.7 }) do
            box("TableLeg", x + dx - 0.3, FLOOR, z + dz - 0.3, x + dx + 0.3, topY - 1.2, z + dz + 0.3, STEEL, Enum.Material.Metal, f)
        end
    end

    -- Blueprint sheet. Top-face SurfaceGui: its "up" points north, so it reads
    -- the right way round for someone standing at the spawn looking in.
    local sheet = box("Blueprint", x - 5.4, topY, z - 3, x + 3.2, topY + 0.04, z + 3,
        Color3.fromRGB(20, 54, 96), Enum.Material.SmoothPlastic, f, { CanCollide = false })
    local g = surface(sheet, Enum.NormalId.Top, 60)
    g.LightInfluence = 0.4
    local BLUE, INK = Color3.fromRGB(20, 54, 96), Color3.fromRGB(200, 225, 255)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLUE }, g)
    -- faint grid
    for i = 1, 15 do
        frame({ Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(i / 16, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.88 }, bg)
    end
    for i = 1, 11 do
        frame({ Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 12), BackgroundColor3 = INK, BackgroundTransparency = 0.88 }, bg)
    end
    text({ Text = "JOB 01  —  THE MANSION", Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 30),
        TextColor3 = INK, FontFace = UITheme.F.display, TextSize = 26 }, bg)
    text({ Text = "NORTH SIDE · 2 GUARDS · VAULT ON BACK WALL", Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 18),
        TextColor3 = INK, TextTransparency = 0.3, FontFace = UITheme.F.bold, TextSize = 14 }, bg)
    -- floor plan
    local plan = frame({ Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.08, 0.28), BackgroundTransparency = 1 }, bg)
    UITheme.stroke(plan, INK, 0.1, 3)
    -- front door gap (bottom edge)
    frame({ Size = UDim2.new(0.22, 0, 0, 7), Position = UDim2.new(0.39, 0, 1, -3), BackgroundColor3 = BLUE }, plan)
    text({ Text = "ENTRY", Size = UDim2.new(0.3, 0, 0, 16), Position = UDim2.new(0.35, 0, 1, 6), TextColor3 = INK,
        FontFace = UITheme.F.bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center }, plan)
    -- vault
    local vault = frame({ Size = UDim2.fromScale(0.2, 0.2), Position = UDim2.fromScale(0.4, 0.04), BackgroundColor3 = Color3.fromRGB(220, 60, 60), BackgroundTransparency = 0.2 }, plan)
    UITheme.stroke(vault, Color3.fromRGB(255, 140, 140), 0, 2)
    text({ Text = "VAULT", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextSize = 16, TextColor3 = Color3.new(1, 1, 1) }, vault)
    -- guard routes (dashed)
    for _, yRel in ipairs({ 0.36, 0.7 }) do
        for i = 0, 9 do
            frame({ Size = UDim2.new(0.05, 0, 0, 3), Position = UDim2.fromScale(0.05 + i * 0.095, yRel),
                BackgroundColor3 = Color3.fromRGB(250, 204, 21) }, plan)
        end
    end
    text({ Text = "GUARD ROUTES", Size = UDim2.new(0.5, 0, 0, 14), Position = UDim2.fromScale(0.05, 0.41),
        TextColor3 = Color3.fromRGB(250, 204, 21), FontFace = UITheme.F.bold, TextSize = 12 }, plan)
    -- side notes
    local notes = frame({ Size = UDim2.fromScale(0.24, 0.62), Position = UDim2.fromScale(0.74, 0.28), BackgroundTransparency = 1 }, bg)
    local lines = { "1  CROSS THE STREET", "2  AVOID THE LIGHT", "3  HOLD E ON VAULT", "4  RUN TO THE CAR", "", "PAYOUT", "$3,000 EACH" }
    for i, l in ipairs(lines) do
        text({ Text = l, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, (i - 1) * 24), TextColor3 = (i >= 6) and T.gold or INK,
            FontFace = (i == 7) and UITheme.F.display or UITheme.F.bold, TextSize = (i == 7) and 22 or 14 }, notes)
    end
    -- CONFIDENTIAL stamp
    local stamp = text({ Text = "CONFIDENTIAL", Size = UDim2.fromOffset(220, 40), Position = UDim2.fromScale(0.72, 0.06),
        Rotation = -10, TextColor3 = Color3.fromRGB(239, 68, 68), TextTransparency = 0.15, FontFace = UITheme.F.display,
        TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center }, bg)
    UITheme.stroke(stamp, Color3.fromRGB(239, 68, 68), 0.2, 2)
    UITheme.corner(stamp, 4)

    -- A few things on the table
    local props = {
        { kit = "furniture", name = "laptop", pos = Vector3.new(x + 4.6, topY, z - 1.2), facing = Vector3.new(0, 0, 1) },
        { kit = "furniture", name = "books", pos = Vector3.new(x + 4.6, topY, z + 2), facing = Vector3.new(0, 0, 1) },
    }
    -- Stools around it
    for _, p in ipairs({ { -3, 5 }, { 1, 5 }, { -3, -5 }, { 1, -5 } }) do
        table.insert(props, { kit = "furniture", name = "stoolBar", pos = Vector3.new(x + p[1], FLOOR, z + p[2]), facing = Vector3.new(0, 0, -p[2]) })
    end
    KenneyLoader.placeMany(props, f)

    -- Bright work lamp right over the table so the blueprint pops
    hangingLamp(f, x, z, FLOOR + 11, 3.2, 18, Color3.fromRGB(235, 240, 255))
end

-- ──────────────────────────────────────────────
-- 🎭 CREW PADS (west wall)
-- ──────────────────────────────────────────────
function SafehouseBuilder:_crewPads(f, refs)
    refs.pads = {}
    for i, role in ipairs(Constants.ROLES) do
        local z = NORTH + 7 + (i - 1) * 7
        local x = WEST + 7
        local col = UITheme.rgb(role.color)

        -- pad: coloured rim under a dark steel disc, soft glow from below
        local rim = part({ Name = role.id .. "PadRim", Shape = Enum.PartType.Cylinder,
            Size = Vector3.new(0.24, 5.6, 5.6), Color = col, Material = Enum.Material.SmoothPlastic,
            CFrame = CFrame.new(x, FLOOR + 0.12, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        part({ Name = role.id .. "Pad", Shape = Enum.PartType.Cylinder,
            Size = Vector3.new(0.3, 4.8, 4.8), Color = Color3.fromRGB(30, 32, 38), Material = Enum.Material.DiamondPlate,
            CFrame = CFrame.new(x, FLOOR + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        local label = box(role.id .. "PadLabel", x - 2, FLOOR + 0.31, z - 0.7, x + 2, FLOOR + 0.32, z + 0.7,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        local lg = surface(label, Enum.NormalId.Top, 40)
        text({ Text = string.upper(role.id), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = col }, lg)
        local light = Instance.new("PointLight")
        light.Color = col
        light.Brightness = 0.6
        light.Range = 9
        light.Parent = rim

        -- invisible trigger volume over the pad
        local hitbox = box(role.id .. "PadTrigger", x - 2.4, FLOOR + 0.3, z - 2.4, x + 2.4, FLOOR + 5, z + 2.4,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        hitbox:SetAttribute("Role", role.id)

        -- wall sign
        local sign = box(role.id .. "Sign", WEST + 0.6, FLOOR + 4, z - 2.8, WEST + 0.8, FLOOR + 9, z + 2.8,
            Color3.fromRGB(16, 18, 24), Enum.Material.SmoothPlastic, f)
        local sg = surface(sign, Enum.NormalId.Right, 60)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, sg)
        frame({ Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = col }, bg)
        text({ Text = string.format("0%d", i), Position = UDim2.fromOffset(22, 26), Size = UDim2.fromOffset(80, 28),
            TextColor3 = T.faint, FontFace = UITheme.F.mono, TextSize = 24 }, bg)
        text({ Text = string.upper(role.id), Position = UDim2.fromOffset(20, 56), Size = UDim2.new(1, -40, 0, 70),
            TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, bg)
        text({ Text = role.blurb, Position = UDim2.fromOffset(22, 130), Size = UDim2.new(1, -44, 0, 50),
            TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 26, TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top }, bg)
        local statusBar = frame({ Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 1, -76),
            BackgroundColor3 = T.bgRaised }, bg)
        UITheme.corner(statusBar, 10)
        local status = text({ Text = "OPEN — STEP ON THE PAD", Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.muted, FontFace = UITheme.F.bold, TextSize = 24 }, statusBar)

        refs.pads[role.id] = { hitbox = hitbox, rim = rim, light = light, status = status, statusBar = statusBar, color = col }
    end
end

-- ──────────────────────────────────────────────
-- 🧰 GEAR WALL + workbench (east wall)
-- ──────────────────────────────────────────────
function SafehouseBuilder:_gearWall(f)
    local board = box("Pegboard", EAST - 0.8, FLOOR + 4.2, NORTH + 10, EAST - 0.6, FLOOR + 11, SOUTH - 8,
        Color3.fromRGB(176, 136, 94), Enum.Material.Wood, f)
    local g = surface(board, Enum.NormalId.Left, 30)
    g.LightInfluence = 0.8
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, g)
    text({ Text = "GEAR", Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(300, 50),
        TextColor3 = Color3.fromRGB(30, 22, 16), FontFace = UITheme.F.display, TextSize = 48 }, bg)
    text({ Text = "SHOP OPENS SOON", Position = UDim2.fromOffset(26, 60), Size = UDim2.fromOffset(300, 20),
        TextColor3 = Color3.fromRGB(80, 50, 30), FontFace = UITheme.F.bold, TextSize = 18 }, bg)
    -- tool outlines, like a real shop's shadow board
    local tools = { { "LOCKPICK", 0.05 }, { "EMP", 0.29 }, { "DRILL", 0.53 }, { "THERMAL", 0.77 } }
    for _, t in ipairs(tools) do
        local slot = frame({ Size = UDim2.fromScale(0.19, 0.46), Position = UDim2.fromScale(t[2], 0.42),
            BackgroundColor3 = Color3.fromRGB(40, 28, 20), BackgroundTransparency = 0.82 }, bg)
        UITheme.corner(slot, 8)
        UITheme.stroke(slot, Color3.fromRGB(40, 28, 20), 0.35, 2)
        text({ Text = t[1], Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -30),
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(50, 34, 24),
            FontFace = UITheme.F.bold, TextSize = 16 }, slot)
        text({ Text = "?", Size = UDim2.fromScale(1, 0.7), TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Color3.fromRGB(50, 34, 24), TextTransparency = 0.5, FontFace = UITheme.F.display, TextSize = 60 }, slot)
    end

    -- workbench
    local bx0, bx1 = EAST - 4.2, EAST - 0.8
    local benchY = FLOOR + 3.2
    box("BenchTop", bx0, benchY - 0.4, NORTH + 11, bx1, benchY, SOUTH - 9, WOOD_DARK, Enum.Material.WoodPlanks, f)
    for _, bz in ipairs({ NORTH + 11.5, (NORTH + SOUTH) / 2, SOUTH - 9.5 }) do
        box("BenchLeg", bx0 + 0.3, FLOOR, bz - 0.25, bx0 + 0.8, benchY - 0.4, bz + 0.25, STEEL, Enum.Material.Metal, f)
    end
    local face = Vector3.new(-1, 0, 0)
    KenneyLoader.placeMany({
        { kit = "furniture", name = "computerScreen", pos = Vector3.new(EAST - 2.2, benchY, NORTH + 15), facing = face },
        { kit = "furniture", name = "computerKeyboard", pos = Vector3.new(EAST - 3.3, benchY, NORTH + 15), facing = face },
        { kit = "furniture", name = "radio", pos = Vector3.new(EAST - 2.2, benchY, NORTH + 20), facing = face },
        { kit = "factory", name = "box-small", pos = Vector3.new(EAST - 2.4, benchY, SOUTH - 11), facing = face },
        { kit = "furniture", name = "chairDesk", pos = Vector3.new(EAST - 6, FLOOR, NORTH + 15), facing = Vector3.new(1, 0, 0) },
    }, f)

    -- cool strip light over the bench
    local strip = box("StripLight", EAST - 3, FLOOR + 12, NORTH + 12, EAST - 2.6, FLOOR + 12.2, SOUTH - 10,
        Color3.fromRGB(220, 235, 255), Enum.Material.Neon, f, { CanCollide = false })
    local sl = Instance.new("SurfaceLight")
    sl.Face = Enum.NormalId.Bottom
    sl.Angle = 120
    sl.Brightness = 1.6
    sl.Range = 14
    sl.Color = Color3.fromRGB(215, 230, 255)
    sl.Parent = strip
end

-- ──────────────────────────────────────────────
-- 📺 LOUNGE + TV (south wall)
-- ──────────────────────────────────────────────
function SafehouseBuilder:_lounge(f, refs)
    local tvW, tvH = 18, 10.125
    local tv = box("TV", -tvW / 2, FLOOR + 4.2, SOUTH - 0.9, tvW / 2, FLOOR + 4.2 + tvH, SOUTH - 0.5,
        Color3.fromRGB(8, 9, 12), Enum.Material.Glass, f)
    box("TVBezel", -tvW / 2 - 0.3, FLOOR + 3.9, SOUTH - 0.7, tvW / 2 + 0.3, FLOOR + 4.5 + tvH, SOUTH - 0.5,
        Color3.fromRGB(18, 18, 20), Enum.Material.Metal, f)
    local glow = Instance.new("SurfaceLight")
    glow.Face = Enum.NormalId.Front
    glow.Brightness = 0.9
    glow.Range = 14
    glow.Angle = 90
    glow.Color = Color3.fromRGB(150, 190, 255)
    glow.Parent = tv

    local g = surface(tv, Enum.NormalId.Front, 44)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 18) }, g)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 35
    grad.Color = ColorSequence.new(Color3.fromRGB(40, 48, 72), Color3.fromRGB(12, 14, 20))
    grad.Parent = bg
    UITheme.padding(bg, 28, 22)

    -- left: next job
    local left = frame({ Size = UDim2.fromScale(0.52, 0.72), BackgroundTransparency = 1 }, bg)
    text({ Text = "NEXT JOB", Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.gold, FontFace = UITheme.F.bold, TextSize = 22 }, left)
    text({ Text = "THE MANSION", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 70),
        TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, left)
    text({ Text = "Crack the vault. Get out clean.", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 26),
        TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 24 }, left)
    local stats = { { "DIFFICULTY", "■ ■ □ □ □" }, { "GUARDS", "2" }, { "PAYOUT", "$3,000 each" } }
    for i, s in ipairs(stats) do
        local cell = frame({ Size = UDim2.new(0.31, 0, 0, 74), Position = UDim2.new((i - 1) * 0.345, 0, 0, 150),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, left)
        UITheme.corner(cell, 10)
        text({ Text = s[1], Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), TextColor3 = T.muted,
            FontFace = UITheme.F.bold, TextSize = 15 }, cell)
        text({ Text = s[2], Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 34),
            TextColor3 = (i == 3) and T.money or T.text, FontFace = UITheme.F.display, TextScaled = true }, cell)
    end

    -- right: top earners
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
        local cash = text({ Text = "", Position = UDim2.new(0.6, 0, 0, y), Size = UDim2.new(0.4, 0, 0, 36),
            TextColor3 = T.money, FontFace = UITheme.F.display, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right }, right)
        rows[r] = { rank = rank, name = name, cash = cash }
    end

    -- bottom: crew roster
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

    refs.tv = { rows = rows, crew = crew }

    -- furniture
    local toTV = Vector3.new(0, 0, 1)
    KenneyLoader.placeMany({
        { kit = "furniture", name = "rugRectangle", pos = Vector3.new(0, FLOOR, SOUTH - 5.5), facing = toTV, opts = { collide = false } },
        { kit = "furniture", name = "loungeSofaLong", pos = Vector3.new(0, FLOOR, SOUTH - 8), facing = toTV },
        { kit = "furniture", name = "tableCoffee", pos = Vector3.new(0, FLOOR, SOUTH - 4.8), facing = toTV },
        { kit = "furniture", name = "cabinetTelevision", pos = Vector3.new(0, FLOOR, SOUTH - 1.8), facing = -toTV },
        { kit = "furniture", name = "speaker", pos = Vector3.new(-11.5, FLOOR, SOUTH - 1.8), facing = -toTV },
        { kit = "furniture", name = "speaker", pos = Vector3.new(11.5, FLOOR, SOUTH - 1.8), facing = -toTV },
        { kit = "furniture", name = "lampRoundFloor", pos = Vector3.new(-13.5, FLOOR, SOUTH - 7), facing = toTV },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(13.5, FLOOR, SOUTH - 7), facing = toTV },
        { kit = "furniture", name = "kitchenFridgeSmall", pos = Vector3.new(WEST + 2.5, FLOOR, SOUTH - 2.5), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "trashcan", pos = Vector3.new(EAST - 2.2, FLOOR, SOUTH - 2.2), facing = Vector3.new(-1, 0, 0) },
        { kit = "furniture", name = "coatRackStanding", pos = Vector3.new(WEST + 2.5, FLOOR, SOUTH - 6), facing = Vector3.new(1, 0, 0) },
    }, f)
end

-- ──────────────────────────────────────────────
-- 📦 Clutter + lights
-- ──────────────────────────────────────────────
function SafehouseBuilder:_clutter(f)
    local up = Vector3.new(0, 1.964, 0)
    local base = FLOOR
    KenneyLoader.placeMany({
        -- crate stacks either side of the garage bay
        { kit = "factory", name = "box-large", pos = Vector3.new(EAST - 3, base, NORTH + 3), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-large", pos = Vector3.new(EAST - 7.2, base, NORTH + 3), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-long", pos = Vector3.new(EAST - 3, base + up.Y, NORTH + 3), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-wide", pos = Vector3.new(GW / 2 + 2.5, base, NORTH + 3), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-large", pos = Vector3.new(WEST + 3, base, NORTH + 2.8), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-small", pos = Vector3.new(WEST + 3, base + up.Y, NORTH + 2.8), facing = Vector3.new(0, 0, 1) },
        { kit = "furniture", name = "cardboardBoxClosed", pos = Vector3.new(-GW / 2 - 2.5, base, NORTH + 2.5), facing = Vector3.new(0, 0, 1) },
        { kit = "furniture", name = "cardboardBoxOpen", pos = Vector3.new(-GW / 2 - 2.8, base, NORTH + 5.2), facing = Vector3.new(1, 0, 0) },
        -- traffic cones marking the bay
        { kit = "factory", name = "cone", pos = Vector3.new(-GW / 2 + 1, base, NORTH + 7), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "cone", pos = Vector3.new(GW / 2 - 1, base, NORTH + 7), facing = Vector3.new(0, 0, 1) },
    }, f)

    for _, p in ipairs({ { -12, NORTH + 8 }, { 12, NORTH + 8 }, { -12, SOUTH - 10 }, { 12, SOUTH - 10 } }) do
        hangingLamp(f, p[1], p[2], FLOOR + 11.5, 2.4, 24)
    end
    -- soft fill so the corners aren't pitch black
    local fill = box("Fill", -0.5, FLOOR + H - 2, CZ - 0.5, 0.5, FLOOR + H - 1.5, CZ + 0.5, STEEL, Enum.Material.Metal, f,
        { Transparency = 1, CanCollide = false })
    local pl = Instance.new("PointLight")
    pl.Brightness = 0.45
    pl.Range = 40
    pl.Color = Color3.fromRGB(190, 200, 225)
    pl.Parent = fill
end

-- ──────────────────────────────────────────────
-- 🛣 STREET + mansion front path
-- ──────────────────────────────────────────────
function SafehouseBuilder:buildStreet(f)
    local zc, hw = W.STREET_Z, W.STREET_HALF_WIDTH
    local L = 240
    local asphalt = Color3.fromRGB(46, 48, 52)
    local paint = Color3.fromRGB(226, 224, 214)
    local walk = Color3.fromRGB(150, 150, 148)

    box("Asphalt", -L / 2, -0.2, zc - hw, L / 2, 0.2, zc + hw, asphalt, Enum.Material.Asphalt, f)
    for x = -L / 2 + 4, L / 2 - 4, 10 do
        if math.abs(x) > 6 then
            box("CentreDash", x - 2, 0.2, zc - 0.18, x + 2, 0.23, zc + 0.18, Color3.fromRGB(230, 190, 60), Enum.Material.SmoothPlastic, f, { CanCollide = false })
        end
    end
    -- zebra crossing lined up with the garage door
    for z = zc - hw + 1, zc + hw - 1.5, 2 do
        box("Zebra", -5, 0.2, z, 5, 0.23, z + 1, paint, Enum.Material.SmoothPlastic, f, { CanCollide = false })
    end
    -- kerbs + sidewalks
    for _, side in ipairs({ -1, 1 }) do
        local edge = zc + side * hw
        box("Kerb", -L / 2, 0, math.min(edge, edge + side * 0.6), L / 2, 0.55, math.max(edge, edge + side * 0.6),
            Color3.fromRGB(175, 175, 172), Enum.Material.Concrete, f)
        local w0, w1 = edge + side * 0.6, edge + side * 4.6
        box("Sidewalk", -L / 2, 0, math.min(w0, w1), L / 2, 0.5, math.max(w0, w1), walk, Enum.Material.Concrete, f)
    end
    -- driveway from the south sidewalk up to the garage
    local south = zc + hw + 4.6
    box("Driveway", -GW / 2 - 1, 0, south, GW / 2 + 1, 0.5, NORTH - 0.5, Color3.fromRGB(120, 120, 118), Enum.Material.Concrete, f)

    -- streetlights along both sidewalks
    for x = -84, 84, 28 do
        if x ~= 0 then
            for _, side in ipairs({ -1, 1 }) do
                local z = zc + side * (hw + 3.8)
                box("LightPole", x - 0.25, 0.5, z - 0.25, x + 0.25, 12, z + 0.25, STEEL, Enum.Material.Metal, f)
                local armEnd = z - side * 3
                box("LightArm", x - 0.15, 11.6, math.min(z, armEnd), x + 0.15, 11.9, math.max(z, armEnd), STEEL, Enum.Material.Metal, f)
                local head = box("LightHead", x - 0.5, 11.3, armEnd - 0.9, x + 0.5, 11.8, armEnd + 0.9, STEEL, Enum.Material.Metal, f)
                box("LightLens", x - 0.35, 11.2, armEnd - 0.7, x + 0.35, 11.3, armEnd + 0.7, WARM_LIGHT, Enum.Material.Neon, f, { CanCollide = false })
                local sp = Instance.new("SpotLight")
                sp.Face = Enum.NormalId.Bottom
                sp.Angle = 115
                sp.Brightness = 2.2
                sp.Range = 22
                sp.Color = Color3.fromRGB(255, 200, 140)
                sp.Shadows = true
                sp.Parent = head
            end
        end
    end

    -- mansion front garden: path from the north sidewalk to the front door, hedges each side
    local pathZ0 = zc - hw - 4.6
    local doorZ = W.MANSION_CENTER.z + W.MANSION_HALF_DEPTH
    box("FrontPath", -4, 0, doorZ, 4, 0.45, pathZ0, Color3.fromRGB(170, 164, 152), Enum.Material.Slate, f)
    for _, sx in ipairs({ -1, 1 }) do
        box("Hedge", sx * 5, 0, doorZ + 1, sx * 6.4, 2, pathZ0 - 0.5, Color3.fromRGB(44, 88, 48), Enum.Material.Grass, f)
    end
end

-- ──────────────────────────────────────────────
function SafehouseBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "Safehouse"
    f.Parent = folder
    local refs = {}

    self:_shell(f)
    self:_garageDoor(f)
    self:_planningTable(f, refs)
    self:_crewPads(f, refs)
    self:_gearWall(f)
    self:_lounge(f, refs)
    self:_clutter(f)

    local street = Instance.new("Folder")
    street.Name = "Street"
    street.Parent = folder
    self:buildStreet(street)

    print("[SafehouseBuilder] Safehouse + street built 🏚")
    return refs
end

return SafehouseBuilder
