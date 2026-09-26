-- ═══════════════ Scheduler ═══════════════
SCHED = { now = 0, heap = {}, seq = 0, frame = 1 / 20 }
local heap = SCHED.heap
local function hpush(item)
	table.insert(heap, item)
	local i = #heap
	while i > 1 do
		local p = i // 2
		local a, b = heap[p], heap[i]
		if a.t < b.t or (a.t == b.t and a.s < b.s) then break end
		heap[p], heap[i] = b, a
		i = p
	end
end
local function hpop()
	local top = heap[1]
	local last = table.remove(heap)
	if #heap > 0 then
		heap[1] = last
		local i = 1
		while true do
			local l, r = i * 2, i * 2 + 1
			local m = i
			local function lt(x, y) return heap[x].t < heap[y].t or (heap[x].t == heap[y].t and heap[x].s < heap[y].s) end
			if l <= #heap and lt(l, m) then m = l end
			if r <= #heap and lt(r, m) then m = r end
			if m == i then break end
			heap[m], heap[i] = heap[i], heap[m]
			i = m
		end
	end
	return top
end
function SCHED.at(t, fn)
	SCHED.seq += 1
	hpush({ t = t, s = SCHED.seq, fn = fn })
end

THREAD_CTX = setmetatable({}, { __mode = "k" })
CANCELLED = setmetatable({}, { __mode = "k" })
function curCtx()
	local co = coroutine.running()
	return (co and THREAD_CTX[co]) or MAIN_CTX
end
MAIN_CTX = { mode = "server", name = "main" }

local function shortTrace(co, err)
	local tb = debug.traceback(co)
	return tostring(err) .. "\n" .. tb
end
function reportError(err, co, where)
	local msg = tostring(err)
	local key = "ERR:" .. msg
	logOnce("errors", key, "[" .. (where or "thread") .. "] " .. shortTrace(co, err))
	if LOG.seen[key] == 1 then print("!!! RUNTIME ERROR: " .. msg) end
end

function resumeThread(co, ...)
	if CANCELLED[co] then return end
	if DEBUG_VT and SCHED.now > DEBUG_VT then print("[resume] " .. tostring(THREAD_SRC[co]) .. " t=" .. SCHED.now) end
	if coroutine.status(co) ~= "suspended" then return end
	local ok, err = coroutine.resume(co, ...)
	if not ok then reportError(err, co) end
end

THREAD_SRC = setmetatable({}, { __mode = "k" })
function newThread(fn, ctx)
	local co = coroutine.create(fn)
	THREAD_CTX[co] = ctx or curCtx()
	local src, line = debug.info(fn, "sl")
	THREAD_SRC[co] = tostring(src) .. ":" .. tostring(line)
	return co
end

