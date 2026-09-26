--[[
    HEIST CREW — MartBuilder
    ────────────────────────────────────────────────
    Job: SUNNY'S MART — the warm-up heist that teaches the game.

    v3.3 "VERTICAL SLICE" (2026-09-26). Malachi: "doesn't feel like a good
    Roblox game — the heist itself is weird". We stopped adding features and
    rebuilt ONE heist to feel right, PAYDAY / Entry Point style:

      ARRIVAL   the crew stands on the SIDEWALK outside the front door,
                facing the store (refs.arrival — JobService.dropPoints prefers
                it over sneakIn). Unmasked = a customer: walk in the front door.
                The sales floor is public; the STOCK ROOM and OFFICE behind
                the EMPLOYEES ONLY curtain are restricted (refs.restricted —
                MaskUpService), the office is a crime room (it holds the safe).
      THE JOB   one goal at a time (refs.goalChain → JobService):
                ① Turn off the camera  — the breaker, straight ahead through
                  the curtain, lit on the stock room's back wall
                ② Crack the safe       — the office, through the stock room
                ③ Bag the cash + load the car — out the loading door, the car
                  is parked in the walled yard right outside
                → hop in + press GO!
                Bonus: Golden Ticket (office wall) · 2 registers · scratch
                tickets · ATM · lotto carton · night deposit · secret stash.
      THE GUARD one guard, one readable lane: up and down the COUNTER aisle,
                pausing at each end (he watches the registers). He never
                looks into the curtain doorway or the stock room.
      THE CAMERA over the freezer, watching the counter + the front door.

    FOOTPRINT x 48..74, z 1..33.5 (sales floor x 50..74, z 1..20; back wing
    x 48..74, z 19..33.5) + the walled yard x 74..83.7. Floor top y 0.5,
    ceiling y 14.5, roof deck y 15.5, parapet y 17.5.

        z 1  ┌PIER┬─ window ─┬── FRONT DOOR x 58..66 ──┬─ window ─┬PIER┐   yard gate x 74..82.5
             │    CLERK  ║c│ G           ·           ·            F│
             │ tickets   ║o│ U   ISLAND  ·  east    ·            R│   🚗 car (78.25, 10)
             │ shelves   ║u│ A   x61.5   ·  aisle   ·            I│   (nose at the gate)
             │           ║n│ R   ..63.5  ·          ·            D│
             │           ║t│ D   z 8..13 ·          ·            G│
             │  FREEZER   BIG BOX  WALL SHELF   CURTAIN (x 63.5..70.5)  ATM │ ← ladder (yard, z 17.4..19.4)
        z 19 ├───────────────────────┬──────────────── EMPLOYEES ONLY ─────┤
             │ TICKET  desk  monitor │ bench($)                    │═ LOADING DOOR
             │ ladder↑   rug         D   the corridor (keep clear)  │═ (roll-up, z 20.5..28)
             │ calendar              D                              │
             │   [SAFE]   cabinet    │ closet rack [BREAKER] rack($)│
        z 33.5└──────────────────────┴──────────────────────────────┘
            x 48                  59.5 60.5                        74

    WALKWAYS ≥ 6: counter aisle x 55.5..61.5 · east aisle x 63.5..70.8 ·
    curtain 7 wide · office door 7 wide · loading door 7.5 wide · the stock
    room corridor z 21..28 is empty floor (door → office, door → yard).
    E PROMPTS ≥ 6 apart (see _checkout / _stockRoom / _office for the math);
    H (hide) / V (roof hatch) ≥ 4 from every E prompt.

    ART (docs/ART_DIRECTION.md): one clean corner-store style. Warm white
    stucco outside with teal + sunny-yellow brand accents; warm light-grey
    walls + teal wainscot inside; products printed as grouped facings (3–4 of
    the same box side by side, label band + lid) instead of random colour
    chips; bottles in the fridges. Neon only on thin trim (sign border, OPEN
    sign, fridge LED strips, tube lenses). Light: two shadowed KEY troffers
    (0.5) + dim fills on the sales floor, a caged work lamp (0.55) over the
    breaker, a desk lamp (0.5) in the office — pools with softer dark between.

    Geometry + props + refs ONLY (no Scripts / prompts / gameplay). Tags set
    here (V2_SPEC §2): HideSpot (+Label), ShadowZone, Vent (+Pair, Exit).

    PUBLIC API:
        MartBuilder:build(folder) -> JobRefs   (V1_SPEC §4 + V2_SPEC §4 + v3 loot, id = "mart")
        v3.3 extra refs:
            arrival    = { at, face, spread, line }   sidewalk drop-in (JobService.dropPoints)
            restricted = { {x0, z0, x1, z1, crime?, name, y0, y1}, ... }   (MaskUpService)
            goalChain  = true            JobService shows the ①②③ chain, one goal at a time
            sneakIn    = the stock room by the loading door: where a guard kick-back /
                         a jail break-out puts you (v3.3: bots drop in beside their owner at arrival)
            guardRoutes[1].waypoints / .pause — the patrol loop (GuardService v3.3 walks it)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local MartBuilder = {}

local M = Enum.Material
local W = Constants.WORLD

-- ── layout ──────────────────────────────────────────────────────────────
local FLOOR = W.FLOOR                                             -- 0.5
local CX, CZ = W.MART_CENTER.x, W.MART_CENTER.z                   -- 62, 13
local X0, X1 = CX - W.MART_HALF_WIDTH, CX + W.MART_HALF_WIDTH     -- 50, 74
local Z0 = CZ - W.MART_HALF_DEPTH                                 -- 1 (the storefront line)
local IX0, IX1 = X0 + 1, X1 - 1        -- 51, 73 (sales floor side walls)
local IZ0 = Z0 + 1                     -- 2
local Z1 = 33.5                        -- outer face of the back wall (inside MiamiBuilder.KEEP_CLEAR z ≤ 34)
local IZ1 = Z1 - 1                     -- 32.5
local BX0 = 48                         -- back wing west wall x 48..49
local BIX0 = BX0 + 1                   -- 49
local CEIL = FLOOR + 14                -- 14.5
local ROOF_Y = CEIL + 1                -- 15.5
local TOP = ROOF_Y + 2                 -- 17.5
local ZF = Z0 - 0.25                   -- 0.75, front face of the storefront
local DOOR_H = FLOOR + 11              -- 11.5 (doorways 11 tall)

local ENT_X0, ENT_X1 = CX - 4, CX + 4           -- front door x 58..66 (8 wide)
local ENT_TOP = FLOOR + 10.5
local WIN_TOP = FLOOR + 10.3
local SALES_Z1 = 19                             -- (v3.3) sales floor back wall z 19..20 (was 15..16)
local BACK_Z0 = 20
local CURTAIN_X0, CURTAIN_X1 = 63.5, 70.5       -- EMPLOYEES ONLY strip curtain (7 wide)
local OFFICE_X1 = 59.5                          -- office | stock wall x 59.5..60.5
local STOCK_X0 = 60.5
local OFFICE_DOOR_Z0, OFFICE_DOOR_Z1 = 22.5, 29.5   -- 7 wide, in the x 59.5..60.5 wall
local LOAD_Z0, LOAD_Z1 = 20.5, 28                   -- roll-up loading door in the east wall (7.5 wide)
-- the roof ladder: in the yard, on the store's east wall, between the car bay
-- (ends z 16.6) and the loading door (starts z 20.5). The bank's side-gap wall
-- (z 29.2..30) closes the yard's south end, so it can't go further south.
local LADDER_Z = 17.6                           -- truss x 74..76, z 16.6..18.6
local NOTCH_Z0, NOTCH_Z1 = 16.1, 19.1           -- parapet notch over it

-- ── the walled SERVICE YARD ──
local YARD_X1 = 83.7                            -- east wall outer face (bank plinth starts at 83.8)
local YARD_Z1 = Z1
local YWALL_T, YWALL_H = 0.6, 12
local GATE_X0, GATE_X1 = X1, 82.5               -- vehicle gate x 74..82.5, line z 1
local CAR_X, CAR_Z = 78.25, 10                  -- getaway parking spot (faces north, at the gate)

-- ── sales floor fixtures ──
local COUNTER_X0, COUNTER_X1, COUNTER_Z0, COUNTER_Z1 = 53, 55.5, 2.6, 11.6
local REGISTER_Z = { 3.6, 10.4 }
local REG_STAND_X = COUNTER_X1 + 2.6            -- 58.1
local DISP_Z = 7                                -- scratch-ticket dispenser centre (behind the clerk)
local ISLAND_X0, ISLAND_X1, ISLAND_Z0, ISLAND_Z1 = 61.5, 63.5, 8.4, 12.6   -- + 0.4 end caps → z 8..13 (6-deep aisles front + back)
local FRIDGE_X0, FRIDGE_Z0, FRIDGE_Z1 = 70.8, 5, 15.5
local GUARD_X = 59.2
local GUARD_Z0, GUARD_Z1 = 4.6, 14.3

-- ── the office safe ──
local SAFE_X = 55
local SAFE_Z0, SAFE_Z1 = 29.5, IZ1 - 0.1       -- z 29.5..32.4
local SAFE_HW = 2.5
local SAFE_Y = FLOOR + 2.7
local SAFE_TOP = FLOOR + 5.5
local DISC_R, DISC_T = 1.6, 0.45

-- ── palette: ONE clean corner-store look ────────────────────────────────
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function shade(c, f) return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1)) end
-- outside
local STUCCO    = rgb(222, 216, 202)     -- warm white stucco
local STUCCO_DK = rgb(196, 190, 176)     -- coping / trim
local TEAL      = rgb(22, 140, 142)      -- the brand colour
local TEAL_DK   = rgb(14, 92, 96)
local SUNNY     = rgb(255, 190, 40)      -- brand yellow
local SUNNY_DK  = rgb(236, 142, 30)
-- inside
local WALL_IN   = rgb(188, 182, 170)     -- warm light grey (Future lighting: never near-white)
local WAINSCOT  = rgb(44, 120, 120)      -- teal wainscot / counter
local CEIL_COL  = rgb(158, 158, 154)
local FLOOR_TILE = rgb(140, 138, 132)    -- mid-tone so the guard cone reads on it
local STEEL     = rgb(58, 62, 70)
local STEEL_DK  = rgb(30, 32, 38)
local STEEL_LT  = rgb(170, 176, 186)
local SHELF_COL = rgb(176, 178, 176)
local WALNUT    = rgb(96, 64, 44)
local INK       = rgb(34, 36, 42)
local PAPER     = rgb(244, 240, 230)
local COOL      = rgb(226, 238, 255)
local WARM      = rgb(255, 222, 186)
local TUBE_LENS = rgb(150, 158, 170)     -- troffer diffuser (dim, so 6 fixtures don't bloom)
local BLOCK     = rgb(128, 130, 126)     -- stock-room painted cinder block
local SAFETY    = rgb(236, 196, 48)

-- products: { body, label band, height (share of the row) } — grouped in
-- facings of 3–4 so a shelf reads as real stock, not confetti
local PRODUCTS = {
    { rgb(206, 48, 52),  rgb(250, 208, 70),  0.86 },   -- red chips bag
    { rgb(248, 190, 40), rgb(196, 44, 40),   0.86 },   -- yellow chips bag
    { rgb(40, 104, 196), rgb(240, 240, 234), 0.78 },   -- blue cracker box
    { rgb(58, 146, 80),  rgb(244, 238, 216), 0.7 },    -- green box
    { rgb(236, 118, 32), rgb(255, 240, 200), 0.92 },   -- orange cereal
    { rgb(124, 66, 166), rgb(250, 218, 116), 0.62 },   -- purple candy
    { rgb(232, 228, 218), rgb(30, 116, 196), 0.74 },   -- white box, blue label
    { rgb(118, 72, 44),  rgb(238, 198, 120), 0.66 },   -- cookies
    { rgb(196, 40, 104), rgb(250, 236, 236), 0.7 },    -- pink
    { rgb(22, 120, 124), rgb(250, 226, 120), 0.8 },    -- teal (Sunny's own brand)
}
-- fridge drinks: { bottle, label, cap }
local DRINKS = {
    { rgb(186, 28, 36),  rgb(240, 240, 240), rgb(200, 30, 36) },    -- cola
    { rgb(52, 150, 70),  rgb(236, 240, 200), rgb(30, 100, 40) },    -- lime soda
    { rgb(244, 136, 32), rgb(255, 236, 190), rgb(200, 90, 20) },    -- orange
    { rgb(40, 96, 200),  rgb(220, 236, 255), rgb(24, 60, 140) },    -- sports drink
    { rgb(206, 224, 236), rgb(40, 120, 210), rgb(40, 120, 210) },   -- water
    { rgb(238, 200, 40), rgb(250, 250, 240), rgb(40, 40, 44) },     -- lemon tea
    { rgb(116, 40, 136), rgb(250, 220, 250), rgb(80, 20, 100) },    -- grape
}

-- ── helpers ─────────────────────────────────────────────────────────────
local function part(props, parent)
    local p = Instance.new("Part")
    p.Anchored = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent
    return p
end

local function box(name, x0, y0, z0, x1, y1, z1, color, material, parent, extra)
    local props = {
        Name = name,
        Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)),
        Position = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        Color = color,
        Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function nc(extra)
    local t = { CanCollide = false }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local function bar(name, a, b, thick, color, material, parent, extra)
    local d = b - a
    local mid = (a + b) / 2
    local cf
    if math.abs(d.Unit.Y) > 0.999 then
        cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)
    else
        cf = CFrame.lookAt(mid, b)
    end
    local props = { Name = name, Size = Vector3.new(thick, thick, d.Magnitude), CFrame = cf,
        Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function tube(name, a, b, color, parent, thick)
    return bar(name, a, b, thick or 0.14, color, M.Neon, parent, { CanCollide = false, CastShadow = false })
end

local function weldTo(anchor, p)
    p.Anchored = false
    p.Massless = true
    p.CanCollide = false
    local w = Instance.new("WeldConstraint")
    w.Part0 = anchor
    w.Part1 = p
    w.Parent = p
end

local function surface(p, face, pps, bright)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 50
    g.LightInfluence = 0
    g.Brightness = bright or 1.2
    g.Parent = p
    return g
end

-- printed / painted things take the room's light; screens + backlit signs stay unlit
local function lit(g)
    g.LightInfluence = 1
    g.Brightness = 1
    return g
end

local function frame(props, parent)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props) do f[k] = v end
    f.Parent = parent
    return f
end

local function text(props, parent)
    local l = UITheme.label(props)
    l.Parent = parent
    return l
end

local function printOn(p, face, str, color, font, pps, bright)
    local g = surface(p, face, pps or 50, bright or 1.1)
    return text({ Text = str, Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = font or UITheme.F.display,
        TextColor3 = color }, g)
end

-- a painted sign: coloured plate, lit by the room
local function sign(name, x0, y0, z0, x1, y1, z1, face, str, plate, ink, parent, font)
    local p = box(name, x0, y0, z0, x1, y1, z1, plate, M.Metal, parent, nc({ CastShadow = false }))
    lit(printOn(p, face, str, ink, font or UITheme.F.display, 50, 1).Parent)
    return p
end

-- a paper poster: coloured header band, big title, small line, footer band
local function poster(name, x0, y0, z0, x1, y1, z1, face, title, sub, band, ink, parent)
    local p = box(name, x0, y0, z0, x1, y1, z1, PAPER, M.Fabric, parent, nc({ CastShadow = false }))
    local g = lit(surface(p, face, 40, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER }, g)
    frame({ Size = UDim2.fromScale(1, 0.2), BackgroundColor3 = band }, g)
    text({ Text = title, Size = UDim2.fromScale(0.9, sub and 0.42 or 0.6), Position = UDim2.fromScale(0.05, 0.25),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = ink }, g)
    if sub then
        text({ Text = sub, Size = UDim2.fromScale(0.86, 0.18), Position = UDim2.fromScale(0.07, 0.7),
            TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextColor3 = INK }, g)
    end
    frame({ Size = UDim2.fromScale(1, 0.05), Position = UDim2.fromScale(0, 0.95), BackgroundColor3 = band }, g)
    return p
end

local function spot(parent, face, color, brightness, range, angle, shadows)
    local s = Instance.new("SpotLight")
    s.Face = face
    s.Color = color
    s.Brightness = brightness
    s.Range = range
    s.Angle = angle
    s.Shadows = shadows == true
    s.Parent = parent
    return s
end

local function point(parent, color, brightness, range, shadows)
    local l = Instance.new("PointLight")
    l.Color = color
    l.Brightness = brightness
    l.Range = range
    l.Shadows = shadows == true
    l.Parent = parent
    return l
end

local function lightAnchor(name, pos, parent)
    return part({ Name = name, Size = Vector3.new(0.2, 0.2, 0.2), Position = pos, Transparency = 1,
        CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
        Material = M.Metal }, parent)
end

-- recessed troffer. brightness 0 = a lit-looking fixture that casts nothing
-- (fill budget); shadows = this one is a key light
local function tubeLight(parent, x, z, alongX, brightness, range, len, shadows, color)
    local half = (len or 4.4) / 2
    local hx, hz = alongX and half or 0.5, alongX and 0.5 or half
    local fx = box("Troffer", x - hx, CEIL - 0.2, z - hz, x + hx, CEIL, z + hz, STEEL_LT, M.Metal, parent, nc())
    box("TrofferLens", x - hx + 0.12, CEIL - 0.24, z - hz + 0.12, x + hx - 0.12, CEIL - 0.2, z + hz - 0.12,
        TUBE_LENS, M.Neon, parent, nc({ CastShadow = false }))
    if (brightness or 0) > 0 then point(fx, color or COOL, brightness, range or 12, shadows == true) end
    return fx
