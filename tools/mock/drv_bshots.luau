local problems = {}
local function bad(msg) table.insert(problems, msg) print("  BAD " .. msg) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local jobs = {}
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		JS:selectJob(id) task.wait(0.3)
		local cfg, r = JS:getCurrent()
		jobs[id] = r
	end
	local BS = mockRequire(SERVER_SCRIPT.BriefingShots)
	local all = BS:publish({ jobs = jobs })
	local RS = REPLICATED
	local folder = RS:FindFirstChild("BriefingShots")
	if not folder then bad("no folder") end
	local function inside(pos)
		for _, p in ipairs(WORKSPACE:GetPartBoundsInRadius(pos, 0.3)) do
			if p.CanCollide and p.Transparency < 0.9 and p.CanQuery ~= false then
				local l = p.CFrame:PointToObjectSpace(pos) local h = p.Size / 2
				if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z then return p end
			end
		end
	end
	for _, id in ipairs({"mart","villa","jewelry","bank"}) do
		local shots = all[id] or {}
		local jf = folder and folder:FindFirstChild(id)
		print("== " .. id .. "  shots=" .. #shots .. " published=" .. tostring(jf and jf:GetAttribute("Count")))
		if #shots < 5 or #shots > 9 then bad(id .. " shot count " .. #shots) end
		for i, s in ipairs(shots) do
			for _, k in ipairs({"from","to"}) do
				local cf = s[k]
				for _, x in ipairs({cf:GetComponents()}) do if x ~= x then bad(id .. " " .. s.tag .. " NaN") end end
				local p = inside(cf.Position)
				if p then bad(id .. " " .. s.tag .. "." .. k .. " inside " .. p:GetFullName()) end
			end
			local look = s.from.LookVector
			local tgt = s.look
			local r = WORKSPACE:Raycast(s.from.Position, tgt - s.from.Position)
			print(string.format("  %-8s %-22s from (%.1f,%.1f,%.1f) to (%.1f,%.1f,%.1f) look(%.2f,%.2f,%.2f) sees %s @%.1f of %.1f",
				s.tag, s.label, s.from.X, s.from.Y, s.from.Z, s.to.X, s.to.Y, s.to.Z, look.X, look.Y, look.Z,
				r and r.Instance:GetFullName():sub(-50) or "nothing", r and r.Distance or -1, (tgt - s.from.Position).Magnitude))
			local sf = jf and jf:FindFirstChild(string.format("%02d", i))
			if not sf or sf:GetAttribute("Tag") ~= s.tag or mtypeof(sf:GetAttribute("From")) ~= "CFrame" then bad(id .. " publish mismatch " .. i) end
		end
	end
end, 60)
print("PROBLEMS: " .. #problems)
report()
