runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local Target = mockRequire(SERVER_SCRIPT.TargetService)
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.3)
		local _, r = JS:getCurrent()
		local kinds, flags = {}, {}
		local tgt = Target:targetFor(id)
		local tspot = 0
		for _, s in ipairs(r.lootSpots or {}) do
			kinds[s.kind] = (kinds[s.kind] or 0) + 1
			local f = {}
			for _, k in ipairs({ "interact", "heavy", "fragile", "hidden", "target", "pool" }) do if s[k] ~= nil and s[k] ~= false then table.insert(f, k .. "=" .. tostring(s[k])) end end
			flags[s.kind .. " [" .. table.concat(f, " ") .. "]" .. (s.inVault == false and "" or " VAULT")] = (flags[s.kind .. " [" .. table.concat(f, " ") .. "]" .. (s.inVault == false and "" or " VAULT")] or 0) + 1
			if s.kind == tgt.kind or s.target then tspot += 1 end
		end
		print(("== %s: %d spots, target %s spots=%d, cases=%d, poolNames=%s"):format(id, #(r.lootSpots or {}), tgt.kind, tspot, #(r.smashCases or {}), tostring(r.poolNames ~= nil)))
		local keys = {} for k in pairs(flags) do table.insert(keys, k) end table.sort(keys)
		for _, k in ipairs(keys) do print("   ", flags[k], k) end
		local acts = {}
		for _, pr in ipairs(findPrompts(r.root)) do if pr.Parent and pr.Parent.Name == "LootPrompt" then acts[pr.ActionText .. (pr.Enabled and "" or " (locked)")] = (acts[pr.ActionText .. (pr.Enabled and "" or " (locked)")] or 0) + 1 end end
		for k, v in pairs(acts) do print("    prompt:", v, k) end
	end
end, 60)
report()