end

local function tag(p, tagName, attrs)
    CollectionService:AddTag(p, tagName)
    for k, v in pairs(attrs or {}) do p:SetAttribute(k, v) end
    return p
end

local function shadowZone(name, x0, z0, x1, z1, parent)
    local p = box(name, x0, FLOOR, z0, x1, FLOOR + 9, z1, rgb(0, 0, 0), M.Concrete, parent, {
        Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
    return tag(p, "ShadowZone")
end

-- a wall along z (x from xa..xb thick) with door gaps { {z0, z1, headerY} }
local function wallZ(name, xa, xb, z0, z1, gaps, color, material, parent, y1)
    y1 = y1 or CEIL
    local cur = z0
    for _, g in ipairs(gaps or {}) do
        if g[1] > cur then box(name, xa, FLOOR, cur, xb, y1, g[1], color, material, parent) end
        box(name .. "Header", xa, g[3], g[1], xb, y1, g[2], color, material, parent)
        cur = g[2]
    end
    if cur < z1 then box(name, xa, FLOOR, cur, xb, y1, z1, color, material, parent) end
end

local function wallX(name, za, zb, x0, x1, gaps, color, material, parent, y1)
    y1 = y1 or CEIL
    local cur = x0
    for _, g in ipairs(gaps or {}) do
        if g[1] > cur then box(name, cur, FLOOR, za, g[1], y1, zb, color, material, parent) end
        box(name .. "Header", g[1], g[3], za, g[2], y1, zb, color, material, parent)
        cur = g[2]
    end
    if cur < x1 then box(name, cur, FLOOR, za, x1, y1, zb, color, material, parent) end
end

local function facingPart(name, centre, size, out, color, material, parent, extra)
    local props = { Name = name, Size = size, CFrame = CFrame.lookAt(centre, centre + out),
        Color = color, Material = material }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

-- Kenney furniture arrives as plain white / grey meshes: repaint after placing.
-- The biggest part gets `main`, the rest `accent`; `byName` (lower-case
-- substring → spec) wins. A spec is { Color3, Material, reflectance? }.
local function paintModel(model, paint)
    local parts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end
    table.sort(parts, function(a, b)
        return a.Size.X * a.Size.Y * a.Size.Z > b.Size.X * b.Size.Y * b.Size.Z
    end)
    for i, p in ipairs(parts) do
        local spec
        if paint.byName then
            local n = string.lower(p.Name)
            for pat, sp in pairs(paint.byName) do
                if string.find(n, pat, 1, true) then
                    spec = sp
                    break
                end
            end
        end
        spec = spec or ((i == 1 or not paint.accent) and paint.main or paint.accent)
        local textured = p:IsA("MeshPart") and p.TextureID ~= ""
        if spec and not textured then
            p.Color = spec[1]
            p.Material = spec[2]
            p.Reflectance = spec[3] or 0
        end
    end
end

-- place one Kenney prop (async, never errors) and repaint it
local function prop(kit, name, pos, facing, parent, paint, opts)
    task.spawn(function()
        local o = { parent = parent }
        for k, v in pairs(opts or {}) do o[k] = v end
        local ok, model = pcall(KenneyLoader.place, kit, name, pos, facing, o)
        if ok and model and paint then pcall(paintModel, model, paint) end
    end)
end

-- (v3.3) a shelf of stock: ONE part, the products printed on its face as
-- FACINGS — runs of 3–4 identical items (body + label band + darker lid).
local function productRow(name, x0, y0, z0, x1, y1, z1, face, seed, parent, count)
    local p = box(name, x0, y0, z0, x1, y1, z1, rgb(70, 70, 72), M.Cardboard, parent, nc({ CastShadow = false }))
    local g = lit(surface(p, face, 24, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(62, 62, 66) }, g)   -- the dark shelf back
    local n = count or 10
    local run = 3 + (seed % 2)
    local w = 1 / n
    for k = 0, n - 1 do
        local pr = PRODUCTS[((seed * 5 + math.floor(k / run) * 3) % #PRODUCTS) + 1]
        local h = pr[3]
        local item = frame({ Size = UDim2.fromScale(w * 0.86, h), Position = UDim2.fromScale(k * w + w * 0.07, 1 - h),
            BackgroundColor3 = pr[1] }, g)
        frame({ Size = UDim2.fromScale(0.82, 0.3), Position = UDim2.fromScale(0.09, 0.36), BackgroundColor3 = pr[2] }, item)
        frame({ Size = UDim2.fromScale(1, 0.1), BackgroundColor3 = shade(pr[1], 0.6) }, item)
    end
    return p
end

-- (v3.3) a fridge shelf of bottles: rounded bottles, label band, cap
local function bottleRow(name, x0, y0, z0, x1, y1, z1, face, seed, parent)
    local p = box(name, x0, y0, z0, x1, y1, z1, rgb(196, 204, 212), M.Metal, parent, nc({ CastShadow = false }))
    local g = lit(surface(p, face, 30, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(196, 204, 212) }, g)
    local n = 6
    local w = 1 / n
    for k = 0, n - 1 do
        local d = DRINKS[((seed * 3 + math.floor(k / 3)) % #DRINKS) + 1]
        local b = frame({ Size = UDim2.fromScale(w * 0.62, 0.74), Position = UDim2.fromScale(k * w + w * 0.19, 0.26),
            BackgroundColor3 = d[1] }, g)
        UITheme.corner(b, 5)
        frame({ Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.4), BackgroundColor3 = d[2] }, b)
        frame({ Size = UDim2.fromScale(w * 0.28, 0.12), Position = UDim2.fromScale(k * w + w * 0.36, 0.14),
            BackgroundColor3 = d[3] }, g)
    end
    return p
end

-- a banknote on one face: pale green paper, engraved panel, portrait window, corner number
local BILL = rgb(186, 206, 168)
local BILL_INK = rgb(92, 128, 88)
local function billFace(p, face, number)
    local g = lit(surface(p, face, 60, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = BILL }, g)
    frame({ Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), BackgroundColor3 = BILL_INK,
        BackgroundTransparency = 0.55 }, g)
    local oval = frame({ Size = UDim2.fromScale(0.26, 0.64), Position = UDim2.fromScale(0.37, 0.18),
        BackgroundColor3 = rgb(214, 226, 200) }, g)
    UITheme.corner(oval, 999)
    if number then
        text({ Text = number, Size = UDim2.fromScale(0.22, 0.4), Position = UDim2.fromScale(0.05, 0.08), TextScaled = true,
            FontFace = UITheme.F.display, TextColor3 = rgb(40, 70, 44) }, g)
    end
    return g
end

-- banded cash stacks (the safe's loot visuals)
local function cashStack(parent, x, y, z, nx, nz, layers, band)
    for l = 0, layers - 1 do
        for i = 0, nx - 1 do
            for j = 0, nz - 1 do
                local bx = x + (i - (nx - 1) / 2) * 0.72
                local bz = z + (j - (nz - 1) / 2) * 0.36
                local brick = box("CashBrick", bx - 0.34, y + l * 0.26, bz - 0.16, bx + 0.34, y + l * 0.26 + 0.24, bz + 0.16,
                    BILL, M.Fabric, parent, nc({ CastShadow = false }))
                if l == layers - 1 then billFace(brick, Enum.NormalId.Top, "100") end
                box("CashBand", bx - 0.08, y + l * 0.26 - 0.005, bz - 0.17, bx + 0.08, y + l * 0.26 + 0.245, bz + 0.17,
                    band or rgb(214, 170, 60), M.Fabric, parent, nc({ CastShadow = false }))
            end
        end
    end
end

-- a till drawer, popped open toward +X (the customer side): bill slots + coin cups
local function tillDrawer(parent, x0, y, z0, x1, z1)
    box("Drawer", x0, y, z0, x1, y + 0.26, z1, rgb(40, 40, 46), M.Metal, parent, nc())
    box("DrawerFront", x1, y - 0.02, z0 - 0.03, x1 + 0.06, y + 0.3, z1 + 0.03, rgb(28, 28, 32), M.Metal, parent, nc())
    local slots = 5
    local w = (z1 - z0 - 0.08) / slots
    local billX1 = x0 + (x1 - x0) * 0.62
    for k = 0, slots - 1 do
        local sz0 = z0 + 0.04 + k * w
        box("Divider", x0 + 0.02, y + 0.26, sz0 - 0.01, billX1, y + 0.3, sz0 + 0.01, rgb(20, 20, 24), M.Metal, parent, nc())
        local b = box("Bills", x0 + 0.04, y + 0.2, sz0 + 0.02, billX1 - 0.03, y + 0.3, sz0 + w - 0.02, BILL, M.Fabric, parent,
            nc({ CastShadow = false }))
        billFace(b, Enum.NormalId.Top, ({ "1", "5", "10", "20", "50" })[k + 1])
        box("Clip", billX1 - 0.16, y + 0.3, sz0 + 0.03, billX1 - 0.12, y + 0.34, sz0 + w - 0.03, STEEL_LT, M.Metal, parent, nc())
    end
    local cups = 4
    local cw = (z1 - z0 - 0.08) / cups
    for k = 0, cups - 1 do
        local cz = z0 + 0.04 + (k + 0.5) * cw
        local cx = (billX1 + x1) / 2
        part({ Name = "CoinCup", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, cw * 0.8, cw * 0.8),
            CFrame = CFrame.new(cx, y + 0.2, cz) * CFrame.Angles(0, 0, math.rad(90)),
            Color = rgb(24, 24, 28), Material = M.Metal, CanCollide = false, CastShadow = false }, parent)
        part({ Name = "Coins", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, cw * 0.62, cw * 0.62),
            CFrame = CFrame.new(cx, y + 0.28, cz) * CFrame.Angles(0, 0, math.rad(90)),
            Color = (k == 3) and rgb(184, 110, 70) or rgb(196, 200, 206), Material = M.Metal, Reflectance = 0.35,
            CanCollide = false, CastShadow = false }, parent)
    end
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL
-- ──────────────────────────────────────────────
function MartBuilder:_shell(f)
    -- sidewalk apron in front (the south sidewalk ends at z -1.4) + a tiled entry pad
    box("Apron", X0, 0, -1.4, X1, FLOOR, Z0, rgb(168, 166, 160), M.Concrete, f)
    box("EntryPad", ENT_X0 - 1, FLOOR, -1.2, ENT_X1 + 1, FLOOR + 0.03, Z0, rgb(120, 118, 114), M.Slate, f, nc({ CastShadow = false }))
    -- floors
    box("FloorSales", X0, 0, Z0, X1, FLOOR, BACK_Z0, FLOOR_TILE, M.CeramicTiles, f)
    box("FloorOffice", BX0, 0, BACK_Z0, 60, FLOOR, Z1, rgb(92, 70, 52), M.WoodPlanks, f)
    box("FloorStock", 60, 0, BACK_Z0, X1, FLOOR, Z1, rgb(128, 128, 124), M.Concrete, f)

    -- exterior walls: warm white stucco (the front is the facade)
    box("WallWest", X0, FLOOR, Z0, IX0, TOP, BACK_Z0, STUCCO, M.Plaster, f)
    box("WallWestReturn", BX0, FLOOR, SALES_Z1, X0, TOP, BACK_Z0, STUCCO, M.Plaster, f)
    box("WallWestBack", BX0, FLOOR, SALES_Z1, BIX0, TOP, Z1, STUCCO, M.Plaster, f)
    box("WallSouth", BIX0, FLOOR, IZ1, IX1, TOP, Z1, STUCCO, M.Plaster, f)
    box("WallEast", IX1, FLOOR, Z0, X1, TOP, NOTCH_Z0, STUCCO, M.Plaster, f)
    box("WallEastNotch", IX1, FLOOR, NOTCH_Z0, X1, ROOF_Y, NOTCH_Z1, STUCCO, M.Plaster, f)   -- parapet notch over the ladder
    box("WallEast", IX1, FLOOR, NOTCH_Z1, X1, TOP, LOAD_Z0, STUCCO, M.Plaster, f)
    box("LoadDoorHeader", IX1, DOOR_H, LOAD_Z0, X1, TOP, LOAD_Z1, STUCCO, M.Plaster, f)
    box("WallEast", IX1, FLOOR, LOAD_Z1, X1, TOP, Z1, STUCCO, M.Plaster, f)
    -- teal base band + a thin yellow line over it, stucco coping on the parapet
    local function band(name, x0, z0, x1, z1)
        box(name, x0, 0, z0, x1, 2.2, z1, TEAL, M.Plaster, f, nc())
    end
    band("BaseBand", X0 - 0.1, Z0, X0, BACK_Z0)
    band("BaseBand", BX0, SALES_Z1 - 0.1, X0, SALES_Z1)
    band("BaseBand", BX0 - 0.1, SALES_Z1 - 0.1, BX0, Z1 + 0.1)
    band("BaseBand", BX0, Z1, X1, Z1 + 0.1)
    band("BaseBand", X1, Z0, X1 + 0.1, NOTCH_Z0 - 0.2)
    band("BaseBand", X1, LOAD_Z1 + 0.3, X1 + 0.1, Z1 - 0.6)
    box("BandLine", X0 - 0.12, 2.2, Z0, X0, 2.45, BACK_Z0, SUNNY, M.Plaster, f, nc())
    box("CopingW", X0 - 0.15, TOP, Z0 - 0.4, IX0 + 0.05, TOP + 0.3, SALES_Z1 - 0.15, STUCCO_DK, M.Plaster, f)
    box("CopingW", BX0 - 0.15, TOP, SALES_Z1 - 0.15, X0 - 0.15, TOP + 0.3, BACK_Z0 + 0.05, STUCCO_DK, M.Plaster, f)
    box("CopingW", BX0 - 0.15, TOP, BACK_Z0 + 0.05, BIX0 + 0.05, TOP + 0.3, Z1 + 0.15, STUCCO_DK, M.Plaster, f)
    box("CopingE", IX1 - 0.05, TOP, Z0 - 0.4, X1 + 0.15, TOP + 0.3, NOTCH_Z0, STUCCO_DK, M.Plaster, f)
    box("CopingE", IX1 - 0.05, TOP, NOTCH_Z1, X1 + 0.15, TOP + 0.3, Z1 + 0.15, STUCCO_DK, M.Plaster, f)
    box("CopingS", BIX0 + 0.05, TOP, IZ1 - 0.05, IX1 - 0.05, TOP + 0.3, Z1 + 0.15, STUCCO_DK, M.Plaster, f)

    -- the west wall faces the car alley: a clean painted sun mural in the brand colours
    local mural = box("Mural", X0 - 0.06, 3, 2.5, X0, 14.5, 18, TEAL, M.Plaster, f, nc())
    local mg = lit(surface(mural, Enum.NormalId.Left, 12, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAL }, mg)
    local sun = frame({ Size = UDim2.fromScale(0.34, 0.46), Position = UDim2.fromScale(0.33, 0.12), BackgroundColor3 = SUNNY }, mg)
    UITheme.corner(sun, 999)
    frame({ Size = UDim2.fromScale(1, 0.06), Position = UDim2.fromScale(0, 0.62), BackgroundColor3 = SUNNY_DK }, mg)
    text({ Text = "SUNNY'S", Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.7),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 246, 236) }, mg)

    -- ceiling + roof deck
    box("Ceiling", IX0, CEIL, IZ0, IX1, CEIL + 0.5, BACK_Z0, CEIL_COL, M.Plaster, f)
    box("Ceiling", BIX0, CEIL, BACK_Z0, IX1, CEIL + 0.5, IZ1, CEIL_COL, M.Plaster, f)
    box("Roof", IX0, CEIL + 0.5, IZ0, IX1, ROOF_Y, BACK_Z0, rgb(150, 150, 150), M.Concrete, f)
    box("Roof", BIX0, CEIL + 0.5, BACK_Z0, IX1, ROOF_Y, IZ1, rgb(150, 150, 150), M.Concrete, f)
    box("RoofLip", IX1, ROOF_Y - 0.5, NOTCH_Z0, X1, ROOF_Y, NOTCH_Z1, rgb(150, 150, 150), M.Concrete, f)
    box("RoofAC", 63, ROOF_Y, 8, 67, ROOF_Y + 2.6, 11.5, STEEL_LT, M.Metal, f)
    box("RoofACFan", 63.8, ROOF_Y + 2.6, 8.7, 66.2, ROOF_Y + 2.7, 10.8, STEEL_DK, M.Metal, f, nc())
    part({ Name = "VentStack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.8, 0.8),
        CFrame = CFrame.new(68, ROOF_Y + 0.8, 24) * CFrame.Angles(0, 0, math.rad(90)),
        Color = STEEL_LT, Material = M.Metal }, f)

    -- interior walls: sales floor back wall (curtain doorway) + the office | stock wall (door)
    wallX("SalesBackWall", SALES_Z1, BACK_Z0, IX0, IX1, { { CURTAIN_X0, CURTAIN_X1, DOOR_H } }, WALL_IN, M.Plaster, f)
    wallZ("OfficeWall", OFFICE_X1, STOCK_X0, BACK_Z0, IZ1, { { OFFICE_DOOR_Z0, OFFICE_DOOR_Z1, DOOR_H } }, WALL_IN, M.Plaster, f)
end

-- ──────────────────────────────────────────────
-- ☀️ FACADE: lit windows, SUNNY'S sign, awning, posters, OPEN sign
-- ──────────────────────────────────────────────
function MartBuilder:_facade(f)
    local fa = Instance.new("Folder")
    fa.Name = "Facade"
    fa.Parent = f

    box("PierW", X0, FLOOR, ZF - 0.2, X0 + 1.5, TOP, IZ0, TEAL, M.Plaster, fa)
    box("PierE", X1 - 1.5, FLOOR, ZF - 0.2, X1, TOP, IZ0, TEAL, M.Plaster, fa)
    box("DoorPierW", ENT_X0 - 0.8, FLOOR, ZF, ENT_X0, WIN_TOP + 0.5, IZ0, TEAL, M.Plaster, fa)
    box("DoorPierE", ENT_X1, FLOOR, ZF, ENT_X1 + 0.8, WIN_TOP + 0.5, IZ0, TEAL, M.Plaster, fa)

    -- two window bays; clean posters stuck on the inside of the glass (low,
    -- so the lit store shows above them)
    local posters = {
        { "ICE COLD", "DRINKS", TEAL, TEAL_DK }, { "LOTTO", "TICKETS HERE", SUNNY_DK, rgb(150, 40, 40) },
        { "2 FOR $3", "ALL CHIPS", rgb(206, 48, 52), rgb(150, 30, 34) }, { "HOT", "COFFEE", SUNNY_DK, rgb(110, 60, 30) },
    }
    local pi = 0
    for _, bay in ipairs({ { X0 + 1.5, ENT_X0 - 0.8 }, { ENT_X1 + 0.8, X1 - 1.5 } }) do
        local b0, b1 = bay[1], bay[2]
        box("Sill", b0, FLOOR, ZF + 0.15, b1, FLOOR + 1.4, IZ0, TEAL, M.Plaster, fa)
        box("SillCap", b0, FLOOR + 1.4, ZF, b1, FLOOR + 1.55, IZ0, STUCCO_DK, M.Plaster, fa)
        box("ShopWindow", b0, FLOOR + 1.55, 1.3, b1, WIN_TOP, 1.5, rgb(200, 222, 232), M.Glass, fa,
            { Transparency = 0.6, Reflectance = 0.15 })
        local mx = (b0 + b1) / 2
        box("Mullion", mx - 0.1, FLOOR + 1.55, 1.2, mx + 0.1, WIN_TOP, 1.6, STEEL_LT, M.Metal, fa)
        box("WindowHead", b0, WIN_TOP, 1.2, b1, WIN_TOP + 0.5, 1.6, STEEL_LT, M.Metal, fa)
        for k = 0, 1 do
            pi = pi + 1
            local px = b0 + (b1 - b0) * (k == 0 and 0.27 or 0.73)
            local ps = posters[pi]
            poster("WindowPoster", px - 1, FLOOR + 1.8, 1.52, px + 1, FLOOR + 4.6, 1.56, Enum.NormalId.Front,
                ps[1], ps[2], ps[3], ps[4], fa)
        end
        -- the store's own glow behind the glass (a lit window from the sidewalk)
        point(lightAnchor("WindowGlow", Vector3.new(mx, FLOOR + 8, 3.2), fa), WARM, 0.3, 9)
    end

    -- entrance: automatic sliding glass doors, parked open behind the window glass
    box("DoorFrameTop", ENT_X0, ENT_TOP, ZF, ENT_X1, WIN_TOP + 0.5, IZ0, STEEL_LT, M.Metal, fa)
    box("DoorTrack", ENT_X0 - 4.2, ENT_TOP - 0.5, 1.95, ENT_X1 + 4.2, ENT_TOP, 2.2, STEEL_LT, M.Metal, fa, nc())
    for _, side in ipairs({ -1, 1 }) do
        local a0 = side < 0 and ENT_X0 - 4 or ENT_X1
        local a1 = side < 0 and ENT_X0 or ENT_X1 + 4
        box("SlidingDoor", a0, FLOOR + 1.55, 2.02, a1, ENT_TOP - 0.5, 2.12, rgb(200, 222, 232), M.Glass, fa,
            nc({ Transparency = 0.6, Reflectance = 0.15 }))
        box("SlidingDoorRail", a0, FLOOR + 1.55, 2.0, a1, FLOOR + 1.9, 2.14, STEEL_LT, M.Metal, fa, nc())
    end
    box("DoorSensor", CX - 0.6, ENT_TOP - 0.4, 1.7, CX + 0.6, ENT_TOP - 0.1, 2, STEEL_DK, M.Metal, fa, nc())
    box("SensorLed", CX + 0.3, ENT_TOP - 0.45, 1.75, CX + 0.45, ENT_TOP - 0.4, 1.9, rgb(80, 255, 120), M.Neon, fa, nc())
    local mat = box("DoorMat", ENT_X0 + 0.8, FLOOR, IZ0 + 0.1, ENT_X1 - 0.8, FLOOR + 0.06, IZ0 + 2.4, rgb(34, 38, 40), M.Fabric, fa, nc())
    local mg = lit(surface(mat, Enum.NormalId.Top, 12, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(34, 38, 40) }, mg)
    text({ Text = "WELCOME", Size = UDim2.fromScale(0.8, 0.5), Position = UDim2.fromScale(0.1, 0.25), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = SUNNY, Rotation = 180 }, mg)
    -- hours decal on the door glass
    poster("HoursDecal", ENT_X1 + 0.9, FLOOR + 5, 1.52, ENT_X1 + 2.3, FLOOR + 6.6, 1.55, Enum.NormalId.Front,
        "OPEN 24/7", "every day", TEAL, TEAL_DK, fa)

    -- fascia: stucco band with a teal stripe + a yellow pinstripe
    box("Fascia", X0 + 1.5, WIN_TOP + 0.5, ZF, X1 - 1.5, TOP, IZ0, STUCCO, M.Plaster, fa)
    box("FasciaStripe", X0 + 1.5, WIN_TOP + 0.5, ZF - 0.1, X1 - 1.5, WIN_TOP + 1.1, ZF, TEAL, M.Plaster, fa)
    box("FasciaPin", X0 + 1.5, WIN_TOP + 1.1, ZF - 0.1, X1 - 1.5, WIN_TOP + 1.25, ZF, SUNNY, M.Plaster, fa, nc())
    box("SignTower", CX - 7.5, TOP, ZF, CX + 7.5, 20.5, IZ0, STUCCO, M.Plaster, fa)
    box("TowerCap", CX - 7.8, 20.5, ZF - 0.3, CX + 7.8, 20.9, IZ0, STUCCO_DK, M.Plaster, fa)

    -- ── the sign: SUNNY'S (backlit panel; neon only on the thin border) ──
    local sx0, sx1, sy0, sy1 = CX - 7, CX + 7, 12.4, 20
    local board = box("SignBoard", sx0, sy0, ZF - 0.25, sx1, sy1, ZF, TEAL_DK, M.Metal, fa)
    local sg = surface(board, Enum.NormalId.Front, 36, 1.5)
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAL_DK }, sg)
    local sunIcon = frame({ Size = UDim2.fromOffset(110, 110), Position = UDim2.fromOffset(30, 70),
        BackgroundColor3 = SUNNY }, sg)
    UITheme.corner(sunIcon, 55)
    for r = 0, 7 do
        local a = r * math.pi / 4
        frame({ Size = UDim2.fromOffset(12, 40), Position = UDim2.fromOffset(85 + 78 * math.sin(a), 125 - 78 * math.cos(a)),
            AnchorPoint = Vector2.new(0.5, 0.5), Rotation = math.deg(a), BackgroundColor3 = SUNNY_DK }, sg)
    end
    local name = text({ Text = "Sunny's", Size = UDim2.fromScale(0.64, 0.62), Position = UDim2.fromScale(0.33, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true,
        FontFace = Font.new("rbxasset://fonts/families/Kalam.json", Enum.FontWeight.Bold),
        TextColor3 = SUNNY }, sg)
    local stroke = Instance.new("UIStroke")
    stroke.Color = rgb(120, 60, 10)
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    stroke.Parent = name
    text({ Text = "MART  ·  OPEN 24/7", Size = UDim2.fromScale(0.6, 0.18), Position = UDim2.fromScale(0.35, 0.72),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(244, 244, 236) }, sg)
    local oz = ZF - 0.32
    tube("SignTube", Vector3.new(sx0, sy1, oz), Vector3.new(sx1, sy1, oz), SUNNY, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx1, sy0, oz), SUNNY, fa)
    tube("SignTube", Vector3.new(sx0, sy0, oz), Vector3.new(sx0, sy1, oz), SUNNY, fa)
    tube("SignTube", Vector3.new(sx1, sy0, oz), Vector3.new(sx1, sy1, oz), SUNNY, fa)
    point(lightAnchor("SignGlow", Vector3.new(CX, 15.5, ZF - 2), fa), rgb(255, 214, 140), 1.3, 14)

    -- striped awning over the door (teal / white), under the sign
    local ax0, ax1, n = CX - 5, CX + 5, 5
    local w = (ax1 - ax0) / n
    local back = Vector3.new(0, 11.5, ZF)
    local front = Vector3.new(0, 10.7, ZF - 2)
    local dir = front - back
    for i = 1, n do
        local x = ax0 + (i - 0.5) * w
        local col = (i % 2 == 1) and TEAL or rgb(240, 238, 230)
        local mid = Vector3.new(x, (back.Y + front.Y) / 2, (back.Z + front.Z) / 2)
        part({ Name = "AwningStripe", Size = Vector3.new(w, 0.14, dir.Magnitude), CFrame = CFrame.lookAt(mid, mid + dir),
            Color = col, Material = M.Fabric, CanCollide = false }, fa)
        box("AwningValance", x - w / 2, 10.3, front.Z - 0.07, x + w / 2, 10.75, front.Z + 0.05, col, M.Fabric, fa, nc())
    end
    local lamp = box("DoorLamp", CX - 0.5, ENT_TOP - 0.3, ZF - 0.4, CX + 0.5, ENT_TOP, ZF, STEEL_DK, M.Metal, fa, nc())
    spot(lamp, Enum.NormalId.Bottom, WARM, 1.2, 13, 110, true)

    -- outside, off the entrance lane (arrival rows stand at x 58..66):
    -- ice chest west, trash can + newspaper box east
    local ice = box("IceChest", X0 + 0.6, FLOOR, -1.1, X0 + 4, 4, 0.5, rgb(226, 234, 240), M.Metal, fa)
    lit(printOn(ice, Enum.NormalId.Front, "ICE", rgb(30, 110, 200), UITheme.F.display, 40, 1).Parent)
    box("IceChestLid", X0 + 0.5, 4, -1.2, X0 + 4.1, 4.25, 0.6, TEAL, M.Metal, fa)
    part({ Name = "TrashCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.6, 1.6),
        CFrame = CFrame.new(ENT_X1 + 3.4, 2, -0.3) * CFrame.Angles(0, 0, math.rad(90)),
        Color = TEAL_DK, Material = M.Metal }, fa)
    local paper = box("NewsBox", X1 - 3.4, FLOOR, -1, X1 - 1.8, 3.6, 0.3, rgb(40, 90, 170), M.Metal, fa)
    lit(printOn(paper, Enum.NormalId.Front, "NEWS", rgb(240, 240, 240), UITheme.F.bold, 50, 1).Parent)

    -- ── OPEN / CLOSED sign in the east window (thin neon border) ──
    local ox0, ox1, oy0, oy1 = 68.2, 71.2, 7.6, 8.9
    local oz0, oz1 = 1.52, 1.66
    local osign = box("OpenSign", ox0, oy0, oz0, ox1, oy1, oz1, rgb(16, 12, 22), M.Metal, fa, nc())
    local og = surface(osign, Enum.NormalId.Front, 60, 1.6)
    local olabel = text({ Text = "CLOSED", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display }, og)
    local oTubes = {
        box("OpenTube", ox0 - 0.12, oy1, oz0, ox1 + 0.12, oy1 + 0.12, oz1, SUNNY, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.12, oy0 - 0.12, oz0, ox1 + 0.12, oy0, oz1, SUNNY, M.Neon, fa, nc()),
        box("OpenTube", ox0 - 0.12, oy0, oz0, ox0, oy1, oz1, SUNNY, M.Neon, fa, nc()),
        box("OpenTube", ox1, oy0, oz0, ox1 + 0.12, oy1, oz1, SUNNY, M.Neon, fa, nc()),
    }
    local oglow = point(osign, rgb(255, 200, 110), 0.8, 7)
    local function openSign(open)
        olabel.Text = open and "OPEN" or "CLOSED"
        olabel.TextColor3 = open and rgb(255, 214, 120) or rgb(150, 60, 50)
        for _, t in ipairs(oTubes) do
            t.Material = open and M.Neon or M.Metal
            t.Color = open and SUNNY or rgb(70, 60, 50)
        end
        oglow.Enabled = open
    end
    openSign(false)
    return openSign
