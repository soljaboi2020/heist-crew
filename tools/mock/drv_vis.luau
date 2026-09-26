runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local G = mockRequire(SERVER_SCRIPT.GuardService)
	local C = mockRequire(REPLICATED.Shared.Constants)
	local p = addPlayer("P")
	for _, id in ipairs({ "villa", "mart", "bank" }) do
		JS:selectJob(id)
		task.wait(2)
		for name, g in pairs(G:getGuards()) do
			local head = g.head.Position
			local look = g.root.CFrame.LookVector
			local tgt = g.root.Position + Vector3.new(look.X, 0, look.Z).Unit * 8
			p.Character:PivotTo(CFrame.new(tgt))
			local hrp = p.Character.HumanoidRootPart
			local to = hrp.Position - head
			local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { g.model }
			local hit = WORKSPACE:Raycast(head, to, rp)
			print(string.format("%s %s head %s root %s look %s dot %.2f cosHalf %.2f hit %s | cantSee %s", id, name, tostring(head), tostring(g.root.Position), tostring(look),
				look:Dot(to.Unit), math.cos(math.rad(C.GUARD_VISION_FOV_DEGREES / 2)), hit and hit.Instance:GetFullName() or "nil", tostring((G.stealthFactor(p)))))
			task.wait(1.5)
			print("     sus attr", p:GetAttribute("GuardSuspicion"), "grace", G.graceUntil)
		end
	end
end, 60)
