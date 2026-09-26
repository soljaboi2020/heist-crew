local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local E = mockRequire(SERVER_SCRIPT.EconomyService)
	local VS = mockRequire(SERVER_SCRIPT.VehicleService)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(4)
	E:addCash(p1, 500000, "test")
	local Shop = cmod("ShopUI")
	inClient(function() Shop:open() end)
	task.wait(1.5)
	local pg = p1.PlayerGui
	local gui = pg:FindFirstChild("ShopUI")
	local page = gui:FindFirstChild("Page_car", true)
	local real, pills = 0, {}
	for _, vf in ipairs(page:GetDescendants()) do
		if vf:IsA("ViewportFrame") then
			for _, m in ipairs(vf:GetChildren()) do
				if m:IsA("Model") and m.Name:sub(1, 3) == "Car" and #m:GetDescendants() > 20 then real += 1 end
			end
		end
	end
	check(real == 6, "car cards preview the REAL car models (" .. real .. "/6)")
	for _, cat in ipairs({ "bag", "car", "trail" }) do
		local pg2 = gui:FindFirstChild("Page_" .. cat, true)
		local shown, sizes = {}, 0
		for _, x in ipairs(pg2:GetDescendants()) do
			if x:IsA("Frame") and x.Name == "Pill" and x.Visible then
				local l = x:FindFirstChildWhichIsA("TextLabel")
				table.insert(shown, l and l.Text or "?")
			end
		end
		for _, x in ipairs(gui:GetDescendants()) do if x:IsA("TextLabel") and x.Text:sub(1, 5) == "SIZE " and x:IsDescendantOf(pg2) then sizes += 1 end end
		check(#shown == 6, cat .. " cards show a power pill: " .. table.concat(shown, " | ") .. (cat == "bag" and (" · size tags " .. sizes) or ""))
	end
	-- click every car card (buy/equip) and watch the club car follow
	inClient(function() Shop:_selectTab("car", true) end)
	print("   clicked:", clickAllButtons(page))
	task.wait(2)
	print("   lobby car now:", VS:getCar().carId, "CarType attr:", p1:GetAttribute("CarType"))
	inClient(function() Shop:close() end)
	-- CarHud label
	local car = VS:getCar()
	triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
	task.wait(1)
	local hud = pg:FindFirstChild("CarPanel", true)
	local CH = cmod("CarHud")
	print("   hud visible", hud and hud.Visible, "CarHud.car", CH and CH.car, "seatpart", p1.Character.Humanoid.SeatPart, "driver", car:getDriver())
	inClient(function() CH:_onSeat(car.driverSeat) CH:_update() end)   -- (mock doesn't replicate SeatPart signals to the client)
	local nm = hud and hud:FindFirstChild("CarName")
	check(nm and nm.Text ~= "", "CarHud shows the car type: '" .. tostring(nm and nm.Text) .. "' / '" .. tostring(hud and hud:FindFirstChild("CarPerk") and hud.CarPerk.Text) .. "'")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 200)
report()
