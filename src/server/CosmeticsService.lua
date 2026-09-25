--[[
    HEIST CREW — CosmeticsService
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25). Stuff you buy with heist cash that only changes
    how you LOOK. Three kinds:

      BAG SKINS   the colour / material of the loot bag on your back
      CAR COLORS  the getaway car's paint while YOU are in the driver seat
      TRAILS      a light streak behind you (club + heists, rebuilt every spawn)

    Every category has one free starter item you always own. Some items are
    VIP-only (need the VIP pass + the cash). The GOLD bag can't be bought: it's
    the day-7 daily reward (DailyRewardService calls :grant).

    The item list lives in COSMETICS below (NOT Constants.lua). ShopService reads
    it with :catalog() and sends it to the client in getState.

    SAVE DATA (PlayerDataService):
        cosmetics         = { [itemId] = true }            -- owned
        equippedCosmetics = { bag = id, car = id, trail = id }

    PLAYER ATTRIBUTES (replicate): BagSkin, CarColor, Trail  (equipped ids)

    PUBLIC API:
        CosmeticsService:init(PlayerDataService, EconomyService, notify)   -- safe to call twice
        CosmeticsService:onPlayerJoined(player)          -- attributes + trail (init hooks this itself)
        CosmeticsService:catalog() -> { item, ... }      -- plain data, safe to send to clients
        CosmeticsService:stateFor(player) -> { owned = {ids}, equipped = {bag, car, trail} }
        CosmeticsService:buy(player, id) -> ok, msg
        CosmeticsService:equip(player, id) -> ok, msg
        CosmeticsService:grant(player, id) -> bool        -- free unlock (rewards); false if already owned
        CosmeticsService:owns(player, id) -> bool
        CosmeticsService:styleBag(player, bagPart)        -- ★ CORE AGENT: call on every bag LootService makes
        CosmeticsService:carPaintFor(player) -> { color = Color3, material = Enum.Material, reflectance } | nil
        CosmeticsService:refreshTrail(player)

    ★ styleBag — LootService.makeBag() builds a Part "LootBag" (the dark sack)
      with a child Part "Strap" (coloured by loot kind). styleBag repaints ONLY
      the sack (Color, Material, Reflectance) so the strap still tells you what's
      inside. Safe to call with nil / a destroyed part / before init.
--]]

local Players = game:GetService("Players")

local CosmeticsService = {}

local PlayerData, Economy = nil, nil
local notify = function() end
local initialized = false

