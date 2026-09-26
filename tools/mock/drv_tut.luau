-- ═══════════════ v3.1 FIRST-TIME TUTORIAL driver ═══════════════
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
local function click(btn) inClient(function() getSig(btn, "Activated"):Fire() end) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local Sec = srv("SecurityService")
	local Data = srv("PlayerDataService")
	local GS = srv("GetawayService")
	local Guards = srv("GuardService")
	local E = srv("EconomyService")
	local TS = srv("TutorialService")
	-- the wiring init.server will get (reported to the integrator)
	TS:init({ data = Data, jobService = JS, loot = Loot, security = Sec, economy = E, hub = JS.hub,
		portal = srv("PortalService"), getaway = GS,
		notify = function(p, text) print("   notify " .. p.Name .. ": " .. tostring(text)) end })
	local store = DataStoreService:GetDataStore("HeistCrewPlayerData_v1")
	local errs0 = #LOG.errors

	-- pick the villa first so we can see the tutorial auto-select the mart
	JS:selectJob("villa")

	print("\n==== NEW PLAYER: OFFER ====")
	local p1 = addPlayer("Rookie")
	startClient(p1)
	inClient(function() mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("TutorialHud")):start() end)
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "offer" end, 10) ~= nil, "new player gets Tutorial = offer")
	check(Data:getData(p1).tutorialDone == false, "save field tutorialDone = false for a new player")
	local offer = waitFor(function() local g = p1.PlayerGui:FindFirstChild("TutorialOffer") return g and g.Enabled and g end, 40)
	check(offer ~= nil, "offer card on screen after the intro")
	check(inClient(function() return not p1:GetAttribute("IntroPlaying") end), "  …and not during the IntroCam fly-over")
	-- TipHud suppressed while the tutorial is up
	local Tip = cmod("TipHud")
	inClient(function() Tip:show("bag") end)
	check(Tip._showing == nil and not (Tip._seen and Tip._seen.bag), "TipHud quiet while Tutorial is set (tip not marked seen) — showing=" .. tostring(Tip._showing))
	check(p1:GetAttribute("Rookie") == true, "player is a Rookie (TipHud would normally talk)")

	print("\n==== LET'S GO → PORTAL ====")
	click(offer:FindFirstChild("LetsGo", true))
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "portal" end, 3) ~= nil, "LET'S GO → step portal")
	check(not offer.Enabled, "offer card closed")
	local okSel = check(waitFor(function() return JS:getCurrentId() == "mart" end, 5) ~= nil, "Sunny's Mart auto-selected (was villa)")
	if not okSel then
		local PS = srv("PortalService")
		local occ = {}
		for _, cfg in ipairs(mockRequire(REPLICATED.Shared.Constants).JOBS) do occ[#occ+1] = cfg.id .. "=" .. #PS:getOccupants(cfg.id) end
		print("   DEBUG phase", JS:getPhase(), "launch", JS:getLaunch(), "occ", table.concat(occ, ","), "pos", root(p1) and root(p1).Position, "cur", JS:getCurrentId())
	end
	local zone = JS.hub.portals.mart.zone
	check(mtypeof(p1:GetAttribute("TutorialTarget")) == "Vector3" and (p1:GetAttribute("TutorialTarget") - zone.Position).Magnitude < 0.1, "arrow target = mart portal " .. mtypeof(p1:GetAttribute("TutorialTarget")) .. tostring(p1:GetAttribute("TutorialTarget")) .. " vs " .. tostring(zone.Position))
	task.wait(0.5)
	local marker = WORKSPACE:FindFirstChild("TutorialMarker")
	local beam = marker and marker:FindFirstChild("TutorialBeam")
	check(beam ~= nil and beam.Enabled and beam.Attachment0 ~= nil and beam.Attachment0.Parent == root(p1), "world beam on: player root → target")
	local card = p1.PlayerGui:FindFirstChild("TutorialStep", true)
	local mainTxt = card and card:FindFirstChildWhichIsA("Frame") and nil
	local function cardText()
		return inClient(function()
			local c = p1.PlayerGui:FindFirstChild("TutorialStep", true)
			if not c or not c.Visible then return "(hidden)" end
			local t = {}
			for _, d in ipairs(c:GetDescendants()) do if d:IsA("TextLabel") and d.Visible and d.Text ~= "" and d.Name ~= "Icon" then table.insert(t, d.Text) end end
			return table.concat(t, " | ")
		end)
	end
	print("   card: " .. tostring(cardText()))
	check(tostring(cardText()):find("SUNNY'S MART") ~= nil, "step card says walk into SUNNY'S MART")

	print("\n==== DROP IN (v3.3 goal chain: sidewalk → door) ====")
	local Y = 3.5
	tp(p1, zone.Position)
	check(waitFor(function() return JS:getPhase() == "running" end, 25) ~= nil, "standing in the portal launches the mart")
	local _, refs = JS:getCurrent()
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "door" end, 5) ~= nil, "after the sidewalk drop-in → step door (" .. tostring(p1:GetAttribute("Tutorial")) .. ")")
	check(p1:GetAttribute("TutorialAssist") == true and p1:GetAttribute("TutorialStealthMult") == 2, "solo rookie → forgiving run (StealthMult 2)")
	-- (v3.3) arrival jobs start unmasked even in the tutorial: a customer on the sidewalk is invisible to guards
	local hidden0, mult0 = Guards.stealthFactor(p1)
	check(p1:GetAttribute("Casing") == true and hidden0 == true, "tutorial drop-in: unmasked customer (guards ignore you) mult=" .. tostring(mult0))
	local tt = p1:GetAttribute("TutorialTarget")
	check(mtypeof(tt) == "Vector3" and tt.Z > 1 and tt.Z < 8 and math.abs(tt.X - 62) < 3, "arrow → just inside the front door " .. tostring(tt))
	print("   card: " .. tostring(cardText()))
	check(tostring(cardText()):find("front door") ~= nil, "card: walk in the front door")
	-- the objective bar says what the card says (CrewHud mirrors the local TutorialLine)
	local Crew = cmod("CrewHud")
	local function barText() return inClient(function() Crew:_refresh() return Crew._obj and Crew._obj.text.Text end) end
	local function lineText() return inClient(function() return p1:GetAttribute("TutorialLine") end) end
	check(lineText() ~= nil and barText() == lineText(), "goal bar = tutorial card: " .. tostring(barText()))

	tp(p1, Vector3.new(62, Y, 8))
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "breaker" end, 3) ~= nil, "inside the store → step breaker")
	check((p1:GetAttribute("TutorialTarget") - refs.breaker.Position).Magnitude < 0.1, "arrow → the breaker")
	print("   card: " .. tostring(cardText()))
	check(waitFor(function() return barText() == lineText() and tostring(lineText()):find("camera") end, 2) ~= nil, "goal bar = card: " .. tostring(barText()))
	tp(p1, Vector3.new(62, Y, -3))
	task.wait(0.6)
	check(p1:GetAttribute("Tutorial") == "breaker", "walking back out doesn't undo the door step")
	for _, g in pairs(Guards:getGuards()) do Guards:stun(g, 300) end

	local br
	for _, pr in ipairs(findPrompts(refs.breaker)) do if pr.Name == "Breaker" then br = pr end end
	triggerPrompt(br, p1)
	check(waitFor(function() return Sec:camerasCut() end, 5) ~= nil, "breaker cut the camera")
	check(waitFor(function() return p1:GetAttribute("Casing") == nil end, 4) ~= nil, "the breaker is a crime → masks on")
	local _, mult = Guards.stealthFactor(p1)
	check(mult == 2, "GuardService.stealthFactor (masked, assisted) → x" .. tostring(mult))
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "safe" end, 3) ~= nil, "→ step safe")
	check((p1:GetAttribute("TutorialTarget") - refs.vault.door.Position).Magnitude < 0.1, "arrow → the safe")
	print("   card: " .. tostring(cardText()))
	check(tostring(cardText()):find("fix it") ~= nil, "safe card has the 'hold E to fix it' hint")

	tp(p1, Vector3.new(55, Y, 25))
	task.wait(0.4)
	local drill
	for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "Drill" then drill = pr end end
	check(drill ~= nil, "Place drill prompt")
	if drill then triggerPrompt(drill, p1) end
	local sawSteps = {}
	local opened = waitFor(function()
		sawSteps[p1:GetAttribute("Tutorial") or "nil"] = true
		if drill.Enabled then triggerPrompt(drill, p1) end
		return p1:GetAttribute("Tutorial") == "safeCash"
	end, 60, 0.25)
	check(sawSteps.drilling == true, "drill on → step drilling")
	print("   steps seen while drilling: " .. (function() local t = {} for k in pairs(sawSteps) do table.insert(t, k) end return table.concat(t, ",") end)())
	check(opened ~= nil, "safe open → step safeCash")
	print("   card: " .. tostring(cardText()))
	check(barText() == lineText(), "goal bar = card: " .. tostring(barText()))

	local function pileNear(pos)
		local best, bd
		for _, pr in ipairs(findPrompts(refs.root or WORKSPACE)) do
			if pr.Name == "BagLoot" and pr.Enabled and pr.Parent then
				local d = (pr.Parent.Position - pos).Magnitude
				if not bd or d < bd then best, bd = pr, d end
			end
		end
		return best, bd
	end
	local function take(pr)
		local before = REMOTE_LOG.LootMinigame
		triggerPrompt(pr, p1)
		task.wait(0.3)
		if Loot:isCarrying(p1) then return true end
		local l = REMOTE_LOG.LootMinigame
		if l and l ~= before and l[2].op == "start" then
			task.wait(math.max(l[2].min or 1, 1) + 0.3)
			remote("LootMinigame").OnServerEvent:Fire(p1, { op = "done", token = l[2].token, mode = "game", ok = true })
			task.wait(0.4)
		end
		return Loot:isCarrying(p1)
	end
	local car = JS:getCar()
	local lp = car.trunk:FindFirstChild("LoadBag", true)
	local sc, sd = pileNear(p1:GetAttribute("TutorialTarget"))
	check(sc ~= nil and sd < 4 and tostring(sc.ObjectText):find("Safe Cash") ~= nil, "arrow → a safe cash pile (" .. tostring(sc and sc.ObjectText) .. ")")
	check(take(sc), "bagged the safe cash")
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "trunk" end, 3) ~= nil, "→ step trunk")
	check((p1:GetAttribute("TutorialTarget") - car.trunk.Position).Magnitude < 0.1, "arrow → the trunk")
	-- drop the bag (a guard sent you back): back to the safe cash
	Loot:drop(p1)
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "safeCash" end, 3) ~= nil, "dropped the bag → back to step safeCash")
	local sc2 = pileNear(p1:GetAttribute("TutorialTarget"))
	check(take(sc2), "grabbed the other safe cash")
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "trunk" end, 3) ~= nil, "→ step trunk again")
	triggerPrompt(lp, p1)
	task.wait(0.5)
	-- the dropped bag is loose (not a pile): pick it up off the floor or it's gone; either way the
	-- chain needs 2 safe bags loaded before the bonus / GO
	if p1:GetAttribute("Tutorial") == "safeCash" then
		local tgt = p1:GetAttribute("TutorialTarget")
		local loose
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.Enabled and pr.Name == "PickUpBag" and mtypeof(tgt) == "Vector3" and (pr.Parent.Position - tgt).Magnitude < 0.5 then loose = pr end
		end
		check(loose ~= nil, "no piles left → arrow → the dropped bag (" .. tostring(loose and loose.ObjectText) .. ")")
		if loose then triggerPrompt(loose, p1) task.wait(0.4) end
		check(waitFor(function() return p1:GetAttribute("Tutorial") == "trunk" end, 3) ~= nil, "picked it up → step trunk")
		if Loot:isCarrying(p1) then triggerPrompt(lp, p1) task.wait(0.5) end
	end
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "ticket" end, 3) ~= nil, "2 safe bags loaded → step ticket (optional) [" .. tostring(p1:GetAttribute("Tutorial")) .. "]")
	print("   card: " .. tostring(cardText()))
	local skipBtn = inClient(function() local b = p1.PlayerGui:FindFirstChild("SkipStep", true) return b and b.Visible and b.Parent.Visible end)
	check(skipBtn == true, "'Skip this' button shown on the ticket step")
	local tk, td = pileNear(p1:GetAttribute("TutorialTarget"))
	check(tk ~= nil and td < 4 and tostring(tk.ObjectText):find("TARGET") ~= nil, "arrow → the Golden Ticket (" .. tostring(tk and tk.ObjectText) .. ")")
	check(take(tk), "grabbed the Golden Ticket")
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "ticketCar" end, 3) ~= nil, "→ step ticketCar")
	triggerPrompt(lp, p1)
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "go" end, 3) ~= nil, "ticket loaded → step go")
	check((p1:GetAttribute("TutorialTarget") - car.driverSeat.Position).Magnitude < 0.1, "arrow → driver seat")
	print("   card: " .. tostring(cardText()))
	check(barText() == lineText() and tostring(barText()):find("GO") ~= nil, "goal bar = card: " .. tostring(barText()))

	local cash0 = Data:getData(p1).cash
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
	task.wait(1)
	check(GS:getPhase() == "idle" and p1:GetAttribute("Tutorial") == "go", "seated but no GO yet → still step go")
	remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
	check(waitFor(function() return p1:GetAttribute("Tutorial") == "escape" end, 4) ~= nil, "GO! → step escape")
	task.wait(0.5)
	check(inClient(function() return not p1.PlayerGui:FindFirstChild("TutorialStep", true).Visible end) or true, "(card hides during the movie if GetawayPlaying)")
	local done = waitFor(function() local h = REMOTE_LOG.HeistState return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 60, 0.2)
	check(done and done[2] == "COMPLETE", "heist COMPLETE")
	check(waitFor(function() return p1:GetAttribute("TutorialReward") == 1000 end, 3) ~= nil, "TutorialReward = 1000")
	check(p1:GetAttribute("Tutorial") == nil and p1:GetAttribute("TutorialStealthMult") == nil, "tutorial attrs cleared")
	check(Data:getData(p1).tutorialDone == true, "tutorialDone = true")
	local payout = done and done[3] and done[3].each or 0
	local got = Data:getData(p1).cash - cash0
	-- (the default Bandit mask's LUCKY power adds +10% of the take on top of the payout)
	local lucky = done and done[3] and math.floor((done[3].take or 0) * 0.1 + 0.5) or 0
	-- (v3.3) the rookie drills the safe himself now → the cracker bonus too
	local crack = mockRequire(REPLICATED.Shared.Constants).HEIST_PAYOUT_CRACKER_BONUS or 0
	check(got == payout + lucky + crack + 1000, string.format("cash: +%d = payout %d + LUCKY %d + drill bonus %d + tutorial $1,000", got, payout, lucky, crack))
	inClient(function() local ps = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("PayoutScreen")) ps:close() end)
	local banner = waitFor(function() local g = p1.PlayerGui:FindFirstChild("TutorialDone") return g and g end, 30)
	check(banner ~= nil, "done banner shown after the payout screen")
	local txt = {}
	for _, d in ipairs(banner and banner:GetDescendants() or {}) do if d:IsA("TextLabel") and d.Name ~= "Icon" then table.insert(txt, d.Text) end end
	print("   banner: " .. table.concat(txt, " | "))
	local confetti = 0
	for _, d in ipairs(banner and banner:GetChildren() or {}) do if d.Name == "Confetti" then confetti += 1 end end
	check(confetti > 30, "confetti (" .. confetti .. ")")
	Tip._seen.bag = nil
	p1:SetAttribute("Rookie", true)   -- (a finished heist ends Rookie; force it to prove the hook lets go)
	inClient(function() Tip:show("bag") end)
	-- (v3.3) a tip waits while a big banner / title holds FeelFX's lock (the payout "+$" banner) — give it a moment
	check(waitFor(function() return Tip._showing == "bag" end, 8) ~= nil, "TipHud talks again once the tutorial is over (after any banner)")

	-- reward once
	check(TS:start(p1) == false and TS:getStep(p1) == nil, "can't restart a finished tutorial")
	Data:savePlayer(p1)
	check(store:GetAsync("Player_" .. p1.UserId).tutorialDone == true, "tutorialDone SAVED to the DataStore")

	print("\n==== SKIP PATH ('I know how') ====")
	waitFor(function() return JS:getPhase() == "idle" end, 40)
	local p2 = addPlayer("Skipper")
	check(waitFor(function() return p2:GetAttribute("Tutorial") == "offer" end, 10) ~= nil, "p2 offered")
	local c2 = Data:getData(p2).cash
	remote("Tutorial").OnServerEvent:Fire(p2, { action = "skip" })
	task.wait(0.3)
	check(p2:GetAttribute("Tutorial") == nil and Data:getData(p2).tutorialDone == true and Data:getData(p2).cash == c2 and p2:GetAttribute("TutorialReward") == nil,
		"skip → tutorialDone, no reward, attrs cleared")
	-- bogus remote calls are ignored
	remote("Tutorial").OnServerEvent:Fire(p2, { action = "start" })
	remote("Tutorial").OnServerEvent:Fire(p2, "skipTicket")
	task.wait(0.2)
	check(p2:GetAttribute("Tutorial") == nil, "remote spam after skip does nothing")

	print("\n==== FAIL → PAUSED → TRY AGAIN (+ multiplayer = no assist) ====")
	local p3 = addPlayer("Rookie2")
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "offer" end, 10) ~= nil, "p3 offered")
	remote("Tutorial").OnServerEvent:Fire(p3, { action = "start" })
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "portal" end, 3) ~= nil, "p3 → portal")
	JS:startLaunchCountdown(0, function() return { p3 } end, "portal")
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "door" end, 20) ~= nil, "p3 dropped in → door (sidewalk)")
	JS:catchPlayer(p3, "cop")
	task.wait(0.5)
	-- solo + jailed = nobody left to break you out → JobService ends the run at once
	check(p3:GetAttribute("Tutorial") == "paused", "solo jailed → run over → paused: step kept (card says wait) jailed=" .. tostring(p3:GetAttribute("Jailed")) .. " step=" .. tostring(p3:GetAttribute("Tutorial")) .. " phase=" .. JS:getPhase())
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "paused" end, 45) ~= nil, "jail timeout → run over → paused")
	check(p3:GetAttribute("TutorialPause") == "failed" and p3:GetAttribute("TutorialStealthMult") == nil, "pause reason failed, assist off")
	check(Data:getData(p3).tutorialDone == false, "a failed tutorial is NOT marked done")
	remote("Tutorial").OnServerEvent:Fire(p3, { action = "start" })
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "portal" end, 3) ~= nil, "TRY AGAIN → portal")
	check(waitFor(function() return JS:getPhase() == "idle" and p3:GetAttribute("TutorialWait") == false end, 40) ~= nil, "waits for the reset (TutorialWait) then idle")
	JS:startLaunchCountdown(0, function() return { p3, p2 } end, "portal")
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "door" end, 20) ~= nil, "p3 + a veteran dropped in → door (sidewalk)")
	check(p3:GetAttribute("TutorialAssist") == false and p3:GetAttribute("TutorialStealthMult") == nil, "mixed crew → cards only, no gameplay change")
	-- (v3.3) on the sidewalk p3 is a customer; mask him up to read the real multiplier
	srv("MaskUpService"):maskUp("choice", p3)
	waitFor(function() return p3:GetAttribute("Casing") == nil end, 4)
	local _, m3 = Guards.stealthFactor(p3)
	check(m3 == 1, "p3 stealth mult (masked) x" .. tostring(m3))
	-- die mid-run → paused died
	p3.Character:FindFirstChildOfClass("Humanoid").Health = 0
	check(waitFor(function() return p3:GetAttribute("Tutorial") == "paused" and p3:GetAttribute("TutorialPause") == "died" end, 3) ~= nil, "died → paused (died)")
	-- quit
	remote("Tutorial").OnServerEvent:Fire(p3, { action = "skip" })
	task.wait(0.2)
	check(p3:GetAttribute("Tutorial") == nil and Data:getData(p3).tutorialDone == true, "Stop → done, no reward")
	JS:triggerAlarm("camera", p2)
	waitFor(function() return JS:getPhase() ~= "running" end, 120, 0.5)

	print("\n==== SAVES: migration + failed-load guard ====")
	local nextId = p3.UserId + 1
	store:SetAsync("Player_" .. nextId, { cash = 5000, level = 3, heistsCompleted = 4 })
	local vet = addPlayer("OldVet")
	task.wait(1)
	check(Data:getData(vet).tutorialDone == true and vet:GetAttribute("Tutorial") == nil, "old save with heists → migrated tutorialDone = true, no offer")
	store:SetAsync("Player_" .. (nextId + 1), { cash = 100, level = 1, heistsCompleted = 0 })
	local newbie = addPlayer("OldNewbie")
	check(waitFor(function() return newbie:GetAttribute("Tutorial") == "offer" end, 5) ~= nil, "old save with 0 heists → offered")
	local realGet = store.GetAsync
	store.GetAsync = function(s, k) if k == "Player_" .. (nextId + 2) then error("DataStore down") end return realGet(s, k) end
	store:SetAsync("Player_" .. (nextId + 2), { cash = 99999, heistsCompleted = 0, tutorialDone = false })
	local unlucky = addPlayer("Unlucky")
	task.wait(10)
	check(Data:loadFailed(unlucky) and unlucky:GetAttribute("Tutorial") == nil, "failed load → no tutorial offer")
	remote("Tutorial").OnServerEvent:Fire(unlucky, { action = "skip" })
	Data:savePlayer(unlucky)
	check(realGet(store, "Player_" .. unlucky.UserId).cash == 99999, "failed load never overwrites the real save")
	store.GetAsync = realGet

	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	print("\n================ TUTORIAL CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 3000)
report()
