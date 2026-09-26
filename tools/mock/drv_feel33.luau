local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(12)
	local pg = p1.PlayerGui
	local N, FX, Tip, CF = cmod("Notifications"), cmod("FeelFX"), cmod("TipHud"), cmod("CameraFeel")
	task.wait(8)
	local z = inClient(function() local lp = p1 return { lp.CameraMinZoomDistance, lp.CameraMaxZoomDistance, lp == p1 } end)
	check(z and z[1] == 6 and z[2] == 24, "zoom range 6..24 (" .. tostring(z and z[1]) .. ".." .. tostring(z and z[2]) .. " same=" .. tostring(z and z[3]) .. ")")
	-- toasts: one at a time + dedupe + echo
	local function toasts() local n = 0 for _, d in ipairs(pg:GetDescendants()) do if d.Name == "Toast" and d:IsA("CanvasGroup") then n += 1 end end return n end
	task.wait(6)
	inClient(function()
		N:show("A guard saw you! You're back at the door. Sneak back in!", "red", 4)
		N:show(p1.DisplayName .. " got sent back to the door", "white", 2)
		N:show("hello", "gold", 2) N:show("hello", "gold", 2) N:show("second", "white", 2)
	end)
	task.wait(0.5)
	check(toasts() == 1, "only ONE toast visible (" .. toasts() .. ")")
	check(#N._queue == 2, "queue = hello + second (echo + duplicate dropped) → " .. #N._queue)
	check(waitFor(function() return #N._queue == 0 and toasts() == 0 end, 15) ~= nil, "queue drains")
	-- banner lock ordering: fade hold → title set → jackpot queued → tip waits
	local log = {}
	inClient(function()
		FX:holdBig(6)
		FX:queueBig(2, function() table.insert(log, { "jackpot", SCHED.now }) end)
	end)
	task.wait(1)
	inClient(function() FX:setBig(2.6) table.insert(log, { "title", SCHED.now }) end)
	p1:SetAttribute("Rookie", true) p1:SetAttribute("Tutorial", nil)
	Tip._seen.bag = nil
	inClient(function() Tip:show("bag") end)
	task.wait(0.5)
	print("DBG", inClient(function() return tostring(p1:GetAttribute("Rookie")) .. " q=" .. #Tip._queue .. " seen=" .. tostring(Tip._seen.bag) .. " busy=" .. tostring(FX:isBigBusy()) .. " tut=" .. tostring(p1:GetAttribute("Tutorial")) end))
	check(Tip._showing == nil, "tip waits while the title/jackpot hold the centre")
	local sh = waitFor(function() return Tip._showing end, 8) check(sh ~= nil, "a tip shows after the jackpot (" .. tostring(sh) .. ")")
	check(#log == 2 and log[2][1] == "jackpot" and log[2][2] - log[1][2] >= 2.5, "jackpot ran after the title (" .. (log[2] and (log[2][2] - log[1][2]) or -1) .. "s)")
	-- banner dedupe
	local before = 0
	inClient(function() FX:banner("CAMERAS OFF") FX:banner("CAMERAS OFF") end)
	task.wait(0.2)
	local holder = pg.FeelFX.Banner
	check(#holder:GetChildren() == 1, "banner shown once")
	-- camera: scripted → restoreBehind → Custom + behind
	local r = inClient(function()
		local cam = WORKSPACE.CurrentCamera
		local root = p1.Character.HumanoidRootPart
		p1.Character:PivotTo(CFrame.lookAt(root.Position, root.Position + Vector3.new(1, 0, 0)))
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(4, 0, 0), root.Position)   -- face-on like the mask shot
		CF.restoreBehind()
		task.wait(0.1)
		local toChar = (root.Position - cam.CFrame.Position)
		return { cam.CameraType == Enum.CameraType.Custom, cam.CFrame.LookVector.X, toChar.X }
	end)
	check(r and r[1], "camera back to Custom")
	check(r and r[2] > 0.8 and r[3] > 0, "camera behind the character looking where it faces (look.x=" .. tostring(r and r[2]) .. ")")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 20000)
report()
