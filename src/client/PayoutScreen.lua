--[[
    HEIST CREW — PayoutScreen  (v1.1)
    ────────────────────────────────────────────────
    The end-of-heist screen — the "numbers go up" moment.

    COMPLETE: grade stamp (S / A / B / C), job name, then each bag counts in
    one at a time (Gold  $1,500 …), the stealth bonus row, YOUR CUT rolling up,
    + XP, time, and PLAY AGAIN.
    FAILED:   BUSTED / OUT OF TIME, why, and one tip for next time.

    Driven by HeistState "COMPLETE"/"FAILED" (payload from JobService.finish).
    Players who weren't in the car see the crew's result and "you didn't make
    it out" instead of a cut.

    v2.0: bags a bot carried say so ("Gold · Rex carried it"), and every bot
    crewmate gets a thank-you line. Words are kid-simple (Malachi's bar: a
    7-year-old gets it).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local PayoutScreen = {}
local localPlayer = Players.LocalPlayer

local GRADE_COLOR = {
    S = Color3.fromRGB(253, 224, 71), A = T.money, B = T.info, C = T.muted, F = T.danger,
}
local GRADE_WORD = {
    S = "PERFECT!", A = "SNEAKY", B = "LOUD", C = "NO LOOT", F = "BUSTED",
}
local TIPS = {
    busted  = "Tip: don't stop the car next to the police. The Driver can press Shift to go super fast!",
    time    = "Tip: when the alarm goes off, stop grabbing stuff and get everyone in the car!",
    caught  = "Tip: if the police catch you, a friend can break you out of jail. Stick together!",
    timeout = "Tip: talk to the Boss (F) to hear the plan, and follow the markers.",
    abandoned = "Tip: bring friends! Every crew job has a special power.",
}
local FAIL_TITLE = {
    time = "OUT OF TIME", timeout = "TOO SLOW", caught = "CAUGHT!", busted = "BUSTED!", abandoned = "CREW LEFT",
}

local function chaChing()
    local s = Instance.new("Sound")
    s.SoundId = Constants.SOUNDS.CASH_CHA_CHING
    s.Volume = 0.25
    s.PlaybackSpeed = 1.4
    s.Parent = SoundService
    s:Play()
    s.Ended:Connect(function() s:Destroy() end)
end

function PayoutScreen:_build()
    local pg = localPlayer:WaitForChild("PlayerGui")
    local old = pg:FindFirstChild("PayoutScreen")
    if old then old:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "PayoutScreen"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 15
    screen.Enabled = false
    screen.Parent = pg

    local dim = Instance.new("Frame")
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 0.45
    dim.BorderSizePixel = 0
    dim.Parent = screen

    local card = Instance.new("CanvasGroup")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(520, 520)
    card.BackgroundColor3 = T.bg
    card.BackgroundTransparency = 0.04
    card.Parent = screen
    UITheme.corner(card, 22)
    UITheme.stroke(card)
    local scale = Instance.new("UIScale")
    scale.Parent = card
    -- (fix v1.1) scale the whole card down on small screens (phones): the card's
    -- UIScale animates between 0.9x and 1x of this fit factor
    self._fit = 1
    local function refit()
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        self._fit = math.clamp(math.min((vp.Y - 40) / 540, (vp.X - 40) / 540), 0.4, 1)
        if screen.Enabled then scale.Scale = self._fit end
    end
    refit()
    if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(1, 0, 0, 5)
    accent.BorderSizePixel = 0
    accent.Parent = card

    local grade = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 20), Size = UDim2.fromOffset(110, 110),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 104, Rotation = 8 })
    grade.Parent = card
    local gradeWord = UITheme.caption("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -28, 0, 128),
        Size = UDim2.fromOffset(110, 14), TextXAlignment = Enum.TextXAlignment.Center })
    gradeWord.Parent = card
    local jobCap = UITheme.caption("", { Position = UDim2.fromOffset(30, 30), Size = UDim2.fromOffset(300, 14) })
    jobCap.Parent = card
    local title = UITheme.label({ Position = UDim2.fromOffset(28, 48), Size = UDim2.fromOffset(340, 50),
        FontFace = UITheme.F.display, TextSize = 44 })
    title.Parent = card
    local subtitle = UITheme.label({ Position = UDim2.fromOffset(30, 100), Size = UDim2.fromOffset(330, 40),
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.medium, TextSize = 16, TextColor3 = T.muted })
    subtitle.Parent = card

    local list = Instance.new("Frame")
    list.Position = UDim2.fromOffset(30, 156)
    list.Size = UDim2.new(1, -60, 0, 210)
    list.BackgroundTransparency = 1
    list.ClipsDescendants = true
    list.Parent = card
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list

    local line = Instance.new("Frame")
    line.Position = UDim2.new(0, 30, 0, 374)
    line.Size = UDim2.new(1, -60, 0, 1)
    line.BackgroundColor3 = T.line
    line.BackgroundTransparency = 0.85
    line.BorderSizePixel = 0
    line.Parent = card
    local cutCap = UITheme.caption("Your money", { Position = UDim2.fromOffset(30, 388), Size = UDim2.fromOffset(200, 14) })
    cutCap.Parent = card
    local cut = UITheme.label({ Position = UDim2.fromOffset(28, 404), Size = UDim2.fromOffset(300, 46),
        FontFace = UITheme.F.display, TextSize = 42, TextColor3 = T.money })
    cut.Parent = card
    local meta = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 392),
        Size = UDim2.fromOffset(200, 40), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
        FontFace = UITheme.F.bold, TextSize = 15, TextColor3 = T.muted, TextWrapped = true })
    meta.Parent = card

    local again = Instance.new("TextButton")
    again.AnchorPoint = Vector2.new(0.5, 1)
    again.Position = UDim2.new(0.5, 0, 1, -18)
    again.Size = UDim2.fromOffset(240, 46)
    again.BackgroundColor3 = T.gold
    again.Text = "PLAY AGAIN"
    again.TextColor3 = T.bg
    again.FontFace = UITheme.F.display
    again.TextSize = 20
    again.Parent = card
    UITheme.corner(again, 23)

    self._u = { screen = screen, card = card, scale = scale, accent = accent, grade = grade, gradeWord = gradeWord,
        jobCap = jobCap, title = title, subtitle = subtitle, list = list, cut = cut, meta = meta, again = again }
    again.Activated:Connect(function() self:close() end)
