--[[
    HEIST CREW — HeistBuilder (world coordinator)
    ────────────────────────────────────────────────
    v1.0 "Neon Miami". Builds the whole world by calling the builders in order:

        MiamiBuilder:applyLighting()      midnight neon lighting (fallback: old dusk)
        SafehouseBuilder:build()          the crew HQ + Ocean Drive
        MiamiBuilder:skinSafehouse()      pastel stucco + neon sign on the HQ
        _buildBoss()                      the Boss at the planning table
        MiamiBuilder:build()              deco hotels, palms, beach, ocean, marina
        VillaBuilder:build()              job 1 — Villa Rosa
        JewelryBuilder:build()            job 2 — Diamond Dolls

    Every builder runs inside pcall: a bug in one of them logs loudly and the
    rest of the world still builds, instead of the whole server dying.
    The old v0.x mansion / vault / box car / round trees / plaza are gone
    (see git history before v1.0 if you ever need them).

    PUBLIC API:
        HeistBuilder:build() -> { heistFolder, safehouse = refs, jobs = { villa = JobRefs, jewelry = JobRefs } }
--]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local NpcFactory = require(script.Parent.NpcFactory)
local SafehouseBuilder = require(script.Parent.SafehouseBuilder)

local HeistBuilder = {}

local W = Constants.WORLD
local function v3(t) return Vector3.new(t.x, t.y, t.z) end

-- optional builders: a missing module must not stop the server
local function optional(name)
    local mod = script.Parent:FindFirstChild(name)
    if not mod then
        warn("[HeistBuilder] " .. name .. " not found — skipping")
        return nil
    end
    local ok, result = pcall(require, mod)
    if not ok then
        warn("[HeistBuilder] " .. name .. " failed to load: " .. tostring(result))
        return nil
    end
    return result
end

local function run(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        warn(string.format("[HeistBuilder] ❌ %s failed: %s", label, tostring(result)))
        return nil
    end
    return result
end

-- ──────────────────────────────────────────────
-- 🌅 FALLBACK LIGHTING (only used if MiamiBuilder is missing)
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
-- 🤵 THE BOSS (inside the safehouse, at the planning table)
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
    -- v0.7.0: stands on the safehouse floor (top at y 0.5) at the planning
    -- table, turned toward the spawn so he's the first face you see.
    local standAt = pos + Vector3.new(0, 0.5 + humanoid.HipHeight + root.Size.Y / 2, 0)
    local spawnPos = v3(W.SPAWN_POSITION)
    bossModel:PivotTo(CFrame.lookAt(standAt, Vector3.new(spawnPos.X, standAt.Y, spawnPos.Z)))
    bossModel.Parent = folder
    NpcFactory.animate(humanoid)
    local head = bossModel:FindFirstChild("Head") or root

    -- Speech bubble above his head
    local attach = Instance.new("Attachment", head)
    attach.Position = Vector3.new(0, 3, 0)
    -- v0.7.0: restyled to match the HUD (UITheme) — smaller, dark glass,
    -- gold name caption, no emoji. Still the one allowed floating bubble.
    local bb = Instance.new("BillboardGui", attach)
    bb.Size = UDim2.fromOffset(250, 78)
    bb.MaxDistance = 36     -- only when you walk up to him, not across the map
    bb.AlwaysOnTop = false
    bb.LightInfluence = 0

    local bg = UITheme.panel({ Size = UDim2.fromScale(1, 1), transparency = 0.12, radius = 14 })
    bg.Parent = bb
    UITheme.caption("The Boss", { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 14),
        TextColor3 = UITheme.C.gold, TextSize = 12 }).Parent = bg
    UITheme.label({ Text = "Crack that vault, kid. Don't get caught.", Position = UDim2.fromOffset(16, 26),
        Size = UDim2.new(1, -32, 0, 42), TextWrapped = true, FontFace = UITheme.F.bold, TextSize = 17,
        TextYAlignment = Enum.TextYAlignment.Top }).Parent = bg
end

-- ──────────────────────────────────────────────
-- 🚀 BUILD!
-- ──────────────────────────────────────────────
function HeistBuilder:build()
    local existing = Workspace:FindFirstChild("HeistWorld")
    if existing then existing:Destroy() end
    local baseplate = Workspace:FindFirstChild("Baseplate")
    if baseplate then baseplate:Destroy() end

    local heistFolder = Instance.new("Folder")
    heistFolder.Name = "HeistWorld"
    heistFolder.Parent = Workspace

    local Miami = optional("MiamiBuilder")
    local Villa = optional("VillaBuilder")
    local Jewelry = optional("JewelryBuilder")

    if Miami and Miami.applyLighting then
        run("Miami lighting", Miami.applyLighting, Miami)
    else
        self:_setupLighting()
    end
    self:_setupAmbientMusic()

    local safehouse = run("Safehouse", SafehouseBuilder.build, SafehouseBuilder, heistFolder) or {}
    if Miami and Miami.skinSafehouse then run("Safehouse skin", Miami.skinSafehouse, Miami, heistFolder) end
    run("Boss", self._buildBoss, self, heistFolder)

    local worldFolder = Instance.new("Folder")
    worldFolder.Name = "Miami"
    worldFolder.Parent = heistFolder
    if Miami and Miami.build then run("Miami world", Miami.build, Miami, worldFolder) end

    local jobs = {}
    if Villa then jobs.villa = run("Villa Rosa", Villa.build, Villa, heistFolder) end
    if Jewelry then jobs.jewelry = run("Diamond Dolls", Jewelry.build, Jewelry, heistFolder) end

    -- Spawn: invisible pad inside the safehouse, facing north toward the table
    local spawn = Workspace:FindFirstChild("SpawnLocation")
    if not spawn then
        for _, child in ipairs(Workspace:GetDescendants()) do
            if child:IsA("SpawnLocation") then spawn = child break end
        end
    end
    if not spawn then
        spawn = Instance.new("SpawnLocation")
        spawn.Name = "SpawnLocation"
    end
    spawn.Anchored = true
    spawn.Size = Vector3.new(6, 0.2, 6)
    spawn.CFrame = CFrame.new(v3(W.SPAWN_POSITION))
    spawn.Transparency = 1
    spawn.CanCollide = false
    spawn.CanTouch = false
    spawn.Material = Enum.Material.SmoothPlastic
    spawn.Parent = heistFolder

    print("[HeistBuilder] World built ✨  jobs:", jobs.villa and "villa" or "-", jobs.jewelry and "jewelry" or "-")
    return { heistFolder = heistFolder, safehouse = safehouse, jobs = jobs }
end

return HeistBuilder
