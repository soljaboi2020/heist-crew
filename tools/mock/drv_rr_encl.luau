-- flood-fill the walkable cells from inside each service yard; report leaks
local CASES = {
	-- the street line is treated as closed (z0): leaving through the gate / front door is fine
	{ job = "mart", start = Vector3.new(77, 0, 20), x0 = 40, x1 = 92, z0 = 2, z1 = 42,
	  leak = function(x, z) return z > 33.6 or x > 83.8 or x < 47.9 end },
	{ job = "jewelry", start = Vector3.new(-33, 0, 30), x0 = -94, x1 = -18, z0 = 4, z1 = 52,
	  leak = function(x, z) return z > 44.1 or x < -82.1 or x > -25 end },
}
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local total = 0
	for _, c in ipairs(CASES) do
		JS:selectJob(c.job)
		task.wait(0.5)
		local guards = WORKSPACE:FindFirstChild("Guards")
		local function free(x, z)
			for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(x, 3.4, z), Vector3.new(1.4, 3.6, 1.4))) do
				if p.CanCollide and not (guards and p:IsDescendantOf(guards)) and not p:IsDescendantOf(WORKSPACE:FindFirstChild("GetawayCar") or guards) then
					if p:FindFirstAncestorOfClass("Model") == nil or not p:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then return false end
				end
			end
			return true
		end
		local seen, q, leaks, n = {}, {}, 0, 0
		local function key(i, j) return i * 1000 + j end
		local si, sj = math.floor(c.start.X), math.floor(c.start.Z)
		table.insert(q, { si, sj }) seen[key(si, sj)] = true
		while #q > 0 do
			local cell = table.remove(q)
			local x, z = cell[1] + 0.5, cell[2] + 0.5
			n += 1
			if c.leak(x, z) then
				leaks += 1
				if leaks <= 6 then print(string.format("  LEAK %s reached %.1f, %.1f", c.job, x, z)) end
			else
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local i, j = cell[1] + d[1], cell[2] + d[2]
					if i >= c.x0 and i < c.x1 and j >= c.z0 and j < c.z1 and not seen[key(i, j)] then
						seen[key(i, j)] = true
						if free(i + 0.5, j + 0.5) then table.insert(q, { i, j }) end
					end
				end
			end
		end
		print(string.format("== %s: %d cells reached, %d leak cells", c.job, n, leaks))
		for _, pt in ipairs(c.job == "mart" and { {54, 23, "office"}, {66, 19, "stock"}, {64, 4, "sales"}, {51, 18, "ticket"}, {54, 27, "safe front"}, {69, 28, "lotto"} }
			or { {-51, 23, "office"}, {-45, 35, "break"}, {-61, 37, "closet"}, {-62, 24, "hall"}, {-62, 10, "showroom"}, {-44, 25, "office bay"}, {-37, 25, "ladder foot"} }) do
			local ok = seen[key(math.floor(pt[1]), math.floor(pt[2]))]
			if not ok then total += 1 end
			print(string.format("   reach %-12s %s", pt[3], ok and "yes" or "NO"))
		end
		total += leaks
	end
	print("ENCLOSURE leaks: " .. total)
end, 120)
