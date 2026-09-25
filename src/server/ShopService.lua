--[[
    HEIST CREW — ShopService
    ────────────────────────────────────────────────
    v1.0. Everything you spend cash on, plus the free stuff:
      • GEAR  — passive perks bought once (Constants.GEAR). "Gear" attribute.
      • MASKS — Roblox-made catalog masks (Constants.MASKS). Worn automatically
                while a job is running (wearMask / removeMask, called by JobService).
      • CODES — promo codes → cash, once each (Constants.CODES).
      • VIP   — game pass (Constants.GAMEPASSES.VIP). Inert while the id is 0.
      • COSMETICS (v2.0) — bag skins / car colors / trails. The item list and
                the rules live in CosmeticsService; this just routes the actions
                and ships the catalog to the client inside getState.
      (v2.0: the daily reward moved to DailyRewardService — you press CLAIM now.)

    Talks to the client through the ShopAction RemoteFunction:
        action, payload -> { ok, msg, state }
    actions: getState · buyGear{id} · buyMask{id} · equipMask{id} · redeemCode{code} · buyVIP
             · buyCosmetic{id} · equipCosmetic{id}                                   (v2.0)
    state.cosmetics = { catalog = {items}, owned = {ids}, equipped = {bag, car, trail} }
    (v2.0 masks agent)
      · MASK POWERS — every Constants.MASKS entry has `ability = {id,name,desc}`.
        wearMask/removeMask switch the power on/off through MaskService.
        state.maskPower = active ability id (or nil) · each state.maskList row
        = { id, name, price, owned, equipped, ability = {id,name,desc} }
      · ROBUX PACKS — state.robuxPacks = { {id, name, cash, robux, available} }
        (available = productId ~= 0). action buyRobuxPack{id} opens the Roblox
        purchase prompt; RobuxService.ProcessReceipt grants the cash.
    Every rule is enforced HERE (price, ownership, once-per-code); the client
    only asks.

    PUBLIC API:
        ShopService:init(PlayerDataService, EconomyService, notifyFn)
        ShopService:onPlayerJoined(player)       -- attributes, VIP check
        ShopService:hasGear(player, id) -> bool
        ShopService:wearMask(player) / ShopService:removeMask(player)
        ShopService:getEquippedMask(player) -> maskId        (v2.0, MaskService reads it)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local MarketplaceService = game:GetService("MarketplaceService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ShopService = {}
local PlayerData, Economy = nil, nil
local notify = function() end

-- v2.0 cosmetics (bag skins / car colors / trails) — its own module, loaded
-- defensively so a broken CosmeticsService can't take the shop down.
local Cosmetics = nil
do
    local mod = script.Parent:FindFirstChild("CosmeticsService")
    if mod then
        local ok, result = pcall(require, mod)
        if ok and type(result) == "table" then
            Cosmetics = result
        else
            warn("[ShopService] CosmeticsService failed to load: " .. tostring(result))
        end
    end
end

-- v2.0 mask powers (masks agent) — optional, looked up lazily so there's no
-- require cycle (MaskService reads the equipped mask back through this file).
local maskServiceCache = nil
local function maskService()
    if maskServiceCache ~= nil then return maskServiceCache or nil end
    local mod = script.Parent:FindFirstChild("MaskService")
    local ok, result = false, nil
    if mod then ok, result = pcall(require, mod) end
    maskServiceCache = (ok and type(result) == "table") and result or false
    return maskServiceCache or nil
end
local function maskPower(method, player)
    local MS = maskService()
    if MS and type(MS[method]) == "function" then
        local ok, err = pcall(MS[method], MS, player)
        if not ok then warn("[ShopService] MaskService:" .. method, err) end
    end
end

local GEAR_BY_ID, MASK_BY_ID = {}, {}
for _, g in ipairs(Constants.GEAR) do GEAR_BY_ID[g.id] = g end
for _, m in ipairs(Constants.MASKS) do MASK_BY_ID[m.id] = m end

local maskTemplates = {}   -- assetId -> Accessory (never parented)
local wearing = {}         -- [player] = true while a mask should be on

local function gearString(d)
    local owned = {}
    for _, g in ipairs(Constants.GEAR) do
        if d.gear[g.id] then table.insert(owned, g.id) end
    end
    return table.concat(owned, ",")
end

local function syncAttributes(player)
    local d = PlayerData:getData(player)
    if not d then return end
    player:SetAttribute("Gear", gearString(d))
    player:SetAttribute("Mask", d.mask)
end

local function stateFor(player)
    local d = PlayerData:getData(player)
    if not d then return {} end
    local gear, masks, codes = {}, {}, {}
    for id in pairs(d.gear) do table.insert(gear, id) end
    for id in pairs(d.masks) do table.insert(masks, id) end
    for c in pairs(d.codes) do table.insert(codes, c) end
    local cosmetics = nil
    if Cosmetics then
        local ok, cs = pcall(function() return Cosmetics:stateFor(player) end)
        if ok and type(cs) == "table" then
            cs.catalog = Cosmetics:catalog()
            cosmetics = cs
        end
    end
    -- v2.0: masks with their powers (so the shop can say what each one does)
    local maskList = {}
    for _, m in ipairs(Constants.MASKS) do
        table.insert(maskList, {
            id = m.id, name = m.name, price = m.price, assetId = m.assetId,
            owned = d.masks[m.id] == true, equipped = d.mask == m.id,
            ability = m.ability,
        })
    end
    -- v2.0: Robux → cash packs (hidden until the owner pastes a productId)
    local robuxPacks = {}
    for _, pk in ipairs(Constants.ROBUX_PACKS or {}) do
        table.insert(robuxPacks, {
            id = pk.id, name = pk.name, cash = pk.cash, robux = pk.robux,
            available = (tonumber(pk.productId) or 0) ~= 0,
        })
    end
    return {
        cash = d.cash, gear = gear, masks = masks, mask = d.mask,
        maskList = maskList,
        maskPower = player:GetAttribute("MaskPower"),
        robuxPacks = robuxPacks,
        vip = player:GetAttribute("VIP") == true,
        vipPassId = Constants.GAMEPASSES.VIP or 0,
        codesRedeemed = codes,
        cosmetics = cosmetics,
    }
end

local function checkVIP(player)
    local id = Constants.GAMEPASSES.VIP or 0
    if id == 0 then
        player:SetAttribute("VIP", false)
        return
    end
    local ok, owns = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
    end)
    player:SetAttribute("VIP", ok and owns == true)
end

-- ── actions ──────────────────────────────────────────────────────────
local actions = {}

function actions.getState(player)
    return true, ""
end

function actions.buyGear(player, payload)
    local g = GEAR_BY_ID[payload and payload.id]
    local d = PlayerData:getData(player)
    if not g or not d then return false, "Unknown item" end
    if d.gear[g.id] then return false, "You already own that" end
    if not Economy:spend(player, g.price, "Gear: " .. g.id) then return false, "Not enough cash" end
    d.gear[g.id] = true
    syncAttributes(player)
    if g.id == "Sneakers" and not player:GetAttribute("CarryingLoot") then
        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 18 * (tonumber(player:GetAttribute("SpeedMult")) or 1) end
    end
    return true, g.name .. " unlocked"
end

function actions.buyMask(player, payload)
    local m = MASK_BY_ID[payload and payload.id]
    local d = PlayerData:getData(player)
    if not m or not d then return false, "Unknown mask" end
    if d.masks[m.id] then return false, "You already own that" end
    if not Economy:spend(player, m.price, "Mask: " .. m.id) then return false, "Not enough cash" end
    d.masks[m.id] = true
    d.mask = m.id
    syncAttributes(player)
    -- (v2.1 fix) buying = equipping, so mid-heist swap the worn mask + its power
    -- too (it used to leave the old mask on with the OLD power)
    if wearing[player] or (player.Character and player.Character:FindFirstChild("HC_Mask")) then
        ShopService:wearMask(player)
    end
    return true, m.name .. " mask equipped"
end

function actions.equipMask(player, payload)
    local m = MASK_BY_ID[payload and payload.id]
    local d = PlayerData:getData(player)
    if not m or not d then return false, "Unknown mask" end
    if not d.masks[m.id] then return false, "You don't own that mask" end
    d.mask = m.id
    syncAttributes(player)
    if wearing[player] or (player.Character and player.Character:FindFirstChild("HC_Mask")) then
        ShopService:wearMask(player)   -- swap it live if they're wearing one (v2.0: + its power)
    end
    return true, m.name .. " equipped"
end

function actions.redeemCode(player, payload)
    local d = PlayerData:getData(player)
    local code = payload and type(payload.code) == "string" and string.upper((payload.code:gsub("%s", ""))) or ""
    local reward = Constants.CODES[code]
    if not d or not reward then return false, "That code doesn't exist" end
    if d.codes[code] then return false, "Already redeemed" end
    d.codes[code] = true
    Economy:addCash(player, reward, "Code " .. code)
    return true, string.format("Code redeemed — +$%d", reward)
end

function actions.buyVIP(player)
    local id = Constants.GAMEPASSES.VIP or 0
    if id == 0 then return false, "VIP isn't available yet" end
    MarketplaceService:PromptGamePassPurchase(player, id)
    return true, ""
end

-- v2.0: Robux → cash. This only OPENS the Roblox purchase prompt; the cash is
-- granted by RobuxService's ProcessReceipt (never here — the client can't be trusted).
function actions.buyRobuxPack(player, payload)
    local id = payload and payload.id
    for _, pk in ipairs(Constants.ROBUX_PACKS or {}) do
        if pk.id == id then
            local productId = tonumber(pk.productId) or 0
            if productId == 0 then return false, "That cash pack isn't in the store yet" end
            MarketplaceService:PromptProductPurchase(player, productId)
            return true, ""
        end
    end
    return false, "Unknown cash pack"
end

function actions.buyCosmetic(player, payload)
    if not Cosmetics then return false, "Cosmetics aren't available right now" end
    return Cosmetics:buy(player, payload and payload.id)
end

function actions.equipCosmetic(player, payload)
    if not Cosmetics then return false, "Cosmetics aren't available right now" end
    return Cosmetics:equip(player, payload and payload.id)
end

-- ── masks ────────────────────────────────────────────────────────────
local function getMaskTemplate(assetId)
    if maskTemplates[assetId] ~= nil then return maskTemplates[assetId] or nil end
    local ok, container = pcall(function() return InsertService:LoadAsset(assetId) end)
    local acc = ok and container and container:FindFirstChildWhichIsA("Accessory", true)
    maskTemplates[assetId] = acc or false
    if not acc then warn("[ShopService] couldn't load mask", assetId, container) end
    return acc
end

function ShopService:wearMask(player)
    local d = PlayerData and PlayerData:getData(player)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not d or not hum then return end
    self:removeMask(player)
    wearing[player] = true
    local m = MASK_BY_ID[d.mask] or MASK_BY_ID.Bandit
    maskPower("activate", player)   -- v2.0: the mask's power turns on with it
    task.spawn(function()
        local template = getMaskTemplate(m.assetId)
        -- (fix v1.1) the load can finish after the run already ended
        if not template or not char.Parent or not wearing[player] then return end
        local acc = template:Clone()
        acc.Name = "HC_Mask"
        for _, d2 in ipairs(acc:GetDescendants()) do
            if d2:IsA("Script") or d2:IsA("LocalScript") then d2:Destroy() end
        end
        pcall(function() hum:AddAccessory(acc) end)
    end)
end

function ShopService:removeMask(player)
    wearing[player] = nil
    maskPower("deactivate", player)   -- v2.0: power off with the mask
    local char = player.Character
    local old = char and char:FindFirstChild("HC_Mask")
    if old then old:Destroy() end
end

-- v2.0: the mask the player has picked (MaskService reads this)
function ShopService:getEquippedMask(player)
    local d = PlayerData and PlayerData:getData(player)
    local id = d and d.mask
    return (id and MASK_BY_ID[id]) and id or "Bandit"
end

function ShopService:hasGear(player, id)
    local d = PlayerData and PlayerData:getData(player)
    return d ~= nil and d.gear[id] == true
end

function ShopService:onPlayerJoined(player)
    syncAttributes(player)
    checkVIP(player)
    -- (v2.1 fix) died / reset mid-heist: the new body had no mask while the power
    -- stayed on. Put it back on (after init.server / MaskService fix WalkSpeed).
    player.CharacterAdded:Connect(function(char)
        if not wearing[player] then return end
        task.delay(1, function()
            if wearing[player] and player.Character == char and char.Parent
                and not char:FindFirstChild("HC_Mask") then
                ShopService:wearMask(player)
            end
        end)
    end)
end

function ShopService:init(playerDataService, economyService, notifyFn)
    PlayerData = playerDataService
    Economy = economyService
    notify = notifyFn or notify
    -- CosmeticsService:init is idempotent — the bootstrap may also call it.
    if Cosmetics then
        local ok, err = pcall(function() Cosmetics:init(PlayerData, Economy, notify) end)
        if not ok then warn("[ShopService] CosmeticsService:init failed: " .. tostring(err)) end
    end

    local remote = Remotes.getRemote(Remotes.NAMES.ShopAction, "RemoteFunction")
    local busy = {}
    remote.OnServerInvoke = function(player, action, payload)
        if busy[player] then return { ok = false, msg = "One sec…", state = stateFor(player) } end
        local fn = actions[action]
        if type(fn) ~= "function" then
            return { ok = false, msg = "Unknown action", state = stateFor(player) }
        end
        busy[player] = true
        local okCall, ok, msg = pcall(fn, player, type(payload) == "table" and payload or {})
        busy[player] = nil
        if not okCall then
            warn("[ShopService] action failed:", action, ok)
            return { ok = false, msg = "Something went wrong", state = stateFor(player) }
        end
        return { ok = ok, msg = msg or "", state = stateFor(player) }
    end

    MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
        if purchased and passId == (Constants.GAMEPASSES.VIP or 0) then
            player:SetAttribute("VIP", true)
            notify(player, "VIP unlocked — +10% on every payout", "gold", 5)
        end
    end)

    Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
    print("[ShopService] Gear, masks, cosmetics, codes + VIP online 🛍")
end

return ShopService
