--[[
    HEIST CREW — DoorStars  (v3.2 heist stars + hot streak)
    ────────────────────────────────────────────────
    Fills the "BestStars" label on each heist door sign in the club (ClubBuilder
    tags it "DoorStars", attribute JobId) with the LOCAL player's best stars on
    that heist + their hot streak:   🔥x3   ★★☆

    The label lives in a server-built SurfaceGui, but the server never writes its
    Text after building it, so each client can set its own copy — everyone sees
    their OWN stars on the same door.

    Reads LOCAL player attributes (PlayerDataService keeps them in sync):
        Stars_<jobId>  0..3    Streak  0..5

    PUBLIC API: DoorStars:start()   (safe to call twice — PayoutScreen starts it too,
                                     so it works even before it's in init.client's ORDER)
--]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local DoorStars = {}
local localPlayer = Players.LocalPlayer
local started = false

local GOLD = "#FDE047"
local EMPTY = "#5B6270"
local FLAME = "#FB923C"

-- "🔥x3  ★★☆" as RichText (pure: the mock tests call it)
function DoorStars.format(stars, streak)
    stars = math.clamp(math.floor(tonumber(stars) or 0), 0, 3)
    streak = math.max(0, math.floor(tonumber(streak) or 0))
    local out = ""
    if streak > 0 then
        out = string.format('<font color="%s">🔥x%d</font>   ', FLAME, streak)
    end
    if stars > 0 then
        out = out .. string.format('<font color="%s">%s</font>', GOLD, string.rep("★", stars))
    end
    if stars < 3 then
        out = out .. string.format('<font color="%s">%s</font>', EMPTY, string.rep("★", 3 - stars))
    end
    return out
end

local function paint(label)
    if not (label and label:IsA("TextLabel")) then return end
    local id = label:GetAttribute("JobId")
    if type(id) ~= "string" then return end
    label.RichText = true
    label.Text = DoorStars.format(localPlayer:GetAttribute("Stars_" .. id), localPlayer:GetAttribute("Streak"))
end

local function paintAll()
    for _, l in ipairs(CollectionService:GetTagged("DoorStars")) do pcall(paint, l) end
end

function DoorStars:start()
    if started then return end
    started = true
    CollectionService:GetInstanceAddedSignal("DoorStars"):Connect(function(l) pcall(paint, l) end)
    localPlayer.AttributeChanged:Connect(function(name)
        if name == "Streak" or string.sub(name, 1, 6) == "Stars_" then paintAll() end
    end)
    paintAll()
    print("[HEIST CREW] DoorStars mounted ✅")
end

return DoorStars
