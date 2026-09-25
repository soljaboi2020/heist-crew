--[[
    HEIST CREW — ShopService
    ────────────────────────────────────────────────
    v1.0. Everything you spend cash on, plus the free stuff:
      • GEAR  — passive perks bought once (Constants.GEAR). "Gear" attribute.
      • MASKS — Roblox-made catalog masks (Constants.MASKS). Worn automatically
                while a job is running (wearMask / removeMask, called by JobService).
      • CODES — promo codes → cash, once each (Constants.CODES).
      • VIP   — game pass (Constants.GAMEPASSES.VIP). Inert while the id is 0.
      • DAILY — login reward on join, streak day N pays DAILY_BASE * N (cap 7).

    Talks to the client through the ShopAction RemoteFunction:
        action, payload -> { ok, msg, state }
    Every rule is enforced HERE (price, ownership, once-per-code); the client
    only asks.

    PUBLIC API:
        ShopService:init(PlayerDataService, EconomyService, notifyFn)
        ShopService:onPlayerJoined(player)       -- attributes, VIP check, daily reward
        ShopService:hasGear(player, id) -> bool
        ShopService:wearMask(player) / ShopService:removeMask(player)
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

local GEAR_BY_ID, MASK_BY_ID = {}, {}
for _, g in ipairs(Constants.GEAR) do GEAR_BY_ID[g.id] = g end
for _, m in ipairs(Constants.MASKS) do MASK_BY_ID[m.id] = m end

local maskTemplates = {}   -- assetId -> Accessory (never parented)

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
    return {
        cash = d.cash, gear = gear, masks = masks, mask = d.mask,
        vip = player:GetAttribute("VIP") == true,
        vipPassId = Constants.GAMEPASSES.VIP or 0,
        codesRedeemed = codes,
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
        if hum then hum.WalkSpeed = 18 end
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
    return true, m.name .. " mask equipped"
end

function actions.equipMask(player, payload)
    local m = MASK_BY_ID[payload and payload.id]
    local d = PlayerData:getData(player)
    if not m or not d then return false, "Unknown mask" end
    if not d.masks[m.id] then return false, "You don't own that mask" end
    d.mask = m.id
    syncAttributes(player)
    if player.Character and player.Character:FindFirstChild("HC_Mask") then
        ShopService:wearMask(player)   -- swap it live if they're wearing one
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
    local m = MASK_BY_ID[d.mask] or MASK_BY_ID.Bandit
    task.spawn(function()
        local template = getMaskTemplate(m.assetId)
        if not template or not char.Parent then return end
        local acc = template:Clone()
        acc.Name = "HC_Mask"
        for _, d2 in ipairs(acc:GetDescendants()) do
            if d2:IsA("Script") or d2:IsA("LocalScript") then d2:Destroy() end
        end
        pcall(function() hum:AddAccessory(acc) end)
    end)
end

function ShopService:removeMask(player)
    local char = player.Character
    local old = char and char:FindFirstChild("HC_Mask")
    if old then old:Destroy() end
end

function ShopService:hasGear(player, id)
    local d = PlayerData and PlayerData:getData(player)
    return d ~= nil and d.gear[id] == true
end

-- ── daily reward ─────────────────────────────────────────────────────
local function daily(player)
    local d = PlayerData:getData(player)
    if not d then return end
    local today = math.floor(os.time() / 86400)
    if d.dailyDay == today then return end
    if d.dailyDay == today - 1 then
        d.dailyStreak = math.min((d.dailyStreak or 0) + 1, 7)
    else
        d.dailyStreak = 1
    end
    d.dailyDay = today
    local reward = Constants.DAILY_BASE * d.dailyStreak
    Economy:addCash(player, reward, "Daily reward day " .. d.dailyStreak)
    task.delay(3, function()
        if player.Parent then
            notify(player, string.format("Daily reward — day %d streak: +$%d", d.dailyStreak, reward), "green", 5)
        end
    end)
end

function ShopService:onPlayerJoined(player)
    syncAttributes(player)
    checkVIP(player)
    daily(player)
end

function ShopService:init(playerDataService, economyService, notifyFn)
    PlayerData = playerDataService
    Economy = economyService
    notify = notifyFn or notify

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
    print("[ShopService] Gear, masks, codes, VIP + daily online 🛍")
end

return ShopService
