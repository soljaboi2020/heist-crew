--[[
    HEIST CREW — MusicController  (v3.1)
    ────────────────────────────────────────────────
    ONE place that owns the music, per player, with 1.5 s crossfades:

      lobby    The Vault / club / street, no heist      APM "Miami Nights A"
      stealth  heist running, nobody's noticed you      "Stealth Attack (Ambient)"
      tension  a guard/camera meter on you > 0.35, or   "Unseen Danger"
               a guard said "Huh?" — decays back to
               stealth after ~4 s of calm
      alarm    alarm on / escaping                      "Running Faster A"
      getaway  the getaway movie (GetawayPlaying)       "Manhattan Chase"
               …except the stealth "Miami Nights FM" cruise: that scene
               plays its own radio, so the music steps aside for it.
      payout   the victory sting (server HEIST_WIN) plays; music ducks
               while the payout card is up.

    All ids were checked loading in Malachi's Studio (2026-09-25). A track
    that fails to load just stays silent (warned once) — never an error.

    Replaces the old always-on server loop (HeistBuilder "AmbientMusic",
    now removed); any leftover copy is muted locally so nothing doubles up.

    🎵 MUSIC button (UITheme rightEdge slot, under DAILY) mutes/unmutes.
    Stored in the local player attribute "MusicMuted" (this session only —
    a server-side save needs PlayerDataService + a remote).

    Public:  MusicController:setMuted(bool)  MusicController:state() -> string
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local MusicController = {}
local localPlayer = Players.LocalPlayer

-- ── tracks ─────────────────────────────────────────────────────────────
local TRACKS = {
    lobby   = { id = "rbxassetid://1846431634",     volume = 0.3 },    -- APM "Miami Nights A"
    stealth = { id = "rbxassetid://9047763385",     volume = 0.32 },   -- "Stealth Attack (Ambient)"
    tension = { id = "rbxassetid://1836289781",     volume = 0.35 },   -- "Unseen Danger"
    alarm   = { id = "rbxassetid://1847683499",     volume = 0.35 },   -- "Running Faster A"
    getaway = { id = "rbxassetid://134157706807016", volume = 0.38 },  -- "Manhattan Chase"
}
local FADE = 1.5               -- seconds for a full crossfade
local TENSION_AT = 0.35        -- suspicion on me that turns the tension on
local TENSION_HOLD = 4         -- seconds of calm before tension falls back to stealth
local DUCK = 0.2               -- music level (x) under the payout card / win-lose sting
local STING_DUCK_TIME = 5      -- seconds to duck after COMPLETE / FAILED (the sting)

-- ── state ──────────────────────────────────────────────────────────────
local sounds = {}              -- [name] = Sound
local mine = {}                -- [Sound] = true (so the radio check skips our own)
local current = "lobby"
local heistRunning = false
local alarmOn = false
local tensionUntil = 0
local duckUntil = 0
local muted = false
local lastHuhGuard = {}        -- [Model] = last Sus value seen (for the "Huh?" edge)

local function inLobbyArea(pos)
    local W = Constants.WORLD
    if pos.Y < (W.HUB_FLOOR or -27.5) + 22 and pos.Y < -3 then return true end   -- The Vault (underground)
    local sh = W.SAFEHOUSE_CENTER
    if sh and math.abs(pos.X - sh.x) < W.SAFEHOUSE_HALF_WIDTH and math.abs(pos.Z - sh.z) < W.SAFEHOUSE_HALF_DEPTH then
        return true
    end
    return false
end

-- the getaway's own stealth radio (a Sound playing the lobby tune that isn't ours)
local function radioPlaying()
    for _, s in ipairs(SoundService:GetChildren()) do
        if s:IsA("Sound") and not mine[s] and s.Playing and s.SoundId == Constants.SOUNDS.LOBBY_AMBIENT then
            return true
        end
    end
    return false
end

-- any guard just went "Huh?" on me (his meter crossed 40%)
local function guardHuh()
    local key = "Sus_" .. localPlayer.UserId
    local huh = false
    local CS = game:GetService("CollectionService")
    for _, g in ipairs(CS:GetTagged("Guard")) do
        local v = g:GetAttribute(key)
        v = type(v) == "number" and v or 0
        local before = lastHuhGuard[g] or 0
        if v >= 0.4 and before < 0.4 then huh = true end
        lastHuhGuard[g] = v
    end
    for g in pairs(lastHuhGuard) do
        if not g.Parent then lastHuhGuard[g] = nil end
    end
    return huh
end

local function pickState(now)
    if localPlayer:GetAttribute("GetawayPlaying") == true then
        return radioPlaying() and "none" or "getaway"
    end
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local pos = root and root.Position
    local sus = math.max(localPlayer:GetAttribute("GuardSuspicion") or 0, localPlayer:GetAttribute("CameraSuspicion") or 0)
    if guardHuh() or sus > TENSION_AT then tensionUntil = now + TENSION_HOLD end

    local atHome = pos == nil or inLobbyArea(pos)
    if heistRunning and not atHome then
        if alarmOn then return "alarm" end
        if now < tensionUntil then return "tension" end
        return "stealth"
    end
    -- no heist (or watching from home): walking into a job early still gets tense
    if not atHome and now < tensionUntil then return "tension" end
    return "lobby"
end

-- ── sounds ─────────────────────────────────────────────────────────────
local function makeSounds()
    local folder = SoundService:FindFirstChild("HC_Music")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "HC_Music"
    folder.Parent = SoundService
    for name, tr in pairs(TRACKS) do
        local s = Instance.new("Sound")
        s.Name = "Music_" .. name
        s.Looped = true
        s.Volume = 0
        s.RollOffMaxDistance = 100000
        local ok = pcall(function() s.SoundId = tr.id end)
        if not ok then warn("[MusicController] bad id for", name) end
        s.Parent = folder
        sounds[name] = s
        mine[s] = true
        task.delay(12, function()
            local loaded = false
            pcall(function() loaded = s.IsLoaded end)
            if not loaded and s.Parent then
                warn(string.format("[MusicController] %s track (%s) hasn't loaded — it'll stay silent", name, tr.id))
            end
        end)
    end
end

-- the old server loop (HeistBuilder "AmbientMusic") — silence it locally if it ever comes back
local function muteLegacy(child)
    if child:IsA("Sound") and child.Name == "AmbientMusic" then
        pcall(function()
            child.Volume = 0
            child:Stop()
        end)
        child:GetPropertyChangedSignal("Volume"):Connect(function()
            if child.Volume ~= 0 then child.Volume = 0 end
        end)
    end
end

local function step(dt, now)
    local target = pickState(now)
    current = target
    local duck = 1
    if localPlayer:GetAttribute("PayoutOpen") == true or now < duckUntil then duck = DUCK end
    local master = muted and 0 or 1
    for name, s in pairs(sounds) do
        local tr = TRACKS[name]
        local want = (name == target) and tr.volume * duck * master or 0
        local rate = tr.volume / FADE * dt
        local v = s.Volume
        if v < want then v = math.min(want, v + rate)
        elseif v > want then v = math.max(want, v - rate) end
        if v ~= s.Volume then s.Volume = v end
        if want > 0 and not s.Playing then
            pcall(function() s:Play() end)
        elseif want == 0 and v <= 0.001 and s.Playing then
            pcall(function() s:Stop() end)   -- (resume positions not needed; saves streaming)
        end
    end
end

-- ── the 🎵 button ──────────────────────────────────────────────────────
function MusicController:_buildButton()
    local b = Instance.new("TextButton")
    b.Name = "MusicButton"
    b.Text = ""
    b.AutoButtonColor = false
    b.LayoutOrder = 2              -- under DAILY (LayoutOrder 1)
    b.Size = UDim2.fromOffset(118, 44)
    b.BackgroundColor3 = T.bg
    b.BackgroundTransparency = 0.08
    b.BorderSizePixel = 0
    UITheme.corner(b, 22)
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 155, 170))
    g.Parent = b
    local stroke = UITheme.stroke(b, T.info, 0.2, 2)
    local badge = UITheme.badge("🎵", T.info, 34)
    badge.AnchorPoint = Vector2.new(0, 0.5)
    badge.Position = UDim2.new(0, 5, 0.5, 0)
    badge.Parent = b
    local label = UITheme.label({ Name = "Label", Text = "MUSIC", Position = UDim2.fromOffset(44, 0),
        Size = UDim2.new(1, -50, 1, 0), FontFace = UITheme.F.display, TextSize = 17, TextColor3 = T.info })
    label.Parent = b
    local sc = Instance.new("UIScale")
    sc.Parent = b
    b.MouseEnter:Connect(function() TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1.06 }):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(sc, TweenInfo.new(0.15), { Scale = 1 }):Play() end)
    b.Activated:Connect(function() self:setMuted(not muted) end)
    self._btn = { button = b, badge = badge, label = label, stroke = stroke }
    -- (v3.1) own corner (bottom-right): in the rightEdge slot it overlapped THE JOB card mid-heist
    local sg = Instance.new("ScreenGui")
    sg.Name = "MusicButton"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 12
    sg.Parent = localPlayer:WaitForChild("PlayerGui")
    b.AnchorPoint = Vector2.new(1, 1)
    b.Position = UDim2.new(1, -14, 1, -14)
    b.Parent = sg
    self:_paintButton()
