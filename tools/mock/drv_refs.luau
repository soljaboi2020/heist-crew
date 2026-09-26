local problems = {}
local function bad(msg) table.insert(problems, msg) print("  BAD " .. msg) end
local function isInst(x, cls) return mtypeof(x) == "Instance" and (not cls or x:IsA(cls)) end
local function inWS(x) return isInst(x) and x:IsDescendantOf(WORKSPACE) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		JS:selectJob(id)
		task.wait(0.3)
		local cfg, r = JS:getCurrent()
		print("== " .. id)
		local keys = {} for k in pairs(r) do table.insert(keys, k) end table.sort(keys) print("   keys: " .. table.concat(keys, " "))
		if not inWS(r.root) then bad(id .. ".root not an Instance in workspace") end
		if mtypeof(r.getawayCFrame) ~= "CFrame" then bad(id .. ".getawayCFrame " .. mtypeof(r.getawayCFrame)) end
		if mtypeof(r.policeStop) ~= "Vector3" then bad(id .. ".policeStop " .. mtypeof(r.policeStop)) end
		if r.entryPoint ~= nil and mtypeof(r.entryPoint) ~= "Vector3" then bad(id .. ".entryPoint " .. mtypeof(r.entryPoint)) end
		if r.breaker ~= nil and not inWS(r.breaker) then bad(id .. ".breaker") end
		if r.openSign ~= nil and type(r.openSign) ~= "function" then bad(id .. ".openSign not fn") end
		for i, c in ipairs(r.cameras or {}) do
			if not inWS(c.head, "BasePart") then bad(id .. ".cameras[" .. i .. "].head") end
			if c.model ~= nil and not inWS(c.model) then bad(id .. ".cameras[" .. i .. "].model") end
		end
		for i, d in ipairs(r.keycardDoors or {}) do
			if not inWS(d.door, "BasePart") then bad(id .. ".keycardDoors[" .. i .. "].door") end
			if not inWS(d.panel, "BasePart") then bad(id .. ".keycardDoors[" .. i .. "].panel") end
		end
		for i, sp in ipairs(r.keycardSpots or {}) do if not inWS(sp, "BasePart") then bad(id .. ".keycardSpots[" .. i .. "] " .. mtypeof(sp)) end end
		if (#(r.keycardDoors or {}) > 0) ~= (#(r.keycardSpots or {}) > 0) then bad(id .. ": keycardDoors/keycardSpots mismatch") end
		for i, row in ipairs(r.laserRows or {}) do
			if mtypeof(row.zoneCFrame) ~= "CFrame" then bad(id .. ".laserRows[" .. i .. "].zoneCFrame") end
			if row.zoneSize ~= nil and mtypeof(row.zoneSize) ~= "Vector3" then bad(id .. ".laserRows[" .. i .. "].zoneSize") end
			if type(row.beams) ~= "table" or #row.beams == 0 then bad(id .. ".laserRows[" .. i .. "].beams") end
		end
		for i, l in ipairs(r.lootSpots or {}) do
			if type(l.kind) ~= "string" or mtypeof(l.cframe) ~= "CFrame" then bad(id .. ".lootSpots[" .. i .. "] kind/cframe") end
			if l.visual ~= nil and not isInst(l.visual) then bad(id .. ".lootSpots[" .. i .. "].visual") end
		end
		for i, c in ipairs(r.smashCases or {}) do
			if mtypeof(c.cframe) ~= "CFrame" then bad(id .. ".smashCases[" .. i .. "].cframe") end
		end
		local v = r.vault
		if v then
			if not inWS(v.door, "BasePart") then bad(id .. ".vault.door") end
			for i, p in ipairs(v.parts or {}) do if not inWS(p, "BasePart") then bad(id .. ".vault.parts[" .. i .. "]") end end
			if v.hinge ~= nil and mtypeof(v.hinge) ~= "CFrame" then bad(id .. ".vault.hinge") end
		else bad(id .. ": no vault") end
		for i, g in ipairs(r.guardRoutes or {}) do
			if mtypeof(g.a) ~= "Vector3" or mtypeof(g.b) ~= "Vector3" then bad(id .. ".guardRoutes[" .. i .. "] a/b") end
		end
		if #(r.guardRoutes or {}) ~= cfg.guards then bad(id .. ": guardRoutes " .. #(r.guardRoutes or {}) .. " vs cfg.guards " .. tostring(cfg.guards)) end
		local s = r.sneakIn
		if not s or mtypeof(s.at) ~= "Vector3" or mtypeof(s.face) ~= "Vector3" or mtypeof(s.spread) ~= "Vector3" then bad(id .. ".sneakIn shape") end
		local kinds = {}
		for i, e in ipairs(r.entrances or {}) do
			kinds[e.kind] = true
			if mtypeof(e.at) ~= "Vector3" or type(e.label) ~= "string" then bad(id .. ".entrances[" .. i .. "]") end
		end
		if not (kinds.front and kinds.side and kinds.roof) then bad(id .. ": entrances missing a kind") end
		for i, h in ipairs(r.hideSpots or {}) do
			if not inWS(h, "BasePart") or not h:HasTag("HideSpot") then bad(id .. ".hideSpots[" .. i .. "] not tagged BasePart") end
			if type(h:GetAttribute("Label")) ~= "string" then bad(id .. ".hideSpots[" .. i .. "] no Label") end
		end
		if #(r.hideSpots or {}) < 2 or #(r.hideSpots or {}) > 4 then bad(id .. ": hideSpots count " .. #(r.hideSpots or {})) end
		for i, z in ipairs(r.shadowZones or {}) do
			if not inWS(z, "BasePart") or not z:HasTag("ShadowZone") then bad(id .. ".shadowZones[" .. i .. "] not tagged BasePart") end
			if z.CanCollide or z.CanQuery or z.CanTouch then bad(id .. ".shadowZones[" .. i .. "] " .. z.Name .. " CanCollide/CanQuery/CanTouch not all false") end
		end
		for i, vv in ipairs(r.vents or {}) do
			if not inWS(vv.a, "BasePart") or not inWS(vv.b, "BasePart") then bad(id .. ".vents[" .. i .. "]") else
				if not vv.a:HasTag("Vent") or not vv.b:HasTag("Vent") then bad(id .. ".vents[" .. i .. "] untagged") end
				if vv.a:GetAttribute("Pair") ~= vv.b.Name or vv.b:GetAttribute("Pair") ~= vv.a.Name then bad(id .. ".vents[" .. i .. "] Pair names don't cross-match") end
			end
		end
		-- sneakIn must not be on a guard route line (2D distance to segment)
		for _, g in ipairs(r.guardRoutes or {}) do
			local a, b, p = g.a, g.b, s.at
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
			local t = ab.Magnitude > 0 and math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1) or 0
			local d = (ap - ab * t).Magnitude
			if d < 10 then bad(string.format("%s: guard route %s passes %.1f studs from sneakIn", id, tostring(g.name), d)) end
			-- any wall between? raycast from sneakIn to closest point
			local q = a + (b - a) * t
			local hit = WORKSPACE:Raycast(p, Vector3.new(q.X - p.X, 0, q.Z - p.Z))
			print(string.format("   route %s closest %.1f studs from sneakIn, wall between: %s", tostring(g.name), d, hit and hit.Instance:GetFullName() or "NONE"))
		end
		-- cameras: can any camera see the sneakIn spot?
		for i, c in ipairs(r.cameras or {}) do
			local to = s.at - c.head.Position
			local hit = WORKSPACE:Raycast(c.head.Position, to)
			if to.Magnitude < 60 then print(string.format("   camera %d %.1f studs from sneakIn, blocked by %s", i, to.Magnitude, hit and hit.Instance:GetFullName() or "NOTHING")) end
		end
		-- getaway car parking vs spec
		print("   getaway at", r.getawayCFrame.Position, "look", r.getawayCFrame.LookVector)
		-- hide spots / vents prompts
		for _, h in ipairs(r.hideSpots or {}) do if not h:FindFirstChild("HidePrompt") then bad(id .. " hide spot without prompt " .. h.Name) end end
	end
	-- hub
	local hub = JS.hub
	print("== hub keys:") local keys = {} for k in pairs(hub) do table.insert(keys, k) end table.sort(keys) print("   " .. table.concat(keys, " "))
	-- jail
	local jail = mockRequire(SERVER_SCRIPT.JailService)
	print("jail release", jail:getReleaseCFrame())
end, 60)
print("PROBLEMS: " .. #problems)
report()
