local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(3)
	local GC = cmod("GuardCones")
	inClient(function() GC:start() end)
	for _, job in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		waitFor(function() return JS:getPhase() == "idle" end, 60)
		JS:selectJob(job)
		task.wait(1)
		JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
		waitFor(function() return JS:getPhase() == "running" end, 20)
		task.wait(4)
		print("== " .. job)
		for m, c in pairs(GC._cones) do
			if c.shown then
				local d = {}
				for i = 0, 10 do if c.dist[i] then table.insert(d, string.format("%.1f", c.dist[i])) end end
				local root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
				print(string.format("  %s %s floorY=%s reach=%s pos=%s dist=[%s]", c.kind, m.Name, tostring(c.floorY), tostring(c.reach), tostring(root and root.Position), table.concat(d, " ")))
				if c.kind == "Guard" then
					local head = m:FindFirstChild("Head")
					local look = m.HumanoidRootPart.CFrame.LookVector
					local hit = inClient(function() local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { m, p1.Character, WORKSPACE.HC_VisionCones }
						local r = WORKSPACE:Raycast(head.Position, Vector3.new(look.X, -0.05, look.Z).Unit * 30, rp) return r and (r.Instance:GetFullName() .. " @" .. tostring(r.Position)) or "nil" end)
					print("    fwd hit:", hit)
				end
			end
		end
		JS:triggerAlarm("camera", p1)
		task.wait(1)
		pcall(function() JS:catchPlayer(p1, "cop") end)
		for _, f in ipairs({ "finish", "endRun", "reset" }) do end
		task.wait(1)
	end
end, 400)
