# Configuration

ProZP stores settings in two INI files in your MacroQuest config directory:

- `SharedSettings_<Server>.ini` — group-wide settings; one file, shared across every character
- `CharSettings_<Server>_<CharName>.ini` — per-character overrides

You rarely need to edit these directly. Most settings are accessible via the
[`/prozp set`](commands.md) command; a few (Auto-Launch Missing, Log Level, Log to File, Show
Timestamps) also have controls in the main panel.

---

## Item Names

**Settings:** `ItemGears`, `ItemBear`, `ItemLittleBuddy`
**Shared:** Yes
**Defaults:** `Gears of Improved Life`, `Cuddly Bear of Mass Rage: Click for Zone-Wide Aggro!
(Timekeep)`, `Little Buddy Confidence Booster 5000`

Exact item names, used for both `/useitem` and inventory lookups. Only change these if your
server uses differently-named (or reskinned) versions of these clickies — the match is exact,
so a typo means ProZP will never detect you as holding the item.

---

## Expedition Recall Command

**Setting:** `ExpeditionRecallCommand`
**Shared:** Yes
**Default:** `#sendmeexpedition`

Said via `/say` by the holder about to click Gears, immediately before clicking it — recalls
anyone in the zone who wandered off back to the zone-in spot, which is where the Gears repop
would send stragglers anyway. Set to an empty string to disable it entirely:

```
/prozp set expeditionrecallcommand
```

---

## Pacing

### Gears Recast

**Setting:** `GearsRecastSec`
**Shared:** Yes
**Default:** `690`

The nominal full solo recast of Gears of Improved Life, in seconds. This paces the flat
wall-clock schedule (`GearsRecastSec / active holder count` between clicks) and scales the
recast bars in the panel. It's a nominal number, not a live readout of your item's actual
cooldown — see [How the Rotation Works](../README.md#how-the-rotation-works) for how the
schedule and the item's real `TimerReady` interact. If you consistently see log lines like
`I clicked Gears (cycle N), 90s after schedule — TimerReady wasn't actually clear until then`,
that's a sign this value is calibrated too low for your server; bump it up.

### Post-Pull Delay

**Setting:** `PostPullDelaySec`
**Shared:** Yes
**Default:** `180`

Flat, unconditional minimum delay after any Bear pull before the next Gears click is allowed —
prevents an instant repop from wasting the pull that was just made. Applies regardless of
`WaitForZoneClear`. Also the absolute floor for `AllowEarlyGears` when there are enough holders
that the recast-based interval would otherwise be shorter than this.

### Allow Early Gears

**Setting:** `AllowEarlyGears`
**Shared:** Yes
**Default:** `true`

`GearsRecastSec` is a nominal guess, not a live readout, so the flat schedule is often more
conservative than the item actually needs — without this, the item can sit ready and unused
until the scheduled deadline catches up. When on, the current turn-holder may click the moment
its own item genuinely reports ready, instead of waiting out the full scheduled interval.

Bounded so it can never fire faster than the interval **one more holder than currently active**
would pace at — a solo holder's 10-minute wait can shrink to 5, but never all the way down to
the large-group `PostPullDelaySec` floor. Reads only your own local item state, never another
character's — this can't cause the whole group to stall waiting on someone else, only ever
speeds up your own turn.

### Little Buddy Pause

**Setting:** `LittleBuddyPauseSec`
**Shared:** Yes
**Default:** `4`

Flat delay after a Gears click before every group member clicks Little Buddy (and the tank
pulls with the Bear). Gives the repop a moment to actually land before everyone re-buffs.

---

## Zone-Clear Gate

**Master switch:** `WaitForZoneClear`
**Shared:** Yes
**Default:** `false`

Off by default — repops are paced purely by turn order and each holder's own Gears recast, with
no extra condition. Turning this on makes the tank wait, after every Bear pull, until the zone
reads truly clear of NPCs (and optionally corpses) before unlocking the next Gears click.

Only turn this on if your farm zone's mobs reliably converge and die fast enough that waiting
for a genuine zero-NPC reading won't stall the rotation — a busy zone can easily never read
truly empty (a stray non-combat NPC, a straggler that wandered off) and this gate has a max-wait
safety valve for exactly that reason, but it's still slower than the default.

| Setting | Shared | Default | Description |
|---------|--------|---------|--------------|
| `ZoneClearRadius` | Yes | `0` | `0` = whole zone (recommended — the Bear pulls everything, so a radius can misread "clear" during a lull while mobs are alive but just not near the tank). Set a positive value to scope the check to a radius instead. |
| `ZoneClearCheckDelaySec` | Yes | `15` | After a Bear pull, how long the tank waits before it starts polling for NPCs — gives the pulled mobs time to actually arrive and engage. |
| `ZoneClearMaxWaitSec` | Yes | `120` | Safety valve: if the NPC/corpse count never hits zero (a stray non-combat NPC, a banker, etc.), give up waiting after this long and unlock the repop anyway rather than stalling forever. |
| `WaitForLootSweep` | Yes | `true` | Also hold the repop until nearby corpses are gone (loot sweep finished), regardless of which addon/framework is doing the looting. |

---

## Auto-Launch Missing

**Settings:** `AutoLaunchMissing`, `LaunchCooldownSec`, `LaunchMaxRetries`
**Shared:** Yes
**Defaults:** `false`, `60`, `3`
**Location:** Settings section in the main panel (`AutoLaunchMissing` only — the cooldown/retry
values are config-only for now)

When a real group member hasn't reported in (no heartbeat within `RosterGraceSec`), ProZP flags
them in the panel's "Not reporting in" warning strip. With `AutoLaunchMissing` on, it also fires
`/dex <name> /lua run prozp` on them automatically via DanNet, retrying up to `LaunchMaxRetries`
times with `LaunchCooldownSec` between attempts. With it off, use the **Launch** button next to
their name in the warning strip to fire them up manually instead.

---

## Console / Logging

*(per-character — each toon has its own values)*

### Log Level

**Setting:** `LogLevel`
**Default:** `3` (Info)
**Options:** `1` Error | `2` Warn | `3` Info | `4` Debug

How much detail shows up in the console. Debug adds a periodic rotation-state snapshot line
(turn, holder count, item readiness, time to next click) — the primary tool for diagnosing
timing or turn-order issues.

### Log to File

**Setting:** `LogToFile`
**Default:** `false`

When enabled, all console output is also written to:
```
<MQ2 config dir>/ProZP/ConsoleLogs_<Server>_<CharName>.log
```

### Show Timestamps

**Setting:** `LogTimestamps`
**Default:** `false`

Prepends a `HH:MM:SS` timestamp to each console/log line.

---

## Heartbeat / Roster

**Settings:** `HeartbeatIntervalSec`, `RosterGraceSec`
**Shared:** Yes
**Defaults:** `8`, `20`

How often (and on any state change) a character broadcasts its status to the rest of its group,
and how long another character can go silent before it's flagged as missing. Rarely need
changing — lower `RosterGraceSec` reacts faster to a dropped character but raises the risk of a
false "missing" flag during a brief lag spike.
