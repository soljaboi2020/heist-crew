-- ═══════════════ Mock Roblox datatypes ═══════════════
TYPEOF = {}          -- metatable -> type name
LOG = { errors = {}, warns = {}, unknown = {}, seen = {} }

local function logOnce(bucket, key, msg)
	if LOG.seen[key] then LOG.seen[key] += 1 return end
	LOG.seen[key] = 1
	table.insert(LOG[bucket], msg)
end
logOnce = logOnce

local rawtypeof = typeof
function mtypeof(v)
	local t = type(v)
	if t == "table" or t == "userdata" then
		local mt = getmetatable(v)
		if mt and TYPEOF[mt] then return TYPEOF[mt] end
		if t == "userdata" then return "userdata" end
		return "table"
	end
	return rawtypeof(v)
end

-- ── Vector3 ──
Vector3 = {}
local V3 = {}
TYPEOF[V3] = "Vector3"
HANG = 0
function hangTick()
	HANG += 1
	if HANG == 3000000 then print("[mock] HANG SUSPECT (t=" .. tostring(SCHED and SCHED.now) .. "):\n" .. debug.traceback()) end
	if HANG == 6000000 then print("[mock] HANG SUSPECT 2:\n" .. debug.traceback()) end
end
local function v3(x, y, z) HANG += 1 if HANG >= 3000000 and (HANG == 3000000 or HANG == 6000000) then hangTick() HANG -= 1 end return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
local function isV3(v) return getmetatable(v) == V3 end
isV3 = isV3
local function chkNum(n, what)
	if type(n) ~= "number" then error("invalid argument to " .. what .. " (number expected, got " .. mtypeof(n) .. ")", 3) end
end
function Vector3.new(x, y, z)
	if x ~= nil and type(x) ~= "number" then error("Vector3.new: number expected, got " .. mtypeof(x), 2) end
	if y ~= nil and type(y) ~= "number" then error("Vector3.new: number expected, got " .. mtypeof(y), 2) end
	if z ~= nil and type(z) ~= "number" then error("Vector3.new: number expected, got " .. mtypeof(z), 2) end
	return v3(x, y, z)
end
Vector3.zero = v3(0, 0, 0); Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0); Vector3.yAxis = v3(0, 1, 0); Vector3.zAxis = v3(0, 0, 1)
function Vector3.FromNormalId(n) return v3(0, 1, 0) end
local V3methods = {}
function V3methods.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3methods.Cross(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V3methods.Lerp(a, b, t)
	if not isV3(b) then error("Vector3:Lerp expects Vector3, got " .. mtypeof(b), 2) end
	chkNum(t, "Lerp")
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3methods.FuzzyEq(a, b, e) e = e or 1e-5 return math.abs(a.X - b.X) <= e and math.abs(a.Y - b.Y) <= e and math.abs(a.Z - b.Z) <= e end
function V3methods.Abs(a) return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
function V3methods.Min(a, b) return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function V3methods.Max(a, b) return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
function V3methods.Floor(a) return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z)) end
function V3methods.Ceil(a) return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z)) end
function V3methods.Sign(a) return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z)) end
function V3methods.Angle(a, b) local m = a.Magnitude * b.Magnitude if m == 0 then return 0 end return math.acos(math.clamp(a:Dot(b) / m, -1, 1)) end
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) if m == 0 then return v3(0 / 0, 0 / 0, 0 / 0) end return v3(v.X / m, v.Y / m, v.Z / m) end
	if k == "x" then return rawget(v, "X") elseif k == "y" then return rawget(v, "Y") elseif k == "z" then return rawget(v, "Z") end
	local m = V3methods[k]
	if m then return m end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3.__newindex = function(_, k) error(tostring(k) .. " cannot be assigned to (Vector3 is immutable)", 2) end
