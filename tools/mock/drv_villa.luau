runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("villa")
	task.wait(1)
	local cfg, refs = JS:getCurrent()
	local n, lights, shadowLights, guis = 0, 0, 0, 0
	for _, d in ipairs(refs.root:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then lights += 1 if d.Shadows then shadowLights += 1 end end
		if d:IsA("SurfaceGui") then guis += 1 end
	end
	print(string.format("VILLA parts=%d lights=%d shadowed=%d surfaceguis=%d", n, lights, shadowLights, guis))
	print("getaway", tostring(refs.getawayCFrame.Position), tostring(refs.getawayCFrame.LookVector))
	local car = WORKSPACE:FindFirstChild("GetawayCar", true)
	if car then print("car pivot", tostring(car:GetPivot().Position)) end
end, 60)
report()
