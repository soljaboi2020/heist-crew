--[[
    HEIST CREW — KenneyLoader
    ────────────────────────────────────────────────
    Puts Kenney props into the world from code. Added 2026-09-25.

    The models live on Roblox as Model assets (uploaded by
    tools/upload_kenney.py → ids in Shared.KenneyAssets). This:
      1. InsertService:LoadAsset(id)          (cached — each model loads once)
      2. scales it to its real size           (Shared.KenneyKit.SIZES, in studs)
      3. anchors it, sets it on the floor, turns it to face where asked
      4. restores colour the importer dropped (furniture kit: flat colours;
         factory kit: its texture atlas, uploaded as image 94958674308524)

    Every failure is a warn + skip, never an error: a prop that doesn't load
    must not stop the level from building.

    ⚠️ FRONT_YAW: which way a Kenney model "faces" after import isn't
    something I could verify without Studio. If furniture comes out facing the
    wall, flip FRONT_YAW between 0 and math.pi — one line fixes all of it.

    PUBLIC API:
        KenneyLoader.place(kit, name, position, facing, opts) -> Model | nil
            kit      : "furniture" | "factory"
            position : Vector3 — where the BOTTOM-CENTRE of the prop goes
            facing   : Vector3 direction the front should face (default -Z / north)
            opts.scale   : extra multiplier on top of the real size (default per kit)
            opts.parent  : Instance (default workspace)
            opts.collide : boolean (default true)
            opts.color / opts.material
                         : (v2.0.2) override the tint on this one copy. Only
                           touches parts the loader tinted itself (the plain
                           white ones) — a textured part is never repainted.
            opts.secondaryColor / opts.secondaryMaterial
                         : same, for the smaller "secondary" parts (legs,
                           frame, pot…) of a multi-part model
            opts.recolor : true = apply opts.color/material to EVERY part,
                           textured or not (rarely what you want)
        KenneyLoader.placeMany(list, parent)
            list items: { kit, name, pos, facing, opts } — also accepts
            item.color / item.material as a shorthand for opts.color/material.
        KenneyLoader.setStyle(name, style)       (v2.0.2)
            Register / replace the default look for a model name, e.g.
            KenneyLoader.setStyle("desk", { color = Color3.fromRGB(90,60,40),
                material = Enum.Material.WoodPlanks,
                secondary = { color = ..., material = ... } })
            Call BEFORE the first place() of that model (templates are cached).
        KenneyLoader.styleFor(kit, name) -> style  (what a model will get)

    (v2.0.2) WHY PROPS CAME OUT AS WHITE BLOCKS — Malachi, Future lighting:
    the importer drops Kenney's flat .mtl colours, so a model arrives as
    plain Plastic in white OR in Roblox's default grey (163,162,165). The
    old check only caught pure white (>0.94), so the grey ones — most of
    them — got nothing. Now ANY low-saturation plain Plastic part with no
    TextureID / SurfaceAppearance is "plain" and gets a real colour +
    Material from STYLES (by model name), largest part = primary, the rest =
    secondary. Factory models keep their texture atlas; the colour set under
    it is only a fallback that shows if the atlas image ever fails to load
    (a MeshPart's Color is hidden under an opaque TextureID).
--]]

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KenneyKit = require(ReplicatedStorage.Shared.KenneyKit)
local okAssets, KenneyAssets = pcall(require, ReplicatedStorage.Shared:WaitForChild("KenneyAssets", 5))
if not okAssets then
    warn("[KenneyLoader] Shared.KenneyAssets missing — props will be skipped:", KenneyAssets)
    KenneyAssets = {}
end

local KenneyLoader = {}

local FRONT_YAW = math.pi
local FACTORY_TEXTURE = "rbxassetid://94958674308524"

-- Roblox avatars are chunkier than real people; real-scale furniture reads
-- as doll-house next to them. These nudge it up a little.
local KIT_SCALE = { furniture = 1.25, factory = 1.0 }

local templates = {}   -- "kit/name" -> Model (never parented)
local loading = {}     -- "kit/name" -> true while a LoadAsset is in flight

-- ──────────────────────────────────────────────
-- 🎨 STYLES (v2.0.2) — the look a plain model gets, matched by model name.
-- First match wins, so specific patterns sit above general ones. `pattern`
-- is a plain, case-insensitive substring of the Kenney model name.
-- style = { color, material, transparency?, secondary = {color, material}?,
--           potBottom = true → the LOWEST part takes `secondary` (plants) }
-- ──────────────────────────────────────────────
local C = Color3.fromRGB
local Mat = Enum.Material

local WALNUT   = { color = C(92, 62, 42),   material = Mat.WoodPlanks }
local OAK      = { color = C(156, 116, 76), material = Mat.WoodPlanks }
local STEEL_LT = { color = C(206, 208, 212), material = Mat.Metal }
local STEEL_DK = { color = C(58, 60, 66),    material = Mat.Metal }
local SCREEN   = { color = C(30, 32, 38),    material = Mat.Metal }
local CHROME   = { color = C(170, 174, 182), material = Mat.Metal }
local CERAMIC  = { color = C(226, 224, 218), material = Mat.Marble }
local CARDBOARD= { color = C(176, 134, 88),  material = Mat.Cardboard }
local LEAVES   = { color = C(58, 104, 60),   material = Mat.LeafyGrass }
local TERRACOTTA = { color = C(168, 92, 62), material = Mat.Slate }

local function st(base, extra)
    local t = { color = base.color, material = base.material }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local STYLES = {
    -- ── kitchen + laundry appliances: light brushed metal, dark trim
    { "washer",        st(STEEL_LT, { secondary = STEEL_DK }) },
    { "dryer",         st(STEEL_LT, { secondary = STEEL_DK }) },
    { "fridge",        st(STEEL_LT, { secondary = STEEL_DK }) },
    { "microwave",     st(STEEL_DK, { secondary = STEEL_LT }) },
    { "stove",         st(STEEL_LT, { secondary = STEEL_DK }) },
    { "hood",          st(CHROME) },
    { "toaster",       st(CHROME, { secondary = STEEL_DK }) },
    { "blender",       st(STEEL_DK, { secondary = CHROME }) },
    { "coffeemachine", st(STEEL_DK, { secondary = CHROME }) },
    { "kitchensink",   st(CHROME, { secondary = WALNUT }) },
    -- ── electronics: near-black metal
    { "cabinettelevision", st(WALNUT, { secondary = SCREEN }) },
    { "cabinetbed",    st(WALNUT, { secondary = OAK }) },
    { "computerscreen", st(SCREEN, { secondary = STEEL_DK }) },
    { "laptop",        st(SCREEN, { secondary = CHROME }) },
    { "television",    st(SCREEN, { secondary = WALNUT }) },
    { "keyboard",      st(SCREEN) },
    { "mouse",         st(SCREEN) },
    { "radio",         { color = C(52, 44, 40), material = Mat.Leather, secondary = CHROME } },
    { "speaker",       { color = C(26, 26, 30), material = Mat.Fabric, secondary = STEEL_DK } },
    -- ── bathroom: ceramic
    { "toilet",        st(CERAMIC, { secondary = CHROME }) },
    { "bathtub",       st(CERAMIC, { secondary = CHROME }) },
    { "bathroomsink",  st(CERAMIC, { secondary = CHROME }) },
    { "shower",        st(CERAMIC, { secondary = CHROME }) },
    { "bathroommirror",{ color = C(190, 214, 224), material = Mat.Glass, secondary = CHROME } },
    { "bathroomcabinet", st(OAK, { secondary = CHROME }) },
    -- ── soft furniture: fabric seats on walnut / metal frames
    { "chairdesk",     { color = C(38, 40, 48), material = Mat.Fabric, secondary = STEEL_DK } },
    { "cushion",       { color = C(46, 86, 96), material = Mat.Fabric, secondary = WALNUT } },
    { "sofa",          { color = C(46, 86, 96), material = Mat.Fabric, secondary = WALNUT } },
    { "loungechair",   { color = C(120, 58, 52), material = Mat.Leather, secondary = WALNUT } },
    { "loungedesignchair", { color = C(120, 58, 52), material = Mat.Leather, secondary = CHROME } },
    { "ottoman",       { color = C(46, 86, 96), material = Mat.Fabric } },
    { "pillowblue",    { color = C(60, 92, 150), material = Mat.Fabric } },
    { "pillow",        { color = C(214, 204, 186), material = Mat.Fabric } },
    { "bed",           { color = C(214, 206, 192), material = Mat.Fabric, secondary = WALNUT } },
    { "bear",          { color = C(150, 105, 70), material = Mat.Fabric } },
    -- ── rugs
    { "doormat",       { color = C(84, 64, 44), material = Mat.Carpet } },
    { "rug",           { color = C(120, 36, 44), material = Mat.Carpet } },
    -- ── wood furniture
    { "bookcase",      st(WALNUT, { secondary = OAK }) },
    { "books",         { color = C(136, 46, 52), material = Mat.Fabric, secondary = { color = C(40, 70, 120), material = Mat.Fabric } } },
    { "desk",          st(WALNUT, { secondary = STEEL_DK }) },
    { "tablecoffeeglass", { color = C(150, 190, 200), material = Mat.Glass, transparency = 0.3, secondary = WALNUT } },
    { "tableglass",    { color = C(150, 190, 200), material = Mat.Glass, transparency = 0.3, secondary = CHROME } },
    { "tablecloth",    { color = C(226, 220, 206), material = Mat.Fabric, secondary = WALNUT } },
    { "table",         st(WALNUT, { secondary = OAK }) },
    { "cabinet",       st(OAK, { secondary = STEEL_DK }) },
    { "kitchenbar",    st(WALNUT, { secondary = CERAMIC }) },
    { "stool",         st(STEEL_DK, { secondary = { color = C(40, 36, 34), material = Mat.Leather } }) },
    { "chair",         st(OAK, { secondary = WALNUT }) },
    { "bench",         st(OAK, { secondary = STEEL_DK }) },
    { "coatrack",      st(WALNUT) },
    { "ceilingfan",    st(WALNUT, { secondary = CHROME }) },
    { "lamp",          { color = C(180, 140, 80), material = Mat.Metal, secondary = { color = C(236, 222, 190), material = Mat.Fabric } } },
    -- ── plants: leaves, with a terracotta pot at the bottom
    { "plant",         st(LEAVES, { secondary = TERRACOTTA, potBottom = true }) },
    -- ── boxes / crates
    { "cardboard",     st(CARDBOARD) },
    { "box",           st(CARDBOARD, { secondary = { color = C(150, 112, 72), material = Mat.Cardboard } }) },
    { "crate",         { color = C(150, 110, 72), material = Mat.WoodPlanks } },
    { "trashcan",      { color = C(62, 84, 76), material = Mat.Metal, secondary = STEEL_DK } },
    -- ── building bits
    { "paneling",      st(WALNUT) },
    { "stairs",        st(OAK, { secondary = STEEL_DK }) },
    { "floor",         st(OAK) },
    { "wall",          { color = C(200, 192, 180), material = Mat.Plaster } },
    { "doorway",       { color = C(200, 192, 180), material = Mat.Plaster, secondary = WALNUT } },
    -- ── factory kit (under its texture atlas — fallback only)
    { "cone",          { color = C(235, 110, 40), material = Mat.Plastic, secondary = { color = C(230, 230, 226), material = Mat.Plastic } } },
    { "warning",       { color = C(235, 180, 40), material = Mat.Metal, secondary = STEEL_DK } },
    { "conveyor",      st(STEEL_DK, { secondary = CHROME }) },
}
local GENERIC = { color = C(120, 118, 114), material = Mat.Metal, secondary = STEEL_DK }

local customStyles = {}   -- name -> style (setStyle)

local function styleFor(kit, name)
    if customStyles[name] then return customStyles[name] end
    local lname = string.lower(name)
    for _, entry in ipairs(STYLES) do
        if string.find(lname, entry[1], 1, true) then return entry[2] end
    end
    -- the kit's own dominant material, unless that's white too
    if kit == "furniture" then
        local matName = KenneyKit.FURNITURE_MATERIAL and KenneyKit.FURNITURE_MATERIAL[name]
        local e = matName and KenneyKit.MATERIALS and KenneyKit.MATERIALS[matName]
        if e then
            local _, sat, val = e.color:ToHSV()
            if sat > 0.12 or val < 0.8 then return { color = e.color, material = e.material } end
        end
    end
    return GENERIC
end

-- "Plain" = what the importer leaves behind when it drops the .mtl colour:
-- untextured, un-SurfaceAppearanced, Plastic, and white/grey (no hue).
local PLAIN_MATS = { [Mat.Plastic] = true, [Mat.SmoothPlastic] = true }
local function isPlain(p, ignoreTexture)
    if not PLAIN_MATS[p.Material] then return false end
    if p:FindFirstChildOfClass("SurfaceAppearance") then return false end
    if not ignoreTexture then
        if p:IsA("MeshPart") and p.TextureID ~= "" then return false end
        local sm = p:FindFirstChildOfClass("SpecialMesh")
        if sm and sm.TextureId ~= "" then return false end
    end
    local _, sat, val = p.Color:ToHSV()
    return sat < 0.12 and val > 0.5
end

local function paint(p, look)
    p.Color = look.color
    p.Material = look.material
    if look.transparency then p.Transparency = look.transparency end
end

-- Tint every plain part of a freshly loaded template. Largest part =
-- "primary", the rest = "secondary" (or the lowest = pot for plants).
-- Parts are tagged with attribute KenneyTint so place() overrides know
-- which ones are ours to repaint.
local function tintTemplate(model, kit, name)
    local style = styleFor(kit, name)
    local plain = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            -- factory: the atlas is (re)applied below, so judge by colour only
            if isPlain(d, kit == "factory") then table.insert(plain, d) end
        end
    end
    if #plain == 0 then return end
    local primary = plain[1]
    local lowest = plain[1]
    for _, p in ipairs(plain) do
        local v, pv = p.Size.X * p.Size.Y * p.Size.Z, primary.Size.X * primary.Size.Y * primary.Size.Z
        if v > pv then primary = p end
        if p.Position.Y - p.Size.Y / 2 < lowest.Position.Y - lowest.Size.Y / 2 then lowest = p end
    end
    local second = style.secondary or style
    for _, p in ipairs(plain) do
        local role
        if #plain == 1 then
            role = "primary"
        elseif style.potBottom then
            role = (p == lowest) and "secondary" or "primary"
        else
            role = (p == primary) and "primary" or "secondary"
        end
        -- a factory part keeps its texture: only the fallback colour changes
        if kit == "factory" then
            p.Color = (role == "primary") and style.color or second.color
        else
            paint(p, (role == "primary") and style or second)
        end
        p:SetAttribute("KenneyTint", role)
    end
end

-- Per-call overrides (opts.color / material / secondary* / recolor)
local function applyOverrides(model, opts)
    if not (opts.color or opts.material or opts.secondaryColor or opts.secondaryMaterial) then return end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            local role = d:GetAttribute("KenneyTint")
            if opts.recolor then role = role or "primary" end
            if role == "primary" then
                if opts.color then d.Color = opts.color end
                if opts.material then d.Material = opts.material end
            elseif role == "secondary" then
                if opts.secondaryColor then d.Color = opts.secondaryColor end
                if opts.secondaryMaterial then d.Material = opts.secondaryMaterial end
            end
        end
    end
end

function KenneyLoader.setStyle(name, style)
    customStyles[name] = style
end

function KenneyLoader.styleFor(kit, name)
    return styleFor(kit, name)
end

local function getTemplate(kit, name)
    local key = kit .. "/" .. name
    if templates[key] then return templates[key] end
    while loading[key] do task.wait(0.1) end
    if templates[key] then return templates[key] end

    local id = KenneyAssets[kit] and KenneyAssets[kit][name]
    if not id then
        warn("[KenneyLoader] no asset id for", key)
        return nil
    end

    loading[key] = true
    local ok, container = pcall(function() return InsertService:LoadAsset(id) end)
    loading[key] = nil
    if not ok or not container then
        warn("[KenneyLoader] LoadAsset failed for", key, id, container)
        return nil
    end

    -- LoadAsset wraps the asset in a Model; unwrap one level if that's all it is
    local model = container
    local kids = container:GetChildren()
    if #kids == 1 and kids[1]:IsA("Model") then
        model = kids[1]
        model.Parent = nil
    elseif #kids == 1 and kids[1]:IsA("BasePart") then
        model = Instance.new("Model")
        kids[1].Parent = model
    end

    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
        elseif d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()   -- our own uploads have none; belt and braces
        end
    end
    -- colour first (it reads the untouched import), then the factory atlas
    local okTint, tintErr = pcall(tintTemplate, model, kit, name)
    if not okTint then warn("[KenneyLoader] tint failed for", key, tintErr) end
    if kit == "factory" then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("MeshPart") and d.TextureID == "" then
                d.TextureID = FACTORY_TEXTURE
            end
        end
    end

    model.Name = name
    templates[key] = model
    return model
end

function KenneyLoader.place(kit, name, position, facing, opts)
    opts = opts or {}
    local template = getTemplate(kit, name)
    if not template then return nil end

    local model = template:Clone()

    -- 1. Size — match the real size's diagonal (robust to import axis swaps)
    local target = KenneyKit.SIZES[kit] and KenneyKit.SIZES[kit][name]
    local current = model:GetExtentsSize()
    if target and current.Magnitude > 0 then
        local factor = (target.Magnitude / current.Magnitude) * (opts.scale or KIT_SCALE[kit] or 1)
        pcall(function() model:ScaleTo(model:GetScale() * factor) end)
    end

    -- 2. Rotate to face `facing`, then drop so the bounding box sits on `position`
    facing = facing or Vector3.new(0, 0, -1)
    local yaw = math.atan2(-facing.X, -facing.Z) + FRONT_YAW
    model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
    local bbCf, bbSize = model:GetBoundingBox()
    local bottom = bbCf.Position.Y - bbSize.Y / 2
    local centre = bbCf.Position
    model:PivotTo(model:GetPivot() + Vector3.new(
        position.X - centre.X, position.Y - bottom, position.Z - centre.Z))

    applyOverrides(model, opts)

    if opts.collide == false then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide = false end
        end
    end

    model.Parent = opts.parent or workspace
    return model
end

-- Fire-and-forget batch: loads everything in parallel so a room of 30 props
-- doesn't take 30 sequential round trips.
function KenneyLoader.placeMany(list, parent)
    for _, item in ipairs(list) do
        task.spawn(function()
            local opts = item.opts or {}
            opts.parent = opts.parent or parent
            if item.color and opts.color == nil then opts.color = item.color end
            if item.material and opts.material == nil then opts.material = item.material end
            KenneyLoader.place(item.kit, item.name, item.pos, item.facing, opts)
        end)
    end
end

return KenneyLoader
