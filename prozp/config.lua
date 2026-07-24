-- INI-based settings: load/save defaults for item names, timing, and toggles
--
-- Two INI files are used:
--   SharedSettings_<Server>.ini        — group-wide settings; written by any toon, read by all at startup
--   CharSettings_<Server>_<Name>.ini   — per-character overrides (LogLevel, UI state)
--
-- Load order: defaults → shared INI → per-character INI (later layers win).
-- Save: shared keys write to both files; per-character keys write only to per-char file.

local mq = require('mq')

local function fileExists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local Config = {}

local _cfgDir = nil
local function prozpDir()
    if not _cfgDir then
        _cfgDir = mq.configDir .. '/ProZP'
        local ok, _, code = os.rename(_cfgDir, _cfgDir)
        if not ok and code ~= 13 then
            os.execute('mkdir "' .. _cfgDir .. '"')
        end
    end
    return _cfgDir
end

local _serverTag = nil
local function serverTag()
    if not _serverTag then
        _serverTag = mq.TLO.EverQuest.Server():gsub(' ', '_')
    end
    return _serverTag
end

local function iniPath()
    return string.format('%s/CharSettings_%s_%s.ini', prozpDir(), serverTag(), mq.TLO.Me.CleanName())
end

local function sharedIniPath()
    return string.format('%s/SharedSettings_%s.ini', prozpDir(), serverTag())
end

-- Default values — all settings live here; add new keys here first
Config.Defaults = {
    -- Item names (exact match — used for both /useitem and FindItem lookups)
    ItemGears       = 'Gears of Improved Life',
    ItemBear        = 'Cuddly Bear of Mass Rage: Click for Zone-Wide Aggro! (Timekeep)',
    ItemLittleBuddy = 'Little Buddy Confidence Booster 5000',

    -- Said by the holder about to click Gears, immediately before clicking it —
    -- recalls everyone in the zone to the zone-in spot, which is where the Gears
    -- repop would send stragglers anyway. Empty string disables it.
    ExpeditionRecallCommand = '#sendmeexpedition',

    -- Nominal recast lengths, used to scale the UI recast bars and to pace the flat
    -- Gears schedule below (see AllowEarlyGears for how live TimerReady factors in).
    -- 690 (not the item tooltip's round 600/10min) matches what an overnight test
    -- run showed as the item's real recast — the flat schedule was consistently
    -- landing ~90s ahead of actual TimerReady on every tank, every cycle.
    GearsRecastSec = 690,
    BearRecastSec  = 1.5,

    -- Timing
    HeartbeatIntervalSec = 8,    -- how often (and on state change) a toon reports in
    RosterGraceSec       = 20,   -- grace before a silent group member is flagged missing
    LittleBuddyPauseSec  = 4,    -- flat delay between a Gears repop and the Little Buddy click

    -- Flat, unconditional delay after any Bear pull before the next Gears click
    -- is allowed — prevents an instant repop wasting the pull that was just
    -- made. Applies regardless of WaitForZoneClear below.
    PostPullDelaySec = 180,

    -- GearsRecastSec is a nominal guess, not the item's real live cooldown, so the
    -- flat schedule above is often more conservative than the item actually needs
    -- (real recast finishes early, sitting idle until nextGearsAt catches up). When
    -- on, the current turn-holder may fire as soon as their own Item.TimerReady()
    -- says ready — but never faster than one *more* holder than currently active
    -- would pace at (e.g. a solo holder's 10-minute wait can shrink to 5, never
    -- down to the large-group PostPullDelaySec floor). This only ever fires
    -- *sooner*, never blocks/delays a click — TimerReady is never a withholding
    -- gate, only a bounded local early-out — so it can't reintroduce the
    -- cross-character stall class described above.
    AllowEarlyGears  = true,

    -- Master switch for the zone-clear gate. Off by default: repops are paced
    -- purely by turn + each holder's own Gears recast (10 min solo, ~5 min
    -- alternating between two, etc.) with no extra condition. Turn on only if
    -- a given zone's mobs reliably converge fast enough that waiting for a
    -- true zero-NPC reading doesn't stall the rotation.
    WaitForZoneClear       = false,

    -- Zone-clear gate: after any Bear pull, the tank waits this long (to let the
    -- pulled mobs actually arrive and engage) before it starts polling for NPCs,
    -- then holds off on the next Gears repop until that count drops to zero.
    -- 0 = whole zone (the Bear pulls everything, so a radius can read "clear"
    -- during a lull while mobs are still alive but just not near the tank).
    -- Set a positive value to scope the check to a radius instead.
    ZoneClearRadius        = 0,
    ZoneClearCheckDelaySec = 15,
    -- Safety valve for the zone-wide check: if a stray non-combat NPC (banker,
    -- quest-giver, etc.) means the count never hits zero, give up waiting after
    -- this long and unlock the repop anyway rather than stalling forever.
    ZoneClearMaxWaitSec    = 120,

    -- Also hold the repop until nearby corpses are gone (loot sweep finished),
    -- regardless of which addon/framework is actually doing the looting.
    WaitForLootSweep       = true,

    -- Missing-toon auto-launch (via DanNet)
    AutoLaunchMissing = false,
    LaunchCooldownSec = 60,
    LaunchMaxRetries  = 3,

    -- Debug / logging (per-character)
    LogLevel      = 3,        -- 1=Error 2=Warn 3=Info 4=Debug
    LogToFile     = false,
    LogTimestamps = false,

    -- UI state (per-character)
    PanelOpen = true,
}

