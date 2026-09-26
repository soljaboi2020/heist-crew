runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(3)
	local MB = mockRequire(SERVER_SCRIPT.MiamiBuilder)
	local KC = MB.KEEP_CLEAR
	local miami = WORKSPACE:FindFirstChild("NeonMiami", true)
	local cityGround = miami:FindFirstChild("CityGround")
	local counts, n = {}, 0
	for _, p in ipairs(miami:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide then
			local mn, mx = partAABB(p)
			if mx.Y > 0.7 then
				for ri, r in ipairs(KC) do
					local inCG = p:IsDescendantOf(cityGround)
					-- city dressing: never inside any rect. Everything else: only the heist lots / yards / marina route / car alley
					local strict = inCG or (ri ~= 1 and ri ~= 17 and ri ~= 4 and ri ~= 5 and ri ~= 6 and ri ~= 7 and ri ~= 18 and ri ~= 19)
					if strict and mx.X > r[1] and mn.X < r[3] and mx.Z > r[2] and mn.Z < r[4] then
						local key = p:GetFullName():gsub("%.%d+$", "")
						if not counts[key .. ri] then
							counts[key .. ri] = true n += 1
							print(string.format("KEEP_CLEAR #%d {%s} ← %s  x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f", ri, table.concat(r, ","), p:GetFullName(), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z))
						end
					end
				end
			end
		end
	end
	print("KEEP_CLEAR violations: " .. n)
end, 30)
