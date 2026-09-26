runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("villa")
	task.wait(1)
	local cfg, refs = JS:getCurrent()
	local props = refs.root:FindFirstChild("Props")
	local n, white = 0, 0
	for _, m in ipairs(props:GetChildren()) do
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 if d.Color.R > 0.9 and d.Color.G > 0.9 and d.Color.B > 0.9 then white += 1 print("  still white:", m.Name, d.Name) end end
		end
	end
	print("props models", #props:GetChildren(), "parts", n, "near-white", white)
	local m = Instance.new("Model") m.Name = "pottedPlant"
	local pot = Instance.new("Part") pot.Size = Vector3.new(2, 2, 2) pot.Position = Vector3.new(0, 1, 0) pot.Color = Color3.new(1,1,1) pot.Parent = m
	local leaves = Instance.new("Part") leaves.Size = Vector3.new(3, 3, 3) leaves.Position = Vector3.new(0, 4, 0) leaves.Color = Color3.new(1,1,1) leaves.Parent = m
	m.Parent = props
	task.wait(0.2)
	print("pot", tostring(pot.Color), tostring(pot.Material), "leaves", tostring(leaves.Color), tostring(leaves.Material))
end, 60)
report()
