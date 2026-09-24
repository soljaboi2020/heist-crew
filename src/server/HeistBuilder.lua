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
local NpcFactory = require(script.Parent.NpcFactory)

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
    -- 2026-09-24: Ambient is what reaches places the sky can't (under the
    -- mansion roof). Pulled way down so the interior is dark and the lamps +
    -- guard flashlights do the lighting. OutdoorAmbient keeps the lobby bright.
    -- Lighting.Technology = Future is set in default.project.json (it can't be
    -- set from a script).
    Lighting.Ambient = Color3.fromRGB(22, 24, 34)
    Lighting.OutdoorAmbient = Color3.fromRGB(85, 90, 110)
    Lighting.ExposureCompensation = 0.2
    Lighting.GlobalShadows = true
    Lighting.EnvironmentDiffuseScale = 0.4
    Lighting.EnvironmentSpecularScale = 0.6
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

    -- Bloom — v0.5.0: was Intensity 0.5 / Threshold 0.9, which caught every gold
    -- surface in the level and smeared the whole frame yellow. Now it only blooms
    -- things that are genuinely brighter than white, so it reads as a glow on the
    -- lamps and the vault instead of a haze over everything.
    local bloom = Instance.new("BloomEffect")
    bloom.Intensity = 0.15
    bloom.Size = 18
    bloom.Threshold = 1.1
    bloom.Parent = Lighting

    -- Color correction — pulled the saturation boost back. Combined with the gold
    -- palette it was pushing everything toward the same yellow.
    local cc = Instance.new("ColorCorrectionEffect")
    cc.Brightness = 0.02
    cc.Contrast = 0.12
    cc.Saturation = -0.02
    cc.TintColor = Color3.fromRGB(255, 248, 240)
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

    -- ── Gold trim ring ──────────────────────────────────────────────
    -- v0.5.0 REWRITE. This used to be a 56-stud-wide SOLID Neon cylinder with the
    -- marble inner disc sitting at the SAME top height (0.85). Two problems:
    -- the discs z-fought, and a neon surface that size is fully emissive, so it
    -- lit the whole scene yellow and flattened everything. (Visible in Malachi's
    -- 2026-09-22 screenshot — the entire plaza read as one glowing blob.)
    --
    -- Now it's an actual ring: 64 small Metal segments laid around the edge.
    -- Metal, not Neon — it catches the lamp light and reads as inlaid brass
    -- instead of emitting its own. No overlap, so nothing z-fights.
    local SEGMENTS = 64
    local trimRadius = W.LOBBY_RADIUS - 1.2
    local segLength = (2 * math.pi * trimRadius) / SEGMENTS + 0.15  -- slight overlap closes the seams
    for i = 1, SEGMENTS do
        local angle = (i / SEGMENTS) * math.pi * 2
        local seg = makePart({
            Name = "PlazaTrim_" .. i,
            Size = Vector3.new(segLength, 0.22, 1.1),
            Color = rgb(C.GOLD_DEEP),
            Material = Enum.Material.Metal,
        })
        seg.CFrame = CFrame.new(
            W.LOBBY_CENTER.x + math.cos(angle) * trimRadius,
            0.58,
            W.LOBBY_CENTER.z + math.sin(angle) * trimRadius
        ) * CFrame.Angles(0, -angle, 0)
        seg.Parent = folder
    end

    -- Darker inlay disc in the middle of the plaza. Sits BELOW the trim height so
    -- the two never share a plane.
    local inner = makePart({
        Name = "PlazaInner",
        Size = Vector3.new(0.3, (W.LOBBY_RADIUS - 3) * 2, (W.LOBBY_RADIUS - 3) * 2),
        Color = Color3.fromRGB(196, 190, 178),
        Material = Enum.Material.Marble,
        Shape = Enum.PartType.Cylinder,
    })
    inner.CFrame = CFrame.new(W.LOBBY_CENTER.x, 0.52, W.LOBBY_CENTER.z) * CFrame.Angles(0, 0, math.rad(90))
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

    -- Brass cap. Was Neon — one more emissive surface feeding the yellow wash.
    local pedestalCap = makePart({
        Name = "PedestalCap",
        Size = Vector3.new(7, 0.5, 7),
        Position = Vector3.new(W.LOBBY_CENTER.x, 6.5, W.LOBBY_CENTER.z),
        Color = rgb(C.GOLD_DEEP),
        Material = Enum.Material.Metal,
    })
    pedestalCap.Parent = folder

    -- ── Signage ─────────────────────────────────────────────────────
    -- v0.5.0: the two floating BillboardGuis that used to live here ("💰 HEIST
    -- CREW 💰" at 600px and the subtitle) are GONE. Between them, the mansion
    -- sign, the vault sign and the boss bubble, Malachi's screenshot had five
    -- pieces of text hovering in midair at once, overlapping each other.
    -- Jailbreak / Flood Escape 2 / Steal a Brainrot all put text on SURFACES and
    -- keep the rest on the screen HUD, so that's what this does now: the title
    -- is printed on the pedestal itself, on all four faces so it reads from any
    -- approach angle.
    for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}) do
        local sg = Instance.new("SurfaceGui", pedestal)
        sg.Face = face
        sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        sg.PixelsPerStud = 50
        sg.LightInfluence = 0.25

        local title = Instance.new("TextLabel", sg)
        title.Size = UDim2.new(1, 0, 0.42, 0)
        title.Position = UDim2.new(0, 0, 0.16, 0)
        title.BackgroundTransparency = 1
        title.Text = "HEIST CREW"
        title.TextColor3 = rgb(C.GOLD)
        title.Font = Enum.Font.GothamBlack
        title.TextScaled = true

        local sub = Instance.new("TextLabel", sg)
        sub.Size = UDim2.new(0.86, 0, 0.16, 0)
        sub.Position = UDim2.new(0.07, 0, 0.58, 0)
        sub.BackgroundTransparency = 1
        sub.Text = "CRACK IT. RUN. GET PAID."
        sub.TextColor3 = Color3.fromRGB(225, 220, 210)
        sub.Font = Enum.Font.GothamMedium
        sub.TextScaled = true
    end

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
        -- v0.5.0: was Brightness 3 / Range 25 on four lamps at once, which flooded
        -- the plaza and killed every shadow. Dimmer and tighter gives pools of
        -- light with dark between them — the thing that makes Cheese Escape and
        -- Jailbreak's night side read as lit rather than washed out.
        local light = Instance.new("PointLight", bulb)
        light.Brightness = 1.4
        light.Range = 17
        light.Color = Color3.fromRGB(255, 214, 160)
        light.Shadows = true
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

    -- 2026-09-24: a real R15 avatar in a suit + fedora (NpcFactory), standing
    -- with an idle animation. Used to be a navy brick with a neon tie.
    local bossModel, humanoid, root = NpcFactory.build({
        name = "Boss_NPC",
        shirt = 6554200369,     -- "Grey Suit w/ Black Vest [+]"
        pants = 6555797786,     -- "Grey Suit w/ Black Vest [-]"
        hats = { 168167624 },   -- "Fedora and Shades" (Roblox)
        bodyColors = {
            head  = Color3.fromRGB(180, 140, 100),
            torso = Color3.fromRGB(20, 25, 50),
            arms  = Color3.fromRGB(20, 25, 50),
            legs  = Color3.fromRGB(15, 15, 20),
        },
    })
    if not bossModel then
        warn("[HeistBuilder] Boss NPC failed to build — skipping")
        return
    end
    root.Anchored = true    -- he stands still; anchoring stops players shoving him
    bossModel:PivotTo(CFrame.new(pos + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0))
        * CFrame.Angles(0, math.rad(180), 0))
    bossModel.Parent = folder
    NpcFactory.animate(humanoid)
    local head = bossModel:FindFirstChild("Head") or root

    -- Speech bubble above his head
    local attach = Instance.new("Attachment", head)
    attach.Position = Vector3.new(0, 3, 0)
    local bb = Instance.new("BillboardGui", attach)
    bb.Size = UDim2.new(0, 280, 0, 110)
    bb.MaxDistance = 40     -- only when you walk up to him, not across the map
    bb.AlwaysOnTop = false
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

    -- Path edging. v0.5.0: these were full-length GOLD NEON strips running the
    -- whole walkway — two more big emissive surfaces in the same frame as the
    -- plaza. Now they're brass kerb stones, and the glow comes from the path
    -- lamps instead. Light should come from light sources, not from the floor.
    for _, xOffset in ipairs({-4.2, 4.2}) do
        local edge = makePart({
            Name = "PathEdge",
            Size = Vector3.new(0.5, 0.35, length),
            Position = Vector3.new(xOffset, 0.45, centerZ),
            Color = rgb(C.GOLD_DEEP),
            Material = Enum.Material.Metal,
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
            Material = Enum.Material.Metal,   -- was Neon (art rule #1)
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
        Material = Enum.Material.Metal,   -- was Neon: a 49x41 glowing slab (art rule #1)
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
        pl.Brightness = 1.2
        pl.Range = 14
        pl.Shadows = true   -- Future lighting: pools of light, dark between them
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
    spawn.Material = Enum.Material.Metal   -- was see-through Neon (art rule #1)
    spawn.TopSurface = Enum.SurfaceType.Smooth
    spawn.BottomSurface = Enum.SurfaceType.Smooth
    spawn.Transparency = 0
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
