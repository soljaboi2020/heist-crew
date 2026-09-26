-- ═══════ v2.1 yard-gate / getaway lane test ═══════
local W
local function bb(m) local cf, sz = m:GetBoundingBox() return cf, sz end
local function isBody(p)
	local m = p:FindFirstAncestorOfClass("Model")
	while m do if m:FindFirstChildOfClass("Humanoid") then return true end m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model") end
	return false
end
function laneSweep(label, startCF, carModel, stopZ, extraIgnore)
	local look = startCF.LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local hits, issues = {}, 0
	local dist = math.abs((stopZ - startCF.Position.Z) / look.Z)
	local prevY
	local yaw = CFrame.lookAt(Vector3.zero, look)
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { carModel } rp.RespectCanCollide = true
	for d = 0, dist, 0.5 do
		local c = startCF.Position + look * d
		-- ground (centre / nose / tail) like Kin.groundAt
		local gy = -math.huge
		for _, off in ipairs({ 0, 4.6, -4.6 }) do
			local q = c + look * off
			local r = WORKSPACE:Raycast(Vector3.new(q.X, (prevY or 0) + 5, q.Z), Vector3.new(0, -80, 0), rp)
			if not r then print(string.format("  [%s] VOID under car at d=%.1f", label, d)) issues += 1 break end
			if r.Material == Enum.Material.Water then print(string.format("  [%s] WATER at d=%.1f", label, d)) issues += 1 break end
			gy = math.max(gy, r.Position.Y)
		end
		if prevY and gy - prevY > 1.2 then issues += 1 print(string.format("  [%s] STEP %.2f at d=%.1f (%s)", label, gy - prevY, d, tostring(c))) end
		prevY = gy
		-- body box: full car footprint (+0.15 margin each side), bumper-bottom .. roof
		local boxCF = CFrame.new(Vector3.new(c.X, gy + 0.95 + 1.3, c.Z)) * yaw.Rotation
		local size = Vector3.new(4.7 + 0.3, 2.6, 11.2)
		for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(boxCF, size)) do
			if p.CanCollide and not hits[p] and not p:IsDescendantOf(carModel) and not isBody(p) and not (extraIgnore and extraIgnore(p)) then
				if partHitsBox(p, boxCF, size) then
					hits[p] = true issues += 1
					local mn, mx = partAABB(p)
					print(string.format("  [%s] BLOCKER at d=%.1f: %s [%s %s] x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f", label, d, p:GetFullName(), p.ClassName, tostring(p.Shape or ""), mn.X, mx.X, mn.Y, mx.Y, mn.Z, mx.Z))
				end
			end
		end
	end
	return issues
end

-- autopilot through VehicleService (real Kin.advance + Blockcast)
function autoDrive(label, car, player, waypoints, timeout)
	local inRemote = REPLICATED.Remotes:FindFirstChild("CarInput") or REPLICATED:FindFirstChild("CarInput", true)
	local wi, stuckT, t0 = 1, 0, SCHED.now
	local lastPos = car.pos
	while SCHED.now - t0 < (timeout or 60) do
		local wp = waypoints[wi]
		if not wp then return true end
		local pos = car.pos
		local to = Vector3.new(wp.X - pos.X, 0, wp.Z - pos.Z)
		if to.Magnitude < 4 then wi += 1 continue end
		local want = math.atan2(-to.X, -to.Z)
		local diff = (want - car.yaw + math.pi) % (2 * math.pi) - math.pi
		local steer = math.clamp(-diff * 2.5, -1, 1)
		local target = math.abs(diff) > 0.3 and (AUTO_TURN or 7) or ((to.Magnitude > 25) and (AUTO_FAST or 12) or 10)
		local thr = car.v < target and 1 or (car.v > target + 3 and -0.3 or 0)
		inRemote.OnServerEvent:Fire(player, thr, steer)
		if AUTO_NITRO and math.abs(diff) < 0.15 and to.Magnitude > 30 then REPLICATED.Remotes.Nitro.OnServerEvent:Fire(player) end
		task.wait(0.1)
		if (car.pos - lastPos).Magnitude < 0.05 then stuckT += 0.1 else stuckT = 0 end
		lastPos = car.pos
		local hs = REMOTE_LOG and REMOTE_LOG["HeistState"]
		if hs and hs[2] == "COMPLETE" and (Vector3.new(car.pos.X, 0, car.pos.Z) - Vector3.new(106, 0, -110)).Magnitude <= 14 then return true end
		if stuckT > 2 then
			local look = CFrame.new(car.pos) * CFrame.Angles(0, car.yaw, 0)
			local _, obEx = nil, { car.model }
			for _, pl in ipairs(PLAYERS:GetPlayers()) do if pl.Character then table.insert(obEx, pl.Character) end end
			local VS = mockRequire(SERVER_SCRIPT.VehicleService)
			local hit
			for k, fn in pairs(VS) do end
			print(string.format("  [%s] DRIVE STUCK at %s yaw %.2f heading to wp%d %s", label, tostring(car.pos), car.yaw, wi, tostring(wp)))
			local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = obEx rp.RespectCanCollide = true
			local origin = look * CFrame.new(0, 1.5, -(5.6 - 0.4))
			local r = WORKSPACE:Blockcast(origin, Vector3.new(4.7, 1.1, 0.4), look.LookVector * 3, rp)
			print("     blockcast ahead → " .. (r and (r.Instance:GetFullName() .. " at " .. tostring(r.Position)) or "nothing (ground/step refused?)"))
			print(string.format("     frozen=%s v=%.1f BustMeter=%s driver=%s alarm=%s", tostring(car.frozen), car.v, tostring(car.model:GetAttribute("BustMeter")), tostring(car:getDriver() and car:getDriver().Name), tostring(car.alarm)))
			local pf = WORKSPACE:FindFirstChild("Police", true)
			if pf then for _, m in ipairs(pf:GetChildren()) do if m:IsA("Model") then print("     police model", m.Name, m:GetPivot().Position) end end end
			return false
		end
	end
	print(string.format("  [%s] DRIVE timeout at wp%d, car at %s", label, wi, tostring(car.pos)))
	return false
end

function marinaWaypoints(startCF)
	local p = startCF.Position
	local look = startCF.LookVector
	local fromNorth = look.Z > 0
	local laneZ = -14
	local wps = {}
	local d = (laneZ - p.Z) / look.Z
	table.insert(wps, p + Vector3.new(look.X, 0, look.Z) * (d - 3))
	table.insert(wps, p + Vector3.new(look.X, 0, look.Z) * d)
	local xDir = (108 > p.X) and 1 or -1
	table.insert(wps, Vector3.new(p.X + xDir * 14, 0, laneZ))
	if math.abs(108 - p.X) > 20 then table.insert(wps, Vector3.new(108 - xDir * 10, 0, laneZ)) end
	table.insert(wps, Vector3.new(108, 0, laneZ - 10))
	table.insert(wps, Vector3.new(106, 0, -104))
	return wps
end
