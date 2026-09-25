--[[
    HEIST CREW — LeaderboardService
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). The "TOP EARNERS" wall board in The Vault.

    A real board, not floating text: dark panel, thin neon trim, a SurfaceGui
    on the front with the title + up to 8 rows (rank · name · total earned ·
    heists). Ranks the players IN THIS SERVER by lifetime heist earnings
    (PlayerDataService lifetimeEarned), ties broken by heistsCompleted.
    Refreshes every 15 s, and a moment after anyone joins or leaves.
    Every refresh also fires the Leaderboard remote to all clients:
        { rows = { { rank, name, cash, heists, userId, vip }, ... } }   (cash = lifetime earned)

    Size: 14 wide x 8 tall. placeBoard's anchorCFrame is the WALL spot: the
    board's back sits on it and its readable front faces anchorCFrame.LookVector.

    PUBLIC API:
        LeaderboardService:init(PlayerDataService)
        LeaderboardService:placeBoard(anchorCFrame, parentFolder) -> Model
        LeaderboardService:refresh()      -- rebuild rows now (also runs every 15 s)
        LeaderboardService:rows() -> rows
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local T = UITheme.C

local LeaderboardService = {}

local BOARD_W, BOARD_H, BOARD_D = 14, 8, 0.6
local PPS = 50                 -- SurfaceGui pixels per stud → 700 x 400 canvas
local MAX_ROWS = 8
local REFRESH = 15

local PINK = Color3.fromRGB(255, 70, 180)
local CYAN = Color3.fromRGB(40, 230, 255)

local PlayerData = nil
local initialized = false
local boards = {}              -- { { model, rowLabels = {...}, empty = TextLabel } }
local lastRows = {}
local remote = nil
local pending = false

-- ── helpers ───────────────────────────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CastShadow = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do (p :: any)[k] = v end
    p.Parent = parent
    return p
end

local function label(props, parent)
    local l = UITheme.label(props)
    l.Parent = parent
    return l
end

-- ── the board ─────────────────────────────────────────────────────────
local COLS = {   -- x offset (px), width (px), alignment
    rank   = { 24, 60,  Enum.TextXAlignment.Left },
    name   = { 90, 300, Enum.TextXAlignment.Left },
    earned = { 400, 180, Enum.TextXAlignment.Right },
    heists = { 590, 86,  Enum.TextXAlignment.Right },
}

local function buildBoard(anchor, parent)
    local model = Instance.new("Model")
    model.Name = "LeaderboardWall"

    -- the board's back face sits on the anchor, front faces LookVector
    local cf = anchor * CFrame.new(0, 0, -BOARD_D / 2)

    local panel = part({
        Name = "Panel", Size = Vector3.new(BOARD_W, BOARD_H, BOARD_D), CFrame = cf,
        Color = Color3.fromRGB(16, 17, 24), Material = Enum.Material.SmoothPlastic, CanCollide = true,
    }, model)
    model.PrimaryPart = panel

    -- brushed-metal frame
    local fw = 0.3
    for _, s in ipairs({
        { Vector3.new(BOARD_W + fw * 2, fw, BOARD_D + 0.2), Vector3.new(0, BOARD_H / 2 + fw / 2, 0) },
        { Vector3.new(BOARD_W + fw * 2, fw, BOARD_D + 0.2), Vector3.new(0, -BOARD_H / 2 - fw / 2, 0) },
        { Vector3.new(fw, BOARD_H, BOARD_D + 0.2), Vector3.new(BOARD_W / 2 + fw / 2, 0, 0) },
        { Vector3.new(fw, BOARD_H, BOARD_D + 0.2), Vector3.new(-BOARD_W / 2 - fw / 2, 0, 0) },
    }) do
        part({ Name = "Frame", Size = s[1], CFrame = cf * CFrame.new(s[2]),
            Color = Color3.fromRGB(40, 42, 52), Material = Enum.Material.Metal }, model)
    end

    -- thin neon trim just inside the frame (accent only): pink top, cyan bottom
    local front = -BOARD_D / 2 - 0.06
    part({ Name = "TrimTop", Size = Vector3.new(BOARD_W - 0.4, 0.08, 0.1),
        CFrame = cf * CFrame.new(0, BOARD_H / 2 - 0.2, front), Color = PINK, Material = Enum.Material.Neon }, model)
    part({ Name = "TrimBottom", Size = Vector3.new(BOARD_W - 0.4, 0.08, 0.1),
        CFrame = cf * CFrame.new(0, -BOARD_H / 2 + 0.2, front), Color = CYAN, Material = Enum.Material.Neon }, model)

    -- screen
    local gui = Instance.new("SurfaceGui")
    gui.Name = "Board"
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = PPS
    gui.LightInfluence = 0
    gui.Brightness = 1.4
    gui.ResetOnSpawn = false
    gui.Parent = panel
    local canvasW = BOARD_W * PPS

    local root = Instance.new("Frame")
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundColor3 = T.bg
    root.BorderSizePixel = 0
    root.Parent = gui
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.fromRGB(26, 22, 40), T.bg)
    grad.Parent = root

    label({ Text = "THE VAULT", Position = UDim2.fromOffset(24, 18), Size = UDim2.fromOffset(300, 18),
        FontFace = UITheme.F.bold, TextSize = 16, TextColor3 = PINK }, root)
    label({ Text = "TOP EARNERS", Position = UDim2.fromOffset(24, 34), Size = UDim2.fromOffset(500, 50),
        FontFace = UITheme.F.display, TextSize = 46 }, root)
    label({ Text = "IN THIS SERVER", Position = UDim2.new(1, -224, 0, 20), Size = UDim2.fromOffset(200, 18),
        FontFace = UITheme.F.bold, TextSize = 14, TextColor3 = T.muted, TextXAlignment = Enum.TextXAlignment.Right }, root)

    -- header row
    local headY = 96
    for key, text in pairs({ rank = "#", name = "CREW MEMBER", earned = "TOTAL EARNED", heists = "HEISTS" }) do
        local c = COLS[key]
        label({ Text = text, Position = UDim2.fromOffset(c[1], headY), Size = UDim2.fromOffset(c[2], 18),
            FontFace = UITheme.F.bold, TextSize = 14, TextColor3 = T.muted, TextXAlignment = c[3] }, root)
    end
    local line = Instance.new("Frame")
    line.Position = UDim2.fromOffset(24, headY + 24)
    line.Size = UDim2.new(1, -48, 0, 2)
    line.BackgroundColor3 = T.line
    line.BackgroundTransparency = 0.85
    line.BorderSizePixel = 0
    line.Parent = root

    -- rows
    local rowTop, rowH = headY + 32, 32
    local rowLabels = {}
    for i = 1, MAX_ROWS do
        local y = rowTop + (i - 1) * rowH
        local bg = Instance.new("Frame")
        bg.Position = UDim2.fromOffset(16, y)
        bg.Size = UDim2.new(1, -32, 0, rowH - 4)
        bg.BackgroundColor3 = T.line
        bg.BackgroundTransparency = (i % 2 == 0) and 0.96 or 1
        bg.BorderSizePixel = 0
        bg.Parent = root
        UITheme.corner(bg, 8)
        local r = {}
        for key, c in pairs(COLS) do
            r[key] = label({ Position = UDim2.fromOffset(c[1] - 16, 0), Size = UDim2.fromOffset(c[2], rowH - 4),
                FontFace = key == "name" and UITheme.F.bold or UITheme.F.display, TextSize = 22,
                TextXAlignment = c[3], TextTruncate = Enum.TextTruncate.AtEnd }, bg)
        end
        r.bg = bg
        rowLabels[i] = r
    end
    local empty = label({ Text = "Finish a heist to get on the board!", Position = UDim2.fromOffset(0, rowTop + 40),
        Size = UDim2.new(1, 0, 0, 30), FontFace = UITheme.F.bold, TextSize = 22, TextColor3 = T.muted,
        TextXAlignment = Enum.TextXAlignment.Center }, root)
    label({ Text = "Earn cash on heists to climb!", AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 24, 1, -14), Size = UDim2.fromOffset(canvasW - 48, 18),
        FontFace = UITheme.F.medium, TextSize = 14, TextColor3 = T.faint }, root)

    model.Parent = parent
    return { model = model, rowLabels = rowLabels, empty = empty }
