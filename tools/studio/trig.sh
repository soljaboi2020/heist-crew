#!/bin/bash
# trig.sh "<ActionText substring>" [holdSeconds]
cat > /tmp/trig.lua <<LUA
local p = game.Players.LocalPlayer; local hrp = p.Character.HumanoidRootPart
local best, bd
for _, d in ipairs(workspace:GetDescendants()) do
  if d:IsA("ProximityPrompt") and d.Enabled and string.find(d.ActionText, "$1", 1, true) then
    local par = d.Parent; local pos = par:IsA("Attachment") and par.WorldPosition or par.Position
    local dist = (pos - hrp.Position).Magnitude
    if not bd or dist < bd then best, bd = d, dist end
  end
end
if not best then return "no prompt" end
local fired = false
local c = best.Triggered:Connect(function() fired = true end)
best:InputHoldBegin(); task.wait(best.HoldDuration + 0.3); best:InputHoldEnd(); task.wait(0.3); c:Disconnect()
return best.ActionText .. "/" .. best.ObjectText .. " dist " .. string.format("%.1f", bd) .. " fired " .. tostring(fired)
LUA
"$(dirname "$0")/lua.sh" Client /tmp/trig.lua
