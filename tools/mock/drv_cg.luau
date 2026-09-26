runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(3)
	local cg
	for _, d in ipairs(WORKSPACE:GetDescendants()) do if d.Name == "CityGround" then cg = d break end end
	assert(cg, "no CityGround")
	local n, hits, seen = 0, 0, {}
	for _, p in ipairs(cg:GetDescendants()) do
		if p:IsA("BasePart") then
			n += 1
			local sz = p.Size - Vector3.new(0.1, 0.1, 0.1)
			if sz.X > 0 and sz.Y > 0 and sz.Z > 0 then
				for _, o in ipairs(WORKSPACE:GetPartBoundsInBox(p.CFrame, sz)) do
					if not o:IsDescendantOf(cg) and o.Name ~= "Ground" and o.ClassName ~= "Terrain" then
						local key = o:GetFullName()
						if not seen[key] then
							seen[key] = true
							hits += 1
							if hits <= 40 then print(string.format("OVERLAP %s @(%.0f,%.0f) with %s @(%.0f,%.1f,%.0f)", p.Name, p.Position.X, p.Position.Z, key, o.Position.X, o.Position.Y, o.Position.Z)) end
						end
					end
				end
			end
		end
	end
	print("citygound parts", n, "overlaps", hits)
	local total = 0
	for _, d in ipairs(WORKSPACE:GetDescendants()) do if d:IsA("BasePart") then total += 1 end end
	print("total parts in workspace", total)
	local lights = 0
	for _, d in ipairs(cg:GetDescendants()) do if d:IsA("Light") then lights += 1 end end
	print("citygound lights", lights)
end, 60)
report()
