-- ═══════════════ v3.0 POLISH integration driver ═══════════════
-- all 4 jobs end-to-end with v3 loot (mini-games via the REAL client, heavy,
-- fragile, jackpot, hidden stash, target) + bots + jail/breakout + the
-- getaway vote (Driver x2) + scene + payout rows, then a reshuffle check.
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
local function lastRemote(name) return REMOTE_LOG[name] end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local Shuffle = srv("LootShuffle")
	local Target = srv("TargetService")
	local Bots = srv("BotService")
	local Data = srv("PlayerDataService")
	local GS = srv("GetawayService")
	local VS = srv("VehicleService")
	local Cos = srv("CosmeticsService")
	local E = srv("EconomyService")
	local Constants = mockRequire(REPLICATED.Shared.Constants)
	local V3 = Constants.LOOT_V3

	local p1 = addPlayer("Malachi")
	startClient(p1)
	local p2 = addPlayer("Buddy")
	task.wait(4)
	local errs0 = #LOG.errors

	print("\n==== WORDING / CATALOG ====")
	local drv
	for _, r in ipairs(Constants.ROLES) do if r.id == "Driver" then drv = r end end
	check(drv and drv.perks:find("x2") and drv.perks:find("5%%") and not drv.perks:lower():find("nitro"), "Driver perk text: " .. tostring(drv and drv.perks))
	for _, j in ipairs(Constants.JOBS) do
		local bad = false
		for _, l in ipairs(j.briefing) do if l:lower():find("marina") or l:lower():find("drive to") then bad = true end end
		check(not bad, j.id .. ": briefing has no 'drive to the marina'")
	end
	local carsOk, carLines = true, {}
	for _, item in ipairs(Cos:catalog()) do
		if item.category == "car" then
			local b = VS.GETAWAY_BONUS[item.carType]
			local want = b > 0 and string.format("+%d%% ESCAPE CASH", math.floor(b * 100 + 0.5)) or "ALL-ROUNDER"
			if not item.power or item.power.name ~= want or tostring(item.power.name):find("SPEED") then carsOk = false end
			table.insert(carLines, item.id .. "=" .. tostring(item.power and item.power.name) .. " '" .. tostring(item.power and item.power.desc) .. "'")
		end
	end
	check(carsOk, "car cards show the getaway cash bonus: " .. table.concat(carLines, " | "))
	local marina = WORKSPACE:FindFirstChild("Marina", true)
	check(marina and marina:FindFirstChild("DropoffRing") == nil and marina:FindFirstChild("Pier") and marina.Pier:FindFirstChild("Speedboat"),
		"marina: no drop-off ring, pier + speedboat intact")
	local signTxt = {}
	for _, d in ipairs(WORKSPACE:GetDescendants()) do
		if d:IsA("TextLabel") and (tostring(d.Text):find("DROP%-OFF") or tostring(d.Text):find("CASH OUT")) then table.insert(signTxt, d.Text) end
	end
	check(#signTxt == 0, "no DROP-OFF / CASH OUT signs left in the world (" .. table.concat(signTxt, ", ") .. ")")

	E:addCash(p1, 1000000, "test")
	p1:SetAttribute("VIP", true)
	for _, id in ipairs({ "CarMuscle", "CarRacer", "CarArmored", "CarMonster", "CarTank" }) do pcall(function() Cos:buy(p1, id) end) end

	local LM = cmod("LootMinigames")
	local function lastMG() local l = REMOTE_LOG.LootMinigame return l and l[1] == p1 and l[2] end
	local gamesSeen = {}
	local sigs = {}

	-- p takes a pile; interact piles go through the client (p1) or the raw remote (p2)
	local function stunGuards()
		for _, g in pairs(srv("GuardService"):getGuards()) do srv("GuardService"):stun(g, 30) end
	end
	local function takePile(pr, p, partner)
		stunGuards()
		tp(p, pr.Parent.Position + Vector3.new(0, 1, 2))
		if partner then tp(partner, pr.Parent.Position + Vector3.new(2, 1, 2)) end
		local before = REMOTE_LOG.LootMinigame
		triggerPrompt(pr, p)
		task.wait(0.25)
		if partner and not Loot:isCarrying(p) then triggerPrompt(pr, partner) task.wait(0.3) end
		if Loot:isCarrying(p) then return true end
		local l = REMOTE_LOG.LootMinigame
		if l and l ~= before and l[1] == p and type(l[2]) == "table" and l[2].op == "start" then
			local msg = l[2]
			gamesSeen[msg.game] = (gamesSeen[msg.game] or 0) + 1
			if p == p1 then
				-- the real client card: check it opened with the right game, then hold E (accessibility fallback)
				check(LM:isOpen() and LM._open and LM._open.game == msg.game, "client card open for '" .. tostring(msg.game) .. "' (" .. tostring(msg.name) .. ")")
				-- server rejects a too-fast finish
				remote("LootMinigame").OnServerEvent:Fire(p, { op = "done", token = msg.token, mode = "game", ok = true })
				task.wait(0.2)
				local r = REMOTE_LOG.LootMinigame
				check(r and r[2].op == "result" and r[2].ok == false, "server rejected an instant finish (" .. tostring(r and r[2].msg) .. ")")
				task.wait(1.3)
				triggerPrompt(pr, p)
				task.wait(0.3)
				inClient(function() UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.E, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }, false) end)
				task.wait((msg.hold or 3) + 0.4)
				inClient(function() UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.E, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }, false) end)
				task.wait(0.5)
			else
				task.wait(math.max(msg.min or 1, 1) + 0.2)
				remote("LootMinigame").OnServerEvent:Fire(p, { op = "done", token = msg.token, mode = "game", ok = true })
				task.wait(0.3)
			end
		end
		if not Loot:isCarrying(p) then
			local l2 = REMOTE_LOG.LootMinigame
			print("   DEBUG take failed: lastMG op=" .. tostring(l2 and l2[2].op) .. " ok=" .. tostring(l2 and l2[2].ok) .. " msg=" .. tostring(l2 and l2[2].msg) .. " reason=" .. tostring(l2 and l2[2].reason)
				.. " p2carry=" .. tostring(p2:GetAttribute("CarryingLoot")) .. " p1carry=" .. tostring(p1:GetAttribute("CarryingLoot")) .. " prompt=" .. pr.ActionText .. " en=" .. tostring(pr.Enabled) .. " LMopen=" .. tostring(LM:isOpen()))
			local nt = REMOTE_LOG.Notify
			print("   DEBUG last notify: " .. tostring(nt and nt[1] and nt[1].Name) .. " " .. tostring(nt and type(nt[2]) == "table" and nt[2].text))
		end
		return Loot:isCarrying(p)
	end
	local function load(p, car)
		local lp = car.trunk and car.trunk:FindFirstChild("LoadBag", true)
		if not lp then return false end
		local n = Loot:counts().loaded
		tp(p, car.trunk.Position + Vector3.new(0, 1, 3))
		triggerPrompt(lp, p)
		task.wait(0.3)
		return Loot:counts().loaded == n + 1
	end
	local function piles(refs, pred)
		local out = {}
		for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do
			if pr.Enabled and (pr.Name == "BagLoot" or pr.Name == "SmashCase") and (not pred or pred(pr)) then table.insert(out, pr) end
		end
		return out
	end
	local function pileAtSpot(refs, spot)
		local want = spot.cframe.Position + Vector3.new(0, 2.5, 0)
		for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do
			if pr.Name == "BagLoot" and pr.Parent and (pr.Parent.Position - want).Magnitude < 0.05 then return pr end
		end
	end
	local function sigOf(refs)
		local t = {}
		for i, s in ipairs(refs.lootSpots or {}) do if Shuffle:isActive(s) then table.insert(t, i) end end
		return table.concat(t, ",") .. "|" .. tostring(Loot:counts().jackpot)
	end

	local PLAN = {
		{ job = "mart",    car = "CarMuscle",  roles = { "Driver", "Hacker" },  votes = { "boat", "highway" },  want = "boat" },
		{ job = "villa",   car = "CarTank",    roles = { "Driver", "Hacker" },  votes = { "highway", "heli" },  want = "highway", loud = true },
		{ job = "jewelry", car = "CarRacer",   roles = { "Hacker", "Lookout" }, votes = { "heli", "heli" },     want = "heli" },
		{ job = "bank",    car = "CarMonster", roles = { "Driver", "Muscle" }, votes = { "heli", "highway" },  want = "highway", loud = true, jail = true },
		{ job = "mart",    car = "CarArmored", roles = { "Lookout", "Driver" }, votes = { "boat", "heli" },     want = "heli", again = true },
	}
	for _, plan in ipairs(PLAN) do
		local tag = "[" .. plan.job .. (plan.again and " #2" or "") .. "]"
		print("\n==== JOB " .. tag .. " ====")
		waitFor(function() return JS:getPhase() == "idle" end, 60)
		Cos:equip(p1, plan.car)
		JS:selectJob(plan.job)
		task.wait(0.5)
		JS:startLaunchCountdown(0, function() return { p1, p2 } end, "portal")
		if not check(waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil, tag .. " launched") then continue end
		p1:SetAttribute("Role", plan.roles[1])
		p2:SetAttribute("Role", plan.roles[2])
		local cfg, refs = JS:getCurrent()
		local car = JS:getCar()
		task.wait(1)
		check(#Bots:getBots() == 1, tag .. " 1 bot for 2 players (" .. #Bots:getBots() .. ")")
		local c0 = Loot:counts()
		check(c0.taken == 0 and c0.loaded == 0 and c0.total > 0, tag .. " fresh loot: " .. c0.total .. " piles, jackpot " .. tostring(c0.jackpot))
		local jpMarked = 0
		for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do if tostring(pr.ObjectText):find("JACKPOT") then jpMarked += 1 end end
		check(c0.jackpot ~= nil and jpMarked > 0, tag .. " jackpot room " .. tostring(c0.jackpot) .. " (" .. jpMarked .. " piles marked)")
		local sig = sigOf(refs)
		if plan.again then
			check(sigs[plan.job] ~= nil and sig ~= sigs[plan.job], tag .. " next run RESHUFFLED (" .. #sig .. " chars, differs from run #1)")
		end
		sigs[plan.job] = sig

		-- hidden stash: roll a seed that reveals one, then one that doesn't
		local stash
		for _, s in ipairs(refs.lootSpots or {}) do if s.hidden then stash = s break end end
		if check(stash ~= nil, tag .. " builder placed a hidden stash (" .. tostring(stash and stash.kind) .. ")") then
			local seedOn, seedOff
			for seed = 1, 600 do
				local active = Shuffle:prepare(refs, seed)
				local on = table.find(active, stash) ~= nil
				if on and not seedOn then seedOn = seed end
				if not on and not seedOff then seedOff = seed end
				if seedOn and seedOff then break end
			end
			Loot:reset({ seed = seedOff })
			check(pileAtSpot(refs, stash) == nil, tag .. " stash rolled OUT → no pile")
			Loot:reset({ seed = seedOn })
			local sp = pileAtSpot(refs, stash)
			check(sp ~= nil and sp.Enabled, tag .. " stash rolled IN (seed " .. tostring(seedOn) .. ") → pile '" .. tostring(sp and sp.ObjectText) .. "'")
			if sp and takePile(sp, p1) then
				check(load(p1, car), tag .. " secret stash bagged + loaded")
			end
		end

		-- a bot run (give it a plain bag)
		local plain = piles(refs, function(pr) return pr.ActionText == "Bag it" and not tostring(pr.ObjectText):find("^TARGET") end)[1]
		if plain and takePile(plain, p1) then
			local b = Bots:getBots()[1]
			local n = Loot:counts().loaded
			tp(p1, b.model:GetPivot().Position + Vector3.new(0, 0, 3))
			local gp = b.model:FindFirstChild("GiveBag", true)
			if gp then triggerPrompt(gp, p1) task.wait(0.3) end
			check(waitFor(function() return Loot:counts().loaded > n end, 45) ~= nil, tag .. " bot carried a bag to the car")
		end

		-- every interact kind in this job, through the REAL client
		local kinds = {}
		for _, pr in ipairs(piles(refs, function(pr) return pr.ActionText ~= "Bag it" and not pr.ActionText:find("Lift") and pr.Name == "BagLoot" end)) do
			if not kinds[pr.ActionText] then kinds[pr.ActionText] = pr end
		end
		for at, pr in pairs(kinds) do
			if Loot:isCarrying(p1) then Loot:drop(p1) task.wait(0.2) end
			local ok = takePile(pr, p1)
			check(ok, tag .. " mini-game '" .. at .. "' (" .. tostring(pr.ObjectText) .. ") → bagged")
			if ok then check(load(p1, car), tag .. "   …loaded") end
		end

		Loot:setVaultOpen(true)
		task.wait(0.2)
		-- heavy: two players, or Muscle solo
		local heavy = piles(refs, function(pr) return pr.ActionText:find("Lift together") ~= nil and not tostring(pr.ObjectText):find("^TARGET") end)[1]
		if heavy then
			if p2:GetAttribute("Role") == "Muscle" then
				local ok = takePile(heavy, p2)
				check(ok and p2:GetAttribute("CarryPartner") == nil, tag .. " Muscle lifts heavy '" .. tostring(heavy.ObjectText) .. "' alone")
				if ok then check(load(p2, car), tag .. "   …Muscle loaded it") end
			else
				local ok = takePile(heavy, p1, p2)
				check(ok and p1:GetAttribute("CarryPartner") == "Buddy", tag .. " heavy '" .. tostring(heavy.ObjectText) .. "' lifted together")
				if ok then check(load(p2, car), tag .. "   …the helper loaded it") end
			end
		else
			print("   (no heavy pile open outside the vault)")
		end

		-- fragile: run with it → CRACK, then load (value drops 25%)
		local fr = piles(refs, function(pr) return tostring(pr.ObjectText):find("FRAGILE") ~= nil and not pr.ActionText:find("Lift") end)[1]
		if fr and takePile(fr, p1) then
			local v0 = Loot:valueOf(p1)
			root(p1).AssemblyLinearVelocity = Vector3.new(14, 0, 0)
			task.wait(2.4)
			root(p1).AssemblyLinearVelocity = Vector3.zero
			local v1 = Loot:valueOf(p1)
			check(v1 < v0 and math.abs(v1 - v0 * 0.75) <= 1, tag .. string.format(" fragile '%s' cracked when running: %d → %d", tostring(fr.ObjectText), v0, v1))
			check(load(p1, car), tag .. "   …cracked bag still loads")
		else
			print("   (no fragile pile open)")
		end

		-- the Boss's target
		Loot:setVaultOpen(true)
		task.wait(0.2)
		local tp_ = piles(refs, function(pr) return tostring(pr.ObjectText):find("^TARGET") ~= nil end)[1]
		if not tp_ then
			for _, sp in ipairs(refs.lootSpots) do if sp.target then
				local pr = pileAtSpot(refs, sp)
				print("   DEBUG target spot", sp.kind, "inVault", sp.inVault, "active", Shuffle:isActive(sp), "pile", pr and pr.ActionText, pr and pr.Enabled, pr and pr.ObjectText)
			end end
			for _, pr in ipairs(findPrompts(refs.root)) do if tostring(pr.ObjectText):find("TARGET") then print("   DEBUG TARGET prompt", pr.Name, pr.Enabled, pr.ActionText, pr.ObjectText, pr:GetFullName()) end end
		end
		if check(tp_ ~= nil, tag .. " target pile out (" .. tostring(tp_ and tp_.ObjectText) .. ")") then
			local heavyT = tp_.ActionText:find("Lift") ~= nil
			local ok = takePile(tp_, p1, heavyT and p2 or nil)
			check(ok and p1:GetAttribute("CarryTarget") == true, tag .. " target bagged" .. (heavyT and " (heavy, 2 players)" or ""))
			if ok then
				check(load(heavyT and p2 or p1, car) and Target:isSecured(), tag .. " target loaded → secured")
			end
		end

		-- alarm → cops → jail → breakout (locks the helicopter)
		if plan.loud then JS:triggerAlarm("camera", p1) task.wait(0.5) end
		if plan.jail then
			JS:catchPlayer(p2, "cop")
			task.wait(0.5)
			check(p2:GetAttribute("Jailed") == true, tag .. " p2 caught → jail")
			local bo
			for _, pr in ipairs(findPrompts(WORKSPACE)) do if pr.Name == "BreakOut" and pr.Enabled then bo = pr end end
			if check(bo ~= nil, tag .. " BreakOut prompt") then
				triggerPrompt(bo, p1)
				task.wait(0.6)
				check(not p2:GetAttribute("Jailed"), tag .. " p1 broke p2 out")
			end
			check(car.model:GetAttribute("HeliOk") == false, tag .. " HeliOk = false after a catch")
		end

		-- everyone in the car → the vote
		if Loot:isCarrying(p1) then Loot:drop(p1) end
		if Loot:isCarrying(p2) then Loot:drop(p2) end
		task.wait(0.3)
		local take0 = Loot:counts().take
		triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
		local other
		for _, seat in ipairs(car.seats) do if seat ~= car.driverSeat and not seat.Occupant then other = seat break end end
		triggerPrompt(other:FindFirstChild("EnterPrompt"), p2)
		if not plan.loud then
			-- (playtest fix 2026-09-25) stealth + bags still out = sitting down does NOT start it; GO! does
			task.wait(2.2)
			check(GS:getPhase() == "idle", tag .. " stealth all in, bags left → waits for GO!")
			remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
		end
		if not check(waitFor(function() return GS:getPhase() == "vote" end, 6) ~= nil, tag .. (plan.loud and " all in (alarm) → vote" or " GO! → vote")) then continue end
		local hasDriver = plan.roles[1] == "Driver" or plan.roles[2] == "Driver"
		local vm = lastRemote("Getaway")[2]
		check(vm.options.heli.ok == (not plan.jail), tag .. " heli " .. (plan.jail and "LOCKED" or "open") .. " (" .. tostring(vm.options.heli.why) .. ")")
		check((vm.driver ~= nil) == hasDriver and (vm.options.boat.driverPct or 0) == (hasDriver and GS.DRIVER_BONUS or 0), tag .. " vote payload driver=" .. tostring(vm.driver))
		task.wait(0.2)
		local sub = inClient(function() local g = p1.PlayerGui:FindFirstChild("GetawayVote") return g and g.Enabled and g:FindFirstChild("Sub", true) and g:FindFirstChild("Sub", true).Text end)
		check(sub and (tostring(sub):find("counts x2") ~= nil) == hasDriver, tag .. " vote UI: " .. tostring(sub))
		inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("GetawayVote")):vote(plan.votes[1]) end)
		remote("Getaway").OnServerEvent:Fire(p2, { action = "vote", route = plan.votes[2] })
		local tally
		task.wait(0.2)
		for _ = 1, 3 do local m = lastRemote("Getaway") if m and m[2].phase == "tally" then tally = m[2] end end
		local decided = waitFor(function() local m = lastRemote("Getaway") return m and (m[2].phase == "decided" or m[2].phase == "scene") and m[2] end, 12)
		local route = decided and (decided.route or (decided.scene and decided.scene.route))
		check(route == plan.want, tag .. string.format(" votes %s/%s (roles %s/%s) → %s (want %s)%s", plan.votes[1], plan.votes[2], plan.roles[1], plan.roles[2], tostring(route), plan.want,
			decided and decided.votes and string.format("  tally boat %d heli %d highway %d", decided.votes.boat or 0, decided.votes.heli or 0, decided.votes.highway or 0) or ""))
		check(waitFor(function() return inClient(function() return p1:GetAttribute("GetawayPlaying") == true end) end, 6) ~= nil, tag .. " movie playing on the client")
		local done = waitFor(function() local h = lastRemote("HeistState") return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 40, 0.2)
		if not check(done and done[2] == "COMPLETE", tag .. " COMPLETE") then continue end
		local p = done[3]
		local b = VS.GETAWAY_BONUS[VS.CAR_TYPES and car.carType or "classic"] or 0
		local carPct = b * (plan.loud and 1 or 0.5) * (route == "highway" and 2 or 1)
		local heliPct = route == "heli" and 0.1 or 0
		local drvPct = hasDriver and 0.05 or 0
		local r5 = function(x) return math.floor(x + 0.5) end
		local want = p.take + (plan.loud and 0 or r5(p.take * (cfg.stealthBonus or 0)))
			+ (carPct > 0 and r5(p.take * carPct) or 0) + (heliPct > 0 and r5(p.take * heliPct) or 0)
			+ (drvPct > 0 and r5(p.take * drvPct) or 0) + ((p.target and p.target.amount) or 0)
		check(p.take == take0, tag .. " take = loaded value " .. tostring(p.take) .. " (" .. tostring(take0) .. ")")
		check(p.each == want, tag .. string.format(" each %s = want %s  (car %s %.1f%%, heli %.0f%%, driver %.0f%%, target %s)", tostring(p.each), tostring(want), car.carType, carPct * 100, heliPct * 100, drvPct * 100, tostring(p.target and p.target.amount)))
		local rows = p.getaway and p.getaway.rows or {}
		local labels = {}
		for _, r in ipairs(rows) do table.insert(labels, r.icon .. " " .. r.label .. " +" .. r.amount) end
		print("     rows: " .. table.concat(labels, " | "))
		local hasDrvRow = false
		for _, r in ipairs(rows) do if r.label:find("Getaway pro") then hasDrvRow = true end end
		check(hasDrvRow == hasDriver, tag .. " Driver 'Getaway pro' row " .. (hasDriver and "present" or "absent"))
		check(#rows == (carPct > 0 and 1 or 0) + (heliPct > 0 and 1 or 0) + (drvPct > 0 and 1 or 0), tag .. " " .. #rows .. " getaway rows")
		check(p.target and p.target.amount == 5000, tag .. " target row +$5,000 (" .. tostring(p.target and p.target.name) .. ")")
		local tk = Target:targetFor(plan.job).kind
		check(Data:getData(p1).targetTrophies and Data:getData(p1).targetTrophies[tk] == true and Data:getData(p2).targetTrophies[tk] == true, tag .. " trophy " .. tk .. " saved for both")
		task.wait(1.5)
		local payoutTxt = inClient(function()
			local ps = p1.PlayerGui:FindFirstChild("PayoutScreen")
			local t = {}
			for _, d in ipairs(ps and ps:GetDescendants() or {}) do if d:IsA("TextLabel") and d.Text:find("Getaway pro") then table.insert(t, d.Text) end end
			return (ps and ps.Enabled and "open" or "closed") .. ":" .. table.concat(t, ",")
		end)
		check(tostring(payoutTxt):sub(1, 4) == "open" and (tostring(payoutTxt):find("Getaway pro") ~= nil) == hasDriver, tag .. " PayoutScreen " .. tostring(payoutTxt))
		inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)
		check(waitFor(function() return inClient(function() return not p1:GetAttribute("GetawayPlaying") end) end, 6) ~= nil
			and inClient(function() return WORKSPACE.CurrentCamera.CameraType end) == Enum.CameraType.Custom, tag .. " movie cleaned up, camera back")
		task.wait(3)
		check(#Bots:getBots() == 0, tag .. " bots gone")
		check(not (root(p1) and root(p1).Anchored) and not (root(p2) and root(p2).Anchored), tag .. " nobody left anchored")
		task.wait(Constants.JOB_RESET_COOLDOWN + 1)
		check(JS:getPhase() == "idle" and Loot:counts().loaded == 0 and not Target:isSecured(), tag .. " reset → idle, car empty, target unsecured")
	end

	print("\n==== MINI-GAME TYPES SEEN IN REAL JOBS ====")
	local seen = {}
	for g, n in pairs(gamesSeen) do table.insert(seen, g .. "×" .. n) end
	table.sort(seen)
	check(gamesSeen.cut and gamesSeen.dial and gamesSeen.stuff and gamesSeen.unscrew and gamesSeen.drill, "all 5 mini-games used by real builders: " .. table.concat(seen, " "))
	check(#LOG.errors == errs0, "no runtime errors during the runs (" .. (#LOG.errors - errs0) .. ")")

	print("\n================ V3 INTEGRATION CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 3000)
report()
