runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local NF = mockRequire(SERVER_SCRIPT.NpcFactory)
	for i = 1, 7 do
		local spec = NF.outfitFor(i, { name = "Bot_" .. i, mask = (i == 7) and 93050572 or nil })
		local m, h, r = NF.build(spec)
		print(i, spec.name, spec.shirt, spec.pants, spec.hats and table.concat(spec.hats, ",") or "-", m ~= nil, h ~= nil)
	end
	local s = NF.outfit("nope")
	print("fallback", s.shirt)
end, 30)
report()
