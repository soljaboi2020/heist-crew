--[[
    HEIST CREW — HideService  (v2.0 "BIGGER", feel agent)
    ────────────────────────────────────────────────
    Closets, big plants, laundry carts: every BasePart tagged "HideSpot"
    (now or added later by a job builder) gets a "Hide" prompt (E).
    ObjectText = the part's "Label" attribute ("Closet").

    KEY (v3.3 "one key"): back on E — E-for-everything is what Roblox players
    expect, and rooms now keep E prompts >= 6 studs apart. To keep the nearest
    thing winning, the hide prompt has a SHORT reach (5 studs, measured from
    the spot's middle; a bit more for a deep spot so you can still reach it
    standing against its front) while loot prompts reach 7 — so next to a
    register the register wins, right in front of the closet the closet wins.
    While you're inside, "Get out" is 0 studs away, so it always wins.

    Hiding:
      • remembers where you stood, moves you into the spot and anchors your
        HumanoidRootPart (you can't walk while hidden)
      • makes your whole character (accessories, face, carried bag) invisible
        to EVERYONE (Transparency = 1 on the server, restored exactly later),
        CanQuery/CanTouch off so camera raycasts pass straight through you and
        a guard walking past can't bump into you, name tag off
      • player attribute Hidden = true → GuardService can't see or chase you,
        and camera rays can't hit you
      • the prompt becomes "Get out" (only for you; others see the spot as
        taken — the client hides it for them via the "Occupant" attribute)
    Getting out puts everything back and drops you where you stood.

    Auto-unhide: death, respawn, leaving, the character being moved away from
    the spot by other code (e.g. a teleport to the club), or the spot vanishing.
    Hiding WITH a bag is allowed. One player per spot.

    Fires Hide remote {hidden, spot} to the hider + FeelService hide/unhide sounds.

    PUBLIC API:
        HideService:init(deps?)          -- deps.feel = FeelService (optional; else required lazily)
        HideService:hide(player, spot) -> bool
        HideService:unhide(player)
        HideService:unhideAll()          -- job reset / end of run
        HideService:isHidden(player) -> bool
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local HideService = {}

local TAG = "HideSpot"
local PROMPT_NAME = "HidePrompt"
local LEASH = 10          -- moved further than this from the spot by someone else → auto-unhide
local REACH = 5           -- (v3.3) prompt reach; loot is 7, vents/hatches 5

local Feel = nil
local hideRemote = nil
local spots = {}          -- [part] = { prompt, occupant = Player? }
local hidden = {}         -- [player] = { spot, standCF, root, char, saved = {...}, conns = {} }

local function sound(name, pos, player)
    if Feel then pcall(function() Feel:sound(name, pos, player) end) end
end

local function fire(player, isHidden, spot)
    if hideRemote and player.Parent then
        pcall(function() hideRemote:FireClient(player, { hidden = isHidden, spot = spot }) end)
    end
end

local function setPromptIdle(entry, part)
    local p = entry.prompt
    if not p then return end
    p.ActionText = "Hide inside"
    p.ObjectText = tostring(part:GetAttribute("Label") or "Hiding spot")
    p:SetAttribute("Occupant", nil)
end

-- ── make a character (in)visible, remembering exactly what we changed ───
local function conceal(char)
    local saved = { parts = {}, decals = {}, hum = nil }
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            saved.parts[d] = { t = d.Transparency, q = d.CanQuery, tc = d.CanTouch, c = d.CanCollide }
            d.Transparency = 1
            d.CanQuery = false
            d.CanTouch = false
            d.CanCollide = false
        elseif d:IsA("Decal") or d:IsA("Texture") then
            saved.decals[d] = d.Transparency
            d.Transparency = 1
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        saved.hum = { dd = hum.DisplayDistanceType }
        hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end
    return saved
end

local function reveal(char, saved)
    for part, st in pairs(saved.parts) do
        if part.Parent then
            part.Transparency = st.t
            part.CanQuery = st.q
            part.CanTouch = st.tc
            part.CanCollide = st.c
        end
    end
    for d, t in pairs(saved.decals) do
        if d.Parent then d.Transparency = t end
    end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and saved.hum then hum.DisplayDistanceType = saved.hum.dd end
end

-- ── hide / unhide ────────────────────────────────────────────────────
function HideService:isHidden(player)
    return hidden[player] ~= nil
end

function HideService:unhide(player, silent)
    local h = hidden[player]
    if not h then
        if player:GetAttribute("Hidden") then player:SetAttribute("Hidden", false) end
        return
    end
    hidden[player] = nil
    for _, c in ipairs(h.conns) do c:Disconnect() end

    local entry = spots[h.spot]
    if entry and entry.occupant == player then
        entry.occupant = nil
        if h.spot.Parent then setPromptIdle(entry, h.spot) end
    end

    local char, root = h.char, h.root
    if char and char.Parent then
        pcall(reveal, char, h.saved)
        -- things added while hidden (a bag picked up via a teammate…) got hidden
        -- by the DescendantAdded hook; reveal handles them too (they're in saved)
        if root and root.Parent then
            root.Anchored = h.wasAnchored or false
            if not h.movedAway then
                pcall(function() char:PivotTo(h.standCF) end)
            end
        end
    end
    player:SetAttribute("Hidden", false)
    fire(player, false, h.spot)
    if not silent then sound("unhide", h.standCF and h.standCF.Position, nil) end
end

function HideService:unhideAll()
    for player in pairs(hidden) do self:unhide(player, true) end
end

function HideService:hide(player, spot)
    local entry = spots[spot]
    if not entry or hidden[player] then return false end
    if entry.occupant and entry.occupant ~= player then return false end
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 or hum.SeatPart then return false end
    if player:GetAttribute("Jailed") then return false end

    local standCF = root.CFrame
    -- stand the (invisible) character in the middle of the spot, feet near its base
    local rootHeight = hum.HipHeight + root.Size.Y / 2
    local base = spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)
    local inPos = base + Vector3.new(0, math.min(rootHeight, spot.Size.Y), 0)
    local face = Vector3.new(standCF.Position.X, inPos.Y, standCF.Position.Z)
    local inCF = (face - inPos).Magnitude > 0.1 and CFrame.lookAt(inPos, face) or CFrame.new(inPos)

    local h = {
        spot = spot, standCF = standCF, root = root, char = char,
        wasAnchored = root.Anchored, conns = {}, inCF = inCF,
    }
    h.saved = conceal(char)
    hidden[player] = h
    entry.occupant = player
    entry.prompt.ActionText = "Get out"
    entry.prompt:SetAttribute("Occupant", player.UserId)

    hum:MoveTo(root.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    char:PivotTo(inCF)
    root.Anchored = true
    player:SetAttribute("Hidden", true)

    -- anything that appears on the character while hidden (a bag, a hat) stays hidden too
    table.insert(h.conns, char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            h.saved.parts[d] = { t = d.Transparency, q = d.CanQuery, tc = d.CanTouch, c = d.CanCollide }
            d.Transparency, d.CanQuery, d.CanTouch, d.CanCollide = 1, false, false, false
        elseif d:IsA("Decal") or d:IsA("Texture") then
            h.saved.decals[d] = d.Transparency
            d.Transparency = 1
        end
    end))
    table.insert(h.conns, hum.Died:Connect(function() HideService:unhide(player, true) end))
    table.insert(h.conns, char.AncestryChanged:Connect(function()
        if not char:IsDescendantOf(workspace) then HideService:unhide(player, true) end
    end))
    table.insert(h.conns, spot.AncestryChanged:Connect(function()
        if not spot:IsDescendantOf(workspace) then HideService:unhide(player, true) end
    end))

    fire(player, true, spot)
    sound("hide", spot.Position, nil)
    return true
end

-- ── spots ────────────────────────────────────────────────────────────
local function addSpot(part)
    if not part:IsA("BasePart") or spots[part] then return end
    local existing = part:FindFirstChild(PROMPT_NAME)
    if existing then existing:Destroy() end
    local p = Instance.new("ProximityPrompt")
    p.Name = PROMPT_NAME
    -- (v3.3) back on E (v3.0.1 had it on H) — short reach instead, so the nearest thing wins
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.GamepadKeyCode = Enum.KeyCode.ButtonX
    p.HoldDuration = 0
    -- measured from the part's middle: a deep closet needs its half-depth on top
    local half = math.min(part.Size.X, part.Size.Z) / 2
    p.MaxActivationDistance = math.max(REACH, half + 3.5)
    p.UIOffset = Vector2.new(0, 24)   -- sits a little lower than a loot prompt at the same spot
    p.RequiresLineOfSight = false   -- the prompt sits inside a closet/plant; LOS would block it
    p.Parent = part
    local entry = { prompt = p, occupant = nil }
    spots[part] = entry
    setPromptIdle(entry, part)

    local busy = {}
    p.Triggered:Connect(function(player)
        if busy[player] then return end
        busy[player] = true
        local ok, err = pcall(function()
            local h = hidden[player]
            if h then
                if h.spot == part then HideService:unhide(player) end
            elseif entry.occupant == nil then
                HideService:hide(player, part)
            end
        end)
        if not ok then warn("[HideService]", err) end
        task.delay(0.3, function() busy[player] = nil end)
    end)
    part:GetAttributeChangedSignal("Label"):Connect(function()
        if not entry.occupant then setPromptIdle(entry, part) end
    end)
end

local function removeSpot(part)
    local entry = spots[part]
    if not entry then return end
    if entry.occupant then HideService:unhide(entry.occupant, true) end
    spots[part] = nil
    if entry.prompt then entry.prompt:Destroy() end
end

function HideService:init(deps)
    deps = deps or {}
    Feel = deps.feel
    if not Feel then
        local mod = script.Parent:FindFirstChild("FeelService")
        if mod then
            local ok, res = pcall(require, mod)
            if ok then Feel = res end
        end
    end
    hideRemote = Remotes.getRemote(Remotes.NAMES.Hide, "RemoteEvent")

    for _, part in ipairs(CollectionService:GetTagged(TAG)) do addSpot(part) end
    CollectionService:GetInstanceAddedSignal(TAG):Connect(addSpot)
    CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeSpot)

    Players.PlayerRemoving:Connect(function(p) HideService:unhide(p, true) end)
    Players.PlayerAdded:Connect(function(p) p:SetAttribute("Hidden", false) end)
    for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("Hidden", false) end

    -- leash: if other code teleports a hidden player (kick-back, back to the
    -- club, jail), let them go instead of leaving an invisible anchored body
    task.spawn(function()
        while true do
            task.wait(0.5)
            for player, h in pairs(hidden) do
                local root = h.root
                if not root or not root.Parent then
                    HideService:unhide(player, true)
                elseif (root.Position - h.inCF.Position).Magnitude > LEASH then
                    h.movedAway = true
                    HideService:unhide(player, true)
                end
            end
        end
    end)
    print("[HideService] ready ✅ —", #CollectionService:GetTagged(TAG), "hide spots")
end

return HideService
