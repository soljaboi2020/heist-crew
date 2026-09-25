--[[
    HEIST CREW — GetawayProps  (v3.0 "THE SCORE", getaway agent)
    ────────────────────────────────────────────────
    Everything the getaway cut-scene needs that isn't already in the world.
    Built ONCE, out of the way of play:

      • TEMPLATES in ReplicatedStorage.HC_GetawayProps (never rendered there —
        each client clones what its scene needs, plays it, destroys it):
          Helicopter   navy news-chopper style, open cabin (4 seats), skids,
                       MainRotor + TailRotor sub-models the client spins,
                       nav lights + belly searchlight. Root = ground under the skids.
          Speedboat    a copy of MiamiBuilder's marina boat (so it matches the one
                       tied to the pier) with a Root at the hull origin; our own
                       build if that boat can't be found.
          Cruiser      PoliceService's black-and-white (chase cars in the scene).
          Roadblock    a cruiser parked ACROSS the road + a striped barrier + cones.
                       Every direct child except Root is one "piece" (the Tank /
                       Armored scene flings them).
          Shutter      a roll-up steel door; its "Door" model lifts to open.
        Every template: Root (invisible, PrimaryPart, at the origin, front = -Z),
        all parts Anchored, no collision / query / touch. Crew spots are
        Attachments "Seat1".."Seat4" on the Root (boat + helicopter).
        ObjectValue HC_GetawayProps.RealBoat → the real speedboat at the pier
        (the client hides it while its copy races off) + attribute RealBoatCF.

      • THE NIGHT HIGHWAY (Workspace.GetawayHighway): a lit 4-lane interstate far
        outside the map (x 900..1800, z 900; the city is x −150..150), jersey
        barriers, lane dashes, sodium streetlights every 60 studs, a green
        I-95 gantry, a dark skyline with a few lit window strips, and a
        sunset-at-night glow at the far end. No player can reach it (void
        between it and the city); the Highway escape cuts to it with a fade.

    Art rules (docs/ART_DIRECTION.md): real Materials everywhere, Neon only on
    bulbs / thin light strips, text only on SurfaceGuis.

    PUBLIC API:
        GetawayProps:init() -> folder        -- idempotent; builds templates + highway
        GetawayProps.HIGHWAY = { x0, x1, z, y, laneOffset }
        GetawayProps.boatCFrame() -> CFrame  -- where the real speedboat floats
        GetawayProps:getFolder() -> Folder | nil
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local GetawayProps = {}

GetawayProps.HIGHWAY = { x0 = 900, x1 = 1800, z = 900, y = 0, laneOffset = 12 }
local DEFAULT_BOAT_CF = CFrame.new(109, -0.3, -141)   -- MiamiBuilder:_marina boatCF

local built = false
local propsFolder = nil
local realBoatCF = DEFAULT_BOAT_CF

-- ── part helpers (local coords: origin = ground, front = -Z) ─────────
local GHOST = { CanCollide = false, CanTouch = false, CanQuery = false }

local function part(props, parent, className)
    local p = Instance.new(className or "Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.CastShadow = true
    for k, v in pairs(props) do (p :: any)[k] = v end
    p.Parent = parent
    return p
end

local function box(parent, name, x0, y0, z0, x1, y1, z1, color, material, extra, className)
    local props = {
        Name = name,
        Size = Vector3.new(math.max(0.05, math.abs(x1 - x0)), math.max(0.05, math.abs(y1 - y0)), math.max(0.05, math.abs(z1 - z0))),
        CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Color = color,
        Material = material or Enum.Material.Metal,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent, className)
end

local function cyl(parent, name, a, b, d, color, material, extra)
    local len = (b - a).Magnitude
    local mid = (a + b) / 2
    local dir = (b - a).Unit
    -- a Cylinder's axis is its X: build a frame whose RightVector = dir
    local up = math.abs(dir.Y) > 0.95 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
    local back = dir:Cross(up).Unit
    local realUp = back:Cross(dir).Unit
    local props = {
        Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, d, d),
        CFrame = CFrame.fromMatrix(mid, dir, realUp, back), Color = color, Material = material or Enum.Material.Metal,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function light(parent, class, color, brightness, range, extra)
    local l = Instance.new(class)
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Shadows = false
    for k, v in pairs(extra or {}) do (l :: any)[k] = v end
    l.Parent = parent
    return l
end

local function surfaceText(p, face, text, color, bg, pps)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 30
    g.LightInfluence = 0.6
    g.Parent = p
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundTransparency = bg and 0 or 1
    if bg then l.BackgroundColor3 = bg end
    l.Text = text
    l.TextScaled = true
    l.Font = Enum.Font.GothamBlack
    l.TextColor3 = color
    l.Parent = g
    return g
end

local function newModel(name, parent)
    local m = Instance.new("Model")
    m.Name = name
    local root = part({ Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(), Transparency = 1, CastShadow = false }, m)
    m.PrimaryPart = root
    if parent then m.Parent = parent end
    return m, root
end

local function seatSpot(root, i, pos)
    local a = Instance.new("Attachment")
    a.Name = "Seat" .. i
    a.Position = pos
    a.Parent = root
end

-- every BasePart: anchored, no collision / query / touch (a scene prop is a picture)
local function ghostAll(model)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
        elseif d:IsA("ProximityPrompt") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
            d:Destroy()
        end
    end
    for _, tag in ipairs(CollectionService:GetTags(model)) do CollectionService:RemoveTag(model, tag) end
end

-- ── helicopter ───────────────────────────────────────────────────────
local NAVY = Color3.fromRGB(26, 36, 62)
local GOLD = Color3.fromRGB(245, 190, 60)
local DARK = Color3.fromRGB(22, 22, 26)
local LEATHER = Color3.fromRGB(40, 34, 36)

local function buildHelicopter(parent)
    local m, root = newModel("Helicopter")
    local M = Enum.Material.Metal
    -- skids + struts
    for _, s in ipairs({ -1, 1 }) do
        box(m, "Skid", s * 2.6 - 0.2, 0.05, -4.2, s * 2.6 + 0.2, 0.45, 4.2, DARK, M)
        box(m, "SkidTip", s * 2.6 - 0.2, 0.3, -4.9, s * 2.6 + 0.2, 0.7, -4.2, DARK, M)
        for _, z in ipairs({ -2.4, 2.2 }) do
            box(m, "Strut", s * 2.35 - 0.15, 0.4, z - 0.15, s * 2.35 + 0.15, 1.5, z + 0.15, DARK, M)
        end
    end
    -- fuselage: floor, open cabin (doors slid back), roof, rear wall
    box(m, "Belly", -2.8, 1.4, -4.4, 2.8, 2.0, 3.2, NAVY, M, { Reflectance = 0.08 })
    box(m, "Floor", -2.5, 2.0, -3.4, 2.5, 2.1, 2.6, DARK, Enum.Material.DiamondPlate)
    box(m, "Chin", -2.4, 1.4, -5.6, 2.4, 2.8, -4.4, NAVY, M, { Reflectance = 0.08 })
    part({ Name = "Canopy", Size = Vector3.new(4.8, 3.0, 2.2), CFrame = CFrame.new(0, 4.3, -4.5),
        Color = Color3.fromRGB(30, 50, 70), Material = Enum.Material.Glass, Transparency = 0.35, Reflectance = 0.25 }, m, "WedgePart")
    box(m, "Roof", -2.8, 5.8, -3.6, 2.8, 6.2, 2.8, NAVY, M, { Reflectance = 0.08 })
    box(m, "RearWall", -2.8, 2.0, 2.6, 2.8, 5.8, 3.2, NAVY, M, { Reflectance = 0.08 })
    for _, s in ipairs({ -1, 1 }) do
        box(m, "PillarF", s * 2.8 - 0.2, 2.0, -3.6, s * 2.8 + 0.2, 5.8, -3.3, NAVY, M)
        box(m, "SillStripe", s * 2.82 - 0.02, 1.55, -4.4, s * 2.82 + 0.02, 1.85, 3.2, GOLD, M)
        -- the slid-back door, parked over the rear wall
        box(m, "SlidDoor", s * 2.95 - 0.1, 2.1, 1.0, s * 2.95 + 0.1, 5.6, 3.6, NAVY, M, { Reflectance = 0.08 })
        box(m, "DoorWindow", s * 3.06 - 0.02, 4.0, 1.4, s * 3.06 + 0.02, 5.1, 3.2, Color3.fromRGB(30, 50, 70), Enum.Material.Glass, { Transparency = 0.3 })
    end
    -- engine + mast
    box(m, "Engine", -1.6, 6.2, -1.6, 1.6, 7.1, 2.6, NAVY:Lerp(Color3.new(0, 0, 0), 0.25), M)
    box(m, "Exhaust", -0.5, 6.6, 2.6, 0.5, 7.0, 3.2, DARK, M)
    cyl(m, "Mast", Vector3.new(0, 7.1, 0.4), Vector3.new(0, 7.9, 0.4), 0.5, DARK, M)
    -- seats (the crew sits here)
    for i, spot in ipairs({ { -1.3, -1.8 }, { 1.3, -1.8 }, { -1.3, 1.1 }, { 1.3, 1.1 } }) do
        box(m, "Seat", spot[1] - 0.65, 2.1, spot[2] - 0.6, spot[1] + 0.65, 2.55, spot[2] + 0.6, LEATHER, Enum.Material.Fabric)
        box(m, "SeatBack", spot[1] - 0.65, 2.55, spot[2] + 0.45, spot[1] + 0.65, 3.8, spot[2] + 0.65, LEATHER, Enum.Material.Fabric)
        seatSpot(root, i, Vector3.new(spot[1], 2.55, spot[2]))
    end
    -- tail
    box(m, "TailBoom", -0.55, 4.2, 3.2, 0.55, 5.1, 13.2, NAVY, M, { Reflectance = 0.08 })
    box(m, "TailStripe", -0.57, 4.5, 3.4, 0.57, 4.7, 12.6, GOLD, M)
    box(m, "Fin", -0.12, 5.1, 11.8, 0.12, 8.2, 13.3, NAVY, M)
    box(m, "Stabilizer", -2.1, 4.5, 11.2, 2.1, 4.7, 12.2, NAVY, M)
    local tailPlate = box(m, "TailPlate", -0.58, 4.25, 6.0, 0.58, 5.05, 10.0, NAVY, M)
    surfaceText(tailPlate, Enum.NormalId.Left, "SKY CREW", GOLD, nil, 40)
    surfaceText(tailPlate, Enum.NormalId.Right, "SKY CREW", GOLD, nil, 40)

    -- main rotor: hub + 4 blades + a faint "blur" disc (spun by the client)
    local rotor = Instance.new("Model")
    rotor.Name = "MainRotor"
    local hub = cyl(rotor, "Hub", Vector3.new(0, 7.8, 0.4), Vector3.new(0, 8.3, 0.4), 1.1, DARK, M)
    rotor.PrimaryPart = hub
    box(rotor, "Blade", -12, 8.05, 0.0, 12, 8.17, 0.8, DARK, M)
    box(rotor, "Blade", -0.4, 8.05, -11.6, 0.4, 8.17, 12.4, DARK, M)
    local disc = part({ Name = "Blur", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 24, 24),
        CFrame = CFrame.new(0, 8.1, 0.4) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 64, 72),
        Material = Enum.Material.Glass, Transparency = 0.88, CastShadow = false }, rotor)
    disc.Name = "Blur"
    rotor.Parent = m
    -- tail rotor (spins around X)
    local tail = Instance.new("Model")
    tail.Name = "TailRotor"
    local thub = cyl(tail, "Hub", Vector3.new(0.6, 6.9, 12.7), Vector3.new(0.95, 6.9, 12.7), 0.5, DARK, M)
    tail.PrimaryPart = thub
    box(tail, "Blade", 0.8, 5.1, 12.5, 0.9, 8.7, 12.9, DARK, M)
    box(tail, "Blade", 0.8, 6.7, 10.9, 0.9, 7.1, 14.5, DARK, M)
    tail.Parent = m

    -- lights: nav (port red / starboard green), tail strobe, belly searchlight
    local navR = box(m, "NavRed", -2.95, 1.6, -4.2, -2.8, 1.8, -3.9, Color3.fromRGB(255, 40, 60), Enum.Material.Neon)
    local navG = box(m, "NavGreen", 2.8, 1.6, -4.2, 2.95, 1.8, -3.9, Color3.fromRGB(40, 255, 120), Enum.Material.Neon)
    light(navR, "PointLight", Color3.fromRGB(255, 40, 60), 1, 6)
    light(navG, "PointLight", Color3.fromRGB(40, 255, 120), 1, 6)
    local strobe = box(m, "Strobe", -0.15, 8.2, 12.9, 0.15, 8.45, 13.2, Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
    light(strobe, "PointLight", Color3.fromRGB(255, 255, 255), 1.5, 10)
    local search = box(m, "Searchlight", -0.35, 1.1, -4.9, 0.35, 1.4, -4.3, Color3.fromRGB(255, 246, 220), Enum.Material.Neon)
    local beam = light(search, "SpotLight", Color3.fromRGB(255, 246, 220), 4, 60, { Angle = 30, Face = Enum.NormalId.Bottom })
    beam.Name = "Beam"
    ghostAll(m)
    m.Parent = parent
    return m
end

-- ── speedboat: MiamiBuilder's, or our own ───────────────────────────
local function findRealBoat()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("Model") and d.Name == "Speedboat" and d:FindFirstChild("Hull") then return d end
    end
    return nil
end

local function buildOwnBoat(m)
    local HULL = Color3.fromRGB(244, 244, 248)
    local PINK = Color3.fromRGB(255, 70, 180)
    box(m, "Hull", -2.5, -1.1, -3.0, 2.5, 1.1, 8.0, HULL, Enum.Material.Metal)
    part({ Name = "BowR", Size = Vector3.new(2.2, 2.5, 5), CFrame = CFrame.new(1.25, 0, -5.5) * CFrame.Angles(0, 0, math.rad(-90)),
        Color = HULL, Material = Enum.Material.Metal }, m, "WedgePart")
    part({ Name = "BowL", Size = Vector3.new(2.2, 2.5, 5), CFrame = CFrame.new(-1.25, 0, -5.5) * CFrame.Angles(0, 0, math.rad(90)),
        Color = HULL, Material = Enum.Material.Metal }, m, "WedgePart")
    box(m, "Deck", -2.2, 1.1, 0.1, 2.2, 1.25, 7.3, Color3.fromRGB(150, 100, 64), Enum.Material.WoodPlanks)
    for _, sx in ipairs({ -1, 1 }) do
        box(m, "Stripe", sx * 2.55 - 0.06, 0.1, -3.0, sx * 2.55 + 0.06, 0.4, 8.0, PINK, Enum.Material.Neon)
        box(m, "Seat", sx * 1.1 - 0.75, 1.25, 0.8, sx * 1.1 + 0.75, 2.05, 2.2, Color3.fromRGB(240, 230, 214), Enum.Material.Fabric)
    end
    part({ Name = "Windshield", Size = Vector3.new(4.2, 1.3, 0.12), CFrame = CFrame.new(0, 1.9, -1.2) * CFrame.Angles(math.rad(30), 0, 0),
        Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.4 }, m)
    box(m, "RearBench", -2, 1.2, 6.3, 2, 2.0, 7.5, Color3.fromRGB(240, 230, 214), Enum.Material.Fabric)
    box(m, "Outboard", -0.7, -0.4, 8.0, 0.7, 2.2, 9.2, Color3.fromRGB(40, 42, 50), Enum.Material.Metal)
end

local function buildBoat(parent)
    local real = findRealBoat()
    local m, root
    if real then
        local okC, copy = pcall(function() return real:Clone() end)
        local hull = okC and copy and copy:FindFirstChild("Hull")
        if hull then
            -- MiamiBuilder built it as boatCF * offsets, with Hull at boatCF * (0, 0, 2.5)
            local origin = hull.CFrame * CFrame.new(0, 0, -2.5)
            realBoatCF = origin
            m = copy
            m.Name = "Speedboat"
            root = part({ Name = "Root", Size = Vector3.new(1, 1, 1), CFrame = origin, Transparency = 1, CastShadow = false }, m)
            m.PrimaryPart = root
            m:PivotTo(CFrame.new())
        elseif okC and copy then
            copy:Destroy()
        end
    end
    if not m then
        m, root = newModel("Speedboat")
        buildOwnBoat(m)
    end
    seatSpot(root, 1, Vector3.new(-1.1, 2.05, 1.5))
    seatSpot(root, 2, Vector3.new(1.1, 2.05, 1.5))
    seatSpot(root, 3, Vector3.new(-1.0, 2.0, 6.9))
    seatSpot(root, 4, Vector3.new(1.0, 2.0, 6.9))
    local wake = Instance.new("Attachment")
    wake.Name = "Wake"
    wake.Position = Vector3.new(0, -0.2, 9.4)
    wake.Parent = root
    ghostAll(m)
    m.Parent = parent
    return m, real
end

-- ── police cruiser (PoliceService's model) ───────────────────────────
local function buildCruiser(parent)
    local model
    local mod = script.Parent:FindFirstChild("PoliceService")
    if mod then
        local ok, PS = pcall(require, mod)
        if ok and type(PS) == "table" and type(PS.buildCruiserModel) == "function" then
            local okB, parts = pcall(PS.buildCruiserModel, 0)
            if okB and type(parts) == "table" and parts.model then model = parts.model end
        end
    end
    if not model then
        -- stand-in: a plain black-and-white box car
        local m = newModel("Cruiser")
        box(m, "Body", -2.35, 0.75, -5.6, 2.35, 1.95, 5.6, Color3.fromRGB(16, 17, 20), Enum.Material.Metal)
        box(m, "Roof", -2.1, 1.95, -1.8, 2.1, 3.4, 2.5, Color3.fromRGB(240, 240, 236), Enum.Material.Metal)
        box(m, "LightRed", -1.6, 3.4, -0.15, -0.1, 3.8, 0.35, Color3.fromRGB(255, 40, 50), Enum.Material.Neon)
        box(m, "LightBlue", 0.1, 3.4, -0.15, 1.6, 3.8, 0.35, Color3.fromRGB(40, 90, 255), Enum.Material.Neon)
        model = m
    end
    model.Name = "Cruiser"
    ghostAll(model)
    model.Parent = parent
    return model
end

-- ── roadblock: cruiser across the road + barrier + cones ─────────────
local function buildRoadblock(parent, cruiserTemplate)
    local m, root = newModel("Roadblock")
    local car = cruiserTemplate:Clone()
    car.Name = "Cruiser"
    car:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0))   -- length along X, across the lane
    car.Parent = m
    -- striped sawhorse barrier on the left (-X)
    local bar = Instance.new("Model")
    bar.Name = "Barrier"
    local WHITE = Color3.fromRGB(236, 236, 230)
    local RED = Color3.fromRGB(200, 30, 36)
    for _, x in ipairs({ -10.6, -8.2 }) do
        box(bar, "Leg", x - 0.12, 0, -0.5, x + 0.12, 2.6, 0.5, Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
    end
    for i = 0, 5 do
        local x0 = -11 + i * 0.5
        box(bar, "Stripe", x0, 1.8, -0.1, x0 + 0.5, 2.5, 0.1, (i % 2 == 0) and WHITE or RED, Enum.Material.WoodPlanks)
    end
    local blink = box(bar, "Blinker", -9.6, 2.5, -0.15, -9.2, 2.85, 0.15, Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
    light(blink, "PointLight", Color3.fromRGB(255, 170, 40), 1.2, 8)
    bar.PrimaryPart = bar:FindFirstChild("Leg")
    bar.Parent = m
    -- cones (on the right, where a quick car can squeeze past)
    local ORANGE = Color3.fromRGB(255, 110, 30)
    for i, spot in ipairs({ { 7.4, -1.2 }, { 7.9, 1.0 }, { -12.4, 0.2 } }) do
        local cone = Instance.new("Model")
        cone.Name = "Cone"
        local base = box(cone, "Base", spot[1] - 0.5, 0, spot[2] - 0.5, spot[1] + 0.5, 0.15, spot[2] + 0.5, Color3.fromRGB(30, 30, 30), Enum.Material.Rubber)
        cyl(cone, "Body", Vector3.new(spot[1], 0.15, spot[2]), Vector3.new(spot[1], 1.3, spot[2]), 0.55, ORANGE, Enum.Material.Plastic)
        cyl(cone, "Band", Vector3.new(spot[1], 0.7, spot[2]), Vector3.new(spot[1], 0.9, spot[2]), 0.6, WHITE, Enum.Material.Plastic)
        cone.PrimaryPart = base
        cone.Parent = m
        local _ = i
    end
    ghostAll(m)
    m.Parent = parent
    return m
end

-- ── roll-up steel shutter (the yard gate opening) ────────────────────
local function buildShutter(parent)
    local m = newModel("Shutter")
    local GREY = Color3.fromRGB(120, 124, 130)
    local W2 = 4.2
    box(m, "PostL", -W2 - 0.5, 0, -0.35, -W2, 9.2, 0.35, Color3.fromRGB(46, 48, 54), Enum.Material.Metal)
    box(m, "PostR", W2, 0, -0.35, W2 + 0.5, 9.2, 0.35, Color3.fromRGB(46, 48, 54), Enum.Material.Metal)
    box(m, "Drum", -W2 - 0.5, 9.2, -0.7, W2 + 0.5, 10.4, 0.7, Color3.fromRGB(46, 48, 54), Enum.Material.Metal)
    local door = Instance.new("Model")
    door.Name = "Door"
    local first
    for i = 0, 9 do
        local slat = box(door, "Slat", -W2, i * 0.92, -0.12, W2, i * 0.92 + 0.88, 0.12, GREY, Enum.Material.CorrugatedSteel)
        first = first or slat
    end
    local stripe = box(door, "HazardStripe", -W2, 0.2, -0.16, W2, 0.5, -0.12, Color3.fromRGB(245, 196, 40), Enum.Material.Metal)
    door.PrimaryPart = first
    door.Parent = m
    local _ = stripe
    ghostAll(m)
    m.Parent = parent
    return m
end

-- ── the night highway (world) ────────────────────────────────────────
local function buildHighway()
    local old = Workspace:FindFirstChild("GetawayHighway")
    if old then old:Destroy() end
    local H = GetawayProps.HIGHWAY
    local f = Instance.new("Folder")
    f.Name = "GetawayHighway"
    local len = H.x1 - H.x0 + 120
    local cx = (H.x0 + H.x1) / 2
    local ASPHALT = Color3.fromRGB(38, 38, 44)
    local CONCRETE = Color3.fromRGB(150, 146, 140)
    local LINE = Color3.fromRGB(226, 226, 220)
    local YELLOW = Color3.fromRGB(230, 190, 60)
    local SODIUM = Color3.fromRGB(255, 190, 120)
    local z = H.z
    local solid = { CanCollide = true, CanQuery = true }
    -- ground + road
    box(f, "Verge", cx - len / 2, H.y - 1.2, z - 70, cx + len / 2, H.y - 0.2, z + 70, Color3.fromRGB(30, 40, 30), Enum.Material.Grass, solid)
    box(f, "Road", cx - len / 2, H.y - 1, z - 22, cx + len / 2, H.y, z + 22, ASPHALT, Enum.Material.Asphalt, solid)
    for _, s in ipairs({ -1, 1 }) do
        box(f, "EdgeLine", cx - len / 2, H.y, z + s * 19.4 - 0.2, cx + len / 2, H.y + 0.04, z + s * 19.4 + 0.2, LINE, Enum.Material.Concrete)
        box(f, "Barrier", cx - len / 2, H.y, z + s * 22 - 0.6, cx + len / 2, H.y + 2.6, z + s * 22 + 0.6, CONCRETE, Enum.Material.Concrete, solid)
    end
    box(f, "Median", cx - len / 2, H.y, z - 0.6, cx + len / 2, H.y + 2.6, z + 0.6, CONCRETE, Enum.Material.Concrete, solid)
    box(f, "MedianLineN", cx - len / 2, H.y, z - 1.2, cx + len / 2, H.y + 0.04, z - 0.9, YELLOW, Enum.Material.Concrete)
    box(f, "MedianLineS", cx - len / 2, H.y, z + 0.9, cx + len / 2, H.y + 0.04, z + 1.2, YELLOW, Enum.Material.Concrete)
    -- lane dashes (both directions)
    for x = H.x0 - 50, H.x1 + 50, 14 do
        for _, dz in ipairs({ -10, 10 }) do
            box(f, "Dash", x, H.y, z + dz - 0.18, x + 6, H.y + 0.04, z + dz + 0.18, LINE, Enum.Material.Concrete)
        end
    end
    -- sodium streetlights on the median (pools of light, dark between)
    for x = H.x0 - 30, H.x1 + 30, 60 do
        cyl(f, "LampPole", Vector3.new(x, H.y + 2.6, z), Vector3.new(x, H.y + 16, z), 0.5, Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
        for _, s in ipairs({ -1, 1 }) do
            box(f, "LampArm", x - 0.2, H.y + 15.6, z + math.min(0, s * 7), x + 0.2, H.y + 16, z + math.max(0, s * 7), Color3.fromRGB(70, 72, 78), Enum.Material.Metal)
            local head = box(f, "LampHead", x - 0.8, H.y + 15.3, z + s * 7 - 0.6, x + 0.8, H.y + 15.8, z + s * 7 + 0.6, Color3.fromRGB(56, 58, 62), Enum.Material.Metal)
            local bulb = box(f, "LampBulb", x - 0.6, H.y + 15.15, z + s * 7 - 0.4, x + 0.6, H.y + 15.3, z + s * 7 + 0.4, SODIUM, Enum.Material.Neon)
            light(head, "SpotLight", SODIUM, 2.2, 34, { Face = Enum.NormalId.Bottom, Angle = 110 })
            local _ = bulb
        end
    end
    -- green I-95 gantry
    local gx = H.x0 + 230
    for _, s in ipairs({ -1, 1 }) do
        box(f, "GantryPost", gx - 0.5, H.y, z + s * 23 - 0.5, gx + 0.5, H.y + 17, z + s * 23 + 0.5, Color3.fromRGB(80, 82, 88), Enum.Material.Metal)
    end
    box(f, "GantryBeam", gx - 0.6, H.y + 16, z - 23.5, gx + 0.6, H.y + 17.2, z + 23.5, Color3.fromRGB(80, 82, 88), Enum.Material.Metal)
    local sign1 = box(f, "Sign", gx - 0.3, H.y + 11.5, z + 4, gx + 0.2, H.y + 16, z + 20, Color3.fromRGB(20, 110, 60), Enum.Material.Metal)
    surfaceText(sign1, Enum.NormalId.Left, "I-95 NORTH  ▲  OUT OF TOWN", Color3.fromRGB(245, 245, 240), Color3.fromRGB(20, 110, 60), 24)
    local sign2 = box(f, "Sign", gx - 0.3, H.y + 11.5, z - 20, gx + 0.2, H.y + 16, z - 4, Color3.fromRGB(20, 110, 60), Enum.Material.Metal)
    surfaceText(sign2, Enum.NormalId.Left, "MIAMI BEACH  ◀  NEXT EXIT", Color3.fromRGB(245, 245, 240), Color3.fromRGB(20, 110, 60), 24)
    -- the skyline: dark towers with a few lit window strips
    local rng = Random.new(1995)
    local TOWER = { Color3.fromRGB(34, 36, 50), Color3.fromRGB(44, 40, 58), Color3.fromRGB(28, 34, 44) }
    local WINDOW = { Color3.fromRGB(255, 200, 140), Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 120, 200) }
    for x = H.x0 - 40, H.x1 + 80, 70 do
        for _, s in ipairs({ -1, 1 }) do
            local w = rng:NextNumber(24, 44)
            local d = rng:NextNumber(24, 40)
            local h = rng:NextNumber(50, 170)
            local tz = z + s * rng:NextNumber(80, 150)
            local tx = x + rng:NextNumber(-15, 15)
            box(f, "Tower", tx - w / 2, H.y, tz - d / 2, tx + w / 2, H.y + h, tz + d / 2, TOWER[rng:NextInteger(1, 3)],
                rng:NextNumber() < 0.5 and Enum.Material.Glass or Enum.Material.Concrete, { Reflectance = 0.05 })
            local col = WINDOW[rng:NextInteger(1, 3)]
            local face = tz - s * d / 2   -- the side facing the highway
            for k = 1, rng:NextInteger(2, 4) do
                local y = H.y + rng:NextNumber(10, h - 6)
                box(f, "WindowStrip", tx - w / 2 + 2, y, face - s * 0.15 - 0.1, tx + w / 2 - 2, y + 0.5, face - s * 0.15 + 0.1, col, Enum.Material.Neon)
                local _ = k
            end
            -- aircraft warning light on the tall ones
            if h > 120 then
                local red = box(f, "RoofBeacon", tx - 0.4, H.y + h, tz - 0.4, tx + 0.4, H.y + h + 0.8, tz + 0.4, Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
                light(red, "PointLight", Color3.fromRGB(255, 40, 40), 1, 12)
            end
        end
    end
    -- sunset-at-night: a glowing horizon band at the far end (a painted sky wall)
    local sky = box(f, "HorizonGlow", H.x1 + 110, H.y - 10, z - 420, H.x1 + 114, H.y + 230, z + 420, Color3.fromRGB(40, 20, 50), Enum.Material.SmoothPlastic, { CastShadow = false })
    local g = Instance.new("SurfaceGui")
    g.Face = Enum.NormalId.Left
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = 2
    g.LightInfluence = 0
    g.Brightness = 1.4
    g.Parent = sky
    local fr = Instance.new("Frame")
    fr.Size = UDim2.fromScale(1, 1)
    fr.BorderSizePixel = 0
    fr.BackgroundColor3 = Color3.new(1, 1, 1)
    fr.Parent = g
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 12, 40)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(120, 40, 110)),
        ColorSequenceKeypoint.new(0.82, Color3.fromRGB(255, 110, 90)),
        ColorSequenceKeypoint.new(0.9, Color3.fromRGB(255, 180, 90)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 20, 40)),
    })
    grad.Parent = fr
    local sun = Instance.new("Frame")
    sun.AnchorPoint = Vector2.new(0.5, 0.5)
    sun.Position = UDim2.fromScale(0.5, 0.86)
    sun.Size = UDim2.fromScale(0.16, 0.34)
    sun.BackgroundColor3 = Color3.fromRGB(255, 150, 80)
    sun.BorderSizePixel = 0
    sun.Parent = fr
    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(0.5, 0)
    sc.Parent = sun
    f:SetAttribute("X0", H.x0)
    f:SetAttribute("X1", H.x1)
    f:SetAttribute("Z", H.z)
    f.Parent = Workspace
    return f