end

-- ──────────────────────────────────────────────
-- 🛒 SALES FLOOR
-- ──────────────────────────────────────────────
-- the double-sided gondola island (x 61.5..63.5, z 8..13): 6-wide aisles both sides
function MartBuilder:_island(f)
    local g = Instance.new("Model")
    g.Name = "Island"
    g.Parent = f
    local x0, x1, z0, z1 = ISLAND_X0, ISLAND_X1, ISLAND_Z0, ISLAND_Z1
    local mid = (x0 + x1) / 2
    local H = FLOOR + 6
    box("Kick", x0, FLOOR, z0, x1, FLOOR + 0.5, z1, rgb(60, 64, 72), M.Metal, g)
    box("Spine", mid - 0.1, FLOOR + 0.5, z0, mid + 0.1, H, z1, rgb(150, 154, 158), M.Metal, g)
    for li, y in ipairs({ FLOOR + 0.5, FLOOR + 1.9, FLOOR + 3.3, FLOOR + 4.7 }) do
        box("Shelf", x0, y - 0.08, z0, x1, y, z1, SHELF_COL, M.Metal, g)
        productRow("ProductsW", x0 + 0.05, y, z0 + 0.1, mid - 0.1, y + 1.15, z1 - 0.1, Enum.NormalId.Left, li, g, 10)
        productRow("ProductsE", mid + 0.1, y, z0 + 0.1, x1 - 0.05, y + 1.15, z1 - 0.1, Enum.NormalId.Right, li + 4, g, 10)
        box("PriceStrip", x0 - 0.03, y - 0.26, z0, x0, y - 0.08, z1, SUNNY, M.Plastic, g, nc({ CastShadow = false }))
        box("PriceStrip", x1, y - 0.26, z0, x1 + 0.03, y - 0.08, z1, SUNNY, M.Plastic, g, nc({ CastShadow = false }))
    end
    -- end caps (north = toward the door, south = toward the back)
    for _, e in ipairs({ { z0 - 0.4, z0, Enum.NormalId.Front, "CHIPS & SNACKS" }, { z1, z1 + 0.4, Enum.NormalId.Back, "CANDY & COOKIES" } }) do
        box("EndCapBody", x0, FLOOR, e[1], x1, H - 0.8, e[2], rgb(60, 64, 72), M.Metal, g)
        for s = 0, 2 do
            local y = FLOOR + 0.8 + s * 1.5
            productRow("EndCapStock", x0 + 0.1, y, e[1] - 0.02, x1 - 0.1, y + 1.1, e[2] + 0.02, e[3], 7 + s, g, 4)
        end
        sign("EndCapSign", x0, H - 0.8, e[1], x1, H + 0.4, e[2], e[3], e[4], TEAL, rgb(250, 246, 236), g)
    end
    -- hanging aisle sign
    local zc = (z0 + z1) / 2
    local hs = box("AisleSign", mid - 0.05, CEIL - 3.2, zc - 2.2, mid + 0.05, CEIL - 2, zc + 2.2, TEAL, M.Metal, g, nc())
    lit(printOn(hs, Enum.NormalId.Left, "SNACKS", rgb(250, 246, 236), UITheme.F.display, 40, 1).Parent)
    lit(printOn(hs, Enum.NormalId.Right, "CANDY", rgb(250, 246, 236), UITheme.F.display, 40, 1).Parent)
    for _, dz in ipairs({ -2, 2 }) do
        bar("SignWire", Vector3.new(mid, CEIL - 2, zc + dz), Vector3.new(mid, CEIL, zc + dz), 0.05, STEEL_DK, M.Metal, g, nc())
    end
end

