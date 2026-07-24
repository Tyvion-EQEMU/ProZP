-- Fleet dashboard: header (logo/version/dev-info), one collapsible section per
-- detected group (Tank + Gears holders only), global and per-group pause, a
-- missing-toon warning strip, a small settings block, and the console log —
-- styled to match ProLoot/ProTask.

local mq       = require('mq')
local Icons    = require('mq.ICONS')
local Roster   = require('prozp.core.roster')
local Rotation = require('prozp.core.rotation')
local Widgets  = require('prozp.ui.widgets')
local Logger   = require('prozp.utils.logger')
local Credits  = require('prozp.ui.credits')
local Mini     = require('prozp.ui.mini')

local Panel = {}

local BUTTON_GOLD = ImVec4(1.0, 0.72, 0.20, 1.0)
local REPO_URL    = 'https://github.com/Tyvion-EQEMU/ProZP'

-- Build notes — update this block each release; no UI changes needed.
-- Format: first line is "vX.Y.Z Tag  —  YYYY-MM-DD", blank line, then
-- bullet entries starting with "  • ". Prepend a new block for each release.
local BUILD_NOTES = [[
v0.1.9 Dev  —  2026-07-22

  New Features:
  • Added Mini Mode, mirroring ProLoot's: a minimize button (top-right of
    the main panel) collapses ProZP into a small titleless overlay —
    logo, app name, a Running/Paused toggle, click the logo to restore
    the main window. New `/prozp mini [on|off]` command to match.
    Since ProZP is fleet-wide rather than per-character, the mini
    toggle controls Pause All / Resume All (not any one group) — the
    tooltip says so explicitly rather than reading as scoped to
    whichever character or group you happened to open it from.

v0.1.8 Dev  —  2026-07-22

  Diagnostics:
  • Investigating a rare live incident: two Gears holders in the same group
    (Tyvion/Ampadarra) both clicked Gears in the same second, twice in one
    session — wastes a charge (both items land on the same recast) but
    doesn't stall or desync anything. Likely cause: Rotation's turn
    fallback ("whoever's turn it was is no longer an active holder —
    restart from the top") is reachable from a single stale/transient
    hasGears heartbeat reading, not just a real holder leaving. Added two
    Debug-only log lines to catch it happening live next time: Roster now
    logs any hasGears flip on a heartbeat, and Rotation logs every time
    the turn fallback actually fires. No behavior change — purely
    observational, gated behind LogLevel 4 like all other Debug lines.

v0.1.7 Dev  —  2026-07-22

  Tuning:
  • Bumped GearsRecastSec default 600 -> 690. An overnight multi-hour test
    run showed a consistent ~90s gap between the flat schedule's deadline
    and the item's real TimerReady on every tank, every cycle — 600s was
    simply short of the item's actual recast. 690 matches what the logs
    showed; shaves that wasted wait off each cycle. (Not a bug fix on its
    own — the v0.1.6 itemReady gate already made the mismatch harmless,
    this just removes the wait.)

v0.1.6 Dev  —  2026-07-21

  Fixes:
  • The scheduled Gears click used to fire blind the moment the flat
    wall-clock deadline arrived, even if the real item wasn't actually off
    cooldown yet (e.g. leftover recast from before a restart) — UseItem
    has no success readback, so that click silently failed in-game while
    Little Buddy, the Bear pull, and turn advance all proceeded as if it
    had worked, onto a zone that was never actually repopulated. The
    click now waits for the item's own TimerReady too. Purely a local,
    ~100ms-repolled condition — worst case is a short wait, never a
    stall, since no other instance's state is involved.

v0.1.5 Dev  —  2026-07-21

  Fixes:
  • Fixed a dedup bug that silently swallowed a real Gears click roughly
    every other turn. cycleId is each holder's own local counter (starts
    at 0, increments only on that holder's clicks), but the guard that
    decides whether a gears_fired broadcast is new compared every
    holder's counter against one shared number — so two holders' counters
    reaching the same value made the second holder's legitimate click
    look like a stale duplicate of the first's. Best case this cost one
    wasted extra click (same tick, invisible). Worst case (seen live) the
    click was swallowed outright, leaving Little Buddy/Bear stuck until
    the original flat deadline arrived ~100s later, discarding the early
    click entirely. The dedup guard is now tracked per sender name so two
    holders' counters can never collide. Also added the holder's name to
    the Little Buddy / Bear-pull log lines for clarity.

v0.1.4 Dev  —  2026-07-21

  New Features:
  • Added ExpeditionRecallCommand (default '#sendmeexpedition'). The holder
    about to click Gears now says this just before clicking — recalls
    anyone who wandered off to the zone-in spot ahead of time, which is
    where the Gears repop would send stragglers anyway. Set to an empty
    string in config to disable.

v0.1.3 Dev  —  2026-07-21

  New Features:
  • Added AllowEarlyGears (on by default). GearsRecastSec is just a nominal
    pacing guess, not the item's real cooldown, so the flat schedule was
    sometimes conservative — the item sat ready and unused until the
    scheduled deadline caught up. When on, the current turn-holder can now
    fire as soon as its own item is actually off recast, but never faster
    than one more holder than currently active would pace at (a solo
    holder's 10-minute wait can shrink to 5, never down to the large-group
    PostPullDelaySec floor). Purely local — never reads another instance's
    recast — and only ever fires sooner, never later, so it can't
    reintroduce the live cross-character stall class fixed in v0.1.1.
    Toggle off via the shared config if you want strict flat pacing back.

v0.1.2 Dev  —  2026-07-21

  Fixes:
  • Log lines were tagged only with the group label (the tank's name), so
    every group member's log file showed the identical tag and there was
    no way to tell which character actually wrote a given line. Every log
    line now also carries the logging character's own name.

v0.1.1 Dev  —  2026-07-21

  Fixes:
  • Rotation no longer gates on live item recast (Item.TimerReady) or waits
    for Little Buddy ack broadcasts before pulling — both were live
    cross-character reads that could desync and stall the whole group.
    Repops now fire on a flat wall-clock timer (GearsRecastSec / number of
    active holders) derived fresh from the last Bear pull. TimerReady is
    now log-only, never a gate.
  • Fixed real-world 35+ minute stall where two Gears holders each believed
    it was the other's turn (the fresh-canonical-list rewrite noted in
    rotation.lua's header was already the correct fix — this build is the
    first deploy of it).

v0.1.0 Dev  —  2026-07-20

  Initial Release:
  • Detects Gears of Improved Life holders per real EQ group and stages an
    alphabetical, evenly-staggered rotation between them
  • Little Buddy rebuff + Bear pull sequenced automatically after every repop
  • Fleet dashboard shows every detected group (Tank + holders only), with
    live recast bars and per-group / global Pause-Resume
  • Detects group members not reporting in and auto-launches them via DanNet
]]

