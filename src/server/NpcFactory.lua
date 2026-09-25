--[[
    HEIST CREW — NpcFactory
    ────────────────────────────────────────────────
    Builds REAL Roblox avatars for NPCs (guards, the Boss) instead of stacking
    boxes. Added 2026-09-24 — the old guards were a 2.5x5 brick + a cube head
    sliding around on a tween, the single biggest "cheap game" tell in the game.

    HOW:
      Players:GetHumanoidDescriptionFromOutfitId / HumanoidDescription
        -> Players:CreateHumanoidModelFromDescription (R15)
      then plays Roblox's default R15 idle / walk / run animations on the
      server-side Animator, so movement replicates to every client.

    FALLBACK CHAIN (so a deleted catalog item can never break the game):
      1. the requested outfit / catalog items
      2. a plain R15 body in the requested body colours (no catalog assets)
      If even that fails, build() returns nil and the caller decides.

    ASSETS USED — all verified against the live catalog 2026-09-24:
      • Outfit 320998366  "Police Officer Nash"  (official Roblox Rthro bundle 349)
      • Shirt  6554200369 / Pants 6555797786  "Grey Suit w/ Black Vest" (TIX Clothing +, 2021)
      • Hat    168167624  "Fedora and Shades"   (Roblox)

    PUBLIC API:
        NpcFactory.build(spec) -> model, humanoid, rootPart | nil
            spec.name        : string
            spec.outfitId    : number?   (a Roblox outfit id — whole look in one go)
            spec.shirt       : number?   (classic shirt asset id)
            spec.pants       : number?   (classic pants asset id)
            spec.hats        : {number}? (hat accessory ids)
            spec.bodyColors  : { head, torso, arms, legs }  (Color3s, used always as the fallback)
            spec.face        : number?   (face accessory id, e.g. sunglasses)  (v2.0.2)
        NpcFactory.animate(humanoid) -> controller
            Hooks Humanoid.Running so idle / walk / run switch automatically.

    (v2.0.2) CREW OUTFITS — so bots stop looking like bright purple blocks:
        NpcFactory.OUTFITS[name]  = { label, shirt, pants, hats, bodyColors }
        NpcFactory.OUTFIT_ORDER   = { "jacket", "denim", "biker", "hoodie", "plaid", "suit" }
        NpcFactory.SKIN_TONES     = { Color3 × 6 }
        NpcFactory.outfit(name, opts?) -> spec      (ready for NpcFactory.build)
            name        : key of OUTFITS (unknown / nil → "jacket")
            opts.name   : spec.name (default "Crew")
            opts.skin   : Color3 for head (+ arms under short sleeves); or
            opts.skinIndex : 1..#SKIN_TONES
            opts.mask   : hat/mask asset id worn IN ADDITION to the outfit's hat
                          (e.g. Constants.MASKS[1].assetId) — the outfit's own
                          hat is dropped so the two don't clip
            opts.noHat  : true = no hat at all
        NpcFactory.outfitFor(i, opts?) -> spec   i-th crew look (wraps OUTFIT_ORDER;
            skin tone rotates too) — e.g. bot #1, #2 get different looks
        Usage (BotService):
            local spec = NpcFactory.outfitFor(botIndex, { name = "Bot_" .. name, mask = maskId })
            local model, humanoid, root = NpcFactory.build(spec)
        Every shirt / pants / hat id below was checked against the live catalog
        (economy.roblox.com asset details) on 2026-09-25; all Roblox-made and
        free except the TIX suit (already used by the Boss). If an item ever
        disappears, build() falls back to a plain body in the outfit's
        bodyColors — which are dark clothing tones, not neon, on purpose.
--]]

local Players = game:GetService("Players")

local NpcFactory = {}

-- Roblox's stock R15 animations. Owned by Roblox, so any game may play them.
local ANIM = {
    idle = "rbxassetid://507766666",
    walk = "rbxassetid://507777826",
    run  = "rbxassetid://507767714",
}