-- drinks fridges down the east wall: stainless frame, glass doors, lit inside, bottles
function MartBuilder:_fridges(f)
    local fr = Instance.new("Folder")
    fr.Name = "Fridges"
    fr.Parent = f
    local x0, x1 = FRIDGE_X0, IX1
    local z0, z1 = FRIDGE_Z0, FRIDGE_Z1
    local H = FLOOR + 7.4
    local STAINLESS = rgb(150, 156, 164)
    box("FridgeBody", x0 + 0.25, FLOOR, z0, x1, H, z1, STAINLESS, M.Metal, fr)
    box("FridgeInside", x0 + 0.3, FLOOR + 0.4, z0 + 0.1, x0 + 0.34, H - 0.2, z1 - 0.1, rgb(214, 220, 226), M.Metal, fr, nc())
    box("FridgeKick", x0, FLOOR, z0, x0 + 0.3, FLOOR + 0.4, z1, rgb(40, 42, 46), M.Metal, fr, nc())
    local hdr = box("FridgeHeader", x0, H, z0, x1, H + 1.2, z1, TEAL, M.Metal, fr)
    lit(printOn(hdr, Enum.NormalId.Left, "ICE COLD DRINKS", rgb(250, 246, 236), UITheme.F.display, 30, 1).Parent)
    local doors = 5
    local dw = (z1 - z0) / doors
    for d = 0, doors - 1 do
        local dz0, dz1 = z0 + d * dw, z0 + (d + 1) * dw
        for s = 0, 4 do
            local y = FLOOR + 0.6 + s * 1.3
            bottleRow("Drinks", x0 + 0.34, y, dz0 + 0.15, x0 + 1.1, y + 1.05, dz1 - 0.15, Enum.NormalId.Left, d * 5 + s, fr)
            box("FridgeShelf", x0 + 0.3, y - 0.05, dz0 + 0.1, x1 - 0.2, y, dz1 - 0.1, rgb(176, 182, 188), M.Metal, fr, nc())
        end
        box("FridgeGlass", x0, FLOOR + 0.4, dz0 + 0.1, x0 + 0.08, H - 0.1, dz1 - 0.1, rgb(214, 234, 244), M.Glass, fr,
            { Transparency = 0.65, Reflectance = 0.12 })
        box("DoorFrame", x0 - 0.04, FLOOR + 0.4, dz1 - 0.1, x0 + 0.14, H - 0.1, dz1 + 0.1, STAINLESS, M.Metal, fr, nc())
        box("DoorFrameTop", x0 - 0.04, H - 0.2, dz0, x0 + 0.14, H - 0.05, dz1, STAINLESS, M.Metal, fr, nc())
        bar("FridgeHandle", Vector3.new(x0 - 0.14, FLOOR + 2.6, dz1 - 0.38), Vector3.new(x0 - 0.14, FLOOR + 5.2, dz1 - 0.38),
            0.1, STEEL_LT, M.Metal, fr, nc())
        -- thin LED strip down each door frame
        box("FridgeLed", x0 + 0.1, FLOOR + 0.5, dz0 + 0.12, x0 + 0.16, H - 0.25, dz0 + 0.18, rgb(190, 214, 236), M.Neon, fr,
            nc({ CastShadow = false }))
    end
    box("DoorFrame", x0 - 0.04, FLOOR + 0.4, z0 - 0.1, x0 + 0.14, H - 0.1, z0 + 0.1, STAINLESS, M.Metal, fr, nc())
    -- the cold light inside (one soft glow for the bank)
    point(lightAnchor("FridgeGlow", Vector3.new(x0 + 0.6, FLOOR + 4.5, (z0 + z1) / 2), fr), rgb(200, 226, 255), 0.35, 8)
end

-- the counter (registers), the clerk's shelves + the SCRATCH & WIN dispenser
function MartBuilder:_checkout(f, refs, loot)
    local c = Instance.new("Folder")
    c.Name = "Checkout"
    c.Parent = f
    local topY = FLOOR + 3.3
    box("CounterBody", COUNTER_X0, FLOOR, COUNTER_Z0, COUNTER_X1, topY - 0.2, COUNTER_Z1, WAINSCOT, M.Plaster, c)
    box("CounterKick", COUNTER_X1, FLOOR, COUNTER_Z0, COUNTER_X1 + 0.05, FLOOR + 0.5, COUNTER_Z1, STEEL_DK, M.Metal, c, nc())
    box("CounterTop", COUNTER_X0 - 0.1, topY - 0.2, COUNTER_Z0 - 0.1, COUNTER_X1 + 0.1, topY, COUNTER_Z1 + 0.1,
        rgb(206, 200, 190), M.Marble, c)
    local front = box("CounterFront", COUNTER_X1, FLOOR + 0.9, COUNTER_Z0 + 2.5, COUNTER_X1 + 0.05, topY - 0.5, COUNTER_Z1 - 2.5,
        SUNNY, M.Plaster, c, nc())
    lit(printOn(front, Enum.NormalId.Right, "THANK YOU!", TEAL_DK, UITheme.F.display, 30, 1).Parent)

    -- two registers, 6.8 studs apart (Register loot = the popped-open till)
    for k, rz in ipairs(REGISTER_Z) do
        local rx = (COUNTER_X0 + COUNTER_X1) / 2
        box("Register", rx - 0.7, topY, rz - 0.55, rx + 0.5, topY + 0.7, rz + 0.55, rgb(34, 34, 40), M.Metal, c)
        local screen = part({ Name = "RegisterScreen", Size = Vector3.new(0.08, 0.7, 1.1),
            CFrame = CFrame.new(rx - 0.4, topY + 1.25, rz) * CFrame.Angles(0, 0, math.rad(-15)),
            Color = rgb(20, 22, 26), Material = M.Metal, CanCollide = false }, c)
        local sg = surface(screen, Enum.NormalId.Left, 80, 0.8)
        frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(10, 24, 18) }, sg)
        text({ Text = "$0.00", Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1),
            TextXAlignment = Enum.TextXAlignment.Right, TextScaled = true, FontFace = UITheme.F.mono,
            TextColor3 = UITheme.C.money }, sg)
        local drawer = Instance.new("Model")
        drawer.Name = "RegisterCash" .. k
        drawer.Parent = c
        tillDrawer(drawer, rx + 0.5, topY + 0.02, rz - 0.5, rx + 1.3, rz + 0.5)
        local stand = Vector3.new(REG_STAND_X, FLOOR + 3, rz)
        table.insert(loot, { kind = "Register", cframe = CFrame.lookAt(stand, Vector3.new(rx, stand.Y, rz)),
            visual = drawer, interact = "stuff", pool = "counter", inVault = false })
    end
    -- a gum + mints rack on the counter between them
    local gum = box("GumRack", COUNTER_X1 - 0.9, topY, 6.2, COUNTER_X1 - 0.1, topY + 1.2, 7.8, STEEL_LT, M.Metal, c, nc())
    productRow("Gum", COUNTER_X1 - 0.12, topY + 0.1, 6.25, COUNTER_X1 - 0.08, topY + 1.1, 7.75, Enum.NormalId.Right, 5, c, 5)
    gum.CanCollide = false

    -- behind the clerk (west wall): two stocked wall shelves + the dispenser
    local dz0, dz1 = DISP_Z - 1.15, DISP_Z + 1.15
    for _, span in ipairs({ { IZ0 + 0.3, dz0 - 0.4 }, { dz1 + 0.4, COUNTER_Z1 } }) do
        box("BackShelf", IX0, FLOOR, span[1], IX0 + 0.9, FLOOR + 7.2, span[2], WALNUT, M.Wood, c)
        for s = 0, 3 do
            local y = FLOOR + 1 + s * 1.5
            box("BackShelfBoard", IX0 + 0.9, y - 0.08, span[1], IX0 + 1.1, y, span[2], SHELF_COL, M.Metal, c, nc())
            productRow("WallProducts", IX0 + 0.9, y, span[1] + 0.1, IX0 + 0.95, y + 1.1, span[2] - 0.1, Enum.NormalId.Right, 11 + s, c, 7)
        end
    end
    -- the SCRATCH & WIN dispenser: 9 clear bins, a roll of tickets in each
    box("DispenserBack", IX0, FLOOR + 2.2, dz0, IX0 + 0.25, FLOOR + 6.7, dz1, rgb(22, 20, 28), M.Metal, c)
    local tickets = Instance.new("Model")
    tickets.Name = "ScratchTickets"
    tickets.Parent = c
    local games = {
        { "$$$", rgb(40, 170, 90) },  { "LUCKY 7", rgb(220, 40, 60) },  { "GOLD RUSH", rgb(230, 170, 30) },
        { "BINGO", rgb(40, 110, 220) }, { "WIN $500", rgb(160, 60, 200) }, { "HOT CASH", rgb(250, 110, 30) },
        { "x10", rgb(20, 160, 170) },  { "SUNNY $", rgb(250, 200, 40) },  { "JACKPOT", rgb(230, 60, 150) },
    }
    local bw = (dz1 - dz0) / 3
    for row = 0, 2 do
        for col = 0, 2 do
            local k = row * 3 + col + 1
            local by = FLOOR + 5.25 - row * 1.45
            local bz = dz0 + (col + 0.5) * bw
            box("BinWall", IX0 + 0.25, by - 0.5, bz - bw / 2, IX0 + 0.9, by + 0.55, bz - bw / 2 + 0.04, rgb(40, 40, 48), M.Metal, c, nc())
            box("BinShelf", IX0 + 0.25, by - 0.52, bz - bw / 2, IX0 + 0.9, by - 0.48, bz + bw / 2, rgb(40, 40, 48), M.Metal, c, nc())
            box("BinFront", IX0 + 0.86, by - 0.3, bz - bw / 2 + 0.04, IX0 + 0.9, by + 0.55, bz + bw / 2, rgb(210, 230, 240), M.Glass, c,
                nc({ Transparency = 0.6, Reflectance = 0.2, CastShadow = false }))
            part({ Name = "TicketRoll", Shape = Enum.PartType.Cylinder, Size = Vector3.new(bw - 0.14, 0.62, 0.62),
                CFrame = CFrame.new(IX0 + 0.58, by + 0.05, bz) * CFrame.Angles(0, math.rad(90), 0),
                Color = games[k][2], Material = M.Fabric, CanCollide = false, CastShadow = false }, tickets)
            local strip = box("TicketStrip", IX0 + 0.92, by - 1.05, bz - bw / 2 + 0.1, IX0 + 0.95, by - 0.28, bz + bw / 2 - 0.08,
                games[k][2], M.Fabric, tickets, nc({ CastShadow = false }))
            local sg = lit(surface(strip, Enum.NormalId.Right, 60, 1))
            frame({ Size = UDim2.fromScale(0.86, 0.34), Position = UDim2.fromScale(0.07, 0.08),
                BackgroundColor3 = rgb(200, 204, 210) }, sg)
            text({ Text = games[k][1], Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.5), TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = rgb(255, 255, 255) }, sg)
        end
    end
    box("BinWall", IX0 + 0.25, FLOOR + 1.3, dz1 - 0.04, IX0 + 0.9, FLOOR + 6.3, dz1, rgb(40, 40, 48), M.Metal, c, nc())
    box("DispenserTrim", IX0 + 0.25, FLOOR + 6.3, dz0, IX0 + 0.95, FLOOR + 6.45, dz1, rgb(212, 172, 92), M.Metal, c, nc())
    sign("LottoSign", IX0 + 0.9, FLOOR + 6.6, dz0 + 0.05, IX0 + 1, FLOOR + 7.5, dz1 - 0.05, Enum.NormalId.Right,
        "SCRATCH & WIN", SUNNY, rgb(120, 20, 60), c)
    -- (v3.3) stand 5.2 / 3.4 from both register stands = 6.2 apart
    local lstand = Vector3.new(IX0 + 1.9, FLOOR + 3, DISP_Z)
    table.insert(loot, { kind = "ScratchTickets", cframe = CFrame.lookAt(lstand, Vector3.new(IX0, lstand.Y, DISP_Z)),
        visual = tickets, pool = "counter", inVault = false })

    -- the clerk's stool (the clerk himself is decorative / optional — none yet)
    part({ Name = "Stool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.4, 1.4),
        CFrame = CFrame.new(IX0 + 1.1, FLOOR + 2.4, 9.4) * CFrame.Angles(0, 0, math.rad(90)),
        Color = TEAL, Material = M.Leather }, c)
    bar("StoolLeg", Vector3.new(IX0 + 1.1, FLOOR, 9.4), Vector3.new(IX0 + 1.1, FLOOR + 2.25, 9.4), 0.2, STEEL_LT, M.Metal, c, nc())
end

-- 🧊 the ice-cream chest freezer in the back-west corner (+ the SECRET STASH, ~1 run in 20)
function MartBuilder:_freezer(f, loot)
    local c = Instance.new("Folder")
    c.Name = "Freezer"
    c.Parent = f
    local fx0, fx1, fz0, fz1 = IX0 + 0.1, 56.4, 16.8, SALES_Z1 - 0.05
    local fTop = FLOOR + 3
    local FRZ = rgb(186, 194, 200)
    box("IceCreamFreezer", fx0, FLOOR, fz0, fx1, FLOOR + 1.9, fz1, FRZ, M.Metal, c)
    box("FreezerWall", fx0, FLOOR + 1.9, fz0, fx1, fTop, fz0 + 0.2, FRZ, M.Metal, c)
    box("FreezerWall", fx0, FLOOR + 1.9, fz1 - 0.2, fx1, fTop, fz1, FRZ, M.Metal, c)
    box("FreezerWall", fx0, FLOOR + 1.9, fz0 + 0.2, fx0 + 0.2, fTop, fz1 - 0.2, FRZ, M.Metal, c)
    box("FreezerWall", fx1 - 0.2, FLOOR + 1.9, fz0 + 0.2, fx1, fTop, fz1 - 0.2, FRZ, M.Metal, c)
    box("FrostRim", fx0 + 0.2, fTop - 0.12, fz0 + 0.2, fx1 - 0.2, fTop - 0.05, fz0 + 0.28, rgb(236, 244, 250), M.Ice, c, nc())
    box("FreezerLid", fx0 + 0.1, fTop, fz0 + 0.1, fx1 - 0.1, fTop + 0.1, fz1 - 0.1, rgb(210, 232, 244), M.Glass, c,
        { Transparency = 0.6, Reflectance = 0.2 })
    point(lightAnchor("FreezerGlow", Vector3.new((fx0 + fx1) / 2, FLOOR + 2.6, 17.9), c), rgb(200, 230, 255), 0.2, 4)
    local tubCols = { rgb(250, 190, 210), rgb(120, 70, 40), rgb(250, 240, 200), rgb(140, 220, 160), rgb(250, 150, 90) }
    for k = 0, 9 do
        local tx = fx0 + 0.6 + (k % 5) * 0.72
        local tz = fz0 + 0.55 + math.floor(k / 5) * 0.62
        part({ Name = "IceCreamTub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 0.55, 0.55),
            CFrame = CFrame.new(tx, FLOOR + 2.15, tz) * CFrame.Angles(0, 0, math.rad(90)),
            Color = rgb(250, 250, 246), Material = M.Plastic, CanCollide = false }, c)
        part({ Name = "TubLid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.58, 0.58),
            CFrame = CFrame.new(tx, FLOOR + 2.42, tz) * CFrame.Angles(0, 0, math.rad(90)),
            Color = tubCols[k % 5 + 1], Material = M.Plastic, CanCollide = false }, c)
    end
    sign("FreezerLabel", fx0 + 0.4, FLOOR + 0.6, fz0 - 0.03, fx1 - 0.4, FLOOR + 1.7, fz0, Enum.NormalId.Front,
        "ICE CREAM", rgb(236, 110, 150), rgb(255, 255, 255), c)
    -- the stash: a torn-open FROZEN PEAS box stuffed with cash
    local stash = Instance.new("Model")
    stash.Name = "SecretStash"
    stash.Parent = c
    local sx0, sx1, sz0, sz1 = 54.4, 55.8, 17.6, 18.5
    local peas = box("PeasBox", sx0, FLOOR + 1.9, sz0, sx1, FLOOR + 2.4, sz1, rgb(60, 150, 70), M.Cardboard, stash, nc())
    local pg = lit(surface(peas, Enum.NormalId.Top, 50, 1))
    text({ Text = "FROZEN PEAS", Size = UDim2.fromScale(0.9, 0.4), Position = UDim2.fromScale(0.05, 0.05), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = rgb(250, 250, 240) }, pg)
    for k = 0, 2 do
        local p0 = box("StashCash", sx0 + 0.15 + k * 0.4, FLOOR + 2.3, sz0 + 0.2, sx0 + 0.47 + k * 0.4, FLOOR + 2.62,
            sz1 - 0.2, BILL, M.Fabric, stash, nc({ CastShadow = false }))
        billFace(p0, Enum.NormalId.Top, "100")
    end
    -- (v3.3) stand 5.3 / 4.4 from the south register stand = 6.9 apart
    local fstand = Vector3.new(52.8, FLOOR + 3, 14.8)
    table.insert(loot, { kind = "SecretStash", cframe = CFrame.lookAt(fstand, Vector3.new(55.1, fstand.Y, 18)),
        visual = stash, hidden = true, pool = "floor", inVault = false })
end

