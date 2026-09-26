runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(64, 4, -3.5), Vector3.new(16, 6, 5))) do
		if x.CanCollide then print(string.format("%s  pos (%.2f, %.2f, %.2f) size (%.2f, %.2f, %.2f)", x:GetFullName(), x.Position.X, x.Position.Y, x.Position.Z, x.Size.X, x.Size.Y, x.Size.Z)) end
	end
end, 30)
