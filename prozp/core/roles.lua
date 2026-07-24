-- What am I: class/tank detection and item recast state for the local character only.
-- Never reaches across characters — that's Roster's job, built from broadcasted heartbeats.

local mq = require('mq')

local Roles = {}

local TANK_CLASSES = { WAR = true, PAL = true, SHD = true }

function Roles.MyName()
    return mq.TLO.Me.CleanName()
end

function Roles.MyClass()
    return mq.TLO.Me.Class.ShortName()
end

function Roles.IsTank()
    return TANK_CLASSES[Roles.MyClass()] == true
end

-- Returns hasItem (bool), readySec (number, 0 = ready to use right now)
function Roles.ItemState(itemName)
    local item = mq.TLO.FindItem('=' .. itemName)
    if not (item and item.ID() and item.ID() > 0) then return false, nil end
    return true, item.TimerReady() or 0
end

function Roles.UseItem(itemName)
    mq.cmdf('/useitem "%s"', itemName)
end

return Roles
