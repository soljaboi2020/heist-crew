--[[
    HEIST CREW — PromptSight (v3.3.1)
    ────────────────────────────────────────────────
    ProximityPrompt.RequiresLineOfSight is checked from the CAMERA, not from
    your character. That's why Invisicam had to be reverted (v3.0.1), and in the
    v3.3 Studio playtest it bit again: backing up in Sunny's stock room let the
    camera slip out through the side door into the yard, the wall then sat
    between the camera and the breaker, and the "Cut the cameras" prompt
    silently vanished even though the player was standing right at it.

    Fix, on YOUR screen only: for every prompt the server made with
    RequiresLineOfSight = true, this module raycasts from your character's HEAD
    to the prompt. If your head can see it, the prompt's local
    RequiresLineOfSight is switched off (so the camera position no longer
    matters). If your head can't see it, it's left on, exactly like before.
    So "no grabbing loot through walls" (v1.1) still holds, just measured from
    the right place.

    It only ever touches RequiresLineOfSight, never Enabled / range / keys, so
    it can't fight the server or the role filter in CrewHud.

    PUBLIC API
        PromptSight:start()
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PromptSight = {}

local localPlayer = Players.LocalPlayer
local CHECK_RANGE = 16     -- only prompts this close to you are checked
local TICK = 0.15

local prompts = {}         -- [ProximityPrompt] = true   (server wanted line of sight)

local function track(d)
    if d:IsA("ProximityPrompt") and prompts[d] == nil then
        -- remember what the SERVER asked for, before we ever touch it
        if d.RequiresLineOfSight then
            prompts[d] = true
        else
            prompts[d] = false
        end
    end
end

local function promptPos(p)
    local par = p.Parent
    if not par then return nil, nil end
    if par:IsA("Attachment") then return par.WorldPosition, par.Parent end
    if par:IsA("BasePart") then return par.Position, par end
    if par:IsA("Model") then return par:GetPivot().Position, par end
    return nil, nil
end

-- the thing the prompt belongs to: its part, and that part's model (if any)
-- Only SMALL models count (a bag, a register, a bot): if a whole building is a
-- Model, "hit anything in it" would mean seeing through its walls.
local function ownerOf(part)
    if not part then return nil end
    local m = part:FindFirstAncestorOfClass("Model")
    if m and m ~= workspace then
        local ok, size = pcall(function() return m:GetExtentsSize() end)
        if ok and size.Magnitude <= 10 then return m end
    end
    return part
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function headSees(head, pos, holder)
    local from = head.Position
    local dir = pos - from
    local ignore = { localPlayer.Character }
    for _, b in ipairs(CollectionService:GetTagged("BotCrew")) do table.insert(ignore, b) end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= localPlayer and pl.Character then table.insert(ignore, pl.Character) end
    end
    rayParams.FilterDescendantsInstances = ignore
    local hit = workspace:Raycast(from, dir, rayParams)
    if not hit then return true end
    -- hitting the thing the prompt sits on (or its model) is "seeing" it
    local owner = ownerOf(holder)
    if holder and (hit.Instance == holder or hit.Instance == owner or (owner and hit.Instance:IsDescendantOf(owner))) then
        return true
    end
    -- a hit within a stud of the prompt is the prompt's own surface
    return (hit.Position - pos).Magnitude < 1.2
end

function PromptSight:start()
    if self._started then return end
    self._started = true
    for _, d in ipairs(workspace:GetDescendants()) do track(d) end
    workspace.DescendantAdded:Connect(track)
    workspace.DescendantRemoving:Connect(function(d)
        if prompts[d] ~= nil then prompts[d] = nil end
    end)

    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc += dt
        if acc < TICK then return end
        acc = 0
        local char = localPlayer.Character
        local head = char and char:FindFirstChild("Head")
        if not head then return end
        for p, wantsSight in pairs(prompts) do
            if wantsSight and p.Parent then
                local pos, holder = promptPos(p)
                if pos then
                    local near = (pos - head.Position).Magnitude <= math.max(CHECK_RANGE, p.MaxActivationDistance + 2)
                    local sees = near and headSees(head, pos, holder)
                    -- head can see it → the camera's view doesn't matter; else the server's rule
                    local want = not sees
                    if p.RequiresLineOfSight ~= want then p.RequiresLineOfSight = want end
                end
            end
        end
    end)
    print("[HEIST CREW] PromptSight mounted ✅ (prompt line-of-sight from your head, not the camera)")
end

return PromptSight
