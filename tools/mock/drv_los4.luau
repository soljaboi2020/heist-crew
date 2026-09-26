runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(4)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("mart") task.wait(0.5)
	local _, refs = JS:getCurrent()
	local att = refs.vault.door:FindFirstChild("DrillPoint")
	local pt = att.WorldPosition
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { refs.vault.door }
	for z = 16.5, 20.5, 1 do
		local line = string.format("z %.1f: ", z)
		for x = 50.5, 59, 1 do
			local r = WORKSPACE:Raycast(Vector3.new(x, 2, z), Vector3.new(0, -8, 0))
			local head = Vector3.new(x, 4.5 + 0.5, z)
			local h = WORKSPACE:Raycast(head, pt - head, rp)
			line = line .. string.format("[%4.1f %s] ", x, h and h.Instance.Name:sub(1, 10) or "CLEAR")
		end
		print(line)
	end
end, 30)
