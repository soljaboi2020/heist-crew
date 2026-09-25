--[[
    HEIST CREW — Remotes Registry
    ────────────────────────────────────────────────
    Single source of truth for every RemoteEvent / RemoteFunction.

    Usage:
        local Remotes = require(ReplicatedStorage.Shared.Remotes)
        local r = Remotes.getRemote(Remotes.NAMES.CashUpdated)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.NAMES = {
    -- Server → Client
    CashUpdated     = "CashUpdated",       -- (newCash:number)
    HeistState      = "HeistState",        -- (state:string, payload:table)
    VaultProgress   = "VaultProgress",     -- (progress:number 0-1)
    AlarmTriggered  = "AlarmTriggered",    -- (active:boolean)
    Notify          = "Notify",            -- ({text:string, color:string, duration:number})

    -- v1.0 (docs/V1_SPEC.md §3)
    JobInfo         = "JobInfo",           -- server→client (info:table)  see spec §5
    ThrowBag        = "ThrowBag",          -- client→server (dir:Vector3)
    UseAbility      = "UseAbility",        -- client→server ()  Lookout mark
    CarInput        = "CarInput",          -- client→server (throttle, steer) while driving
    Nitro           = "Nitro",             -- client→server ()  Driver boost
    ReadyUp         = "ReadyUp",           -- client→server ()  toggle ready for the next job
    LaunchJob       = "LaunchJob",         -- server→client ({phase="fade"|"title", jobName, tagline})
    ShopAction      = "ShopAction",        -- RemoteFunction (action:string, payload:table) -> {ok,msg,state}

    -- v2.0 (docs/V2_SPEC.md §3)
    FeelFX          = "FeelFX",            -- server→client ({kind="cash"|"loot"|"load"|"sound", amount, pos, sound})
    Crouch          = "Crouch",            -- client→server (on:boolean)
    Hide            = "Hide",              -- server→client ({hidden:boolean, spot:BasePart?})
    Portal          = "Portal",            -- server→client ({portals = {[jobId] = {count, needed, launchAt}}})
    IntroCam        = "IntroCam",          -- server→client ({points = {CFrame...}}) first-join fly-over
    DailyReward     = "DailyReward",       -- RemoteFunction ("status"|"claim") -> {ok, day, amount, nextAt, msg}
    Jail            = "Jail",              -- server→client ({jailed:boolean, freeAt:number?})
    Leaderboard     = "Leaderboard",       -- server→client ({rows = {{name, cash, heists}}})

    -- Client → Server (none yet — using ProximityPrompt for vault interaction)
}

local function getRemotesFolder()
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "Remotes"
        folder.Parent = ReplicatedStorage
    end
    return folder
end

function Remotes.getRemote(name, classType)
    classType = classType or "RemoteEvent"
    if not RunService:IsServer() then
        -- Client: never CREATE the folder (a local copy would shadow the real one
        -- and every WaitForChild below would wait in the wrong place forever).
        local real = ReplicatedStorage:WaitForChild("Remotes", 10)
        return real and real:WaitForChild(name, 10) or nil
    end
    local folder = getRemotesFolder()

    if RunService:IsServer() then
        local r = folder:FindFirstChild(name)
        if not r then
            r = Instance.new(classType)
            r.Name = name
            r.Parent = folder
        end
        return r
    else
        return folder:WaitForChild(name, 10)
    end
end

return Remotes
