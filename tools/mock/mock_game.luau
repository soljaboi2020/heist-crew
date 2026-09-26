NIL_MEMBERS = { ["GuiService.SelectedObject"] = true, ["GuiService.SelectedCoreObject"] = true }
-- ═══════════════ Services + DataModel + require shim ═══════════════
local function apiService(name, members)
	local mt = {}
	TYPEOF[mt] = "Instance"
	mt.__index = function(t, k)
		if k == "Name" or k == "ClassName" then return name end
		if k == "IsA" then return function(_, c) return c == name or c == "Instance" end end
		if k == "GetAttribute" then return function() return nil end end
		if k == "FindFirstChild" then return function() return nil end end
		if NIL_MEMBERS[name .. "." .. tostring(k)] then return nil end
		local loc = callerLoc(2)
		logOnce("unknown", "S:" .. name .. "." .. tostring(k) .. loc, string.format("service %s.%s read @ %s", name, tostring(k), loc))
		error(tostring(k) .. " is not a valid member of " .. name, 2)
	end
	mt.__tostring = function() return name end
	return setmetatable(members, mt)
end

GAME = newInstance("DataModel")
GAME.Name = "Game"
WORKSPACE = newInstance("Workspace", GAME)
WORKSPACE.Name = "Workspace"
local cam = newInstance("Camera", WORKSPACE)
cam.Name = "Camera"
D[WORKSPACE].props.CurrentCamera = cam
local terrain = newInstance("Terrain", WORKSPACE)
terrain.Name = "Terrain"
D[terrain].props.Anchored = true
D[terrain].props.Size = Vector3.new(0, 0, 0)
local function svc(class, name)
	local s = newInstance(class, GAME)
	s.Name = name or class
	return s