task = {}
function task.spawn(f, ...)
	local co
	if type(f) == "thread" then co = f else
		if type(f) ~= "function" then error("task.spawn: function or thread expected, got " .. mtypeof(f), 2) end
		co = newThread(f)
	end
	resumeThread(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or newThread(f)
	local args = table.pack(...)
	SCHED.at(SCHED.now, function() resumeThread(co, table.unpack(args, 1, args.n)) end)
	return co
end
function task.delay(t, f, ...)
	if type(t) ~= "number" then error("task.delay: number expected, got " .. mtypeof(t), 2) end
	if type(f) ~= "function" and type(f) ~= "thread" then error("task.delay: function expected, got " .. mtypeof(f), 2) end
	local co = type(f) == "thread" and f or newThread(f)
	local args = table.pack(...)
	SCHED.at(SCHED.now + math.max(t, 0), function() resumeThread(co, table.unpack(args, 1, args.n)) end)
	return co
end
function task.wait(t)
	t = t or 0
	if type(t) ~= "number" then error("task.wait: number expected, got " .. mtypeof(t), 2) end
	local co = coroutine.running()
	if not co or not coroutine.isyieldable() then error("task.wait called from non-yieldable context", 2) end
	local start = SCHED.now
	SCHED.at(SCHED.now + math.max(t, SCHED.frame), function() resumeThread(co, SCHED.now - start) end)
	return coroutine.yield()
end
function task.cancel(co) CANCELLED[co] = true end
function task.synchronize() end
function task.desynchronize() end
wait = task.wait
function delay(t, f) return task.delay(t, f) end
spawn = function(f) return task.defer(f) end
BASE_TIME = 1790000000
function tick() return BASE_TIME + SCHED.now end
function time() return SCHED.now end
function elapsedTime() return SCHED.now end

function yieldForever(reason)
	local co = coroutine.running()
	if reason then logOnce("warns", "YF:" .. reason, "infinite yield: " .. reason) end
	return coroutine.yield()
end

-- ═══════════════ Signals ═══════════════
local SigMT = {}
TYPEOF[SigMT] = "RBXScriptSignal"
local ConnMT = {}
TYPEOF[ConnMT] = "RBXScriptConnection"
Signal = {}
SigMT.__index = Signal
ConnMT.__index = { Disconnect = function(c) c.Connected = false c.sig.handlers[c] = nil end }
function Signal.new(name) return setmetatable({ name = name, handlers = {}, order = {}, waiting = {} }, SigMT) end
function Signal:Connect(fn)
	if type(fn) ~= "function" then error("Attempt to connect failed: Passed value is not a function (" .. mtypeof(fn) .. ") to " .. tostring(self.name), 2) end
	local c = setmetatable({ Connected = true, fn = fn, sig = self, ctx = curCtx() }, ConnMT)
	self.handlers[c] = true
	table.insert(self.order, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect() fn(...) end)
	return c
end
Signal.ConnectParallel = Signal.Connect
function Signal:Wait()
	local co = coroutine.running()
	table.insert(self.waiting, co)
	return coroutine.yield()
end
function Signal:Fire(...)
	local order = self.order
	local live = {}
	for _, c in ipairs(order) do if self.handlers[c] then table.insert(live, c) end end
	self.order = live
	for _, c in ipairs(live) do
		if c.Connected then
			local co = newThread(c.fn, c.ctx)
			resumeThread(co, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in ipairs(w) do resumeThread(co, ...) end
end
function Signal:DisconnectAll()
	for c in pairs(self.handlers) do c.Connected = false end
	self.handlers = {}; self.order = {}
end

-- ═══════════════ Any (permissive stand-in) ═══════════════
local AnyMT = {}
ANY = setmetatable({}, AnyMT)
AnyMT.__index = function() return ANY end
AnyMT.__newindex = function() end
AnyMT.__call = function() return ANY end
AnyMT.__tostring = function() return "<Any>" end
TYPEOF[AnyMT] = "Any"

-- ═══════════════ Instances ═══════════════
D = setmetatable({}, { __mode = "k" })
IMT = {}
TYPEOF[IMT] = "Instance"
Instance = {}
NILV = {}   -- sentinel: "property exists, default nil"

SUPER = {
	PVInstance = "Instance", BasePart = "PVInstance", Model = "PVInstance",
	Part = "FormFactorPart", FormFactorPart = "BasePart", MeshPart = "TriangleMeshPart", TriangleMeshPart = "BasePart",
	WedgePart = "FormFactorPart", CornerWedgePart = "BasePart", TrussPart = "BasePart", SpawnLocation = "Part", Seat = "Part",
	VehicleSeat = "BasePart", UnionOperation = "PartOperation", PartOperation = "TriangleMeshPart", Terrain = "BasePart",
	Workspace = "WorldRoot", WorldRoot = "Model", Actor = "Model",
	GuiBase = "Instance", GuiBase2d = "GuiBase", GuiObject = "GuiBase2d", LayerCollector = "GuiBase2d",
	Frame = "GuiObject", TextLabel = "GuiObject", GuiButton = "GuiObject", TextButton = "GuiButton", ImageButton = "GuiButton",
	ImageLabel = "GuiObject", ScrollingFrame = "GuiObject", TextBox = "GuiObject", ViewportFrame = "GuiObject",
	CanvasGroup = "GuiObject", VideoFrame = "GuiObject",
	ScreenGui = "LayerCollector", SurfaceGuiBase = "LayerCollector", SurfaceGui = "SurfaceGuiBase", BillboardGui = "LayerCollector",
	Light = "Instance", PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light",
	ValueBase = "Instance", IntValue = "ValueBase", NumberValue = "ValueBase", StringValue = "ValueBase", BoolValue = "ValueBase",
	ObjectValue = "ValueBase", Vector3Value = "ValueBase", CFrameValue = "ValueBase", Color3Value = "ValueBase",
	UIComponent = "Instance", UICorner = "UIComponent", UIStroke = "UIComponent", UIGradient = "UIComponent", UIPadding = "UIComponent",
	UIScale = "UIComponent", UIConstraint = "UIComponent", UISizeConstraint = "UIConstraint", UITextSizeConstraint = "UIConstraint",
	UIAspectRatioConstraint = "UIConstraint", UILayout = "UIComponent", UIGridStyleLayout = "UILayout", UIListLayout = "UIGridStyleLayout",
	UIGridLayout = "UIGridStyleLayout", UIPageLayout = "UIGridStyleLayout", UIFlexItem = "UIComponent",
	PostEffect = "Instance", BloomEffect = "PostEffect", ColorCorrectionEffect = "PostEffect", BlurEffect = "PostEffect",
	SunRaysEffect = "PostEffect", DepthOfFieldEffect = "PostEffect",
	LuaSourceContainer = "Instance", BaseScript = "LuaSourceContainer", Script = "BaseScript", LocalScript = "Script", ModuleScript = "LuaSourceContainer",
	JointInstance = "Instance", Weld = "JointInstance", Motor6D = "JointInstance", WeldConstraint = "Instance",
	Constraint = "Instance", RopeConstraint = "Constraint", AlignPosition = "Constraint", AlignOrientation = "Constraint",
	LinearVelocity = "Constraint", HingeConstraint = "Constraint", BallSocketConstraint = "Constraint",
	FaceInstance = "Instance", Decal = "FaceInstance", Texture = "Decal",
	Accoutrement = "Instance", Accessory = "Accoutrement", Clothing = "CharacterAppearance", CharacterAppearance = "Instance",
	Shirt = "Clothing", Pants = "Clothing", BodyColors = "CharacterAppearance",
	Folder = "Instance", Configuration = "Instance", Sound = "Instance", SoundGroup = "Instance", Animation = "Instance", Animator = "Instance",
	AnimationTrack = "Instance", Humanoid = "Instance", HumanoidDescription = "Instance", Attachment = "Instance", Bone = "Attachment",
	Highlight = "Instance", ParticleEmitter = "Instance", Trail = "Instance", Beam = "Instance", Sky = "Instance", Atmosphere = "Instance",
	Clouds = "Instance", ProximityPrompt = "Instance", RemoteEvent = "Instance", RemoteFunction = "Instance", UnreliableRemoteEvent = "Instance",
	BindableEvent = "Instance", BindableFunction = "Instance", Camera = "PVInstance", Player = "Instance", PlayerGui = "BasePlayerGui",
	BasePlayerGui = "Instance", PlayerScripts = "Instance", Backpack = "Instance", StarterGear = "Instance",
	ClickDetector = "Instance", SelectionBox = "Instance", Fire = "Instance", Smoke = "Instance", Sparkles = "Instance",
	Explosion = "Instance", BodyVelocity = "Instance", BodyGyro = "Instance", BodyPosition = "Instance", Tool = "BackpackItem",
	BackpackItem = "Instance", SpecialMesh = "Instance", BlockMesh = "Instance", Team = "Instance", Dialog = "Instance",
	PathfindingModifier = "Instance", PathfindingLink = "Instance", VectorForce = "Constraint", Path = "Instance",
	Tween = "Instance", DataModel = "Instance", Lighting = "Instance", Players = "Instance", ReplicatedStorage = "Instance",
	ServerScriptService = "Instance", ServerStorage = "Instance", StarterPlayer = "Instance", StarterPlayerScripts = "Instance",
	StarterCharacterScripts = "Instance", StarterGui = "Instance", StarterPack = "Instance", SoundService = "Instance",
	Teams = "Instance", Chat = "Instance", TextChatService = "Instance", HttpService = "Instance",
}
function isA(class, want)
	local c = class
	while c do
		if c == want then return true end
		c = SUPER[c]
	end
	return false
end
CREATABLE = {}
for k in pairs(SUPER) do CREATABLE[k] = true end
for _, abstract in ipairs({ "PVInstance", "BasePart", "FormFactorPart", "TriangleMeshPart", "GuiBase", "GuiBase2d", "GuiObject",
	"LayerCollector", "Light", "ValueBase", "UIComponent", "UIConstraint", "UILayout", "UIGridStyleLayout", "PostEffect",
	"LuaSourceContainer", "BaseScript", "JointInstance", "Constraint", "FaceInstance", "Accoutrement", "Clothing", "CharacterAppearance",
	"GuiButton", "SurfaceGuiBase", "WorldRoot", "BasePlayerGui", "BackpackItem", "PartOperation", "Terrain", "Workspace", "DataModel",
	"Player", "PlayerGui", "AnimationTrack", "Tween", "Path", "Players", "Lighting", "ReplicatedStorage", "ServerScriptService",
	"StarterPlayer", "StarterGui", "SoundService", "HttpService" }) do CREATABLE[abstract] = nil end

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
DEFAULTS = {
	Instance = { Archivable = true },
	BasePart = { Anchored = false, CanCollide = true, CanTouch = true, CanQuery = true, Transparency = 0, Reflectance = 0,
		Color = Color3.new(0.64, 0.635, 0.647), Material = Enum.Material.Plastic, Locked = false, Massless = false, CastShadow = true,
		CollisionGroup = "Default", AssemblyLinearVelocity = Vector3.zero, AssemblyAngularVelocity = Vector3.zero, Velocity = Vector3.zero,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth, FrontSurface = Enum.SurfaceType.Smooth,
		BackSurface = Enum.SurfaceType.Smooth, LeftSurface = Enum.SurfaceType.Smooth, RightSurface = Enum.SurfaceType.Smooth,
		CustomPhysicalProperties = NILV, RootPriority = 0, MaterialVariant = "", AudioCanCollide = true, EnableFluidForces = true,
		PivotOffset = CFrame.identity, BrickColor = BrickColor.new("Medium stone grey"), LocalTransparencyModifier = 0, RotVelocity = Vector3.zero,
		CollisionGroupId = 0 },
	Part = { Shape = Enum.PartType.Block },
	MeshPart = { MeshId = "", TextureID = "", DoubleSided = false, MeshSize = Vector3.new(1, 1, 1), RenderFidelity = NILV, CollisionFidelity = NILV },
	UnionOperation = { UsePartColor = false },
	SpawnLocation = { Neutral = true, Duration = 10, Enabled = true, AllowTeamChangeOnTouch = false, TeamColor = BrickColor.new("White") },
	Seat = { Disabled = false, Occupant = NILV },
	VehicleSeat = { Disabled = false, Occupant = NILV, Throttle = 0, Steer = 0, ThrottleFloat = 0, SteerFloat = 0, MaxSpeed = 25, Torque = 10, TurnSpeed = 1, HeadsUpDisplay = true },
	TrussPart = { Style = Enum.Style.AlternatingSupports },
	Model = { PrimaryPart = NILV, LevelOfDetail = NILV, ModelStreamingMode = NILV },
	Workspace = { Gravity = 196.2, FilteringEnabled = true, StreamingEnabled = false, DistributedGameTime = 0, FallenPartsDestroyHeight = -500 },
	Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = false, HipHeight = 2,
		AutoRotate = true, Sit = false, PlatformStand = false, DisplayName = "", DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer,
		HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged, NameDisplayDistance = 100, HealthDisplayDistance = 100,
		RigType = Enum.HumanoidRigType.R15, MoveDirection = Vector3.zero, FloorMaterial = Enum.Material.Air, Jump = false, RequiresNeck = true,
		BreakJointsOnDeath = true, EvaluateStateMachine = true, SeatPart = NILV, WalkToPoint = Vector3.zero, AutoJumpEnabled = true,
		MaxSlopeAngle = 89, CameraOffset = Vector3.zero, TargetPoint = Vector3.zero, NameOcclusion = NILV },
	GuiObject = { Position = UDim2.new(), Size = UDim2.new(), AnchorPoint = Vector2.zero, BackgroundColor3 = Color3.fromRGB(163, 162, 165),
		BackgroundTransparency = 0, BorderSizePixel = 1, BorderColor3 = Color3.fromRGB(27, 42, 53), Visible = true, ZIndex = 1, LayoutOrder = 0,
		Rotation = 0, ClipsDescendants = false, AutomaticSize = Enum.AutomaticSize.None, Active = false, Selectable = false,
		AbsoluteSize = Vector2.new(100, 100), AbsolutePosition = Vector2.zero, AbsoluteRotation = 0, Interactable = true, BorderMode = NILV,
		SizeConstraint = NILV, NextSelectionDown = NILV, SelectionImageObject = NILV, GuiState = NILV },
	TextLabel = { Text = "Label" }, TextButton = { Text = "Button" }, TextBox = { Text = "", PlaceholderText = "", ClearTextOnFocus = true,
		MultiLine = false, TextEditable = true, CursorPosition = 1, PlaceholderColor3 = Color3.new(0.7, 0.7, 0.7) },
	GuiButton = { AutoButtonColor = true, Modal = false, Selected = false },
	ImageLabel = { Image = "", ImageColor3 = WHITE, ImageTransparency = 0, ScaleType = NILV, ImageRectOffset = Vector2.zero, ImageRectSize = Vector2.zero, SliceCenter = NILV, ResampleMode = NILV, SliceScale = 1, TileSize = UDim2.fromScale(1, 1), IsLoaded = true },
	ImageButton = { Image = "", ImageColor3 = WHITE, ImageTransparency = 0, ScaleType = NILV, ImageRectOffset = Vector2.zero, ImageRectSize = Vector2.zero, SliceCenter = NILV, HoverImage = "", PressedImage = "", SliceScale = 1 },
	ScrollingFrame = { CanvasSize = UDim2.new(0, 0, 2, 0), CanvasPosition = Vector2.zero, ScrollBarThickness = 12, ScrollingDirection = Enum.ScrollingDirection.XY,
		AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollBarImageColor3 = WHITE, ScrollBarImageTransparency = 0, ElasticBehavior = NILV, ScrollingEnabled = true,
		VerticalScrollBarInset = Enum.ScrollBarInset.None, HorizontalScrollBarInset = Enum.ScrollBarInset.None, AbsoluteCanvasSize = Vector2.new(100, 200), AbsoluteWindowSize = Vector2.new(100, 100),
		TopImage = "", MidImage = "", BottomImage = "", VerticalScrollBarPosition = NILV },
	CanvasGroup = { GroupTransparency = 0, GroupColor3 = WHITE },
	ViewportFrame = { CurrentCamera = NILV, Ambient = WHITE, LightColor = WHITE, LightDirection = Vector3.new(-1, -1, -1), ImageTransparency = 0, ImageColor3 = WHITE },
	LayerCollector = { Enabled = true, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Global, AbsoluteSize = Vector2.new(1280, 720) },
	ScreenGui = { IgnoreGuiInset = false, DisplayOrder = 0, ScreenInsets = NILV, ClipToDeviceSafeArea = true, SafeAreaCompatibility = NILV },
	SurfaceGui = { Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, PixelsPerStud = 50, CanvasSize = Vector2.new(800, 600),
		Adornee = NILV, AlwaysOnTop = false, LightInfluence = 1, Brightness = 1, ClipsDescendants = true, MaxDistance = 1000, ZOffset = 0, ToolPunchThroughDistance = 0 },
	BillboardGui = { Size = UDim2.new(), StudsOffset = Vector3.zero, StudsOffsetWorldSpace = Vector3.zero, ExtentsOffset = Vector3.zero,
		ExtentsOffsetWorldSpace = Vector3.zero, AlwaysOnTop = false, MaxDistance = math.huge, Adornee = NILV, LightInfluence = 1, SizeOffset = Vector2.zero,
		ClipsDescendants = false, DistanceLowerLimit = 0, DistanceUpperLimit = -1, DistanceStep = 0, Brightness = 1, PlayerToHideFrom = NILV },
	TextLabel_ = {},
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIStroke = { Color = BLACK, Thickness = 1, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, LineJoinMode = NILV, Enabled = true },
	UIGradient = { Color = ColorSequence.new(WHITE), Transparency = NumberSequence.new(0), Rotation = 0, Offset = Vector2.zero, Enabled = true },
	UIGridStyleLayout = { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.Name, HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top, AbsoluteContentSize = Vector2.new(100, 100) },
	UIListLayout = { Padding = UDim.new(0, 0), Wraps = false, HorizontalFlex = NILV, VerticalFlex = NILV, ItemLineAlignment = NILV },
	UIGridLayout = { CellSize = UDim2.fromOffset(100, 100), CellPadding = UDim2.fromOffset(5, 5), FillDirectionMaxCells = 0, StartCorner = NILV, AbsoluteCellSize = Vector2.new(100, 100), AbsoluteCellCount = Vector2.new(1, 1) },
	UIPadding = { PaddingTop = UDim.new(), PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new() },
	UIScale = { Scale = 1 },
	UISizeConstraint = { MinSize = Vector2.zero, MaxSize = Vector2.new(math.huge, math.huge) },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	UIAspectRatioConstraint = { AspectRatio = 1, AspectType = NILV, DominantAxis = NILV },
	Light = { Brightness = 1, Color = WHITE, Enabled = true, Shadows = false },
	PointLight = { Range = 8 }, SpotLight = { Range = 16, Angle = 90, Face = Enum.NormalId.Front }, SurfaceLight = { Range = 16, Angle = 90, Face = Enum.NormalId.Front },
	Sound = { SoundId = "", Volume = 0.5, Looped = false, Playing = false, PlaybackSpeed = 1, TimePosition = 0, TimeLength = 1, IsLoaded = true,
		IsPlaying = false, IsPaused = false, RollOffMaxDistance = 10000, RollOffMinDistance = 10, RollOffMode = Enum.RollOffMode.Inverse, PlayOnRemove = false, SoundGroup = NILV, PlaybackLoudness = 0 },
	ProximityPrompt = { ActionText = "Interact", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10, Enabled = true,
		KeyboardKeyCode = Enum.KeyCode.E, GamepadKeyCode = Enum.KeyCode.ButtonX, RequiresLineOfSight = true, Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
		Style = Enum.ProximityPromptStyle.Default, UIOffset = Vector2.zero, ClickablePrompt = true, AutoLocalize = true },
	Attachment = { Visible = false, Axis = Vector3.xAxis, SecondaryAxis = Vector3.yAxis },
	Highlight = { FillColor = Color3.new(1, 0, 0), FillTransparency = 0.5, OutlineColor = WHITE, OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Adornee = NILV, Enabled = true },
	ParticleEmitter = { Color = ColorSequence.new(WHITE), Size = NumberSequence.new(1), Transparency = NumberSequence.new(0), Lifetime = NumberRange.new(5, 10),
		Rate = 20, Speed = NumberRange.new(5), SpreadAngle = Vector2.zero, Enabled = true, Texture = "", LightEmission = 0, LightInfluence = 0,
		Rotation = NumberRange.new(0), RotSpeed = NumberRange.new(0), Acceleration = Vector3.zero, Drag = 0, EmissionDirection = Enum.NormalId.Top,
		ZOffset = 0, LockedToPart = false, Brightness = 1, Orientation = NILV, Shape = NILV, ShapeStyle = NILV, ShapeInOut = NILV, VelocityInheritance = 0, TimeScale = 1, Squash = NumberSequence.new(0) },
	Trail = { Attachment0 = NILV, Attachment1 = NILV, Color = ColorSequence.new(WHITE), Transparency = NumberSequence.new(0), Lifetime = 2, Enabled = true, FaceCamera = false,
		WidthScale = NumberSequence.new(1), MinLength = 0.1, LightEmission = 0, LightInfluence = 0, Texture = "", MaxLength = 0, Brightness = 1, TextureLength = 1, TextureMode = NILV },
	Beam = { Attachment0 = NILV, Attachment1 = NILV, Color = ColorSequence.new(WHITE), Transparency = NumberSequence.new(0), Enabled = true, FaceCamera = false,
		Width0 = 1, Width1 = 1, Segments = 10, CurveSize0 = 0, CurveSize1 = 0, LightEmission = 0, LightInfluence = 0, Texture = "", TextureSpeed = 1, TextureLength = 1, TextureMode = NILV, Brightness = 1, ZOffset = 0 },
	Sky = { CelestialBodiesShown = true, StarCount = 3000, SunAngularSize = 21, MoonAngularSize = 11, SkyboxBk = "", SkyboxDn = "", SkyboxFt = "", SkyboxLf = "", SkyboxRt = "", SkyboxUp = "", SunTextureId = "", MoonTextureId = "", SkyboxOrientation = Vector3.zero },
	Atmosphere = { Density = 0.3, Offset = 0, Color = WHITE, Decay = WHITE, Glare = 0, Haze = 0 },
	BloomEffect = { Intensity = 1, Size = 24, Threshold = 2, Enabled = true },
	ColorCorrectionEffect = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE, Enabled = true },
	BlurEffect = { Size = 24, Enabled = true }, SunRaysEffect = { Intensity = 0.25, Spread = 1, Enabled = true },
	DepthOfFieldEffect = { Enabled = true, FarIntensity = 0.75, FocusDistance = 0.05, InFocusRadius = 10, NearIntensity = 0.75 },
	IntValue = { Value = 0 }, NumberValue = { Value = 0 }, StringValue = { Value = "" }, BoolValue = { Value = false }, ObjectValue = { Value = NILV },
	Vector3Value = { Value = Vector3.zero }, CFrameValue = { Value = CFrame.identity }, Color3Value = { Value = BLACK },
	Animation = { AnimationId = "" },
	AnimationTrack = { IsPlaying = false, Length = 1, Looped = false, Priority = Enum.AnimationPriority.Core, Speed = 1, TimePosition = 0, WeightCurrent = 1, WeightTarget = 1 },
	Camera = { FieldOfView = 70, CameraType = Enum.CameraType.Custom, CameraSubject = NILV, ViewportSize = Vector2.new(1280, 720), NearPlaneZ = -0.1, HeadLocked = true, HeadScale = 1, DiagonalFieldOfView = 90, MaxAxisFieldOfView = 70, FieldOfViewMode = NILV, VRTiltAndRollEnabled = false },
	Player = { UserId = 1, DisplayName = "", Character = NILV, Team = NILV, TeamColor = BrickColor.new("White"), Neutral = true, RespawnLocation = NILV,
		AccountAge = 100, MembershipType = NILV, CameraMaxZoomDistance = 128, CameraMinZoomDistance = 0.5, CameraMode = NILV, DevEnableMouseLock = true,
		AutoJumpEnabled = true, CharacterAppearanceId = 1, HealthDisplayDistance = 100, NameDisplayDistance = 100, ReplicationFocus = NILV, GameplayPaused = false, LocaleId = "en-us", FollowUserId = 0, HasVerifiedBadge = false },
	Lighting = { Ambient = BLACK, Brightness = 2, ClockTime = 14, OutdoorAmbient = Color3.new(.5, .5, .5), ColorShift_Top = BLACK, ColorShift_Bottom = BLACK,
		EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0, ExposureCompensation = 0, FogColor = Color3.new(.75, .75, .75), FogEnd = 100000, FogStart = 0,
		GeographicLatitude = 41.7, GlobalShadows = true, Technology = NILV, TimeOfDay = "14:00:00", ShadowSoftness = 0.2, LightingStyle = NILV, PrioritizeLightingQuality = false },
	Decal = { Texture = "", Face = Enum.NormalId.Front, Transparency = 0, Color3 = WHITE, ZIndex = 1 },
	Texture = { StudsPerTileU = 2, StudsPerTileV = 2, OffsetStudsU = 0, OffsetStudsV = 0 },
	JointInstance = { Part0 = NILV, Part1 = NILV, C0 = CFrame.identity, C1 = CFrame.identity, Enabled = true },
	WeldConstraint = { Part0 = NILV, Part1 = NILV, Enabled = true },
	Constraint = { Attachment0 = NILV, Attachment1 = NILV, Enabled = true, Visible = false, Color = BrickColor.new("White") },
	ClickDetector = { MaxActivationDistance = 32, CursorIcon = "" },
	SelectionBox = { Adornee = NILV, Color3 = WHITE, LineThickness = 0.15, Transparency = 0, SurfaceTransparency = 1, SurfaceColor3 = WHITE, Visible = true },
	Shirt = { ShirtTemplate = "" }, Pants = { PantsTemplate = "" },
	Accessory = { AccessoryType = NILV },
	RemoteFunction = { OnServerInvoke = NILV, OnClientInvoke = NILV },
	BindableFunction = { OnInvoke = NILV },
	Script = { Enabled = true, Disabled = false }, ModuleScript = {},
	Fire = { Heat = 9, Size = 5, Color = WHITE, SecondaryColor = WHITE, Enabled = true, TimeScale = 1 },
	Smoke = { Opacity = 0.5, RiseVelocity = 1, Size = 1, Color = WHITE, Enabled = true, TimeScale = 1 },
	Sparkles = { SparkleColor = WHITE, Enabled = true, TimeScale = 1 },
	BodyVelocity = { Velocity = Vector3.zero, MaxForce = Vector3.zero, P = 1250 },
	SpecialMesh = { MeshType = NILV, MeshId = "", TextureId = "", Scale = Vector3.one, Offset = Vector3.zero, VertexColor = Vector3.one },
	Tool = { RequiresHandle = true, CanBeDropped = true, Enabled = true, ToolTip = "", TextureId = "", Grip = CFrame.identity, ManualActivationOnly = false },
	Clouds = { Cover = 0.5, Density = 0.7, Color = WHITE, Enabled = true },
	SoundService = { AmbientReverb = NILV, RolloffScale = 1, DistanceFactor = 3.33, DopplerScale = 1, RespectFilteringEnabled = true },
	Terrain = { WaterColor = Color3.new(0.05, 0.3, 0.4), WaterReflectance = 1, WaterTransparency = 0.3, WaterWaveSize = 0.15, WaterWaveSpeed = 10, Decoration = false },
	Team = { TeamColor = BrickColor.new("White"), AutoAssignable = true },
	PathfindingModifier = { Label = "", PassThrough = false },
	HumanoidDescription = {},
	Explosion = { BlastPressure = 500000, BlastRadius = 4, DestroyJointRadiusPercent = 1, ExplosionType = NILV, Position = Vector3.zero, Visible = true },
	Backpack = {}, PlayerGui = { ScreenOrientation = NILV, SelectionImageObject = NILV, CurrentScreenOrientation = NILV },
	StarterGui = { ShowDevelopmentGui = true, ScreenOrientation = NILV },
	StarterPlayer = { CharacterWalkSpeed = 16, CharacterJumpPower = 50, CharacterJumpHeight = 7.2, CameraMaxZoomDistance = 400, LoadCharacterAppearance = true },
	Players = { MaxPlayers = 8, CharacterAutoLoads = true, RespawnTime = 5, BubbleChat = true },
}
local TEXT_DEFAULTS = { TextColor3 = BLACK, TextSize = 14, TextScaled = false, TextWrapped = false, Font = Enum.Font.Legacy,
	FontFace = Font.new("rbxasset://fonts/families/LegacyArial.json"), TextTransparency = 0, TextStrokeTransparency = 1, TextStrokeColor3 = BLACK,
	TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, RichText = false, TextTruncate = Enum.TextTruncate.None,
	TextBounds = Vector2.new(50, 14), LineHeight = 1, MaxVisibleGraphemes = -1, TextFits = true, TextDirection = NILV, LocalizedText = "", OpenTypeFeatures = "" }
