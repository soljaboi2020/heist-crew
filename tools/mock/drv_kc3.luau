runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(3)
	local MB = mockRequire(SERVER_SCRIPT.MiamiBuilder)
	local KC = MB.KEEP_CLEAR
	local miami = WORKSPACE:FindFirstChild("NeonMiami", true)
	local cg = miami:FindFirstChild("CityGround")
	local n = 0
	for _, p in ipairs(cg:GetDescendants()) do
		if p:IsA("BasePart") then
			local mn, mx = partAABB(p)
			if mx.Y > 0.7 then
				for ri, r in ipairs(KC) do
					if mx.X > r[1] and mn.X < r[3] and mx.Z > r[2] and mn.Z < r[4] then
						n += 1
						if n < 40 and not p:IsDescendantOf(cg:FindFirstChild("RoadEnds")) then print(string.format("CITYGROUND in KEEP_CLEAR #%d {%s}: %s CC=%s x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f", ri, table.concat(r, ","), p:GetFullName(), tostring(p.CanCollide), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z)) end
					end
				end
			end
		end
	end
	print("CityGround KEEP_CLEAR violations: " .. n)
	-- Miami collidables interpenetrating job/club/safehouse builders' collidables
	local hw = WORKSPACE:FindFirstChild("HeistWorld")
	local m2 = 0
	for _, p in ipairs(miami:GetDescendants()) do
		if p:IsA("BasePart") and p.CanCollide and p.Transparency < 1 then
			local mn, mx = partAABB(p)
			if mx.Y > 0.7 then
				for _, q in ipairs(WORKSPACE:GetPartBoundsInBox(p.CFrame, p.Size)) do
					if q.CanCollide and q.Transparency < 1 and not q:IsDescendantOf(miami) and q:IsDescendantOf(hw) and q.Name ~= "Ground" then
						local qmn, qmx = partAABB(q)
						-- shrink test by 0.1 so touching faces don't count
						if qmx.Y > 0.7 and partHitsBox(q, p.CFrame, p.Size - Vector3.new(0.2, 0.2, 0.2)) then
							m2 += 1
							if m2 < 40 then print(string.format("OVERLAP %s [x %.2f..%.2f y %.1f..%.1f z %.2f..%.2f]  ×  %s [x %.2f..%.2f y %.1f..%.1f z %.2f..%.2f]", p:GetFullName(), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z, q:GetFullName(), qmn.X, qmx.X, qmn.Y, qmx.Y, qmn.Z, qmx.Z)) end
						end
					end
				end
			end
		end
	end
	print("Miami×builder overlaps: " .. m2)
end, 60)
