--[[
    HEIST CREW — DailyRewardService
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Come back every day, get paid.

        DAY 1  $250    DAY 2  $400    DAY 3  $600    DAY 4  $800
        DAY 5  $1,000  DAY 6  $1,500  DAY 7  $3,000 + the SOLID GOLD bag skin

    • One claim every 20 hours (not "per calendar day", so time zones don't matter).
    • Miss more than 48 hours and the streak starts over at day 1.
    • After day 7 it loops back to day 1.
    • The player PRESSES claim (DailyRewardUI pops up on join) — nothing is paid
      automatically, so the kid sees the reward land.
    • If this player's save failed to load, claiming is refused: that session
      never saves, so the reward would vanish (and the real save still says
      "not claimed", which would let it be claimed twice).

    REMOTE: DailyReward (RemoteFunction)
        InvokeServer("status") -> { ok, day, amount, nextAt, msg, claimable, secondsLeft,
                                    streak, rewards = {amounts x7}, bonus = "Solid Gold bag" }
        InvokeServer("claim")  -> same shape; ok = true only if it paid
        day       = the day you can claim next (1..7)
        nextAt    = unix time (os.time) when it can be claimed (<= now if claimable)
        streak    = the last day you claimed (0 if the streak is broken)

    SAVE FIELDS (PlayerDataService): lastDailyAt (unix s), dailyStreak (1..7)

    PUBLIC API:
        DailyRewardService:init(PlayerDataService, EconomyService, notify [, CosmeticsService])
        DailyRewardService:status(player) -> table   (same as the remote)
        DailyRewardService:claim(player)  -> table
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DailyRewardService = {}

local REWARDS = { 250, 400, 600, 800, 1000, 1500, 3000 }
local DAY7_ITEM = "BagGold"             -- CosmeticsService item id
local DAY7_ITEM_NAME = "Solid Gold bag"
local DAY7_DUPE_BONUS = 1000            -- already own the gold bag? extra cash instead
local COOLDOWN = 20 * 3600
local STREAK_BREAK = 48 * 3600

DailyRewardService.REWARDS = REWARDS

local PlayerData, Economy, Cosmetics = nil, nil, nil
local notify = function() end
local initialized = false
local busy = {}

local function cosmetics()
    if Cosmetics then return Cosmetics end
    local mod = script.Parent:FindFirstChild("CosmeticsService")
    if mod then
        local ok, result = pcall(require, mod)
        if ok and type(result) == "table" then Cosmetics = result end
    end
    return Cosmetics
end

local function fmtWait(secs)
    secs = math.max(0, math.floor(secs))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return "a moment"
end

local function money(n)
    local s = tostring(math.floor(n))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return "$" .. s
end

-- Work out where this player stands right now (pure — changes nothing)
local function compute(d, now)
    local last = tonumber(d.lastDailyAt) or 0
    local streak = math.clamp(math.floor(tonumber(d.dailyStreak) or 0), 0, 7)
    local since = now - last
    if last <= 0 or since > STREAK_BREAK then streak = 0 end   -- never / missed a day: start over
    local claimable = last <= 0 or since >= COOLDOWN
    local day = (streak % 7) + 1
    local nextAt = claimable and now or (last + COOLDOWN)
    return {
        claimable = claimable,
        day = day,
        streak = streak,
        amount = REWARDS[day],
        nextAt = nextAt,
        secondsLeft = math.max(0, nextAt - now),
    }
end

local function reply(ok, c, msg)
    return {
        ok = ok, msg = msg or "",
        day = c and c.day or 1, amount = c and c.amount or REWARDS[1],
        nextAt = c and c.nextAt or 0, secondsLeft = c and c.secondsLeft or 0,
        claimable = c and c.claimable or false, streak = c and c.streak or 0,
        rewards = REWARDS, bonus = DAY7_ITEM_NAME,
    }
end

function DailyRewardService:status(player)
    local d = PlayerData and PlayerData:getData(player)
    if not d then return reply(false, nil, "Loading your save...") end
    local c = compute(d, os.time())
    local r
    if c.claimable then
        r = reply(true, c, string.format("DAY %d — %s — CLAIM!", c.day, money(c.amount)))
    else
        r = reply(true, c, "Next reward in " .. fmtWait(c.secondsLeft))
    end
    -- (v2.1) tell the client up front when the save didn't load (Studio without API access)
    local okF, failed = pcall(function() return PlayerData.loadFailed and PlayerData:loadFailed(player) end)
    r.saveFailed = okF and failed == true or false
    return r
end

function DailyRewardService:claim(player)
    local d = PlayerData and PlayerData:getData(player)
    if not d then return reply(false, nil, "Loading your save... try again in a second") end
    if PlayerData.loadFailed and PlayerData:loadFailed(player) then
        return reply(false, compute(d, os.time()),
            "Your save didn't load, so rewards are paused. Rejoin to claim!")
    end
    local now = os.time()
    local c = compute(d, now)
    if not c.claimable then
        return reply(false, c, "Come back in " .. fmtWait(c.secondsLeft) .. "!")
    end

    -- mark it FIRST so nothing can double-pay
    d.lastDailyAt = now
    d.dailyStreak = c.day
    Economy:addCash(player, c.amount, "Daily reward day " .. c.day)

    local msg = string.format("Day %d reward: +%s!", c.day, money(c.amount))
    if c.day == 7 then
        local C = cosmetics()
        local granted = C and C.grant and C:grant(player, DAY7_ITEM)
        if granted then
            msg = string.format("Day 7! +%s and the %s!", money(c.amount), DAY7_ITEM_NAME)
        else
            Economy:addCash(player, DAY7_DUPE_BONUS, "Daily reward day 7 bonus")
            msg = string.format("Day 7! +%s (+%s bonus)!", money(c.amount), money(DAY7_DUPE_BONUS))
        end
    end
    notify(player, msg, "gold", 5)

    -- save now: a crash before they leave shouldn't hand out a second claim
    task.spawn(function()
        if player.Parent then PlayerData:savePlayer(player) end
    end)

    local after = compute(d, now)
    return reply(true, {
        claimable = false, day = c.day, streak = c.day, amount = c.amount,
        nextAt = after.nextAt, secondsLeft = after.secondsLeft,
    }, msg)
end

-- The bootstrap makes every remote a RemoteEvent except ShopAction, so this
-- one may already exist as the wrong class. Swap it for a RemoteFunction.
local function getRemoteFunction()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if not folder then
        Remotes.getRemote(Remotes.NAMES.ShopAction, "RemoteFunction")   -- creates the folder
        folder = ReplicatedStorage:FindFirstChild("Remotes")
    end
    local name = Remotes.NAMES.DailyReward or "DailyReward"
    local r = folder:FindFirstChild(name)
    if r and not r:IsA("RemoteFunction") then
        warn("[DailyRewardService] DailyReward was a " .. r.ClassName .. " — replacing it with a RemoteFunction")
        r:Destroy()
        r = nil
    end
    if not r then
        r = Instance.new("RemoteFunction")
        r.Name = name
        r.Parent = folder
    end
    return r
end

function DailyRewardService:init(playerDataService, economyService, notifyFn, cosmeticsService)
    PlayerData = playerDataService or PlayerData
    Economy = economyService or Economy
    notify = notifyFn or notify
    Cosmetics = cosmeticsService or Cosmetics
    if initialized then return end
    initialized = true

    local remote = getRemoteFunction()
    remote.OnServerInvoke = function(player, action)
        if action == "claim" then
            if busy[player] then return reply(false, nil, "One sec...") end
            busy[player] = true
            local ok, res = pcall(function() return self:claim(player) end)
            busy[player] = nil
            if ok then return res end
            warn("[DailyRewardService] claim failed:", res)
            return reply(false, nil, "Something went wrong. Try again!")
        end
        local ok, res = pcall(function() return self:status(player) end)
        if ok then return res end
        warn("[DailyRewardService] status failed:", res)
        return reply(false, nil, "Something went wrong.")
    end

    Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
    print("[DailyRewardService] 7-day streak rewards online")
end

return DailyRewardService
