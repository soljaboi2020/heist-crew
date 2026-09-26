--[[
    HEIST CREW — VentService (v2.0)
    ────────────────────────────────────────────────
    Makes every crawl vent / roof hatch usable. Job builders tag BOTH ends of a
    vent with CollectionService "Vent" and set attribute Pair = the Name of the
    other end (docs/V2_SPEC.md §2). This adds a "Crawl through" prompt on
    each end; using it fades you over to the other end.

    KEY (v3.3 "one key"): back on E (v3.0.1 had moved it to V after the Golden
    Ticket sat beside the mart's roof hatch). E-for-everything is what Roblox
    players expect, and rooms now keep E prompts >= 6 studs apart. So the
    nearest thing wins naturally:
      • the prompt sits on an Attachment at the spot you STAND to use it (this
        end's exit spot), not up on the ceiling hatch / inside the wall grille
      • reach 5 studs (loot reaches 7) — you have to be right at the vent
      • ActionText says what happens ("Climb to the roof", "Crawl through"),
        ObjectText what it is ("Roof hatch" / "Vent").

    Where you come out: the other end's Position + its LookVector * 2.5 (builders
    point each vent part's LookVector at the spot a player should appear), lifted
    to standing height. Works on any floor height (the bank's floor is y 2.0).

    PUBLIC API
        VentService:init({ feel = FeelService? })
--]]

local CollectionService = game:GetService("CollectionService")

local VentService = {}

local deps = {}
local busy = {}
local REACH = 5

local function findPair(part)
    local pairName = part:GetAttribute("Pair")
    if not pairName then return nil end
    -- prefer a sibling-ish match inside the same job folder
    local root = part
    for _ = 1, 6 do
        if root.Parent and root.Parent ~= workspace then root = root.Parent end
    end
    for _, other in ipairs(CollectionService:GetTagged("Vent")) do
        if other ~= part and other.Name == pairName and other:IsDescendantOf(root) then return other end
    end
    for _, other in ipairs(CollectionService:GetTagged("Vent")) do
        if other ~= part and other.Name == pairName then return other end
    end
    return nil
end

local function exitCFrame(target)
    -- builders may set attribute Exit (Vector3) = exactly where to stand
    local ex = target:GetAttribute("Exit")
    if typeof(ex) == "Vector3" then
        local f = target.CFrame.LookVector
        local flat = Vector3.new(f.X, 0, f.Z)
        if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
        local pos = ex + Vector3.new(0, 3, 0)
        return CFrame.lookAt(pos, pos + flat.Unit)
    end
    local look = target.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    local pos = target.Position + look * 2.5
    pos = Vector3.new(pos.X, math.max(pos.Y, target.Position.Y - target.Size.Y / 2) + 3, pos.Z)
    if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
    return CFrame.lookAt(pos, pos + flat.Unit)
end

-- what the thing IS, for the prompt's ObjectText
local function objectText(part)
    local label = string.lower(tostring(part:GetAttribute("Label") or ""))
    local name = string.lower(part.Name)
    if label:find("vent", 1, true) then return "Vent" end
    if label:find("roof", 1, true) or label:find("climb", 1, true) or name:find("hatch", 1, true) then
        return "Roof hatch"
    end
    return "Vent"
end

-- (v3.3) where the prompt lives: at the spot you stand to use this end (its
-- own exit spot), a bit above the floor — so reach is measured from where the
-- player actually is, not from a hatch up in the ceiling
local function promptParent(part)
    local ok, cf = pcall(exitCFrame, part)
    if not ok or not cf then return part end
    local standAt = cf.Position - Vector3.new(0, 1, 0)
    -- only if it is close to the part (else the prompt would float far from the vent)
    if (standAt - part.Position).Magnitude > 9 then return part end
    local a = Instance.new("Attachment")
    a.Name = "VentPromptSpot"
    a.Parent = part
    a.WorldPosition = standAt
    return a
end

-- ActionText = what happens. Builders' Label is sometimes a verb ("Climb down")
-- and sometimes a noun ("Roof hatch", "Air vent") — nouns get a verb here.
local VERBS = { climb = true, crawl = true, go = true, drop = true, enter = true, use = true, sneak = true }
local function actionText(part)
    local label = part:GetAttribute("Label")
    if type(label) == "string" and label ~= "" then
        local first = string.lower(label:match("^(%a+)") or "")
        if VERBS[first] then return label end
    end
    if objectText(part) == "Roof hatch" then
        local other = findPair(part)
        if other and other.Position.Y < part.Position.Y - 3 then return "Climb down" end
        if other and other.Position.Y > part.Position.Y + 3 then return "Climb to the roof" end
        return "Climb through"
    end
    return "Crawl through"
end

local function attach(part)
    if not part:IsA("BasePart") or part:FindFirstChild("VentPrompt", true) then return end
    -- (v3.3.1) attribute ExitOnly = true: this end is only an exit (no prompt here)
    if part:GetAttribute("ExitOnly") == true then return end
    local p = Instance.new("ProximityPrompt")
    p.Name = "VentPrompt"
    p.ActionText = actionText(part)
    p.ObjectText = objectText(part)
    -- the other end may be tagged a moment later: fix the words once it exists
    task.defer(function()
        -- builders set attributes right AFTER tagging, so re-check them here
        if part:GetAttribute("ExitOnly") == true then
            local spot = p.Parent
            p:Destroy()
            if spot and spot:IsA("Attachment") and spot.Name == "VentPromptSpot" then spot:Destroy() end
            return
        end
        if p.Parent then p.ActionText = actionText(part) end
    end)
    p.KeyboardKeyCode = Enum.KeyCode.E        -- (v3.3) one key: E, like every Roblox game
    p.GamepadKeyCode = Enum.KeyCode.ButtonX
    p.HoldDuration = 0.5
    p.MaxActivationDistance = REACH
    p.RequiresLineOfSight = false
    p.Parent = promptParent(part)
    p.Triggered:Connect(function(player)
        if busy[player] then return end
        if player:GetAttribute("Jailed") or player:GetAttribute("Hidden") then return end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 or hum.SeatPart then return end
        local other = findPair(part)
        if not other then
            warn("[VentService] no pair for vent " .. part:GetFullName())
            return
        end
        busy[player] = true
        if deps.feel then pcall(function() deps.feel:sound("door", part.Position, player) end) end
        task.delay(0.35, function()
            if hrp.Parent then hrp.CFrame = exitCFrame(other) end
            task.delay(0.6, function() busy[player] = nil end)
        end)
    end)
end

function VentService:init(d)
    deps = d or {}
    for _, part in ipairs(CollectionService:GetTagged("Vent")) do attach(part) end
    CollectionService:GetInstanceAddedSignal("Vent"):Connect(attach)
    game:GetService("Players").PlayerRemoving:Connect(function(p) busy[p] = nil end)
end

return VentService
