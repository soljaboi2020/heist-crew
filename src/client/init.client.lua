--[[
    HEIST CREW — Client Bootstrap (v1.0)
    ────────────────────────────────────────────────
    Mounts every piece of UI. All of it shares one look: Shared.UITheme.

      CashHud        cash card (top-right)
      Notifications  toasts (top-centre, under the objective)
      HeistHud       alarm vignette + drill bar + result card
      CrewHud        role card, objective pill, title card, role-only prompt filter
      JobHud         THE JOB checklist + take + level (right side)
      LootHud        carrying pill + G to throw + keycard chip
      AbilityHud     role perks, Lookout mark (Q), guard/camera highlights
      ShopUI         gear / masks / codes / VIP (opens at the gear wall)
      CarHud         speed, bust meter, nitro, drop-off arrow (while driving)
      BriefingUI     Boss briefing cut-scene, READY UP, drop-in fade + title  (v1.1)
      WaypointHud    on-screen markers to the next goal                       (v1.1)
      DetectionHud   "being spotted" meter + direction arrow                  (v1.1)
      PayoutScreen   end-of-heist breakdown, grade, XP, PLAY AGAIN            (v1.1)
      TipHud         first-run coaching from the Boss                         (v1.1)

    Each module is started in its own protected call — one broken HUD can't
    stop the others from mounting.
--]]

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

print("══════════════════════════════════════════")
print(string.format("[HEIST CREW] Client online ✅ — playing as %s", localPlayer.Name))
print("══════════════════════════════════════════")

-- (fix v1.1) Roblox's own player list sits top-right, right on top of the cash
-- and job cards. The safehouse TV shows the leaderboard instead.
pcall(function()
    game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- (fix v1.1.1) On some PCs / graphics settings a CanvasGroup at GroupTransparency 1
-- still draws its contents — Malachi saw "SPOTTING…" and the drop-in title on
-- screen when they should have been invisible. So every CanvasGroup in our UI
-- is hidden outright whenever it's (nearly) fully transparent.
do
    local pg = localPlayer:WaitForChild("PlayerGui")
    local function watch(cg)
        if not cg:IsA("CanvasGroup") then return end
        local function sync() cg.Visible = cg.GroupTransparency < 0.98 end
        sync()
        cg:GetPropertyChangedSignal("GroupTransparency"):Connect(sync)
    end
    for _, d in ipairs(pg:GetDescendants()) do watch(d) end
    pg.DescendantAdded:Connect(watch)
end

local ORDER = {
    "CashHud", "Notifications", "HeistHud", "CrewHud",
    "JobHud", "LootHud", "AbilityHud", "ShopUI", "CarHud",
    "BriefingUI", "WaypointHud", "DetectionHud", "PayoutScreen", "TipHud",
}

for _, name in ipairs(ORDER) do
    local mod = script:FindFirstChild(name)
    if not mod then
        warn("[HEIST CREW] UI module missing: " .. name)
    else
        task.spawn(function()
            local ok, err = pcall(function()
                require(mod):start()
            end)
            if not ok then warn("[HEIST CREW] " .. name .. " failed: " .. tostring(err)) end
        end)
    end
end
