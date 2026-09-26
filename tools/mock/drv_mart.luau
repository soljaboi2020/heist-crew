runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local cfg, refs = JS:getCurrent()
	local att = refs.vault.door.DrillPoint
	local target = att.WorldPosition
	print("target", target)
	-- parts near target within 8 studs
	for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(target), Vector3.new(14, 8, 14))) do
		if x.CanCollide or x.CanQuery then print(string.format("   near %s pos %s size %s CanCollide %s CanQuery %s T %.1f", x:GetFullName(), tostring(x.Position), tostring(x.Size), tostring(x.CanCollide), tostring(x.CanQuery), x.Transparency)) end
	end
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { refs.vault.door }
	local counts = {}
	for r = 1.5, 6.5 do for a = 0, 23 do
		local p = target + Vector3.new(math.cos(a * math.pi / 12) * r, 1.5, math.sin(a * math.pi / 12) * r)
		local hit = WORKSPACE:Raycast(p, target - p, rp)
		local k = hit and hit.Instance:GetFullName() or "CLEAR"
		counts[k] = (counts[k] or 0) + 1
	end end
	for k, v in pairs(counts) do print("   ray first-hit", v, k) end
end, 20)
