--[[
    HEIST CREW — ClubBuilder  (v1.2 "THE VAULT")
    ────────────────────────────────────────────────
    The crew's underground HQ: a two-storey neon nightclub hidden under the
    Riverside Auto Body shop. This is where you SPAWN. (Malachi picked option A,
    2026-09-25: "a huge inside center where the heist spawns you".)

    Footprint x -44..44, z 0..64, floor top y -27.5 (Constants.WORLD.HUB_*),
    ceiling y -3.5 — safely under the street-level lawn (y -2..0).

      NORTH  DJ stage + LED wall ("THE VAULT") + moving truss spots
             dance floor (glass tiles the client animates — ClubFX)
      CENTRE holo planning table: blueprint + Boss (the plan) + "see another plan" (R)
             job screen hanging above it (next job · top earners · crew)
      WEST   the bar, VIP mezzanine above it (stairs by the stage)
             mask wall (real catalog masks on display heads) → opens the shop
      EAST   crew-role pads + signs
      SOUTH  freight elevator up to the auto shop ·
             garage bay with the ramp the getaway car rolls up at launch ·
             trophy room (fills in as the crew pulls off heists) ·
             a big ARCH (x -7..7) through to the entrance lobby

    v2.0 "BIGGER" — THE ENTRANCE LOBBY + HEIST HALL (annex south of the club,
    x -32..44, z 65..118, same floor, ceiling F+20). Malachi: spawns must "look
    real, not just outside some weird stuff", "like most games".
      CENTRE red carpet from the spawn medallion up to the arch, velvet ropes,
             the bouncer + host stand, a lit "THE VAULT" marquee over the arch,
             a hanging direction sign (BOSS / MASKS & GEAR / HEIST DOORS)
             6 SpawnLocations on the medallion, facing north into the club
      WEST   coat check (counter + coat rails) · leaderboard wall + lounge
      EAST   HEIST HALL: 4 heist doors (elevator doors in the east wall), one per
             job (mart · villa · jewelry · bank, easy → hard, north → south),
             each with a sign (name · difficulty · players) and a glowing floor
             zone in front — walk in to join that heist (PortalService does the rest)

    Returns refs in the SAME shape SafehouseBuilder used to (pads / tv /
    blueprint) so CrewService + SafehouseBuilder:showJob work unchanged, plus
    trophies / bay / prompts. Geometry only — services add the behaviour.
    Tagged for ClubFX (client): DanceTile, ClubLight, ClubSpot, ClubEQ,
    PortalGlow, MarqueeBulb.  Tagged for PortalHud: PortalZone (attr JobId).

    v2 REFS (docs/V2_SPEC.md §7):
      refs.spawnPads = { SpawnLocation × 6 }   Neutral, Enabled, Duration 5, facing north
      refs.portals[jobId] = { zone = BasePart, setState = function(count, needed, launchIn, locked) }
          zone     : invisible trigger box (CanCollide false, CanTouch true, Anchored),
                     tagged "PortalZone", attribute JobId = jobId
          setState : count (players in the zone), needed (players to launch, may be nil),
                     launchIn (seconds left, nil/0 = not counting), locked (false | true |
                     level number) → updates the door sign, floor glow and door leaves
      refs.leaderboardAnchor = CFrame   (see _lobbyWest — board front faces along LookVector)
      refs.introPath = { CFrame × 6 }   first-join camera fly-over (IntroCam.lua)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local KenneyLoader = require(script.Parent.KenneyLoader)

local ClubBuilder = {}

local W = Constants.WORLD
local T = UITheme.C
local F = W.HUB_FLOOR                         -- -27.5 (floor top)
local HW, HD, H = W.HUB_HALF_WIDTH, W.HUB_HALF_DEPTH, W.HUB_HEIGHT
local CZ = W.HUB_CENTER.z
local X0, X1 = -HW, HW                        -- -44 .. 44
local Z0, Z1 = CZ - HD, CZ + HD               -- 0 .. 64
local TOP = F + H                             -- -3.5 ceiling
local MEZZ = F + 11                           -- -16.5 mezzanine floor top

local PINK = Color3.fromRGB(255, 70, 180)
local CYAN = Color3.fromRGB(40, 230, 255)
local PURPLE = Color3.fromRGB(170, 90, 255)
local WALL = Color3.fromRGB(34, 30, 44)
local PANEL = Color3.fromRGB(24, 22, 32)
local STEEL = Color3.fromRGB(44, 47, 56)
local WOOD = Color3.fromRGB(70, 46, 34)
local GOLD = Color3.fromRGB(212, 170, 80)
local VELVET = Color3.fromRGB(128, 18, 34)

-- v2.0: arch in the club's south wall → the entrance lobby / heist hall annex
local ARCH_HW, ARCH_H = 7, 11                 -- opening x -7..7, 11 tall
local LX0, LX1 = -32, 44                      -- annex floor x
local LZ0, LZ1 = Z1 + 1, 118                  -- annex floor z 65..118
local LTOP = F + 20                           -- annex ceiling
local PORTAL_Z = { 74, 86, 98, 110 }          -- heist door centres on the east wall (x 44)
local PORTAL_ORDER = { "mart", "villa", "jewelry", "bank" }   -- easy → hard, north → south
local PORTAL_HW, PORTAL_H = 4, 11             -- door opening 8 wide, 11 tall
local SPAWN_XS, SPAWN_ZS = { -6, 0, 6 }, { 98, 104 }

-- ── helpers (same style as SafehouseBuilder) ─────────────────────────
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
        Color = color, Material = material,
    }
    for k, v in pairs(extra or {}) do props[k] = v end
    return part(props, parent)
end

local function neon(name, x0, y0, z0, x1, y1, z1, color, parent)
    return box(name, x0, y0, z0, x1, y1, z1, color, Enum.Material.Neon, parent, { CanCollide = false })
end

local function surface(p, face, pps)
    local g = Instance.new("SurfaceGui")
    g.Face = face
    g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    g.PixelsPerStud = pps or 40
    g.LightInfluence = 0
    g.Brightness = 1.4
    g.Parent = p
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

local function light(class, parent, props)
    local l = Instance.new(class)
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function sub(parent, name)
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

local function prompt(parent, name, action, object, key, hold)
    local p = Instance.new("ProximityPrompt")
    p.Name = name
    p.ActionText = action
    p.ObjectText = object
    p.HoldDuration = hold or 0.3
    p.MaxActivationDistance = 10
    p.RequiresLineOfSight = false
    p.KeyboardKeyCode = key or Enum.KeyCode.E
    p.Parent = parent
    return p
end

-- ──────────────────────────────────────────────
-- 🏗 SHELL
-- ──────────────────────────────────────────────
function ClubBuilder:_shell(f)
    -- polished dark floor
    box("Floor", X0, F - 1, Z0, X1, F, Z1, Color3.fromRGB(26, 24, 32), Enum.Material.Marble, f, { Reflectance = 0.08 })
    box("Ceiling", X0 - 1, TOP, Z0 - 1, X1 + 1, TOP + 1, Z1 + 1, Color3.fromRGB(18, 18, 24), Enum.Material.Metal, f)
    -- walls
    box("WallN", X0 - 1, F, Z0 - 1, X1 + 1, TOP, Z0, WALL, Enum.Material.Concrete, f)
    -- (v2.0) the south wall has a big arch through to the entrance lobby
    box("WallSW", X0 - 1, F, Z1, -ARCH_HW, TOP, Z1 + 1, WALL, Enum.Material.Concrete, f)
    box("WallSE", ARCH_HW, F, Z1, X1 + 1, TOP, Z1 + 1, WALL, Enum.Material.Concrete, f)
    box("WallSHeader", -ARCH_HW, F + ARCH_H, Z1, ARCH_HW, TOP, Z1 + 1, WALL, Enum.Material.Concrete, f)
    box("WallW", X0 - 1, F, Z0, X0, TOP, Z1, WALL, Enum.Material.Concrete, f)
    box("WallE", X1, F, Z0, X1 + 1, TOP, Z1, WALL, Enum.Material.Concrete, f)
    -- acoustic panels (fabric) in a band around the room
    box("PanelsW", X0, F + 3, Z0 + 1, X0 + 0.3, F + 9, Z1 - 1, PANEL, Enum.Material.Fabric, f)
    box("PanelsE", X1 - 0.3, F + 3, Z0 + 1, X1, F + 9, Z1 - 1, PANEL, Enum.Material.Fabric, f)
    box("PanelsSW", X0 + 1, F + 3, Z1 - 0.3, -ARCH_HW - 1, F + 9, Z1, PANEL, Enum.Material.Fabric, f)
    box("PanelsSE", ARCH_HW + 1, F + 3, Z1 - 0.3, X1 - 1, F + 9, Z1, PANEL, Enum.Material.Fabric, f)
    -- ceiling trusses
    for z = Z0 + 8, Z1 - 4, 12 do
        box("Truss", X0, TOP - 1.4, z - 0.4, X1, TOP - 0.6, z + 0.4, STEEL, Enum.Material.Metal, f)
    end
    -- neon: pink along the long walls up top, cyan along the short walls, purple at the base
    neon("NeonW", X0 + 0.05, TOP - 2.2, Z0 + 1, X0 + 0.3, TOP - 2, Z1 - 1, PINK, f)
    neon("NeonE", X1 - 0.3, TOP - 2.2, Z0 + 1, X1 - 0.05, TOP - 2, Z1 - 1, PINK, f)
    neon("NeonN", X0 + 1, TOP - 2.2, Z0 + 0.05, X1 - 1, TOP - 2, Z0 + 0.3, CYAN, f)
    neon("NeonS", X0 + 1, TOP - 2.2, Z1 - 0.3, X1 - 1, TOP - 2, Z1 - 0.05, CYAN, f)
    neon("BaseW", X0 + 0.3, F + 0.1, Z0 + 1, X0 + 0.45, F + 0.25, Z1 - 1, PURPLE, f)
    neon("BaseE", X1 - 0.45, F + 0.1, Z0 + 1, X1 - 0.3, F + 0.25, Z1 - 1, PURPLE, f)
    -- four big columns with neon rings
    for _, c in ipairs({ { -22, 24 }, { 22, 24 }, { -22, 40 }, { 22, 40 } }) do
        part({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(H, 3, 3),
            CFrame = CFrame.new(c[1], F + H / 2, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(40, 38, 50), Material = Enum.Material.Concrete }, f)
        for _, y in ipairs({ F + 3, TOP - 4 }) do
            part({ Name = "ColumnRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 3.3, 3.3),
                CFrame = CFrame.new(c[1], y, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
                Color = (c[2] < 30) and CYAN or PINK, Material = Enum.Material.Neon, CanCollide = false }, f)
        end
    end
    -- soft fill so it's moody, not pitch black
    local fill = box("Fill", -1, TOP - 3, CZ - 1, 1, TOP - 2.5, CZ + 1, STEEL, Enum.Material.Metal, f, { Transparency = 1, CanCollide = false })
    -- (v2.0.2) a touch lower under Future: the neon + truss spots do the work
    light("PointLight", fill, { Brightness = 0.4, Range = 60, Color = Color3.fromRGB(150, 120, 200) })
end

-- ──────────────────────────────────────────────
-- 🎧 DJ STAGE + LED WALL + truss spots
-- ──────────────────────────────────────────────
function ClubBuilder:_stage(f)
    local sy = F + 2.5
    box("Stage", -14, F, Z0, 14, sy, Z0 + 9, Color3.fromRGB(30, 30, 36), Enum.Material.DiamondPlate, f)
    neon("StageEdge", -14, sy - 0.25, Z0 + 9, 14, sy - 0.05, Z0 + 9.2, CYAN, f)
    for i = 1, 3 do
        box("StageStep", -4, F, Z0 + 9 + (i - 1) * 0.9, 4, sy - i * 0.8, Z0 + 9.9 + (i - 1) * 0.9,
            Color3.fromRGB(34, 34, 40), Enum.Material.DiamondPlate, f)
    end
    -- DJ desk + decks
    box("DJDesk", -5, sy, Z0 + 4.5, 5, sy + 3, Z0 + 6.5, Color3.fromRGB(16, 16, 20), Enum.Material.Metal, f)
    neon("DJDeskGlow", -5, sy + 0.3, Z0 + 6.5, 5, sy + 0.45, Z0 + 6.6, PINK, f)
    for _, dx in ipairs({ -2.6, 2.6 }) do
        part({ Name = "Turntable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.2, 2.2),
            CFrame = CFrame.new(dx, sy + 3.1, Z0 + 5.5) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(12, 12, 14), Material = Enum.Material.Metal }, f)
    end
    KenneyLoader.placeMany({
        { kit = "furniture", name = "speaker", pos = Vector3.new(-11, sy, Z0 + 5), facing = Vector3.new(0, 0, 1), opts = { scale = 2.4 } },
        { kit = "furniture", name = "speaker", pos = Vector3.new(11, sy, Z0 + 5), facing = Vector3.new(0, 0, 1), opts = { scale = 2.4 } },
        { kit = "furniture", name = "laptop", pos = Vector3.new(0, sy + 3, Z0 + 5.4), facing = Vector3.new(0, 0, -1) },
    }, f)

    -- LED wall (the client animates the EQ bars — ClubFX)
    local led = box("LEDWall", -18, F + 3, Z0, 18, F + 19, Z0 + 0.4, Color3.fromRGB(6, 6, 10), Enum.Material.Glass, f)
    local g = surface(led, Enum.NormalId.Back, 22)
    g.Brightness = 2
    CollectionService:AddTag(g, "ClubEQ")
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 6, 16) }, g)
    local grad = Instance.new("UIGradient")
    grad.Rotation = 90
    grad.Color = ColorSequence.new(Color3.fromRGB(60, 10, 70), Color3.fromRGB(8, 20, 60))
    grad.Parent = bg
    local eq = frame({ Name = "EQ", Size = UDim2.new(1, -60, 0.55, 0), Position = UDim2.new(0, 30, 0.42, 0),
        BackgroundTransparency = 1 }, bg)
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.Padding = UDim.new(0, 6)
    layout.Parent = eq
    for i = 1, 28 do
        local b = frame({ Name = "Bar", Size = UDim2.new(1 / 28, -6, 0.3, 0), BackgroundColor3 = (i % 2 == 0) and PINK or CYAN }, eq)
        b.LayoutOrder = i
        UITheme.corner(b, 3)
    end
    text({ Text = "THE VAULT", Position = UDim2.fromScale(0, 0.06), Size = UDim2.fromScale(1, 0.32),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(255, 240, 250), TextStrokeColor3 = PINK, TextStrokeTransparency = 0.2 }, bg)
    light("SurfaceLight", led, { Face = Enum.NormalId.Back, Brightness = 1.2, Range = 22, Angle = 90, Color = PURPLE })

    -- truss with moving spots (ClubSpot — rotated by ClubFX on each client)
    box("StageTruss", -16, TOP - 5, Z0 + 10, 16, TOP - 4.4, Z0 + 10.6, STEEL, Enum.Material.Metal, f)
    local cols = { PINK, CYAN, PURPLE, Color3.fromRGB(255, 170, 60) }
    for i, x in ipairs({ -12, -4, 4, 12 }) do
        local head = part({ Name = "MovingHead", Size = Vector3.new(1.2, 1.2, 1.6), Color = Color3.fromRGB(20, 20, 24),
            Material = Enum.Material.Metal, CanCollide = false,
            CFrame = CFrame.lookAt(Vector3.new(x, TOP - 5.6, Z0 + 10.3), Vector3.new(x, F, Z0 + 20)) }, f)
        head:SetAttribute("Seed", i)
        CollectionService:AddTag(head, "ClubSpot")
        light("SpotLight", head, { Face = Enum.NormalId.Front, Angle = 28, Brightness = 5, Range = 40, Color = cols[i], Shadows = false })
    end
