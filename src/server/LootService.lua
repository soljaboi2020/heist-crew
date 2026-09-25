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
        bags only turn into cash when the car reaches the marina (JobService).

    Vault loot stays locked (prompts disabled) until JobService opens the vault.

    Callbacks: onEvent(kind, player, data)  kinds: "take", "smash", "load", "throw"
        data = { kind, pos (Vector3), value, bot (bot name, for loads a bot made) }

    v2.0: BOT CREW (BotService) can carry a bag for you — "Give bag" on the bot
    moves your bag onto its back, it walks to the car and loads it. A bot load
    counts EXACTLY like a player load (same `loaded` list, same "load" event).
    Carried bags are passed to CosmeticsService:styleBag(player, bag) if that
    service exists (progression agent), pcall-guarded.

    PUBLIC API:
        LootService:init(callbacks, ShopService)
        LootService:arm(jobRefs) / :disarm() / :reset()
        LootService:setVaultOpen(open)
        LootService:attachTrunk(trunkPart)
        LootService:drop(player)                 -- caught / left / reset
        LootService:counts() -> { total, loaded, take, taken, cases, casesTaken, vault, vaultTaken, open, openTaken }
        LootService:getLoaded() -> { {kind, value, bot?} }
        LootService:remaining() -> { {pos, kind, isCase, locked} }
        LootService:isCarrying(player) -> bool
        LootService:clearLoaded()
        LootService.info(kind) -> { value, speed, color }   (never nil; LOOT_DEFAULT fallback)
      v2.0 bots:
        LootService:transferToBot(player, botModel) -> kind | nil   -- player's bag onto the bot
        LootService:botCarrying(botModel) -> kind | nil
        LootService:botLoad(botModel, trunkPart?) -> boolean        -- bot puts its bag in the car
        LootService:dropBot(botModel)                               -- bot despawning: bag falls loose
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local LootService = {}
local cb = { onEvent = function() end }
local Shop = nil

local refs = nil
local piles = {}          -- { kind, visual, prompt, taken, isVault, hidden = {part=transparency} }
local carriers = {}       -- [player] = { kind, bag = Model }
local loose = {}          -- thrown/dropped bag parts
local loaded = {}         -- { kind, value }
local trunkPrompt = nil
local vaultOpen = false
local conns = {}

local DEFAULT_SPEED = 16
local botBags = {}        -- [botModel] = { kind, bag, owner }
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

local function hideVisual(pile, hide)
    local v = pile.visual
    if not v then return end
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
        for p, st in pairs(pile.hidden or {}) do
            p.Transparency = st.t
            p.CanCollide = st.c
        end
        pile.hidden = nil
        for _, d in ipairs(v:GetDescendants()) do
            if d:IsA("Light") or d:IsA("SurfaceGui") then d.Enabled = true end
        end
    end
end

-- ── carrying ─────────────────────────────────────────────────────────
-- v2.0 masks: Kitsune "FOX SPEED" — MaskService sets the SpeedMult attribute
-- (1.2) while the power is on; every speed this file writes is scaled by it.
local function speedMult(player)
    local m = tonumber(player:GetAttribute("SpeedMult"))
    return (m and m > 0) and m or 1
end

local function carrySpeed(player, kind)
    local base = DEFAULT_SPEED + ((Shop and Shop:hasGear(player, "Sneakers")) and 2 or 0)
    if player:GetAttribute("Role") == "Muscle" then return base * speedMult(player) end
    local target = info(kind).speed or 13
    local slow = base - target
    if Shop and Shop:hasGear(player, "Duffel") then slow = slow / 2 end
    return (base - slow) * speedMult(player)
end

