runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	for _, id in ipairs({"villa","bank"}) do
	JS:selectJob(id) task.wait(0.3)
	local cfg, r = JS:getCurrent()
	local d = r.vault.door
	print(id, "vault door", d:GetFullName(), d.Position, d.Size, d.CFrame.LookVector, "parts", r.vault.parts and #r.vault.parts)
	local m = d:FindFirstAncestorWhichIsA("Model") print(" door model", m and m:GetFullName(), m and #m:GetChildren())
	local b = r.breaker print(" breaker", b:GetFullName(), b.Position, b.Size, b.CanCollide)
	local bm = b:FindFirstAncestorWhichIsA("Model") print(" breaker model", bm and bm:GetFullName())
	local k = r.keycardDoors[1].door print(" kc", k:GetFullName(), k.Position, k.Size)
	for _, p in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(d.Position + d.CFrame.LookVector*4), Vector3.new(8,8,8))) do
		if p.Transparency < 0.9 then print("   near door:", p:GetFullName(), p.Position, p.Size, p.CanCollide, p.Transparency) end
	end
	end
end, 30)
report()