-- 🏧 the ATM in the back-east corner, facing west. Jammed: twenties poke out of the slot.
function MartBuilder:_atm(f, loot)
    local a = Instance.new("Model")
    a.Name = "ATM"
    a.Parent = f
    local x0, x1, z0, z1 = 71.3, IX1, 16.3, SALES_Z1 - 0.05
    local GRAPHITE = rgb(46, 50, 58)
    local BRUSHED = rgb(172, 178, 188)
    local fx = x0 - 0.12
    box("AtmCabinet", x0, FLOOR, z0, x1, FLOOR + 5.5, z1, GRAPHITE, M.Metal, a)
    box("AtmPlinth", x0 - 0.05, FLOOR, z0 - 0.05, x1, FLOOR + 0.4, z1 + 0.02, rgb(26, 28, 32), M.Metal, a)
    box("AtmFascia", fx, FLOOR + 1.4, z0 + 0.1, x0, FLOOR + 5.3, z1 - 0.1, BRUSHED, M.Metal, a, { Reflectance = 0.12 })
    local hdr = box("AtmHeader", fx - 0.05, FLOOR + 5.5, z0, x1, FLOOR + 6.3, z1, rgb(18, 84, 186), M.Metal, a)
    local hg = surface(hdr, Enum.NormalId.Left, 40, 1)
    text({ Text = "ATM", Size = UDim2.fromScale(0.5, 0.8), Position = UDim2.fromScale(0.05, 0.1), TextScaled = true,
        FontFace = UITheme.F.display, TextColor3 = rgb(255, 255, 255) }, hg)
    text({ Text = "CASH 24/7", Size = UDim2.fromScale(0.4, 0.4), Position = UDim2.fromScale(0.56, 0.3), TextScaled = true,
        FontFace = UITheme.F.bold, TextColor3 = rgb(255, 214, 120) }, hg)
    local zc = (z0 + z1) / 2
    local scr = box("AtmScreen", fx - 0.02, FLOOR + 3.7, zc - 0.55, fx, FLOOR + 4.7, zc + 0.35, rgb(10, 20, 40), M.Glass, a, nc())
    local sg = surface(scr, Enum.NormalId.Left, 60, 0.8)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, sg)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(rgb(30, 110, 210), rgb(10, 40, 110))
    grad.Parent = bg
    text({ Text = "OUT OF ORDER?", Size = UDim2.fromScale(0.9, 0.26), Position = UDim2.fromScale(0.05, 0.14), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = rgb(255, 214, 120) }, sg)
    text({ Text = "PLEASE TAKE YOUR CASH", Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.56), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextColor3 = rgb(255, 255, 255) }, sg)
    point(scr, rgb(120, 170, 255), 0.3, 5, false)
    box("HoodTop", fx - 0.4, FLOOR + 4.7, zc - 0.62, fx, FLOOR + 4.78, zc + 0.42, GRAPHITE, M.Metal, a, nc())
    box("HoodSide", fx - 0.4, FLOOR + 3.7, zc - 0.62, fx, FLOOR + 4.78, zc - 0.56, GRAPHITE, M.Metal, a, nc())
    box("HoodSide", fx - 0.4, FLOOR + 3.7, zc + 0.36, fx, FLOOR + 4.78, zc + 0.42, GRAPHITE, M.Metal, a, nc())
    box("CardSlot", fx - 0.08, FLOOR + 3.9, zc + 0.5, fx, FLOOR + 4.1, zc + 0.75, rgb(20, 20, 24), M.Metal, a, nc())
    box("CardLed", fx - 0.09, FLOOR + 4.12, zc + 0.56, fx - 0.05, FLOOR + 4.16, zc + 0.69, rgb(80, 255, 120), M.Neon, a,
        nc({ CastShadow = false }))
    local pad = part({ Name = "Keypad", Size = Vector3.new(0.5, 0.08, 0.9),
        CFrame = CFrame.new(fx - 0.25, FLOOR + 3.3, zc - 0.1) * CFrame.Angles(0, 0, math.rad(12)),
        Color = GRAPHITE, Material = M.Metal, CanCollide = false }, a)
    local kg = lit(surface(pad, Enum.NormalId.Top, 80, 1))
    for r = 0, 3 do
        for col = 0, 3 do
            local key = frame({ Size = UDim2.fromScale(0.2, 0.2), Position = UDim2.fromScale(0.04 + r * 0.24, 0.04 + col * 0.24),
                BackgroundColor3 = (col == 3) and ({ rgb(220, 50, 50), rgb(240, 200, 40), rgb(60, 190, 90), rgb(200, 204, 210) })[r + 1]
                    or rgb(200, 204, 210) }, kg)
            UITheme.corner(key, 3)
        end
    end
    box("ReceiptSlot", fx - 0.06, FLOOR + 2.95, zc + 0.35, fx, FLOOR + 3.02, zc + 0.75, rgb(20, 20, 24), M.Metal, a, nc())
    box("CashSlot", fx - 0.08, FLOOR + 2.3, zc - 0.5, fx, FLOOR + 2.55, zc + 0.3, rgb(16, 16, 20), M.Metal, a, nc())
    local wad = Instance.new("Model")
    wad.Name = "ATMCash"
    wad.Parent = f
    for k = 0, 4 do
        local b = part({ Name = "Twenty", Size = Vector3.new(0.5, 0.03, 0.72),
            CFrame = CFrame.new(fx - 0.2, FLOOR + 2.36 + k * 0.035, zc - 0.1) * CFrame.Angles(0, math.rad(-8 + k * 4), math.rad(-6)),
            Color = BILL, Material = M.Fabric, CanCollide = false, CastShadow = false }, wad)
        if k == 4 then billFace(b, Enum.NormalId.Top, "20") end
    end
    local stand = Vector3.new(69.3, FLOOR + 3, zc)
    table.insert(loot, { kind = "ATMCash", cframe = CFrame.lookAt(stand, Vector3.new(x0, stand.Y, zc)),
        visual = wad, interact = "drill", pool = "floor", inVault = false })
end

function MartBuilder:_salesFloor(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "SalesFloor"
    s.Parent = f
    self:_island(s)
    self:_fridges(s)
    self:_checkout(s, refs, loot)
    self:_freezer(s, loot)
    self:_atm(s, loot)

    -- walls: warm light-grey lining above a teal wainscot + a yellow cap line
    local function lining(name, x0, z0, x1, z1)
        box(name, x0, FLOOR + 3, z0, x1, CEIL, z1, WALL_IN, M.Plaster, s, nc())
        box(name .. "Wainscot", x0, FLOOR, z0, x1, FLOOR + 3, z1, WAINSCOT, M.Plaster, s, nc())
    end
    lining("WallLiningW", IX0, IZ0, IX0 + 0.05, SALES_Z1)
    lining("WallLiningE", IX1 - 0.05, IZ0, IX1, SALES_Z1)
    lining("WallLiningBack", IX0, SALES_Z1 - 0.05, CURTAIN_X0, SALES_Z1)
    lining("WallLiningBack", CURTAIN_X1, SALES_Z1 - 0.05, IX1, SALES_Z1)
    box("WainscotCap", IX0, FLOOR + 3, SALES_Z1 - 0.12, CURTAIN_X0, FLOOR + 3.15, SALES_Z1, SUNNY, M.Plaster, s, nc())
    box("WainscotCap", CURTAIN_X1, FLOOR + 3, SALES_Z1 - 0.12, IX1, FLOOR + 3.15, SALES_Z1, SUNNY, M.Plaster, s, nc())
    box("CoveBase", IX0, FLOOR, SALES_Z1 - 0.14, CURTAIN_X0, FLOOR + 0.4, SALES_Z1 - 0.05, rgb(26, 26, 30), M.Rubber, s, nc())
    box("CoveBase", CURTAIN_X1, FLOOR, SALES_Z1 - 0.14, IX1, FLOOR + 0.4, SALES_Z1 - 0.05, rgb(26, 26, 30), M.Rubber, s, nc())
    -- front wall inner face above the windows
    box("FrontLining", IX0, WIN_TOP + 0.5, IZ0, IX1, CEIL, IZ0 + 0.05, WALL_IN, M.Plaster, s, nc())

    -- the BIG BOX: a stack of soda cases you can hide inside (HideSpot)
    local bx0, bx1, bz0, bz1 = 57, 59.6, 16.5, SALES_Z1 - 0.05
    local bigBox = box("BigBox", bx0, FLOOR, bz0, bx1, FLOOR + 4.2, bz1, rgb(186, 146, 96), M.Cardboard, s)
    local bg = lit(surface(bigBox, Enum.NormalId.Front, 30, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(186, 146, 96) }, bg)
    frame({ Size = UDim2.fromScale(1, 0.02), Position = UDim2.fromScale(0, 0.49), BackgroundColor3 = rgb(140, 104, 64) }, bg)
    text({ Text = "SUNNY SODA", Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.12),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = TEAL_DK }, bg)
    text({ Text = "24 PACK", Size = UDim2.fromScale(0.8, 0.18), Position = UDim2.fromScale(0.1, 0.62),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextColor3 = INK }, bg)
    box("BigBoxFlap", bx0, FLOOR + 4.2, bz0, bx1, FLOOR + 4.3, bz0 + 0.8, rgb(170, 132, 86), M.Cardboard, s, nc())
    tag(bigBox, "HideSpot", { Label = "Big box" })
    table.insert(refs.hideSpots, bigBox)

    -- a flat brand board between the big box and the curtain (a shelf here
    -- made the aisle behind the island only 5 deep)
    local bb = box("BrandBoard", 60.2, FLOOR + 4.6, SALES_Z1 - 0.08, 63.2, FLOOR + 8.6, SALES_Z1, TEAL, M.Plaster, s, nc())
    local bbg = lit(surface(bb, Enum.NormalId.Front, 30, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEAL }, bbg)
    local bsun = frame({ Size = UDim2.fromScale(0.42, 0.32), Position = UDim2.fromScale(0.29, 0.1), BackgroundColor3 = SUNNY }, bbg)
    UITheme.corner(bsun, 999)
    text({ Text = "SUNNY'S", Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.48), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = rgb(250, 246, 236) }, bbg)
    text({ Text = "SINCE 1987", Size = UDim2.fromScale(0.7, 0.12), Position = UDim2.fromScale(0.15, 0.74), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextColor3 = SUNNY }, bbg)

    -- promo posters on the back wall + the EMPLOYEES ONLY plate over the curtain
    poster("PromoPoster", 52, FLOOR + 6.2, SALES_Z1 - 0.06, 56, FLOOR + 9.6, SALES_Z1, Enum.NormalId.Front,
        "HOT DOGS", "$1.99", SUNNY_DK, rgb(150, 50, 30), s)
    poster("PromoPoster", 71.4, FLOOR + 7.2, SALES_Z1 - 0.06, 72.9, FLOOR + 9.4, SALES_Z1, Enum.NormalId.Front,
        "SLUSH!", nil, TEAL, TEAL_DK, s)

    -- ceiling: two rows of troffers. KEY lights (shadows) mid-floor, dim fills
    -- front + back — pools of light with softer dark between (guard cones read)
    for _, tx in ipairs({ 57.5, 67 }) do
        tubeLight(s, tx, 4.6, false, 0.22, 10, 4)                -- front fills (the windows glow warm from outside too)
        tubeLight(s, tx, 10.5, false, 0.5, 13, 4, true)         -- keys
        tubeLight(s, tx, 16.2, false, 0.15, 9, 4)               -- back fills
    end

    -- floor: a teal band in front of the fridges + a door-to-curtain tile runner (it guides you back)
    box("FridgeBand", FRIDGE_X0 - 1.6, FLOOR, FRIDGE_Z0, FRIDGE_X0, FLOOR + 0.02, FRIDGE_Z1, rgb(18, 104, 106), M.CeramicTiles, s, nc())
    box("Runner", 65.6, FLOOR, IZ0 + 2.6, 68.4, FLOOR + 0.02, SALES_Z1 - 0.3, rgb(118, 116, 112), M.CeramicTiles, s,
        nc({ CastShadow = false }))

    table.insert(refs.shadowZones, shadowZone("ShadowFreezerCorner", IX0, 14.6, 56.6, SALES_Z1, s))
    table.insert(refs.shadowZones, shadowZone("ShadowBigBox", 56.6, 15.8, 60, SALES_Z1, s))
    return bigBox
end

