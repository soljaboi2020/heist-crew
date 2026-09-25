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

local function nearWhite(c)
    return c.R > 0.94 and c.G > 0.94 and c.B > 0.94
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
            if d:IsA("MeshPart") then
                if kit == "factory" and d.TextureID == "" then
                    d.TextureID = FACTORY_TEXTURE
                end
                if kit == "furniture" and d.TextureID == "" and nearWhite(d.Color) then
                    KenneyKit.applyColor(d, name)
                end
            end
        elseif d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()   -- our own uploads have none; belt and braces
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
            KenneyLoader.place(item.kit, item.name, item.pos, item.facing, opts)
        end)
    end
end

return KenneyLoader
