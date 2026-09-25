--[[
    HEIST CREW — UITheme
    ────────────────────────────────────────────────
    ONE look for every piece of UI, so the HUD stops being five different
    styles glued together. Added 2026-09-25 (Malachi: "make sure ui is nice
    not like crappy blocky").

    The look: dark smoked-glass panels, thin light hairline borders, soft
    rounded corners, Roblox's own BuilderSans type, and colour used ONLY for
    meaning (green = money, gold = objective, red = danger, role colours).
    No emoji in HUD text, no thick coloured outlines, no full-width bars.

    Used by the client HUDs AND by the server for in-world screens (TV,
    blueprint, role signs) so the world and the HUD match.
--]]

local UITheme = {}

-- ── Palette ────────────────────────────────────────────────────────────
UITheme.C = {
    bg        = Color3.fromRGB(11, 13, 19),
    bgRaised  = Color3.fromRGB(22, 26, 36),
    line      = Color3.fromRGB(255, 255, 255),
    text      = Color3.fromRGB(241, 245, 249),
    muted     = Color3.fromRGB(148, 163, 184),
    faint     = Color3.fromRGB(71, 85, 105),
    money     = Color3.fromRGB(74, 222, 128),
    gold      = Color3.fromRGB(251, 191, 36),
    danger    = Color3.fromRGB(248, 113, 113),
    dangerDeep= Color3.fromRGB(185, 28, 28),
    info      = Color3.fromRGB(56, 189, 248),
}

-- ── Type ───────────────────────────────────────────────────────────────
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
UITheme.F = {
    display = Font.new(FAMILY, Enum.FontWeight.Heavy),
    bold    = Font.new(FAMILY, Enum.FontWeight.Bold),
    medium  = Font.new(FAMILY, Enum.FontWeight.Medium),
    mono    = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

-- ── Helpers ────────────────────────────────────────────────────────────
function UITheme.corner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 10)
    c.Parent = parent
    return c
end

-- Hairline border — the thing that makes a dark panel read as "glass"
function UITheme.stroke(parent, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = color or UITheme.C.line
    s.Transparency = transparency or 0.88
    s.Thickness = thickness or 1
    s.Parent = parent
    return s
end

function UITheme.padding(parent, x, y)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, x or 12)
    p.PaddingRight = UDim.new(0, x or 12)
    p.PaddingTop = UDim.new(0, y or x or 12)
    p.PaddingBottom = UDim.new(0, y or x or 12)
    p.Parent = parent
    return p
end

-- Smoked-glass panel: dark, slightly see-through, lighter at the top
function UITheme.panel(props)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = UITheme.C.bg
    f.BackgroundTransparency = props and props.transparency or 0.18
    f.BorderSizePixel = 0
    for k, v in pairs(props or {}) do
        if k ~= "transparency" and k ~= "radius" and k ~= "noStroke" then f[k] = v end
    end
    UITheme.corner(f, props and props.radius or 12)
    if not (props and props.noStroke) then UITheme.stroke(f) end
    local g = Instance.new("UIGradient")
    g.Rotation = 90
    g.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 205, 215))
    g.Parent = f
    return f
end

function UITheme.label(props)
    local l = Instance.new("TextLabel")
    l.Text = ""   -- (fix v1.1.1) Roblox's default is the word "Label" — it showed on screen
    l.BackgroundTransparency = 1
    l.TextColor3 = UITheme.C.text
    l.FontFace = UITheme.F.bold
    l.TextSize = 16
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    for k, v in pairs(props or {}) do l[k] = v end
    return l
end

-- Small uppercase caption ("CASH", "YOUR ROLE", "OBJECTIVE")
function UITheme.caption(text, props)
    local l = UITheme.label({
        Text = string.upper(text),
        TextColor3 = UITheme.C.muted,
        FontFace = UITheme.F.bold,
        TextSize = 11,
    })
    for k, v in pairs(props or {}) do l[k] = v end
    return l
end

function UITheme.rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

-- "1234567" -> "$1,234,567"
function UITheme.money(n)
    local s = tostring(math.floor(n or 0))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return "$" .. s
end

return UITheme