-- ──────────────────────────────────────────────
-- 📦 STOCK ROOM (the breaker = goal ①) + the loading door
-- ──────────────────────────────────────────────
function MartBuilder:_stockRoom(f, refs, loot)
    local s = Instance.new("Folder")
    s.Name = "StockRoom"
    s.Parent = f
    -- x 60.5..73, z 20..32.5 (12.5 × 12.5). The CORRIDOR z 21..28 stays empty:
    -- curtain → office door (west) and → loading door (east).
    -- E prompts: breaker (66.5, 32.3) · lotto (71.55, 28.2) · deposit (61.95, 23.4)
    --   breaker↔lotto 6.5 · breaker↔deposit 9.8 · lotto↔deposit 10.6
    -- H: closet (61.5, 31.5) is 5.0 from the breaker, 8.1 from the deposit.

    -- strip curtain: you walk through it, the guard can't see through it
    local n = 11
    local sw = (CURTAIN_X1 - CURTAIN_X0) / n
    for k = 0, n - 1 do
        local x = CURTAIN_X0 + (k + 0.5) * sw
        box("CurtainStrip", x - sw / 2 + 0.03, FLOOR + 0.2, SALES_Z1 + 0.45, x + sw / 2 - 0.03, DOOR_H, SALES_Z1 + 0.55,
            rgb(200, 222, 230), M.Glass, s, nc({ Transparency = 0.45, CastShadow = false }))
    end
    box("CurtainRail", CURTAIN_X0, DOOR_H - 0.2, SALES_Z1 + 0.35, CURTAIN_X1, DOOR_H, SALES_Z1 + 0.65, STEEL_LT, M.Metal, s, nc())
    for _, x in ipairs({ CURTAIN_X0, CURTAIN_X1 - 0.2 }) do
        box("DoorCasing", x, FLOOR, SALES_Z1 - 0.06, x + 0.2, DOOR_H, BACK_Z0 + 0.06, STEEL_LT, M.Metal, s, nc())
    end
    local cmid = (CURTAIN_X0 + CURTAIN_X1) / 2
    sign("EmployeesOnly", cmid - 2, DOOR_H + 0.5, SALES_Z1 - 0.1, cmid + 2, DOOR_H + 1.6, SALES_Z1, Enum.NormalId.Front,
        "EMPLOYEES ONLY", rgb(196, 44, 56), rgb(255, 255, 255), s, UITheme.F.bold)

    -- painted cinder-block walls + a yellow bump stripe
    box("BlockWall", STOCK_X0, FLOOR, IZ1 - 0.08, IX1, CEIL, IZ1, BLOCK, M.Brick, s, nc())
    box("BlockWall", STOCK_X0, FLOOR, BACK_Z0, CURTAIN_X0, CEIL, BACK_Z0 + 0.06, BLOCK, M.Brick, s, nc())
    box("BlockWall", CURTAIN_X1, FLOOR, BACK_Z0, IX1, CEIL, BACK_Z0 + 0.06, BLOCK, M.Brick, s, nc())
    box("BlockWall", CURTAIN_X0, DOOR_H, BACK_Z0, CURTAIN_X1, CEIL, BACK_Z0 + 0.06, BLOCK, M.Brick, s, nc())
    box("BlockWall", STOCK_X0, FLOOR, BACK_Z0, STOCK_X0 + 0.06, CEIL, OFFICE_DOOR_Z0, BLOCK, M.Brick, s, nc())
    box("BlockWall", STOCK_X0, FLOOR, OFFICE_DOOR_Z1, STOCK_X0 + 0.06, CEIL, IZ1, BLOCK, M.Brick, s, nc())
    box("BlockWall", STOCK_X0, DOOR_H, OFFICE_DOOR_Z0, STOCK_X0 + 0.06, CEIL, OFFICE_DOOR_Z1, BLOCK, M.Brick, s, nc())
    box("BlockLining", IX1 - 0.06, FLOOR, BACK_Z0, IX1, CEIL, LOAD_Z0, BLOCK, M.Brick, s, nc())
    box("BlockLining", IX1 - 0.06, FLOOR, LOAD_Z1, IX1, CEIL, IZ1, BLOCK, M.Brick, s, nc())
    box("BlockLining", IX1 - 0.06, DOOR_H, LOAD_Z0, IX1, CEIL, LOAD_Z1, BLOCK, M.Brick, s, nc())
    box("BumpStripe", STOCK_X0, FLOOR + 0.9, IZ1 - 0.12, IX1, FLOOR + 1.4, IZ1 - 0.08, SAFETY, M.Plaster, s, nc())
    -- the corridor lines (door → door), painted on the concrete
    box("FloorLine", STOCK_X0 + 0.4, FLOOR, 21, IX1 - 0.4, FLOOR + 0.02, 21.25, SAFETY, M.Plaster, s, nc())
    box("FloorLine", STOCK_X0 + 0.4, FLOOR, 28.2, IX1 - 0.4, FLOOR + 0.02, 28.45, SAFETY, M.Plaster, s, nc())

    -- ① THE BREAKER: centred on the back wall, straight ahead through the
    -- curtain, under its own caged work lamp, a yellow "stand here" box on the floor
    local bx0, bx1 = 65.7, 67.3
    local bzf = IZ1 - 0.45                          -- front face (faces north)
    local breaker = box("BreakerPanel", bx0, FLOOR + 2.8, bzf, bx1, FLOOR + 6.2, IZ1 - 0.08, rgb(96, 102, 110), M.Metal, s)
    local bg = lit(surface(breaker, Enum.NormalId.Front, 50, 1))
    text({ Text = "SECURITY", Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.04),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 204, 21) }, bg)
    text({ Text = "CAMERA · ALARM", Size = UDim2.new(1, 0, 0.1, 0), Position = UDim2.fromScale(0, 0.21),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.bold,
        TextColor3 = rgb(30, 32, 38) }, bg)
    for r = 0, 2 do
        for col = 0, 3 do
            frame({ Size = UDim2.fromScale(0.14, 0.12), Position = UDim2.fromScale(0.12 + col * 0.2, 0.4 + r * 0.18),
                BackgroundColor3 = rgb(40, 42, 48) }, bg)
        end
    end
    for k, col in ipairs({ rgb(80, 255, 120), rgb(255, 180, 40) }) do
        local lx = bx0 + 0.5 + (k - 1) * 0.6
        box("BreakerLed", lx - 0.07, FLOOR + 5.8, bzf - 0.07, lx + 0.07, FLOOR + 5.94, bzf, col, M.Neon, s, nc())
    end
    box("Conduit", 66.4, FLOOR + 7.5, IZ1 - 0.3, 66.6, CEIL, IZ1 - 0.08, STEEL_LT, M.Metal, s, nc())
    sign("BreakerSign", bx0 - 0.2, FLOOR + 6.6, IZ1 - 0.14, bx1 + 0.2, FLOOR + 7.5, IZ1 - 0.08, Enum.NormalId.Front,
        "HIGH VOLTAGE", SUNNY, INK, s)
    for _, e in ipairs({ { 65.4, 29.4, 67.6, 29.6 }, { 65.4, 29.4, 65.6, 30.5 }, { 67.4, 29.4, 67.6, 30.5 } }) do
        box("StandHereLine", e[1], FLOOR, e[2], e[3], FLOOR + 0.02, e[4], SAFETY, M.Plaster, s, nc())
    end
    bar("LampCord", Vector3.new(66.5, CEIL, 29.8), Vector3.new(66.5, CEIL - 2.8, 29.8), 0.06, STEEL_DK, M.Rubber, s, nc())
    local cage = box("CageLamp", 66.1, CEIL - 3.4, 29.4, 66.9, CEIL - 2.8, 30.2, STEEL_DK, M.Metal, s, nc())
    box("CageLampBulb", 66.25, CEIL - 3.55, 29.55, 66.75, CEIL - 3.4, 30.05, WARM, M.Neon, s, nc({ CastShadow = false }))
    point(cage, rgb(255, 204, 150), 0.55, 13, true)

    -- racking either side of the breaker (cover), stocked
    local rz0 = IZ1 - 1.9
    local function rack(x0, x1, seed)
        for _, y in ipairs({ FLOOR + 0.3, FLOOR + 2.8, FLOOR + 5.3 }) do
            box("RackShelf", x0, y, rz0, x1, y + 0.15, IZ1 - 0.08, rgb(56, 88, 156), M.Metal, s)
        end
        for _, px in ipairs({ x0 + 0.05, x1 - 0.05 }) do
            box("RackPost", px - 0.08, FLOOR, rz0, px + 0.08, FLOOR + 7.4, rz0 + 0.15, rgb(230, 120, 40), M.Metal, s, nc())
        end
        local k = 0
        local bxa = x0 + 0.2
        while bxa + 1.05 < x1 - 0.1 do
            local y = (k % 2 == 0) and FLOOR + 0.45 or FLOOR + 2.95
            box("StockBox", bxa, y, rz0 + 0.2, bxa + 1.05, y + 1.3 + ((k + seed) % 3) * 0.3, IZ1 - 0.15,
                rgb(176 + ((k + seed) % 3) * 8, 140 + (k % 2) * 10, 96), M.Cardboard, s)
            k = k + 1
            bxa = bxa + 1.2
        end
    end
    rack(62.7, 65.2, 0)
    rack(67.8, 72.9, 1)

    -- the lotto carton on the east rack's top shelf (Lottery)
    local lot = Instance.new("Model")
    lot.Name = "LottoCarton"
    lot.Parent = s
    local lx0, lx1, lz0, lz1 = 70.6, 72.5, rz0 + 0.2, IZ1 - 0.15
    local ly0, ly1 = FLOOR + 5.45, FLOOR + 6.3
    box("CartonBase", lx0, ly0, lz0, lx1, ly0 + 0.08, lz1, rgb(196, 160, 110), M.Cardboard, lot, nc())
    local front = box("CartonFront", lx0, ly0, lz0, lx1, ly1, lz0 + 0.06, SUNNY, M.Cardboard, lot, nc())
    lit(printOn(front, Enum.NormalId.Front, "SUNSHINE LOTTO", rgb(160, 30, 80), UITheme.F.display, 40, 1).Parent)
    box("CartonBack", lx0, ly0, lz1 - 0.06, lx1, ly1, lz1, SUNNY, M.Cardboard, lot, nc())
    box("CartonSide", lx0, ly0, lz0, lx0 + 0.06, ly1, lz1, SUNNY, M.Cardboard, lot, nc())
    box("CartonSide", lx1 - 0.06, ly0, lz0, lx1, ly1, lz1, SUNNY, M.Cardboard, lot, nc())
    local packCols = { rgb(230, 57, 70), rgb(33, 158, 188), rgb(106, 176, 76), rgb(155, 93, 229), rgb(251, 133, 0) }
    for k = 0, 9 do
        local px = lx0 + 0.16 + (k % 5) * 0.34
        local pz = lz0 + 0.3 + math.floor(k / 5) * 0.6
        box("TicketPack", px - 0.14, ly0 + 0.08, pz - 0.24, px + 0.14, ly1 + 0.08, pz + 0.24, packCols[k % 5 + 1],
            M.Cardboard, lot, nc({ CastShadow = false }))
    end
    local lmx = (lx0 + lx1) / 2
    local ls = Vector3.new(lmx, FLOOR + 3, rz0 - 2.4)
    table.insert(loot, { kind = "Lottery", cframe = CFrame.lookAt(ls, Vector3.new(lmx, ls.Y, IZ1)), visual = lot,
        pool = "stockroom", inVault = false })

    -- a steel workbench on the north wall, west of the curtain: tonight's
    -- NIGHT DEPOSIT bag + the spare till tray, waiting for the bank run
    local wx0, wx1, wz0, wz1 = STOCK_X0 + 0.2, CURTAIN_X0 - 0.3, BACK_Z0 + 0.06, BACK_Z0 + 1.5
    local ty = FLOOR + 3
    box("BenchTop", wx0, ty - 0.15, wz0, wx1, ty, wz1, STEEL_LT, M.DiamondPlate, s)
    for _, lx in ipairs({ wx0 + 0.1, wx1 - 0.2 }) do
        box("BenchLeg", lx, FLOOR, wz1 - 0.2, lx + 0.1, ty - 0.15, wz1 - 0.1, STEEL, M.Metal, s, nc())
    end
    box("BenchShelf", wx0, FLOOR + 0.6, wz0, wx1, FLOOR + 0.7, wz1, STEEL, M.Metal, s, nc())
    local bag = Instance.new("Model")
    bag.Name = "NightDeposit"
    bag.Parent = s
    local bz = wz0 + 0.2
    box("DepositBag", wx0 + 0.2, ty, bz, wx0 + 1.4, ty + 0.5, bz + 1.0, rgb(60, 72, 96), M.Fabric, bag, nc())
    part({ Name = "BagPuff", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 0.35, 0.9),
        Position = Vector3.new(wx0 + 0.8, ty + 0.5, bz + 0.5), Color = rgb(60, 72, 96), Material = M.Fabric, CanCollide = false }, bag)
    box("BagZip", wx0 + 0.25, ty + 0.62, bz + 0.45, wx0 + 1.35, ty + 0.66, bz + 0.55, rgb(220, 190, 60), M.Metal, bag, nc())
    local lab = box("BagLabel", wx0 + 0.3, ty + 0.1, bz + 1.0, wx0 + 1.3, ty + 0.4, bz + 1.03, PAPER, M.Fabric, bag, nc())
    lit(printOn(lab, Enum.NormalId.Back, "NIGHT DEPOSIT", rgb(30, 40, 80), UITheme.F.bold, 60, 1).Parent)
    tillDrawer(bag, wx0 + 1.5, ty, bz, wx0 + 2.3, bz + 1.0)
    local dmx = (wx0 + wx1) / 2
    local ds = Vector3.new(dmx, FLOOR + 3, 23.4)
    table.insert(loot, { kind = "Register", cframe = CFrame.lookAt(ds, Vector3.new(dmx, ds.Y, BACK_Z0)), visual = bag,
        interact = "stuff", pool = "stockroom", inVault = false })

    -- tall steel broom closet in the dark south-west corner (HideSpot)
    local closet = box("BroomCloset", STOCK_X0 + 0.1, FLOOR, IZ1 - 1.85, STOCK_X0 + 2, FLOOR + 7.4, IZ1 - 0.08,
        rgb(110, 138, 156), M.Metal, s)
    local cg = lit(surface(closet, Enum.NormalId.Front, 30, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(110, 138, 156) }, cg)
    frame({ Size = UDim2.fromScale(0.02, 0.96), Position = UDim2.fromScale(0.49, 0.02), BackgroundColor3 = rgb(60, 80, 96) }, cg)
    for k = 0, 1 do
        frame({ Size = UDim2.fromScale(0.06, 0.12), Position = UDim2.fromScale(0.4 + k * 0.14, 0.45), BackgroundColor3 = STEEL_LT }, cg)
        for v = 0, 3 do
            frame({ Size = UDim2.fromScale(0.3, 0.012), Position = UDim2.fromScale(0.08 + k * 0.5, 0.06 + v * 0.03),
                BackgroundColor3 = rgb(60, 80, 96) }, cg)
        end
    end
    tag(closet, "HideSpot", { Label = "Closet" })
    table.insert(refs.hideSpots, closet)

    -- a neat stack of soda cases in the north-east corner, clear of the loading door
    box("SodaCases", 71.3, FLOOR, 28.6, 72.9, FLOOR + 2.6, 30.4, rgb(40, 110, 200), M.Cardboard, s)
    box("SodaCases", 71.4, FLOOR + 2.6, 28.8, 72.8, FLOOR + 3.8, 30.2, rgb(206, 48, 52), M.Cardboard, s)

    -- lights: the breaker's cage lamp is the key; two dim tubes over the corridor
    tubeLight(s, 63.2, 24.5, true, 0.18, 9, 3.6, false, rgb(255, 220, 180))
    tubeLight(s, 69.6, 24.5, true, 0.18, 9, 3.6, false, rgb(255, 220, 180))
    table.insert(refs.shadowZones, shadowZone("ShadowStockCorner", STOCK_X0, 28.5, 64.6, IZ1, s))

    -- ── the loading door: a steel roll-up shutter, rolled up, onto the yard ──
    local x = X1
    local STEELC = rgb(70, 74, 82)
    box("BackDoorFrameN", x, 0, LOAD_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, LOAD_Z0, STEELC, M.Metal, s)
    box("BackDoorFrameS", x, 0, LOAD_Z1, x + 0.25, DOOR_H + 0.3, LOAD_Z1 + 0.3, STEELC, M.Metal, s)
    box("BackDoorFrameTop", x, DOOR_H, LOAD_Z0 - 0.3, x + 0.25, DOOR_H + 0.3, LOAD_Z1 + 0.3, STEELC, M.Metal, s)
    box("ShutterHood", x + 0.25, DOOR_H + 0.3, LOAD_Z0 - 0.2, x + 1.05, DOOR_H + 1.1, LOAD_Z1 + 0.2,
        rgb(96, 100, 110), M.Metal, s, nc())
    box("ShutterSlats", x + 0.25, DOOR_H - 0.25, LOAD_Z0 + 0.05, x + 0.4, DOOR_H + 0.3, LOAD_Z1 - 0.05,
        rgb(150, 156, 166), M.DiamondPlate, s, nc())
    for _, gz in ipairs({ LOAD_Z0, LOAD_Z1 - 0.15 }) do
        box("ShutterGuide", x + 0.25, FLOOR, gz, x + 0.4, DOOR_H, gz + 0.15, STEEL, M.Metal, s, nc())
    end
    box("BackDoorStep", x, 0, LOAD_Z0, x + 2, FLOOR, LOAD_Z1, rgb(150, 146, 140), M.Concrete, s)
    sign("BackDoorPlate", x + 0.25, DOOR_H + 1.3, LOAD_Z0 + 1.8, x + 0.35, DOOR_H + 2.4, LOAD_Z1 - 1.8, Enum.NormalId.Right,
        "DELIVERIES", rgb(26, 26, 30), SUNNY, s, UITheme.F.bold)
    local mid = (LOAD_Z0 + LOAD_Z1) / 2
    local lamp = box("AlleyLamp", x + 0.25, DOOR_H + 2.6, mid - 0.5, x + 0.9, DOOR_H + 3.0, mid + 0.5, STEEL_DK, M.Metal, s, nc())
    box("AlleyLampLens", x + 0.3, DOOR_H + 2.5, mid - 0.4, x + 0.85, DOOR_H + 2.6, mid + 0.4, rgb(255, 214, 150), M.Neon, s, nc())
    spot(lamp, Enum.NormalId.Bottom, rgb(255, 200, 140), 1.1, 16, 100, true)

    return breaker
end

