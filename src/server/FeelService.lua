--[[
    HEIST CREW — FeelService  (v2.0 "BIGGER", feel agent)
    ────────────────────────────────────────────────
    The "juice" + the sneaking state. Malachi's playtest: "felt flat",
    "doesn't feel like a Roblox game". This is the server half of the fix:

      • FEEL FX   money pop-ups, loot pops, "bag loaded", big centre banners,
                  named one-shot sounds. All go out on the FeelFX remote and
                  client/FeelFX.lua draws/plays them.
      • CROUCH    the Crouch remote (C / LeftCtrl / ButtonB / touch button).
                  Sets player attribute Crouching and caps WalkSpeed at 8.
      • SHADOW    every 0.25 s: is the player's root inside a CollectionService
                  "ShadowZone" part? → player attribute InShadow.

    Crouch vs. other WalkSpeed writers (LootService bag speed, Sneakers +2):
      we never fight them. While crouching, any OTHER write to WalkSpeed is
      remembered as the "real" speed (attribute PreCrouchSpeed) and the live
      value is clamped to min(real, 8). Standing up restores the real speed —
      so picking up / dropping a bag mid-crouch still ends at the right speed.

    FeelFX payload (V2_SPEC §3):
        { kind = "cash"|"loot"|"load"|"sound"|"big", amount, pos, sound, id, text, by, shake }
      `sound` is a name from FeelService.SOUNDS, `id` its resolved asset
      (the client plays `id`, so this table is the single source of truth).

    PUBLIC API:
        FeelService:init()
        FeelService:cash(player|nil, amount, worldPos?)   -- "+$250" pop (nil player = everyone)
        FeelService:loot(player, kind, worldPos?)         -- "+ GOLD" pop + pickup sound (everyone sees it)
        FeelService:load(amount, worldPos?)               -- "+$1,500 LOADED" pop + load sound (everyone)
        FeelService:big(text, opts?)                      -- centre banner for everyone
                                                          --   opts = { player=, sound=name, shake=bool, color="gold"|"money"|"danger"|"info" }
        FeelService:sound(name, worldPos?, player?)       -- named one-shot (3D if worldPos)
        FeelService:setCrouch(player, on)                 -- same as the remote, for server code
        FeelService.SOUNDS                                -- the named sound table
        FeelService.CROUCH_SPEED                          -- 8
    Never errors on a bad sound or a missing character.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FeelService = {}

FeelService.CROUCH_SPEED = 8
local SHADOW_TICK = 0.25

local CS = Constants.SOUNDS or {}

-- Named sounds. Only standard Roblox built-ins (rbxasset://sounds/...) plus the
-- asset ids this project already ships in Constants.SOUNDS. `pitch`/`volume`
-- are optional. The client wraps every play in pcall, so a bad id is silent.
FeelService.SOUNDS = {
    pickup      = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6, pitch = 1.15 },
    cash        = { id = CS.CASH_CHA_CHING or "rbxasset://sounds/electronicpingshort.wav", volume = 0.7 },
    tick        = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, pitch = 1.3 },
    load        = { id = "rbxasset://sounds/snap.mp3", volume = 0.8, pitch = 0.8 },
    alarm_small = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.8, pitch = 0.55 },
    door        = { id = "rbxasset://sounds/button.wav", volume = 0.7, pitch = 0.8 },
    vault_open  = { id = "rbxasset://sounds/bass.wav", volume = 1, pitch = 0.7 },
    hide        = { id = "rbxasset://sounds/swoosh.wav", volume = 0.6, pitch = 0.9 },
    unhide      = { id = "rbxasset://sounds/swoosh.wav", volume = 0.6, pitch = 1.2 },
    crouch      = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, pitch = 0.8 },
    success     = { id = "rbxasset://sounds/victory.wav", volume = 0.7 },
    fail        = { id = CS.HEIST_FAIL or "rbxasset://sounds/bass.wav", volume = 0.7 },
}

local remote = nil
local crouchState = {}     -- [player] = { hum = Humanoid, conn = RBXScriptConnection, writing = bool }
local shadowRunning = false

-- ── sending ──────────────────────────────────────────────────────────
local function send(player, payload)
    if not remote then return end
    pcall(function()
        if player then
            if player.Parent then remote:FireClient(player, payload) end
        else
            remote:FireAllClients(payload)
        end
    end)
end

local function soundPayload(name)
    local s = FeelService.SOUNDS[name]
    if not s then return nil end
    return { sound = name, id = s.id, volume = s.volume, pitch = s.pitch }
end

local function vec(pos)
    if typeof(pos) == "Vector3" then return pos end
    if typeof(pos) == "CFrame" then return pos.Position end
    if typeof(pos) == "Instance" and pos:IsA("BasePart") then return pos.Position end
    return nil
end

local function withSound(payload, name)
    local s = soundPayload(name)
    if s then
        payload.sound, payload.id, payload.volume, payload.pitch = s.sound, s.id, s.volume, s.pitch
    end
    return payload
end

function FeelService:sound(name, worldPos, player)
    local s = soundPayload(name)
    if not s then return end
    s.kind = "sound"
    s.pos = vec(worldPos)
    if name == "vault_open" then s.shake = true end
    send(player, s)
end

function FeelService:cash(player, amount, worldPos)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return end
    send(player, withSound({ kind = "cash", amount = amount, pos = vec(worldPos) }, "cash"))
end

