runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	for _, d in ipairs(WORKSPACE:GetDescendants()) do
		if d.Name == "BusSignPole" or d.Name == "ShelterPost" then print(d.Name, tostring(d.Position), tostring(d.Size), tostring(d.CFrame.LookVector), d.CanCollide) end
	end
	for _, x in ipairs(WORKSPACE:GetPartBoundsInBox(CFrame.new(-42.4, 1.6, -2), Vector3.new(4.7, 1.1, 2))) do print("inbox", x:GetFullName()) end
end, 20)
report()
