--[[
    HEIST CREW — CosmeticsService
    ────────────────────────────────────────────────
    v2.0 "BIGGER" (2026-09-25) — v2.2 "GEAR THAT DOES STUFF" (2026-09-25).
    Stuff you buy with heist cash. Like the masks, EVERY item now DOES
    something (Malachi: "cosmetics that actually do something"):

      CARS    real getaway car TYPES (VehicleService builds a different model
              for each). Colour is folded into the type — no separate paint.
              (v3.0: nobody drives — cars PAY instead of going faster. The
               bonus comes from VehicleService.GETAWAY_BONUS; loud escape = full,
               sneaky = half, Highway = x2. The stunt is what it does in the movie.)
                Classic        free      +0%   dodges the cops
                Muscle Car     $8,000    +5%   nitro burst
                Street Racer   $20,000   +8%   leaves the cops in the dust
                Armored Truck  $35,000   +8%   cops bounce off
                Monster Truck  $60,000   +10%  jumps a police car
                Tank           $150,000  +12%  VIP only. smashes the roadblock
              (speedMult / bustMult / nitroCooldown are kept for old saves and
               the dormant driving code; nothing reads them while DRIVING = false)
              WHICH CAR SPAWNS: the crew's BEST car = the most expensive car
              anyone in the crew has equipped (ties → the first player in the
              crew list). In the club the preview car uses everyone in the
              server. VehicleService:chooseForCrew(players) locks it at the
              drop-in; it unlocks when the car resets after the run.
      TRAILS  a light streak behind you + a WALK SPEED boost, everywhere
              (club + heists). In price order: No Trail +2% · Mint +4% · Pink
              +6% · Sunset +8% · Money +10% · Rainbow (VIP) +12%.
              Stacks with Fox Speed multiplicatively; crouch still caps at 8
              (FeelService). Attribute TrailSpeedMult; LootService owns the
              actual WalkSpeed maths (LootService:refreshWalkSpeed).
      BAGS    bag TIERS: each bag you load into the car is worth more.
                Starter 1.0x · Duffel +10% · Sports +20% · Pro Heist +35%
                · Solid Gold (day-7 reward) +50% · Ice Diamond (VIP) +50%
              The tier that pays is the bag the loot was IN when it went into
              the trunk: your bag on your back, or YOUR bag on a bot's back
              (bots keep the owner's bonus). A thrown bag someone else picks up
              goes into THEIR bag. Bigger tiers are physically bigger.

    Every category has one free starter item you always own. Some items are
    VIP-only (need the VIP pass + the cash). The GOLD bag can't be bought: it's
    the day-7 daily reward (DailyRewardService calls :grant).

    The item list lives in COSMETICS below (NOT Constants.lua). ShopService reads
    it with :catalog() and sends it to the client in getState. Every item has
    power = { name, desc } (the pill + one line on its shop card).

    SAVE DATA (PlayerDataService):
        cosmetics         = { [itemId] = true }            -- owned
        equippedCosmetics = { bag = id, car = id, trail = id }
      v2.2 MIGRATION (runs on every read, idempotent): old ids map to new ones
      (MIGRATE below) so nobody loses a paid item — old car PAINTS become the
      Muscle Car (the $15k VIP Gold Chrome paint → Street Racer); old bag skins
      become the nearest tier up. Unknown ids fall back to the starter.

    PLAYER ATTRIBUTES (replicate): BagSkin, CarType, Trail (equipped ids),
        TrailSpeedMult (number, 1 + boost), BagValueMult (number)

    PUBLIC API:
        CosmeticsService:init(PlayerDataService, EconomyService, notify)   -- safe to call twice
        CosmeticsService:onPlayerJoined(player)          -- attributes + trail (init hooks this itself)
        CosmeticsService:catalog() -> { item, ... }      -- plain data, safe to send to clients
        CosmeticsService:stateFor(player) -> { owned = {ids}, equipped = {bag, car, trail} }
        CosmeticsService:buy(player, id) -> ok, msg
        CosmeticsService:equip(player, id) -> ok, msg
        CosmeticsService:grant(player, id) -> bool        -- free unlock (rewards); false if already owned
        CosmeticsService:owns(player, id) -> bool
        CosmeticsService:styleBag(player, bagPart)        -- LootService calls it on every bag it makes
        CosmeticsService:refreshTrail(player)
      v2.2 gear powers:
        CosmeticsService:carStats(id) -> { id, name, carType, speedMult, bustMult, nitroCooldown, perk }
        CosmeticsService:carFor(player) -> id            -- equipped car id (starter fallback)
        CosmeticsService:pickCrewCar(players) -> id      -- the crew's best (see CARS above)
        CosmeticsService:trailSpeedMult(player) -> number  -- 1.02 .. 1.12
        CosmeticsService:bagTier(player) -> { id, name, valueMult, scale }
        CosmeticsService:carPaintFor(player) -> nil      -- (retired, kept so old callers don't break)
--]]

local Players = game:GetService("Players")

local CosmeticsService = {}

local PlayerData, Economy = nil, nil
local notify = function() end
local initialized = false

-- ── THE CATALOG ───────────────────────────────────────────────────────
-- category: "bag" | "car" | "trail"   (listed cheapest → priciest per category)
-- price 0 + starter = true  → everybody owns it
-- vipOnly  → needs the VIP pass (and the cash)
-- rewardOnly → can't be bought (daily reward)
-- color / color2 = {r,g,b}. material = Enum.Material name. Trails use color → color2.
-- power = { name = pill text, desc = one line }  (shown on the shop card)
--   cars:   carType (VehicleService model), speedMult, bustMult, nitroCooldown
--   trails: speedBoost (0.02 = +2% walk speed)
--   bags:   valueMult (cash per loaded bag), scale (how big it looks), size (label)
local COSMETICS = {
    -- BAGS (tiers)
    { id = "BagClassic",  category = "bag", name = "Starter Bag",   price = 0, starter = true,
      color = { 28, 30, 36 },    material = "Fabric",  valueMult = 1.00, scale = 1.00, size = "S",
      power = { name = "NORMAL CASH", desc = "Every bag pays its normal price" },
      blurb = "The old faithful" },
    { id = "BagDuffel",   category = "bag", name = "Duffel Bag",    price = 3000,
      color = { 86, 104, 60 },   material = "Fabric",  valueMult = 1.10, scale = 1.10, size = "M",
      power = { name = "+10% CASH", desc = "Bags you load pay 10% more" },
      blurb = "Roomier. Pays more." },
    { id = "BagSports",   category = "bag", name = "Sports Bag",    price = 10000,
      color = { 60, 140, 235 },  material = "Leather", valueMult = 1.20, scale = 1.20, size = "L",
      power = { name = "+20% CASH", desc = "Bags you load pay 20% more" },
      blurb = "Big gym bag, big money" },
    { id = "BagPro",      category = "bag", name = "Pro Heist Bag", price = 30000,
      color = { 200, 40, 60 },   material = "Leather", valueMult = 1.35, scale = 1.30, size = "XL",
      power = { name = "+35% CASH", desc = "Bags you load pay 35% more" },
      blurb = "What the pros carry" },
    { id = "BagGold",     category = "bag", name = "Solid Gold",    price = 0, rewardOnly = true,
      color = { 245, 190, 50 },  material = "Foil", reflectance = 0.2, valueMult = 1.50, scale = 1.40, size = "XXL",
      power = { name = "+50% CASH", desc = "Bags you load pay 50% more" },
      blurb = "Day 7 daily reward" },
    { id = "BagDiamond",  category = "bag", name = "Ice Diamond",   price = 40000, vipOnly = true,
      color = { 180, 230, 255 }, material = "Glass", reflectance = 0.3, valueMult = 1.50, scale = 1.40, size = "XXL",
      power = { name = "+50% CASH", desc = "Bags you load pay 50% more" },
      blurb = "VIP only. Pure ice." },

    -- CARS (real getaway car types — VehicleService builds each one)
    { id = "CarClassic",  category = "car", name = "Classic",       price = 0, starter = true,
      carType = "classic", color = { 242, 242, 238 }, speedMult = 1.00, bustMult = 1.00, nitroCooldown = 12,
      power = { name = "ALL-ROUNDER", desc = "Dodges the cops. Gets the job done." },
      blurb = "The trusty Miami wedge" },
    { id = "CarMuscle",   category = "car", name = "Muscle Car",    price = 8000,
      carType = "muscle", color = { 214, 58, 34 }, speedMult = 1.15, bustMult = 1.00, nitroCooldown = 7,
      power = { name = "+5% ESCAPE CASH", desc = "Nitro burst past the cops!" },
      blurb = "Loud engine, big nitro" },
    { id = "CarRacer",    category = "car", name = "Street Racer",  price = 20000,
      carType = "racer", color = { 255, 196, 20 }, speedMult = 1.35, bustMult = 1.00, nitroCooldown = 12,
      power = { name = "+8% ESCAPE CASH", desc = "Leaves the cops in the dust!" },
      blurb = "Low, wide supercar" },
    { id = "CarArmored",  category = "car", name = "Armored Truck", price = 35000,
      carType = "armored", color = { 92, 98, 104 }, speedMult = 1.00, bustMult = 0.50, nitroCooldown = 12,
      power = { name = "+8% ESCAPE CASH", desc = "Cops bounce right off it!" },
      blurb = "Steel plates everywhere" },
    { id = "CarMonster",  category = "car", name = "Monster Truck", price = 60000,
      carType = "monster", color = { 40, 170, 90 }, speedMult = 1.20, bustMult = 0.70, nitroCooldown = 12,
      power = { name = "+10% ESCAPE CASH", desc = "Jumps right over a police car!" },
      blurb = "Giant wheels. Giant fun." },
    { id = "CarTank",     category = "car", name = "Tank",          price = 150000, vipOnly = true,
      carType = "tank", color = { 96, 110, 66 }, speedMult = 0.85, bustMult = 0.25, nitroCooldown = 12,
      power = { name = "+12% ESCAPE CASH", desc = "Smashes through the roadblock!" },
      blurb = "VIP only. It's a TANK." },

    -- TRAILS (behind your character + walk speed)
    { id = "TrailNone",   category = "trail", name = "No Trail",    price = 0, starter = true, speedBoost = 0.02,
      power = { name = "+2% SPEED", desc = "A tiny bit faster. Nice and sneaky." },
      blurb = "Nice and sneaky" },
    { id = "TrailMint",   category = "trail", name = "Mint Streak", price = 750, speedBoost = 0.04,
      color = { 150, 225, 200 }, color2 = { 40, 230, 255 },
      power = { name = "+4% SPEED", desc = "You walk and run 4% faster" },
      blurb = "A cool green swoosh" },
    { id = "TrailPink",   category = "trail", name = "Pink Neon",   price = 2000, speedBoost = 0.06,
      color = { 255, 70, 180 },  color2 = { 180, 90, 255 },
      power = { name = "+6% SPEED", desc = "You walk and run 6% faster" },
      blurb = "Hot pink to purple" },
    { id = "TrailSunset", category = "trail", name = "Sunset",      price = 4500, speedBoost = 0.08,
      color = { 255, 140, 60 },  color2 = { 255, 70, 180 },
      power = { name = "+8% SPEED", desc = "You walk and run 8% faster" },
      blurb = "Orange into pink" },
    { id = "TrailCash",   category = "trail", name = "Money Trail", price = 8000, speedBoost = 0.10,
      color = { 74, 222, 128 },  color2 = { 34, 197, 94 },
      power = { name = "+10% SPEED", desc = "You walk and run 10% faster" },
      blurb = "Leave cash behind you" },
    { id = "TrailRainbow", category = "trail", name = "Rainbow",    price = 15000, vipOnly = true, speedBoost = 0.12,
      color = { 255, 80, 80 },   color2 = { 80, 120, 255 },  rainbow = true,
      power = { name = "+12% SPEED", desc = "VIP only. The fastest trail." },
      blurb = "VIP only. All the colors." },
}

-- v2.2 save migration: old id → new id (never lose a paid item)
local MIGRATE = {
    -- v2.0 car PAINTS → the first real car (the VIP gold paint → the racer)
    CarPink = "CarMuscle", CarCyan = "CarMuscle", CarSunset = "CarMuscle", CarMidnight = "CarMuscle",
    CarGold = "CarRacer",
    -- v2.0 bag skins → the nearest bag tier up
    BagCamo = "BagDuffel", BagFlamingo = "BagDuffel", BagMint = "BagSports", BagSteel = "BagSports",
}
CosmeticsService.MIGRATE = MIGRATE

local BY_ID = {}
local STARTER = {}   -- [category] = id
for _, item in ipairs(COSMETICS) do
    BY_ID[item.id] = item
    if item.starter then STARTER[item.category] = item.id end
end

local ATTR = { bag = "BagSkin", car = "CarType", trail = "Trail" }

CosmeticsService.ITEMS = COSMETICS   -- read-only please
CosmeticsService.BY_ID = BY_ID

-- ── helpers ───────────────────────────────────────────────────────────
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function material(name)
    local ok, m = pcall(function() return (Enum.Material :: any)[name] end)
    return ok and m or Enum.Material.Fabric
end

-- optional sibling services, looked up lazily (no require cycles at load time)
local optionalCache = {}
local function optionalService(name)
    if optionalCache[name] ~= nil then return optionalCache[name] or nil end
    local mod = script.Parent and script.Parent:FindFirstChild(name)
    local ok, result = false, nil
    if mod then ok, result = pcall(require, mod) end
    optionalCache[name] = (ok and type(result) == "table") and result or false
    return optionalCache[name] or nil
end

-- v2.2: map retired ids to their replacements, in place. Idempotent.
local function migrateSave(d)
    for old, new in pairs(MIGRATE) do
        if d.cosmetics[old] then
            d.cosmetics[old] = nil
            if BY_ID[new] and not BY_ID[new].starter then d.cosmetics[new] = true end
        end
    end
    for cat, id in pairs(d.equippedCosmetics) do
        local new = MIGRATE[id]
        if new then
            d.equippedCosmetics[cat] = new
        elseif type(id) ~= "string" or not BY_ID[id] or BY_ID[id].category ~= cat then
            d.equippedCosmetics[cat] = nil   -- unknown → starter (equippedId falls back)
        end
    end
end

local function dataFor(player)
    local d = PlayerData and PlayerData:getData(player)
    if not d then return nil end
    if type(d.cosmetics) ~= "table" then d.cosmetics = {} end
    if type(d.equippedCosmetics) ~= "table" then d.equippedCosmetics = {} end
    migrateSave(d)   -- idempotent + cheap (a dozen table reads)
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

-- ── walk speed (trails) ───────────────────────────────────────────────
function CosmeticsService:trailSpeedMult(player)
    if not player then return 1 end
    local item = BY_ID[equippedId(player, "trail")]
    return 1 + ((item and tonumber(item.speedBoost)) or 0)
end

-- LootService owns WalkSpeed (bag / no bag, Sneakers, SpeedMult, TrailSpeedMult)
local function refreshWalkSpeed(player)
    local Loot = optionalService("LootService")
    if Loot and type(Loot.refreshWalkSpeed) == "function" then
        local ok, err = pcall(Loot.refreshWalkSpeed, Loot, player)
        if not ok then warn("[CosmeticsService] refreshWalkSpeed:", err) end
    end
end

-- ── bags ──────────────────────────────────────────────────────────────
function CosmeticsService:bagTier(player)
    local item = player and BY_ID[equippedId(player, "bag")] or BY_ID[STARTER.bag]
    return {
        id = item.id, name = item.name,
        valueMult = tonumber(item.valueMult) or 1,
        scale = tonumber(item.scale) or 1,
    }
end

-- ── cars ──────────────────────────────────────────────────────────────
function CosmeticsService:carStats(id)
    local item = BY_ID[id]
    if not item or item.category ~= "car" then item = BY_ID[STARTER.car] end
    return {
        id = item.id, name = item.name, carType = item.carType or "classic",
        speedMult = tonumber(item.speedMult) or 1, bustMult = tonumber(item.bustMult) or 1,
        nitroCooldown = tonumber(item.nitroCooldown) or 12,
        perk = item.power and item.power.name or "",
        color = item.color and rgb(item.color) or nil,
    }
end

function CosmeticsService:carFor(player)
    if not player then return STARTER.car end
    return equippedId(player, "car")
end

-- the crew's best car: the priciest equipped one (ties → first in the list)
function CosmeticsService:pickCrewCar(players)
    local best, bestPrice = STARTER.car, -1
    for _, p in ipairs(players or {}) do
        if typeof(p) == "Instance" and p:IsA("Player") and p.Parent then
            local id = equippedId(p, "car")
            local item = BY_ID[id]
            local price = item and (item.price or 0) or 0
            if price > bestPrice then best, bestPrice = id, price end
        end
    end
    return best
end

local function syncAttributes(player)
    for category, attr in pairs(ATTR) do
        player:SetAttribute(attr, equippedId(player, category))
    end
    local tsm = CosmeticsService:trailSpeedMult(player)
    player:SetAttribute("TrailSpeedMult", tsm ~= 1 and tsm or nil)
    local tier = CosmeticsService:bagTier(player)
    player:SetAttribute("BagValueMult", tier.valueMult)
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
        -- trail speed: init.server (Sneakers, 0.5 s) and MaskService (Fox, 0.8 s)
        -- write WalkSpeed after a respawn without the trail; land ours after them
        task.delay(1.2, function()
            if player.Parent and player.Character == char then refreshWalkSpeed(player) end
        end)
    end)
    -- MaskService writes WalkSpeed right after it flips SpeedMult (Fox on/off)
    -- without the trail factor → re-apply the full number once it's done
    player:GetAttributeChangedSignal("SpeedMult"):Connect(function()
        task.defer(function()
            if player.Parent then refreshWalkSpeed(player) end
        end)
    end)
end

-- (v3.0 polish) a car card's power, straight from VehicleService's getaway
-- numbers so the shop can never drift from what the payout actually pays
local function carPower(item)
    local V = optionalService("VehicleService")
    if not V or type(V.GETAWAY_BONUS) ~= "table" then return item.power end
    local b = tonumber(V.GETAWAY_BONUS[item.carType or "classic"]) or 0
    local desc = (type(V.stuntFor) == "function" and V.stuntFor(item.carType)) or (item.power and item.power.desc) or ""
    local name = b > 0 and string.format("+%d%% ESCAPE CASH", math.floor(b * 100 + 0.5)) or "ALL-ROUNDER"
    return { name = name, desc = desc }
end

-- ── public: catalog / state ───────────────────────────────────────────
function CosmeticsService:catalog()
    local out = {}
    for i, item in ipairs(COSMETICS) do
        local power = item.category == "car" and carPower(item) or item.power
        out[i] = {
            id = item.id, category = item.category, name = item.name, blurb = item.blurb or "",
            price = item.price or 0, starter = item.starter == true, vipOnly = item.vipOnly == true,
            rewardOnly = item.rewardOnly == true, rainbow = item.rainbow == true,
            color = item.color, color2 = item.color2, material = item.material, reflectance = item.reflectance,
            -- v2.2 powers
            power = power and { name = power.name, desc = power.desc } or nil,
            carType = item.carType, speedMult = item.speedMult, bustMult = item.bustMult,
            nitroCooldown = item.nitroCooldown, speedBoost = item.speedBoost,
            valueMult = item.valueMult, scale = item.scale, size = item.size,
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
    id = MIGRATE[id] or id
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
    id = MIGRATE[id] or id
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
    id = MIGRATE[id] or id
    local item = BY_ID[id]
    local d = dataFor(player)
    if not item or not d then return false end
    if ownsItem(d, item) then return false end
    d.cosmetics[item.id] = true
    d.equippedCosmetics[item.category] = item.id
    self:_applied(player, item.category)
    return true
end

local function refreshLobbyCar()
    local Vehicle = optionalService("VehicleService")
    if Vehicle and type(Vehicle.refreshType) == "function" then
        local ok, err = pcall(Vehicle.refreshType, Vehicle)
        if not ok then warn("[CosmeticsService] refreshType:", err) end
    end
end

-- live refresh after a change
function CosmeticsService:_applied(player, category)
    syncAttributes(player)
    if category == "trail" then
        self:refreshTrail(player)
        refreshWalkSpeed(player)
    elseif category == "bag" then
        -- rebuild a bag they're carrying right now (new size + look)
        local Loot = optionalService("LootService")
        if Loot and type(Loot.refreshCarriedBag) == "function" then
            pcall(Loot.refreshCarriedBag, Loot, player)
        else
            local char = player.Character
            local bag = char and char:FindFirstChild("LootBag")
            if bag then self:styleBag(player, bag) end
        end
    elseif category == "car" then
        -- the club's getaway car shows the crew's best car (never mid-run)
        refreshLobbyCar()
    end
end

-- ── public: styling hooks ─────────────────────────────────────────────
-- paints the sack (size is LootService's job: makeBag(kind, cf, scale))
function CosmeticsService:styleBag(player, bag)
    if not bag or typeof(bag) ~= "Instance" or not bag:IsA("BasePart") then return end
    if not player or not player:IsA("Player") then return end
    local item = BY_ID[equippedId(player, "bag")]
    if not item or not item.color then return end
    bag.Color = rgb(item.color)
    bag.Material = material(item.material or "Fabric")
    bag.Reflectance = item.reflectance or 0
    bag:SetAttribute("Skin", item.id)
    bag:SetAttribute("ValueMult", tonumber(item.valueMult) or 1)
end

-- (retired in v2.2: colour is part of each car type now)
function CosmeticsService:carPaintFor(_player)
    return nil
end

-- ── lifecycle ─────────────────────────────────────────────────────────
function CosmeticsService:onPlayerJoined(player)
    syncAttributes(player)
    if player.Character then
        self:refreshTrail(player)
        refreshWalkSpeed(player)
    end
    refreshLobbyCar()
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
            refreshWalkSpeed(player)
            refreshLobbyCar()
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
    Players.PlayerRemoving:Connect(function()
        task.defer(refreshLobbyCar)
    end)

    print("[CosmeticsService] Bag tiers, car types + speed trails online")
end

return CosmeticsService