end

-- ──────────────────────────────────────────────
-- 💃 DANCE FLOOR (tiles animated client-side)
-- ──────────────────────────────────────────────
function ClubBuilder:_danceFloor(f)
    local x0, z0 = -12, 12
    local cols, rows = 12, 8
    local palette = { PINK, CYAN, PURPLE }
    for c = 0, cols - 1 do
        for r = 0, rows - 1 do
            local t = part({ Name = "DanceTile", Size = Vector3.new(1.9, 0.2, 1.9),
                Position = Vector3.new(x0 + c * 2 + 1, F + 0.1, z0 + r * 2 + 1),
                Color = palette[(c + r) % 3 + 1], Material = Enum.Material.Glass, Transparency = 0.1, Reflectance = 0.1 }, f)
            t:SetAttribute("Col", c)
            t:SetAttribute("Row", r)
            CollectionService:AddTag(t, "DanceTile")
        end
    end
    neon("FloorFrameN", x0 - 0.3, F, z0 - 0.3, x0 + cols * 2 + 0.3, F + 0.25, z0, CYAN, f)
    neon("FloorFrameS", x0 - 0.3, F, z0 + rows * 2, x0 + cols * 2 + 0.3, F + 0.25, z0 + rows * 2 + 0.3, CYAN, f)
    neon("FloorFrameW", x0 - 0.3, F, z0, x0, F + 0.25, z0 + rows * 2, CYAN, f)
    neon("FloorFrameE", x0 + cols * 2, F, z0, x0 + cols * 2 + 0.3, F + 0.25, z0 + rows * 2, CYAN, f)
    for i, p in ipairs({ { -6, 16 }, { 6, 16 }, { -6, 24 }, { 6, 24 } }) do
        local anchor = box("FloorLight", p[1] - 0.2, TOP - 3, p[2] - 0.2, p[1] + 0.2, TOP - 2.6, p[2] + 0.2, STEEL,
            Enum.Material.Metal, f, { Transparency = 1, CanCollide = false })
        anchor:SetAttribute("Seed", i)
        CollectionService:AddTag(anchor, "ClubLight")
        light("PointLight", anchor, { Brightness = 2.2, Range = 26, Color = palette[(i - 1) % 3 + 1] })
    end
end

-- ──────────────────────────────────────────────
-- 🍸 BAR (west) + VIP MEZZANINE above it
-- ──────────────────────────────────────────────
function ClubBuilder:_bar(f)
    local bx = X0 + 8     -- counter front face x -36
    box("BarBase", bx - 2, F, 12, bx, F + 3.4, 34, WOOD, Enum.Material.WoodPlanks, f)
    box("BarTop", bx - 2.3, F + 3.4, 11.7, bx + 0.3, F + 3.7, 34.3, Color3.fromRGB(230, 225, 235), Enum.Material.Marble, f)
    neon("BarGlow", bx + 0.02, F + 0.3, 12, bx + 0.12, F + 0.45, 34, PINK, f)
    -- back bar: shelves + bottles against the wall
    for i, y in ipairs({ F + 4, F + 6.5, F + 9 }) do
        box("Shelf" .. i, X0 + 0.3, y, 13, X0 + 2.2, y + 0.25, 33, Color3.fromRGB(30, 26, 28), Enum.Material.Metal, f)
        neon("ShelfGlow" .. i, X0 + 2.15, y - 0.05, 13, X0 + 2.25, y, 33, i % 2 == 0 and CYAN or PURPLE, f)
        local bottleCols = { Color3.fromRGB(60, 180, 90), Color3.fromRGB(200, 120, 40), Color3.fromRGB(80, 140, 220), Color3.fromRGB(220, 60, 90) }
        for z = 13.8, 32.4, 1.25 do
            local hgt = 1.1 + ((z * 7) % 3) * 0.25
            part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(hgt, 0.45, 0.45),
                CFrame = CFrame.new(X0 + 1.2, y + 0.25 + hgt / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
                Color = bottleCols[math.floor(z) % 4 + 1], Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false }, f)
        end
    end
    -- BAR sign
    local sign = box("BarSign", X0 + 0.3, F + 12, 18, X0 + 0.6, F + 15, 28, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local g = surface(sign, Enum.NormalId.Right, 30)
    g.Brightness = 2.5
    text({ Text = "COCKTAILS", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 200, 235),
        TextStrokeColor3 = PINK, TextStrokeTransparency = 0 }, g)
    light("PointLight", sign, { Brightness = 1.5, Range = 14, Color = PINK })
    local props = {}
    for z = 14, 32, 3 do
        table.insert(props, { kit = "furniture", name = "stoolBar", pos = Vector3.new(bx + 1.6, F, z), facing = Vector3.new(-1, 0, 0) })
    end
    KenneyLoader.placeMany(props, f)
    for _, z in ipairs({ 16, 23, 30 }) do
        local lamp = box("BarPendant", bx - 1.2, MEZZ - 3, z - 0.4, bx - 0.4, MEZZ - 2.6, z + 0.4, Color3.fromRGB(230, 180, 120),
            Enum.Material.Neon, f, { CanCollide = false })
        light("PointLight", lamp, { Brightness = 1.2, Range = 10, Color = Color3.fromRGB(255, 190, 130) })
    end

    -- VIP mezzanine above the bar: x -44..-32, z 2..38, with glass railing
    local mx1 = X0 + 12
    box("Mezzanine", X0, MEZZ - 0.6, Z0 + 2, mx1, MEZZ, 38, Color3.fromRGB(30, 28, 36), Enum.Material.DiamondPlate, f)
    box("MezzRailGlass", mx1 - 0.15, MEZZ, Z0 + 5.5, mx1, MEZZ + 3, 38, Color3.fromRGB(170, 200, 255), Enum.Material.Glass, f, { Transparency = 0.6 })
    box("MezzRailTop", mx1 - 0.25, MEZZ + 3, Z0 + 5.5, mx1 + 0.1, MEZZ + 3.25, 38, STEEL, Enum.Material.Metal, f)
    box("MezzRailGlassS", X0, MEZZ, 37.85, mx1, MEZZ + 3, 38, Color3.fromRGB(170, 200, 255), Enum.Material.Glass, f, { Transparency = 0.6 })
    neon("MezzGlow", mx1 - 0.3, MEZZ - 0.7, Z0 + 2, mx1, MEZZ - 0.55, 38, CYAN, f)
    -- stairs along the north wall, from the stage's west side up to the mezzanine
    -- stairs along the north wall: from the floor at x -16 climbing WEST to the
    -- mezzanine edge at x -32 (22 steps of 0.5 up, ~0.73 across)
    local steps = 22
    local run = (-16) - mx1          -- 16 studs
    for i = 1, steps do
        local xa = -16 - (i - 1) * run / steps
        local xb = xa - run / steps
        local y = F + i * (MEZZ - F) / steps
        box("Step", xb, F, Z0 + 1, xa, y, Z0 + 5, Color3.fromRGB(34, 32, 40), Enum.Material.DiamondPlate, f)
    end
    KenneyLoader.placeMany({
        { kit = "furniture", name = "loungeDesignSofa", pos = Vector3.new(X0 + 3, MEZZ, 14), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "loungeDesignSofa", pos = Vector3.new(X0 + 3, MEZZ, 26), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "tableCoffeeGlass", pos = Vector3.new(X0 + 7, MEZZ, 14), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "tableCoffeeGlass", pos = Vector3.new(X0 + 7, MEZZ, 26), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(X0 + 2, MEZZ, 36), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(X0 + 2, MEZZ, 6), facing = Vector3.new(1, 0, 0) },
    }, f)
    local vip = box("VIPSign", X0 + 0.3, MEZZ + 4, 18, X0 + 0.6, MEZZ + 6.5, 24, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local vg = surface(vip, Enum.NormalId.Right, 30)
    vg.Brightness = 2.5
    text({ Text = "VIP", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display,
        TextScaled = true, TextColor3 = Color3.fromRGB(255, 235, 180), TextStrokeColor3 = Color3.fromRGB(255, 170, 60), TextStrokeTransparency = 0 }, vg)
end

-- ──────────────────────────────────────────────
-- 🗺 HOLO TABLE + JOB SCREEN
-- ──────────────────────────────────────────────
local function drawTV(bg, refs)
    UITheme.padding(bg, 28, 22)
    local left = frame({ Size = UDim2.fromScale(0.52, 0.72), BackgroundTransparency = 1 }, bg)
    text({ Text = "NEXT JOB", Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.gold, FontFace = UITheme.F.bold, TextSize = 22 }, left)
    local jobName = text({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 70),
        TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, left)
    local jobTag = text({ Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 26),
        TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 24 }, left)
    local statCells = {}
    for i, s in ipairs({ "DIFFICULTY", "GUARDS", "TAKE" }) do
        local cell = frame({ Size = UDim2.new(0.31, 0, 0, 74), Position = UDim2.new((i - 1) * 0.345, 0, 0, 150),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, left)
        UITheme.corner(cell, 10)
        text({ Text = s, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 18), TextColor3 = T.muted,
            FontFace = UITheme.F.bold, TextSize = 15 }, cell)
        statCells[i] = text({ Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 34),
            TextColor3 = (i == 3) and T.money or T.text, FontFace = UITheme.F.display, TextScaled = true }, cell)
    end
    local right = frame({ Size = UDim2.fromScale(0.42, 0.72), Position = UDim2.fromScale(0.58, 0),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.95 }, bg)
    UITheme.corner(right, 12)
    UITheme.padding(right, 16, 12)
    text({ Text = "TOP EARNERS", Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.gold, FontFace = UITheme.F.bold, TextSize = 22 }, right)
    local rows = {}
    for r = 1, 5 do
        local y = 34 + (r - 1) * 44
        local rank = text({ Text = tostring(r), Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(30, 36),
            TextColor3 = (r == 1) and T.gold or T.faint, FontFace = UITheme.F.display, TextSize = 28 }, right)
        local name = text({ Text = "—", Position = UDim2.fromOffset(36, y), Size = UDim2.new(0.6, -36, 0, 36),
            TextColor3 = T.text, FontFace = UITheme.F.bold, TextSize = 26, TextTruncate = Enum.TextTruncate.AtEnd }, right)
        local cash = text({ Position = UDim2.new(0.6, 0, 0, y), Size = UDim2.new(0.4, 0, 0, 36),
            TextColor3 = T.money, FontFace = UITheme.F.display, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Right }, right)
        rows[r] = { rank = rank, name = name, cash = cash }
    end
    local crewRow = frame({ Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.78), BackgroundTransparency = 1 }, bg)
    local crew = {}
    for i, role in ipairs(Constants.ROLES) do
        local chip = frame({ Size = UDim2.new(0.235, 0, 1, 0), Position = UDim2.fromScale((i - 1) * 0.255, 0),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.94 }, crewRow)
        UITheme.corner(chip, 10)
        frame({ Size = UDim2.new(0, 6, 1, -20), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = UITheme.rgb(role.color) }, chip)
        text({ Text = string.upper(role.id), Position = UDim2.fromOffset(26, 8), Size = UDim2.new(1, -34, 0.4, 0),
            TextColor3 = UITheme.rgb(role.color), FontFace = UITheme.F.bold, TextScaled = true }, chip)
        crew[role.id] = text({ Text = "open", Position = UDim2.new(0, 26, 0.45, 0), Size = UDim2.new(1, -34, 0.45, 0),
            TextColor3 = T.muted, FontFace = UITheme.F.bold, TextScaled = true, TextTruncate = Enum.TextTruncate.AtEnd }, chip)
    end
    refs.tv = { rows = rows, crew = crew, jobName = jobName, jobTag = jobTag, stats = statCells }
end

