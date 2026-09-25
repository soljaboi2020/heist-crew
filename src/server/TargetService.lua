--[[
    HEIST CREW — TargetService  (v3.0 "THE SCORE", LOOT-CORE · docs/V3_SPEC.md §2.5, §4)
    ────────────────────────────────────────────────
    The Boss's named TARGET for each heist (exactly one per job):
        mart    Golden Ticket   · villa Golden Flamingo
        jewelry Pink Diamond    · bank  Crown Jewel
    (Constants.LOOT_V3.TARGETS — kind, name, Boss line.)

    Loading the target into the getaway car SECURES it:
      • the crew gets +$5,000 on top of the take (bonusFor — JobService pays it)
      • the player who loaded it (for a bot load: the bag's owner) gets a saved
        TARGET TROPHY — data.targetTrophies[kind] = true in their save
        (PlayerDataService saves the whole data table, so no new API needed)
      • the club's BOSS TARGETS wall (ClubBuilder) lights that trophy's plinth
        while ANYONE in the server owns it. The wall is found through
        CollectionService tag "TargetTrophy" (attribute TargetKind); we set its
        attribute Owned = true/false and ClubBuilder draws it.

    For the HUD: ReplicatedStorage attributes
        TargetKind, TargetName, TargetLine, TargetBonus (number), TargetSecured (bool)
    follow the ActiveJob attribute (set by JobService when a job is armed).

    LootService calls onSecured (on every load) and resetRun (arm / reset /
    clearLoaded). It also calls init() for you, so this works with no wiring.

    PUBLIC API (§4):
        TargetService:init(deps?)                    -- idempotent. deps = { data = PlayerDataService, feel = FeelService }
        TargetService:targetFor(jobId) -> { kind, name, line, bonus } | nil
        TargetService:isTarget(kind, jobId?) -> bool
        TargetService:onSecured(player|nil, kind) -> bool      -- true if that was this job's target
        TargetService:bonusFor(run?) -> number       -- TARGET_BONUS if secured this run, else 0
                                                     --   run.jobId (if given) must match the armed job
        TargetService:isSecured() -> bool, securedBy (Player|nil)
        TargetService:resetRun()                     -- new run: not secured
        TargetService:awardCrew(players)             -- optional: trophy to every escapee too
        TargetService:ownsTrophy(player, kind) -> bool
        TargetService:refreshWall()                  -- re-light the club wall from who is online
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local TargetService = {}

local V3 = Constants.LOOT_V3 or {}
local TAG = "TargetTrophy"

local inited = false
local deps = {}
local secured = false
local securedBy = nil
local securedJob = nil

-- optional sibling services (never a hard require)
local cache = {}
local function optional(name)
    if cache[name] ~= nil then return cache[name] or nil end
    local mod = script.Parent:FindFirstChild(name)
    local ok, r = false, nil
    if mod then ok, r = pcall(require, mod) end
    cache[name] = (ok and type(r) == "table") and r or false
    return cache[name] or nil
end
local function dataService() return deps.data or optional("PlayerDataService") end
local function feelService() return deps.feel or optional("FeelService") end

local function activeJob()
    return ReplicatedStorage:GetAttribute("ActiveJob")
end

function TargetService:targetFor(jobId)
    local t = V3.TARGETS and V3.TARGETS[jobId or activeJob() or ""]
    if not t then return nil end
    return { kind = t.kind, name = t.name, line = t.line, bonus = V3.TARGET_BONUS or 5000 }
end

function TargetService:isTarget(kind, jobId)
    local t = self:targetFor(jobId)
    return t ~= nil and kind == t.kind
end

local function publish()
    local t = TargetService:targetFor(activeJob())
    pcall(function()
        ReplicatedStorage:SetAttribute("TargetKind", t and t.kind or "")
        ReplicatedStorage:SetAttribute("TargetName", t and t.name or "")
        ReplicatedStorage:SetAttribute("TargetLine", t and t.line or "")
        ReplicatedStorage:SetAttribute("TargetBonus", t and t.bonus or 0)
        ReplicatedStorage:SetAttribute("TargetSecured", secured)
    end)
end

-- ── trophies ─────────────────────────────────────────────────────────
local function trophiesOf(player)
    local DS = dataService()
    if not DS or type(DS.getData) ~= "function" then return nil end
    local ok, data = pcall(DS.getData, DS, player)
    if not ok or type(data) ~= "table" then return nil end
    if type(data.targetTrophies) ~= "table" then data.targetTrophies = {} end
    return data.targetTrophies
end

function TargetService:ownsTrophy(player, kind)
    local t = player and trophiesOf(player)
    return t ~= nil and t[kind] == true
end

local function giveTrophy(player, kind)
    if not player or not player.Parent then return false end
    local t = trophiesOf(player)
    if not t then return false end
    local new = t[kind] ~= true
    t[kind] = true
    return new
end

function TargetService:refreshWall()
    local owned = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local t = trophiesOf(p)
        if t then for kind, yes in pairs(t) do if yes == true then owned[kind] = true end end end
    end
    for _, m in ipairs(CollectionService:GetTagged(TAG)) do
        local kind = m:GetAttribute("TargetKind")
        if kind then
            local want = owned[kind] == true
            if m:GetAttribute("Owned") ~= want then m:SetAttribute("Owned", want) end
        end
    end
    return owned
end

-- ── the run ──────────────────────────────────────────────────────────
function TargetService:resetRun()
    secured, securedBy, securedJob = false, nil, nil
    publish()
end

function TargetService:isSecured()
    return secured, securedBy
end

function TargetService:onSecured(player, kind)
    local jobId = activeJob()
    if not self:isTarget(kind, jobId) then return false end
    local t = self:targetFor(jobId)
    local first = not secured
    secured, securedJob = true, jobId
    if player and player.Parent then securedBy = player end
    publish()
    if player and giveTrophy(player, kind) then
        self:refreshWall()
    end
    if first then
        local F = feelService()
        if F and type(F.big) == "function" then
            pcall(F.big, F, "TARGET SECURED!", { color = "gold", sound = "success", shake = true })
        end
        pcall(function()
            Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent"):FireAllClients({
                text = string.format("The Boss's %s is in the car!  +%s bonus", t.name, UITheme.money(t.bonus)),
                color = "gold", duration = 4 })
        end)
    end
    return true
end

function TargetService:bonusFor(run)
    if not secured then return 0 end
    if type(run) == "table" and run.jobId ~= nil and securedJob ~= nil and run.jobId ~= securedJob then return 0 end
    return V3.TARGET_BONUS or 5000
end

function TargetService:awardCrew(players)
    if not secured or type(players) ~= "table" then return end
    local jobT = self:targetFor(securedJob)
    if not jobT then return end
    local any = false
    for _, p in ipairs(players) do
        if typeof(p) == "Instance" and p:IsA("Player") and giveTrophy(p, jobT.kind) then any = true end
    end
    if any then self:refreshWall() end
end

function TargetService:init(d)
    if type(d) == "table" then
        for k, v in pairs(d) do deps[k] = v end
    end
    if inited then return end
    inited = true
    ReplicatedStorage:GetAttributeChangedSignal("ActiveJob"):Connect(publish)
    publish()
    -- the wall follows who is in the server (their save loads a moment after joining)
    Players.PlayerAdded:Connect(function(p)
        task.delay(3, function() if p.Parent then self:refreshWall() end end)
        task.delay(10, function() if p.Parent then self:refreshWall() end end)
    end)
    Players.PlayerRemoving:Connect(function()
        task.defer(function() self:refreshWall() end)
    end)
    CollectionService:GetInstanceAddedSignal(TAG):Connect(function() task.defer(function() self:refreshWall() end) end)
    task.delay(2, function() self:refreshWall() end)
end

return TargetService
