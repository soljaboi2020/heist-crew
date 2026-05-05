--[[
    HEIST CREW — HeistService
    ────────────────────────────────────────────────
    The brain of the heist. Owns the state machine:

        IDLE  → vault is locked, no heist in progress
        CRACKING → a player is holding E on the vault
        ESCAPING → vault cracked, alarm active, escape zone live
        COMPLETE → player touched the getaway car (payout)
        FAILED → guard caught the player (no payout)

    Wires up the vault ProximityPrompt and the getaway car Touched event.

    PUBLIC API:
        HeistService:init(refs, GuardService, EconomyService)
        HeistService:onPlayerCaught(player, guard)  -- called by GuardService
        HeistService:onPlayerSpotted(player, guard) -- called by GuardService
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HeistService = {}

local refs = nil
local GuardService = nil
local EconomyService = nil

local stateRemote     = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
local progressRemote  = Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent")
local alarmRemote     = Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent")
local notifyRemote    = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")

-- ──────────────────────────────────────────────
-- Heist session state
-- ──────────────────────────────────────────────
local session = {
    state = "IDLE",
    activePlayer = nil,
    crackProgress = 0,
    crackingThread = nil,
    spottedDuringHeist = false,
    cooldownEnds = 0,  -- os.clock() when vault becomes crackable again
}

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function notifyAll(text, color, duration)
    for _, p in ipairs(Players:GetPlayers()) do
        notifyRemote:FireClient(p, {text = text, color = color, duration = duration or 3})
    end
end

local function notifyOne(player, text, color, duration)
    notifyRemote:FireClient(player, {text = text, color = color, duration = duration or 3})
end

local function broadcastState(stateName, payload)
    for _, p in ipairs(Players:GetPlayers()) do
        stateRemote:FireClient(p, stateName, payload or {})
    end
end

local function setVaultColor(color)
    if refs and refs.vault then refs.vault.Color = color end
end

local function setGetawayActive(active)
    if not refs or not refs.getawayCar then return end
    if active then
        refs.getawayCar.Color = Color3.fromRGB(40, 200, 80)
        refs.getawayCar.Material = Enum.Material.Neon
        if refs.getawayLabel then
            refs.getawayLabel.TextColor3 = Color3.fromRGB(34, 197, 94)
            refs.getawayLabel.Text = "🚗 GETAWAY — RUN!"
        end
    else
        refs.getawayCar.Color = Color3.fromRGB(40, 40, 50)
        refs.getawayCar.Material = Enum.Material.Metal
        if refs.getawayLabel then
            refs.getawayLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
            refs.getawayLabel.Text = "🚗 GETAWAY"
        end
    end
end

-- ──────────────────────────────────────────────
-- Vault interaction (uses ProximityPrompt for the "hold E" UX)
-- ──────────────────────────────────────────────
local function setupVaultPrompt()
    -- Remove old prompt if it exists
    for _, child in ipairs(refs.vault:GetChildren()) do
        if child:IsA("ProximityPrompt") then child:Destroy() end
    end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Crack Vault"
    prompt.ObjectText = "💰 VAULT"
    prompt.HoldDuration = Constants.VAULT_CRACK_TIME
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
    prompt.Parent = refs.vault

    prompt.PromptShown:Connect(function()
        if session.state ~= "IDLE" then
            prompt.Enabled = false
            task.delay(0.5, function() prompt.Enabled = true end)
        end
    end)

    -- Send progress updates while holding
    prompt.PromptButtonHoldBegan:Connect(function(player)
        if session.state ~= "IDLE" then return end
        if os.clock() < session.cooldownEnds then
            notifyOne(player, "Vault on cooldown — wait " .. math.ceil(session.cooldownEnds - os.clock()) .. "s", "red", 2)
            return
        end

        session.state = "CRACKING"
        session.activePlayer = player
        session.spottedDuringHeist = false

        notifyOne(player, "🔧 Cracking the vault...", "gold", 3)

        -- Tick progress to all clients while held
        session.crackingThread = task.spawn(function()
            local startTime = os.clock()
            while session.state == "CRACKING" do
                local elapsed = os.clock() - startTime
                local progress = math.min(1, elapsed / Constants.VAULT_CRACK_TIME)
                progressRemote:FireClient(player, progress)
                task.wait(0.1)
            end
        end)
    end)

    prompt.PromptButtonHoldEnded:Connect(function(player)
        if session.state == "CRACKING" then
            session.state = "IDLE"
            session.activePlayer = nil
            if session.crackingThread then
                task.cancel(session.crackingThread)
                session.crackingThread = nil
            end
            progressRemote:FireClient(player, 0)
            notifyOne(player, "Vault crack interrupted", "red", 2)
        end
    end)

    -- Successful full hold = vault cracked
    prompt.Triggered:Connect(function(player)
        if session.state ~= "CRACKING" then return end
        HeistService:onVaultCracked(player)
    end)

    refs._vaultPrompt = prompt
end

-- ──────────────────────────────────────────────
-- Getaway car: only active when ESCAPING
-- ──────────────────────────────────────────────
local function setupGetaway()
    refs.getawayCar.Touched:Connect(function(hit)
        if session.state ~= "ESCAPING" then return end
        local char = hit:FindFirstAncestorOfClass("Model")
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        if player ~= session.activePlayer then return end
        HeistService:onHeistComplete(player)
    end)
end

-- ──────────────────────────────────────────────
-- State transitions
-- ──────────────────────────────────────────────
function HeistService:onVaultCracked(player)
    if session.state ~= "CRACKING" then return end
    session.state = "ESCAPING"
    if session.crackingThread then task.cancel(session.crackingThread); session.crackingThread = nil end

    progressRemote:FireClient(player, 1)
    notifyAll(string.format("🚨 ALARM! %s cracked the vault!", player.Name), "red", 4)
    EconomyService:addCash(player, Constants.HEIST_PAYOUT_VAULT, "Vault cracked")

    -- Activate alarm
    for _, p in ipairs(Players:GetPlayers()) do
        alarmRemote:FireClient(p, true)
    end
    setVaultColor(Color3.fromRGB(60, 60, 60))  -- dim the vault
    setGetawayActive(true)
    GuardService:setAlarmActive(true, player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or nil)

    broadcastState("ESCAPING", {player = player.Name, escapeSeconds = Constants.GETAWAY_TIMER})

    -- Escape timer
    task.spawn(function()
        local startTime = os.clock()
        while session.state == "ESCAPING" do
            local elapsed = os.clock() - startTime
            if elapsed >= Constants.GETAWAY_TIMER then
                HeistService:onHeistFailed(player, "Ran out of time!")
                return
            end
            task.wait(0.5)
        end
    end)
end

function HeistService:onHeistComplete(player)
    if session.state ~= "ESCAPING" then return end
    session.state = "COMPLETE"

    EconomyService:addCash(player, Constants.HEIST_PAYOUT_ESCAPE, "Heist escape")
    if not session.spottedDuringHeist then
        EconomyService:addCash(player, Constants.HEIST_PAYOUT_STEALTH_BONUS, "Stealth bonus")
        notifyAll(string.format("🥷 %s pulled off a CLEAN HEIST!", player.Name), "green", 5)
    else
        notifyAll(string.format("💰 %s escaped with the loot!", player.Name), "green", 5)
    end

    broadcastState("COMPLETE", {player = player.Name})

    HeistService:resetHeist()
end

function HeistService:onHeistFailed(player, reason)
    if session.state == "IDLE" or session.state == "COMPLETE" or session.state == "FAILED" then return end
    session.state = "FAILED"

    notifyAll(string.format("❌ Heist failed: %s", reason or "Caught!"), "red", 4)
    broadcastState("FAILED", {player = player.Name, reason = reason})

    -- Teleport player back to spawn
    if player and player.Character then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.CFrame = CFrame.new(0, 10, 0)
        end
    end

    HeistService:resetHeist()
end

function HeistService:resetHeist()
    -- Cool down before vault is crackable again
    session.cooldownEnds = os.clock() + Constants.VAULT_RESET_COOLDOWN
    session.activePlayer = nil
    session.spottedDuringHeist = false

    setVaultColor(Color3.fromRGB(234, 179, 8))  -- Restore gold color
    setGetawayActive(false)

    -- Clear alarm
    for _, p in ipairs(Players:GetPlayers()) do
        alarmRemote:FireClient(p, false)
    end
    GuardService:reset()

    -- Re-enable IDLE state after cooldown
    task.delay(Constants.VAULT_RESET_COOLDOWN, function()
        if session.state ~= "IDLE" then
            session.state = "IDLE"
            broadcastState("IDLE", {})
            notifyAll(string.format("🔓 Vault re-armed — ready for the next crew!"), "gold", 3)
        end
    end)

    session.state = "IDLE"
    broadcastState("IDLE", {})
end

-- ──────────────────────────────────────────────
-- GuardService callbacks
-- ──────────────────────────────────────────────
function HeistService:onPlayerSpotted(player, guard)
    if session.state == "CRACKING" then
        -- Spotted while cracking = instant fail
        HeistService:onHeistFailed(player, "Spotted by " .. guard.name .. "!")
    elseif session.state == "ESCAPING" then
        -- Already in escape — guard tries to chase
        session.spottedDuringHeist = true
    elseif session.state == "IDLE" then
        -- Pre-heist sneaking — give a warning, don't fail
        notifyOne(player, "👀 A guard saw you — back off!", "red", 2)
    end
end

function HeistService:onPlayerCaught(player, guard)
    if session.state == "ESCAPING" or session.state == "CRACKING" then
        HeistService:onHeistFailed(player, "Caught by " .. guard.name)
    elseif session.state == "IDLE" then
        -- Pre-heist contact — just push them back
        notifyOne(player, "👮 Get out of the mansion!", "red", 2)
        if player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = CFrame.new(0, 10, 0)
            end
        end
    end
end

-- ──────────────────────────────────────────────
-- Init
-- ──────────────────────────────────────────────
function HeistService:init(worldRefs, guardSvc, economySvc)
    refs = worldRefs
    GuardService = guardSvc
    EconomyService = economySvc

    setupVaultPrompt()
    setupGetaway()
    setVaultColor(Color3.fromRGB(234, 179, 8))
    setGetawayActive(false)

    print("[HeistService] Ready — IDLE state, vault armed")
end

return HeistService
