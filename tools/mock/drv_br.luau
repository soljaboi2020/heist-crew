runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("jewelry") task.wait(0.5)
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(-51, 4, 29), Vector3.new(12, 7, 14))) do
		local mn, mx = partAABB(p)
		if p.CanCollide and mx.Y > 1 then print(string.format("%-70s %s x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f", p:GetFullName(), p.ClassName, mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z)) end
	end
end, 10)
