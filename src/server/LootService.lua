--[[
    HEIST CREW — LootService
    ────────────────────────────────────────────────
    v1.0. Loot you physically carry (the Payday mechanic).

      • Every lootSpot / smashCase of the armed job is a pile with a prompt.
        Taking it puts a DUFFEL BAG on your back: you slow down to the loot's
        speed (Constants.LOOT; Muscle ignores it; Tactical Duffel halves it)
        and your jump drops. One bag at a time.
      • G throws the bag (ThrowBag remote) — it flies, lands, and anyone can
        pick it up. Getting caught drops it where you stood.
      • "Load bag" at the getaway car's trunk moves it into the car. Loaded
        bags only turn into cash when the crew gets away (JobService → the getaway movie).

    Vault loot stays locked (prompts disabled) until JobService opens the vault.

    Callbacks: onEvent(kind, player, data)  kinds: "take", "smash", "load", "throw"
        data = { kind, name, pos (Vector3), value, bot (bot name, for loads a bot made) }
        (+ "full" / "emptyHanded" notices, unchanged)

    v2.0: BOT CREW (BotService) can carry a bag for you — "Give bag" on the bot
    moves your bag onto its back, it walks to the car and loads it. A bot load
    counts EXACTLY like a player load (same `loaded` list, same "load" event).
    Carried bags are passed to CosmeticsService:styleBag(player, bag) if that
    service exists (progression agent), pcall-guarded.

    v2.2 GEAR POWERS (gear agent):
      • BAG TIERS — CosmeticsService:bagTier(player) → { valueMult, scale }.
        A bag is built at the carrier's scale (bigger tiers look bigger) and
        pays at the valueMult of the bag it's IN when it hits the trunk: the
        loader's own bag, or — for a bot load — the bag OWNER's (bots keep your
        bonus). Loaded rows carry { value (with bonus), base, bonus, tier, by }
        so counts().take / the payout include it automatically.
      • WALK SPEED — every speed this file writes is scaled by the player's
        SpeedMult (Fox Speed mask) × TrailSpeedMult (trail) attributes.

    v3.0 "THE SCORE" (LOOT-CORE, docs/V3_SPEC.md §2):
      • SHUFFLE — arm()/reset() run LootShuffle:prepare(refs): only ~60% of each
        pool is out, one JACKPOT room is all-out at x1.5, hidden stashes ~1/20.
        Nothing to wire — every arm/reset is a fresh shuffle.
      • ITEMS — a bag now carries an item { kind, name, base, mult (jackpot),
        integrity (fragile), heavy, fragile, targetKind, contents }.
        LootService:valueOf(bag) = base × jackpot × fragile × bag tier.
      • MINI-GAMES — a spot with `interact` (or a kind with a default interact)
        starts a mini-game on the grabber's screen (RemoteEvent "LootMinigame",
        client LootMinigames.lua). The server checks it took at least
        LOOT_V3.MINIGAMES[game].min seconds (or the 3 s hold-E fallback), that
        you're still next to it, then bags it. Too fast = rejected, try again.
            server → client { op = "start", token, game, title, hint, name, kind, value, min, hold, timeout }
                            { op = "stop", token, reason }        (caught / reset / timed out)
                            { op = "result", token, ok, msg }
            client → server { op = "done", token, mode = "game"|"hold", ok = true }
                            { op = "cancel", token }
      • HEAVY — "Lift together": the first lifter waits, a second player (or a
        crew bot standing close) lifts the other side. Both walk at HEAVY_SPEED,
        tied by a rope beam; either one can load it at the trunk; get too far
        apart and it drops. The Muscle lifts it alone at full speed.
      • FRAGILE — loses 25% per bump (running > 2 s, grabbed/dropped, thrown,
        falling > 6 studs). FeelFX "CRACK!". Crouch-walking (C) is safe.
      • TARGET — loading the job's Boss target calls TargetService:onSecured.
        The +$5,000 is NOT in counts().take — JobService adds
        TargetService:bonusFor(run) (see TargetService).
      • BAG LOOKS — the bag bulges with value and cash bundles poke out.
        (playtest fix 2026-09-25: the carried bag covered half the third-person
        screen.) A bag reads as a backpack/duffel: ~1.9 × 1.3 × 0.9 studs, and
        value + bag tier + heavy together grow it at most ×1.3 (BAG_MAX_GROWTH),
        so the biggest bag is ~2.5 studs wide. It sits snug on the back.
      • Carrier attributes for the HUD (player): CarryingLoot (kind, as before),
        CarryName, CarryValue, CarryHeavy, CarryFragile, CarryIntegrity,
        CarryJackpot, CarryTarget, CarryPartner (the other lifter's name);
        the second lifter gets CarryHelping (item name) + CarryPartner.

    PUBLIC API:
        LootService:init(callbacks, ShopService)
        LootService:arm(jobRefs, opts?) / :disarm() / :reset(opts?)     opts = { seed = number } (tests)
        LootService:setVaultOpen(open)
        LootService:attachTrunk(trunkPart)
        LootService:drop(player)                 -- caught / left / reset (fragile: a bump)
        LootService:counts() -> { total, loaded, allLoaded, take, taken, cases, casesTaken, vault, vaultTaken, open, openTaken,
                                  targetSecured, targetBonus, jackpot }     (take does NOT include targetBonus)
        LootService:getLoaded() -> { {kind, name, value, base, bonus, tier, bot?, by?, target?, jackpot?, integrity} }
        LootService:remaining() -> { {pos, kind, name, isCase, locked, heavy, target} }
        LootService:isCarrying(player) -> bool   -- carrying OR helping lift a heavy one
        LootService:clearLoaded()
        LootService.info(kind) -> { value, speed, color, name, ... }   (never nil; LOOT_DEFAULT fallback)
      v3.0:
        LootService:valueOf(bag, owner?) -> number
            bag = an item table, a bag Part, or a Player (what they carry). The bag
            tier is owner's (or the carrying player's); none = x1.
        LootService:carried(player) -> item | nil      -- (the lifter's item for a helper too)
        LootService:jackpot() -> { pool, name, mult }
      v2.2 gear:
        LootService:refreshWalkSpeed(player)      -- re-apply bag/no-bag speed with every multiplier
        LootService:refreshCarriedBag(player)     -- rebuild the carried bag (new tier size/look)
      v2.0 bots:
        LootService:transferToBot(player, botModel) -> kind | nil   -- player's bag onto the bot
        LootService:botCarrying(botModel) -> kind | nil
        LootService:botLoad(botModel, trunkPart?) -> boolean        -- bot puts its bag in the car
        LootService:dropBot(botModel)                               -- bot despawning: bag falls loose
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local LootShuffle = require(script.Parent.LootShuffle)
local TargetService = require(script.Parent.TargetService)

local LootService = {}
local cb = { onEvent = function() end }
local Shop = nil
local V3 = Constants.LOOT_V3 or {}
local GAMES = V3.MINIGAMES or {}

local refs = nil
local piles = {}          -- { kind, item, visual, prompt, anchor, taken, isVault, isCase, glass, spot, unlocked, busyBy }
local carriers = {}       -- [player] = { kind, item, bag, partner (Player|bot Model|nil), att0, att1, runT, airTop, farT }
local helpers = {}        -- [helper Player] = lifter Player
local botHelpers = {}     -- [bot Model] = lifter Player
local loose = {}          -- thrown/dropped bag parts
local bagItems = setmetatable({}, { __mode = "k" })   -- [bag Part] = item
local loaded = {}         -- rows (see getLoaded)
local lifts = {}          -- [pile|bag] = { first, at, token }
local sessions = {}       -- [player] = { pile, token, t0, game }
local trunkPrompt = nil
local vaultOpen = false
local conns = {}
local runSeed = nil
local depositRng = nil
local sessionToken = 0
local minigameRemote = nil
local notifyRemote = nil

local DEFAULT_SPEED = 16
local botBags = {}        -- [botModel] = { kind, item, bag, owner, tier }
local currentTrunk = nil

local function track(c) table.insert(conns, c) return c end

-- v2.0 mask powers (masks agent): optional MaskService lookup, never a hard require
local maskSvc = nil
local function maskHas(player, abilityId)
    if maskSvc == nil then
        local mod = script.Parent:FindFirstChild("MaskService")
        local ok, r = false, nil
        if mod then ok, r = pcall(require, mod) end
        maskSvc = (ok and type(r) == "table" and type(r.has) == "function") and r or false
    end
    if not maskSvc then return false end
    local ok, yes = pcall(maskSvc.has, maskSvc, player, abilityId)
    return ok and yes == true
end

-- v2.0: any loot kind a builder names pays something (LOOT_DEFAULT), never nil
local function info(kind)
    return Constants.LOOT[kind] or Constants.LOOT_DEFAULT or { value = 500, speed = 13, color = { 255, 255, 255 } }
end
LootService.info = info

-- optional sibling services (other agents' files may not exist yet)
local optionalCache = {}
local function optionalService(name)
    if optionalCache[name] ~= nil then return optionalCache[name] or nil end
    local mod = script.Parent:FindFirstChild(name)
    local ok, result = false, nil
    if mod then ok, result = pcall(require, mod) end
    optionalCache[name] = (ok and type(result) == "table") and result or false
    return optionalCache[name] or nil
end
local function styleBag(player, bag)
    local C = optionalService("CosmeticsService")
    if C and type(C.styleBag) == "function" then
        local ok, err = pcall(C.styleBag, C, player, bag)
        if not ok then warn("[LootService] styleBag:", err) end
    end
end
local function feel(method, ...)
    local F = optionalService("FeelService")
    if F and type(F[method]) == "function" then
        local ok, err = pcall(F[method], F, ...)
        if not ok then warn("[LootService] Feel:" .. method, err) end
    end
end
local function notify(player, text, color, duration)
    if not notifyRemote or not player or not player:IsA("Player") or not player.Parent then return end
    pcall(function() notifyRemote:FireClient(player, { text = text, color = color or "white", duration = duration or 3 }) end)
end
local function notifyAll(text, color, duration)
    for _, p in ipairs(Players:GetPlayers()) do notify(p, text, color, duration) end
end

local function isPlayer(x) return typeof(x) == "Instance" and x:IsA("Player") end
local function rootOf(x)
    if not x then return nil end
    local m = isPlayer(x) and x.Character or x
    return m and (m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)) or nil
end
local function torsoOf(x)
    local m = isPlayer(x) and x.Character or x
    return m and (m:FindFirstChild("UpperTorso") or m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")) or nil
end

local function hideVisual(pile, hide)
    local v = pile.visual
    if typeof(v) ~= "Instance" then return end
    local list = v:IsA("BasePart") and { v } or {}
    for _, d in ipairs(v:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(list, d) end
    end
    if hide then
        pile.hidden = pile.hidden or {}
        for _, p in ipairs(list) do
            if pile.hidden[p] == nil then pile.hidden[p] = { t = p.Transparency, c = p.CanCollide } end
            p.Transparency = 1
            p.CanCollide = false
        end
        for _, d in ipairs(v:GetDescendants()) do
            if d:IsA("Light") or d:IsA("SurfaceGui") then d.Enabled = false end
        end
    else
        if not pile.hidden then return end
        for p, st in pairs(pile.hidden) do
            p.Transparency = st.t
            p.CanCollide = st.c
        end
        pile.hidden = nil
        for _, d in ipairs(v:GetDescendants()) do
            if d:IsA("Light") or d:IsA("SurfaceGui") then d.Enabled = true end
        end
    end
end

-- ── items (v3.0) ─────────────────────────────────────────────────────
local function flagOf(spot, kind, field)
    local v = spot and spot[field]
    if v ~= nil then return v == true end
    return info(kind)[field] == true
end

local function newItem(kind, spot, mult)
    local d = info(kind)
    local interact = spot and spot.interact
    if interact == nil then interact = d.interact end
    if type(interact) ~= "string" or not GAMES[interact] then interact = nil end
    local targetKind = nil
    if spot and type(spot.target) == "string" and spot.target ~= "" then
        targetKind = spot.target
    elseif (spot and spot.target == true) or TargetService:isTarget(kind) then
        targetKind = kind
    end
    return {
        kind = kind, name = d.name or kind, base = d.value or 0, mult = mult or 1, integrity = 1,
        heavy = flagOf(spot, kind, "heavy"), fragile = flagOf(spot, kind, "fragile"),
        deposit = d.deposit == true, interact = interact, targetKind = targetKind,
        hidden = spot ~= nil and spot.hidden == true, pool = spot and spot.pool,
        boxNumber = spot and tonumber(spot.boxNumber) or nil,
    }
end

-- base × jackpot × fragile × tier (rounded)
local function itemValue(item, tierMult)
    if type(item) ~= "table" then return 0 end
    local floor = V3.FRAGILE_FLOOR or 0.25
    local v = (tonumber(item.base) or 0) * (tonumber(item.mult) or 1)
        * math.max(floor, tonumber(item.integrity) or 1) * (tonumber(tierMult) or 1)
    return math.floor(v + 0.5)
end

-- v2.2 bag tiers (CosmeticsService) — { valueMult, scale, id }
local function bagTier(player)
    local C = player and isPlayer(player) and optionalService("CosmeticsService")
    if C and type(C.bagTier) == "function" then
        local ok, t = pcall(C.bagTier, C, player)
        if ok and type(t) == "table" then return t end
    end
    return { valueMult = 1, scale = 1, id = nil }
end
local function tierMult(player)
    return math.max(1, tonumber(bagTier(player).valueMult) or 1)
end

-- deposit boxes: roll what's inside (weighted), once, when it's opened
local function rollDeposit(item)
    if not item.deposit or item.contents then return end
    local list = V3.DEPOSIT_BOX or {}
    local total = 0
    for _, e in ipairs(list) do total = total + (tonumber(e.weight) or 0) end
    if total <= 0 then return end
    local r = (depositRng and depositRng.next() or math.random()) * total
    local pick = list[#list]
    for _, e in ipairs(list) do
        r = r - (tonumber(e.weight) or 0)
        if r < 0 then pick = e break end
    end
    local name = pick.name
    if not name and type(pick.names) == "table" and #pick.names > 0 then
        local i = depositRng and depositRng.int(1, #pick.names) or math.random(1, #pick.names)
        name = pick.names[i]
    end
    item.contents = pick.id
    item.base = tonumber(pick.value) or item.base
    item.name = (item.boxNumber and ("Deposit Box #" .. item.boxNumber) or "Deposit Box") .. ": " .. tostring(name or "???")
    item.duck = pick.id == "duck"
    item.line = pick.line
end

-- ── carrying ─────────────────────────────────────────────────────────
-- v2.0 masks: Kitsune "FOX SPEED" — MaskService sets the SpeedMult attribute
-- (1.2) while the power is on; every speed this file writes is scaled by it.
-- v2.2: × the trail's TrailSpeedMult (CosmeticsService) — multiplicative with Fox Speed
local function speedMult(player)
    local m = tonumber(player:GetAttribute("SpeedMult"))
    local t = tonumber(player:GetAttribute("TrailSpeedMult"))
    return ((m and m > 0) and m or 1) * ((t and t > 0) and t or 1)
end

local function baseSpeed(player)
    return DEFAULT_SPEED + ((Shop and Shop:hasGear(player, "Sneakers")) and 2 or 0)
end

local function carrySpeed(player, item)
    local base = baseSpeed(player)
    if player:GetAttribute("Role") == "Muscle" then return base * speedMult(player) end
    local target = item.heavy and (V3.HEAVY_SPEED or 9) or (info(item.kind).speed or 13)
    local slow = math.max(0, base - target)
    if Shop and Shop:hasGear(player, "Duffel") then slow = slow / 2 end
    return (base - slow) * speedMult(player)
end

local function setSpeed(player, item)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    hum.WalkSpeed = item and carrySpeed(player, item) or baseSpeed(player) * speedMult(player)
    hum.UseJumpPower = false
    hum.JumpHeight = item and (item.heavy and 2.5 or 4) or 7.2
end

-- v3: the bag bulges with value, and cash bundles poke out of the top.
-- (playtest fix 2026-09-25) a backpack, not a boulder: base ~1.9 x 1.3 x 0.9 and
-- value (≤ +15%) × bag tier (half its scale, ≤ +20%) × heavy (+15%), capped ×1.3.
local BAG_BASE = Vector3.new(1.9, 1.3, 0.9)
local BAG_MAX_GROWTH = 1.3
local function bagGrowth(item, value, scale)
    local bulge = 1 + math.clamp((value - 1000) / 20000, 0, 0.15)
    if item.heavy then bulge = math.max(bulge, 1.15) end
    local tier = 1 + (math.clamp(tonumber(scale) or 1, 0.8, 1.4) - 1) * 0.5
    return math.clamp(bulge * tier, 0.9, BAG_MAX_GROWTH)
end
-- where a bag sits on a torso: snug against the back, a touch low (so the
-- third-person camera looks OVER it, not through it)
local function backOffset(item, scale)
    local g = bagGrowth(item, itemValue(item, 1), scale)
    return CFrame.new(0, -0.15, 0.5 + BAG_BASE.Z * g / 2)
end
LootService._bagGrowth = bagGrowth   -- (tests)
LootService.BAG_MAX_GROWTH = BAG_MAX_GROWTH

local function makeBag(item, cframe, scale)
    local kind = item.kind
    local value = itemValue(item, 1)
    local g = bagGrowth(item, value, scale)
    scale = g   -- bundles / bands follow the bag
    local col = UITheme.rgb(info(kind).color or { 255, 255, 255 })
    local bag = Instance.new("Part")
    bag.Name = "LootBag"
    bag.Size = BAG_BASE * g
    bag.Material = Enum.Material.Fabric
    bag.Color = Color3.fromRGB(28, 30, 36)
    bag.CanCollide = false
    bag.Massless = true
    bag:SetAttribute("Kind", kind)
    bag:SetAttribute("LootName", item.name)
    bag:SetAttribute("Value", value)
    -- (fix v1.1) position BEFORE welding — a WeldConstraint keeps the offset it
    -- sees when made, so welding at the origin left the strap floating there
    bag.CFrame = cframe or CFrame.new()
    local function weldOn(p)
        p.CanCollide = false
        p.CanQuery = false
        p.Massless = true
        local w = Instance.new("WeldConstraint")
        w.Part0, w.Part1 = bag, p
        w.Parent = p
        p.Parent = bag
    end
    local strap = Instance.new("Part")
    strap.Name = "Strap"
    strap.Size = Vector3.new(bag.Size.X + 0.05, 0.2, bag.Size.Z + 0.05)
    strap.Material = Enum.Material.Fabric
    strap.Color = col
    strap.CFrame = bag.CFrame
    weldOn(strap)
    local bundles = value >= 6000 and 3 or value >= 2500 and 2 or value >= 1000 and 1 or 0
    for i = 1, bundles do
        local b = Instance.new("Part")
        b.Name = "CashBundle"
        b.Size = Vector3.new(0.55, 0.22, 0.32) * scale
        b.Material = Enum.Material.Fabric
        b.Color = Color3.fromRGB(96, 170, 96)
        local x = (i - (bundles + 1) / 2) * 0.5 * scale
        b.CFrame = bag.CFrame * CFrame.new(x, bag.Size.Y / 2 + 0.05, 0) * CFrame.Angles(0, 0, math.rad((i % 2 == 0) and 25 or -20))
        weldOn(b)
        local band = Instance.new("Part")
        band.Name = "Band"
        band.Size = Vector3.new(0.1, 0.24, 0.34) * scale
        band.Material = Enum.Material.SmoothPlastic
        band.Color = Color3.fromRGB(240, 220, 150)
        band.CFrame = b.CFrame
        weldOn(band)
    end
    bagItems[bag] = item
    return bag
end

local CARRY_ATTRS = { "CarryingLoot", "CarryName", "CarryValue", "CarryHeavy", "CarryFragile", "CarryIntegrity",
    "CarryJackpot", "CarryTarget", "CarryPartner", "CarryHelping" }

local function syncAttrs(player)
    local c = carriers[player]
    local item = c and c.item
    if not item then
        for _, a in ipairs(CARRY_ATTRS) do
            if a ~= "CarryHelping" and a ~= "CarryPartner" then player:SetAttribute(a, nil) end
        end
        if not helpers[player] then
            player:SetAttribute("CarryHelping", nil)
            player:SetAttribute("CarryPartner", nil)
        end
        return
    end
    player:SetAttribute("CarryName", item.name)
    player:SetAttribute("CarryValue", itemValue(item, tierMult(player)))
    player:SetAttribute("CarryHeavy", item.heavy == true)
    player:SetAttribute("CarryFragile", item.fragile == true)
    player:SetAttribute("CarryIntegrity", item.integrity or 1)
    player:SetAttribute("CarryJackpot", (item.mult or 1) > 1)
    player:SetAttribute("CarryTarget", item.targetKind ~= nil)
    local partner = c.partner
    player:SetAttribute("CarryPartner", partner and (isPlayer(partner) and partner.DisplayName
        or partner:GetAttribute("BotName") or partner.Name) or nil)
    player:SetAttribute("CarryHelping", nil)
    -- set LAST: HUDs listen to CarryingLoot and read the rest
    player:SetAttribute("CarryingLoot", item.kind)
end

-- the rope between two lifters (a Beam in the bag, so it goes when the bag goes)
local function tether(c, fromPart, toPart)
    if c.att0 then c.att0:Destroy() c.att0 = nil end
    if c.att1 then c.att1:Destroy() c.att1 = nil end
    if not (c.bag and fromPart and toPart) then return end
    local a0 = Instance.new("Attachment")
    a0.Name = "HeavyTether"
    a0.Parent = fromPart
    local a1 = Instance.new("Attachment")
    a1.Name = "HeavyTether"
    a1.Parent = toPart
    local beam = Instance.new("Beam")
    beam.Name = "Tether"
    beam.Attachment0, beam.Attachment1 = a0, a1
    beam.Width0, beam.Width1 = 0.25, 0.25
    beam.FaceCamera = true
    beam.Color = ColorSequence.new(Color3.fromRGB(214, 180, 120))
    beam.Parent = c.bag
    c.att0, c.att1 = a0, a1
end

local function releaseHelper(helper)
    if not helper then return end
    if isPlayer(helper) then
        helpers[helper] = nil
        helper:SetAttribute("CarryHelping", nil)
        helper:SetAttribute("CarryPartner", nil)
        if not carriers[helper] then setSpeed(helper, nil) end
    else
        botHelpers[helper] = nil
        if helper.Parent then helper:SetAttribute("CarryHelping", nil) end
    end
end

local function attachBag(player, c)
    local char = player.Character
    local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
    if not torso then return end
    -- v2.2: bigger tiers are (a little) bigger; backOffset keeps it snug on the back
    local scale = bagTier(player).scale
    local bag = makeBag(c.item, torso.CFrame * backOffset(c.item, scale), scale)
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1 = torso, bag
    weld.Parent = bag
    bag.Parent = char
    c.bag = bag
    styleBag(player, bag)
    if c.partner then tether(c, torso, torsoOf(c.partner)) end
end

-- item = nil clears (and lets go of any lifting buddy). partner = the other lifter (heavy)
local function setCarrying(player, item, partner)
    local old = carriers[player]
    if old then
        if old.bag then old.bag:Destroy() end
        if old.att0 then old.att0:Destroy() end
        if old.att1 then old.att1:Destroy() end
        if old.partner and old.partner ~= partner then releaseHelper(old.partner) end
    end
    carriers[player] = nil
    if item then
        local c = { kind = item.kind, item = item, partner = partner, runT = 0, farT = 0 }
        carriers[player] = c
        if partner then
            if isPlayer(partner) then
                helpers[partner] = player
                partner:SetAttribute("CarryHelping", item.name)
                partner:SetAttribute("CarryPartner", player.DisplayName)
                setSpeed(partner, item)
            else
                botHelpers[partner] = player
                partner:SetAttribute("CarryHelping", item.name)
            end
        end
        setSpeed(player, item)
        attachBag(player, c)
    else
        setSpeed(player, nil)
    end
    syncAttrs(player)
end

-- a fragile item gets bumped: 25% off (never below the floor), CRACK!
local function bump(item, who, why)
    if not item or not item.fragile then return false end
    local floor = V3.FRAGILE_FLOOR or 0.25
    local before = item.integrity or 1
    if before <= floor + 1e-6 then return false end
    item.integrity = math.max(floor, before - (V3.FRAGILE_LOSS or 0.25))
    if who and isPlayer(who) then
        feel("big", "CRACK!", { player = who, color = "danger", sound = "alarm_small", shake = true })
        local tip = why == "run" and "  Hold C to walk slow with it!" or ""
        notify(who, string.format("Your %s cracked! Now it's worth %s.%s", item.name,
            UITheme.money(itemValue(item, tierMult(who))), tip), "red", 3)
        if carriers[who] then syncAttrs(who) end
    end
    return true
end

-- owner (v2.1): the player whose bag skin it keeps (throw / drop / death) — optional
local tryLift
local function spawnLoose(item, cframe, velocity, owner)
    if not item then return nil end
    local bag = makeBag(item, cframe, owner and bagTier(owner).scale or 1)
    if owner then styleBag(owner, bag) end
    bag.Massless = false
    bag.CanCollide = true
    bag.Parent = refs and refs.root or workspace
    for _, d in ipairs(bag:GetDescendants()) do
        if d:IsA("BasePart") then d.Massless = true end
    end
    pcall(function() bag:SetNetworkOwner(nil) end)
    if velocity then bag.AssemblyLinearVelocity = velocity end
    -- (fix v1.1) once it has landed, pin it and stop it colliding — a bag on the
    -- road used to stop the getaway car dead
    task.delay(2, function()
        if bag.Parent then
            bag.Anchored = true
            bag.CanCollide = false
        end
    end)
    local p = Instance.new("ProximityPrompt")
    p.Name = "PickUpBag"
    p.ActionText = item.heavy and "Lift together" or "Pick up"
    p.ObjectText = item.name .. " · " .. UITheme.money(itemValue(item, 1)) .. (item.heavy and " · HEAVY" or "")
    p.HoldDuration = 0.3
    p.MaxActivationDistance = 8
    p.RequiresLineOfSight = true
    p.Parent = bag
    p.Triggered:Connect(function(player)
        if not bag.Parent then return end
        if carriers[player] or helpers[player] or sessions[player] then
            cb.onEvent("full", player)
            return
        end
        if item.heavy then
            tryLift(player, {
                key = bag, item = item, prompt = p, baseText = "Lift together",
                pos = function() return bag.Position end,
                take = function(lifter, partner)
                    if not bag.Parent then return end
                    bag:Destroy()
                    setCarrying(lifter, item, partner)
                end,
            })
            return
        end
        bag:Destroy()
        setCarrying(player, item)
    end)
    table.insert(loose, bag)
    return bag
end

-- ── heavy lifting (v3.0) ─────────────────────────────────────────────
local function nearbyBot(player, pos)
    local B = optionalService("BotService")
    if not B or type(B.getBots) ~= "function" then return nil end
    local ok, list = pcall(B.getBots, B)
    if not ok or type(list) ~= "table" then return nil end
    local best, bestD = nil, V3.HEAVY_LIFT_NEAR or 12
    -- your own bots first, then anyone's
    for pass = 1, 2 do
        for _, b in ipairs(list) do
            local m = b.model
            if m and m.Parent and (pass == 2 or b.owner == player) and not botBags[m] and not botHelpers[m] then
                local r = rootOf(m)
                local d = r and (r.Position - pos).Magnitude
                if d and d <= bestD then best, bestD = m, d end
            end
        end
        if best then return best end
    end
    return nil
end

local function near(player, pos, dist)
    local r = rootOf(player)
    return r ~= nil and (r.Position - pos).Magnitude <= dist
end

-- src = { key, item, prompt, baseText, pos = fn -> Vector3, take = fn(lifter, partner) }
tryLift = function(player, src)
    local pos = src.pos()
    if player:GetAttribute("Role") == "Muscle" then
        lifts[src.key] = nil
        if src.prompt then src.prompt.ActionText = src.baseText end
        notify(player, "MUSCLE! You lift it all by yourself.", "gold", 2)
        src.take(player, nil)
        return
    end
    local L = lifts[src.key]
    local reach = (V3.HEAVY_LIFT_NEAR or 12)
    if L and L.first ~= player and L.first.Parent and not carriers[L.first] and not helpers[L.first]
        and os.clock() - L.at <= (V3.HEAVY_LIFT_WAIT or 10) and near(L.first, pos, reach + 2) then
        lifts[src.key] = nil
        if src.prompt then src.prompt.ActionText = src.baseText end
        notify(L.first, player.DisplayName .. " grabbed the other side. Carry it together!", "gold", 3)
        notify(player, "You're carrying it together with " .. L.first.DisplayName .. ". Stay close!", "gold", 3)
        src.take(L.first, player)
        return
    end
    -- a crew bot standing close lifts the other side
    local bot = nearbyBot(player, pos)
    if bot then
        lifts[src.key] = nil
        if src.prompt then src.prompt.ActionText = src.baseText end
        notify(player, string.format("%s grabbed the other side!", tostring(bot:GetAttribute("BotName") or bot.Name)), "gold", 3)
        src.take(player, bot)
        return
    end
    local token = {}
    lifts[src.key] = { first = player, at = os.clock(), token = token }
    if src.prompt then src.prompt.ActionText = "Lift together (1/2)" end
    notify(player, string.format("The %s is HEAVY! Wait here. A buddy has to lift the other side (or the Muscle can lift it alone).",
        src.item.name), "gold", 4)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then notify(p, player.DisplayName .. " needs help lifting the " .. src.item.name .. "!", "gold", 3) end
    end
    task.delay(V3.HEAVY_LIFT_WAIT or 10, function()
        local cur = lifts[src.key]
        if cur and cur.token == token then
            lifts[src.key] = nil
            if src.prompt and src.prompt.Parent then src.prompt.ActionText = src.baseText end
            notify(player, "Nobody came to help. Get a buddy (or the Muscle) and try again!", "white", 3)
        end
    end)
end

-- ── drop ─────────────────────────────────────────────────────────────
-- a lifter / helper lets go → the item falls where the lifter stands
local function dropAt(player, reason)
    local primary = helpers[player] or player
    local c = carriers[primary]
    if not c then
        if not helpers[player] then syncAttrs(player) end
        return nil
    end
    local item = c.item
    local partner = c.partner
    local root = rootOf(primary) or rootOf(player)
    local cf = root and root.CFrame * CFrame.new(0, -1, 1.5) or nil
    setCarrying(primary, nil)
    if reason ~= "quiet" then bump(item, primary, reason) end
    if partner and isPlayer(partner) and partner ~= player then
        notify(partner, "Your buddy let go! It fell on the floor.", "white", 3)
    end
    if player ~= primary then
        notify(primary, "Your buddy let go! It fell on the floor.", "white", 3)
    end
    if cf and refs then spawnLoose(item, cf, nil, primary) end
    return item
end

local endSession -- (forward) mini-games

function LootService:drop(player)
    if sessions[player] then endSession(player, "caught", true) end
    for key, L in pairs(lifts) do if L.first == player then lifts[key] = nil end end
    if not carriers[player] and not helpers[player] then
        player:SetAttribute("CarryingLoot", nil)
        syncAttrs(player)
        return
    end
    dropAt(player, "grabbed")
end

-- ── piles ────────────────────────────────────────────────────────────
local function takePile(pile, player, partner)
    if pile.taken then return end
    pile.taken = true
    pile.prompt.Enabled = false
    hideVisual(pile, true)
    if pile.glass then
        -- shatter: hide the glass top and throw a few shards
        local g = pile.glass
        g.Transparency = 1
        g.CanCollide = false
        for _ = 1, 7 do
            local shard = Instance.new("Part")
            shard.Name = "Shard"
            shard.Size = Vector3.new(math.random(2, 5) / 10, 0.05, math.random(2, 5) / 10)
            shard.Material = Enum.Material.Glass
            shard.Color = g.Color
            shard.Transparency = 0.3
            shard.CanCollide = false
            shard.CFrame = g.CFrame * CFrame.new(math.random(-8, 8) / 10, 0.2, math.random(-5, 5) / 10)
                * CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
            shard.AssemblyLinearVelocity = Vector3.new(math.random(-8, 8), math.random(6, 14), math.random(-8, 8))
            shard.Parent = refs.root
            Debris:AddItem(shard, 2.5)
        end
    end
    local item = pile.item
    rollDeposit(item)
    setCarrying(player, item, partner)
    if item.duck then
        feel("big", "QUACK!", { player = player, color = "info", sound = "tick" })
        notify(player, item.line or "It's a rubber duck! Worth $1.", "white", 4)
        notifyAll(player.DisplayName .. " found a rubber duck. Quack!", "white", 3)
    elseif item.deposit then
        notify(player, string.format("%s! (%s)", item.name, UITheme.money(itemValue(item, 1))), "gold", 3)
    end
    if item.hidden then
        feel("big", "SECRET STASH!", { color = "gold", sound = "success" })
        notifyAll(player.DisplayName .. " found a SECRET STASH!", "gold", 4)
    end
    cb.onEvent(pile.isCase and "smash" or "take", player,
        { kind = item.kind, name = item.name, pos = pile.anchor.Position, value = itemValue(item, 1),
          heavy = item.heavy, target = item.targetKind ~= nil })
end

local function grabPile(pile, player)
    if pile.item.heavy then
        tryLift(player, {
            key = pile, item = pile.item, prompt = pile.prompt, baseText = pile.baseText,
            pos = function() return pile.anchor.Position end,
            take = function(lifter, partner) takePile(pile, lifter, partner) end,
        })
    else
        takePile(pile, player, nil)
    end
end

-- ── mini-games (v3.0) ────────────────────────────────────────────────
endSession = function(player, reason, tell)
    local s = sessions[player]
    sessions[player] = nil
    if not s then return end
    if s.pile.busyBy == player then s.pile.busyBy = nil end
    if tell and minigameRemote and player.Parent then
        pcall(function() minigameRemote:FireClient(player, { op = "stop", token = s.token, reason = reason }) end)
    end
end

local function startMinigame(player, pile)
    local other = pile.busyBy
    if other and other ~= player and sessions[other] and sessions[other].pile == pile then
        notify(player, other.DisplayName .. " is already on it!", "white", 2)
        return
    end
    if sessions[player] then endSession(player, "switch", true) end
    local game_ = pile.item.interact
    local g = GAMES[game_] or {}
    sessionToken = sessionToken + 1
    local s = { pile = pile, token = sessionToken, t0 = os.clock(), game = game_ }
    sessions[player] = s
    pile.busyBy = player
    if minigameRemote then
        pcall(function()
            minigameRemote:FireClient(player, {
                op = "start", token = s.token, game = game_, title = g.title, hint = g.hint,
                kind = pile.item.kind, name = pile.item.name, value = itemValue(pile.item, 1),
                min = g.min or 1, hold = V3.MINIGAME_HOLD or 3, timeout = V3.MINIGAME_TIMEOUT or 30,
            })
        end)
    end
    task.delay(V3.MINIGAME_TIMEOUT or 30, function()
        if sessions[player] == s then endSession(player, "timeout", true) end
    end)
end

local function reply(player, token, ok, msg)
    if minigameRemote and player.Parent then
        pcall(function() minigameRemote:FireClient(player, { op = "result", token = token, ok = ok, msg = msg }) end)
    end
end

local lastMsg = {}
local function onMinigameMessage(player, msg)
    if type(msg) ~= "table" then return end
    local nowT = os.clock()
    if lastMsg[player] and nowT - lastMsg[player] < 0.05 then return end
    lastMsg[player] = nowT
    local s = sessions[player]
    if not s or msg.token ~= s.token then return end
    if msg.op == "cancel" then
        endSession(player, "cancel", false)
        return
    end
    if msg.op ~= "done" then return end
    local pile = s.pile
    local elapsed = nowT - s.t0
    local g = GAMES[s.game] or {}
    local need = (msg.mode == "hold") and math.max(0, (V3.MINIGAME_HOLD or 3) - 0.3) or (g.min or 1)
    endSession(player, "done", false)
    if msg.ok ~= true then
        reply(player, s.token, false, "Oops! Try again.")
        return
    end
    if elapsed < need then
        reply(player, s.token, false, "Too fast! Try again.")
        return
    end
    if pile.taken or not pile.anchor.Parent or not table.find(piles, pile) then
        reply(player, s.token, false, "Someone already took it!")
        return
    end
    if not pile.prompt.Enabled then
        reply(player, s.token, false, "It's locked!")
        return
    end
    if not near(player, pile.anchor.Position, V3.MINIGAME_REACH or 14) then
        reply(player, s.token, false, "Too far away! Get closer.")
        return
    end
    if carriers[player] or helpers[player] then
        reply(player, s.token, false, "Your hands are full!")
        return
    end
    pile.unlocked = true
    pile.prompt.ActionText = pile.baseText
    pile.prompt.HoldDuration = pile.item.heavy and 0.4 or 0.3
    reply(player, s.token, true, nil)
    grabPile(pile, player)
end

-- v3: a dial / drill on loot INSIDE the vault or safe is that lock again — the
-- crew already drilled it, so no second lock (deposit boxes keep theirs: each box
-- is its own little lock)
local function skipsLock(item, isVault)
    return isVault and (item.interact == "dial" or item.interact == "drill") and not item.deposit
end

local function actionFor(item, isCase)
    if isCase then return "Smash & grab" end
    if item.interact then return (GAMES[item.interact] or {}).prompt or "Open it" end
    if item.heavy then return "Lift together" end
    return "Bag it"
end

local function addPile(kind, visual, standCFrame, isVault, isCase, glass, spot, mult)
    local item = newItem(kind, spot, mult)
    if isCase or skipsLock(item, isVault) then item.interact = nil end
    local anchor = Instance.new("Part")
    anchor.Name = "LootPrompt"
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.Anchored = true
    anchor.CFrame = standCFrame + Vector3.new(0, 2.5, 0)
    anchor.Parent = refs.root
    local p = Instance.new("ProximityPrompt")
    p.Name = isCase and "SmashCase" or "BagLoot"
    p.ActionText = actionFor(item, isCase)
    local valueText = item.deposit and "???" or UITheme.money(itemValue(item, 1))
    local shownName = (item.deposit and item.boxNumber) and (item.name .. " #" .. item.boxNumber) or item.name
    p.ObjectText = (item.targetKind and "TARGET: " or "") .. shownName .. " · " .. valueText
        .. ((item.mult or 1) > 1 and "  JACKPOT" or "") .. (item.heavy and " · HEAVY" or "")
        .. (item.fragile and " · FRAGILE" or "")
    p.HoldDuration = isCase and 1.2 or item.interact and 0.25 or item.heavy and 0.4 or 1
    -- v3: a builder can shrink it (spot.promptRange — the Pink Diamond's laser cage)
    local range = spot and tonumber(spot.promptRange)
    p.MaxActivationDistance = (range and range > 0) and range or 7
    p.RequiresLineOfSight = true   -- (fix v1.1) no grabbing loot through walls
    p.Enabled = not isVault
    p.Parent = anchor
    local pile = { kind = kind, item = item, visual = visual, prompt = p, anchor = anchor, taken = false,
        isVault = isVault, isCase = isCase, glass = glass, glassT = glass and glass.Transparency, glassC = glass and glass.CanCollide, spot = spot,
        baseText = item.heavy and "Lift together" or (isCase and "Smash & grab" or "Bag it") }
    p.Triggered:Connect(function(player)
        if pile.taken then return end
        if sessions[player] and sessions[player].pile == pile then return end   -- already playing it
        if carriers[player] or helpers[player] then
            cb.onEvent("full", player)
            return
        end
        if pile.item.interact and not pile.unlocked then
            startMinigame(player, pile)
            return
        end
        grabPile(pile, player)
    end)
    table.insert(piles, pile)
end

-- ── car ──────────────────────────────────────────────────────────────
-- v2.2: the bag's tier pays — `owner` = whose bag it is (the loader, or a bot's owner)
local function loadInto(trunk, item, player, botName, owner, tierOverride)
    local tier = tierOverride or bagTier(owner)
    local mult = math.max(1, tonumber(tier.valueMult) or 1)
    local base = itemValue(item, 1)
    local value = itemValue(item, mult)
    table.insert(loaded, { kind = item.kind, name = item.name, value = value, base = base, bonus = value - base,
        tier = tier.id, bot = botName, by = owner and owner.Name or nil, target = item.targetKind ~= nil,
        jackpot = (item.mult or 1) > 1, integrity = item.integrity or 1, contents = item.contents })
    local car = trunk and trunk:FindFirstAncestorOfClass("Model")
    if car then car:SetAttribute("Bags", #loaded) end
    if item.targetKind then
        local ok, err = pcall(TargetService.onSecured, TargetService, owner or player, item.targetKind)
        if not ok then warn("[LootService] onSecured:", err) end
    end
    cb.onEvent("load", player, { kind = item.kind, name = item.name, value = value, base = base, bonus = value - base,
        tier = tier.id, tierName = tier.name, pos = trunk and trunk.Position, bot = botName,
        target = item.targetKind ~= nil })
end

function LootService:attachTrunk(trunk)
    if trunkPrompt then trunkPrompt:Destroy() trunkPrompt = nil end
    currentTrunk = trunk
    if not trunk then return end
    local p = Instance.new("ProximityPrompt")
    p.Name = "LoadBag"
    p.ActionText = "Load bag"
    p.ObjectText = "Getaway car"
    p.HoldDuration = 0.5
    p.MaxActivationDistance = 9
    p.RequiresLineOfSight = false
    p.Parent = trunk
    trunkPrompt = p
    p.Triggered:Connect(function(player)
        -- v3: either lifter of a heavy one can put it in
        local owner = helpers[player] or player
        local c = carriers[owner]
        if not c then
            cb.onEvent("emptyHanded", player)
            return
        end
        local item = c.item
        setCarrying(owner, nil)
        loadInto(trunk, item, player, nil, owner)
    end)
end

-- ── v2.0 bot crew ────────────────────────────────────────────────────
local function clearBotBag(botModel)
    local b = botBags[botModel]
    botBags[botModel] = nil
    if b and b.bag then b.bag:Destroy() end
    if botModel and botModel.Parent then botModel:SetAttribute("CarryingLoot", nil) end
    return b
end

function LootService:transferToBot(player, botModel)
    local c = carriers[player]
    if not c or not botModel or not botModel.Parent or botBags[botModel] then return nil end
    local torso = torsoOf(botModel)
    if not torso then return nil end
    local item = c.item
    setCarrying(player, nil)
    releaseHelper(botModel)
    local tier = bagTier(player)   -- it's still YOUR bag on the bot (tier fixed at hand-over)
    local scale = tier.scale
    local bag = makeBag(item, torso.CFrame * backOffset(item, scale), scale)
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1 = torso, bag
    weld.Parent = bag
    bag.Parent = botModel
    botBags[botModel] = { kind = item.kind, item = item, bag = bag, owner = player, tier = tier }
    botModel:SetAttribute("CarryingLoot", item.kind)
    styleBag(player, bag)
    return item.kind
end

function LootService:botCarrying(botModel)
    local b = botBags[botModel]
    return b and b.kind or nil
end

function LootService:botLoad(botModel, trunk)
    local b = botBags[botModel]
    trunk = trunk or currentTrunk
    if not b or not trunk or not trunk.Parent then return false end
    clearBotBag(botModel)
    local owner = (b.owner and b.owner.Parent) and b.owner or nil
    loadInto(trunk, b.item, owner, botModel:GetAttribute("BotName") or botModel.Name, owner, b.tier)
    return true
end

function LootService:dropBot(botModel)
    -- a bot that was helping someone lift: that lift ends (the lifter drops it)
    local lifter = botHelpers[botModel]
    if lifter and carriers[lifter] and carriers[lifter].partner == botModel then
        dropAt(lifter, "quiet")
    end
    botHelpers[botModel] = nil
    local b = clearBotBag(botModel)
    if not b or not refs then return end
    local root = botModel and botModel:FindFirstChild("HumanoidRootPart")
    if root then spawnLoose(b.item, root.CFrame * CFrame.new(0, -1, 1.5), nil, (b.owner and b.owner.Parent) and b.owner or nil) end
end

-- ── queries ──────────────────────────────────────────────────────────
function LootService:counts()
    local take, taken = 0, 0
    for _, l in ipairs(loaded) do take = take + l.value end
    for _, p in ipairs(piles) do if p.taken then taken = taken + 1 end end
    local cases, casesTaken = 0, 0
    for _, p in ipairs(piles) do
        if p.isCase then
            cases = cases + 1
            if p.taken then casesTaken = casesTaken + 1 end
        end
    end
    -- v2.0: split the rest into loot behind the vault/safe door and loot out in the open
    local vault, vaultTaken, open, openTaken = 0, 0, 0, 0
    for _, p in ipairs(piles) do
        if not p.isCase then
            if p.isVault then
                vault = vault + 1
                if p.taken then vaultTaken = vaultTaken + 1 end
            else
                open = open + 1
                if p.taken then openTaken = openTaken + 1 end
            end
        end
    end
    local secured = TargetService:isSecured()
    -- allLoaded (playtest fix 2026-09-25): every bag of this job is in the trunk —
    -- JobService lets "everyone sat down" start the escape by itself only then
    -- (or when the alarm is on)
    return { total = #piles, loaded = #loaded, allLoaded = #piles > 0 and #loaded >= #piles, take = take, taken = taken, cases = cases, casesTaken = casesTaken,
        vault = vault, vaultTaken = vaultTaken, open = open, openTaken = openTaken,
        targetSecured = secured == true, targetBonus = TargetService:bonusFor(nil),
        jackpot = LootShuffle:info().jackpotName }
end

-- v1.1: for the payout breakdown
function LootService:getLoaded()
    local out = {}
    for _, l in ipairs(loaded) do out[#out + 1] = table.clone(l) end
    return out
end

-- v1.1: where untaken loot still is (for waypoints)
function LootService:remaining()
    local out = {}
    for _, p in ipairs(piles) do
        if not p.taken and p.anchor then
            table.insert(out, { pos = p.anchor.Position, kind = p.kind, name = p.item.name, isCase = p.isCase,
                locked = p.isVault and not vaultOpen, heavy = p.item.heavy, target = p.item.targetKind ~= nil })
        end
    end
    return out
end

function LootService:isCarrying(player)
    return carriers[player] ~= nil or helpers[player] ~= nil
end

function LootService:carried(player)
    local c = carriers[helpers[player] or player]
    return c and c.item or nil
end

function LootService:valueOf(bag, owner)
    local item = nil
    if typeof(bag) == "table" then
        item = bag.item or bag
    elseif typeof(bag) == "Instance" then
        if bag:IsA("Player") then
            local c = carriers[helpers[bag] or bag]
            item = c and c.item
            owner = owner or helpers[bag] or bag
        else
            item = bagItems[bag]
            if not item then
                for m, b in pairs(botBags) do
                    if b.bag == bag or m == bag then item = b.item owner = owner or b.owner break end
                end
            end
        end
    end
    if not item then return 0 end
    return itemValue(item, owner and tierMult(owner) or 1)
end

function LootService:jackpot()
    local i = LootShuffle:info()
    return { pool = i.jackpotPool, name = i.jackpotName, mult = i.jackpotMult }
end

-- v2.2: the right WalkSpeed for right now (bag or not) × SpeedMult × TrailSpeedMult
function LootService:refreshWalkSpeed(player)
    local char = player and player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    local c = carriers[helpers[player] or player]
    local want = c and carrySpeed(player, c.item) or baseSpeed(player) * speedMult(player)
    if math.abs(hum.WalkSpeed - want) > 1e-3 then hum.WalkSpeed = want end
end

-- v2.2: new bag tier equipped mid-carry → rebuild it (size + skin)
function LootService:refreshCarriedBag(player)
    local c = player and carriers[player]
    if not c then return end
    if c.bag then c.bag:Destroy() c.bag = nil end
    if c.att0 then c.att0:Destroy() c.att0 = nil end
    if c.att1 then c.att1:Destroy() c.att1 = nil end
    attachBag(player, c)
    syncAttrs(player)
end

function LootService:clearLoaded()
    loaded = {}
    TargetService:resetRun()
end

function LootService:setVaultOpen(open)
    vaultOpen = open
    for _, p in ipairs(piles) do
        if p.isVault and not p.taken then p.prompt.Enabled = open end
    end
end

-- ── the per-tick watcher: fragile bumps + heavy tether ───────────────
local function watch(dt)
    for player, c in pairs(carriers) do
        local item = c.item
        local root = rootOf(player)
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if item and root and hum and hum.Health > 0 then
            if item.fragile then
                local v = root.AssemblyLinearVelocity
                local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
                if horiz > (V3.FRAGILE_RUN_SPEED or 10) then
                    c.runT = (c.runT or 0) + dt
                    if c.runT >= (V3.FRAGILE_RUN_TIME or 2) then
                        bump(item, player, "run")
                        c.runT = (V3.FRAGILE_RUN_TIME or 2) - (V3.FRAGILE_RECRACK or 3)
                    end
                else
                    c.runT = math.min(c.runT or 0, 0)
                end
                local y = root.Position.Y
                if hum.FloorMaterial == Enum.Material.Air then
                    c.airTop = math.max(c.airTop or y, y)
                else
                    if c.airTop and c.airTop - y > (V3.FRAGILE_FALL or 6) then bump(item, player, "fall") end
                    c.airTop = nil
                end
            end
            local partner = c.partner
            if partner and isPlayer(partner) then
                local pr = rootOf(partner)
                local ph = partner.Character and partner.Character:FindFirstChildOfClass("Humanoid")
                if not partner.Parent or not pr or not ph or ph.Health <= 0 then
                    dropAt(player, "quiet")
                else
                    local d = (pr.Position - root.Position).Magnitude
                    if d > (V3.HEAVY_TETHER or 16) then
                        c.farT = (c.farT or 0) + dt
                        if c.farT >= (V3.HEAVY_TETHER_TIME or 1.5) then
                            notify(player, "Too far apart! Stay close to your buddy.", "red", 3)
                            notify(partner, "Too far apart! Stay close to your buddy.", "red", 3)
                            dropAt(player, "quiet")
                        end
                    else
                        c.farT = 0
                    end
                end
            elseif partner and not partner.Parent then
                -- the bot helper went away
                c.partner = nil
                botHelpers[partner] = nil
                syncAttrs(player)
            end
        end
    end
end

-- ── lifecycle ────────────────────────────────────────────────────────
local function endAllSessions(reason)
    for p in pairs(sessions) do endSession(p, reason, true) end
    sessions = {}
end

local function clearCarry()
    for player in pairs(carriers) do setCarrying(player, nil) end
    carriers = {}
    for h in pairs(helpers) do releaseHelper(h) end
    helpers = {}
    for b in pairs(botHelpers) do releaseHelper(b) end
    botHelpers = {}
    for bot in pairs(botBags) do clearBotBag(bot) end
    for _, b in ipairs(loose) do if b.Parent then b:Destroy() end end
    loose = {}
    lifts = {}
end

local function clearPiles()
    for _, p in ipairs(piles) do
        hideVisual(p, false)
        if p.glass then
            p.glass.Transparency = p.glassT or 0.5
            p.glass.CanCollide = p.glassC ~= false
        end
        if p.anchor then p.anchor:Destroy() end
    end
    piles = {}
    LootShuffle:restore(refs)
end

-- a fresh shuffle → the piles for this run
local function buildPiles(seed)
    local active, sinfo = LootShuffle:prepare(refs, seed)
    runSeed = sinfo.seed
    depositRng = LootShuffle._newRng((tonumber(runSeed) or 1) + 7919)
    for _, spot in ipairs(active) do
        -- (fix v1.1) loot sitting out in the open (jewelry pink diamond / painting)
        -- is marked inVault = false by the builder and is grabbable straight away
        if spot.kind then
            -- v3: a spot's own `glass` (e.g. the bank's Crown case) shatters when it's taken, like a smash case
            local glass = (typeof(spot.glass) == "Instance" and spot.glass:IsA("BasePart")) and spot.glass or nil
            addPile(spot.kind, spot.visual, spot.cframe, refs.vault ~= nil and spot.inVault ~= false, false, glass, spot,
                LootShuffle:multFor(spot))
        end
    end
    for _, case in ipairs(refs.smashCases or {}) do
        addPile(case.kind or "Jewels", case.visual, case.cframe, false, true, case.glass, case, 1)
    end
    TargetService:resetRun()
end

function LootService:disarm()
    for _, c in ipairs(conns) do c:Disconnect() end
    conns = {}
    endAllSessions("reset")
    clearCarry()
    if refs then clearPiles() end
    piles = {}
    loaded = {}
    if trunkPrompt then trunkPrompt:Destroy() trunkPrompt = nil end
    currentTrunk = nil
    refs = nil
end

function LootService:arm(jobRefs, opts)
    self:disarm()
    refs = jobRefs
    buildPiles(opts and opts.seed)
    vaultOpen = false
    track(Players.PlayerRemoving:Connect(function(p)
        if sessions[p] then endSession(p, "left", false) end
        if carriers[p] or helpers[p] then
            -- leave the bag where they stood so the crew can grab it
            dropAt(p, "quiet")
        end
        carriers[p] = nil
        helpers[p] = nil
    end))
end

function LootService:reset(opts)
    endAllSessions("reset")
    clearCarry()
    loaded = {}
    if refs then
        clearPiles()
        buildPiles(opts and opts.seed)
    end
    vaultOpen = false
end

function LootService:init(callbacks, shopService)
    cb.onEvent = callbacks.onEvent or cb.onEvent
    Shop = shopService
    notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
    minigameRemote = Remotes.getRemote("LootMinigame", "RemoteEvent")
    minigameRemote.OnServerEvent:Connect(onMinigameMessage)
    pcall(TargetService.init, TargetService, { feel = optionalService("FeelService") })

    local throwRemote = Remotes.getRemote(Remotes.NAMES.ThrowBag, "RemoteEvent")
    local lastThrow = {}
    throwRemote.OnServerEvent:Connect(function(player, dir)
        local c = carriers[player]
        if not c or typeof(dir) ~= "Vector3" then return end
        if lastThrow[player] and os.clock() - lastThrow[player] < 0.5 then return end
        lastThrow[player] = os.clock()
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local muscle = player:GetAttribute("Role") == "Muscle"
        if c.item.heavy and not muscle then
            notify(player, "Too heavy to throw! Carry it to the car.", "white", 2)
            return
        end
        local flat = Vector3.new(dir.X, 0, dir.Z)
        if flat.Magnitude < 0.1 then flat = root.CFrame.LookVector end
        flat = flat.Unit
        local item = c.item
        setCarrying(player, nil)
        bump(item, player, "throw")
        local speed = Constants.BAG_THROW_SPEED * (muscle and 1.3 or 1)
        -- v2.0 masks: 8-Bit Skull "POWER THROW" → twice as far (same arc height, 2x sideways speed)
        if maskHas(player, "powerthrow") then speed = speed * ((Constants.MASK_POWERS or {}).THROW_MULT or 2) end
        spawnLoose(item, root.CFrame * CFrame.new(0, 1.5, -2.5), flat * speed + Vector3.new(0, 22, 0), player)
        cb.onEvent("throw", player, { kind = item.kind, name = item.name })
    end)

    -- (fix v1.1) dying / resetting while carrying drops the bag where you fell
    -- (it used to vanish with the old character, lost for the whole run)
    local function hook(player)
        local function onChar(char, existing)
            if not existing then
                if carriers[player] or helpers[player] then dropAt(player, "quiet") end
                carriers[player] = nil
                player:SetAttribute("CarryingLoot", nil)
                syncAttrs(player)
            end
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                hum.Died:Connect(function()
                    if sessions[player] then endSession(player, "died", true) end
                    if carriers[player] or helpers[player] then dropAt(player, "fall") end
                end)
            end
        end
        player.CharacterAdded:Connect(onChar)
        if player.Character then task.spawn(onChar, player.Character, true) end
    end
    Players.PlayerAdded:Connect(hook)
    for _, player in ipairs(Players:GetPlayers()) do hook(player) end

    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc = acc + (tonumber(dt) or 0)
        if acc < 0.1 then return end
        local step = acc
        acc = 0
        if next(carriers) == nil then return end
        local ok, err = pcall(watch, step)
        if not ok then warn("[LootService] watch:", err) end
    end)
end

-- (tests) pure helpers, no side effects
LootService._test = { newItem = newItem, rollDeposit = rollDeposit, itemValue = itemValue }

return LootService
