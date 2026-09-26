-- ═══════════════ v2.2 PingService + PingWheel + MobileActionButton driver ═══════════════
local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function waitFor(cond, timeout) local t0 = SCHED.now while SCHED.now - t0 < (timeout or 10) do local ok, r = pcall(cond) if ok and r then return r end task.wait(0.1) end return nil end
local function inClient(fn) local res local co = newThread(function() res = table.pack(pcall(fn)) end, CLIENT_CTX) resumeThread(co) waitFor(function() return res ~= nil end, 30) if res and not res[1] then print("  client fn error: " .. tostring(res[2])) end return res and res[2] end
local function cmod(name) return inClient(function() return mockRequire(CLIENT_SCRIPT_TEMPLATE:FindFirstChild(name)) end) end
local CS = CollectionService

-- spy on ProximityPrompt:InputHoldBegin / InputHoldEnd
local HOLD = { began = 0, ended = 0, last = nil }
METHODS.ProximityPrompt = METHODS.ProximityPrompt or {}
METHODS.ProximityPrompt.InputHoldBegin = function(self) HOLD.began += 1 HOLD.last = self end
METHODS.ProximityPrompt.InputHoldEnd = function(self) HOLD.ended += 1 end

local function part(name, pos, size, parent, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size or Vector3.new(4, 4, 4)
	p.CFrame = CFrame.new(pos)
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = parent or WORKSPACE
	return p
end

runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local JS = mockRequire(SERVER_SCRIPT.JobService)
	local PS = mockRequire(SERVER_SCRIPT.PingService)
	PS:init({ jobService = JS })
	check(REPLICATED.Remotes:FindFirstChild("Ping") ~= nil and REPLICATED.Remotes:FindFirstChild("QuickChat") ~= nil, "remotes Ping + QuickChat created")

	local p1 = addPlayer("Malachi")
	startClient(p1)
	task.wait(3)
	local PW = cmod("PingWheel")
	local MAB = cmod("MobileActionButton")
	inClient(function() PW:start() end)
	task.wait(1)
	check(p1.PlayerGui:FindFirstChild("PingWheel") ~= nil, "PingWheel ScreenGui mounted")

	-- ── test range high in the sky ──
	local range = Instance.new("Folder") range.Name = "PingRange" range.Parent = WORKSPACE
	local Y = 600
	part("Floor", Vector3.new(0, Y - 0.5, 0), Vector3.new(400, 1, 400), range)
	local wall = part("PlainWall", Vector3.new(0, Y + 4, -30), Vector3.new(20, 8, 1), range)
	-- guard model
	local guard = Instance.new("Model") guard.Name = "TestGuard"
	local ghrp = part("HumanoidRootPart", Vector3.new(30, Y + 3, 0), Vector3.new(2, 2, 1), guard)
	local ghead = part("Head", Vector3.new(30, Y + 4.5, 0), Vector3.new(1, 1, 1), guard)
	Instance.new("Humanoid").Parent = guard
	guard.PrimaryPart = ghrp
	guard.Parent = range
	CS:AddTag(guard, "Guard")
	-- camera model
	local camM = Instance.new("Model") camM.Name = "TestCam"
	local camPart = part("Lens", Vector3.new(-30, Y + 8, 0), Vector3.new(1, 1, 2), camM)
	camM.Parent = range
	CS:AddTag(camM, "SecurityCamera")
	-- loot: invisible CanQuery=false anchor with BagLoot prompt, next to a visual
	local lootVis = part("GoldBars", Vector3.new(0, Y + 1, 30), Vector3.new(3, 2, 3), range)
	local anchor = part("LootPrompt", Vector3.new(0, Y + 2.5, 29), Vector3.new(1, 1, 1), range, { Transparency = 1, CanCollide = false, CanQuery = false })
	local lp = Instance.new("ProximityPrompt") lp.Name = "BagLoot" lp.ActionText = "Bag it" lp.HoldDuration = 1 lp.Parent = anchor
	-- keycard door, vent, far wall
	local door = part("KeycardDoor", Vector3.new(30, Y + 5, -30), Vector3.new(8, 10, 1), range)
	local vent = part("VentPanel", Vector3.new(-30, Y + 1, -30), Vector3.new(3, 3, 1), range)
	CS:AddTag(vent, "Vent")
	local far = part("FarWall", Vector3.new(-220, Y + 5, 0), Vector3.new(40, 10, 1), range)
	task.wait(0.5)

	local here = Vector3.new(0, Y + 3, 0)
	p1.Character:PivotTo(CFrame.new(here))
	task.wait(0.3)
	local cam = WORKSPACE.CurrentCamera
	local function aimAt(pos)
		local eye = here + Vector3.new(0, 1.5, 0)
		cam.CFrame = CFrame.lookAt(eye, pos)
		D[cam].props.CFrame = CFrame.lookAt(eye, pos)
	end
	local function clientPing(pos)
		return inClient(function()
			PW._lastPing = -99
			aimAt(pos)
			return PW:ping()
		end)
	end
	local function lastRec() return PW._pings[#PW._pings] end
	local function clear() inClient(function() for i = #PW._pings, 1, -1 do PW:_removePing(PW._pings[i]) end end) end

	-- ── 1. plain ping round-trip ──
	check(clientPing(wall.Position) == true, "client sends a ping (T)")
	task.wait(0.3)
	check(PW:activeCount() == 1, "ping came back to the sender (" .. PW:activeCount() .. ")")
	local r = lastRec()
	check(r and r.kind == "look" and r.label == "LOOK", "plain wall → LOOK (" .. tostring(r and r.kind) .. ")")
	check(r and r.bb and r.bb.Parent == p1.PlayerGui and r.bb.AlwaysOnTop == true, "billboard marker in PlayerGui, AlwaysOnTop")
	check(r and r.anchor and r.anchor.Parent and (r.anchor.Position - Vector3.new(0, Y + 4, -29.5)).Magnitude < 1.5, "marker anchored at the hit point (" .. tostring(r and r.anchor and r.anchor.Position) .. ")")
	check(r and r.byName == "Malachi", "marker names the pinger")
	check(GAME:GetService("SoundService"):FindFirstChild("HC_PingSound") ~= nil, "ping sound exists")

	-- ── 2. rate limits ──
	local before = PW:activeCount()
	check(inClient(function() aimAt(wall.Position) return PW:ping() end) == false, "client-side cooldown blocks an instant second ping")
	clientPing(wall.Position)   -- bypass client limit: server should drop it
	task.wait(0.3)
	check(PW:activeCount() == before, "server drops a ping inside 0.7 s (" .. PW:activeCount() .. ")")
	task.wait(0.8)
	local pl, why = PS:ping(p1, here, (wall.Position - here).Unit)
	local pl2, why2 = PS:ping(p1, here, (wall.Position - here).Unit)
	check(pl ~= nil and pl2 == nil and why2 == "cooldown", "PS:ping rate limit (" .. tostring(why) .. "/" .. tostring(why2) .. ")")
	check(PS:ping(p1, Vector3.new(0 / 0, 0, 0), Vector3.new(0, 0, -1)) == nil, "NaN origin rejected")
	check(PS:ping(p1, here, Vector3.zero) == nil, "zero dir rejected")
	check(PS:ping(p1, "x", 5) == nil, "junk args rejected")

	-- ── 3. max distance ──
	task.wait(0.8)
	local fp, fwhy = PS:ping(p1, here, (far.Position - here).Unit)
	check(fp == nil and (fwhy == "too far" or fwhy == "nothing there"), "220 studs away → rejected (" .. tostring(fwhy) .. ")")
	-- silly camera origin gets clamped to the head
	task.wait(0.8)
	local cp = PS:ping(p1, here + Vector3.new(0, 0, 500), (wall.Position - here).Unit)
	check(cp ~= nil, "far-away origin clamped to the head, still pings")

	-- ── 4. kinds ──
	task.wait(0.8) clear()
	clientPing(ghead.Position) task.wait(0.3)
	r = lastRec()
	check(r and r.kind == "guard" and r.label == "GUARD", "guard → GUARD (" .. tostring(r and r.kind) .. ")")
	check(r and r.follow ~= nil and r.bb.Adornee == ghead, "guard marker follows his head")
	check(guard:FindFirstChild("HC_Ping") and guard.HC_Ping:IsA("Highlight"), "guard highlighted for the crew")
	task.wait(3.2)
	check(guard:FindFirstChild("HC_Ping") == nil, "guard highlight gone after ~3 s")

	task.wait(0.2)
	clientPing(ghrp.Position + Vector3.new(0, 0, 1.6)) task.wait(0.3)   -- aim slightly beside him
	r = lastRec()
	check(r and r.kind == "guard", "aim-help: a near-miss on a guard still counts (" .. tostring(r and r.kind) .. ")")

	task.wait(0.5)
	clientPing(camPart.Position) task.wait(0.3)
	r = lastRec()
	check(r and r.kind == "camera" and r.label == "CAMERA", "camera → CAMERA (" .. tostring(r and r.kind) .. ")")

	task.wait(0.5)
	clientPing(lootVis.Position) task.wait(0.3)
	r = lastRec()
	check(r and r.kind == "loot" and r.label == "LOOT", "loot visual near a BagLoot anchor → LOOT (" .. tostring(r and r.kind) .. ")")

	task.wait(0.5)
	clientPing(door.Position) task.wait(0.3)
	r = lastRec()
	check(r and r.kind == "door" and r.label == "KEYCARD", "keycard door → KEYCARD (" .. tostring(r and r.label) .. ")")

	task.wait(0.5)
	clientPing(vent.Position) task.wait(0.3)
	r = lastRec()
	check(r and r.kind == "vent", "vent → VENT (" .. tostring(r and r.kind) .. ")")

	-- Lookout guard pings last longer
	task.wait(0.8) clear()
	p1:SetAttribute("Role", "Lookout")
	local lk = PS:ping(p1, here, (ghead.Position - here - Vector3.new(0, 1.5, 0)).Unit)
	check(lk and lk.life == PS.LOOKOUT_LIFE, "Lookout guard ping lasts " .. tostring(lk and lk.life) .. " s")
	p1:SetAttribute("Role", nil)

	-- ── 5. max 3 per player + lifetime ──
	task.wait(0.8) clear()
	for i = 1, 5 do
		clientPing(wall.Position + Vector3.new(i * 2 - 6, 0, 0))
		task.wait(0.8)
	end
	check(PW:activeCount(p1.UserId) == 3, "max 3 markers per player (" .. PW:activeCount(p1.UserId) .. ")")
	local bbs = 0
	for _, x in ipairs(p1.PlayerGui:GetChildren()) do if x.Name:sub(1, 8) == "HC_Ping_" then bbs += 1 end end
	check(bbs == 3, "exactly 3 billboards alive (" .. bbs .. ")")
	task.wait(4.6)
	local rr = PW._pings[#PW._pings]
	check(rr and rr.cg and rr.cg.GroupTransparency > 0.05, "marker fading near the end (" .. tostring(rr and rr.cg and rr.cg.GroupTransparency) .. ")")
	task.wait(1.5)
	check(PW:activeCount() == 0, "all markers gone after 6 s (" .. PW:activeCount() .. ")")
	bbs = 0
	for _, x in ipairs(p1.PlayerGui:GetChildren()) do if x.Name:sub(1, 8) == "HC_Ping_" then bbs += 1 end end
	local anchors = WORKSPACE:FindFirstChild("HC_Pings")
	check(bbs == 0 and (not anchors or #anchors:GetChildren() == 0), "billboards + anchors cleaned up")

	-- off-screen arrow
	clientPing(wall.Position) task.wait(0.3)
	inClient(function() cam.CFrame = CFrame.lookAt(here, here + Vector3.new(0, 0, 10)) D[cam].props.CFrame = CFrame.lookAt(here, here + Vector3.new(0, 0, 10)) end)   -- turn around
	task.wait(0.3)
	r = lastRec()
	check(r and r.edge and r.edge.Visible == true, "behind you → edge arrow shows")
	inClient(function() aimAt(wall.Position) end)
	task.wait(0.3)
	check(r and r.edge and r.edge.Visible == false, "on screen → edge arrow hides")

	-- ── 6. keys: tap T = ping, middle mouse = ping ──
	task.wait(0.8) clear()
	inClient(function() PW._lastPing = -99 aimAt(wall.Position) end)
	pressKey(Enum.KeyCode.T)
	task.wait(0.4)
	check(PW:activeCount() == 1, "tap T pings (" .. PW:activeCount() .. ")")
	check(PW._open ~= true, "tap T does NOT open the wheel")
	task.wait(0.8)
	inClient(function() PW._lastPing = -99 end)
	UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.Unknown, UserInputType = Enum.UserInputType.MouseButton3, Position = Vector3.zero, Delta = Vector3.zero }, false)
	task.wait(0.4)
	check(PW:activeCount() == 2, "middle mouse pings (" .. PW:activeCount() .. ")")
	task.wait(0.8)
	inClient(function() PW._lastPing = -99 end)
	UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.DPadUp, UserInputType = Enum.UserInputType.Gamepad1, Position = Vector3.zero, Delta = Vector3.zero }, false)
	task.wait(0.4)
	check(PW:activeCount() == 3, "gamepad D-pad up pings (" .. PW:activeCount() .. ")")
	-- typing in chat (processed) must not ping
	task.wait(0.8)
	inClient(function() PW._lastPing = -99 end)
	pressKey(Enum.KeyCode.T, true)
	task.wait(0.4)
	check(PW:activeCount() == 3, "T while typing does nothing")

	-- ── 7. quick-chat wheel ──
	local chatSeen = {}
	REPLICATED.Remotes.QuickChat.OnServerEvent:Connect(function(_, i) table.insert(chatSeen, i) end)
	-- hold T → wheel, select, release → send
	local tIn = { KeyCode = Enum.KeyCode.T, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.Begin, Position = Vector3.zero, Delta = Vector3.zero }
	UserInputService.InputBegan:Fire(tIn, false)
	task.wait(0.35)
	check(PW._open == true and PW._wheel.Visible == true and PW._mode == "hold", "hold T opens the wheel")
	inClient(function() PW:_select(3) end)
	UserInputService.InputEnded:Fire(tIn, false)
	task.wait(0.4)
	check(chatSeen[#chatSeen] == 3 and PW._open == false, "release T sends the highlighted line (" .. tostring(chatSeen[#chatSeen]) .. ")")
	local bub = p1.PlayerGui:FindFirstChild("HC_ChatBubble_" .. p1.UserId)
	check(bub and bub.Adornee == p1.Character.Head and bub.AlwaysOnTop == false, "speech bubble over the speaker's head")
	local txt
	for _, x in ipairs(bub and bub:GetDescendants() or {}) do if x.Name == "Text" then txt = x.Text end end
	check(txt == "Go go go!", "bubble says the line (" .. tostring(txt) .. ")")
	check(PW:activeCount() == 3, "holding T did not also ping")
	task.wait(3.2)
	check(p1.PlayerGui:FindFirstChild("HC_ChatBubble_" .. p1.UserId) == nil, "bubble gone after 3 s")
	-- release with nothing highlighted = cancel
	UserInputService.InputBegan:Fire(tIn, false)
	task.wait(0.35)
	local n0 = #chatSeen
	UserInputService.InputEnded:Fire(tIn, false)
	task.wait(0.3)
	check(#chatSeen == n0 and PW._open == false, "release with nothing picked = cancel")
	-- slice geometry
	check(PW._sliceFor(Vector2.new(0, -50), 30) == 1 and PW._sliceFor(Vector2.new(50, -20), 30) == 2
		and PW._sliceFor(Vector2.new(0, 50), 30) == 4 and PW._sliceFor(Vector2.new(-50, -20), 30) == 6
		and PW._sliceFor(Vector2.new(5, 5), 30) == nil, "direction → slice mapping")
	-- touch: open, tap slice
	task.wait(1.6)
	inClient(function() PW:openWheel("touch") end)
	check(PW._shade.Visible == true, "touch wheel shows a tap-outside shade")
	inClient(function() local s = D[PW._slices[6].button].sigs.Activated if s then s:Fire() end end)
	task.wait(0.4)
	check(chatSeen[#chatSeen] == 6 and PW._open == false, "tapping a slice sends it (" .. tostring(chatSeen[#chatSeen]) .. ")")
	-- touch: centre = ping
	task.wait(0.8) clear()
	inClient(function() PW._lastPing = -99 aimAt(wall.Position) PW:openWheel("touch") local s = D[PW._wheel.Centre].sigs.Activated if s then s:Fire() end end)
	task.wait(0.4)
	check(PW:activeCount() == 1 and PW._open == false, "wheel centre 📍 pings (" .. PW:activeCount() .. ")")
	-- number key while open
	task.wait(1.6)
	inClient(function() PW:openWheel("pad") end)
	pressKey(Enum.KeyCode.Two)
	task.wait(0.4)
	check(chatSeen[#chatSeen] == 2, "number key 2 while open sends line 2")
	-- server chat limits
	task.wait(1.6)
	local c1 = PS:say(p1, 1)
	local c2, cw = PS:say(p1, 1)
	check(c1 ~= nil and c2 == nil and cw == "cooldown", "quick-chat rate limit (" .. tostring(cw) .. ")")
	task.wait(1.6)
	check(PS:say(p1, 7) == nil and PS:say(p1, 0) == nil and PS:say(p1, 1.5) == nil and PS:say(p1, "1") == nil, "bad chat index rejected")
	-- toast for someone else's line
	local p2 = addPlayer("Buddy")
	task.wait(0.5)
	local shown
	inClient(function()
		local N = mockRequire(CLIENT_SCRIPT_TEMPLATE.Notifications)
		local orig = N.show
		N.show = function(self, text, ...) shown = text return orig(self, text, ...) end
		PW:_onChat({ by = p2, index = 5 })
		N.show = orig
	end)
	check(shown and shown:find("Buddy") and shown:find("Need help!"), "crew toast for a teammate's line (" .. tostring(shown) .. ")")
	check(p1.PlayerGui:FindFirstChild("HC_ChatBubble_" .. p2.UserId) ~= nil, "bubble over the teammate's head")

	-- ── 8. crew audience ──
	local aud = PS._audience(p1)
	check(#aud == 2, "no job running → everyone hears (" .. #aud .. ")")

	-- ── 9. mobile action button ──
	inClient(function() MAB._forceTouch = true MAB:start() end)
	task.wait(0.5)
	local gui = p1.PlayerGui:FindFirstChild("MobileActionButton")
	check(gui ~= nil and gui.ActionButton.Visible == false, "action button built, hidden with no prompt")
	local sz = gui and gui.ActionButton.Size.X.Offset or 0
	check(sz >= 96, "button is >= 96 px (" .. sz .. ")")
	p1.Character:PivotTo(CFrame.new(Vector3.new(0, Y + 3, 26)))
	inClient(function() ProximityPromptService.PromptShown:Fire(lp, Enum.ProximityPromptInputType.Touch) end)
	task.wait(0.3)
	check(MAB:current() == lp and gui.ActionButton.Visible == true, "tracks the shown prompt")
	local lab, ico
	for _, x in ipairs(gui:GetDescendants()) do if x.Name == "Action" then lab = x.Text end if x.Name == "Icon" and x.Parent.Name == "Face" then ico = x.Text end end
	check(lab == "BAG IT" and ico == "✋", "label = ActionText, grab icon (" .. tostring(lab) .. " " .. tostring(ico) .. ")")
	-- a second, nearer prompt wins
	local hideP = part("HideSpot", Vector3.new(0, Y + 3, 27), Vector3.new(2, 2, 2), range)
	local hp = Instance.new("ProximityPrompt") hp.Name = "HidePrompt" hp.ActionText = "Hide" hp.HoldDuration = 0 hp.Parent = hideP
	inClient(function() ProximityPromptService.PromptShown:Fire(hp, Enum.ProximityPromptInputType.Touch) end)
	task.wait(0.3)
	check(MAB:current() == hp, "nearest shown prompt wins")
	for _, x in ipairs(gui:GetDescendants()) do if x.Name == "Action" then lab = x.Text end if x.Name == "Icon" and x.Parent.Name == "Face" then ico = x.Text end end
	check(lab == "HIDE" and ico == "🙈", "hide icon (" .. tostring(lab) .. " " .. tostring(ico) .. ")")
	inClient(function() ProximityPromptService.PromptHidden:Fire(hp) end)
	task.wait(0.3)
	check(MAB:current() == lp, "back to the loot prompt when hide hides")
	-- press / hold / release
	local b0, e0 = HOLD.began, HOLD.ended
	inClient(function() D[gui.ActionButton].sigs.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }) end)
	task.wait(0.5)
	check(HOLD.began == b0 + 1 and HOLD.last == lp, "press → prompt:InputHoldBegin()")
	local ringR = MAB._halves[1].grad.Rotation
	check(ringR > 45 and ringR < 180, "hold ring filling over HoldDuration (" .. ringR .. "°)")
	inClient(function() D[gui.ActionButton].sigs.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch, KeyCode = Enum.KeyCode.Unknown, Position = Vector3.zero }) end)
	task.wait(0.2)
	check(HOLD.ended == e0 + 1 and MAB._holding == nil, "release → prompt:InputHoldEnd()")
	-- hidden mid-hold releases
	inClient(function() MAB:press() ProximityPromptService.PromptHidden:Fire(lp) end)
	task.wait(0.3)
	check(HOLD.ended == e0 + 2 and gui.ActionButton.Visible == false and MAB:current() == nil, "prompt hidden mid-hold → released + button hides")
	-- disabled prompt drops out
	inClient(function() ProximityPromptService.PromptShown:Fire(lp, Enum.ProximityPromptInputType.Touch) end)
	task.wait(0.2)
	lp.Enabled = false
	task.wait(0.3)
	check(MAB:current() == nil and gui.ActionButton.Visible == false, "disabled prompt → button hides")
	-- icon table
	local function ic(t, n) local x = Instance.new("ProximityPrompt") x.ActionText = t x.Name = n or "P" return MAB._iconFor(x) end
	check(ic("Place drill") == "🔧" and ic("Crawl through") == "🕳" and ic("Smash & grab") == "💎" and ic("Get in (driver)") == "🚗"
		and ic("Load bag") == "📦" and ic("Takedown") == "💪" and ic("Break out") == "🔓" and ic("Hack", "Hack") == "💻" and ic("Zzz") == "👉",
		"icons by type")
	-- PC (not forced) never builds it
	local built
	inClient(function()
		local fresh = {}
		for k, v in pairs(MAB) do fresh[k] = v end
		fresh._forceTouch = false
		p1.PlayerGui.MobileActionButton.Name = "MAB_old"
		MAB.start(fresh)
		built = p1.PlayerGui:FindFirstChild("MobileActionButton") ~= nil
	end)
	check(built == false, "keyboard PC: no action button")

	-- ── 10. crew audience during a run (JobService stubbed: phase running, only p1 in the run) ──
	local oPhase, oIn = JS.getPhase, JS.isInRun
	JS.getPhase = function() return "running" end
	JS.isInRun = function(_, p) return p == p1 and p1:GetAttribute("Jailed") ~= true end
	local a1, a2 = PS._audience(p1), PS._audience(p2)
	check(#a1 == 1 and a1[1] == p1 and #a2 == 1 and a2[1] == p2, "in a run: crew hears the crew, lobby hears the lobby (" .. #a1 .. "/" .. #a2 .. ")")
	p1:SetAttribute("Jailed", true)
	local a3 = PS._audience(p1)
	check(#a3 == 1 and a3[1] == p1, "a jailed teammate stays on the crew channel")
	p1:SetAttribute("Jailed", nil)
	JS.getPhase, JS.isInRun = oPhase, oIn

	report()
	print("\n==== SUMMARY ====")
	local pass, fail = 0, 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "PASS" then pass += 1 else fail += 1 print(c) end end
	print(pass .. "/" .. (pass + fail) .. " passed")
end, 400)
