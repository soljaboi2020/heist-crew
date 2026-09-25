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

    ⚠ Since v1.2 most of the list above lives in The Vault (ClubBuilder); the
    old functions are kept but not called. v2.0: the shop is dressed as the
    crew's COVER BUSINESS — a real-looking "Riverside Auto Body" (_autoShop):
    car on a 2-post lift, car with its hood up, tool wall, tyre rack, oil
    drums, service desk + price board + OPEN sign, waiting area — with the
    freight lift down to The Vault in the middle.

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

    -- v1.0: the exterior sign + wall lamps are built by MiamiBuilder:skinSafehouse()
    -- (neon Miami version) — nothing here any more.
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
    -- v1.0: title, floor plan and notes are drawn per job by SafehouseBuilder:showJob()
    local title = text({ Text = "", Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 30),
        TextColor3 = INK, FontFace = UITheme.F.display, TextSize = 26 }, bg)
    local sub = text({ Text = "", Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 18),
        TextColor3 = INK, TextTransparency = 0.3, FontFace = UITheme.F.bold, TextSize = 14 }, bg)
    local plan = frame({ Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.08, 0.28), BackgroundTransparency = 1 }, bg)
    local notes = frame({ Size = UDim2.fromScale(0.24, 0.62), Position = UDim2.fromScale(0.74, 0.28), BackgroundTransparency = 1 }, bg)
    refs.blueprint = { title = title, sub = sub, plan = plan, notes = notes, ink = INK, paper = BLUE }
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

    -- v1.0: change the job from the table
    local tableTop = f:FindFirstChild("TableTop")
    if tableTop then
        local p = Instance.new("ProximityPrompt")
        p.Name = "NextJob"
        p.ActionText = "Change job"
        p.ObjectText = "Planning table"
        p.HoldDuration = 0.4
        p.MaxActivationDistance = 9
        p.RequiresLineOfSight = false
        p.Parent = tableTop
        p.KeyboardKeyCode = Enum.KeyCode.R
        p.GamepadKeyCode = Enum.KeyCode.ButtonY
        p.Triggered:Connect(function(player)
            if SafehouseBuilder.onNextJob then SafehouseBuilder.onNextJob(player) end
        end)
        -- v1.1: ready up for the drop-in (everyone ready → countdown → launch)
        local r = Instance.new("ProximityPrompt")
        r.Name = "ReadyUp"
        r.ActionText = "Ready up"
        r.ObjectText = "Planning table"
        r.HoldDuration = 0.3
        r.MaxActivationDistance = 9
        r.RequiresLineOfSight = false
        r.Parent = tableTop
        r.Triggered:Connect(function(player)
            if SafehouseBuilder.onReadyUp then SafehouseBuilder.onReadyUp(player) end
        end)
    end

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
        -- Top-face text runs along world Z here (seen in Malachi's screenshot),
        -- so the long side of the label goes on Z — it was squeezed into 1.4 studs.
        local label = box(role.id .. "PadLabel", x - 0.8, FLOOR + 0.31, z - 2.1, x + 0.8, FLOOR + 0.32, z + 2.1,
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
        local status = text({ Text = "OPEN", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6),
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.muted, FontFace = UITheme.F.bold, TextScaled = true }, statusBar)
        local cap = Instance.new("UITextSizeConstraint")
        cap.MaxTextSize = 30
        cap.Parent = status

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
    text({ Text = "OPEN  ·  PRESS E", Position = UDim2.fromOffset(26, 60), Size = UDim2.fromOffset(300, 20),
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

    -- v1.0: the shop opens from here (client ShopUI listens for this prompt)
    local sp = Instance.new("ProximityPrompt")
    sp.Name = "OpenShop"
    sp.ActionText = "Open shop"
    sp.ObjectText = "Gear wall"
    sp.MaxActivationDistance = 10
    sp.RequiresLineOfSight = false
    sp.Parent = board

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
    local jobName = text({ Text = "", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 70),
        TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, left)
    local jobTag = text({ Text = "", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 26),
        TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 24 }, left)
    local statCells = {}
    local stats = { { "DIFFICULTY", "" }, { "GUARDS", "" }, { "TAKE", "" } }
    for i, s in ipairs(stats) do
        local cell = frame({ Size = UDim2.new(0.31, 0, 0, 74), Position = UDim2.new((i - 1) * 0.345, 0, 0, 150),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, left)
        UITheme.corner(cell, 10)
        text({ Text = s[1], Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), TextColor3 = T.muted,
            FontFace = UITheme.F.bold, TextSize = 15 }, cell)
        statCells[i] = text({ Text = s[2], Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 34),
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

    refs.tv = { rows = rows, crew = crew, jobName = jobName, jobTag = jobTag, stats = statCells }

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
                -- (perf v1.1) 12 shadowed street lamps was too heavy on phones.
                -- (v2.0.2) Future lighting: shadows back on 4 KEY lamps only —
                -- across from the auto shop (x ±28, north side) and in front of
                -- Diamond Dolls / Sunny's Mart (x ∓56, south side).
                sp.Shadows = (side == -1 and math.abs(x) == 28) or (side == 1 and math.abs(x) == 56)
                sp.Parent = head
            end
        end
    end

    -- mansion front garden: path from the north sidewalk to the front door, hedges each side
    local pathZ0 = zc - hw - 4.6
    -- v2.0 check: the villa's front face is MANSION_CENTER.z + MANSION_HALF_DEPTH
    -- = -67 + 29 = -38 (docs/V2_SPEC.md §1: "Front door x 0 at z -38"), so this path
    -- runs z -38 → -26.6 — exactly the villa's front garden. VillaBuilder relies on
    -- this path (x -4..4) + hedges (x ±5..6.4) and keeps them clear. Falls back to
    -- -38 if the constants ever go missing.
    local doorZ = (W.MANSION_CENTER and W.MANSION_HALF_DEPTH) and (W.MANSION_CENTER.z + W.MANSION_HALF_DEPTH) or -38
    box("FrontPath", -4, 0, doorZ, 4, 0.45, pathZ0, Color3.fromRGB(170, 164, 152), Enum.Material.Slate, f)
    for _, sx in ipairs({ -1, 1 }) do
        box("Hedge", sx * 5, 0, doorZ + 1, sx * 6.4, 2, pathZ0 - 0.5, Color3.fromRGB(44, 88, 48), Enum.Material.Grass, f)
    end
end

-- ──────────────────────────────────────────────
-- 🗺 v1.0: redraw the blueprint + TV for the selected job
-- ──────────────────────────────────────────────
local NOTES = {
    villa = { "1  CUT THE CAMERAS", "2  FIND THE KEYCARD", "3  TIME THE LASERS", "4  DRILL THE VAULT",
              "5  LOAD THE CAR", "6  GO! PICK YOUR ESCAPE" },
    jewelry = { "1  SMASH THE CASES", "2  SILENT ALARM — MOVE", "3  BACK-ROOM KEYCARD", "4  DRILL THE SAFE",
                "5  LOAD THE CAR", "6  GO! PICK YOUR ESCAPE" },
}

function SafehouseBuilder:showJob(refs, cfg, jobRefs)
    local bp = refs and refs.blueprint
    if bp then
        local idx = 1
        for i, j in ipairs(Constants.JOBS) do if j.id == cfg.id then idx = i end end
        bp.title.Text = string.format("JOB 0%d  —  %s", idx, cfg.name)
        bp.sub.Text = string.upper(cfg.tagline)
        bp.plan:ClearAllChildren()
        bp.notes:ClearAllChildren()
        local INK, PAPER = bp.ink, bp.paper
        local pl = jobRefs.plan
        if pl and pl.bounds then
            local x0, z0, x1, z1 = pl.bounds[1], pl.bounds[2], pl.bounds[3], pl.bounds[4]
            local function rel(x, z) return (x - x0) / (x1 - x0), (z - z0) / (z1 - z0) end
            UITheme.stroke(bp.plan, INK, 0.1, 3)
            for _, r in ipairs(pl.rooms or {}) do
                local ax, az = rel(math.min(r[1], r[3]), math.min(r[2], r[4]))
                local bx, bz = rel(math.max(r[1], r[3]), math.max(r[2], r[4]))
                local room = frame({ Position = UDim2.fromScale(ax, az), Size = UDim2.fromScale(bx - ax, bz - az),
                    BackgroundTransparency = 1 }, bp.plan)
                UITheme.stroke(room, INK, 0.35, 1)
                text({ Text = r[5] or "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
                    TextColor3 = INK, TextTransparency = 0.25, FontFace = UITheme.F.bold, TextScaled = true }, room)
            end
            for _, route in ipairs(jobRefs.guardRoutes or {}) do
                if route.a and route.b then
                    for k = 0, 8 do
                        local pnt = route.a:Lerp(route.b, k / 8)
                        local rx, rz = rel(pnt.X, pnt.Z)
                        frame({ Position = UDim2.fromScale(rx, rz), Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0.5, 0.5),
                            BackgroundColor3 = Color3.fromRGB(250, 204, 21) }, bp.plan)
                    end
                end
            end
            if pl.vault then
                local vx, vz = rel(pl.vault[1], pl.vault[2])
                local v = frame({ Position = UDim2.fromScale(vx, vz), Size = UDim2.fromOffset(60, 30), AnchorPoint = Vector2.new(0.5, 0.5),
                    BackgroundColor3 = Color3.fromRGB(220, 60, 60), BackgroundTransparency = 0.15 }, bp.plan)
                UITheme.corner(v, 4)
                text({ Text = cfg.id == "jewelry" and "SAFE" or "VAULT", Size = UDim2.fromScale(1, 1),
                    TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 15,
                    TextColor3 = Color3.new(1, 1, 1) }, v)
            end
            if pl.entry then
                local ex, ez = rel(pl.entry[1], pl.entry[2])
                frame({ Position = UDim2.fromScale(ex, ez), Size = UDim2.fromOffset(44, 7), AnchorPoint = Vector2.new(0.5, 0.5),
                    BackgroundColor3 = PAPER }, bp.plan)
                text({ Text = "ENTRY", Position = UDim2.new(ex, -30, ez, 6), Size = UDim2.fromOffset(60, 14),
                    TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = INK, FontFace = UITheme.F.bold, TextSize = 12 }, bp.plan)
            end
        end
        for i, l in ipairs(NOTES[cfg.id] or {}) do
            text({ Text = l, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, (i - 1) * 24), TextColor3 = INK,
                FontFace = UITheme.F.bold, TextSize = 14 }, bp.notes)
        end
    end

    local tv = refs and refs.tv
    if tv then
        tv.jobName.Text = cfg.name
        tv.jobTag.Text = cfg.tagline
        local d = cfg.difficulty or 1
        tv.stats[1].Text = string.rep("■ ", d) .. string.rep("□ ", 5 - d)
        tv.stats[2].Text = tostring(#(jobRefs.guardRoutes or {}))
        local take = 0
        for _, sp in ipairs(jobRefs.lootSpots or {}) do take = take + ((Constants.LOOT[sp.kind] or {}).value or 0) end
        for _, c in ipairs(jobRefs.smashCases or {}) do take = take + ((Constants.LOOT[c.kind or "Jewels"] or {}).value or 0) end
        tv.stats[3].Text = "up to " .. UITheme.money(take)
    end
end

-- ──────────────────────────────────────────────
-- 🔧 v2.0: dress the auto shop as a REAL business (it's the crew's cover).
-- Car up on a 2-post lift (west bay), a car with its hood up (east bay), tool
-- chests + workbench + pegboard, a tyre rack, oil drums, a service desk with
-- a price board, a waiting area and an OPEN sign. The freight lift in the
-- middle stays clear (x -4..4, z 18..26) and so does the lane to it from the
-- garage door (x -9..9).
-- ──────────────────────────────────────────────
local function wheel(parent, x, y, z)
    part({ Name = "Tyre", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.2, 2.2),
        CFrame = CFrame.new(x, y, z), Color = Color3.fromRGB(24, 24, 26), Material = Enum.Material.Fabric }, parent)
    part({ Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.95, 1.2, 1.2),
        CFrame = CFrame.new(x, y, z), Color = Color3.fromRGB(170, 172, 178), Material = Enum.Material.Metal }, parent)