-- ── THE CATALOG ───────────────────────────────────────────────────────
-- category: "bag" | "car" | "trail"
-- price 0 + starter = true  → everybody owns it
-- vipOnly  → needs the VIP pass (and the cash)
-- rewardOnly → can't be bought (daily reward)
-- color / color2 = {r,g,b}. material = Enum.Material name. Trails use color → color2.
local COSMETICS = {
    -- BAG SKINS
    { id = "BagClassic",  category = "bag", name = "Classic Black", price = 0, starter = true,
      color = { 28, 30, 36 },    material = "Fabric",       blurb = "The old faithful" },
    { id = "BagCamo",     category = "bag", name = "Jungle Camo",   price = 500,
      color = { 86, 104, 60 },   material = "Fabric",       blurb = "Blend into the plants" },
    { id = "BagFlamingo", category = "bag", name = "Flamingo",      price = 1500,
      color = { 242, 120, 180 }, material = "Leather",      blurb = "Pink. Loud. Proud." },
    { id = "BagMint",     category = "bag", name = "Miami Mint",    price = 3500,
      color = { 120, 220, 190 }, material = "Leather",      blurb = "Fresh like the ocean" },
    { id = "BagSteel",    category = "bag", name = "Steel Case",    price = 7500,
      color = { 170, 176, 186 }, material = "DiamondPlate", reflectance = 0.1, blurb = "Nobody's opening this" },
    { id = "BagDiamond",  category = "bag", name = "Ice Diamond",   price = 15000, vipOnly = true,
      color = { 180, 230, 255 }, material = "Glass",        reflectance = 0.3, blurb = "VIP only. Pure ice." },
    { id = "BagGold",     category = "bag", name = "Solid Gold",    price = 0, rewardOnly = true,
      color = { 245, 190, 50 },  material = "Foil",         reflectance = 0.2, blurb = "Day 7 daily reward" },

    -- CAR COLORS (the getaway car body)
    { id = "CarClassic",  category = "car", name = "Vice White",    price = 0, starter = true,
      color = { 242, 242, 238 }, material = "SmoothPlastic", reflectance = 0.12, blurb = "Straight off the lot" },
    { id = "CarPink",     category = "car", name = "Hot Pink",      price = 1000,
      color = { 255, 90, 170 },  material = "SmoothPlastic", reflectance = 0.12, blurb = "Everyone will see you" },
    { id = "CarCyan",     category = "car", name = "Ocean Cyan",    price = 2500,
      color = { 60, 200, 235 },  material = "SmoothPlastic", reflectance = 0.12, blurb = "Cool as the sea" },
    { id = "CarSunset",   category = "car", name = "Sunset Orange", price = 5000,
      color = { 255, 140, 60 },  material = "SmoothPlastic", reflectance = 0.12, blurb = "Drive into the sunset" },
    { id = "CarMidnight", category = "car", name = "Midnight",      price = 9000,
      color = { 22, 24, 32 },    material = "SmoothPlastic", reflectance = 0.2,  blurb = "Hard to spot at night" },
    { id = "CarGold",     category = "car", name = "Gold Chrome",   price = 15000, vipOnly = true,
      color = { 230, 180, 60 },  material = "Metal",         reflectance = 0.25, blurb = "VIP only. Shine on." },

    -- TRAILS (behind your character)
    { id = "TrailNone",   category = "trail", name = "No Trail",    price = 0, starter = true,
      blurb = "Nice and sneaky" },
    { id = "TrailMint",   category = "trail", name = "Mint Streak", price = 750,
      color = { 150, 225, 200 }, color2 = { 40, 230, 255 },  blurb = "A cool green swoosh" },
    { id = "TrailPink",   category = "trail", name = "Pink Neon",   price = 2000,
      color = { 255, 70, 180 },  color2 = { 180, 90, 255 },  blurb = "Hot pink to purple" },
    { id = "TrailSunset", category = "trail", name = "Sunset",      price = 4500,
      color = { 255, 140, 60 },  color2 = { 255, 70, 180 },  blurb = "Orange into pink" },
    { id = "TrailCash",   category = "trail", name = "Money Trail", price = 8000,
      color = { 74, 222, 128 },  color2 = { 34, 197, 94 },   blurb = "Leave cash behind you" },
    { id = "TrailRainbow", category = "trail", name = "Rainbow",    price = 15000, vipOnly = true,
      color = { 255, 80, 80 },   color2 = { 80, 120, 255 },  rainbow = true, blurb = "VIP only. All the colors." },
}

local BY_ID = {}
local STARTER = {}   -- [category] = id
for _, item in ipairs(COSMETICS) do
    BY_ID[item.id] = item
    if item.starter then STARTER[item.category] = item.id end
end

local ATTR = { bag = "BagSkin", car = "CarColor", trail = "Trail" }

CosmeticsService.ITEMS = COSMETICS   -- read-only please
CosmeticsService.BY_ID = BY_ID

-- ── helpers ───────────────────────────────────────────────────────────
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function material(name)
    local ok, m = pcall(function() return (Enum.Material :: any)[name] end)
    return ok and m or Enum.Material.Fabric
end

local function dataFor(player)
    local d = PlayerData and PlayerData:getData(player)
    if not d then return nil end
    if type(d.cosmetics) ~= "table" then d.cosmetics = {} end
    if type(d.equippedCosmetics) ~= "table" then d.equippedCosmetics = {} end
    return d
end

local function isVIP(player)
    return player:GetAttribute("VIP") == true
end

local function ownsItem(d, item)
    return item.starter == true or d.cosmetics[item.id] == true
