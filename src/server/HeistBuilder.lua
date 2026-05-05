--[[
    HEIST CREW — HeistBuilder (v0.3 — POLISHED)
    ────────────────────────────────────────────────
    Builds the ENTIRE world procedurally:

      🌅 World atmosphere
         - Skybox (cinematic night)
         - Atmosphere (haze + density)
         - Bloom + ColorCorrection (cinematic look)
         - Ambient music

      🏙 Lobby plaza (where players spawn)
         - Circular marble plaza with gold ring border
         - Center pedestal with neon "💰 HEIST CREW" sign
         - 4 lamp posts (with PointLights) at compass points
         - Tutorial billboard ("How to Play")
         - "Boss" NPC standing nearby with chat bubble
         - Decorative trees / fence
         - Stylized SpawnLocation pad

      🛣 Walkway
         - Stone-textured path from lobby → mansion entrance
         - Gold edge strips lining both sides
         - Lamp posts at intervals

      🏛 Mansion (much closer + much prettier)
         - White marble walls (smooth plastic + stroke detail)
         - 4 corner pillars (cylinders, gold caps)
         - Grand archway entrance (no door, just an opening)
         - Tile floor with red carpet runner leading to vault
         - Slate roof with dark trim
         - Interior PointLights for ambiance
         - Decorative wall paintings (color-block frames)

      💰 Vault
         - Gold DiamondPlate cube w/ jewels stacked on top
         - PointLight halo
         - "💰 VAULT" billboard

      🚗 Getaway car
         - Stylized: sloped body, roof, 4 wheels, headlights
         - Idle = dark metal, Active (alarm) = green Neon glow

    PUBLIC API:
        HeistBuilder:build()
            returns refs = { vault, getawayCar, getawayLabel, ... }
--]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local HeistBuilder = {}

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function v3(t) return Vector3.new(t.x, t.y, t.z) end
local C = Constants.COLORS
local W = Constants.WORLD

local function makePart(props)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do
        p[k] = v
    end
    return p
end

local function billboardText(parent, text, color, size, studsAbove)
    local attach = Instance.new("Attachment", parent)
    attach.Position = Vector3.new(0, studsAbove or 4, 0)
    local bb = Instance.new("BillboardGui", attach)
    bb.Size = UDim2.new(0, size or 300, 0, 80)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    local label = Instance.new("TextLabel", bb)
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or rgb(C.WHITE)
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    return label
end

-- ──────────────────────────────────────────────
-- 🌅 LIGHTING + SKYBOX + ATMOSPHERE
-- ──────────────────────────────────────────────
function HeistBuilder:_setupLighting()
    -- Cinematic dusk look
    Lighting.ClockTime = 19.5  -- Just after sunset
    Lighting.GeographicLatitude = 41
    Lighting.Brightness = 1.5
    Lighting.Ambient = Color3.fromRGB(50, 55, 75)
    Lighting.OutdoorAmbient = Color3.fromRGB(85, 90, 110)
    Lighting.ExposureCompensation = 0.2
    Lighting.GlobalShadows = true
    Lighting.FogColor = Color3.fromRGB(35, 40, 60)
    Lighting.FogStart = 200
    Lighting.FogEnd = 800

    -- Clear any existing sky/atmosphere
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("ColorCorrectionEffect") then
            child:Destroy()
        end
    end

    -- Sky (use Roblox built-in night sky)
    local sky = Instance.new("Sky")
    sky.SkyboxBk = "rbxasset://sky/sky512_bk.tex"
    sky.SkyboxDn = "rbxasset://sky/sky512_dn.tex"
    sky.SkyboxFt = "rbxasset://sky/sky512_ft.tex"
    sky.SkyboxLf = "rbxasset://sky/sky512_lf.tex"
    sky.SkyboxRt = "rbxasset://sky/sky512_rt.tex"
    sky.SkyboxUp = "rbxasset://sky/sky512_up.tex"
    sky.StarCount = 3000
    sky.SunAngularSize = 11
    sky.MoonAngularSize = 11
    sky.Parent = Lighting

    -- Atmosphere (haze)
    local atmo = Instance.new("Atmosphere")
    atmo.Density = 0.35
    atmo.Offset = 0.25
    atmo.Color = Color3.fromRGB(199, 199, 199)
    atmo.Decay = Color3.fromRGB(106, 112, 125)
    atmo.Glare = 0.2
    atmo.Haze = 1.5
    atmo.Parent = Lighting

    -- Bloom (cinematic glow)
    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = 0.5
    bloom.Size = 24
    bloom.Threshold = 0.9
    bloom.Parent = Lighting

    -- Color correction (slight teal/orange grade)
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Brightness = 0
    cc.Contrast = 0.15
    cc.Saturation = 0.1
    cc.TintColor = Color3.fromRGB(255, 245, 230)
    cc.Parent = Lighting

    print("[HeistBuilder] Lighting + skybox + atmosphere applied 🌅")
end

-- ──────────────────────────────────────────────
-- 🎵 AMBIENT MUSIC (server plays it via Workspace)
-- ──────────────────────────────────────────────
function HeistBuilder:_setupAmbientMusic()
    -- Remove any old music
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Sound") and child.Name == "AmbientMusic" then
            child:Destroy()
        end
    end

    local music = Instance.new("Sound")
    music.Name = "AmbientMusic"
    music.SoundId = Constants.SOUNDS.LOBBY_AMBIENT
    music.Volume = 0.3
    music.Looped = true
    music.Parent = Workspace
    music:Play()
end

-- ──────────────────────────────────────────────
-- 🌳 GROUND (replace baseplate with grass + concrete plaza)
-- ──────────────────────────────────────────────
function HeistBuilder:_setupGround(folder)
    -- Hide / remove the default Baseplate if present
    local baseplate = Workspace:FindFirstChild("Baseplate")
    if baseplate then baseplate:Destroy() end

    -- Big grass ground plane
    local grass = makePart({
        Name = "Grass",
        Size = Vector3.new(400, 2, 400),
        Position = Vector3.new(0, -1, -30),
        Color = rgb(C.GRASS_GREEN),
        Material = Enum.Material.Grass,
    })
    grass.Parent = folder

    -- Lobby plaza floor (circle approximated by a wide cylinder)
    local plaza = makePart({
        Name = "LobbyPlaza",
        Size = Vector3.new(0.5, W.LOBBY_RADIUS * 2, W.LOBBY_RADIUS * 2),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
        Shape = Enum.PartType.Cylinder,
    })
    plaza.CFrame = CFrame.new(W.LOBBY_CENTER.x, 0.25, W.LOBBY_CENTER.z) * CFrame.Angles(0, 0, math.rad(90))
    plaza.Parent = folder

    -- Gold ring border on plaza edge
    local ring = makePart({
        Name = "PlazaRing",
        Size = Vector3.new(0.6, W.LOBBY_RADIUS * 2, W.LOBBY_RADIUS * 2),
        Color = rgb(C.GOLD),
        Material = Enum.Material.Neon,
        Shape = Enum.PartType.Cylinder,
    })
    ring.CFrame = CFrame.new(W.LOBBY_CENTER.x, 0.55, W.LOBBY_CENTER.z) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = folder

    -- Inner darker plaza disc on top of the ring (so ring shows as a border)
    local inner = makePart({
        Name = "PlazaInner",
        Size = Vector3.new(0.3, (W.LOBBY_RADIUS - 1.5) * 2, (W.LOBBY_RADIUS - 1.5) * 2),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
        Shape = Enum.PartType.Cylinder,
    })
    inner.CFrame = CFrame.new(W.LOBBY_CENTER.x, 0.7, W.LOBBY_CENTER.z) * CFrame.Angles(0, 0, math.rad(90))
    inner.Parent = folder
end

-- ──────────────────────────────────────────────
-- 🏙 LOBBY: pedestal sign + lamp posts + tutorial + boss
-- ──────────────────────────────────────────────
function HeistBuilder:_buildLobby(folder)
    -- Center pedestal with the giant "HEIST CREW" sign
    local pedestal = makePart({
        Name = "LobbyPedestal",
        Size = Vector3.new(6, 6, 6),
        Position = Vector3.new(W.LOBBY_CENTER.x, 3, W.LOBBY_CENTER.z),
        Color = rgb(C.MARBLE_DARK),
        Material = Enum.Material.Marble,
    })
    pedestal.Parent = folder

    -- Top neon block
    local pedestalCap = makePart({
        Name = "PedestalCap",
        Size = Vector3.new(7, 0.5, 7),
        Position = Vector3.new(W.LOBBY_CENTER.x, 6.5, W.LOBBY_CENTER.z),
        Color = rgb(C.GOLD),
        Material = Enum.Material.Neon,
    })
    pedestalCap.Parent = folder

    -- "HEIST CREW" billboard floating above pedestal
    billboardText(pedestalCap, "💰 HEIST CREW 💰", rgb(C.GOLD), 600, 6)

    -- Subtitle
    local subAttach = Instance.new("Attachment", pedestalCap)
    subAttach.Position = Vector3.new(0, 3, 0)
    local subBb = Instance.new("BillboardGui", subAttach)
    subBb.Size = UDim2.new(0, 480, 0, 50)
    subBb.AlwaysOnTop = true
    subBb.LightInfluence = 0
    local subLabel = Instance.new("TextLabel", subBb)
    subLabel.Size = UDim2.new(1, 0, 1, 0)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "Crack the vault. Escape the guards. Get paid."
    subLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    subLabel.Font = Enum.Font.GothamBold
    subLabel.TextScaled = true
    subLabel.TextStrokeTransparency = 0
    subLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

    -- 4 lamp posts at compass points around plaza
    local lampOffsets = {
        Vector3.new( W.LOBBY_RADIUS - 2, 0,  0),
        Vector3.new(-W.LOBBY_RADIUS + 2, 0,  0),
        Vector3.new( 0, 0,  W.LOBBY_RADIUS - 2),
        Vector3.new( 0, 0, -W.LOBBY_RADIUS + 2),
    }
    for i, offset in ipairs(lampOffsets) do
        local pos = Vector3.new(W.LOBBY_CENTER.x, 0, W.LOBBY_CENTER.z) + offset
        local pole = makePart({
            Name = "LampPole_" .. i,
            Size = Vector3.new(0.6, 10, 0.6),
            Position = pos + Vector3.new(0, 5, 0),
            Color = rgb(C.MARBLE_DARK),
            Material = Enum.Material.Metal,
        })
        pole.Parent = folder
        local bulb = makePart({
            Name = "LampBulb_" .. i,
            Size = Vector3.new(1.5, 1.5, 1.5),
            Position = pos + Vector3.new(0, 10.3, 0),
            Color = rgb(C.GOLD),
            Material = Enum.Material.Neon,
            Shape = Enum.PartType.Ball,
        })
        bulb.Parent = folder
        local light = Instance.new("PointLight", bulb)
        light.Brightness = 3
        light.Range = 25
        light.Color = Color3.fromRGB(255, 220, 150)
    end

    -- Tutorial billboard ("How to Play")
    local board = makePart({
        Name = "TutorialBoard",
        Size = Vector3.new(0.5, 7, 8),
        Position = v3(W.TUTORIAL_BOARD_POS) + Vector3.new(0, 4, 0),
        Color = rgb(C.MARBLE_DARK),
        Material = Enum.Material.Wood,
        Orientation = Vector3.new(0, 30, 0),
    })
    board.Parent = folder

    local boardSurface = Instance.new("SurfaceGui", board)
    boardSurface.Face = Enum.NormalId.Right
    boardSurface.LightInfluence = 0
    boardSurface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    boardSurface.PixelsPerStud = 60

    local boardBg = Instance.new("Frame", boardSurface)
    boardBg.Size = UDim2.new(1, 0, 1, 0)
    boardBg.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    boardBg.BackgroundTransparency = 0.1
    boardBg.BorderSizePixel = 0

    local boardTitle = Instance.new("TextLabel", boardBg)
    boardTitle.Size = UDim2.new(1, 0, 0.2, 0)
    boardTitle.Position = UDim2.new(0, 0, 0.05, 0)
    boardTitle.BackgroundTransparency = 1
    boardTitle.Text = "📋 HOW TO HEIST"
    boardTitle.TextColor3 = rgb(C.GOLD)
    boardTitle.Font = Enum.Font.GothamBlack
    boardTitle.TextScaled = true

    local boardBody = Instance.new("TextLabel", boardBg)
    boardBody.Size = UDim2.new(0.9, 0, 0.7, 0)
    boardBody.Position = UDim2.new(0.05, 0, 0.27, 0)
    boardBody.BackgroundTransparency = 1
    boardBody.Text = "1. Walk to the mansion 🏛\n2. Sneak past guards (yellow cones!)\n3. Hold E on the gold vault\n4. Run to the green getaway car 🚗\n5. Cash in! 💰"
    boardBody.TextColor3 = Color3.fromRGB(255, 255, 255)
    boardBody.Font = Enum.Font.GothamBold
    boardBody.TextScaled = true
    boardBody.TextXAlignment = Enum.TextXAlignment.Left
    boardBody.TextYAlignment = Enum.TextYAlignment.Top

    -- Boss NPC
    self:_buildBoss(folder)

    -- Decorative trees scattered around plaza edge
    self:_buildTrees(folder)
end

-- ──────────────────────────────────────────────
-- 🤵 BOSS NPC (welcome character)
-- ──────────────────────────────────────────────
function HeistBuilder:_buildBoss(folder)
    local pos = v3(W.BOSS_NPC_POS)
    local bossModel = Instance.new("Model")
    bossModel.Name = "Boss_NPC"
    bossModel.Parent = folder

    local body = makePart({
        Name = "Body",
        Size = Vector3.new(2.5, 5, 1.5),
        Position = pos + Vector3.new(0, 2.5, 0),
        Color = Color3.fromRGB(20, 25, 50),
        Material = Enum.Material.Fabric,
        Orientation = Vector3.new(0, 180, 0),
    })
    body.Parent = bossModel

    local tie = makePart({
        Name = "Tie",
        Size = Vector3.new(0.4, 2, 0.1),
        Position = pos + Vector3.new(0, 3.2, -0.78),
        Color = rgb(C.GOLD),
        Material = Enum.Material.Neon,
    })
    tie.Parent = bossModel

    local head = makePart({
        Name = "Head",
        Size = Vector3.new(1.6, 1.6, 1.6),
        Position = pos + Vector3.new(0, 5.8, 0),
        Color = Color3.fromRGB(180, 140, 100),
        Material = Enum.Material.Plastic,
    })
    head.CanCollide = false
    head.Parent = bossModel

    local hat = makePart({
        Name = "Hat",
        Size = Vector3.new(2.2, 0.5, 2.2),
        Position = pos + Vector3.new(0, 6.9, 0),
        Color = Color3.fromRGB(15, 15, 15),
        Material = Enum.Material.Fabric,
    })
    hat.CanCollide = false
    hat.Parent = bossModel

    bossModel.PrimaryPart = body

    -- Speech bubble above his head
    local attach = Instance.new("Attachment", head)
    attach.Position = Vector3.new(0, 2.8, 0)
    local bb = Instance.new("BillboardGui", attach)
    bb.Size = UDim2.new(0, 280, 0, 110)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0

    local bg = Instance.new("Frame", bb)
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    bg.BackgroundTransparency = 0.1
    bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", bg)
    stroke.Color = rgb(C.GOLD)
    stroke.Thickness = 2

    local nameLabel = Instance.new("TextLabel", bg)
    nameLabel.Size = UDim2.new(1, 0, 0.3, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "🤵 THE BOSS"
    nameLabel.TextColor3 = rgb(C.GOLD)
    nameLabel.Font = Enum.Font.GothamBlack
    nameLabel.TextScaled = true

    local lineLabel = Instance.new("TextLabel", bg)
    lineLabel.Size = UDim2.new(0.9, 0, 0.6, 0)
    lineLabel.Position = UDim2.new(0.05, 0, 0.32, 0)
    lineLabel.BackgroundTransparency = 1
    lineLabel.Text = "Crack that vault, kid.\nDon't get caught."
    lineLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    lineLabel.Font = Enum.Font.GothamBold
    lineLabel.TextScaled = true
end

-- ──────────────────────────────────────────────
-- 🌲 DECORATIVE TREES
-- ──────────────────────────────────────────────
function HeistBuilder:_buildTrees(folder)
    local treePositions = {
        Vector3.new(-50, 0, 20),
        Vector3.new( 50, 0, 20),
        Vector3.new(-50, 0, -10),
        Vector3.new( 60, 0, -25),
        Vector3.new(-60, 0, -40),
        Vector3.new( 55, 0, -55),
        Vector3.new(-65, 0, 5),
        Vector3.new( 25, 0, 30),
        Vector3.new(-25, 0, 30),
    }
    for i, pos in ipairs(treePositions) do
        local trunk = makePart({
            Name = "TreeTrunk_" .. i,
            Size = Vector3.new(2, 8, 2),
            Position = pos + Vector3.new(0, 4, 0),
            Color = Color3.fromRGB(80, 50, 25),
            Material = Enum.Material.Wood,
        })
        trunk.Parent = folder
        local leaves = makePart({
            Name = "TreeLeaves_" .. i,
            Size = Vector3.new(7, 7, 7),
            Position = pos + Vector3.new(0, 11, 0),
            Color = Color3.fromRGB(38, 95, 45),
            Material = Enum.Material.Grass,
            Shape = Enum.PartType.Ball,
        })
        leaves.Parent = folder
    end
end

-- ──────────────────────────────────────────────
-- 🛣 PATH from lobby to mansion
-- ──────────────────────────────────────────────
function HeistBuilder:_buildPath(folder)
    local startZ = W.PATH_START.z
    local endZ = W.PATH_END.z
    local length = math.abs(endZ - startZ)
    local centerZ = (startZ + endZ) / 2

    local path = makePart({
        Name = "MansionPath",
        Size = Vector3.new(8, 0.4, length),
        Position = Vector3.new(0, 0.2, centerZ),
        Color = rgb(C.PATH_STONE),
        Material = Enum.Material.Slate,
    })
    path.Parent = folder

    for _, xOffset in ipairs({-4.2, 4.2}) do
        local edge = makePart({
            Name = "PathEdge",
            Size = Vector3.new(0.4, 0.5, length),
            Position = Vector3.new(xOffset, 0.5, centerZ),
            Color = rgb(C.GOLD),
            Material = Enum.Material.Neon,
        })
        edge.Parent = folder
    end

    for _, xOffset in ipairs({-6, 6}) do
        local pos = Vector3.new(xOffset, 0, centerZ)
        local pole = makePart({
            Name = "PathLamp_Pole",
            Size = Vector3.new(0.5, 9, 0.5),
            Position = pos + Vector3.new(0, 4.5, 0),
            Color = rgb(C.MARBLE_DARK),
            Material = Enum.Material.Metal,
        })
        pole.Parent = folder
        local bulb = makePart({
            Name = "PathLamp_Bulb",
            Size = Vector3.new(1.2, 1.2, 1.2),
            Position = pos + Vector3.new(0, 9.2, 0),
            Color = rgb(C.GOLD),
            Material = Enum.Material.Neon,
            Shape = Enum.PartType.Ball,
        })
        bulb.Parent = folder
        local light = Instance.new("PointLight", bulb)
        light.Brightness = 2.5
        light.Range = 20
        light.Color = Color3.fromRGB(255, 220, 150)
    end
end

-- ──────────────────────────────────────────────
-- 🏛 MANSION (the heist target)
-- ──────────────────────────────────────────────
function HeistBuilder:_buildMansion(folder)
    local mansionFolder = Instance.new("Folder")
    mansionFolder.Name = "Mansion"
    mansionFolder.Parent = folder

    local cx = W.MANSION_CENTER.x
    local cz = W.MANSION_CENTER.z
    local hw = W.MANSION_HALF_WIDTH
    local hd = W.MANSION_HALF_DEPTH
    local h  = W.MANSION_WALL_HEIGHT
    local doorW = W.MANSION_DOOR_WIDTH

    -- Floor (marble tile)
    local floor = makePart({
        Name = "MansionFloor",
        Size = Vector3.new(hw * 2, 0.5, hd * 2),
        Position = Vector3.new(cx, 0.25, cz),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    floor.Parent = mansionFolder

    -- Red carpet runner from entrance to vault
    local carpet = makePart({
        Name = "Carpet",
        Size = Vector3.new(6, 0.6, hd * 2 - 2),
        Position = Vector3.new(cx, 0.5, cz),
        Color = rgb(C.CARPET_RED),
        Material = Enum.Material.Fabric,
    })
    carpet.Parent = mansionFolder

    -- Back wall (north — solid, has the vault embedded)
    local backWall = makePart({
        Name = "BackWall",
        Size = Vector3.new(hw * 2, h, 1),
        Position = Vector3.new(cx, h / 2, cz - hd),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    backWall.Parent = mansionFolder

    -- Side walls
    local leftWall = makePart({
        Name = "LeftWall",
        Size = Vector3.new(1, h, hd * 2),
        Position = Vector3.new(cx - hw, h / 2, cz),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    leftWall.Parent = mansionFolder

    local rightWall = makePart({
        Name = "RightWall",
        Size = Vector3.new(1, h, hd * 2),
        Position = Vector3.new(cx + hw, h / 2, cz),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    rightWall.Parent = mansionFolder

    -- Front wall (south) — split around the doorway
    local sideWidth = (hw * 2 - doorW) / 2
    local frontLeft = makePart({
        Name = "FrontLeft",
        Size = Vector3.new(sideWidth, h, 1),
        Position = Vector3.new(cx - (doorW / 2 + sideWidth / 2), h / 2, cz + hd),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    frontLeft.Parent = mansionFolder

    local frontRight = makePart({
        Name = "FrontRight",
        Size = Vector3.new(sideWidth, h, 1),
        Position = Vector3.new(cx + (doorW / 2 + sideWidth / 2), h / 2, cz + hd),
        Color = rgb(C.MARBLE_WHITE),
        Material = Enum.Material.Marble,
    })
    frontRight.Parent = mansionFolder

    -- Archway header (top of doorway)
    local archHeader = makePart({
        Name = "ArchHeader",
        Size = Vector3.new(doorW + 4, 3, 1),
        Position = Vector3.new(cx, h - 1.5, cz + hd),
        Color = rgb(C.GOLD_DEEP),
        Material = Enum.Material.Marble,
    })
    archHeader.Parent = mansionFolder

    -- Pillars at corners
    local pillarOffsets = {
        Vector3.new( hw - 1.5, 0,  hd - 1.5),
        Vector3.new(-hw + 1.5, 0,  hd - 1.5),
        Vector3.new( hw - 1.5, 0, -hd + 1.5),
        Vector3.new(-hw + 1.5, 0, -hd + 1.5),
    }
    for i, offset in ipairs(pillarOffsets) do
        local p = Vector3.new(cx, 0, cz) + offset
        local pillar = makePart({
            Name = "Pillar_" .. i,
            Size = Vector3.new(h + 1, 2.5, 2.5),
            Color = rgb(C.MARBLE_WHITE),
            Material = Enum.Material.Marble,
            Shape = Enum.PartType.Cylinder,
        })
        pillar.CFrame = CFrame.new(p + Vector3.new(0, (h + 1) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
        pillar.Parent = mansionFolder

        -- Gold cap on top
        local cap = makePart({
            Name = "PillarCap_" .. i,
            Size = Vector3.new(0.5, 3.2, 3.2),
            Color = rgb(C.GOLD),
            Material = Enum.Material.Neon,
            Shape = Enum.PartType.Cylinder,
        })
        cap.CFrame = CFrame.new(p + Vector3.new(0, h + 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
        cap.Parent = mansionFolder
    end

    -- Roof (slate, slightly overhanging)
    local roof = makePart({
        Name = "Roof",
        Size = Vector3.new(hw * 2 + 4, 1, hd * 2 + 4),
        Position = Vector3.new(cx, h + 0.5, cz),
        Color = rgb(C.MARBLE_DARK),
        Material = Enum.Material.Slate,
    })
    roof.Parent = mansionFolder

    -- Roof trim
    local roofTrim = makePart({
        Name = "RoofTrim",
        Size = Vector3.new(hw * 2 + 5, 0.4, hd * 2 + 5),
        Position = Vector3.new(cx, h + 1.2, cz),
        Color = rgb(C.GOLD),
        Material = Enum.Material.Neon,
    })
    roofTrim.Parent = mansionFolder

    -- "MANSION" sign above the door
    billboardText(archHeader, "🏛 MANSION HEIST", rgb(C.GOLD), 500, 4)

    -- Interior lights
    for _, lightPos in ipairs({
        Vector3.new(cx - 8, h - 3, cz - 4),
        Vector3.new(cx + 8, h - 3, cz - 4),
        Vector3.new(cx - 8, h - 3, cz + 8),
        Vector3.new(cx + 8, h - 3, cz + 8),
    }) do
        local lightBulb = makePart({
            Name = "InteriorLight",
            Size = Vector3.new(0.8, 0.8, 0.8),
            Position = lightPos,
            Color = rgb(C.GOLD),
            Material = Enum.Material.Neon,
            Shape = Enum.PartType.Ball,
        })
        lightBulb.CanCollide = false
        lightBulb.Parent = mansionFolder
        local pl = Instance.new("PointLight", lightBulb)
        pl.Brightness = 2
        pl.Range = 18
        pl.Color = Color3.fromRGB(255, 220, 150)
    end

    -- Decorative wall paintings
    local paintingColors = {
        Color3.fromRGB(150, 50, 50),
        Color3.fromRGB(50, 100, 150),
        Color3.fromRGB(200, 180, 60),
    }
    for i, paintColor in ipairs(paintingColors) do
        local x = cx - hw + 0.6
        local z = cz + (i - 2) * 8
        local frame = makePart({
            Name = "Painting_" .. i,
            Size = Vector3.new(0.3, 4, 5),
            Position = Vector3.new(x, h / 2, z),
            Color = Color3.fromRGB(80, 60, 40),
            Material = Enum.Material.Wood,
        })
        frame.Parent = mansionFolder
        local canvas = makePart({
            Name = "PaintingCanvas_" .. i,
            Size = Vector3.new(0.1, 3.4, 4.4),
            Position = Vector3.new(x + 0.15, h / 2, z),
            Color = paintColor,
            Material = Enum.Material.SmoothPlastic,
        })
        canvas.Parent = mansionFolder
    end

    return mansionFolder
end

-- ──────────────────────────────────────────────
-- 💰 VAULT
-- ──────────────────────────────────────────────
function HeistBuilder:_buildVault(folder)
    local vp = v3(W.MANSION_VAULT)

    local vault = makePart({
        Name = "Vault",
        Size = Vector3.new(8, 10, 4),
        Position = vp,
        Color = rgb(C.GOLD),
        Material = Enum.Material.DiamondPlate,
    })
    vault.Parent = folder

    local pl = Instance.new("PointLight", vault)
    pl.Brightness = 4
    pl.Range = 25
    pl.Color = Color3.fromRGB(255, 220, 100)

    -- Decorative jewels stacked on top
    local jewelColors = {
        Color3.fromRGB(255, 50, 50),    -- ruby
        Color3.fromRGB(50, 200, 100),   -- emerald
        Color3.fromRGB(80, 150, 255),   -- sapphire
    }
    for i, col in ipairs(jewelColors) do
        local jewel = makePart({
            Name = "Jewel_" .. i,
            Size = Vector3.new(1.2, 1.2, 1.2),
            Position = vp + Vector3.new((i - 2) * 2.5, 6, 0),
            Color = col,
            Material = Enum.Material.Neon,
            Shape = Enum.PartType.Ball,
        })
        jewel.Parent = folder
    end

    billboardText(vault, "💰 VAULT", rgb(C.GOLD), 350, 8)

    return vault
end

-- ──────────────────────────────────────────────
-- 🚗 GETAWAY CAR
-- ──────────────────────────────────────────────
function HeistBuilder:_buildGetawayCar(folder)
    local gp = v3(W.GETAWAY_POSITION)

    local body = makePart({
        Name = "GetawayCar",
        Size = Vector3.new(8, 4, 16),
        Position = gp,
        Color = Color3.fromRGB(40, 40, 50),
        Material = Enum.Material.Metal,
    })
    body.Parent = folder

    local roof = makePart({
        Name = "GetawayCarRoof",
        Size = Vector3.new(6, 2.5, 9),
        Position = gp + Vector3.new(0, 3.2, 0),
        Color = Color3.fromRGB(25, 25, 35),
        Material = Enum.Material.Metal,
    })
    roof.Parent = folder

    local windshield = makePart({
        Name = "Windshield",
        Size = Vector3.new(5.8, 2, 0.3),
        Position = gp + Vector3.new(0, 3.2, -4.3),
        Color = Color3.fromRGB(80, 130, 200),
        Material = Enum.Material.Glass,
        Transparency = 0.3,
    })
    windshield.Parent = folder

    local wheelOffsets = {
        Vector3.new( 4.2, -1.5,  5),
        Vector3.new(-4.2, -1.5,  5),
        Vector3.new( 4.2, -1.5, -5),
        Vector3.new(-4.2, -1.5, -5),
    }
    for i, offset in ipairs(wheelOffsets) do
        local wheelPos = gp + offset
        local wheel = makePart({
            Name = "Wheel_" .. i,
            Size = Vector3.new(2.2, 2.5, 2.5),
            Position = wheelPos,
            Color = Color3.fromRGB(15, 15, 15),
            Material = Enum.Material.Plastic,
            Shape = Enum.PartType.Cylinder,
        })
        wheel.Parent = folder
    end

    -- Headlights
    for _, xOff in ipairs({-2.5, 2.5}) do
        local headlight = makePart({
            Name = "Headlight",
            Size = Vector3.new(1.2, 1.2, 0.3),
            Position = gp + Vector3.new(xOff, 0.5, 8.1),
            Color = Color3.fromRGB(255, 240, 180),
            Material = Enum.Material.Neon,
        })
        headlight.Parent = folder
        local pl = Instance.new("PointLight", headlight)
        pl.Brightness = 3
        pl.Range = 15
        pl.Color = Color3.fromRGB(255, 240, 180)
    end

    local label = billboardText(body, "🚗 GETAWAY", Color3.fromRGB(120, 120, 120), 350, 6)

    return body, label
end

-- ──────────────────────────────────────────────
-- 🚀 BUILD!
-- ──────────────────────────────────────────────
function HeistBuilder:build()
    -- Clean slate
    local existing = Workspace:FindFirstChild("HeistWorld")
    if existing then existing:Destroy() end

    local heistFolder = Instance.new("Folder")
    heistFolder.Name = "HeistWorld"
    heistFolder.Parent = Workspace

    self:_setupLighting()
    self:_setupAmbientMusic()
    self:_setupGround(heistFolder)
    self:_buildLobby(heistFolder)
    self:_buildPath(heistFolder)
    local mansionFolder = self:_buildMansion(heistFolder)
    local vault = self:_buildVault(heistFolder)
    local getawayCar, getawayLabel = self:_buildGetawayCar(heistFolder)

    -- Move SpawnLocation to lobby plaza (or create if missing — destroyed baseplate may have taken it)
    local spawn = Workspace:FindFirstChild("SpawnLocation")
    if not spawn then
        for _, child in ipairs(Workspace:GetDescendants()) do
            if child:IsA("SpawnLocation") then spawn = child; break end
        end
    end
    if not spawn then
        spawn = Instance.new("SpawnLocation")
        spawn.Name = "SpawnLocation"
    end
    spawn.Anchored = true
    spawn.CanCollide = true
    spawn.Position = Vector3.new(W.SPAWN_POSITION.x, W.SPAWN_POSITION.y, W.SPAWN_POSITION.z)
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Color = rgb(C.GREEN_PRIMARY)
    spawn.Material = Enum.Material.Neon
    spawn.TopSurface = Enum.SurfaceType.Smooth
    spawn.BottomSurface = Enum.SurfaceType.Smooth
    spawn.Transparency = 0.2
    spawn.Parent = heistFolder

    print("[HeistBuilder] World built ✨")
    print(string.format("[HeistBuilder]   Lobby plaza @ (%d, %d, %d)", W.LOBBY_CENTER.x, 0, W.LOBBY_CENTER.z))
    print(string.format("[HeistBuilder]   Mansion centered @ (%d, %d, %d)", W.MANSION_CENTER.x, 0, W.MANSION_CENTER.z))
    print(string.format("[HeistBuilder]   Vault @ (%d, %d, %d)", W.MANSION_VAULT.x, W.MANSION_VAULT.y, W.MANSION_VAULT.z))
    print(string.format("[HeistBuilder]   Getaway car @ (%d, %d, %d)", W.GETAWAY_POSITION.x, W.GETAWAY_POSITION.y, W.GETAWAY_POSITION.z))

    return {
        heistFolder = heistFolder,
        mansionFolder = mansionFolder,
        vault = vault,
        getawayCar = getawayCar,
        getawayLabel = getawayLabel,
    }
end

return HeistBuilder
