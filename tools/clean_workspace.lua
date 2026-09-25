-- Paste into Studio's COMMAND BAR (edit mode, NOT while playing) and press Ctrl+Enter.
-- Moves everything in Workspace that the game code did NOT make into
-- ServerStorage._OldInserts. Nothing is deleted: open ServerStorage later to
-- drag something back, or delete the folder once you're happy.
local keep = { Terrain = true, Camera = true, SpawnLocation = true }
local bin = game.ServerStorage:FindFirstChild("_OldInserts") or Instance.new("Folder")
bin.Name = "_OldInserts"
bin.Parent = game.ServerStorage
local moved = 0
for _, child in ipairs(workspace:GetChildren()) do
	if not keep[child.Name] and not child:IsA("Terrain") and not child:IsA("Camera") then
		print("[Cleanup] moving", child:GetFullName(), child.ClassName)
		child.Parent = bin
		moved += 1
	end
end
print("[Cleanup] moved " .. moved .. " thing(s) to ServerStorage._OldInserts")
