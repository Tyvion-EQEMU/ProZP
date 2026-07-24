-- Credits tooltip: hover the Credits button in the panel header to show

local Credits = {}

local _colorWheel = {}
local _colorTimer = {}

local DATA = {
    Devs = {
        'Tyvion',
        'Claude',
    },
    Inspirations = {
        'Lisie',
        'Grimmier378',
    },
}

local function renderName(name)
    local now = os.clock()
    _colorWheel[name] = _colorWheel[name] or math.random(10000)
    _colorTimer[name] = _colorTimer[name] or now

    if now - _colorTimer[name] > 0.25 then
        _colorWheel[name] = _colorWheel[name] + 1
        _colorTimer[name] = now
    end

    local cw  = _colorWheel[name]
    local len = #name
    for i = 1, len do
        local v   = math.floor(math.sin(0.4 * (cw + i)) * 80 + 160)
        local col = IM_COL32(v, v, v, 255)
        if i > 1 then ImGui.SameLine(0, 1) end
        ImGui.PushStyleColor(ImGuiCol.Text, col)
        ImGui.Text(name:sub(i, i))
        ImGui.PopStyleColor()
    end
end

-----------------------------------------------------------------------
-- Snake border
-----------------------------------------------------------------------
-- Traces a point on the perimeter of a (optionally rounded) rectangle.
-- radius=0 gives sharp corners; radius>0 follows quarter-circle arcs.
local function perimeterPoint(pos, size, t, radius)
    local w, h = size.x, size.y
    radius = math.min(radius or 0, math.min(w, h) * 0.5)

    if radius <= 0 then
        local d = (t % 1.0) * (2 * (w + h))
        if d < w then
            return ImVec2(pos.x + d,               pos.y)
        elseif d < w + h then
            return ImVec2(pos.x + w,               pos.y + d - w)
        elseif d < 2 * w + h then
            return ImVec2(pos.x + w - (d - w - h), pos.y + h)
        else
            return ImVec2(pos.x,                   pos.y + h - (d - 2*w - h))
        end
    end

    local sw      = w - 2 * radius          -- straight horizontal segment length
    local sh      = h - 2 * radius          -- straight vertical segment length
    local arc     = math.pi * 0.5 * radius  -- quarter-circle arc length
    local total   = 2 * sw + 2 * sh + 4 * arc
    local d       = (t % 1.0) * total

    -- top edge L→R
    if d < sw then return ImVec2(pos.x + radius + d, pos.y) end
    d = d - sw
    -- top-right arc  (centre w-r, r)  -π/2 → 0
    if d < arc then
        local a = -math.pi*0.5 + (d/arc)*math.pi*0.5
        return ImVec2(pos.x+(w-radius)+radius*math.cos(a), pos.y+radius+radius*math.sin(a))
    end
    d = d - arc
    -- right edge T→B
    if d < sh then return ImVec2(pos.x + w, pos.y + radius + d) end
    d = d - sh
    -- bottom-right arc  (centre w-r, h-r)  0 → π/2
    if d < arc then
        local a = (d/arc)*math.pi*0.5
        return ImVec2(pos.x+(w-radius)+radius*math.cos(a), pos.y+(h-radius)+radius*math.sin(a))
    end
    d = d - arc
    -- bottom edge R→L
    if d < sw then return ImVec2(pos.x+(w-radius)-d, pos.y+h) end
    d = d - sw
    -- bottom-left arc  (centre r, h-r)  π/2 → π
    if d < arc then
        local a = math.pi*0.5 + (d/arc)*math.pi*0.5
        return ImVec2(pos.x+radius+radius*math.cos(a), pos.y+(h-radius)+radius*math.sin(a))
    end
    d = d - arc
    -- left edge B→T
    if d < sh then return ImVec2(pos.x, pos.y+(h-radius)-d) end
    d = d - sh
    -- top-left arc  (centre r, r)  π → 3π/2
    local a = math.pi + (d/arc)*math.pi*0.5
    return ImVec2(pos.x+radius+radius*math.cos(a), pos.y+radius+radius*math.sin(a))
end

local function snakeDraw(pos, size, lineW, dark, radius)
    if size.x < 4 or size.y < 4 then return end
    local phase = (os.clock() / 1.5) % 1.0
    local dl    = ImGui.GetForegroundDrawList()
    local STEPS = 64
    local TAIL  = 0.28
    for i = 0, STEPS - 1 do
        local t1   = i / STEPS
        local dist = (phase - t1) % 1.0
        if dist < TAIL then
            local bright = 1.0 - (dist / TAIL)
            bright = bright * bright
            local a   = math.floor(bright * 255)
            local col
            if dark then
                col = IM_COL32(0, 0, 0, a)
            else
                local v = math.min(255, math.floor(bright * 220 + 55))
                col = IM_COL32(v, v, v, a)
            end
            local p1 = perimeterPoint(pos, size, t1,            radius)
            local p2 = perimeterPoint(pos, size, (i+1) / STEPS, radius)
            dl:AddLine(p1, p2, col, lineW)
        end
    end
end

-- Called from panel.lua with the button's screen rect.
-- Pass dark=true for a black snake, radius>0 to match rounded button corners.
function Credits.DrawSnake(pos, size, dark, radius)
    snakeDraw(pos, size, 2.0, dark, radius)
end

-----------------------------------------------------------------------

function Credits.RenderTooltip()
    local io  = ImGui.GetIO()
    local cx  = io.DisplaySize.x * 0.5
    local cy  = io.DisplaySize.y * 0.33
    ImGui.SetNextWindowPos(ImVec2(cx, cy), ImGuiCond.Always, ImVec2(0.5, 0.5))
    ImGui.SetNextWindowSize(ImVec2(250, 0), ImGuiCond.Always)
    ImGui.BeginTooltip()

    if ImGui.CollapsingHeader('Developed By', ImGuiTreeNodeFlags.DefaultOpen) then
        for _, name in ipairs(DATA.Devs) do
            renderName(name)
        end
    end

    ImGui.Spacing()

    if ImGui.CollapsingHeader('Credits & Acknowledgements', ImGuiTreeNodeFlags.DefaultOpen) then
        if #DATA.Inspirations == 0 then
            ImGui.TextDisabled('(coming soon)')
        end
        for _, name in ipairs(DATA.Inspirations) do
            renderName(name)
        end
    end

    -- Snake border around the tooltip window
    snakeDraw(ImGui.GetWindowPosVec(), ImGui.GetWindowSizeVec(), 1.5)

    ImGui.EndTooltip()
end

return Credits
