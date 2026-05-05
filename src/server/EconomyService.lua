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
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = {}

local cashUpdatedRemote = Remotes.getRemote("CashUpdated", "RemoteEvent")

function EconomyService:fireCashUpdate(player)
    local data = PlayerDataService:getData(player)
    if data then
        cashUpdatedRemote:FireClient(player, data.cash)
    end
end

function EconomyService:addCash(player, amount, reason)
    if amount <= 0 then return end

    local newBalance = PlayerDataService:addCash(player, amount)
    self:fireCashUpdate(player)

    print(string.format("[EconomyService] %s +$%d (%s) → $%d",
        player.Name, amount, reason or "unspecified", newBalance))
    return newBalance
end

return EconomyService
