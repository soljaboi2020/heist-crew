-- ═══════════════ v3.2 HEIST STARS + HOT STREAK driver ═══════════════
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
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local Data = srv("PlayerDataService")
	local E = srv("EconomyService")
	local PS = srv("PortalService")
	local Constants = mockRequire(REPLICATED.Shared.Constants)
	local store = DataStoreService:GetDataStore("HeistCrewPlayerData_v1")
	local errs0 = #LOG.errors

	print("\n==== CONSTANTS ====")
	check(Constants.STARS and Constants.STARS.PAR.mart == 150 and Constants.STARS.PAR.bank == 420, "STARS.PAR")
	check(Constants.STARS.UNLOCK.villa == 1 and Constants.STARS.UNLOCK.jewelry == 3 and Constants.STARS.UNLOCK.bank == 6 and Constants.STARS.UNLOCK.mart == 0, "STARS.UNLOCK")
	check(Constants.STREAK and Constants.STREAK.MAX == 5 and Constants.STREAK.PER_LEVEL == 0.10, "STREAK")

	print("\n==== NEW PLAYER: saves + locks ====")
	local p1 = addPlayer("Newbie")
	startClient(p1)
	task.wait(3)
	pcall(function() remote("Tutorial").OnServerEvent:Fire(p1, { action = "skip" }) end)
	local d1 = Data:getData(p1)
	check(type(d1.bestStars) == "table" and next(d1.bestStars) == nil and d1.totalStars == 0 and d1.unlockAll == false and d1.streak == 0 and d1.streakAtRisk == false,
		"new save: bestStars {}, totalStars 0, unlockAll false, streak 0")
	check(p1:GetAttribute("Streak") == 0 and p1:GetAttribute("TotalStars") == 0 and p1:GetAttribute("Stars_villa") == 0 and p1:GetAttribute("UnlockAll") == false, "attributes Streak / TotalStars / Stars_<job> / UnlockAll set")
	check(JS:isUnlocked("mart") and not JS:isUnlocked("villa") and not JS:isUnlocked("jewelry") and not JS:isUnlocked("bank"), "only the mart is open for a brand-new player")
	check(JS:starsNeeded("bank") == 6 and JS:starsNeeded("mart") == 0, "JobService:starsNeeded")
	task.wait(2.5)
	local pl = REMOTE_LOG.Portal and REMOTE_LOG.Portal[2]
	local pv = pl and pl.portals and pl.portals.villa
	check(pv and pv.locked == true and pv.starsNeeded == 1 and pl.portals.mart.starsNeeded == 0, "Portal payload: villa locked=true, starsNeeded=1 (" .. tostring(pv and pv.starsNeeded) .. ")")
	local function doorStatus(id)
		local door = WORKSPACE:FindFirstChild("Door_" .. id, true)
		for _, d in ipairs(door and door:GetDescendants() or {}) do
			if d:IsA("TextLabel") and (tostring(d.Text):find("Need") or tostring(d.Text):find("Walk in") or tostring(d.Text):find("progress") or tostring(d.Text):find("player")) then return d.Text end
		end
	end
	check(tostring(doorStatus("bank")):find("Need ⭐ 6") ~= nil, "bank door sign: " .. tostring(doorStatus("bank")))
	check(tostring(doorStatus("mart")):find("Walk in") ~= nil, "mart door sign: " .. tostring(doorStatus("mart")))
	-- cycleJob refuses a star-locked heist
	JS:cycleJob(p1)
	check(JS:getCurrentId() == "mart", "cycleJob stays on the mart (others star-locked)")

	-- client door labels
	local tagged = CollectionService:GetTagged("DoorStars")
	check(#tagged == 4, "4 DoorStars labels on the heist doors (" .. #tagged .. ")")
	local function doorLabel(id)
		return inClient(function()
			for _, l in ipairs(CollectionService:GetTagged("DoorStars")) do
				if l:GetAttribute("JobId") == id then return l.Text end
			end
		end)
	end
	check(tostring(doorLabel("mart")):find("★★★") ~= nil and not tostring(doorLabel("mart")):find("🔥"), "client mart label = 3 empty stars: " .. tostring(doorLabel("mart")))

	-- helpers: a fake loot state + a full run
	local realCounts, realLoaded = Loot.counts, Loot.getLoaded
	local fake = nil
	Loot.counts = function(self)
		local c = realCounts(self)
		if fake then c.total, c.loaded, c.take = fake.total, fake.loaded, fake.take c.allLoaded = fake.loaded >= fake.total end
		return c
	end
	Loot.getLoaded = function(self)
		if not fake then return realLoaded(self) end
		local out = {}
		for i = 1, fake.loaded do out[i] = { kind = "cash", name = "Cash", value = math.floor(fake.take / math.max(1, fake.loaded)) } end
		return out
	end
	local function run(players, opts)
		waitFor(function() return JS:getPhase() == "idle" end, 60, 0.5)
		task.wait(1)
		fake = { total = opts.total or 5, loaded = opts.loaded or 5, take = opts.take or 5000 }
		REMOTE_LOG.HeistState = nil
		JS:startLaunchCountdown(0, function() return players end, "portal")
		waitFor(function() return JS:getPhase() == "running" end, 30)
		for _, p in ipairs(players) do
			if p.Parent then check(Data:getData(p).streakAtRisk == true, "  " .. p.Name .. ": streakAtRisk on during the run") end
		end
		if opts.during then opts.during() end
		if opts.alarm then JS:triggerAlarm("camera", players[1]) end
		task.wait(opts.wait or 20)
		if not opts.fail then JS:beginGetaway("go", players[1]) end
		local done = waitFor(function() local h = REMOTE_LOG.HeistState return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 400, 0.5)
		fake = nil
		return done and done[3], done and done[2]
	end
	local function me(p, payload) return payload and payload.players and payload.players[tostring(p.UserId)] end

	print("\n==== RUN 1: mart, quiet, all loot, fast → ⭐⭐⭐ ====")
	local cash0 = Data:getData(p1).cash
	local pay1, st1 = run({ p1 }, { wait = 20 })
	check(st1 == "COMPLETE", "run 1 COMPLETE")
	local s1 = pay1 and pay1.stars or {}
	check(s1.stealth == true and s1.loot == true and s1.fast == true and s1.count == 3 and s1.par == 150, string.format("stars: stealth=%s loot=%s fast=%s count=%s time=%s", tostring(s1.stealth), tostring(s1.loot), tostring(s1.fast), tostring(s1.count), tostring(s1.time)))
	check((s1.time or 999) >= 19 and (s1.time or 0) <= 25, "⏱ clock stops at the getaway (time " .. tostring(s1.time) .. "s, the movie isn't counted)")
	local m1 = me(p1, pay1) or {}
	check(m1.streakBefore == 0 and m1.streakAfter == 1 and (m1.streakBonus or 0) == 0, "streak 0 → 1, no bonus on the first win")
	check(m1.bestBefore == 0 and m1.bestAfter == 3 and m1.totalStars == 3, "best mart 0 → 3, total 3")
	local lucky1 = math.floor(5000 * 0.1 + 0.5)
	check((Data:getData(p1).cash - cash0 == (m1.pay or -1) + lucky1 or Data:getData(p1).cash - cash0 == m1.pay) and m1.pay == pay1.each, string.format("cash +%d = pay %s (+LUCKY %d)", Data:getData(p1).cash - cash0, tostring(m1.pay), lucky1))
	check(Data:getData(p1).streakAtRisk == false, "streakAtRisk cleared at the finish")
	check(p1:GetAttribute("Streak") == 1 and p1:GetAttribute("Stars_mart") == 3 and p1:GetAttribute("TotalStars") == 3, "attributes updated (Streak 1, Stars_mart 3, TotalStars 3)")
	check(JS:isUnlocked("villa") and JS:isUnlocked("jewelry") and not JS:isUnlocked("bank"), "3 stars → villa + jewelry open, bank still locked")
	-- payout screen (client)
	task.wait(4)
	local ui = inClient(function()
		local P = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen"))
		local u = P._u
		local t = {}
		for k, s in ipairs(u.starSlots) do t[k] = { cap = s.cap.Text, lit = s.star.TextTransparency == 0 } end
		return { stars = t, newBest = u.newBest.Visible, meta = u.meta.Text, cut = u.cut.Text }
	end) or { stars = {} }
	local st = ui.stars
	check(st[1] and st[1].lit and st[2].lit and st[3].lit, "payout: all 3 stars lit")
	check(st[1] and st[1].cap == "Sneaky! No alarm" and st[2].cap == "All the loot!" and tostring(st[3].cap):find("^Fast! 0:2") ~= nil, "payout captions: " .. (st[1] and (st[1].cap .. " | " .. st[2].cap .. " | " .. st[3].cap) or "?"))
	check(ui.newBest == true, "payout: NEW BEST!")
	check(tostring(ui.meta):find("🔥 Streak x1!") ~= nil, "payout meta shows the streak going up: " .. tostring(ui.meta))
	check(tostring(doorLabel("mart")):find("🔥x1") ~= nil and select(2, tostring(doorLabel("mart")):gsub("★", "")) == 3, "door label: " .. tostring(doorLabel("mart")))
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== RUN 2: mart, LOUD, 3/5 bags, fast → ⭐ (fast only), streak bonus x1 ====")
	cash0 = Data:getData(p1).cash
	local pay2, st2 = run({ p1 }, { alarm = true, loaded = 3, take = 3000, wait = 6 })
	check(st2 == "COMPLETE", "run 2 COMPLETE")
	local s2 = pay2 and pay2.stars or {}
	check(s2.stealth == false and s2.loot == false and s2.fast == true and s2.count == 1 and s2.bagsLoaded == 3 and s2.bagsTotal == 5, "stars: alarm ✗, loot ✗ (3/5), fast ✓ → 1")
	local m2 = me(p1, pay2) or {}
	check(m2.streakBefore == 1 and m2.streakAfter == 2 and m2.streakBonus == 300 and m2.streakPct == 10, string.format("streak 1 → 2, bonus +10%% of $3,000 = %s", tostring(m2.streakBonus)))
	check(m2.pay == pay2.each + 300, string.format("pay %s = each %s + 300", tostring(m2.pay), tostring(pay2.each)))
	check(Data:getData(p1).cash - cash0 == m2.pay + 300, "cash = pay + LUCKY")
	check(m2.bestBefore == 3 and m2.bestAfter == 3 and Data:getData(p1).bestStars.mart == 3, "best stays 3 (a worse run never lowers it)")
	task.wait(4)
	local ui2 = inClient(function()
		local P = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen"))
		local u = P._u
		local rows = {}
		for _, r in ipairs(u.list:GetChildren()) do
			if r:IsA("Frame") then
				local t = {}
				for _, d in ipairs(r:GetDescendants()) do if d:IsA("TextLabel") and d.Text ~= "" then table.insert(t, d.Text) end end
				table.insert(rows, table.concat(t, " "))
			end
		end
		return { caps = { u.starSlots[1].cap.Text, u.starSlots[2].cap.Text, u.starSlots[3].cap.Text }, newBest = u.newBest.Visible, rows = rows, cut = u.cut.Text }
	end) or { caps = {}, rows = {} }
	check(ui2.caps[1] == "The alarm went off" and ui2.caps[2] == "Left 2 bags behind", "missed-star reasons: " .. tostring(ui2.caps[1]) .. " | " .. tostring(ui2.caps[2]) .. " | " .. tostring(ui2.caps[3]))
	check(ui2.newBest == false, "no NEW BEST on a worse run")
	local hot = false
	for _, r in ipairs(ui2.rows) do if r:find("HOT STREAK x1") and r:find("%+10%%") then hot = true end end
	check(hot, "payout row 🔥 HOT STREAK x1 +10% (rows: " .. table.concat(ui2.rows, " / ") .. ")")
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== RUN 3: mart, quiet, all loot, SLOW → ⭐⭐ + 'Too slow — beat 2:30' ====")
	local pay3 = run({ p1 }, { wait = 160 })
	local s3 = pay3 and pay3.stars or {}
	check(s3.stealth == true and s3.loot == true and s3.fast == false and s3.count == 2, "stars: stealth ✓ loot ✓ fast ✗ (time " .. tostring(s3.time) .. ")")
	local lines = inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")).starLines(true, s3) end) or {}
	check(lines[3] and lines[3].text == "Too slow — beat 2:30" and lines[3].on == false, "caption: " .. tostring(lines[3] and lines[3].text))
	local m3 = me(p1, pay3) or {}
	check(m3.streakBefore == 2 and m3.streakAfter == 3 and m3.streakBonus == 1000, "streak 2 → 3, bonus 20% of $5,000 = " .. tostring(m3.streakBonus))
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== RUN 4: FAIL (alarm, out of time) → streak -1, no stars ====")
	local pay4, st4 = run({ p1 }, { alarm = true, fail = true, wait = 1 })
	check(st4 == "FAILED", "run 4 FAILED (" .. tostring(pay4 and pay4.result) .. ")")
	local m4 = me(p1, pay4) or {}
	check(pay4 and pay4.stars and pay4.stars.count == 0, "no stars on a fail")
	check(m4.streakBefore == 3 and m4.streakAfter == 2 and m4.bestBefore == nil, "streak 3 → 2 (one level, not zero)")
	local fl = inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")).starLines(false, pay4.stars) end) or {}
	check(fl[1] and fl[1].text == "Get away to earn stars", "fail caption: " .. tostring(fl[1] and fl[1].text))
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== RUN 5: empty car → no stars, streak unchanged ====")
	local pay5 = run({ p1 }, { loaded = 0, take = 0, wait = 10 })
	local m5 = me(p1, pay5) or {}
	check(pay5 and pay5.stars.count == 0 and m5.streakBefore == 2 and m5.streakAfter == 2, "empty car: 0 stars, streak 2 → 2")

	print("\n==== CAP: streak never goes past 5 ====")
	Data:changeStreak(p1, 10)
	check(Data:getStreak(p1) == 5 and p1:GetAttribute("Streak") == 5, "changeStreak clamps to 5")
	local pay6 = run({ p1 }, { wait = 20 })
	local m6 = me(p1, pay6) or {}
	check(m6.streakBefore == 5 and m6.streakAfter == 5 and m6.streakBonus == 2500 and m6.streakPct == 50, "x5 win: stays 5, +50% = " .. tostring(m6.streakBonus))
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== CREW: a teammate left behind (jailed) loses a level; a leaver loses a level ====")
	local p2 = addPlayer("Buddy")
	local p3 = addPlayer("Quitter")
	task.wait(2)
	for _, p in ipairs({ p2, p3 }) do pcall(function() remote("Tutorial").OnServerEvent:Fire(p, { action = "skip" }) end) end
	Data:changeStreak(p2, 3)
	Data:changeStreak(p3, 4)
	local p3id = p3.UserId
	local pay7 = run({ p1, p2, p3 }, { wait = 20, during = function()
		task.wait(2)
		removePlayer(p3)
		task.wait(1)
		JS:catchPlayer(p2, "cop")
		task.wait(1)
	end })
	local m7a, m7b = me(p1, pay7) or {}, me(p2, pay7) or {}
	check(m7a.streakAfter == 5 and m7b.streakBefore == 3 and m7b.streakAfter == 2 and m7b.bestAfter == nil, "escapee keeps x5; jailed teammate 3 → 2 and gets no stars")
	check(me({ UserId = p3id }, pay7) == nil, "the leaver isn't in the payout")
	local saved = store:GetAsync("Player_" .. p3id)
	local eff = saved and ((saved.streak or 0) - (saved.streakAtRisk and 1 or 0))
	check(eff == 3, string.format("leaver's save: streak %s atRisk %s → next load = %s (4 → 3)", tostring(saved and saved.streak), tostring(saved and saved.streakAtRisk), tostring(eff)))
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")):close() end)

	print("\n==== SAVES: migrate + grandfathering + disconnect ====")
	Data:savePlayer(p1)
	local s = store:GetAsync("Player_" .. p1.UserId)
	check(s.bestStars and s.bestStars.mart == 3 and s.totalStars == 3 and s.streak == 5 and s.streakAtRisk == false and s.unlockAll == false, "p1 saved: bestStars.mart 3, totalStars 3, streak 5")
	local base = 5000
	store:SetAsync("Player_" .. (base + 1), { cash = 5000, level = 3, heistsCompleted = 4 })
	store:SetAsync("Player_" .. (base + 2), { cash = 100, level = 1, heistsCompleted = 0 })
	store:SetAsync("Player_" .. (base + 3), { cash = 100, heistsCompleted = 2, bestStars = { villa = 2, mart = 9 }, unlockAll = false, streak = 4, streakAtRisk = true })
	store:SetAsync("Player_" .. (base + 4), { cash = 100, heistsCompleted = 1, bestStars = {}, streak = 1, streakAtRisk = true })
	local function fakeLoad(uid, name)
		local fp = newInstance("Player")
		fp.Name = name
		D[fp].props.UserId = uid
		return fp, Data:loadPlayer(fp)
	end
	local _, vet = fakeLoad(base + 1, "OldVet")
	check(vet.unlockAll == true and vet.streak == 0 and vet.totalStars == 0, "old save with heists → unlockAll (grandfathered)")
	local vp = fakeLoad(base + 1, "OldVet")
	check(Data:canOpen(vp, 6) == true, "grandfathered vet can open the bank")
	local _, nb = fakeLoad(base + 2, "OldNewbie")
	check(nb.unlockAll == false, "old save with 0 heists → not grandfathered")
	local sp, st = fakeLoad(base + 3, "Star")
	check(st.bestStars.mart == 3 and st.bestStars.villa == 2 and st.totalStars == 5 and st.unlockAll == false, "bad star values clamped (mart 9 → 3), total recomputed 5, a stars-era save is never grandfathered")
	check(st.streak == 3 and st.streakAtRisk == false, "saved mid-run (atRisk) → streak 4 → 3 on load")
	check(sp:GetAttribute("Stars_villa") == 2 and sp:GetAttribute("TotalStars") == 5 and sp:GetAttribute("Streak") == 3, "attributes set on load")
	check(Data:canOpen(sp, 3) and not Data:canOpen(sp, 6), "5 stars → can open 3, not 6")
	local _, z = fakeLoad(base + 4, "Zero")
	check(z.streak == 0, "streak 1 + disconnect → 0 (floor, never negative)")
	-- failed load: never locked out
	local realGet = store.GetAsync
	store.GetAsync = function(s2, k) if k == "Player_" .. (base + 9) then error("DataStore down") end return realGet(s2, k) end
	local fp9 = fakeLoad(base + 9, "Unlucky")
	store.GetAsync = realGet
	check(Data:loadFailed(fp9) and Data:canOpen(fp9, 6), "failed load → canOpen (never lock out a save we can't see)")

	print("\n==== SERVER-WIDE LOCK: a grandfathered vet in the server opens every door ====")
	check(not JS:isUnlocked("bank"), "bank locked (nobody in the server has 6 / unlockAll)")
	local p4 = addPlayer("RealVet")   -- uid picks up after the others
	task.wait(1)
	Data:getData(p4).unlockAll = true
	check(JS:isUnlocked("bank"), "with a vet in the server the bank opens")
	waitFor(function() return JS:getPhase() == "idle" end, 60, 0.5)
	task.wait(2.5)
	local pl2 = REMOTE_LOG.Portal and REMOTE_LOG.Portal[2]
	check(pl2 and pl2.portals.bank.locked == false and pl2.portals.bank.starsNeeded == 0, "Portal payload: bank unlocked")
	check(not tostring(doorStatus("bank")):find("Need"), "bank door sign no longer says Need: " .. tostring(doorStatus("bank")))
	local tsLocked = srv("TutorialService")
	check(JS:isUnlocked("mart"), "mart always open (TutorialService relies on it)")

	Loot.counts, Loot.getLoaded = realCounts, realLoaded
	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	for i = errs0 + 1, #LOG.errors do print("   ERR " .. tostring(LOG.errors[i]):sub(1, 400)) end
	print("\n================ STARS + STREAK CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 4000)
report()
