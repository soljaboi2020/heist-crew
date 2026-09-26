-- ═══════════════ v3.4 GOAL CHAIN driver (villa / jewelry / bank) ═══════════════
-- Every heist plays one goal at a time: cameras → keycard → door → vault → loot → GO.
-- Also: an E-prompt clash audit (the mart bug where "Climb to the roof" beat
-- "Place drill"), and a sidewalk-clearance survey for arrival spots.
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
local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
local function root(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function tp(p, pos) if root(p) then p.Character:PivotTo(CFrame.new(pos)) end end
local function remote(name) return REPLICATED.Remotes:FindFirstChild(name) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
-- trigger a prompt WITHOUT the mock's "+2 z" teleport (that dropped us into the bank lasers)
-- which way a wall panel's screen faces (its SurfaceGui face), in world space
local function screenDir(part)
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("SurfaceGui") then
			local f = c.Face
			if f == Enum.NormalId.Front then return part.CFrame.LookVector end
			if f == Enum.NormalId.Back then return -part.CFrame.LookVector end
			if f == Enum.NormalId.Right then return part.CFrame.RightVector end
			if f == Enum.NormalId.Left then return -part.CFrame.RightVector end
		end
	end
	return -part.CFrame.LookVector
end
local function fireAt(prompt, player)
	if not prompt.Enabled then return false end
	getSig(prompt, "PromptButtonHoldBegan"):Fire(player)
	ProximityPromptService.PromptButtonHoldBegan:Fire(prompt, player)
	getSig(prompt, "Triggered"):Fire(player)
	ProximityPromptService.PromptTriggered:Fire(prompt, player)
	getSig(prompt, "PromptButtonHoldEnded"):Fire(player)
	getSig(prompt, "TriggerEnded"):Fire(player)
	ProximityPromptService.PromptTriggerEnded:Fire(prompt, player)
	return true
end

local function promptPos(pr)
	local par = pr.Parent
	if not par then return nil end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Model") then return par:GetPivot().Position end
	return nil
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	local Loot = srv("LootService")
	local MU = srv("MaskUpService")
	local Sec = srv("SecurityService")
	local GS = srv("GetawayService")
	local Constants = mockRequire(REPLICATED.Shared.Constants)
	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(4)
	p1:SetAttribute("Tutorial", nil)
	p1:SetAttribute("UnlockAll", true)
	local errs0 = #LOG.errors
	task.spawn(function()
		local last
		while true do
			local l = REMOTE_LOG.Notify
			if l ~= last then
				last = l
				local txt = l and tostring(l[2])
				if txt and (txt:find("ALARM") or txt:find("alarm")) then
					local r = root(p1)
					print(string.format("   >>> %s  (p1 at %.1f, %.1f, %.1f)", txt, r and r.Position.X or 0, r and r.Position.Y or 0, r and r.Position.Z or 0))
				end
			end
			task.wait(0.05)
		end
	end)
	local function info() local l = REMOTE_LOG.JobInfo return l and l[2] end
	local function current(i)
		for _, s in ipairs((i or {}).steps or {}) do if not s.done and not s.optional then return s end end
	end
	local function stepsStr(i)
		local t = {}
		for _, s in ipairs((i or {}).steps or {}) do table.insert(t, (s.done and "✓" or (s.optional and "○" or "·")) .. s.id .. "=" .. s.label) end
		return table.concat(t, " | ")
	end
	local function targetsStr(i)
		local t = {}
		for _, x in ipairs((i or {}).targets or {}) do table.insert(t, x.kind .. ":" .. x.label) end
		return table.concat(t, ", ")
	end
	local function solidAt(p, w)
		local hits = {}
		for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(p), Vector3.new(w, 4, w))) do
			if x.CanCollide and not (x:FindFirstAncestorOfClass("Model") and x:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid")) then
				table.insert(hits, x.Name)
			end
		end
		return hits
	end

	-- ═══ SIDEWALK SURVEY (where can an arrival stand?) ═══
	print("\n==== SIDEWALK SURVEY ====")
	for _, cx in ipairs({ -64, 108 }) do
		local row = {}
		for x = cx - 8, cx + 8, 1 do
			local cells = ""
			for _, z in ipairs({ -2.0, -3.4, -5.2 }) do
				cells = cells .. ((#solidAt(Vector3.new(x, 3.5, z), 2.6) > 0) and "#" or ".")
			end
			table.insert(row, string.format("%d:%s", x, cells))
		end
		print(string.format("   x=%d  (z -2.0/-3.4/-5.2)  %s", cx, table.concat(row, " ")))
		for x = cx - 8, cx + 8, 2 do
			local h = solidAt(Vector3.new(x, 3.5, -3.4), 2.6)
			if #h > 0 then print(string.format("     (%d, -3.4) blocked by %s", x, table.concat(h, "/"))) end
		end
	end

	for _, jobId in ipairs({ "villa", "jewelry", "bank" }) do
		print("\n\n################ " .. jobId .. " ################")
		JS:selectJob(jobId)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		check(refs.goalChain == true, jobId .. ": goal chain on")
		if refs.arrival then
			local a = refs.arrival
			local back = flat(a.at - a.face).Unit
			local dbad = {}
			for i = 1, 8 do
				local row, col = (i - 1) % 4, math.floor((i - 1) / 4)
				local p = a.at + a.spread * ((row - 1.5) * 2) + back * (col * (a.rowGap or 2))
				local h = solidAt(p, 2.6)
				if #h > 0 then table.insert(dbad, string.format("(%.1f,%.1f) %s", p.X, p.Z, table.concat(h, "/"))) end
			end
			check(#dbad == 0, jobId .. ": all 8 arrival drop points clear " .. table.concat(dbad, "; "))
		end

		JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
		check(waitFor(function() return JS:getPhase() == "running" end, 20) ~= nil, jobId .. " launched")
		task.wait(0.6)
		local lp = root(p1).Position
		print(string.format("   landed at (%.1f, %.1f, %.1f)  casing=%s", lp.X, lp.Y, lp.Z, tostring(p1:GetAttribute("Casing"))))
		local PUBLIC = { jewelry = Vector3.new(-64, 3.5, 8), bank = Vector3.new(108, 4.5, 18) }
		local BACK = { jewelry = Vector3.new(-62, 3.5, 24), bank = Vector3.new(115, 4.5, 33.5) }
		if refs.arrival then
			check(lp.Z < -1.5 and lp.Z > -6 and math.abs(lp.X - refs.arrival.at.X) < 4, jobId .. ": lands on the sidewalk")
			check(root(p1).CFrame.LookVector.Z > 0.8, jobId .. ": faces the building")
			check(p1:GetAttribute("Casing") == true, jobId .. ": casing (unmasked customer)")
			local function zoneAt(pt)
				for _, z in ipairs(MU:zones()) do
					if z.x0 and pt.X >= z.x0 and pt.X <= z.x1 and pt.Z >= z.z0 and pt.Z <= z.z1 then return z end
				end
			end
			local zs = {}
			for _, z in ipairs(MU:zones()) do table.insert(zs, (z.name or "?") .. (z.crime and "!" or "")) end
			print("   restricted zones: " .. table.concat(zs, ", "))
			check(zoneAt(PUBLIC[jobId]) == nil, jobId .. ": front room is public")
			check(zoneAt(BACK[jobId]) ~= nil, jobId .. ": back of house is staff-only (" .. tostring(zoneAt(BACK[jobId]) and zoneAt(BACK[jobId]).name) .. ")")
		else
			check(p1:GetAttribute("Casing") == true, jobId .. ": casing in the staff room")
		end

		local bb = refs.plan and refs.plan.bounds
		local function inBounds(p)
			if not bb then return true end
			return p.X > bb[1] - 6 and p.X < bb[3] + 6 and p.Z > bb[2] - 6 and p.Z < bb[4] + 6
		end
		-- ── E-prompt clash audit: standing where you use a GOAL prompt, which other E prompts reach you?
		local E = {}
		for _, pr in ipairs(findPrompts(WORKSPACE)) do
			local pos = promptPos(pr)
			if pos and pr.KeyboardKeyCode == Enum.KeyCode.E and inBounds(pos) then
				table.insert(E, { pr = pr, pos = pos, name = pr.Name .. "(" .. tostring(pr.ObjectText):sub(1, 18) .. ")" })
			end
		end
		local goals = {}
		for _, e in ipairs(E) do
			local n = e.pr.Name
			if n == "Breaker" or n == "Drill" or n == "Swipe" or n == "TakeKeycard" then table.insert(goals, e) end
		end
		-- keycard spots: the card only spawns at ONE, but any spot might hold it
		local clashes = {}
		for _, g in ipairs(goals) do
			for _, o in ipairs(E) do
				if o ~= g and o.pr.Name ~= g.pr.Name and not (g.pr.Name == "Breaker" and o.pr.Name == "BreakerHacker") then
					local d = (o.pos - g.pos).Magnitude
					-- you stand ~2.5 from the goal; the other one reaches you if d - 2.5 < its reach
					if d - 2.5 < o.pr.MaxActivationDistance and d < 7.5 then
						table.insert(clashes, string.format("%s ↔ %s %.1f (reach %d)", g.name, o.name, d, o.pr.MaxActivationDistance))
					end
				end
			end
		end
		print("   goal prompts: " .. #goals .. ", E prompts nearby: " .. #E)
		-- (the precise audit lives in drv_eaudit.luau)

		local i0 = info()
		print("   steps: " .. stepsStr(i0))
		print("   targets: " .. targetsStr(i0))
		MU:maskUp("button", p1)
		task.wait(2)

		-- ① breaker
		local cs = current(info())
		if refs.breaker and #(refs.cameras or {}) > 0 then
			check(cs and cs.id == "cameras", jobId .. " goal ①: " .. tostring(cs and cs.label))
			local br
			for _, pr in ipairs(findPrompts(refs.breaker)) do if pr.Name == "Breaker" then br = pr end end
			tp(p1, refs.breaker.Position + flat(screenDir(refs.breaker)) * 2.5)
			if br then fireAt(br, p1) end
			task.wait(2)
			check(Sec:camerasCut(), jobId .. ": cameras cut")
		end
		-- ② keycard
		task.wait(0.3)
		cs = current(info())
		if #(refs.keycardDoors or {}) > 0 then
			check(cs and cs.id == "keycard", jobId .. " goal ②: " .. tostring(cs and cs.label))
			local ti = info()
			local searchN = 0
			for _, t in ipairs(ti.targets or {}) do if t.label == "SEARCH" then searchN += 1 end end
			check(searchN >= 1, jobId .. ": SEARCH markers (" .. targetsStr(ti) .. ")")
			local take
			for _, pr in ipairs(findPrompts(WORKSPACE)) do if pr.Name == "TakeKeycard" and pr.Enabled then take = pr end end
			if check(take ~= nil, jobId .. ": keycard exists") then
				tp(p1, promptPos(take) + Vector3.new(0, 0.5, 0))
				triggerPrompt(take, p1)
				task.wait(0.5)
			end
			check(p1:GetAttribute("HasKeycard") == true, jobId .. ": holding the keycard")
			cs = current(info())
			check(cs and cs.id == "door", jobId .. " goal ③: " .. tostring(cs and cs.label))
			local door = refs.keycardDoors[1]
			local sw
			for _, pr in ipairs(findPrompts(door.panel)) do if pr.Name == "Swipe" then sw = pr end end
			tp(p1, door.panel.Position + flat(screenDir(door.panel)) * 2.5)
			if sw then fireAt(sw, p1) end
			task.wait(1.5)
			check(Sec:doorsOpen(), jobId .. ": door open")
		end
		-- ④ vault
		task.wait(0.3)
		cs = current(info())
		check(cs and cs.id == "vault", jobId .. " goal ④: " .. tostring(cs and cs.label))
		local drill
		for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "Drill" then drill = pr end end
		if check(drill ~= nil, jobId .. ": drill prompt") then
			local dpos = promptPos(drill)
			tp(p1, Vector3.new(dpos.X, dpos.Y - 1, dpos.Z) + flat(refs.vault.door.CFrame.LookVector) * 2.5)
			fireAt(drill, p1)
		end
		local fixes = 0
		local opened = waitFor(function()
			if drill and drill.Enabled then fireAt(drill, p1) fixes += 1 end
			return (function() for _, r in ipairs(Loot:remaining()) do if r.inVault and not r.locked then return true end end end)()
				or info() and current(info()) and current(info()).id ~= "vault"
		end, 120, 0.5)
		check(opened, string.format("%s: vault open (drill fixed %d×)", jobId, fixes))
		task.wait(0.4)
		local i2 = info()
		cs = current(i2)
		print("   steps: " .. stepsStr(i2))
		print("   targets: " .. targetsStr(i2))
		check(cs and cs.id == "loot", jobId .. " goal ⑤: " .. tostring(cs and cs.label))
		-- ⑤ bag + load until the step ticks
		local car = JS:getCar()
		p1:SetAttribute("Role", "Muscle")   -- heavy gold solo
		for k = 1, 6 do
			cs = current(info())
			if not cs or cs.id ~= "loot" then break end
			local pile
			for _, t in ipairs(info().targets or {}) do
				if t.label == "CASH" then
					for _, pr in ipairs(findPrompts(refs.root)) do
						if (pr.Name == "BagLoot" or pr.Name == "SmashCase") and pr.Enabled then
							local pp = promptPos(pr)
							if pp and (pp - t.pos).Magnitude < 4 then pile = pr end
						end
					end
					if pile then break end
				end
			end
			if not pile then print("   no pile for a CASH marker (" .. targetsStr(info()) .. ")") break end
			tp(p1, promptPos(pile) + Vector3.new(0, 0.5, 0))
			triggerPrompt(pile, p1)
			task.wait(0.5)
			if not Loot:isCarrying(p1) then
				local l = REMOTE_LOG.LootMinigame
				if l and l[1] == p1 and l[2].op == "start" then
					task.wait((l[2].min or 1) + 0.3)
					remote("LootMinigame").OnServerEvent:Fire(p1, { op = "done", token = l[2].token, mode = "game", ok = true })
					task.wait(0.5)
				end
			end
			if Loot:isCarrying(p1) then
				local lpp = car.trunk and car.trunk:FindFirstChild("LoadBag", true)
				tp(p1, car.trunk.Position + Vector3.new(0, 1, 3))
				if lpp then triggerPrompt(lpp, p1) end
				task.wait(0.5)
			else
				print("   could not bag " .. tostring(pile.ObjectText))
			end
			print("   now: " .. tostring(current(info()) and current(info()).label))
		end
		cs = current(info())
		check(cs and cs.id == "car", jobId .. " last goal: " .. tostring(cs and cs.label))
		check(not (info() or {}).alarm, jobId .. ": still stealth (no alarm)")
		triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
		task.wait(0.5)
		remote("Getaway").OnServerEvent:Fire(p1, { action = "go" })
		waitFor(function() return GS:getPhase() == "vote" end, 6)
		remote("Getaway").OnServerEvent:Fire(p1, { action = "vote", route = "boat" })
		local done = waitFor(function() local h = REMOTE_LOG.HeistState return h and (h[2] == "COMPLETE" or h[2] == "FAILED") and h end, 60, 0.2)
		check(done and done[2] == "COMPLETE", jobId .. ": heist COMPLETE (" .. tostring(done and done[3] and done[3].take) .. ")")
		REMOTE_LOG.HeistState = nil
		task.wait(Constants.JOB_RESET_COOLDOWN + 12)
		check(JS:getPhase() == "idle", jobId .. ": reset → idle")
	end

	check(#LOG.errors == errs0, "no runtime errors (" .. (#LOG.errors - errs0) .. ")")
	print("\n================ CHAIN CHECKS ================")
	local pass, fail = 0, 0
	for _, l in ipairs(CHECKS) do if l:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(l) end end
	print(string.format("%d passed, %d failed", pass, fail))
end, 3000)
report()
