--[[
    HEIST CREW — VentService (v2.0)
    ────────────────────────────────────────────────
    Makes every crawl vent / roof hatch usable. Job builders tag BOTH ends of a
    vent with CollectionService "Vent" and set attribute Pair = the Name of the
    other end (docs/V2_SPEC.md §2). This adds a "Crawl through" prompt on
    each end; using it fades you over to the other end.

    KEY (playtest fix, 2026-09-25): vent / hatch prompts use their OWN key —
    V on keyboard, ButtonY on gamepad — and a short 6-stud reach, so they never
    compete with an E loot prompt standing next to them (Sunny's Mart's Golden
    Ticket sat beside the roof hatch and E climbed to the roof instead).

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

local function attach(part)
    if not part:IsA("BasePart") or part:FindFirstChild("VentPrompt") then return end
    local p = Instance.new("ProximityPrompt")
    p.Name = "VentPrompt"
    p.ActionText = part:GetAttribute("Label") or "Crawl through"
    p.ObjectText = "Vent"
    p.KeyboardKeyCode = Enum.KeyCode.V        -- NOT E: E is the loot / door key
    p.GamepadKeyCode = Enum.KeyCode.ButtonY   -- (ButtonX is the default "interact")
    p.HoldDuration = 0.5
    p.MaxActivationDistance = 6
    p.RequiresLineOfSight = false
    p.Parent = part
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
