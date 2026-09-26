#!/bin/bash
# usage: walk.sh x y z   — walks the player's character there via PathfindingService (server)
cat > /tmp/walk.lua <<LUA
local PFS = game:GetService("PathfindingService")
local p = game.Players:GetPlayers()[1]
local char = p.Character; local hum = char:FindFirstChildOfClass("Humanoid"); local hrp = char.HumanoidRootPart
local goal = Vector3.new($1, $2, $3)
local path = PFS:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
path:ComputeAsync(hrp.Position, goal)
if path.Status ~= Enum.PathStatus.Success then return "no path: " .. path.Status.Name end
for _, w in ipairs(path:GetWaypoints()) do
  hum:MoveTo(w.Position)
  local t0 = os.clock()
  while (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(w.Position.X, 0, w.Position.Z)).Magnitude > 2.5 and os.clock() - t0 < 3 do task.wait(0.1) end
end
return "arrived near " .. tostring(hrp.Position)
LUA
"$(dirname "$0")/lua.sh" Server /tmp/walk.lua
