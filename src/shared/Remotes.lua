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
