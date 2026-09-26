local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local jobs = {}
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		JS:selectJob(id) task.wait(0.3)
		local _, r = JS:getCurrent() jobs[id] = r
	end
	local BS = mockRequire(SERVER_SCRIPT.BriefingShots)
	local all = BS:publish({ jobs = jobs })
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(30)
	local BUI = inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("BriefingUI")) end)
	local prompt = findPrompts(WORKSPACE, function(x) return x.Name == "Briefing" end)[1]
	check(prompt ~= nil, "Boss Briefing prompt found")
	local camProxy = {}
	setmetatable(camProxy, { __index = function(_, k) return inClient(function() return WORKSPACE.CurrentCamera[k] end) end })
	local cam = camProxy
	local pg = p1.PlayerGui
	local gui = pg:FindFirstChild("BriefingUI")
	local function hudEnabledCount()
		return inClient(function() local n = 0 for _, g in ipairs(pg:GetChildren()) do if g:IsA("ScreenGui") and g ~= gui and g.Enabled then n += 1 end end return n end)
	end
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		JS:selectJob(id) task.wait(0.5)
		local cfg
		for _, j in ipairs(mockRequire(REPLICATED.Shared.Constants).JOBS) do if j.id == id then cfg = j end end
		-- plan
		local shots = inClient(function() return BUI._loadShots(id) end)
		local plan = inClient(function() return BUI._planShots(cfg.briefing, shots) end)
		local tags = {}
		for i, st in ipairs(plan) do tags[i] = st.shot.tag .. (st.reversed and "<" or "") end
		print("  " .. id .. " line→shot: " .. table.concat(tags, " "))
		check(plan[1].shot.tag == "wide", id .. " line 1 is the wide shot")
		local hud0 = hudEnabledCount()
		inClient(function() p1:SetAttribute("HeardPlan", nil) end)
		triggerPrompt(prompt, p1)
		task.wait(0.6)
		check(cam.CameraType == Enum.CameraType.Scriptable, id .. " camera scriptable during briefing")
		local chip = gui:FindFirstChild("ShotCaption", true)
		check(chip and inClient(function() return chip.Visible end), id .. " caption chip visible: " .. tostring(chip and chip:FindFirstChildWhichIsA("TextLabel").Text))
		check(hudEnabledCount() == 0, id .. " other HUD hidden (" .. hud0 .. " → " .. hudEnabledCount() .. ")")
		-- sample the camera through each line: must be near the planned shot
		local far = 0
		for i, st in ipairs(plan) do
			task.wait(2.1)
			local s = st.shot
			local ccf = cam.CFrame
		local d = math.min((ccf.Position - s.from.Position).Magnitude + (ccf.Position - s.to.Position).Magnitude)
			local seg = (s.from.Position - s.to.Position).Magnitude
			if d > seg + 1 then far += 1 print(string.format("    line %d cam (%.1f,%.1f,%.1f) not on shot %s", i, ccf.X, ccf.Y, ccf.Z, s.tag)) end
			local c = { ccf:GetComponents() } for _, x in ipairs(c) do if x ~= x then far += 100 end end
			task.wait(4.2 - 2.1 + (i < #plan and 0.13 or 0))
		end
		check(far == 0, id .. " camera followed the planned shots line by line")
		waitFor(function() return inClient(function() return p1:GetAttribute("HeardPlan") end) == true end, 6)
		task.wait(0.6)
		check(inClient(function() return p1:GetAttribute("HeardPlan") end) == true, id .. " HeardPlan set")
		check(cam.CameraType == Enum.CameraType.Custom, id .. " camera restored (" .. tostring(cam.CameraType) .. ")")
		check(hudEnabledCount() == hud0, id .. " HUD restored (" .. hudEnabledCount() .. "/" .. hud0 .. ")")
		check(not inClient(function() return chip.Visible end), id .. " chip hidden after")
		check(inClient(function() return gui:FindFirstChild("Ready").Visible end), id .. " GOT IT card shown")
		inClient(function() BUI._ui.readyCard.Visible = false end)
	end
	-- skip mid-way
	JS:selectJob("bank") task.wait(0.5)
	inClient(function() p1:SetAttribute("HeardPlan", nil) end)
	triggerPrompt(prompt, p1) task.wait(3)
	pressKey(Enum.KeyCode.Space) task.wait(1)
	check(inClient(function() return p1:GetAttribute("HeardPlan") end) == true and cam.CameraType == Enum.CameraType.Custom, "Space skips the fly-through and restores the camera")
	check(hudEnabledCount() > 0, "HUD back after skip")
	-- no shots → old club camera
	REPLICATED.BriefingShots:Destroy()
	inClient(function() BUI._ui.readyCard.Visible = false end)
	inClient(function() p1:SetAttribute("HeardPlan", nil) end)
	local hud0 = hudEnabledCount()
	triggerPrompt(prompt, p1) task.wait(1)
	local fy = cam.CFrame.Y
		check(cam.CameraType == Enum.CameraType.Scriptable and fy < -10, "no shots → old club camera (y " .. string.format("%.1f", fy) .. ")")
	check(hudEnabledCount() == hud0, "fallback leaves the HUD alone")
	waitFor(function() return inClient(function() return p1:GetAttribute("HeardPlan") end) == true end, 60)
	task.wait(0.6)
	check(inClient(function() return p1:GetAttribute("HeardPlan") end) == true and cam.CameraType == Enum.CameraType.Custom, "fallback briefing finishes + restores")
	local fails = 0 for _, c in ipairs(CHECKS) do if c:sub(1,4) == "FAIL" then fails += 1 end end
	print(string.format("CHECKS %d/%d passed", #CHECKS - fails, #CHECKS))
end, 400)
report()