local function vop(name, f)
	return function(a, b)
		if type(a) == "number" then return v3(f(a, b.X), f(a, b.Y), f(a, b.Z)) end
		if type(b) == "number" then return v3(f(a.X, b), f(a.Y, b), f(a.Z, b)) end
		if not isV3(a) or not isV3(b) then error("attempt to perform arithmetic (" .. name .. ") on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
		return v3(f(a.X, b.X), f(a.Y, b.Y), f(a.Z, b.Z))
	end
end
V3.__add = function(a, b)
	if not isV3(a) or not isV3(b) then error("attempt to perform arithmetic (add) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	if not isV3(a) or not isV3(b) then error("attempt to perform arithmetic (sub) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = vop("mul", function(a, b) return a * b end)
V3.__div = vop("div", function(a, b) return a / b end)
V3.__idiv = vop("idiv", function(a, b) return a // b end)
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return string.format("%g, %g, %g", a.X, a.Y, a.Z) end

-- ── Vector2 ──
Vector2 = {}
local V2 = {}
TYPEOF[V2] = "Vector2"
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end
function Vector2.new(x, y)
	if x ~= nil and type(x) ~= "number" then error("Vector2.new: number expected, got " .. mtypeof(x), 2) end
	if y ~= nil and type(y) ~= "number" then error("Vector2.new: number expected, got " .. mtypeof(y), 2) end
	return v2(x, y)
end
Vector2.zero = v2(0, 0); Vector2.one = v2(1, 1); Vector2.xAxis = v2(1, 0); Vector2.yAxis = v2(0, 1)
V2.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y) return v2(v.X / m, v.Y / m) end
	if k == "x" then return rawget(v, "X") elseif k == "y" then return rawget(v, "Y") end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y end end
	if k == "Lerp" then return function(a, b, t) return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end end
	if k == "Cross" then return function(a, b) return a.X * b.Y - a.Y * b.X end end
	if k == "Abs" then return function(a) return v2(math.abs(a.X), math.abs(a.Y)) end end
	if k == "Max" then return function(a, b) return v2(math.max(a.X, b.X), math.max(a.Y, b.Y)) end end
	if k == "Min" then return function(a, b) return v2(math.min(a.X, b.X), math.min(a.Y, b.Y)) end end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
local function v2op(f)
	return function(a, b)
		if type(a) == "number" then return v2(f(a, b.X), f(a, b.Y)) end
		if type(b) == "number" then return v2(f(a.X, b), f(a.Y, b)) end
		if getmetatable(a) ~= V2 or getmetatable(b) ~= V2 then error("attempt to perform arithmetic on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
		return v2(f(a.X, b.X), f(a.Y, b.Y))
	end
end
V2.__add = v2op(function(a, b) return a + b end)
V2.__sub = v2op(function(a, b) return a - b end)
V2.__mul = v2op(function(a, b) return a * b end)
V2.__div = v2op(function(a, b) return a / b end)
V2.__unm = function(a) return v2(-a.X, -a.Y) end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2.__tostring = function(a) return string.format("%g, %g", a.X, a.Y) end

-- ── CFrame ──  stored as {x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22}
CFrame = {}
local CF = {}
TYPEOF[CF] = "CFrame"
local function cf(x, y, z, a, b, c, d, e, f, g, h, i)
	return setmetatable({ x, y, z, a or 1, b or 0, c or 0, d or 0, e or 1, f or 0, g or 0, h or 0, i or 1 }, CF)
end
local function isCF(v) return getmetatable(v) == CF end
isCF = isCF
local function orthonorm(c)
	-- Gram-Schmidt columns
	local x = v3(c[4], c[7], c[10]); local y = v3(c[5], c[8], c[11])
	if x.Magnitude < 1e-9 then x = v3(1, 0, 0) end
	x = x.Unit
	y = y - x * x:Dot(y)
	if y.Magnitude < 1e-9 then y = v3(0, 1, 0) end
	y = y.Unit
	local z = x:Cross(y)
	return cf(c[1], c[2], c[3], x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end
function CFrame.new(...)
	local n = select("#", ...)
	local a = ...
	if n == 0 then return cf(0, 0, 0) end
	if n == 1 then
		if not isV3(a) then error("CFrame.new: Vector3 expected, got " .. mtypeof(a), 2) end
		return cf(a.X, a.Y, a.Z)
	end
	if n == 2 then
		local p, l = ...
		if not isV3(p) or not isV3(l) then error("CFrame.new(pos, lookAt): Vector3s expected", 2) end
		return CFrame.lookAt(p, l)
	end
	if n == 3 then
		local x, y, z = ...
		chkNum(x, "CFrame.new"); chkNum(y, "CFrame.new"); chkNum(z, "CFrame.new")
		return cf(x, y, z)
	end
	if n == 7 then
		local x, y, z, qx, qy, qz, qw = ...
		local r00 = 1 - 2 * (qy * qy + qz * qz); local r01 = 2 * (qx * qy - qz * qw); local r02 = 2 * (qx * qz + qy * qw)
		local r10 = 2 * (qx * qy + qz * qw); local r11 = 1 - 2 * (qx * qx + qz * qz); local r12 = 2 * (qy * qz - qx * qw)
		local r20 = 2 * (qx * qz - qy * qw); local r21 = 2 * (qy * qz + qx * qw); local r22 = 1 - 2 * (qx * qx + qy * qy)
		return cf(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	if n == 12 then
		for i = 1, 12 do chkNum((select(i, ...)), "CFrame.new") end
		return cf(...)
	end
	error("CFrame.new: invalid number of arguments " .. n, 2)
end
function CFrame.lookAt(at, target, up)
	if not isV3(at) or not isV3(target) then error("CFrame.lookAt: Vector3 expected, got " .. mtypeof(at) .. ", " .. mtypeof(target), 2) end
	up = up or v3(0, 1, 0)
	local look = target - at
	if look.Magnitude < 1e-9 then return cf(at.X, at.Y, at.Z) end
	local zv = (-look).Unit
	local xv = up:Cross(zv)
	if xv.Magnitude < 1e-6 then
		xv = v3(0, 0, 1):Cross(zv)
		if xv.Magnitude < 1e-6 then xv = v3(1, 0, 0) end
	end
	xv = xv.Unit
	local yv = zv:Cross(xv)
	return cf(at.X, at.Y, at.Z, xv.X, yv.X, zv.X, xv.Y, yv.Y, zv.Y, xv.Z, yv.Z, zv.Z)
end
local function rotX(a) local c, s = math.cos(a), math.sin(a) return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c) end
local function rotY(a) local c, s = math.cos(a), math.sin(a) return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c) end
local function rotZ(a) local c, s = math.cos(a), math.sin(a) return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1) end
function CFrame.Angles(rx, ry, rz)
	chkNum(rx, "CFrame.Angles"); chkNum(ry or 0, "CFrame.Angles"); chkNum(rz or 0, "CFrame.Angles")
	return rotX(rx) * rotY(ry or 0) * rotZ(rz or 0)
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz) return rotY(ry) * rotX(rx) * rotZ(rz) end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromAxisAngle(axis, a)
	local u = axis.Unit local c, s = math.cos(a), math.sin(a) local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return cf(0, 0, 0, t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	if not isV3(pos) or not isV3(vx) or not isV3(vy) then error("CFrame.fromMatrix: Vector3 expected", 2) end
	vz = vz or vx:Cross(vy).Unit
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
CFrame.identity = cf(0, 0, 0)
local CFm = {}
function CFm.Inverse(c)
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12]
	local x, y, z = c[1], c[2], c[3]
	return cf(-(r00 * x + r10 * y + r20 * z), -(r01 * x + r11 * y + r21 * z), -(r02 * x + r12 * y + r22 * z),
		r00, r10, r20, r01, r11, r21, r02, r12, r22)
end
function CFm.ToWorldSpace(a, b) return a * b end
function CFm.ToObjectSpace(a, b) return a:Inverse() * b end
function CFm.PointToWorldSpace(a, p) return a * p end
function CFm.PointToObjectSpace(a, p)
	if not isV3(p) then error("PointToObjectSpace expects Vector3, got " .. mtypeof(p), 2) end
	return a:Inverse() * p
end
function CFm.VectorToWorldSpace(a, v) return a.Rotation * v end
function CFm.VectorToObjectSpace(a, v) return a.Rotation:Inverse() * v end
function CFm.GetComponents(c) return table.unpack(c, 1, 12) end
CFm.components = CFm.GetComponents
function CFm.Lerp(a, b, t)
	if not isCF(b) then error("CFrame:Lerp expects CFrame, got " .. mtypeof(b), 2) end
	local r = {}
	for i = 1, 12 do r[i] = a[i] + (b[i] - a[i]) * t end
	return orthonorm(r)
end
function CFm.ToEulerAnglesYXZ(c)
	local r02, r10, r11, r12, r22 = c[6], c[7], c[8], c[9], c[12]
	local rx = math.asin(-math.clamp(r12, -1, 1))
	local ry = math.atan2(r02, r22)
	local rz = math.atan2(r10, r11)
	return rx, ry, rz
end
CFm.ToOrientation = CFm.ToEulerAnglesYXZ
function CFm.ToEulerAnglesXYZ(c)
	local r02 = c[6]
	local ry = math.asin(math.clamp(r02, -1, 1))
	local rx = math.atan2(-c[9], c[12])
	local rz = math.atan2(-c[5], c[4])
	return rx, ry, rz
end
function CFm.ToAxisAngle(c) return v3(0, 1, 0), 0 end
function CFm.Orthonormalize(c) return orthonorm(c) end
function CFm.FuzzyEq(a, b, e) e = e or 1e-5 for i = 1, 12 do if math.abs(a[i] - b[i]) > e then return false end end return true end
CF.__index = function(c, k)
	if k == "Position" or k == "p" then return v3(c[1], c[2], c[3]) end
	if k == "X" then return c[1] elseif k == "Y" then return c[2] elseif k == "Z" then return c[3] end
	if k == "LookVector" or k == "lookVector" then return v3(-c[6], -c[9], -c[12]) end
	if k == "RightVector" or k == "XVector" then return v3(c[4], c[7], c[10]) end
	if k == "UpVector" or k == "YVector" then return v3(c[5], c[8], c[11]) end
	if k == "ZVector" then return v3(c[6], c[9], c[12]) end
	if k == "Rotation" then return cf(0, 0, 0, table.unpack(c, 4, 12)) end
	local m = CFm[k]
	if m then return m end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end
CF.__newindex = function(_, k) error(tostring(k) .. " cannot be assigned to (CFrame is immutable)", 2) end
CF.__mul = function(a, b)
	if not isCF(a) then error("attempt to perform arithmetic (mul) on " .. mtypeof(a) .. " and CFrame", 2) end
	if isV3(b) then
		return v3(a[4] * b.X + a[5] * b.Y + a[6] * b.Z + a[1], a[7] * b.X + a[8] * b.Y + a[9] * b.Z + a[2], a[10] * b.X + a[11] * b.Y + a[12] * b.Z + a[3])
	end
	if not isCF(b) then error("attempt to perform arithmetic (mul) on CFrame and " .. mtypeof(b), 2) end
	local a00, a01, a02, a10, a11, a12, a20, a21, a22 = a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
	local b00, b01, b02, b10, b11, b12, b20, b21, b22 = b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12]
	return cf(
		a00 * b[1] + a01 * b[2] + a02 * b[3] + a[1],
		a10 * b[1] + a11 * b[2] + a12 * b[3] + a[2],
		a20 * b[1] + a21 * b[2] + a22 * b[3] + a[3],
		a00 * b00 + a01 * b10 + a02 * b20, a00 * b01 + a01 * b11 + a02 * b21, a00 * b02 + a01 * b12 + a02 * b22,
		a10 * b00 + a11 * b10 + a12 * b20, a10 * b01 + a11 * b11 + a12 * b21, a10 * b02 + a11 * b12 + a12 * b22,
		a20 * b00 + a21 * b10 + a22 * b20, a20 * b01 + a21 * b11 + a22 * b21, a20 * b02 + a21 * b12 + a22 * b22)
