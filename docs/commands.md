# Slash Command Reference

All ProZP commands start with `/prozp` followed by a subcommand.

---

## Starting and Stopping

| Command | Description |
|---------|-------------|
| `/lua run prozp` | Start ProZP |
| `/lua stop prozp` | Stop ProZP completely |

---

## Group Control

| Command | Description |
|---------|-------------|
| `/prozp pause` | Pause the rotation on **every group** at once (fleet-wide) |
| `/prozp resume` | Resume the rotation on **every group** at once (fleet-wide) |

To pause or resume just *one* group instead of the whole fleet, use that group's pause toggle
in the panel — see [`README.md`](../README.md#the-main-window).

---

## Interface

| Command | Description |
|---------|-------------|
| `/prozp show` | Restore the main panel if it has been closed *or* minimized |
| `/prozp hide` | Close the main panel |
| `/prozp mini` | Toggle Mini Mode on/off |
| `/prozp mini on` | Force Mini Mode on |
| `/prozp mini off` | Force Mini Mode off (equivalent to `/prozp show`) |

Mini Mode collapses the panel into a small titleless overlay — logo, app name, and a single
Pause All / Resume All toggle. Click the logo to restore the main window. Unlike `PanelOpen`,
Mini Mode isn't saved between sessions — it always starts off on a fresh `/lua run prozp`.

---

## Settings

```
/prozp set <setting> <value>
```

Changes a config setting by name. Setting names are case-insensitive.

### Examples

```
/prozp set gearsrecastsec 690
/prozp set allowearlygears false
/prozp set expeditionrecallcommand #sendmeexpedition
/prozp set waitforzoneclear true
/prozp set autolaunchmissing true
/prozp set logtofile true
/prozp set loglevel 4
```

### All Settable Keys

<div align="center">

| Key | Type | Shared | Example Values |
|-----|------|--------|-----------------|
| `ItemGears` | string | Yes | `Gears of Improved Life` |
| `ItemBear` | string | Yes | `Cuddly Bear of Mass Rage: Click for Zone-Wide Aggro! (Timekeep)` |
| `ItemLittleBuddy` | string | Yes | `Little Buddy Confidence Booster 5000` |
| `ExpeditionRecallCommand` | string | Yes | `#sendmeexpedition` (empty string disables it) |
| `GearsRecastSec` | number | Yes | `690` |
| `BearRecastSec` | number | Yes | `1.5` |
| `HeartbeatIntervalSec` | number | Yes | `8` |
| `RosterGraceSec` | number | Yes | `20` |
| `LittleBuddyPauseSec` | number | Yes | `4` |
| `PostPullDelaySec` | number | Yes | `180` |
| `AllowEarlyGears` | boolean | Yes | `true`, `false` |
| `WaitForZoneClear` | boolean | Yes | `true`, `false` |
| `ZoneClearRadius` | number | Yes | `0` (whole zone) |
| `ZoneClearCheckDelaySec` | number | Yes | `15` |
| `ZoneClearMaxWaitSec` | number | Yes | `120` |
| `WaitForLootSweep` | boolean | Yes | `true`, `false` |
| `AutoLaunchMissing` | boolean | Yes | `true`, `false` |
| `LaunchCooldownSec` | number | Yes | `60` |
| `LaunchMaxRetries` | number | Yes | `3` |
| `LogLevel` | number | No (per-character) | `1` (Error), `2` (Warn), `3` (Info), `4` (Debug) |
| `LogToFile` | boolean | No (per-character) | `true`, `false` |
| `LogTimestamps` | boolean | No (per-character) | `true`, `false` |

</div>

Full explanation of every setting in [Configuration](configuration.md).

---

## Help

Running `/prozp` with no subcommand, or an unrecognized one, prints a summary of available
commands to chat.
