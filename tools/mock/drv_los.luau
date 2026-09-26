runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({ "mart", "villa", "bank", "jewelry" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		local v = refs.vault
		local door = v.door
		print("== " .. id .. " vault door " .. door:GetFullName() .. " size " .. tostring(door.Size) .. " pos " .. tostring(door.Position) .. " look " .. tostring(door.CFrame.LookVector))
		for i, p in ipairs(v.parts or {}) do print(string.format("   part %d %s size %s pos %s", i, p.Name, tostring(p.Size), tostring(p.Position))) end
		for a = 0, 15 do
			local ang = a * math.pi / 8
			for _, dist in ipairs({ 3, 5 }) do
				for _, hy in ipairs({ 1.5, 0 }) do
					local from = door.Position + Vector3.new(math.cos(ang) * dist, hy, math.sin(ang) * dist)
					local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { door }
					local hit = WORKSPACE:Raycast(from, door.Position - from, rp)
					if not hit then print(string.format("   CLEAR from angle %d dist %d dy %.1f  (%s)", a * 22.5, dist, hy, tostring(from))) end
				end
			end
		end
		-- for the 2 main axis directions, show what blocks
		for _, dir in ipairs({ door.CFrame.LookVector, -door.CFrame.LookVector, door.CFrame.RightVector, -door.CFrame.RightVector }) do
			local from = door.Position + dir * 4 + Vector3.new(0, 1.5, 0)
			local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { door }
			local hit = WORKSPACE:Raycast(from, door.Position - from, rp)
			print("   from " .. tostring(dir) .. " side: first hit " .. (hit and (hit.Instance:GetFullName() .. " CanQuery=" .. tostring(hit.Instance.CanQuery) .. " at " .. tostring(hit.Position)) or "none"))
		end
		if id == "bank" then
			for _, pr in ipairs(findPrompts(refs.root)) do
				if pr.Name == "BagLoot" then
					local pos = pr.Parent.Position
					local clear = 0
					for a = 0, 7 do
						local from = pos + Vector3.new(math.cos(a * math.pi / 4) * 5, 1, math.sin(a * math.pi / 4) * 5)
						local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { pr.Parent }
						local hit = WORKSPACE:Raycast(from, pos - from, rp)
						if not hit then clear += 1 end
						if a == 0 and hit then print("   loot@" .. tostring(pos) .. " " .. pr.ObjectText .. " blocked by " .. hit.Instance:GetFullName()) end
					end
					if clear == 0 then print("   ENCLOSED loot " .. pr.ObjectText .. " at " .. tostring(pos)) end
				end
			end
		end
	end
end, 60)