end

local function paintBoard(b, rows)
    if not b.model.Parent then return end
    b.empty.Visible = #rows == 0
    for i = 1, MAX_ROWS do
        local r, data = b.rowLabels[i], rows[i]
        r.bg.Visible = data ~= nil
        if data then
            local medal = (i == 1 and T.gold) or (i == 2 and Color3.fromRGB(203, 213, 225))
                or (i == 3 and Color3.fromRGB(217, 150, 90)) or T.muted
            r.rank.Text = tostring(i)
            r.rank.TextColor3 = medal
            r.name.Text = data.name
            r.name.TextColor3 = data.vip and T.gold or T.text
            r.earned.Text = UITheme.money(data.cash)
            r.earned.TextColor3 = T.money
            r.heists.Text = tostring(data.heists)
            r.heists.TextColor3 = T.text
        end
    end
end

-- ── data ──────────────────────────────────────────────────────────────
local function collect()
    local rows = {}
    for _, p in ipairs(Players:GetPlayers()) do
        local d = PlayerData and PlayerData:getData(p)
        if d then
            table.insert(rows, {
                name = p.DisplayName,
                userId = p.UserId,
                cash = math.floor(tonumber(d.lifetimeEarned) or 0),
                heists = math.floor(tonumber(d.heistsCompleted) or 0),
                vip = p:GetAttribute("VIP") == true,
            })
        end
    end
    table.sort(rows, function(a, b)
        if a.cash ~= b.cash then return a.cash > b.cash end
        if a.heists ~= b.heists then return a.heists > b.heists end
        return a.name < b.name
    end)
    for i, r in ipairs(rows) do r.rank = i end
    return rows