function ClubBuilder:_holoTable(f, refs)
    local c = W.HUB_TABLE
    local top = F + 3.4
    part({ Name = "HoloBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.1, 8, 8),
        CFrame = CFrame.new(c.x, F + 1.55, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Color3.fromRGB(20, 20, 26), Material = Enum.Material.Metal }, f)
    local ring = part({ Name = "HoloRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 12.4, 12.4),
        CFrame = CFrame.new(c.x, top - 0.15, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = Color3.fromRGB(14, 14, 18), Material = Enum.Material.Metal }, f)
    part({ Name = "HoloRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 12.7, 12.7),
        CFrame = CFrame.new(c.x, top - 0.25, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = CYAN, Material = Enum.Material.Neon, CanCollide = false }, f)
    -- the blueprint, drawn in glowing cyan (SafehouseBuilder:showJob fills it in)
    local sheet = box("HoloSheet", c.x - 4.6, top, c.z - 3.3, c.x + 4.6, top + 0.04, c.z + 3.3,
        Color3.fromRGB(6, 20, 30), Enum.Material.Glass, f, { CanCollide = false })
    local g = surface(sheet, Enum.NormalId.Top, 60)
    g.Brightness = 2
    local PAPER, INK = Color3.fromRGB(6, 22, 34), Color3.fromRGB(90, 235, 255)
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = PAPER }, g)
    for i = 1, 15 do
        frame({ Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(i / 16, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.9 }, bg)
    end
    for i = 1, 11 do
        frame({ Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 12), BackgroundColor3 = INK, BackgroundTransparency = 0.9 }, bg)
    end
    local title = text({ Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 30), TextColor3 = INK,
        FontFace = UITheme.F.display, TextSize = 26 }, bg)
    local subT = text({ Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 18), TextColor3 = INK,
        TextTransparency = 0.3, FontFace = UITheme.F.bold, TextSize = 14 }, bg)
    local plan = frame({ Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.08, 0.28), BackgroundTransparency = 1 }, bg)
    local notes = frame({ Size = UDim2.fromScale(0.24, 0.62), Position = UDim2.fromScale(0.74, 0.28), BackgroundTransparency = 1 }, bg)
    refs.blueprint = { title = title, sub = subT, plan = plan, notes = notes, ink = INK, paper = PAPER }
    -- hologram column
    part({ Name = "Hologram", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 7, 7),
        CFrame = CFrame.new(c.x, top + 2.5, c.z) * CFrame.Angles(0, 0, math.rad(90)),
        Color = CYAN, Material = Enum.Material.ForceField, Transparency = 0.2, CanCollide = false, CanQuery = false }, f)
    light("PointLight", sheet, { Brightness = 2, Range = 16, Color = CYAN })

    refs.readyPart = ring
    -- (fix v1.2.2) the two prompts used to share one point AND the Boss's E prompt was
    -- a few studs away, so Roblox flipped between them every frame. Each prompt now
    -- sits on its own spot on the spawn side of the table, and the Boss uses F.
    local function spot(name, dx)
        local a = Instance.new("Attachment")
        a.Name = name
        a.Parent = ring   -- parent first: WorldPosition needs the part
        a.WorldPosition = Vector3.new(c.x + dx, top + 1.2, c.z + 5.4)
        return a
    end
    local r = prompt(spot("ReadySpot", 2.6), "ReadyUp", "I'm ready!", "Holo table", Enum.KeyCode.E, 0.3)
    r.MaxActivationDistance = 8
    -- (v2.0) the HEIST DOORS in the lobby are how you start now; a second "ready"
    -- button at the table would confuse a 7-year-old. The prompt + hook are kept
    -- (flip ClubBuilder.TABLE_READY_PROMPT to bring it back).
    r.Enabled = ClubBuilder.TABLE_READY_PROMPT == true
    r.Triggered:Connect(function(player) if ClubBuilder.onReadyUp then ClubBuilder.onReadyUp(player) end end)
    local n = prompt(spot("JobSpot", -2.6), "NextJob", "See another heist plan", "Holo table", Enum.KeyCode.R, 0.4)
    n.MaxActivationDistance = 8
    n.GamepadKeyCode = Enum.KeyCode.ButtonY
    n.Triggered:Connect(function(player) if ClubBuilder.onNextJob then ClubBuilder.onNextJob(player) end end)

    local stools = {}
    for i = 0, 5 do
        local a = math.rad(30 + i * 60)
        if i ~= 0 then   -- leave a gap on the east side (30°) for the Boss
            table.insert(stools, { kit = "furniture", name = "stoolBar",
                pos = Vector3.new(c.x + math.cos(a) * 7.6, F, c.z + math.sin(a) * 7.6),
                facing = Vector3.new(-math.cos(a), 0, -math.sin(a)) })
        end
    end
    KenneyLoader.placeMany(stools, f)

    -- job screen hanging north of the table, facing the spawn
    local sw, sh = 20, 11.25
    local sz = c.z - 9
    local tv = box("JobScreen", c.x - sw / 2, TOP - 5 - sh, sz - 0.2, c.x + sw / 2, TOP - 5, sz + 0.2,
        Color3.fromRGB(8, 9, 12), Enum.Material.Glass, f)
    box("JobScreenBezel", c.x - sw / 2 - 0.3, TOP - 5.3 - sh, sz - 0.3, c.x + sw / 2 + 0.3, TOP - 4.7, sz - 0.15,
        Color3.fromRGB(18, 18, 20), Enum.Material.Metal, f)
    for _, dx in ipairs({ -sw / 2 + 1, sw / 2 - 1 }) do
        box("ScreenCable", c.x + dx - 0.06, TOP - 4.7, sz - 0.06, c.x + dx + 0.06, TOP, sz + 0.06, STEEL, Enum.Material.Metal, f, { CanCollide = false })
    end
    local tg = surface(tv, Enum.NormalId.Back, 40)
    tg.Brightness = 1.3
    local tbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 18) }, tg)
    local tgr = Instance.new("UIGradient")
    tgr.Rotation = 35
    tgr.Color = ColorSequence.new(Color3.fromRGB(40, 30, 72), Color3.fromRGB(12, 14, 20))
    tgr.Parent = tbg
    drawTV(tbg, refs)
    light("SurfaceLight", tv, { Face = Enum.NormalId.Back, Brightness = 0.8, Range = 16, Angle = 90, Color = Color3.fromRGB(150, 170, 255) })
end

