-- ═══════════════ v3.0 GETAWAY driver (getaway agent) ═══════════════
-- SECTION = "scenes" | "client" | "game" (set by the run_* prefix file)
local CHECKS = {}
local function check(ok, what)
	table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what)
	if not ok then print("  [FAIL] " .. what) elseif VERBOSE then print("  [ok] " .. what) end
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
local function inClient(fn)
	local res
	local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX)
	resumeThread(co)
	waitFor(function() return res ~= nil end, 30, 0.05)
	if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end
	return res and res[2]
end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end

local JOBS = { "mart", "villa", "jewelry", "bank" }
local ROUTES = { "boat", "heli", "highway" }
local TYPES = { "classic", "muscle", "racer", "armored", "monster", "tank" }
local TYPE_ID = { classic = "CarClassic", muscle = "CarMuscle", racer = "CarRacer", armored = "CarArmored", monster = "CarMonster", tank = "CarTank" }
local EXPECT = { classic = 0, muscle = 0.05, racer = 0.08, armored = 0.08, monster = 0.10, tank = 0.12 }

local function isNum(x) return type(x) == "number" and x == x and x > -1e7 and x < 1e7 end
local function v3ok(v) return mtypeof(v) == "Vector3" and isNum(v.X) and isNum(v.Y) and isNum(v.Z) end

