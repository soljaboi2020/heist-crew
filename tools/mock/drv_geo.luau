local issues = 0
local function solidAt(pos, ignore)
	local out = {}
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(1.6, 4.5, 1.6))) do
		if p.CanCollide and p.Transparency < 1 and not (ignore and p:IsDescendantOf(ignore)) then
			-- precise: is the point within 0.6 studs of the part's OBB interior?
			local l = p.CFrame:PointToObjectSpace(pos)
			local h = p.Size / 2
			if math.abs(l.X) < h.X + 0.8 and math.abs(l.Y) < h.Y + 1.2 and math.abs(l.Z) < h.Z + 0.8 then
				-- ignore the floor directly below (top face under the feet)
				local top = (p.CFrame * CFrame.new(0, h.Y, 0)).Position.Y
				if not (p.Size.Y < 3 and top < pos.Y - 1.5) then table.insert(out, p) end
			end
		end
	end
	return out
end
local function report1(label, pos, ignore)
	local hits = solidAt(pos, ignore)
	if #hits > 0 then
		issues += 1
		local names = {}
		for i, h in ipairs(hits) do if i <= 3 then table.insert(names, h:GetFullName() .. string.format(" size(%.1f,%.1f,%.1f)", h.Size.X, h.Size.Y, h.Size.Z)) end end
		print("  BLOCKED " .. label .. " @ " .. tostring(pos) .. " → " .. table.concat(names, " | "))
	end
end
local function enclosed(pr)
	local par = pr.Parent
	local pos = par:IsA("Attachment") and par.WorldPosition or (par:IsA("BasePart") and par.Position)
	if not pos then return false end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { par:IsA("Attachment") and par.Parent or par }
	local clear = 0
	for i = 0, 7 do
		local a = i * math.pi / 4
		local from = pos + Vector3.new(math.cos(a) * 5, 1, math.sin(a) * 5)
		local hit = WORKSPACE:Raycast(from, pos - from, rp)
		if not hit then clear += 1 end
	end
	return clear == 0
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local hub = JS.hub
	for i, pad in ipairs(hub.spawnPads) do report1("spawnPad " .. i, pad.Position + Vector3.new(0, 3.5, 0)) end
	local W = mockRequire(REPLICATED.Shared.Constants).WORLD
	-- jail
	local J = mockRequire(SERVER_SCRIPT.JailService)
	for i, d in ipairs(J:getOccupiedDoors()) do end
	for _, x in ipairs(WORKSPACE:GetDescendants()) do if x.Name == "BreakOut" and x:IsA("ProximityPrompt") then end end
	print("jail release", J:getReleaseCFrame().Position) report1("jail release", J:getReleaseCFrame().Position)
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		print("== " .. id)
		local s = refs.sneakIn
		local out = Vector3.new(s.at.X - s.face.X, 0, s.at.Z - s.face.Z).Unit
		for i = 1, 8 do
			local row = (i - 1) % 4
			local col = math.floor((i - 1) / 4)
			report1("drop point " .. i, s.at + s.spread * ((row - 1.5) * 2) + out * (col * 2.5))
		end
		for i = 1, 2 do
			local away = out
			report1("bot spawn " .. i, s.at + s.spread * ((i - 1.5) * 3) + away * 5 + Vector3.new(0, 1, 0))
		end
		for i, g in ipairs(refs.guardRoutes) do
			report1("guard " .. tostring(g.name) .. " a", g.a) report1("guard " .. tostring(g.name) .. " b", g.b)
			-- is the straight a→b path clear?
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { WORKSPACE:FindFirstChild("Guards") }
			local hit = WORKSPACE:Raycast(g.a + Vector3.new(0, 0.5, 0), g.b - g.a, rp)
			if hit and hit.Instance.CanCollide and hit.Instance.Transparency < 1 then issues += 1 print("  ROUTE " .. tostring(g.name) .. " a→b blocked by " .. hit.Instance:GetFullName() .. " at " .. tostring(hit.Position)) end
		end
		for i, e in ipairs(refs.entrances) do report1("entrance " .. e.kind, e.at) end
		for i, v in ipairs(refs.vents) do
			for _, part in ipairs({ v.a, v.b }) do
				local ex = part:GetAttribute("Exit")
				local pos
				if typeof(ex) == "Vector3" then pos = ex + Vector3.new(0, 3, 0) else
					local look = part.CFrame.LookVector
					pos = part.Position + look * 2.5
					pos = Vector3.new(pos.X, math.max(pos.Y, part.Position.Y - part.Size.Y / 2) + 3, pos.Z)
				end
				report1("vent exit " .. part.Name, pos, part)
			end
		end
		report1("getaway car", refs.getawayCFrame.Position + Vector3.new(0, 3, 0), WORKSPACE:FindFirstChild("GetawayCar", true))
		local n, enc = 0, 0
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.RequiresLineOfSight then
				n += 1
				if enclosed(pr) then enc += 1 print("  ENCLOSED prompt (LOS on, every side blocked): " .. pr:GetFullName() .. " '" .. pr.ActionText .. "'") end
			end
		end
		print(string.format("   %d LOS prompts, %d look enclosed", n, enc))
	end
	-- jail cells
	local cellsFolder
	print("TOTAL geometry issues: " .. issues)
end, 60)
report()
