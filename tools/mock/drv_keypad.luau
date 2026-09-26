-- ad-hoc v3.3: one keypad prompt on E (swipe / hack / need keycard)
local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout, step) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(step or 0.1) end return nil end
local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS, Sec = srv("JobService"), srv("SecurityService")
	local p1 = addPlayer("Hax")
	local p2 = addPlayer("Plain")
	startClient(p1)
	task.wait(4)
	local errs0 = #LOG.errors
	JS:selectJob("villa")
	task.wait(0.5)
	JS:startLaunchCountdown(0, function() return { p1, p2 } end, "portal")
	check(waitFor(function() return JS:getPhase() == "running" end, 25) ~= nil, "villa launched")
	for _, g in pairs(srv("GuardService"):getGuards()) do srv("GuardService"):stun(g, 500) end
	local _, refs = JS:getCurrent()
	local panel = refs.keycardDoors[1].panel
	local n = 0
	for _, d in ipairs(panel:GetDescendants()) do if d:IsA("ProximityPrompt") then n += 1 end end
	local sw = panel:FindFirstChild("Swipe", true)
	check(n == 1 and sw and sw.KeyboardKeyCode == Enum.KeyCode.E and sw.ObjectText == "Keypad", "ONE keypad prompt on E, ObjectText Keypad (" .. n .. ")")
	check(panel:FindFirstChild("HackKeypad", true) == nil, "no separate H hack prompt")
	p1:SetAttribute("Role", "Hacker")
	p2:SetAttribute("Role", "Lookout")
	task.wait(0.3)
	local seen = inClient(function() local C = mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild("CrewHud")) C:_filterPrompt(sw) return sw.ActionText .. "|" .. sw.HoldDuration end)
	check(seen == "Hack it (Hacker)|4", "Hacker without card sees 'Hack it (Hacker)' 4 s on HIS client (" .. tostring(seen) .. ")")
	p1:SetAttribute("HasKeycard", true)
	task.wait(0.3)
	local seen2 = inClient(function() return sw.ActionText .. "|" .. sw.HoldDuration end)
	check(seen2 == "Swipe keycard|0.3", "picking up the card switches it to 'Swipe keycard' (" .. tostring(seen2) .. ")")
	p1:SetAttribute("HasKeycard", false)
	task.wait(0.3)
	triggerPrompt(sw, p2)
	task.wait(0.3)
	local nt = REMOTE_LOG.Notify
	check(not Sec:doorsOpen() and nt and tostring(nt[2].text):find("need the keycard"), "no card, not Hacker → 'You need the keycard (or a Hacker)' (" .. tostring(nt and nt[2].text) .. ")")
	triggerPrompt(sw, p1)   -- mock: instant (a tap)
	task.wait(0.3)
	nt = REMOTE_LOG.Notify
	check(not Sec:doorsOpen() and nt and tostring(nt[2].text):find("Hold E to hack"), "Hacker tap (no real hold) → 'Hold E to hack it!' (" .. tostring(nt and nt[2].text) .. ")")
	-- a real 4 s hold
	getSig(sw, "PromptButtonHoldBegan"):Fire(p1)
	task.wait(3.6)
	getSig(sw, "Triggered"):Fire(p1)
	getSig(sw, "PromptButtonHoldEnded"):Fire(p1)
	task.wait(0.5)
	check(Sec:doorsOpen(), "Hacker held E ~4 s → door open")
	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 600)
report()
