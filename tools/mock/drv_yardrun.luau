runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local VS = mockRequire(SERVER_SCRIPT.VehicleService)
	local Amb = SERVER_SCRIPT:FindFirstChild("AmbientService") and mockRequire(SERVER_SCRIPT.AmbientService)
	local p1 = addPlayer("Malachi")
	task.wait(1)
	local total = 0
	for _, id in ipairs(YARD_JOBS) do
		JS:selectJob(id)
		task.wait(1)
		local cfg, refs = JS:getCurrent()
		local car = VS:getCar()
		local cf = refs.getawayCFrame
		local mcf, msz = car.model:GetBoundingBox()
		print(string.format("== %s getaway %s look %s | car bbox size %s", id, tostring(cf.Position), tostring(cf.LookVector), tostring(msz)))
		local stopZ = cf.LookVector.Z > 0 and -12 or -16
		-- ignore ambient traffic/pedestrians (dynamic)
		local amb = WORKSPACE:FindFirstChild("Ambient", true)
		local n = laneSweep(id, cf, car.model, stopZ, function(p) return amb and p:IsDescendantOf(amb) end)
		total += n
		print(string.format("   static lane issues: %d", n))
		-- real drive
		local ep = car.driverSeat:FindFirstChild("EnterPrompt")
		triggerPrompt(ep, p1)
		task.wait(0.5)
		print("   driver:", car:getDriver() and car:getDriver().Name)
		local ok = autoDrive(id, car, p1, marinaWaypoints(cf), 90)
		local dm = (Vector3.new(car.pos.X, 0, car.pos.Z) - Vector3.new(106, 0, -110)).Magnitude
		print(string.format("   DRIVE %s: reached marina ring? %s (dist %.1f, final %s)", id, tostring(ok and dm <= 14), dm, tostring(car.pos)))
		if not (ok and dm <= 14) then total += 1 end
		car:ejectAll()
		task.wait(0.5)
	end
	print("YARD TOTAL issues: " .. total)
end, 900)
report()