end

-- a simple saloon car (nose north), wheels resting at `baseY`
local function car(parent, cx, cz, baseY, color, hoodUp)
    local m = Instance.new("Model")
    m.Name = "CustomerCar"
    m.Parent = parent
    local b0 = baseY + 0.6
    box("Body", cx - 2.8, b0, cz - 5.5, cx + 2.8, b0 + 1.8, cz + 5.5, color, Enum.Material.Metal, m, { Reflectance = 0.12 })
    box("Cabin", cx - 2.4, b0 + 1.8, cz - 1.8, cx + 2.4, b0 + 3.4, cz + 3.2, color, Enum.Material.Metal, m)
    box("Windshield", cx - 2.2, b0 + 1.9, cz - 1.95, cx + 2.2, b0 + 3.2, cz - 1.8, Color3.fromRGB(120, 150, 170), Enum.Material.Glass, m, { Transparency = 0.35 })
    box("RearGlass", cx - 2.2, b0 + 1.9, cz + 3.2, cx + 2.2, b0 + 3.2, cz + 3.35, Color3.fromRGB(120, 150, 170), Enum.Material.Glass, m, { Transparency = 0.35 })
    for _, sx in ipairs({ -1, 1 }) do
        box("SideGlass", cx + sx * 2.4, b0 + 1.95, cz - 1.6, cx + sx * 2.45, b0 + 3.2, cz + 3, Color3.fromRGB(120, 150, 170), Enum.Material.Glass, m, { Transparency = 0.35 })
        box("Headlight", cx + sx * 1.6 - 0.5, b0 + 0.9, cz - 5.55, cx + sx * 1.6 + 0.5, b0 + 1.3, cz - 5.5, Color3.fromRGB(240, 240, 230), Enum.Material.Glass, m)
        box("Taillight", cx + sx * 1.8 - 0.5, b0 + 0.9, cz + 5.5, cx + sx * 1.8 + 0.5, b0 + 1.3, cz + 5.55, Color3.fromRGB(200, 30, 30), Enum.Material.Glass, m)
        for _, wz in ipairs({ cz - 3.4, cz + 3.4 }) do wheel(m, cx + sx * 2.5, baseY + 1.1, wz) end
    end
    box("Bumper", cx - 2.9, b0 + 0.2, cz - 5.8, cx + 2.9, b0 + 0.7, cz - 5.5, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, m)
    box("BumperRear", cx - 2.9, b0 + 0.2, cz + 5.5, cx + 2.9, b0 + 0.7, cz + 5.8, Color3.fromRGB(40, 40, 44), Enum.Material.Metal, m)
    if hoodUp then
        box("Engine", cx - 2, b0 + 1, cz - 5.2, cx + 2, b0 + 1.8, cz - 2.4, Color3.fromRGB(50, 52, 58), Enum.Material.Metal, m)
        -- hood hinged at the windshield, propped open ~60°
        local hinge = CFrame.new(cx, b0 + 1.8, cz - 1.9)
        part({ Name = "Hood", Size = Vector3.new(5.4, 0.15, 3.6), Color = color, Material = Enum.Material.Metal,
            CFrame = hinge * CFrame.Angles(math.rad(-60), 0, 0) * CFrame.new(0, 0, -1.8) }, m)
    else
        box("Hood", cx - 2.7, b0 + 1.8, cz - 5.4, cx + 2.7, b0 + 1.9, cz - 1.8, color, Enum.Material.Metal, m)
    end
    return m