for _, c in ipairs({ "TextLabel", "TextButton", "TextBox" }) do for k, v in pairs(TEXT_DEFAULTS) do DEFAULTS[c][k] = v end end
PERMISSIVE = { HumanoidDescription = true, Terrain = true, Accessory = true, AlignPosition = true, AlignOrientation = true, LinearVelocity = true,
	BodyGyro = true, BodyPosition = true, VectorForce = true, HingeConstraint = true, RopeConstraint = true, BallSocketConstraint = true, Dialog = true,
	BodyColors = true, Chat = true, TextChatService = true, Motor6D = true, Bone = true, Clouds = true }

local function defaultFor(class, k)
	local c = class
	while c do
		local t = DEFAULTS[c]
		if t then
			local v = t[k]
			if v ~= nil then return v end
		end
		c = SUPER[c]
	end
	return nil
end

-- ── per-class methods ──
METHODS = {}
local function methodFor(class, k)
	local c = class
	while c do
		local t = METHODS[c]
		if t then local m = t[k] if m ~= nil then return m end end
		c = SUPER[c]
	end
	return nil
end

-- known event names (lazily created)
EVENTS = {
	Instance = { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "Changed", "AttributeChanged" },
	BasePart = { "Touched", "TouchEnded" },
	Humanoid = { "Died", "HealthChanged", "MoveToFinished", "Running", "StateChanged", "Seated", "Jumping", "FreeFalling", "Touched", "AnimationPlayed", "ApplyDescriptionFinished" },
	GuiObject = { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "SelectionGained", "SelectionLost", "TouchTap" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" },
	TextBox = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
	ScrollingFrame = {},
	ProximityPrompt = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
	ClickDetector = { "MouseClick", "MouseHoverEnter", "MouseHoverLeave", "RightMouseClick" },
	Sound = { "Ended", "Loaded", "Played", "Stopped", "Paused", "Resumed", "DidLoop" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	UnreliableRemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	Player = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" },
	Players = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
	Seat = {}, VehicleSeat = {},
	AnimationTrack = { "Stopped", "Ended", "DidLoop", "KeyframeReached" },
	Animator = { "AnimationPlayed" },
	Tween = { "Completed" },
	Path = { "Blocked", "Unblocked" },
	Camera = {},
	Workspace = { "PersistentLoaded" },
	Tool = { "Activated", "Deactivated", "Equipped", "Unequipped" },
	ValueBase = {},
	Model = {},
	Explosion = { "Hit" },
	DataModel = { "Close" },
}
local function isEvent(class, k)
	local c = class
	while c do
		local t = EVENTS[c]
		if t then for _, n in ipairs(t) do if n == k then return true end end end
		c = SUPER[c]
	end
	return false
end

-- ── geometry helpers ──
local function partCF(d) return d.props.CFrame or CFrame.identity end

function newInstance(class, parent)
	local inst = setmetatable({}, IMT)
	D[inst] = { class = class, props = {}, children = {}, attrs = {}, tags = {}, sigs = {}, propSigs = {}, attrSigs = {}, owner = curCtx().mode }
	local d = D[inst]
	d.props.Name = class
	if isA(class, "BasePart") then
		d.props.CFrame = CFrame.identity
		d.props.Size = class == "Part" and Vector3.new(4, 1, 2) or Vector3.new(1, 1, 1)
		if class == "SpawnLocation" then d.props.Size = Vector3.new(12, 1, 12) end
		if class == "TrussPart" then d.props.Size = Vector3.new(2, 10, 2) end
	end
	if class == "Attachment" then d.props.CFrame = CFrame.identity end
	if class == "Camera" then d.props.CFrame = CFrame.new(0, 20, 20); d.props.Focus = CFrame.identity end
	if parent ~= nil then inst.Parent = parent end
	return inst
end

function Instance.new(class, parent)
	if type(class) ~= "string" then error("Instance.new: string expected, got " .. mtypeof(class), 2) end
	if not CREATABLE[class] then error("Unable to create an Instance of type \"" .. class .. "\"", 2) end
	if parent ~= nil and mtypeof(parent) ~= "Instance" then error("Instance.new: bad parent " .. mtypeof(parent), 2) end
	return newInstance(class, parent)
end

local function getSig(inst, k)
	local d = D[inst]
	local s = d.sigs[k]
	if not s then s = Signal.new(d.props.Name .. "." .. k) d.sigs[k] = s end
	return s
end
getSig = getSig
local function firePropChanged(inst, k)
	local d = D[inst]
	local s = d.propSigs[k]
	if s then s:Fire() end
	local c = d.sigs.Changed
	if c then
		if isA(d.class, "ValueBase") and k == "Value" then c:Fire(inst.Value) elseif not isA(d.class, "ValueBase") then c:Fire(k) end
	end
end
firePropChanged = firePropChanged

function isDescendantOf(inst, anc)
	local p = D[inst].parent
	while p do
		if p == anc then return true end
		p = D[p].parent
	end
	return false
end

local function descendants(inst, out)
	out = out or {}
	for _, c in ipairs(D[inst].children) do
		table.insert(out, c)
		descendants(c, out)
	end
	return out
end
descendants = descendants

TAGGED = {}          -- tag -> set
TAG_ADDED = {}       -- tag -> Signal
TAG_REMOVED = {}
function inGame(inst) return GAME ~= nil and (inst == GAME or isDescendantOf(inst, GAME)) end

local function setParent(inst, newParent)
	local d = D[inst]
	if d.locked then
		error("The Parent property of " .. tostring(d.props.Name) .. " is locked, current parent: NULL, new parent " .. (newParent and D[newParent].props.Name or "NULL"), 3)
	end
	if newParent ~= nil and mtypeof(newParent) ~= "Instance" then error("Parent: Instance expected, got " .. mtypeof(newParent), 3) end
	if newParent == inst or (newParent and isDescendantOf(newParent, inst)) then
		error("Attempt to set parent of " .. d.props.Name .. " to " .. D[newParent].props.Name .. " would result in circular reference", 3)
	end
	local old = d.parent
	if old == newParent then return end
	local wasIn = inGame(inst)
	if old then
		local od = D[old]
		for i, c in ipairs(od.children) do if c == inst then table.remove(od.children, i) break end end
		local a = old
		local removed = { inst }
		for _, x in ipairs(descendants(inst)) do table.insert(removed, x) end
		while a do
			local s = D[a].sigs.DescendantRemoving
			if s then for _, x in ipairs(removed) do s:Fire(x) end end
			a = D[a].parent
		end
		if od.sigs.ChildRemoved then od.sigs.ChildRemoved:Fire(inst) end
	end
	d.parent = newParent
	if newParent then
		table.insert(D[newParent].children, inst)
	end
	markSpatialDirty(inst)
	firePropChanged(inst, "Parent")
	if d.sigs.AncestryChanged then d.sigs.AncestryChanged:Fire(inst, newParent) end
	for _, x in ipairs(descendants(inst)) do
		local s = D[x].sigs.AncestryChanged
		if s then s:Fire(inst, newParent) end
	end
	local nowIn = inGame(inst)
	if nowIn ~= wasIn then
		local all = { inst }
		for _, x in ipairs(descendants(inst)) do table.insert(all, x) end
		for _, x in ipairs(all) do
			for tag in pairs(D[x].tags) do
				if nowIn then
					TAGGED[tag] = TAGGED[tag] or {}
					if TAG_ADDED[tag] then TAG_ADDED[tag]:Fire(x) end
				else
					if TAG_REMOVED[tag] then TAG_REMOVED[tag]:Fire(x) end
				end
			end
		end
	end
	if newParent then
		local nd = D[newParent]
		if nd.sigs.ChildAdded then nd.sigs.ChildAdded:Fire(inst) end
		local a = newParent
		local added = { inst }
		for _, x in ipairs(descendants(inst)) do table.insert(added, x) end
		while a do
			local s = D[a].sigs.DescendantAdded
			if s then for _, x in ipairs(added) do s:Fire(x) end end
			a = D[a].parent
		end
	end
end

-- property type checks on assignment
local function tcheck(inst, k, v)
	local d = D[inst]
	local cls = d.class
	local want
	if isA(cls, "BasePart") then
		want = ({ Position = "Vector3", Size = "Vector3", CFrame = "CFrame", Orientation = "Vector3", Color = "Color3", Transparency = "number",
			Anchored = "boolean", CanCollide = "boolean", CanTouch = "boolean", CanQuery = "boolean", Reflectance = "number", Rotation = "Vector3",
			AssemblyLinearVelocity = "Vector3", Massless = "boolean", CastShadow = "boolean", BrickColor = "BrickColor" })[k]
	elseif isA(cls, "GuiObject") then
		want = ({ Position = "UDim2", Size = "UDim2", AnchorPoint = "Vector2", BackgroundColor3 = "Color3", TextColor3 = "Color3", BackgroundTransparency = "number",
			Visible = "boolean", ZIndex = "number", FontFace = "Font", ImageColor3 = "Color3", TextSize = "number", Rotation = "number",
			TextTransparency = "number", ImageTransparency = "number", TextStrokeColor3 = "Color3", TextStrokeTransparency = "number", LayoutOrder = "number",
			CanvasSize = "UDim2", CanvasPosition = "Vector2", GroupTransparency = "number", BorderSizePixel = "number", TextScaled = "boolean", TextWrapped = "boolean",
			RichText = "boolean", Image = "string", ScrollBarThickness = "number", ClipsDescendants = "boolean" })[k]
		if k == "Text" and type(v) ~= "string" and type(v) ~= "number" then error("Unable to assign property Text. string expected, got " .. mtypeof(v), 3) end
	elseif cls == "BillboardGui" then
		want = ({ Size = "UDim2", StudsOffset = "Vector3", StudsOffsetWorldSpace = "Vector3", MaxDistance = "number", AlwaysOnTop = "boolean" })[k]
	elseif cls == "SurfaceGui" then
		want = ({ CanvasSize = "Vector2", PixelsPerStud = "number", LightInfluence = "number", AlwaysOnTop = "boolean" })[k]
	elseif cls == "Attachment" then
		want = ({ Position = "Vector3", CFrame = "CFrame", WorldPosition = "Vector3", Orientation = "Vector3" })[k]
	elseif isA(cls, "Light") then
		want = ({ Color = "Color3", Brightness = "number", Range = "number", Angle = "number", Enabled = "boolean", Shadows = "boolean" })[k]
	elseif cls == "Humanoid" then
		want = ({ WalkSpeed = "number", Health = "number", MaxHealth = "number", JumpPower = "number", JumpHeight = "number", HipHeight = "number", DisplayName = "string" })[k]
	elseif cls == "ProximityPrompt" then
		want = ({ HoldDuration = "number", MaxActivationDistance = "number", ActionText = "string", ObjectText = "string", Enabled = "boolean",
			RequiresLineOfSight = "boolean", UIOffset = "Vector2" })[k]
	elseif cls == "Highlight" then
		want = ({ FillColor = "Color3", OutlineColor = "Color3", FillTransparency = "number", OutlineTransparency = "number" })[k]
	elseif cls == "ParticleEmitter" or cls == "Trail" or cls == "Beam" then
		want = ({ Color = "ColorSequence", Transparency = "NumberSequence", Size = "NumberSequence", Lifetime = cls == "ParticleEmitter" and "NumberRange" or "number",
			Speed = "NumberRange", Rate = "number", SpreadAngle = "Vector2", Rotation = "NumberRange", RotSpeed = "NumberRange", Acceleration = "Vector3", WidthScale = "NumberSequence" })[k]
	elseif cls == "UIStroke" then
		want = ({ Color = "Color3", Thickness = "number", Transparency = "number" })[k]
	elseif cls == "UIGradient" then
		want = ({ Color = "ColorSequence", Transparency = "NumberSequence", Rotation = "number", Offset = "Vector2" })[k]
	elseif cls == "UICorner" then
		want = ({ CornerRadius = "UDim" })[k]
	elseif cls == "UIListLayout" then
		want = ({ Padding = "UDim" })[k]
	elseif cls == "UIGridLayout" then
		want = ({ CellSize = "UDim2", CellPadding = "UDim2" })[k]
	elseif cls == "UIPadding" then
		want = ({ PaddingTop = "UDim", PaddingBottom = "UDim", PaddingLeft = "UDim", PaddingRight = "UDim" })[k]
	elseif cls == "Sound" then
		want = ({ Volume = "number", SoundId = "string", Looped = "boolean", PlaybackSpeed = "number" })[k]
	elseif cls == "Camera" then
		want = ({ CFrame = "CFrame", FieldOfView = "number", Focus = "CFrame" })[k]
	elseif cls == "Model" then
		if k == "PrimaryPart" and v ~= nil and not (mtypeof(v) == "Instance" and isA(D[v].class, "BasePart")) then error("PrimaryPart must be a BasePart", 3) end
	end
	if want and v ~= nil and mtypeof(v) ~= want then
		error(string.format("Unable to assign property %s. %s expected, got %s (on %s %s)", k, want, mtypeof(v), cls, tostring(d.props.Name)), 3)
	end
	-- enum-valued properties
	local cur = defaultFor(cls, k)
	if cur ~= nil and cur ~= NILV and mtypeof(cur) == "EnumItem" then
		if type(v) == "string" then
			local ok = pcall(function() return cur.EnumType[v] end)
			if not ok then error("Unable to assign property " .. k .. ": '" .. v .. "' is not a valid " .. cur.EnumType.Name, 3) end
		elseif type(v) == "number" then
		elseif mtypeof(v) ~= "EnumItem" or v.EnumType ~= cur.EnumType then
			error("Unable to assign property " .. k .. ". EnumItem of type " .. cur.EnumType.Name .. " expected, got " .. (mtypeof(v) == "EnumItem" and tostring(v) or mtypeof(v)), 3)
		end
	end
	if k == "Material" and isA(cls, "BasePart") and mtypeof(v) == "EnumItem" and v.EnumType ~= Enum.Material then
		error("Unable to assign property Material: got " .. tostring(v), 3)
	end
	if (k == "Font") and isA(cls, "GuiObject") and mtypeof(v) == "EnumItem" and v.EnumType ~= Enum.Font then
		error("Unable to assign property Font: got " .. tostring(v), 3)
	end
	if (k == "Adornee" or k == "Part0" or k == "Part1" or k == "Attachment0" or k == "Attachment1" or k == "CameraSubject" or k == "PrimaryPart") and v ~= nil and mtypeof(v) ~= "Instance" then
		error("Unable to assign property " .. k .. ". Instance expected, got " .. mtypeof(v), 3)
	end
	if type(v) == "number" and v ~= v then
		logOnce("warns", "NAN:" .. cls .. k, "NaN assigned to " .. cls .. "." .. k .. " @ " .. (debug.info(3, "s") or "?") .. ":" .. (debug.info(3, "l") or "?"))
	end
end

function callerLoc(level)
	local s, l = debug.info(level + 1, "sl")
	return tostring(s) .. ":" .. tostring(l)
end

IMT.__index = function(inst, k)
	HANG += 1
	if HANG == 3000000 or HANG == 6000000 then hangTick() HANG -= 1 end
	local d = D[inst]
	if d == nil then error("attempt to index destroyed mock instance", 2) end
	local props = d.props
	if d.cprops and curCtx().mode == "client" then
		local cv = d.cprops[k]
		if cv ~= nil then if cv == NILV then return nil end return cv end
	end
	local v = props[k]
	if v ~= nil then return v end
	local cls = d.class
	-- computed props
	if k == "ClassName" then return cls end
	if k == "Parent" then return d.parent end
	if isA(cls, "BasePart") then
		if k == "Position" then return props.CFrame.Position end
		if k == "Orientation" or k == "Rotation" then local rx, ry, rz = props.CFrame:ToOrientation() return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz)) end
		if k == "Mass" or k == "AssemblyMass" then local s = props.Size return s.X * s.Y * s.Z * 0.7 end
		if k == "AssemblyRootPart" then return inst end
		if k == "ExtentsSize" then return props.Size end
	end
	if cls == "Attachment" then
		if k == "Position" then return props.CFrame.Position end
		if k == "WorldPosition" or k == "WorldCFrame" then
			local p = d.parent
			local base = (p and isA(D[p].class, "BasePart")) and D[p].props.CFrame or CFrame.identity
			local w = base * props.CFrame
			return k == "WorldPosition" and w.Position or w
		end
		if k == "Orientation" then return Vector3.zero end
	end
	if cls == "Humanoid" then
		if k == "RootPart" then local p = d.parent return p and p:FindFirstChild("HumanoidRootPart") end
	end
	if isA(cls, "Model") and k == "WorldPivot" then return inst:GetPivot() end
	if (cls == "TextLabel" or cls == "TextButton" or cls == "TextBox") and k == "ContentText" then return tostring(props.Text or defaultFor(cls, "Text")) end
	local m = methodFor(cls, k)
	if m then return m end
	for _, c in ipairs(d.children) do
		if D[c].props.Name == k then return c end
	end
	if isEvent(cls, k) then return getSig(inst, k) end
	local dv = defaultFor(cls, k)
	if dv ~= nil then
		if dv == NILV then return nil end
		return dv
	end
	if PERMISSIVE[cls] then return nil end
	local loc = callerLoc(2)
	logOnce("unknown", "U:" .. cls .. "." .. k .. "@" .. loc, string.format("%s.%s (name=%s) read @ %s", cls, tostring(k), tostring(props.Name), loc))
	error(tostring(k) .. " is not a valid member of " .. cls .. " \"" .. inst:GetFullName() .. "\"", 2)
