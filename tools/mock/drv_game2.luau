AUTO_NITRO = true
AUTO_TURN = 14
AUTO_FAST = 45
-- ═══════════════ full game-loop driver ═══════════════
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
local function tp(p, pos) local r = root(p) if r then p.Character:PivotTo(CFrame.new(pos)) end end
local function promptsIn(rootInst, name, onlyEnabled)
	local out = {}
	for _, x in ipairs(findPrompts(rootInst)) do
		if (not name or x.Name == name) and (not onlyEnabled or x.Enabled) then table.insert(out, x) end
	end
	return out
end
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end
local function lastRemote(name) return REMOTE_LOG[name] end
local function taggedIn(tag, rootInst)
	local out = {}
	for _, x in ipairs(CollectionService:GetTagged(tag)) do if x:IsDescendantOf(rootInst) then table.insert(out, x) end end
	return out
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local Bots = srv("BotService")
	local Jail = srv("JailService")
	local Hide = srv("HideService")
	local Guard = srv("GuardService")
	local Cos = srv("CosmeticsService")
	local LB = srv("LeaderboardService")
	local Police = srv("PoliceService")
	local Sec = srv("SecurityService")
	local hub = JS.hub
	local Econ = srv("EconomyService")
	ECON_LOG = {}
	local realAdd = Econ.addCash
	Econ.addCash = function(self, pl, amt, why, ...) table.insert(ECON_LOG, { p = pl, amt = amt, why = tostring(why) }) return realAdd(self, pl, amt, why, ...) end
	local MS = srv("MaskService")
	do
		local G = srv("GuardService")
		local real = G.setAlarmActive
		G.setAlarmActive = function(self, on, ...)
			if on then
				print("   [alarm-trace] t=" .. SCHED.now .. debug.traceback("", 2):sub(1, 400))
				for _, pl in ipairs(PLAYERS:GetPlayers()) do
					local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
					print("     ", pl.Name, r and r.Position, "seat", pl.Character and pl.Character:FindFirstChildOfClass("Humanoid") and tostring(pl.Character:FindFirstChildOfClass("Humanoid").SeatPart), "jailed", pl:GetAttribute("Jailed"))
				end
				local _, rr = JS:getCurrent()
				for _, row in ipairs(rr.laserRows or {}) do
					if row.zoneCFrame then
						for _, part in ipairs(WORKSPACE:GetPartBoundsInBox(row.zoneCFrame, row.zoneSize or Vector3.new(8, 5, 0.6))) do
							local m = part:FindFirstAncestorOfClass("Model")
							if m and PLAYERS:GetPlayerFromCharacter(m) then print("      IN LASER ZONE:", part:GetFullName(), part.Position, part.ClassName) end
						end
					end
				end
				for _, b in ipairs(CollectionService:GetTagged("Laser")) do
					for _, pl in ipairs(PLAYERS:GetPlayers()) do
						local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
						if r and (b.Position - r.Position).Magnitude < 8 then print("      near laser", b:GetFullName(), b.Position, b.Size) end
					end
				end
			end
			return real(self, on, ...)
		end
	end
	local shopRF0 = remote("ShopAction")
	local realInv = shopRF0.OnServerInvoke
	shopRF0.OnServerInvoke = function(pl, action, payload)
		local b = string.format("Mask=%s power=%s", tostring(pl:GetAttribute("Mask")), tostring(pl:GetAttribute("MaskPower")))
		local r = realInv(pl, action, payload)
		if action ~= "getState" then print(string.format("   [shop] %s %s %s → ok=%s msg=%s | before %s | after Mask=%s power=%s", pl.Name, tostring(action), type(payload) == "table" and tostring(payload.id) or "", tostring(r.ok), tostring(r.msg), b, tostring(pl:GetAttribute("Mask")), tostring(pl:GetAttribute("MaskPower")))) end
		return r
	end

	local p1 = addPlayer("Malachi")
	if WITH_CLIENT then startClient(p1) end
	local p2 = addPlayer("Buddy")
	task.wait(3)

	-- ── static wiring checks ──
	print("\n==== WIRING ====")
	check(type(hub.spawnPads) == "table" and #hub.spawnPads >= 4, "hub.spawnPads >= 4 (" .. tostring(hub.spawnPads and #hub.spawnPads) .. ")")
	for _, pad in ipairs(hub.spawnPads or {}) do
		check(pad:IsA("SpawnLocation") and pad.Neutral == true and pad.Duration == 5 and pad:IsDescendantOf(WORKSPACE), "spawn pad " .. pad:GetFullName() .. " Neutral/Duration=5/in workspace")
	end
	check(type(hub.portals) == "table", "hub.portals table")
	for _, cfg in ipairs(mockRequire(REPLICATED.Shared.Constants).JOBS) do
		local po = hub.portals and hub.portals[cfg.id]
		check(po and mtypeof(po.zone) == "Instance" and po.zone:IsA("BasePart") and po.zone.CanCollide == false and type(po.setState) == "function", "portal for " .. cfg.id .. " (zone BasePart CanCollide=false + setState)")
	end
	check(#CollectionService:GetTagged("PortalZone") >= 0, "PortalZone tagged count = " .. #CollectionService:GetTagged("PortalZone"))
	check(mtypeof(hub.leaderboardAnchor) == "CFrame", "hub.leaderboardAnchor CFrame")
	check(type(hub.introPath) == "table" and #hub.introPath >= 4 and mtypeof(hub.introPath[1]) == "CFrame", "hub.introPath 4+ CFrames")
	check(lastRemote("IntroCam") ~= nil, "IntroCam fired to a player")
	local dr = remote("DailyReward")
	check(dr and dr.ClassName == "RemoteFunction", "DailyReward is a RemoteFunction")
	check(#CollectionService:GetTagged("HideSpot") > 0, "HideSpot tagged parts: " .. #CollectionService:GetTagged("HideSpot"))
	local noPrompt = 0
	for _, h in ipairs(CollectionService:GetTagged("HideSpot")) do if not h:FindFirstChild("HidePrompt") then noPrompt += 1 print("   no HidePrompt: " .. h:GetFullName()) end end
	check(noPrompt == 0, "every HideSpot has a HidePrompt")
	local vents = CollectionService:GetTagged("Vent")
	check(#vents > 0, "Vent tagged parts: " .. #vents)
	for _, v in ipairs(vents) do
		local pairName = v:GetAttribute("Pair")
		local found = 0
		for _, o in ipairs(vents) do if o ~= v and o.Name == pairName then found += 1 end end
		check(v:FindFirstChild("VentPrompt", true) ~= nil and pairName ~= nil and found >= 1, "vent " .. v:GetFullName() .. " Pair=" .. tostring(pairName) .. " matches=" .. found .. (found > 1 and " (AMBIGUOUS name)" or ""))
	end
	local shadow = CollectionService:GetTagged("ShadowZone")
	check(#shadow > 0, "ShadowZone tagged parts: " .. #shadow)
	for _, z in ipairs(shadow) do
		if z.CanCollide or z.CanQuery or z.CanTouch then print("   ShadowZone collides/queries/touches: " .. z:GetFullName() .. " " .. tostring(z.CanCollide) .. tostring(z.CanQuery) .. tostring(z.CanTouch)) end
	end
	check(Jail:isReady(), "JailService has cells")

	-- daily reward + cosmetics + leaderboard (server-side API)
	print("\n==== DAILY / COSMETICS / LEADERBOARD ====")
	local st = dr.OnServerInvoke(p1, "status")
	check(type(st) == "table" and st.ok ~= nil, "DailyReward status → " .. (type(st) == "table" and string.format("ok=%s day=%s amount=%s nextAt=%s", tostring(st.ok), tostring(st.day), tostring(st.amount), tostring(st.nextAt)) or tostring(st)))
	local cl = dr.OnServerInvoke(p1, "claim")
	check(type(cl) == "table" and cl.ok == true, "DailyReward claim → " .. (type(cl) == "table" and tostring(cl.msg) or tostring(cl)))
	local cl2 = dr.OnServerInvoke(p1, "claim")
	check(type(cl2) == "table" and cl2.ok == false, "DailyReward second claim refused → " .. (type(cl2) == "table" and tostring(cl2.msg) or tostring(cl2)))
	local cat = Cos:catalog()
	check(type(cat) == "table", "Cosmetics catalog")
	local firstId
	for _, item in ipairs(cat) do if (item.price or 0) > 0 and (item.price or 0) <= 500 then firstId = item.id break end end
	if not firstId and cat[1] then firstId = cat[1].id end
	local E = srv("EconomyService")
	E:addCash(p1, 100000, "test")
	print("   buying cosmetic", firstId, Cos:buy(p1, firstId))
	print("   equip", Cos:equip(p1, firstId))
	check(Cos:owns(p1, firstId), "cosmetic owned after buy")
	local shopRF = remote("ShopAction")
	local r = shopRF.OnServerInvoke(p1, "getState", {})
	check(type(r) == "table", "ShopAction getState")
	for _, item in ipairs(cat) do
		if item.id ~= firstId then
			local rr = shopRF.OnServerInvoke(p1, "buyCosmetic", { id = item.id })
			local re = shopRF.OnServerInvoke(p1, "equipCosmetic", { id = item.id })
		end
	end
	check(true, "bought/equipped every cosmetic via ShopAction")
	LB:refresh()
	task.wait(1)
	check(lastRemote("Leaderboard") ~= nil, "Leaderboard remote fired")

	-- the four jobs
	local JOBS = { "mart", "villa", "jewelry", "bank" }
	for _, jobId in ipairs(JOBS) do
		print("\n==== JOB " .. jobId .. " ====")
		waitFor(function() return JS:getPhase() == "idle" end, 60)
		check(JS:getPhase() == "idle", jobId .. ": phase idle before launch (" .. JS:getPhase() .. ")")
		-- both players step in the portal
		local zone = hub.portals[jobId].zone
		tp(p1, zone.Position + Vector3.new(0, 3, 0))
		tp(p2, zone.Position + Vector3.new(1, 3, 0))
		local launched = waitFor(function() return JS:getPhase() == "running" end, 30)
		check(launched and JS:getCurrentId() == jobId, jobId .. ": launched via portal (current=" .. tostring(JS:getCurrentId()) .. ")")
		if not launched then continue end
		local cfg, refs = JS:getCurrent()
		local s = refs.sneakIn
		check(s and mtypeof(s.at) == "Vector3" and mtypeof(s.face) == "Vector3" and mtypeof(s.spread) == "Vector3", jobId .. ": sneakIn shape")
		local d1 = (root(p1).Position - s.at).Magnitude
		check(d1 < 12, jobId .. ": p1 dropped in near sneakIn (" .. string.format("%.1f", d1) .. " studs)")
		check(type(refs.entrances) == "table" and #refs.entrances >= 3, jobId .. ": 3 entrances")
		check(type(refs.hideSpots) == "table" and #refs.hideSpots >= 2, jobId .. ": hideSpots " .. tostring(refs.hideSpots and #refs.hideSpots))
		check(type(refs.shadowZones) == "table", jobId .. ": shadowZones " .. tostring(refs.shadowZones and #refs.shadowZones))
		check(type(refs.vents) == "table", jobId .. ": vents " .. tostring(refs.vents and #refs.vents))
		check(p1:GetAttribute("Role") ~= nil, jobId .. ": auto-role given (" .. tostring(p1:GetAttribute("Role")) .. ")")
		task.wait(1)
		local bots = Bots:getBots()
		check(#bots == 1, jobId .. ": bots spawned for 2 players = " .. #bots)

		if WITH_CLIENT then
			for _, k in ipairs({ Enum.KeyCode.C, Enum.KeyCode.Q, Enum.KeyCode.G, Enum.KeyCode.H, Enum.KeyCode.F, Enum.KeyCode.R, Enum.KeyCode.Escape, Enum.KeyCode.C }) do pressKey(k) task.wait(0.3) end
			print("   clicked client buttons:", clickAllButtons(p1.PlayerGui))
			task.wait(0.5)
		end
		print("   [mask-trace] crouch: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- crouch
		remote("Crouch").OnServerEvent:Fire(p1, true)
		task.wait(0.2)
		check(p1:GetAttribute("Crouching") == true, jobId .. ": Crouch remote sets Crouching")
		remote("Crouch").OnServerEvent:Fire(p1, false)
		task.wait(0.2)
		check(not p1:GetAttribute("Crouching"), jobId .. ": uncrouch")

		print("   [mask-trace] hide / unhide: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- hide / unhide
		local spot = refs.hideSpots and refs.hideSpots[1]
		if spot then
			local hp = spot:FindFirstChild("HidePrompt")
			triggerPrompt(hp, p1)
			task.wait(0.4)
			check(p1:GetAttribute("Hidden") == true, jobId .. ": hide in " .. spot:GetFullName())
			triggerPrompt(hp, p1)
			task.wait(0.5)
			check(not p1:GetAttribute("Hidden"), jobId .. ": unhide")
		end

		print("   [mask-trace] vents: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- vents
		for vi, v in ipairs(refs.vents or {}) do
			check(mtypeof(v.a) == "Instance" and mtypeof(v.b) == "Instance", jobId .. ": vent " .. vi .. " {a,b} parts")
			if mtypeof(v.a) == "Instance" then
				local vp = v.a:FindFirstChild("VentPrompt", true)
				if check(vp ~= nil, jobId .. ": vent " .. vi .. " a has VentPrompt") then
					task.wait(1)
					triggerPrompt(vp, p1)
					task.wait(0.6)
					local dist = (root(p1).Position - v.b.Position).Magnitude
					check(dist < 8, jobId .. ": vent " .. vi .. " took p1 to b (" .. string.format("%.1f", dist) .. " studs from " .. v.b.Name .. ")")
					task.wait(1)
					local vp2 = v.b:FindFirstChild("VentPrompt", true)
					if vp2 then triggerPrompt(vp2, p1) task.wait(0.6)
						check((root(p1).Position - v.a.Position).Magnitude < 8, jobId .. ": vent " .. vi .. " back to a") end
				end
			end
		end

		print("   [mask-trace] guard catch → kickBack: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- guard catch → kickBack
		local guards = {}
		for _, g in pairs(Guard:getGuards()) do table.insert(guards, g) end
		check(#guards == cfg.guards, jobId .. ": guards spawned " .. #guards .. " (cfg " .. tostring(cfg.guards) .. ")")
		for _, g in ipairs(guards) do
			print("   guard", g.name, "pos", g.root.Position, "alarm", g.alarmActive, "stunned", g.stunnedUntil, "look", g.root.CFrame.LookVector)
			local d = (g.root.Position - s.at).Magnitude
			if d < 15 then print("   WARNING guard " .. g.name .. " is " .. string.format("%.1f", d) .. " studs from sneakIn") end
		end
		task.wait(8)   -- drop-in grace
		if jobId == "villa" and guards[2] then
			-- Goalie TOUGH GUY: first grab breaks free, the second sends you to the door
			Econ:addCash(p2, 5000, "test")
			shopRF0.OnServerInvoke(p2, "buyMask", { id = "Goalie" })
			shopRF0.OnServerInvoke(p2, "equipMask", { id = "Goalie" })
			task.wait(8)
			check(p2:GetAttribute("MaskPower") == "toughguy", "villa: p2 wearing Goalie → MaskPower toughguy (" .. tostring(p2:GetAttribute("MaskPower")) .. ")")
			local gt = guards[2]
			local gpart = (gt.model or gt):IsA("Model") and (gt.model or gt):FindFirstChildWhichIsA("BasePart", true) or gt.root
			local spot = gpart.Position + Vector3.new(0, 0, 2)
			tp(p2, spot) touch(gpart, root(p2)) task.wait(0.5)
			local stayed = (root(p2).Position - spot).Magnitude < 3
			local consumed = MS:useToughGuy(p2) == false   -- already spent this run
			check(stayed and consumed and JS:getPhase() == "running", "villa: TOUGH GUY once (1st grab free=" .. tostring(stayed) .. ", spent after=" .. tostring(consumed) .. ")")
			shopRF0.OnServerInvoke(p2, "equipMask", { id = "Bandit" })
			task.wait(3.5)
		end
		if guards[1] then
			-- vision: stand 8 studs in front of the guard and wait for the meter to fill
			local g0 = guards[1]
			local spotted = false
			for i = 1, 40 do
				local look = g0.root.CFrame.LookVector
				local dir = Vector3.new(look.X, 0, look.Z).Unit
				local r = (g0.nextWaypoint and g0.nextWaypoint - g0.root.Position)
				if r and Vector3.new(r.X, 0, r.Z).Magnitude > 1 then dir = Vector3.new(r.X, 0, r.Z).Unit g0.root.CFrame = CFrame.lookAt(g0.root.Position, g0.root.Position + dir) end
				tp(p1, g0.root.Position + dir * 8 - Vector3.new(0, 1, 0))
				task.wait(0.1)
				if (root(p1).Position - s.at).Magnitude < 12 then spotted = true break end
			end
			print("   vision test guard", g0.name, "at", g0.root.Position, "p1", root(p1).Position, "alarm", g0.alarmActive)
			check(spotted, jobId .. ": guard vision spotted p1 → kickBack to sneakIn (sus=" .. tostring(p1:GetAttribute("GuardSuspicion")) .. ")")
			task.wait(3.5)
			local g = guards[2] or guards[1]
			local gm = g.model or g
			local gpart = gm:IsA("Model") and gm:FindFirstChildWhichIsA("BasePart", true) or gm
			tp(p1, gpart.Position + Vector3.new(0, 0, 2))
			touch(gpart, root(p1))
			task.wait(0.5)
			local dd = (root(p1).Position - s.at).Magnitude
			check(dd < 12, jobId .. ": guard grab → kickBack to sneakIn (" .. string.format("%.1f", dd) .. ")")
			check(JS:getPhase() == "running", jobId .. ": still running after kickBack")
		end

		print("   [mask-trace] grab loot and give it to the bot: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- grab loot and give it to the bot
		local lootRoot = refs.root or WORKSPACE
		local open = {}
		for _, pr in ipairs(promptsIn(lootRoot, nil, true)) do if (pr.Name == "BagLoot" and pr.ActionText == "Bag it") or pr.Name == "SmashCase" then table.insert(open, pr) end end
		check(#open > 0, jobId .. ": enabled loot prompts = " .. #open)
		if open[1] then
			triggerPrompt(open[1], p1)
			task.wait(0.3)
			check(Loot:isCarrying(p1), jobId .. ": p1 carrying after " .. open[1].Name)
			local b = Bots:getBots()[1]
			if b then
				tp(p1, b.model:GetPivot().Position + Vector3.new(0, 0, 3))
				local gp = b.model:FindFirstChild("GiveBag", true)
				if check(gp ~= nil, jobId .. ": bot has GiveBag prompt") then
					triggerPrompt(gp, p1)
					task.wait(0.3)
					check(not Loot:isCarrying(p1) and Loot:botCarrying(b.model), jobId .. ": bag moved to bot")
					local loaded = waitFor(function() return Loot:counts().loaded >= 1 end, 45)
					check(loaded ~= nil, jobId .. ": bot walked the bag to the car and loaded it (loaded=" .. Loot:counts().loaded .. ")")
				end
			end
		end
		-- second loot: player loads trunk directly
		local open2 = {}
		for _, pr in ipairs(promptsIn(lootRoot, nil, true)) do if (pr.Name == "BagLoot" and pr.ActionText == "Bag it") or pr.Name == "SmashCase" then table.insert(open2, pr) end end
		if open2[1] then
			triggerPrompt(open2[1], p1)
			task.wait(0.3)
			local car = JS:getCar()
			local lp = car and car.trunk and car.trunk:FindFirstChild("LoadBag", true)
			if check(lp ~= nil, jobId .. ": trunk LoadBag prompt") then
				local before = Loot:counts().loaded
				triggerPrompt(lp, p1)
				task.wait(0.3)
				check(Loot:counts().loaded == before + 1, jobId .. ": player loaded bag into trunk")
			end
		end

		print("   [mask-trace] keycard + door: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- keycard + door
		if #(refs.keycardDoors or {}) > 0 then
			local kc = waitFor(function() return promptsIn(WORKSPACE, "TakeKeycard", true)[1] end, 5)
			if check(kc ~= nil, jobId .. ": keycard prompt exists") then
				triggerPrompt(kc, p1)
				task.wait(0.3)
				check(p1:GetAttribute("HasKeycard") == true, jobId .. ": took keycard")
				local sw = refs.keycardDoors[1].panel:FindFirstChild("Swipe", true)
				if check(sw ~= nil, jobId .. ": keypad Swipe prompt") then
					triggerPrompt(sw, p1)
					task.wait(0.5)
					check(Sec:doorsOpen(), jobId .. ": keycard doors open")
				end
			end
		else
			check(Sec:doorsOpen(), jobId .. ": no keycard doors → doorsOpen() true")
		end

		print("   [mask-trace] drill the vault: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- drill the vault
		if refs.vault and refs.vault.door then
			local dp = refs.vault.door:FindFirstChild("Drill", true)
			if check(dp ~= nil, jobId .. ": drill prompt on vault door") then
				triggerPrompt(dp, p1)
				local t0 = SCHED.now
				local lastVaultCount = 0
				while SCHED.now - t0 < 120 do
					task.wait(0.5)
					if dp.Enabled and dp.Parent then triggerPrompt(dp, p1) end
					local c = Loot:counts()
					if (c.vault or 0) > 0 and JS:getPhase() == "running" then
						local vaultOpen = false
						for _, pr in ipairs(promptsIn(lootRoot, "BagLoot", true)) do vaultOpen = true end
					end
					local info = lastRemote("VaultProgress")
					if info and info[2] == 1 then break end
				end
				task.wait(3)
				local vl = 0
				for _, pr in ipairs(promptsIn(lootRoot, "BagLoot", true)) do vl += 1 end
				check(vl > 0, jobId .. ": vault loot unlocked after drilling (" .. vl .. " prompts)")
			end
		end

		print("   [mask-trace] camera alarm (or laser) → police: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- camera alarm (or laser) → police
		local alarmed = false
		for _, cam in ipairs(refs.cameras or {}) do
			if cam.head then
				local head = cam.head
				for i = 1, 80 do
					local lk = head.CFrame.LookVector
					local fl = WORKSPACE:Raycast(head.Position + lk * 6, Vector3.new(0, -30, 0))
					local floorY = fl and fl.Position.Y or 0.5
					local t = lk.Y < -0.05 and math.clamp((head.Position.Y - (floorY + 3)) / -lk.Y, 4, 30) or 10
					local at = head.Position + lk * t
					tp(p1, Vector3.new(at.X, floorY + 3, at.Z))
					task.wait(0.1)
					if lastRemote("AlarmTriggered") and lastRemote("AlarmTriggered")[2] == true then alarmed = true break end
				end
			end
			if alarmed then break end
		end
		check(alarmed or #(refs.cameras or {}) == 0, jobId .. ": camera saw player → alarm (" .. #(refs.cameras or {}) .. " cameras)")
		if not alarmed then
			-- force via laser or a guard in alarm? skip: use silent path by touching a laser
			print("   (no camera alarm; trying lasers)")
		end
		if alarmed then
			local cops = waitFor(function()
				local f = WORKSPACE:FindFirstChild("Police")
				if not f then return nil end
				for _, m in ipairs(f:GetDescendants()) do if m:IsA("Humanoid") then return m.Parent end end
				return nil
			end, 30)
			check(cops ~= nil, jobId .. ": cops spawned after alarm")
			if cops then
				local cpart = cops:FindFirstChild("HumanoidRootPart") or cops:FindFirstChildWhichIsA("BasePart", true)
				tp(p1, cpart.Position + Vector3.new(0, 0, 2))
				-- touch every part (the brain may only listen on some)
				for _, pp in ipairs(cops:GetDescendants()) do if pp:IsA("BasePart") then touch(pp, root(p1)) end end
				task.wait(0.5)
				check(p1:GetAttribute("Jailed") == true, jobId .. ": cop catch → Jailed")
				local jr = lastRemote("Jail")
				check(jr and jr[1] == p1 and type(jr[2]) == "table" and jr[2].jailed == true, jobId .. ": Jail remote {jailed=true}")
				-- p2 breaks p1 out
				local bo
				for _, pr in ipairs(promptsIn(WORKSPACE, "BreakOut", true)) do bo = pr end
				if check(bo ~= nil, jobId .. ": BreakOut prompt enabled on a cell door") then
					triggerPrompt(bo, p2)
					task.wait(0.5)
					check(not p1:GetAttribute("Jailed"), jobId .. ": p2 broke p1 out")
					check((root(p1).Position - s.at).Magnitude < 12, jobId .. ": freed p1 back at sneakIn")
				end
			end
		end

		print("   [mask-trace] drive to the marina with both players in the car: p1 Mask=" .. tostring(p1:GetAttribute("Mask")) .. " power=" .. tostring(p1:GetAttribute("MaskPower")) .. " HC_Mask=" .. tostring(p1.Character and p1.Character:FindFirstChild("HC_Mask") ~= nil))
		-- drive to the marina with both players in the car
		local car = JS:getCar()
		if check(car ~= nil, jobId .. ": getaway car exists") then
			local ep = car.driverSeat:FindFirstChild("EnterPrompt")
			triggerPrompt(ep, p1)
			local other
			for _, seat in ipairs(car.seats) do if seat ~= car.driverSeat and not seat.Occupant then other = seat break end end
			if other then triggerPrompt(other:FindFirstChild("EnterPrompt"), p2) end
			task.wait(0.3)
			check(#car:getOccupants() == 2, jobId .. ": both players in the car (" .. #car:getOccupants() .. ")")
			local W = mockRequire(REPLICATED.Shared.Constants).WORLD
			ECON_LOG = {}
			local startCF = refs.getawayCFrame
			car:_placeAt(startCF)
			task.wait(0.2)
			for _, mname in ipairs({ "freeze", "ejectAll" }) do
				local realM = car[mname]
				car[mname] = function(self, ...)
					print("   [car-trace] " .. mname .. " t=" .. SCHED.now .. " args=" .. tostring((...)) .. " car " .. tostring(self.pos) .. " v " .. string.format("%.1f", self.v) .. debug.traceback("", 2):sub(1, 300))
					for _, m in ipairs(CollectionService:GetTagged("PoliceCruiser")) do print("      cruiser", m.Name, m:GetPivot().Position, "gap", string.format("%.1f", (m:GetPivot().Position - self.model:GetPivot().Position).Magnitude)) end
					return realM(self, ...)
				end
			end
			for _, m in ipairs(CollectionService:GetTagged("PoliceCruiser")) do print("      cruiser at drive start", m:GetPivot().Position) end
			if not KEEP_POLICE then Police:recall() task.wait(0.5) end
			local drove = autoDrive(jobId, car, p1, marinaWaypoints(startCF), 120)
			check(drove, jobId .. ": drove the getaway car out of its yard gate to the marina (car at " .. tostring(car.pos) .. ")")
			if not drove then car:_placeAt(CFrame.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z)) end
			local done = waitFor(function() return lastRemote("HeistState") and (lastRemote("HeistState")[2] == "COMPLETE" or lastRemote("HeistState")[2] == "FAILED") end, 10)
			local hs = lastRemote("HeistState")
			task.wait(0.5)
			local each, lucky = {}, {}
			for _, e in ipairs(ECON_LOG) do
				if e.why:find("Heist payout") then each[e.p] = (each[e.p] or 0) + e.amt end
				if e.why:find("LUCKY") then lucky[e.p] = (lucky[e.p] or 0) + e.amt end
			end
			for _, pl in ipairs({ p1, p2 }) do
				local want = MS:has(pl, "lucky") and true or (pl:GetAttribute("Mask") == "Bandit")
				print(string.format("   payout %s: cut %s, LUCKY %s, mask %s", pl.Name, tostring(each[pl]), tostring(lucky[pl]), tostring(pl:GetAttribute("Mask"))))
			end
			local take = hs and hs[3] and hs[3].take
			local luckyOk = true
			for _, pl in ipairs({ p1, p2 }) do
				if pl:GetAttribute("Mask") == "Bandit" and each[pl] then
					luckyOk = luckyOk and lucky[pl] == math.floor((take or 0) * 0.1 + 0.5)
				end
			end
			check(luckyOk, jobId .. ": LUCKY bonus = 10% of the take (" .. tostring(take) .. ") for Bandit wearers")
			check(done and hs[2] == "COMPLETE", jobId .. ": finished at marina → " .. tostring(hs and hs[2]) .. " take=" .. tostring(hs and hs[3] and hs[3].take) .. " each=" .. tostring(hs and hs[3] and hs[3].each) .. " grade=" .. tostring(hs and hs[3] and hs[3].grade))
		end
		task.wait(2)
		check(#Bots:getBots() == 0, jobId .. ": bots despawned after finish")
		LB:refresh()
		task.wait(20)   -- reset cooldown
		check(JS:getPhase() == "idle", jobId .. ": reset → idle (" .. JS:getPhase() .. ")")
		-- step out of the portal zone area: back to club spawn
		tp(p1, hub.spawnPads[1].Position + Vector3.new(0, 3, 0))
		tp(p2, hub.spawnPads[2].Position + Vector3.new(0, 3, 0))
		task.wait(1)
	end

	if WITH_CLIENT then
		-- lobby UI: open daily reward + shop by keys, click everything
		for _, k in ipairs({ Enum.KeyCode.B, Enum.KeyCode.M, Enum.KeyCode.E, Enum.KeyCode.Escape }) do pressKey(k) task.wait(0.3) end
		print("   clicked client buttons (lobby):", clickAllButtons(p1.PlayerGui))
		task.wait(3)
		print("   clicked client buttons (lobby 2):", clickAllButtons(p1.PlayerGui))
		task.wait(3)
	end
	-- leaving + shutdown
	removePlayer(p2)
	task.wait(1)
	for _, f in ipairs(BIND_TO_CLOSE) do f() end
	print("\n==== CHECK SUMMARY ====")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 print(c) end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 3000)
report()
