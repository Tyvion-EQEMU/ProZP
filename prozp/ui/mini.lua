-- Mini overlay: no title bar, animated Pause All / Resume All toggle, logo click to
-- restore the main window. Mirrors ProLoot's mini.lua as closely as ProZP's fleet-wide
-- (rather than single-character) model allows — see the Pause All toggle below.

local mq      = require('mq')
local Roster  = require('prozp.core.roster')
local Rotation = require('prozp.core.rotation')
local Widgets = require('prozp.ui.widgets')

local Mini = {}

local _config  = nil
local _version = nil
local _logoTex = nil

function Mini.Init(config, version)
    _config  = config
    _version = version

    -- No separate 32x32 asset — the 64x64 header logo scales down fine at this size.
    _logoTex = mq.CreateTexture(mq.TLO.Lua.Dir() .. '/prozp/profusion_logo_64x64.png')
end

function Mini.Render(onClose)
    if not _config then return end

    local flags = bit32.bor(
        ImGuiWindowFlags.NoTitleBar,
        ImGuiWindowFlags.NoScrollbar,
        ImGuiWindowFlags.AlwaysAutoResize
    )
    ImGui.Begin('##prozpmini', nil, flags)

    -- Logo — click to restore main window
    if _logoTex then
        ImGui.Image(_logoTex:GetTextureID(), ImVec2(32, 32))
    else
        local sp = ImGui.GetCursorScreenPosVec()
        local dl = ImGui.GetWindowDrawList()
        dl:AddRectFilled(sp, ImVec2(sp.x + 32, sp.y + 32), IM_COL32(40, 80, 140, 200))
        dl:AddRect(sp,       ImVec2(sp.x + 32, sp.y + 32), IM_COL32(100, 150, 210, 180))
        ImGui.InvisibleButton('##prozpmini_logo', ImVec2(32, 32))
    end
    if ImGui.IsItemClicked() then
        if onClose then onClose() end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
        ImGui.BeginTooltip()
        ImGui.Text('Click to restore main window')
        ImGui.EndTooltip()
    end

    ImGui.SameLine()
    ImGui.BeginGroup()
        local appName = _version and _version._AppName or 'ProZP'
        ImGui.Text(appName)

        -- Fleet-wide, not per-group/per-character — ProZP has no single "this
        -- character's" running state the way ProLoot does, so this toggle mirrors the
        -- main panel's Pause All / Resume All buttons rather than any one group's row.
        local running = not Roster.AnyPaused()
        local newRunning, toggled = Widgets.Toggle('##prozp_mini_pauseall', running)
        if toggled then
            if newRunning then Rotation.RequestResume(nil) else Rotation.RequestPause(nil) end
        end
        if ImGui.IsItemHovered() then
            ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
            ImGui.BeginTooltip()
            ImGui.Text(running and 'Pause All — click to pause every group'
                                 or 'Resume All — click to resume every group')
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        if not running then
            ImGui.TextColored(ImVec4(1.0, 0.4, 0.4, 1.0), 'Paused')
        else
            ImGui.TextColored(ImVec4(0.3, 1.0, 0.3, 1.0), 'Running')
        end
    ImGui.EndGroup()

    ImGui.End()
end

return Mini
