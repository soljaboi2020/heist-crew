--[[
    HEIST CREW — PlayerDataService
    ────────────────────────────────────────────────
    Wraps Roblox DataStoreService. Loads a player's saved data on join,
    keeps it in an in-memory cache while they play, saves on leave + shutdown.

    DESIGN:
    - DataStores don't work in Studio without "Allow API Access" enabled.
      We pcall everything so the server falls back to in-memory only — you
      can still test the game in Studio, you just won't persist between
      Play sessions until you publish or enable API access.

    PUBLIC API:
        PlayerDataService:loadPlayer(player)   → fills cache, returns data
        PlayerDataService:savePlayer(player)   → writes to DataStore
        PlayerDataService:getData(player)      → returns the cache table
        PlayerDataService:setCash(player, n)   → overwrites cash
        PlayerDataService:addCash(player, n)   → adds to cash, returns new balance
        PlayerDataService:addLifetimeEarned(player, n) → total heist cash ever earned (leaderboard)
        PlayerDataService:isReady(player)      → true once loaded AND the load didn't fail
        PlayerDataService:loadFailed(player)   → true if this session will never save

    v2.0 SAVE FIELDS (all migrated in for old saves — see migrate()):
        lastDailyAt       unix seconds of the last daily-reward claim (0 = never)
        dailyStreak       day (1..7) of the last claim; next claim is day+1 (DailyRewardService)
        lifetimeEarned    heist cash ever paid out (LeaderboardService "TOP EARNERS")
        cosmetics         { [itemId] = true }  owned bag skins / car colors / trails
        equippedCosmetics { bag = id, car = id, trail = id }  (CosmeticsService)

    v3.1 SAVE FIELD (first-time tutorial, TutorialService):
        tutorialDone      bool. New players start false (TutorialService offers the
                          Sunny's Mart walkthrough). OLD saves with no field are
                          migrated to `heistsCompleted > 0` so veterans never get it.
        PlayerDataService:isTutorialDone(player)   -> bool (true if not loaded yet / load failed:
                                                      never nag someone whose real save we can't see)
        PlayerDataService:markTutorialDone(player) -> bool  true only the FIRST time (reward-once guard)
--]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local PlayerDataService = {}

local cache = {}  -- [userId] = data table
local loadFailed = {}  -- [userId] = true → NEVER save over their real data this session

-- DataStore key. Bump the version suffix if you ever change the data shape
-- in a way that breaks old saves.
local STORE_NAME = "HeistCrewPlayerData_v1"

local store = nil
local ok, result = pcall(function()
    return DataStoreService:GetDataStore(STORE_NAME)
end)
if ok then
    store = result
    print("[PlayerDataService] DataStore connected ✅")
else
    warn("[PlayerDataService] DataStore unavailable — running in-memory only. " ..
         "(Normal in Studio without 'Allow API Access' enabled.)")
end

-- Default data for brand new players
local function makeDefaultData()
    return {
        cash = Constants.STARTING_CASH,
        level = 1,
        xp = 0,
        heistsCompleted = 0,
        gear = {},              -- [gearId] = true
        masks = { Bandit = true },
        mask = "Bandit",
        codes = {},             -- [CODE] = true
        dailyDay = 0,           -- (v1.x, retired) day number of the last auto-claim
        dailyStreak = 0,        -- v2: day 1..7 of the last claim
        lastDailyAt = 0,        -- v2: unix seconds of the last claim
        bagsSecured = 0,
        lifetimeEarned = 0,     -- v2: heist cash ever earned (leaderboard)
        cosmetics = {},         -- v2: [itemId] = true
        equippedCosmetics = {}, -- v2: { bag, car, trail }
        tutorialDone = false,   -- v3.1: finished or skipped the first-time tutorial
    }
end

-- v1.0: older saves (v0.x) only had cash/level/heistsCompleted. Fill anything
-- missing so every service can assume the full shape.
local function migrate(data)
    if type(data) ~= "table" then data = {} end
    -- v2.0: daily reward moved from "calendar day index" to real timestamps.
    -- Carry an old v1.x claim over so the streak isn't lost.
    local oldDay = tonumber(data.dailyDay)
    if data.lastDailyAt == nil and oldDay and oldDay > 0 then
        data.lastDailyAt = oldDay * 86400
    end
    -- v2.0: the leaderboard counts lifetime earnings. Old saves never tracked
    -- it, so seed it with what they're holding (they earned at least that).
    if data.lifetimeEarned == nil and tonumber(data.cash) then
        data.lifetimeEarned = math.max(0, math.floor(data.cash - Constants.STARTING_CASH))
    end
    -- v3.1: the first-time tutorial. An old save (no field) that already
    -- finished a heist doesn't need it; an old save with 0 heists gets offered it.
    if data.tutorialDone == nil then
        data.tutorialDone = (tonumber(data.heistsCompleted) or 0) > 0
    end
    local defaults = makeDefaultData()
    for k, v in pairs(defaults) do
        if data[k] == nil then data[k] = v end
    end
    if type(data.masks) ~= "table" then data.masks = { Bandit = true } end
    data.masks.Bandit = true
    for _, k in ipairs({ "gear", "codes", "cosmetics", "equippedCosmetics" }) do
        if type(data[k]) ~= "table" then data[k] = {} end
    end
    for _, k in ipairs({ "lastDailyAt", "dailyStreak", "lifetimeEarned", "heistsCompleted" }) do
        if type(data[k]) ~= "number" then data[k] = tonumber(data[k]) or 0 end
    end
    data.dailyStreak = math.clamp(math.floor(data.dailyStreak), 0, 7)
    data.tutorialDone = data.tutorialDone == true
    return data
end

function PlayerDataService:loadPlayer(player)
    local data = nil

    if store then
        -- (fix v1.1) retry, and if the read truly fails, play on defaults but
        -- never save — saving defaults would wipe the player's real progress
        local ok = false
        for attempt = 1, 3 do
            local success, result = pcall(function()
                return store:GetAsync("Player_" .. player.UserId)
            end)
            if success then
                ok = true
                if result then data = result end
                break
            end
            warn(string.format("[PlayerDataService] load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
            task.wait(attempt)
        end
        if not ok then
            loadFailed[player.UserId] = true
            warn("[PlayerDataService] " .. player.Name .. " couldn't be loaded — this session won't save")
        end
    end

    if not data then
        data = makeDefaultData()
    end
    data = migrate(data)

    cache[player.UserId] = data
    print(string.format("[PlayerDataService] Loaded %s — cash: $%d, level: %d",
        player.Name, data.cash, data.level))
    return data
end

function PlayerDataService:savePlayer(player)
    local data = cache[player.UserId]
    if not data then return end
    if loadFailed[player.UserId] then
        warn("[PlayerDataService] not saving " .. player.Name .. " — their load failed earlier")
        return
    end

    if store then
        local success, err = pcall(function()
            store:SetAsync("Player_" .. player.UserId, data)
        end)
        if success then
            print(string.format("[PlayerDataService] Saved %s — cash: $%d", player.Name, data.cash))
        else
            warn(string.format("[PlayerDataService] FAILED to save %s: %s", player.Name, tostring(err)))
        end
    end
end

function PlayerDataService:isReady(player)
    return cache[player.UserId] ~= nil and not loadFailed[player.UserId]
end

function PlayerDataService:loadFailed(player)
    return loadFailed[player.UserId] == true
end

-- v2.0: total heist cash ever earned (the TOP EARNERS board). Call it next to
-- every heist payout (JobService) — NOT for codes, daily rewards or refunds.
function PlayerDataService:addLifetimeEarned(player, amount)
    local data = cache[player.UserId]
    amount = tonumber(amount)
    if not data or not amount or amount <= 0 then return data and data.lifetimeEarned or 0 end
    data.lifetimeEarned = math.floor((tonumber(data.lifetimeEarned) or 0) + amount)
    return data.lifetimeEarned
end

-- v3.1 first-time tutorial (TutorialService)
function PlayerDataService:isTutorialDone(player)
    local data = cache[player.UserId]
    if not data or loadFailed[player.UserId] then return true end
    return data.tutorialDone == true
end

-- true only the first time (so the tutorial reward can never be paid twice)
function PlayerDataService:markTutorialDone(player)
    local data = cache[player.UserId]
    if not data or data.tutorialDone == true then return false end
    data.tutorialDone = true
    return true
end

function PlayerDataService:getData(player)
    return cache[player.UserId]
end

function PlayerDataService:setCash(player, amount)
    local data = cache[player.UserId]
    if not data then return end
    data.cash = math.max(0, math.floor(amount))
end

function PlayerDataService:addCash(player, amount)
    local data = cache[player.UserId]
    if not data then return 0 end
    data.cash = math.max(0, math.floor(data.cash + amount))
    return data.cash
end

return PlayerDataService
