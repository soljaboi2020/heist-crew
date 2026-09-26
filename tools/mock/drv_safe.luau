runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("mart") task.wait(0.5)
	local _, refs = JS:getCurrent()
	local door = refs.vault.door
	local att = door:FindFirstChild("DrillPoint")
	print("door", door:GetFullName(), "pos", door.Position, "size", door.Size, "look", door.CFrame.LookVector)
	print("att world", att.WorldPosition)
	for k, v in pairs(refs.vault) do print("vault." .. k, typeof(v) == "Instance" and v:GetFullName() or tostring(v)) end
	local pt = att.WorldPosition
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pt), Vector3.new(8, 6, 8))) do
		local mn, mx = partAABB(p)
		print(string.format("  %-66s CC=%s CQ=%s x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f %s", p:GetFullName(), tostring(p.CanCollide), tostring(p.CanQuery), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z, partContainsPoint(p, pt) and "<<CONTAINS PROMPT" or ""))
	end
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { door }
	for i = 0, 7 do
		local a = i * math.pi / 4
		local from = pt + Vector3.new(math.cos(a) * 5, 1, math.sin(a) * 5)
		local h = WORKSPACE:Raycast(from, pt - from, rp)
		print("  ray from", from, "→", h and h.Instance:GetFullName() or "CLEAR")
	end
end, 10)