end

function SafehouseBuilder:_autoShop(f)
    local yellow = Color3.fromRGB(212, 168, 44)
    local red = Color3.fromRGB(176, 36, 36)
    local paint = function(name, x0, z0, x1, z1)
        box(name, x0, FLOOR, z0, x1, FLOOR + 0.02, z1, yellow, Enum.Material.SmoothPlastic, f, { CanCollide = false })
    end
    -- bay outlines on the floor
    for _, bx in ipairs({ { -21, -9 }, { 9, 21 } }) do
        paint("BayLine", bx[1], 13, bx[1] + 0.3, 30)
        paint("BayLine", bx[2] - 0.3, 13, bx[2], 30)
        paint("BayLine", bx[1], 29.7, bx[2], 30)
    end
    -- oil stains
    for _, s in ipairs({ { -15, 20, 2.4 }, { 15, 24, 1.8 }, { -4, 12, 1.4 } }) do
        part({ Name = "OilStain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, s[3] * 2, s[3] * 2),
            CFrame = CFrame.new(s[1], FLOOR + 0.01, s[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(30, 30, 30), Material = Enum.Material.SmoothPlastic, Transparency = 0.55,
            CanCollide = false }, f)
    end

    -- WEST BAY: 2-post lift with a car up on it
    local lx, lz = -15, 22
    for _, px in ipairs({ -20.4, -9.6 }) do
        box("LiftColumn", px - 0.4, FLOOR, lz - 0.6, px + 0.4, 12.2, lz + 0.6, red, Enum.Material.Metal, f)
        box("LiftColumnBase", px - 0.9, FLOOR, lz - 1, px + 0.9, FLOOR + 0.3, lz + 1, STEEL, Enum.Material.Metal, f)
        for _, dz in ipairs({ -3.2, 3.2 }) do
            local ax = (px < lx) and px + 0.4 or px - 0.4
            box("LiftArm", math.min(ax, lx + (px < lx and -1.6 or 1.6)), 5.6, lz + dz - 0.25,
                math.max(ax, lx + (px < lx and -1.6 or 1.6)), 5.9, lz + dz + 0.25, STEEL, Enum.Material.Metal, f)
        end
    end
    box("LiftBeam", -20.8, 12.2, lz - 0.4, -9.2, 12.8, lz + 0.4, red, Enum.Material.Metal, f)
    car(f, lx, lz, 5.9 - 0.6, Color3.fromRGB(40, 90, 160), false)
    KenneyLoader.placeMany({
        { kit = "factory", name = "cone", pos = Vector3.new(-20, FLOOR, 29), facing = Vector3.new(0, 0, -1) },
    }, f)
    -- drain pan under it
    box("DrainPan", -16, FLOOR, 21, -14, FLOOR + 0.3, 23, Color3.fromRGB(30, 30, 34), Enum.Material.Metal, f)

    -- EAST BAY: car on the floor, hood up, work light
    car(f, 15, 22, FLOOR, Color3.fromRGB(200, 60, 60), true)
    box("WorkLight", 11, FLOOR, 15.4, 11.3, FLOOR + 5, 15.7, STEEL, Enum.Material.Metal, f)
    local head = box("WorkLightHead", 10.7, FLOOR + 5, 15.2, 11.6, FLOOR + 5.8, 15.9, Color3.fromRGB(230, 200, 60), Enum.Material.Metal, f)
    local sl = Instance.new("SpotLight")
    sl.Face = Enum.NormalId.Right
    sl.Angle = 70
    sl.Brightness = 1.6
    sl.Range = 14
    sl.Color = Color3.fromRGB(255, 240, 210)
    sl.Shadows = false
    sl.Parent = head

    -- WEST WALL: workbench, pegboard with tools, red tool chests
    box("Workbench", WEST + 0.6, FLOOR + 3.2, 30.5, WEST + 3.4, FLOOR + 3.6, 37.5, WOOD_DARK, Enum.Material.WoodPlanks, f)
    for _, z in ipairs({ 30.8, 37.2 }) do
        box("BenchLeg", WEST + 2.8, FLOOR, z - 0.2, WEST + 3.2, FLOOR + 3.2, z + 0.2, STEEL, Enum.Material.Metal, f)
    end
    box("Vise", WEST + 2.2, FLOOR + 3.6, 36, WEST + 3.2, FLOOR + 4.4, 36.8, Color3.fromRGB(60, 90, 140), Enum.Material.Metal, f)
    box("Pegboard", WEST + 0.5, FLOOR + 4.4, 30.5, WEST + 0.65, FLOOR + 8.6, 37.5, Color3.fromRGB(150, 118, 84), Enum.Material.Wood, f)
    local tools = {
        { 31.4, 6.8, 0.25, 2.2 }, { 32.3, 7.0, 0.25, 1.8 }, { 33.2, 6.6, 0.3, 2.6 }, { 34.4, 7.2, 0.5, 1.2 },
        { 35.4, 6.9, 0.25, 2.0 }, { 36.4, 7.1, 0.35, 1.6 },
    }
    for _, t in ipairs(tools) do
        box("Tool", WEST + 0.65, FLOOR + t[2] - t[4] / 2, t[1] - t[3] / 2, WEST + 0.8, FLOOR + t[2] + t[4] / 2, t[1] + t[3] / 2,
            Color3.fromRGB(70, 72, 80), Enum.Material.Metal, f, { CanCollide = false })
    end
    for _, z in ipairs({ 23.6, 25.9 }) do
        box("ToolChest", WEST + 0.6, FLOOR, z - 1.1, WEST + 2.6, FLOOR + 4, z + 1.1, red, Enum.Material.Metal, f)
        for k = 1, 4 do
            local y = FLOOR + k * 0.9
            box("Drawer", WEST + 2.6, y - 0.05, z - 0.9, WEST + 2.65, y + 0.05, z + 0.9, Color3.fromRGB(200, 200, 205), Enum.Material.Metal, f, { CanCollide = false })
        end
    end

    -- EAST WALL: tyre rack
    for _, y in ipairs({ FLOOR + 0.3, FLOOR + 3.1 }) do
        box("RackShelf", EAST - 3, y, 15.5, EAST - 0.6, y + 0.2, 30.5, STEEL, Enum.Material.Metal, f)
        for z = 16.3, 29.8, 1.05 do
            part({ Name = "RackTyre", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.4, 2.4),
                CFrame = CFrame.new(EAST - 1.8, y + 1.4, z) * CFrame.Angles(0, math.rad(90), 0),
                Color = Color3.fromRGB(26, 26, 28), Material = Enum.Material.Fabric }, f)
        end
    end
    for _, z in ipairs({ 15.5, 30.5 }) do
        box("RackPost", EAST - 3, FLOOR, z - 0.1, EAST - 2.8, FLOOR + 6, z + 0.1, STEEL, Enum.Material.Metal, f)
    end
    -- oil drums by the tyre rack
    for i, p in ipairs({ { EAST - 2, 32 }, { EAST - 4.4, 31.8 } }) do
        part({ Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 2, 2),
            CFrame = CFrame.new(p[1], FLOOR + 1.5, p[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = (i == 1) and Color3.fromRGB(30, 80, 150) or Color3.fromRGB(170, 40, 40), Material = Enum.Material.Metal }, f)
    end

    -- SERVICE DESK (south-east): counter, computer, price board, OPEN sign
    box("DeskCounter", 10, FLOOR, 33.5, 20, FLOOR + 3.6, 35, Color3.fromRGB(230, 226, 218), Enum.Material.Plaster, f)
    box("DeskCounterTop", 9.8, FLOOR + 3.6, 33.3, 20.2, FLOOR + 3.9, 35.2, WOOD_DARK, Enum.Material.WoodPlanks, f)
    box("DeskStripe", 10, FLOOR + 2.4, 33.45, 20, FLOOR + 2.8, 33.5, Color3.fromRGB(242, 160, 190), Enum.Material.SmoothPlastic, f)
    KenneyLoader.placeMany({
        { kit = "furniture", name = "computerScreen", pos = Vector3.new(16, FLOOR + 3.9, 34.4), facing = Vector3.new(0, 0, 1) },
        { kit = "furniture", name = "chairDesk", pos = Vector3.new(15, FLOOR, 37), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "radio", pos = Vector3.new(11.5, FLOOR + 3.9, 34.3), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(EAST - 3, FLOOR, SOUTH - 1.6), facing = Vector3.new(-1, 0, 0) },
        -- waiting area (south-west of the lift)
        { kit = "furniture", name = "benchCushion", pos = Vector3.new(-12, FLOOR, SOUTH - 1.8), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "benchCushion", pos = Vector3.new(-6, FLOOR, SOUTH - 1.8), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "tableCoffee", pos = Vector3.new(-9, FLOOR, SOUTH - 5), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "kitchenCoffeeMachine", pos = Vector3.new(-16.5, FLOOR + 3.3, SOUTH - 1.4), facing = Vector3.new(0, 0, -1) },
        { kit = "furniture", name = "trashcan", pos = Vector3.new(-2.5, FLOOR, SOUTH - 1.5), facing = Vector3.new(0, 0, -1) },
    }, f)
    box("CoffeeStand", -18, FLOOR, SOUTH - 2.2, -15, FLOOR + 3.3, SOUTH - 0.6, WOOD_DARK, Enum.Material.WoodPlanks, f)

    local board = box("PriceBoard", 9.5, FLOOR + 5, SOUTH - 0.6, 20.5, FLOOR + 10.5, SOUTH - 0.5, Color3.fromRGB(20, 24, 30), Enum.Material.Metal, f)
    local pg = surface(board, Enum.NormalId.Front, 36)
    local pbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(20, 24, 30) }, pg)
    text({ Text = "SERVICE MENU", Position = UDim2.fromScale(0.05, 0.03), Size = UDim2.fromScale(0.9, 0.2),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(245, 200, 90) }, pbg)
    for i, row in ipairs({ { "OIL CHANGE", "$29" }, { "NEW TIRES", "$59" }, { "BRAKES", "$99" }, { "PAINT & BODY", "ASK US" } }) do
        local y = 0.26 + (i - 1) * 0.18
        text({ Text = row[1], Position = UDim2.fromScale(0.06, y), Size = UDim2.fromScale(0.6, 0.15),
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.text }, pbg)
        text({ Text = row[2], Position = UDim2.fromScale(0.62, y), Size = UDim2.fromScale(0.32, 0.15),
            TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.display, TextScaled = true,
            TextColor3 = T.money }, pbg)
    end
    local open = box("OpenSign", 12, FLOOR + 11, SOUTH - 0.6, 18, FLOOR + 13, SOUTH - 0.5, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
    local og = surface(open, Enum.NormalId.Front, 30)
    og.Brightness = 2.4
    text({ Text = "OPEN", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 120, 150),
        TextStrokeColor3 = Color3.fromRGB(255, 40, 100), TextStrokeTransparency = 0.2 }, og)
    local ol = Instance.new("PointLight")
    ol.Color = Color3.fromRGB(255, 90, 140)
    ol.Brightness = 0.8
    ol.Range = 8
    ol.Parent = open
    local deskSign = box("DeskSign", 10.5, FLOOR + 8.8, 33.2, 19.5, FLOOR + 10.2, 33.4, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
    box("DeskSignCable", 14.9, FLOOR + 10.2, 33.25, 15.1, FLOOR + H, 33.35, STEEL, Enum.Material.Metal, f, { CanCollide = false })
    local dg = surface(deskSign, Enum.NormalId.Front, 30)
    dg.Brightness = 1.8
    text({ Text = "SERVICE DESK", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(150, 225, 200) }, dg)

    -- big painted name on the back wall — the first thing you see through the garage door
    local name = box("ShopName", -12, FLOOR + 9.5, SOUTH - 0.6, 8, FLOOR + 13, SOUTH - 0.5, Color3.fromRGB(240, 232, 222), Enum.Material.Plaster, f)
    local ng = surface(name, Enum.NormalId.Front, 30)
    ng.LightInfluence = 1
    text({ Text = "RIVERSIDE AUTO BODY", Position = UDim2.fromScale(0.03, 0.05), Size = UDim2.fromScale(0.94, 0.6),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(200, 60, 110) }, ng)
    text({ Text = "FAMILY OWNED  ·  SINCE 1986", Position = UDim2.fromScale(0.1, 0.66), Size = UDim2.fromScale(0.8, 0.28),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextScaled = true,
        TextColor3 = Color3.fromRGB(60, 110, 100) }, ng)
end

-- ──────────────────────────────────────────────
-- 🛗 v1.2: freight lift down to The Vault
-- ──────────────────────────────────────────────
function SafehouseBuilder:_liftDown(f)
    local e = W.SAFEHOUSE_ELEVATOR
    local x0, x1, z0, z1 = e.x - 4, e.x + 4, e.z - 4, e.z + 4
    local yellow = Color3.fromRGB(212, 168, 44)
    box("LiftPlate", x0, FLOOR, z0, x1, FLOOR + 0.25, z1, Color3.fromRGB(70, 72, 78), Enum.Material.DiamondPlate, f)
    box("LiftStripeN", x0, FLOOR + 0.25, z0, x1, FLOOR + 0.28, z0 + 0.4, yellow, Enum.Material.SmoothPlastic, f, { CanCollide = false })
    box("LiftStripeS", x0, FLOOR + 0.25, z1 - 0.4, x1, FLOOR + 0.28, z1, yellow, Enum.Material.SmoothPlastic, f, { CanCollide = false })
    for _, p in ipairs({ { x0, z0 }, { x1, z0 }, { x0, z1 }, { x1, z1 } }) do
        box("LiftPost", p[1] - 0.25, FLOOR, p[2] - 0.25, p[1] + 0.25, FLOOR + 9, p[2] + 0.25, yellow, Enum.Material.Metal, f)
    end
    box("LiftFrame", x0 - 0.25, FLOOR + 9, z0 - 0.25, x1 + 0.25, FLOOR + 9.5, z1 + 0.25, yellow, Enum.Material.Metal, f)
    local panel = box("LiftPanel", x1 - 0.2, FLOOR + 3.5, z1 - 1.4, x1 + 0.3, FLOOR + 5.5, z1 - 0.4, Color3.fromRGB(20, 20, 24), Enum.Material.Metal, f)
    box("LiftButton", x1 + 0.3, FLOOR + 4.3, z1 - 1.1, x1 + 0.4, FLOOR + 4.7, z1 - 0.7, Color3.fromRGB(255, 70, 180), Enum.Material.Neon, f, { CanCollide = false })
    local sign = box("LiftSign", x0 + 0.5, FLOOR + 9.6, z1 - 0.1, x1 - 0.5, FLOOR + 11.2, z1 + 0.1, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Back, 30)
    sg.Brightness = 2
    text({ Text = "▼ THE VAULT", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 150, 215) }, sg)
    local pl = Instance.new("PointLight")
    pl.Color = Color3.fromRGB(255, 70, 180)
    pl.Brightness = 1.2
    pl.Range = 12
    pl.Parent = panel
    local p = Instance.new("ProximityPrompt")
    p.Name = "ElevatorDown"
    p.ActionText = "Down to The Vault"
    p.ObjectText = "Freight lift"
    p.HoldDuration = 0.5
    p.MaxActivationDistance = 9
    p.RequiresLineOfSight = false
    p.Parent = panel
    p.Triggered:Connect(function(player)
        if SafehouseBuilder.onElevator then SafehouseBuilder.onElevator(player, "down") end
    end)
end

-- ──────────────────────────────────────────────
function SafehouseBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "Safehouse"
    f.Parent = folder
    local refs = {}

    self:_shell(f)
    self:_garageDoor(f)
    -- v1.2: the crew pads, planning table, gear wall and TV moved down to The
    -- Vault (ClubBuilder). The auto shop is just the cover business now, with
    -- a freight lift down to the club. (_planningTable/_crewPads/_gearWall/
    -- _lounge are kept in this file but no longer called.)
    self:_clutter(f)
    self:_autoShop(f)      -- v2.0: service bays, tool wall, tyre rack, service desk
    self:_liftDown(f)

    local street = Instance.new("Folder")
    street.Name = "Street"
    street.Parent = folder
    self:buildStreet(street)

    print("[SafehouseBuilder] Safehouse + street built 🏚")
    return refs
end

return SafehouseBuilder
