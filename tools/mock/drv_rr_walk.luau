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
local nbad = 0
local function standClear(label, pos, w)
	local c = Vector3.new(pos.X, 0.5 + 3.3, pos.Z)
	local hits = solids(c, Vector3.new(w or 1.8, 4.6, w or 1.8), function(p) return p:IsDescendantOf(WORKSPACE:FindFirstChild("Guards")) end)
	if #hits > 0 then nbad += 1 print("  BAD " .. label .. " not standable @ " .. tostring(Vector3.new(pos.X, 0, pos.Z)) .. " → " .. names(hits)) end
end
-- a doorway: a 3-wide body sweep through the opening, plus clear head room to y 11
local function doorway(label, a, b)
	local d = b - a
	for t = 0, 1, 0.1 do standClear(label .. string.format(" t=%.1f", t), a + d * t, 2.6) end
end
local POINTS = {
	mart = {
		{ "front door", Vector3.new(62, 0, 1.5) }, { "curtain", Vector3.new(66.6, 0, 15.5) }, { "ATM front", Vector3.new(69.3, 0, 14.05) },
		{ "east aisle", Vector3.new(69.1, 0, 9) }, { "back aisle", Vector3.new(64, 0, 13.8) }, { "freezer front", Vector3.new(53.8, 0, 12.2) },
		{ "clerk aisle", Vector3.new(53.3, 0, 6.5) },
		{ "office floor", Vector3.new(54.5, 0, 23) }, { "ticket stand", Vector3.new(51.6, 0, 18.1) }, { "safe approach", Vector3.new(54.5, 0, 27.4) },
		{ "ladder foot", Vector3.new(51.9, 0, 24.3) }, { "sofa-safe gap", Vector3.new(51.1, 0, 26.1) }, { "office desk chair gap", Vector3.new(55.5, 0, 20.5) },
		{ "stock room N", Vector3.new(66, 0, 18.5) }, { "deposit stand", Vector3.new(66, 0, 22.2) }, { "lotto stand", Vector3.new(69.45, 0, 28.3) },
		{ "stock W aisle", Vector3.new(62.5, 0, 25) }, { "stock E aisle", Vector3.new(69.8, 0, 25) }, { "sneakIn", Vector3.new(69, 0, 20.8) },
		{ "yard by door", Vector3.new(76.5, 0, 21) }, { "yard to ladder", Vector3.new(77.2, 0, 26.5) },
	},
	jewelry = RR_JEWEL_POINTS or {},
}
local DOORS = {
	mart = {
		{ "curtain", Vector3.new(66.6, 0, 14), Vector3.new(66.6, 0, 17.6) },
		{ "office door", Vector3.new(62, 0, 23.5), Vector3.new(58, 0, 23.5) },
		{ "loading door", Vector3.new(71.5, 0, 21), Vector3.new(76, 0, 21) },
	},
	jewelry = RR_JEWEL_DOORS or {},
}
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs(RR_JOBS or { "mart", "jewelry" }) do
		JS:selectJob(id)
		task.wait(0.6)
		print("== walk " .. id)
		for _, d in ipairs(POINTS[id]) do standClear(id .. " " .. d[1], d[2]) end
		for _, d in ipairs(DOORS[id]) do doorway(id .. " " .. d[1], d[2], d[3]) end
	end
	print("WALK issues: " .. nbad)
end, 60)
