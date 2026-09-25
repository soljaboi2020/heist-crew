--[[
    HEIST CREW — EconomyService
    ────────────────────────────────────────────────
    Sits on top of PlayerDataService. The ONLY place that hands out cash.
    Everything that pays a player (test pad, vault crack, heist completion)
    calls EconomyService:addCash() — never touches PlayerDataService directly.

    Why? Single choke-point so we can later:
    - Apply gamepass multipliers (e.g., VIP +10%)
    - Log every payout for analytics
    - Enforce daily/heist payout caps
    - Trigger achievement notifications

    PUBLIC API:
        EconomyService:addCash(player, amount, reason)
        EconomyService:fireCashUpdate(player)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = {}

local cashUpdatedRemote = Remotes.getRemote("CashUpdated", "RemoteEvent")

-- v0.7.0: cash is ALSO mirrored to a player attribute + the standard Roblox
-- leaderboard. The attribute replicates on its own, so the HUD can read the
-- right number the moment it loads — no race against the first remote event
-- (the old HUD sat at "$0" when it missed that event).
local function mirror(player, cash)
    player:SetAttribute("Cash", cash)
    local stats = player:FindFirstChild("leaderstats")
    if not stats then
        stats = Instance.new("Folder")
        stats.Name = "leaderstats"
        stats.Parent = player
    end
    local v = stats:FindFirstChild("Cash")
    if not v then
        v = Instance.new("IntValue")
        v.Name = "Cash"
        v.Parent = stats
    end
    v.Value = cash
end

function EconomyService:fireCashUpdate(player)
    local data = PlayerDataService:getData(player)
    if data then
        mirror(player, data.cash)
        cashUpdatedRemote:FireClient(player, data.cash)
    end
end

-- v1.0: payouts (anything with opts.payout) get the VIP multiplier. Shop refunds,
-- codes and daily rewards don't.
function EconomyService:addCash(player, amount, reason, opts)
    if amount <= 0 then return end
    if opts and opts.payout and player:GetAttribute("VIP") then
        amount = math.floor(amount * Constants.VIP_MULTIPLIER + 0.5)
    end

    local newBalance = PlayerDataService:addCash(player, amount)
    self:fireCashUpdate(player)

    print(string.format("[EconomyService] %s +$%d (%s) → $%d",
        player.Name, amount, reason or "unspecified", newBalance))
    return newBalance
end

-- Spend cash. Returns true only if the player could afford it (nothing changes otherwise).
function EconomyService:spend(player, amount, reason)
    local data = PlayerDataService:getData(player)
    if not data or amount < 0 or data.cash < amount then return false end
    PlayerDataService:addCash(player, -amount)
    self:fireCashUpdate(player)
    print(string.format("[EconomyService] %s -$%d (%s) → $%d", player.Name, amount, reason or "spend", data.cash))
    return true
end

return EconomyService
