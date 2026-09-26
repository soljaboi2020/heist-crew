--[[
    HEIST CREW — BotFade (v3.3.1)
    ────────────────────────────────────────────────
    Found in a Claude-driven Studio playtest: the AI crewmates (BotService) walk
    behind their player, which is exactly where the camera sits, so two bots
    filled half the screen in the small back rooms.

    BotService now trails them off to the side, and this is the safety net: any
    bot standing between the camera and your character (or right up against the
    camera) fades out locally with LocalTransparencyModifier, the same trick
    Roblox uses for your own character when you zoom in. It's purely visual and
    only on YOUR screen. Nothing is sent to the server.

    PUBLIC API
        BotFade:start()
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BotFade = {}

local localPlayer = Players.LocalPlayer
local FADE = 0.75          -- how see-through a blocking bot gets
local LINE_RADIUS = 3.2    -- studs from the camera→you line that counts as "in the way"
local NEAR_CAMERA = 4.5    -- any bot this close to the camera fades regardless

local faded = {}           -- [Model] = true

local function setModel(model, amount)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            d.LocalTransparencyModifier = amount
        end
    end
end

local function blocking(model, camPos, target)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root then return false end
    local p = root.Position
    if (p - camPos).Magnitude < NEAR_CAMERA then return true end
    local line = target - camPos
    local len = line.Magnitude
    if len < 1e-3 then return false end
    local dir = line / len
    local t = (p - camPos):Dot(dir)
    if t <= 0 or t >= len - 1 then return false end   -- behind the camera, or past you
    local closest = camPos + dir * t
    return (p - closest).Magnitude < LINE_RADIUS
end

function BotFade:start()
    if self._started then return end
    self._started = true
    local acc = 0
    RunService.RenderStepped:Connect(function(dt)
        acc += dt
        if acc < 0.1 then return end
        acc = 0
        local cam = workspace.CurrentCamera
        local char = localPlayer.Character
        local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
        local seen = {}
        if cam and head then
            local camPos = cam.CFrame.Position
            for _, m in ipairs(CollectionService:GetTagged("BotCrew")) do   -- BotService tags every bot
                if m:IsA("Model") and m:IsDescendantOf(workspace) then
                    if blocking(m, camPos, head.Position) then
                        seen[m] = true
                        if not faded[m] then
                            faded[m] = true
                            setModel(m, FADE)
                        end
                    end
                end
            end
        end
        for m in pairs(faded) do
            if not seen[m] then
                faded[m] = nil
                if m.Parent then setModel(m, 0) end
            end
        end
    end)
    print("[HEIST CREW] BotFade mounted ✅")
end

return BotFade
