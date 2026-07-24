-- Per-group rotation: whose turn it is is derived fresh, every check, from the
-- canonical alphabetically-sorted list of currently-active Gears holders — never
-- from an incrementally-built per-instance array. That distinction matters: an
-- earlier version tracked a mutable queue array that each instance built up as it
-- discovered holders one at a time, and every instance discovers *itself* first
-- (self-heartbeat loops back near-instantly) before it discovers anyone else (a
-- real cross-character broadcast, arriving a beat later). That meant each holder's
-- own instance always inserted "the other guy" ahead of itself, so two holders
-- could each end up believing it was the *other's* turn — a symmetric deadlock
-- where neither ever fires. Recomputing the canonical list fresh, and advancing
-- by name (not by array index), makes every instance agree regardless of when
-- each one happened to learn about whom.
--
-- Pacing is a flat wall-clock timer, not a live recast/ack negotiation. After any
-- Bear pull (bootstrap or end-of-cycle), every instance schedules its own next
-- allowed Gears click at now + GearsRecastSec / holderCount (floored by
-- PostPullDelaySec), recomputing holderCount fresh at that moment. Item.TimerReady()
-- is never a *cross-character* gate — only ever read from each instance's own,
-- local item state — because a real multi-hour run showed the opposite approach
-- (gating on another character's live recast + waiting for Little Buddy ack
-- broadcasts from every group member) stalling indefinitely: see the deadlock
-- example above, which is exactly the kind of live cross-character state this
-- design avoids depending on. Little Buddy has no ack-wait either — every group
-- member clicks it on a flat delay after Gears fires, and the tank pulls the Bear
-- right after its own click, with no confirmation required from anyone else.
--
-- The click itself, though, does wait on local TimerReady: UseItem is
-- fire-and-forget with no success readback, so reaching nextGearsAt while the
-- real item is still on cooldown (e.g. leftover recast from before a restart)
-- used to click blind anyway, silently failing in-game while turn/Little
-- Buddy/Bear pull all proceeded as if it had worked. Now the click waits for
-- itemReady too — since that's a purely local, ~100ms-repolled condition, the
-- worst case is a short wait, never a stall (no other instance's state is ever
-- read), so this can't reintroduce the class of bug above.
--
-- AllowEarlyGears: GearsRecastSec is a nominal guess, not the item's real live
-- cooldown, so the flat schedule is often more conservative than necessary — the
-- item sits ready, unused, until nextGearsAt catches up. When on, the current
-- turn-holder may fire the moment its *own* Item.TimerReady() says ready, but
-- never faster than earlyFloorSec() allows — the interval one *more* holder than
-- currently active would use (e.g. a solo holder can shave its 10-minute wait
-- down to 5, never all the way to the large-group PostPullDelaySec floor).
--
-- Sequence per cycle: holder-whose-turn-it-is says ExpeditionRecallCommand (pulls
-- any stragglers to the zone-in spot ahead of the repop that would send them
-- there anyway) then clicks Gears -> after LittleBuddyPauseSec, everyone clicks
-- Little Buddy and the tank pulls with the Bear -> the next Gears click is
-- scheduled from that Bear pull -> (optionally) tank polls for zone-wide
-- NPCs/corpses before unlocking the next click. A script instance only ever
-- manages its own group's rotation.

local mq     = require('mq')
local Roles  = require('prozp.core.roles')
local Comms  = require('prozp.core.comms')
local Roster = require('prozp.core.roster')
local Logger = require('prozp.utils.logger')

local Rotation = {}

local _config              = nil
local _pendingLittleBuddyAt = nil
local _lastDebugSnapshotAt  = 0

