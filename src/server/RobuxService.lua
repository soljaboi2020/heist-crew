--[[
    HEIST CREW — RobuxService  (v2.0, masks + robux agent)
    ────────────────────────────────────────────────
    Robux → in-game cash packs (Developer Products). Constants.ROBUX_PACKS:
        small  $5,000    for 25 R$      medium $30,000  for 99 R$
        large  $100,000  for 249 R$     huge   $500,000 for 799 R$
    A pack with productId = 0 is NOT for sale (the shop greys it out and
    buyRobuxPack refuses). Nothing here does anything until the ids are pasted in.

    ═══ HOW MALACHI TURNS THE PACKS ON (once, ~5 minutes) ═══
      1. The game must be PUBLISHED (File → Publish to Roblox in Studio).
      2. Go to https://create.roblox.com/dashboard/creations → click Heist Crew.
      3. Left menu: Monetization → Developer Products → "Create a Developer Product".
      4. Make 4 products (name / price in Robux / an icon if you want):
           "Pocket Cash  — $5,000"    25
           "Bag of Cash  — $30,000"   99
           "Cash Stack   — $100,000"  249
           "Money Truck  — $500,000"  799
      5. After saving each one, copy its Product ID (the long number on the
         product's row / "Copy Asset ID" in the ⋯ menu).
      6. Paste each id into src/shared/Constants.lua → Constants.ROBUX_PACKS,
         replacing the matching `productId = 0`. Save — Rojo syncs it.
      7. Test in Studio: purchases there are FREE test purchases (no real Robux),
         so buy one and check the cash goes up and the Output says "granted".
      ⚠️ Only ONE script in the whole game may set MarketplaceService.ProcessReceipt.
         This is it. Any future dev product (e.g. a "getaway boost") gets added to
         the `handlers` below — never a second ProcessReceipt.

    ═══ WHY THE RECEIPT CODE LOOKS PARANOID ═══
    Roblox calls ProcessReceipt until we answer PurchaseGranted — it can call it
    again for the same purchase (server crash, rejoin, a second server). So:
      • IDEMPOTENT per PurchaseId: granted ids are saved in the player's own save
        (`robuxPurchases[purchaseId] = unix time`). A repeat receipt for a saved id
        just answers PurchaseGranted and gives nothing.
      • The player's save must be LOADED and healthy (PlayerDataService:isReady)
        — otherwise NotProcessedYet and Roblox retries later (next join).
      • Cash is added, then the save is written IMMEDIATELY; PurchaseGranted is
        returned only if that write SUCCEEDED. If it fails we answer
        NotProcessedYet — the id is already in memory, so the retry won't pay
        twice; it just tries to save again.
      • Two receipts for the same id at the same moment: the second one waits
        (NotProcessedYet) while the first is in flight.
      • Unknown product id / player not in this server → NotProcessedYet (never
        "granted" for something we didn't give).

    SAVING: prefers PlayerDataService:savePlayer(player) if it returns true/false.
    The current savePlayer returns nothing, so we fall back to writing the same
    cache table to the same DataStore key ourselves (store name below MUST match
    PlayerDataService's STORE_NAME). In Studio with no DataStore access we grant
    anyway (test purchases are free) and warn.

    Save field added: robuxPurchases = { [purchaseId] = unixTime } (pruned to the
    newest 200 — Roblox only re-sends recent receipts).

    PUBLIC API:
        RobuxService:init({ data = PlayerDataService, economy = EconomyService, notify = fn?, feel = FeelService? })
        RobuxService:packFor(productId) -> pack | nil
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local RobuxService = {}

-- ⚠️ must equal STORE_NAME in PlayerDataService.lua (fallback save path only)
local STORE_NAME = "HeistCrewPlayerData_v1"
local KEEP_PURCHASES = 200

local Data, Economy, Feel = nil, nil, nil
local notify = function() end
local inFlight = {}        -- [purchaseId] = true while a receipt is being processed
local started = false

local fallbackStore, fallbackTried = nil, false
local function getFallbackStore()
    if fallbackTried then return fallbackStore end
    fallbackTried = true
    local ok, s = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
    fallbackStore = ok and s or nil
    return fallbackStore
end

local function money(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return "$" .. out:gsub("^,", "")
end

function RobuxService:packFor(productId)
    productId = tonumber(productId)
    if not productId or productId == 0 then return nil end
    for _, pk in ipairs(Constants.ROBUX_PACKS or {}) do
        if tonumber(pk.productId) == productId then return pk end
    end
    return nil
end

-- keep the purchase list from growing forever (oldest dropped first)
local function prune(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    if n <= KEEP_PURCHASES then return end
    local rows = {}
    for id, t in pairs(list) do table.insert(rows, { id = id, t = tonumber(t) or 0 }) end
    table.sort(rows, function(a, b) return a.t > b.t end)
    for i = KEEP_PURCHASES + 1, #rows do list[rows[i].id] = nil end
end

-- true only if the player's save is confirmed written
local function saveNow(player)
    if Data and type(Data.savePlayer) == "function" then
        local ok, result = pcall(Data.savePlayer, Data, player)
        if ok and type(result) == "boolean" then return result end
        -- savePlayer returned nothing: we can't tell if it worked → write it ourselves
    end
    local d = Data and Data:getData(player)
    if not d then return false end
    local store = getFallbackStore()
    if not store then
        if RunService:IsStudio() then
            warn("[RobuxService] no DataStore in Studio — granting the test purchase without saving")
            return true
        end
        return false
    end
    for attempt = 1, 3 do
        local ok, err = pcall(function() store:SetAsync("Player_" .. player.UserId, d) end)
        if ok then return true end
        warn(string.format("[RobuxService] save attempt %d failed for %s: %s", attempt, player.Name, tostring(err)))
        if attempt < 3 then task.wait(attempt) end
    end
    if RunService:IsStudio() then
        warn("[RobuxService] save failed in Studio (API access off?) — granting the test purchase anyway")
        return true
    end
    return false
end

-- ── the receipt handler ──────────────────────────────────────────────
local function processReceipt(receipt)
    local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
    local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted

    local purchaseId = tostring(receipt.PurchaseId)
    local pack = RobuxService:packFor(receipt.ProductId)
    if not pack then
        warn("[RobuxService] receipt for unknown product " .. tostring(receipt.ProductId) .. " — not granted")
        return NOT_YET
    end
    local player = Players:GetPlayerByUserId(receipt.PlayerId)
    if not player then return NOT_YET end                       -- not in this server: retried on rejoin
    if not Data or not Economy then return NOT_YET end
    if type(Data.isReady) == "function" and not Data:isReady(player) then
        return NOT_YET                                          -- save not loaded / load failed
    end
    local d = Data:getData(player)
    if not d then return NOT_YET end
    if inFlight[purchaseId] then return NOT_YET end
    inFlight[purchaseId] = true

    local ok, decision = pcall(function()
        if type(d.robuxPurchases) ~= "table" then d.robuxPurchases = {} end
        if d.robuxPurchases[purchaseId] == nil then
            -- first time we've seen it: record + pay (in memory), then save
            d.robuxPurchases[purchaseId] = os.time()
            prune(d.robuxPurchases)
            Economy:addCash(player, pack.cash, "Robux pack " .. pack.id .. " (" .. purchaseId .. ")")
            notify(player, string.format("+%s cash! Thanks for the support!", money(pack.cash)), "gold", 5)
            if Feel and type(Feel.cash) == "function" then pcall(Feel.cash, Feel, player, pack.cash) end
        end
        -- (repeat receipt: already paid — just make sure it's saved)
        if saveNow(player) then
            print(string.format("[RobuxService] %s: pack %s granted (+%d) purchase %s",
                player.Name, pack.id, pack.cash, purchaseId))
            return GRANTED
        end
        warn("[RobuxService] save failed for purchase " .. purchaseId .. " — Roblox will retry")
        return NOT_YET
    end)
    inFlight[purchaseId] = nil
    if not ok then
        warn("[RobuxService] receipt error: " .. tostring(decision))
        return NOT_YET
    end
    return decision
end

function RobuxService:init(deps)
    deps = deps or {}
    Data = deps.data or Data
    Economy = deps.economy or Economy
    Feel = deps.feel or Feel
    notify = deps.notify or notify
    if started then return end
    started = true
    MarketplaceService.ProcessReceipt = processReceipt
    local live = 0
    for _, pk in ipairs(Constants.ROBUX_PACKS or {}) do
        if (tonumber(pk.productId) or 0) ~= 0 then live = live + 1 end
    end
    print(string.format("[RobuxService] cash packs online 💸 (%d of %d have a product id)",
        live, #(Constants.ROBUX_PACKS or {})))
end

return RobuxService
