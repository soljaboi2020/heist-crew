runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("villa")
	task.wait(1)
	local cfg, refs = JS:getCurrent()
	local VS = mockRequire(SERVER_SCRIPT.VehicleService)
	local car = VS:getCar()
	local carModel = car and car.model
	local start = refs.getawayCFrame.Position
	print("car at", tostring(carModel and carModel:GetPivot().Position))
	-- sweep: car AABB x ±2.45 (a little wider than 4.7), length 11.2, y ground+0.9 .. +3.4
	local hits = {}
	local function aabb(p)
		local cf, s = p.CFrame, p.Size / 2
		local mn = Vector3.new(math.huge, math.huge, math.huge)
		local mx = -mn
		for _, dx in ipairs({ -1, 1 }) do for _, dy in ipairs({ -1, 1 }) do for _, dz in ipairs({ -1, 1 }) do
			local w = cf * Vector3.new(s.X * dx, s.Y * dy, s.Z * dz)
			mn = Vector3.new(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
			mx = Vector3.new(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
		end end end
		return mn, mx
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { carModel }
	rp.RespectCanCollide = true
	local prevY = nil
	for z = start.Z, -12, 0.5 do
		-- ground under centre, nose, tail
		local ys = {}
		for _, off in ipairs({ 0, 4.6, -4.6 }) do
			local r = WORKSPACE:Raycast(Vector3.new(start.X, 6, z + off), Vector3.new(0, -80, 0), rp)
			table.insert(ys, r and r.Position.Y or -999)
			if not r then print("VOID at z", z + off) end
		end
		local gy = math.max(ys[1], ys[2], ys[3])
		if prevY and gy - prevY > 1.2 then print(string.format("STEP %.2f at z %.1f", gy - prevY, z)) end
		prevY = gy
		local lo = Vector3.new(start.X - 2.45, gy + 0.9, z - 5.6)
		local hi = Vector3.new(start.X + 2.45, gy + 3.4, z + 5.6)
		for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new((lo + hi) / 2), hi - lo)) do
			if p.CanCollide and not p:IsDescendantOf(carModel) and not hits[p] then
				local mn, mx = aabb(p)
				if mx.X > lo.X and mn.X < hi.X and mx.Y > lo.Y and mn.Y < hi.Y and mx.Z > lo.Z and mn.Z < hi.Z then
					hits[p] = true
					print(string.format("OBSTACLE at car z %.1f: %s  x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f", z, p:GetFullName(), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z))
				end
			end
		end
	end
	print("sweep done, final ground y", prevY)
end, 60)
report()