-- ──────────────────────────────────────────────
-- 🎭 CREW PADS (east wall)
-- ──────────────────────────────────────────────
function ClubBuilder:_crewPads(f, refs)
    refs.pads = {}
    for i, role in ipairs(Constants.ROLES) do
        local z = 12 + (i - 1) * 7
        local x = X1 - 7
        local col = UITheme.rgb(role.color)
        local rim = part({ Name = role.id .. "PadRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.24, 5.6, 5.6),
            Color = col, Material = Enum.Material.SmoothPlastic,
            CFrame = CFrame.new(x, F + 0.12, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        part({ Name = role.id .. "Pad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.8, 4.8),
            Color = Color3.fromRGB(30, 32, 38), Material = Enum.Material.DiamondPlate,
            CFrame = CFrame.new(x, F + 0.15, z) * CFrame.Angles(0, 0, math.rad(90)) }, f)
        local label = box(role.id .. "PadLabel", x - 0.8, F + 0.31, z - 2.1, x + 0.8, F + 0.32, z + 2.1,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        -- (fix v1.2.2) text read upside down from the room side; turn it to face you
        label.CFrame = label.CFrame * CFrame.Angles(0, math.pi, 0)
        local lg = surface(label, Enum.NormalId.Top, 40)
        text({ Text = string.upper(role.id), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = col }, lg)
        local pl = light("PointLight", rim, { Color = col, Brightness = 0.6, Range = 9 })
        local hitbox = box(role.id .. "PadTrigger", x - 2.4, F + 0.3, z - 2.4, x + 2.4, F + 5, z + 2.4,
            Color3.new(), Enum.Material.SmoothPlastic, f, { Transparency = 1, CanCollide = false })
        hitbox:SetAttribute("Role", role.id)

        local sign = box(role.id .. "Sign", X1 - 0.8, F + 4, z - 2.8, X1 - 0.6, F + 9, z + 2.8,
            Color3.fromRGB(16, 18, 24), Enum.Material.SmoothPlastic, f)
        local sg = surface(sign, Enum.NormalId.Left, 60)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, sg)
        frame({ Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = col }, bg)
        text({ Text = string.format("0%d", i), Position = UDim2.fromOffset(22, 26), Size = UDim2.fromOffset(80, 28),
            TextColor3 = T.faint, FontFace = UITheme.F.mono, TextSize = 24 }, bg)
        text({ Text = string.upper(role.id), Position = UDim2.fromOffset(20, 56), Size = UDim2.new(1, -40, 0, 70),
            TextColor3 = T.text, FontFace = UITheme.F.display, TextScaled = true }, bg)
        text({ Text = role.blurb, Position = UDim2.fromOffset(22, 130), Size = UDim2.new(1, -44, 0, 50),
            TextColor3 = T.muted, FontFace = UITheme.F.medium, TextSize = 26, TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top }, bg)
        local statusBar = frame({ Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0, 20, 1, -76), BackgroundColor3 = T.bgRaised }, bg)
        UITheme.corner(statusBar, 10)
        local status = text({ Text = "OPEN", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6),
            TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.muted, FontFace = UITheme.F.bold, TextScaled = true }, statusBar)
        local cap = Instance.new("UITextSizeConstraint")
        cap.MaxTextSize = 30
        cap.Parent = status
        refs.pads[role.id] = { hitbox = hitbox, rim = rim, light = pl, status = status, statusBar = statusBar, color = col }
    end
    local head = box("CrewSign", X1 - 0.8, F + 11, 12, X1 - 0.6, F + 13.5, 33, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local hg = surface(head, Enum.NormalId.Left, 30)
    hg.Brightness = 2.5
    text({ Text = "PICK YOUR ROLE", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(220, 250, 255),
        TextStrokeColor3 = CYAN, TextStrokeTransparency = 0 }, hg)
    light("PointLight", head, { Brightness = 1.2, Range = 14, Color = CYAN })
end

-- ──────────────────────────────────────────────
-- 😷 MASK WALL (west, south of the bar) → opens the shop
-- ──────────────────────────────────────────────
local ATTACH = {   -- where each accessory attachment sits on a 1.2-stud R15-ish head
    FaceFrontAttachment = CFrame.new(0, 0, -0.6),
    FaceCenterAttachment = CFrame.new(0, 0, 0),
    HatAttachment = CFrame.new(0, 0.6, 0),
    HairAttachment = CFrame.new(0, 0.6, 0),
}

function ClubBuilder:_maskWall(f)
    local wx = X0 + 0.3
    local board = box("MaskBoard", wx, F + 2, 40, wx + 0.3, F + 13, 58, Color3.fromRGB(20, 18, 26), Enum.Material.Fabric, f)
    local title = box("MaskSign", wx + 0.3, F + 13.5, 42, wx + 0.6, F + 16, 56, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local tg = surface(title, Enum.NormalId.Right, 30)
    tg.Brightness = 2.5
    text({ Text = "MASKS & GEAR", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 225, 245),
        TextStrokeColor3 = PINK, TextStrokeTransparency = 0 }, tg)
    light("PointLight", title, { Brightness = 1.2, Range = 14, Color = PINK })

    for i, m in ipairs(Constants.MASKS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local z = 43 + col * 4.2
        local y = F + 9.5 - row * 5
        -- little shelf + display head facing into the room (+X)
        box("MaskShelf", wx + 0.3, y - 1.2, z - 1.2, wx + 2.2, y - 1, z + 1.2, Color3.fromRGB(34, 32, 40), Enum.Material.Metal, f)
        local headPart = part({ Name = "DisplayHead", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2),
            CFrame = CFrame.lookAt(Vector3.new(wx + 1.3, y - 0.4, z), Vector3.new(wx + 10, y - 0.4, z)),
            Color = Color3.fromRGB(58, 56, 66), Material = Enum.Material.SmoothPlastic }, f)
        local plate = box("MaskPlate", wx + 0.3, y - 2.6, z - 1.4, wx + 0.4, y - 1.6, z + 1.4, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
        local pg = surface(plate, Enum.NormalId.Right, 40)
        text({ Text = string.upper(m.name), Size = UDim2.fromScale(1, 0.55), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.text }, pg)
        text({ Text = m.price == 0 and "FREE" or UITheme.money(m.price), Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
            TextColor3 = m.price == 0 and T.money or T.gold }, pg)
        local spot = box("MaskSpot", wx + 3.6, y + 1.8, z - 0.2, wx + 4, y + 2.1, z + 0.2, STEEL, Enum.Material.Metal, f, { CanCollide = false })
        light("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 50, Brightness = 2, Range = 6, Color = Color3.fromRGB(255, 230, 240) })
        -- load the real mask onto the head (async; skipped silently if it won't load)
        task.spawn(function()
            local ok, container = pcall(function() return InsertService:LoadAsset(m.assetId) end)
            local acc = ok and container and container:FindFirstChildWhichIsA("Accessory", true)
            local handle = acc and acc:FindFirstChild("Handle")
            if not handle then return end
            local att = handle:FindFirstChildWhichIsA("Attachment")
            local offset = att and ATTACH[att.Name] or CFrame.new(0, 0, -0.55)
            handle = handle:Clone()
            for _, d in ipairs(handle:GetDescendants()) do
                if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Weld") or d:IsA("WeldConstraint") then d:Destroy() end
            end
            handle.Anchored = true
            handle.CanCollide = false
            local a2 = att and handle:FindFirstChild(att.Name)
            handle.CFrame = headPart.CFrame * offset * (a2 and a2.CFrame:Inverse() or CFrame.new())
            handle.Name = "Mask_" .. m.id
            handle.Parent = f
        end)
    end

    -- shop counter in front of the wall
    local counter = box("ShopCounter", wx + 6, F, 44, wx + 8, F + 3.4, 54, WOOD, Enum.Material.WoodPlanks, f)
    box("ShopCounterTop", wx + 5.8, F + 3.4, 43.8, wx + 8.2, F + 3.7, 54.2, Color3.fromRGB(230, 225, 235), Enum.Material.Marble, f)
    neon("ShopCounterGlow", wx + 8.02, F + 0.3, 44, wx + 8.12, F + 0.45, 54, CYAN, f)
    local p = prompt(counter, "OpenShop", "Open shop", "Masks & gear", Enum.KeyCode.E, 0)
    p.MaxActivationDistance = 11
end

-- ──────────────────────────────────────────────
-- 🏆 TROPHY ROOM (south-east)
-- ──────────────────────────────────────────────
local function trophyVisual(i, cf, parent)
    local fo = Instance.new("Model")
    fo.Name = "Trophy" .. i
    fo.Parent = parent
    local gold = Color3.fromRGB(240, 190, 60)
    if i == 1 then
        part({ Name = "GoldBar", Size = Vector3.new(1.6, 0.6, 0.8), CFrame = cf * CFrame.new(0, 0.3, 0),
            Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 }, fo)
    elseif i == 2 then
        for k = 0, 5 do
            part({ Name = "Cash", Size = Vector3.new(1.2, 0.35, 0.6),
                CFrame = cf * CFrame.new((k % 2) * 0.65 - 0.3, 0.2 + math.floor(k / 2) * 0.36, 0),
                Color = Color3.fromRGB(90, 170, 90), Material = Enum.Material.Fabric }, fo)
        end
    elseif i == 3 then
        part({ Name = "Diamond", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(0, 0.9, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
            Color = Color3.fromRGB(150, 230, 255), Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.4 }, fo)
        local glow = part({ Name = "Core", Size = Vector3.new(0.35, 0.35, 0.35), CFrame = cf * CFrame.new(0, 0.9, 0),
            Color = CYAN, Material = Enum.Material.Neon, CanCollide = false }, fo)
        light("PointLight", glow, { Brightness = 1.5, Range = 6, Color = CYAN })
    elseif i == 4 then
        part({ Name = "Frame", Size = Vector3.new(0.2, 2.2, 2.8), CFrame = cf * CFrame.new(0, 1.3, 0),
            Color = gold, Material = Enum.Material.Metal }, fo)
        local canvas = part({ Name = "Canvas", Size = Vector3.new(0.1, 1.8, 2.4), CFrame = cf * CFrame.new(-0.12, 1.3, 0),
            Color = Color3.fromRGB(40, 60, 110), Material = Enum.Material.Fabric }, fo)
        local g = surface(canvas, Enum.NormalId.Left, 60)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(30, 50, 100) }, g)
        frame({ Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.2), BackgroundColor3 = Color3.fromRGB(240, 180, 60), Rotation = 12 }, bg)
        frame({ Size = UDim2.fromScale(0.3, 0.3), Position = UDim2.fromScale(0.55, 0.5), BackgroundColor3 = Color3.fromRGB(230, 80, 120) }, bg)
    else
        task.spawn(function()
            local bear = KenneyLoader.place("furniture", "bear", cf.Position, Vector3.new(-1, 0, 0), { parent = fo, scale = 1.6 })
            if bear then
                for _, d in ipairs(bear:GetDescendants()) do
                    if d:IsA("BasePart") then
                        d:SetAttribute("BaseT", 0)
                        d.Color = gold
                        d.Material = Enum.Material.Metal
                        d.Reflectance = 0.25
                        if d:IsA("MeshPart") then d.TextureID = "" end
                    end
                end
                bear:SetAttribute("Hidden", fo:GetAttribute("Hidden"))
                for _, d in ipairs(bear:GetDescendants()) do
                    if d:IsA("BasePart") and fo:GetAttribute("Hidden") then d.Transparency = 1 end
                end
            end
        end)
    end
    return fo
end

local function setModelVisible(m, visible)
    m:SetAttribute("Hidden", not visible)
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then
            if d:GetAttribute("BaseT") == nil then d:SetAttribute("BaseT", d.Transparency) end
            d.Transparency = visible and d:GetAttribute("BaseT") or 1
        elseif d:IsA("Light") or d:IsA("SurfaceGui") then
            d.Enabled = visible
        end
    end
end

function ClubBuilder:_trophyRoom(f, refs)
    local rx0, rz0 = 26, 46
    -- partition walls with an opening facing the room
    box("TrophyWallN", rx0, F, rz0 - 0.4, X1, F + 9, rz0, WALL, Enum.Material.Concrete, f)
    box("TrophyWallW", rx0 - 0.4, F, rz0, rx0, F + 9, rz0 + 6, WALL, Enum.Material.Concrete, f)
    box("TrophyFloor", rx0, F, rz0, X1, F + 0.06, Z1, Color3.fromRGB(60, 20, 30), Enum.Material.Fabric, f)
    local sign = box("TrophySign", rx0 + 2, F + 9.2, rz0 - 0.5, X1 - 2, F + 11.6, rz0 - 0.3, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 30)
    sg.Brightness = 2.5
    text({ Text = "TROPHY ROOM", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 240, 200),
        TextStrokeColor3 = Color3.fromRGB(255, 170, 60), TextStrokeTransparency = 0 }, sg)
    light("PointLight", sign, { Brightness = 1.2, Range = 12, Color = Color3.fromRGB(255, 190, 90) })

    refs.trophies = {}
    for i, tr in ipairs(Constants.TROPHIES) do
        local z = rz0 + 3 + (i - 1) * 3.4
        local x = X1 - 3
        box("Pedestal", x - 1.2, F, z - 1.2, x + 1.2, F + 3, z + 1.2, Color3.fromRGB(30, 28, 34), Enum.Material.Marble, f)
        box("CaseGlass", x - 1.15, F + 3, z - 1.15, x + 1.15, F + 5.8, z + 1.15, Color3.fromRGB(200, 220, 255), Enum.Material.Glass, f,
            { Transparency = 0.75, CanCollide = false })
        local plate = box("TrophyPlate", x - 1.25, F + 1.2, z - 1.1, x - 1.2, F + 2.6, z + 1.1, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, f)
        local pg = surface(plate, Enum.NormalId.Left, 50)
        local name = text({ Size = UDim2.fromScale(1, 0.55), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = T.gold }, pg)
        local info = text({ Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.muted }, pg)
        local spot = box("TrophySpot", x - 0.2, F + 8.6, z - 0.2, x + 0.2, F + 8.9, z + 0.2, STEEL, Enum.Material.Metal, f, { CanCollide = false })
        local sl = light("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 40, Brightness = 3, Range = 9, Color = Color3.fromRGB(255, 225, 170) })
        local vis = trophyVisual(i, CFrame.new(x, F + 3, z), f)
        refs.trophies[i] = { at = tr.at, name = tr.name, blurb = tr.blurb, visual = vis, label = name, info = info, light = sl }
    end
    refs.setTrophies = function(best)
        for _, t in ipairs(refs.trophies) do
            local unlocked = best >= t.at
            setModelVisible(t.visual, unlocked)
            t.light.Enabled = unlocked
            t.label.Text = unlocked and t.name or "LOCKED"
            t.info.Text = unlocked and t.blurb or string.format("%d heist%s", t.at, t.at == 1 and "" or "s")
        end
    end
    refs.setTrophies(0)
    -- v3.0: the Boss's target trophies along the north wall of the same room
    local ok, err = pcall(function() ClubBuilder:_targetWall(f, refs) end)
    if not ok then warn("[ClubBuilder] target wall failed: " .. tostring(err)) end
end

-- ──────────────────────────────────────────────
-- 🎯 BOSS TARGETS WALL (v3.0, LOOT-CORE) — inside the trophy room, along its
-- north partition (x 27..38.6, z 46..49.2). One plinth per job target
-- (Constants.LOOT_V3.TARGETS, easy → hard). Each plinth Model is tagged
-- "TargetTrophy" with attribute TargetKind; TargetService sets its attribute
-- Owned = true while ANYONE in the server owns that trophy → the model shows,
-- the spotlight + glow come on and the plate reads its name. Otherwise a dark
-- "???" plinth. refs.setTargetTrophies({ [kind] = true }) does the same by hand.
-- ──────────────────────────────────────────────
local function targetModel(kind, cf, parent)
    local m = Instance.new("Model")
    m.Name = "Target_" .. kind
    m.Parent = parent
    local gold = Color3.fromRGB(240, 190, 60)
    local function p(props) return part(props, m) end
    if kind == "GoldFlamingo" then
        p({ Name = "Leg", Size = Vector3.new(0.15, 1.3, 0.15), CFrame = cf * CFrame.new(0, 0.65, 0), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        p({ Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 0.8, 0.8), CFrame = cf * CFrame.new(0, 1.55, 0), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        p({ Name = "Neck", Size = Vector3.new(0.14, 0.9, 0.14), CFrame = cf * CFrame.new(0.4, 2.05, 0) * CFrame.Angles(0, 0, math.rad(-15)), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        p({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), CFrame = cf * CFrame.new(0.5, 2.5, 0), Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        p({ Name = "Beak", Size = Vector3.new(0.3, 0.1, 0.1), CFrame = cf * CFrame.new(0.72, 2.45, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.SmoothPlastic })
    elseif kind == "PinkDiamond" then
        p({ Name = "Stand", Size = Vector3.new(0.5, 0.5, 0.5), CFrame = cf * CFrame.new(0, 0.25, 0), Color = Color3.fromRGB(40, 36, 44), Material = Enum.Material.Marble })
        p({ Name = "Gem", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
            Color = Color3.fromRGB(255, 120, 200), Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.4 })
    elseif kind == "GoldenTicket" then
        local t = p({ Name = "Ticket", Size = Vector3.new(1.6, 0.9, 0.06), CFrame = cf * CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(-15), 0, 0),
            Color = Color3.fromRGB(252, 211, 77), Material = Enum.Material.Foil })
        local g = surface(t, Enum.NormalId.Back, 50)
        text({ Text = "GOLDEN TICKET", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(120, 70, 10) }, g)
    elseif kind == "CrownJewel" then
        p({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 1.2, 1.2), CFrame = cf * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
            Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        for k = 0, 4 do
            local a = math.rad(k * 72)
            p({ Name = "Point", Size = Vector3.new(0.18, 0.5, 0.18), CFrame = cf * CFrame.new(math.cos(a) * 0.5, 1.0, math.sin(a) * 0.5),
                Color = gold, Material = Enum.Material.Metal, Reflectance = 0.3 })
        end
        p({ Name = "Jewel", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = cf * CFrame.new(0, 1.05, 0),
            Color = Color3.fromRGB(192, 132, 252), Material = Enum.Material.Glass, Reflectance = 0.3 })
    else
        p({ Name = "Mystery", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(0, 0.9, 0), Color = gold, Material = Enum.Material.Metal })
    end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") then d.CanCollide = false end
    end
    return m
end

function ClubBuilder:_targetWall(f, refs)
    local V3 = Constants.LOOT_V3 or {}
    local targets = V3.TARGETS or {}
    local list = {}
    for _, job in ipairs(Constants.JOBS) do
        local t = targets[job.id]
        if t then table.insert(list, { kind = t.kind, name = t.name, job = job.name }) end
    end
    if #list == 0 then return end
    -- sign on the room side of the north partition (the wall's south face is z 46)
    local sign = box("TargetSign", 27, F + 6.3, 46, 38.6, F + 8.2, 46.2, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Back, 30)
    sg.Brightness = 2.2
    text({ Text = "BOSS TARGETS", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 225, 150),
        TextStrokeColor3 = Color3.fromRGB(200, 120, 30), TextStrokeTransparency = 0.2 }, sg)

    refs.targetTrophies = {}
    local x0, step = 28.6, 3.1
    local z = 48.1
    for i, t in ipairs(list) do
        local x = x0 + (i - 1) * step
        local holder = Instance.new("Model")
        holder.Name = "TargetTrophy_" .. t.kind
        holder:SetAttribute("TargetKind", t.kind)
        holder:SetAttribute("Owned", false)
        holder.Parent = f
        box("Plinth", x - 1.1, F, z - 1.1, x + 1.1, F + 2.6, z + 1.1, Color3.fromRGB(34, 30, 38), Enum.Material.Marble, holder)
        box("PlinthCap", x - 1.2, F + 2.6, z - 1.2, x + 1.2, F + 2.75, z + 1.2, GOLD, Enum.Material.Metal, holder)
        local glow = box("PlinthGlow", x - 1.12, F + 0.3, z + 1.1, x + 1.12, F + 0.42, z + 1.14, T.gold, Enum.Material.Neon, holder, { CanCollide = false })
        box("CaseGlass", x - 1.05, F + 2.75, z - 1.05, x + 1.05, F + 5.6, z + 1.05, Color3.fromRGB(200, 220, 255), Enum.Material.Glass, holder,
            { Transparency = 0.8, CanCollide = false })
        -- name plate on the plinth's front (facing into the room, +Z)
        local plate = box("Plate", x - 0.95, F + 1.1, z + 1.1, x + 0.95, F + 2.3, z + 1.16, Color3.fromRGB(12, 12, 16), Enum.Material.Metal, holder)
        local pg = surface(plate, Enum.NormalId.Back, 60)
        local name = text({ Size = UDim2.fromScale(1, 0.58), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.display, TextScaled = true, TextColor3 = T.gold, Text = "???" }, pg)
        local sub_ = text({ Position = UDim2.fromScale(0, 0.58), Size = UDim2.fromScale(1, 0.42), TextXAlignment = Enum.TextXAlignment.Center,
            FontFace = UITheme.F.bold, TextScaled = true, TextColor3 = T.muted, Text = t.job }, pg)
        local spot = box("TargetSpot", x - 0.2, F + 8.6, z - 0.2, x + 0.2, F + 8.9, z + 0.2, STEEL, Enum.Material.Metal, holder, { CanCollide = false })
        local sl = light("SpotLight", spot, { Face = Enum.NormalId.Bottom, Angle = 40, Brightness = 3, Range = 9, Color = Color3.fromRGB(255, 225, 170) })
        local vis = targetModel(t.kind, CFrame.new(x, F + 2.75, z), holder)
        local entry = { kind = t.kind, name = t.name, holder = holder, visual = vis, label = name, sub = sub_, light = sl, glow = glow }
        refs.targetTrophies[t.kind] = entry
        local function apply()
            local owned = holder:GetAttribute("Owned") == true
            setModelVisible(vis, owned)
            sl.Enabled = owned
            glow.Transparency = owned and 0 or 0.85
            name.Text = owned and string.upper(t.name) or "???"
            name.TextColor3 = owned and T.gold or T.faint
            sub_.Text = owned and t.job or ("steal it at " .. t.job)
        end
        holder:GetAttributeChangedSignal("Owned"):Connect(apply)
        apply()
        CollectionService:AddTag(holder, "TargetTrophy")
    end
    refs.setTargetTrophies = function(owned)
        owned = type(owned) == "table" and owned or {}
        for kind, e in pairs(refs.targetTrophies) do e.holder:SetAttribute("Owned", owned[kind] == true) end
    end
end

-- ──────────────────────────────────────────────
-- 🚗 GARAGE BAY + RAMP (south-west)
-- ──────────────────────────────────────────────
function ClubBuilder:_garageBay(f, refs)
    local bx0, bx1 = -26, -8                 -- south-centre-west, clear of the mask wall
    local cx = (bx0 + bx1) / 2               -- -17
    box("BayFloor", bx0, F, 44, bx1, F + 0.05, Z1, Color3.fromRGB(60, 60, 64), Enum.Material.Concrete, f)
    for _, x in ipairs({ bx0 + 1, bx1 - 1 }) do
        box("BayLine", x - 0.15, F + 0.05, 44, x + 0.15, F + 0.08, Z1 - 16, Color3.fromRGB(212, 168, 44), Enum.Material.SmoothPlastic, f, { CanCollide = false })
    end
    box("BayWallE", bx1, F, 44, bx1 + 0.5, F + 8, Z1 - 17, WALL, Enum.Material.Concrete, f)
    -- the ramp: from the bay floor (z 48) up to a roll-up door high in the south wall
    local a = Vector3.new(cx, F, Z1 - 16)
    local b = Vector3.new(cx, F + 10, Z1 - 0.5)
    local mid = (a + b) / 2
    local len = (b - a).Magnitude
    part({ Name = "Ramp", Size = Vector3.new(14, 0.8, len), CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -0.4, 0),
        Color = Color3.fromRGB(54, 54, 58), Material = Enum.Material.DiamondPlate }, f)
    for _, sx in ipairs({ -7.2, 7.2 }) do
        part({ Name = "RampRail", Size = Vector3.new(0.3, 1, len), CFrame = CFrame.lookAt(mid + Vector3.new(sx, 0.5, 0), b + Vector3.new(sx, 0.5, 0)),
            Color = Color3.fromRGB(212, 168, 44), Material = Enum.Material.Metal }, f)
    end
    -- roll-up door where the ramp meets the wall (slats)
    for i = 0, 4 do
        box("BayDoorSlat", cx - 8, F + 10 + i * 2, Z1 - 0.6, cx + 8, F + 12 + i * 2, Z1 - 0.2,
            (i % 2 == 0) and Color3.fromRGB(96, 102, 110) or Color3.fromRGB(84, 90, 98), Enum.Material.Metal, f)
    end
    local warn = box("BaySign", cx - 6, F + 20.5, Z1 - 0.6, cx + 6, F + 22.5, Z1 - 0.4, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local wg = surface(warn, Enum.NormalId.Front, 30)
    wg.Brightness = 2
    text({ Text = "GETAWAY BAY", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 220, 120) }, wg)
    for _, x in ipairs({ bx0 + 3, bx1 - 3 }) do
        local l = box("BayLamp", x - 0.5, TOP - 2, 50 - 0.5, x + 0.5, TOP - 1.5, 50 + 0.5, STEEL, Enum.Material.Metal, f)
        light("SpotLight", l, { Face = Enum.NormalId.Bottom, Angle = 90, Brightness = 2.5, Range = 30, Color = Color3.fromRGB(235, 240, 255) })
    end
    KenneyLoader.placeMany({
        { kit = "factory", name = "cone", pos = Vector3.new(bx0 + 2, F, 46), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "cone", pos = Vector3.new(bx1 - 2, F, 46), facing = Vector3.new(0, 0, 1) },
        { kit = "factory", name = "box-large", pos = Vector3.new(bx0 + 2.5, F, Z1 - 3), facing = Vector3.new(1, 0, 0) },
    }, f)
    -- where the launch cut-scene parks a copy of the getaway car, and where it drives to
    refs.bay = {
        start = CFrame.lookAt(Vector3.new(cx, F, Z1 - 20), Vector3.new(cx, F, Z1)),
        rampFoot = CFrame.lookAt(Vector3.new(cx, F, Z1 - 16), b),
        rampTop = CFrame.lookAt(b - (b - a).Unit * 3, b),
        camFrom = Vector3.new(cx + 16, F + 7, 40),
        camTo = Vector3.new(cx, F + 3, Z1 - 12),
    }
end

-- ──────────────────────────────────────────────
-- 🛗 FREIGHT ELEVATOR (up to the auto shop)
-- ──────────────────────────────────────────────
function ClubBuilder:_elevator(f, refs)
    local e = W.HUB_ELEVATOR
    local x0, x1, z0, z1 = e.x - 4, e.x + 4, Z1 - 7, Z1
    box("LiftFloor", x0, F, z0, x1, F + 0.3, z1, Color3.fromRGB(70, 72, 78), Enum.Material.DiamondPlate, f)
    for _, p in ipairs({ { x0, z0 }, { x1, z0 } }) do
        box("LiftPost", p[1] - 0.25, F, p[2] - 0.25, p[1] + 0.25, F + 10, p[2] + 0.25, Color3.fromRGB(212, 168, 44), Enum.Material.Metal, f)
    end
    box("LiftTop", x0 - 0.25, F + 10, z0 - 0.25, x1 + 0.25, F + 10.5, z1, Color3.fromRGB(212, 168, 44), Enum.Material.Metal, f)
    box("LiftSideW", x0 - 0.1, F + 0.3, z0, x0 + 0.1, F + 10, z1, Color3.fromRGB(80, 80, 88), Enum.Material.DiamondPlate, f, { Transparency = 0.3 })
    box("LiftSideE", x1 - 0.1, F + 0.3, z0, x1 + 0.1, F + 10, z1, Color3.fromRGB(80, 80, 88), Enum.Material.DiamondPlate, f, { Transparency = 0.3 })
    local panel = box("LiftPanel", x1 - 0.6, F + 3.5, z0 + 0.4, x1 - 0.2, F + 5.5, z0 + 1.4, Color3.fromRGB(20, 20, 24), Enum.Material.Metal, f)
    neon("LiftButton", x1 - 0.7, F + 4.3, z0 + 0.7, x1 - 0.6, F + 4.7, z0 + 1.1, Color3.fromRGB(60, 240, 140), f)
    local sign = box("LiftSign", x0 + 0.5, F + 10.6, z0 - 0.3, x1 - 0.5, F + 12.2, z0 - 0.1, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, f)
    local sg = surface(sign, Enum.NormalId.Front, 30)
    sg.Brightness = 2
    text({ Text = "▲ STREET", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(120, 255, 180) }, sg)
    light("PointLight", panel, { Brightness = 1, Range = 10, Color = Color3.fromRGB(120, 255, 180) })
    local p = prompt(panel, "ElevatorUp", "Up to the street", "Freight lift", Enum.KeyCode.E, 0.5)
    p.MaxActivationDistance = 8
    p.Triggered:Connect(function(player) if ClubBuilder.onElevator then ClubBuilder.onElevator(player, "up") end end)
end

-- ══════════════════════════════════════════════════════════════════════
-- v2.0 "BIGGER": ENTRANCE LOBBY + HEIST HALL (annex south of the club)
-- ══════════════════════════════════════════════════════════════════════
local UP = Vector3.new(0, 1, 0)

local function flat(v)
    local d = Vector3.new(v.X, 0, v.Z)
    return d.Magnitude > 1e-3 and d.Unit or Vector3.new(0, 0, -1)
end

-- Words painted on the floor, readable by someone looking along `readDir`.
-- A Top-face SurfaceGui's "up" runs along the part's local -X and its width
-- along local Z (that's what the v1.2.2 role-pad fix established), so local -X
-- is pointed along the reading direction.
local function floorText(parent, name, pos, readDir, w, h, str, color)
    local d = flat(readDir)
    local p = part({ Name = name, Size = Vector3.new(h, 0.05, w), CFrame = CFrame.fromMatrix(pos, -d, UP),
        Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false }, parent)
    local g = surface(p, Enum.NormalId.Top, 40)
    g.Brightness = 1.6
    text({ Text = str, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = color }, g)
    return p
end

-- One painted ">" chevron on the floor, tip at `tip`, pointing along `dir`.
local function chevron(parent, tip, dir, color, len, wid)
    local d = flat(dir)
    local right = d:Cross(UP)
    for _, s in ipairs({ -1, 1 }) do
        local v = (-d + right * s).Unit
        local c = tip + v * (len / 2)
        part({ Name = "ArrowPaint", Size = Vector3.new(wid, 0.04, len), CFrame = CFrame.lookAt(c, c + v),
            Color = color, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false,
            CanTouch = false }, parent)
    end
end

-- A floor arrow: WORDS, then three chevrons pointing along `dir`.
local function floorArrow(parent, at, dir, readDir, label, color, textW)
    local d = flat(dir)
    textW = textW or 7
    local base = Vector3.new(at.X, F + 0.09, at.Z)
    floorText(parent, "FloorWord", base, readDir, textW, 1.6, label, color)
    local start = (math.abs(flat(readDir):Dot(d)) > 0.7) and 1.2 or (textW / 2 + 0.6)
    for k = 0, 2 do
        chevron(parent, base + d * (start + 1.3 + k * 1.5), d, color, 1.7, 0.4)
    end
end

-- Hanging sign board with a SurfaceGui on one face
local function signBoard(parent, name, x0, y0, z0, x1, y1, z1, face, pps)
    local b = box(name, x0, y0, z0, x1, y1, z1, Color3.fromRGB(10, 10, 14), Enum.Material.Metal, parent)
    local g = surface(b, face, pps or 30)
    g.Brightness = 2.2
    return b, g
end

local function chandelier(parent, x, z, y)
    box("ChandelierRod", x - 0.08, y + 0.4, z - 0.08, x + 0.08, LTOP, z + 0.08, GOLD, Enum.Material.Metal, parent, { CanCollide = false })
    part({ Name = "ChandelierRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5.2, 5.2),
        CFrame = CFrame.new(x, y + 0.4, z) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD,
        Material = Enum.Material.Metal, CanCollide = false }, parent)
    for k = 0, 7 do
        local a = k * math.pi / 4
        part({ Name = "ChandelierBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
            Position = Vector3.new(x + math.cos(a) * 2.3, y + 0.85, z + math.sin(a) * 2.3),
            Color = Color3.fromRGB(255, 226, 176), Material = Enum.Material.Neon, CanCollide = false }, parent)
    end
    local core = box("ChandelierCore", x - 0.45, y - 0.5, z - 0.45, x + 0.45, y + 0.3, z + 0.45, GOLD, Enum.Material.Metal, parent, { CanCollide = false })
    light("PointLight", core, { Brightness = 1.3, Range = 26, Color = Color3.fromRGB(255, 214, 170), Shadows = true })
end

-- Job info for a door: Constants.JOBS first (the core agent owns it), with a
-- fallback so the four doors always build even before mart/bank exist there.
local JOB_FALLBACK = {
    mart    = { id = "mart",    name = "SUNNY'S MART",  difficulty = 1, unlockLevel = 1 },
    villa   = { id = "villa",   name = "VILLA ROSA",    difficulty = 2, unlockLevel = 1 },
    jewelry = { id = "jewelry", name = "DIAMOND DOLLS", difficulty = 3, unlockLevel = 1 },
    bank    = { id = "bank",    name = "OCEAN BANK",    difficulty = 4, unlockLevel = 1 },
}
local JOB_COLOR = {
    mart = Color3.fromRGB(74, 222, 128), villa = PINK, jewelry = CYAN, bank = Color3.fromRGB(251, 191, 36),
}
local DIFF_WORD = { "EASY", "MEDIUM", "HARD", "VERY HARD" }

local function jobCfg(id)
    for _, j in ipairs(Constants.JOBS or {}) do
        if j.id == id then return j end
    end
    return JOB_FALLBACK[id] or { id = id, name = string.upper(tostring(id)), difficulty = 1, unlockLevel = 1 }
end

-- HeistBuilder's v1.1.1 "switch off every other SpawnLocation" pass predates
-- these pads: it would disable five of them and drag one to SPAWN_POSITION.
-- Until it's pointed at refs.spawnPads, each pad quietly puts itself back.
local function guardSpawn(s)
    local cf, size = s.CFrame, s.Size
    local busy = false
    local function restore()
        if busy then return end
        busy = true
        task.defer(function()
            if s.Parent then
                s.Enabled = true
                s.Neutral = true
                s.Duration = 5
                s.Size = size
                s.CFrame = cf
                s.Transparency = 1
                s.CanCollide = false
            end
            busy = false
        end)
    end
    s:GetPropertyChangedSignal("Enabled"):Connect(function() if not s.Enabled then restore() end end)
    s:GetPropertyChangedSignal("CFrame"):Connect(function() if s.CFrame ~= cf then restore() end end)
end

-- ──────────────────────────────────────────────
-- 🏛 LOBBY SHELL (floor, walls, ceiling, arch, lights)
-- ──────────────────────────────────────────────
function ClubBuilder:_lobbyShell(f)
    local plaster = Color3.fromRGB(62, 32, 40)
    box("LobbyFloor", LX0, F - 1, LZ0, 16, F, LZ1, Color3.fromRGB(46, 38, 36), Enum.Material.Marble, f, { Reflectance = 0.08 })
    box("HallFloor", 16, F - 1, LZ0, LX1, F, LZ1, Color3.fromRGB(34, 34, 40), Enum.Material.Slate, f)
    box("LobbyCeiling", LX0 - 1, LTOP, LZ0, 51, LTOP + 1, LZ1 + 1, Color3.fromRGB(24, 22, 28), Enum.Material.Metal, f)
    box("LobbyWallW", LX0 - 1, F, LZ0, LX0, LTOP, LZ1, plaster, Enum.Material.Plaster, f)
    box("LobbyWallS", LX0 - 1, F, LZ1, 51, LTOP, LZ1 + 1, plaster, Enum.Material.Plaster, f)
    -- the club's south wall is this room's north wall: plaster it on this side
    box("LobbyCladNW", LX0, F, LZ0, -ARCH_HW - 0.8, LTOP, LZ0 + 0.2, plaster, Enum.Material.Plaster, f)
    box("LobbyCladNE", ARCH_HW + 0.8, F, LZ0, LX1, LTOP, LZ0 + 0.2, plaster, Enum.Material.Plaster, f)
    box("LobbyCladArch", -ARCH_HW - 0.8, F + ARCH_H + 0.8, LZ0, ARCH_HW + 0.8, LTOP, LZ0 + 0.2, plaster, Enum.Material.Plaster, f)
    -- wood wainscot + a gold rail around the lobby part (west of the hall)
    -- (the west wall skips z 71.3..86.7: that's the leaderboard spot — see _lobbyWest)
    for _, zz in ipairs({ { LZ0 + 0.2, 71.3 }, { 86.7, LZ1 } }) do
        box("WainscotW", LX0, F, zz[1], LX0 + 0.3, F + 4, zz[2], WOOD, Enum.Material.WoodPlanks, f)
        box("RailW", LX0 + 0.3, F + 4, zz[1], LX0 + 0.45, F + 4.25, math.min(zz[2], LZ1 - 0.3), GOLD, Enum.Material.Metal, f)
    end
    box("WainscotS", LX0, F, LZ1 - 0.3, 16, F + 4, LZ1, WOOD, Enum.Material.WoodPlanks, f)
    box("WainscotNW", LX0, F, LZ0 + 0.2, -ARCH_HW - 0.8, F + 4, LZ0 + 0.5, WOOD, Enum.Material.WoodPlanks, f)
    box("RailS", LX0, F + 4, LZ1 - 0.45, 16, F + 4.25, LZ1 - 0.3, GOLD, Enum.Material.Metal, f)

    -- the arch: floor under the wall thickness, then a gold frame on both faces
    box("ArchSill", -ARCH_HW, F - 1, Z1, ARCH_HW, F, LZ0, Color3.fromRGB(46, 38, 36), Enum.Material.Marble, f)
    for _, zz in ipairs({ { Z1 - 0.4, Z1 }, { LZ0 + 0.2, LZ0 + 0.6 } }) do
        box("ArchPostW", -ARCH_HW - 0.8, F, zz[1], -ARCH_HW, F + ARCH_H + 0.8, zz[2], GOLD, Enum.Material.Metal, f)
        box("ArchPostE", ARCH_HW, F, zz[1], ARCH_HW + 0.8, F + ARCH_H + 0.8, zz[2], GOLD, Enum.Material.Metal, f)
        box("ArchLintel", -ARCH_HW, F + ARCH_H, zz[1], ARCH_HW, F + ARCH_H + 0.8, zz[2], GOLD, Enum.Material.Metal, f)
    end

    -- marble columns (west half only — the east half is the heist hall + the intro camera's path)
    for _, c in ipairs({ { -14, 70 }, { -14, 92 } }) do
        part({ Name = "LobbyColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(LTOP - F, 3, 3),
            CFrame = CFrame.new(c[1], (F + LTOP) / 2, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
            Color = Color3.fromRGB(226, 218, 206), Material = Enum.Material.Marble }, f)
        for _, y in ipairs({ F + 0.4, LTOP - 0.6 }) do
            part({ Name = "ColumnBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 3.4, 3.4),
                CFrame = CFrame.new(c[1], y, c[2]) * CFrame.Angles(0, 0, math.rad(90)),
                Color = GOLD, Material = Enum.Material.Metal }, f)
        end
    end

    -- light: warm and bright — the lobby is the SAFE place (art rule #5)
    chandelier(f, 0, 77, LTOP - 5)
    chandelier(f, 0, 101, LTOP - 5)
    chandelier(f, -22, 79, LTOP - 6)
    local fill = box("LobbyFill", -1, LTOP - 3, 91, 1, LTOP - 2.5, 93, STEEL, Enum.Material.Metal, f, { Transparency = 1, CanCollide = false })
    light("PointLight", fill, { Brightness = 0.6, Range = 60, Color = Color3.fromRGB(255, 222, 190) })
end

-- ──────────────────────────────────────────────
-- 🟥 LOBBY CENTRE: spawn medallion, red carpet, ropes, marquee, signs
-- ──────────────────────────────────────────────
function ClubBuilder:_lobbyCentre(f, refs)
    -- red carpet from the spawn medallion, through the arch, into the club
    box("Carpet", -4, F, 56, 4, F + 0.06, 91, VELVET, Enum.Material.Fabric, f)
    for _, sx in ipairs({ -1, 1 }) do
        box("CarpetEdge", sx * 4, F, 56, sx * 4.25, F + 0.07, 91, GOLD, Enum.Material.Metal, f)
    end

    -- spawn medallion: gold-rimmed dark marble disc, "THE VAULT" in the middle
    local mz = (SPAWN_ZS[1] + SPAWN_ZS[#SPAWN_ZS]) / 2      -- 101
    local function disc(name, dia, h, color, mat)
        part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, dia, dia),
            CFrame = CFrame.new(0, F + h / 2, mz) * CFrame.Angles(0, 0, math.rad(90)),
            Color = color, Material = mat, CanCollide = false, CanQuery = false }, f)
    end
    disc("MedallionRim", 21, 0.06, GOLD, Enum.Material.Metal)
    disc("Medallion", 20, 0.08, Color3.fromRGB(24, 22, 30), Enum.Material.Marble)
    disc("MedallionRing", 9, 0.1, GOLD, Enum.Material.Metal)
    disc("MedallionCore", 8.4, 0.12, Color3.fromRGB(40, 14, 26), Enum.Material.Marble)
    floorText(f, "MedallionWord", Vector3.new(0, F + 0.15, mz), Vector3.new(0, 0, -1), 7, 1.5, "THE VAULT", GOLD)

    -- SPAWN PADS — 6 of them on the medallion, facing north into the club.
    -- Duration 5 = Roblox's own ForceField for 5 s (spawn protection).
    refs.spawnPads = {}
    local i = 0
    for _, z in ipairs(SPAWN_ZS) do
        for _, x in ipairs(SPAWN_XS) do
            i = i + 1
            local pos = Vector3.new(x, F + 0.1, z)
            local s = Instance.new("SpawnLocation")
            s.Name = "ClubSpawn" .. i
            s.Anchored = true
            s.Size = Vector3.new(5, 0.2, 5)
            s.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
            s.Transparency = 1
            s.CanCollide = false
            s.CanTouch = false
            s.CanQuery = false
            s.Material = Enum.Material.SmoothPlastic
            s.TopSurface = Enum.SurfaceType.Smooth
            s.BottomSurface = Enum.SurfaceType.Smooth
            s.Neutral = true
            s.AllowTeamChangeOnTouch = false
            s.Duration = 5
            s.Enabled = true
            s:SetAttribute("ClubSpawnPad", true)
            s.Parent = f
            guardSpawn(s)
            table.insert(refs.spawnPads, s)
        end
    end

    -- velvet ropes along the carpet (gaps at z 78..82 to step off left/right)
    local function post(x, z)
        box("StanchionBase", x - 0.5, F, z - 0.5, x + 0.5, F + 0.2, z + 0.5, GOLD, Enum.Material.Metal, f)
        box("Stanchion", x - 0.14, F + 0.2, z - 0.14, x + 0.14, F + 3.1, z + 0.14, GOLD, Enum.Material.Metal, f)
        part({ Name = "StanchionTop", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5),
            Position = Vector3.new(x, F + 3.25, z), Color = GOLD, Material = Enum.Material.Metal }, f)
    end
    local function rope(a, b)
        local mid = (a + b) / 2 - Vector3.new(0, 0.6, 0)
        for _, seg in ipairs({ { a, mid }, { mid, b } }) do
            local p0, p1 = seg[1], seg[2]
            local c = (p0 + p1) / 2
            part({ Name = "VelvetRope", Shape = Enum.PartType.Cylinder, Size = Vector3.new((p1 - p0).Magnitude, 0.28, 0.28),
                CFrame = CFrame.lookAt(c, p1) * CFrame.Angles(0, math.rad(90), 0), Color = VELVET,
                Material = Enum.Material.Fabric }, f)
        end
    end
    for _, sx in ipairs({ -5.2, 5.2 }) do
        for _, run in ipairs({ { 68, 71.4, 74.8, 78.2 }, { 82, 86, 90 } }) do
            for k, z in ipairs(run) do
                post(sx, z)
                if k > 1 then rope(Vector3.new(sx, F + 2.9, run[k - 1]), Vector3.new(sx, F + 2.9, z)) end
            end
        end
    end

    -- THE VAULT marquee over the arch, facing the spawn (bulbs chase — ClubFX)
    local sx0, sx1, sy0, sy1 = -13, 13, F + 12.2, F + 18.4
    local sign, sg = signBoard(f, "VaultMarquee", sx0, sy0, LZ0 + 0.2, sx1, sy1, LZ0 + 0.6, Enum.NormalId.Back, 30)
    sg.Brightness = 2.6
    local sbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 8, 20) }, sg)
    local sgr = Instance.new("UIGradient")
    sgr.Rotation = 90
    sgr.Color = ColorSequence.new(Color3.fromRGB(70, 16, 60), Color3.fromRGB(14, 10, 30))
    sgr.Parent = sbg
    text({ Text = "THE VAULT", Position = UDim2.fromScale(0.04, 0.06), Size = UDim2.fromScale(0.92, 0.62),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(255, 232, 170), TextStrokeColor3 = PINK, TextStrokeTransparency = 0.1 }, sbg)
    text({ Text = "HEIST CREW HQ  ·  MEMBERS ONLY", Position = UDim2.fromScale(0.1, 0.7), Size = UDim2.fromScale(0.8, 0.2),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.bold, TextScaled = true,
        TextColor3 = Color3.fromRGB(220, 250, 255) }, sbg)
    light("SurfaceLight", sign, { Face = Enum.NormalId.Back, Brightness = 1.4, Range = 18, Angle = 80, Color = Color3.fromRGB(255, 190, 220) })
    local idx = 0
    local function bulb(x, y)
        idx = idx + 1
        local b = part({ Name = "MarqueeBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.42, 0.42, 0.42),
            Position = Vector3.new(x, y, LZ0 + 0.75), Color = Color3.fromRGB(255, 226, 170),
            Material = Enum.Material.Neon, CanCollide = false, CanQuery = false }, f)
        b:SetAttribute("Index", idx)
        CollectionService:AddTag(b, "MarqueeBulb")
    end
    for x = sx0 + 0.4, sx1 - 0.3, 1.3 do bulb(x, sy1 - 0.35) end
    for y = sy1 - 1.5, sy0 + 0.6, -1.2 do bulb(sx1 - 0.35, y) end
    for x = sx1 - 0.4, sx0 + 0.3, -1.3 do bulb(x, sy0 + 0.35) end
    for y = sy0 + 1.5, sy1 - 0.6, 1.2 do bulb(sx0 + 0.35, y) end

    -- hanging direction sign between the spawn and the arch
    local dy0, dy1, dz = F + 12.5, F + 15.5, 90
    for _, x in ipairs({ -13, 13 }) do
        box("SignCable", x - 0.06, dy1, dz - 0.06, x + 0.06, LTOP, dz + 0.06, STEEL, Enum.Material.Metal, f, { CanCollide = false })
    end
    local dir, dgBack = signBoard(f, "DirectionSign", -15, dy0, dz - 0.2, 15, dy1, dz + 0.2, Enum.NormalId.Back, 30)
    local cells = {
        { "▲  MASKS & GEAR", PINK }, { "▲  THE BOSS", T.gold }, { "HEIST DOORS  ▶", T.money },
    }
    local dbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, dgBack)
    for k, c in ipairs(cells) do
        local cell = frame({ Position = UDim2.new((k - 1) / 3, 6, 0, 8), Size = UDim2.new(1 / 3, -12, 1, -16),
            BackgroundColor3 = T.bgRaised }, dbg)
        UITheme.corner(cell, 10)
        frame({ Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = c[2] }, cell)
        text({ Text = c[1], Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 1, -20),
            TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
            TextColor3 = c[2] }, cell)
    end
    -- back side, for people coming back from the club (heading south, east is on the LEFT)
    local dgFront = surface(dir, Enum.NormalId.Front, 30)
    dgFront.Brightness = 2.2
    local fbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, dgFront)
    text({ Text = "◀  HEIST DOORS", Position = UDim2.fromScale(0.05, 0.1), Size = UDim2.fromScale(0.9, 0.8),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = T.money }, fbg)
    light("PointLight", dir, { Brightness = 0.8, Range = 10, Color = Color3.fromRGB(255, 230, 200) })

    -- floor arrows (painted, not glowing — rule #1)
    floorArrow(f, Vector3.new(0, 0, 86.5), Vector3.new(0, 0, -1), Vector3.new(0, 0, -1), "THE BOSS", T.gold, 5)
    floorArrow(f, Vector3.new(-9.5, 0, 88), Vector3.new(0, 0, -1), Vector3.new(0, 0, -1), "MASKS & GEAR", PINK, 6.4)
    floorArrow(f, Vector3.new(15, 0, 100), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), "HEISTS", T.money, 6)
    floorArrow(f, Vector3.new(29, 0, 100), Vector3.new(1, 0, 0), Vector3.new(1, 0, 0), "HEIST DOORS", T.money, 6)
    -- inside the club, just past the arch: the way back to the doors
    floorArrow(f, Vector3.new(0, 0, 53), Vector3.new(0, 0, 1), Vector3.new(0, 0, 1), "HEIST DOORS", T.money, 6)

    -- two-sided pylon just inside the club (east of the carpet, clear of the intro camera)
    local py = box("WayPylon", 4.6, F, 57.7, 6.6, F + 7, 58.3, Color3.fromRGB(14, 14, 18), Enum.Material.Metal, f)
    box("WayPylonCap", 4.5, F + 7, 57.6, 6.7, F + 7.2, 58.4, GOLD, Enum.Material.Metal, f)
    local pyS = surface(py, Enum.NormalId.Back, 50)       -- faces south: people walking in from the lobby
    pyS.Brightness = 2
    local pyN = surface(py, Enum.NormalId.Front, 50)      -- faces north: people in the club
    pyN.Brightness = 2
    local function pylonRows(g, rows)
        local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, g)
        for k, r in ipairs(rows) do
            local y = (k - 1) / #rows
            frame({ Position = UDim2.new(0, 8, y, 8), Size = UDim2.new(0, 6, 1 / #rows, -16), BackgroundColor3 = r[2] }, bg)
            text({ Text = r[1], Position = UDim2.new(0, 20, y, 6), Size = UDim2.new(1, -28, 1 / #rows, -12),
                FontFace = UITheme.F.display, TextScaled = true, TextColor3 = r[2] }, bg)
        end
    end
    pylonRows(pyS, { { "▲ BOSS", T.gold }, { "◀ MASKS", PINK }, { "▶ ROLES", T.info } })
    pylonRows(pyN, { { "▲ HEIST", T.money }, { "   DOORS", T.money }, { "▲ STREET", T.muted } })
end

-- ──────────────────────────────────────────────
-- 🧥 LOBBY WEST: coat check, leaderboard wall, lounge
-- ──────────────────────────────────────────────
function ClubBuilder:_lobbyWest(f, refs)
    local plaster = Color3.fromRGB(62, 32, 40)
    -- COAT CHECK (south-west corner, counter faces north)
    box("CoatRoomWall", -18, F, 105.4, -17.4, F + 10, LZ1, plaster, Enum.Material.Plaster, f)
    box("CoatCounter", LX0, F, 103.6, -19.6, F + 3.6, 105.4, WOOD, Enum.Material.WoodPlanks, f)
    box("CoatCounterTop", LX0, F + 3.6, 103.4, -19.4, F + 3.9, 105.6, Color3.fromRGB(232, 226, 236), Enum.Material.Marble, f)
    box("CoatCounterRail", LX0, F + 0.3, 103.5, -19.6, F + 0.5, 103.6, GOLD, Enum.Material.Metal, f)
    part({ Name = "CounterBell", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6),
        Position = Vector3.new(-22, F + 4.1, 104.4), Color = GOLD, Material = Enum.Material.Metal }, f)
    box("TicketStack", -26, F + 3.9, 104.1, -25.2, F + 4.2, 104.7, Color3.fromRGB(240, 200, 90), Enum.Material.SmoothPlastic, f)
    local coatCols = {
        Color3.fromRGB(30, 30, 34), Color3.fromRGB(120, 36, 42), Color3.fromRGB(46, 62, 96), Color3.fromRGB(150, 120, 90),
        Color3.fromRGB(70, 70, 76), Color3.fromRGB(30, 70, 60), Color3.fromRGB(190, 170, 150),
    }
    for r, z in ipairs({ 109, 114 }) do
        for _, x in ipairs({ LX0 + 1.5, -20.5 }) do
            box("CoatRailPost", x - 0.12, F, z - 0.12, x + 0.12, F + 7.8, z + 0.12, STEEL, Enum.Material.Metal, f)
        end
        box("CoatRail", LX0 + 1.5, F + 7.5, z - 0.08, -20.5, F + 7.66, z + 0.08, STEEL, Enum.Material.Metal, f, { CanCollide = false })
        local n = 0
        for x = LX0 + 2.6, -21.4, 0.8 do
            n = n + 1
            local tilt = ((n * 37 + r * 11) % 7 - 3) * 0.02
            part({ Name = "Coat", Size = Vector3.new(0.45, 3.6, 1.7),
                CFrame = CFrame.new(x, F + 5.6, z) * CFrame.Angles(0, 0, tilt),
                Color = coatCols[(n + r * 3) % #coatCols + 1], Material = Enum.Material.Fabric, CanCollide = false }, f)
        end
    end
    local _, cg = signBoard(f, "CoatCheckSign", -29, F + 9.2, 103.6, -21, F + 11.4, 103.8, Enum.NormalId.Front, 30)
    text({ Text = "COAT CHECK", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        FontFace = UITheme.F.display, TextScaled = true, TextColor3 = Color3.fromRGB(255, 232, 190),
        TextStrokeColor3 = Color3.fromRGB(200, 120, 40), TextStrokeTransparency = 0.3 }, cg)
    local lamp = box("CoatLamp", -25.4, LTOP - 6, 106.6, -24.6, LTOP - 5.6, 107.4, GOLD, Enum.Material.Metal, f, { CanCollide = false })
    box("CoatLampRod", -25.06, LTOP - 5.6, 106.94, -24.94, LTOP, 107.06, GOLD, Enum.Material.Metal, f, { CanCollide = false })
    light("PointLight", lamp, { Brightness = 1.1, Range = 16, Color = Color3.fromRGB(255, 205, 150) })

    -- LEADERBOARD WALL (west wall, x -32): a framed 14 × 8 spot. The progression
    -- agent's board goes in front of this backing panel.
    local zc, yc = 79, F + 7
    local bx = LX0 + 0.2
    local backing = box("BoardBacking", LX0, yc - 4.2, zc - 7.2, bx, yc + 4.2, zc + 7.2, Color3.fromRGB(16, 16, 22), Enum.Material.Fabric, f)
    for _, e in ipairs({
        { yc - 4.5, zc - 7.5, yc - 4.2, zc + 7.5 }, { yc + 4.2, zc - 7.5, yc + 4.5, zc + 7.5 },
        { yc - 4.2, zc - 7.5, yc + 4.2, zc - 7.2 }, { yc - 4.2, zc + 7.2, yc + 4.2, zc + 7.5 },
    }) do
        box("BoardFrame", LX0, e[1], e[2], bx + 0.15, e[3], e[4], GOLD, Enum.Material.Metal, f)
    end
    local ph = surface(backing, Enum.NormalId.Right, 20)
    text({ Text = "TOP HEISTERS", Position = UDim2.fromScale(0, 0.35), Size = UDim2.fromScale(1, 0.3),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = T.faint }, ph)
    for _, z in ipairs({ zc - 4, zc + 4 }) do
        local from = Vector3.new(LX0 + 6, LTOP - 0.6, z)
        local sp = part({ Name = "BoardSpot", Size = Vector3.new(0.6, 0.6, 0.9), Color = STEEL, Material = Enum.Material.Metal,
            CanCollide = false, CFrame = CFrame.lookAt(from, Vector3.new(LX0, yc, z)) }, f)
        light("SpotLight", sp, { Face = Enum.NormalId.Front, Angle = 50, Brightness = 1.6, Range = 22,
            Color = Color3.fromRGB(255, 236, 214), Shadows = false })
    end
    -- CFrame at the centre of the clear 14 × 8 wall spot, 0.1 in front of the backing.
    -- ► The board's READABLE FRONT faces along anchor.LookVector (out of the wall,
    --   +X, into the lobby). A reader stands in front of it looking along -LookVector.
    --   Build the board as a Part with CFrame = anchor * CFrame.new(0, 0, -thickness/2)
    --   and put its SurfaceGui on Enum.NormalId.Front. Up = anchor.UpVector (+Y).
    --   Clear area: 14 wide (along anchor.RightVector) × 8 tall.
    refs.leaderboardAnchor = CFrame.lookAt(Vector3.new(bx + 0.1, yc, zc), Vector3.new(bx + 1.1, yc, zc))

    -- LOUNGE facing the board (keeps x -32..-25 clear in front of it)
    KenneyLoader.placeMany({
        { kit = "furniture", name = "rugRectangle", pos = Vector3.new(-21.5, F, 79), facing = Vector3.new(-1, 0, 0), opts = { collide = false } },
        { kit = "furniture", name = "loungeSofa", pos = Vector3.new(-19.5, F, 75.5), facing = Vector3.new(-1, 0, 0) },
        { kit = "furniture", name = "loungeSofa", pos = Vector3.new(-19.5, F, 82.5), facing = Vector3.new(-1, 0, 0) },
        { kit = "furniture", name = "tableCoffee", pos = Vector3.new(-23, F, 79), facing = Vector3.new(-1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(LX0 + 1.6, F, 67.5), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(LX0 + 1.6, F, 91), facing = Vector3.new(1, 0, 0) },
        { kit = "furniture", name = "pottedPlant", pos = Vector3.new(-10.5, F, 67.5), facing = Vector3.new(0, 0, 1) },
        { kit = "furniture", name = "coatRackStanding", pos = Vector3.new(-18.8, F, 102.6), facing = Vector3.new(0, 0, -1) },
    }, f)
end

-- ──────────────────────────────────────────────
-- 🕴 BOUNCER + host stand by the arch
-- ──────────────────────────────────────────────
function ClubBuilder:_bouncer(f)
    box("HostStand", 8.8, F, 72.6, 10.4, F + 3.3, 73.8, WOOD, Enum.Material.WoodPlanks, f)
    box("HostStandTop", 8.6, F + 3.3, 72.4, 10.6, F + 3.5, 74, GOLD, Enum.Material.Metal, f)
    box("Clipboard", 9.2, F + 3.5, 72.8, 9.9, F + 3.56, 73.5, Color3.fromRGB(235, 235, 228), Enum.Material.SmoothPlastic, f)
    local okReq, NpcFactory = pcall(require, script.Parent.NpcFactory)
    if not okReq or not NpcFactory then return end
    task.spawn(function()
        local ok, model, humanoid, root = pcall(NpcFactory.build, {
            name = "Bouncer_NPC",
            bodyColors = {
                head  = Color3.fromRGB(120, 84, 60),
                torso = Color3.fromRGB(18, 18, 22),
                arms  = Color3.fromRGB(120, 84, 60),
                legs  = Color3.fromRGB(22, 22, 26),
            },
        })
        if not ok or not model or not humanoid or not root then
            warn("[ClubBuilder] bouncer NPC skipped:", ok and "build returned nil" or tostring(model))
            return
        end
        root.Anchored = true
        local standAt = Vector3.new(9.6, F + humanoid.HipHeight + root.Size.Y / 2, 69.6)
        model:PivotTo(CFrame.lookAt(standAt, Vector3.new(2, standAt.Y, 80)))
        model.Parent = f
        pcall(NpcFactory.animate, humanoid)
        -- the one allowed kind of floating text: a short NPC speech bubble
        local head = model:FindFirstChild("Head") or root
        local att = Instance.new("Attachment")
        att.Position = Vector3.new(0, 2.6, 0)
        att.Parent = head
        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(230, 64)
        bb.MaxDistance = 30
        bb.LightInfluence = 0
        bb.Parent = att
        local bg = UITheme.panel({ Size = UDim2.fromScale(1, 1), transparency = 0.12, radius = 14 })
        bg.Parent = bb
        UITheme.caption("Bouncer", { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 14),
            TextColor3 = T.gold }).Parent = bg
        UITheme.label({ Text = "Welcome in! Heist doors are over on the right.", Position = UDim2.fromOffset(14, 22),
            Size = UDim2.new(1, -28, 0, 36), TextWrapped = true, FontFace = UITheme.F.bold, TextSize = 15,
            TextYAlignment = Enum.TextYAlignment.Top }).Parent = bg
    end)
end

-- ──────────────────────────────────────────────
-- 🚪 HEIST HALL: the east wall with 4 heist doors
-- ──────────────────────────────────────────────
function ClubBuilder:_portal(f, id, index, c)
    local cfg = jobCfg(id)
    local col = JOB_COLOR[id] or GOLD
    local WX = LX1                                      -- wall face x 44
    local z0, z1 = c - PORTAL_HW, c + PORTAL_HW
    local trim = Color3.fromRGB(64, 66, 76)

    -- (v2.0.2) A REAL elevator / vault door, not a white slab (Malachi,
    -- Future lighting: "very simple / bad"). Gunmetal frame proud of the wall
    -- with bolt heads, steel-lined reveal, brass name plate + a floor-number
    -- display in the head, a call button, and brushed-steel leaves with a
    -- rubber centre seam, a raised panel, a kick plate and a thin job-colour
    -- light line. Every leaf detail slides with its leaf.
    local GUN = Color3.fromRGB(58, 60, 70)
    local BRUSHED = Color3.fromRGB(168, 172, 182)
    local BRUSHED_DK = Color3.fromRGB(138, 142, 152)
    local BOLT = Color3.fromRGB(196, 198, 206)
    local FX0 = WX - 0.9                                -- frame front face (x 43.1)
    local HEAD0, HEAD1 = F + PORTAL_H, F + PORTAL_H + 1.2

    box("DoorPostN", FX0, F, z0 - 1.1, WX, HEAD1, z0, GUN, Enum.Material.Metal, f)
    box("DoorPostS", FX0, F, z1, WX, HEAD1, z1 + 1.1, GUN, Enum.Material.Metal, f)
    box("DoorLintel", FX0, HEAD0, z0, WX, HEAD1, z1, GUN, Enum.Material.Metal, f)
    -- plinth blocks at the foot of each post (breaks up the silhouette)
    box("DoorPlinthN", FX0 - 0.12, F, z0 - 1.22, WX, F + 1.1, z0 + 0.02, Color3.fromRGB(40, 42, 50), Enum.Material.DiamondPlate, f)
    box("DoorPlinthS", FX0 - 0.12, F, z1 - 0.02, WX, F + 1.1, z1 + 1.22, Color3.fromRGB(40, 42, 50), Enum.Material.DiamondPlate, f)
    -- steel-lined reveal from the wall face back to the leaves
    local REVEAL = Color3.fromRGB(120, 124, 134)
    box("RevealN", WX, F, z0, 46.6, F + PORTAL_H, z0 + 0.15, REVEAL, Enum.Material.Metal, f)
    box("RevealS", WX, F, z1 - 0.15, 46.6, F + PORTAL_H, z1, REVEAL, Enum.Material.Metal, f)
    box("RevealTop", WX, F + PORTAL_H - 0.15, z0, 46.6, F + PORTAL_H, z1, REVEAL, Enum.Material.Metal, f)
    box("Sill", FX0, F, z0, 47.2, F + 0.06, z1, Color3.fromRGB(150, 154, 162), Enum.Material.DiamondPlate, f,
        { CanCollide = false })
    -- thin job-colour light line on the inside edge of the frame
    neon("DoorStripN", FX0 - 0.04, F + 1.1, z0 - 0.26, FX0, F + PORTAL_H, z0 - 0.12, col, f)
    neon("DoorStripS", FX0 - 0.04, F + 1.1, z1 + 0.12, FX0, F + PORTAL_H, z1 + 0.26, col, f)
    neon("DoorStripTop", FX0 - 0.04, HEAD0 + 0.12, z0 - 0.26, FX0, HEAD0 + 0.26, z1 + 0.26, col, f)
    -- bolt heads up both posts and along the head
    local function bolt(y, z)
        part({ Name = "Bolt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.3, 0.3),
            CFrame = CFrame.new(FX0 - 0.06, y, z), Color = BOLT, Material = Enum.Material.Metal,
            CanCollide = false, CanQuery = false, CastShadow = false }, f)
    end
    for y = F + 1.8, F + PORTAL_H - 0.4, 1.7 do
        bolt(y, z0 - 0.7)
        bolt(y, z1 + 0.7)
    end
    for _, zz in ipairs({ z0 - 0.7, z1 + 0.7 }) do bolt(HEAD0 + 0.6, zz) end

    -- floor-number display (dark glass, amber digits) + brass name plate in the head
    local disp = box("FloorDisplay", FX0 - 0.1, HEAD0 + 0.2, c + 1.2, FX0, HEAD1 - 0.2, c + 3.7,
        Color3.fromRGB(12, 10, 10), Enum.Material.Glass, f, { CanCollide = false })
    local dg = surface(disp, Enum.NormalId.Left, 50)
    dg.Brightness = 2
    local dispText = text({ Text = "▲ " .. index, Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.mono, TextScaled = true,
        TextColor3 = Color3.fromRGB(255, 176, 60) }, dg)
    local plate = box("NamePlate", FX0 - 0.08, HEAD0 + 0.25, c - 3.8, FX0, HEAD1 - 0.25, c + 0.9,
        Color3.fromRGB(196, 158, 84), Enum.Material.Metal, f, { CanCollide = false })
    local pg = surface(plate, Enum.NormalId.Left, 50)
    pg.LightInfluence = 1
    pg.Brightness = 1
    text({ Text = cfg.name or string.upper(id), Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = Color3.fromRGB(36, 26, 14) }, pg)
    -- call button on the north post
    box("CallPanel", FX0 - 0.06, F + 4.3, z0 - 0.95, FX0, F + 5.7, z0 - 0.35, Color3.fromRGB(24, 24, 28), Enum.Material.Metal, f,
        { CanCollide = false })
    part({ Name = "CallButton", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 0.36, 0.36),
        CFrame = CFrame.new(FX0 - 0.09, F + 5.0, z0 - 0.65), Color = col, Material = Enum.Material.Neon,
        CanCollide = false, CanQuery = false }, f)

    -- sliding elevator doors (open only as the heist leaves — v2.0.1)
    local leaves = {}
    local function slide(pt, s)
        local closed = pt.CFrame
        table.insert(leaves, { part = pt, closed = closed, open = closed + Vector3.new(0, 0, s * (PORTAL_HW - 0.3)) })
    end
    for _, s in ipairs({ -1, 1 }) do
        local zb = c + s * PORTAL_HW                    -- outer edge; c = the seam
        local zlo, zhi = math.min(c, zb), math.max(c, zb)
        slide(box("DoorLeaf", 46.6, F, zlo, 47.1, F + PORTAL_H, zhi, BRUSHED, Enum.Material.Metal, f,
            { Reflectance = 0.12 }), s)
        local deco = { CanCollide = false, CanQuery = false }
        -- raised centre panel (slightly darker brushed steel)
        slide(box("LeafPanel", 46.5, F + 1.4, zlo + 0.45, 46.6, F + PORTAL_H - 0.6, zhi - 0.45, BRUSHED_DK,
            Enum.Material.Metal, f, deco), s)
        -- kick plate
        slide(box("LeafKick", 46.5, F, zlo + 0.1, 46.6, F + 1.1, zhi - 0.1, Color3.fromRGB(86, 88, 96),
            Enum.Material.DiamondPlate, f, deco), s)
        -- thin job-colour light line at hand height
        slide(box("LeafLine", 46.44, F + 5.2, zlo + 0.45, 46.5, F + 5.36, zhi - 0.45, col, Enum.Material.Neon, f, deco), s)
        -- rubber seam where the two leaves meet
        local sz0, sz1 = (s < 0) and (c - 0.12) or c, (s < 0) and c or (c + 0.12)
        slide(box("LeafSeam", 46.48, F, sz0, 46.62, F + PORTAL_H, sz1, Color3.fromRGB(16, 16, 18),
            Enum.Material.Rubber, f, deco), s)
    end
    local shaft = box("ShaftLight", 48.6, F + 5, c - 0.2, 49, F + 5.4, c + 0.2, STEEL, Enum.Material.Metal, f,
        { Transparency = 1, CanCollide = false })
    local shaftLight = light("PointLight", shaft, { Brightness = 2.5, Range = 9, Color = col, Enabled = false })

    -- the glowing floor zone in front of the door (glass + thin light edges)
    local pad = box("PortalPad", 36.5, F, z0 + 0.2, 46.5, F + 0.06, z1 - 0.2, col, Enum.Material.Glass, f,
        { Transparency = 0.45, CanCollide = false, CanQuery = false })
    neon("PadEdgeW", 36.3, F, z0 + 0.2, 36.5, F + 0.07, z1 - 0.2, col, f)
    neon("PadEdgeN", 36.3, F, z0, WX - 0.4, F + 0.07, z0 + 0.2, col, f)
    neon("PadEdgeS", 36.3, F, z1 - 0.2, WX - 0.4, F + 0.07, z1, col, f)
    floorText(f, "StandHere", Vector3.new(38.6, F + 0.1, c), Vector3.new(1, 0, 0), 6.4, 1.4, "WALK IN", col)
    local glow = box("PortalGlow", 40.3, F + 1, c - 0.2, 40.7, F + 1.4, c + 0.2, STEEL, Enum.Material.Metal, f,
        { Transparency = 1, CanCollide = false, CanQuery = false })
    light("PointLight", glow, { Brightness = 1, Range = 11, Color = col })
    glow:SetAttribute("State", "idle")
    CollectionService:AddTag(glow, "PortalGlow")
    local fixture = box("PortalDownlight", 39.4, LTOP - 0.4, c - 0.6, 40.6, LTOP, c + 0.6, STEEL, Enum.Material.Metal, f, { CanCollide = false })
    light("SpotLight", fixture, { Face = Enum.NormalId.Bottom, Angle = 70, Brightness = 1.6, Range = 24,
        Color = Color3.fromRGB(255, 244, 230), Shadows = false })

    -- the trigger volume PortalService watches (and PortalHud finds by tag)
    local zone = box("PortalZone_" .. id, 36, F, z0, 47, F + 8, z1, Color3.new(), Enum.Material.SmoothPlastic, f,
        { Transparency = 1, CanCollide = false, CanTouch = true, CanQuery = false })
    zone:SetAttribute("JobId", id)
    CollectionService:AddTag(zone, "PortalZone")

    -- the sign over the door: DOOR n · NAME · difficulty · status
    local sign, g = signBoard(f, "DoorSign", WX - 0.5, F + 12.3, c - 5, WX - 0.3, F + 17.3, c + 5, Enum.NormalId.Left, 40)
    g.Brightness = 1.8
    local bg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, g)
    frame({ Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = col }, bg)
    text({ Text = string.format("DOOR %d", index), Position = UDim2.fromOffset(18, 14), Size = UDim2.fromOffset(140, 22),
        TextColor3 = T.faint, FontFace = UITheme.F.mono, TextSize = 20 }, bg)
    text({ Text = cfg.name or string.upper(id), Position = UDim2.fromOffset(16, 34), Size = UDim2.new(1, -32, 0, 64),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = T.text, TextStrokeColor3 = col, TextStrokeTransparency = 0.4 }, bg)
    local d = math.clamp(math.floor(cfg.difficulty or 1), 1, 4)
    local diffRow = frame({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 102),
        Size = UDim2.fromOffset(300, 30), BackgroundTransparency = 1 }, bg)
    for k = 1, 4 do
        local dia = frame({ Size = UDim2.fromOffset(17, 17), Position = UDim2.fromOffset(14 + (k - 1) * 30, 6),
            Rotation = 45, BackgroundColor3 = col, BackgroundTransparency = (k <= d) and 0 or 1 }, diffRow)
        if k > d then UITheme.stroke(dia, col, 0.2, 2) end
    end
    text({ Text = DIFF_WORD[d], Position = UDim2.fromOffset(140, 0), Size = UDim2.fromOffset(160, 30),
        FontFace = UITheme.F.display, TextSize = 26, TextColor3 = col }, diffRow)
    local bar = frame({ Position = UDim2.new(0, 16, 1, -60), Size = UDim2.new(1, -32, 0, 48), BackgroundColor3 = T.bgRaised }, bg)
    UITheme.corner(bar, 10)
    local status = text({ Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 1, -10),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = T.text }, bar)
    light("PointLight", sign, { Brightness = 0.9, Range = 10, Color = col })

    local isOpen = false
    local function setDoors(open)
        if isOpen == open then return end
        isOpen = open
        for _, l in ipairs(leaves) do
            TweenService:Create(l.part, TweenInfo.new(open and 1.2 or 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                { CFrame = open and l.open or l.closed }):Play()
        end
        shaftLight.Enabled = open
    end

    -- count: players in the zone · needed: players it takes to launch (nil = unknown)
    -- launchIn: seconds until the drop-in (nil/0 = not counting) · locked: false | true | level
    local function setState(count, needed, launchIn, locked)
        count = math.max(0, math.floor(tonumber(count) or 0))
        needed = tonumber(needed)
        launchIn = tonumber(launchIn)
        if locked then
            -- (v2.0.1) locked == true just means a heist is already running
            status.Text = (type(locked) == "number") and string.format("LOCKED — level %d", locked) or "Heist in progress…"
            status.TextColor3 = T.danger
            glow:SetAttribute("State", "locked")
            dispText.Text = "✕"
            dispText.TextColor3 = Color3.fromRGB(255, 70, 70)
            pad.Transparency = 0.85
            setDoors(false)
        elseif launchIn and launchIn > 0 then
            status.Text = string.format("Starting in %d…", math.ceil(launchIn))
            status.TextColor3 = T.money
            glow:SetAttribute("State", "launch")
            dispText.Text = (launchIn <= 1.2) and "▲▲" or tostring(math.ceil(launchIn))
            dispText.TextColor3 = Color3.fromRGB(120, 255, 150)
            pad.Transparency = 0.2
            -- (v2.0.1) Malachi: "don't open the door till it's leaving"
            setDoors(launchIn <= 1.2)
        elseif count > 0 then
            if needed and needed > 0 then
                status.Text = string.format("%d / %d players", count, needed)
            else
                status.Text = string.format("%d player%s in", count, count == 1 and "" or "s")
            end
            status.TextColor3 = T.gold
            glow:SetAttribute("State", "busy")
            dispText.Text = "▲ " .. index
            dispText.TextColor3 = Color3.fromRGB(255, 200, 80)
            pad.Transparency = 0.3
            setDoors(false)
        else
            status.Text = "Walk in to play!"
            status.TextColor3 = T.text
            glow:SetAttribute("State", "idle")
            dispText.Text = "▲ " .. index
            dispText.TextColor3 = Color3.fromRGB(255, 176, 60)
            pad.Transparency = 0.45
            setDoors(false)
        end
    end
    setState(0, nil, nil, false)
    return { zone = zone, setState = setState }
end

function ClubBuilder:_heistHall(f, refs)
    local WX, BX = LX1, 50                              -- wall face / back of the door block
    local block = Color3.fromRGB(30, 30, 36)
    local zPrev = LZ0
    for _, c in ipairs(PORTAL_Z) do
        box("HallPier", WX, F, zPrev, BX, LTOP, c - PORTAL_HW, block, Enum.Material.Concrete, f)
        box("DoorHeader", WX, F + PORTAL_H, c - PORTAL_HW, BX, LTOP, c + PORTAL_HW, block, Enum.Material.Concrete, f)
        box("AlcoveFloor", WX, F - 1, c - PORTAL_HW, BX, F, c + PORTAL_HW, Color3.fromRGB(44, 44, 50), Enum.Material.DiamondPlate, f)
        box("ShaftBack", BX - 0.6, F, c - PORTAL_HW, BX, F + PORTAL_H, c + PORTAL_HW, Color3.fromRGB(14, 14, 18), Enum.Material.Metal, f)
        zPrev = c + PORTAL_HW
    end
    box("HallPier", WX, F, zPrev, BX, LTOP, LZ1, block, Enum.Material.Concrete, f)
    -- banner along the top of the door wall
    local _, bg = signBoard(f, "HallBanner", WX - 0.4, F + 17.8, LZ0 + 1, WX - 0.2, F + 19.6, LZ1 - 1, Enum.NormalId.Left, 24)
    local bbg = frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.bg }, bg)
    text({ Text = "HEIST DOORS  ·  WALK IN TO START  ·  EASY  ▶  HARD", Size = UDim2.fromScale(1, 1),
        TextXAlignment = Enum.TextXAlignment.Center, FontFace = UITheme.F.display, TextScaled = true,
        TextColor3 = T.money }, bbg)

    refs.portals = {}
    for i, id in ipairs(PORTAL_ORDER) do
        local c = PORTAL_Z[i]
        local ok, res = pcall(self._portal, self, sub(f, "Door_" .. id), id, i, c)
        if ok then
            refs.portals[id] = res
        else
            warn("[ClubBuilder] heist door " .. id .. " failed: " .. tostring(res))
        end
    end
end

-- ──────────────────────────────────────────────
-- ✨ POLISH (v2.0.2) — fewer flat surfaces for Future lighting:
-- coffered lobby ceiling, gold floor inlay, baseboards, wall sconces
-- (pools of light on the walls), ribbed steel cladding on the door wall.
-- ──────────────────────────────────────────────
function ClubBuilder:_polish(f)
    local DARKWOOD = Color3.fromRGB(46, 30, 24)
    local deco = { CanCollide = false, CanQuery = false }

    -- lobby: coffered ceiling (beams on a 12-stud grid, gold edge on the underside)
    for _, x in ipairs({ -26, -14, -2, 10 }) do
        box("CofferBeamZ", x - 0.6, LTOP - 1.4, LZ0 + 0.2, x + 0.6, LTOP, LZ1, DARKWOOD, Enum.Material.WoodPlanks, f, deco)
        box("CofferTrimZ", x - 0.65, LTOP - 1.5, LZ0 + 0.2, x + 0.65, LTOP - 1.4, LZ1, GOLD, Enum.Material.Metal, f, deco)
    end
    for _, z in ipairs({ 71, 83, 95, 107 }) do
        box("CofferBeamX", LX0, LTOP - 1.4, z - 0.6, 16, LTOP, z + 0.6, DARKWOOD, Enum.Material.WoodPlanks, f, deco)
        box("CofferTrimX", LX0, LTOP - 1.5, z - 0.65, 16, LTOP - 1.4, z + 0.65, GOLD, Enum.Material.Metal, f, deco)
    end

    -- lobby: thin gold inlay lines in the marble (under the carpet + medallion)
    local INLAY = Color3.fromRGB(176, 140, 66)
    for _, x in ipairs({ -24, -16, -8, 8 }) do
        box("FloorInlay", x - 0.1, F, LZ0 + 0.5, x + 0.1, F + 0.02, LZ1 - 0.5, INLAY, Enum.Material.Metal, f, deco)
    end
    for _, z in ipairs({ 72, 80, 88, 96, 104, 112 }) do
        box("FloorInlay", LX0 + 0.5, F, z - 0.1, 15.5, F + 0.02, z + 0.1, INLAY, Enum.Material.Metal, f, deco)
    end
    -- a dark border band where the lobby marble meets the hall slate
    box("FloorBorder", 15.2, F, LZ0 + 0.2, 16, F + 0.03, LZ1, Color3.fromRGB(20, 18, 22), Enum.Material.Marble, f, deco)

    -- club: dark metal baseboards (the walls met the floor with no line at all)
    local BASE = Color3.fromRGB(20, 20, 26)
    box("BaseboardN", X0, F, Z0, X1, F + 0.7, Z0 + 0.15, BASE, Enum.Material.Metal, f, deco)
    box("BaseboardW", X0, F, Z0, X0 + 0.15, F + 0.7, Z1, BASE, Enum.Material.Metal, f, deco)
    box("BaseboardE", X1 - 0.15, F, Z0, X1, F + 0.7, Z1, BASE, Enum.Material.Metal, f, deco)
    box("BaseboardSW", X0, F, Z1 - 0.15, -ARCH_HW - 0.8, F + 0.7, Z1, BASE, Enum.Material.Metal, f, deco)
    box("BaseboardSE", ARCH_HW + 0.8, F, Z1 - 0.15, X1, F + 0.7, Z1, BASE, Enum.Material.Metal, f, deco)

    -- lobby: gold wall sconces → warm pools of light on the plaster
    local function sconce(pos, out)
        local base = part({ Name = "SconcePlate", Size = Vector3.new(0.9, 1.4, 0.15),
            CFrame = CFrame.lookAt(pos, pos + out), Color = GOLD, Material = Enum.Material.Metal }, f)
        base.CanCollide = false
        local shade = part({ Name = "SconceShade", Size = Vector3.new(0.9, 0.7, 0.6),
            CFrame = CFrame.lookAt(pos + out * 0.4 + Vector3.new(0, 0.35, 0), pos + out * 2 + Vector3.new(0, 0.35, 0)),
            Color = Color3.fromRGB(240, 214, 170), Material = Enum.Material.Fabric, CanCollide = false }, f)
        light("SpotLight", shade, { Face = Enum.NormalId.Top, Angle = 70, Brightness = 1.2, Range = 10,
            Color = Color3.fromRGB(255, 206, 150) })
        light("SpotLight", base, { Face = Enum.NormalId.Bottom, Angle = 60, Brightness = 0.6, Range = 7,
            Color = Color3.fromRGB(255, 206, 150) })
    end
    sconce(Vector3.new(-12, F + 7.5, LZ1 - 0.1), Vector3.new(0, 0, -1))
    sconce(Vector3.new(10, F + 7.5, LZ1 - 0.1), Vector3.new(0, 0, -1))
    sconce(Vector3.new(LX0 + 0.1, F + 7.5, 95), Vector3.new(1, 0, 0))
    sconce(Vector3.new(-24, F + 7.5, LZ0 + 0.3), Vector3.new(0, 0, 1))

    -- heist hall: ribbed steel cladding on the piers between the doors, a
    -- dark skirting, and a light trough along the ceiling (no extra lights)
    local zPrev = LZ0
    local RIB = Color3.fromRGB(70, 72, 82)
    for i = 1, #PORTAL_Z + 1 do
        local zEnd = (i <= #PORTAL_Z) and (PORTAL_Z[i] - PORTAL_HW - 1.3) or LZ1
        local zStart = (i == 1) and zPrev or (PORTAL_Z[i - 1] + PORTAL_HW + 1.3)
        if zEnd - zStart > 0.6 then
            box("HallSkirting", LX1 - 0.35, F, zStart, LX1, F + 0.8, zEnd, BASE, Enum.Material.Metal, f, deco)
            for z = zStart + 0.3, zEnd - 0.3, 0.9 do
                box("WallRib", LX1 - 0.25, F + 0.8, z - 0.15, LX1, F + 11.8, z + 0.15, RIB, Enum.Material.Metal, f, deco)
            end
        end
    end
    box("HallTrough", 30, LTOP - 0.6, LZ0 + 1, 32, LTOP, LZ1 - 1, Color3.fromRGB(26, 26, 32), Enum.Material.Metal, f, deco)
    box("HallTroughGlow", 30.3, LTOP - 0.65, LZ0 + 1.2, 31.7, LTOP - 0.6, LZ1 - 1.2, Color3.fromRGB(255, 236, 210),
        Enum.Material.Neon, f, deco)
end

-- ──────────────────────────────────────────────
-- 🎥 first-join fly-over: street → auto shop lift → club → heist doors → spawn
-- ──────────────────────────────────────────────
function ClubBuilder:_introPath(refs)
    local mz = (SPAWN_ZS[1] + SPAWN_ZS[#SPAWN_ZS]) / 2
    refs.introPath = {
        CFrame.lookAt(Vector3.new(0, 9, -27), Vector3.new(0, 12, 3)),             -- across the street: RIVERSIDE AUTO sign
        CFrame.lookAt(Vector3.new(3, 10, 14), Vector3.new(0, 0.5, 22)),           -- in the shop, over the freight lift
        CFrame.lookAt(Vector3.new(-24, F + 15, 12), Vector3.new(0, F + 4, 40)),   -- down in the club: bar → holo table
        CFrame.lookAt(Vector3.new(0, F + 7, 67), Vector3.new(20, F + 5, 90)),     -- through the arch into the lobby
        CFrame.lookAt(Vector3.new(20, F + 9, 84), Vector3.new(LX1, F + 6, 92)),   -- the heist doors
        CFrame.lookAt(Vector3.new(0, F + 9, LZ1 - 4), Vector3.new(0, F + 3, mz - 2)), -- the spawn medallion
    }
end

-- ──────────────────────────────────────────────
function ClubBuilder:build(folder)
    local f = Instance.new("Folder")
    f.Name = "TheVault"
    f.Parent = folder
    local refs = {}
    local steps = {
        { "shell", function() self:_shell(sub(f, "Shell")) end },
        { "stage", function() self:_stage(sub(f, "Stage")) end },
        { "dance floor", function() self:_danceFloor(sub(f, "DanceFloor")) end },
        { "bar", function() self:_bar(sub(f, "Bar")) end },
        { "holo table", function() self:_holoTable(sub(f, "HoloTable"), refs) end },
        { "crew pads", function() self:_crewPads(sub(f, "CrewPads"), refs) end },
        { "mask wall", function() self:_maskWall(sub(f, "MaskWall")) end },
        { "trophy room", function() self:_trophyRoom(sub(f, "TrophyRoom"), refs) end },
        { "garage bay", function() self:_garageBay(sub(f, "GarageBay"), refs) end },
        { "elevator", function() self:_elevator(sub(f, "Elevator"), refs) end },
        -- v2.0: entrance lobby + heist hall
        { "lobby shell", function() self:_lobbyShell(sub(f, "LobbyShell")) end },
        { "lobby centre", function() self:_lobbyCentre(sub(f, "Lobby"), refs) end },
        { "lobby west", function() self:_lobbyWest(sub(f, "LobbyWest"), refs) end },
        { "bouncer", function() self:_bouncer(sub(f, "Bouncer")) end },
        { "heist hall", function() self:_heistHall(sub(f, "HeistHall"), refs) end },
        { "polish", function() self:_polish(sub(f, "Polish")) end },
        { "intro path", function() self:_introPath(refs) end },
    }
    for _, s in ipairs(steps) do
        local ok, err = pcall(s[2])
        if not ok then warn("[ClubBuilder] " .. s[1] .. " failed: " .. tostring(err)) end
    end
    print("[ClubBuilder] The Vault is open 🪩")
    return refs
end

return ClubBuilder
