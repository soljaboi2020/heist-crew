runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({ "mart", "jewelry" }) do
		JS:selectJob(id)
		task.wait(2)
		local cfg, refs = JS:getCurrent()
		local p = refs.getawayCFrame.Position
		-- swept bumper box from the car's tail to the far side of the road
		local zTail, zEnd = p.Z + 5.8, -24
		local c = Vector3.new(p.X, 0.1 + 1.5, (zTail + zEnd) / 2)
		local seen = {}
		for _, w in ipairs({ 4.7, 6.7 }) do
			for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(c), Vector3.new(w, 1.1, zTail - zEnd))) do
				if x.CanCollide and not seen[x] and not x:FindFirstAncestor("GetawayCar") and not x:FindFirstAncestor("Ambient") then
					seen[x] = true
					print(string.format("  %s w=%.1f  %s  pos %s size %s", id, w, x:GetFullName(), tostring(x.Position), tostring(x.Size)))
				end
			end
		end
	end
end, 60)
report()
