-- ═══════ v2.2 GEAR: cars / trails / bags that DO something ═══════
local CHECKS = {}
local ROWS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function row(item, buy, equip, effect, note) table.insert(ROWS, string.format("%-12s buy %-8s equip %-5s effect %-5s %s", item, tostring(buy), tostring(equip), tostring(effect), note or "")) end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function srv(n) return mockRequire(SERVER_SCRIPT:FindFirstChild(n)) end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function hum(p) return p.Character and p.Character:FindFirstChildOfClass("Humanoid") end
local function tp(p, pos) p.Character:PivotTo(CFrame.new(pos)) end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 0.02) end
function localExtents(model)
	local pv = model:GetPivot()
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local w = (p.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
				local l = pv:PointToObjectSpace(w)
				mn = Vector3.new(math.min(mn.X, l.X), math.min(mn.Y, l.Y), math.min(mn.Z, l.Z))
				mx = Vector3.new(math.max(mx.X, l.X), math.max(mx.Y, l.Y), math.max(mx.Z, l.Z))
			end end end
		end
	end
	return mn, mx
end
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

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS, Loot, Cos, Shop, PD, E, VS, Police, Feel = srv("JobService"), srv("LootService"), srv("CosmeticsService"), srv("ShopService"), srv("PlayerDataService"), srv("EconomyService"), srv("VehicleService"), srv("PoliceService"), srv("FeelService")
	local C = mockRequire(REPLICATED.Shared.Constants)
	local shopRF = REPLICATED.Remotes.ShopAction
	local function act(p, a, pl) return shopRF.OnServerInvoke(p, a, pl or {}) end
	local amb = WORKSPACE:FindFirstChild("Ambient", true)
	if amb then amb:Destroy() end   -- no moving traffic in the speed tests

	-- ════ 1. SAVE MIGRATION ════
	print("\n==== MIGRATION ====")
	local p0 = addPlayerUid("OldSave", 555)
	task.wait(2)
	local d0 = PD:getData(p0)
	d0.cosmetics = { CarPink = true, CarGold = true, BagMint = true, BagCamo = true, TrailPink = true, BagDiamond = true }
	d0.equippedCosmetics = { car = "CarGold", bag = "BagCamo", trail = "TrailPink" }
	local st = Cos:stateFor(p0)
	local own = {} for _, id in ipairs(st.owned) do own[id] = true end
	check(own.CarMuscle and own.CarRacer and own.BagSports and own.BagDuffel and own.TrailPink and own.BagDiamond and not own.CarPink,
		"old paints/skins mapped: CarPink→CarMuscle, CarGold→CarRacer, BagMint→BagSports, BagCamo→BagDuffel, TrailPink kept, BagDiamond kept (owned: " .. table.concat(st.owned, ",") .. ")")
	check(st.equipped.car == "CarRacer" and st.equipped.bag == "BagDuffel" and st.equipped.trail == "TrailPink",
		"old equipped ids mapped (car " .. tostring(st.equipped.car) .. ", bag " .. tostring(st.equipped.bag) .. ", trail " .. tostring(st.equipped.trail) .. ")")
	d0.equippedCosmetics.bag = "BagDoesNotExist"
	d0.equippedCosmetics.car = 42
	st = Cos:stateFor(p0)
	check(st.equipped.bag == "BagClassic" and st.equipped.car == "CarClassic", "unknown equipped ids fall back to the starter (" .. st.equipped.bag .. ", " .. st.equipped.car .. ")")
	local r = act(p0, "equipCosmetic", { id = "CarPink" })
	check(r.ok and p0:GetAttribute("CarType") == "CarMuscle", "equip with an OLD id resolves to its new item (" .. tostring(r.msg) .. ")")
	removePlayer(p0)
	task.wait(1)

	-- ════ 2. setup ════
	local p1 = addPlayerUid("Malachi", 777)
	task.wait(2.5)
	E:addCash(p1, 5000000, "test")
	p1:SetAttribute("VIP", true)
	task.wait(0.3)
	local cat = Cos:catalog()
	local byId = {} for _, it in ipairs(cat) do byId[it.id] = it end
	local function buyEquip(it)
		local buyOk
		if it.starter then buyOk = Cos:owns(p1, it.id) and "starter"
		elseif it.rewardOnly then
			local rr = act(p1, "buyCosmetic", { id = it.id })
			buyOk = (not rr.ok) and Cos:grant(p1, it.id) and "reward"
		elseif it.vipOnly then
			p1:SetAttribute("VIP", false) task.wait(0.1)
			local rr = act(p1, "buyCosmetic", { id = it.id })
			p1:SetAttribute("VIP", true) task.wait(0.1)
			local rr2 = act(p1, "buyCosmetic", { id = it.id })
			buyOk = (not rr.ok) and rr2.ok and "vip"
		else
			local cash0 = p1:GetAttribute("Cash")
			local rr = act(p1, "buyCosmetic", { id = it.id })
			buyOk = rr.ok and (cash0 - p1:GetAttribute("Cash") == it.price) and ("$" .. it.price)
		end
		local re = act(p1, "equipCosmetic", { id = it.id })
		local attr = ({ bag = "BagSkin", car = "CarType", trail = "Trail" })[it.category]
		local equipOk = re.ok and p1:GetAttribute(attr) == it.id and re.state.cosmetics.equipped[it.category] == it.id
		return buyOk, equipOk
	end
	for _, it in ipairs(cat) do
		check(type(it.power) == "table" and type(it.power.name) == "string" and it.power.name ~= "", it.id .. " has a power pill: " .. tostring(it.power and it.power.name))
	end

	-- ════ 3. CARS: lobby preview follows equips, speed, nitro, bust ════
	print("\n==== CARS ====")
	local car = VS:getCar()
	local trunk0 = car.trunk
	p1:SetAttribute("Role", "Hacker")
	local Kin = VS.Kinematic
	local inRemote = REPLICATED.Remotes:FindFirstChild("CarInput") or REPLICATED:FindFirstChild("CarInput", true)
	for _, it in ipairs(cat) do
		if it.category == "car" then
			local buyOk, equipOk = buyEquip(it)
			task.wait(0.3)
			car = VS:getCar()
			local emn, emx = localExtents(car.model)
			local size = emx - emn
			local typed = car.carId == it.id and car.model:GetAttribute("CarType") == it.carType and car.model:GetAttribute("CarName") == it.name
			local sameTrunk = car.trunk == trunk0 and trunk0.Parent == car.model and trunk0:FindFirstChild("LoadBag") ~= nil
			local nSeats = 0 for _, x in ipairs(car.model:GetDescendants()) do if x:IsA("Seat") or x:IsA("VehicleSeat") then nSeats += 1 end end
			check(typed and sameTrunk and nSeats == 4, it.id .. ": lobby car rebuilt as '" .. tostring(car.model:GetAttribute("CarType")) .. "', same Trunk+LoadBag=" .. tostring(sameTrunk) .. ", seats=" .. nSeats)
			check(size.X <= 5.5 + 1e-3 and size.Y <= 7.3, string.format("%s: size %.2f wide x %.2f tall x %.2f long, x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f (≤5.5 wide incl wheels, ≤7.3 tall)", it.id, size.X, size.Y, size.Z, emn.X, emx.X, emn.Y, emx.Y, emn.Z, emx.Z))
			-- top speed on the open street (x -140 → +X, lane z -18)
			local ep = car.driverSeat:FindFirstChild("EnterPrompt")
			car:_placeAt(CFrame.lookAt(Vector3.new(-140, 0, -18), Vector3.new(0, 0, -18)))
			triggerPrompt(ep, p1) task.wait(0.3)
			local seated = car:getDriver() == p1
			local vmax = 0
			for _ = 1, 45 do
				inRemote.OnServerEvent:Fire(p1, 1, 0)
				task.wait(0.1)
				vmax = math.max(vmax, car.v)
			end
			inRemote.OnServerEvent:Fire(p1, 0, 0)
			local wantV = VS.TUNE.MAX_FORWARD * (it.speedMult or 1)
			local speedOk = seated and near(vmax, wantV, 0.6)
			-- nitro recharge (Driver role)
			p1:SetAttribute("Role", "Driver")
			car.model:SetAttribute("NitroReadyAt", 0)
			local now = WORKSPACE:GetServerTimeNow()
			REPLICATED.Remotes.Nitro.OnServerEvent:Fire(p1)
			task.wait(0.1)
			local cd = (car.model:GetAttribute("NitroReadyAt") or 0) - now
			local nitroOk = near(cd, it.nitroCooldown or 12, 0.3) and car.model:GetAttribute("NitroCooldown") == (it.nitroCooldown or 12)
			local vN = 0
			for _ = 1, 15 do inRemote.OnServerEvent:Fire(p1, 1, 0) task.wait(0.1) vN = math.max(vN, car.v) end
			p1:SetAttribute("Role", "Hacker")
			-- stop, then let the cops sit next to us: bust fill rate
			for _ = 1, 40 do inRemote.OnServerEvent:Fire(p1, -1, 0) task.wait(0.1) if car.v <= 0.05 then break end end
			inRemote.OnServerEvent:Fire(p1, 0, 0)
			car.v = 0
			car.model:SetAttribute("BustMeter", 0)
			Police:chaseCar(car)
			local startM = waitFor(function() return (car.model:GetAttribute("BustMeter") or 0) > 0.03 end, 15)
			local m0, t0 = car.model:GetAttribute("BustMeter"), SCHED.now
			task.wait(1.0)
			local m1, t1 = car.model:GetAttribute("BustMeter"), SCHED.now
			local rate = (m1 - m0) / (t1 - t0)
			local wantRate = (1 / 4.5) * (it.bustMult or 1)
			Police:recall()
			car.model:SetAttribute("BustMeter", 0)
			local bustOk = startM and near(rate, wantRate, 0.012)
			car:ejectAll() task.wait(0.3)
			local effect = speedOk and nitroOk and bustOk
			local note = string.format("top %.1f (want %.1f) · nitro cd %.1fs top %.1f · bust %.3f/s → full in %.1fs (want %.1fs)",
				vmax, wantV, cd, vN, rate, rate > 0 and 1 / rate or -1, 4.5 / (it.bustMult or 1))
			check(buyOk and equipOk and effect, it.id .. " " .. note)
			row(it.id, buyOk, equipOk, effect, note)
		end
	end
	-- crew pick rule
	local p2 = addPlayerUid("Buddy", 888)
	task.wait(2.5)
	E:addCash(p2, 1000000, "test")
	act(p2, "buyCosmetic", { id = "CarArmored" })
	act(p1, "equipCosmetic", { id = "CarMuscle" })
	task.wait(0.3)
	check(Cos:pickCrewCar({ p1, p2 }) == "CarArmored" and Cos:pickCrewCar({ p1 }) == "CarMuscle", "crew's best car = priciest equipped (p1 Muscle + p2 Armored → " .. Cos:pickCrewCar({ p1, p2 }) .. ")")
	check(VS:getCar().carId == "CarArmored", "club car previews the best car in the server (" .. VS:getCar().carId .. ")")
	removePlayer(p2)
	task.wait(0.5)
	check(VS:getCar().carId == "CarMuscle", "…and drops back when that player leaves (" .. VS:getCar().carId .. ")")

	-- ════ 4. launch mart: car locked to the crew's pick ════
	print("\n==== LAUNCH ====")
	act(p1, "equipCosmetic", { id = "CarMonster" })
	task.wait(0.2)
	local zone = JS.hub.portals.mart.zone
	tp(p1, zone.Position + Vector3.new(0, 3, 0))
	check(waitFor(function() return JS:getPhase() == "running" end, 30), "mart launched")
	task.wait(8.5)
	car = VS:getCar()
	check(car.carId == "CarMonster" and VS:isCrewLocked() and car.trunk == trunk0, "launch → getaway car is the crew's pick (" .. car.carId .. "), locked, same trunk")
	act(p1, "equipCosmetic", { id = "CarRacer" })
	task.wait(0.3)
	check(VS:getCar().carId == "CarMonster", "equipping another car mid-run does NOT swap the getaway car")
	local _, refs = JS:getCurrent()

	-- ════ 5. TRAILS: walk speed, stacks with Fox, crouch cap ════
	print("\n==== TRAILS ====")
	Loot:drop(p1)
	act(p1, "equipMask", { id = "Bandit" })
	task.wait(0.3)
	p1:SetAttribute("Role", "Hacker")
	for _, it in ipairs(cat) do
		if it.category == "trail" then
			local buyOk, equipOk = buyEquip(it)
			task.wait(0.2)
			local m = 1 + it.speedBoost
			local ws1 = hum(p1).WalkSpeed
			local okBase = near(ws1, 16 * m)
			-- Fox Speed on top
			act(p1, "buyMask", { id = "Kitsune" }) act(p1, "equipMask", { id = "Kitsune" })
			task.wait(0.3)
			local ws2 = hum(p1).WalkSpeed
			local okFox = near(ws2, 16 * 1.2 * m)
			-- crouch caps at 8, standing up restores
			Feel:setCrouch(p1, true) task.wait(0.1)
			local ws3 = hum(p1).WalkSpeed
			Feel:setCrouch(p1, false) task.wait(0.1)
			local ws4 = hum(p1).WalkSpeed
			local okCrouch = ws3 == 8 and near(ws4, 16 * 1.2 * m)
			act(p1, "equipMask", { id = "Bandit" })
			task.wait(0.3)
			local ws5 = hum(p1).WalkSpeed
			local okOff = near(ws5, 16 * m)
			local tr = root(p1):FindFirstChild("HC_Trail")
			local vis = (it.color == nil and tr == nil) or (it.color ~= nil and tr ~= nil)
			local effect = okBase and okFox and okCrouch and okOff and vis
			local note = string.format("walk %.2f (x%.2f) · +Fox %.2f · crouch %s → up %.2f · Fox off %.2f · trail=%s", ws1, m, ws2, tostring(ws3), ws4, ws5, tostring(tr ~= nil))
			check(buyOk and equipOk and effect, it.id .. " " .. note)
			row(it.id, buyOk, equipOk, effect, note)
		end
	end
	-- trail survives a respawn (after init.server / MaskService writes)
	spawnCharacter(p1)
	task.wait(2)
	check(near(hum(p1).WalkSpeed, 16 * 1.12), "Rainbow trail speed re-applied after respawn (" .. hum(p1).WalkSpeed .. ")")
	-- carrying a bag: slowed by the loot, trail still multiplies
	local function carry()
		if Loot:isCarrying(p1) then return true end
		for _, pr in ipairs(findPrompts(refs.root)) do if (pr.Name == "BagLoot" or pr.Name == "PickUpBag" or pr.Name == "SmashCase") and pr.Enabled then triggerPrompt(pr, p1) task.wait(0.3) if Loot:isCarrying(p1) then return true end end end
		return false
	end
	carry()
	local kind = p1:GetAttribute("CarryingLoot")
	local li = Loot.info(kind)
	local slow = 16 - li.speed
	check(near(hum(p1).WalkSpeed, (16 - slow) * 1.12), string.format("carrying %s: %.2f = loot speed %d x trail 1.12", tostring(kind), hum(p1).WalkSpeed, li.speed))
	Loot:drop(p1)
	task.wait(0.2)

	-- ════ 6. BAGS: size + value per loaded bag (+ bots keep your bonus) ════
	print("\n==== BAGS ====")
	local function loadOne()
		Loot:reset()
		task.wait(0.1)
		if not carry() then return nil end
		local bag = p1.Character:FindFirstChild("LootBag")
		local k = p1:GetAttribute("CarryingLoot")
		triggerPrompt(VS:getCar().trunk:FindFirstChild("LoadBag"), p1)
		task.wait(0.2)
		local L = Loot:getLoaded()
		return L[#L], bag, k
	end
	for _, it in ipairs(cat) do
		if it.category == "bag" then
			local buyOk, equipOk = buyEquip(it)
			task.wait(0.2)
			local l, bag, k = loadOne()
			local base = Loot.info(k).value
			local want = math.floor(base * it.valueMult + 0.5)
			local sizeOk = bag and bag.Size.X >= 1.7 and bag.Size.X <= 1.9 * (Loot.BAG_MAX_GROWTH or 1.3) + 0.01   -- (2026-09-25) backpack-sized, max x1.3
			local valOk = l and l.value == want and l.base == base and l.tier == it.id
			local effect = sizeOk and valOk
			local note = string.format("bag %.2f wide (x%.2f) · %s $%d → loaded $%s (want $%d)", bag and bag.Size.X or -1, it.scale, tostring(k), base, tostring(l and l.value), want)
			check(buyOk and equipOk and effect, it.id .. " " .. note)
			row(it.id, buyOk, equipOk, effect, note)
		end
	end
	-- a bot carrying YOUR bag keeps your bonus (even if the bot loads it)
	act(p1, "equipCosmetic", { id = "BagPro" })
	Loot:reset() task.wait(0.1)
	carry()
	local k2 = p1:GetAttribute("CarryingLoot")
	local bot = Instance.new("Model") bot.Name = "TestBot"
	local bt = Instance.new("Part") bt.Name = "UpperTorso" bt.Parent = bot
	local bh = Instance.new("Part") bh.Name = "HumanoidRootPart" bh.Parent = bot
	bot:SetAttribute("BotName", "Bot Tony")
	bot.Parent = WORKSPACE
	Loot:transferToBot(p1, bot)
	local botBag = bot:FindFirstChild("LootBag")
	act(p1, "equipCosmetic", { id = "BagClassic" })   -- you switch bags; the bot still has your Pro bag on
	Loot:botLoad(bot)
	local L = Loot:getLoaded()
	local lb = L[#L]
	local wantB = math.floor(Loot.info(k2).value * 1.35 + 0.5)
	check(botBag and botBag.Size.X >= 1.7 and botBag.Size.X <= 2.48 and lb and lb.bot == "Bot Tony" and lb.value == wantB,
		string.format("bot carried the owner's Pro bag (%.2f wide) and loaded it at +35%%: $%s (want $%d)", botBag and botBag.Size.X or -1, tostring(lb and lb.value), wantB))
	print("   (bot load tier " .. tostring(lb and lb.tier) .. " — fixed when the bag was handed over)")
	bot:Destroy()

	-- ════ 7. payout includes the bag bonus ════
	print("\n==== PAYOUT ====")
	act(p1, "equipCosmetic", { id = "BagPro" })
	Loot:reset() task.wait(0.1)
	local expect = 0
	for _ = 1, 2 do
		carry()
		local kk = p1:GetAttribute("CarryingLoot")
		if kk then expect += math.floor(Loot.info(kk).value * 1.35 + 0.5) end
		triggerPrompt(VS:getCar().trunk:FindFirstChild("LoadBag"), p1)
		task.wait(0.2)
	end
	local take = Loot:counts().take
	check(take == expect and expect > 0, "counts().take includes the +35% (take $" .. take .. ", want $" .. expect .. ")")
	car = VS:getCar()
	local cash0 = p1:GetAttribute("Cash")
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1) task.wait(0.3)
	local W = C.WORLD
	car:_placeAt(CFrame.new(W.DROPOFF.x, W.DROPOFF.y, W.DROPOFF.z))
	waitFor(function() return JS:getPhase() ~= "running" end, 15)
	task.wait(1)
	local hs = REMOTE_LOG and REMOTE_LOG["HeistState"]
	local payload = hs and hs[3]
	local gained = p1:GetAttribute("Cash") - cash0
	check(payload and payload.take == expect and gained >= expect, string.format("payout: HeistState take $%s (want $%d), cash +$%d", tostring(payload and payload.take), expect, gained))
	-- after the run: car unlocks and goes back to the server's best (p1 now has Racer equipped)
	task.wait(5)
	check(not VS:isCrewLocked() and VS:getCar().carId == "CarRacer", "after the run the car unlocks → club preview = Racer (" .. VS:getCar().carId .. ")")

	-- ════ 8. save / load keeps everything ════
	print("\n==== SAVE / LOAD ====")
	local before = act(p1, "getState").state
	PD:savePlayer(p1)
	removePlayer(p1)
	task.wait(2)
	local p1b = addPlayerUid("Malachi", 777)
	task.wait(3)
	p1b:SetAttribute("VIP", true)
	task.wait(0.3)
	local after = act(p1b, "getState").state
	local function set(t) local o = {} for _, x in ipairs(t or {}) do o[x] = true end return o end
	local same = true for _, it in ipairs(cat) do if set(before.cosmetics.owned)[it.id] ~= set(after.cosmetics.owned)[it.id] then same = false print("   diff", it.id) end end
	check(same, "owned gear survives save/load (" .. #after.cosmetics.owned .. " items)")
	for _, k in ipairs({ "bag", "car", "trail" }) do
		check(before.cosmetics.equipped[k] == after.cosmetics.equipped[k], "equipped " .. k .. " survives (" .. tostring(after.cosmetics.equipped[k]) .. ")")
	end
	task.wait(1.5)
	check(near(hum(p1b).WalkSpeed, 16 * 1.12), "rejoin: trail speed applied (" .. hum(p1b).WalkSpeed .. ")")

	print("\n==== ITEM TABLE ====")
	for _, r2 in ipairs(ROWS) do print(r2) end
	print("\n==== CHECK SUMMARY ====")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 print(c) end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 1500)
report()
