-- Tracks who's reporting in via heartbeat broadcasts, both for my own real EQ group
-- (ground truth for Rotation's turn-taking) and fleet-wide across every group (for the
-- UI dashboard). Also flags real group members who never show up and, if MQ2DanNet is
-- loaded, auto-launches the script on them.

local mq     = require('mq')
local Roles  = require('prozp.core.roles')
local Comms  = require('prozp.core.comms')
local Logger = require('prozp.utils.logger')

local Roster = {}

local _config    = nil
local _startedAt = nil

-- name -> { name, groupId, isTank, hasGears, hasBear, gearsReadySec, paused, lastSeen }
local _members = {}

-- Real EQ group member names, including self; refreshed every Tick()
local _myGroupNames = {}

-- name -> { attempts, nextAttemptAt }
local _launchState = {}

local function refreshMyGroup()
    local names = { [Roles.MyName()] = true }
    local size = mq.TLO.Group.GroupSize() or 0
    for i = 1, size - 1 do
        local member = mq.TLO.Group.Member(i)
        local name = member and member.Name()
        if name then names[name] = true end
    end
    _myGroupNames = names
end

function Roster.IsMyGroupMember(name)
    return _myGroupNames[name] == true
end

-- Stable per-group label for the fleet UI: the tank's name. Converges once that
-- toon's heartbeat (isTank=true) has been seen; until then falls back to my own name.
function Roster.MyGroupId()
    if Roles.IsTank() then return Roles.MyName() end
    for name in pairs(_myGroupNames) do
        local m = _members[name]
        if m and m.isTank then return m.name end
    end
    return Roles.MyName()
end

function Roster.Init(config)
    _config    = config
    _startedAt = mq.gettime()
    refreshMyGroup()

    Comms.On('heartbeat', function(content)
        -- Debug-only: hasGears flipping on an already-known member is exactly the kind
        -- of transient signal that could make activeHolderNames() drop someone for a
        -- single Tick(), tripping Rotation's turn-fallback even though nothing really
        -- changed — see the turn-fallback log in rotation.lua. Only logs on an actual
        -- change, not every heartbeat, so it's cheap even when it does fire.
        local prev = _members[content.name]
        if prev and prev.hasGears ~= content.hasGears then
            Logger.Debug('hasGears flipped for %s: %s -> %s (received by %s)',
                content.name, tostring(prev.hasGears), tostring(content.hasGears), Roles.MyName())
        end

        _members[content.name] = {
            name                  = content.name,
            groupId               = content.groupId,
            isTank                = content.isTank,
            hasGears              = content.hasGears,
            hasBear               = content.hasBear,
            gearsReadySec         = content.gearsReadySec,
            bearReadySec          = content.bearReadySec,
            nextGearsRemainingSec = content.nextGearsRemainingSec,
            nextGearsIntervalSec  = content.nextGearsIntervalSec,
            paused                = content.paused,
            lastSeen              = mq.gettime(),
        }
    end)
end

-- Currently-active members of MY OWN real EQ group. This is the ground truth Rotation
-- uses for building the holder queue and the Little Buddy ack set — never the eventually-
-- consistent groupId label below, which is display-only.
function Roster.MyActiveMembers()
    local now, graceMs, out = mq.gettime(), _config:Get('RosterGraceSec') * 1000, {}
    for name in pairs(_myGroupNames) do
        local m = _members[name]
        if m and (now - m.lastSeen) < graceMs then
            out[#out + 1] = m
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Fleet-wide: true if any known member, in any group, is currently paused. Pause/Resume
-- broadcasts apply to every instance in a group at once, so any one member's flag is
-- representative of that whole group — used by the mini overlay's single Pause All /
-- Resume All toggle, which has no per-group concept of its own.
function Roster.AnyPaused()
    for _, m in pairs(_members) do
        if m.paused then return true end
    end
    return false
end

-- Fleet-wide view: every group label seen so far (for the dashboard's section list)
function Roster.KnownGroupLabels()
    local seen, out = {}, {}
    for _, m in pairs(_members) do
        local label = m.groupId or m.name
        if not seen[label] then
            seen[label] = true
            out[#out + 1] = label
        end
    end
    table.sort(out)
    return out
end

function Roster.MembersByGroupLabel(label)
    local out = {}
    for _, m in pairs(_members) do
        if (m.groupId or m.name) == label then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Roster.MissingFromMyGroup()
    if not _startedAt then return {} end
    local now = mq.gettime()
    if (now - _startedAt) < (_config:Get('RosterGraceSec') * 1000) then return {} end

    local graceMs, out = _config:Get('RosterGraceSec') * 1000, {}
    for name in pairs(_myGroupNames) do
        if name ~= Roles.MyName() then
            local m = _members[name]
            if not m or (now - m.lastSeen) >= graceMs then
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

local function attemptLaunch(name)
    if not _config:Get('AutoLaunchMissing') then return end
    if not mq.TLO.Plugin('MQ2DanNet').IsLoaded() then
        Logger.Warn('%s is not reporting in - MQ2DanNet not loaded, cannot auto-launch', name)
        return
    end

    local state = _launchState[name]
    if not state then
        state = { attempts = 0, nextAttemptAt = 0 }
        _launchState[name] = state
    end
    if state.attempts >= _config:Get('LaunchMaxRetries') then return end

    local now = mq.gettime()
    if now < state.nextAttemptAt then return end

    state.attempts      = state.attempts + 1
    state.nextAttemptAt = now + (_config:Get('LaunchCooldownSec') * 1000)
    Logger.Warn('%s is not running ProZP - launching via DanNet (attempt %d/%d)',
        name, state.attempts, _config:Get('LaunchMaxRetries'))
    mq.cmdf('/dex %s /lua run prozp', name)
end

-- Manual override from the UI: ignore cooldown/retry-cap and fire immediately
function Roster.LaunchNow(name)
    _launchState[name] = { attempts = 0, nextAttemptAt = 0 }
    attemptLaunch(name)
end

function Roster.Tick()
    refreshMyGroup()

    for _, name in ipairs(Roster.MissingFromMyGroup()) do
        attemptLaunch(name)
    end

    -- Clear launch state once a toon reports back in
    for name in pairs(_launchState) do
        if _myGroupNames[name] and _members[name] then
            _launchState[name] = nil
        end
    end
end

return Roster