local function makeBag(kind, cframe)
    local col = UITheme.rgb(info(kind).color or { 255, 255, 255 })
    local bag = Instance.new("Part")
    bag.Name = "LootBag"
    bag.Size = Vector3.new(2.2, 1.3, 1.2)
    bag.Material = Enum.Material.Fabric
    bag.Color = Color3.fromRGB(28, 30, 36)
    bag.CanCollide = false
    bag.Massless = true
    bag:SetAttribute("Kind", kind)
    -- (fix v1.1) position BEFORE welding — a WeldConstraint keeps the offset it
    -- sees when made, so welding at the origin left the strap floating there
    bag.CFrame = cframe or CFrame.new()
    local strap = Instance.new("Part")
    strap.Name = "Strap"
    strap.Size = Vector3.new(2.25, 0.25, 1.25)
    strap.Material = Enum.Material.Fabric
    strap.Color = col
    strap.CanCollide = false
    strap.Massless = true
    strap.CFrame = bag.CFrame
    local w = Instance.new("WeldConstraint")
    w.Part0, w.Part1 = bag, strap
    w.Parent = strap
    strap.Parent = bag
    return bag
end

local function setCarrying(player, kind)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local old = carriers[player]
    if old and old.bag then old.bag:Destroy() end
    carriers[player] = nil
    player:SetAttribute("CarryingLoot", kind)
    if hum then
        hum.WalkSpeed = kind and carrySpeed(player, kind)
            or (DEFAULT_SPEED + ((Shop and Shop:hasGear(player, "Sneakers")) and 2 or 0)) * speedMult(player)
        hum.UseJumpPower = false
        hum.JumpHeight = kind and 4 or 7.2
    end
    if not kind or not char then return end
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    if not torso then return end
    local bag = makeBag(kind, torso.CFrame * CFrame.new(0, 0, 1))
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1 = torso, bag
    weld.Parent = bag
    bag.Parent = char
    carriers[player] = { kind = kind, bag = bag }
    styleBag(player, bag)
end

-- owner (v2.1): the player whose bag skin it keeps (throw / drop / death) — optional
local function spawnLoose(kind, cframe, velocity, owner)
    local bag = makeBag(kind, cframe)
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
    p.ActionText = "Pick up"
    p.ObjectText = kind .. " · " .. UITheme.money(info(kind).value or 0)
    p.HoldDuration = 0.3
    p.MaxActivationDistance = 8
    p.RequiresLineOfSight = true
    p.Parent = bag
    track(p.Triggered:Connect(function(player)
        if carriers[player] or not bag.Parent then return end
        bag:Destroy()
        setCarrying(player, kind)
    end))
    table.insert(loose, bag)
    return bag
end

function LootService:drop(player)
    local c = carriers[player]
    if not c then
        player:SetAttribute("CarryingLoot", nil)
        return
    end
    local kind = c.kind
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    setCarrying(player, nil)
    if root and refs then
        spawnLoose(kind, root.CFrame * CFrame.new(0, -1, 1.5), nil, player)
    end
end

-- ── piles ────────────────────────────────────────────────────────────
local function addPile(kind, visual, standCFrame, isVault, isCase, glass)
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
    p.ActionText = isCase and "Smash & grab" or "Bag it"
    p.ObjectText = kind .. " · " .. UITheme.money(info(kind).value or 0)
    p.HoldDuration = isCase and 1.2 or 1
    p.MaxActivationDistance = 7
    p.RequiresLineOfSight = true   -- (fix v1.1) no grabbing loot through walls
    p.Enabled = not isVault
    p.Parent = anchor
    local pile = { kind = kind, visual = visual, prompt = p, anchor = anchor, taken = false, isVault = isVault, isCase = isCase,
        glass = glass, glassT = glass and glass.Transparency }
    track(p.Triggered:Connect(function(player)
        if pile.taken then return end
        if carriers[player] then
            cb.onEvent("full", player)
            return
        end
        pile.taken = true
        p.Enabled = false
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
        setCarrying(player, kind)
        cb.onEvent(isCase and "smash" or "take", player, { kind = kind, pos = anchor.Position, value = info(kind).value })
    end))
    table.insert(piles, pile)
end