end

function LeaderboardService:rows()
    return lastRows
end

function LeaderboardService:refresh()
    local rows = collect()
    lastRows = rows
    for i = #boards, 1, -1 do
        local b = boards[i]
        if not b.model.Parent then
            table.remove(boards, i)
        else
            local ok, err = pcall(paintBoard, b, rows)
            if not ok then warn("[LeaderboardService] paint failed:", err) end
        end
    end
    if remote then
        local top = {}
        for i = 1, math.min(#rows, 10) do top[i] = rows[i] end
        remote:FireAllClients({ rows = top })
    end
end

local function soon()
    if pending then return end
    pending = true
    task.delay(2, function()
        pending = false
        LeaderboardService:refresh()
    end)
end

function LeaderboardService:placeBoard(anchorCFrame, parentFolder)
    if typeof(anchorCFrame) ~= "CFrame" then
        warn("[LeaderboardService] placeBoard needs a CFrame")
        return nil
    end
    local b = buildBoard(anchorCFrame, parentFolder or workspace)
    table.insert(boards, b)
    pcall(paintBoard, b, lastRows)
    soon()
    return b.model
end

function LeaderboardService:init(playerDataService)
    PlayerData = playerDataService or PlayerData
    if initialized then return end
    initialized = true

    remote = Remotes.getRemote(Remotes.NAMES.Leaderboard, "RemoteEvent")
    if remote and not remote:IsA("RemoteEvent") then remote = nil end

    Players.PlayerAdded:Connect(function(p)
        task.delay(3, soon)   -- their save loads first
        p:GetAttributeChangedSignal("VIP"):Connect(soon)
    end)
    Players.PlayerRemoving:Connect(function() task.defer(soon) end)

    task.spawn(function()
        while true do
            local ok, err = pcall(function() LeaderboardService:refresh() end)
            if not ok then warn("[LeaderboardService] refresh failed:", err) end
            task.wait(REFRESH)
        end
    end)
    print("[LeaderboardService] TOP EARNERS board online")
end

return LeaderboardService
