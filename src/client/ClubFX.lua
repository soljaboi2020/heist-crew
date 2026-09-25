--[[
    HEIST CREW — ClubFX  (v1.2)
    ────────────────────────────────────────────────
    Makes The Vault feel alive — ALL client-side, so none of it costs network
    traffic and every player sees it smoothly:

      DanceTile  glass floor tiles ripple through pink / cyan / purple
      ClubLight  coloured point lights over the floor pulse and shift hue
      ClubSpot   moving-head spots on the stage truss sweep the room
      ClubEQ     the LED wall's equaliser bars bounce
      MarqueeBulb (v2.0) the bulbs round THE VAULT sign over the arch chase
      PortalGlow  (v2.0) each heist door's floor light breathes; faster and
                  brighter while that door counts down (attribute State =
                  idle | busy | launch | locked, set by the server)

    Only runs while you're down in the club (below y -10), to save work
    everywhere else.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local ClubFX = {}
local localPlayer = Players.LocalPlayer

local PALETTE = {
    Color3.fromRGB(255, 70, 180),
    Color3.fromRGB(40, 230, 255),
    Color3.fromRGB(170, 90, 255),
    Color3.fromRGB(255, 150, 60),
}

local function pick(t)
    local n = #PALETTE
    local i = math.floor(t) % n + 1
    local j = i % n + 1
    return PALETTE[i]:Lerp(PALETTE[j], t % 1)
end

function ClubFX:start()
    local spotBase = {}
    local function base(p)
        if not spotBase[p] then spotBase[p] = p.CFrame end
        return spotBase[p]
    end
    local acc = 0
    RunService.RenderStepped:Connect(function(dt)
        local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not root or root.Position.Y > Constants.WORLD.HUB_FLOOR + 20 then return end
        acc = acc + dt
        if acc < 1 / 30 then return end   -- 30 fps is plenty for lights
        local step = acc
        acc = 0
        local t = os.clock()

        for _, tile in ipairs(CollectionService:GetTagged("DanceTile")) do
            local c = tile:GetAttribute("Col") or 0
            local r = tile:GetAttribute("Row") or 0
            local wave = t * 1.4 - (c + r) * 0.18
            tile.Color = pick(wave)
            tile.Transparency = 0.05 + 0.25 * (0.5 + 0.5 * math.sin(t * 5 + c * 0.7 - r * 0.5))
        end
        for _, anchor in ipairs(CollectionService:GetTagged("ClubLight")) do
            local seed = anchor:GetAttribute("Seed") or 1
            local l = anchor:FindFirstChildWhichIsA("Light")
            if l then
                l.Color = pick(t * 0.6 + seed)
                l.Brightness = 1.4 + 1.2 * (0.5 + 0.5 * math.sin(t * 4 + seed))
            end
        end
        for _, head in ipairs(CollectionService:GetTagged("ClubSpot")) do
            local seed = head:GetAttribute("Seed") or 1
            local yaw = math.sin(t * 0.7 + seed * 1.7) * 0.9
            local pitch = -0.2 + math.sin(t * 0.5 + seed) * 0.35
            head.CFrame = base(head) * CFrame.Angles(pitch, yaw, 0)
        end
        for _, g in ipairs(CollectionService:GetTagged("ClubEQ")) do
            local eq = g:FindFirstChild("EQ", true)
            if eq then
                for _, bar in ipairs(eq:GetChildren()) do
                    if bar:IsA("Frame") then
                        local i = bar.LayoutOrder
                        local h = 0.15 + 0.85 * math.abs(math.sin(t * (2.2 + (i % 5) * 0.4) + i * 0.9)) * (0.6 + 0.4 * math.sin(t * 1.3))
                        bar.Size = UDim2.new(bar.Size.X.Scale, bar.Size.X.Offset, h, 0)
                    end
                end
            end
        end
        -- v2.0 lobby
        for _, b in ipairs(CollectionService:GetTagged("MarqueeBulb")) do
            local i = b:GetAttribute("Index") or 0
            local on = (math.floor(t * 8) - i) % 4 ~= 0
            b.Transparency = on and 0 or 0.75
        end
        for _, g in ipairs(CollectionService:GetTagged("PortalGlow")) do
            local l = g:FindFirstChildWhichIsA("Light")
            if l then
                local st = g:GetAttribute("State")
                if st == "locked" then
                    l.Enabled = false
                else
                    l.Enabled = true
                    local speed, base, amp = 2, 0.8, 0.4
                    if st == "busy" then speed, base, amp = 3.5, 1.3, 0.5 end
                    if st == "launch" then speed, base, amp = 9, 2, 1 end
                    l.Brightness = base + amp * (0.5 + 0.5 * math.sin(t * speed))
                end
            end
        end
        local _ = step
    end)
    print("[HEIST CREW] ClubFX mounted ✅")
end

return ClubFX