end
CF.__add = function(a, b)
	if not isCF(a) or not isV3(b) then error("attempt to perform arithmetic (add) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return cf(a[1] + b.X, a[2] + b.Y, a[3] + b.Z, table.unpack(a, 4, 12))
end
CF.__sub = function(a, b)
	if not isCF(a) or not isV3(b) then error("attempt to perform arithmetic (sub) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return cf(a[1] - b.X, a[2] - b.Y, a[3] - b.Z, table.unpack(a, 4, 12))
end
CF.__eq = function(a, b) for i = 1, 12 do if a[i] ~= b[i] then return false end end return true end
CF.__tostring = function(c) return table.concat(c, ", ") end

-- ── Color3 ──
Color3 = {}
local C3 = {}
TYPEOF[C3] = "Color3"
local function c3(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end
function Color3.new(r, g, b)
	for _, v in ipairs({ r or 0, g or 0, b or 0 }) do if type(v) ~= "number" then error("Color3.new: number expected, got " .. mtypeof(v), 2) end end
	return c3(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	for _, v in ipairs({ r or 0, g or 0, b or 0 }) do if type(v) ~= "number" then error("Color3.fromRGB: number expected, got " .. mtypeof(v), 2) end end
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6); local f = h * 6 - i; local p = v * (1 - s); local q = v * (1 - f * s); local t = v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return c3(v, t, p) elseif i == 1 then return c3(q, v, p) elseif i == 2 then return c3(p, v, t)
	elseif i == 3 then return c3(p, q, v) elseif i == 4 then return c3(t, p, v) else return c3(v, p, q) end
end
function Color3.fromHex(h) h = h:gsub("#", "") return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255) end
function Color3.toHSV(c)
	local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == c.R then h = ((c.G - c.B) / d) % 6 elseif mx == c.G then h = (c.B - c.R) / d + 2 else h = (c.R - c.G) / d + 4 end
		h = h / 6
	end
	return h, mx == 0 and 0 or d / mx, mx
end
C3.__index = function(c, k)
	if k == "r" then return rawget(c, "R") elseif k == "g" then return rawget(c, "G") elseif k == "b" then return rawget(c, "B") end
	if k == "Lerp" then return function(a, b, t)
		if getmetatable(b) ~= C3 then error("Color3:Lerp expects Color3, got " .. mtypeof(b), 2) end
		return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
	if k == "ToHex" then return function(a) return string.format("%02X%02X%02X", math.floor(a.R * 255 + .5), math.floor(a.G * 255 + .5), math.floor(a.B * 255 + .5)) end end
	if k == "ToHSV" then return Color3.toHSV end
	error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3.__tostring = function(c) return string.format("%g, %g, %g", c.R, c.G, c.B) end

-- ── UDim / UDim2 ──
UDim = {}
local UD = {}
TYPEOF[UD] = "UDim"
function UDim.new(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD) end
UD.__index = function(_, k) error(tostring(k) .. " is not a valid member of UDim", 2) end
UD.__add = function(a, b) return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset) end
UD.__sub = function(a, b) return UDim.new(a.Scale - b.Scale, a.Offset - b.Offset) end
UD.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
UDim2 = {}
local U2 = {}
TYPEOF[U2] = "UDim2"
local function u2(xs, xo, ys, yo)
	for _, v in ipairs({ xs, xo, ys, yo }) do if type(v) ~= "number" then error("UDim2: number expected, got " .. mtypeof(v), 3) end end
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, U2)
end
function UDim2.new(a, b, c, d)
	if getmetatable(a) == UD then return u2(a.Scale, a.Offset, b.Scale, b.Offset) end
	return u2(a or 0, b or 0, c or 0, d or 0)