-- ── car ──────────────────────────────────────────────────────────────
local function loadInto(trunk, kind, player, botName)
    local value = info(kind).value or 0
    table.insert(loaded, { kind = kind, value = value, bot = botName })
    local car = trunk and trunk:FindFirstAncestorOfClass("Model")
    if car then car:SetAttribute("Bags", #loaded) end
    cb.onEvent("load", player, { kind = kind, value = value, pos = trunk and trunk.Position, bot = botName })
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
    track(p.Triggered:Connect(function(player)
        local c = carriers[player]
        if not c then
            cb.onEvent("emptyHanded", player)
            return
        end
        local kind = c.kind
        setCarrying(player, nil)
        loadInto(trunk, kind, player, nil)
    end))
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
    local torso = botModel:FindFirstChild("UpperTorso") or botModel:FindFirstChild("Torso")
        or botModel:FindFirstChild("HumanoidRootPart")
    if not torso then return nil end
    local kind = c.kind
    setCarrying(player, nil)
    local bag = makeBag(kind, torso.CFrame * CFrame.new(0, 0, 1))
    local weld = Instance.new("WeldConstraint")
    weld.Part0, weld.Part1 = torso, bag
    weld.Parent = bag
    bag.Parent = botModel
    botBags[botModel] = { kind = kind, bag = bag, owner = player }
    botModel:SetAttribute("CarryingLoot", kind)
    styleBag(player, bag)
    return kind
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
    loadInto(trunk, b.kind, owner, botModel:GetAttribute("BotName") or botModel.Name)
    return true
end

function LootService:dropBot(botModel)
    local b = clearBotBag(botModel)
    if not b or not refs then return end
    local root = botModel and botModel:FindFirstChild("HumanoidRootPart")
    if root then spawnLoose(b.kind, root.CFrame * CFrame.new(0, -1, 1.5), nil, (b.owner and b.owner.Parent) and b.owner or nil) end
end

function LootService:counts()
    local take, taken = 0, 0
    for _, l in ipairs(loaded) do take = take + l.value end
    for _, p in ipairs(piles) do if p.taken then taken = taken + 1 end end
    local cases = 0
    for _, p in ipairs(piles) do if p.isCase then cases = cases + 1 end end
    local casesTaken = 0
    for _, p in ipairs(piles) do if p.isCase and p.taken then casesTaken = casesTaken + 1 end end
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
    return { total = #piles, loaded = #loaded, take = take, taken = taken, cases = cases, casesTaken = casesTaken,
        vault = vault, vaultTaken = vaultTaken, open = open, openTaken = openTaken }
end

-- v1.1: for the payout breakdown
function LootService:getLoaded()
    local out = {}
    for _, l in ipairs(loaded) do table.insert(out, { kind = l.kind, value = l.value, bot = l.bot }) end
    return out
end

-- v1.1: where untaken loot still is (for waypoints)
function LootService:remaining()
    local out = {}
    for _, p in ipairs(piles) do
        if not p.taken and p.anchor then
            table.insert(out, { pos = p.anchor.Position, kind = p.kind, isCase = p.isCase, locked = p.isVault and not vaultOpen })
        end
    end
    return out
end

function LootService:isCarrying(player)
    return carriers[player] ~= nil
end

function LootService:clearLoaded()
    loaded = {}
end

function LootService:setVaultOpen(open)
    vaultOpen = open
    for _, p in ipairs(piles) do
        if p.isVault and not p.taken then p.prompt.Enabled = open end
    end
end

-- ── lifecycle ────────────────────────────────────────────────────────
function LootService:disarm()
    for _, c in ipairs(conns) do c:Disconnect() end
    conns = {}
    for _, p in ipairs(piles) do
        hideVisual(p, false)
        if p.glass then
            p.glass.Transparency = p.glassT or 0.5
            p.glass.CanCollide = true
        end
        if p.anchor then p.anchor:Destroy() end
    end
    piles = {}
    for _, b in ipairs(loose) do if b.Parent then b:Destroy() end end
    loose = {}
    for player in pairs(carriers) do setCarrying(player, nil) end
    carriers = {}
    for bot in pairs(botBags) do clearBotBag(bot) end
    loaded = {}
    if trunkPrompt then trunkPrompt:Destroy() trunkPrompt = nil end
    currentTrunk = nil
    refs = nil
end

function LootService:arm(jobRefs)
    self:disarm()
    refs = jobRefs
    for _, spot in ipairs(refs.lootSpots or {}) do
        -- (fix v1.1) loot sitting out in the open (jewelry pink diamond / painting)
        -- is marked inVault = false by the builder and is grabbable straight away
        addPile(spot.kind, spot.visual, spot.cframe, refs.vault ~= nil and spot.inVault ~= false, false)
    end
    for _, case in ipairs(refs.smashCases or {}) do
        addPile(case.kind or "Jewels", case.visual, case.cframe, false, true, case.glass)
    end
    vaultOpen = false
    track(Players.PlayerRemoving:Connect(function(p)
        if carriers[p] then
            -- leave the bag where they stood so the crew can grab it
            local c = carriers[p]
            local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if root then spawnLoose(c.kind, root.CFrame, nil, p) end
            carriers[p] = nil
        end
    end))
end

function LootService:reset()
    for player in pairs(carriers) do setCarrying(player, nil) end
    carriers = {}
    for bot in pairs(botBags) do clearBotBag(bot) end
    for _, b in ipairs(loose) do if b.Parent then b:Destroy() end end
    loose = {}
    loaded = {}
    for _, p in ipairs(piles) do
        p.taken = false
        hideVisual(p, false)
        if p.glass then
            p.glass.Transparency = p.glassT or 0.5
            p.glass.CanCollide = true
        end
        p.prompt.Enabled = not p.isVault
    end
    vaultOpen = false
end

function LootService:init(callbacks, shopService)
    cb.onEvent = callbacks.onEvent or cb.onEvent
    Shop = shopService

    local throwRemote = Remotes.getRemote(Remotes.NAMES.ThrowBag, "RemoteEvent")
    local lastThrow = {}
    throwRemote.OnServerEvent:Connect(function(player, dir)
        local c = carriers[player]
        if not c or typeof(dir) ~= "Vector3" then return end
        if lastThrow[player] and os.clock() - lastThrow[player] < 0.5 then return end
        lastThrow[player] = os.clock()
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local flat = Vector3.new(dir.X, 0, dir.Z)
        if flat.Magnitude < 0.1 then flat = root.CFrame.LookVector end
        flat = flat.Unit
        local kind = c.kind
        setCarrying(player, nil)
        local muscle = player:GetAttribute("Role") == "Muscle"
        local speed = Constants.BAG_THROW_SPEED * (muscle and 1.3 or 1)
        -- v2.0 masks: 8-Bit Skull "POWER THROW" → twice as far (same arc height, 2x sideways speed)
        if maskHas(player, "powerthrow") then speed = speed * ((Constants.MASK_POWERS or {}).THROW_MULT or 2) end
        local bag = spawnLoose(kind, root.CFrame * CFrame.new(0, 1.5, -2.5), flat * speed + Vector3.new(0, 22, 0), player)
        cb.onEvent("throw", player, { kind = kind })
    end)

    -- (fix v1.1) dying / resetting while carrying drops the bag where you fell
    -- (it used to vanish with the old character, lost for the whole run)
    local function hook(player)
        local function onChar(char, existing)
            if not existing then
                carriers[player] = nil
                player:SetAttribute("CarryingLoot", nil)
            end
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                hum.Died:Connect(function()
                    local c = carriers[player]
                    if not c then return end
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if c.bag then c.bag:Destroy() end
                    carriers[player] = nil
                    player:SetAttribute("CarryingLoot", nil)
                    if root and refs then spawnLoose(c.kind, root.CFrame, nil, player) end
                end)
            end
        end
        player.CharacterAdded:Connect(onChar)
        if player.Character then task.spawn(onChar, player.Character, true) end
    end
    Players.PlayerAdded:Connect(hook)
    for _, player in ipairs(Players:GetPlayers()) do hook(player) end
end

return LootService