end

IMT.__newindex = function(inst, k, v)
	local d = D[inst]
	if k == "Parent" then setParent(inst, v) return end
	if k == "ClassName" then error("ClassName is read-only", 2) end
	if type(k) ~= "string" then error("bad property key", 2) end
	local cls = d.class
	if k == "Name" then
		if type(v) ~= "string" and type(v) ~= "number" then error("Unable to assign property Name. string expected, got " .. mtypeof(v), 2) end
		d.props.Name = tostring(v); firePropChanged(inst, k) return
	end
	-- unknown property writes: flag them (Roblox errors "X is not a valid member")
	if defaultFor(cls, k) == nil and not PERMISSIVE[cls] and methodFor(cls, k) == nil then
		local known = { Size = 1, CFrame = 1, Position = 1, Orientation = 1, Rotation = 1, Value = 1, Focus = 1, Text = 1, WorldPosition = 1, WorldCFrame = 1 }
		if not known[k] and not (d.props[k] ~= nil) then
			local loc = callerLoc(2)
			logOnce("unknown", "W:" .. cls .. "." .. k .. "@" .. loc, string.format("WRITE %s.%s = %s (name=%s) @ %s", cls, k, mtypeof(v), tostring(d.props.Name), loc))
		end
	end
	tcheck(inst, k, v)
	if d.owner == "server" and curCtx().mode == "client" and k ~= "Parent" then
		-- client write to a replicated instance: only this client sees it
		d.cprops = d.cprops or {}
		if v == nil then d.cprops[k] = NILV else d.cprops[k] = v end
		firePropChanged(inst, k)
		return
	end
	if isA(cls, "BasePart") then
		if k == "Position" then
			local c = d.props.CFrame
			d.props.CFrame = CFrame.new(v) * c.Rotation
			NAN_CHECK(d.props.CFrame, inst)
			markSpatialDirty(inst); firePropChanged(inst, "Position"); firePropChanged(inst, "CFrame") return
		elseif k == "Orientation" or k == "Rotation" then
			local p = d.props.CFrame.Position
			d.props.CFrame = CFrame.new(p) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
			markSpatialDirty(inst); firePropChanged(inst, k) return
		elseif k == "CFrame" or k == "Size" then
			if k == "CFrame" then NAN_CHECK(v, inst) v = v:Orthonormalize() end
			d.props[k] = v; markSpatialDirty(inst); firePropChanged(inst, k)
			if k == "CFrame" then firePropChanged(inst, "Position") end
			return
		end
	end
	if cls == "Attachment" then
		if k == "Position" then d.props.CFrame = CFrame.new(v) * d.props.CFrame.Rotation return end
		if k == "WorldPosition" then
			local p = d.parent
			local base = (p and isA(D[p].class, "BasePart")) and D[p].props.CFrame or CFrame.identity
			d.props.CFrame = CFrame.new(base:PointToObjectSpace(v)) return
		end
		if k == "WorldCFrame" then
			local p = d.parent
			local base = (p and isA(D[p].class, "BasePart")) and D[p].props.CFrame or CFrame.identity
			d.props.CFrame = base:Inverse() * v return
		end
		if k == "Orientation" then d.props.CFrame = CFrame.new(d.props.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)) return end
	end
	if isA(cls, "Model") and k == "WorldPivot" then d.props._pivot = v return end
	if cls == "Humanoid" and k == "Health" then
		local old = d.props.Health or 100
		local mx = d.props.MaxHealth or 100
		v = math.clamp(v, 0, mx)
		d.props.Health = v
		firePropChanged(inst, k)
		if d.sigs.HealthChanged then d.sigs.HealthChanged:Fire(v) end
		if v <= 0 and old > 0 then getSig(inst, "Died"):Fire() end
		return
	end
	if cls == "Sound" and k == "Playing" then
		d.props.Playing = v; d.props.IsPlaying = v; return
	end
	d.props[k] = v
	firePropChanged(inst, k)
end
IMT.__tostring = function(inst) return D[inst].props.Name end

-- ── Instance methods ──
local IM = {}
METHODS.Instance = IM
function IM.FindFirstChild(self, name, recursive)
	if type(name) ~= "string" then error("FindFirstChild: string expected, got " .. mtypeof(name), 2) end
	for _, c in ipairs(D[self].children) do if D[c].props.Name == name then return c end end
	if recursive then
		for _, c in ipairs(descendants(self)) do if D[c].props.Name == name then return c end end
	end
	return nil
end
function IM.FindFirstChildOfClass(self, cls)
	for _, c in ipairs(D[self].children) do if D[c].class == cls then return c end end
	return nil
