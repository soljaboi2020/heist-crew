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

    v2.1 UI overhaul: chunky card with a colour wash in the result colour,
    the grade stamped in a ringed disc, every row gets an icon badge, big
    PLAY AGAIN button, and the whole card follows the HUD scale (UITheme).

    v3.0 "THE SCORE" (getaway agent): the card lands over the getaway movie's
    final shot (GetawayCinematic holds it; the dim is lighter while the movie
    plays). "got away by boat / in the helicopter / on the highway", plus the
    new bonus rows from the payload: car power (+5..12%, half when sneaky, x2
    on the highway), helicopter +10%, and the Boss's target (+$5,000). More
    than 4 bags fold into one "N bags" row so the bonuses always fit.
    Sets the LOCAL player attribute PayoutOpen = true while the card is up
    (GetawayCinematic hands the camera back when it goes false).

    v3.2 STARS + HOT STREAK: three big stars under the title fill in one by one
    (ding each) with a line under each — earned ("No alarm!") or why you missed it
    ("Too slow — beat 4:00", "Left 2 bags", "The alarm went off"). "NEW BEST!" when
    you beat your best on this heist. A "🔥 HOT STREAK x3 +30%" row pays YOUR streak
    bonus (payload.players[tostring(UserId)].streakBonus, already inside `pay`), and
    the meta line shows where the streak is now (up / cooled down).
    Also starts DoorStars (the per-player stars on the club's heist doors).
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
    busted  = "Tip: when the alarm goes off, jump in the car fast and hit GO!",
    time    = "Tip: when the alarm goes off, stop grabbing stuff and get everyone in the car!",
    caught  = "Tip: if the police catch you, a friend can break you out of jail. Stick together!",
    timeout = "Tip: talk to the Boss (F) to hear the plan, and follow the markers.",
    abandoned = "Tip: bring friends! Every crew job has a special power.",
}
-- v3.0: how the crew got away
local ROUTE_WORDS = { boat = "by boat", heli = "in the helicopter", highway = "on the highway" }

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
    dim.Name = "Dim"
    dim.Size = UDim2.fromScale(1, 1)
    dim.BackgroundColor3 = Color3.new(0, 0, 0)
    dim.BackgroundTransparency = 0.45
    dim.BorderSizePixel = 0
    dim.Parent = screen

    local card = Instance.new("CanvasGroup")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(0.5, 0.5)
    card.Size = UDim2.fromOffset(540, 680)
    card.BackgroundColor3 = T.bg
    card.BackgroundTransparency = 0.02
    card.Parent = screen
    UITheme.corner(card, 24)
    local cg = Instance.new("UIGradient")
    cg.Rotation = 90
    cg.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 155, 170))
    cg.Parent = card
    local scale = Instance.new("UIScale")
    scale.Parent = card
    -- (fix v1.1) scale the whole card down on small screens (phones): the card's
    -- UIScale animates between 0.9x and 1x of this fit factor
    self._fit = 1
    local function refit()
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        -- v2.1: follows the HUD scale (big on 1440p), never bigger than the screen
        self._fit = math.clamp(math.min(UITheme.scale(), (vp.Y - 40) / 700, (vp.X - 40) / 560), 0.4, 1.6)
        if screen.Enabled then scale.Scale = self._fit end
    end
    refit()
    if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit) end
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(1, 0, 0, 8)
    accent.BorderSizePixel = 0
    accent.Parent = card
    -- colour wash behind the title, in the result colour
    local wash = Instance.new("Frame")
    wash.Name = "Wash"
    wash.Size = UDim2.new(1, 0, 0, 170)
    wash.BorderSizePixel = 0
    wash.BackgroundTransparency = 0
    wash.Parent = card
    local wg = Instance.new("UIGradient")
    wg.Rotation = 90
    wg.Transparency = NumberSequence.new(0.72, 1)
    wg.Parent = wash

    local gradeDisc = Instance.new("Frame")
    gradeDisc.AnchorPoint = Vector2.new(1, 0)
    gradeDisc.Position = UDim2.new(1, -30, 0, 24)
    gradeDisc.Size = UDim2.fromOffset(112, 112)
    gradeDisc.BackgroundColor3 = T.bgDeep
    gradeDisc.BackgroundTransparency = 0.25
    gradeDisc.Parent = card
    UITheme.corner(gradeDisc, 56)
    local gradeRing = UITheme.stroke(gradeDisc, T.gold, 0.05, 4)
    local grade = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -31, 0, 24), Size = UDim2.fromOffset(110, 110),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextSize = 96, Rotation = 8 })
    grade.Parent = card
    local gradeWord = UITheme.caption("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 142),
        Size = UDim2.fromOffset(112, 16), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center })
    gradeWord.Parent = card
    local jobCap = UITheme.caption("", { Position = UDim2.fromOffset(30, 32), Size = UDim2.fromOffset(300, 16), TextSize = 14 })
    jobCap.Parent = card
    local title = UITheme.label({ Position = UDim2.fromOffset(28, 50), Size = UDim2.fromOffset(360, 54),
        FontFace = UITheme.F.display, TextSize = 48 })
    title.Parent = card
    local subtitle = UITheme.label({ Position = UDim2.fromOffset(30, 106), Size = UDim2.fromOffset(350, 44),
        TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = UITheme.F.medium, TextSize = 17, TextColor3 = T.text })
    subtitle.Parent = card

    -- v3.2 ⭐ the three heist stars
    local starRow = Instance.new("Frame")
    starRow.Name = "Stars"
    starRow.Position = UDim2.fromOffset(30, 164)
    starRow.Size = UDim2.new(1, -60, 0, 100)
    starRow.BackgroundTransparency = 1
    starRow.Parent = card
    local starSlots = {}
    for k = 1, 3 do
        local slot = Instance.new("Frame")
        slot.Position = UDim2.fromScale((k - 1) / 3, 0)
        slot.Size = UDim2.fromScale(1 / 3, 1)
        slot.BackgroundTransparency = 1
        slot.Parent = starRow
        local star = UITheme.label({ Text = "★", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.fromOffset(80, 62), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
            TextSize = 62, TextColor3 = T.muted, TextTransparency = 0.6 })
        star.Parent = slot
        local cap = UITheme.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62),
            Size = UDim2.new(1, -6, 0, 36), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true, FontFace = UITheme.F.bold, TextSize = 14, TextColor3 = T.muted })
        cap.Parent = slot
        starSlots[k] = { star = star, cap = cap }
    end
    local newBest = UITheme.label({ Text = "NEW BEST!", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, -4),
        Size = UDim2.fromOffset(110, 20), TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.display,
        TextSize = 18, TextColor3 = Color3.fromRGB(253, 224, 71), Rotation = 6, Visible = false })
    newBest.Parent = starRow

    local list = Instance.new("Frame")
    list.Position = UDim2.fromOffset(30, 272)
    list.Size = UDim2.new(1, -60, 0, 220)
    list.BackgroundTransparency = 1
    list.ClipsDescendants = true
    list.Parent = card
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = list

    local line = Instance.new("Frame")
    line.Position = UDim2.new(0, 30, 0, 500)
    line.Size = UDim2.new(1, -60, 0, 1)
    line.BackgroundColor3 = T.line
    line.BackgroundTransparency = 0.85
    line.BorderSizePixel = 0
    line.Parent = card
    local cutCap = UITheme.caption("Your money", { Position = UDim2.fromOffset(30, 512), Size = UDim2.fromOffset(200, 16),
        TextSize = 14 })
    cutCap.Parent = card
    local cut = UITheme.label({ Position = UDim2.fromOffset(28, 528), Size = UDim2.fromOffset(300, 52),
        FontFace = UITheme.F.display, TextSize = 48, TextColor3 = T.money })
    cut.Parent = card
    local meta = UITheme.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 512),
        Size = UDim2.fromOffset(230, 72), TextXAlignment = Enum.TextXAlignment.Right, TextYAlignment = Enum.TextYAlignment.Top,
        FontFace = UITheme.F.display, TextSize = 18, TextColor3 = T.gold, TextWrapped = true })
    meta.Parent = card

    local again = UITheme.button("PLAY AGAIN", T.gold, { AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(280, 54), TextSize = 24 })
    again.Parent = card

    self._u = { screen = screen, dim = dim, card = card, scale = scale, accent = accent, wash = wash, gradeRing = gradeRing,
        grade = grade, gradeWord = gradeWord,
        jobCap = jobCap, title = title, subtitle = subtitle, list = list, cut = cut, meta = meta, again = again,
        starSlots = starSlots, newBest = newBest }
    again.Activated:Connect(function() self:close() end)
