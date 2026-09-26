runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(3)
	local camPos
	local co = newThread(function() camPos = WORKSPACE.CurrentCamera.CFrame.Position end, CLIENT_CTX) resumeThread(co)
	print("client cam", camPos, "server cam", WORKSPACE.CurrentCamera.CFrame.Position)
	local spin = Instance.new("Part") spin.Anchored = true spin.Parent = WORKSPACE spin.CFrame = CFrame.new(WORKSPACE.CurrentCamera.CFrame.Position + Vector3.new(0, 0, -20))
	spin:SetAttribute("Spin", 90)
	CollectionService:AddTag(spin, "Spin")
	local LH = nil
	local co2 = newThread(function()
		LH = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("LootHud"))
		print("tagged", #CollectionService:GetTagged("Spin"), "isDesc", spin:IsDescendantOf(WORKSPACE), "rate", spin:GetAttribute("Spin"))
		local ok, e = pcall(function() LH:_startSpinners() end) print("start", ok, e)
	end, CLIENT_CTX) resumeThread(co2)
	local l0 = spin.CFrame.LookVector
	task.wait(1)
	print("look", l0, spin.CFrame.LookVector)
	local co3 = newThread(function()
		local cam = WORKSPACE.CurrentCamera
		print("cam", cam, cam and cam.CFrame.Position)
		for _, p in ipairs(CollectionService:GetTagged("Spin")) do print("  spin", p:GetFullName(), p.Position, cam and (p.Position - cam.CFrame.Position).Magnitude, p:GetAttribute("Spin")) end
		local c0 = spin.CFrame
		spin.CFrame = spin.CFrame * CFrame.Angles(0, math.rad(45), 0)
		print("manual", c0.LookVector, spin.CFrame.LookVector)
	end, CLIENT_CTX) resumeThread(co3)
end, 30)
report()