-- ──────────────────────────────────────────────
-- 🗄 OFFICE: the safe (goal ②), the Golden Ticket, desk, CCTV, roof ladder
-- ──────────────────────────────────────────────
function MartBuilder:_office(f, refs, loot)
    local o = Instance.new("Folder")
    o.Name = "Office"
    o.Parent = f
    -- x 49..59.5, z 20..32.5. North: ticket (west) + desk (east). West wall:
    -- the roof ladder. South: the safe. E prompts: ticket stand (51.4, 22.1) ·
    -- drill point (55, 28.0) 6.6 away · SafeCash stands (53.8 / 56.2, 27.7),
    -- ticket↔nearest 6.1. V (hatch, 49.7, 26.6) ≥ 4.2 from all of them.

    -- walls: warm grey above a dark-teal wainscot + chair rail (same family as the shop)
    local OFFICE_WAIN = rgb(30, 86, 90)
    local RAIL = rgb(206, 200, 188)
    local function wall(x0, z0, x1, z1)
        box("Wainscot", x0, FLOOR, z0, x1, FLOOR + 3.4, z1, OFFICE_WAIN, M.Plaster, o, nc())
        box("WallLining", x0, FLOOR + 3.6, z0, x1, CEIL, z1, WALL_IN, M.Plaster, o, nc())
    end
    wall(BIX0, BACK_Z0, OFFICE_X1, BACK_Z0 + 0.06)                 -- north
    wall(BIX0, IZ1 - 0.06, OFFICE_X1, IZ1)                          -- south
    wall(BIX0, BACK_Z0, BIX0 + 0.06, IZ1)                           -- west
    local ex = OFFICE_X1 - 0.06
    wall(ex, BACK_Z0, OFFICE_X1, OFFICE_DOOR_Z0)                    -- east (door gap)
    wall(ex, OFFICE_DOOR_Z1, OFFICE_X1, IZ1)
    box("WallLining", ex, DOOR_H, OFFICE_DOOR_Z0, OFFICE_X1, CEIL, OFFICE_DOOR_Z1, WALL_IN, M.Plaster, o, nc())
    for _, r in ipairs({
        { BIX0, BACK_Z0 + 0.06, OFFICE_X1, BACK_Z0 + 0.16 }, { BIX0, IZ1 - 0.16, OFFICE_X1, IZ1 - 0.06 },
        { BIX0 + 0.06, BACK_Z0, BIX0 + 0.16, IZ1 },
    }) do
        box("ChairRail", r[1], FLOOR + 3.4, r[2], r[3], FLOOR + 3.6, r[4], RAIL, M.Wood, o, nc())
    end
    for _, zz in ipairs({ { OFFICE_DOOR_Z0, OFFICE_DOOR_Z0 + 0.25 }, { OFFICE_DOOR_Z1 - 0.25, OFFICE_DOOR_Z1 } }) do
        box("DoorCasing", ex - 0.08, FLOOR, zz[1], OFFICE_X1, DOOR_H, zz[2], RAIL, M.Wood, o, nc())
    end
    box("DoorCasing", ex - 0.08, DOOR_H, OFFICE_DOOR_Z0, OFFICE_X1, DOOR_H + 0.25, OFFICE_DOOR_Z1, RAIL, M.Wood, o, nc())
    sign("OfficeSign", 60.56, DOOR_H + 0.4, 24.5, 60.62, DOOR_H + 1.3, 27.5, Enum.NormalId.Right,
        "OFFICE", TEAL, rgb(250, 246, 236), o)

    -- desk along the north wall, east end
    local dx0, dx1, dz0, dz1 = 54.8, 59.2, BACK_Z0 + 0.06, BACK_Z0 + 2.2
    local topY = FLOOR + 2.9
    box("DeskTop", dx0, topY - 0.25, dz0, dx1, topY, dz1, WALNUT, M.Wood, o)
    box("DeskSide", dx0, FLOOR, dz0, dx0 + 0.2, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskSide", dx1 - 0.2, FLOOR, dz0, dx1, topY - 0.25, dz1, WALNUT, M.Wood, o)
    box("DeskBack", dx0, FLOOR + 0.8, dz0, dx1, topY - 0.25, dz0 + 0.2, WALNUT, M.Wood, o)
    -- desk lamp = the office's key light
    local lx, lz = dx0 + 0.4, dz0 + 1.5
    box("LampBase", lx - 0.25, topY, lz - 0.25, lx + 0.25, topY + 0.1, lz + 0.25, STEEL_DK, M.Metal, o, nc())
    bar("LampArm", Vector3.new(lx, topY + 0.1, lz), Vector3.new(lx + 0.4, topY + 1.3, lz + 0.2), 0.07, STEEL_DK, M.Metal, o, nc())
    local shade_ = box("LampShade", lx + 0.1, topY + 1.1, lz - 0.1, lx + 0.8, topY + 1.45, lz + 0.5, TEAL, M.Metal, o, nc())
    spot(shade_, Enum.NormalId.Bottom, rgb(255, 204, 150), 0.5, 11, 90, true)
    box("Papers", 57.4, topY, dz0 + 0.6, 58.4, topY + 0.1, dz0 + 1.4, PAPER, M.Fabric, o, nc())
    part({ Name = "Mug", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 0.35, 0.35),
        CFrame = CFrame.new(58.6, topY + 0.23, dz0 + 1.7) * CFrame.Angles(0, 0, math.rad(90)),
        Color = SUNNY, Material = M.Plastic, CanCollide = false }, o)

    -- CCTV monitor over the desk (faces south into the office)
    local mon = box("CctvMonitor", 55.4, FLOOR + 5.2, BACK_Z0 + 0.06, 58.4, FLOOR + 7.4, BACK_Z0 + 0.3, rgb(20, 20, 24), M.Metal, o)
    local mg = surface(mon, Enum.NormalId.Back, 50, 0.9)
    for k, label in ipairs({ "CAM 1 · REGISTER", "NO SIGNAL" }) do
        local cell = frame({ Size = UDim2.fromScale(0.47, 0.9), Position = UDim2.fromScale(0.02 + (k - 1) * 0.49, 0.05),
            BackgroundColor3 = rgb(18, 34, 40) }, mg)
        text({ Text = label, Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.05),
            TextScaled = true, FontFace = UITheme.F.mono, TextColor3 = rgb(140, 220, 200) }, cell)
    end
    point(lightAnchor("MonitorGlow", Vector3.new(56.9, FLOOR + 5.5, BACK_Z0 + 1.2), o), rgb(150, 200, 255), 0.25, 6)

    -- calendar + sticky note on the west wall, south of the ladder
    local cal = box("Calendar", BIX0 + 0.06, 5.5, 28.6, BIX0 + 0.14, 7.6, 30.2, PAPER, M.Fabric, o, nc())
    local calg = lit(surface(cal, Enum.NormalId.Right, 40, 1))
    frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER }, calg)
    frame({ Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = TEAL }, calg)
    text({ Text = "SEPT", Size = UDim2.fromScale(0.9, 0.25), Position = UDim2.fromScale(0.05, 0.03),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(255, 255, 255) }, calg)
    local note = box("StickyNote", BIX0 + 0.06, 6.2, 30.5, BIX0 + 0.11, 7.1, 31.4, rgb(255, 236, 120), M.Fabric, o, nc())
    lit(printOn(note, Enum.NormalId.Right, "SAFE CODE?\nNICE TRY", rgb(60, 50, 30), UITheme.F.bold, 80, 1).Parent)

    -- the roof ladder on the west wall (inside end of the roof "vent")
    local lz0, lz1 = 25.5, 27.7
    for _, rz in ipairs({ lz0, lz1 }) do
        box("LadderRail", BIX0 + 0.06, FLOOR, rz - 0.1, BIX0 + 0.6, CEIL, rz + 0.1, STEEL_LT, M.Metal, o, nc())
    end
    for y = FLOOR + 1, CEIL - 1, 1.2 do
        box("LadderRung", BIX0 + 0.35, y, lz0, BIX0 + 0.5, y + 0.12, lz1, STEEL_LT, M.Metal, o, nc())
    end
    box("CeilingHatch", BIX0 + 0.2, CEIL - 0.12, lz0 - 0.3, BIX0 + 3, CEIL, lz1 + 0.3, STEEL, M.Metal, o, nc())
    local inside = facingPart("SM_RoofHatchInside", Vector3.new(BIX0 + 0.7, FLOOR + 3, (lz0 + lz1) / 2),
        Vector3.new(2, 5, 0.15), Vector3.new(1, 0, 0), rgb(250, 204, 21), M.Metal, o,
        { Transparency = 0.2, CanCollide = false })
    local ig = lit(surface(inside, Enum.NormalId.Front, 40, 1))
    text({ Text = "UP TO ROOF", Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.05),
        TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true, FontFace = UITheme.F.display,
        TextColor3 = rgb(30, 30, 30) }, ig)

    -- a rug down the middle
    box("Rug", 51.6, FLOOR, 23.2, 57.8, FLOOR + 0.04, 27.2, rgb(40, 96, 100), M.Fabric, o, nc({ CastShadow = false }))
    box("RugBorder", 51.9, FLOOR + 0.04, 23.5, 57.5, FLOOR + 0.05, 26.9, rgb(214, 180, 96), M.Fabric, o,
        nc({ CastShadow = false, Transparency = 0.55 }))

    -- a filing cabinet on the east wall, south of the door
    local cab = box("FilingCabinet", OFFICE_X1 - 1.4, FLOOR, 30.2, OFFICE_X1 - 0.06, FLOOR + 4.6, 32.3, rgb(96, 104, 98), M.Metal, o)
    local cgui = lit(surface(cab, Enum.NormalId.Left, 30, 1))
    for d = 0, 3 do
        local drw = frame({ Size = UDim2.fromScale(0.9, 0.22), Position = UDim2.fromScale(0.05, 0.03 + d * 0.245),
            BackgroundColor3 = rgb(110, 118, 112) }, cgui)
        frame({ Size = UDim2.fromScale(0.3, 0.08), Position = UDim2.fromScale(0.35, 0.3), BackgroundColor3 = STEEL_LT }, drw)
    end

    -- ceiling: two dim warm panels (the desk lamp + picture light are the bright spots)
    for _, lzc in ipairs({ { 23.2, 0.2 }, { 28.8, 0.16 } }) do
        tubeLight(o, 54.3, lzc[1], true, lzc[2], 11, 3.2, false, WARM)
    end
    table.insert(refs.shadowZones, shadowZone("ShadowOfficeCorner", BIX0, 28.6, 52.3, IZ1, o))
    prop("furniture", "trashcan", Vector3.new(dx0 - 0.8, FLOOR, dz0 + 0.8), Vector3.new(0, 0, 1), o,
        { main = { rgb(60, 64, 70), M.Metal } }, { collide = false })

    -- ── the floor safe (against the south wall, door facing north) ──
    local sx0, sx1 = SAFE_X - SAFE_HW, SAFE_X + SAFE_HW
    local fz0, fz1 = SAFE_Z0, SAFE_Z0 + 0.4
    local oy0, oy1 = SAFE_Y - 1.1, SAFE_Y + 1.1
    local ox0, ox1 = SAFE_X - 1.1, SAFE_X + 1.1
    local topS = SAFE_TOP
    local SAFE_COL = rgb(52, 70, 64)
    local body = Instance.new("Model")
    body.Name = "Safe"
    body.Parent = o
    box("SafeBack", sx0, FLOOR, SAFE_Z1 - 0.4, sx1, topS, SAFE_Z1, SAFE_COL, M.Metal, body)
    box("SafeSide", sx0, FLOOR, fz1, sx0 + 0.4, topS, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeSide", sx1 - 0.4, FLOOR, fz1, sx1, topS, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeTop", sx0, topS - 0.4, fz0, sx1, topS, SAFE_Z1, SAFE_COL, M.Metal, body)
    box("SafeFloor", sx0 + 0.4, FLOOR, fz1, sx1 - 0.4, FLOOR + 0.4, SAFE_Z1 - 0.4, SAFE_COL, M.Metal, body)
    box("SafeFront", sx0, FLOOR, fz0, ox0, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox1, FLOOR, fz0, sx1, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox0, oy1, fz0, ox1, topS - 0.4, fz1, SAFE_COL, M.Metal, body)
    box("SafeFront", ox0, FLOOR, fz0, ox1, oy0, fz1, SAFE_COL, M.Metal, body)
    box("SafeLining", sx0 + 0.4, FLOOR + 0.4, SAFE_Z1 - 0.5, sx1 - 0.4, topS - 0.4, SAFE_Z1 - 0.4, rgb(120, 20, 36), M.Fabric, body)
    box("SafeShelf", sx0 + 0.4, SAFE_Y - 0.1, fz1, sx1 - 0.4, SAFE_Y, SAFE_Z1 - 0.5, STEEL_LT, M.Metal, body)
    box("SafePinstripe", sx0 - 0.02, topS - 0.9, fz0 - 0.02, sx1 + 0.02, topS - 0.78, SAFE_Z1, rgb(220, 190, 110), M.Metal, body, nc())
    local plate = box("SafeNameplate", SAFE_X - 1, topS - 0.7, fz0 - 0.04, SAFE_X + 1, topS - 0.45, fz0, rgb(220, 190, 110), M.Metal, body, nc())
    lit(printOn(plate, Enum.NormalId.Front, "SUNNY'S", rgb(60, 36, 14), UITheme.F.display, 60, 1).Parent)
    -- a little spot on the safe so it's the thing you see from the door
    local sl = box("SafeSpot", SAFE_X - 0.4, CEIL - 0.25, 27.6, SAFE_X + 0.4, CEIL, 28.4, STEEL_DK, M.Metal, o, nc())
    spot(sl, Enum.NormalId.Bottom, rgb(255, 214, 170), 0.45, 12, 45, false)

    -- round door, hinged on the WEST edge, swings open north-west (+100°)
    local dz = fz0 - DISC_T / 2
    local faceZ = fz0 - DISC_T
    local door = Instance.new("Model")
    door.Name = "SafeDoor"
    door.Parent = o
    local swing = {}
    local function add(p)
        table.insert(swing, p)
        return p
    end
    add(part({ Name = "DoorDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(DISC_T, DISC_R * 2, DISC_R * 2),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, dz) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(150, 160, 156), Material = M.Metal, Reflectance = 0.12 }, door))
    local lock = add(box("LockPlate", SAFE_X - 0.5, SAFE_Y - 0.5, faceZ - 0.14, SAFE_X + 0.5, SAFE_Y + 0.5, faceZ,
        rgb(220, 190, 110), M.Metal, door, { Reflectance = 0.2 }))
    add(part({ Name = "Dial", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.7, 0.7),
        CFrame = CFrame.new(SAFE_X, SAFE_Y, faceZ - 0.21) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(28, 28, 32), Material = M.Metal, CanCollide = false }, door))
    local hub = Vector3.new(SAFE_X + 0.95, SAFE_Y, faceZ - 0.2)
    add(part({ Name = "Handle", Size = Vector3.new(0.14, 1.1, 0.14), CFrame = CFrame.new(hub),
        Color = STEEL_LT, Material = M.Metal, CanCollide = false }, door))
    local hx = SAFE_X - DISC_R
    for _, ky in ipairs({ SAFE_Y - 0.9, SAFE_Y + 0.9 }) do
        part({ Name = "HingeKnuckle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.32, 0.32),
            CFrame = CFrame.new(hx, ky, faceZ + 0.08) * CFrame.Angles(0, 0, math.rad(90)),
            Color = STEEL_DK, Material = M.Metal }, body)
    end
    refs.vault = {
        door = lock,
        parts = swing,
        hinge = CFrame.new(hx, SAFE_Y, faceZ),
        openAngle = math.rad(100),
        drillOffset = Vector3.new(0, 2, -1),     -- "Place drill" at head height
    }

    -- safe contents: cash on the shelf + cash on the floor of the safe
    local innerZ = (fz1 + SAFE_Z1 - 0.5) / 2
    local c1 = Instance.new("Model")
    c1.Name = "SafeCashTop"
    c1.Parent = o
    cashStack(c1, SAFE_X, SAFE_Y, innerZ, 2, 2, 3, rgb(214, 170, 60))
    local c2 = Instance.new("Model")
    c2.Name = "SafeCashLow"
    c2.Parent = o
    cashStack(c2, SAFE_X, FLOOR + 0.4, innerZ, 3, 2, 2, rgb(150, 90, 200))
    local loose = box("LooseBills", SAFE_X + 0.2, FLOOR + 0.92, innerZ - 0.2, SAFE_X + 0.9, FLOOR + 0.97, innerZ + 0.15, BILL, M.Fabric,
        c2, nc({ CastShadow = false }))
    billFace(loose, Enum.NormalId.Top, "20")
    part({ Name = "CoinBag", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.5, 0.5),
        Position = Vector3.new(SAFE_X - 0.8, FLOOR + 1.15, innerZ), Color = rgb(150, 130, 96), Material = M.Fabric,
        CanCollide = false, CastShadow = false }, c2)
    local function stand(x)
        local p = Vector3.new(x, FLOOR + 3, SAFE_Z0 - 1.8)
        return CFrame.lookAt(p, Vector3.new(x, p.Y, SAFE_Z0))
    end
    table.insert(loot, { kind = "SafeCash", cframe = stand(SAFE_X + 1.2), visual = c1, interact = "dial", pool = "office" })
    table.insert(loot, { kind = "SafeCash", cframe = stand(SAFE_X - 1.2), visual = c2, interact = "dial", pool = "office" })

    -- 🎟️ THE TARGET: Sunny's GOLDEN TICKET, framed on the north wall under a picture light
    local gx, gy = 51.4, FLOOR + 6.6
    local fw, fh = 1.2, 0.85
    local wz = BACK_Z0 + 0.06
    local GILT = rgb(226, 178, 62)
    box("FrameBack", gx - fw, gy - fh, wz, gx + fw, gy + fh, wz + 0.06, rgb(110, 16, 34), M.Fabric, o, nc())
    for _, e in ipairs({
        { gx - fw - 0.16, gy + fh, gx + fw + 0.16, gy + fh + 0.16 }, { gx - fw - 0.16, gy - fh - 0.16, gx + fw + 0.16, gy - fh },
        { gx - fw - 0.16, gy - fh, gx - fw, gy + fh }, { gx + fw, gy - fh, gx + fw + 0.16, gy + fh },
    }) do
        box("GiltFrame", e[1], e[2], wz, e[3], e[4], wz + 0.26, GILT, M.Metal, o, nc({ Reflectance = 0.3 }))
    end
    box("FrameGlass", gx - fw, gy - fh, wz + 0.2, gx + fw, gy + fh, wz + 0.22, rgb(220, 236, 244), M.Glass, o,
        nc({ Transparency = 0.85, Reflectance = 0.3, CastShadow = false }))
    local tv = Instance.new("Model")
    tv.Name = "GoldenTicket"
    tv.Parent = o
    local ticket = box("Ticket", gx - 0.8, gy - 0.34, wz + 0.07, gx + 0.8, gy + 0.34, wz + 0.1, rgb(240, 196, 70), M.Metal, tv,
        nc({ Reflectance = 0.25, CastShadow = false }))
    local tg = surface(ticket, Enum.NormalId.Back, 80, 1)
    tg.LightInfluence = 0.6
    local tbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, tg)
    local tgrad = Instance.new("UIGradient")
    tgrad.Rotation = 20
    tgrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, rgb(250, 220, 110)),
        ColorSequenceKeypoint.new(0.5, rgb(255, 244, 190)),
        ColorSequenceKeypoint.new(1, rgb(214, 160, 40)),
    })
    tgrad.Parent = tbg
    local border = frame({ Size = UDim2.fromScale(0.94, 0.86), Position = UDim2.fromScale(0.03, 0.07), BackgroundTransparency = 1 }, tg)
    local bst = Instance.new("UIStroke")
    bst.Color = rgb(150, 100, 20)
    bst.Thickness = 3
    bst.Parent = border
    text({ Text = "GOLDEN TICKET", Size = UDim2.fromScale(0.74, 0.36), Position = UDim2.fromScale(0.23, 0.1), TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextColor3 = rgb(120, 60, 10) }, tg)
    text({ Text = "SUNNY'S MART  ·  $1,000,000 WINNER  ·  1987", Size = UDim2.fromScale(0.72, 0.2), Position = UDim2.fromScale(0.24, 0.52),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextColor3 = rgb(110, 70, 10) }, tg)
    point(ticket, rgb(255, 214, 120), 0.3, 3.5, false)
    bar("PictureLightArm", Vector3.new(gx, gy + fh + 0.16, wz + 0.05), Vector3.new(gx, gy + fh + 0.5, wz + 0.4), 0.06, GILT, M.Metal, o, nc())
    local pl = box("PictureLight", gx - 0.8, gy + fh + 0.42, wz + 0.3, gx + 0.8, gy + fh + 0.58, wz + 0.55, GILT, M.Metal, o, nc())
    spot(pl, Enum.NormalId.Bottom, rgb(255, 216, 160), 0.8, 6, 70, false)
    local plq = box("TicketPlaque", gx - 0.6, gy - fh - 0.52, wz, gx + 0.6, gy - fh - 0.28, wz + 0.04, GILT, M.Metal, o, nc())
    lit(printOn(plq, Enum.NormalId.Back, "OUR FIRST MILLIONAIRE", rgb(60, 36, 14), UITheme.F.display, 80, 1).Parent)
    local ts = Vector3.new(gx, FLOOR + 3, 22.1)
    table.insert(loot, { kind = "GoldenTicket", target = "GoldenTicket", cframe = CFrame.lookAt(ts, Vector3.new(gx, ts.Y, BACK_Z0)),
        visual = tv, pool = "office", inVault = false })

    -- desk chair + monitor (Kenney, repainted after they load)
    prop("furniture", "chairDesk", Vector3.new(57.2, FLOOR, dz1 + 0.7), Vector3.new(0, 0, -1), o,
        { main = { rgb(28, 26, 30), M.Fabric }, accent = { rgb(150, 154, 162), M.Metal } }, { collide = false })
    prop("furniture", "computerScreen", Vector3.new(56.6, topY, dz0 + 0.7), Vector3.new(0, 0, 1), o,
        { main = { rgb(36, 38, 44), M.Metal, 0.05 }, byName = { screen = { rgb(40, 90, 140), M.Glass, 0.2 } } })

    return inside
end