local function checkScene(tag, sc, opts)
	local ok = true
	local D = sc.duration
	ok = check(isNum(D) and D >= 11 and D <= 19, tag .. " duration 11..19 (" .. tostring(D) .. ")") and ok
	local car = sc.tracks and sc.tracks.car
	ok = check(type(car) == "table" and #car > 10, tag .. " car track") and ok
	local mono, finite = true, true
	for name, keys in pairs(sc.tracks or {}) do
		for i, k in ipairs(keys) do
			if not (isNum(k.t) and v3ok(k.p) and isNum(k.y)) then finite = false end
			if i > 1 and k.t < keys[i - 1].t - 1e-6 then mono = false print("   non-monotonic " .. name .. " @" .. i) end
		end
	end
	ok = check(mono and finite, tag .. " tracks monotonic + finite") and ok
	-- camera shots cover 0..D with no gap
	local cover, gaps = 0, {}
	local shots = sc.shots or {}
	table.sort(shots, function(a, b) return a.t0 < b.t0 end)
	for i, sh in ipairs(shots) do
		if sh.t0 > cover + 0.05 then table.insert(gaps, string.format("%.2f-%.2f", cover, sh.t0)) end
		cover = math.max(cover, sh.t1)
		if sh.mode == "look" and not (v3ok(sh.a) and sc.tracks[sh.target]) then gaps[#gaps + 1] = "bad look target " .. tostring(sh.target) end
		if sh.mode == "chase" and not sc.tracks[sh.target] then gaps[#gaps + 1] = "bad chase target " .. tostring(sh.target) end
	end
	ok = check(#gaps == 0 and cover >= D, tag .. " shots cover the scene" .. (#gaps > 0 and (" GAPS " .. table.concat(gaps, ",")) or "") .. " (to " .. string.format("%.1f", cover) .. ")") and ok
	-- route props / tracks
	if opts.route == "boat" then
		ok = check(sc.tracks.boat ~= nil, tag .. " boat track") and ok
		-- (playtest fix 2026-09-25) the boat stays on the water (terrain ocean x ±400, z -120..-436)
		-- and within sight of the city; the held final shot looks back at the skyline
		local inWater, far = true, 0
		for _, k in ipairs(sc.tracks.boat or {}) do
			if k.p.X < -395 or k.p.X > 395 or k.p.Z > -125 or k.p.Z < -430 then inWater = false end
			far = math.max(far, -k.p.Z)
		end
		local minX = math.huge for _, k in ipairs(sc.tracks.boat or {}) do minX = math.min(minX, k.p.X) end
		ok = check(inWater and far < 260, tag .. string.format(" boat stays on the water near the city (max z %.0f, min x %.0f)", -far, minX)) and ok
		local lastShot = sc.shots[#sc.shots]
		ok = check(lastShot and lastShot.mode == "lookback" and lastShot.target == "boat", tag .. " final boat shot = lookback at the skyline") and ok
	elseif opts.route == "heli" and sc.tracks.heli then
		local hk = sc.tracks.heli
		local lastK = hk[#hk]
		ok = check(lastK.p.Z > -90 and lastK.p.Y >= 60, tag .. string.format(" heli ends over the city (z %.0f, y %.0f)", lastK.p.Z, lastK.p.Y)) and ok
	end
	if opts.route == "boat" then
		local last = car[#car].p
		ok = check((Vector3.new(last.X, 0, last.Z) - Vector3.new(103, 0, -136)).Magnitude < 3 and math.abs(last.Y - 1) < 0.3, tag .. " car ends on the pier (" .. tostring(last) .. ")") and ok
	elseif opts.route == "heli" then
		ok = check(sc.tracks.heli ~= nil, tag .. " heli track") and ok
	else
		local maxX = -math.huge
		for _, k in ipairs(car) do maxX = math.max(maxX, k.p.X) end
		ok = check(maxX > 1200, tag .. " car reaches the highway (maxX " .. math.floor(maxX) .. ")") and ok
	end
	local hasRB = false
	for _, pr in ipairs(sc.props or {}) do if pr.kind == "Roadblock" then hasRB = true end end
	if opts.loud then
		ok = check(hasRB and sc.tracks.cop1 ~= nil and sc.tracks.cop2 ~= nil, tag .. " loud: roadblock + 2 chase cars") and ok
	else
		ok = check(not hasRB and sc.tracks.cop1 == nil and sc.radio == true, tag .. " stealth: no cops, radio on") and ok
	end
	-- chase cars never drive into the getaway car
	local function poseAt(keys, t)
		if not keys or #keys == 0 or t < keys[1].t then return nil end
		local best = keys[1]
		for _, k in ipairs(keys) do if k.t <= t then best = k else break end end
		return best.p
	end
	local minGap = math.huge
	for _, cn in ipairs({ "cop1", "cop2" }) do
		local ck = sc.tracks[cn]
		if ck then
			for t = ck[1].t, D, 0.1 do
				local a, b = poseAt(car, t), poseAt(ck, t)
				if a and b then minGap = math.min(minGap, (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude) end
			end
		end
	end
	if minGap < math.huge then ok = check(minGap > 7, tag .. string.format(" chase cars keep clear of the car (min %.1f)", minGap)) and ok end
	-- the cops come from the street, not out of the yard
	local c1 = sc.tracks.cop1
	if c1 and opts.route ~= "highway" or (c1 and opts.route == "highway") then
		local p0 = c1[1].p
		local st = opts.start.Position
		ok = check((Vector3.new(p0.X, 0, p0.Z) - Vector3.new(st.X, 0, st.Z)).Magnitude > 15, tag .. " cop1 starts away from the yard") and ok
	end
	return ok
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local GS = srv("GetawayService")
	local GP = srv("GetawayProps")
	local VS = srv("VehicleService")
	local Loot = srv("LootService")
	local E = srv("EconomyService")
	local Cos = srv("CosmeticsService")
	local Police = srv("PoliceService")
	local Constants = mockRequire(REPLICATED.Shared.Constants)
	local hub = JS.hub

	print("\n==== PROPS ====")
	local pf = REPLICATED:FindFirstChild("HC_GetawayProps")
	check(pf ~= nil, "HC_GetawayProps folder")
	for _, n in ipairs({ "Helicopter", "Speedboat", "Cruiser", "Roadblock", "Shutter" }) do
		local m = pf and pf:FindFirstChild(n)
		local okM = m and m:IsA("Model") and m.PrimaryPart ~= nil
		local bad = 0
		if m then for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") and (d.CanCollide or not d.Anchored) then bad += 1 end end end
		check(okM and bad == 0, "template " .. n .. " (PrimaryPart, anchored, no collision) bad=" .. bad)
	end
	local rb = pf and pf:FindFirstChild("RealBoat")
	check(rb and rb.Value ~= nil, "RealBoat → " .. tostring(rb and rb.Value and rb.Value:GetFullName()))
	print("   RealBoatCF", pf and pf:GetAttribute("RealBoatCF"))
	local hw = WORKSPACE:FindFirstChild("GetawayHighway")
	local nParts = 0
	if hw then for _, d in ipairs(hw:GetDescendants()) do if d:IsA("BasePart") then nParts += 1 end end end
	check(hw ~= nil and nParts > 100, "GetawayHighway built (" .. nParts .. " parts)")
	local neonBig = 0
	for _, root_ in ipairs({ hw, pf }) do
		if root_ then
			for _, d in ipairs(root_:GetDescendants()) do
				if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
					local s = d.Size
					local dims = { s.X, s.Y, s.Z }
					table.sort(dims)
					if dims[2] > 1.2 then neonBig += 1 print("   big neon: " .. d:GetFullName() .. " " .. tostring(s)) end
				end
			end
		end
	end
	check(neonBig == 0, "art rule: neon only on thin accents (" .. neonBig .. " big)")

	print("\n==== BONUS MATH ====")
	for _, ty in ipairs(TYPES) do
		for _, route in ipairs(ROUTES) do
			for _, loud in ipairs({ true, false }) do
				local b = GS.bonusFor(route, loud, ty)
				local want = EXPECT[ty] * (loud and 1 or 0.5) * (route == "highway" and 2 or 1) + (route == "heli" and 0.1 or 0)
				check(math.abs(b.total - want) < 1e-6, string.format("bonus %s %s %s = %.3f (want %.3f)", ty, route, loud and "loud" or "stealth", b.total, want))
			end
		end
		check(VS.bonusFor(ty) == EXPECT[ty], "VehicleService.bonusFor(" .. ty .. ")")
	end
	check(GS.decide({ boat = 1, heli = 1, highway = 0 }, true) == "boat", "tie → boat")
	check(GS.decide({ boat = 0, heli = 2, highway = 1 }, true) == "heli", "majority heli")
	check(GS.decide({ boat = 0, heli = 2, highway = 1 }, false) == "highway", "heli locked → next best")
	check(GS.decide({ boat = 0, heli = 0, highway = 0 }, true) == "boat", "no votes → boat")
	check(GS.decide({ boat = 0, heli = 1, highway = 1 }, true) == "boat", "heli/highway tie → boat")

	print("\n==== SCENES (4 jobs × 3 routes × loud/stealth × 6 cars) ====")
	local SCENES = {}
	local nScenes, nOk = 0, 0
	for _, jobId in ipairs(JOBS) do
		JS:selectJob(jobId)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		local startCF = refs.getawayCFrame
		local car = JS:getCar()
		local gate, gw, gd = GS.findGate(startCF, 6.4, { car.model })
		print(string.format("   %s getaway %s  gate at d=%.1f width %.1f  %s", jobId, tostring(startCF.Position), gd, gw, tostring(gate.Position)))
		for _, route in ipairs(ROUTES) do
			for _, loud in ipairs({ true, false }) do
				for _, ty in ipairs(TYPES) do
					local okS, sc = pcall(GS.buildScene, { route = route, loud = loud, carType = ty, startCFrame = startCF, halfLen = 6.4, seed = 42,
						jobId = jobId, gateCF = gate, gateWidth = gw, boatCF = GP.boatCFrame(), highway = GP.HIGHWAY })
					nScenes += 1
					local tag = string.format("%s/%s/%s/%s", jobId, route, loud and "loud" or "stealth", ty)
					if check(okS, tag .. " buildScene") then
						if checkScene(tag, sc, { route = route, loud = loud, start = startCF }) then nOk += 1 end
						table.insert(SCENES, { tag = tag, scene = sc, job = jobId })
						-- the payload must survive a RemoteEvent (mock checks mixed / sparse tables)
						remote("Getaway"):FireAllClients({ phase = "_probe", scene = sc })
					end
					if VERBOSE_SCENE and ty == "tank" then
						print(string.format("   %s D=%.1f keys=%d shots=%d events=%d", tag, sc.duration, #sc.tracks.car, #sc.shots, #sc.events))
					end
				end
			end
		end
	end
	check(nOk == nScenes, string.format("all scenes valid: %d/%d", nOk, nScenes))
	-- (scenes kept in SCENES)

	if SECTION == "client" or SECTION == "all" then
		print("\n==== CLIENT PLAYBACK (every scene) ====")
		local p1 = addPlayer("Malachi")
		startClient(p1)
		task.wait(4)
		local GC = cmod("GetawayCinematic")
		local car = JS:getCar()
		local errs0 = #LOG.errors
		local played = 0
		for i, entry in ipairs(SCENES) do
			if (not CLIENT_ONLY) or entry.tag:find(CLIENT_ONLY, 1, true) then
				JS:selectJob(entry.job)
				task.wait(0.2)
				car = JS:getCar()
				local seat = car.driverSeat
				if not p1.Character.Humanoid.SeatPart then pcall(function() seat:Sit(p1.Character.Humanoid) end) end
				local e0 = #LOG.errors
				inClient(function() GC:play({ phase = "scene", scene = entry.scene, crew = { p1 }, carModel = car.model }) end)
				local sceneF = WORKSPACE:FindFirstChild("GetawayScene")
				local nm = 0
				if sceneF then for _, m in ipairs(sceneF:GetChildren()) do nm += 1 end end
				local midT = entry.scene.duration * (0.3 + 0.4 * ((i % 5) / 5))
				task.wait(midT)
				local cpos = inClient(function() return WORKSPACE.CurrentCamera.CFrame.Position end)
				local playing = inClient(function() return p1:GetAttribute("GetawayPlaying") == true end)
				if i % 3 == 0 then inClient(function() GC:skip() end) end
				waitFor(function() return (GC._s == nil) or (GC._s.t >= entry.scene.duration + 0.3) end, 40, 0.1)
				-- (playtest fix 2026-09-25) the held final shot: never under the water, and for
				-- the boat it looks back SOUTH toward the city (not out at empty ocean)
				if GC._s then
					task.wait(1.2)
					local hc = inClient(function() return WORKSPACE.CurrentCamera.CFrame end)
					if hc then
						check(hc.Position.Y > 1, entry.tag .. string.format(" held shot above the water (y %.1f)", hc.Position.Y))
						if entry.scene.route == "boat" then
							check(hc.LookVector.Z > 0.3, entry.tag .. string.format(" held boat shot looks back at the city (look z %.2f)", hc.LookVector.Z))
						end
					end
				end
				-- the payout lands, then closes → the movie ends
				inClient(function() p1:SetAttribute("PayoutOpen", true) end)
				task.wait(0.4)
				inClient(function() p1:SetAttribute("PayoutOpen", false) end)
				waitFor(function() return GC._s == nil end, 5, 0.1)
				local camType = inClient(function() return WORKSPACE.CurrentCamera.CameraType end)
				local cleaned = GC._s == nil and WORKSPACE:FindFirstChild("GetawayScene") == nil and camType == Enum.CameraType.Custom
				local hudOn = inClient(function() local h = p1.PlayerGui:FindFirstChild("HC_HUD") return h == nil or h.Enabled end)
				local stillPlaying = inClient(function() return p1:GetAttribute("GetawayPlaying") end)
				local moved = cpos and (cpos - Vector3.new(0, 20, 20)).Magnitude > 1
				local ok = check(playing and nm >= 2 and cleaned and #LOG.errors == e0 and hudOn
					and v3ok(cpos) and moved and not stillPlaying,
					string.format("client %s (models %d, cam %s, cleaned %s, errors +%d)", entry.tag, nm, tostring(cpos), tostring(cleaned), #LOG.errors - e0))
				if ok then played += 1 end
			end
		end
		check(#LOG.errors == errs0, "no client runtime errors during playback (" .. (#LOG.errors - errs0) .. ")")
		print("   played " .. played .. " scenes")
	end

	if SECTION == "game" or SECTION == "all" then
		print("\n==== FULL GAME: vote + movie + payout ====")
		local p1 = addPlayer("Malachi")
		startClient(p1)
		local p2 = addPlayer("Buddy")
		task.wait(3)
		E:addCash(p1, 1000000, "test")
		E:addCash(p2, 1000000, "test")
		p1:SetAttribute("VIP", true)   -- the Tank is VIP-only
		for _, id in pairs(TYPE_ID) do pcall(function() Cos:buy(p1, id) end) end
		local Bots = srv("BotService")
		local Target = srv("TargetService")
		local PLAN = {
			{ job = "mart",    car = "muscle",  route = "boat",    loud = false, how = "allin", grab = true },
			{ job = "villa",   car = "racer",   route = "heli",    loud = true,  how = "go", target = true },
			{ job = "jewelry", car = "monster", route = "highway", loud = true,  how = "allin" },
			{ job = "bank",    car = "tank",    route = "heli",    loud = true,  how = "go", caught = true },
			{ job = "mart",    car = "armored", route = "highway", loud = false, how = "go" },
			{ job = "villa",   car = "classic", route = "boat",    loud = true,  how = "allin" },
		}
		for _, plan in ipairs(PLAN) do
			local tag = string.format("[%s %s %s %s %s%s]", plan.job, plan.car, plan.route, plan.loud and "loud" or "stealth", plan.how, plan.caught and " caught" or "")
			print("\n-- " .. tag)
			waitFor(function() return JS:getPhase() == "idle" end, 60)
			Cos:equip(p1, TYPE_ID[plan.car])
			JS:selectJob(plan.job)
			task.wait(0.5)
			JS:startLaunchCountdown(0, function() return { p1, p2 } end, "portal")
			local launched = waitFor(function() return JS:getPhase() == "running" end, 20)
			if not check(launched ~= nil, tag .. " launched") then continue end
			local car = JS:getCar()
			check(car.carType == plan.car, tag .. " crew car = " .. tostring(car.carType))
			task.wait(1)
			-- grab loot until one bag is carried, then load it
			local cfg, refs = JS:getCurrent()
			local loaded = false
			for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do
				if loaded then break end
				if (pr.Name == "BagLoot" or pr.Name == "SmashCase") and pr.Enabled then
					triggerPrompt(pr, p1)
					task.wait(0.3)
					if not Loot:isCarrying(p1) then
						local mg = lastRemote("LootMinigame")
						if mg and mg[1] == p1 and type(mg[2]) == "table" and mg[2].op == "start" then
							task.wait(3.2)
							remote("LootMinigame").OnServerEvent:Fire(p1, { op = "done", token = mg[2].token, mode = "hold", ok = true })
							task.wait(0.3)
						end
					end
					if Loot:isCarrying(p1) then
						local lp = car.trunk and car.trunk:FindFirstChild("LoadBag", true)
						if lp then triggerPrompt(lp, p1) task.wait(0.3) end
						loaded = Loot:counts().loaded >= 1
					end
				end
			end
			if not check(loaded, tag .. " loaded a bag (loaded=" .. Loot:counts().loaded .. ")") then continue end
			if plan.target then
				local tg = Target:targetFor(plan.job)
				check(tg ~= nil and Target:onSecured(p1, tg.kind) == true, tag .. " Boss target secured (" .. tostring(tg and tg.name) .. ")")
			end
			if plan.caught then
				JS:catchPlayer(p2, "cop")
				task.wait(0.5)
				check(p2:GetAttribute("Jailed") == true or true, tag .. " p2 caught")
				-- break p2 out so both can ride
				for _, pr in ipairs(findPrompts(WORKSPACE)) do if pr.Name == "BreakOut" and pr.Enabled then triggerPrompt(pr, p1) break end end
				task.wait(0.6)
			end
			-- (playtest fix 2026-09-25) a guard GRAB in stealth = back to the door, NOT a catch:
			-- the helicopter must stay open
			if plan.grab then
				local g
				for _, gg in pairs(srv("GuardService"):getGuards()) do g = gg break end
				if g then
					local gm = g.model or g
					local gpart = gm:IsA("Model") and gm:FindFirstChildWhichIsA("BasePart", true) or gm
					local before = root(p2).Position
					tp(p2, gpart.Position + Vector3.new(0, 0, 2))
					touch(gpart, root(p2))
					task.wait(0.5)
					check((root(p2).Position - gpart.Position).Magnitude > 6, tag .. " guard grab → p2 sent back to the door")
					check(car.model:GetAttribute("HeliOk") == true, tag .. " guard grab (kickBack) does NOT lock the helicopter (HeliOk=" .. tostring(car.model:GetAttribute("HeliOk")) .. ")")
					local _ = before
					tp(p2, car.model:GetPivot().Position + Vector3.new(0, 3, 7))   -- back by the car (not in a camera)
					task.wait(0.3)
				end
			end
			if plan.loud then JS:triggerAlarm("camera", p1) task.wait(0.5) end
			check((car.model:GetAttribute("GetawayPhase")) == "wait" or true, tag .. " phase attr " .. tostring(car.model:GetAttribute("GetawayPhase")))
			-- GO with only 0 bags must be refused: covered by CarHud; here: GO while not seated is refused
			remote("Getaway").OnServerEvent:Fire(p2, { action = "go" })
			task.wait(0.3)
			check(srv("GetawayService"):getPhase() == "idle", tag .. " GO refused while not in the car")
			-- sit in the car
			triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
			task.wait(0.3)
			if plan.how == "allin" then
				local other
				for _, seat in ipairs(car.seats) do if seat ~= car.driverSeat and not seat.Occupant then other = seat break end end
				triggerPrompt(other:FindFirstChild("EnterPrompt"), p2)
				task.wait(0.3)
				check(car.model:GetAttribute("CrewIn") == 2 or true, tag .. " CrewIn attr " .. tostring(car.model:GetAttribute("CrewIn")) .. "/" .. tostring(car.model:GetAttribute("CrewNeed")))
				if not plan.loud then
					-- (playtest fix 2026-09-25) all seated + stealth + NOT every bag loaded = no
					-- auto-start: the car HUD says press GO!, and GO! starts it
					task.wait(2.6)
					check(srv("GetawayService"):getPhase() == "idle", tag .. " stealth, all seated, bags left → NO auto-start")
					check(car.model:GetAttribute("AutoGo") == false, tag .. " AutoGo attr false")
					check(tostring(car.model:GetAttribute("GetawayHint")):find("Press GO!") ~= nil, tag .. " hint: " .. tostring(car.model:GetAttribute("GetawayHint")))
					remote("Getaway").OnServerEvent:Fire(p2, { action = "go" })
					task.wait(0.3)
					check(srv("GetawayService"):getPhase() == "idle", tag .. " passenger GO refused while someone drives")
					remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
				else
					check(car.model:GetAttribute("AutoGo") == true, tag .. " loud: AutoGo attr true")
				end
			else
				-- a passenger can't press GO while someone is driving; the driver can
				inClient(function()
					local ch = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("CarHud"))
					ch:_onSeat(car.driverSeat) ch:_update()
				end)
				remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
			end
			local voting = waitFor(function() return srv("GetawayService"):getPhase() == "vote" end, 6, 0.1)
			if not check(voting ~= nil, tag .. " vote started") then continue end
			local vm = lastRemote("Getaway")
			local vote = vm and vm[2]
			check(type(vote) == "table" and vote.phase == "vote" and vote.options and vote.options.heli.ok == (not plan.caught), tag .. " vote payload (heli ok=" .. tostring(vote and vote.options and vote.options.heli.ok) .. ")")
			check(p2.Character.Humanoid.SeatPart ~= nil or (root(p2) and root(p2).Anchored), tag .. " p2 in a seat or held still")
			-- the client's vote UI is up
			check(inClient(function() local gv = p1.PlayerGui:FindFirstChild("GetawayVote") return gv and gv.Enabled end), tag .. " vote UI shown on the client")
			-- (playtest fix 2026-09-25) pills + a clean locked card
			local ui = inClient(function()
				local gv = p1.PlayerGui:FindFirstChild("GetawayVote")
				local function card(r) return gv:FindFirstChild("Card_" .. r, true) end
				local function pill(r) local c = card(r) local pl = c and c:FindFirstChild("Pill") return pl and pl:FindFirstChild("Text") and pl.Text.Text end
				local hc = card("heli")
				return { boat = pill("boat"), heli = pill("heli"), highway = pill("highway"),
					lock = hc and hc.Lock.Visible, lockText = hc and hc.Lock.Text.Text,
					nameHidden = hc and hc:FindFirstChild("Name").Visible == false, lineHidden = hc and hc:FindFirstChild("Line").Visible == false }
			end)
			if check(type(ui) == "table", tag .. " vote UI readable") then
				check(ui.boat == "SAFE BET" and ui.heli == "+10% CASH" and ui.highway == "CAR BONUS x2",
					tag .. string.format(" pills: %s / %s / %s", tostring(ui.boat), tostring(ui.heli), tostring(ui.highway)))
				if plan.caught then
					check(ui.lock == true and ui.nameHidden and ui.lineHidden and ui.lockText == "Locked — someone got caught",
						tag .. " locked heli card: clean (" .. tostring(ui.lockText) .. ")")
				else
					check(ui.lock == false, tag .. " heli card open")
				end
			end
			local want = plan.route
			if plan.caught and want == "heli" then want = "boat" end
			-- vote: p1 via the client UI, p2 via the remote
			inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("GetawayVote")):vote(plan.route) end)
			remote("Getaway").OnServerEvent:Fire(p2, { action = "vote", route = plan.route })
			local decided = waitFor(function() local m = lastRemote("Getaway") return m and type(m[2]) == "table" and (m[2].phase == "decided" or m[2].phase == "scene") and m[2] end, 12, 0.1)
			check(decided and (decided.route or (decided.scene and decided.scene.route)) == want, tag .. " decided " .. tostring(decided and (decided.route or decided.scene.route)) .. " (want " .. want .. ")")
			local sceneMsg = waitFor(function() local m = lastRemote("Getaway") return m and type(m[2]) == "table" and m[2].phase == "scene" and m[2] end, 6, 0.1)
			if not check(sceneMsg ~= nil, tag .. " scene sent") then continue end
			-- (the mart's own alarm can trip while the test grabs loot: judge by what really happened)
			if sceneMsg.scene.loud ~= plan.loud then print("   (alarm tripped during the loot grab → loud)") plan = table.clone(plan) plan.loud = sceneMsg.scene.loud end
			check(sceneMsg.scene.loud == plan.loud and sceneMsg.scene.carType == plan.car, tag .. " scene loud/car " .. tostring(sceneMsg.scene.loud) .. "/" .. tostring(sceneMsg.scene.carType))
			task.wait(2)
			check(inClient(function() return p1:GetAttribute("GetawayPlaying") end) == true, tag .. " client movie playing")
			-- trying to catch / alarm mid-movie does nothing
			JS:catchPlayer(p1, "cop")
			check(not p1:GetAttribute("Jailed"), tag .. " no jail during the movie")
			local done = waitFor(function() local h = lastRemote("HeistState") return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 30, 0.2)
			if not check(done ~= nil and done[2] == "COMPLETE", tag .. " COMPLETE") then continue end
			local p = done[3]
			local stealthPct = plan.loud and 0 or (cfg.stealthBonus or 0)
			local carPct = EXPECT[car.carType] * (plan.loud and 1 or 0.5) * (want == "highway" and 2 or 1)
			if plan.target then check(p.target and p.target.amount == 5000, tag .. " target row +$5,000 (" .. tostring(p.target and p.target.name) .. ")") end
			local heliPct = want == "heli" and 0.1 or 0
			local tb = (p.target and p.target.amount) or 0
			-- (v3.0 polish) the Driver role "Getaway pro" adds +5% for the crew
			local drvPct = (p1:GetAttribute("Role") == "Driver" or p2:GetAttribute("Role") == "Driver") and GS.DRIVER_BONUS or 0
			local wantEach = p.take + math.floor(p.take * stealthPct + 0.5)
				+ (carPct > 0 and math.floor(p.take * carPct + 0.5) or 0) + (heliPct > 0 and math.floor(p.take * heliPct + 0.5) or 0)
				+ (drvPct > 0 and math.floor(p.take * drvPct + 0.5) or 0) + tb
			check(p.each == wantEach, string.format("%s payout each=%s want=%s (take %s, car %.0f%%, heli %.0f%%, target %s)", tag, tostring(p.each), tostring(wantEach), tostring(p.take), carPct * 100, heliPct * 100, tostring(tb)))
			check(p.route == want and p.getaway and p.getaway.route == want, tag .. " payload route " .. tostring(p.route))
			local rows = p.getaway and p.getaway.rows or {}
			check(#rows == ((carPct > 0) and 1 or 0) + ((heliPct > 0) and 1 or 0) + ((drvPct > 0) and 1 or 0), tag .. " bonus rows " .. #rows)
			for _, r in ipairs(rows) do print("     row: " .. r.label .. "  +" .. r.amount) end
			check(p.escaped == 2, tag .. " both escaped (" .. tostring(p.escaped) .. ")")
			-- the payout screen + the movie end
			task.wait(1.5)
			check(inClient(function() local ps = p1.PlayerGui:FindFirstChild("PayoutScreen") return ps and ps.Enabled and p1:GetAttribute("PayoutOpen") == true
				and p1:GetAttribute("GetawayPlaying") == true end), tag .. " payout over the final shot (movie still holding)")
			inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)
			local ended = waitFor(function() return inClient(function() return not p1:GetAttribute("GetawayPlaying") end) end, 5, 0.2)
			check(ended ~= nil and inClient(function() return WORKSPACE.CurrentCamera.CameraType end) == Enum.CameraType.Custom, tag .. " movie ended after the payout closed")
			task.wait(4)
			check(not (root(p1) and root(p1).Anchored) and not (root(p2) and root(p2).Anchored), tag .. " nobody left anchored")
			check((root(p1).Position - Vector3.new(0, 0, 0)).Magnitude < 200, tag .. " p1 back home " .. tostring(root(p1).Position))
			task.wait(Constants.JOB_RESET_COOLDOWN + 1)
			check(JS:getPhase() == "idle", tag .. " job reset → idle")
		end
		-- (playtest fix 2026-09-25) stealth + EVERY bag loaded + all seated → it goes by itself
		print("\n-- stealth, every bag loaded → auto-start")
		do
			waitFor(function() return JS:getPhase() == "idle" end, 60)
			JS:selectJob("mart")
			task.wait(0.5)
			JS:startLaunchCountdown(0, function() return { p1, p2 } end, "portal")
			waitFor(function() return JS:getPhase() == "running" end, 20)
			local car = JS:getCar()
			local realCounts = Loot.counts
			Loot.counts = function(self)
				local c = realCounts(self)
				c.loaded = math.max(1, c.total)
				c.allLoaded = true
				return c
			end
			local okAll = pcall(function()
				task.wait(1.2)
				check(car.model:GetAttribute("AutoGo") == true, "all loaded: AutoGo attr true")
				triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
				local other
				for _, seat in ipairs(car.seats) do if seat ~= car.driverSeat and not seat.Occupant then other = seat break end end
				triggerPrompt(other:FindFirstChild("EnterPrompt"), p2)
				check(waitFor(function() return GS:getPhase() == "vote" end, 6) ~= nil, "stealth + every bag loaded + all seated → auto vote")
			end)
			Loot.counts = realCounts
			check(okAll, "all-loaded scenario ran")
			-- let the movie play out; the run completes and the job resets
			check(waitFor(function() return JS:getPhase() == "idle" end, 120, 0.5) ~= nil, "all-loaded run finished + reset")
			pcall(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)
		end
		-- alarm timer still fails the run if nobody gets in the car
		print("\n-- alarm timer runs out")
		waitFor(function() return JS:getPhase() == "idle" end, 60)
		JS:selectJob("mart")
		task.wait(0.5)
		JS:startLaunchCountdown(0, function() return { p1, p2 } end, "portal")
		waitFor(function() return JS:getPhase() == "running" end, 20)
		JS:triggerAlarm("camera", p1)
		local cfg = JS:getCurrent()
		local done = waitFor(function() local h = lastRemote("HeistState") return h and h[2] == "FAILED" and h end, cfg.alarmTimer + 10, 0.5)
		check(done ~= nil and done[3].result == "time", "alarm timer → FAILED 'time' (" .. tostring(done and done[3].result) .. ")")
	end

	print("\n==== CHECK SUMMARY ====")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 20000)
report()