-- Keys written to the shared INI so all toons inherit them on startup.
-- Per-character keys (LogLevel, UI state) are intentionally excluded.
local SHARED_KEYS = {
    ItemGears            = true,
    ItemBear             = true,
    ItemLittleBuddy      = true,
    ExpeditionRecallCommand = true,
    GearsRecastSec       = true,
    BearRecastSec        = true,
    HeartbeatIntervalSec = true,
    RosterGraceSec       = true,
    LittleBuddyPauseSec  = true,
    PostPullDelaySec       = true,
    AllowEarlyGears        = true,
    WaitForZoneClear       = true,
    ZoneClearRadius        = true,
    ZoneClearCheckDelaySec = true,
    ZoneClearMaxWaitSec    = true,
    WaitForLootSweep       = true,
    AutoLaunchMissing    = true,
    LaunchCooldownSec    = true,
    LaunchMaxRetries     = true,
}

-- Live config table — starts as a copy of defaults, then overwritten by INI
Config.Settings = {}

local function toBool(v)
    if type(v) == 'boolean' then return v end
    if v == nil then return false end
    return tostring(v):lower() == 'true' or tostring(v) == '1'
end

local function coerce(default, raw)
    if raw == nil then return default end
    local t = type(default)
    if t == 'boolean' then return toBool(raw) end
    if t == 'number'  then return tonumber(raw) or default end
    return tostring(raw)
end

local function readIni(iniFile, settings, defaults)
    if not fileExists(iniFile) then return end
    for k, default in pairs(defaults) do
        local raw = mq.TLO.Ini(iniFile, 'prozp', k, tostring(default))()
        settings[k] = coerce(default, raw)
    end
end

function Config:Load()
    -- Layer 1: defaults
    for k, v in pairs(self.Defaults) do
        self.Settings[k] = v
    end

    -- Layer 2: shared INI (group-wide settings)
    readIni(sharedIniPath(), self.Settings, self.Defaults)

    -- Layer 3: per-character INI (individual overrides)
    readIni(iniPath(), self.Settings, self.Defaults)
end

function Config:Save()
    local ini    = iniPath()
    local shared = sharedIniPath()
    for k, v in pairs(self.Settings) do
        mq.cmdf('/ini "%s" "prozp" "%s" "%s"', ini, k, tostring(v))
        if SHARED_KEYS[k] then
            mq.cmdf('/ini "%s" "prozp" "%s" "%s"', shared, k, tostring(v))
        end
    end
end

function Config:Get(key)
    if self.Settings[key] == nil then
        return self.Defaults[key]
    end
    return self.Settings[key]
end

function Config:Set(key, value)
    self.Settings[key] = coerce(self.Defaults[key], value)
end

function Config:SetAndSave(key, value)
    self:Set(key, value)
    self:Save()
end

-- Call once at startup
function Config:Init()
    self:Load()
end

return Config