end
function UDim2.fromScale(x, y) return u2(x or 0, 0, y or 0, 0) end
function UDim2.fromOffset(x, y) return u2(0, x or 0, 0, y or 0) end
U2.__index = function(u, k)
	if k == "Width" then return rawget(u, "X") elseif k == "Height" then return rawget(u, "Y") end
	if k == "Lerp" then return function(a, b, t)
		if getmetatable(b) ~= U2 then error("UDim2:Lerp expects UDim2, got " .. mtypeof(b), 2) end
		return u2(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t) end end
	error(tostring(k) .. " is not a valid member of UDim2", 2)
end
U2.__add = function(a, b)
	if getmetatable(a) ~= U2 or getmetatable(b) ~= U2 then error("attempt to perform arithmetic (add) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return u2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2.__sub = function(a, b)
	if getmetatable(a) ~= U2 or getmetatable(b) ~= U2 then error("attempt to perform arithmetic (sub) on " .. mtypeof(a) .. " and " .. mtypeof(b), 2) end
	return u2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
U2.__tostring = function(u) return string.format("{%g, %g}, {%g, %g}", u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset) end

-- ── misc datatypes ──
local function simpleType(name, ctor)
	local mt = {}
	TYPEOF[mt] = name
	mt.__index = function(_, k) error(tostring(k) .. " is not a valid member of " .. name, 2) end
	return function(...) return setmetatable(ctor(...), mt) end, mt
end
NumberRange = {}
NumberRange.new = simpleType("NumberRange", function(a, b) return { Min = a, Max = b or a } end)
NumberSequenceKeypoint = {}
NumberSequenceKeypoint.new = simpleType("NumberSequenceKeypoint", function(t, v, e) return { Time = t, Value = v, Envelope = e or 0 } end)
NumberSequence = {}
NumberSequence.new = simpleType("NumberSequence", function(a, b)
	if type(a) == "number" then
		b = b or a
		return { Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) } }
	end
	if type(a) ~= "table" or #a < 2 then error("NumberSequence.new: need >= 2 keypoints", 3) end
	for i, kp in ipairs(a) do
		if mtypeof(kp) ~= "NumberSequenceKeypoint" then error("NumberSequence.new: bad keypoint " .. i, 3) end
	end
	if a[1].Time ~= 0 or a[#a].Time ~= 1 then error("NumberSequence: first keypoint must be at 0 and last at 1", 3) end
	return { Keypoints = a }
end)
ColorSequenceKeypoint = {}
ColorSequenceKeypoint.new = simpleType("ColorSequenceKeypoint", function(t, c)
	if mtypeof(c) ~= "Color3" then error("ColorSequenceKeypoint.new: Color3 expected, got " .. mtypeof(c), 3) end
	return { Time = t, Value = c }
end)
ColorSequence = {}
ColorSequence.new = simpleType("ColorSequence", function(a, b)
	if mtypeof(a) == "Color3" then return { Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } } end
	if type(a) ~= "table" or #a < 2 then error("ColorSequence.new: need >= 2 keypoints", 3) end
	if a[1].Time ~= 0 or a[#a].Time ~= 1 then error("ColorSequence: first keypoint must be at 0 and last at 1", 3) end
	for i = 2, #a do if a[i].Time < a[i - 1].Time then error("ColorSequence: keypoints out of order", 3) end end
	return { Keypoints = a }
end)
TweenInfo = {}
TweenInfo.new = simpleType("TweenInfo", function(t, s, d, rc, rev, dl)
	return { Time = t or 1, EasingStyle = s, EasingDirection = d, RepeatCount = rc or 0, Reverses = rev or false, DelayTime = dl or 0 }
end)
Rect = {}
Rect.new = simpleType("Rect", function(a, b, c, d) return { Min = v2(a, b), Max = v2(c, d), Width = (c or 0) - (a or 0), Height = (d or 0) - (b or 0) } end)
PhysicalProperties = {}
PhysicalProperties.new = simpleType("PhysicalProperties", function(d, f, e, fw, ew) return { Density = d, Friction = f, Elasticity = e, FrictionWeight = fw, ElasticityWeight = ew } end)
Font = {}
local FontMT
Font.new, FontMT = simpleType("Font", function(fam, w, s)
	if type(fam) ~= "string" then error("Font.new: string family expected", 3) end
	return { Family = fam, Weight = w, Style = s, Bold = false }
end)
function Font.fromEnum(e) return Font.new("rbxasset://fonts/families/GothamSSm.json") end
function Font.fromName(n, w, s) return Font.new("rbxasset://fonts/families/" .. n .. ".json", w, s) end
Ray = {}
Ray.new = simpleType("Ray", function(o, d) return { Origin = o, Direction = d } end)
Region3 = {}
Region3.new = simpleType("Region3", function(a, b) return { CFrame = CFrame.new((a + b) / 2), Size = b - a } end)
RaycastParams = {}
local RPmt = {}
TYPEOF[RPmt] = "RaycastParams"
function RaycastParams.new() return setmetatable({ FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false, CollisionGroup = "Default", RespectCanCollide = false, BruteForceAllSlow = false, AddToFilter = function(self, x) end }, RPmt) end
OverlapParams = {}
local OPmt = {}
TYPEOF[OPmt] = "OverlapParams"
function OverlapParams.new() return setmetatable({ FilterDescendantsInstances = {}, FilterType = nil, MaxParts = 0, CollisionGroup = "Default", RespectCanCollide = false, AddToFilter = function(self, x) end }, OPmt) end
BrickColor = {}
BrickColor.new = simpleType("BrickColor", function(n) return { Name = tostring(n), Color = c3(0.5, 0.5, 0.5), Number = 1 } end)
function BrickColor.random() return BrickColor.new("Random") end
function BrickColor.palette(i) return BrickColor.new("P" .. i) end
for _, n in ipairs({ "White", "Gray", "DarkGray", "Black", "Red", "Yellow", "Green", "Blue" }) do BrickColor[n] = function() return BrickColor.new(n) end end
DateTime = {}
function DateTime.now() return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000, ToIsoDate = function() return "2026-09-25T00:00:00Z" end, FormatUniversalTime = function() return "" end } end
function DateTime.fromUnixTimestamp(t) return { UnixTimestamp = t, ToUniversalTime = function() return os.date("!*t", t) end } end
Random = {}
local RandMT = {}
TYPEOF[RandMT] = "Random"
RandMT.__index = {
	NextNumber = function(self, a, b)
		a = a or 0; b = b or 1
		if type(a) ~= "number" or type(b) ~= "number" then error("Random:NextNumber expects numbers", 2) end
		return a + math.random() * (b - a)
	end,
	NextInteger = function(self, a, b)
		if type(a) ~= "number" or type(b) ~= "number" then error("Random:NextInteger expects 2 numbers, got " .. mtypeof(a) .. "," .. mtypeof(b), 2) end
		if b < a then error("Random:NextInteger: invalid argument #2 (max must be >= min) " .. a .. " > " .. b, 2) end
		return math.random(math.floor(a), math.floor(b))
	end,
	NextUnitVector = function() return v3(math.random() - .5, math.random() - .5, math.random() - .5).Unit end,
	Shuffle = function(self, t) for i = #t, 2, -1 do local j = math.random(i) t[i], t[j] = t[j], t[i] end end,
	Clone = function(self) return Random.new() end,
}
function Random.new(seed) return setmetatable({}, RandMT) end
Axes = { new = function() return {} end }
Faces = { new = function() return {} end }