-- ──────────────────────────────────────────────
-- 🚗 the walled SERVICE YARD (the getaway car) + the roof
-- ──────────────────────────────────────────────
function MartBuilder:_yard(f, refs)
    local a = Instance.new("Folder")
    a.Name = "ServiceYard"
    a.Parent = f
    local BRICK = rgb(150, 84, 62)
    local CAP = rgb(196, 188, 176)
    local PLINTH = rgb(78, 74, 72)
    local H, T = YWALL_H, YWALL_T
    local EX0 = YARD_X1 - T               -- inner face of the east wall (83.1)
    local SZ0 = YARD_Z1 - T

    -- ground + the parking bay
    box("YardFloor", X1, 0, Z0, EX0, 0.1, SZ0, rgb(52, 52, 58), M.Asphalt, a)
    box("Driveway", X1, 0, -1.4, EX0, 0.1, Z0, rgb(150, 148, 142), M.Concrete, a)
    local LINE = SAFETY
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z - 6.2, CAR_X - 3.2, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X + 3.2, 0.1, CAR_Z - 6.2, CAR_X + 3.4, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    box("BayLine", CAR_X - 3.4, 0.1, CAR_Z + 6.4, CAR_X + 3.4, 0.12, CAR_Z + 6.6, LINE, M.Plaster, a, nc())
    -- hatched "keep clear" box in front of the loading door
    for k = 0, 4 do
        local z = LOAD_Z0 + 0.8 + k * 1.5
        part({ Name = "KeepClearHatch", Size = Vector3.new(0.2, 0.02, 2.4),
            CFrame = CFrame.new(X1 + 2.6, 0.11, z) * CFrame.Angles(0, math.rad(45), 0),
            Color = LINE, Material = M.Plaster, CanCollide = false, CastShadow = false }, a)
    end

    -- brick walls (meet the store walls exactly)
    box("YardGatePost", GATE_X1, 0, Z0 - 0.3, EX0, H + 1, Z0 + 0.7, BRICK, M.Brick, a)
    box("YardWallE", EX0, 0, Z0 - 0.3, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    box("YardWallS", X1, 0, SZ0, YARD_X1, H, YARD_Z1, BRICK, M.Brick, a)
    box("YardCoping", EX0 - 0.1, H, Z0 - 0.4, YARD_X1 + 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("YardCoping", X1, H, SZ0 - 0.1, EX0 - 0.1, H + 0.35, YARD_Z1 + 0.1, CAP, M.Concrete, a)
    box("PostCap", GATE_X1 - 0.1, H + 1, Z0 - 0.4, EX0, H + 1.4, Z0 + 0.8, CAP, M.Concrete, a)
    box("Plinth", EX0 - 0.08, 0.1, Z0 + 0.7, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())
    box("Plinth", X1, 0.1, SZ0 - 0.08, EX0, 1.1, SZ0, PLINTH, M.Concrete, a, nc())

    -- the vehicle gate: roll-up shutter, rolled up (clear height 10.6)
    local SHUT = rgb(150, 156, 166)
    local gz0, gz1 = Z0 - 0.2, Z0 + 0.4
    local beam = box("GateHeader", GATE_X0, 11.4, gz0, GATE_X1, 12.2, gz1, BRICK, M.Brick, a)
    box("ShutterDrum", GATE_X0 + 0.1, 10.9, gz0 + 0.05, GATE_X1 - 0.1, 11.4, gz1 + 0.35, SHUT, M.Metal, a, nc())
    box("ShutterBottomBar", GATE_X0 + 0.2, 10.6, gz1 - 0.05, GATE_X1 - 0.2, 10.9, gz1 + 0.15, STEEL, M.Metal, a, nc())
    for _, gx in ipairs({ GATE_X0 + 0.05, GATE_X1 - 0.2 }) do
        box("ShutterGuide", gx, 0.1, gz0 + 0.1, gx + 0.15, 11.4, gz1, STEEL, M.Metal, a, nc())
    end
    lit(printOn(beam, Enum.NormalId.Front, "DELIVERIES · NO PARKING", rgb(250, 240, 220), UITheme.F.bold, 30, 1).Parent)
    local lantern = box("PostLantern", GATE_X1 + 0.1, H + 1.4, Z0 - 0.2, EX0 - 0.1, H + 2.3, Z0 + 0.5, STEEL_DK, M.Metal, a, nc())
    box("PostLanternGlass", GATE_X1 + 0.18, H + 1.55, Z0 - 0.12, EX0 - 0.18, H + 2.15, Z0 + 0.42, rgb(255, 214, 150), M.Neon, a,
        nc({ CastShadow = false }))
    point(lantern, rgb(255, 196, 130), 0.8, 12, false)

    -- the yard's key light over the car (shadows)
    local key = box("YardLamp", EX0 - 0.7, 9.6, CAR_Z - 0.7, EX0, 10.3, CAR_Z + 0.7, STEEL_DK, M.Metal, a, nc())
    box("YardLampLens", EX0 - 0.65, 9.52, CAR_Z - 0.6, EX0 - 0.05, 9.6, CAR_Z + 0.6, rgb(255, 196, 120), M.Neon, a,
        nc({ CastShadow = false }))
    spot(key, Enum.NormalId.Bottom, rgb(255, 184, 120), 1.3, 24, 120, true)

    -- props against the east wall, south of the car, clear of the door → car walk
    -- (the walk from the loading door to the car's trunk keeps ≥ 6 clear
    -- between the ladder's corner (76, 18.6) and the dumpster's (80, 24))
    local dz0, dz1 = 24, 27.8
    box("Dumpster", EX0 - 3.1, 0.4, dz0, EX0 - 0.2, 4.2, dz1, rgb(30, 90, 150), M.Metal, a)
    box("DumpsterLid", EX0 - 3.2, 4.2, dz0 - 0.1, EX0 - 0.1, 4.45, dz1 + 0.1, rgb(22, 66, 110), M.Metal, a)
    box("DumpsterSkid", EX0 - 2.9, 0.1, dz0 + 0.2, EX0 - 0.4, 0.4, dz1 - 0.2, STEEL_DK, M.Metal, a)
    part({ Name = "BinBag", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.2, 1.3),
        Position = Vector3.new(EX0 - 1.2, 0.7, 28.5), Color = rgb(24, 24, 28), Material = M.Rubber }, a)
    part({ Name = "FlatBoxes", Size = Vector3.new(0.3, 3.4, 2.6),
        CFrame = CFrame.new(EX0 - 0.5, 1.8, 18.4) * CFrame.Angles(0, 0, math.rad(10)),
        Color = rgb(186, 150, 104), Material = M.Cardboard, CanCollide = false }, a)
    -- puddles: flat ovals a shade darker than the asphalt, a little reflective
    for _, pd in ipairs({ { 80.6, 19.6, 3.4, 1.8, 1.3 }, { 76.2, 2.8, 2.8, 1.4, 0.2 } }) do
        local pud = part({ Name = "Puddle", Size = Vector3.new(pd[3], 0.04, pd[4]),
            CFrame = CFrame.new(pd[1], 0.1, pd[2]) * CFrame.Angles(0, pd[5], 0), Color = rgb(40, 41, 48),
            Material = M.SmoothPlastic, Transparency = 0.3, Reflectance = 0.4,
            CanCollide = false, CastShadow = false, CanQuery = false, CanTouch = false }, a)
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.Sphere
        mesh.Parent = pud
    end
    -- a painted sun on the yard wall beside the car (brand colours)
    local mural = box("YardMural", EX0 - 0.06, 2, 2.6, EX0, 8.8, 8.6, BRICK, M.Brick, a, nc({ Transparency = 1 }))
    local mg = lit(surface(mural, Enum.NormalId.Left, 16, 1))
    local sun = frame({ Size = UDim2.fromScale(0.34, 0.5), Position = UDim2.fromScale(0.33, 0.08), BackgroundColor3 = SUNNY }, mg)
    UITheme.corner(sun, 999)
    text({ Text = "SUNNY SIDE UP", Size = UDim2.fromScale(0.96, 0.26), Position = UDim2.fromScale(0.02, 0.66),
        TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextColor3 = rgb(250, 240, 220) }, mg)

    -- the roof ladder: a climbable truss on the store's east wall (z 17.4..19.4)
    local truss = Instance.new("TrussPart")
    truss.Name = "RoofLadder"
    truss.Anchored = true
    truss.Size = Vector3.new(2, 18, 2)
    truss.CFrame = CFrame.new(X1 + 1, 9, LADDER_Z)
    truss.Color = STEEL_LT
    truss.Material = M.Metal
    truss.Parent = a
    sign("RoofSign", X1, 2.4, LADDER_Z - 2.6, X1 + 0.1, 3.6, LADDER_Z - 1.4, Enum.NormalId.Right, "ROOF",
        rgb(250, 204, 21), rgb(30, 30, 30), a)

    table.insert(refs.shadowZones, shadowZone("ShadowYard", EX0 - 4.5, 17.2, EX0, 21.2, a))
end

function MartBuilder:_roof(f)
    local r = Instance.new("Folder")
    r.Name = "RoofAccess"
    r.Parent = f
    local hx, hz = 52.2, 26.6                      -- over the office ladder
    box("HatchPaint", hx - 2.4, ROOF_Y, hz - 2.4, hx + 2.4, ROOF_Y + 0.03, hz + 2.4, rgb(230, 190, 40), M.Concrete, r, nc())
    box("HatchCurb", hx - 1.7, ROOF_Y, hz - 1.7, hx + 1.7, ROOF_Y + 0.6, hz + 1.7, STEEL, M.Metal, r)
    local lid = facingPart("SM_RoofHatch", Vector3.new(hx, ROOF_Y + 0.75, hz), Vector3.new(2.9, 0.3, 2.9),
        Vector3.new(1, 0, 0), rgb(250, 204, 21), M.DiamondPlate, r)
    bar("HatchHandle", Vector3.new(hx + 0.7, ROOF_Y + 1.0, hz - 0.7), Vector3.new(hx + 0.7, ROOF_Y + 1.0, hz + 0.7), 0.14,
        STEEL_DK, M.Metal, r, nc())
    return lid
end

-- ──────────────────────────────────────────────
-- 📹 CAMERA
-- ──────────────────────────────────────────────
function MartBuilder:_camera(f, name, mount, out, target, yawRange, period)
    local m = Instance.new("Model")
    m.Name = name
    m.Parent = f
    part({ Name = "Bracket", Size = Vector3.new(0.9, 0.9, 0.2), CFrame = CFrame.lookAt(mount + out * 0.1, mount + out * 2),
        Color = STEEL_DK, Material = M.Metal, CanCollide = false }, m)
    local armEnd = mount + out * 1.1
    bar("Body", mount + out * 0.2, armEnd, 0.22, STEEL_DK, M.Metal, m, nc())
    part({ Name = "Knuckle", Shape = Enum.PartType.Ball, Size = Vector3.new(0.34, 0.34, 0.34), Position = armEnd,
        Color = STEEL_DK, Material = M.Metal, CanCollide = false }, m)
    local headPos = armEnd + Vector3.new(0, -0.45, 0)
    local head = part({ Name = "Head", Size = Vector3.new(0.7, 0.6, 1.3), CFrame = CFrame.lookAt(headPos, target),
        Color = rgb(226, 228, 232), Material = M.Metal, CanCollide = false }, m)
    local lens = part({ Name = "Lens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.42, 0.42),
        CFrame = head.CFrame * CFrame.new(0, 0, -0.68) * CFrame.Angles(0, math.rad(90), 0),
        Color = rgb(12, 12, 16), Material = M.Glass }, m)
    weldTo(head, lens)
    local led = part({ Name = "Led", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16),
        CFrame = head.CFrame * CFrame.new(0.22, 0.2, -0.6), Color = rgb(255, 50, 50), Material = M.Neon }, m)
    weldTo(head, led)
    local light = spot(head, Enum.NormalId.Front, rgb(255, 60, 60), 1.2, 30, 48)
    return { model = m, head = head, light = light, led = led, yawRange = yawRange, period = period }
end

-- ──────────────────────────────────────────────
function MartBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "SunnysMart"
    f.Parent = folder

    local refs = {
        id = "mart",
        root = f,
        entryPoint = Vector3.new(CX, 3, -2),
        -- (v3.3 SLICE) the crew starts on the SIDEWALK, all facing the front door,
        -- in two rows of 4 (x 62.2..67.6, z -3.4 / -5.2), ≥ 1.3 clear of the
        -- city's litter bin (60, -1.9), the palm (70, -2.7) and the lamp pole
        -- (56, -2.2). The yard gate is open to the right: the getaway car shows.
        arrival = { at = Vector3.new(64.9, 3.5, -3.4), face = Vector3.new(64.9, 3.5, 6), spread = Vector3.new(0.9, 0, 0),
            rowGap = 1.8,
            line = "Walk in like a customer. The breaker is in the back!" },
        -- a guard kick-back / jail break-out puts you here: the stock room by the
        -- loading door, away from the guard (he never leaves the shop floor)
        sneakIn = { at = Vector3.new(70.5, 3.5, 24.2), face = Vector3.new(62, 3.5, 24.2),
            spread = Vector3.new(0, 0, 0.45) },
        goalChain = true,
        -- MaskUpService: behind the curtain is staff only. The office holds the
        -- safe → walking in = MASK UP. y band keeps the roof public.
        restricted = {
            { STOCK_X0, SALES_Z1 + 0.4, IX1, IZ1, name = "STOCK ROOM", y0 = FLOOR - 4, y1 = FLOOR + 12 },
            { BIX0, SALES_Z1 + 0.4, OFFICE_X1 + 0.5, IZ1, crime = true, name = "OFFICE", y0 = FLOOR - 4, y1 = FLOOR + 12 },
        },
        entrances = {
            { kind = "front", at = Vector3.new(CX, 3, -2.5), label = "Front door" },
            { kind = "side", at = Vector3.new(X1 + 3, 3, (LOAD_Z0 + LOAD_Z1) / 2), label = "Loading door (yard)" },
            { kind = "roof", at = Vector3.new(X1 + 3.2, 3, LADDER_Z), label = "Roof ladder" },
        },
        hideSpots = {},
        shadowZones = {},
        vents = {},
        policeStop = Vector3.new(28, 0, -14),
        getawayCFrame = CFrame.lookAt(Vector3.new(CAR_X, 0, CAR_Z), Vector3.new(CAR_X, 0, CAR_Z - 10)),
        keycardDoors = {},
        keycardSpots = {},
        laserRows = {},
        smashCases = {},
        poolNames = { counter = "COUNTER", floor = "SHOP FLOOR", stockroom = "STOCK ROOM", office = "OFFICE" },
    }
    local loot = {}

    self:_shell(f)
    refs.openSign = self:_facade(f)
    self:_salesFloor(f, refs, loot)
    refs.breaker = self:_stockRoom(f, refs, loot)
    local hatchInside = self:_office(f, refs, loot)
    self:_yard(f, refs)
    local hatchRoof = self:_roof(f)
    refs.lootSpots = loot

    tag(hatchRoof, "Vent", { Pair = hatchInside.Name, Label = "Climb down",
        Exit = Vector3.new(55.4, ROOF_Y, 26.6) })
    tag(hatchInside, "Vent", { Pair = hatchRoof.Name, Label = "Climb to the roof",
        Exit = Vector3.new(51.9, FLOOR, 26.6) })
    refs.vents = { { a = hatchRoof, b = hatchInside } }

    local cams = Instance.new("Folder")
    cams.Name = "Cameras"
    cams.Parent = f
    -- over the freezer, watching the counter and the front door. The curtain
    -- (east of it, behind its sweep) is a blind spot.
    local cam = self:_camera(cams, "Camera_Register", Vector3.new(55.2, 12.5, SALES_Z1), Vector3.new(0, 0, -1),
        Vector3.new(56.5, FLOOR, 7), 60, 8)
    refs.cameras = { cam }
    sign("CameraSticker", 53.6, 10, SALES_Z1 - 0.06, 56.8, 11, SALES_Z1, Enum.NormalId.Front,
        "SMILE! YOU'RE ON CAMERA", SUNNY, INK, cams, UITheme.F.bold)

    -- ONE guard: up and down the counter aisle (x 59.2), pausing at each end.
    -- ≥ 2 studs off the counter (55.5) and the island (61.5). Facing south at
    -- the back end, the curtain doorway is 50° off his nose (his FOV is ±40°).
    -- (v3.3) `waypoints` / `pause` = his loop round the island, walked by
    -- GuardService (a / b stay as the fallback lane for older code).
    refs.guardRoutes = {
        { name = "Guard_Sunny", spawn = Vector3.new(GUARD_X, 3.5, GUARD_Z0),
            a = Vector3.new(GUARD_X, 3.5, GUARD_Z0), b = Vector3.new(GUARD_X, 3.5, GUARD_Z1),
            waypoints = {
                Vector3.new(GUARD_X, 3.5, GUARD_Z0), Vector3.new(GUARD_X, 3.5, GUARD_Z1),
                Vector3.new(67.2, 3.5, GUARD_Z1), Vector3.new(67.2, 3.5, GUARD_Z0),
            },
            pause = 2 },
    }

    refs.plan = {
        bounds = { BX0, Z0, X1, Z1 },
        rooms = {
            { X0, Z0, X1, SALES_Z1, "STORE" },
            { BIX0, BACK_Z0, OFFICE_X1, IZ1, "OFFICE" },
            { STOCK_X0, BACK_Z0, IX1, IZ1, "STOCK" },
        },
        vault = { SAFE_X, (SAFE_Z0 + SAFE_Z1) / 2 },
        entry = { CX, Z0 },
    }

    print("[MartBuilder] Sunny's Mart built ☀️")
    return refs
end

return MartBuilder
