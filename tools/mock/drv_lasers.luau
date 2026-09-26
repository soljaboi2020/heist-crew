local function srv(name) return mockRequire(SERVER_SCRIPT:FindFirstChild(name)) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	for _, id in ipairs({ "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.3)
		local cfg, refs = JS:getCurrent()
		print("== " .. id)
		for i, row in ipairs(refs.laserRows or {}) do
			local c, s = row.zoneCFrame, row.zoneSize or Vector3.new(8, 5, 0.6)
			print(string.format("  row %d centre (%.1f, %.1f, %.1f) size (%.1f, %.1f, %.1f)", i, c.Position.X, c.Position.Y, c.Position.Z, s.X, s.Y, s.Z))
		end
		local d = refs.keycardDoors and refs.keycardDoors[1]
		if d then
			local pp = d.panel
			print(string.format("  keypad (%.1f, %.1f, %.1f) look (%.2f, %.2f)  stand ≈ (%.1f, %.1f)", pp.Position.X, pp.Position.Y, pp.Position.Z, pp.CFrame.LookVector.X, pp.CFrame.LookVector.Z,
				pp.Position.X + pp.CFrame.LookVector.X * 2.5, pp.Position.Z + pp.CFrame.LookVector.Z * 2.5))
		end
		local vd = refs.vault.door
		print(string.format("  vault door (%.1f, %.1f, %.1f) look (%.2f, %.2f)  drillOffset %s", vd.Position.X, vd.Position.Y, vd.Position.Z, vd.CFrame.LookVector.X, vd.CFrame.LookVector.Z, tostring(refs.vault.drillOffset)))
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.Name == "Drill" then
				local par = pr.Parent
				local pos = par:IsA("Attachment") and par.WorldPosition or par.Position
				print(string.format("  drill prompt at (%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))
			end
		end
	end
end, 200)
report()
