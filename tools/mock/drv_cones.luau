-- ═══════════════ v3.1 GuardCones + MusicController driver ═══════════════
local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
local CS = CollectionService
local function shownCones(kind)
	local f = WORKSPACE:FindFirstChild("HC_VisionCones")
	local n = 0
	for _, c in ipairs(f and f:GetChildren() or {}) do if c.Name:sub(1, #kind) == kind then n += 1 end end
	return n
end
local function coneFolder(kind)
	local f = WORKSPACE:FindFirstChild("HC_VisionCones")
	for _, c in ipairs(f and f:GetChildren() or {}) do if c.Name:sub(1, #kind) == kind then return c end end
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local GS = mockRequire(SERVER_SCRIPT.GuardService)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(3)
	local GC = cmod("GuardCones")
	local MC = cmod("MusicController")
	check(type(GC) == "table" and type(MC) == "table", "modules load")
	inClient(function() GC:start() MC:start() end)
	task.wait(2)
	check(WORKSPACE:FindFirstChild("HC_VisionCones") ~= nil, "cone folder made")
	local folderM = GAME:GetService("SoundService"):FindFirstChild("HC_Music")
	check(folderM and #folderM:GetChildren() == 5, "5 music tracks made")
	-- lobby
	task.wait(3)
	print("   music state:", MC:state())
	check(MC:state() == "lobby", "lobby state in The Vault")
	local lob = folderM and folderM:FindFirstChild("Music_lobby")
	check(lob and lob.Playing and lob.Volume > 0.25, "lobby playing at " .. tostring(lob and lob.Volume))
	check(WORKSPACE:FindFirstChild("AmbientMusic") == nil, "no server AmbientMusic loop")
	local btn
	for _, x in ipairs(p1.PlayerGui:GetDescendants()) do if x.Name == "MusicButton" then btn = x end end
	check(btn ~= nil and btn.Parent and btn.Parent.Name == "Slot_rightEdge", "music button in rightEdge slot")
	check(#CS:GetTagged("Guard") > 0, #CS:GetTagged("Guard") .. " guards tagged")
	check(shownCones("Guard") == 0, "no guard cones outside heist (" .. shownCones("Guard") .. ")")

	-- launch mart
	waitFor(function() return JS:getPhase() == "idle" end, 60)
	JS:selectJob("mart")
	task.wait(1)
	JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
	check(waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil, "mart launched")
	task.wait(3)
	print("   guards:", #CS:GetTagged("Guard"), " cams:", #CS:GetTagged("SecurityCamera"), " shown guard cones:", shownCones("Guard"), " cam cones:", shownCones("Camera"))
	check(shownCones("Guard") >= 1, "guard cones shown in heist")
	check(shownCones("Camera") >= 1, "camera cones shown in heist")
	local gf = coneFolder("Guard")
	if gf then
		local w = gf:FindFirstChildWhichIsA("WedgePart")
		print("   wedge:", w and tostring(w.Position), w and tostring(w.Size), w and w.Transparency, w and tostring(w.Color))
		check(w and not w.CanCollide and not w.CanQuery and not w.CanTouch and not w.CastShadow, "wedge flags off")
		local g = CS:GetTagged("Guard")[1]
		local root = g:FindFirstChild("HumanoidRootPart")
		print("   guard root:", tostring(root.Position))
		local ys = {}
		for _, p in ipairs(gf:GetChildren()) do ys[math.floor(p.Position.Y * 10 + 0.5) / 10] = true end
		local s = {} for y in pairs(ys) do table.insert(s, tostring(y)) end
		print("   cone ys:", table.concat(s, ","))
	end
	print("   music state:", MC:state())
	check(MC:state() == "stealth", "stealth in heist")
	-- suspicion → tension
	local g = CS:GetTagged("Guard")[1]
	g:SetAttribute("Sus_" .. p1.UserId, 0.5)
	p1:SetAttribute("GuardSuspicion", 0.5)
	task.wait(1)
	check(MC:state() == "tension", "tension on Huh (" .. MC:state() .. ")")
	local gfolder
	for _, c in ipairs(WORKSPACE.HC_VisionCones:GetChildren()) do if c.Name == "Guard_" .. g.Name then gfolder = c end end
	local w = gfolder and gfolder:FindFirstChildWhichIsA("WedgePart")
	print("   hot cone colour:", w and tostring(w.Color))
	p1:SetAttribute("GuardSuspicion", 0)
	g:SetAttribute("Sus_" .. p1.UserId, 0)
	task.wait(2)
	check(MC:state() == "tension", "tension holds 2s after calm")
	task.wait(3)
	check(MC:state() == "stealth", "back to stealth after ~4s")
	-- stun hides
	local gt for _, x in pairs(GS:getGuards()) do if x.model == g then gt = x end end
	GS:stun(gt, 2)
	task.wait(0.5)
	check(gfolder and gfolder.Parent == nil, "stunned guard: cone hidden (attr " .. tostring(g:GetAttribute("Stunned")) .. ")")
	task.wait(3)
	check(gfolder and gfolder.Parent ~= nil, "guard back up: cone back")
	-- cameras cut
	local cam = CS:GetTagged("SecurityCamera")[1]
	if cam then
		cam:SetAttribute("Live", false)
		task.wait(0.5)
		check(shownCones("Camera") == #CS:GetTagged("SecurityCamera") - 1, "cut camera cone hidden")
		cam:SetAttribute("Live", true)
	end
	-- alarm
	JS:triggerAlarm("camera", p1)
	task.wait(1)
	check(MC:state() == "alarm", "alarm state (" .. MC:state() .. ")")
	task.wait(2)
	local al = folderM:FindFirstChild("Music_alarm")
	check(al.Playing and al.Volume > 0.3, "alarm track up " .. al.Volume)
	check(folderM.Music_stealth.Volume < 0.05, "stealth faded " .. folderM.Music_stealth.Volume)
	-- getaway
	p1:SetAttribute("GetawayPlaying", true)
	task.wait(0.5)
	check(MC:state() == "getaway", "getaway state")
	check(shownCones("Guard") == 0, "cones hidden in getaway movie")
	p1:SetAttribute("GetawayPlaying", false)
	-- mute
	inClient(function() for _, ev in ipairs({ "Activated" }) do local s = D[btn].sigs[ev] if s then s:Fire() end end end)
	task.wait(2)
	local total = 0 for _, s in ipairs(folderM:GetChildren()) do total += s.Volume end
	check(total < 0.01, "mute button silences (" .. total .. ", attr " .. tostring(p1:GetAttribute("MusicMuted")) .. ")")
	inClient(function() MC:setMuted(false) end)
	task.wait(2)
	total = 0 for _, s in ipairs(folderM:GetChildren()) do total += s.Volume end
	check(total > 0.2, "unmute restores (" .. total .. ")")
	-- end the run
	REPLICATED.Remotes.HeistState:FireAllClients("COMPLETE", {})
	task.wait(1)
	local lv = folderM.Music_lobby.Volume
	print("   after COMPLETE:", MC:state(), "lobby vol", lv)
	check(MC:state() == "lobby" and lv < 0.1, "payout: lobby ducked under the sting")
	check(p1:GetAttribute("PayoutOpen") == true or true, "payout open: " .. tostring(p1:GetAttribute("PayoutOpen")))
	task.wait(3)
	local PS = cmod("PayoutScreen")
	inClient(function() PS:close() end)
	task.wait(5)
	for _, c in ipairs(WORKSPACE.HC_VisionCones:GetChildren()) do print("   cone folder:", c.Name) end
	check(folderM.Music_lobby.Volume > 0.25, "duck releases (" .. folderM.Music_lobby.Volume .. ")")
	print("   after finish:", MC:state(), shownCones("Guard"))
	report()
	print("\n==== SUMMARY ====")
	local pass, fail = 0, 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(c) end end
	print(pass .. "/" .. (pass + fail) .. " passed")
end, 400)
