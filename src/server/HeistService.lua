--[[
    HEIST CREW — HeistService
    ────────────────────────────────────────────────
    The brain of the heist. Owns the state machine:

        IDLE     → vault is locked, no heist in progress
        CRACKING → someone is holding E on the vault
        ESCAPING → vault cracked, alarm active, the whole crew is running
        COMPLETE → the run resolved (everyone escaped, got caught, or timed out)
        FAILED   → nobody made it out

    ─── v0.4.0 — CO-OP REWRITE ───────────────────────
    This used to track a single `activePlayer`: only the person who cracked the
    vault could get paid, and only they could finish at the getaway car. Everyone
    else on the server was a spectator. The game's whole pitch is 4-player co-op,
    so that is now a shared crew run:

      • ANY player can crack the vault. The cracker gets a bonus for doing it.
      • When the vault pops, EVERY player on the server joins the crew.
      • EVERY crew member escapes individually by reaching the getaway car,
        and each one gets paid.
      • Getting caught is PERSONAL, not team-wide. One player going down no
        longer fails the run for everyone — the rest keep going.
      • Being spotted no longer instantly fails the heist. It costs the crew
        its stealth bonus and brings the guards down early.
      • The run resolves when every crew member has either escaped or been
        taken out, or when the escape timer expires.

    PUBLIC API:
        HeistService:init(refs, GuardService, EconomyService)
        HeistService:onPlayerCaught(player, guard)  -- called by GuardService
        HeistService:onPlayerSpotted(player, guard) -- called by GuardService
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HeistService = {}

-- Sound helpers
local activeAlarmSound = nil
local function playOneShot(soundId, volume)
    local s = Instance.new("Sound")
    s.SoundId = soundId
    s.Volume = volume or 0.6
    s.Parent = Workspace
    s:Play()
    s.Ended:Connect(function() s:Destroy() end)
    task.delay(10, function() if s and s.Parent then s:Destroy() end end)
end
local function startAlarmLoop()
    if activeAlarmSound then activeAlarmSound:Stop(); activeAlarmSound:Destroy() end
    activeAlarmSound = Instance.new("Sound")
    activeAlarmSound.Name = "AlarmSound"
    activeAlarmSound.SoundId = Constants.SOUNDS.ALARM
    activeAlarmSound.Volume = 0.7
    activeAlarmSound.Looped = true
    activeAlarmSound.Parent = Workspace
    activeAlarmSound:Play()
end
local function stopAlarmLoop()
    if activeAlarmSound then
        activeAlarmSound:Stop()
        activeAlarmSound:Destroy()
        activeAlarmSound = nil
    end
end

local refs = nil
local GuardService = nil
local EconomyService = nil

local stateRemote     = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
local progressRemote  = Remotes.getRemote(Remotes.NAMES.VaultProgress, "RemoteEvent")
local alarmRemote     = Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent")
local notifyRemote    = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")

-- ──────────────────────────────────────────────
-- Heist session state (crew-wide)
-- ──────────────────────────────────────────────
-- session.crew maps Player -> { escaped = bool, out = bool }
--   escaped : reached the getaway car and got paid
--   out     : caught by a guard, no payout, run continues without them
local session = {
    state = "IDLE",
    cracker = nil,          -- who actually cracked it (earns the bonus)
    crew = {},
    crackProgress = 0,
    crackingThread = nil,
    escapeThread = nil,
    spotted = false,        -- crew-wide: kills the stealth bonus for EVERYONE
    cooldownEnds = 0,
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

-- Push vault progress to the whole crew, not just the cracker, so everyone
-- can watch the bar fill and knows when to get ready to run.
local function broadcastProgress(progress)
    for _, p in ipairs(Players:GetPlayers()) do
        progressRemote:FireClient(p, progress)
    end
end

-- How many crew are still in play (not escaped, not taken out)?
local function activeCrewCount()
    local n = 0
    for _, entry in pairs(session.crew) do
        if not entry.escaped and not entry.out then n = n + 1 end
    end
    return n
end

local function crewTally()
    local escaped, caught, total = 0, 0, 0
    for _, entry in pairs(session.crew) do
        total = total + 1
        if entry.escaped then escaped = escaped + 1 end
        if entry.out then caught = caught + 1 end
    end
    return escaped, caught, total
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

local function sendToLobby(player)
    if player and player.Character then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        -- back to the safehouse spawn (was a hardcoded (0,10,0), the old plaza)
        local sp = Constants.WORLD.SPAWN_POSITION
        if hrp then hrp.CFrame = CFrame.new(sp.x, sp.y + 2, sp.z) end
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

    prompt.PromptButtonHoldBegan:Connect(function(player)
        -- Somebody else is already working the vault — don't stomp their crack.
        if session.state == "CRACKING" then
            if session.cracker and session.cracker ~= player then
                notifyOne(player, "🔧 " .. session.cracker.Name .. " is already on the vault — cover them!", "gold", 2)
            end
            return
        end
        if session.state ~= "IDLE" then return end
        if os.clock() < session.cooldownEnds then
            notifyOne(player, "Vault on cooldown — wait " .. math.ceil(session.cooldownEnds - os.clock()) .. "s", "red", 2)
            return
        end

        session.state = "CRACKING"
        session.cracker = player
        session.spotted = false

        notifyOne(player, "🔧 Cracking the vault...", "gold", 3)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player then
                notifyOne(p, "🔧 " .. player.Name .. " is cracking the vault — get ready to run!", "gold", 3)
            end
        end

        session.crackingThread = task.spawn(function()
            local startTime = os.clock()
            while session.state == "CRACKING" do
                local elapsed = os.clock() - startTime
                local progress = math.min(1, elapsed / Constants.VAULT_CRACK_TIME)
                broadcastProgress(progress)
                task.wait(0.1)
            end
        end)
    end)

    prompt.PromptButtonHoldEnded:Connect(function(player)
        -- Only the person actually cracking can interrupt the crack.
        if session.state == "CRACKING" and session.cracker == player then
            session.state = "IDLE"
            session.cracker = nil
            if session.crackingThread then
                task.cancel(session.crackingThread)
                session.crackingThread = nil
            end
            broadcastProgress(0)
            notifyAll("Vault crack interrupted", "red", 2)
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
-- Getaway car: any crew member can escape through it
-- ──────────────────────────────────────────────
local function setupGetaway()
    refs.getawayCar.Touched:Connect(function(hit)
        if session.state ~= "ESCAPING" then return end
        local char = hit:FindFirstAncestorOfClass("Model")
        if not char then return end
        local player = Players:GetPlayerFromCharacter(char)
        if not player then return end
        HeistService:onPlayerEscaped(player)
    end)
end

-- ──────────────────────────────────────────────
-- State transitions
-- ──────────────────────────────────────────────
function HeistService:onVaultCracked(player)
    if session.state ~= "CRACKING" then return end
    session.state = "ESCAPING"
    if session.crackingThread then task.cancel(session.crackingThread); session.crackingThread = nil end

    -- Everyone on the server is now on the hook. This is the crew.
    session.crew = {}
    for _, p in ipairs(Players:GetPlayers()) do
        session.crew[p] = {escaped = false, out = false}
    end

    broadcastProgress(1)

    local _, _, crewSize = crewTally()
    if crewSize > 1 then
        notifyAll(string.format("🚨 ALARM! %s cracked it — %d-person crew, GO!", player.Name, crewSize), "red", 4)
    else
        notifyAll(string.format("🚨 ALARM! %s cracked the vault!", player.Name), "red", 4)
    end

    -- Cracking bonus goes to whoever did the work
    EconomyService:addCash(player, Constants.HEIST_PAYOUT_CRACKER_BONUS, "Cracked the vault")
    notifyOne(player, string.format("🔓 +$%d cracker bonus", Constants.HEIST_PAYOUT_CRACKER_BONUS), "gold", 3)

    -- 🔊 Sound: vault cracked + alarm wail
    playOneShot(Constants.SOUNDS.VAULT_CRACK, 0.8)
    startAlarmLoop()

    -- Activate alarm
    for _, p in ipairs(Players:GetPlayers()) do
        alarmRemote:FireClient(p, true)
    end
    setVaultColor(Color3.fromRGB(60, 60, 60))  -- dim the vault
    setGetawayActive(true)
    GuardService:setAlarmActive(true, player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or nil)

    broadcastState("ESCAPING", {player = player.Name, escapeSeconds = Constants.GETAWAY_TIMER, crewSize = crewSize})

    -- Escape timer — anyone still inside when it expires is left behind
    session.escapeThread = task.spawn(function()
        local startTime = os.clock()
        while session.state == "ESCAPING" do
            if os.clock() - startTime >= Constants.GETAWAY_TIMER then
                HeistService:onTimerExpired()
                return
            end
            task.wait(0.5)
        end
    end)
end

-- One crew member reached the car. Pay them and check if the run is done.
function HeistService:onPlayerEscaped(player)
    if session.state ~= "ESCAPING" then return end
    local entry = session.crew[player]
    if not entry then return end          -- wasn't part of this run
    if entry.escaped or entry.out then return end  -- already resolved

    entry.escaped = true

    local payout = Constants.HEIST_PAYOUT_VAULT + Constants.HEIST_PAYOUT_ESCAPE
    EconomyService:addCash(player, payout, "Heist escape")

    if not session.spotted then
        EconomyService:addCash(player, Constants.HEIST_PAYOUT_STEALTH_BONUS, "Stealth bonus")
        payout = payout + Constants.HEIST_PAYOUT_STEALTH_BONUS
        notifyOne(player, string.format("🥷 CLEAN GETAWAY — +$%d", payout), "green", 5)
    else
        notifyOne(player, string.format("💰 You got out — +$%d", payout), "green", 5)
    end

    local escaped, _, total = crewTally()
    if total > 1 then
        notifyAll(string.format("🚗 %s made it out (%d/%d)", player.Name, escaped, total), "green", 3)
    end

    if activeCrewCount() == 0 then
        HeistService:finishHeist()
    end
end

-- Timer ran out. Anyone still inside is left behind.
function HeistService:onTimerExpired()
    if session.state ~= "ESCAPING" then return end

    for p, entry in pairs(session.crew) do
        if not entry.escaped and not entry.out then
            entry.out = true
            notifyOne(p, "⏰ Left behind — the car took off without you.", "red", 4)
            sendToLobby(p)
        end
    end

    HeistService:finishHeist()
end

-- Resolve the run and report how the crew did.
function HeistService:finishHeist()
    if session.state ~= "ESCAPING" then return end

    local escaped, caught, total = crewTally()
    session.state = (escaped > 0) and "COMPLETE" or "FAILED"

    stopAlarmLoop()
    if escaped > 0 then
        playOneShot(Constants.SOUNDS.HEIST_WIN, 0.8)
        playOneShot(Constants.SOUNDS.CASH_CHA_CHING, 0.7)
        if total > 1 then
            if escaped == total then
                notifyAll(string.format("🏆 FULL CREW OUT — all %d escaped!", total), "green", 5)
            else
                notifyAll(string.format("💰 Heist done — %d of %d got away.", escaped, total), "gold", 5)
            end
        end
    else
        playOneShot(Constants.SOUNDS.HEIST_FAIL, 0.7)
        notifyAll("❌ Heist failed — nobody made it out.", "red", 4)
    end

    broadcastState(session.state, {escaped = escaped, caught = caught, crewSize = total})
    HeistService:resetHeist()
end

function HeistService:resetHeist()
    if session.escapeThread then
        task.cancel(session.escapeThread)
        session.escapeThread = nil
    end

    -- Cool down before vault is crackable again
    session.cooldownEnds = os.clock() + Constants.VAULT_RESET_COOLDOWN
    session.cracker = nil
    session.crew = {}
    session.spotted = false

    setVaultColor(Color3.fromRGB(234, 179, 8))  -- Restore gold color
    setGetawayActive(false)
    broadcastProgress(0)

    -- Clear alarm
    for _, p in ipairs(Players:GetPlayers()) do
        alarmRemote:FireClient(p, false)
    end
    stopAlarmLoop()
    GuardService:reset()

    -- Re-enable IDLE state after cooldown
    task.delay(Constants.VAULT_RESET_COOLDOWN, function()
        session.state = "IDLE"
        broadcastState("IDLE", {})
        notifyAll("🔓 Vault re-armed — ready for the next crew!", "gold", 3)
    end)

    session.state = "IDLE"
    broadcastState("IDLE", {})
end

-- ──────────────────────────────────────────────
-- GuardService callbacks
-- ──────────────────────────────────────────────
function HeistService:onPlayerSpotted(player, guard)
    if session.state == "CRACKING" then
        -- Used to be an instant team-wide fail. Now it costs the crew its
        -- stealth bonus and brings the guards early — the run continues.
        if not session.spotted then
            session.spotted = true
            notifyAll(string.format("👀 %s got spotted by %s — stealth bonus gone!", player.Name, guard.name), "red", 4)
            GuardService:setAlarmActive(true, player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or nil)
        end

    elseif session.state == "ESCAPING" then
        session.spotted = true

    elseif session.state == "IDLE" then
        notifyOne(player, "👀 A guard saw you — back off!", "red", 2)
    end
end

function HeistService:onPlayerCaught(player, guard)
    if session.state == "ESCAPING" or session.state == "CRACKING" then
        session.spotted = true

        -- If the cracker goes down mid-crack, the crack dies but the vault
        -- stays armed — someone else on the crew can pick it back up.
        if session.state == "CRACKING" then
            if session.crackingThread then
                task.cancel(session.crackingThread)
                session.crackingThread = nil
            end
            session.state = "IDLE"
            session.cracker = nil
            broadcastProgress(0)
            notifyAll(string.format("👮 %s got caught by %s — vault's still there!", player.Name, guard.name), "red", 4)
            playOneShot(Constants.SOUNDS.HEIST_FAIL, 0.5)
            sendToLobby(player)
            return
        end

        -- Caught while escaping: that player is out, the rest keep running.
        local entry = session.crew[player]
        if entry and not entry.escaped and not entry.out then
            entry.out = true
            notifyOne(player, "👮 Caught by " .. guard.name .. " — no payout.", "red", 4)
            local _, _, total = crewTally()
            if total > 1 then
                notifyAll(string.format("👮 %s got taken down!", player.Name), "red", 3)
            end
            sendToLobby(player)

            if activeCrewCount() == 0 then
                HeistService:finishHeist()
            end
        end

    elseif session.state == "IDLE" then
        notifyOne(player, "👮 Get out of the mansion!", "red", 2)
        sendToLobby(player)
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

    -- A player leaving mid-run shouldn't stall the heist waiting on them.
    Players.PlayerRemoving:Connect(function(player)
        local entry = session.crew[player]
        if entry and not entry.escaped and not entry.out then
            entry.out = true
            if session.state == "ESCAPING" and activeCrewCount() == 0 then
                HeistService:finishHeist()
            end
        end
        if session.cracker == player and session.state == "CRACKING" then
            if session.crackingThread then
                task.cancel(session.crackingThread)
                session.crackingThread = nil
            end
            session.state = "IDLE"
            session.cracker = nil
            broadcastProgress(0)
        end
    end)

    print("[HeistService] Ready — IDLE state, vault armed (co-op crew mode)")
end

return HeistService