end

-- ── public ───────────────────────────────────────────────────────────
function GetawayProps.boatCFrame()
    return realBoatCF
end

function GetawayProps:getFolder()
    return propsFolder
end

function GetawayProps:init()
    if built and propsFolder and propsFolder.Parent then return propsFolder end
    built = true
    local old = ReplicatedStorage:FindFirstChild("HC_GetawayProps")
    if old then old:Destroy() end
    local f = Instance.new("Folder")
    f.Name = "HC_GetawayProps"
    local function try(label, fn)
        local ok, err = pcall(fn)
        if not ok then warn("[GetawayProps] " .. label .. ":", err) end
    end
    local cruiser
    try("helicopter", function() buildHelicopter(f) end)
    try("speedboat", function()
        local _, real = buildBoat(f)
        local ov = Instance.new("ObjectValue")
        ov.Name = "RealBoat"
        ov.Value = real
        ov.Parent = f
        f:SetAttribute("RealBoatCF", realBoatCF)
    end)
    try("cruiser", function() cruiser = buildCruiser(f) end)
    try("roadblock", function() if cruiser then buildRoadblock(f, cruiser) end end)
    try("shutter", function() buildShutter(f) end)
    try("highway", function() buildHighway() end)
    f.Parent = ReplicatedStorage
    propsFolder = f
    print("[GetawayProps] helicopter, speedboat, roadblock, chase cars + the night highway ready 🚁🚤🛣️")
    return f
end

return GetawayProps