end

function MusicController:_paintButton()
    local u = self._btn
    if not u then return end
    local col = muted and T.faint or T.info
    UITheme.setBadge(u.badge, muted and "🔇" or "🎵", col)
    u.label.Text = muted and "MUTED" or "MUSIC"
    u.label.TextColor3 = muted and T.muted or T.info
    u.stroke.Color = col
end

function MusicController:setMuted(on)
    muted = on == true
    if localPlayer:GetAttribute("MusicMuted") ~= muted then localPlayer:SetAttribute("MusicMuted", muted) end
    self:_paintButton()
end

function MusicController:state() return current end

function MusicController:start()
    if self._started then return end
    self._started = true
    muted = localPlayer:GetAttribute("MusicMuted") == true
    makeSounds()

    for _, c in ipairs(Workspace:GetChildren()) do muteLegacy(c) end
    Workspace.ChildAdded:Connect(muteLegacy)

    localPlayer:GetAttributeChangedSignal("MusicMuted"):Connect(function()
        local v = localPlayer:GetAttribute("MusicMuted") == true
        if v ~= muted then
            muted = v
            self:_paintButton()
        end
    end)

    task.spawn(function()
        local ok, err = pcall(function()
            Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent").OnClientEvent:Connect(function(state)
                if state == "ACTIVE" then
                    heistRunning = true
                elseif state == "ESCAPING" then
                    heistRunning, alarmOn = true, true
                else
                    heistRunning, alarmOn, tensionUntil = false, false, 0
                    if state == "COMPLETE" or state == "FAILED" then duckUntil = os.clock() + STING_DUCK_TIME end
                end
            end)
            Remotes.getRemote(Remotes.NAMES.AlarmTriggered, "RemoteEvent").OnClientEvent:Connect(function(active)
                alarmOn = active == true
                if alarmOn then heistRunning = true end
            end)
        end)
        if not ok then warn("[MusicController] remotes:", err) end
    end)

    task.spawn(function()
        local ok, err = pcall(function() self:_buildButton() end)
        if not ok then warn("[MusicController] button:", err) end
    end)

    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.1 then return end
        local d = acc
        acc = 0
        local ok, err = pcall(step, d, os.clock())
        if not ok and not self._warned then
            self._warned = true
            warn("[MusicController] step failed:", err)
        end
    end)
    print("[HEIST CREW] MusicController mounted ✅")
end

return MusicController
