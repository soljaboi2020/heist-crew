--[[
    HEIST CREW — Notifications (toasts)
    ────────────────────────────────────────────────
    v0.7.0, v2.1 UI overhaul. Toasts stack in the topCenter slot, directly
    under the objective bar (so they can never cover it): a chunky rounded
    card, a coloured accent + dot for meaning (green = money, red = danger,
    gold = heads-up), big white text. (v3.3: ONE at a time — see below.)
    They fade + pop in and fade out (v3.3.1: a plain Frame, each piece fades; CanvasGroups lagged).

    v3.3 "ONE POPUP AT A TIME" (Malachi: "doesn't feel like a good Roblox game"
    — three toasts + a banner + a tip at once was the worst of it):
      • ONE toast on screen. The rest wait in a short queue (max 4; red = danger
        jumps ahead of the others). While something is waiting, the toast on
        screen is cut short (≥ 1.4 s) so the queue never lags behind the game.
      • default 2.5 s (was 3). Server durations are capped at 4 s.
      • the same text within 5 s is dropped (shown or still queued).
      • crew echo: the server tells the crew "Malachi got sent back to the door"
        right next to Malachi's own "A guard saw you!" — the crew copy that
        names YOU is dropped when you got your own toast within 1 s.
      • non-red toasts wait (≤ 3 s) while a big centre banner/title is up
        (FeelFX:isBigBusy), so the drop-in reads title → jackpot → toast.

    Server fires:  Notify:FireClient(player, {text=..., color="green"|"red"|"gold"|"white", duration=3})

    PUBLIC API:
        Notifications:start()
        Notifications:show(text, colorName, duration)   -- queued
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local Notifications = {}
local localPlayer = Players.LocalPlayer

local ACCENT = {
    green = T.money,
    red   = T.danger,
    gold  = T.gold,
    white = T.info,
}

local DEFAULT_DURATION = 2.5
local MAX_DURATION = 4
local MIN_WHEN_BUSY = 1.4     -- a toast with others waiting behind it stays at least this long
local DEDUPE = 5
local ECHO_WINDOW = 1.0
local MAX_QUEUE = 4
local BIG_WAIT_MAX = 3

local FeelFX = nil
local function bigBusy()
    if FeelFX == nil then
        FeelFX = false
        local mod = script.Parent:FindFirstChild("FeelFX")
        if mod then
            local ok, res = pcall(require, mod)
            if ok and type(res) == "table" then FeelFX = res end
        end
    end
    if not FeelFX or type(FeelFX.isBigBusy) ~= "function" then return false end
    local ok, busy = pcall(FeelFX.isBigBusy, FeelFX)
    return ok and busy == true
end

-- does this text name the local player as a whole word?
local function namesMe(text)
    local me = localPlayer.DisplayName
    if type(me) ~= "string" or me == "" then return false end
    local i = string.find(text, me, 1, true)
    while i do
        local before = i > 1 and text:sub(i - 1, i - 1) or " "
        local after = text:sub(i + #me, i + #me)
        if not before:match("[%w_]") and not after:match("[%w_]") then return true end
        i = string.find(text, me, i + 1, true)
    end
    return false
end

function Notifications:_buildContainer()
    local playerGui = localPlayer:WaitForChild("PlayerGui")
    local existing = playerGui:FindFirstChild("ToastNotifications")
    if existing then existing:Destroy() end

    local container = Instance.new("Frame")
    container.Name = "Toasts"
    container.LayoutOrder = 2
    container.BackgroundTransparency = 1
    container.Size = UDim2.fromOffset(0, 0)
    container.AutomaticSize = Enum.AutomaticSize.XY
    container.Parent = UITheme.slot("topCenter")

    local layout = Instance.new("UIListLayout")
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = container

    self._container = container
    self._n = 0
end

-- queue entry point (server toasts + any HUD)
function Notifications:show(text, colorName, duration)
    text = tostring(text or "")
    if text == "" then return end
    self._queue = self._queue or {}
    self._recent = self._recent or {}
    local now = os.clock()
    -- dedupe: same text shown or queued in the last DEDUPE s
    local last = self._recent[text]
    if last and now - last < DEDUPE then return end
    for _, q in ipairs(self._queue) do
        if q.text == text then return end
    end
    self._recent[text] = now
    for k, t in pairs(self._recent) do
        if now - t > DEDUPE then self._recent[k] = nil end
    end
    local entry = {
        text = text, color = colorName,
        duration = math.clamp(tonumber(duration) or DEFAULT_DURATION, 1, MAX_DURATION),
        at = now, echo = namesMe(text),
    }
    if not entry.echo then
        self._lastPersonal = now
        -- a crew echo about me that is still waiting is now redundant
        for i = #self._queue, 1, -1 do
            local q = self._queue[i]
            if q.echo and now - q.at < ECHO_WINDOW then table.remove(self._queue, i) end
        end
    elseif self._lastPersonal and now - self._lastPersonal < ECHO_WINDOW then
        return   -- I already got my own toast about this
    end
    if colorName == "red" then
        -- danger goes ahead of everything that isn't danger
        local at = #self._queue + 1
        for i, q in ipairs(self._queue) do
            if q.color ~= "red" then at = i break end
        end
        table.insert(self._queue, at, entry)
    else
        table.insert(self._queue, entry)
    end
    while #self._queue > MAX_QUEUE do
        -- drop the oldest non-danger one (else the oldest)
        local drop = 1
        for i, q in ipairs(self._queue) do
            if q.color ~= "red" then drop = i break end
        end
        table.remove(self._queue, drop)
    end
    self:_pump()
end

function Notifications:_pump()
    if self._pumping then return end
    self._pumping = true
    task.spawn(function()
        while self._queue and #self._queue > 0 do
            local entry = self._queue[1]
            -- (v3.3) crew echoes wait a beat so a personal toast right behind them can cancel them
            if entry.echo and os.clock() - entry.at < 0.3 then
                task.wait(0.3 - (os.clock() - entry.at))
            end
            if self._queue[1] ~= entry then continue end
            -- don't talk over a big banner / the drop-in title (danger never waits)
            if entry.color ~= "red" then
                local t0 = os.clock()
                while bigBusy() and os.clock() - t0 < BIG_WAIT_MAX do task.wait(0.2) end
            end
            if self._queue[1] ~= entry then continue end
            table.remove(self._queue, 1)
            local ok, err = pcall(function() self:_display(entry) end)
            if not ok then warn("[HEIST CREW] toast failed: " .. tostring(err)) end
        end
        self._pumping = false
    end)
end

-- shows ONE toast and yields until it's gone (or cut short by a waiting one)
function Notifications:_display(entry)
    if not self._container then return end
    local text, colorName, duration = entry.text, entry.color, entry.duration
    local accent = ACCENT[colorName] or ACCENT.white
    self._n = self._n + 1

    -- only ever one toast on screen
    for _, c in ipairs(self._container:GetChildren()) do
        if c.Name == "Toast" and c:IsA("GuiObject") then c:Destroy() end
    end

    -- (v3.3.1) a plain Frame, NOT a CanvasGroup: on Malachi's PC (and in Studio captures)
    -- a CanvasGroup's texture lagged its fade, so the toast text stayed nearly invisible
    -- on a dark panel. Each piece now fades on its own (see fade() below).
    local toast = Instance.new("Frame")
    toast.Name = "Toast"
    toast.LayoutOrder = self._n
    toast.AutomaticSize = Enum.AutomaticSize.X
    toast.Size = UDim2.fromOffset(0, 50)
    toast.BackgroundColor3 = Color3.new(1, 1, 1)      -- (v3.2) the gradient below carries the colour
    toast.BackgroundTransparency = 0.04
    toast.Parent = self._container
    UITheme.corner(toast, 16)
    -- v3.2: a glow of the toast's colour on the left, fading into night purple
    local g = Instance.new("UIGradient")
    g.Rotation = 0
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.bg:Lerp(accent, 0.45)),
        ColorSequenceKeypoint.new(0.35, T.bg),
        ColorSequenceKeypoint.new(1, T.bgDeep),
    })
    g.Parent = toast

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 6, 1, -16)
    bar.Position = UDim2.fromOffset(10, 8)
    bar.BackgroundColor3 = accent
    bar.BorderSizePixel = 0
    bar.Parent = toast
    UITheme.corner(bar, 3)

    local label = UITheme.label({
        Text = text,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 1, 0),
        Position = UDim2.fromOffset(26, 0),
        FontFace = UITheme.F.display,
        TextSize = 21,
        TextColor3 = T.text,
    })
    label.Parent = toast
    local pad = Instance.new("UIPadding")
    pad.PaddingRight = UDim.new(0, 44)   -- room for the 24px left inset + breathing space
    pad.Parent = toast

    local scale = Instance.new("UIScale")
    scale.Scale = 0.9
    scale.Parent = toast
    -- remember every piece's resting transparency, start them all invisible, fade in
    local pieces = {}
    for _, d in ipairs(toast:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            table.insert(pieces, { d, "TextTransparency", d.TextTransparency })
            table.insert(pieces, { d, "BackgroundTransparency", d.BackgroundTransparency })
        elseif d:IsA("GuiObject") then
            table.insert(pieces, { d, "BackgroundTransparency", d.BackgroundTransparency })
            if d:IsA("ImageLabel") then table.insert(pieces, { d, "ImageTransparency", d.ImageTransparency }) end
        elseif d:IsA("UIStroke") then
            table.insert(pieces, { d, "Transparency", d.Transparency })
        end
    end
    table.insert(pieces, { toast, "BackgroundTransparency", toast.BackgroundTransparency })
    local function fade(shown, t, dir)
        for _, pc in ipairs(pieces) do
            local target = shown and pc[3] or 1
            if not shown or pc[3] < 1 then
                TweenService:Create(pc[1], TweenInfo.new(t, Enum.EasingStyle.Quad, dir), { [pc[2]] = target }):Play()
            end
        end
    end
    for _, pc in ipairs(pieces) do pc[1][pc[2]] = 1 end
    fade(true, 0.25, Enum.EasingDirection.Out)
    TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Scale = 1 }):Play()

    local t0 = os.clock()
    while toast.Parent do
        local el = os.clock() - t0
        if el >= duration then break end
        if el >= MIN_WHEN_BUSY and self._queue and #self._queue > 0 then break end
        task.wait(0.1)
    end
    if not toast.Parent then return end
    fade(false, 0.25, Enum.EasingDirection.In)
    task.wait(0.27)
    if toast.Parent then toast:Destroy() end
end

function Notifications:start()
    if self._started then return end   -- safe to call twice (init.client + tests)
    self._started = true
    self._queue, self._recent = {}, {}
    self:_buildContainer()
    local notifyRemote = Remotes.getRemote(Remotes.NAMES.Notify, "RemoteEvent")
    if notifyRemote then
        notifyRemote.OnClientEvent:Connect(function(payload)
            payload = type(payload) == "table" and payload or {}
            self:show(payload.text or "", payload.color or "white", payload.duration or DEFAULT_DURATION)
        end)
    end
    print("[HEIST CREW] Notifications mounted ✅")
end

return Notifications