end
PLAYERS = svc("Players")
LIGHTING = svc("Lighting")
REPLICATED = svc("ReplicatedStorage")
SSS = svc("ServerScriptService")
local serverStorage = svc("ServerStorage")
STARTER_PLAYER = svc("StarterPlayer")
local sps = newInstance("StarterPlayerScripts", STARTER_PLAYER)
sps.Name = "StarterPlayerScripts"
local scs = newInstance("StarterCharacterScripts", STARTER_PLAYER)
scs.Name = "StarterCharacterScripts"
STARTER_GUI = svc("StarterGui")
local soundService = svc("SoundService")
local teams = svc("Teams")
local starterPack = svc("StarterPack")
local httpInst = svc("HttpService")
local replicatedFirst = svc("Folder", "ReplicatedFirst")
local chat = svc("Chat")
local tcs = svc("TextChatService")
DEFAULTS.HttpService = { HttpEnabled = true }
METHODS.HttpService = {
	GenerateGUID = function(_, braces) return (braces == false and "" or "{") .. string.format("%08x-0000-4000-8000-%012x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff)) .. (braces == false and "" or "}") end,
	JSONEncode = function(_, v) return JSON_ENCODE(v) end,
	JSONDecode = function(_, s) return JSON_DECODE(s) end,
	UrlEncode = function(_, s) return s end,
	GetAsync = function() error("HTTP disabled in mock", 2) end,
	PostAsync = function() error("HTTP disabled in mock", 2) end,
	RequestAsync = function() error("HTTP disabled in mock", 2) end,
}
function JSON_ENCODE(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" or t == "number" then return tostring(v) end
	if t == "string" then return '"' .. v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"' end
	if t == "table" then
		if #v > 0 then local o = {} for _, x in ipairs(v) do table.insert(o, JSON_ENCODE(x)) end return "[" .. table.concat(o, ",") .. "]" end
		local o = {} for k, x in pairs(v) do table.insert(o, JSON_ENCODE(tostring(k)) .. ":" .. JSON_ENCODE(x)) end return "{" .. table.concat(o, ",") .. "}"
	end
	error("JSONEncode: cannot encode " .. mtypeof(v))
end
function JSON_DECODE(s) error("JSONDecode not implemented in mock") end

-- RunService
local heartbeat, stepped, renderStepped = Signal.new("Heartbeat"), Signal.new("Stepped"), Signal.new("RenderStepped")
local renderBinds = {}
RunService = apiService("RunService", {
	Heartbeat = heartbeat, Stepped = stepped, RenderStepped = renderStepped,
	PostSimulation = heartbeat, PreSimulation = stepped, PreRender = renderStepped, PreAnimation = stepped,
	IsServer = function() return curCtx().mode == "server" end,
	IsClient = function() return curCtx().mode == "client" end,
	IsStudio = function() return true end,
	IsRunning = function() return true end,
	IsRunMode = function() return false end,
	IsEdit = function() return false end,
	BindToRenderStep = function(_, name, prio, fn)
		if curCtx().mode ~= "client" then error("BindToRenderStep can only be called from the client", 2) end
		if type(name) ~= "string" or type(prio) ~= "number" or type(fn) ~= "function" then error("BindToRenderStep(name, priority:number, fn) bad args: " .. mtypeof(name) .. "," .. mtypeof(prio) .. "," .. mtypeof(fn), 2) end
		renderBinds[name] = { fn = fn, ctx = curCtx() }
	end,
	UnbindFromRenderStep = function(_, name) renderBinds[name] = nil end,
})
FRAME_COUNT = 0
local function frame()
	FRAME_COUNT += 1
	local dt = SCHED.frame
	D[WORKSPACE].props.DistributedGameTime = SCHED.now
	stepped:Fire(SCHED.now, dt)
	heartbeat:Fire(dt)
	if CLIENT then
		for _, b in pairs(renderBinds) do resumeThread(newThread(b.fn, b.ctx), dt) end
		renderStepped:Fire(dt)
	end
	SCHED.at(SCHED.now + dt, frame)
end
SCHED.at(0, frame)

-- TweenService
local EASE = { Linear = true }
TweenService = apiService("TweenService", {
	Create = function(_, inst, info, goal)
		if mtypeof(inst) ~= "Instance" then error("TweenService:Create: Instance expected as arg 1, got " .. mtypeof(inst), 2) end
		if mtypeof(info) ~= "TweenInfo" then error("TweenService:Create: TweenInfo expected as arg 2, got " .. mtypeof(info), 2) end
		if type(goal) ~= "table" then error("TweenService:Create: table expected as arg 3", 2) end
		for k, v in pairs(goal) do
			local ok, cur = pcall(function() return inst[k] end)
			if not ok then error("TweenService:Create no property named '" .. tostring(k) .. "' for object '" .. inst.Name .. "' (" .. D[inst].class .. ")", 2) end
			local tc, tv = mtypeof(cur), mtypeof(v)
			if cur ~= nil and tc ~= tv and not (tc == "number" and tv == "number") then
				error("TweenService:Create property named '" .. k .. "' on object '" .. inst.Name .. "' is not a data type that can be tweened (have " .. tc .. ", goal " .. tv .. ")", 2)
			end
			if tv ~= "number" and tv ~= "Vector3" and tv ~= "CFrame" and tv ~= "Color3" and tv ~= "UDim2" and tv ~= "UDim" and tv ~= "Vector2" and tv ~= "boolean" and tv ~= "NumberRange" and tv ~= "Rect" and tv ~= "EnumItem" then
				error("TweenService:Create property '" .. k .. "' type " .. tv .. " cannot be tweened", 2)
			end
		end
		local tw = newInstance("Tween")
		D[tw].props._inst = inst; D[tw].props._goal = goal; D[tw].props._info = info
		D[tw].props.Instance = inst; D[tw].props.TweenInfo = info
		return tw
	end,
	GetValue = function(_, a) return a end,
	SmoothDamp = function(_, cur, target) return target, 0 end,
})
Debris = apiService("Debris", {
	AddItem = function(_, inst, t)
		if mtypeof(inst) ~= "Instance" then error("Debris:AddItem: Instance expected", 2) end
		task.delay(t or 10, function() if not D[inst].destroyed then inst:Destroy() end end)
	end,
	MaxItems = 1000,
})
ProximityPromptService = apiService("ProximityPromptService", {
	PromptTriggered = Signal.new("PromptTriggered"), PromptShown = Signal.new("PromptShown"), PromptHidden = Signal.new("PromptHidden"),
	PromptButtonHoldBegan = Signal.new("PromptButtonHoldBegan"), PromptButtonHoldEnded = Signal.new("PromptButtonHoldEnded"),
	PromptTriggerEnded = Signal.new("PromptTriggerEnded"), Enabled = true, MaxPromptsVisible = 16,
})
local PathMT = {}
TYPEOF[PathMT] = "Instance"
PathMT.__index = function(p, k)
	if k == "ComputeAsync" then return function(self, a, b)
		if not isV3(a) or not isV3(b) then error("ComputeAsync: Vector3 expected, got " .. mtypeof(a) .. "," .. mtypeof(b), 2) end
		task.wait()
		rawset(self, "_a", a) rawset(self, "_b", b) rawset(self, "Status", Enum.PathStatus.Success)
	end end
	if k == "GetWaypoints" then return function(self)
		local a, b = rawget(self, "_a"), rawget(self, "_b")
		if not a then return {} end
		local mid = a:Lerp(b, 0.5)
		return { { Position = a, Action = Enum.PathWaypointAction.Walk, Label = "" }, { Position = mid, Action = Enum.PathWaypointAction.Walk, Label = "" }, { Position = b, Action = Enum.PathWaypointAction.Walk, Label = "" } }
	end end
	if k == "CheckOcclusionAsync" then return function() return -1 end end
	if k == "Blocked" or k == "Unblocked" then local s = Signal.new(k) rawset(p, k, s) return s end
	if k == "Destroy" then return function() end end
	if k == "Status" then return Enum.PathStatus.NoPath end
	error(tostring(k) .. " is not a valid member of Path", 2)
end
PathfindingService = apiService("PathfindingService", {
	CreatePath = function(_, params)
		if params ~= nil and type(params) ~= "table" then error("CreatePath: table expected", 2) end
		return setmetatable({}, PathMT)
	end,
	FindPathAsync = function(self, a, b) local p = setmetatable({}, PathMT) p:ComputeAsync(a, b) return p end,
})
local stores = {}
local function makeStore(name, ordered)
	local data = {}
	local st = {
		GetAsync = function(_, k) if type(k) ~= "string" then error("DataStore key must be a string, got " .. mtypeof(k), 2) end return data[k] end,
		SetAsync = function(_, k, v)
			if type(k) ~= "string" then error("DataStore key must be a string, got " .. mtypeof(k), 2) end
			local ok, e = pcall(JSON_ENCODE, v) if not ok then error("SetAsync: value not storable: " .. tostring(e), 2) end
			data[k] = v
		end,
		UpdateAsync = function(_, k, fn) local nv = fn(data[k]) if nv ~= nil then local ok, e = pcall(JSON_ENCODE, nv) if not ok then error("UpdateAsync: value not storable: " .. tostring(e), 2) end data[k] = nv end return data[k] end,
		RemoveAsync = function(_, k) local v = data[k] data[k] = nil return v end,
		IncrementAsync = function(_, k, n) data[k] = (data[k] or 0) + (n or 1) return data[k] end,
		GetSortedAsync = function(_, asc, pageSize)
			if not ordered then error("GetSortedAsync only on OrderedDataStore", 2) end
			if type(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 then error("GetSortedAsync: pageSize must be 1-100", 2) end
			local rows = {}
			for k, v in pairs(data) do table.insert(rows, { key = k, value = v }) end
			table.sort(rows, function(a, b) if asc then return a.value < b.value end return a.value > b.value end)
			local page = {}
			for i = 1, math.min(pageSize, #rows) do page[i] = rows[i] end
			return { GetCurrentPage = function() return page end, IsFinished = true, AdvanceToNextPageAsync = function() end }
		end,
		_data = data,
	}
	if ordered then
		local set = st.SetAsync
		st.SetAsync = function(s, k, v) if type(v) ~= "number" or v ~= math.floor(v) then error("OrderedDataStore:SetAsync value must be an integer, got " .. tostring(v), 2) end return set(s, k, v) end
	end
	return st
end
DataStoreService = apiService("DataStoreService", {
	GetDataStore = function(_, name, scope) stores[name] = stores[name] or makeStore(name) return stores[name] end,
	GetOrderedDataStore = function(_, name) stores["O:" .. name] = stores["O:" .. name] or makeStore(name, true) return stores["O:" .. name] end,
	GetGlobalDataStore = function() stores._g = stores._g or makeStore("g") return stores._g end,
	GetRequestBudgetForRequestType = function() return 100 end,
})
MarketplaceService = apiService("MarketplaceService", {
	UserOwnsGamePassAsync = function(_, uid, id) if type(uid) ~= "number" or type(id) ~= "number" then error("UserOwnsGamePassAsync(userId, passId) numbers expected", 2) end return false end,
	PlayerOwnsAsset = function() return false end,
	GetProductInfo = function(_, id, t) return { Name = "Pass", PriceInRobux = 99, Description = "", IconImageAssetId = 0, IsForSale = true } end,
	PromptGamePassPurchase = function(_, p, id) if mtypeof(p) ~= "Instance" or type(id) ~= "number" then error("PromptGamePassPurchase(player, id) bad args", 2) end end,
	PromptProductPurchase = function() end, PromptPurchase = function() end,
	PromptGamePassPurchaseFinished = Signal.new("PGPPF"), PromptProductPurchaseFinished = Signal.new("PPPF"), PromptPurchaseFinished = Signal.new("PPF"),
	ProcessReceipt = nil,
})
InsertService = apiService("InsertService", {
	LoadAsset = function(_, id)
		if type(id) ~= "number" then error("LoadAsset: number expected, got " .. mtypeof(id), 2) end
		local c = newInstance("Model")
		c.Name = "Model"
		local m = newInstance("Model", c)
		m.Name = "Asset" .. id
		local mp = newInstance("MeshPart", m)
		mp.Size = Vector3.new(2, 2, 2)
		-- real proportions from KenneyKit.SIZES (reverse lookup of the asset id)
		if not KENNEY_REV then
			KENNEY_REV = {}
			local okA, A = pcall(mockRequire, REPLICATED.Shared.KenneyAssets)
			local okK, K = pcall(mockRequire, REPLICATED.Shared.KenneyKit)
			if okA and okK then
				for kit, list in pairs(A) do
					if type(list) == "table" then
						for name, aid in pairs(list) do
							local sz = K.SIZES and K.SIZES[kit] and K.SIZES[kit][name]
							if sz then KENNEY_REV[aid] = sz end
						end
					end
				end
			end
		end
		if KENNEY_REV[id] then mp.Size = KENNEY_REV[id] return c end
		-- anything else = a catalog accessory (Roblox-made masks): Model > Accessory > Handle
		m:Destroy()
		local acc = newInstance("Accessory", c)
		acc.Name = "CatalogAccessory" .. id
		local h = newInstance("Part", acc)
		h.Name = "Handle" h.Size = Vector3.new(1, 1, 1)
		local att = newInstance("Attachment", h) att.Name = "FaceFrontAttachment"
		LOADED_ASSETS = LOADED_ASSETS or {}
		LOADED_ASSETS[id] = (LOADED_ASSETS[id] or 0) + 1
		return c
	end,
})
PhysicsService = apiService("PhysicsService", {
	RegisterCollisionGroup = function(_, n) if type(n) ~= "string" then error("RegisterCollisionGroup: string expected", 2) end end,
	CollisionGroupSetCollidable = function(_, a, b, c) if type(a) ~= "string" or type(b) ~= "string" or type(c) ~= "boolean" then error("CollisionGroupSetCollidable(string, string, bool) bad args", 2) end end,
	IsCollisionGroupRegistered = function() return true end,
	CreateCollisionGroup = function() return 1 end,
	SetPartCollisionGroup = function() end,
	GetRegisteredCollisionGroups = function() return {} end,
	CollisionGroupsAreCollidable = function() return true end,
})
UserInputService = apiService("UserInputService", {
	InputBegan = Signal.new("InputBegan"), InputEnded = Signal.new("InputEnded"), InputChanged = Signal.new("InputChanged"),
	LastInputTypeChanged = Signal.new("LastInputTypeChanged"), TouchStarted = Signal.new("TouchStarted"), TouchEnded = Signal.new("TouchEnded"),
	TouchTap = Signal.new("TouchTap"), JumpRequest = Signal.new("JumpRequest"), GamepadConnected = Signal.new("gc"), GamepadDisconnected = Signal.new("gd"),
	WindowFocused = Signal.new("wf"), WindowFocusReleased = Signal.new("wfr"), TextBoxFocused = Signal.new("tbf"), TextBoxFocusReleased = Signal.new("tbfr"),
	TouchEnabled = false, KeyboardEnabled = true, GamepadEnabled = false, MouseEnabled = true, VREnabled = false, AccelerometerEnabled = false, GyroscopeEnabled = false,
	MouseBehavior = Enum.MouseBehavior.Default, MouseIconEnabled = true, MouseDeltaSensitivity = 1, ModalEnabled = false,
	GetLastInputType = function() return Enum.UserInputType.Keyboard end,
	IsKeyDown = function(_, k) if mtypeof(k) ~= "EnumItem" then error("IsKeyDown: KeyCode expected", 2) end return false end,
	IsMouseButtonPressed = function() return false end,
	GetFocusedTextBox = function() return nil end,
	GetMouseLocation = function() return Vector2.new(640, 360) end,
	GetMouseDelta = function() return Vector2.zero end,
	GetConnectedGamepads = function() return {} end,
	GetNavigationGamepads = function() return {} end,
	GetKeysPressed = function() return {} end,
	GetGamepadConnected = function() return false end,
	GetStringForKeyCode = function(_, k) return k.Name end,
	GetImageForKeyCode = function() return "" end,
	GetDeviceType = function() return Enum.DeviceType.Desktop end,
	PreferredInput = Enum.PreferredInput.KeyboardAndMouse,
})
local actions = {}
ContextActionService = apiService("ContextActionService", {
	BindAction = function(_, name, fn, touch, ...)
		if type(name) ~= "string" or type(fn) ~= "function" or type(touch) ~= "boolean" then error("BindAction(name:string, fn, createTouchButton:boolean, ...) bad args: " .. mtypeof(name) .. "," .. mtypeof(fn) .. "," .. mtypeof(touch), 2) end
		for i = 1, select("#", ...) do local x = select(i, ...) if mtypeof(x) ~= "EnumItem" then error("BindAction input " .. i .. " must be an EnumItem, got " .. mtypeof(x), 2) end end
		actions[name] = { fn = fn, ctx = curCtx(), inputs = { ... } }
	end,
	BindActionAtPriority = function(_, name, fn, touch, prio, ...)
		if type(name) ~= "string" or type(fn) ~= "function" or type(touch) ~= "boolean" or type(prio) ~= "number" then error("BindActionAtPriority(name, fn, touch:boolean, priority:number, ...) bad args: " .. mtypeof(touch) .. "," .. mtypeof(prio), 2) end
		actions[name] = { fn = fn, ctx = curCtx(), inputs = { ... } }
	end,
	UnbindAction = function(_, name) actions[name] = nil end,
	UnbindAllActions = function() actions = {} end,
	GetButton = function(_, name) return nil end,
	SetTitle = function(_, name, t) if type(name) ~= "string" then error("SetTitle: name expected", 2) end end,
	SetPosition = function(_, name, p) if mtypeof(p) ~= "UDim2" then error("SetPosition: UDim2 expected, got " .. mtypeof(p), 2) end end,
	SetImage = function() end, SetDescription = function() end,
	GetBoundActionInfo = function(_, n) return actions[n] or {} end,
	GetAllBoundActionInfo = function() return {} end,
	LocalToolEquipped = Signal.new("lte"), LocalToolUnequipped = Signal.new("ltu"),
})
MOCK_ACTIONS = function() return actions end
GuiService = apiService("GuiService", {
	GetGuiInset = function() return Vector2.new(0, 58), Vector2.zero end,
	TopbarInset = Rect.new(0, 0, 1280, 58),
	MenuOpened = Signal.new("mo"), MenuClosed = Signal.new("mc"),
	SelectedObject = nil, AutoSelectGuiEnabled = true, GuiNavigationEnabled = true, MenuIsOpen = false, ReducedMotionEnabled = false,
	PreferredTransparency = 1, TouchControlsEnabled = true, ViewportDisplaySize = Enum.DisplaySize.Medium,
	IsTenFootInterface = function() return false end,
	CloseInspectMenu = function() end, InspectPlayerFromUserId = function() end,
})
METHODS.StarterGui = {
	SetCoreGuiEnabled = function(_, t, on) if mtypeof(t) ~= "EnumItem" then error("SetCoreGuiEnabled: CoreGuiType expected", 2) end end,
	GetCoreGuiEnabled = function() return true end,
	SetCore = function(_, n, v) if type(n) ~= "string" then error("SetCore: string", 2) end end,
	GetCore = function() return nil end,
}
TextService = apiService("TextService", {
	GetTextSize = function(_, text, size, font, frame)
		if type(text) ~= "string" or type(size) ~= "number" or mtypeof(font) ~= "EnumItem" or mtypeof(frame) ~= "Vector2" then error("GetTextSize(string, number, Font, Vector2) bad args", 2) end
		return Vector2.new(#text * size * 0.55, size)
	end,
	GetTextBoundsAsync = function(_, params) return Vector2.new(100, 14) end,
	FilterStringAsync = function(_, s) return { GetNonChatStringForBroadcastAsync = function() return s end } end,
})
ContentProvider = apiService("ContentProvider", { PreloadAsync = function() end, RequestQueueSize = 0 })
TeleportService = apiService("TeleportService", { Teleport = function() end, TeleportAsync = function() end, GetLocalPlayerTeleportData = function() return nil end })
BadgeService = apiService("BadgeService", { AwardBadge = function() return true end, UserHasBadgeAsync = function() return false end, GetBadgeInfoAsync = function() return {} end })
MessagingService = apiService("MessagingService", { PublishAsync = function() end, SubscribeAsync = function() return { Disconnect = function() end } end })
LocalizationService = apiService("LocalizationService", { RobloxLocaleId = "en-us", SystemLocaleId = "en-us", GetCountryRegionForPlayerAsync = function() return "US" end })
SocialService = apiService("SocialService", { CanSendGameInviteAsync = function() return false end, PromptGameInvite = function() end })
AnalyticsService = apiService("AnalyticsService", { LogCustomEvent = function() end, LogEconomyEvent = function() end, LogProgressionEvent = function() end, LogOnboardingFunnelStepEvent = function() end, LogFunnelStepEvent = function() end })
HapticService = apiService("HapticService", { IsVibrationSupported = function() return false end, SetMotor = function() end, IsMotorSupported = function() return false end })
VRService = apiService("VRService", { VREnabled = false })
AssetService = apiService("AssetService", {})
GroupService = apiService("GroupService", { GetGroupsAsync = function() return {} end })
MemoryStoreService = apiService("MemoryStoreService", {})
CollectionService = apiService("CollectionService", CollectionServiceImpl)

local SERVICES = {
	Workspace = WORKSPACE, Players = PLAYERS, Lighting = LIGHTING, ReplicatedStorage = REPLICATED, ServerScriptService = SSS,
	ServerStorage = serverStorage, StarterPlayer = STARTER_PLAYER, StarterGui = STARTER_GUI, SoundService = soundService, Teams = teams,
	StarterPack = starterPack, HttpService = httpInst, ReplicatedFirst = replicatedFirst, Chat = chat, TextChatService = tcs,
	RunService = RunService, TweenService = TweenService, Debris = Debris, ProximityPromptService = ProximityPromptService,
	PathfindingService = PathfindingService, DataStoreService = DataStoreService, MarketplaceService = MarketplaceService,
	InsertService = InsertService, PhysicsService = PhysicsService, UserInputService = UserInputService,
	ContextActionService = ContextActionService, GuiService = GuiService, TextService = TextService, ContentProvider = ContentProvider,
	TeleportService = TeleportService, BadgeService = BadgeService, MessagingService = MessagingService, LocalizationService = LocalizationService,
	SocialService = SocialService, AnalyticsService = AnalyticsService, HapticService = HapticService, VRService = VRService,
	AssetService = AssetService, GroupService = GroupService, MemoryStoreService = MemoryStoreService, CollectionService = CollectionService,
}
BIND_TO_CLOSE = {}
METHODS.DataModel = {
	GetService = function(_, name)
		if type(name) ~= "string" then error("GetService: string expected", 2) end
		local s = SERVICES[name]
		if not s then error("'" .. name .. "' is not a valid Service name", 2) end
		return s
	end,
	FindService = function(_, name) return SERVICES[name] end,
	BindToClose = function(_, fn) if type(fn) ~= "function" then error("BindToClose: function expected", 2) end table.insert(BIND_TO_CLOSE, fn) end,
	IsLoaded = function() return true end,
	GetJobsInfo = function() return {} end,
}
DEFAULTS.DataModel = { PlaceId = 0, GameId = 0, JobId = "mock-job", CreatorId = 1, PlaceVersion = 1, PrivateServerId = "", PrivateServerOwnerId = 0, CreatorType = NILV }
EVENTS.DataModel = { "Close", "Loaded" }

-- LocalPlayer is context-dependent
local baseIndex = IMT.__index
IMT.__index = function(inst, k)
	if inst == PLAYERS and k == "LocalPlayer" then
		if curCtx().mode == "client" then return CLIENT and CLIENT.player end
		return nil
	end
	return baseIndex(inst, k)
end

-- ═══════════════ source tree + require ═══════════════
local MODCACHE = {}
local LOADING = {}
GENV = nil
local function mprint(...)
	local t = table.pack(...)
	for i = 1, t.n do t[i] = tostring(t[i]) end
	print(string.format("[%s %.1f] %s", curCtx().mode == "client" and "cli" or "srv", SCHED.now, table.concat(t, " ", 1, t.n)))
end
local function mwarn(...)
	local t = table.pack(...)
	for i = 1, t.n do t[i] = tostring(t[i]) end
	local msg = table.concat(t, " ", 1, t.n)
	print(string.format("[%s %.1f] WARN %s", curCtx().mode == "client" and "cli" or "srv", SCHED.now, msg))
	logOnce("warns", "W:" .. msg, "(" .. curCtx().mode .. ") " .. msg)
end
local mos = {
	clock = function() return SCHED.now end,
	time = function(t) if t then return os.time(t) end return BASE_TIME + math.floor(SCHED.now) end,
	date = function(f, t) return os.date(f, t or (BASE_TIME + math.floor(SCHED.now))) end,
	difftime = os.difftime,
}
function mockRequire(x)
	if mtypeof(x) ~= "Instance" then error("require: Attempted to call require with invalid argument(s). (" .. mtypeof(x) .. ")", 2) end
	local d = D[x]
	if d.class ~= "ModuleScript" then error("require: Attempted to call require with a " .. d.class .. " (" .. x:GetFullName() .. ")", 2) end
	local path = d.props._src
	local key = curCtx().mode .. ":" .. path
	local c = MODCACHE[key]
	if c then
		if c.err then error("Requested module experienced an error while loading: " .. x:GetFullName(), 2) end
		return c.value
	end
	if LOADING[key] then error("Requested module was required recursively: " .. path, 2) end
	LOADING[key] = true
	local chunk, perr = loadstring(SOURCES[path], "=" .. path)
	if not chunk then error("parse error: " .. tostring(perr)) end
	local env = setmetatable({ script = x }, { __index = GENV, __newindex = function(t, k, v) rawset(t, k, v) end })
	setfenv(chunk, env)
	local res = table.pack(pcall(chunk))
	LOADING[key] = nil
	if not res[1] then
		MODCACHE[key] = { err = true }
		logOnce("errors", "MODLOAD:" .. path .. tostring(res[2]), "module load failed " .. path .. ": " .. tostring(res[2]))
		error(tostring(res[2]), 2)
	end
	if res.n ~= 2 then
		MODCACHE[key] = { err = true }
		error("Module code did not return exactly one value: " .. path, 2)
	end
	MODCACHE[key] = { value = res[2] }
	return res[2]
end

GENV = {
	game = GAME, Game = GAME, workspace = WORKSPACE, Workspace = WORKSPACE, script = nil,
	Instance = Instance, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, UDim = UDim, UDim2 = UDim2,
	BrickColor = BrickColor, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint, ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint, NumberRange = NumberRange, TweenInfo = TweenInfo, Random = Random, Ray = Ray, Rect = Rect,
	RaycastParams = RaycastParams, OverlapParams = OverlapParams, Region3 = Region3, PhysicalProperties = PhysicalProperties, Font = Font,
	DateTime = DateTime, Axes = Axes, Faces = Faces, Enum = Enum,
	task = task, wait = wait, delay = delay, spawn = spawn, tick = tick, time = time, elapsedTime = elapsedTime,
	typeof = mtypeof, type = type, require = mockRequire, print = mprint, warn = mwarn, error = error, assert = assert,
	pcall = pcall, xpcall = xpcall, ypcall = pcall, select = select, pairs = pairs, ipairs = ipairs, next = next, tostring = tostring, tonumber = tonumber,
	rawget = rawget, rawset = rawset, rawequal = rawequal, rawlen = rawlen, setmetatable = setmetatable, getmetatable = getmetatable,
	unpack = table.unpack, newproxy = newproxy, gcinfo = function() return 1000 end, collectgarbage = function() return 1000 end,
	math = math, string = string, table = table, coroutine = coroutine, utf8 = utf8, bit32 = bit32, buffer = buffer, debug = debug, vector = vector,
	os = mos, shared = {}, settings = function() return ANY end, UserSettings = function() return ANY end, version = function() return "0.650" end,
	printidentity = function() end, getfenv = getfenv, setfenv = setfenv, loadstring = nil,
}
GENV._G = GENV

-- Build Rojo tree
local function mkModule(parent, name, path, class)
	local m = newInstance(class or "ModuleScript", parent)
	m.Name = name
	D[m].props._src = path
	return m
end
SERVER_SCRIPT = mkModule(SSS, "Server", "src/server/init.server.lua", "Script")
local shared = newInstance("Folder", REPLICATED)
shared.Name = "Shared"
local assets = newInstance("Folder", REPLICATED)
assets.Name = "Assets"
local cliScript = mkModule(sps, "Client", "src/client/init.client.lua", "LocalScript")
CLIENT_SCRIPT_TEMPLATE = cliScript
for path in pairs(SOURCES) do
	local dir, file = path:match("^src/(%w+)/([%w_]+)%.lua$")
	if dir and not file:match("^init") then
		local parent = dir == "server" and SERVER_SCRIPT or dir == "shared" and shared or dir == "client" and cliScript
		if parent then mkModule(parent, file, path) end
	end
end

function runScript(inst, ctx)
	local path = D[inst].props._src
	local chunk, perr = loadstring(SOURCES[path], "=" .. path)
	if not chunk then error(perr) end
	setfenv(chunk, setmetatable({ script = inst }, { __index = GENV }))
	local co = newThread(chunk, ctx)
	resumeThread(co)
	return co
end

-- ═══════════════ test helpers ═══════════════
local nextUid = 1000
function addPlayer(name)
	nextUid += 1
	local p = newInstance("Player")
	p.Name = name
	D[p].props.UserId = nextUid
	D[p].props.DisplayName = name
	local bp = newInstance("Backpack", p) bp.Name = "Backpack"
	local pg = newInstance("PlayerGui", p) pg.Name = "PlayerGui"
	local ps = newInstance("PlayerScripts", p) ps.Name = "PlayerScripts"
	p.Parent = PLAYERS
	getSig(PLAYERS, "PlayerAdded"):Fire(p)
	task.wait(0.2)
	spawnCharacter(p)
	return p
end
function removePlayer(p)
	getSig(PLAYERS, "PlayerRemoving"):Fire(p)
	if p.Character then p.Character:Destroy() end
	p:Destroy()
end
function triggerPrompt(prompt, player, note)
	if mtypeof(prompt) ~= "Instance" or D[prompt].class ~= "ProximityPrompt" then error("triggerPrompt: not a prompt: " .. tostring(prompt)) end
	local pd = D[prompt].props
	local parent = prompt.Parent
	local where = parent and (isA(D[parent].class, "BasePart") and parent.Position or (parent:IsA("Attachment") and parent.WorldPosition) or (parent:IsA("Model") and parent:GetPivot().Position))
	-- teleport the player next to the prompt so distance checks pass
	local char = player.Character
	if char and where then char:PivotTo(CFrame.new(where + Vector3.new(0, 0, 2))) end
	if pd.Enabled == false then print("[mock] NOTE prompt disabled: " .. prompt:GetFullName() .. " " .. (note or "")) return false end
	getSig(prompt, "PromptButtonHoldBegan"):Fire(player)
	ProximityPromptService.PromptButtonHoldBegan:Fire(prompt, player)
	getSig(prompt, "Triggered"):Fire(player)
	ProximityPromptService.PromptTriggered:Fire(prompt, player)
	getSig(prompt, "PromptButtonHoldEnded"):Fire(player)
	getSig(prompt, "TriggerEnded"):Fire(player)
	ProximityPromptService.PromptTriggerEnded:Fire(prompt, player)
	return true
end
function touch(part, other)
	getSig(part, "Touched"):Fire(other)
end
function findPrompts(root, pred)
	local out = {}
	for _, x in ipairs(descendants(root or WORKSPACE)) do
		if D[x].class == "ProximityPrompt" and (not pred or pred(x)) then table.insert(out, x) end
	end
	return out
end

-- main loop
function runMain(fn, maxT)
	local co = newThread(fn, MAIN_CTX)
	resumeThread(co)
	local limit = SCHED.now + (maxT or 600)
	while coroutine.status(co) ~= "dead" and SCHED.now < limit do
		if REAL_LIMIT and os.clock() > REAL_LIMIT then print("[mock] real-time limit hit at t=" .. SCHED.now) break end
		local item = heap[1]
		if not item then break end
		if item.t > limit then break end
		local it = (function()
			local top = heap[1]
			-- pop
			return top
		end)()
		-- real pop
		local popped = (function()
			local h = heap
			local top = h[1]
			local last = table.remove(h)
			if #h > 0 then
				h[1] = last
				local i = 1
				while true do
					local l, r = i * 2, i * 2 + 1
					local m = i
					if l <= #h and (h[l].t < h[m].t or (h[l].t == h[m].t and h[l].s < h[m].s)) then m = l end
					if r <= #h and (h[r].t < h[m].t or (h[r].t == h[m].t and h[r].s < h[m].s)) then m = r end
					if m == i then break end
					h[m], h[i] = h[i], h[m]
					i = m
				end
			end
			return top
		end)()
		SCHED.now = math.max(SCHED.now, popped.t)
		HANG = 0
		local ok, e = pcall(popped.fn)
		if not ok then reportError(e, coroutine.running() or co, "scheduler") end
	end
	if coroutine.status(co) ~= "dead" then print("[mock] driver did not finish (t=" .. SCHED.now .. ")") end
end

function report()
	print("\n================ MOCK REPORT ================")
	print("virtual time: " .. string.format("%.1f", SCHED.now) .. "s, frames " .. FRAME_COUNT)
	print("\n---- RUNTIME ERRORS (" .. #LOG.errors .. ") ----")
	for _, e in ipairs(LOG.errors) do print(e) print("") end
	print("\n---- WARNINGS (" .. #LOG.warns .. ") ----")
	for _, e in ipairs(LOG.warns) do print(e) end
	print("\n---- UNKNOWN MEMBERS (" .. #LOG.unknown .. ") ----")
	for _, e in ipairs(LOG.unknown) do print(e) end
end

CLIENT_CTX = { mode = "client", name = "client" }
function startClient(p)
	CLIENT = { player = p }
	D[WORKSPACE].props.CurrentCamera.CameraSubject = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	runScript(CLIENT_SCRIPT_TEMPLATE, CLIENT_CTX)
end
function pressKey(key, gameProcessed)
	local input = { KeyCode = key, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.Begin, Position = Vector3.zero, Delta = Vector3.zero }
	UserInputService.InputBegan:Fire(input, gameProcessed or false)
	for name, a in pairs(MOCK_ACTIONS()) do
		for _, k in ipairs(a.inputs) do
			if k == key then resumeThread(newThread(a.fn, a.ctx), name, Enum.UserInputState.Begin, input) end
		end
	end
	local input2 = table.clone(input) input2.UserInputState = Enum.UserInputState.End
	UserInputService.InputEnded:Fire(input2, gameProcessed or false)
	for name, a in pairs(MOCK_ACTIONS()) do
		for _, k in ipairs(a.inputs) do
			if k == key then resumeThread(newThread(a.fn, a.ctx), name, Enum.UserInputState.End, input2) end
		end
	end
end
function clickAllButtons(root)
	local n = 0
	for _, x in ipairs(descendants(root)) do
		if isA(D[x].class, "GuiButton") and x.Visible then
			for _, ev in ipairs({ "MouseButton1Click", "Activated" }) do
				local s = D[x].sigs[ev]
				if s then s:Fire() n += 1 end
			end
		end
	end
	return n
end
