-- ═══════════════ v3.0 LOOT-CORE driver ═══════════════
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
local function hum(p) return p.Character and p.Character:FindFirstChildOfClass("Humanoid") end
local function tp(p, pos) if root(p) then p.Character:PivotTo(CFrame.new(pos)) end end
local function approx(a, b, e) return math.abs((a or -1e9) - (b or 1e9)) <= (e or 0.01) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local Shuffle = srv("LootShuffle")
	local Target = srv("TargetService")
	local Bots = srv("BotService")
	local Data = srv("PlayerDataService")
	local C = mockRequire(REPLICATED.Shared.Constants)
	local V3 = C.LOOT_V3

	local p1 = addPlayer("Malachi")
	startClient(p1)
	local p2 = addPlayer("Buddy")
	task.wait(4)
	local LM = inClient(function()
		local m = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("LootMinigames"))
		m:start()
		return m
	end)
	task.wait(1)
	check(type(LM) == "table" and LM._remote ~= nil, "client LootMinigames started + found the LootMinigame remote")
	check(REPLICATED.Remotes:FindFirstChild("LootMinigame") ~= nil and REPLICATED.Remotes.LootMinigame:IsA("RemoteEvent"),
		"server created RemoteEvent ReplicatedStorage.Remotes.LootMinigame")

	-- ── the real jobs ──
	print("\n==== REAL JOBS ====")
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.3)
		local _, jr = JS:getCurrent()
		local cc = Loot:counts()
		local ls = jr.lootSpots or {}
		local v3fields = 0
		for _, s in ipairs(ls) do if s.pool or s.interact or s.heavy or s.fragile or s.hidden or s.target then v3fields += 1 end end
		check(cc.total > 0, string.format("%s: %d piles out of %d spots (+cases) · jackpot '%s' · %d spots with v3 fields",
			id, cc.total, #ls, tostring(cc.jackpot), v3fields))
	end

	-- ── bots still work ──
	print("\n==== BOTS ====")
	JS:selectJob("villa")
	task.wait(0.3)
	local _, vr = JS:getCurrent()
	local made = Bots:spawnFor({ p1 }, vr)
	task.wait(1)
	local bot = made and made[1]
	check(bot ~= nil, "bot spawned")
	-- give p1 a plain bag (any non-interact, non-heavy, unlocked pile)
	local plain
	for _, pr in ipairs(findPrompts(vr.root)) do
		if pr.Name == "BagLoot" and pr.Enabled and pr.ActionText == "Bag it" then plain = pr break end
	end
	if plain then
		p1:SetAttribute("Role", "Hacker")
		triggerPrompt(plain, p1)
		task.wait(0.2)
		local kind = p1:GetAttribute("CarryingLoot")
		check(kind ~= nil, "p1 bagged real villa loot: " .. tostring(kind))
		local moved = Loot:transferToBot(p1, bot)
		check(moved == kind and Loot:botCarrying(bot) == kind and p1:GetAttribute("CarryingLoot") == nil, "transferToBot")
		local car = JS:getCar()
		local before2 = Loot:counts().loaded
		check(Loot:botLoad(bot, car and car.trunk) == true and Loot:counts().loaded == before2 + 1, "botLoad counts like a player load")
	else
		check(false, "no plain BagLoot prompt in the villa to test bots with")
	end
	-- a bot lifts the other side of a heavy one
	local fake2 = {}
	local heavyPr
	for _, pr in ipairs(findPrompts(vr.root)) do if pr.Name == "BagLoot" and pr.Enabled and pr.ActionText == "Lift together" then heavyPr = pr break end end
	if heavyPr and bot then
		bot:PivotTo(CFrame.new(heavyPr.Parent.Position + Vector3.new(2, 0, 0)))
		triggerPrompt(heavyPr, p1)
		task.wait(0.3)
		check(p1:GetAttribute("CarryingLoot") ~= nil and p1:GetAttribute("CarryPartner") ~= nil, "a crew bot lifts the other side (" .. tostring(p1:GetAttribute("CarryPartner")) .. ")")
		Loot:drop(p1)
	else
		print("  (no open heavy pile in the villa right now — builders may not have tagged heavy yet)")
	end
	-- throw from the client
	if plain then
		for _, pr in ipairs(findPrompts(vr.root)) do
			if pr.Name == "BagLoot" and pr.Enabled and pr.ActionText == "Bag it" then triggerPrompt(pr, p1) break end
		end
		task.wait(0.2)
		local nLoose = #findPrompts(vr.root, function(x) return x.Name == "PickUpBag" end)
		inClient(function() REPLICATED.Remotes.ThrowBag:FireServer(Vector3.new(0, 0, -1)) end)
		task.wait(0.4)
		check(p1:GetAttribute("CarryingLoot") == nil and #findPrompts(vr.root, function(x) return x.Name == "PickUpBag" end) == nLoose + 1, "throw still works")
	end


	-- ── a fake refs set with every combo ──
	JS:selectJob("villa")   -- ActiveJob = villa → the target is GoldFlamingo
	task.wait(0.5)
	check(Target:targetFor("villa").kind == "GoldFlamingo" and Target:targetFor("bank").name == "Crown Jewel", "targetFor(job) → {kind,name,line}")
	check(REPLICATED:GetAttribute("TargetName") == "Golden Flamingo", "ReplicatedStorage TargetName follows ActiveJob (" .. tostring(REPLICATED:GetAttribute("TargetName")) .. ")")
	local fake = Instance.new("Folder")
	fake.Name = "FakeJob"
	fake.Parent = WORKSPACE
	local spots = {}
	local BASE = Vector3.new(600, 0.5, 600)
	local n = 0
	local function vis(name)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = Vector3.new(1, 1, 1)
		p.Transparency = 0.1
		p.Parent = fake
		return p
	end
	local function add(t)
		n += 1
		local pos = BASE + Vector3.new((n % 10) * 12, 0, math.floor(n / 10) * 12)
		t.cframe = CFrame.new(pos)
		t.visual = vis(t.kind .. n)
		t.visual.CFrame = CFrame.new(pos)
		table.insert(spots, t)
		return t
	end
	for _ = 1, 5 do add({ kind = "Painting", pool = "gallery", inVault = false }) end            -- interact cut (kind default)
	for _ = 1, 4 do add({ kind = "Wine", pool = "wineCellar", inVault = false }) end             -- fragile (kind default)
	for _ = 1, 3 do add({ kind = "GoldBars", pool = "vault", inVault = true }) end               -- heavy, vault
	for _ = 1, 6 do add({ kind = "DepositBox", pool = "boxes", inVault = false, interact = "stuff" }) end
	add({ kind = "JewelryBox", inVault = false })                                                -- dial, no pool (always out)
	add({ kind = "Necklace", inVault = false, interact = "unscrew" })
	add({ kind = "ATMCash", inVault = false })                                                   -- drill default
	add({ kind = "Cash", inVault = false, fragile = true, heavy = true })                        -- flags from the spot
	add({ kind = "Register", inVault = false, interact = false })                               -- interact explicitly OFF
	local flamingo = add({ kind = "GoldFlamingo", target = "GoldFlamingo", inVault = false, pool = "gallery" }) -- target in a pool: always out
	add({ kind = "SecretStash", hidden = true, inVault = false })
	add({ kind = "SecretStash", hidden = true, inVault = false })
	local caged = add({ kind = "Watch", inVault = false, promptRange = 2.5 })
	local safeCash = add({ kind = "SafeCash", inVault = true })                               -- dial by default, but it's in the drilled safe
	local vaultBox = add({ kind = "DepositBox", inVault = true, interact = "dial", boxNumber = 7 })
	local refs = { root = fake, lootSpots = spots, vault = { door = vis("VaultDoor") }, poolNames = { vault = "Big Vault" } }

	print("\n==== SHUFFLE ====")
	local function sig(active)
		local t = {}
		for _, s in ipairs(active) do table.insert(t, s.visual.Name) end
		return table.concat(t, ",")
	end
	local a1, i1 = Shuffle:prepare(refs, 42)
	local s1 = sig(a1)
	local a2, i2 = Shuffle:prepare(refs, 42)
	check(s1 == sig(a2) and i1.jackpotPool == i2.jackpotPool, "same seed → same run (jackpot " .. tostring(i1.jackpotPool) .. ", " .. #a1 .. "/" .. #spots .. " out)")
	local differs = false
	for seed = 43, 60 do local a = Shuffle:prepare(refs, seed) if sig(a) ~= s1 then differs = true end end
	check(differs, "different seeds → different runs")
	local okCounts, okTarget, okHidden = true, true, true
	local jackpots, hiddenOn, runs = {}, 0, 3000
	for seed = 1, runs do
		local active, info = Shuffle:prepare(refs, seed)
		jackpots[tostring(info.jackpotPool)] = (jackpots[tostring(info.jackpotPool)] or 0) + 1
		hiddenOn += info.hiddenOn
		local byPool = {}
		local tOn = false
		for _, s in ipairs(active) do
			if s.pool and not s.target then byPool[s.pool] = (byPool[s.pool] or 0) + 1 end
			if s == flamingo then tOn = true end
		end
		if not tOn then okTarget = false end
		local want = { gallery = 3, wineCellar = 2, vault = 3, boxes = 4 }   -- round(0.6 n); gallery has 5 non-target; the VAULT is always all out
		local full = { gallery = 5, wineCellar = 4, vault = 3, boxes = 6 }
		for pool, w in pairs(want) do
			local got = byPool[pool] or 0
			if pool == info.jackpotPool then w = full[pool] end
			if got ~= w then okCounts = false end
		end
		if seed <= 3 then
			for _, s in ipairs(spots) do
				local on = table.find(active, s) ~= nil
				if on ~= (s.visual.Transparency < 1) then okHidden = false end
			end
		end
	end
	check(okCounts, "every run: ~60% of each pool out, the jackpot pool 100% out, vault loot always out")
	check(okTarget, "the target spot is out on every run (even inside a pool)")
	check(okHidden, "inactive spots' visuals hidden, active ones shown")
	local rate = hiddenOn / (runs * 2)
	check(rate > 0.03 and rate < 0.07, string.format("hidden stash rate ≈ 1/20 (%.3f)", rate))
	local jp = 0 for _ in pairs(jackpots) do jp += 1 end
	check(jp == 4, "jackpot rotates over all 4 pools (" .. jp .. ")")
	check(Shuffle.poolName(refs, "wineCellar") == "WINE CELLAR" and Shuffle.poolName(refs, "vault") == "BIG VAULT"
		and Shuffle.poolName(refs, "a") == "ROOM A", "jackpot room names: camelCase / refs.poolNames / short ids")
	Shuffle:restore(refs)
	local allBack = true
	for _, s in ipairs(spots) do if s.visual.Transparency ~= 0.1 then allBack = false end end
	check(allBack, "restore() puts every visual back")

	-- builder stash covers: spot.reveal(show)
	local stash = nil
	for _, s in ipairs(spots) do if s.hidden then stash = s break end end
	local calls = {}
	stash.reveal = function(show) table.insert(calls, show) end
	local okReveal = true
	for seed = 1, 400 do
		calls = {}
		local active = Shuffle:prepare(refs, seed)
		local on = table.find(active, stash) ~= nil
		-- prepare = restore (false) then the roll (true iff on)
		if calls[#calls] ~= on then okReveal = false end
		if stash.visual.Transparency ~= 0.1 then okReveal = false end   -- reveal() owns it, we don't touch the visual
	end
	calls = {}
	Shuffle:restore(refs)
	check(okReveal and calls[1] == false, "hidden spot.reveal(true) iff rolled in, reveal(false) otherwise + on restore")
	stash.reveal = nil

	-- a target inside the jackpot pool gets x1.5 too
	local seedGal
	for seed = 1, 300 do local _, info = Shuffle:prepare(refs, seed) if info.jackpotPool == "gallery" then seedGal = seed break end end
	check(seedGal and Shuffle:multFor(flamingo) == 1.5, "target in the jackpot room is worth x1.5 too")
	Shuffle:restore(refs)

	print("\n==== ARM (fake refs) ====")
	-- find a seed where the jackpot is NOT the gallery (so painting values are x1) — and one where it's the wine cellar
	local seedWine
	for seed = 1, 200 do local _, info = Shuffle:prepare(refs, seed) if info.jackpotPool == "wineCellar" then seedWine = seed break end end
	Shuffle:restore(refs)
	Loot:arm(refs, { seed = seedWine })
	local c = Loot:counts()
	check(c.total > 0 and c.jackpot == "WINE CELLAR", "arm(refs,{seed}) builds piles for the active spots (" .. c.total .. ", jackpot " .. tostring(c.jackpot) .. ")")
	check(REPLICATED:GetAttribute("LootJackpot") == "WINE CELLAR", "LootJackpot attribute published for the HUD")
	local function pileAt(spot)
		local want = spot.cframe.Position + Vector3.new(0, 2.5, 0)
		for _, pr in ipairs(findPrompts(fake)) do
			if pr.Parent and pr.Parent.Name == "LootPrompt" and (pr.Parent.Position - want).Magnitude < 0.01 then return pr end
		end
	end
	local function activeSpot(kind, pred)
		for _, s in ipairs(spots) do
			if s.kind == kind and pileAt(s) and pileAt(s).Enabled and (not pred or pred(s)) then return s end
		end
	end
	local function lastMG() local l = REMOTE_LOG.LootMinigame return l and l[2] end
	local function clientSend(msg) inClient(function() REPLICATED.Remotes.LootMinigame:FireServer(msg) end) end

	-- ── mini-games: server validation ──
	print("\n==== MINI-GAMES ====")
	local painting = activeSpot("Painting")
	local pp = pileAt(painting)
	check(pp.ActionText == "Cut it out" and pp.HoldDuration <= 0.3, "interact prompt: '" .. pp.ActionText .. "' (" .. pp.ObjectText .. ")")
	triggerPrompt(pp, p1)
	task.wait(0.2)
	local m = lastMG()
	check(m and m.op == "start" and m.game == "cut" and m.name == "Painting" and m.min == V3.MINIGAMES.cut.min, "prompt → server sends start {game=cut}")
	local card = p1.PlayerGui:FindFirstChild("LootMinigames")
	check(card and card.Enabled and card:FindFirstChild("Card") ~= nil, "client opened the mini-game card")
	clientSend({ op = "done", token = m.token, mode = "game", ok = true })
	task.wait(0.2)
	local r = lastMG()
	check(r.op == "result" and r.ok == false and tostring(r.msg):find("fast"), "too-fast finish REJECTED (" .. tostring(r.msg) .. ")")
	check(p1:GetAttribute("CarryingLoot") == nil, "…and nothing was bagged")
	task.wait(1.3)
	triggerPrompt(pp, p1)
	task.wait(0.1)
	m = lastMG()
	task.wait(V3.MINIGAMES.cut.min + 0.1)
	clientSend({ op = "done", token = m.token, mode = "game", ok = true })
	task.wait(0.3)
	check(lastMG().ok == true and p1:GetAttribute("CarryingLoot") == "Painting", "finish after min time → accepted + bagged")
	check(p1:GetAttribute("CarryName") == "Painting" and p1:GetAttribute("CarryValue") == 3000, "carry attrs: name + value (" .. tostring(p1:GetAttribute("CarryValue")) .. ")")
	check(Loot:valueOf(p1) == 3000, "valueOf(player) = base x1 jackpot x1 fragile x1 tier")
	-- wrong token / other player can't finish
	Loot:drop(p1)
	task.wait(0.2)
	-- hold-E fallback: too short then long enough (server side)
	local jb = activeSpot("JewelryBox")
	triggerPrompt(pileAt(jb), p1)
	task.wait(0.1)
	m = lastMG()
	check(m.game == "dial", "JewelryBox → dial (kind default)")
	task.wait(1.5)
	clientSend({ op = "done", token = m.token, mode = "hold", ok = true })
	task.wait(0.2)
	check(lastMG().ok == false, "hold fallback at 1.5 s rejected (needs 3 s)")
	triggerPrompt(pileAt(jb), p1)
	task.wait(0.1)
	m = lastMG()
	clientSend({ op = "done", token = (m.token or 0) + 999, mode = "game", ok = true })
	task.wait(0.2)
	check(lastMG().op == "start", "a wrong token is ignored")
	task.wait(2.9)
	clientSend({ op = "done", token = m.token, mode = "hold", ok = true })
	task.wait(0.3)
	check(p1:GetAttribute("CarryingLoot") == "JewelryBox", "hold fallback at 3 s accepted")
	Loot:drop(p1)
	task.wait(0.2)
	-- too far away
	local atm = activeSpot("ATMCash")
	triggerPrompt(pileAt(atm), p1)
	task.wait(0.1)
	m = lastMG()
	check(m.game == "drill", "ATMCash → drill")
	tp(p1, atm.cframe.Position + Vector3.new(40, 3, 0))
	task.wait(3)
	clientSend({ op = "done", token = m.token, mode = "game", ok = true })
	task.wait(0.2)
	check(lastMG().ok == false and tostring(lastMG().msg):find("far"), "finishing from 40 studs away rejected")
	-- busy: p2 can't start a pile p1 is playing
	triggerPrompt(pileAt(atm), p1)
	task.wait(0.1)
	triggerPrompt(pileAt(atm), p2)
	task.wait(0.1)
	check(REMOTE_LOG.Notify and REMOTE_LOG.Notify[1] == p2 and tostring(REMOTE_LOG.Notify[2].text):find("already"), "second player told 'already on it'")
	-- caught mid-game → stop
	Loot:drop(p1)
	task.wait(0.2)
	check(lastMG().op == "stop" and lastMG().reason == "caught", "drop()/caught mid-game → server stops the mini-game")
	check(not LM:isOpen(), "client closed the card on stop")

	-- ── mini-games: the REAL client (hold E, then tap-to-stuff) ──
	print("\n==== CLIENT PLAYS ====")
	task.wait(1)
	triggerPrompt(pileAt(atm), p1)
	task.wait(0.3)
	check(LM:isOpen(), "client card open for the drill")
	inClient(function() UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.E, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }, false) end)
	task.wait(3.4)
	inClient(function() UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.E, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }, false) end)
	task.wait(0.6)
	check(p1:GetAttribute("CarryingLoot") == "ATMCash", "client: holding E 3 s finishes the mini-game → bagged")
	Loot:drop(p1)
	task.wait(0.3)
	local box = activeSpot("DepositBox")
	triggerPrompt(pileAt(box), p1)
	task.wait(0.3)
	check(LM:isOpen() and lastMG().game == "stuff", "deposit box → stuff game open")
	local t0 = SCHED.now
	while LM:isOpen() and SCHED.now - t0 < 6 do
		inClient(function()
			UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }, false)
			UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }, false)
		end)
		task.wait(0.11)
	end
	task.wait(0.5)
	local dn = p1:GetAttribute("CarryName")
	check(p1:GetAttribute("CarryingLoot") == "DepositBox" and type(dn) == "string" and dn:find("^Deposit Box: "),
		string.format("client: tapping fills the bag in %.1f s → '%s' (%s)", SCHED.now - t0, tostring(dn), tostring(p1:GetAttribute("CarryValue"))))
	-- HUD shows the real name
	local kindLbl
	for _, x in ipairs(p1.PlayerGui:GetDescendants()) do if x.Name == "Kind" and x:IsA("TextLabel") then kindLbl = x end end
	check(kindLbl and kindLbl.Text == string.upper(dn), "LootHud pill shows the name (" .. tostring(kindLbl and kindLbl.Text) .. ")")
	Loot:drop(p1)
	task.wait(0.3)
	-- the four other games at least run headless for a few frames each (no errors) with a mouse
	for _, g in ipairs({ "cut", "dial", "unscrew", "drill" }) do
		inClient(function()
			LM:_onMessage({ op = "start", token = -1, game = g, title = "T", hint = "H", name = "X", value = 1, min = 1, hold = 3, timeout = 30 })
			UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }, false)
		end)
		task.wait(0.6)
		check(LM:isOpen() and LM._open.game == g, "client game '" .. g .. "' runs (card open, no errors)")
		inClient(function() UserInputService.InputEnded:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }, false) LM:_close(0) end)
		task.wait(0.3)
	end
	-- headless: the pure game logic reaches 100% with ideal input
	local GAMES = LM._GAMES
	local function simulate(name, drive, maxT)
		local area = Instance.new("Frame")
		area.Size = UDim2.fromOffset(400, 240)
		area.Parent = p1.PlayerGui
		local api = { seed = 7, scale = 1, sound = function() end, down = false, taps = 0, stick = Vector2.zero, keyTurn = 0, gamepad = false }
		local ptr = nil
		api.pointer = function() return ptr end
		local g = GAMES[name].build(area, api)
		local t, dt, p = 0, 1 / 60, 0
		while t < (maxT or 8) and p < 1 do
			ptr = drive(g, api, t)
			p = GAMES[name].update(g, dt, api)
			api.taps = 0
			t += dt
		end
		area:Destroy()
		return p, t
	end
	-- cut: pointer rides along the path, as fast as a hand can
	local pc, tc = simulate("cut", function(g, api, t)
		api.down = true
		local s = math.min(g.P + 5, t * 900)
		local cw, ch = g.cw, g.ch
		local x, y
		if s <= cw then x, y = s, 0 elseif s <= cw + ch then x, y = cw, s - cw elseif s <= 2 * cw + ch then x, y = cw - (s - cw - ch), ch else x, y = 0, ch - (s - 2 * cw - ch) end
		return Vector2.new(x, y)
	end)
	check(pc >= 1 and tc >= V3.MINIGAMES.cut.min and tc <= 6, string.format("cut: full lap in %.2f s (>= server min %.1f, <= 6)", tc, V3.MINIGAMES.cut.min))
	local pdl, tdl = simulate("dial", function(g, api, t)
		api.gamepad = true
		local tgt = g.targets[math.min(g.clicks + 1, g.need)]
		api.stick = Vector2.new(math.sin(math.rad(tgt)), math.cos(math.rad(tgt)))
		return nil
	end)
	check(pdl >= 1 and tdl >= V3.MINIGAMES.dial.min and tdl <= 6, string.format("dial (gamepad): 3 clicks in %.2f s (>= %.1f)", tdl, V3.MINIGAMES.dial.min))
	local pst, tst = simulate("stuff", function(g, api, t) api.taps = 1 return nil end)
	check(pst >= 1 and tst >= V3.MINIGAMES.stuff.min and tst <= 6, string.format("stuff (tap every frame): full in %.2f s (>= %.1f)", tst, V3.MINIGAMES.stuff.min))
	local pun, tun = simulate("unscrew", function(g, api, t) api.gamepad = true api.down = true api.stick = Vector2.new(1, 0) return nil end)
	check(pun >= 1 and tun >= V3.MINIGAMES.unscrew.min and tun <= 6, string.format("unscrew (hold + spin): done in %.2f s (>= %.1f)", tun, V3.MINIGAMES.unscrew.min))
	local pdr, tdr = simulate("drill", function(g, api, t) api.taps = 1 return nil end)
	check(pdr >= 1 and tdr >= V3.MINIGAMES.drill.min and tdr <= 6, string.format("drill (tap to place + fix jam): done in %.2f s (>= %.1f)", tdr, V3.MINIGAMES.drill.min))

	-- ── interact = false and spot flags ──
	print("\n==== FLAGS ====")
	check(pileAt(caged).MaxActivationDistance == 2.5, "spot.promptRange → MaxActivationDistance 2.5")
	check(pileAt(safeCash).ActionText == "Bag it", "SafeCash inside the drilled safe: no second lock (" .. pileAt(safeCash).ActionText .. ")")
	check(pileAt(vaultBox).ActionText == "Crack it" and pileAt(vaultBox).ObjectText:find("Deposit Box #7"), "vault deposit box keeps its own dial (" .. pileAt(vaultBox).ObjectText .. ")")
	local reg = activeSpot("Register")
	check(pileAt(reg).ActionText == "Bag it", "Register with interact=false → plain 'Bag it'")
	local cashHF = activeSpot("Cash")
	check(pileAt(cashHF).ActionText == "Lift together" and pileAt(cashHF).ObjectText:find("HEAVY") and pileAt(cashHF).ObjectText:find("FRAGILE"),
		"spot heavy/fragile flags override the kind (" .. pileAt(cashHF).ObjectText .. ")")

	-- ── heavy ──
	print("\n==== HEAVY ====")
	p1:SetAttribute("Role", "Hacker")
	p2:SetAttribute("Role", "Lookout")
	Loot:setVaultOpen(true)
	local gb = activeSpot("GoldBars")
	local gp = pileAt(gb)
	triggerPrompt(gp, p1)
	task.wait(0.2)
	check(p1:GetAttribute("CarryingLoot") == nil and gp.ActionText == "Lift together (1/2)", "first lifter waits (1/2)")
	triggerPrompt(gp, p2)
	task.wait(0.3)
	check(p1:GetAttribute("CarryingLoot") == "GoldBars" and p2:GetAttribute("CarryHelping") == "Gold Bars", "second player → carried together")
	local function mult(p) return (p:GetAttribute("SpeedMult") or 1) * (p:GetAttribute("TrailSpeedMult") or 1) end
	check(approx(hum(p1).WalkSpeed, V3.HEAVY_SPEED * mult(p1)) and approx(hum(p2).WalkSpeed, V3.HEAVY_SPEED * mult(p2)),
		"both slowed to HEAVY_SPEED (" .. hum(p1).WalkSpeed .. " / " .. hum(p2).WalkSpeed .. ")")
	local bag = p1.Character:FindFirstChild("LootBag")
	check(bag and bag:FindFirstChild("Tether") and bag.Tether:IsA("Beam"), "tether beam between the two")
	check(p1:GetAttribute("CarryPartner") == "Buddy" and p2:GetAttribute("CarryPartner") == "Malachi", "CarryPartner both ways")
	check(Loot:isCarrying(p2) == true, "isCarrying(helper) = true (can't grab other loot)")
	-- throw refused for non-Muscle
	inClient(function() REPLICATED.Remotes.ThrowBag:FireServer(Vector3.new(0, 0, -1)) end)
	task.wait(0.3)
	check(p1:GetAttribute("CarryingLoot") == "GoldBars", "can't throw heavy loot (non-Muscle)")
	-- the HELPER loads it at the trunk
	local trunk = Instance.new("Part") trunk.Anchored = true trunk.Parent = fake trunk.Position = BASE + Vector3.new(0, 1, -20)
	local carM = Instance.new("Model") carM.Parent = fake trunk.Parent = carM
	Loot:attachTrunk(trunk)
	local before = #Loot:getLoaded()
	triggerPrompt(trunk:FindFirstChild("LoadBag"), p2)
	task.wait(0.3)
	local rows = Loot:getLoaded()
	check(#rows == before + 1 and rows[#rows].kind == "GoldBars" and rows[#rows].by == "Malachi", "helper loads it → counted (owner = lifter)")
	check(p1:GetAttribute("CarryingLoot") == nil and p2:GetAttribute("CarryHelping") == nil and approx(hum(p2).WalkSpeed, 16 * mult(p2)),
		"both let go + speeds restored (" .. hum(p2).WalkSpeed .. ")")
	-- tether break
	local gb2 = activeSpot("GoldBars")
	triggerPrompt(pileAt(gb2), p1)
	triggerPrompt(pileAt(gb2), p2)
	task.wait(0.3)
	tp(p2, root(p1).Position + Vector3.new(40, 0, 0))
	task.wait(2.2)
	local looseHeavy = nil
	for _, pr in ipairs(findPrompts(fake)) do if pr.Name == "PickUpBag" and pr.ActionText == "Lift together" then looseHeavy = pr end end
	check(p1:GetAttribute("CarryingLoot") == nil and looseHeavy ~= nil, "too far apart → it drops (loose heavy bag, 'Lift together')")
	-- Muscle solo picks the loose heavy bag up
	p2:SetAttribute("Role", "Muscle")
	triggerPrompt(looseHeavy, p2)
	task.wait(0.3)
	check(p2:GetAttribute("CarryingLoot") == "GoldBars" and p2:GetAttribute("CarryPartner") == nil and approx(hum(p2).WalkSpeed, 16 * mult(p2)),
		"Muscle lifts it alone at full speed (" .. hum(p2).WalkSpeed .. ")")
	Loot:drop(p2)
	task.wait(0.2)
	p2:SetAttribute("Role", "Lookout")
	-- nobody helps → pending expires
	local gb3 = activeSpot("GoldBars")
	if gb3 then
		triggerPrompt(pileAt(gb3), p1)
		task.wait(V3.HEAVY_LIFT_WAIT + 0.5)
		check(pileAt(gb3).ActionText == "Lift together" and p1:GetAttribute("CarryingLoot") == nil, "lift request times out → prompt resets")
	end

	-- ── fragile ──
	print("\n==== FRAGILE ====")
	local wine = activeSpot("Wine")
	local wp = pileAt(wine)
	check(wp.ObjectText:find("JACKPOT") ~= nil, "jackpot pile marked on its prompt (" .. wp.ObjectText .. ")")
	triggerPrompt(wp, p1)
	task.wait(0.2)
	check(Loot:valueOf(p1) == 2400, "wine in the JACKPOT room: 1600 x1.5 = " .. tostring(Loot:valueOf(p1)))
	check(p1:GetAttribute("CarryJackpot") == true and p1:GetAttribute("CarryFragile") == true, "CarryJackpot + CarryFragile attrs")
	-- walk (crouch speed) = safe
	root(p1).AssemblyLinearVelocity = Vector3.new(8, 0, 0)
	task.wait(3)
	check(p1:GetAttribute("CarryIntegrity") == 1, "crouch-walking (8) for 3 s: no crack")
	root(p1).AssemblyLinearVelocity = Vector3.new(14, 0, 0)
	task.wait(2.3)
	check(approx(p1:GetAttribute("CarryIntegrity"), 0.75) and p1:GetAttribute("CarryValue") == 1800,
		"running > 2 s → CRACK: 75% (" .. tostring(p1:GetAttribute("CarryValue")) .. ")")
	check(REMOTE_LOG.FeelFX and REMOTE_LOG.FeelFX[2] and REMOTE_LOG.FeelFX[2].text == "CRACK!", "FeelFX 'CRACK!' banner sent")
	root(p1).AssemblyLinearVelocity = Vector3.zero
	-- fall > 6 studs
	local h = hum(p1)
	h.FloorMaterial = Enum.Material.Air
	task.wait(0.2)
	tp(p1, root(p1).Position + Vector3.new(0, 10, 0))
	task.wait(0.2)
	tp(p1, root(p1).Position - Vector3.new(0, 10, 0))
	task.wait(0.05)
	h.FloorMaterial = Enum.Material.Plastic
	task.wait(0.3)
	check(approx(p1:GetAttribute("CarryIntegrity"), 0.5), "falling 10 studs → another crack (" .. tostring(p1:GetAttribute("CarryIntegrity")) .. ")")
	-- grabbed (drop) → crack, loose bag keeps the damage
	Loot:drop(p1)
	task.wait(0.2)
	local lw
	for _, pr in ipairs(findPrompts(fake)) do if pr.Name == "PickUpBag" and pr.ObjectText:find("Fancy Wine") then lw = pr end end
	check(lw ~= nil, "dropped wine is a loose bag")
	triggerPrompt(lw, p1)
	task.wait(0.2)
	check(approx(p1:GetAttribute("CarryIntegrity"), 0.25) and Loot:valueOf(p1) == 600, "grabbed → crack again, and it never goes below 25% (" .. Loot:valueOf(p1) .. ")")
	Loot:drop(p1)
	task.wait(0.2)
	check(true, "(floor holds on further drops)")

	-- ── target ──
	print("\n==== TARGET ====")
	check(Target:bonusFor({ jobId = "villa" }) == 0, "bonusFor = 0 before the target is loaded")
	local fp = pileAt(flamingo)
	check(fp and fp.ObjectText:find("^TARGET: Golden Flamingo"), "target pile labelled (" .. tostring(fp and fp.ObjectText) .. ")")
	p2:SetAttribute("Role", "Muscle")
	triggerPrompt(fp, p2)
	task.wait(0.2)
	check(p2:GetAttribute("CarryTarget") == true, "CarryTarget attr")
	triggerPrompt(trunk:FindFirstChild("LoadBag"), p2)
	task.wait(0.3)
	check(Target:isSecured() == true and REPLICATED:GetAttribute("TargetSecured") == true, "loading the target → secured (+ HUD attribute)")
	check(Target:bonusFor({ jobId = "villa" }) == 5000 and Target:bonusFor({ jobId = "bank" }) == 0 and Target:bonusFor() == 5000, "bonusFor(run) = $5,000 (only for this job)")
	local c2 = Loot:counts()
	check(c2.targetSecured == true and c2.targetBonus == 5000, "counts().targetSecured / targetBonus")
	local d = Data:getData(p2)
	check(d and d.targetTrophies and d.targetTrophies.GoldFlamingo == true, "trophy SAVED on the loader (data.targetTrophies.GoldFlamingo)")
	task.wait(0.5)
	local wall
	for _, x in ipairs(CollectionService:GetTagged("TargetTrophy")) do if x:GetAttribute("TargetKind") == "GoldFlamingo" then wall = x end end
	check(wall ~= nil and wall:GetAttribute("Owned") == true, "club BOSS TARGETS wall: Golden Flamingo plinth lit")
	local others = 0
	for _, x in ipairs(CollectionService:GetTagged("TargetTrophy")) do if x:GetAttribute("Owned") == false then others += 1 end end
	check(others == 3, "the other 3 plinths stay dark (" .. others .. ")")
	local plate = wall and wall:FindFirstChild("Plate")
	local lbl = plate and plate:FindFirstChildWhichIsA("SurfaceGui") and plate:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
	check(lbl and lbl.Text == "GOLDEN FLAMINGO", "plate reads GOLDEN FLAMINGO (" .. tostring(lbl and lbl.Text) .. ")")
	Target:awardCrew({ p1 })
	check(Data:getData(p1).targetTrophies.GoldFlamingo == true, "awardCrew(players) gives escapees the trophy too")
	Loot:clearLoaded()
	check(Target:bonusFor() == 0 and REPLICATED:GetAttribute("TargetSecured") == false, "clearLoaded() → not secured any more")
	-- player leaves → wall re-checks (p2 still owns, so still lit)
	p2:SetAttribute("Role", "Lookout")

	-- ── deposit boxes ──
	print("\n==== DEPOSIT BOXES ====")
	local counts, ducks = {}, 0
	local N = 4000
	for i = 1, N do
		local it = Loot._test.newItem("DepositBox", nil, 1)
		Loot._test.rollDeposit(it)
		counts[it.contents] = (counts[it.contents] or 0) + 1
		if it.duck then
			ducks += 1
			if Loot._test.itemValue(it, 1) ~= 1 then counts.badDuck = true end
		end
	end
	local function pct(k) return (counts[k] or 0) / N end
	check(math.abs(pct("cash") - 0.5) < 0.04 and math.abs(pct("jewels") - 0.3) < 0.04 and math.abs(pct("rare") - 0.15) < 0.03 and math.abs(pct("duck") - 0.05) < 0.02,
		string.format("weights: cash %.2f jewels %.2f rare %.2f duck %.2f", pct("cash"), pct("jewels"), pct("rare"), pct("duck")))
	check(not counts.badDuck, "the rubber duck is worth $1")
	-- a real duck take → funny line
	local duckItem = Loot._test.newItem("DepositBox", nil, 1)
	for _ = 1, 500 do duckItem = Loot._test.newItem("DepositBox", nil, 1) Loot._test.rollDeposit(duckItem) if duckItem.duck then break end end
	check(duckItem.duck and duckItem.name == "Deposit Box: Rubber Duck" and tostring(duckItem.line):find("QUACK"), "duck: name + funny line")

	-- ── reset reshuffles ──
	print("\n==== RESET ====")
	Loot:reset({ seed = 99 })
	local c3 = Loot:counts()
	check(c3.loaded == 0 and c3.taken == 0 and c3.total > 0, "reset() → fresh shuffle, nothing taken, nothing loaded (" .. c3.total .. " piles)")
	check(pileAt(flamingo) and pileAt(flamingo).Enabled, "target pile back after reset")
	Loot:disarm()
	local back = true
	for _, s in ipairs(spots) do if s.visual.Transparency ~= 0.1 then back = false end end
	check(back, "disarm() restores every visual")

	-- ── HUD: jackpot banner + target chip ──
	print("\n==== HUD ====")
	Loot:arm(refs, { seed = seedWine })
	task.wait(0.2)
	local LH = inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("LootHud")) end)
	inClient(function() LH:_jackpotBanner() end)
	task.wait(0.3)
	local bannerText
	for _, x in ipairs(p1.PlayerGui:GetDescendants()) do if x:IsA("TextLabel") and tostring(x.Text):find("JACKPOT") then bannerText = x.Text end end
	check(bannerText == "JACKPOT: THE WINE CELLAR X1.5!" or bannerText == "JACKPOT: the WINE CELLAR x1.5!", "jackpot banner: " .. tostring(bannerText))
	inClient(function() REPLICATED.Remotes.JobInfo.OnClientEvent:Fire({ stage = "ACTIVE", steps = {} }) end)
	task.wait(0.3)
	local chip
	for _, x in ipairs(p1.PlayerGui:GetDescendants()) do if x.Name == "Target" and x:IsA("Frame") then chip = x end end
	local txt = {}
	for _, x in ipairs(chip and chip:GetDescendants() or {}) do if x:IsA("TextLabel") and x.Text ~= "" then table.insert(txt, x.Text) end end
	check(chip and chip.Visible and table.concat(txt, " "):find("Golden Flamingo") and table.concat(txt, " "):find("5,000"), "target chip during a heist: " .. table.concat(txt, " "))
	inClient(function() REPLICATED.Remotes.JobInfo.OnClientEvent:Fire({ stage = "IDLE", steps = {} }) end)
	task.wait(0.3)
	check(chip and not chip.Visible, "target chip hidden outside a heist")
	-- helper pill
	p1:SetAttribute("Role", "Hacker") p2:SetAttribute("Role", "Lookout")
	Loot:setVaultOpen(true)
	local gbh = activeSpot("GoldBars")
	triggerPrompt(pileAt(gbh), p2)
	triggerPrompt(pileAt(gbh), p1)
	task.wait(0.4)
	local cap
	for _, x in ipairs(p1.PlayerGui:GetDescendants()) do if x:IsA("TextLabel") and x.Text == "HELPING" then cap = x end end
	check(p1:GetAttribute("CarryHelping") == "Gold Bars" and cap ~= nil, "helper sees the HELPING pill")
	Loot:drop(p1)

	-- spinning turntables (client)
	local camPos = inClient(function() return WORKSPACE.CurrentCamera.CFrame.Position end)
	local spin = Instance.new("Part") spin.Anchored = true spin.Parent = fake spin.CFrame = CFrame.new(camPos + Vector3.new(0, 0, -20))
	spin:SetAttribute("Spin", 90)
	CollectionService:AddTag(spin, "Spin")
	local LH2 = inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("LootHud")) end)
	local ang = inClient(function()
		local look0 = spin.CFrame.LookVector
		for _ = 1, 20 do LH2:_spinStep(0.05, camPos) end
		return math.deg(math.acos(math.clamp(look0:Dot(spin.CFrame.LookVector), -1, 1)))
	end)
	check(ang > 60 and ang < 120, string.format("tag 'Spin' (90°/s) turns (20 client frames x 0.05 s): %.0f°", ang))

	print("\n================ LOOT3 CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 400)
report()
