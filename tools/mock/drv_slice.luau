-- ═══════════════ v3.3 SUNNY'S MART VERTICAL SLICE driver ═══════════════
-- sidewalk arrival → casing walk-in → ① breaker (mask up) → ② drill the safe
-- → ③ bag + load the safe cash (+ Golden Ticket bonus) → GO → vote → payout.
-- Also: layout checks (prompt spacing, walkways, guard lane) + the one-goal HUD feed.
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
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function tp(p, pos) if root(p) then p.Character:PivotTo(CFrame.new(pos)) end end
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local MU = srv("MaskUpService")
	local Sec = srv("SecurityService")
	local Guards = srv("GuardService")
	local GS = srv("GetawayService")
	local Bots = srv("BotService")
	local Constants = mockRequire(REPLICATED.Shared.Constants)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(4)
	p1:SetAttribute("Tutorial", nil)
	local errs0 = #LOG.errors
	local launchLog, muLog = {}, {}
	inClient(function()
		remote("LaunchJob").OnClientEvent:Connect(function(pl) if pl.phase == "title" then table.insert(launchLog, pl) end end)
	end)
	local function info() local l = REMOTE_LOG.JobInfo return l and l[2] end
	local function current(i)
		for _, s in ipairs((i or {}).steps or {}) do if not s.done and not s.optional then return s end end
	end
	local function mainTargets(i)
		local out = {}
		for _, t in ipairs((i or {}).targets or {}) do if t.label ~= "BONUS" then table.insert(out, t) end end
		return out
	end
	local function stepsStr(i)
		local t = {}
		for _, s in ipairs((i or {}).steps or {}) do table.insert(t, (s.done and "✓" or (s.optional and "○" or "·")) .. s.id .. "=" .. s.label) end
		return table.concat(t, " | ")
	end
	local function targetsStr(i)
		local t = {}
		for _, x in ipairs((i or {}).targets or {}) do table.insert(t, x.kind .. ":" .. x.label) end
		return table.concat(t, ", ")
	end

	-- ═══ LAYOUT ═══
	print("\n==== LAYOUT ====")
	JS:selectJob("mart")
	task.wait(0.5)
	local cfg, refs = JS:getCurrent()
	check(refs.arrival and refs.goalChain == true and type(refs.restricted) == "table" and #refs.restricted == 2, "refs: arrival + goalChain + 2 restricted zones")
	check(refs.breaker and refs.vault and refs.vault.door and #refs.cameras == 1 and #refs.guardRoutes == 1, "refs: breaker, safe, 1 camera, 1 guard")
	check(#refs.hideSpots >= 2 and #refs.vents == 1 and #refs.shadowZones >= 4, string.format("refs: %d hide spots, %d vent, %d shadow zones", #refs.hideSpots, #refs.vents, #refs.shadowZones))
	check(refs.getawayCFrame.Position == Vector3.new(78.25, 0, 10), "getaway car still in the yard (78.25, 0, 10)")
	-- E prompts ≥ 6 apart (loot stands + breaker + drill point). Pairs that are never
	-- enabled together are exempt: the 2 SafeCash piles (one safe), drill ↔ SafeCash.
	local E = {}
	for _, s in ipairs(refs.lootSpots) do table.insert(E, { name = s.kind, pos = s.cframe.Position + Vector3.new(0, 2.5, 0) }) end
	table.insert(E, { name = "Breaker", pos = refs.breaker.Position })
	local dp = refs.vault.door.CFrame * CFrame.new(refs.vault.drillOffset or Vector3.zero)
	table.insert(E, { name = "Drill", pos = refs.vault.door.Position + (refs.vault.drillOffset or Vector3.zero) })
	local worst, bad = math.huge, {}
	for i = 1, #E do for k = i + 1, #E do
		local a, b = E[i], E[k]
		local exempt = (a.name == "SafeCash" and b.name == "SafeCash") or ((a.name == "Drill" or b.name == "Drill") and (a.name == "SafeCash" or b.name == "SafeCash"))
		local d = (a.pos - b.pos).Magnitude
		if not exempt then
			worst = math.min(worst, d)
			if d < 6 then table.insert(bad, string.format("%s↔%s %.2f", a.name, b.name, d)) end
		end
	end end
	check(#bad == 0, string.format("E prompts ≥ 6 apart (closest %.2f) %s", worst, table.concat(bad, "; ")))
	local hv = {}
	for _, h in ipairs(refs.hideSpots) do table.insert(hv, { name = "Hide:" .. h:GetAttribute("Label"), pos = h.Position }) end
	for _, v in ipairs(refs.vents) do table.insert(hv, { name = "Vent", pos = v.b.Position }) end
	local hbad, hworst = {}, math.huge
	for _, h in ipairs(hv) do for _, e in ipairs(E) do
		local d = (flat(h.pos) - flat(e.pos)).Magnitude
		hworst = math.min(hworst, d)
		if d < 4 then table.insert(hbad, string.format("%s↔%s %.2f", h.name, e.name, d)) end
	end end
	check(#hbad == 0, string.format("H/V ≥ 4 from every E prompt (closest %.2f) %s", hworst, table.concat(hbad, "; ")))

	-- walkways: a 4-wide, 4-tall box swept along each route hits nothing solid
	local rp = OverlapParams and OverlapParams.new() or nil
	local function solidAt(p, w)
		local hits = {}
		for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(p), Vector3.new(w, 4, w))) do
			if x.CanCollide and not (x:FindFirstAncestorOfClass("Model") and x:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid")) then
				table.insert(hits, x.Name)
			end
		end
		return hits
	end
	local function route(name, pts, w)
		local blocked = {}
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local n = math.max(1, math.ceil((b - a).Magnitude / 0.5))
			for s = 0, n do
				local p = a:Lerp(b, s / n)
				local h = solidAt(p, w)
				if #h > 0 then table.insert(blocked, string.format("(%.1f,%.1f) %s", p.X, p.Z, table.concat(h, "/"))) break end
			end
		end
		check(#blocked == 0, string.format("walkway %s clear at %d wide %s", name, w, table.concat(blocked, "; ")))
	end
	local Y = 3.5
	route("sidewalk → door → east aisle → curtain → breaker", {
		Vector3.new(64.2, Y, -3.4), Vector3.new(63, Y, 4.5), Vector3.new(67.2, Y, 6), Vector3.new(67, Y, 18), Vector3.new(67, Y, 24), Vector3.new(66.5, Y, 28.5) }, 4)
	route("stock corridor → office door → safe", {
		Vector3.new(66, Y, 24.5), Vector3.new(60, Y, 26), Vector3.new(55, Y, 26) }, 4)
	route("stock corridor → loading door → car trunk", {
		Vector3.new(66, Y, 24.5), Vector3.new(76.3, Y, 24.5), Vector3.new(78.1, Y, 21), Vector3.new(78.2, Y, 19.5) }, 4)
	route("counter aisle (the guard lane)", { Vector3.new(59.2, Y, 4.6), Vector3.new(59.2, Y, 14.3) }, 4)
	route("door → counter aisle → registers", { Vector3.new(62, Y, 3), Vector3.new(58.5, Y, 6), Vector3.new(58.5, Y, 12) }, 4)
	-- 6-wide main aisles
	route("front aisle 6 deep (door ↔ island end cap)", { Vector3.new(59, Y, 5), Vector3.new(67.7, Y, 5) }, 5.9)
	route("back aisle 6 deep (island ↔ back wall shelf)", { Vector3.new(62.7, Y, 16), Vector3.new(67.7, Y, 16) }, 5.9)
	route("east aisle 6 wide", { Vector3.new(67.1, Y, 6), Vector3.new(67.1, Y, 16) }, 6)
	route("counter aisle 6 wide (5.6 box: counter lip at 55.6, island at 61.5)", { Vector3.new(58.55, Y, 6), Vector3.new(58.55, Y, 13) }, 5.6)

	-- every sidewalk drop point is clear of street furniture (3 wide)
	local dbad = {}
	local a = refs.arrival
	local back = flat(a.at - a.face).Unit
	for i = 1, 8 do
		local row, col = (i - 1) % 4, math.floor((i - 1) / 4)
		local p = a.at + a.spread * ((row - 1.5) * 2) + back * (col * (a.rowGap or 2))
		local h = solidAt(p, 2.6)
		if #h > 0 then table.insert(dbad, string.format("(%.1f,%.1f) %s", p.X, p.Z, table.concat(h, "/"))) end
	end
	check(#dbad == 0, "all 8 sidewalk drop points clear " .. table.concat(dbad, "; "))
	-- the guard: never looks into the curtain doorway from his lane's ends
	local gr = refs.guardRoutes[1]
	local fovHalf = Constants.GUARD_VISION_FOV_DEGREES / 2
	local cur = Vector3.new(67, Y, 19.5)
	for _, e in ipairs({ { gr.b, gr.b - gr.a }, { gr.a, gr.a - gr.b } }) do
		local look = flat(e[2]).Unit
		local to = flat(cur - e[1]).Unit
		local ang = math.deg(math.acos(math.clamp(look:Dot(to), -1, 1)))
		check(ang > fovHalf, string.format("guard at (%.1f, %.1f) looking %s: curtain is %.0f° off his nose (FOV ±%.0f°)", e[1].X, e[1].Z, look.Z > 0 and "south" or "north", ang, fovHalf))
	end

	-- ═══ LAUNCH → SIDEWALK ═══
	print("\n==== LAUNCH: SIDEWALK ARRIVAL ====")
	JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
	check(waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil, "mart launched")
	inClient(function() local r = remote("MaskUp") if r then r.OnClientEvent:Connect(function(pl) table.insert(muLog, pl) end) end end)
	local hrp = root(p1)
	local pos = hrp.Position
	check(pos.Z > -5.6 and pos.Z < -1.5 and pos.X > 60 and pos.X < 70, string.format("p1 lands on the sidewalk outside the door (%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))
	check(hrp.CFrame.LookVector.Z > 0.8, "p1 faces the store (look " .. tostring(hrp.CFrame.LookVector) .. ")")
	check(p1:GetAttribute("Casing") == true and MU:isCasing(), "casing: unmasked customer")
	local tl = launchLog[#launchLog]
	check(tl and tostring(tl.subtitle):find("customer") ~= nil, "title card: " .. tostring(tl and tl.subtitle))
	local fromCar = (Vector3.new(78.25, Y, 10) - pos)
	check(fromCar.Magnitude < 25, string.format("getaway car %.1f studs away through the open yard gate", fromCar.Magnitude))
	local botPos = {}
	for _, b in ipairs(Bots:getBots()) do
		local bp = b.model:GetPivot().Position
		table.insert(botPos, bp)
		print(string.format("   bot %s at (%.1f, %.1f, %.1f)", b.model.Name, bp.X, bp.Y, bp.Z))
	end
	-- (v3.3) bots drop in at refs.arrival, right beside their owner (not in the stock room)
	local botsOk = #botPos == 2
	for _, bp in ipairs(botPos) do
		if flat(bp - pos).Magnitude > 4.5 or bp.Z > 0 then botsOk = false end
	end
	if #botPos == 2 and flat(botPos[1] - botPos[2]).Magnitude < 1.5 then botsOk = false end
	check(botsOk, "2 bots on the sidewalk beside p1, not on top of each other")

	-- (v3.3) the guard walks the MartBuilder waypoint loop in order, facing where he walks
	do
		local g
		for _, x in pairs(Guards:getGuards()) do g = x end
		local wps = gr.waypoints
		local seq, facingOk, facingN, lastAt = {}, 0, 0, nil
		local t0 = SCHED.now
		while SCHED.now - t0 < 30 and #seq < 6 do
			local rp = g.root.Position
			local near = nil
			for k, w in ipairs(wps) do if flat(rp - w).Magnitude < 2.2 then near = k end end
			if near and near ~= lastAt then table.insert(seq, near) lastAt = near end
			if not near and g.lastPos then
				local mv = flat(rp - g.lastPos)
				if mv.Magnitude > 0.3 then
					facingN += 1
					if flat(g.root.CFrame.LookVector).Unit:Dot(mv.Unit) > 0.9 then facingOk += 1 end
				end
			end
			g.lastPos = rp
			task.wait(0.2)
		end
		g.lastPos = nil
		local inOrder = #seq >= 5
		for k = 2, #seq do if seq[k] ~= seq[k - 1] % #wps + 1 then inOrder = false end end
		check(inOrder, "guard walks the waypoint loop in order (" .. table.concat(seq, "→") .. ")")
		check(facingN >= 3 and facingOk / facingN > 0.8, string.format("guard faces the way he walks (%d/%d samples)", facingOk, facingN))
		-- at each stop (facing the way he came, ± his small look-around) the curtain stays out of his FOV
		local worst = 999
		for k, w in ipairs(wps) do
			local prev = wps[(k - 2) % #wps + 1]
			local look = flat(w - prev).Unit
			local ang = math.deg(math.acos(math.clamp(look:Dot(flat(cur - w).Unit), -1, 1))) - 12
			worst = math.min(worst, ang)
		end
		check(worst > fovHalf, string.format("at every loop stop the curtain is ≥ %.0f° off his nose (FOV ±%.0f°)", worst, fovHalf))
	end
	task.wait(0.5)
	local i0 = info()
	print("   steps: " .. stepsStr(i0))
	print("   targets: " .. targetsStr(i0))
	local cs = current(i0)
	check(cs and cs.id == "cameras" and cs.label:find("camera"), "goal ①: " .. tostring(cs and cs.label))
	local mt = mainTargets(i0)
	check(#mt == 1 and mt[1].kind == "optional" and mt[1].label == "BREAKER" and (mt[1].pos - refs.breaker.Position).Magnitude < 0.1, "waypoint = the breaker only (" .. targetsStr(i0) .. ")")
	local nonOpt = 0
	for _, s in ipairs(i0.steps) do if not s.optional then nonOpt += 1 end end
	check(nonOpt == 4, "4 goals on the bar: camera · safe · cash→car · GO (" .. nonOpt .. ")")

	-- ═══ WALK IN AS A CUSTOMER ═══
	print("\n==== CASING WALK-IN ====")
	tp(p1, Vector3.new(62, Y, 8))
	task.wait(0.6)
	check(p1:GetAttribute("InRestricted") ~= true and p1:GetAttribute("Casing") == true, "shop floor: public (not restricted), still casing")
	local hid = Guards.stealthFactor(p1)
	check(hid == true, "the guard treats a customer as invisible")
	tp(p1, Vector3.new(67, Y, 24))
	task.wait(0.6)
	check(p1:GetAttribute("InRestricted") == true and p1:GetAttribute("Casing") == true, "stock room: RESTRICTED, still casing (not a crime room)")

	-- ═══ ① BREAKER ═══
	print("\n==== ① TURN OFF THE CAMERA ====")
	local br
	for _, pr in ipairs(findPrompts(refs.breaker)) do if pr.Name == "Breaker" then br = pr end end
	if check(br ~= nil, "breaker prompt") then
		triggerPrompt(br, p1)
		task.wait(2)
	end
	check(Sec:camerasCut(), "camera cut")
	local mu = muLog[#muLog]
	check(mu and mu.phase == "maskup" and mu.reason == "crime", "cutting the breaker = MASK UP (" .. tostring(mu and mu.text) .. ")")
	check(waitFor(function() return p1:GetAttribute("Casing") == nil and p1:GetAttribute("MaskPower") ~= nil end, 3) ~= nil, "masks on")
	task.wait(0.3)
	local i1 = info()
	print("   steps: " .. stepsStr(i1))
	cs = current(i1)
	check(cs and cs.id == "vault" and cs.label:find("safe"), "goal ②: " .. tostring(cs and cs.label))
	mt = mainTargets(i1)
	check(#mt == 1 and mt[1].kind == "vault" and mt[1].label == "DRILL", "waypoint = the safe only (" .. targetsStr(i1) .. ")")

	-- ═══ ② SAFE ═══
	print("\n==== ② CRACK THE SAFE ====")
	tp(p1, Vector3.new(55, Y, 25))
	task.wait(0.4)
	local drill
	for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "Drill" then drill = pr end end
	if check(drill ~= nil and drill.Enabled, "Place drill prompt") then
		triggerPrompt(drill, p1)
	end
	local sawDrilling, sawJam, fixes = false, false, 0
	local opened = waitFor(function()
		local c = current(info())
		if c and c.id == "vault" then
			if c.label:find("Drilling") then sawDrilling = true end
			if c.label:find("stuck") then sawJam = true end
		end
		if drill.Enabled then triggerPrompt(drill, p1) fixes += 1 end
		return Loot:counts().vault > 0 and (function() for _, r in ipairs(Loot:remaining()) do if r.kind == "SafeCash" and not r.locked then return true end end end)()
	end, 60, 0.5)
	check(opened, string.format("safe open (drill fixed %d×)", fixes))
	check(sawDrilling, "objective bar showed the drill %")
	task.wait(0.3)
	local i2 = info()
	print("   steps: " .. stepsStr(i2))
	print("   targets: " .. targetsStr(i2))
	cs = current(i2)
	check(cs and cs.id == "loot" and cs.label:find("0/2"), "goal ③: " .. tostring(cs and cs.label))
	local cashT, carT, bonusT = 0, 0, 0
	for _, t in ipairs(i2.targets) do
		if t.kind == "loot" and t.label == "CASH" then cashT += 1 elseif t.kind == "car" then carT += 1 elseif t.label == "BONUS" then bonusT += 1 end
	end
	check(cashT == 2 and carT == 1 and #i2.targets <= 4, string.format("waypoints = 2 safe cash + car (+%d bonus)", bonusT))

	-- ═══ ③ BAG + LOAD ═══
	print("\n==== ③ BAG THE CASH + LOAD THE CAR ====")
	local car = JS:getCar()
	local function loadBag()
		local lp = car.trunk and car.trunk:FindFirstChild("LoadBag", true)
		local n = Loot:counts().loaded
		tp(p1, car.trunk.Position + Vector3.new(0, 1, 3))
		if lp then triggerPrompt(lp, p1) end
		task.wait(0.4)
		return Loot:counts().loaded == n + 1
	end
	for k = 1, 2 do
		local pile
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.Name == "BagLoot" and pr.Enabled and tostring(pr.ObjectText):find("Safe Cash") then pile = pr break end
		end
		if check(pile ~= nil, "safe cash pile #" .. k .. " (" .. tostring(pile and pile.ActionText) .. ")") then
			triggerPrompt(pile, p1)
			task.wait(0.4)
			if not Loot:isCarrying(p1) then
				local l = REMOTE_LOG.LootMinigame
				if l and l[1] == p1 and l[2].op == "start" then
					task.wait((l[2].min or 1) + 0.3)
					remote("LootMinigame").OnServerEvent:Fire(p1, { op = "done", token = l[2].token, mode = "game", ok = true })
					task.wait(0.4)
				end
			end
			check(Loot:isCarrying(p1), "  …bagged")
			check(loadBag(), "  …loaded in the car")
			task.wait(0.3)
			local c = current(info())
			print("   now: " .. tostring(c and c.label))
		end
	end
	local i3 = info()
	print("   steps: " .. stepsStr(i3))
	cs = current(i3)
	check(cs and cs.id == "car" and cs.label:find("GO"), "last goal: " .. tostring(cs and cs.label))
	mt = mainTargets(i3)
	check(#mt == 1 and mt[1].kind == "car" and mt[1].label == "GO!", "waypoint = the car (" .. targetsStr(i3) .. ")")
	-- bonus: the Golden Ticket
	local tk
	for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "BagLoot" and pr.Enabled and tostring(pr.ObjectText):find("^TARGET") then tk = pr end end
	if check(tk ~= nil, "bonus: Golden Ticket pile") then
		triggerPrompt(tk, p1)
		task.wait(0.4)
		if Loot:isCarrying(p1) then check(loadBag(), "bonus loaded") end
		task.wait(0.3)
		local bs
		for _, s in ipairs(info().steps) do if s.id == "target" then bs = s end end
		check(bs and bs.optional and bs.done, "bonus step ticked: " .. tostring(bs and bs.label))
	end

	-- ═══ GO ═══
	print("\n==== GO! ====")
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
	task.wait(0.5)
	remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
	check(waitFor(function() return GS:getPhase() == "vote" end, 6) ~= nil, "GO → escape vote")
	remote("Getaway").OnServerEvent:Fire(p1, { action = "vote", route = "boat" })
	local done = waitFor(function() local h = REMOTE_LOG.HeistState return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 60, 0.2)
	check(done and done[2] == "COMPLETE", "heist COMPLETE")
	local pay = done and done[3] or {}
	print(string.format("   take %s  each %s  target %s  stars %s/%s/%s time %s", tostring(pay.take), tostring(pay.each),
		tostring(pay.target and pay.target.amount), tostring(pay.stars and pay.stars.stealth), tostring(pay.stars and pay.stars.loot),
		tostring(pay.stars and pay.stars.fast), tostring(pay.stars and pay.stars.time)))
	check((pay.take or 0) >= 2400 and (pay.each or 0) > pay.take and pay.target and pay.target.amount == 5000, "payout: safe cash + ticket + bonuses")
	check(pay.stars and pay.stars.stealth == true, "stealth star (no alarm)")
	task.wait(Constants.JOB_RESET_COOLDOWN + 12)
	check(JS:getPhase() == "idle" and p1:GetAttribute("Casing") == nil, "reset → idle")

	-- ═══ KICK-BACK goes to the stock room, not the sidewalk ═══
	print("\n==== KICK-BACK + 2ND RUN ====")
	JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
	check(waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil, "relaunched")
	MU:maskUp("button", p1)
	task.wait(1.2)
	tp(p1, Vector3.new(58.5, Y, 8))
	local g1
	for _, g in pairs(Guards:getGuards()) do g1 = g end
	Guards.graceUntil = 0
	getSig(g1.root, "Touched"):Fire(root(p1))
	task.wait(0.6)
	local kp = root(p1).Position
	check((kp - refs.sneakIn.at).Magnitude < 4 and kp.Z > 20, string.format("guard grab → back to the stock room (%.1f, %.1f)", kp.X, kp.Z))

	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	print("\n================ SLICE CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 1500)
report()
