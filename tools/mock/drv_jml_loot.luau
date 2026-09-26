-- ═══════ v3.0 JEWELRY-MART-LOOT checks ═══════
local problems = 0
local function bad(msg) problems += 1 print("  BAD " .. msg) end
local function isInst(x) return mtypeof(x) == "Instance" end
-- precise: does part p intersect an axis-aligned box (centre c, half h)?
local function obbHitsAABB(p, c, h)
	local cf, hs = p.CFrame, p.Size / 2
	-- sample the part's 8 corners + centre + face centres: coarse SAT-lite
	local axes = { cf.RightVector, cf.UpVector, cf.LookVector }
	-- SAT on world axes + part axes
	local function proj(axis)
		local r = math.abs(axes[1]:Dot(axis)) * hs.X + math.abs(axes[2]:Dot(axis)) * hs.Y + math.abs(axes[3]:Dot(axis)) * hs.Z
		local pc = cf.Position:Dot(axis)
		local br = math.abs(axis.X) * h.X + math.abs(axis.Y) * h.Y + math.abs(axis.Z) * h.Z
		local bc = c:Dot(axis)
		return math.abs(pc - bc) <= r + br
	end
	for _, a in ipairs({ Vector3.new(1,0,0), Vector3.new(0,1,0), Vector3.new(0,0,1), axes[1], axes[2], axes[3] }) do
		if not proj(a) then return false end
	end
	return true
end
local function solids(c, size, ignoreFn)
	local out = {}
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(c), size)) do
		if p.CanCollide and p.Transparency < 1 and not (ignoreFn and ignoreFn(p)) and obbHitsAABB(p, c, size / 2) then
			table.insert(out, p)
		end
	end
	return out
