--[[
    HEIST CREW — ProgressService
    ────────────────────────────────────────────────
    v1.0. XP + levels. XP from finishing runs, secured bags and stealth
    (Constants.XP). XP needed to go from level L to L+1 = LEVEL_BASE * L.
    Mirrors Level / XP / XPNext to player attributes for the HUD.

    PUBLIC API:
        ProgressService:init(PlayerDataService, notifyFn)
        ProgressService:sync(player)
        ProgressService:addXP(player, amount, reason)
        ProgressService:getLevel(player) -> number
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Constants)

local ProgressService = {}
local PlayerData = nil
local notify = function() end

local function need(level)
    return Constants.XP.LEVEL_BASE * level
end

function ProgressService:init(playerDataService, notifyFn)
    PlayerData = playerDataService
    notify = notifyFn or notify
end

function ProgressService:sync(player)
    local d = PlayerData and PlayerData:getData(player)
    if not d then return end
    player:SetAttribute("Level", d.level or 1)
    player:SetAttribute("XP", d.xp or 0)
    player:SetAttribute("XPNext", need(d.level or 1))
    -- v1.1: first-timers get coaching tips until they finish a heist
    player:SetAttribute("Rookie", (d.heistsCompleted or 0) == 0)
end

function ProgressService:addXP(player, amount, reason)
    local d = PlayerData and PlayerData:getData(player)
    if not d or amount <= 0 then return end
    d.xp = (d.xp or 0) + math.floor(amount)
    d.level = d.level or 1
    local leveled = false
    while d.xp >= need(d.level) do
        d.xp = d.xp - need(d.level)
        d.level = d.level + 1
        leveled = true
    end
    self:sync(player)
    if leveled then
        notify(player, string.format("LEVEL UP — you're level %d", d.level), "gold", 4)
        for _, job in ipairs(Constants.JOBS) do
            if job.unlockLevel == d.level then
                notify(player, string.format("New job unlocked: %s", job.name), "gold", 5)
            end
        end
    end
end

function ProgressService:getLevel(player)
    local d = PlayerData and PlayerData:getData(player)
    return d and d.level or 1
end

return ProgressService
