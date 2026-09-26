local function blockedPoint(pos)
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(1.2, 3.5, 1.2))) do
		if p.CanCollide and p.Transparency < 1 then return true end
	end
	return false
end
local function reachable(pr)
	local par = pr.Parent
	local target = par:IsA("Attachment") and par.WorldPosition or par.Position
	local ignore = par:IsA("Attachment") and par.Parent or par
	local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude local ex = { ignore, WORKSPACE:FindFirstChild("Guards") }
	for _, k in ipairs(WORKSPACE:GetDescendants()) do if k.Name == "Keycard" and k:IsA("BasePart") then table.insert(ex, k) end end
	rp.FilterDescendantsInstances = ex
	local maxd = pr.MaxActivationDistance
	for r = 1.5, maxd - 0.5, 1 do
		for a = 0, 23 do
			local ang = a * math.pi / 12
			for _, dy in ipairs({ -1.5, 0, 1.5 }) do
				local p = target + Vector3.new(math.cos(ang) * r, dy, math.sin(ang) * r)
				if not blockedPoint(p) then
					local hit = WORKSPACE:Raycast(p + Vector3.new(0, 1.5, 0), target - (p + Vector3.new(0, 1.5, 0)), rp)
					if not hit then return true, p end
				end
			end
		end
	end
	return false
end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({ "mart", "villa", "jewelry", "bank" }) do
		JS:selectJob(id)
		task.wait(0.5)
		local cfg, refs = JS:getCurrent()
		local bad = 0
		for _, pr in ipairs(findPrompts(refs.root)) do
			if pr.RequiresLineOfSight then
				local ok = reachable(pr)
				if not ok then bad += 1 print("  UNREACHABLE (LOS) " .. id .. ": " .. pr:GetFullName() .. " '" .. pr.ActionText .. "' " .. pr.ObjectText) end
			end
		end
		for i, spot in ipairs(refs.keycardSpots or {}) do
			local card = Instance.new("Part") card.Size = Vector3.new(0.9, 0.06, 0.6) card.Anchored = true card.CanCollide = false
			card.CFrame = spot * CFrame.new(0, 0.05, 0) card.Parent = refs.root
			local pr = Instance.new("ProximityPrompt") pr.MaxActivationDistance = 7 pr.Parent = card
			if not reachable(pr) then bad += 1 print("  UNREACHABLE keycard spot " .. id .. " #" .. i .. " at " .. tostring(spot.Position)) end
			card:Destroy()
		end
		-- bots spawn: owner at sneakIn
		local Bots = mockRequire(SERVER_SCRIPT.BotService)
		local pl = PLAYERS:GetPlayers()[1] or addPlayer("BotOwner")
		pl.Character:PivotTo(CFrame.new(refs.sneakIn.at))
		Bots:spawnFor({ pl }, refs)
		for _, b in ipairs(Bots:getBots()) do
			local pos = b.model:GetPivot().Position
			for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(2, 4, 2))) do
				if x.CanCollide and not x:IsDescendantOf(b.model) and not x:IsDescendantOf(pl.Character) and not (x.Parent and x.Parent.Parent and x.Parent.Parent.Name == "BotCrew") then bad += 1 print("  BOT " .. b.name .. " spawned inside " .. x:GetFullName()) end
			end
		end
		Bots:despawnAll()
		print(id .. ": unreachable LOS prompts = " .. bad)
	end
end, 60)