local function applyColors(desc, colors)
    if not colors then return end
    desc.HeadColor     = colors.head  or desc.HeadColor
    desc.TorsoColor    = colors.torso or desc.TorsoColor
    desc.LeftArmColor  = colors.arms  or desc.LeftArmColor
    desc.RightArmColor = colors.arms  or desc.RightArmColor
    desc.LeftLegColor  = colors.legs  or desc.LeftLegColor
    desc.RightLegColor = colors.legs  or desc.RightLegColor
end

local function buildDescription(spec, plain)
    local desc
    if spec.outfitId and not plain then
        local ok, result = pcall(function()
            return Players:GetHumanoidDescriptionFromOutfitId(spec.outfitId)
        end)
        if ok and result then
            desc = result
        else
            warn("[NpcFactory] outfit", spec.outfitId, "failed:", result)
        end
    end
    desc = desc or Instance.new("HumanoidDescription")

    if not plain then
        if spec.shirt then desc.Shirt = spec.shirt end
        if spec.pants then desc.Pants = spec.pants end
        if spec.hats then
            local ids = {}
            for _, id in ipairs(spec.hats) do table.insert(ids, tostring(id)) end
            desc.HatAccessory = table.concat(ids, ",")
        end
        if spec.face then desc.FaceAccessory = tostring(spec.face) end
    else
        applyColors(desc, spec.bodyColors)
    end
    -- An outfit carries its own colours; only override when we asked for them
    -- and there is no outfit (otherwise we'd paint over the uniform).
    if not spec.outfitId then applyColors(desc, spec.bodyColors) end
    return desc
end

-- ──────────────────────────────────────────────
-- 👕 CREW OUTFITS (v2.0.2)
-- ──────────────────────────────────────────────
local C = Color3.fromRGB

NpcFactory.SKIN_TONES = {
    C(234, 184, 146), C(204, 142, 105), C(160, 106, 72),
    C(124, 82, 56), C(92, 60, 42), C(245, 205, 172),
}

-- Fallback body colours = the outfit's own clothing tones, so even a plain
-- body (catalog down) reads as "a person in dark clothes", never a neon block.
NpcFactory.OUTFITS = {
    jacket = { label = "Black jacket",
        shirt = 382538295,          -- Guitar Tee with Black Jacket (Roblox)
        pants = 382538503,          -- Black Jeans with Sneakers (Roblox)
        hats  = { 81708856 },       -- Robber Beanie (Roblox)
        bodyColors = { torso = C(30, 30, 34), arms = C(30, 30, 34), legs = C(24, 26, 32) } },
    denim = { label = "Denim jacket",
        shirt = 144076436,          -- Grey Striped Shirt with Denim Jacket (Roblox)
        pants = 382537569,          -- Black Jeans (Roblox)
        hats  = { 45178010 },       -- Leather Baseball Cap (Roblox)
        bodyColors = { torso = C(62, 86, 120), arms = C(62, 86, 120), legs = C(26, 28, 34) } },
    biker = { label = "Biker",
        shirt = 144076358,          -- Blue and Black Motorcycle Shirt (Roblox)
        pants = 398633812,          -- Black Jeans with White Shoes (Roblox)
        hats  = { 3756428149 },     -- Black Forehead Sunglasses (Roblox)
        bodyColors = { torso = C(34, 48, 86), arms = C(24, 24, 30), legs = C(24, 26, 32) } },
    hoodie = { label = "Hoodie",
        shirt = 398633584,          -- Denim Jacket with White Hoodie (Roblox)
        pants = 398635338,          -- Ripped Skater Pants (Roblox)
        hats  = { 61886689 },       -- Black Sk8er Beanie with Visor (Roblox)
        bodyColors = { torso = C(70, 96, 130), arms = C(70, 96, 130), legs = C(46, 52, 64) } },
    plaid = { label = "Plaid shirt",
        shirt = 398635081,          -- Blue Plaid Shirt (Roblox)
        pants = 144076760,          -- Dark Green Jeans (Roblox)
        hats  = { 243773374 },      -- Hip Grey Beanie (Roblox)
        bodyColors = { torso = C(48, 70, 120), arms = C(48, 70, 120), legs = C(40, 56, 44) } },
    suit = { label = "The inside man",
        shirt = 6554200369,         -- Grey Suit w/ Black Vest (TIX Clothing +, same as the Boss)
        pants = 6555797786,
        hats  = { 168167624 },      -- Fedora and Shades (Roblox)
        bodyColors = { torso = C(88, 90, 96), arms = C(88, 90, 96), legs = C(70, 72, 78) } },
}
NpcFactory.OUTFIT_ORDER = { "jacket", "denim", "biker", "hoodie", "plaid", "suit" }

function NpcFactory.outfit(name, opts)
    opts = opts or {}
    local o = NpcFactory.OUTFITS[name or ""] or NpcFactory.OUTFITS.jacket
    local skin = opts.skin
        or NpcFactory.SKIN_TONES[((tonumber(opts.skinIndex) or 1) - 1) % #NpcFactory.SKIN_TONES + 1]
    local hats = {}
    if opts.mask then
        table.insert(hats, opts.mask)
    elseif not opts.noHat then
        for _, id in ipairs(o.hats or {}) do table.insert(hats, id) end
    end
    return {
        name = opts.name or "Crew",
        shirt = o.shirt,
        pants = o.pants,
        hats = (#hats > 0) and hats or nil,
        bodyColors = {
            head = skin,
            torso = o.bodyColors.torso,
            arms = o.bodyColors.arms or skin,
            legs = o.bodyColors.legs,
        },
    }
end

function NpcFactory.outfitFor(i, opts)
    i = math.max(1, math.floor(tonumber(i) or 1))
    opts = table.clone(opts or {})
    if opts.skin == nil and opts.skinIndex == nil then opts.skinIndex = i * 2 - 1 end
    local order = NpcFactory.OUTFIT_ORDER
    return NpcFactory.outfit(order[(i - 1) % #order + 1], opts)
end

function NpcFactory.build(spec)
    local model
    for _, plain in ipairs({ false, true }) do
        local ok, result = pcall(function()
            return Players:CreateHumanoidModelFromDescription(
                buildDescription(spec, plain), Enum.HumanoidRigType.R15)
        end)
        if ok and result then
            model = result
            break
        end
        warn(string.format("[NpcFactory] %s: %s build failed (%s)",
            spec.name, plain and "plain" or "catalog", tostring(result)))
    end
    if not model then return nil end

    model.Name = spec.name
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")

    -- No floating name tag / health bar over NPCs (art rule #3: no floating text).
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    -- A guard that trips over a player and lies on the floor is funny exactly once.
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid.BreakJointsOnDeath = false

    -- The generated rig ships the player "Animate" LocalScript, which never runs
    -- on an NPC. Remove it so nothing fights the Animator below.
    local animate = model:FindFirstChild("Animate")
    if animate then animate:Destroy() end

    return model, humanoid, root
end

function NpcFactory.animate(humanoid)
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local tracks = {}
    for key, id in pairs(ANIM) do
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if ok then
            track.Looped = true
            track.Priority = (key == "idle") and Enum.AnimationPriority.Idle
                or Enum.AnimationPriority.Movement
            tracks[key] = track
        else
            warn("[NpcFactory] could not load", key, "animation:", track)
        end
    end

    local current
    local function play(key, speed)
        local track = tracks[key]
        if not track then return end
        if current ~= track then
            if current then current:Stop(0.2) end
            track:Play(0.2)
            current = track
        end
        track:AdjustSpeed(speed or 1)
    end

    play("idle")
    humanoid.Running:Connect(function(speed)
        if speed > 12 then
            play("run", speed / 16)
        elseif speed > 0.5 then
            play("walk", speed / 10)
        else
            play("idle")
        end
    end)

    return { play = play }
end

return NpcFactory
