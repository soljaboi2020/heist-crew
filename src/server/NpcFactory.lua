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
        NpcFactory.animate(humanoid) -> controller
            Hooks Humanoid.Running so idle / walk / run switch automatically.
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
    else
        applyColors(desc, spec.bodyColors)
    end
    -- An outfit carries its own colours; only override when we asked for them
    -- and there is no outfit (otherwise we'd paint over the uniform).
    if not spec.outfitId then applyColors(desc, spec.bodyColors) end
    return desc
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
