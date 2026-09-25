--[[
    HEIST CREW — LootShuffle  (v3.0 "THE SCORE", LOOT-CORE · docs/V3_SPEC.md §2.3)
    ────────────────────────────────────────────────
    Every run looks a little different:

      • POOLS    lootSpots with the same `pool` are a group. Each run only
                 ~60% of a pool is out (Constants.LOOT_V3.SHUFFLE_ACTIVE, at
                 least 1). The rest are hidden (visual invisible, no prompt).
      • JACKPOT  one pool is picked as the JACKPOT room: every spot in it is
                 out and worth x1.5 (LOOT_V3.JACKPOT_MULT).
      • HIDDEN   `hidden = true` spots (the secret stash) roll ~1 in 20
                 (LOOT_V3.HIDDEN_CHANCE) per spot. Otherwise invisible.
                 If the builder gives the spot `reveal = function(show)` (it
                 shows/hides the stash AND its cover — painting swings, rug
                 folds), we call reveal(true) when it's rolled in, reveal(false)
                 when it isn't and on restore(). No reveal → we hide the visual.
      • TARGET   a `target` spot (or the job's Boss-target kind) is ALWAYS out
                 and never hidden. Spots with no `pool` are always out.
      • VAULT    vault/safe loot (inVault ~= false in a job with a vault) is
                 ALWAYS out, so drilling always pays. Its pool can still be the
                 jackpot room (x1.5).
      Smash cases (refs.smashCases) are never shuffled.

    Deterministic per seed: the same refs + seed always give the same run
    (own Park–Miller PRNG — Roblox's Random is fine too, but this also works in
    the test mock, and the order of pools/spots is sorted, never hash order).

    Jackpot room name: refs.poolNames[pool] if the builder gave one (e.g.
    { a = "Wine Cellar" }), else a tidied pool id ("wineCellar" → "WINE
    CELLAR"), else "ROOM A". Published for the HUD as ReplicatedStorage
    attributes LootJackpot (string, "" = none) and LootJackpotMult.

    PUBLIC API:
        LootShuffle:prepare(refs, seed?) -> activeSpots, info
            restores the previous shuffle first, then rolls a new one.
            activeSpots = { lootSpot }  (same tables as refs.lootSpots, in order)
            info = { seed, jackpotPool, jackpotName, jackpotMult, hiddenOn, total, active }
        LootShuffle:restore(refs?)            -- every visual back the way the builder made it
        LootShuffle:isActive(spot) -> bool
        LootShuffle:multFor(spot) -> number   -- 1.5 in the jackpot room, else 1
        LootShuffle:info() -> info (last prepare)
        LootShuffle.poolName(refs, pool) -> "WINE CELLAR"
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local LootShuffle = {}

local V3 = Constants.LOOT_V3 or {}

local state = {
    revealers = {},   -- hidden spots with spot.reveal (called false on restore)
    active = {},      -- [spot] = true
    mult = {},        -- [spot] = number
    saved = {},       -- [visual] = { parts = {[part] = {t, c}}, fx = {[inst] = enabled} }
    info = { seed = 0, jackpotPool = nil, jackpotName = "", jackpotMult = 1, hiddenOn = 0, total = 0, active = 0 },
}

-- ── deterministic PRNG (Park–Miller minimal standard; exact in doubles) ──
local function newRng(seed)
    -- (small seeds give tiny first numbers with a raw Park–Miller, so offset + warm up)
    local s = (math.floor(math.abs(tonumber(seed) or 1)) + 1234567) % 2147483647
    if s == 0 then s = 1234567 end
    for _ = 1, 6 do s = (s * 48271) % 2147483647 end
    local rng = {}
    function rng.next()     -- (0, 1)
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
    function rng.int(a, b)  -- a..b inclusive
        return a + math.floor(rng.next() * (b - a + 1))
    end
    return rng
end
LootShuffle._newRng = newRng

local function targetKindFor(refs)
    local jobId = refs and refs.jobId or ReplicatedStorage:GetAttribute("ActiveJob")
    local t = jobId and V3.TARGETS and V3.TARGETS[jobId]
    return t and t.kind or nil
end

local function isTarget(spot, targetKind)
    if spot.target ~= nil and spot.target ~= false then return true end
    return targetKind ~= nil and spot.kind == targetKind
end

-- ── visuals ───────────────────────────────────────────────────────────
local function setShown(visual, shown)
    if typeof(visual) ~= "Instance" then return end
    if shown then
        local sv = state.saved[visual]
        if not sv then return end
        for p, st in pairs(sv.parts) do
            if p.Parent then
                p.Transparency = st.t
                p.CanCollide = st.c
                p.CanQuery = st.q
            end
        end
        for d, en in pairs(sv.fx) do
            if d.Parent then pcall(function() d.Enabled = en end) end
        end
        state.saved[visual] = nil
        return
    end
    if state.saved[visual] then return end
    local sv = { parts = {}, fx = {} }
    local list = {}
    if visual:IsA("BasePart") then table.insert(list, visual) end
    for _, d in ipairs(visual:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(list, d)
        elseif d:IsA("Light") or d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter")
            or d:IsA("Beam") or d:IsA("ProximityPrompt") then
            sv.fx[d] = d.Enabled
            d.Enabled = false
        end
    end
    for _, p in ipairs(list) do
        sv.parts[p] = { t = p.Transparency, c = p.CanCollide, q = p.CanQuery }
        p.Transparency = 1
        p.CanCollide = false
        p.CanQuery = false
    end
    state.saved[visual] = sv
end

local function reveal(spot, show)
    local ok, err = pcall(spot.reveal, show)
    if not ok then warn("[LootShuffle] reveal:", err) end
end

function LootShuffle:restore(refs)
    for visual in pairs(state.saved) do setShown(visual, true) end
    state.saved = {}
    -- builder-made stash covers go back to "hidden" (their built state)
    local seen = {}
    for _, spot in ipairs(state.revealers) do seen[spot] = true reveal(spot, false) end
    for _, spot in ipairs((refs and refs.lootSpots) or {}) do
        if type(spot) == "table" and spot.hidden and type(spot.reveal) == "function" and not seen[spot] then reveal(spot, false) end
    end
    state.revealers = {}
    state.active = {}
    state.mult = {}
    state.info = { seed = 0, jackpotPool = nil, jackpotName = "", jackpotMult = 1, hiddenOn = 0, total = 0, active = 0 }
    pcall(function()
        ReplicatedStorage:SetAttribute("LootJackpot", "")
        ReplicatedStorage:SetAttribute("LootJackpotMult", 1)
    end)
end

-- ── naming ────────────────────────────────────────────────────────────
function LootShuffle.poolName(refs, pool)
    if pool == nil then return "" end
    local names = refs and refs.poolNames
    if type(names) == "table" and type(names[pool]) == "string" and names[pool] ~= "" then
        return string.upper(names[pool])
    end
    local s = tostring(pool)
    if #s <= 2 then return "ROOM " .. string.upper(s) end
    s = s:gsub("(%l)(%u)", "%1 %2"):gsub("[_%-]+", " ")
    return string.upper(s)
end

-- ── the shuffle ───────────────────────────────────────────────────────
function LootShuffle:prepare(refs, seed)
    self:restore(refs)
    seed = tonumber(seed) or (math.floor(os.clock() * 1000003) + math.random(1, 1000000))
    local rng = newRng(seed)
    local spots = (refs and refs.lootSpots) or {}
    local targetKind = targetKindFor(refs)
    local shareActive = tonumber(V3.SHUFFLE_ACTIVE) or 0.6
    local jackpotMult = tonumber(V3.JACKPOT_MULT) or 1.5
    local hiddenChance = tonumber(V3.HIDDEN_CHANCE) or 0.05

    -- group the pool spots (targets + hidden stashes sit outside the pools)
    local pools, poolIds = {}, {}
    local on = {}
    local hiddenOn = 0
    for i, spot in ipairs(spots) do
        if type(spot) == "table" then
            local inVault = refs.vault ~= nil and spot.inVault ~= false
            if (isTarget(spot, targetKind) or inVault) and not (spot.hidden and not isTarget(spot, targetKind)) then
                -- the Boss's target and the vault always pay; their pool can
                -- still be the jackpot room (x1.5)
                on[spot] = true
                if spot.pool ~= nil then
                    local key = tostring(spot.pool)
                    if not pools[key] then
                        pools[key] = { id = spot.pool, list = {}, fixed = {} }
                        table.insert(poolIds, key)
                    end
                    table.insert(pools[key].fixed, spot)
                end
            elseif spot.hidden then
                -- roll every hidden spot, in list order (deterministic)
                if rng.next() < hiddenChance then
                    on[spot] = true
                    hiddenOn = hiddenOn + 1
                end
            elseif spot.pool ~= nil then
                local key = tostring(spot.pool)
                if not pools[key] then
                    pools[key] = { id = spot.pool, list = {}, fixed = {} }
                    table.insert(poolIds, key)
                end
                table.insert(pools[key].list, { spot = spot, i = i })
            else
                on[spot] = true
            end
        end
    end
    table.sort(poolIds)

    -- the jackpot room
    local jackpotKey = nil
    if #poolIds > 0 then jackpotKey = poolIds[rng.int(1, #poolIds)] end

    for _, key in ipairs(poolIds) do
        local list = pools[key].list
        if key == jackpotKey then
            for _, e in ipairs(list) do
                on[e.spot] = true
                state.mult[e.spot] = jackpotMult
            end
            for _, spot in ipairs(pools[key].fixed) do state.mult[spot] = jackpotMult end
        elseif #list > 0 then
            local want = math.max(1, math.floor(#list * shareActive + 0.5))
            -- Fisher–Yates on a copy, pick the first `want`
            local order = table.clone(list)
            for i = #order, 2, -1 do
                local j = rng.int(1, i)
                order[i], order[j] = order[j], order[i]
            end
            for k = 1, math.min(want, #order) do on[order[k].spot] = true end
        end
    end

    local active = {}
    for _, spot in ipairs(spots) do
        if type(spot) == "table" then
            local revealer = spot.hidden and type(spot.reveal) == "function"
            if revealer then table.insert(state.revealers, spot) end
            if on[spot] then
                state.active[spot] = true
                table.insert(active, spot)
                if revealer then reveal(spot, true) end
            elseif revealer then
                reveal(spot, false)
            else
                setShown(spot.visual, false)
            end
        end
    end

    local jackpotPool = jackpotKey and pools[jackpotKey].id or nil
    state.info = {
        seed = seed,
        jackpotPool = jackpotPool,
        jackpotName = jackpotPool ~= nil and LootShuffle.poolName(refs, jackpotPool) or "",
        jackpotMult = jackpotPool ~= nil and jackpotMult or 1,
        hiddenOn = hiddenOn,
        total = #spots,
        active = #active,
    }
    pcall(function()
        ReplicatedStorage:SetAttribute("LootJackpot", state.info.jackpotName)
        ReplicatedStorage:SetAttribute("LootJackpotMult", state.info.jackpotMult)
    end)
    return active, state.info
end

function LootShuffle:isActive(spot)
    return state.active[spot] == true
end

function LootShuffle:multFor(spot)
    return state.mult[spot] or 1
end

function LootShuffle:info()
    return state.info
end

return LootShuffle