end
function IM.FindFirstChildWhichIsA(self, cls, recursive)
	for _, c in ipairs(D[self].children) do if isA(D[c].class, cls) then return c end end
	if recursive then for _, c in ipairs(descendants(self)) do if isA(D[c].class, cls) then return c end end end
	return nil
end
function IM.FindFirstDescendant(self, name) return IM.FindFirstChild(self, name, true) end
function IM.FindFirstAncestor(self, name)
	local p = D[self].parent
	while p do if D[p].props.Name == name then return p end p = D[p].parent end
	return nil
end
function IM.FindFirstAncestorOfClass(self, cls)
	local p = D[self].parent
	while p do if D[p].class == cls then return p end p = D[p].parent end
	return nil
end
function IM.FindFirstAncestorWhichIsA(self, cls)
	local p = D[self].parent
	while p do if isA(D[p].class, cls) then return p end p = D[p].parent end
	return nil
end
function IM.WaitForChild(self, name, timeout)
	if type(name) ~= "string" then error("WaitForChild: string expected", 2) end
	local c = IM.FindFirstChild(self, name)
	if c then return c end
	local start = SCHED.now
	local warned = false
	while true do
		task.wait(0.1)
		c = IM.FindFirstChild(self, name)
		if c then return c end
		if timeout and SCHED.now - start >= timeout then return nil end
		if not timeout and not warned and SCHED.now - start > 5 then
			warned = true
			logOnce("warns", "WFC:" .. self:GetFullName() .. "." .. name, "Infinite yield possible on '" .. self:GetFullName() .. ":WaitForChild(\"" .. name .. "\")' @ " .. callerLoc(2))
		end
	end
end
function IM.GetChildren(self) return table.clone(D[self].children) end
function IM.GetDescendants(self) return descendants(self) end
function IM.IsA(self, cls) return isA(D[self].class, cls) end
function IM.IsDescendantOf(self, anc)
	if anc == nil then error("IsDescendantOf: argument nil", 2) end
	return isDescendantOf(self, anc)
end
function IM.IsAncestorOf(self, desc) return isDescendantOf(desc, self) end
function IM.GetFullName(self)
	local parts = {}
	local x = self
	while x and x ~= GAME do table.insert(parts, 1, D[x].props.Name) x = D[x].parent end
	return table.concat(parts, ".")
end
function IM.Destroy(self)
	local d = D[self]
	if d.destroyed then return end
	if d.sigs.Destroying then d.sigs.Destroying:Fire() end
	for _, c in ipairs(table.clone(d.children)) do IM.Destroy(c) end
	if d.parent then setParent(self, nil) end
	d.locked = true
	d.destroyed = true
	for _, s in pairs(d.sigs) do s:DisconnectAll() end
	for _, s in pairs(d.propSigs) do s:DisconnectAll() end
end
IM.Remove = function(self) setParent(self, nil) end
function IM.ClearAllChildren(self) for _, c in ipairs(table.clone(D[self].children)) do IM.Destroy(c) end end
function IM.Clone(self)
	local d = D[self]
	if d.props.Archivable == false then return nil end
	local c = setmetatable({}, IMT)
	local nd = { class = d.class, props = table.clone(d.props), children = {}, attrs = table.clone(d.attrs), tags = table.clone(d.tags), sigs = {}, propSigs = {}, attrSigs = {} }
	D[c] = nd
	for _, ch in ipairs(d.children) do
		local cc = IM.Clone(ch)
		if cc then D[cc].parent = c table.insert(nd.children, cc) end
	end
	-- remap PrimaryPart
	if d.props.PrimaryPart then
		local idx
		local desc = descendants(self)
		for i, x in ipairs(desc) do if x == d.props.PrimaryPart then idx = i end end
		nd.props.PrimaryPart = idx and descendants(c)[idx] or nil
	end
	return c
end
local ATTR_OK = { ["nil"] = true, boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true, Rect = true, Font = true, EnumItem = true }
function IM.SetAttribute(self, name, v)
	if type(name) ~= "string" then error("SetAttribute: attribute name must be a string", 2) end
	if not name:match("^[%w_]+$") or #name > 100 or name:sub(1, 3) == "RBX" then error("SetAttribute: invalid attribute name '" .. name .. "'", 2) end
	local t = mtypeof(v)
	if not ATTR_OK[t] then error("SetAttribute: " .. t .. " is not a supported attribute type (attribute '" .. name .. "' on " .. D[self].props.Name .. ")", 2) end
	local d = D[self]
	if d.owner == "server" and curCtx().mode == "client" then
		d.cattrs = d.cattrs or {}
		d.cattrs[name] = v == nil and NILV or v
		local s = d.attrSigs[name]
		if s then s:Fire() end
		return
	end
	if d.attrs[name] == v then return end
	d.attrs[name] = v
	local s = d.attrSigs[name]
	if s then s:Fire() end
	if d.sigs.AttributeChanged then d.sigs.AttributeChanged:Fire(name) end
end
function IM.GetAttribute(self, name)
	if type(name) ~= "string" then error("GetAttribute: string expected", 2) end
	local d = D[self]
	if d.cattrs and curCtx().mode == "client" then
		local cv = d.cattrs[name]
		if cv ~= nil then if cv == NILV then return nil end return cv end
	end
	return d.attrs[name]
end
function IM.GetAttributes(self) return table.clone(D[self].attrs) end
function IM.GetAttributeChangedSignal(self, name)
	local d = D[self]
	local s = d.attrSigs[name]
	if not s then s = Signal.new("attr:" .. name) d.attrSigs[name] = s end
	return s
end
function IM.GetPropertyChangedSignal(self, name)
	local d = D[self]
	-- validate name exists
	local ok = pcall(function() return self[name] end)
	if not ok then error("GetPropertyChangedSignal: " .. tostring(name) .. " is not a valid property name of " .. d.class, 2) end
	local s = d.propSigs[name]
	if not s then s = Signal.new("prop:" .. name) d.propSigs[name] = s end
	return s
end
function IM.AddTag(self, tag) CollectionServiceImpl.AddTag(nil, self, tag) end
function IM.RemoveTag(self, tag) CollectionServiceImpl.RemoveTag(nil, self, tag) end
function IM.HasTag(self, tag) return D[self].tags[tag] == true end
function IM.GetTags(self) local t = {} for k in pairs(D[self].tags) do table.insert(t, k) end return t end
function IM.GetActor() return nil end
function IM.GetDebugId(self) return tostring(self) end

-- ── PVInstance / BasePart / Model ──
local PV = {}
METHODS.PVInstance = PV
local BP = {}
METHODS.BasePart = BP
function BP.GetPivot(self) return D[self].props.CFrame end
function BP.PivotTo(self, c)
	if not isCF(c) then error("PivotTo: CFrame expected, got " .. mtypeof(c), 2) end
	NAN_CHECK(c, self)
	self.CFrame = c
end
function BP.SetNetworkOwner(self, p)
	if D[self].props.Anchored then error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts (" .. self:GetFullName() .. ")", 2) end
	if p ~= nil and not (mtypeof(p) == "Instance" and D[p].class == "Player") then error("SetNetworkOwner: Player expected", 2) end
	if not inGame(self) then error("SetNetworkOwner: part must be a descendant of Workspace", 2) end
end
function BP.SetNetworkOwnershipAuto(self) end
function BP.GetNetworkOwner() return nil end
function BP.CanSetNetworkOwnership(self) return not D[self].props.Anchored end
function BP.GetTouchingParts(self) return {} end
function BP.GetConnectedParts(self) return { self } end
function BP.GetJoints() return {} end
function BP.GetMass(self) return self.Mass end
function BP.ApplyImpulse() end
function BP.ApplyAngularImpulse() end
function BP.BreakJoints() end
function BP.GetVelocityAtPosition() return Vector3.zero end
function BP.GetRootPart(self) return self end
function BP.GetClosestPointOnSurface(self, p) return p end
function BP.SubtractAsync(self) return self:Clone() end
function BP.UnionAsync(self) return self:Clone() end
local MD = {}
METHODS.Model = MD
local function modelParts(m)
	local out = {}
	for _, x in ipairs(descendants(m)) do if isA(D[x].class, "BasePart") then table.insert(out, x) end end
	return out
end
function aabbOf(parts)
	local mn, mx
	for _, p in ipairs(parts) do
		local c, s = D[p].props.CFrame, D[p].props.Size
		local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
		local ex = math.abs(c[4]) * hx + math.abs(c[5]) * hy + math.abs(c[6]) * hz
		local ey = math.abs(c[7]) * hx + math.abs(c[8]) * hy + math.abs(c[9]) * hz
		local ez = math.abs(c[10]) * hx + math.abs(c[11]) * hy + math.abs(c[12]) * hz
		local lo = Vector3.new(c[1] - ex, c[2] - ey, c[3] - ez)
		local hi = Vector3.new(c[1] + ex, c[2] + ey, c[3] + ez)
		mn = mn and mn:Min(lo) or lo
		mx = mx and mx:Max(hi) or hi
	end
	return mn, mx
end
function MD.GetPivot(self)
	local d = D[self]
	if d.props.PrimaryPart then return D[d.props.PrimaryPart].props.CFrame end
	if d.props._pivot then return d.props._pivot end
	local mn, mx = aabbOf(modelParts(self))
	if not mn then return CFrame.identity end
	return CFrame.new((mn + mx) / 2)
end
function MD.PivotTo(self, c)
	if not isCF(c) then error("PivotTo: CFrame expected, got " .. mtypeof(c), 2) end
	NAN_CHECK(c, self)
	local old = MD.GetPivot(self)
	local delta = c * old:Inverse()
	for _, p in ipairs(modelParts(self)) do
		local before = D[p].props.CFrame
		D[p].props.CFrame = (delta * D[p].props.CFrame):Orthonormalize()
		local q = D[p].props.CFrame.Position
		if q.X ~= q.X and not NAN_DUMPED then NAN_DUMPED = true print("[NAN-PIVOT] model " .. self:GetFullName() .. " part " .. p.Name .. "\n  c=" .. tostring(c) .. "\n  old=" .. tostring(old) .. "\n  before=" .. tostring(before) .. "\n  primary=" .. tostring(D[self].props.PrimaryPart and D[self].props.PrimaryPart.Name) .. " _pivot=" .. tostring(D[self].props._pivot)) end
		NAN_CHECK(D[p].props.CFrame, p)
		firePropChanged(p, "CFrame")
	end
	markSpatialDirty(self)
	D[self].props._pivot = c
end
function MD.SetPrimaryPartCFrame(self, c)
	if not D[self].props.PrimaryPart then error("Model:SetPrimaryPartCFrame() failed because no PrimaryPart has been set", 2) end
	MD.PivotTo(self, c)
end
function MD.GetPrimaryPartCFrame(self)
	local pp = D[self].props.PrimaryPart
	return pp and D[pp].props.CFrame or CFrame.identity
end
function MD.GetBoundingBox(self)
	local mn, mx = aabbOf(modelParts(self))
	if not mn then return MD.GetPivot(self), Vector3.zero end
	return CFrame.new((mn + mx) / 2), mx - mn
end
function MD.GetExtentsSize(self)
	local mn, mx = aabbOf(modelParts(self))
	if not mn then return Vector3.zero end
	return mx - mn
end
function MD.GetScale(self) return D[self].props._scale or 1 end
function MD.ScaleTo(self, s)
	if type(s) ~= "number" or s <= 0 then error("ScaleTo: positive number expected", 2) end
	local old = MD.GetScale(self)
	local f = s / old
	local piv = MD.GetPivot(self)
	for _, p in ipairs(modelParts(self)) do
		local pd = D[p].props
		local rel = piv:ToObjectSpace(pd.CFrame)
		pd.CFrame = piv * (rel.Rotation + rel.Position * f)
		pd.Size = pd.Size * f
	end
	D[self].props._scale = s
end
function MD.MoveTo(self, pos) MD.PivotTo(self, CFrame.new(pos)) end
function MD.TranslateBy(self, v) MD.PivotTo(self, MD.GetPivot(self) + v) end
function MD.BreakJoints() end
function MD.MakeJoints() end
function MD.GetModelCFrame(self) return MD.GetPivot(self) end
function MD.GetModelSize(self) return MD.GetExtentsSize(self) end
function MD.AddPersistentPlayer() end

-- ── spatial grid (static parts hashed once, moved/added parts kept in DYN) ──
local CELL = 24
local GRID = nil
local DYN = {}
function markSpatialDirty(inst)
	if not GRID or inst == nil then return end
	local d = D[inst]
	if isA(d.class, "BasePart") then DYN[inst] = true end
	for _, x in ipairs(descendants(inst)) do if isA(D[x].class, "BasePart") then DYN[x] = true end end
end
local function ckey(ix, iz) return ix * 100000 + iz end
local function buildGrid()
	GRID = {}
	DYN = {}
	for _, p in ipairs(descendants(WORKSPACE)) do
		if isA(D[p].class, "BasePart") then
			local mn, mx = aabbOf({ p })
			if (mx - mn).Magnitude > 2000 then DYN[p] = true else
				for ix = math.floor(mn.X / CELL), math.floor(mx.X / CELL) do
					for iz = math.floor(mn.Z / CELL), math.floor(mx.Z / CELL) do
						local k = ckey(ix, iz)
						local c = GRID[k]
						if not c then c = {} GRID[k] = c end
						table.insert(c, p)
					end
				end
			end
		end
	end
