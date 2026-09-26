runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local want = { villa = { 1, 5 }, jewelry = { 2 }, bank = { 2, 5 } }
	for id, list in pairs(want) do
		JS:selectJob(id)
		task.wait(0.3)
		local _, refs = JS:getCurrent()
		for _, i in ipairs(list) do
			local spot = refs.keycardSpots[i]
			local target = (spot * CFrame.new(0, 0.05, 0)).Position
			print(id, i, target)
			local counts = {}
			for r = 2, 6 do for a = 0, 11 do
				local p = target + Vector3.new(math.cos(a * math.pi / 6) * r, 1.5, math.sin(a * math.pi / 6) * r)
				local hit = WORKSPACE:Raycast(p, target - p)
				local k = hit and (hit.Instance:GetFullName() .. (hit.Instance:IsA("MeshPart") and " [mesh bbox]" or "")) or "CLEAR"
				counts[k] = (counts[k] or 0) + 1
			end end
			for k, v in pairs(counts) do print("     ", v, k) end
			-- containing parts
			for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(target), Vector3.new(0.2, 0.2, 0.2))) do
				local l = x.CFrame:PointToObjectSpace(target) local h = x.Size / 2
				if math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z then print("      INSIDE " .. x:GetFullName() .. " size " .. tostring(x.Size)) end
			end
		end
	end
end, 30)