end
local function names(list) local t = {} for i, p in ipairs(list) do if i <= 4 then table.insert(t, p:GetFullName()) end end return table.concat(t, " | ") end
-- body-sized box standing on the floor at xz (y 1..5.5 above floor 0.5 = clears thresholds/rugs)
local function standClear(label, pos)
	local c = Vector3.new(pos.X, 0.5 + 3.3, pos.Z)
	local hits = solids(c, Vector3.new(1.8, 4.6, 1.8))
	if #hits > 0 then bad(label .. " not standable @ " .. tostring(Vector3.new(pos.X, 0, pos.Z)) .. " → " .. names(hits)) end
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local C = mockRequire(REPLICATED.Shared.Constants)
	for _, id in ipairs({ "jewelry", "mart" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		print("== " .. id .. "  (" .. #(refs.lootSpots or {}) .. " lootSpots, " .. #(refs.smashCases or {}) .. " smash cases, "
			.. #(refs.laserRows or {}) .. " laser rows)")
		local targets, pools = 0, {}
		for i, l in ipairs(refs.lootSpots or {}) do
			local tag = string.format("%s#%d %s", id, i, tostring(l.kind))
			if type(l.kind) ~= "string" or not C.LOOT[l.kind] then bad(tag .. ": kind not in Constants.LOOT") end
			if mtypeof(l.cframe) ~= "CFrame" then bad(tag .. ": cframe") end
			if not isInst(l.visual) or not l.visual:IsDescendantOf(WORKSPACE) then bad(tag .. ": visual missing / not in workspace")
			else
				local n = l.visual:IsA("BasePart") and 1 or 0
				for _, d in ipairs(l.visual:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
				if n == 0 then bad(tag .. ": visual has no parts") end
				local vpos = l.visual:IsA("Model") and l.visual:GetBoundingBox().Position or l.visual.Position
				local d = (vpos - l.cframe.Position)
				d = Vector3.new(d.X, 0, d.Z).Magnitude
				if d > 5 then bad(string.format("%s: stand point %.1f studs from its visual", tag, d)) end
				-- visual must not block movement
				for _, dd in ipairs(l.visual:GetDescendants()) do
					if dd:IsA("BasePart") and dd.CanCollide and dd.Transparency < 1 then bad(tag .. ": collidable visual part " .. dd:GetFullName()) break end
				end
				print(string.format("   %-2d %-14s pool=%-9s interact=%-8s hidden=%-5s target=%-12s inVault=%-5s parts=%d  stand %s",
					i, l.kind, tostring(l.pool), tostring(l.interact), tostring(l.hidden == true), tostring(l.target),
					tostring(l.inVault), n, tostring(Vector3.new(math.floor(l.cframe.Position.X * 10) / 10, 0, math.floor(l.cframe.Position.Z * 10) / 10))))
			end
			if l.interact ~= nil and not (C.LOOT_V3.MINIGAMES or {})[l.interact] then bad(tag .. ": interact " .. tostring(l.interact)) end
			if l.target then targets += 1 if l.target ~= C.LOOT_V3.TARGETS[id].kind then bad(tag .. " target mismatch") end end
			if l.pool then pools[l.pool] = (pools[l.pool] or 0) + 1 end
			standClear(tag .. " stand", l.cframe.Position)
		end
		if targets ~= 1 then bad(id .. ": " .. targets .. " targets (want 1)") end
		local pl = {} for k, v in pairs(pools) do table.insert(pl, k .. "=" .. v) end table.sort(pl)
		print("   pools: " .. table.concat(pl, " ") .. "   poolNames: " .. tostring(refs.poolNames ~= nil))
		-- smash cases untouched
		for i, c in ipairs(refs.smashCases or {}) do
			if not isInst(c.glass) or not isInst(c.visual) or c.kind ~= "Jewels" then bad(id .. " smashCase " .. i) end
		end
		-- Spin attribute
		local spins = 0
		for _, d in ipairs(refs.root:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("Spin") then
				spins += 1
				print(string.format("   Spin part %s = %s deg/s, welded children: %d", d:GetFullName(), tostring(d:GetAttribute("Spin")),
					(function() local n = 0 for _, w in ipairs(refs.root:GetDescendants()) do if w:IsA("WeldConstraint") and w.Part0 == d then n += 1 end end return n end)()))
			end
		end
		-- laser rows
		for i, row in ipairs(refs.laserRows or {}) do
			if mtypeof(row.zoneCFrame) ~= "CFrame" or mtypeof(row.zoneSize) ~= "Vector3" or #row.beams == 0 then bad(id .. " laser row " .. i .. " shape") end
			for _, b in ipairs(row.beams) do
				if b.CanCollide or b.CanQuery or b.CanTouch then bad("beam " .. b:GetFullName() .. " collides/queries") break end
				if b.Transparency ~= 1 then bad("beam " .. b:GetFullName() .. " visible at build") break end
				if not b:HasTag("Laser") then bad("beam not tagged Laser (SecurityService arm)") break end
			end
			print(string.format("   laser row %d: %d beams, zone %s size %s on %.1f off %.1f", i, #row.beams,
				tostring(row.zoneCFrame.Position), tostring(row.zoneSize), row.onTime or -1, row.offTime or -1))
		end
		-- guard routes: sample the segment every 0.5 with a 4-wide body box (2 studs clear each side)
		for _, g in ipairs(refs.guardRoutes or {}) do
			local seg = g.b - g.a
			local worst
			for d = 0, seg.Magnitude, 0.5 do
				local p = g.a + seg.Unit * d
				local hits = solids(Vector3.new(p.X, 3.8, p.Z), Vector3.new(4, 4.6, 4), function(x) return x:IsDescendantOf(WORKSPACE:FindFirstChild("Guards") or refs.root) and x:FindFirstAncestorOfClass("Model") and x:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") end)
				if #hits > 0 then worst = names(hits) .. " at " .. tostring(p) break end
			end
			if worst then bad("guard " .. g.name .. " route not 2 studs clear: " .. worst) else print("   guard " .. g.name .. " route clear (4-wide)") end
		end
		-- sneakIn drop points
		standClear(id .. " sneakIn", refs.sneakIn.at)
		-- prompts enclosed?
		for _, pr in ipairs(findPrompts(refs.root)) do
			local par = pr.Parent
			local pos = par:IsA("Attachment") and par.WorldPosition or par.Position
			local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { par }
			local clear = 0
			for k = 0, 7 do
				local a = k * math.pi / 4
				local from = pos + Vector3.new(math.cos(a) * 5, 1, math.sin(a) * 5)
				if not WORKSPACE:Raycast(from, pos - from, rp) then clear += 1 end
			end
			if clear == 0 then bad("ENCLOSED prompt " .. pr:GetFullName() .. " '" .. pr.ActionText .. "'") end
		end
		-- doorways / walkways (body box must be clear)
		local doors = id == "jewelry" and {
			{ "front door", Vector3.new(-64, 0, -0.5) }, { "front door in", Vector3.new(-64, 0, 2.5) },
			{ "west of cage", Vector3.new(-68.9, 0, 6.6) }, { "east of cage", Vector3.new(-59.1, 0, 6.6) },
			{ "north of cage", Vector3.new(-64, 0, 2.6) }, { "south of cage", Vector3.new(-64, 0, 11.5) },
			{ "archway", Vector3.new(-62, 0, 16.5) }, { "keycard door", Vector3.new(-67.5, 0, 20.5) },
			{ "office door", Vector3.new(-56.5, 0, 21) }, { "break door", Vector3.new(-50.5, 0, 25.5) },
			{ "closet door", Vector3.new(-62, 0, 28.5) }, { "closet inside", Vector3.new(-60.4, 0, 30.5) },
			{ "safe opening", Vector3.new(-76.5, 0, 24.5) }, { "safe room", Vector3.new(-76, 0, 27) },
			{ "staff door", Vector3.new(-46.5, 0, 30.3) }, { "office middle", Vector3.new(-52.5, 0, 21) },
			{ "hall end", Vector3.new(-62, 0, 26.5) }, { "window bust W", Vector3.new(-77.2, 0, 2.9) },
		} or {
			{ "front door", Vector3.new(62, 0, 1.5) }, { "curtain", Vector3.new(66.5, 0, 15.5) },
			{ "office door", Vector3.new(59.5, 0, 20) }, { "back door", Vector3.new(73.5, 0, 20) },
			{ "ATM front", Vector3.new(69.3, 0, 14.05) }, { "east aisle", Vector3.new(69.1, 0, 9) },
			{ "back aisle", Vector3.new(64, 0, 13.8) }, { "freezer front", Vector3.new(53.8, 0, 12.2) },
			{ "office floor", Vector3.new(55.5, 0, 19.2) }, { "ticket frame", Vector3.new(52.7, 0, 18.4) },
			{ "stock room", Vector3.new(65, 0, 16.9) },
		}
		for _, d in ipairs(doors) do standClear(id .. " " .. d[1], d[2]) end
	end
	-- shuffle + security arm with the new rows
	local LS = mockRequire(SERVER_SCRIPT.LootShuffle)
	for _, id in ipairs({ "jewelry", "mart" }) do
		JS:selectJob(id)
		task.wait(0.3)
		local _, refs = JS:getCurrent()
		for seed = 1, 40 do
			local act, info = LS:prepare(refs, seed)
			local hasT = false
			for _, s in ipairs(act) do if s.target then hasT = true end end
			if not hasT then bad(id .. " seed " .. seed .. " shuffle dropped the target") break end
		end
		local _, info = LS:prepare(refs, 7)
		print(string.format("   %s shuffle seed 7: %d/%d active, jackpot %s", id, info.active, info.total, tostring(info.jackpotName)))
		LS:restore(refs)
	end
	-- lasers tick: is the cage row toggling? (arm jewelry, let time pass)
	JS:selectJob("jewelry")
	task.wait(0.3)
	local _, refs = JS:getCurrent()
	local SS = mockRequire(SERVER_SCRIPT.SecurityService)
	pcall(function() SS:arm(refs) end)
	local seen = {}
	for _ = 1, 60 do
		task.wait(0.1)
		local b = refs.laserRows[3].beams[1]
		seen[b.Transparency] = true
	end
	print("   cage beam transparency seen: 0=" .. tostring(seen[0] == true) .. " 1=" .. tostring(seen[1] == true))
	print("PROBLEMS: " .. problems)
end, 60)
report()
