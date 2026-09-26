-- prompt spacing: E prompts >= 6 apart, V/H >= 4 from any E (per job)
local JOBS = RR_JOBS or { "mart", "jewelry" }
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local total = 0
	for _, id in ipairs(JOBS) do
		JS:selectJob(id)
		task.wait(0.6)
		local cfg, refs = JS:getCurrent()
		local list = {}
		for _, pr in ipairs(WORKSPACE:GetDescendants()) do
			if pr:IsA("ProximityPrompt") and (pr:IsDescendantOf(refs.root) or (pr.Parent and pr.Parent.Name == "LootPrompt")) then
				local par = pr.Parent
				local pos = par:IsA("Attachment") and par.WorldPosition or (par:IsA("BasePart") and par.Position)
				if pos and pr:IsDescendantOf(refs.root) then
					local key = pr.KeyboardKeyCode
					local k = (key == nil or key == Enum.KeyCode.E) and "E" or tostring(key):gsub("Enum.KeyCode.", "")
					local role = pr:GetAttribute("RoleOnly")
					if not role then
						table.insert(list, { pr = pr, pos = pos, key = k, par = par, label = pr.ActionText .. " / " .. pr.ObjectText, en = pr.Enabled })
					end
				end
			end
		end
		print(string.format("== %s: %d prompts", id, #list))
		for _, a in ipairs(list) do print(string.format("   [%s]%s %-40s @ %.1f, %.1f, %.1f", a.key, a.en and "" or "(off)", a.label:sub(1, 40), a.pos.X, a.pos.Y, a.pos.Z)) end
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if a.par ~= b.par then
					local d = (a.pos - b.pos).Magnitude
					local need = (a.key == "E" and b.key == "E") and 6 or ((a.key == "E" or b.key == "E") and 4 or 0)
					-- two vault piles of the same safe open together: report separately
					if d < need then
						local isDrill = function(x) return x.pr.Name == "Drill" end
						local vaultPair = ((not a.en) and (not b.en)) or ((not a.en) and isDrill(b)) or ((not b.en) and isDrill(a))
						local showroom = id == "jewelry" and a.pos.Z < 16 and b.pos.Z < 16
						print(string.format("  %s %s: [%s] %s  <->  [%s] %s  d=%.2f (need %d)", vaultPair and "NOTE(vault/drill seq)" or (showroom and "INFO(showroom)" or "CLOSE"), id, a.key, a.label, b.key, b.label, d, need))
						if not vaultPair and not showroom then total += 1 end
					end
				end
			end
		end
	end
	print("SPACING issues: " .. total)
end, 60)