local _state = {
    currentTurnName         = nil,  -- name of whoever's turn it is; nil = not yet determined
    cycleId                 = 0,    -- last cycle *I* initiated (only meaningful if I'm a holder)
    -- Dedup guard, keyed by sender name: highest cycleId accepted FROM EACH holder.
    -- cycleId is each holder's own local counter (starts at 0, increments only on
    -- that holder's own clicks) — comparing two different holders' counters
    -- against a single shared number would cause false "duplicate" rejections
    -- every time their counters happen to reach the same value, silently
    -- swallowing a legitimate click and leaving turn/awaitingBearPull stuck until
    -- the sender's own counter climbs back past whatever the other holder last
    -- broadcast. Keying by name makes each holder's sequence independent.
    gearsCycleSeen          = {},
    -- Name + cycleId of the most recently accepted gears-fired event, for the
    -- Little Buddy / Bear-pull log lines below (which happen after the fact and
    -- have no cycleId of their own to log).
    lastFiredBy             = nil,
    lastFiredCycleId        = nil,
    -- True from the moment Gears fires until the tank actually pulls the Bear —
    -- blocks a second Gears click (e.g. by the next holder in line) from sneaking
    -- in before the Little Buddy/Bear-pull sequence for this cycle has finished.
    awaitingBearPull        = false,
    -- Starts paused: on first load the zone hasn't been pulled yet, so there's
    -- nothing to repop. Resume manually once the first pull/clear is done.
    paused                  = true,
    -- No holder clicks Gears until the tank has pulled at least once — there's
    -- nothing to "repopulate" on a zone that was never cleared to begin with.
    everPulled              = false,
    -- True from the moment the tank pulls until the zone is confirmed clear —
    -- covers both the bootstrap pull and every subsequent end-of-cycle pull.
    -- Only used when WaitForZoneClear is on.
    awaitingClear           = false,
    clearCheckAt            = nil,
    clearMaxWaitAt          = nil,
    -- Wall-clock deadline for the next Gears click, set fresh from every Bear pull
    -- (bootstrap or end-of-cycle) — this alone paces the rotation; no live recast
    -- value is ever part of the gating condition.
    nextGearsAt             = nil,
    currentIntervalSec      = nil,  -- interval used to compute nextGearsAt, for UI display
    -- Timestamp of the last Bear pull, independent of nextGearsAt (which can be far
    -- later) — the PostPullDelaySec floor for AllowEarlyGears is measured from this.
    pulledAt                = nil,
}

-- The canonical, deterministic, alphabetically-sorted list of currently active
-- Gears holder names in my own real EQ group. Identical on every instance,
-- regardless of the order in which each one happened to learn about whom —
-- Roster.MyActiveMembers() is already sorted, so this is just a filter.
local function activeHolderNames()
    local names = {}
    for _, m in ipairs(Roster.MyActiveMembers()) do
        if m.hasGears then names[#names + 1] = m.name end
    end
    return names
end

local function currentTurn()
    local names = activeHolderNames()
    if #names == 0 then return nil end
    if not _state.currentTurnName then return names[1] end
    for _, n in ipairs(names) do
        if n == _state.currentTurnName then return n end
    end
    -- Whoever's turn it was is no longer an active holder — restart from the top.
    -- Debug-only: this is also reachable from a single stale/transient heartbeat
    -- (e.g. one bad hasGears reading for the actual holder), not just a real
    -- departure — logging every time it fires makes that distinction visible after
    -- the fact instead of only being inferable from a same-second double Gears fire.
    Logger.Debug('turn fallback: currentTurnName=%s not in active list [%s] — restarting from %s',
        tostring(_state.currentTurnName), table.concat(names, ','), names[1])
    return names[1]
end

-- Advances to the holder after firedName in the current canonical list. If
-- firedName isn't in the list (e.g. they just dropped), restart from the top.
local function advanceTurn(firedName)
    local names = activeHolderNames()
    if #names == 0 then _state.currentTurnName = nil; return end
    for i, n in ipairs(names) do
        if n == firedName then
            _state.currentTurnName = names[(i % #names) + 1]
            return
        end
    end
    _state.currentTurnName = names[1]
end

-- The shared interval between Gears clicks: GearsRecastSec split evenly across
-- however many holders are currently active, floored by PostPullDelaySec so an
-- unusually large holder count (or a small GearsRecastSec) can never repop faster
-- than a pull needs time to actually land.
local function cycleIntervalSec()
    local holderCount = math.max(1, #activeHolderNames())
    return math.max(_config:Get('GearsRecastSec') / holderCount, _config:Get('PostPullDelaySec'))
end

-- Floor for AllowEarlyGears: never faster than the interval one *more* holder
-- than currently active would use. This keeps the reclaimed slack bounded by
-- holder count instead of collapsing to the flat PostPullDelaySec regardless of
-- group size — a solo holder can shave time off its 10-minute interval, but only
-- down to what a 2-holder group would pace at (5 min), never all the way to the
-- large-group floor.
local function earlyFloorSec()
    local holderCount = math.max(1, #activeHolderNames())
    return math.max(_config:Get('GearsRecastSec') / (holderCount + 1), _config:Get('PostPullDelaySec'))
end

local function handleGearsFired(content)
    local lastSeen = _state.gearsCycleSeen[content.name] or 0
    if content.cycleId <= lastSeen then return end
    _state.gearsCycleSeen[content.name] = content.cycleId
    _state.lastFiredBy      = content.name
    _state.lastFiredCycleId = content.cycleId
    _state.awaitingBearPull = true
    advanceTurn(content.name)
    _pendingLittleBuddyAt = mq.gettime() + (_config:Get('LittleBuddyPauseSec') * 1000)
    Logger.Info('[%s] Gears fired by %s (cycle %d)', Roster.MyGroupId(), content.name, content.cycleId)
end

-- Applied directly by the tank the instant it pulls (bootstrap or end-of-cycle),
-- and again by every instance on receipt of the 'pull_started' broadcast. Cheap
-- and idempotent (unlike gears_fired) so no dedup guard is needed.
local function applyPullStarted()
    local now = mq.gettime()
    _state.everPulled         = true
    _state.awaitingBearPull   = false
    _state.currentIntervalSec = cycleIntervalSec()
    _state.nextGearsAt        = now + _state.currentIntervalSec * 1000
    _state.pulledAt           = now

    if _config:Get('WaitForZoneClear') then
        _state.awaitingClear  = true
        _state.clearCheckAt   = now + (_config:Get('ZoneClearCheckDelaySec') * 1000)
        _state.clearMaxWaitAt = now + (_config:Get('ZoneClearMaxWaitSec') * 1000)
    end
end

function Rotation.Init(config)
    _config = config

    Comms.On('gears_fired', function(content)
        if Roster.IsMyGroupMember(content.name) then handleGearsFired(content) end
    end)

    Comms.On('pause', function(content)
        if content.groupId == nil or content.groupId == Roster.MyGroupId() then
            _state.paused = true
            Logger.Info('[%s] Paused', Roster.MyGroupId())
        end
    end)

    Comms.On('resume', function(content)
        if content.groupId == nil or content.groupId == Roster.MyGroupId() then
            _state.paused = false
            Logger.Info('[%s] Resumed', Roster.MyGroupId())
        end
    end)

    Comms.On('pull_started', function(content)
        if content.groupId == Roster.MyGroupId() then
            applyPullStarted()
        end
    end)

    Comms.On('zone_clear', function(content)
        if content.groupId == Roster.MyGroupId() then
            _state.awaitingClear = false
        end
    end)
end

-- 0 (default) means "whole zone" — the Bear pulls everything, so scoping to a
-- radius around the tank can read "clear" during a lull while mobs are still
-- alive but just not near the tank at that instant. A positive radius scopes
-- the check down, if that's ever preferable for a given zone.
local function spawnSearch(spawnType)
    local radius = _config:Get('ZoneClearRadius') or 0
    if radius > 0 then
        return string.format('%s radius %d%s', spawnType, radius, spawnType == 'npc' and ' nopet' or '')
    end
    return spawnType == 'npc' and 'npc nopet' or spawnType
end

-- Tank-only: the bootstrap pull, and the zone-clear poll (if enabled). The
-- end-of-cycle pull happens in Tick() instead, right after the flat Little Buddy
-- pause, since it has to run in lockstep with every other instance's Little Buddy
-- click rather than on a tank-only cadence.
local function tickTank(groupId)
    if not _state.everPulled then
        local hasBear = Roles.ItemState(_config:Get('ItemBear'))
        if hasBear then
            Roles.UseItem(_config:Get('ItemBear'))
            Logger.Info('[%s] Initial pull — I clicked the Bear', groupId)
            applyPullStarted()
            Comms.Send('pull_started', { groupId = groupId })
        end
        return
    end

    if _state.awaitingClear and mq.gettime() >= _state.clearCheckAt then
        local nearbyMobs = mq.TLO.SpawnCount(spawnSearch('npc'))() or 0
        local nearbyCorpses = 0
        if _config:Get('WaitForLootSweep') then
            nearbyCorpses = mq.TLO.SpawnCount(spawnSearch('npccorpse'))() or 0
        end
        local timedOut = _state.clearMaxWaitAt and mq.gettime() >= _state.clearMaxWaitAt

        if nearbyMobs == 0 and nearbyCorpses == 0 then
            _state.awaitingClear = false
            Logger.Info('[%s] Zone clear — repop unlocked', groupId)
            Comms.Send('zone_clear', { groupId = groupId })
        elseif timedOut then
            _state.awaitingClear = false
            Logger.Warn('[%s] Zone-clear check timed out with %d NPC(s) and %d corpse(s) still detected — unlocking repop anyway',
                groupId, nearbyMobs, nearbyCorpses)
            Comms.Send('zone_clear', { groupId = groupId })
        end
    end
end

function Rotation.Tick()
    local myName  = Roles.MyName()
    local groupId = Roster.MyGroupId()
    local now     = mq.gettime()

    if Roles.IsTank() and not _state.paused then
        tickTank(groupId)
    end

    local hasGears, gearsReadySec = Roles.ItemState(_config:Get('ItemGears'))

    if now - _lastDebugSnapshotAt >= 15000 then
        _lastDebugSnapshotAt = now
        Logger.Debug(
            '[%s] snapshot: me=%s turn=%s holders=%d hasGears=%s gearsReadySec=%s paused=%s everPulled=%s awaitingClear=%s awaitingBearPull=%s nextGearsInSec=%s',
            groupId, myName, tostring(currentTurn()), #activeHolderNames(), tostring(hasGears),
            tostring(gearsReadySec), tostring(_state.paused), tostring(_state.everPulled),
            tostring(_state.awaitingClear), tostring(_state.awaitingBearPull),
            tostring(_state.nextGearsAt and math.max(0, (_state.nextGearsAt - now) / 1000)))
    end

    -- Paced by the wall-clock schedule + whose turn it is — but the click only
    -- actually fires once TimerReady confirms the item is truly off cooldown.
    -- UseItem is fire-and-forget with no success readback, so clicking blind
    -- whenever the schedule said so (the old behavior — logged as a warning
    -- below) meant a real cooldown mismatch (e.g. leftover recast from before a
    -- restart) silently failed the click in-game while the rest of the sequence
    -- (Little Buddy, Bear pull, turn advance) proceeded anyway, onto a zone that
    -- was never actually repopulated. Requiring itemReady here only ever adds a
    -- short local wait (this same check re-runs every ~100ms) — it reads no
    -- other instance's state, so it can't reintroduce the cross-character stall
    -- class the flat schedule was built to avoid.
    local pastDeadline   = _state.nextGearsAt and now >= _state.nextGearsAt
    local pastEarlyFloor = _config:Get('AllowEarlyGears') and _state.pulledAt
        and now >= _state.pulledAt + earlyFloorSec() * 1000
    local itemReady = (gearsReadySec or 0) <= 0

    if hasGears and not _state.paused and _state.everPulled and not _state.awaitingClear
        and not _state.awaitingBearPull and (pastDeadline or pastEarlyFloor) and itemReady
        and currentTurn() == myName then
        local cycleId = _state.cycleId + 1
        _state.cycleId = cycleId
        local recallCmd = _config:Get('ExpeditionRecallCommand')
        if recallCmd and recallCmd ~= '' then
            mq.cmdf('/say %s', recallCmd)
        end
        Roles.UseItem(_config:Get('ItemGears'))
        if pastEarlyFloor and not pastDeadline then
            Logger.Info('[%s] I clicked Gears early — item ready %ds ahead of schedule (cycle %d)',
                groupId, math.floor((_state.nextGearsAt - now) / 1000), cycleId)
        elseif pastDeadline and _state.nextGearsAt then
            local lateSec = math.floor((now - _state.nextGearsAt) / 1000)
            if lateSec > 0 then
                Logger.Info('[%s] I clicked Gears (cycle %d), %ds after schedule — TimerReady wasn\'t actually clear until then',
                    groupId, cycleId, lateSec)
            else
                Logger.Info('[%s] I clicked Gears (cycle %d)', groupId, cycleId)
            end
        else
            Logger.Info('[%s] I clicked Gears (cycle %d)', groupId, cycleId)
        end
        local content = { groupId = groupId, name = myName, cycleId = cycleId }
        handleGearsFired(content)
        Comms.Send('gears_fired', content)
    end

    -- Time for my Little Buddy click? Every group member fires on this same flat
    -- schedule — no waiting for anyone else's confirmation.
    if _pendingLittleBuddyAt and now >= _pendingLittleBuddyAt then
        _pendingLittleBuddyAt = nil
        Roles.UseItem(_config:Get('ItemLittleBuddy'))
        Logger.Info('[%s] I clicked Little Buddy (%s cycle %d)', groupId, _state.lastFiredBy, _state.lastFiredCycleId)

        if Roles.IsTank() then
            local hasBear = Roles.ItemState(_config:Get('ItemBear'))
            if hasBear then
                Roles.UseItem(_config:Get('ItemBear'))
                Logger.Info('[%s] I pulled with the Bear (%s cycle %d)', groupId, _state.lastFiredBy, _state.lastFiredCycleId)
                applyPullStarted()
                Comms.Send('pull_started', { groupId = groupId })
            else
                Logger.Warn('[%s] Tank does not have the Bear item — cannot pull', groupId)
            end
        end
    end
end

function Rotation.MyPaused()
    return _state.paused
end

function Rotation.NextHolder()
    return currentTurn()
end

-- Seconds remaining before the next Gears click is due, for display on the tank's
-- "Cuddly Bear" row — which otherwise shows the Bear's own ~1.5s recast, never the
-- interesting number during the multi-minute wait between repops. Returns nil once
-- a click is actually due / not applicable.
function Rotation.NextGearsRemainingSec()
    if not _state.nextGearsAt then return nil end
    local remaining = (_state.nextGearsAt - mq.gettime()) / 1000
    return remaining > 0 and remaining or nil
end

-- The interval NextGearsRemainingSec is counting down from, for scaling the UI's
-- recast bar correctly (it can be up to GearsRecastSec, not just PostPullDelaySec).
function Rotation.NextGearsIntervalSec()
    return _state.currentIntervalSec
end

function Rotation.RequestPause(groupId)
    Comms.Send('pause', { groupId = groupId })
    if groupId == nil or groupId == Roster.MyGroupId() then
        _state.paused = true
    end
end

function Rotation.RequestResume(groupId)
    Comms.Send('resume', { groupId = groupId })
    if groupId == nil or groupId == Roster.MyGroupId() then
        _state.paused = false
    end
end

return Rotation
