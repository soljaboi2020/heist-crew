-- E-prompt audit: from the spot you STAND to use each goal prompt, can another E
-- prompt reach you and be (about) as close? Then Roblox may show that one instead.
local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function promptPos(pr)
	local par = pr.Parent
	if not par then return nil end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Model") then return par:GetPivot().Position end
end
local TOTAL = 0
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	for ji, jobId in ipairs(JOBS_TO_AUDIT or { "mart", "villa", "jewelry", "bank" }) do
		local p1 = addPlayer("Aud" .. ji)
		task.wait(3)
		p1:SetAttribute("UnlockAll", true)
		p1:SetAttribute("Tutorial", nil)
		JS:selectJob(jobId)
		task.wait(0.4)
		local cfg, refs = JS:getCurrent()
		JS:startLaunchCountdown(0, function() return { p1 } end, "portal")
		local t0 = SCHED.now
		while JS:getPhase() ~= "running" and SCHED.now - t0 < 20 do task.wait(0.2) end
		task.wait(0.5)
		local bb = refs.plan and refs.plan.bounds
		local function inB(p) return not bb or (p.X > bb[1] - 8 and p.X < bb[3] + 8 and p.Z > bb[2] - 8 and p.Z < bb[4] + 8) end
		local E, goals = {}, {}
		for _, pr in ipairs(findPrompts(WORKSPACE)) do
			local pos = promptPos(pr)
			if pos and pr.KeyboardKeyCode == Enum.KeyCode.E and inB(pos) and pr.Name ~= "BreakerHacker" then
				local e = { pr = pr, pos = pos, name = pr.Name .. "(" .. tostring(pr.ObjectText):sub(1, 22) .. ")" }
				table.insert(E, e)
				local n = pr.Name
				if n == "Breaker" or n == "Drill" or n == "Swipe" or n == "TakeKeycard" then
					-- where you stand: in front of the part the prompt is on
					local par = pr.Parent:IsA("Attachment") and pr.Parent.Parent or pr.Parent
					local look = par:IsA("BasePart") and flat(par.CFrame.LookVector) or Vector3.new(0, 0, 1)
					if n == "Drill" and refs.vault and refs.vault.door then look = flat(refs.vault.door.CFrame.LookVector) end
					if n == "TakeKeycard" then look = Vector3.new(0, 0, 0) end
					local stand = Vector3.new(pos.X, 3.5, pos.Z) + (look.Magnitude > 0.1 and look.Unit * 2.5 or Vector3.zero)
					table.insert(goals, { e = e, stand = stand })
				end
			end
		end
		-- keycard: every keycard SPOT might hold it (the card only spawns at one this run)
		for _, spot in ipairs(refs.keycardSpots or {}) do
			local pos = spot.Position + Vector3.new(0, 0.5, 0)
			table.insert(goals, { e = { name = "KeycardSpot", pos = pos, pr = { MaxActivationDistance = 8, Name = "TakeKeycard" } }, stand = Vector3.new(pos.X, 3.5, pos.Z) })
		end
		-- wall-mounted panels (breaker, keypad): you could be on either side of the part's
		-- LookVector; the real side is the one with room. Count a clash only if BOTH sides clash.
		local extra = {}
		for _, g in ipairs(goals) do
			local n = g.e.pr.Name
			if n == "Breaker" or n == "Swipe" then
				local mirror = Vector3.new(2 * g.e.pos.X - g.stand.X, 3.5, 2 * g.e.pos.Z - g.stand.Z)
				table.insert(extra, { e = g.e, stand = mirror, pairWith = g })
				g.pairWith = true
			end
		end
		for _, x in ipairs(extra) do table.insert(goals, x) end
		local bad = {}
		local sideBad = {}
		for _, g in ipairs(goals) do
			local dg = (g.e.pos - g.stand).Magnitude
			for _, o in ipairs(E) do
				local vaultPair = g.e.pr.Name == "Drill" and o.pr.Enabled == false   -- vault loot: enabled only once the drill is done
				if o ~= g.e and o.pr.Name ~= g.e.pr.Name and not vaultPair then
					local d = (o.pos - g.stand).Magnitude
					if d <= o.pr.MaxActivationDistance and d <= dg + 1.5 then
						sideBad[g] = true
						table.insert(bad, string.format("%s @(%.1f,%.1f): %s is %.1f away (goal %.1f, its reach %d) at (%.1f, %.1f, %.1f)",
							g.e.name, g.stand.X, g.stand.Z, o.name, d, dg, o.pr.MaxActivationDistance, o.pos.X, o.pos.Y, o.pos.Z))
					end
				end
			end
		end
		-- drop panel clashes where the OTHER side of the wall is clean
		local keep = {}
		for _, line in ipairs(bad) do table.insert(keep, line) end
		for _, x in ipairs(extra) do
			if not (sideBad[x] and sideBad[x.pairWith]) then
				local nm = x.e.name
				local k2 = {}
				for _, line in ipairs(keep) do if line:sub(1, #nm) ~= nm then table.insert(k2, line) end end
				keep = k2
			end
		end
		bad = keep
		print(string.format("== %s: %d goal spots, %d E prompts, %d clashes", jobId, #goals, #E, #bad))
		for _, b in ipairs(bad) do print("   " .. b) end
		TOTAL += #bad
		-- end the run: the only crew member leaves
		removePlayer(p1)
		local t1 = SCHED.now
		while JS:getPhase() ~= "idle" and SCHED.now - t1 < 90 do task.wait(0.5) end
		print("   phase after leave: " .. JS:getPhase())
	end
	print("AUDIT TOTAL CLASHES: " .. TOTAL)
end, 3000)
report()
