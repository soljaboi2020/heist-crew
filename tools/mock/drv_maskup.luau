-- ═══════════════ v3.2 MASK UP / casing driver ═══════════════
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
		task.wait(step or 0.1)
	end
	return nil
end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function tp(p, pos) if root(p) then p.Character:PivotTo(CFrame.new(pos)) end end
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local MU = srv("MaskUpService")
	local Guards = srv("GuardService")
	local Sec = srv("SecurityService")
	local Loot = srv("LootService")
	local Shop = srv("ShopService")
	local p1 = addPlayer("Malachi")
	startClient(p1)
	local p2 = addPlayer("Buddy")
	task.wait(4)
	for _, p in ipairs({ p1, p2 }) do p:SetAttribute("Tutorial", nil) end
	local UI = cmod("MaskUpUI")
	inClient(function() UI:start() end)
	local errs0 = #LOG.errors

	local launchLog = {}
	inClient(function()
		remote("LaunchJob").OnClientEvent:Connect(function(pl) if pl.phase == "title" then table.insert(launchLog, pl) end end)
	end)
	local muLog = {}
	local function hookMU()
		inClient(function()
			local r = remote("MaskUp")
			if r and not muLog._hooked then muLog._hooked = true r.OnClientEvent:Connect(function(pl) table.insert(muLog, pl) end) end
		end)
	end

	local function launch(jobId, list)
		waitFor(function() return JS:getPhase() == "idle" end, 90)
		JS:selectJob(jobId)
		task.wait(0.5)
		JS:startLaunchCountdown(0, function() return list or { p1, p2 } end, "portal")
		return waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil
	end
	local function masked(p) return p:GetAttribute("MaskPower") ~= nil end
	local function endRun()
		-- quickest clean end: everyone leaves the run → abandoned is not possible with players present,
		-- so use the jail timeout path: catch both with cops and wait out the 30 s
		JS:triggerAlarm("camera", p1)
		task.wait(0.3)
		JS:catchPlayer(p1, "cop") JS:catchPlayer(p2, "cop")
		waitFor(function() return JS:getPhase() ~= "running" end, 60)
		waitFor(function() return JS:getPhase() == "idle" end, 60)
	end

	-- ── 1. villa: drop-in = casing ──
	print("\n==== VILLA: CASING AT DROP-IN ====")
	check(launch("villa"), "villa launched")
	hookMU()
	local cfg, refs = JS:getCurrent()
	check(p1:GetAttribute("Casing") == true and p2:GetAttribute("Casing") == true, "both players Casing = true")
	check(not masked(p1) and not masked(p2), "no mask power during casing (MaskPower nil)")
	check(MU:isCasing(), "MU:isCasing()")
	local names = {}
	for _, z in ipairs(MU:zones()) do table.insert(names, z.name .. (z.crime and "*" or "")) end
	print("   zones: " .. table.concat(names, ", "))
	check(#MU:zones() > 0, "villa has restricted zones (" .. #MU:zones() .. ")")
	task.wait(0.5)
	local tl = launchLog[#launchLog]
	check(tl and tl.subtitle == "Look around. Mask up when you're ready.", "title card subtitle = casing line: " .. tostring(tl and tl.subtitle))
	local tSubText = inClient(function()
		local g = p1.PlayerGui:FindFirstChild("BriefingUI", true)
		for _, d in ipairs(p1.PlayerGui:GetDescendants()) do
			if d:IsA("TextLabel") and (d.Text == "Look around. Mask up when you're ready." ) then return d.Text end
		end
		return nil
	end)
	print("   (BriefingUI label found: " .. tostring(tSubText) .. ")")
	task.wait(3)
	local uiVis = inClient(function()
		local g = p1.PlayerGui:FindFirstChild("HC_MaskUp")
		local h = g and g:FindFirstChild("MaskUpHolder")
		local chip = p1.PlayerGui:FindFirstChild("CasingChip", true)
		return (h and h.Visible) and chip and chip.Visible
	end)
	check(uiVis == true, "client: MASK UP button + CASING chip visible")

	-- sneakIn room is public: stealthFactor says hidden
	local hid = Guards.stealthFactor(p1)
	check(hid == true and p1:GetAttribute("InRestricted") ~= true, "at sneakIn: civilian (guards can't 'see' a customer)")

	-- guard in a public room looking at p1: no suspicion
	Guards.graceUntil = 0
	local g
	for _, gg in pairs(Guards:getGuards()) do
		local pos = gg.root.Position
		local inZone = false
		for _, z in ipairs(MU:zones()) do if z.x0 and pos.X >= z.x0 and pos.X <= z.x1 and pos.Z >= z.z0 and pos.Z <= z.z1 then inZone = true end end
		if not inZone then g = gg break end
	end
	print("   test guard: " .. tostring(g and g.name))
	local function standBefore(guard, d)
		local look = guard.root.CFrame.LookVector
		local pos = guard.head.Position + Vector3.new(look.X, 0, look.Z).Unit * (d or 6)
		tp(p1, Vector3.new(pos.X, guard.root.Position.Y, pos.Z))
	end
	local maxSus = 0
	for i = 1, 30 do
		standBefore(g, 6)
		task.wait(0.1)
		maxSus = math.max(maxSus, p1:GetAttribute("GuardSuspicion") or 0)
	end
	check(p1:GetAttribute("InRestricted") ~= true, "guard spot is public (InRestricted not set)")
	check(maxSus == 0 and MU:isCasing(), "public: 3 s in front of a guard → suspicion stays 0 (" .. maxSus .. "), still casing")
	-- bumping into him does nothing either
	local before = root(p1).Position
	for _, part in ipairs(g.model:GetDescendants()) do if part:IsA("BasePart") then touch(part, root(p1)) break end end
	task.wait(0.3)
	check((root(p1).Position - before).Magnitude < 3, "public: bumping a guard does nothing (no kick-back)")

	-- same spot, but made restricted → meter fills, kick-back to the door, still casing, no mask
	local gp = g.root.Position
	table.insert(MU:zones(), { x0 = gp.X - 30, z0 = gp.Z - 30, x1 = gp.X + 30, z1 = gp.Z + 30, y0 = -50, y1 = 100, crime = false, name = "TESTROOM" })
	maxSus = 0
	local kicked = false
	for i = 1, 60 do
		if kicked then break end
		standBefore(g, 6)
		task.wait(0.1)
		local s = p1:GetAttribute("GuardSuspicion") or 0
		maxSus = math.max(maxSus, s)
		local hrp = root(p1)
		if hrp and refs.sneakIn and (hrp.Position - refs.sneakIn.at).Magnitude < 8 then kicked = true end
	end
	check(p1:GetAttribute("InRestricted") == true or kicked, "restricted room → InRestricted = true")
	local hidR, multR = Guards.stealthFactor(p1)
	print(string.format("   restricted guard meter %.2f kicked=%s (mock raycast may not see characters)", maxSus, tostring(kicked)))
	check((maxSus > 0.3 and kicked) or (hidR == false and multR == 1 and p1:GetAttribute("InRestricted") == true),
		"restricted: guards treat p1 normally (stealthFactor false,1)")
	-- the kick-back itself while casing (what a full meter calls)
	Guards.graceUntil = 0
	standBefore(g, 3)
	task.wait(0.3)
	g.cooldown = 0 g.stunnedUntil = 0
	for _, part in ipairs(g.model:GetDescendants()) do if part:IsA("BasePart") then touch(part, root(p1)) break end end
	task.wait(0.3)
	check(refs.sneakIn and (root(p1).Position - refs.sneakIn.at).Magnitude < 8, "restricted: bumping a guard while casing → kickBack to sneakIn, no alarm")
	check(MU:isCasing() and not masked(p1), "kick-back while casing: still casing, no mask")
	table.remove(MU:zones())
	task.wait(3.5)   -- guard stun wears off

	-- camera: public → no fill; restricted → fills
	local cam = refs.cameras and refs.cameras[1]
	if cam and cam.head then
		local function inFront()
			local pos = cam.head.Position + cam.head.CFrame.LookVector * 10
			tp(p1, pos)
		end
		local mc = 0
		for i = 1, 15 do inFront() task.wait(0.1) mc = math.max(mc, p1:GetAttribute("CameraSuspicion") or 0) end
		check(mc == 0, "public: camera ignores a customer (" .. mc .. ")")
		local cp = cam.head.Position
		table.insert(MU:zones(), { x0 = cp.X - 40, z0 = cp.Z - 40, x1 = cp.X + 40, z1 = cp.Z + 40, y0 = -50, y1 = 100, crime = false, name = "TESTCAM" })
		mc = 0
		for i = 1, 8 do inFront() task.wait(0.1) mc = math.max(mc, p1:GetAttribute("CameraSuspicion") or 0) end
		check(mc > 0, string.format("restricted: camera meter fills (%.2f)", mc))
		table.remove(MU:zones())
		tp(p1, refs.sneakIn.at)
		task.wait(2)
	end
	check(MU:isCasing(), "still casing before any crime")

	-- ── 2. crime: bag some loot → masks on for the WHOLE crew ──
	print("\n==== CRIME AUTO-MASKS ====")
	local pile
	for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do
		if pr.Name == "BagLoot" and pr.Enabled then pile = pr break end
	end
	if check(pile ~= nil, "found a BagLoot prompt") then
		local n0 = #muLog
		getSig(pile, "PromptButtonHoldBegan"):Fire(p1)
		ProximityPromptService.PromptButtonHoldBegan:Fire(pile, p1)
		task.wait(0.2)
		local ev = muLog[#muLog]
		check(#muLog > n0 and ev.phase == "maskup" and ev.reason == "crime", "starting a crime prompt → maskup event (" .. tostring(ev and ev.text) .. ")")
		check(not masked(p1), "…mask not on yet before the snap")
		task.wait(1)
		check(masked(p1) and masked(p2), "after the snap: BOTH players masked (" .. tostring(p1:GetAttribute("MaskPower")) .. "/" .. tostring(p2:GetAttribute("MaskPower")) .. ")")
		check(p1:GetAttribute("Casing") == nil and p2:GetAttribute("Casing") == nil, "Casing cleared")
		check(Guards.stealthFactor(p1) == false, "guards see p1 normally again")
		task.wait(1)
		local camType = inClient(function() return WORKSPACE.CurrentCamera.CameraType end)
		check(camType == Enum.CameraType.Custom, "client: camera back to Custom after the shot")
		local titleOn = inClient(function() local t = p1.PlayerGui.HC_MaskUp:FindFirstChild("Title") return t and t.GroupTransparency < 0.5 and t.Big.Text end)
		check(titleOn == "MASKS ON", "client: MASKS ON title showing")
		local btnHidden = inClient(function() return not p1.PlayerGui.HC_MaskUp.MaskUpHolder.Visible end)
		check(btnHidden, "client: MASK UP button gone")
		-- kick-back still works masked (guard), no second maskup
		local n1 = #muLog
		JS:triggerAlarm("camera", p1)
		task.wait(0.3)
		check(#muLog == n1, "alarm after mask up: no second maskup")
	end
	endRun()
	check(p1:GetAttribute("Casing") == nil and not MU:isCasing(), "run over → casing state clear")

	-- ── 3. button: mart ──
	print("\n==== MART: MASK UP BUTTON (key M) ====")
	check(launch("mart"), "mart launched")
	check(p1:GetAttribute("Casing") == true, "casing again")
	task.wait(3)
	local n0 = #muLog
	inClient(function() end)
	pressKey(Enum.KeyCode.M)
	task.wait(0.3)
	local ev = muLog[#muLog]
	check(#muLog > n0 and ev.reason == "button" and ev.by == p1.DisplayName, "M key → maskup (button) by " .. tostring(ev and ev.by))
	task.wait(1)
	check(masked(p1) and masked(p2), "button masks everyone (p2 too)")
	check(p1:GetAttribute("MaskPower") ~= nil, "power active only after mask up")
	endRun()

	-- ── 4. walking into the vault: bank ──
	print("\n==== BANK: WALK INTO THE VAULT ====")
	check(launch("bank"), "bank launched")
	names = {}
	for _, z in ipairs(MU:zones()) do table.insert(names, z.name .. (z.crime and "*" or "")) end
	print("   zones: " .. table.concat(names, ", "))
	cfg, refs = JS:getCurrent()
	local v = refs.plan.vault
	Guards.graceUntil = os.clock() + 100
	tp(p1, Vector3.new(v[1], refs.sneakIn.at.Y, v[2]))
	task.wait(0.5)
	ev = muLog[#muLog]
	check(ev and ev.reason == "zone", "into the vault → maskup (zone): " .. tostring(ev and ev.text))
	task.wait(1)
	check(masked(p1) and masked(p2), "zone mask-up masks everyone")
	endRun()

	-- ── 5. timer ──
	print("\n==== JEWELRY: 60 s TIMER ====")
	MU.CASING_TIME = 4
	check(launch("jewelry"), "jewelry launched")
	check(p1:GetAttribute("Casing") == true, "casing")
	task.wait(5)
	ev = muLog[#muLog]
	check(ev and ev.reason == "time", "time ran out → maskup (time)")
	task.wait(1)
	check(masked(p1) and masked(p2), "timer masks everyone")
	MU.CASING_TIME = 60
	endRun()

	-- ── 6. keycard pickup = crime (jewelry prompt path via real prompt) ──
	print("\n==== JEWELRY: KEYCARD = CRIME ====")
	check(launch("jewelry"), "jewelry launched again")
	local kc
	for _, pr in ipairs(findPrompts(WORKSPACE)) do if pr.Name == "TakeKeycard" and pr.Enabled then kc = pr end end
	if check(kc ~= nil, "keycard prompt") then
		triggerPrompt(kc, p2)
		task.wait(1.2)
		check(masked(p1) and masked(p2) and p2:GetAttribute("HasKeycard") == true, "p2 took the keycard → everyone masked")
	end
	-- mid-run jail + breakout still work
	JS:triggerAlarm("camera", p1)
	task.wait(0.3)
	JS:catchPlayer(p2, "cop")
	task.wait(0.5)
	check(p2:GetAttribute("Jailed") == true, "cop catch → jail")
	local bo
	for _, pr in ipairs(findPrompts(WORKSPACE)) do if pr.Name == "BreakOut" and pr.Enabled then bo = pr end end
	if bo then triggerPrompt(bo, p1) task.wait(0.6) end
	check(not p2:GetAttribute("Jailed"), "breakout works")
	endRun()

	-- ── 7. tutorial: no casing ──
	-- (v3.3 slice) Sunny's Mart has refs.arrival: the crew starts on the sidewalk, so even a
	-- tutorial run cases (unmasked customer) — the old "tutorial skips casing" was intended to change
	print("\n==== TUTORIAL RUN: ARRIVAL JOB STILL CASES ====")
	p1:SetAttribute("Tutorial", "portal")
	check(launch("mart", { p1 }), "tutorial mart launched")
	check(p1:GetAttribute("Casing") == true and MU:isCasing(), "tutorial run on an arrival job: casing (unmasked customer)")
	task.wait(0.5)
	check(not masked(p1), "tutorial run: no mask at the sidewalk drop-in")
	tl = launchLog[#launchLog]
	local _, mrefs = srv("JobService"):getCurrent()
	check(tl and mrefs and mrefs.arrival and tl.subtitle == mrefs.arrival.line, "tutorial title card: the arrival line (" .. tostring(tl and tl.subtitle) .. ")")
	p1:SetAttribute("Tutorial", nil)

	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	print("\n================ MASK UP CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 3000)
report()
