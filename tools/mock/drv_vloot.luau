local VALID = { Painting = true, GoldRecord = true, GoldFlamingo = true, Wine = true, JewelryBox = true, Cash = true, GoldBars = true, Diamonds = true, SecretStash = true }
local issues = 0
local function bad(msg) issues += 1 print("  ✗ " .. msg) end
local function partsOf(inst)
	local t = inst:IsA("BasePart") and { inst } or {}
	for _, d in ipairs(inst:GetDescendants()) do if d:IsA("BasePart") then table.insert(t, d) end end
	return t
end
local function aabb(p)
	local cf, s = p.CFrame, p.Size / 2
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
		local w = cf * Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
		mn = Vector3.new(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
		mx = Vector3.new(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
	end end end
	return mn, mx
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local C = mockRequire(REPLICATED.Shared.Constants)
	JS:selectJob("villa")
	task.wait(1)
	local cfg, refs = JS:getCurrent()
	local root = refs.root
	print("== lootSpots: " .. #refs.lootSpots)
	local targets, pools = 0, {}
	local newParts = {}
	for i, s in ipairs(refs.lootSpots) do
		local flags = {}
		for _, k in ipairs({ "heavy", "fragile", "hidden", "inVault" }) do if s[k] then table.insert(flags, k) end end
		if s.interact then table.insert(flags, "interact=" .. s.interact) end
		if s.target then table.insert(flags, "TARGET=" .. s.target) targets += 1 end
		local p = s.cframe.Position
		print(string.format("  %2d %-12s pool=%-8s stand(%.1f, %.1f)  %s  visual=%s", i, s.kind, tostring(s.pool), p.X, p.Z, table.concat(flags, ","), s.visual and s.visual.Name or "nil"))
		if not VALID[s.kind] then bad("invalid kind " .. tostring(s.kind)) end
		if not C.LOOT[s.kind] then bad("kind not in Constants.LOOT " .. tostring(s.kind)) end
		if not s.pool then bad("no pool") end
		pools[s.pool] = (pools[s.pool] or 0) + 1
		if not s.visual or not s.visual:IsDescendantOf(root) then bad("visual missing/outside root #" .. i) end
		local vp = s.visual and partsOf(s.visual) or {}
		if #vp == 0 then bad("visual has no parts #" .. i) end
		for _, q in ipairs(vp) do table.insert(newParts, q) end
		-- stand spot must be standable (not inside anything solid)
		local stand = p + Vector3.new(0, 3, 0)
		for _, q in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(stand), Vector3.new(1.4, 4.4, 1.4))) do
			if q.CanCollide and q.Transparency < 1 and not q:IsDescendantOf(WORKSPACE:FindFirstChild("Guards") or root) == false then end
			if q.CanCollide and q.Transparency < 1 and q.Name ~= "LootPrompt" then
				local l = q.CFrame:PointToObjectSpace(stand)
				local h = q.Size / 2
				if math.abs(l.X) < h.X + 0.7 and math.abs(l.Y) < h.Y + 2.2 and math.abs(l.Z) < h.Z + 0.7 then
					bad(string.format("stand #%d %s blocked by %s", i, s.kind, q:GetFullName()))
				end
			end
		end
		-- the loot must be within prompt reach (anchor at stand+2.5, MaxActivationDistance 7) of the visual centre
		local cen = Vector3.zero
		for _, q in ipairs(vp) do cen += q.Position end
		cen /= math.max(1, #vp)
		local d = (Vector3.new(cen.X, 0, cen.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
		if d > 5 then bad(string.format("#%d %s: stand %.1f studs from the loot", i, s.kind, d)) end
		-- hidden stash: all hidden now, reveal round-trips
		if s.hidden then
			if type(s.reveal) ~= "function" then bad("hidden spot without reveal()") else
				local vis = 0
				for _, q in ipairs(vp) do if q.Transparency < 1 then vis += 1 end end
				if vis > 0 then bad("hidden stash visible by default (" .. vis .. " parts)") end
				s.reveal(true)
				local shown = 0
				for _, q in ipairs(vp) do if q.Transparency < 1 then shown += 1 end end
				if shown == 0 then bad("reveal(true) showed nothing") end
				print(string.format("     reveal(true): %d/%d parts shown", shown, #vp))
				s.reveal(false)
				for _, q in ipairs(vp) do if q.Transparency < 1 then bad("reveal(false) left " .. q.Name .. " visible") break end end
			end
		end
	end
	print("targets: " .. targets)
	if targets ~= 1 then bad("need exactly one target") end
	for k, v in pairs(pools) do print("  pool " .. k .. " = " .. v) end

	-- new static props too (for the route/door checks)
	for _, nm in ipairs({ "Safe", "WallStash", "RugStash", "WineWall", "FlamingoPlinth" }) do
		local f = root:FindFirstChild(nm, true)
		if not f then bad("missing folder " .. nm) else for _, q in ipairs(partsOf(f)) do table.insert(newParts, q) end end
	end
	for _, q in ipairs(root:GetDescendants()) do
		if q:IsA("BasePart") and (q.Name:match("^Console") or q.Name:match("^Speaker") or q.Name == "RecordSleeve" or q.Name:match("^Turntable") or q.Name:match("^Platter")
			or q.Name == "Tonearm" or q.Name == "RecordSpot" or q.Name:match("^Pallet") or q.Name:match("^Gold") or q.Name:match("^Dolly") or q.Name:match("^TrayStand")
			or q.Name:match("^Painting") or q.Name == "FruitBowl" or q.Name == "Fruit" or q.Name:match("^Perfume") or q.Name == "HairBrush") then
			table.insert(newParts, q)
		end
	end
	print("new/loot parts checked: " .. #newParts)
	-- guard routes: nothing new within 2 studs of the a→b line (y 0.5..7)
	for _, g in ipairs(refs.guardRoutes) do
		local a, b = g.a, g.b
		for _, q in ipairs(newParts) do
			local mn, mx = aabb(q)
			if mn.Y < 7 and mx.Y > 0.6 then
				-- distance from segment (in XZ) to the box
				local n = 24
				for k = 0, n do
					local pt = a:Lerp(b, k / n)
					local dx = math.max(mn.X - pt.X, 0, pt.X - mx.X)
					local dz = math.max(mn.Z - pt.Z, 0, pt.Z - mx.Z)
					if math.sqrt(dx * dx + dz * dz) < 2 then
						bad(string.format("%s within 2 studs of %s route: %s", q.Name, g.name, q:GetFullName())) break
					end
				end
			end
		end
	end
	-- doorways (opening span along the wall, ±1.6 across it, y 0.6..10)
	local doors = {
		{ "x", -14, -52, -44 }, { "x", 14, -52, -44 }, { "z", -58, -32, -24 }, { "z", -58, -6, 6 }, { "z", -58, 24, 32 },
		{ "z", -70, -32, -24 }, { "z", -70, -4, 4 }, { "z", -70, 30, 38 }, { "x", -18, -79, -72 }, { "x", 18, -78.5, -71.5 },
		{ "z", -80, 20, 27 }, { "z", -80, 32, 40 }, { "x", 28, -94, -87 }, { "z", -38, -5, 5 }, { "x", 42, -92, -85 }, { "z", -82, -3, 3 },
	}
	for _, q in ipairs(newParts) do
		if q.CanCollide then
			local mn, mx = aabb(q)
			for _, d in ipairs(doors) do
				local hit
				if d[1] == "x" then -- wall at x = d[2], opening along z
					hit = mx.X > d[2] - 1.6 and mn.X < d[2] + 1.6 and mx.Z > d[3] and mn.Z < d[4]
				else
					hit = mx.Z > d[2] - 1.6 and mn.Z < d[2] + 1.6 and mx.X > d[3] and mn.X < d[4]
				end
				if hit and mn.Y < 10 and mx.Y > 0.6 then bad("doorway blocked by " .. q:GetFullName()) end
			end
		end
	end
	-- sneakIn room must stay clean
	local si = refs.sneakIn.at
	for _, q in ipairs(newParts) do
		if (q.Position - si).Magnitude < 6 then bad("new part near sneakIn: " .. q:GetFullName()) end
	end
	-- vault door swing sweep x 4.5..6.1 z -81..-90
	for _, q in ipairs(newParts) do
		local mn, mx = aabb(q)
		if mx.X > 3.5 and mn.X < 7 and mx.Z > -91 and mn.Z < -81 and mx.Y > 0.6 and mn.Y < 9.5 then bad("in vault-door swing: " .. q:GetFullName()) end
	end
	print("TOTAL villa-loot issues: " .. issues)
end, 60)
report()
