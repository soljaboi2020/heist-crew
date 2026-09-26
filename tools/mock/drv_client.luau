local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local E = mockRequire(SERVER_SCRIPT.EconomyService)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(4)
	E:addCash(p1, 500000, "test")
	local pg = p1.PlayerGui
	-- every client module started?
	local n, bad = 0, {}
	for _, m in ipairs(CLIENT_SCRIPT_TEMPLATE:GetChildren()) do
		if m:IsA("ModuleScript") then
			n += 1
			local mod = cmod(m.Name)
			if type(mod) ~= "table" or type(mod.start) ~= "function" then table.insert(bad, m.Name) end
		end
	end
	check(#bad == 0, n .. " client modules loaded with :start() (bad: " .. table.concat(bad, ",") .. ")")

	-- ── DailyRewardUI open path ──
	local DR = cmod("DailyRewardUI")
	local btn
	for _, x in ipairs(pg:GetDescendants()) do if x.Name == "DailyButton" then btn = x end end
	check(btn ~= nil and btn:IsA("GuiButton"), "DailyRewardUI reopen button exists in a UITheme slot (" .. tostring(btn and btn:GetFullName()) .. ")")
	if btn then inClient(function() for _, ev in ipairs({ "Activated", "MouseButton1Click" }) do local s = D[btn].sigs[ev] if s then s:Fire() end end end) end
	task.wait(1)
	local drGui = pg:FindFirstChild("DailyRewardUI")
	local vis = 0
	for _, x in ipairs(drGui and drGui:GetDescendants() or {}) do if x:IsA("GuiObject") and x.Visible and x:IsA("TextLabel") and x.Text ~= "" then vis += 1 end end
	check(DR._open == true and DR._group and DR._group.Visible == true, "DailyRewardUI opens from its button (open=" .. tostring(DR._open) .. ", " .. vis .. " labels)")
	print("   clicked in daily UI:", clickAllButtons(drGui))
	task.wait(1)
	inClient(function() if DR.close then DR:close() end end)
	task.wait(1)
	check(DR._open ~= true, "DailyRewardUI closes")
	pressKey(Enum.KeyCode.Escape)

	-- ── ShopUI: every tab ──
	local Shop = cmod("ShopUI")
	inClient(function() Shop:open() end)
	task.wait(1)
	for _, tab in ipairs({ "gear", "masks", "bag", "car", "trail", "cash", "codes", "vip" }) do
		inClient(function() Shop:open() Shop:_selectTab(tab, true) end)
		task.wait(0.5)
		local shopGui = pg:FindFirstChild("ShopUI")
		local vp, cards, labels = 0, 0, {}
		for _, x in ipairs(shopGui:GetDescendants()) do
			local shown = x:IsA("GuiObject") and x.Visible
			local a = x.Parent
			while shown and a and a ~= shopGui do if a:IsA("GuiObject") and not a.Visible then shown = false end a = a.Parent end
			if shown then
				if x:IsA("ViewportFrame") then vp += 1 end
				if x:IsA("ImageLabel") and tostring(x.Image):find("rbxthumb") then cards += 1 end
				if x:IsA("TextLabel") and #labels < 4 and x.Text ~= "" then table.insert(labels, x.Text) end
			end
		end
		print(string.format("   tab %-6s visible ViewportFrames=%d rbxthumb images=%d  e.g. %s", tab, vp, cards, table.concat(labels, " | ")))
		if tab == "masks" then check(cards >= 8 or vp >= 8, "masks tab shows a picture per mask (thumbs " .. cards .. ", viewports " .. vp .. ")") end
		if tab == "bag" or tab == "car" then check(vp >= 5, tab .. " tab shows ViewportFrame previews (" .. vp .. ")") end
		if tab == "cash" then
			local packs = 0
			for _, x in ipairs(shopGui:GetDescendants()) do if x:IsA("TextLabel") and x.Visible and (x.Text:find("R%$") or x.Text:find("Robux")) then packs += 1 end end
			check(packs >= 4, "cash tab lists the 4 Robux packs (" .. packs .. " R$ labels)")
		end
		local clicked = clickAllButtons(shopGui)
		task.wait(1)
	end
	inClient(function() Shop:close() end)
	task.wait(1)
	check(pg:FindFirstChild("ShopUI") ~= nil, "shop survived every tab + button")

	-- ── run a job for JobHud + WaypointHud ──
	tp = function(p, pos) p.Character:PivotTo(CFrame.new(pos)) end
	tp(p1, JS.hub.portals.mart.zone.Position + Vector3.new(0, 3, 0))
	check(waitFor(function() return JS:getPhase() == "running" end, 30), "mart launched")
	task.wait(2)
	local JH = cmod("JobHud")
	local wasC = JH._collapsed
	inClient(function() JH:_toggle() end)
	task.wait(0.5)
	check(wasC == true, "JobHud starts FOLDED (v3.2)")
	check(JH._collapsed == false and JH._steps.Visible == true, "JobHud opens on toggle (steps shown)")
	inClient(function() JH:_toggle() end)
	task.wait(0.5)
	check(JH._collapsed == true and JH._steps.Visible == false, "JobHud collapses (steps hidden)")
	pressKey(Enum.KeyCode.J) task.wait(0.3)
	local toggle
	for _, x in ipairs(pg:GetDescendants()) do if x.Name == "Toggle" and x:IsA("GuiButton") then toggle = x end end
	if JH._collapsed and toggle then inClient(function() D[toggle].sigs.Activated:Fire() end) end
	task.wait(0.5)
	check(JH._collapsed == false and JH._steps.Visible == true, "JobHud expands again via its Toggle button")

	-- WaypointHud: flood it with targets near the player
	local info = REMOTE_LOG["JobInfo"] and REMOTE_LOG["JobInfo"][2]
	if not info then info = REMOTE_LOG["JobInfo"] and REMOTE_LOG["JobInfo"][1] end
	local base = p1.Character.HumanoidRootPart.Position
	local fake = table.clone(type(info) == "table" and info or {})
	fake.targets = {}
	local kinds = { "loot", "search", "door", "vault", "car", "loot", "loot", "marina", "optional" }
	for i, k in ipairs(kinds) do table.insert(fake.targets, { pos = base + Vector3.new(math.cos(i) * 8, 0, math.sin(i) * 8), label = k:upper(), kind = k }) end
	local jr = REPLICATED.Remotes.JobInfo
	local cam = WORKSPACE.CurrentCamera
	local maxVis = 0
	for i = 1, 20 do
		cam.CFrame = CFrame.lookAt(base + Vector3.new(0, 12, 18), base)
		jr:FireClient(p1, fake)
		task.wait(0.1)
		local v = 0
		local wg = pg:FindFirstChild("WaypointHud")
		for _, x in ipairs(wg and wg:GetChildren() or {}) do if x.Name == "Marker" and x.Visible then v += 1 end end
		maxVis = math.max(maxVis, v)
	end
	check(maxVis >= 1 and maxVis <= 3, "WaypointHud with " .. #fake.targets .. " targets shows at most 3 markers (max seen " .. maxVis .. ")")

	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 400)
report()