end

-- what's equipped in a category (falls back to the starter if the save is odd)
local function equippedId(player, category)
    local d = dataFor(player)
    local id = d and d.equippedCosmetics[category]
    local item = id and BY_ID[id]
    if not item or item.category ~= category or not ownsItem(d, item) then
        return STARTER[category]
    end
    -- VIP items need VIP to wear (the pass can't lapse, but be safe)
    if item.vipOnly and not isVIP(player) then return STARTER[category] end
    return id
end

local function syncAttributes(player)
    for category, attr in pairs(ATTR) do
        player:SetAttribute(attr, equippedId(player, category))
    end
end

-- ── trails ────────────────────────────────────────────────────────────
local TRAIL_NAME = "HC_Trail"

local function clearTrail(char)
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    for _, name in ipairs({ TRAIL_NAME, TRAIL_NAME .. "_A0", TRAIL_NAME .. "_A1" }) do
        local found = root:FindFirstChild(name)
        if found then found:Destroy() end
    end
end

function CosmeticsService:refreshTrail(player)
    local char = player and player.Character
    if not char then return end
    clearTrail(char)
    local item = BY_ID[equippedId(player, "trail")]
    if not item or not item.color then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local a0 = Instance.new("Attachment")
    a0.Name = TRAIL_NAME .. "_A0"
    a0.Position = Vector3.new(0, 0.9, 0.4)
    a0.Parent = root
    local a1 = Instance.new("Attachment")
    a1.Name = TRAIL_NAME .. "_A1"
    a1.Position = Vector3.new(0, -1.1, 0.4)
    a1.Parent = root

    local trail = Instance.new("Trail")
    trail.Name = TRAIL_NAME
    trail.Attachment0 = a0
    trail.Attachment1 = a1
    trail.Lifetime = 0.45
    trail.MinLength = 0.1
    trail.FaceCamera = true
    trail.LightEmission = 0.7
    trail.LightInfluence = 0.2
    trail.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 1),
    })
    trail.WidthScale = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0.2),
    })
    if item.rainbow then
        trail.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
            ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 60)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 230, 120)),
            ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 180, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 90, 255)),
        })
    else
        trail.Color = ColorSequence.new(rgb(item.color), rgb(item.color2 or item.color))
    end
    trail.Parent = root
end

local function hookCharacter(player)
    player.CharacterAdded:Connect(function(char)
        char:WaitForChild("HumanoidRootPart", 10)
        if player.Parent then CosmeticsService:refreshTrail(player) end
    end)
end

-- ── public: catalog / state ───────────────────────────────────────────
function CosmeticsService:catalog()
    local out = {}
    for i, item in ipairs(COSMETICS) do
        out[i] = {
            id = item.id, category = item.category, name = item.name, blurb = item.blurb or "",
            price = item.price or 0, starter = item.starter == true, vipOnly = item.vipOnly == true,
            rewardOnly = item.rewardOnly == true, rainbow = item.rainbow == true,
            color = item.color, color2 = item.color2, material = item.material,
        }
    end
    return out
end

function CosmeticsService:stateFor(player)
    local d = dataFor(player)
    local owned = {}
    if d then
        for _, item in ipairs(COSMETICS) do
            if ownsItem(d, item) then table.insert(owned, item.id) end
        end
    end
    return {
        owned = owned,
        equipped = {
            bag = equippedId(player, "bag"),
            car = equippedId(player, "car"),
            trail = equippedId(player, "trail"),
        },
    }
end

function CosmeticsService:owns(player, id)
    local d = dataFor(player)
    local item = BY_ID[id]
    return d ~= nil and item ~= nil and ownsItem(d, item)
end