-- ── Enum ──
local ENUM_ITEMS = {
	Material = "Plastic SmoothPlastic Neon Wood WoodPlanks Marble Slate Concrete Granite Brick Pebble Cobblestone Rock Sandstone Basalt CrackedLava Limestone Pavement CorrodedMetal CorrugatedSteel DiamondPlate Foil Metal Grass LeafyGrass Sand Fabric Snow Mud Ground Asphalt Salt Ice Glacier Glass ForceField Air Water Cardboard Carpet CeramicTiles ClayRoofTiles RoofShingles Leather Plaster Rubber",
	EasingStyle = "Linear Sine Back Quad Quart Quint Bounce Elastic Exponential Circular Cubic",
	EasingDirection = "In Out InOut",
	PartType = "Ball Block Cylinder Wedge CornerWedge",
	SortOrder = "LayoutOrder Name Custom",
	FillDirection = "Horizontal Vertical",
	HorizontalAlignment = "Center Left Right",
	VerticalAlignment = "Center Top Bottom",
	TextXAlignment = "Left Right Center",
	TextYAlignment = "Top Center Bottom",
	AutomaticSize = "None X Y XY",
	NormalId = "Right Top Back Left Bottom Front",
	SurfaceType = "Smooth Glue Weld Studs Inlet Universal Hinge Motor SteppingMotor SmoothNoOutlines",
	FontWeight = "Thin ExtraLight Light Regular Medium SemiBold Bold ExtraBold Heavy",
	ZIndexBehavior = "Global Sibling",
	ApplyStrokeMode = "Contextual Border",
	TextTruncate = "None AtEnd SplitWord",
	ScrollingDirection = "X Y XY",
	ScrollBarInset = "None ScrollBar Always",
	SurfaceGuiSizingMode = "FixedSize PixelsPerStud",
	HighlightDepthMode = "AlwaysOnTop Occluded",
	RollOffMode = "Inverse Linear InverseTapered LinearSquare",
	CameraType = "Fixed Attach Watch Track Follow Custom Scriptable Orbital",
	Style = "AlternatingSupports BridgeStyleSupports NoSupports",
	AnimationPriority = "Idle Movement Action Action2 Action3 Action4 Core",
	RaycastFilterType = "Exclude Include Blacklist Whitelist",
	PathStatus = "Success ClosestNoPath ClosestOutOfRange FailStartNotEmpty FailFinishNotEmpty NoPath",
	PathWaypointAction = "Walk Jump Custom",
	ProximityPromptExclusivity = "OnePerButton OneGlobally AlwaysShow",
	ContextActionResult = "Pass Sink",
	ContextActionPriority = "Low Medium Default High",
	RenderPriority = "First Input Camera Character Last",
	HumanoidRigType = "R6 R15",
	HumanoidDisplayDistanceType = "Viewer Subject None",
	HumanoidHealthDisplayType = "DisplayWhenDamaged AlwaysOn AlwaysOff",
	CoreGuiType = "PlayerList Health Backpack Chat All EmotesMenu SelfView Captures",
	InfoType = "Asset Product GamePass Subscription Bundle",
	UserInputState = "Begin Change End Cancel None",
	HumanoidStateType = "FallingDown Ragdoll GettingUp Jumping Swimming Freefall Flying Landed Running RunningNoPhysics StrafingNoPhysics Climbing Seated PlatformStanding Dead Physics None",
	ProximityPromptStyle = "Default Custom",
	Font = "Legacy Arial ArialBold SourceSans SourceSansBold SourceSansLight SourceSansItalic Bodoni Garamond Cartoon Code Highway SciFi Arcade Fantasy Antique SourceSansSemibold Gotham GothamMedium GothamBold GothamBlack AmaticSC Bangers Creepster DenkOne Fondamento FredokaOne GrenzeGotisch IndieFlower JosefinSans Jura Kalam LuckiestGuy Merriweather Michroma Nunito Oswald PatrickHand PermanentMarker Roboto RobotoCondensed RobotoMono Sarpanch SpecialElite TitilliumWeb Ubuntu BuilderSans BuilderSansMedium BuilderSansBold BuilderSansExtraBold Arimo ArimoBold Unknown",
}
local EnumItemMT = {}
TYPEOF[EnumItemMT] = "EnumItem"
EnumItemMT.__tostring = function(e) return "Enum." .. e.EnumType.Name .. "." .. e.Name end
EnumItemMT.__index = function(e, k)
	if k == "IsA" then return function(self, n) return self.EnumType.Name == n end end
	error(tostring(k) .. " is not a valid member of EnumItem", 2)
