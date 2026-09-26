runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(3)
	local cg
	for _, d in ipairs(WORKSPACE:GetDescendants()) do if d.Name == "CityGround" then cg = d break end end
	local c = {}
	local models = {}
	for _, p in ipairs(cg:GetDescendants()) do
		if p:IsA("BasePart") then
			local k = p.Parent:IsA("Model") and ("M:" .. p.Parent.Name) or p.Name
			c[k] = (c[k] or 0) + 1
		elseif p:IsA("Model") then models[p.Name] = (models[p.Name] or 0) + 1 end
	end
	local arr = {}
	for k, v in pairs(c) do table.insert(arr, {k, v}) end
	table.sort(arr, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(20, #arr) do print(arr[i][1], arr[i][2]) end
	for k, v in pairs(models) do print("model", k, v) end
end, 60)
report()
