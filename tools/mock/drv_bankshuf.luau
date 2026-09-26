runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local LS = mockRequire(SERVER_SCRIPT.LootShuffle)
	JS:selectJob("bank")
	task.wait(0.5)
	local _, refs = JS:getCurrent()
	local stash, crownMissing, jack = 0, 0, {}
	for seed = 1, 200 do
		LS:prepare(refs, seed)
		for _, s in ipairs(refs.lootSpots) do
			if s.kind == "SecretStash" and LS:isActive(s) then stash += 1 end
			if s.kind == "CrownJewel" and not LS:isActive(s) then crownMissing += 1 end
		end
		local i = LS:info()
		jack[i.jackpotName] = (jack[i.jackpotName] or 0) + 1
	end
	print("stash armed in " .. stash .. "/200 runs; crown missing in " .. crownMissing)
	for k, v in pairs(jack) do print("  jackpot " .. k .. ": " .. v) end
	-- visual hidden when inactive?
	LS:prepare(refs, 3)
	for _, s in ipairs(refs.lootSpots) do
		if not LS:isActive(s) then
			local p = s.visual:IsA("BasePart") and s.visual or s.visual:FindFirstChildWhichIsA("BasePart", true)
			if p.Transparency < 1 then print("  VISIBLE while inactive: " .. s.kind) end
		end
	end
	LS:restore(refs)
end, 60)
report()