end
local EnumTypeMT = {}
TYPEOF[EnumTypeMT] = "Enum"
local enumTypes = {}
local function makeEnumType(name)
	local et = setmetatable({ Name = name, _items = {}, _list = {} }, EnumTypeMT)
	local known = ENUM_ITEMS[name]
	if known then
		local i = 0
		for w in known:gmatch("%S+") do
			local it = setmetatable({ Name = w, Value = i, EnumType = et }, EnumItemMT)
			et._items[w] = it; table.insert(et._list, it); i += 1
		end
		et._closed = true
	end
	return et
end
EnumTypeMT.__index = function(et, k)
	if k == "GetEnumItems" then return function(self) return table.clone(self._list) end end
	if k == "FromName" then return function(self, n) return self._items[n] end end
	if k == "FromValue" then return function(self, v) for _, it in ipairs(self._list) do if it.Value == v then return it end end return nil end end
	local items = rawget(et, "_items")
	local it = items[k]
	if it then return it end
	if rawget(et, "_closed") then error(tostring(k) .. " is not a valid EnumItem of Enum." .. rawget(et, "Name"), 2) end
	it = setmetatable({ Name = k, Value = #rawget(et, "_list"), EnumType = et }, EnumItemMT)
	items[k] = it; table.insert(rawget(et, "_list"), it)
	return it
end
Enum = setmetatable({}, { __index = function(t, k)
	local et = enumTypes[k]
	if not et then et = makeEnumType(k); enumTypes[k] = et end
	return et
end })
