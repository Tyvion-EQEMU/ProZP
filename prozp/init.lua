-- Entry point: wires config, comms, roster, rotation, and UI together; drives the
-- main loop via /lua run prozp

local mq    = require('mq')
local ImGui = require('ImGui')

-- Version block — single source of truth
local Version = {
    _AppName  = 'ProZP',
    _version  = '0.1.9',
    _author   = 'Tyvion',
    _buildTag = 'Dev',
}

local Config   = require('prozp.config')
local Logger   = require('prozp.utils.logger')
local Roles    = require('prozp.core.roles')
local Comms    = require('prozp.core.comms')
local Roster   = require('prozp.core.roster')
local Rotation = require('prozp.core.rotation')
local Panel    = require('prozp.ui.panel')

Config:Init()
Logger.Init(Config)
Comms.Init()
Roster.Init(Config)
Rotation.Init(Config)
Panel.Init(Config, Version)

-----------------------------------------------------------------------
-- Command: /prozp pause | resume | show | hide | set <setting> <value>
-----------------------------------------------------------------------
mq.bind('/prozp', function(subcmd, ...)
    subcmd = (subcmd or ''):lower()
    local args = { ... }
    if subcmd == 'pause' then
        Rotation.RequestPause(nil)
        printf('\agProZP: paused (all groups)')
    elseif subcmd == 'resume' then
        Rotation.RequestResume(nil)
        printf('\agProZP: resumed (all groups)')
    elseif subcmd == 'show' then
        Panel.Show()
    elseif subcmd == 'hide' then
        Config:SetAndSave('PanelOpen', false)
    elseif subcmd == 'mini' then
        local miniArg = (args[1] or ''):lower()
        if miniArg == 'on' then
            Panel.SetMini(true)
        elseif miniArg == 'off' then
            Panel.SetMini(false)
        else
            Panel.ToggleMini()
        end
    elseif subcmd == 'set' then
        local rawKey = args[1]
        local value  = args[2]
        if rawKey and value then
            local key = nil
            for k in pairs(Config.Defaults) do
                if k:lower() == rawKey:lower() then key = k; break end
            end
            if key then
                Config:SetAndSave(key, value)
                printf('\agProZP: %s = %s', key, tostring(Config:Get(key)))
            else
                printf('\arProZP: unknown setting "%s"', rawKey)
            end
        else
            printf('\ayProZP set <setting> <value>  (e.g. /prozp set logtofile true)')
        end
    else
        printf('\ayProZP commands: pause | resume | show | hide | mini [on|off] | set <setting> <value>')
    end
end)

-----------------------------------------------------------------------
-- ImGui render callback
-----------------------------------------------------------------------
mq.imgui.init('prozp', function()
    Panel.Render()
end)

-----------------------------------------------------------------------
-- Main loop
-----------------------------------------------------------------------
printf('\agProZP v%s by %s', Version._version, Version._author)
Logger.Info('v%s started', Version._version)

local HEARTBEAT_MS  = Config:Get('HeartbeatIntervalSec') * 1000
local lastHeartbeat = 0

while true do
    mq.doevents()

    local now = mq.gettime()
    if now - lastHeartbeat >= HEARTBEAT_MS then
        lastHeartbeat = now
        local hasGears, gearsReadySec = Roles.ItemState(Config:Get('ItemGears'))
        local hasBear, bearReadySec   = Roles.ItemState(Config:Get('ItemBear'))
        Comms.Send('heartbeat', {
            groupId              = Roster.MyGroupId(),
            name                 = Roles.MyName(),
            isTank               = Roles.IsTank(),
            hasGears             = hasGears,
            hasBear              = hasBear,
            gearsReadySec        = gearsReadySec or 0,
            bearReadySec         = bearReadySec or 0,
            nextGearsRemainingSec = Rotation.NextGearsRemainingSec(),
            nextGearsIntervalSec  = Rotation.NextGearsIntervalSec(),
            paused               = Rotation.MyPaused(),
        })
    end

    Roster.Tick()
    Rotation.Tick()

    mq.delay(100)
end
