-- ═══════ v2.2: every car type drives out of every yard gate ═══════
function localExtents(model)
	local pv = model:GetPivot()
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local l = pv:PointToObjectSpace((p.CFrame * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position)
				mn = Vector3.new(math.min(mn.X, l.X), math.min(mn.Y, l.Y), math.min(mn.Z, l.Z))
				mx = Vector3.new(math.max(mx.X, l.X), math.max(mx.Y, l.Y), math.max(mx.Z, l.Z))
			end end end
		end
	end
	return mn, mx
end
local function isBody(p)
	local m = p:FindFirstAncestorOfClass("Model")
	while m do if m:FindFirstChildOfClass("Humanoid") then return true end m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") end
	return false
end
-- full-body sweep: the car's real width (incl wheels) and height, from 0.4 above the ground
local function bodySweep(label, startCF, car, stopZ)
	local mn, mx = localExtents(car.model)
	local look = startCF.LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local yaw = CFrame.lookAt(Vector3.zero, look)
	local issues, hits = 0, {}
	local dist = math.abs((stopZ - startCF.Position.Z) / look.Z)
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { car.model } rp.RespectCanCollide = true
	local prevY
	for d = 0, dist, 0.5 do
		local c = startCF.Position + look * d
		local gy = -math.huge
		for _, off in ipairs({ 0, car.halfLen - 1, -(car.halfLen - 1) }) do
			local q = c + look * off
			local r = WORKSPACE:Raycast(Vector3.new(q.X, (prevY or 0) + 5, q.Z), Vector3.new(0, -80, 0), rp)
			if r then gy = math.max(gy, r.Position.Y) end
		end
		prevY = gy
		local y0, y1 = gy + 0.55, gy + mx.Y   -- curbs / door steps (≤0.5) are climbed by the ground-follow
		local size = Vector3.new(mx.X - mn.X, y1 - y0, mx.Z - mn.Z)
		local boxCF = CFrame.new(Vector3.new(c.X, (y0 + y1) / 2, c.Z)) * yaw.Rotation * CFrame.new(0, 0, (mn.Z + mx.Z) / 2)
		for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(boxCF, size)) do
			if p.CanCollide and not hits[p] and not p:IsDescendantOf(car.model) and not isBody(p) then
				if partHitsBox(p, boxCF, size) then
					hits[p] = true issues += 1
					local a, b = partAABB(p)
					print(string.format("  [%s] BODY HITS at d=%.1f: %s y %.2f..%.2f x %.2f..%.2f z %.2f..%.2f", label, d, p:GetFullName(), a.Y, b.Y, a.X, b.X, a.Z, b.Z))
				end
			end
		end
	end
	return issues
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local VS = mockRequire(SERVER_SCRIPT.VehicleService)
	local amb = WORKSPACE:FindFirstChild("Ambient", true)
	if amb then amb:Destroy() end
	local p1 = addPlayer("Malachi")
	task.wait(1)
	local total, rows = 0, {}
	for _, id in ipairs(YARD_JOBS) do
		for _, carId in ipairs({ "CarClassic", "CarMuscle", "CarRacer", "CarArmored", "CarMonster", "CarTank" }) do
			JS:selectJob(id)
			task.wait(0.5)
			local cfg, refs = JS:getCurrent()
			local car = VS:getCar()
			car:setType(carId)
			local cf = refs.getawayCFrame
			local stopZ = cf.LookVector.Z > 0 and -12 or -16
			local label = id .. "/" .. carId
			local n = bodySweep(label, cf, car, stopZ)
			triggerPrompt(car.driverSeat:FindFirstChild("EnterPrompt"), p1)
			task.wait(0.4)
			local ok = autoDrive(label, car, p1, marinaWaypoints(cf), 90)
			local dm = (Vector3.new(car.pos.X, 0, car.pos.Z) - Vector3.new(106, 0, -110)).Magnitude
			local drove = ok and dm <= 14
			if not drove then n += 1 end
			total += n
			table.insert(rows, string.format("%-8s %-11s gate/lane hits %d · drove to marina %s (%.1f from ring)", id, carId, n - (drove and 0 or 1), tostring(drove), dm))
			car:ejectAll()
			task.wait(0.3)
		end
	end
	print("\n==== YARD × CAR TYPE ====")
	for _, r in ipairs(rows) do print(r) end
	print("GYARD TOTAL issues: " .. total)
end, 3000)
report()
