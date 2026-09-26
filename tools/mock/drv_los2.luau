local function srv(n) return mockRequire(SERVER_SCRIPT:FindFirstChild(n)) end
local function standable(pos)
	-- a player can stand here: floor below within 4, body box clear
	local r = WORKSPACE:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -8, 0))
	if not r then return nil end
	local feet = r.Position.Y
	local cf = CFrame.new(pos.X, feet + 2.8, pos.Z)
	local size = Vector3.new(1.8, 5, 1.2)
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(cf, size)) do
		local m = p:FindFirstAncestorOfClass("Model")
		if p.CanCollide and not (m and m:FindFirstChildOfClass("Humanoid")) and partHitsBox(p, cf, size) then return nil end
	end
	return feet
end
function losReport(pr)
	local par = pr.Parent
	local pt = par:IsA("Attachment") and par.WorldPosition or par.Position
	local part = par:IsA("Attachment") and par.Parent or par
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { part }
	for _, pl in ipairs(PLAYERS:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
	local g = WORKSPACE:FindFirstChild("Guards", true) if g then table.insert(ex, g) end
	rp.FilterDescendantsInstances = ex
	local spots, headOk, camOk = 0, 0, 0
	local R = pr.MaxActivationDistance
	for dx = -R, R, 1 do for dz = -R, R, 1 do
		local q = Vector3.new(pt.X + dx, pt.Y, pt.Z + dz)
		if Vector3.new(dx, 0, dz).Magnitude <= R - 0.5 then
			local feet = standable(q)
			if feet and math.abs(feet - (pt.Y - 3)) < 4 then
				local head = Vector3.new(q.X, feet + 4.5, q.Z)
				if (head - pt).Magnitude <= R then
					spots += 1
					if not WORKSPACE:Raycast(head, pt - head, rp) then headOk += 1 end
					-- third-person camera: 10 back + 4 up from the head, pulled in by walls
					local back = Vector3.new(head.X - pt.X, 0, head.Z - pt.Z)
					back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
					local want = head + back * 10 + Vector3.new(0, 4, 0)
					local hit = WORKSPACE:Raycast(head, want - head, rp)
					local cam = hit and (head + (want - head).Unit * math.max(0, hit.Distance - 0.5)) or want
					if not WORKSPACE:Raycast(cam, pt - cam, rp) then camOk += 1 end
				end
			end
		end
	end end
	return spots, headOk, camOk, pt
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = srv("JobService")
	task.wait(3)   -- Kenney props load (spawned)
	for _, id in ipairs(LOS_JOBS or { "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id) task.wait(0.5)
		local _, refs = JS:getCurrent()
		print("== " .. id)
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.RequiresLineOfSight and pr.Enabled ~= nil then
				local spots, h, c, pt = losReport(pr)
				local flag = (spots == 0 or h == 0 or c == 0) and "  <<< PROBLEM" or ""
				if flag ~= "" or pr.Name == "Drill" then
					print(string.format("  %-28s %-60s spots %3d head-LOS %3d cam-LOS %3d%s", pr.Name .. " '" .. pr.ActionText .. "'", pr.Parent:GetFullName():gsub("Workspace.HeistWorld.", ""), spots, h, c, flag))
				end
			end
		end
	end
end, 60)
report()
