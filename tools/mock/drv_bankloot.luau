-- BANK-LOOT v3 checks: kinds, flags, visuals, reachability, door swing, routes
local problems = 0
local function bad(msg) problems += 1 print("  BAD " .. msg) end
local FLOOR = 2.0
local VALID = { GoldBars = true, MoneyCart = true, DepositBox = true, Bonds = true, CrownJewel = true, SecretStash = true,
	Cash = true, Jewels = true, Watch = true }
local INTERACT = { cut = true, dial = true, stuff = true, unscrew = true, drill = true }

local function solid(pos, size, ignore)
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pos), size)) do
		if p.CanCollide and p.Transparency < 1 and not (ignore and ignore[p]) then return p end
	end
	return nil
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local C = mockRequire(REPLICATED.Shared.Constants)
	for k in pairs(C.LOOT or {}) do VALID[k] = true end
	for k in pairs(C.LOOT_V3 or {}) do VALID[k] = true end
	JS:selectJob("bank")
	task.wait(0.5)
	local cfg, refs = JS:getCurrent()
	local spots = refs.lootSpots
	print("bank lootSpots: " .. #spots)

	-- 1. contract ------------------------------------------------------------
	local pools, kinds, seenVis = {}, {}, {}
	local nTarget, nDep, nDial, nHidden = 0, 0, 0, 0
	for i, s in ipairs(spots) do
		local tag = string.format("#%d %s", i, tostring(s.kind))
		if not VALID[s.kind] then bad(tag .. " unknown kind") end
		if mtypeof(s.cframe) ~= "CFrame" then bad(tag .. " cframe") end
		if not (mtypeof(s.visual) == "Instance" and s.visual:IsDescendantOf(WORKSPACE)) then bad(tag .. " visual missing") else
			local n = s.visual:IsA("BasePart") and 1 or 0
			for _, d in ipairs(s.visual:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
			if n == 0 then bad(tag .. " visual has no parts") end
			if seenVis[s.visual] then bad(tag .. " shares a visual with " .. seenVis[s.visual]) end
			seenVis[s.visual] = tag
		end
		if s.interact ~= nil and not INTERACT[s.interact] then bad(tag .. " interact " .. tostring(s.interact)) end
		for _, f in ipairs({ "heavy", "fragile", "hidden", "inVault" }) do
			if s[f] ~= nil and type(s[f]) ~= "boolean" then bad(tag .. " " .. f .. " not boolean") end
		end
		if s.target then nTarget += 1 if s.target ~= "CrownJewel" then bad(tag .. " target " .. s.target) end end
		if s.kind == "DepositBox" then nDep += 1 if s.interact == "dial" then nDial += 1 end end
		if s.hidden then nHidden += 1 end
		pools[tostring(s.pool)] = (pools[tostring(s.pool)] or 0) + 1
		kinds[s.kind] = (kinds[s.kind] or 0) + 1
	end
	if nTarget ~= 1 then bad("targets = " .. nTarget) end
	if nDep ~= 20 then bad("DepositBox = " .. nDep) end
	if nDial ~= 4 then bad("dial deposit boxes = " .. nDial) end
	if nHidden ~= 1 then bad("hidden spots = " .. nHidden) end
	local pl = {} for k, v in pairs(pools) do table.insert(pl, k .. "=" .. v) end table.sort(pl)
	local kl = {} for k, v in pairs(kinds) do table.insert(kl, k .. "=" .. v) end table.sort(kl)
	print("  pools: " .. table.concat(pl, " "))
	print("  kinds: " .. table.concat(kl, " "))

	-- LootService made one prompt per spot?
	local nPrompt = 0
	for _, pr in ipairs(findPrompts(refs.root)) do if pr.Name == "BagLoot" then nPrompt += 1 end end
	print("  BagLoot prompts: " .. nPrompt)
	if nPrompt ~= #spots then bad("prompt count " .. nPrompt .. " vs spots " .. #spots) end

	-- 2. open the vault door (reachability is judged with it OPEN) + swing sweep --
	local v = refs.vault
	local closed = {}
	for _, p in ipairs(v.parts) do closed[p] = p.CFrame end
	local lootFolder = refs.root:FindFirstChild("VaultLoot")
	local lootSet = {}
	for _, d in ipairs(lootFolder:GetDescendants()) do if d:IsA("BasePart") then lootSet[d] = true end end
	local swingHits = {}
	for deg = 0, -100, -4 do
		local sw = v.hinge * CFrame.Angles(0, math.rad(deg), 0)
		for _, p in ipairs(v.parts) do
			local cf = sw * v.hinge:ToObjectSpace(closed[p])
			for _, q in ipairs(WORKSPACE:GetPartBoundsInBox(cf, p.Size)) do
				if lootSet[q] and not swingHits[q] then swingHits[q] = true bad(string.format("door swing %d° (%s) hits %s", deg, p.Name, q:GetFullName())) end
			end
		end
	end
	local open = v.hinge * CFrame.Angles(0, v.openAngle, 0)
	for _, p in ipairs(v.parts) do p.CFrame = open * v.hinge:ToObjectSpace(closed[p]) end

	-- 3. walk grid (0.5 studs), character box 1.8 × 3.6 × 1.8 ---------------------
	local function flood(x0, x1, z0, z1, start)
		local step = 0.5
		local free, seen = {}, {}
		local function key(i, j) return i * 10000 + j end
		local nx, nz = math.floor((x1 - x0) / step), math.floor((z1 - z0) / step)
		local si, sj = math.floor((start.X - x0) / step + 0.5), math.floor((start.Z - z0) / step + 0.5)
		local q, h = { { si, sj } }, 1
		seen[key(si, sj)] = true
		while h <= #q do
			local c = q[h] h += 1
			local pos = Vector3.new(x0 + c[1] * step, FLOOR + 2.7, z0 + c[2] * step)
			if not solid(pos, Vector3.new(1.8, 3.6, 1.8)) then
				free[#free + 1] = pos
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local i, j = c[1] + d[1], c[2] + d[2]
					if i >= 0 and i <= nx and j >= 0 and j <= nz and not seen[key(i, j)] then
						seen[key(i, j)] = true
						q[#q + 1] = { i, j }
					end
				end
			end
		end
		return free
	end
	local vaultCells = flood(85.2, 106.5, 39.7, 53.8, Vector3.new(105, 0, 49))
	local hallCells = flood(85, 131, 9, 28, Vector3.new(108, 0, 12))
	print(string.format("  walkable cells: vault %d, hall %d", #vaultCells, #hallCells))
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { WORKSPACE:FindFirstChild("Guards") }
	for _, s in ipairs(spots) do table.insert(ex, s.visual) end
	for _, pr in ipairs(findPrompts(refs.root)) do table.insert(ex, pr.Parent) end
	rp.FilterDescendantsInstances = ex
	for i, s in ipairs(spots) do
		local anchor = s.cframe.Position + Vector3.new(0, 2.5, 0)
		local cells = (s.inVault ~= false) and vaultCells or hallCells
		local best = math.huge
		for _, c in ipairs(cells) do
			local d = (c - anchor).Magnitude
			if d < best and d <= 6.5 then
				local eye = c + Vector3.new(0, 1.2, 0)
				local hit = WORKSPACE:Raycast(eye, anchor - eye, rp)
				if not hit then best = d end
			end
		end
		local inside = solid(anchor, Vector3.new(0.3, 0.3, 0.3))
		if inside then bad(string.format("#%d %s prompt anchor inside %s", i, s.kind, inside:GetFullName())) end
		if best == math.huge then bad(string.format("#%d %s (%s) UNREACHABLE from the walk grid, anchor %s", i, s.kind, tostring(s.pool), tostring(anchor)))
		elseif best > 4 then print(string.format("  note #%d %s nearest standing cell %.1f studs", i, s.kind, best)) end
	end
	-- the vault doorway itself must be walkable with the door open
	for _, z in ipairs({ 46.5, 49, 51.5 }) do
		local p = solid(Vector3.new(106.9, FLOOR + 2.7, z), Vector3.new(1.4, 3.6, 1.4))
		if p then bad("vault doorway blocked at z " .. z .. " by " .. p:GetFullName()) end
	end
	for _, p in ipairs(v.parts) do p.CFrame = closed[p] end

	-- 4. guard routes: nothing new within 2 studs (report every collidable) -----
	for _, g in ipairs(refs.guardRoutes) do
		local a, b = g.a, g.b
		local n = math.max(1, math.floor((b - a).Magnitude / 0.5))
		local near = {}
		for k = 0, n do
			local p = a + (b - a) * (k / n)
			for _, q in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(p.X, FLOOR + 2.5, p.Z), Vector3.new(4, 3, 4))) do
				if q.CanCollide and q.Transparency < 1 and not near[q] then
					near[q] = true
				end
			end
		end
		local names = {}
		for q in pairs(near) do if q:IsDescendantOf(refs.root) then table.insert(names, q.Name) end end
		table.sort(names)
		print(string.format("  route %s within 2 studs: %s", tostring(g.name), #names > 0 and table.concat(names, ",") or "nothing"))
	end
end, 60)
print("BANKLOOT PROBLEMS: " .. problems)
report()