local _config    = nil
local _version   = nil
local _logoTex   = nil
local _panelOpen = true
local _devInfoOpen = false
local _miniMode  = false

function Panel.Init(config, version)
    _config    = config
    _version   = version
    _logoTex   = mq.CreateTexture(mq.TLO.Lua.Dir() .. '/prozp/profusion_logo_64x64.png')
    _panelOpen = config:Get('PanelOpen')

    Mini.Init(config, version)
end

function Panel.ToggleMini()
    _miniMode = not _miniMode
end

function Panel.SetMini(value)
    _miniMode = value
end

-- Restores the main window from either hidden or mini mode — used by /prozp show.
function Panel.Show()
    _config:SetAndSave('PanelOpen', true)
    _panelOpen = true
    _miniMode  = false
end

local function drawHeader()
    if not _version then return end

    if _logoTex then
        ImGui.Image(_logoTex:GetTextureID(), ImVec2(64, 64))
    else
        local sp = ImGui.GetCursorScreenPosVec()
        local dl = ImGui.GetWindowDrawList()
        dl:AddRectFilled(sp, ImVec2(sp.x + 64, sp.y + 64), IM_COL32(40, 80, 140, 200))
        dl:AddRect(sp,       ImVec2(sp.x + 64, sp.y + 64), IM_COL32(100, 150, 210, 180))
        ImGui.Dummy(ImVec2(64, 64))
    end
    ImGui.SameLine()
    ImGui.BeginGroup()
    local verStr = string.format('%s  v%s', _version._AppName, _version._version)
    ImGui.Text(verStr)
    if ImGui.IsItemHovered() then
        ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)
        ImGui.BeginTooltip()
        ImGui.TextDisabled("What's New / Dev Info")
        ImGui.EndTooltip()
    end
    if ImGui.IsItemClicked(0) then _devInfoOpen = not _devInfoOpen end
    if _version._buildTag then
        ImGui.SameLine()
        -- Barber-pole: each character's phase offset by its index so the
        -- gold→white highlight sweeps diagonally across the tag text.
        local tag   = '[' .. _version._buildTag .. ']'
        local t     = os.clock() * 0.5   -- stripe speed (cycles/sec)
        local pitch = 0.12               -- phase offset per character
        for i = 1, #tag do
            local w = (math.sin((t - i * pitch) * math.pi * 2) + 1.0) * 0.5
            if i > 1 then ImGui.SameLine(0, 1) end
            ImGui.TextColored(
                ImVec4(1.0, 0.72 + 0.28 * w, 0.20 + 0.80 * w, 1.0),
                tag:sub(i, i))
        end
    end
    ImGui.TextDisabled('by ')
    ImGui.SameLine(0, 0)
    ImGui.TextColored(BUTTON_GOLD, 'Tyvion')
    if ImGui.IsItemHovered() then ImGui.SetMouseCursor(ImGuiMouseCursor.Hand) end
    if ImGui.IsItemClicked(0) then
        os.execute('start "" "https://github.com/Tyvion-EQEMU"')
    end
    local btnW = 60
    ImGui.SetCursorPosX(select(1, ImGui.GetContentRegionMax()) - btnW)
    ImGui.Button('Credits', btnW, 0)
    if ImGui.IsItemHovered() then
        local bmin = ImGui.GetItemRectMinVec()
        local bmax = ImGui.GetItemRectMaxVec()
        Credits.RenderTooltip()
        Credits.DrawSnake(bmin, ImVec2(bmax.x - bmin.x, bmax.y - bmin.y))
    end
    ImGui.EndGroup()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

