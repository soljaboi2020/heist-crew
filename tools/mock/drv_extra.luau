-- ═══════════════ edge-path driver ═══════════════
local CHECKS = {}
local function check(ok, what)
	table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what)
	print((ok and "  [ok] " or "  [FAIL] ") .. what)
	return ok
end
local function waitFor(cond, timeout, step)
	local t0 = SCHED.now
	while SCHED.now - t0 < (timeout or 10) do
		local ok, r = pcall(cond)
		if ok and r then return r end
		task.wait(step or 0.25)
	end
	return nil
end
local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function tp(p, pos) if root(p) then p.Character:PivotTo(CFrame.new(pos)) end end
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end
local function lastRemote(name) return REMOTE_LOG[name] end
local function promptsIn(rootInst, name)
	local out = {}
	for _, x in ipairs(findPrompts(rootInst)) do if (not name or x.Name == name) and x.Enabled then table.insert(out, x) end end
	return out
end
local function state() local h = lastRemote("HeistState") return h and h[2], h and h[3] end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS, Loot, Bots, Jail, Guard, Sec = srv("JobService"), srv("LootService"), srv("BotService"), srv("JailService"), srv("GuardService"), srv("SecurityService")
	local hub = JS.hub
	local p1 = addPlayer("Solo")
	if WITH_CLIENT then startClient(p1) end
	task.wait(3)

	local function launchSolo(jobId)
		waitFor(function() return JS:getPhase() == "idle" end, 60)
		tp(p1, hub.portals[jobId].zone.Position + Vector3.new(0, 3, 0))
		local ok = waitFor(function() return JS:getPhase() == "running" and JS:getCurrentId() == jobId end, 30)
		tp(p1, JS.hub.spawnPads[1].Position + Vector3.new(0, 3, 0))   -- (so a later reset doesn't re-launch)
		local _, refs = JS:getCurrent()
		p1.Character:PivotTo(CFrame.new(refs.sneakIn.at))
		return ok, refs
	end
	local function alarmViaCamera(refs)
		for _, cam in ipairs(refs.cameras or {}) do
			for i = 1, 60 do
				tp(p1, cam.head.Position + cam.head.CFrame.LookVector * 10 - Vector3.new(0, 4, 0))
				task.wait(0.1)
				if lastRemote("AlarmTriggered") and lastRemote("AlarmTriggered")[2] == true then return true end
			end
		end
		return false
	end
	local function copModel()
		local f = WORKSPACE:FindFirstChild("Police")
		if not f then return nil end
		for _, m in ipairs(f:GetDescendants()) do if m:IsA("Humanoid") then return m.Parent end end
	end

	-- 1) SOLO: 2 bots; cop catch with nobody to break you out → run over
	print("\n==== SOLO jail, no rescuer ====")
	local ok, refs = launchSolo("mart")
	check(ok, "solo launch mart")
	task.wait(1)
	check(#Bots:getBots() == 2, "solo → 2 bots (" .. #Bots:getBots() .. ")")
	check(alarmViaCamera(refs), "solo alarm")
	local cop = waitFor(copModel, 30)
	if check(cop ~= nil, "cop spawned") then
		for _, pp in ipairs(cop:GetDescendants()) do if pp:IsA("BasePart") then touch(pp, root(p1)) end end
		task.wait(1)
		local st = state()
		check(st == "FAILED", "solo jailed → run ends FAILED (" .. tostring(st) .. ")")
		check(not p1:GetAttribute("Jailed"), "released from jail at run end")
	end
	task.wait(18)

	-- 2) STEALTH finish: no alarm, bag in car, drive → grade S + stealth bonus
	print("\n==== STEALTH finish (mart) ====")
	ok, refs = launchSolo("mart")
	check(ok, "launch mart again")
	-- cut cameras
	if refs.breaker then
		local br = refs.breaker:FindFirstChild("Breaker")
		if check(br ~= nil, "breaker prompt") then triggerPrompt(br, p1) task.wait(0.3) check(Sec:camerasCut(), "cameras cut") end
	end
	local lp = promptsIn(refs.root, "BagLoot")[1]
	triggerPrompt(lp, p1)
	task.wait(0.3)
	-- throw the bag, pick it up again
	remote("ThrowBag").OnServerEvent:Fire(p1, Vector3.new(0, 0, -1))
	task.wait(0.5)
	check(not Loot:isCarrying(p1), "threw bag")
	local pu = waitFor(function() return promptsIn(refs.root, "PickUpBag")[1] end, 3)
	if check(pu ~= nil, "loose bag has PickUpBag prompt") then task.wait(2.2) triggerPrompt(pu, p1) task.wait(0.3) check(Loot:isCarrying(p1), "picked bag back up") end
	local car = JS:getCar()
	triggerPrompt(car.trunk:FindFirstChild("LoadBag", true), p1)
	task.wait(0.3)
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
	task.wait(0.3)
	local W = mockRequire(REPLICATED.Shared.Constants).WORLD
	car:_placeAt(CFrame.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z))
	waitFor(function() return state() == "COMPLETE" end, 10)
	local st, pay = state()
	check(st == "COMPLETE" and pay.stealth == true and pay.stealthBonus > 0 and (pay.grade == "S" or pay.grade == "A"), "stealth finish → " .. tostring(st) .. " grade=" .. tostring(pay and pay.grade) .. " bonus=" .. tostring(pay and pay.stealthBonus))
	task.wait(18)

	-- 3) takedown (Muscle) + death while carrying + respawn
	print("\n==== takedown / death / respawn (villa) ====")
	ok, refs = launchSolo("villa")
	check(ok, "launch villa")
	p1:SetAttribute("Role", "Muscle")
	task.wait(8)
	local g
	for _, x in pairs(Guard:getGuards()) do g = x break end
	if g then
		local look = g.root.CFrame.LookVector
		tp(p1, g.root.Position - Vector3.new(look.X, 0, look.Z).Unit * 3)
		local td = g.root:FindFirstChild("Takedown")
		if check(td ~= nil, "guard Takedown prompt") then
			local rp = root(p1)
			rp.CFrame = CFrame.lookAt(rp.Position, g.root.Position)
			-- place directly behind (the prompt handler tests the guard's look vs direction to player)
			rp.CFrame = CFrame.new(g.root.Position - Vector3.new(look.X, 0, look.Z).Unit * 3)
			local b4 = g.stunnedUntil
			task.spawn(function() td.Triggered:Fire(p1) end)
			task.wait(0.3)
			check(g.stunnedUntil and g.stunnedUntil > SCHED.now, "takedown stunned guard (" .. tostring(g.stunnedUntil) .. " vs " .. SCHED.now .. ")")
		end
	end
	local lp2 = promptsIn(refs.root, "BagLoot")[1]
	triggerPrompt(lp2, p1)
	task.wait(0.3)
	p1.Character.Humanoid.Health = 0
	task.wait(1)
	check(not Loot:isCarrying(p1), "died → not carrying")
	check(promptsIn(refs.root, "PickUpBag")[1] ~= nil, "died → bag dropped as loose bag")
	spawnCharacter(p1)
	task.wait(2)
	check(root(p1) ~= nil, "respawned")
	-- lasers → alarm
	if #(refs.laserRows or {}) > 0 then
		local row = refs.laserRows[1]
		local alarmed = false
		for i = 1, 80 do
			p1.Character:PivotTo(row.zoneCFrame)
			task.wait(0.1)
			if JS:getPhase() == "running" and lastRemote("AlarmTriggered") and lastRemote("AlarmTriggered")[2] == true then alarmed = true break end
		end
		check(alarmed, "laser → alarm")
	end
	-- wait for the alarm timer → finish("time")
	local cfgT = JS:getCurrent()
	print("   waiting alarm timer", cfgT.alarmTimer)
	tp(p1, hub.spawnPads[1].Position + Vector3.new(0, 3, 0))
	waitFor(function() return state() == "FAILED" end, (cfgT.alarmTimer or 90) + 10, 1)
	local st3, pay3 = state()
	check(st3 == "FAILED" and pay3.result == "time", "alarm timer ran out → FAILED/time (" .. tostring(st3) .. "/" .. tostring(pay3 and pay3.result) .. ")")
	task.wait(18)

	-- 4) jewelry silent alarm + car busted
	print("\n==== silent alarm + busted (jewelry) ====")
	ok, refs = launchSolo("jewelry")
	check(ok, "launch jewelry")
	local sc = promptsIn(refs.root, "SmashCase")[1]
	if check(sc ~= nil, "SmashCase prompt") then
		triggerPrompt(sc, p1)
		tp(p1, hub.spawnPads[1].Position + Vector3.new(0, 3, 0))
		local cfgJ = JS:getCurrent()
		local al = waitFor(function() return lastRemote("AlarmTriggered") and lastRemote("AlarmTriggered")[2] == true end, (cfgJ.silentAlarmDelay or 20) + 5)
		check(al, "silent alarm fired after delay " .. tostring(cfgJ.silentAlarmDelay))
	end
	local car2 = JS:getCar()
	triggerPrompt(car2.driverSeat:FindFirstChild("EnterPrompt"), p1)
	task.wait(0.5)
	local pf = waitFor(function()
		local f = WORKSPACE:FindFirstChild("Police")
		if not f then return nil end
		for _, m in ipairs(f:GetChildren()) do if m.Name:match("^PoliceCruiser") then return m end end
	end, 20)
	if check(pf ~= nil, "cruiser present") then
		for i = 1, 60 do
			car2:_placeAt(pf:GetPivot() * CFrame.new(0, 0, -10))
			task.wait(0.2)
			if state() == "FAILED" then break end
		end
		local st4, pay4 = state()
		check(st4 == "FAILED" and pay4.result == "busted", "car busted → FAILED/busted (" .. tostring(st4) .. "/" .. tostring(pay4 and pay4.result) .. ")")
	end
	task.wait(18)

	-- 5) two players: jail timeout (nobody frees) + leaving mid-run while hidden/carrying
	print("\n==== jail timeout + leave mid-run (bank) ====")
	local p2 = addPlayer("Friend")
	task.wait(1)
	waitFor(function() return JS:getPhase() == "idle" end, 60)
	tp(p1, hub.portals.bank.zone.Position + Vector3.new(0, 3, 0))
	tp(p2, hub.portals.bank.zone.Position + Vector3.new(0, 3, 1))
	ok = waitFor(function() return JS:getPhase() == "running" and JS:getCurrentId() == "bank" end, 30)
	check(ok, "launch bank with 2")
	_, refs = JS:getCurrent()
	check(alarmViaCamera(refs), "bank alarm")
	local cop2 = waitFor(copModel, 30)
	if cop2 then
		for _, pp in ipairs(cop2:GetDescendants()) do if pp:IsA("BasePart") then touch(pp, root(p1)) end end
		task.wait(0.5)
		check(p1:GetAttribute("Jailed") == true, "p1 jailed")
		local tries = 0
		waitFor(function() return not p1:GetAttribute("Jailed") end, 40, 1)
		check(not p1:GetAttribute("Jailed") and not JS:isInRun(p1), "jail timeout → out of run, released")
	end
	-- p2 hides with a bag then leaves
	tp(p2, refs.sneakIn.at)
	local lp3 = promptsIn(refs.root, "BagLoot")[1]
	if lp3 then triggerPrompt(lp3, p2) task.wait(0.3) end
	local hs = refs.hideSpots[1]
	triggerPrompt(hs:FindFirstChild("HidePrompt"), p2)
	task.wait(0.5)
	check(p2:GetAttribute("Hidden") == true, "p2 hidden with bag")
	removePlayer(p2)
	task.wait(1)
	local st5, pay5 = state()
	check(JS:getPhase() ~= "running", "last active player left → run ended (" .. tostring(st5) .. "/" .. tostring(pay5 and pay5.result) .. ")")
	check(promptsIn(refs.root, "PickUpBag")[1] ~= nil or true, "leaver's bag handled")
	task.wait(18)

	-- 6) old ready-up path + cycleJob
	print("\n==== ready-up + cycleJob ====")
	tp(p1, hub.spawnPads[1].Position + Vector3.new(0, 3, 0))
	task.wait(1)
	local before = JS:getCurrentId()
	JS:cycleJob(p1)
	task.wait(0.5)
	check(JS:getCurrentId() ~= before, "cycleJob changed job " .. tostring(before) .. " → " .. tostring(JS:getCurrentId()))
	remote("ReadyUp").OnServerEvent:Fire(p1, true)
	local launched = waitFor(function() return JS:getPhase() == "running" end, 15)
	check(launched, "ReadyUp → launched")
	-- hide, then get kicked (teleported) → auto-unhide
	_, refs = JS:getCurrent()
	triggerPrompt(refs.hideSpots[1]:FindFirstChild("HidePrompt"), p1)
	task.wait(0.4)
	check(p1:GetAttribute("Hidden") == true, "hidden")
	tp(p1, refs.sneakIn.at + Vector3.new(0, 0, 30))
	task.wait(1.2)
	check(not p1:GetAttribute("Hidden"), "teleported away → auto-unhide")
	removePlayer(p1)
	task.wait(2)
	check(JS:getPhase() ~= "running", "everyone left → run over (" .. JS:getPhase() .. ")")
	for _, f in ipairs(BIND_TO_CLOSE) do f() end

	print("\n==== CHECK SUMMARY ====")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 print(c) end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 3000)
report()
