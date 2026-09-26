runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(4)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	JS:selectJob("mart") task.wait(0.5)
	local _, refs = JS:getCurrent()
	local att = refs.vault.door:FindFirstChild("DrillPoint")
	local pr = att:FindFirstChild("Drill")
	for _, off in ipairs({ Vector3.new(0, 0, -1.5), Vector3.new(0, 0.8, -1.5), Vector3.new(0, 1.4, -1.2), Vector3.new(0, 1.4, -0.8), Vector3.new(0, 2, -1.0), Vector3.new(0, 1.0, -1.0), Vector3.new(0, 1.6, -1.2), Vector3.new(0, 1.8, -1.0), Vector3.new(0, 1.2, -1.5) }) do
		att.Position = off
		local s, h, c, pt = losReport(pr)
		print(string.format("offset %s world %s  spots %d head %d cam %d", tostring(off), tostring(pt), s, h, c))
	end
end, 30)
