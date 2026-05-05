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
--]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local PlayerDataService = {}

local cache = {}  -- [userId] = data table

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
        heistsCompleted = 0,
    }
end

function PlayerDataService:loadPlayer(player)
    local data = nil

    if store then
        local success, result = pcall(function()
            return store:GetAsync("Player_" .. player.UserId)
        end)
        if success and result then
            data = result
        end
    end

    if not data then
        data = makeDefaultData()
    end

    cache[player.UserId] = data
    print(string.format("[PlayerDataService] Loaded %s — cash: $%d, level: %d",
        player.Name, data.cash, data.level))
    return data
end

function PlayerDataService:savePlayer(player)
    local data = cache[player.UserId]
    if not data then return end

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
