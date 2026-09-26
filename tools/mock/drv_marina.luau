runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	for z = -90, -112, -0.5 do
		local hits = {}
		for _, x in ipairs({ 104, 106, 108 }) do
			local r = WORKSPACE:Raycast(Vector3.new(x, 6, z), Vector3.new(0, -80, 0))
			table.insert(hits, r and string.format("%.2f %s %s", r.Position.Y, r.Instance.Name, r.Material.Name) or "VOID")
		end
		print(z, table.concat(hits, " | "))
	end
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(106, 2, -100), Vector3.new(6, 3, 6))) do if p.CanCollide then local mn, mx = partAABB(p) print("PART", p:GetFullName(), mn, mx) end end
end, 10)