end

local function row(parent, order, left, right, color)
    local r = Instance.new("Frame")
    r.LayoutOrder = order
    r.Size = UDim2.new(1, 0, 0, 24)
    r.BackgroundTransparency = 1
    r.Parent = parent
    UITheme.label({ Text = left, Size = UDim2.fromScale(0.65, 1), FontFace = UITheme.F.bold, TextSize = 16 }).Parent = r
    UITheme.label({ Text = right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.35, 1),
        TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.display, TextSize = 17, TextColor3 = color or T.text }).Parent = r
    r.Visible = false
    return r
end

function PayoutScreen:close()
    local u = self._u
    local out = TweenService:Create(u.card, TweenInfo.new(0.25), { GroupTransparency = 1 })
    out:Play()
    out.Completed:Wait()
    u.screen.Enabled = false
end

function PayoutScreen:show(win, p)
    local u = self._u
    local token = {}
    self._token = token
    for _, c in ipairs(u.list:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end

    local g = win and (p.grade or "B") or "F"
    local mine = false
    for _, id in ipairs(p.escapees or {}) do if id == localPlayer.UserId then mine = true end end
    u.accent.BackgroundColor3 = win and T.money or T.danger
    u.grade.Text = g
    u.grade.TextColor3 = GRADE_COLOR[g] or T.text
    u.gradeWord.Text = GRADE_WORD[g] or ""
    u.jobCap.Text = p.jobName or ""
    if win then
        u.title.Text = "YOU DID IT!"
        u.title.TextColor3 = T.text
        u.subtitle.Text = string.format("%d of %d got away on the boat", p.escaped or 0, math.max(p.crewSize or 0, p.escaped or 0))
    else
        u.title.Text = FAIL_TITLE[p.result or ""] or "BUSTED!"
        u.title.TextColor3 = T.danger
        u.subtitle.Text = TIPS[p.result or ""] or TIPS.caught
    end

    local rows = {}
    local order = 0
    for _, b in ipairs(p.bags or {}) do
        order = order + 1
        local info = Constants.LOOT[b.kind] or Constants.LOOT_DEFAULT
        local col = info and info.color and UITheme.rgb(info.color) or T.text
        local left = tostring(b.kind or "Loot")
        if b.bot then left = left .. "  ·  " .. tostring(b.bot) .. " carried it" end
        table.insert(rows, row(u.list, order, left, UITheme.money(b.value or 0), col))
    end
    if win and (p.stealthBonus or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "Sneaky bonus (no alarm!)", "+" .. UITheme.money(p.stealthBonus), T.gold))
    end
    if win and #(p.bags or {}) == 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "The car was empty", "$0", T.muted))
    end
    -- v2.0 bot crew lines
    for _, bot in ipairs(p.botCrew or {}) do
        order = order + 1
        local n = tonumber(bot.bags) or 0
        local right = n > 0 and string.format("%d bag%s", n, n == 1 and "" or "s") or "helped"
        table.insert(rows, row(u.list, order, "Bot crew: " .. tostring(bot.name or "Bot"), right, T.info))
    end
    if (p.jailed or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "Still in jail at the end", tostring(p.jailed), T.danger))
    end

    u.cut.Text = "$0"
    local each = (win and mine) and (p.each or 0) or 0
    local mins = math.floor((p.time or 0) / 60)
    u.meta.Text = string.format("%s\n%d:%02d", (win and mine) and ("+" .. tostring(p.xp or 0) .. " XP") or "", mins, (p.time or 0) % 60)
    if not mine and win then
        u.meta.Text = "You didn't get away this time\n" .. string.format("%d:%02d", mins, (p.time or 0) % 60)
    end

    u.screen.Enabled = true
    u.card.GroupTransparency = 1
    local fit = self._fit or 1
    u.scale.Scale = 0.9 * fit
    TweenService:Create(u.card, TweenInfo.new(0.3), { GroupTransparency = 0 }):Play()
    TweenService:Create(u.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()

    task.spawn(function()
        task.wait(0.5)
        for _, r in ipairs(rows) do
            if self._token ~= token then return end
            r.Visible = true
            chaChing()
            task.wait(0.28)
        end
        -- roll the cut
        local nv = Instance.new("NumberValue")
        nv.Changed:Connect(function(v) u.cut.Text = UITheme.money(v) end)
        TweenService:Create(nv, TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = each }):Play()
        -- stamp the grade
        u.grade.TextTransparency = 1
        task.wait(1.1)
        if self._token ~= token then return end
        u.grade.TextSize = 160
        u.grade.TextTransparency = 0
        TweenService:Create(u.grade, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 104 }):Play()
    end)
end

function PayoutScreen:start()
    self:_build()
    local remote = Remotes.getRemote(Remotes.NAMES.HeistState, "RemoteEvent")
    if remote then
        remote.OnClientEvent:Connect(function(state, payload)
            if state == "COMPLETE" then
                self:show(true, payload or {})
            elseif state == "FAILED" then
                self:show(false, payload or {})
            end
        end)
    end
    print("[HEIST CREW] PayoutScreen mounted ✅")
end

return PayoutScreen
