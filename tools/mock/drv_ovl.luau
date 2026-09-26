runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(2)
	local function scan(label, rootName, x0, z0, x1, z1)
		local c = Vector3.new((x0 + x1) / 2, 6, (z0 + z1) / 2)
		local n = 0
		for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(c), Vector3.new(x1 - x0, 11.6, z1 - z0))) do
			if not p:FindFirstAncestor(rootName) and not p:FindFirstAncestor("Ambient") then
				n += 1
				if n <= 25 then print(string.format("  %s foreign: %s pos %s size %s", label, p:GetFullName(), tostring(p.Position), tostring(p.Size))) end
			end
		end
		print(label, "foreign parts:", n)
	end
	scan("JEWELRY yard", "DiamondDolls", -46, 2.6, -25, 44)
	scan("JEWELRY back", "DiamondDolls", -82.6, 35, -46, 44)
	scan("MART yard", "SunnysMart", 74, 1, 83.7, 33.5)
	scan("MART back", "SunnysMart", 50, 25, 74, 33.5)
end, 30)
report()
