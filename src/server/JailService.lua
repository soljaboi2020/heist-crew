--[[
    HEIST CREW — JailService  (v2.0 "BIGGER", V2_SPEC §6)
    ────────────────────────────────────────────────
    A cop grabbing you no longer takes you straight out of the heist: you go
    to a cell in the police station (MiamiBuilder builds it, x -104..-80,
    z -52..-28). The kid rule: "the police catch you → jail. A friend can
    break you out."

      • jail(player) teleports you into a free cell, sets the player attribute
        Jailed = true, keeps the cell door shut and fires the Jail remote
        { jailed = true, freeAt } to you.
      • a "Break out" ProximityPrompt (hold 2 s) shows on your cell door.
        Any teammate who is still in the run (not jailed, not out) can use it
        → you're freed and JobService drops you back at the job's sneakIn.
      • nobody frees you in Constants.JAIL.TIME (30 s) → onTimeout: JobService
        takes you out of the run and sends you to the club.
      • walking out / respawning while jailed puts you back in the cell.
      • release(player) / releaseAll() are SILENT (no callbacks) — JobService
        uses them when the run ends and does the teleport itself.

    This service never teleports anyone OUT of jail itself — JobService
    decides where you go (sneakIn / the club). It only puts you IN.

    PUBLIC API:
        JailService:init({ jail = world.jail, notify = fn(player, text, color, dur)?, jobService = JobService })
            jail = { cells = { { inside = CFrame, door = BasePart }, ... }, release = CFrame }
            (calls jobService:useJail(self) so catches route here)
        JailService:isReady() -> boolean                 -- a jail with at least one cell exists
        JailService:jail(player, { onFreed = fn(player, rescuer), onTimeout = fn(player) }) -> boolean
        JailService:free(player, rescuer) -> boolean     -- what the Break-out prompt calls
        JailService:release(player)                      -- silent
        JailService:releaseAll()                         -- silent
        JailService:isJailed(player) -> boolean
        JailService:getReleaseCFrame() -> CFrame | nil
        JailService:getOccupiedDoors() -> { { pos = Vector3, player = Player } }
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local JailService = {}

local JAIL = Constants.JAIL or { TIME = 30, BREAKOUT_HOLD = 2 }
local STRAY_DIST = 14        -- further than this from your cell = put back

local cells = {}             -- { inside = CFrame, door = BasePart, prompt, occupant, entry }
local byPlayer = {}          -- [Player] = entry
local releaseCF = nil
local notifyFn = nil
local Job = nil
local jailRemote = Remotes.getRemote(Remotes.NAMES.Jail, "RemoteEvent")

local function now() return Workspace:GetServerTimeNow() end

local function say(player, text, color, duration)
    if notifyFn and player and player.Parent then
        pcall(notifyFn, player, text, color or "white", duration or 3)
    end
end

local function standCFrame(cell)
    -- `inside` is a floor-level spot in the cell; lift the root above the floor
    return cell.inside + Vector3.new(0, 3, 0)
end

local function putInCell(player, cell)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp then return false end
    if hum and hum.SeatPart then
        local w = hum.SeatPart:FindFirstChild("SeatWeld")
        if w then w:Destroy() end
        hum.Sit = false
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = standCFrame(cell)
    return true
end

local function shutDoor(cell)
    if cell.door and cell.door.Parent then
        cell.door.CanCollide = true
        if cell.doorT ~= nil then cell.door.Transparency = cell.doorT end
    end
end

local function setPrompt(cell, player)
    if not cell.prompt then return end
    cell.prompt.Enabled = player ~= nil
    cell.prompt.ObjectText = player and (player.DisplayName .. "'s cell") or "Cell"
end

local function clear(player)
    local entry = byPlayer[player]
    if not entry then return nil end
    byPlayer[player] = nil
    local cell = entry.cell
    if cell.occupant == player then
        cell.occupant = nil
        -- a doubled-up cell keeps its prompt for whoever is still inside
        for other, e in pairs(byPlayer) do
            if e.cell == cell and other.Parent then cell.occupant = other break end
        end
        setPrompt(cell, cell.occupant)
        shutDoor(cell)
    end
    if player.Parent then
        player:SetAttribute("Jailed", nil)
        jailRemote:FireClient(player, { jailed = false })
    end
    return entry
end

function JailService:isReady()
    return #cells > 0
end

function JailService:isJailed(player)
    return byPlayer[player] ~= nil
end

function JailService:getReleaseCFrame()
    return releaseCF
end

-- where the Break-out prompts are right now (JobService turns these into waypoints)
function JailService:getOccupiedDoors()
    local out = {}
    for _, cell in ipairs(cells) do
        if cell.occupant and cell.occupant.Parent and cell.door then
            table.insert(out, { pos = cell.door.Position, player = cell.occupant })
        end
    end
    return out
end

function JailService:jail(player, callbacks)
    if not player or not player.Parent or #cells == 0 then return false end
    if byPlayer[player] then return true end
    local cell = nil
    for _, c in ipairs(cells) do
        if not c.occupant or not c.occupant.Parent then cell = c break end
    end
    if not cell then
        -- every cell full: double up in the first one (never fail a catch over this)
        cell = cells[1]
    end
    if not putInCell(player, cell) then return false end
    local entry = {
        cell = cell, freeAt = now() + JAIL.TIME, token = {},
        onFreed = callbacks and callbacks.onFreed, onTimeout = callbacks and callbacks.onTimeout,
    }
    byPlayer[player] = entry
    cell.occupant = cell.occupant or player
    shutDoor(cell)
    setPrompt(cell, cell.occupant)
    player:SetAttribute("Jailed", true)
    player:SetAttribute("GuardSuspicion", 0)
    player:SetAttribute("CameraSuspicion", 0)
    jailRemote:FireClient(player, { jailed = true, freeAt = entry.freeAt })

    local token = entry.token
    task.delay(JAIL.TIME, function()
        local e = byPlayer[player]
        if not e or e.token ~= token then return end
        clear(player)
        if e.onTimeout then
            local ok, err = pcall(e.onTimeout, player)
            if not ok then warn("[JailService] onTimeout:", err) end
        end
    end)
    return true
end

function JailService:free(player, rescuer)
    local entry = byPlayer[player]
    if not entry then return false end
    clear(player)
    if entry.onFreed then
        local ok, err = pcall(entry.onFreed, player, rescuer)
        if not ok then warn("[JailService] onFreed:", err) end
    end
    return true
end

function JailService:release(player)
    clear(player)
end

function JailService:releaseAll()
    local list = {}
    for p in pairs(byPlayer) do table.insert(list, p) end
    for _, p in ipairs(list) do clear(p) end
end

-- the Break-out prompt: frees whoever is in this cell
local function onBreakOut(cell, rescuer)
    if rescuer:GetAttribute("Jailed") then
        say(rescuer, "You can't break yourself out — wait for a friend!", "white", 3)
        return
    end
    local canFree = true
    if Job and type(Job.canBreakOut) == "function" then
        local ok, result = pcall(Job.canBreakOut, Job, rescuer)
        canFree = ok and result == true
    end
    if not canFree then
        say(rescuer, "Only someone on the heist can do that", "white", 2)
        return
    end
    -- everyone jailed in this cell goes free (doubled-up cells too)
    local freed = {}
    for p, e in pairs(byPlayer) do
        if e.cell == cell then table.insert(freed, p) end
    end
    for _, p in ipairs(freed) do JailService:free(p, rescuer) end
end

local function buildPrompt(cell)
    local door = cell.door
    if not (door and door:IsA("BasePart")) then return end
    cell.doorT = door.Transparency
    -- the prompt sits on the OUTSIDE face of the door (away from the cell)
    local att = Instance.new("Attachment")
    att.Name = "BreakOutPoint"
    local out = door.Position - cell.inside.Position
    out = Vector3.new(out.X, 0, out.Z)
    out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(0, 0, 1)
    att.WorldPosition = door.Position + out * 1.5
    att.Parent = door
    local p = Instance.new("ProximityPrompt")
    p.Name = "BreakOut"
    p.ActionText = "Break out"
    p.ObjectText = "Cell"
    p.HoldDuration = JAIL.BREAKOUT_HOLD
    p.MaxActivationDistance = 7
    p.RequiresLineOfSight = false
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
    p.Enabled = false
    p:SetAttribute("HideIfJailed", true)   -- client hint: the prisoner doesn't need to see it
    p.Parent = att
    p.Triggered:Connect(function(rescuer) onBreakOut(cell, rescuer) end)
    cell.prompt = p
end

function JailService:init(deps)
    deps = deps or {}
    notifyFn = deps.notify
    Job = deps.jobService
    local jail = deps.jail
    cells = {}
    if type(jail) == "table" and type(jail.cells) == "table" then
        for _, c in ipairs(jail.cells) do
            if typeof(c.inside) == "CFrame" then
                local cell = { inside = c.inside, door = c.door }
                buildPrompt(cell)
                shutDoor(cell)
                table.insert(cells, cell)
            end
        end
        if typeof(jail.release) == "CFrame" then releaseCF = jail.release end
    end
    if Job and type(Job.useJail) == "function" then Job:useJail(self) end

    -- keep prisoners in their cell (walked out through a gap, respawned, etc.)
    task.spawn(function()
        while true do
            task.wait(1)
            for player, entry in pairs(byPlayer) do
                if player.Parent then
                    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                    if hrp and (hrp.Position - entry.cell.inside.Position).Magnitude > STRAY_DIST then
                        putInCell(player, entry.cell)
                    end
                end
            end
        end
    end)
    local function hook(player)
        player.CharacterAdded:Connect(function()
            local entry = byPlayer[player]
            if entry then
                task.wait(0.3)
                if byPlayer[player] == entry then putInCell(player, entry.cell) end
            end
        end)
    end
    Players.PlayerAdded:Connect(hook)
    for _, p in ipairs(Players:GetPlayers()) do hook(p) end
    Players.PlayerRemoving:Connect(function(p)
        local entry = byPlayer[p]
        if entry then
            byPlayer[p] = nil
            if entry.cell.occupant == p then
                entry.cell.occupant = nil
                for other, e in pairs(byPlayer) do
                    if e.cell == entry.cell and other.Parent then entry.cell.occupant = other break end
                end
                setPrompt(entry.cell, entry.cell.occupant)
            end
        end
    end)

    if #cells == 0 then
        warn("[JailService] no jail cells — cops catching you = out of the run (old rule)")
    else
        print("[JailService] Ready —", #cells, "cells")
    end
end

return JailService
