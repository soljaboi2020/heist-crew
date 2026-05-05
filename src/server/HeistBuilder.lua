--[[
    HEIST CREW — HeistBuilder
    ────────────────────────────────────────────────
    Procedurally builds the world geometry on server startup:
      - Mansion (walls, floor, roof, doorway)
      - Vault (inside the mansion)
      - Getaway car (outside)
      - Decorative spawn ring

    Returns refs to the important parts so other services can wire up
    interactions (touch, ProximityPrompt, etc.) without re-finding them.

    PUBLIC API:
        HeistBuilder:build()  →  table with refs: { vault, getawayCar, mansionDoor, mansionFolder, ... }
--]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local HeistBuilder = {}

local function v3(t) return Vector3.new(t.x, t.y, t.z) end
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

-- Helper: make an anchored part with sensible defaults
local function makePart(name, parent, props)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do
        p[k] = v
    end
    p.Parent = parent
    return p
end

-- Build the mansion: floor, 4 walls (with doorway gap in the south wall), roof
local function buildMansion(folder)
    local W = Constants.WORLD
    local center = v3(W.MANSION_CENTER)
    local halfW = W.MANSION_HALF_WIDTH
    local halfD = W.MANSION_HALF_DEPTH
    local height = W.MANSION_WALL_HEIGHT
    local doorWidth = W.MANSION_DOOR_WIDTH

    local stoneColor = Color3.fromRGB(82, 78, 72)
    local floorColor = Color3.fromRGB(50, 45, 38)

    -- Floor
    makePart("Floor", folder, {
        Size = Vector3.new(halfW * 2, 1, halfD * 2),
        Position = center + Vector3.new(0, 0, 0),
        Material = Enum.Material.WoodPlanks,
        Color = floorColor,
    })

    -- Roof (slightly transparent so you can see inside from the outside)
    makePart("Roof", folder, {
        Size = Vector3.new(halfW * 2, 1, halfD * 2),
        Position = center + Vector3.new(0, height + 0.5, 0),
        Material = Enum.Material.Slate,
        Color = Color3.fromRGB(40, 40, 40),
        Transparency = 0.5,
    })

    -- North wall (back wall, behind vault — solid)
    makePart("WallNorth", folder, {
        Size = Vector3.new(halfW * 2, height, 1),
        Position = center + Vector3.new(0, height / 2 + 0.5, -halfD),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })

    -- East wall (right side — solid)
    makePart("WallEast", folder, {
        Size = Vector3.new(1, height, halfD * 2),
        Position = center + Vector3.new(halfW, height / 2 + 0.5, 0),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })

    -- West wall (left side — solid)
    makePart("WallWest", folder, {
        Size = Vector3.new(1, height, halfD * 2),
        Position = center + Vector3.new(-halfW, height / 2 + 0.5, 0),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })

    -- South wall (front, with doorway gap — split into 3 sections)
    -- Left segment
    local leftSegWidth = (halfW * 2 - doorWidth) / 2
    makePart("WallSouth_Left", folder, {
        Size = Vector3.new(leftSegWidth, height, 1),
        Position = center + Vector3.new(-(doorWidth / 2 + leftSegWidth / 2), height / 2 + 0.5, halfD),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })
    -- Right segment
    makePart("WallSouth_Right", folder, {
        Size = Vector3.new(leftSegWidth, height, 1),
        Position = center + Vector3.new((doorWidth / 2 + leftSegWidth / 2), height / 2 + 0.5, halfD),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })
    -- Top (lintel) above the doorway
    makePart("WallSouth_Lintel", folder, {
        Size = Vector3.new(doorWidth, height - 9, 1),
        Position = center + Vector3.new(0, height / 2 + 0.5 + 4.5, halfD),
        Material = Enum.Material.Concrete,
        Color = stoneColor,
    })

    -- Big "MANSION" sign above the door
    local signPart = makePart("MansionSign", folder, {
        Size = Vector3.new(doorWidth, 3, 0.3),
        Position = center + Vector3.new(0, height + 2.5, halfD + 0.5),
        Material = Enum.Material.SmoothPlastic,
        Color = rgb(Constants.COLORS.BG_DARK),
        CanCollide = false,
    })
    local signGui = Instance.new("SurfaceGui", signPart)
    signGui.Face = Enum.NormalId.Front
    signGui.LightInfluence = 0
    signGui.AlwaysOnTop = true
    signGui.PixelsPerStud = 50
    local signLabel = Instance.new("TextLabel", signGui)
    signLabel.Size = UDim2.new(1, 0, 1, 0)
    signLabel.BackgroundTransparency = 1
    signLabel.Text = "🏛 MANSION HEIST"
    signLabel.TextColor3 = rgb(Constants.COLORS.GOLD)
    signLabel.TextScaled = true
    signLabel.Font = Enum.Font.GothamBlack

    return center
end

-- Build the vault — a glowing gold cube inside the mansion
local function buildVault(folder)
    local vault = makePart("Vault", folder, {
        Size = Vector3.new(8, 10, 4),
        Position = v3(Constants.WORLD.MANSION_VAULT),
        Material = Enum.Material.DiamondPlate,
        Color = rgb(Constants.COLORS.GOLD),
    })

    -- Glowing yellow outline
    local light = Instance.new("PointLight", vault)
    light.Color = rgb(Constants.COLORS.GOLD)
    light.Range = 14
    light.Brightness = 1.5

    -- Floating sign
    local sign = makePart("VaultSign", folder, {
        Size = Vector3.new(8, 2, 0.2),
        Position = v3(Constants.WORLD.MANSION_VAULT) + Vector3.new(0, 7.5, 0),
        Material = Enum.Material.SmoothPlastic,
        Color = rgb(Constants.COLORS.BG_DARK),
        CanCollide = false,
    })
    local gui = Instance.new("SurfaceGui", sign)
    gui.Face = Enum.NormalId.Front
    gui.LightInfluence = 0
    gui.AlwaysOnTop = true
    gui.PixelsPerStud = 50
    local label = Instance.new("TextLabel", gui)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "💰 VAULT"
    label.TextColor3 = rgb(Constants.COLORS.GOLD)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack

    return vault
end

-- Build the getaway car (a styled box w/ wheels)
local function buildGetawayCar(folder)
    local pos = v3(Constants.WORLD.GETAWAY_POSITION)

    local body = makePart("GetawayCar", folder, {
        Size = Vector3.new(10, 4, 18),
        Position = pos,
        Material = Enum.Material.Metal,
        Color = Color3.fromRGB(40, 40, 50),
    })

    -- Roof
    local roof = makePart("CarRoof", folder, {
        Size = Vector3.new(8, 3, 10),
        Position = pos + Vector3.new(0, 3.5, -1),
        Material = Enum.Material.Metal,
        Color = Color3.fromRGB(20, 20, 25),
        CanCollide = false,
    })
    -- Wheels (decorative)
    local wheelData = {
        {x = 5,  z = 6},
        {x = -5, z = 6},
        {x = 5,  z = -6},
        {x = -5, z = -6},
    }
    for i, w in ipairs(wheelData) do
        makePart("Wheel" .. i, folder, {
            Shape = Enum.PartType.Cylinder,
            Size = Vector3.new(2, 3, 3),
            CFrame = CFrame.new(pos + Vector3.new(w.x, -1.5, w.z)) * CFrame.Angles(0, 0, math.rad(90)),
            Material = Enum.Material.Plastic,
            Color = Color3.fromRGB(20, 20, 20),
            CanCollide = false,
        })
    end

    -- Sign
    local sign = makePart("GetawaySign", folder, {
        Size = Vector3.new(10, 3, 0.2),
        Position = pos + Vector3.new(0, 6.5, 0),
        Material = Enum.Material.SmoothPlastic,
        Color = rgb(Constants.COLORS.BG_DARK),
        CanCollide = false,
    })
    local gui = Instance.new("SurfaceGui", sign)
    gui.Face = Enum.NormalId.Front
    gui.LightInfluence = 0
    gui.AlwaysOnTop = true
    gui.PixelsPerStud = 50
    local label = Instance.new("TextLabel", gui)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "🚗 GETAWAY"
    label.TextColor3 = Color3.fromRGB(120, 120, 120)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBlack
    label.Name = "GetawayLabel"

    return body, label
end

-- Decorative ring around the spawn area
local function buildSpawnRing(folder)
    local pos = v3(Constants.WORLD.SPAWN_POSITION)
    local segments = 24
    local radius = 30
    for i = 1, segments do
        local angle = (i / segments) * math.pi * 2
        local x = math.cos(angle) * radius
        local z = math.sin(angle) * radius
        makePart("SpawnRing_" .. i, folder, {
            Size = Vector3.new(2, 0.3, 4),
            CFrame = CFrame.new(pos.X + x, 0.15, pos.Z + z) * CFrame.Angles(0, -angle, 0),
            Material = Enum.Material.Neon,
            Color = rgb(Constants.COLORS.GREEN_PRIMARY),
            CanCollide = false,
        })
    end
end

function HeistBuilder:build()
    -- Container folder for all our generated geometry
    local heistFolder = Workspace:FindFirstChild("HeistWorld")
    if heistFolder then heistFolder:Destroy() end
    heistFolder = Instance.new("Folder")
    heistFolder.Name = "HeistWorld"
    heistFolder.Parent = Workspace

    local mansionFolder = Instance.new("Folder", heistFolder)
    mansionFolder.Name = "Mansion"

    local mansionCenter = buildMansion(mansionFolder)
    local vault = buildVault(mansionFolder)
    local car, getawayLabel = buildGetawayCar(heistFolder)
    buildSpawnRing(heistFolder)

    print("[HeistBuilder] World built ✅ — mansion at", mansionCenter, "vault at", vault.Position)

    return {
        heistFolder = heistFolder,
        mansionFolder = mansionFolder,
        vault = vault,
        getawayCar = car,
        getawayLabel = getawayLabel,
    }
end

return HeistBuilder
