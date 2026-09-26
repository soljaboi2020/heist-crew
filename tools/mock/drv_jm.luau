runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local VS = mockRequire(SERVER_SCRIPT.VehicleService)
	local Kin = VS.Kinematic
	for _, id in ipairs({ "mart", "jewelry" }) do
		JS:selectJob(id)
		task.wait(2)
		local cfg, refs = JS:getCurrent()
		local n, lights, shadowLights, guis = 0, 0, 0, 0
		for _, d in ipairs(refs.root:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then lights += 1 if d.Shadows then shadowLights += 1 end end
			if d:IsA("SurfaceGui") then guis += 1 end
		end
		print(string.format("%s parts=%d lights=%d shadowed=%d surfaceguis=%d", id, n, lights, shadowLights, guis))
		print("getaway", tostring(refs.getawayCFrame.Position), tostring(refs.getawayCFrame.LookVector))
		local car = VS:spawnGetaway(refs.getawayCFrame)
		task.wait(0.1)
		print("car pos", tostring(car.pos), "yaw", car.yaw)
		-- anything solid overlapping the parked car?
		local cf = CFrame.new(car.pos) * CFrame.Angles(0, car.yaw, 0)
		for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(cf * CFrame.new(0, 2.5, 0), Vector3.new(4.9, 4, 11.4))) do
			if x.CanCollide and not x:IsDescendantOf(car.model) and x.Size.Y > 0.3 and x.Position.Y > car.pos.Y + 0.2 then
				print("  OVERLAP parked car:", x:GetFullName(), tostring(x.Position), tostring(x.Size))
			end
		end
		local gEx, oEx = Kin.filters(car.model)
		local body = { pos = car.pos, yaw = car.yaw, v = 18, halfLen = 5.6, width = 4.7, model = car.model }
		local steps = 0
		while steps < 400 and body.pos.Z > -12 do
			local blocked = Kin.advance(body, 1 / 30, gEx, oEx)
			steps += 1
			if blocked then
				local hit = Kin.obstacle(CFrame.new(body.pos) * CFrame.Angles(0, body.yaw, 0), 1, 5.6, 4.7, 2, oEx)
				print("  BLOCKED at", tostring(body.pos), hit and hit.Instance:GetFullName() or "(ground)")
				break
			end
		end
		print("  drove to", tostring(body.pos), "steps", steps)
	end
end, 60)
report()
