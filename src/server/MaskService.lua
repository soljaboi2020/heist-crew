--[[
    HEIST CREW — MaskService  (v2.0 "BIGGER", masks agent)
    ────────────────────────────────────────────────
    Malachi: "each mask should do something different". Every mask in
    Constants.MASKS has an `ability` (a POWER). The power is ON while you wear
    the mask in a heist, and OFF in the club.

        Bandit   LUCKY        +10% cash from every bag            (JobService payout)
        Goalie   TOUGH GUY    first guard catch each heist = break free (JobService kickBack)
        Owl      NIGHT VISION shadow zones hide you 2x (not 1.6x)  (GuardService.stealthFactor)
        Kitsune  FOX SPEED    +20% walk speed                     (this file + LootService)
        Pixel    POWER THROW  bags fly twice as far               (LootService throw)
        Catrina  GHOST        cameras take 2x longer to see you   (SecurityService cameras)
        Mystery  SURPRISE!    a random other power each heist, announced at drop-in
        Cyber    HACK CHIP    breaker + keypad hacks 2x faster    (SecurityService prompts)

    WHEN IS A POWER ON?
      ShopService:wearMask(player) → MaskService:activate(player)
      ShopService:removeMask(player) → MaskService:deactivate(player)
      (JobService already calls wearMask when you join a run and removeMask when
      you're out / the run ends, so the power follows the mask exactly.)
      Mystery rolls ONCE per run — on the first activate of the run (that's the
      drop-in: JobService puts masks on right before it fires "launched") — and
      is announced then. It keeps that power even if the mask is re-worn
      mid-run. Rolls are cleared on JobService "finished".
      Tough Guy is once per run (recharged on "launched" and "finished").

    ATTRIBUTES (set on the Player, server-only writes):
      MaskPower  (string)  active ability id, e.g. "foxspeed" (nil = none). For the HUD.
      MaskPowerName (string) e.g. "FOX SPEED"  · MaskPowerDesc (string) kid words.
      SpeedMult  (number)  WalkSpeed multiplier (1.2 for FOX SPEED, nil otherwise).
                 LootService multiplies its bag / no-bag speeds by it.

    FOX SPEED vs FeelService crouch: we just write Humanoid.WalkSpeed. While you
    crouch, FeelService treats any write as the new "real" speed (PreCrouchSpeed)
    and keeps the live value capped at 8, so standing up lands on the fast speed.
    Crouching is NOT faster with Fox Speed (the cap wins) — on purpose.

    Other files use it through a tiny guarded lookup (never a hard require):
        local mod = script.Parent:FindFirstChild("MaskService")
        local ok, MS = pcall(require, mod) ; if ok and MS:has(p, "ghost") then ...

    PUBLIC API:
        MaskService:init({ shop = ShopService, notify = fn?, feel = FeelService?, jobService = JobService? })
        MaskService:has(player, abilityId) -> bool       -- power is ON right now
        MaskService:activeAbility(player) -> id | nil
        MaskService:abilityInfo(id) -> { id, name, desc } | nil
        MaskService:activate(player) / :deactivate(player)   -- ShopService calls these
        MaskService:useToughGuy(player) -> bool           -- true once per run (consumes it)
        MaskService:newRun()                              -- clears Mystery rolls + Tough Guy
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MaskService = {}

local P = Constants.MASK_POWERS or {}
local FOX = P.FOX_SPEED or 1.2
local BASE_SPEED = 16

local Shop, Feel = nil, nil
local notify = function() end

local ABILITY = {}        -- abilityId -> { id, name, desc }
local MASK_ABILITY = {}   -- maskId -> abilityId
local MYSTERY_POOL = {}   -- every ability except "surprise"
for _, m in ipairs(Constants.MASKS or {}) do
    local a = m.ability
    if a and a.id then
        ABILITY[a.id] = a
        MASK_ABILITY[m.id] = a.id
        if a.id ~= "surprise" then table.insert(MYSTERY_POOL, a.id) end
    end
end

local active = {}         -- [player] = abilityId (the RESOLVED power, never "surprise")
local mysteryRoll = {}    -- [player] = abilityId rolled for this run
local toughUsed = {}      -- [player] = true once Tough Guy saved them this run
local speedApplied = {}   -- [player] = multiplier we applied to the humanoid

-- ── helpers ──────────────────────────────────────────────────────────
local function equippedMask(player)
    if Shop and type(Shop.getEquippedMask) == "function" then
        local ok, id = pcall(Shop.getEquippedMask, Shop, player)
        if ok and id then return id end
    end
    return player:GetAttribute("Mask") or "Bandit"
end

local function hasSneakers(player)
    if Shop and type(Shop.hasGear) == "function" then
        local ok, r = pcall(Shop.hasGear, Shop, player, "Sneakers")
        return ok and r == true
    end
    return false
end

local function humOf(player)
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function banner(player, text)
    if Feel and type(Feel.big) == "function" then
        pcall(Feel.big, Feel, text, { player = player, color = "gold", sound = "pickup" })
    end
end

-- Fox Speed: set/clear the SpeedMult attribute and fix the live WalkSpeed.
-- Carrying a bag: LootService owns the number; we scale what's there.
local function applySpeed(player, mult)
    local prev = speedApplied[player] or 1
    player:SetAttribute("SpeedMult", mult ~= 1 and mult or nil)
    speedApplied[player] = mult ~= 1 and mult or nil
    local hum = humOf(player)
    if not hum or hum.Health <= 0 then return end
    if player:GetAttribute("CarryingLoot") then
        if prev ~= mult and prev > 0 then hum.WalkSpeed = hum.WalkSpeed / prev * mult end
    else
        hum.WalkSpeed = (BASE_SPEED + (hasSneakers(player) and 2 or 0)) * mult
    end
end

local function setPower(player, id)
    active[player] = id
    local a = id and ABILITY[id]
    player:SetAttribute("MaskPower", id)
    player:SetAttribute("MaskPowerName", a and a.name or nil)
    player:SetAttribute("MaskPowerDesc", a and a.desc or nil)
    local wantMult = (id == "foxspeed") and FOX or 1
    if (speedApplied[player] or 1) ~= wantMult then applySpeed(player, wantMult) end
end

local function rollMystery(player, announce)
    if #MYSTERY_POOL == 0 then return nil end
    local id = MYSTERY_POOL[math.random(1, #MYSTERY_POOL)]
    mysteryRoll[player] = id
    if announce then
        local a = ABILITY[id]
        notify(player, string.format("SURPRISE! Your mask power this heist: %s (%s)", a.name, a.desc), "gold", 6)
        banner(player, "SURPRISE! " .. a.name)
    end
    return id
end

-- ── public ───────────────────────────────────────────────────────────
function MaskService:abilityInfo(id)
    return id and ABILITY[id] or nil
end

function MaskService:activeAbility(player)
    return player and active[player] or nil
end

function MaskService:has(player, abilityId)
    return player ~= nil and abilityId ~= nil and active[player] == abilityId
end

function MaskService:activate(player)
    if not player or not player.Parent then return end
    local id = MASK_ABILITY[equippedMask(player)]
    local announce = active[player] ~= id
    if id == "surprise" then
        announce = false   -- rollMystery announces its own pick
        id = mysteryRoll[player] or rollMystery(player, true)
    end
    setPower(player, id)
    local a = id and ABILITY[id]
    if announce and a and mysteryRoll[player] then   -- (v3.1) role card shows the power; toast only for SURPRISE!
        notify(player, string.format("Mask power: %s (%s)", a.name, a.desc), "gold", 5)
    end
end

function MaskService:deactivate(player)
    if not player then return end
    if active[player] == nil and not speedApplied[player] then return end
    setPower(player, nil)
end

function MaskService:useToughGuy(player)
    if not self:has(player, "toughguy") or toughUsed[player] then return false end
    toughUsed[player] = true
    notify(player, "TOUGH GUY! You broke free from the guard! (only once per heist)", "gold", 4)
    banner(player, "TOUGH GUY! You broke free!")
    return true
end

function MaskService:newRun()
    mysteryRoll = {}
    toughUsed = {}
end

function MaskService:init(deps)
    deps = deps or {}
    Shop = deps.shop or Shop
    Feel = deps.feel or Feel
    notify = deps.notify or notify

    local Job = deps.jobService
    if not Job then
        local mod = script.Parent:FindFirstChild("JobService")
        if mod then
            local ok, r = pcall(require, mod)
            if ok and type(r) == "table" then Job = r end
        end
    end
    if Job and type(Job.subscribe) == "function" then
        Job:subscribe("launched", function()
            -- fresh run: Tough Guy recharged. (Mystery was already rolled +
            -- announced by activate() when JobService put the masks on.)
            toughUsed = {}
        end)
        Job:subscribe("finished", function()
            MaskService:newRun()
        end)
    else
        warn("[MaskService] JobService not found — Mystery rolls on first wear, Tough Guy resets never")
    end

    local function hook(player)
        player.CharacterAdded:Connect(function()
            -- new body: init.server / LootService reset WalkSpeed; re-apply ours after them
            speedApplied[player] = nil
            player:SetAttribute("SpeedMult", nil)
            if active[player] == "foxspeed" then
                task.delay(0.8, function()
                    if player.Parent and active[player] == "foxspeed" then applySpeed(player, FOX) end
                end)
            end
        end)
    end
    Players.PlayerAdded:Connect(hook)
    for _, p in ipairs(Players:GetPlayers()) do hook(p) end
    Players.PlayerRemoving:Connect(function(p)
        active[p], mysteryRoll[p], toughUsed[p], speedApplied[p] = nil, nil, nil, nil
    end)
    print("[MaskService] mask powers online 🎭")
end

return MaskService