end
local function inWorkspace(p) return not D[p].destroyed and isDescendantOf(p, WORKSPACE) end
local function candidatesBox(mn, mx)
	if not GRID then buildGrid() end
	local out, seen = {}, {}
	if (mx.X - mn.X) > 4000 or (mx.Z - mn.Z) > 4000 or mx.X ~= mx.X then
		logOnce("warns", "BIGBOX" .. callerLoc(3), "huge spatial box query " .. tostring(mn) .. " .. " .. tostring(mx) .. " @ " .. callerLoc(3))
		mn = Vector3.new(math.max(mn.X, -2000), mn.Y, math.max(mn.Z, -2000)); mx = Vector3.new(math.min(mx.X, 2000), mx.Y, math.min(mx.Z, 2000))
	end
	for ix = math.floor(mn.X / CELL), math.floor(mx.X / CELL) do
		for iz = math.floor(mn.Z / CELL), math.floor(mx.Z / CELL) do
			for _, p in ipairs(GRID[ckey(ix, iz)] or {}) do
				if not seen[p] and not DYN[p] then seen[p] = true table.insert(out, p) end
			end
		end
	end
	for p in pairs(DYN) do
		if not seen[p] then
			if D[p].destroyed then DYN[p] = nil elseif inWorkspace(p) then seen[p] = true table.insert(out, p) end
		end
	end
	return out
end
local function candidatesRay(origin, dir)
	if not GRID then buildGrid() end
	local out, seen, cells = {}, {}, {}
	local len = dir.Magnitude
	if len > 5000 or len ~= len then
		logOnce("warns", "BIGRAY" .. callerLoc(3), "huge raycast length " .. tostring(len) .. " @ " .. callerLoc(3))
		if len ~= len then return {} end
		dir = dir.Unit * 5000 len = 5000
	end
	local steps = math.max(1, math.ceil(len / (CELL / 3)))
	for i = 0, steps do
		local q = origin + dir * (i / steps)
		for dx = -1, 1 do for dz = -1, 1 do
			cells[ckey(math.floor(q.X / CELL) + dx, math.floor(q.Z / CELL) + dz)] = true
		end end
	end
	for k in pairs(cells) do
		for _, p in ipairs(GRID[k] or {}) do
			if not seen[p] and not DYN[p] then seen[p] = true table.insert(out, p) end
		end
	end
	for p in pairs(DYN) do
		if not seen[p] then
			if D[p].destroyed then DYN[p] = nil elseif inWorkspace(p) then seen[p] = true table.insert(out, p) end
		end
	end
	return out
end
local function worldParts()
	local out = {}
	for _, x in ipairs(descendants(WORKSPACE)) do if isA(D[x].class, "BasePart") then table.insert(out, x) end end
	return out
end
local function filtered(params)
	local list = params and params.FilterDescendantsInstances or {}
	local ftype = params and params.FilterType
	local include = ftype == Enum.RaycastFilterType.Include or ftype == Enum.RaycastFilterType.Whitelist
	return function(p)
		local inList = false
		for _, f in ipairs(list) do
			if p == f or isDescendantOf(p, f) then inList = true break end
		end
		if include then return inList end
		return not inList
	end
end
local function checkParams(params, kind, lvl)
	if params == nil then return end
	local t = mtypeof(params)
	if kind == "ray" and t ~= "RaycastParams" then error("Raycast: RaycastParams expected, got " .. t, lvl) end
	if kind == "overlap" and t ~= "OverlapParams" then error("Overlap query: OverlapParams expected, got " .. t, lvl) end
	for i, f in ipairs(params.FilterDescendantsInstances or {}) do
		if mtypeof(f) ~= "Instance" then error("FilterDescendantsInstances[" .. i .. "] is not an Instance (" .. mtypeof(f) .. ")", lvl) end
	end
end
RAYCAST_MODE = "obb"   -- "none" = never hits; "obb" = real ray-vs-box
-- shape of a part for precise queries: "block" | "cyl" | "ball" | "wedge"
function partShape(p)
	local d = D[p]
	if d.class == "WedgePart" then return "wedge" end
	local sh = d.props.Shape
	if sh == Enum.PartType.Cylinder then return "cyl" end
	if sh == Enum.PartType.Ball then return "ball" end
	if sh == Enum.PartType.Wedge then return "wedge" end
	return "block"
end
-- is a point (in PART-LOCAL space) inside the part's real shape?
function localInShape(shape, l, h, eps)
	eps = eps or 0
	if math.abs(l.X) > h.X + eps or math.abs(l.Y) > h.Y + eps or math.abs(l.Z) > h.Z + eps then return false end
	if shape == "cyl" then
		local r = math.min(h.Y, h.Z)
		return l.Y * l.Y + l.Z * l.Z <= (r + eps) * (r + eps)
	elseif shape == "ball" then
		local r = math.min(h.X, h.Y, h.Z)
		return l.X * l.X + l.Y * l.Y + l.Z * l.Z <= (r + eps) * (r + eps)
	elseif shape == "wedge" then
		-- Roblox wedge: full height at the back (+Z), slope down to the front (-Z)
		return l.Y / h.Y <= l.Z / h.Z + eps / math.min(h.Y, h.Z)
	end
	return true
end
local function rayOBB(origin, dir, p)
	local pd = D[p].props
	local inv = pd.CFrame:Inverse()
	local o = inv * origin
	local dv = inv.Rotation * dir
	local h = pd.Size / 2
	local tmin, tmax = 0, 1
	for _, ax in ipairs({ "X", "Y", "Z" }) do
		local oo, dd, hh = o[ax], dv[ax], h[ax]
		if math.abs(dd) < 1e-9 then
			if oo < -hh or oo > hh then return nil end
		else
			local t1, t2 = (-hh - oo) / dd, (hh - oo) / dd
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin = math.max(tmin, t1); tmax = math.min(tmax, t2)
			if tmin > tmax then return nil end
		end
	end
	local shape = partShape(p)
	-- Roblox: a ray that STARTS inside a part never hits that part
	if localInShape(shape, o, h, -1e-6) then return nil end
	if shape == "block" then return tmin end
	-- round / sloped shapes: march the clipped segment (exact enough for the mock)
	local n = math.max(8, math.ceil((tmax - tmin) * dir.Magnitude / 0.05))
	n = math.min(n, 4000)
	for i = 0, n do
		local t = tmin + (tmax - tmin) * i / n
		if localInShape(shape, o + dv * t, h, 1e-6) then return t end
	end
	return nil
end
-- SAT overlap of two oriented boxes
function obbOverlap(cfA, hA, cfB, hB)
	local ax = { cfA.RightVector, cfA.UpVector, -cfA.LookVector }
	local bx = { cfB.RightVector, cfB.UpVector, -cfB.LookVector }
	local ha = { hA.X, hA.Y, hA.Z }
	local hb = { hB.X, hB.Y, hB.Z }
	local T = cfB.Position - cfA.Position
	local axes = {}
	for i = 1, 3 do table.insert(axes, ax[i]) table.insert(axes, bx[i]) end
	for i = 1, 3 do for j = 1, 3 do
		local c = ax[i]:Cross(bx[j])
		if c.Magnitude > 1e-6 then table.insert(axes, c.Unit) end
	end end
	for _, L in ipairs(axes) do
		local ra, rb = 0, 0
		for i = 1, 3 do ra += ha[i] * math.abs(ax[i]:Dot(L)) rb += hb[i] * math.abs(bx[i]:Dot(L)) end
		if math.abs(T:Dot(L)) > ra + rb then return false end
	end
	return true
