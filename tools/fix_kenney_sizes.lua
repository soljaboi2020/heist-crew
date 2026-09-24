-- Paste into Roblox Studio's COMMAND BAR (View -> Command Bar), press Enter.
-- Shrinks every imported Kenney model in Workspace to its real size, restores
-- its colour, and sets it down on the ground. Changes only Kenney meshes it
-- recognises by name; anything else is listed in Output and left alone.
local K = require(game.ReplicatedStorage.Shared.KenneyKit)
local fixed, unknown = 0, {}
local function find(name)
	name = string.lower(name or "")
	for kit, t in pairs(K.SIZES) do
		for key in pairs(t) do
			if string.lower(key) == name then return kit, key end
		end
	end
end
for _, p in ipairs(workspace:GetDescendants()) do
	if p:IsA("MeshPart") and not p:IsDescendantOf(workspace:FindFirstChild("HeistWorld") or Instance.new("Folder")) then
		local kit, key = find(p.Name)
		if not kit and p.Parent then kit, key = find(p.Parent.Name) end
		if kit then
			local bottom = p.Position.Y - p.Size.Y / 2
			K.applySize(p, kit, key)
			K.applyColor(p, key)
			p.Position = Vector3.new(p.Position.X, math.max(bottom, 0.5) + p.Size.Y / 2, p.Position.Z)
			fixed += 1
		elseif p.Size.Magnitude > 60 then
			table.insert(unknown, p:GetFullName() .. " " .. tostring(p.Size))
		end
	end
end
print("[KenneyFix] resized " .. fixed .. " model(s)")
for _, u in ipairs(unknown) do warn("[KenneyFix] big mesh I don't recognise: " .. u) end
