runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local Loot = mockRequire(SERVER_SCRIPT.LootService)
	JS:selectJob("villa")
	task.wait(0.3)
	local _, r = JS:getCurrent()
	local hs = {}
	for _, s in ipairs(r.lootSpots) do if s.hidden then table.insert(hs, s) end end
	print("hidden spots", #hs, "with reveal", (hs[1] and type(hs[1].reveal)) or "-")
	local seen = 0
	for seed = 1, 120 do
		Loot:reset({ seed = seed })
		for _, pr in ipairs(findPrompts(r.root)) do if pr.Parent and pr.Parent.Name == "LootPrompt" and pr.ObjectText:find("Secret") then seen += 1 end end
	end
	print("secret stash piles seen over 120 resets:", seen)
end, 120)
report()
