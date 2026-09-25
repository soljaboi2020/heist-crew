--[[
    HEIST CREW — CrewService
    ────────────────────────────────────────────────
    v0.7.0 (2026-09-25). Runs the safehouse:
      • CREW PADS — step on one to take that role. One player per role;
        stepping on another pad swaps you; leaving the server frees it.
        Your role is stored as the player attribute "Role" (the HUD reads it).
      • THE TV — top 5 earners in this server + who holds each role,
        refreshed every 2 seconds.
      • leaderstats "Cash" is handled in EconomyService, not here.

    ⚠️ Roles are cosmetic for now: badge, sign, roster. Role abilities are a
    separate, not-yet-approved build (Rule #12).

    PUBLIC API:
        CrewService:init(safehouseRefs, PlayerDataService)
        CrewService:getRole(player) -> string | nil
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local CrewService = {}

local holders = {}     -- roleId -> Player
local refs = nil
local PlayerData = nil
local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")

local function notify(player, msg, color)
    notifyRemote:FireClient(player, { text = msg, color = color or "white", duration = 3 })
end

local function roleOf(player)
    for roleId, p in pairs(holders) do
        if p == player then return roleId end
    end
    return nil
end

local function paintPad(roleId)
    local pad = refs and refs.pads and refs.pads[roleId]
    if not pad then return end
    local holder = holders[roleId]
    if holder then
        pad.status.Text = string.upper(holder.DisplayName)
        pad.status.TextColor3 = UITheme.C.bg
        pad.statusBar.BackgroundColor3 = pad.color
        TweenService:Create(pad.light, TweenInfo.new(0.4), { Brightness = 2.2, Range = 12 }):Play()
    else
        pad.status.Text = "OPEN"
        pad.status.TextColor3 = UITheme.C.muted
        pad.statusBar.BackgroundColor3 = UITheme.C.bgRaised
        TweenService:Create(pad.light, TweenInfo.new(0.4), { Brightness = 0.6, Range = 9 }):Play()
    end
end

local function assign(player, roleId)
    local current = holders[roleId]
    if current == player then return end
    if current and current.Parent then
        notify(player, string.format("%s is already the %s", current.DisplayName, roleId), "red")
        return
    end
    local old = roleOf(player)
    if old then
        holders[old] = nil
        paintPad(old)
    end
    holders[roleId] = player
    player:SetAttribute("Role", roleId)
    paintPad(roleId)
    notify(player, "You're the " .. roleId, "gold")
end

local function release(player)
    local old = roleOf(player)
    if old then
        holders[old] = nil
        paintPad(old)
    end
end

local function refreshTV()
    local tv = refs and refs.tv
    if not tv then return end

    local board = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local data = PlayerData and PlayerData:getData(p)
        table.insert(board, { name = p.DisplayName, cash = data and data.cash or 0 })
    end
    table.sort(board, function(a, b) return a.cash > b.cash end)
    for i, row in ipairs(tv.rows) do
        local e = board[i]
        row.name.Text = e and e.name or "—"
        row.name.TextColor3 = e and UITheme.C.text or UITheme.C.faint
        row.cash.Text = e and UITheme.money(e.cash) or ""
    end

    for _, role in ipairs(Constants.ROLES) do
        local label = tv.crew[role.id]
        local holder = holders[role.id]
        if label then
            label.Text = holder and holder.DisplayName or "open"
            label.TextColor3 = holder and UITheme.C.text or UITheme.C.muted
        end
    end
end

function CrewService:getRole(player)
    return roleOf(player)
end

function CrewService:init(safehouseRefs, playerDataService)
    refs = safehouseRefs or {}
    PlayerData = playerDataService

    for roleId, pad in pairs(refs.pads or {}) do
        paintPad(roleId)
        pad.hitbox.Touched:Connect(function(hit)
            local character = hit:FindFirstAncestorOfClass("Model")
            local player = character and Players:GetPlayerFromCharacter(character)
            if player then assign(player, roleId) end
        end)
    end

    Players.PlayerRemoving:Connect(release)

    task.spawn(function()
        while true do
            local ok, err = pcall(refreshTV)
            if not ok then warn("[CrewService] TV refresh failed:", err) end
            task.wait(2)
        end
    end)

    print("[CrewService] Crew pads + safehouse TV online 🎭")
end

return CrewService
