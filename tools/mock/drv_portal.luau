local fails = 0
local function check(ok, what) print((ok and "  [ok] " or "  [FAIL] ") .. what) if not ok then fails += 1 end end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < timeout do if cond() then return true end task.wait(0.25) end return false end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local hub = JS.hub
	local calls = {}
	for id, po in pairs(hub.portals) do
		local orig = po.setState
		po.setState = function(...) table.insert(calls, { id, ... }) return orig(...) end
	end
	local spawns = {}
	for _, x in ipairs(WORKSPACE:GetDescendants()) do if x:IsA("SpawnLocation") then table.insert(spawns, x:GetFullName() .. " enabled=" .. tostring(x.Enabled)) end end
	print("SpawnLocations:\n   " .. table.concat(spawns, "\n   "))
	local p1 = addPlayer("A")
	local p2 = addPlayer("B")
	task.wait(1)
	for _, p in ipairs({ p1, p2 }) do
		local best = math.huge
		for _, pad in ipairs(hub.spawnPads) do best = math.min(best, (p.Character.HumanoidRootPart.Position - pad.Position).Magnitude) end
		check(best < 6, p.Name .. " spawned on a club spawn pad (" .. string.format("%.1f", best) .. ")")
	end
	-- half the server in the villa portal → 15 s countdown
	p1.Character:PivotTo(CFrame.new(hub.portals.villa.zone.Position + Vector3.new(0, 3, 0)))
	task.wait(1.5)
	check(JS:getCurrentId() == "villa", "busiest portal picked villa")
	local la, src = JS:getLaunch()
	check(la > 0 and src == "portal" and math.abs((la - WORKSPACE:GetServerTimeNow()) - 14) < 2, "half the server → ~15 s countdown (" .. string.format("%.1f", la - WORKSPACE:GetServerTimeNow()) .. ")")
	local sawCountdown = false
	for _, c in ipairs(calls) do if c[1] == "villa" and c[4] ~= nil then sawCountdown = true end end
	check(sawCountdown, "setState got a launchIn for villa")
	-- step out → cancel
	p1.Character:PivotTo(CFrame.new(hub.spawnPads[1].Position + Vector3.new(0, 3, 0)))
	task.wait(1)
	check(JS:getLaunch() == 0, "leaving the portal cancels the countdown")
	-- step back in, second joins → shortened to 5 s
	p1.Character:PivotTo(CFrame.new(hub.portals.villa.zone.Position + Vector3.new(0, 3, 0)))
	task.wait(3)
	p2.Character:PivotTo(CFrame.new(hub.portals.villa.zone.Position + Vector3.new(1, 3, 0)))
	task.wait(0.6)
	local la2 = JS:getLaunch()
	check(la2 > 0 and la2 - WORKSPACE:GetServerTimeNow() <= 5.5, "everyone in → countdown shortened to 5 s (" .. string.format("%.1f", la2 - WORKSPACE:GetServerTimeNow()) .. ")")
	-- p2 leaves portal before launch → still launches (half)? then only p1 goes
	p2.Character:PivotTo(CFrame.new(hub.spawnPads[2].Position + Vector3.new(0, 3, 0)))
	check(waitFor(function() return JS:getPhase() == "running" end, 20), "launched")
	check(JS:isInRun(p1) and not JS:isInRun(p2), "only the player in the portal dropped in")
	local locked = true
	task.wait(1)
	for _, c in ipairs(calls) do if c[5] == false then end end
	local last = {}
	for _, c in ipairs(calls) do last[c[1]] = c end
	for id, c in pairs(last) do check(c[5] == true, "portal " .. id .. " shows locked while running") end
	local pr = REMOTE_LOG.Portal
	check(pr and type(pr[2].portals) == "table" and pr[2].portals.villa and pr[2].portals.villa.locked == true, "Portal remote payload {portals={villa={locked=true..}}}")
	print(string.format("%d portal checks failed", fails))
end, 200)
report()
