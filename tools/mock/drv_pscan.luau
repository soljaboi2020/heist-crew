runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(3)
	local CS = game_CollectionService or CollectionService
	for _, v in ipairs(CS:GetTagged("Vent")) do
		local p = v:FindFirstChild("VentPrompt", true)
		local par = p and p.Parent
		local pos = par and (par:IsA("Attachment") and par.WorldPosition or par.Position)
		print(string.format("VENT %-28s on=%s dist=%.1f y=%.1f act=%s obj=%s key=%s", v.Name, par and par.ClassName or "?", pos and (pos - v.Position).Magnitude or -1, pos and pos.Y or -1, p and p.ActionText, p and p.ObjectText, p and tostring(p.KeyboardKeyCode)))
	end
	for _, h in ipairs(CS:GetTagged("HideSpot")) do
		local p = h:FindFirstChild("HidePrompt")
		print(string.format("HIDE %-28s size=%s reach=%.1f", h.Name, tostring(h.Size), p and p.MaxActivationDistance or -1))
	end
end, 200)
report()
