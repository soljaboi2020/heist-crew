--[[
    HEIST CREW — Remotes Registry
    ────────────────────────────────────────────────
    Single source of truth for every RemoteEvent / RemoteFunction
    in the game. Server creates them on startup, clients fetch them
    by name (and wait for them to replicate).

    Usage:
        local Remotes = require(ReplicatedStorage.Shared.Remotes)
        local cashRemote = Remotes.getRemote("CashUpdated", "RemoteEvent")
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Registry of remote names (so we don't typo strings everywhere)
Remotes.NAMES = {
    CashUpdated = "CashUpdated",  -- server → client: tells client their new cash balance
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

-- Server creates the remote if missing, client waits for it
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