function FeelService:loot(player, kind, worldPos)
    local info = (Constants.LOOT or {})[kind] or {}
    local pos = vec(worldPos)
    if not pos and player and player.Character then
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        pos = root and root.Position
    end
    send(nil, withSound({
        kind = "loot",
        text = tostring(kind or "LOOT"),
        amount = info.value,
        pos = pos,
        by = player and player.Name or nil,
        color = info.color,
    }, "pickup"))
end

function FeelService:load(amount, worldPos)
    send(nil, withSound({ kind = "load", amount = math.floor(tonumber(amount) or 0), pos = vec(worldPos) }, "load"))
end

function FeelService:big(text, opts)
    opts = opts or {}
    local payload = { kind = "big", text = tostring(text or ""), shake = opts.shake == true, color = opts.color }
    if opts.sound then withSound(payload, opts.sound) end
    if opts.sound == "vault_open" and opts.shake == nil then payload.shake = true end
    send(opts.player, payload)
end

-- ── crouch ───────────────────────────────────────────────────────────
local function humOf(player)
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function clearCrouchState(player)
    local st = crouchState[player]
    if st and st.conn then st.conn:Disconnect() end
    crouchState[player] = nil
end

function FeelService:setCrouch(player, on)
    on = on == true
    local hum = humOf(player)
    local was = player:GetAttribute("Crouching") == true
    if on and (not hum or hum.Health <= 0 or hum.SeatPart) then on = false end
    if on == was and (not on or (crouchState[player] and crouchState[player].hum == hum)) then return end

    if on then
        clearCrouchState(player)
        local st = { hum = hum, writing = false }
        crouchState[player] = st
        player:SetAttribute("PreCrouchSpeed", hum.WalkSpeed)
        player:SetAttribute("Crouching", true)
        st.writing = true
        hum.WalkSpeed = math.min(hum.WalkSpeed, FeelService.CROUCH_SPEED)
        st.writing = false
        -- someone else (LootService, Sneakers) changed the speed mid-crouch:
        -- that's the new "real" speed; keep the crouch cap on top of it
        st.conn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if st.writing or crouchState[player] ~= st then return end
            local v = hum.WalkSpeed
            player:SetAttribute("PreCrouchSpeed", v)
            local capped = math.min(v, FeelService.CROUCH_SPEED)
            if capped ~= v then
                st.writing = true
                hum.WalkSpeed = capped
                st.writing = false
            end
        end)
    else
        local st = crouchState[player]
        clearCrouchState(player)
        player:SetAttribute("Crouching", false)
        local real = player:GetAttribute("PreCrouchSpeed")
        player:SetAttribute("PreCrouchSpeed", nil)
        if hum and st and st.hum == hum and typeof(real) == "number" then
            hum.WalkSpeed = real
        end
    end
    self:sound("crouch", nil, player)
end

-- ── shadows ──────────────────────────────────────────────────────────
local function inside(part, point)
    local p = part.CFrame:PointToObjectSpace(point)
    local h = part.Size / 2
    return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y + 2.5 and math.abs(p.Z) <= h.Z
end

local function shadowLoop()
    if shadowRunning then return end
    shadowRunning = true
    task.spawn(function()
        while true do
            task.wait(SHADOW_TICK)
            local ok, err = pcall(function()
                local zones = CollectionService:GetTagged("ShadowZone")
                for _, player in ipairs(Players:GetPlayers()) do
                    local char = player.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local now = false
                    if root then
                        local pos = root.Position
                        for _, z in ipairs(zones) do
                            if z:IsA("BasePart") and z:IsDescendantOf(workspace) and inside(z, pos) then
                                now = true
                                break
                            end
                        end
                    end
                    if (player:GetAttribute("InShadow") == true) ~= now then
                        player:SetAttribute("InShadow", now)
                    end
                end
            end)
            if not ok then warn("[FeelService] shadow:", err) end
        end
    end)
end

-- ── init ─────────────────────────────────────────────────────────────
function FeelService:init()
    remote = Remotes.getRemote(Remotes.NAMES.FeelFX, "RemoteEvent")
    local crouchRemote = Remotes.getRemote(Remotes.NAMES.Crouch, "RemoteEvent")

    local last = {}
    crouchRemote.OnServerEvent:Connect(function(player, on)
        if typeof(on) ~= "boolean" then return end
        if last[player] and os.clock() - last[player] < 0.15 then return end
        last[player] = os.clock()
        local ok, err = pcall(function() FeelService:setCrouch(player, on) end)
        if not ok then warn("[FeelService] crouch:", err) end
    end)

    local function hook(player)
        player:SetAttribute("Crouching", false)
        player:SetAttribute("InShadow", false)
        local function onChar(char)
            -- a new body starts standing; the old speed belonged to the old body
            clearCrouchState(player)
            player:SetAttribute("Crouching", false)
            player:SetAttribute("PreCrouchSpeed", nil)
            local hum = char:WaitForChild("Humanoid", 10)
            if hum then
                -- stand up when you get into the getaway car
                hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
                    if hum.SeatPart and player:GetAttribute("Crouching") then
                        FeelService:setCrouch(player, false)
                    end
                end)
            end
        end
        player.CharacterAdded:Connect(onChar)
        if player.Character then task.spawn(onChar, player.Character) end
    end
    Players.PlayerAdded:Connect(hook)
    for _, p in ipairs(Players:GetPlayers()) do task.spawn(hook, p) end
    Players.PlayerRemoving:Connect(function(p)
        clearCrouchState(p)
        last[p] = nil
    end)

    shadowLoop()
    print("[FeelService] ready ✅")
end

return FeelService
