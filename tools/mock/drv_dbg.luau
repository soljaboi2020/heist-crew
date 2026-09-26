runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		local s = refs.sneakIn
		print(id, "sneakIn at", s.at, "face", s.face, "spread", s.spread)
		for i, r in ipairs(refs.guardRoutes or {}) do
			print("   route", r.name, "spawn", r.spawn, "a", r.a, "b", r.b, string.format("dist a %.1f b %.1f", (r.a - s.at).Magnitude, (r.b - s.at).Magnitude))
		end
		for n, g in pairs(mockRequire(SERVER_SCRIPT.GuardService):getGuards()) do print("   guard", n, g.root.Position) end
		for _, e in ipairs(refs.entrances or {}) do print("   entrance", e.kind, e.at, e.label) end
		print("   getaway", refs.getawayCFrame and refs.getawayCFrame.Position, "policeStop", refs.policeStop)
	end
end, 60)
report()
