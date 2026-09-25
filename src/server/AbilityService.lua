--[[
    HEIST CREW — AbilityService
    ────────────────────────────────────────────────
    v1.0. The one ACTIVE role ability: the Lookout's MARK (Q).
    Marks every guard, cop and security camera within 70 studs of the Lookout
    for the whole crew for 10 seconds (sets MarkedUntil = server time; the
    client AbilityHud draws the highlights). 30 s cooldown, enforced here.

    The other roles' perks are PASSIVE and live where they apply:
      Hacker  → SecurityService (fast breaker, hack keypads)
      Muscle  → LootService (no bag slowdown, longer throw) + GuardService (takedown)
      Driver  → VehicleService (+20% speed, nitro)
      Lookout → AbilityHud (always sees guards/cameras) + this mark

    PUBLIC API:
        AbilityService:init(notifyFn)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AbilityService = {}

local RANGE = 70
local DURATION = 10
local COOLDOWN = 30

function AbilityService:init(notify)
    notify = notify or function() end
    local ready = {}
    Remotes.getRemote(Remotes.NAMES.UseAbility, "RemoteEvent").OnServerEvent:Connect(function(player)
        if player:GetAttribute("Role") ~= "Lookout" then return end
        local now = workspace:GetServerTimeNow()
        if ready[player] and now < ready[player] then
            notify(player, string.format("Mark ready in %ds", math.ceil(ready[player] - now)), "white", 2)
            return
        end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        ready[player] = now + COOLDOWN
        player:SetAttribute("AbilityReadyAt", ready[player])

        local marked = 0
        for _, tag in ipairs({ "Guard", "SecurityCamera" }) do
            for _, model in ipairs(CollectionService:GetTagged(tag)) do
                local pivot = model:IsA("Model") and model:GetPivot().Position
                    or (model:IsA("BasePart") and model.Position)
                if pivot and (pivot - root.Position).Magnitude <= RANGE then
                    model:SetAttribute("MarkedUntil", now + DURATION)
                    marked = marked + 1
                end
            end
        end
        if marked > 0 then
            local msg = string.format("%s marked %d target%s", player.DisplayName, marked, marked == 1 and "" or "s")
            for _, p in ipairs(Players:GetPlayers()) do notify(p, msg, "gold", 3) end
        else
            notify(player, "Nothing to mark nearby", "white", 2)
        end
    end)
    Players.PlayerRemoving:Connect(function(p) ready[p] = nil end)
    print("[AbilityService] Lookout mark online 👁")
end

return AbilityService