end
-- world AABB of a part (what Roblox's GetPartBoundsIn* compares against)
function partAABB(p)
	local cf, s = D[p].props.CFrame, D[p].props.Size / 2
	local r = cf.Rotation
	local ex = Vector3.new(
		math.abs(r.RightVector.X) * s.X + math.abs(r.UpVector.X) * s.Y + math.abs(r.LookVector.X) * s.Z,
		math.abs(r.RightVector.Y) * s.X + math.abs(r.UpVector.Y) * s.Y + math.abs(r.LookVector.Y) * s.Z,
		math.abs(r.RightVector.Z) * s.X + math.abs(r.UpVector.Z) * s.Y + math.abs(r.LookVector.Z) * s.Z)
	return cf.Position - ex, cf.Position + ex
end
-- PRECISE: does the part's real shape overlap the oriented box (cf, size)?
function partHitsBox(p, cf0, size, eps)
	local pd = D[p].props
	local h = pd.Size / 2
	if not obbOverlap(pd.CFrame, h, cf0, size / 2) then return false end
	local shape = partShape(p)
	if shape == "block" then return true end
	-- sample the part-local sub-box that the query box's AABB covers
	local inv = pd.CFrame:Inverse()
	local qs = size / 2
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = -mn
	for _, dx in ipairs({ -1, 1 }) do for _, dy in ipairs({ -1, 1 }) do for _, dz in ipairs({ -1, 1 }) do
		local w = inv * (cf0 * Vector3.new(qs.X * dx, qs.Y * dy, qs.Z * dz))
		mn = Vector3.new(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
		mx = Vector3.new(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
	end end end
	mn = Vector3.new(math.max(mn.X, -h.X), math.max(mn.Y, -h.Y), math.max(mn.Z, -h.Z))
	mx = Vector3.new(math.min(mx.X, h.X), math.min(mx.Y, h.Y), math.min(mx.Z, h.Z))
	if mn.X > mx.X or mn.Y > mx.Y or mn.Z > mx.Z then return false end
	local N = 18
	local qinv = cf0:Inverse()
	for i = 0, N do for j = 0, N do for k = 0, N do
		local l = Vector3.new(mn.X + (mx.X - mn.X) * i / N, mn.Y + (mx.Y - mn.Y) * j / N, mn.Z + (mx.Z - mn.Z) * k / N)
		if localInShape(shape, l, h, eps or 1e-6) then
			local q = qinv * (pd.CFrame * l)
			if math.abs(q.X) <= qs.X and math.abs(q.Y) <= qs.Y and math.abs(q.Z) <= qs.Z then return true end
		end
	end end end
	return false
end
function partContainsPoint(p, pos, eps)
	local pd = D[p].props
	return localInShape(partShape(p), pd.CFrame:PointToObjectSpace(pos), pd.Size / 2, eps or 0)
end
TERRAIN_BLOCKS = {}
local function terrainMatAt(pt)
	local m = nil
	for _, b in ipairs(TERRAIN_BLOCKS) do
		local l = b.cf:PointToObjectSpace(pt)
		if math.abs(l.X) <= b.h.X and math.abs(l.Y) <= b.h.Y and math.abs(l.Z) <= b.h.Z then m = b.mat end
	end
	return m
end
function terrainRay(origin, dir, params)
	if #TERRAIN_BLOCKS == 0 then return nil end
	if params and params.FilterDescendantsInstances then
		local ok = true
		for _, f in ipairs(params.FilterDescendantsInstances) do if f == WORKSPACE.Terrain then ok = false end end
		local inc = params.FilterType == Enum.RaycastFilterType.Include
		if inc == ok then return nil end
	end
	local ts = {}
	for _, b in ipairs(TERRAIN_BLOCKS) do
		local inv = b.cf:Inverse()
		local o, dv = inv * origin, inv.Rotation * dir
		local tmin, tmax, miss = 0, 1, false
		for _, ax in ipairs({ "X", "Y", "Z" }) do
			local oo, dd, hh = o[ax], dv[ax], b.h[ax]
			if math.abs(dd) < 1e-9 then if oo < -hh or oo > hh then miss = true break end
			else
				local t1, t2 = (-hh - oo) / dd, (hh - oo) / dd
				if t1 > t2 then t1, t2 = t2, t1 end
				tmin = math.max(tmin, t1) tmax = math.min(tmax, t2)
				if tmin > tmax then miss = true break end
			end
		end
		if not miss then table.insert(ts, tmin) end
	end
	table.sort(ts)
	local eps = 1e-4 / math.max(dir.Magnitude, 1e-6)
	for _, t in ipairs(ts) do
		local m = terrainMatAt(origin + dir * (t + eps))
		if m and m ~= Enum.Material.Air and not (m == Enum.Material.Water and params and params.IgnoreWater) then return t, m end
	end
	return nil
end
function NAN_CHECK(c, inst)
	local comps = { c:GetComponents() }
	for _, x in ipairs(comps) do
		if x ~= x or x == math.huge or x == -math.huge then
			local tb = debug.traceback("", 3)
			logOnce("errors", "NAN:" .. tb:sub(1, 300), "NaN/inf CFrame written to " .. tostring(inst and inst:GetFullName()) .. " t=" .. SCHED.now .. " cf=" .. tostring(c) .. tb:sub(1, 700))
			return
		end
	end
end
local WR = {}
METHODS.WorldRoot = WR
function WR.Raycast(self, origin, dir, params)
	if not isV3(origin) or not isV3(dir) then error("Raycast: Vector3 origin/direction expected, got " .. mtypeof(origin) .. ", " .. mtypeof(dir), 2) end
	checkParams(params, "ray", 3)
	if RAYCAST_MODE == "none" then return nil end
	local ok = filtered(params)
	local best, bestT
	for _, p in ipairs(candidatesRay(origin, dir)) do
		local pd = D[p].props
		if pd.CanQuery ~= false and ok(p) and (not params or not params.RespectCanCollide or pd.CanCollide ~= false) then
			local t = rayOBB(origin, dir, p)
			if t and (not bestT or t < bestT) then best, bestT = p, t end
		end
	end
	-- terrain fill blocks (later fills win; Air carves)
	local tt, tmat = terrainRay(origin, dir, params)
	if tt and (not bestT or tt < bestT) then
		return { Instance = WORKSPACE.Terrain, Position = origin + dir * tt, Normal = Vector3.yAxis, Distance = dir.Magnitude * tt, Material = tmat }
	end
	if not best then return nil end
	return { Instance = best, Position = origin + dir * bestT, Normal = Vector3.yAxis, Distance = dir.Magnitude * bestT, Material = D[best].props.Material or Enum.Material.Plastic }
end
function WR.Blockcast(self, cf0, size, dir, params)
	if not isCF(cf0) or not isV3(size) or not isV3(dir) then error("Blockcast: bad args " .. mtypeof(cf0) .. "," .. mtypeof(size) .. "," .. mtypeof(dir), 2) end
	checkParams(params, "ray", 3)
	if RAYCAST_MODE == "none" then return nil end
	local ok = filtered(params)
	local len = dir.Magnitude
	if len < 1e-6 then return nil end
	local e = size.Magnitude / 2 + 0.5
	local a, b = cf0.Position, cf0.Position + dir
	local mn = Vector3.new(math.min(a.X, b.X) - e, math.min(a.Y, b.Y) - e, math.min(a.Z, b.Z) - e)
	local mx = Vector3.new(math.max(a.X, b.X) + e, math.max(a.Y, b.Y) + e, math.max(a.Z, b.Z) + e)
	local cands = {}
	for _, p in ipairs(candidatesBox(mn, mx)) do
		local pd = D[p].props
		if pd.CanQuery ~= false and ok(p) and (not params or not params.RespectCanCollide or pd.CanCollide ~= false) then
			-- Roblox: parts already overlapping the start shape are not hit
			if not partHitsBox(p, cf0, size) then table.insert(cands, p) end
		end
	end
	if #cands == 0 then return nil end
	local n = math.max(1, math.ceil(len / 0.1))
	for i = 1, n do
		local t = i / n
		local c = cf0 + dir * t
		for _, p in ipairs(cands) do
			if partHitsBox(p, c, size) then
				return { Instance = p, Position = c.Position, Normal = -dir.Unit, Distance = len * t, Material = D[p].props.Material or Enum.Material.Plastic }
			end
		end
	end
	return nil
end
function WR.Spherecast(self, pos, r, dir, params) return WR.Raycast(self, pos, dir, params) end
function WR.Shapecast() return nil end
local function inBox(p, cf0, size)
	local mn, mx = partAABB(p)
	return obbOverlap(CFrame.new((mn + mx) / 2), (mx - mn) / 2, cf0, size / 2)
end
function WR.GetPartBoundsInBox(self, cf0, size, params)
	if not isCF(cf0) or not isV3(size) then error("GetPartBoundsInBox: CFrame, Vector3 expected, got " .. mtypeof(cf0) .. ", " .. mtypeof(size), 2) end
	checkParams(params, "overlap", 3)
	local ok = filtered(params)
	local out = {}
	local e = size.Magnitude / 2
	for _, p in ipairs(candidatesBox(cf0.Position - Vector3.new(e, e, e), cf0.Position + Vector3.new(e, e, e))) do
		if D[p].props.CanQuery ~= false and ok(p) and inBox(p, cf0, size) then table.insert(out, p) end
	end
	return out
end
function WR.GetPartBoundsInRadius(self, pos, r, params)
	if not isV3(pos) or type(r) ~= "number" then error("GetPartBoundsInRadius: Vector3, number expected", 2) end
	checkParams(params, "overlap", 3)
	local ok = filtered(params)
	local out = {}
	for _, p in ipairs(candidatesBox(pos - Vector3.new(r, r, r), pos + Vector3.new(r, r, r))) do
		if D[p].props.CanQuery ~= false and ok(p) and (D[p].props.CFrame.Position - pos).Magnitude <= r + D[p].props.Size.Magnitude / 2 then table.insert(out, p) end
	end
	return out
end
function WR.GetPartsInPart(self, part, params)
	if mtypeof(part) ~= "Instance" or not isA(D[part].class, "BasePart") then error("GetPartsInPart: BasePart expected", 2) end
	checkParams(params, "overlap", 3)
	local r = WR.GetPartBoundsInBox(self, D[part].props.CFrame, D[part].props.Size, params)
	local out = {}
	for _, x in ipairs(r) do if x ~= part and partHitsBox(x, D[part].props.CFrame, D[part].props.Size) then table.insert(out, x) end end
	return out
end
function WR.FindPartOnRay() return nil, Vector3.zero end
function WR.FindPartOnRayWithIgnoreList() return nil, Vector3.zero end
function WR.FindPartsInRegion3() return {} end
function WR.ArePartsTouchingOthers() return false end
function WR.GetServerTimeNow() return BASE_TIME + SCHED.now end
function WR.BulkMoveTo(self, parts, cfs) for i, p in ipairs(parts) do p.CFrame = cfs[i] end end

-- ── Humanoid ──
local HM = {}
METHODS.Humanoid = HM
function HM.MoveTo(self, pos, part)
	if not isV3(pos) then error("Humanoid:MoveTo: Vector3 expected, got " .. mtypeof(pos), 2) end
	local d = D[self]
	d.moveSeq = (d.moveSeq or 0) + 1
	local seq = d.moveSeq
	d.props.WalkToPoint = pos
	local model = d.parent
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local from = root.Position
	local flat = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z)
	local speed = math.max(d.props.WalkSpeed or 16, 1)
	local dt = math.clamp(flat.Magnitude / speed, 0.05, 8)
	local reached = dt < 8
	task.delay(dt, function()
		if d.moveSeq ~= seq or d.destroyed then return end
		if root.Parent then
			local target = reached and Vector3.new(pos.X, from.Y, pos.Z) or from + flat.Unit * speed * 8
			local c = D[root].props.CFrame
			local rot = c.Rotation
			if d.props.AutoRotate ~= false and flat.Magnitude > 0.1 then rot = CFrame.lookAt(Vector3.zero, flat.Unit) end
			local delta = CFrame.new(target) * rot * c:Inverse()
			if model:IsA("Model") then model:PivotTo(delta * model:GetPivot()) end
		end
		if d.sigs.MoveToFinished then d.sigs.MoveToFinished:Fire(reached) end
	end)
end
function HM.Move(self, dir) end
function HM.TakeDamage(self, n) self.Health = self.Health - n end
function HM.ChangeState(self, s) D[self].state = s if D[self].sigs.StateChanged then D[self].sigs.StateChanged:Fire(nil, s) end end
function HM.GetState(self) return D[self].state or Enum.HumanoidStateType.Running end
function HM.SetStateEnabled(self, s, on)
	if mtypeof(s) ~= "EnumItem" or s.EnumType ~= Enum.HumanoidStateType then error("SetStateEnabled: HumanoidStateType expected", 2) end
	if type(on) ~= "boolean" then error("SetStateEnabled: boolean expected", 2) end
end
function HM.GetStateEnabled() return true end
function HM.LoadAnimation(self, anim)
	local animator = self:FindFirstChildOfClass("Animator")
	return METHODS.Animator.LoadAnimation(animator or newInstance("Animator"), anim)
end
function HM.GetPlayingAnimationTracks() return {} end
function HM.ApplyDescription(self, desc) if mtypeof(desc) ~= "Instance" then error("ApplyDescription: HumanoidDescription expected", 2) end end
HM.ApplyDescriptionReset = HM.ApplyDescription
function HM.GetAppliedDescription(self) return newInstance("HumanoidDescription") end
function HM.AddAccessory(self, acc)
	local char = D[self].parent
	local head = char and char:FindFirstChild("Head")
	local h = acc:FindFirstChild("Handle")
	if head and h then
		h.CFrame = head.CFrame * CFrame.new(0, 0, -0.6)
		h.CanCollide = false h.Massless = true
		local w = Instance.new("WeldConstraint") w.Part0 = head w.Part1 = h w.Parent = h
	end
	acc.Parent = char
end
function HM.RemoveAccessories(self) end
function HM.GetAccessories(self) return {} end
function HM.UnequipTools() end
function HM.EquipTool() end
function HM.BuildRigFromAttachments() end
function HM.GetLimb() return nil end
function HM.GetMoveVelocity() return Vector3.zero end
function HM.GetBodyPartR15() return nil end
function HM.ReplaceBodyPartR15() return true end
function HM.PlayEmote() return true end
METHODS.Animator = {
	LoadAnimation = function(self, anim)
		if mtypeof(anim) ~= "Instance" or D[anim].class ~= "Animation" then error("LoadAnimation requires an Animation object", 2) end
		local tr = newInstance("AnimationTrack")
		D[tr].props.Animation = anim
		return tr
	end,
	GetPlayingAnimationTracks = function() return {} end,
	ApplyJointVelocities = function() end,
}
METHODS.AnimationTrack = {
	Play = function(self) self.IsPlaying = true end,
	Stop = function(self) self.IsPlaying = false getSig(self, "Stopped"):Fire() end,
	AdjustSpeed = function(self, s) self.Speed = s end,
	AdjustWeight = function() end,
	GetMarkerReachedSignal = function(self, n) return getSig(self, "marker:" .. n) end,
	GetTimeOfKeyframe = function() return 0 end,
}
local function seatSit(self, h)
	if mtypeof(h) ~= "Instance" or D[h].class ~= "Humanoid" then error("Seat:Sit: Humanoid expected", 2) end
	if D[self].props.Disabled then return end
	D[self].props.Occupant = h
	D[h].props.SeatPart = self
	D[h].props.Sit = true
	local w = newInstance("Weld", self) w.Name = "SeatWeld"
	w.Part0 = self
	local root = h.Parent and h.Parent:FindFirstChild("HumanoidRootPart")
	w.Part1 = root
	w.Destroying:Connect(function()
		if D[self].props.Occupant == h then D[self].props.Occupant = nil D[h].props.SeatPart = nil D[h].props.Sit = false firePropChanged(self, "Occupant") end
	end)
	firePropChanged(self, "Occupant")
	if root then h.Parent:PivotTo(self.CFrame + Vector3.new(0, 2, 0)) end
end
METHODS.Seat = { Sit = seatSit }
METHODS.VehicleSeat = { Sit = seatSit }
METHODS.ParticleEmitter = { Emit = function(self, n) end, Clear = function() end }
METHODS.Sound = {
	Play = function(self)
		local d = D[self]
		d.props.Playing = true; d.props.IsPlaying = true
		d.playSeq = (d.playSeq or 0) + 1
		local seq = d.playSeq
		getSig(self, "Played"):Fire(d.props.SoundId)
		if not d.props.Looped then
			task.delay(d.props.TimeLength or 1, function()
				if d.playSeq == seq and not d.destroyed and d.props.Playing then
					d.props.Playing = false; d.props.IsPlaying = false
					if d.sigs.Ended then d.sigs.Ended:Fire(d.props.SoundId) end
				end
			end)
		end
	end,
	Stop = function(self) local d = D[self] d.props.Playing = false d.props.IsPlaying = false d.playSeq = (d.playSeq or 0) + 1 end,
	Pause = function(self) D[self].props.Playing = false end,
	Resume = function(self) D[self].props.Playing = true end,
}
METHODS.BindableEvent = { Fire = function(self, ...) getSig(self, "Event"):Fire(...) end }
METHODS.BindableFunction = { Invoke = function(self, ...) local f = self.OnInvoke if not f then error("BindableFunction has no OnInvoke", 2) end return f(...) end }
METHODS.Terrain = { FillBlock = function(self, c, s, m)
	if not isCF(c) or not isV3(s) or mtypeof(m) ~= "EnumItem" then error("FillBlock(CFrame, Vector3, Material): bad args " .. mtypeof(c) .. "," .. mtypeof(s) .. "," .. mtypeof(m), 2) end
	table.insert(TERRAIN_BLOCKS, { cf = c, h = s / 2, mat = m })
end, FillBall = function() end, FillCylinder = function() end, FillRegion = function() end, Clear = function() end, FillWedge = function() end,
	ReadVoxels = function() return {}, {} end, WriteVoxels = function() end }
METHODS.GuiObject = {
	TweenPosition = function() return true end, TweenSize = function() return true end, TweenSizeAndPosition = function() return true end,
}
METHODS.TextBox = { CaptureFocus = function() end, ReleaseFocus = function() end, IsFocused = function() return false end }
METHODS.PlayerGui = { GetGuiObjectsAtPosition = function() return {} end, SetTopbarTransparency = function() end }
METHODS.LayerCollector = { GetGuiObjectsAtPosition = function() return {} end }
METHODS.ModuleScript = {}
METHODS.Camera = {
	WorldToViewportPoint = function(self, p)
		if not isV3(p) then error("WorldToViewportPoint: Vector3 expected, got " .. mtypeof(p), 2) end
		local l = D[self].props.CFrame:PointToObjectSpace(p)
		return Vector3.new(640 + l.X * 10, 360 - l.Y * 10, -l.Z), l.Z < 0
	end,
	ScreenPointToRay = function(self, x, y) return Ray.new(D[self].props.CFrame.Position, D[self].props.CFrame.LookVector) end,
	ViewportPointToRay = function(self, x, y) return Ray.new(D[self].props.CFrame.Position, D[self].props.CFrame.LookVector) end,
	GetPartsObscuringTarget = function() return {} end,
	Interpolate = function() end,
	GetRenderCFrame = function(self) return D[self].props.CFrame end,
}
METHODS.Camera.WorldToScreenPoint = METHODS.Camera.WorldToViewportPoint
METHODS.Lighting = {
	GetMinutesAfterMidnight = function(self) return (self.ClockTime or 14) * 60 end,
	SetMinutesAfterMidnight = function(self, m) self.ClockTime = m / 60 end,
	GetSunDirection = function() return Vector3.new(0, 1, 0) end, GetMoonDirection = function() return Vector3.new(0, -1, 0) end,
}
METHODS.ClickDetector = {}

-- ── Tween ──
METHODS.Tween = {
	Play = function(self)
		local d = D[self]
		d.playSeq = (d.playSeq or 0) + 1
		local seq = d.playSeq
		d.props.PlaybackState = Enum.PlaybackState.Playing
		local info = d.props._info
		if info.RepeatCount < 0 then
			-- loops forever: apply once and never complete
			for k, v in pairs(d.props._goal) do pcall(function() d.props._inst[k] = v end) end
			return
		end
		local dur = info.DelayTime + info.Time * (info.RepeatCount + 1) * (info.Reverses and 2 or 1)
		task.delay(dur, function()
			if d.playSeq ~= seq then return end
			local target = d.props._inst
			if D[target].destroyed then return end
			for k, v in pairs(d.props._goal) do
				local ok, e = pcall(function() target[k] = v end)
				if not ok then reportError(e, coroutine.running(), "tween-apply") end
			end
			d.props.PlaybackState = Enum.PlaybackState.Completed
			if d.sigs.Completed then d.sigs.Completed:Fire(Enum.PlaybackState.Completed) end
		end)
	end,
	Cancel = function(self)
		local d = D[self]
		d.playSeq = (d.playSeq or 0) + 1
		d.props.PlaybackState = Enum.PlaybackState.Cancelled
		if d.sigs.Completed then d.sigs.Completed:Fire(Enum.PlaybackState.Cancelled) end
	end,
	Pause = function(self) local d = D[self] d.playSeq = (d.playSeq or 0) + 1 end,
}
DEFAULTS.Tween = { PlaybackState = Enum.PlaybackState.Begin, TweenInfo = NILV, Instance = NILV }

-- ── Remotes ──
CLIENT = nil   -- { player = Player } when a client harness is running
REMOTE_LOG = {}
local function checkRemoteArgs(name, ...)
	local n = select("#", ...)
	local function walk(v, path, depth, seen)
		local t = type(v)
		if t == "function" then logOnce("errors", "RA:" .. name .. path, "remote " .. name .. ": function in payload at " .. path .. " (Roblox drops/errors) @ " .. callerLoc(4)) return end
		if t == "thread" then logOnce("errors", "RA:" .. name .. path, "remote " .. name .. ": thread in payload at " .. path) return end
		if t == "table" and not getmetatable(v) then
			if seen[v] then logOnce("errors", "RA:cyc" .. name, "remote " .. name .. ": cyclic table at " .. path) return end
			seen[v] = true
			local hasN, hasS = false, false
			for k, x in pairs(v) do
				if type(k) == "number" then hasN = true elseif type(k) == "string" then hasS = true
				else logOnce("errors", "RA:key" .. name .. path, "remote " .. name .. ": non-string/number key (" .. mtypeof(k) .. ") at " .. path .. " — dropped") end
				walk(x, path .. "." .. tostring(k), depth + 1, seen)
			end
			if hasN and hasS then logOnce("warns", "RA:mix" .. name .. path, "remote " .. name .. ": mixed array/dict table at " .. path .. " — Roblox drops keys @ " .. callerLoc(4)) end
			if hasN and not hasS then
				local cnt = 0 for _ in pairs(v) do cnt += 1 end
				if cnt ~= #v then logOnce("warns", "RA:sparse" .. name .. path, "remote " .. name .. ": sparse array at " .. path .. " (numeric keys, holes) — Roblox may truncate @ " .. callerLoc(4)) end
			end
		end
	end
	for i = 1, n do walk((select(i, ...)), "arg" .. i, 0, {}) end
end
METHODS.RemoteEvent = {
	FireClient = function(self, player, ...)
		if mtypeof(player) ~= "Instance" or D[player].class ~= "Player" then error("FireClient: Player expected as argument 1, got " .. mtypeof(player), 2) end
		checkRemoteArgs(self.Name, ...)
		REMOTE_LOG[self.Name] = table.pack(player, ...)
		if CLIENT and CLIENT.player == player then
			local args = table.pack(...)
			local s = getSig(self, "OnClientEvent")
			resumeThread(newThread(function() s:Fire(table.unpack(args, 1, args.n)) end, CLIENT_CTX))
		end
	end,
	FireAllClients = function(self, ...)
		checkRemoteArgs(self.Name, ...)
		REMOTE_LOG[self.Name] = table.pack("ALL", ...)
		local args = table.pack(...)
		if CLIENT then resumeThread(newThread(function() getSig(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n)) end, CLIENT_CTX)) end
	end,
	FireServer = function(self, ...)
		if curCtx().mode ~= "client" then error("FireServer can only be called from the client", 2) end
		checkRemoteArgs(self.Name, ...)
		local args = table.pack(...)
		-- the server handler runs on the SERVER (its SetAttribute calls are real, not client-local)
		resumeThread(newThread(function() getSig(self, "OnServerEvent"):Fire(CLIENT.player, table.unpack(args, 1, args.n)) end, MAIN_CTX))
	end,
}
METHODS.UnreliableRemoteEvent = METHODS.RemoteEvent
METHODS.RemoteFunction = {
	InvokeServer = function(self, ...)
		if curCtx().mode ~= "client" then error("InvokeServer can only be called from the client", 2) end
		local f = D[self].props.OnServerInvoke
		if not f then logOnce("errors", "RF:" .. self.Name, "RemoteFunction " .. self.Name .. " has no OnServerInvoke (client would hang)") return yieldForever() end
		local caller = coroutine.running()
		local r, done, waiting = nil, false, false
		local args = table.pack(...)
		local co = newThread(function()
			local ok, e = pcall(function() r = table.pack(f(CLIENT.player, table.unpack(args, 1, args.n))) end)
			if not ok then reportError(e, coroutine.running(), "OnServerInvoke " .. self.Name) r = table.pack() end
			done = true
			if waiting then resumeThread(caller) end
		end, MAIN_CTX)
		resumeThread(co)
		if not done then waiting = true coroutine.yield() end
		checkRemoteArgs(self.Name .. "(return)", table.unpack(r, 1, r.n))
		return table.unpack(r, 1, r.n)
	end,
	InvokeClient = function(self, p, ...)
		local f = D[self].props.OnClientInvoke
		if not f then return yieldForever() end
		return f(...)
	end,
}

-- ── Player ──
METHODS.Player = {
	Kick = function(self, msg) print("[mock] KICK " .. self.Name .. ": " .. tostring(msg)) end,
	LoadCharacter = function(self) spawnCharacter(self) end,
	GetMouse = function(self) return setmetatable({ Hit = CFrame.identity, Target = nil, X = 0, Y = 0, Button1Down = Signal.new("b1d"), Button1Up = Signal.new("b1u"), Move = Signal.new("mm"), Icon = "" }, { __index = function() return ANY end }) end,
	GetNetworkPing = function() return 0.05 end,
	IsInGroup = function() return false end,
	GetRankInGroup = function() return 0 end,
	GetRoleInGroup = function() return "Guest" end,
	GetFriendsOnline = function() return {} end,
	IsFriendsWith = function() return false end,
	HasAppearanceLoaded = function() return true end,
	ClearCharacterAppearance = function() end,
	DistanceFromCharacter = function(self, p) local c = self.Character local r = c and c:FindFirstChild("HumanoidRootPart") return r and (r.Position - p).Magnitude or 0 end,
	GetJoinData = function() return {} end,
	RequestStreamAroundAsync = function() end,
	SetSuperSafeChat = function() end,
}
METHODS.Players = {
	GetPlayers = function(self)
		local out = {}
		for _, c in ipairs(D[self].children) do if D[c].class == "Player" then table.insert(out, c) end end
		return out
	end,
	GetPlayerFromCharacter = function(self, char)
		if char == nil then return nil end
		for _, c in ipairs(D[self].children) do if D[c].class == "Player" and D[c].props.Character == char then return c end end
		return nil
	end,
	GetPlayerByUserId = function(self, id)
		for _, c in ipairs(D[self].children) do if D[c].class == "Player" and D[c].props.UserId == id then return c end end
		return nil
	end,
	GetUserIdFromNameAsync = function() return 1 end,
	GetNameFromUserIdAsync = function(_, id) return "User" .. tostring(id) end,
	GetUserThumbnailAsync = function() return "rbxasset://textures/ui/GuiImagePlaceholder.png", true end,
	GetHumanoidDescriptionFromUserId = function(self, id) return newInstance("HumanoidDescription") end,
	GetHumanoidDescriptionFromOutfitId = function(self, id)
		if type(id) ~= "number" then error("GetHumanoidDescriptionFromOutfitId: number expected", 2) end
		return newInstance("HumanoidDescription")
	end,
	CreateHumanoidModelFromDescription = function(self, desc, rig)
		if mtypeof(desc) ~= "Instance" or D[desc].class ~= "HumanoidDescription" then error("CreateHumanoidModelFromDescription: HumanoidDescription expected", 2) end
		return makeRig("NPC")
	end,
	CreateHumanoidModelFromUserId = function(self, id) return makeRig("NPC") end,
	GetFriendsAsync = function() return { GetCurrentPage = function() return {} end, IsFinished = true } end,
}
DEFAULTS.Players.LocalPlayer = NILV

function makeRig(name)
	local m = newInstance("Model")
	m.Name = name
	local hrp = newInstance("Part", m)
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	local head = newInstance("Part", m)
	head.Name = "Head"; head.Size = Vector3.new(2, 1, 1); head.CFrame = CFrame.new(0, 1.5, 0)
	local ut = newInstance("MeshPart", m)
	ut.Name = "UpperTorso"; ut.Size = Vector3.new(2, 1.6, 1)
	for _, n in ipairs({ "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftFoot", "RightFoot" }) do
		local p = newInstance("MeshPart", m) p.Name = n p.Size = Vector3.new(1, 1, 1)
	end
	local ra = newInstance("Attachment", D[m].children[#D[m].children - 4])
	ra.Name = "RightGripAttachment"
	local hum = newInstance("Humanoid", m)
	newInstance("Animator", hum)
	local ba = newInstance("Attachment", hrp) ba.Name = "RootAttachment"
	local ha = newInstance("Attachment", head) ha.Name = "HatAttachment"
	m.PrimaryPart = hrp
	return m
end

PLAYER_SPAWN = nil  -- function(player) -> CFrame
function spawnCharacter(player)
	local old = D[player].props.Character
	if old then
		getSig(player, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	local char = makeRig(player.Name)
	D[char].props.Archivable = false
	local at = CFrame.new(0, 5, 0)
	-- spawn on a SpawnLocation if any
	local spawns = {}
	for _, x in ipairs(descendants(WORKSPACE)) do if D[x].class == "SpawnLocation" and D[x].props.Enabled ~= false then table.insert(spawns, x) end end
	local rl = D[player].props.RespawnLocation
	if rl then at = rl.CFrame + Vector3.new(0, 3.5, 0)
	elseif #spawns > 0 then at = spawns[math.random(#spawns)].CFrame + Vector3.new(0, 3.5, 0) end
	char:PivotTo(at)
	D[player].props.Character = char
	char.Parent = WORKSPACE
	firePropChanged(player, "Character")
	getSig(player, "CharacterAdded"):Fire(char)
	return char
end

-- ── CollectionService ──
CollectionServiceImpl = {
	AddTag = function(_, inst, tag)
		if mtypeof(inst) ~= "Instance" then error("AddTag: Instance expected, got " .. mtypeof(inst), 2) end
		if type(tag) ~= "string" then error("AddTag: string expected", 2) end
		local d = D[inst]
		if d.tags[tag] then return end
		d.tags[tag] = true
		TAGGED[tag] = TAGGED[tag] or {}
		TAGGED[tag][inst] = true
		if inGame(inst) and TAG_ADDED[tag] then TAG_ADDED[tag]:Fire(inst) end
	end,
	RemoveTag = function(_, inst, tag)
		local d = D[inst]
		if not d.tags[tag] then return end
		d.tags[tag] = nil
		if TAGGED[tag] then TAGGED[tag][inst] = nil end
		if inGame(inst) and TAG_REMOVED[tag] then TAG_REMOVED[tag]:Fire(inst) end
	end,
	HasTag = function(_, inst, tag) return D[inst].tags[tag] == true end,
	GetTags = function(_, inst) local t = {} for k in pairs(D[inst].tags) do table.insert(t, k) end return t end,
	GetTagged = function(_, tag)
		if type(tag) ~= "string" then error("GetTagged: string expected", 2) end
		local out = {}
		for inst in pairs(TAGGED[tag] or {}) do
			if D[inst].tags[tag] and not D[inst].destroyed and inGame(inst) then table.insert(out, inst) end
		end
		return out
	end,
	GetInstanceAddedSignal = function(_, tag)
		TAG_ADDED[tag] = TAG_ADDED[tag] or Signal.new("tagadded:" .. tag)
		return TAG_ADDED[tag]
	end,
	GetInstanceRemovedSignal = function(_, tag)
		TAG_REMOVED[tag] = TAG_REMOVED[tag] or Signal.new("tagremoved:" .. tag)
		return TAG_REMOVED[tag]
	end,
	GetAllTags = function() local t = {} for k in pairs(TAGGED) do table.insert(t, k) end return t end,
}
