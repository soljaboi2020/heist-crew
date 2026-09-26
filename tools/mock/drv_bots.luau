runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local Bots = mockRequire(SERVER_SCRIPT.BotService)
	local p = addPlayer("Solo")
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		Bots:spawnFor({ p }, refs)
		for _, b in ipairs(Bots:getBots()) do
			local pos = b.model:GetPivot().Position
			local hits = {}
			for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(2, 4, 2))) do
				if x.CanCollide and not x:IsDescendantOf(b.model) then table.insert(hits, x:GetFullName()) end
			end
			print(id, b.name, pos, #hits == 0 and "clear" or ("BLOCKED " .. table.concat(hits, ", ")))
		end
		-- drill prompt parent
		local d = refs.vault.door:FindFirstChild("DrillPoint")
		print("   drill prompt at", d and d.WorldPosition, d and d:FindFirstChild("Drill") and "ok")
	end
end, 30)
report()