end

local function row(parent, order, left, right, color, icon)
    local r = Instance.new("Frame")
    r.LayoutOrder = order
    r.Size = UDim2.new(1, 0, 0, 32)
    r.BackgroundColor3 = T.bgRaised
    r.BackgroundTransparency = 0.45
    r.BorderSizePixel = 0
    r.Parent = parent
    UITheme.corner(r, 10)
    local b = UITheme.badge(icon or UITheme.ICON.bag, color or T.gold, 24)
    b.AnchorPoint = Vector2.new(0, 0.5)
    b.Position = UDim2.new(0, 6, 0.5, 0)
    b.Parent = r
    UITheme.label({ Text = left, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(0.68, -38, 1, 0), FontFace = UITheme.F.bold,
        TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = r
    UITheme.label({ Text = right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromScale(0.32, 1),
        TextXAlignment = Enum.TextXAlignment.Right, FontFace = UITheme.F.display, TextSize = 19, TextColor3 = color or T.text }).Parent = r
    r.Visible = false
    return r
end

-- v3.2 ⭐ what each star says (pure: the mock tests call it). s = payload.stars
local function clock(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%d:%02d", sec // 60, sec % 60)
end
function PayoutScreen.starLines(win, s)
    s = type(s) == "table" and s or {}
    if not win then
        return {
            { on = false, text = "Get away to earn stars" },
            { on = false, text = "" },
            { on = false, text = "" },
        }
    end
    local left = math.max(0, (tonumber(s.bagsTotal) or 0) - (tonumber(s.bagsLoaded) or 0))
    return {
        { on = s.stealth == true, text = s.stealth and "Sneaky! No alarm" or "The alarm went off" },
        { on = s.loot == true, text = s.loot and "All the loot!"
            or (left > 0 and string.format("Left %d bag%s behind", left, left == 1 and "" or "s") or "Get every bag") },
        { on = s.fast == true, text = s.fast and ("Fast! " .. clock(s.time))
            or ("Too slow — beat " .. clock(s.par)) },
    }
end

-- v3.2 🔥 my streak info from the payload (nil = not in this run)
function PayoutScreen.mine(p)
    local players = type(p) == "table" and type(p.players) == "table" and p.players or {}
    return players[tostring(localPlayer and localPlayer.UserId or 0)]
end

local function ding(pitch)
    local ok = pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
        s.Volume = 0.5
        s.PlaybackSpeed = pitch or 1
        s.Parent = SoundService
        s:Play()
        s.Ended:Connect(function() s:Destroy() end)
    end)
    return ok
end

function PayoutScreen:close()
    local u = self._u
    local out = TweenService:Create(u.card, TweenInfo.new(0.25), { GroupTransparency = 1 })
    out:Play()
    out.Completed:Wait()
    u.screen.Enabled = false
    localPlayer:SetAttribute("PayoutOpen", false)
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
    u.wash.BackgroundColor3 = win and T.money or T.danger
    u.grade.Text = g
    u.grade.TextColor3 = GRADE_COLOR[g] or T.text
    u.gradeRing.Color = GRADE_COLOR[g] or T.gold
    u.gradeWord.Text = GRADE_WORD[g] or ""
    u.jobCap.Text = p.jobName or ""
    if win then
        u.title.Text = "YOU DID IT!"
        u.title.TextColor3 = T.text
        local how = ROUTE_WORDS[p.route or (p.getaway and p.getaway.route) or ""] or "with the loot"
        u.subtitle.Text = string.format("%d of %d got away %s", p.escaped or 0, math.max(p.crewSize or 0, p.escaped or 0), how)
    else
        u.title.Text = FAIL_TITLE[p.result or ""] or "BUSTED!"
        u.title.TextColor3 = T.danger
        u.subtitle.Text = TIPS[p.result or ""] or TIPS.caught
    end

    local rows = {}
    local order = 0
    local bagList = p.bags or {}
    if #bagList > 4 then
        -- v3.0: lots of bags fold into one row so the getaway bonuses still fit
        local sum = 0
        for _, b in ipairs(bagList) do sum = sum + (tonumber(b.value) or 0) end
        order = order + 1
        table.insert(rows, row(u.list, order, string.format("%d bags of loot", #bagList), UITheme.money(sum), T.money, UITheme.ICON.bag))
    else
        for _, b in ipairs(bagList) do
            order = order + 1
            local info = Constants.LOOT[b.kind] or Constants.LOOT_DEFAULT
            local col = info and info.color and UITheme.rgb(info.color) or T.text
            local left = tostring(b.name or b.kind or "Loot")
            if b.bot then left = left .. "  ·  " .. tostring(b.bot) .. " carried it" end
            table.insert(rows, row(u.list, order, left, UITheme.money(b.value or 0), col, b.bot and "🤖" or UITheme.ICON.bag))
        end
    end
    if win and (p.stealthBonus or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "Sneaky bonus (no alarm!)", "+" .. UITheme.money(p.stealthBonus), T.gold, UITheme.ICON.star))
    end
    -- v3.2 🔥 your hot streak bonus
    local me = PayoutScreen.mine(p)
    if win and me and (tonumber(me.streakBonus) or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, string.format("HOT STREAK x%d  +%d%%", tonumber(me.streakBefore) or 0,
            tonumber(me.streakPct) or 0), "+" .. UITheme.money(me.streakBonus), Color3.fromRGB(251, 146, 60), "🔥"))
    end
    -- v3.0 getaway bonuses (car power, helicopter) + the Boss's target
    if win and type(p.getaway) == "table" then
        for _, g in ipairs(p.getaway.rows or {}) do
            order = order + 1
            table.insert(rows, row(u.list, order, tostring(g.label or "Getaway bonus"), "+" .. UITheme.money(g.amount or 0), T.gold, g.icon or UITheme.ICON.car))
        end
    end
    if win and type(p.target) == "table" and (tonumber(p.target.amount) or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "Boss's target: " .. tostring(p.target.name or "?"), "+" .. UITheme.money(p.target.amount), T.gold, UITheme.ICON.target))
    end
    if win and #(p.bags or {}) == 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "The car was empty", "$0", T.muted, UITheme.ICON.car))
    end
    -- v2.0 bot crew lines
    for _, bot in ipairs(p.botCrew or {}) do
        order = order + 1
        local n = tonumber(bot.bags) or 0
        local right = n > 0 and string.format("%d bag%s", n, n == 1 and "" or "s") or "helped"
        table.insert(rows, row(u.list, order, "Bot crew: " .. tostring(bot.name or "Bot"), right, T.info, "🤖"))
    end
    if (p.jailed or 0) > 0 then
        order = order + 1
        table.insert(rows, row(u.list, order, "Still in jail at the end", tostring(p.jailed), T.danger, UITheme.ICON.jail))
    end

    u.cut.Text = "$0"
    local each = (win and mine) and (p.each or 0) or 0
    -- v3.2: your pay includes your own streak bonus
    if win and mine and me and tonumber(me.pay) then each = me.pay end
    local mins = math.floor((p.time or 0) / 60)
    u.meta.Text = string.format("%s\n%d:%02d", (win and mine) and ("+" .. tostring(p.xp or 0) .. " XP") or "", mins, (p.time or 0) % 60)
    if not mine and win then
        u.meta.Text = "You didn't get away this time\n" .. string.format("%d:%02d", mins, (p.time or 0) % 60)
    end
    -- v3.2 🔥 where the streak is now
    if me and tonumber(me.streakAfter) and tonumber(me.streakBefore) then
        local a, b = tonumber(me.streakAfter), tonumber(me.streakBefore)
        local line
        if a > b then line = string.format("🔥 Streak x%d!", a)
        elseif a < b then line = string.format("🔥 Streak cooled to x%d", a)
        elseif a > 0 then line = string.format("🔥 Streak x%d", a) end
        if line then u.meta.Text = u.meta.Text .. "\n" .. line end
    end
    -- v3.2 ⭐ reset the stars (they fill in below)
    local lines = PayoutScreen.starLines(win, p.stars)
    for k, slot in ipairs(u.starSlots) do
        slot.star.TextColor3 = T.muted
        slot.star.TextTransparency = 0.6
        slot.star.TextSize = 62
        slot.cap.Text = ""
        slot.cap.TextColor3 = T.muted
        slot.lineText = lines[k] and lines[k].text or ""
        slot.on = lines[k] and lines[k].on == true
    end
    u.newBest.Visible = false
    local showNewBest = win and mine and me and (tonumber(me.bestAfter) or 0) > (tonumber(me.bestBefore) or 0)

    u.screen.Enabled = true
    localPlayer:SetAttribute("PayoutOpen", true)
    -- v3.0: lighter dim while the getaway movie's final shot plays behind the card
    if u.dim then u.dim.BackgroundTransparency = localPlayer:GetAttribute("GetawayPlaying") and 0.75 or 0.45 end
    u.card.GroupTransparency = 1
    local fit = self._fit or 1
    u.scale.Scale = 0.9 * fit
    TweenService:Create(u.card, TweenInfo.new(0.3), { GroupTransparency = 0 }):Play()
    TweenService:Create(u.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()

    task.spawn(function()
        task.wait(0.5)
        -- v3.2 ⭐ stars fill in one by one
        local lit = 0
        for _, slot in ipairs(u.starSlots) do
            if self._token ~= token then return end
            slot.cap.Text = slot.lineText or ""
            if slot.on then
                lit = lit + 1
                slot.star.TextColor3 = Color3.fromRGB(253, 224, 71)
                slot.star.TextTransparency = 0
                slot.star.TextSize = 96
                TweenService:Create(slot.star, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 62 }):Play()
                slot.cap.TextColor3 = T.text
                ding(0.9 + 0.15 * lit)
            else
                slot.cap.TextColor3 = T.muted
            end
            task.wait(0.4)
        end
        if showNewBest and self._token == token then u.newBest.Visible = true end
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
        u.grade.TextSize = 150
        u.grade.TextTransparency = 0
        TweenService:Create(u.grade, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = 96 }):Play()
    end)
end

function PayoutScreen:start()
    self:_build()
    -- v3.2: the per-player stars on the club's heist doors (DoorStars guards a double start)
    pcall(function()
        local ds = script.Parent:FindFirstChild("DoorStars")
        if ds then require(ds):start() end
    end)
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
