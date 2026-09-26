local function srv(n) return mockRequire(SERVER_SCRIPT:FindFirstChild(n)) end
local function bodyHits(pos, ignore)
	-- R15 body around HRP: x 2, y pos-3 .. pos+2.2, z 1.2 (rough), precise vs shapes
	local cf = CFrame.new(pos + Vector3.new(0, -0.4, 0))
	local size = Vector3.new(2, 5.2, 1.4)
	local out = {}
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(cf, size)) do
		local m = p:FindFirstAncestorOfClass("Model")
		local isChar = m and m:FindFirstChildOfClass("Humanoid")
		if p.CanCollide and not isChar and not (ignore and p:IsDescendantOf(ignore)) and partHitsBox(p, cf, size) then
			-- ignore the floor directly under the feet
			local mn, mx = partAABB(p)
			if mx.Y > pos.Y - 1.9 then table.insert(out, string.format("%s y%.1f..%.1f", p:GetFullName(), mn.Y, mx.Y)) end
		end
	end
	return out
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS, Bots = srv("JobService"), srv("BotService")
	local p1 = addPlayer("Malachi")
	local p2 = addPlayer("Buddy")
	task.wait(2)
	local bad = 0
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local _, refs = JS:getCurrent()
		for _, crew in ipairs({ { p1 }, { p1, p2 } }) do
			local sI = refs.sneakIn
			for k, pl in ipairs(crew) do pl.Character:PivotTo(CFrame.lookAt(sI.at + sI.spread * ((k - 1 - 1.5) * 2), sI.face)) end
			local made = Bots:spawnFor(crew, refs)
			for _, m in ipairs(made) do
				local pos = m:FindFirstChild("HumanoidRootPart").Position
				local hits = bodyHits(pos, m)
				print(string.format("%s crew=%d bot %s at %s → %s", id, #crew, m.Name, tostring(pos), #hits == 0 and "clear" or ("INSIDE: " .. table.concat(hits, " | "))))
				if #hits > 0 then bad += 1 end
			end
			Bots:despawnAll()
			task.wait(0.2)
		end
		-- player drop points (JobService.dropPoints logic mirrored in the geo driver)
		local s = refs.sneakIn
		local out = Vector3.new(s.at.X - s.face.X, 0, s.at.Z - s.face.Z).Unit
		for i = 1, 8 do
			local row = (i - 1) % 4
			local col = math.floor((i - 1) / 4)
			local pos = s.at + s.spread * ((row - 1.5) * 2) + out * (col * 2.5)
			local hits = bodyHits(pos)
			if #hits > 0 then bad += 1 print(string.format("%s drop point %d %s INSIDE: %s", id, i, tostring(pos), table.concat(hits, " | "))) end
		end
	end
	print("SPAWN issues: " .. bad)
end, 60)
report()