local function renderDevInfo()
    if not _devInfoOpen then return end

    ImGui.SetNextWindowSize(ImVec2(430, 360), ImGuiCond.FirstUseEver)
    local open, shouldDraw = ImGui.Begin('ProZP Dev Info', _devInfoOpen, ImGuiWindowFlags.None)
    _devInfoOpen = open
    if ImGui.IsWindowFocused() and ImGui.IsKeyPressed(ImGuiKey.Escape) then _devInfoOpen = false end

    if shouldDraw then
        ImGui.TextColored(BUTTON_GOLD, "What's New")
        ImGui.Separator()
        ImGui.Spacing()
        ImGui.BeginChild('##devnotes', ImVec2(0, 170), true, ImGuiWindowFlags.None)
        ImGui.TextWrapped(BUILD_NOTES)
        ImGui.EndChild()

        ImGui.Spacing()

        ImGui.TextColored(BUTTON_GOLD, 'Feedback & Bug Reports')
        ImGui.Separator()
        ImGui.Spacing()
        ImGui.TextWrapped(
            'Found a bug or have a suggestion? Open an issue on GitHub. ' ..
            'A helpful report includes: character name, group, what happened, ' ..
            'and what you expected instead.')
        ImGui.Spacing()
        ImGui.SetNextItemWidth(-88)
        ImGui.InputText('##repourl', REPO_URL, ImGuiInputTextFlags.ReadOnly)
        ImGui.SameLine()
        if ImGui.Button('Copy URL', 83, 0) then
            ImGui.SetClipboardText(REPO_URL)
        end
    end

    ImGui.End()
end

