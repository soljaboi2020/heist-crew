-- ═══════ masks + cosmetics end-to-end ═══════
local CHECKS = {}
local ROWS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function row(item, buy, equip, effect, note) table.insert(ROWS, string.format("%-14s buy %-5s equip %-5s effect %-5s %s", item, tostring(buy), tostring(equip), tostring(effect), note or "")) end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function srv(n) return mockRequire(SERVER_SCRIPT:FindFirstChild(n)) end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function hum(p) return p.Character and p.Character:FindFirstChildOfClass("Humanoid") end
local function tp(p, pos) p.Character:PivotTo(CFrame.new(pos)) end
local function addPlayerUid(name, uid)
	local p = newInstance("Player") p.Name = name
	D[p].props.UserId = uid D[p].props.DisplayName = name
	local bp = newInstance("Backpack", p) bp.Name = "Backpack"
	local pg = newInstance("PlayerGui", p) pg.Name = "PlayerGui"
	local ps = newInstance("PlayerScripts", p) ps.Name = "PlayerScripts"
	p.Parent = PLAYERS
	getSig(PLAYERS, "PlayerAdded"):Fire(p)
	task.wait(0.2)
	spawnCharacter(p)
	return p
end
local function c3eq(a, b) return a and b and math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01 end
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS, Loot, Cos, Shop, MS, PD, E, Guard, Sec, VS = srv("JobService"), srv("LootService"), srv("CosmeticsService"), srv("ShopService"), srv("MaskService"), srv("PlayerDataService"), srv("EconomyService"), srv("GuardService"), srv("SecurityService"), srv("VehicleService")
	local C = mockRequire(REPLICATED.Shared.Constants)
	local shopRF = REPLICATED.Remotes.ShopAction
	local function act(p, a, pl) return shopRF.OnServerInvoke(p, a, pl or {}) end
	local p1 = addPlayerUid("Malachi", 777)
	task.wait(2)
	E:addCash(p1, 2000000, "test")
	local r0 = act(p1, "getState")
	check(r0.ok and type(r0.state.maskList) == "table" and #r0.state.maskList == #C.MASKS, "getState maskList has every mask")

	-- ── launch mart solo via its portal ──
	local zone = JS.hub.portals.mart.zone
	tp(p1, zone.Position + Vector3.new(0, 3, 0))
	check(waitFor(function() return JS:getPhase() == "running" end, 30), "mart launched")
	task.wait(8.5)   -- drop-in grace
	local _, refs = JS:getCurrent()
	local s = refs.sneakIn
	local LOADED0 = table.clone(LOADED_ASSETS or {})

	-- ── MASKS ──
	print("\n==== MASKS ====")
	local seenMystery
	for _, m in ipairs(C.MASKS) do
		local buyOk = true
		if m.price > 0 then
			local r = act(p1, "buyMask", { id = m.id })
			buyOk = r.ok == true
			local rowS
			for _, x in ipairs(r.state.maskList) do if x.id == m.id then rowS = x end end
			buyOk = buyOk and rowS and rowS.owned and rowS.equipped
			check(buyOk, "buyMask " .. m.id .. " → " .. tostring(r.msg))
		end
		local r = act(p1, "equipMask", { id = m.id })
		task.wait(0.3)
		local acc = p1.Character:FindFirstChild("HC_Mask")
		local equipOk = r.ok and p1:GetAttribute("Mask") == m.id and acc ~= nil and acc:IsA("Accessory") and (LOADED_ASSETS[m.assetId] or 0) > 0
		check(equipOk, "equipMask " .. m.id .. " in a run → HC_Mask accessory on the character (loaded asset " .. m.assetId .. ": " .. tostring(LOADED_ASSETS[m.assetId]) .. ") msg=" .. tostring(r.msg))
		local nMasks = 0 for _, x in ipairs(p1.Character:GetChildren()) do if x.Name == "HC_Mask" then nMasks += 1 end end
		check(nMasks == 1, m.id .. ": exactly one HC_Mask on the character (" .. nMasks .. ")")
		local power = p1:GetAttribute("MaskPower")
		local want = m.ability.id
		local effect, note = false, ""
		if want == "surprise" then
			effect = power ~= nil and power ~= "surprise" and MS:has(p1, power)
			seenMystery = power
			act(p1, "equipMask", { id = "Bandit" }) task.wait(0.2)
			act(p1, "equipMask", { id = "Mystery" }) task.wait(0.2)
			effect = effect and p1:GetAttribute("MaskPower") == seenMystery
			note = "rolled " .. tostring(power) .. ", kept after re-wear=" .. tostring(p1:GetAttribute("MaskPower") == seenMystery)
		else
			effect = power == want and MS:has(p1, want) and p1:GetAttribute("MaskPowerName") == m.ability.name
			if want == "foxspeed" then
				local ws = hum(p1).WalkSpeed
				effect = effect and math.abs(ws - 16 * 1.2) < 0.01 and p1:GetAttribute("SpeedMult") == 1.2
				note = "WalkSpeed " .. ws
			elseif want == "nightvision" then
				p1:SetAttribute("InShadow", true)
				local _, mult = Guard.stealthFactor(p1)
				p1:SetAttribute("InShadow", nil)
				effect = effect and mult == 2
				note = "shadow mult " .. tostring(mult)
			elseif want == "powerthrow" then
				local lp
				for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "BagLoot" and pr.Enabled then lp = pr break end end
				if lp then
					triggerPrompt(lp, p1) task.wait(0.3)
					local before = {}
					for _, x in ipairs(refs.root:GetDescendants()) do if x.Name == "LootBag" then before[x] = true end end
					REPLICATED.Remotes.ThrowBag.OnServerEvent:Fire(p1, Vector3.new(1, 0, 0))
					task.wait(0.1)
					local thrown
					for _, x in ipairs(refs.root:GetDescendants()) do if x.Name == "LootBag" and not before[x] then thrown = x end end
					local v = thrown and thrown.AssemblyLinearVelocity
					local hs = v and Vector3.new(v.X, 0, v.Z).Magnitude
					local roleMult = p1:GetAttribute("Role") == "Muscle" and 1.3 or 1
					effect = effect and hs and math.abs(hs - C.BAG_THROW_SPEED * 2 * roleMult) < 0.5
					note = "throw speed " .. tostring(hs) .. " (normal " .. C.BAG_THROW_SPEED * roleMult .. ", role " .. tostring(p1:GetAttribute("Role")) .. ")"
					-- put the bag back to the player for later
					local pk = thrown and thrown:FindFirstChild("PickUpBag")
					if pk then triggerPrompt(pk, p1) task.wait(0.2) Loot:drop(p1) end
				else note = "no loot prompt" effect = false end
			elseif want == "hackchip" then
				local bp = refs.breaker and refs.breaker:FindFirstChild("Breaker")
				if bp then
					tp(p1, refs.breaker.Position + Vector3.new(0, 0, 2))
					bp.PromptButtonHoldBegan:Fire(p1)
					task.wait(bp.HoldDuration / 2 - 0.2)
					local early = Sec:camerasCut()
					task.wait(0.4)
					effect = effect and not early and Sec:camerasCut() == true
					note = string.format("breaker hold %.1fs → cut at ~%.1fs", bp.HoldDuration, bp.HoldDuration / 2)
				end
			elseif want == "toughguy" and TOUGH_NOW then
				local g
				for _, gg in pairs(Guard:getGuards()) do g = gg break end
				local gm = g.model or g
				local gpart = gm:IsA("Model") and gm:FindFirstChildWhichIsA("BasePart", true) or gm
				local spot = gpart.Position + Vector3.new(0, 0, 2)
				tp(p1, spot) touch(gpart, root(p1)) task.wait(0.5)
				local stayed = (root(p1).Position - spot).Magnitude < 3
				task.wait(2.5)
				tp(p1, spot) touch(gpart, root(p1)) task.wait(0.5)
				local sentBack = (root(p1).Position - s.at).Magnitude < 12
				effect = effect and stayed and sentBack
				note = "1st grab stayed=" .. tostring(stayed) .. ", 2nd grab back to door=" .. tostring(sentBack)
				task.wait(2.5)
			else
				note = "power flag only (" .. want .. ")"
			end
		end
		check(effect, m.id .. " power " .. want .. " active: " .. note)
		row(m.id, buyOk, equipOk, effect, note)
	end
	-- Tough Guy last (cameras are cut by now, so no camera alarm muddies it)
	TOUGH_NOW = true
	do
		act(p1, "equipMask", { id = "Goalie" }) task.wait(0.3)
		local g
		for _, gg in pairs(Guard:getGuards()) do g = gg break end
		local gm = g.model or g
		local gpart = gm:IsA("Model") and gm:FindFirstChildWhichIsA("BasePart", true) or gm
		local spot = gpart.Position + Vector3.new(0, 0, 2)
		tp(p1, spot) touch(gpart, root(p1)) task.wait(0.5)
		local stayed = (root(p1).Position - spot).Magnitude < 3
		task.wait(3.5)
		spot = gpart.Position + Vector3.new(0, 0, 2)
		tp(p1, spot) touch(gpart, root(p1)) task.wait(0.5)
		local sentBack = (root(p1).Position - s.at).Magnitude < 12
		local ok = stayed and sentBack and JS:getPhase() == "running"
		check(ok, "Goalie TOUGH GUY: 1st grab broke free=" .. tostring(stayed) .. ", 2nd grab back to door=" .. tostring(sentBack))
		ROWS[2] = ROWS[2]:gsub("effect %S+%s+power flag only %(toughguy%)", "effect " .. tostring(ok) .. " 1st grab free=" .. tostring(stayed) .. " 2nd→door=" .. tostring(sentBack))
	end
	-- swapping off Kitsune restores speed
	act(p1, "equipMask", { id = "Kitsune" }) task.wait(0.3)
	act(p1, "equipMask", { id = "Owl" }) task.wait(0.3)
	check(math.abs(hum(p1).WalkSpeed - 16) < 0.01 and p1:GetAttribute("SpeedMult") == nil and p1:GetAttribute("MaskPower") == "nightvision", "swap Kitsune→Owl: speed back to 16, power nightvision (" .. hum(p1).WalkSpeed .. ")")
	act(p1, "equipMask", { id = "Bandit" }) task.wait(0.3)

	-- ── COSMETICS ──
	print("\n==== COSMETICS ====")
	local cat = Cos:catalog()
	-- a carried bag for the bag skins
	local function carry()
		if Loot:isCarrying(p1) then return true end
		for _, pr in ipairs(findPrompts(refs.root)) do if (pr.Name == "BagLoot" or pr.Name == "PickUpBag") and pr.Enabled then triggerPrompt(pr, p1) task.wait(0.3) if Loot:isCarrying(p1) then return true end end end
		return false
	end
	local car = JS:getCar()
	for _, it in ipairs(cat) do
		local expectBuy = not it.starter and not it.vipOnly and not it.rewardOnly
		local buyOk
		if it.starter then buyOk = Cos:owns(p1, it.id) and "starter"
		elseif it.rewardOnly then
			local rr = act(p1, "buyCosmetic", { id = it.id })
			buyOk = (not rr.ok) and Cos:grant(p1, it.id) and "reward(grant)"
		elseif it.vipOnly then
			p1:SetAttribute("VIP", false) task.wait(0.1)
			local rr = act(p1, "buyCosmetic", { id = it.id })
			local refused = not rr.ok
			p1:SetAttribute("VIP", true) task.wait(0.1)
			local rr2 = act(p1, "buyCosmetic", { id = it.id })
			buyOk = refused and rr2.ok and "vip"
		else
			local rr = act(p1, "buyCosmetic", { id = it.id })
			buyOk = rr.ok
		end
		local re = act(p1, "equipCosmetic", { id = it.id })
		local attr = ({ bag = "BagSkin", car = "CarColor", trail = "Trail" })[it.category]
		local equipOk = re.ok and p1:GetAttribute(attr) == it.id and re.state.cosmetics and re.state.cosmetics.equipped[it.category] == it.id
		local effect, note = false, ""
		if it.category == "bag" then
			carry()
			local bag = p1.Character:FindFirstChild("LootBag")
			local okC = bag and c3eq(bag.Color, rgb(it.color)) and bag.Material == Enum.Material[it.material] and bag:GetAttribute("Skin") == it.id
			-- throw it: the loose bag keeps the skin
			local before = {}
			for _, x in ipairs(refs.root:GetDescendants()) do if x.Name == "LootBag" then before[x] = true end end
			REPLICATED.Remotes.ThrowBag.OnServerEvent:Fire(p1, Vector3.new(0, 0, 1))
			task.wait(0.1)
			local thrown
			for _, x in ipairs(refs.root:GetDescendants()) do if x.Name == "LootBag" and not before[x] then thrown = x end end
			local okT = thrown and c3eq(thrown.Color, rgb(it.color)) and thrown:GetAttribute("Skin") == it.id
			effect = okC and okT
			note = "carried=" .. tostring(okC) .. " thrown=" .. tostring(okT)
			task.wait(0.6)
			local pk = thrown and thrown:FindFirstChild("PickUpBag")
			if pk then triggerPrompt(pk, p1) task.wait(0.3) end
		elseif it.category == "car" then
			if not car:getDriver() then triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1) task.wait(0.3) end
			local paintOk = car.model:GetAttribute("Paint") == it.id
			local pt = car.paint and car.paint[1]
			effect = paintOk and pt and c3eq(pt.Color, rgb(it.color))
			note = "driver=" .. tostring(car:getDriver() and car:getDriver().Name) .. " Paint=" .. tostring(car.model:GetAttribute("Paint"))
		else
			local tr = root(p1):FindFirstChild("HC_Trail")
			if it.color then
				effect = tr ~= nil and tr:IsA("Trail") and #root(p1):GetChildren() > 0
				local n = 0 for _, x in ipairs(root(p1):GetChildren()) do if x.Name == "HC_Trail" then n += 1 end end
				effect = effect and n == 1
				note = "trails on root=" .. n
			else
				effect = tr == nil
				note = "no trail"
			end
		end
		check(buyOk and equipOk and effect, "cosmetic " .. it.id .. " buy=" .. tostring(buyOk) .. " equip=" .. tostring(equipOk) .. " effect=" .. tostring(effect) .. " " .. note)
		row(it.id, buyOk, equipOk, effect, note)
	end
	-- car paint back to default when the driver gets out
	car:ejectAll() task.wait(0.3)
	check(car.model:GetAttribute("Paint") == "CarClassic", "car paint resets when the driver leaves (" .. tostring(car.model:GetAttribute("Paint")) .. ")")
	-- trail survives respawn
	act(p1, "equipCosmetic", { id = "TrailPink" })
	spawnCharacter(p1)
	task.wait(1)
	local tr = root(p1):FindFirstChild("HC_Trail")
	check(tr ~= nil, "trail re-attached after respawn")
	-- mask back on after respawn in a run?
	task.wait(1)
	print("   after respawn: HC_Mask=" .. tostring(p1.Character:FindFirstChild("HC_Mask") ~= nil) .. " MaskPower=" .. tostring(p1:GetAttribute("MaskPower")))

	-- ── run ends → mask off, power off ──
	act(p1, "equipMask", { id = "Kitsune" }) task.wait(0.3)
	local Econ = E
	-- finish: drive to marina quickly
	Loot:drop(p1)
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1) task.wait(0.3)
	local W = C.WORLD
	car:_placeAt(CFrame.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z))
	waitFor(function() return JS:getPhase() ~= "running" end, 15)
	task.wait(1)
	check(p1.Character:FindFirstChild("HC_Mask") == nil and p1:GetAttribute("MaskPower") == nil, "run over → mask + power off (" .. tostring(p1:GetAttribute("MaskPower")) .. ")")
	check(p1:GetAttribute("SpeedMult") == nil, "run over → SpeedMult cleared")
	task.wait(1)
	local wsNow = hum(p1) and hum(p1).WalkSpeed
	check(wsNow and math.abs(wsNow - 16) < 0.01, "run over → WalkSpeed back to 16 (" .. tostring(wsNow) .. ")")

	-- equip in the club = no mask/power
	act(p1, "equipMask", { id = "Catrina" }) task.wait(0.3)
	check(p1.Character:FindFirstChild("HC_Mask") == nil and p1:GetAttribute("MaskPower") == nil, "equip in the club: no mask worn, no power")

	-- ── save / load round trip ──
	print("\n==== SAVE / LOAD ====")
	local before = act(p1, "getState").state
	PD:savePlayer(p1)
	removePlayer(p1)
	task.wait(2)
	local p1b = addPlayerUid("Malachi", 777)
	task.wait(3)
	local after = act(p1b, "getState").state
	local function set(t) local o = {} for _, x in ipairs(t or {}) do o[x] = true end return o end
	local sameMasks = true for _, m in ipairs(C.MASKS) do if set(before.masks)[m.id] ~= set(after.masks)[m.id] then sameMasks = false end end
	check(sameMasks and after.mask == "Catrina", "masks owned + equipped survive save/load (equipped " .. tostring(after.mask) .. ")")
	local sameC = true for _, it in ipairs(cat) do if set(before.cosmetics.owned)[it.id] ~= set(after.cosmetics.owned)[it.id] then sameC = false print("   diff", it.id) end end
	check(sameC, "cosmetics owned survive save/load")
	for _, k in ipairs({ "bag", "car", "trail" }) do
		local vipFallback = k == "car" and before.cosmetics.equipped[k] == "CarGold" and after.cosmetics.equipped[k] == "CarClassic"
		check(before.cosmetics.equipped[k] == after.cosmetics.equipped[k] or vipFallback, "equipped " .. k .. (vipFallback and " (VIP-only → starter without VIP, by design)" or "") .. " survives (" .. tostring(before.cosmetics.equipped[k]) .. " → " .. tostring(after.cosmetics.equipped[k]) .. ")")
	end
	check(p1b:GetAttribute("Trail") == after.cosmetics.equipped.trail and root(p1b):FindFirstChild("HC_Trail") ~= nil, "trail attached on rejoin (" .. tostring(p1b:GetAttribute("Trail")) .. ")")
	check(p1b:GetAttribute("Mask") == "Catrina", "Mask attribute restored on rejoin")

	print("\n==== ITEM TABLE ====")
	for _, r in ipairs(ROWS) do print(r) end
	print("\n==== CHECK SUMMARY ====")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 print(c) end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 900)
report()
