runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("villa")
	task.wait(1)
	local cfg, refs = JS:getCurrent()
	local by = {}
	for _, d in ipairs(refs.root:GetDescendants()) do
		if d:IsA("BasePart") then
			local top = d
			while top.Parent ~= refs.root do top = top.Parent end
			local k = top.Name
			if top.Name == "Grounds" or top.Name == "Finishes" then
				local sub = d
				while sub.Parent ~= top do sub = sub.Parent end
				k = top.Name .. "/" .. sub.Name .. ":" .. d.Name
			end
			by[k] = (by[k] or 0) + 1
		end
	end
	local keys = {}
	for k, v in pairs(by) do table.insert(keys, k) end
	table.sort(keys, function(a, b) return by[a] > by[b] end)
	for i, k in ipairs(keys) do if i <= 40 then print(k, by[k]) end end
end, 60)
report()