local function renderGroupSection(label)
    local members = Roster.MembersByGroupLabel(label)

    -- One row per item, not per character — a tank holding both Gears and the
    -- Bear gets two rows, since each item has its own independent recast.
    -- The Bear row always sorts to the top of the table, regardless of where
    -- the tank's name falls alphabetically among the group's holders.
    local rows = {}
    local anyPaused = false
    for _, m in ipairs(members) do
        if m.isTank or m.hasGears then
            if m.paused then anyPaused = true end
        end
        if m.isTank then
            -- While a cycle is pending, show that countdown here instead of the
            -- Bear's real (~1.5s, uninteresting) recast — this is the number that
            -- actually paces the rotation.
            local pending = m.nextGearsRemainingSec
            if pending and pending > 0 then
                rows[#rows + 1] = {
                    name = m.name, item = 'Cuddly Bear',
                    ready = pending, total = m.nextGearsIntervalSec or _config:Get('GearsRecastSec'),
                }
            else
                rows[#rows + 1] = {
                    name = m.name, item = 'Cuddly Bear',
                    ready = m.bearReadySec or 0, total = _config:Get('BearRecastSec'),
                }
            end
        end
    end
    for _, m in ipairs(members) do
        if m.hasGears then
            rows[#rows + 1] = {
                name = m.name, item = 'Gears',
                ready = m.gearsReadySec or 0, total = _config:Get('GearsRecastSec'),
            }
        end
    end
    if #rows == 0 then return end

    -- AllowOverlap still let both widgets register the same click — Dear ImGui
    -- doesn't actually arbitrate overlapping hit-boxes, it just quiets the hover
    -- ambiguity. The only reliable fix is non-overlapping layout: draw the
    -- toggle first in its own space, then the header starts after it via
    -- SameLine, so their hit-boxes never share any pixels.
    -- Toggle shows "running" state (green = active), not "paused" — green-while-
    -- paused would read backwards, especially since groups now start paused.
    local newRunning, changed = Widgets.Toggle('##pause_' .. label, not anyPaused)
    if changed then
        if newRunning then Rotation.RequestResume(label) else Rotation.RequestPause(label) end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(anyPaused and 'Paused — click to resume' or 'Running — click to pause')
    end

    ImGui.SameLine()
    local expanded = ImGui.CollapsingHeader(
        string.format('Group: %s (Tank)###group_%s', label, label), ImGuiTreeNodeFlags.DefaultOpen)

    if not expanded then return end

    if ImGui.BeginTable('##rows_' .. label, 3, 0) then
        ImGui.TableSetupColumn('Name',   ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableSetupColumn('Item',   ImGuiTableColumnFlags.WidthFixed, 85)
        ImGui.TableSetupColumn('Recast', ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableHeadersRow()

        for _, row in ipairs(rows) do
            ImGui.TableNextRow()
            ImGui.TableNextColumn(); ImGui.Text(row.name)
            ImGui.TableNextColumn(); ImGui.Text(row.item)
            ImGui.TableNextColumn()
            Widgets.RecastBar(row.ready, row.total, -1)
        end
        ImGui.EndTable()
    end
end

local function renderMissing()
    local missing = Roster.MissingFromMyGroup()
    if #missing == 0 then return end

    ImGui.TextColored(ImVec4(1.0, 0.65, 0.0, 1.0),
        string.format('Not reporting in: %s', table.concat(missing, ', ')))
    for _, name in ipairs(missing) do
        ImGui.SameLine()
        if ImGui.Button('Launch ' .. name .. '##launch_' .. name) then
            Roster.LaunchNow(name)
        end
    end
end

local function renderSettings()
    if not ImGui.CollapsingHeader('Settings') then return end

    if ImGui.BeginTable('##syssettings', 2, 0) then
        ImGui.TableSetupColumn('##slbl', ImGuiTableColumnFlags.WidthFixed, 130)
        ImGui.TableSetupColumn('##sctl', ImGuiTableColumnFlags.WidthStretch)

        ImGui.TableNextRow()
        ImGui.TableNextColumn(); ImGui.Text('Auto-launch Missing')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('When a group member isn\'t reporting in, automatically fire /dex <name> /lua run prozp on them (via DanNet)')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local autoLaunch = _config:Get('AutoLaunchMissing')
        local newAutoLaunch, alChanged = Widgets.Toggle('##autolaunch', autoLaunch)
        if alChanged then _config:SetAndSave('AutoLaunchMissing', newAutoLaunch) end

        ImGui.EndTable()
    end
end

local function renderConsole()
    if not ImGui.CollapsingHeader('Console') then return end

    if ImGui.BeginTable('##debugopts', 2, 0) then
        ImGui.TableSetupColumn('##dlbl', ImGuiTableColumnFlags.WidthFixed, 115)
        ImGui.TableSetupColumn('##dctl', ImGuiTableColumnFlags.WidthStretch)

        ImGui.TableNextRow()
        ImGui.TableNextColumn(); ImGui.Text('Log Level')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('How much detail do you want in the console window?')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn(); ImGui.SetNextItemWidth(-1)
        local levelIdx = _config:Get('LogLevel') or 3
        local newLevelIdx, levelChanged = ImGui.Combo('##loglevel', levelIdx,
            Logger.LevelLabels(), #Logger.LevelLabels())
        if levelChanged then _config:SetAndSave('LogLevel', newLevelIdx) end

        ImGui.TableNextRow()
        ImGui.TableNextColumn(); ImGui.Text('Log to File')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Create a local log file of the Console events')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local logToFile = _config:Get('LogToFile')
        local newLogToFile, fileChanged = Widgets.Toggle('##logtofile', logToFile)
        if fileChanged then _config:SetAndSave('LogToFile', newLogToFile) end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text('Writes to ConsoleLogs_<Server>_<Char>.log')
            ImGui.EndTooltip()
        end

        ImGui.TableNextRow()
        ImGui.TableNextColumn(); ImGui.Text('Show Timestamps')
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.PushTextWrapPos(280)
            ImGui.TextWrapped('Add Timestamps to the local log file, if Log to File is enabled')
            ImGui.PopTextWrapPos()
            ImGui.EndTooltip()
        end
        ImGui.TableNextColumn()
        local logTs = _config:Get('LogTimestamps')
        local newLogTs, tsChanged = Widgets.Toggle('##logts', logTs)
        if tsChanged then _config:SetAndSave('LogTimestamps', newLogTs) end

        ImGui.EndTable()
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader('ProZP Output', ImGuiTreeNodeFlags.DefaultOpen) then
        local conW = select(1, ImGui.GetContentRegionAvail())
        Logger.GetConsole():Render(ImVec2(conW, 180))
    end
end

function Panel.Render()
    if not _config then return end

    -- Mini mode: show the compact overlay, hide the main window entirely.
    if _miniMode then
        Mini.Render(function() _miniMode = false end)
        renderDevInfo()
        return
    end

    if _panelOpen then
        ImGui.SetNextWindowSize(ImVec2(420, 520), ImGuiCond.FirstUseEver)
        local open, shouldDraw = ImGui.Begin('ProZP', _panelOpen)
        if open ~= _panelOpen then
            _config:SetAndSave('PanelOpen', open)
        end
        _panelOpen = open

        if shouldDraw then
            -- Minimize button — top right, y aligned to content start.
            local _savedPos    = ImGui.GetCursorPosVec()
            local contentMaxX = select(1, ImGui.GetContentRegionMax())
            ImGui.SetCursorPos(ImVec2(contentMaxX - 18, _savedPos.y))
            if ImGui.SmallButton(Icons.FA_COMPRESS) then
                _miniMode = true
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text('Activate Mini Mode')
                ImGui.EndTooltip()
            end
            ImGui.SetCursorPos(_savedPos)

            drawHeader()

            if ImGui.Button('Pause All') then Rotation.RequestPause(nil) end
            ImGui.SameLine()
            if ImGui.Button('Resume All') then Rotation.RequestResume(nil) end

            ImGui.Separator()
            renderMissing()
            ImGui.Separator()

            for _, label in ipairs(Roster.KnownGroupLabels()) do
                renderGroupSection(label)
            end

            ImGui.Separator()
            renderSettings()
            ImGui.Spacing()
            renderConsole()
        end
        ImGui.End()
    end

    renderDevInfo()
end

return Panel