-- ── public: buy / equip / grant ───────────────────────────────────────
function CosmeticsService:buy(player, id)
    local item = BY_ID[id]
    local d = dataFor(player)
    if not item or not d then return false, "Unknown item" end
    if ownsItem(d, item) then return false, "You already own that" end
    if item.rewardOnly then return false, "Get this from the day 7 daily reward!" end
    if item.vipOnly and not isVIP(player) then return false, "That one is VIP only" end
    if not Economy or not Economy:spend(player, item.price, "Cosmetic: " .. item.id) then
        return false, "Not enough cash"
    end
    d.cosmetics[item.id] = true
    d.equippedCosmetics[item.category] = item.id   -- buying = wearing it
    self:_applied(player, item.category)
    return true, item.name .. " equipped!"
end

function CosmeticsService:equip(player, id)
    local item = BY_ID[id]
    local d = dataFor(player)
    if not item or not d then return false, "Unknown item" end
    if not ownsItem(d, item) then return false, "You don't own that yet" end
    if item.vipOnly and not isVIP(player) then return false, "That one is VIP only" end
    d.equippedCosmetics[item.category] = item.id
    self:_applied(player, item.category)
    return true, item.name .. " equipped!"
end

function CosmeticsService:grant(player, id)
    local item = BY_ID[id]
    local d = dataFor(player)
    if not item or not d then return false end
    if ownsItem(d, item) then return false end
    d.cosmetics[item.id] = true
    d.equippedCosmetics[item.category] = item.id
    self:_applied(player, item.category)
    return true
end

-- live refresh after a change
function CosmeticsService:_applied(player, category)
    syncAttributes(player)
    if category == "trail" then
        self:refreshTrail(player)
    elseif category == "bag" then
        -- restyle a bag they're carrying right now
        local char = player.Character
        local bag = char and char:FindFirstChild("LootBag")
        if bag then self:styleBag(player, bag) end
    elseif category == "car" then
        -- repaint the getaway car if they're driving it right now
        local ok, Vehicle = pcall(require, script.Parent:FindFirstChild("VehicleService"))
        if ok and type(Vehicle) == "table" and Vehicle.refreshPaint then
            pcall(function() Vehicle:refreshPaint() end)
        end
    end
end

-- ── public: styling hooks ─────────────────────────────────────────────
function CosmeticsService:styleBag(player, bag)
    if not bag or typeof(bag) ~= "Instance" or not bag:IsA("BasePart") then return end
    if not player or not player:IsA("Player") then return end
    local item = BY_ID[equippedId(player, "bag")]
    if not item or not item.color then return end
    bag.Color = rgb(item.color)
    bag.Material = material(item.material or "Fabric")
    bag.Reflectance = item.reflectance or 0
    bag:SetAttribute("Skin", item.id)
end

function CosmeticsService:carPaintFor(player)
    if not player then return nil end
    local item = BY_ID[equippedId(player, "car")]
    if not item or not item.color then return nil end
    return {
        id = item.id,
        color = rgb(item.color),
        material = material(item.material or "SmoothPlastic"),
        reflectance = item.reflectance or 0.12,
    }
end

-- ── lifecycle ─────────────────────────────────────────────────────────
function CosmeticsService:onPlayerJoined(player)
    syncAttributes(player)
    if player.Character then self:refreshTrail(player) end
end

function CosmeticsService:init(playerDataService, economyService, notifyFn)
    PlayerData = playerDataService or PlayerData
    Economy = economyService or Economy
    notify = notifyFn or notify
    if initialized then return end
    initialized = true

    local function added(player)
        hookCharacter(player)
        -- VIP can flip on mid-session (pass bought) — refresh what's wearable
        player:GetAttributeChangedSignal("VIP"):Connect(function()
            syncAttributes(player)
            self:refreshTrail(player)
        end)
        -- PlayerDataService loads on join (it can yield) — wait for the data
        task.spawn(function()
            local t0 = os.clock()
            while player.Parent and not (PlayerData and PlayerData:getData(player)) and os.clock() - t0 < 30 do
                task.wait(0.5)
            end
            if player.Parent then self:onPlayerJoined(player) end
        end)
    end
    Players.PlayerAdded:Connect(added)
    for _, p in ipairs(Players:GetPlayers()) do added(p) end


    print("[CosmeticsService] Bag skins, car colors + trails online")
end

return CosmeticsService
