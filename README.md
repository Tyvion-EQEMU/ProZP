# ProZP

A MacroQuest **Lua** addon for the Profusion EQEMU server that automates a zone-farming loop
built around three custom clicky items — pull the whole zone, repop it, refresh buffs, repeat —
coordinated fairly across every group that's running it, without babysitting recast timers.

---

## What It Does

Three clickies drive the loop:

- **The Bear** — aggros and pulls every mob in the zone to whoever clicks it
- **Gears of Improved Life** — repops the entire zone; holder duty rotates between everyone
  in your real group who has one
- **Little Buddy** — reapplies a buff set (including regen) that needs refreshing every cycle

The cycle: the current Gears holder clicks Gears → everyone clicks Little Buddy → the tank
pulls with the Bear → repeat. ProZP tracks whose turn it is, paces repops on a flat wall-clock
schedule instead of babysitting live recast timers, and gives you a dashboard to watch and
control every group running it — from any one of your characters.

---

## Requirements

- **MacroQuest** with Lua support (MQ2Lua plugin loaded)
- **MQ2DanNet** — required for cross-character coordination (turn tracking, Little Buddy/Bear
  sequencing, the fleet dashboard, and Auto-Launch Missing). ProZP does not function without it.

---

## Installation

1. Copy the `prozp` folder into your MacroQuest `lua` directory:
   ```
   <MQ2 install path>\lua\prozp\
   ```
   The folder should contain `init.lua` directly inside it — not nested deeper.

2. Verify the structure looks like this:
   ```
   lua/
   └── prozp/
       ├── init.lua
       ├── config.lua
       ├── core/
       ├── ui/
       └── utils/
   ```

---

## First Launch

On each character you want in the rotation, type:

```
/lua run prozp
```

Every running instance discovers the others in its real EQ group automatically via DanNet —
there's nothing to configure to get started. ProZP starts **paused**: once your group has done
its first zone pull (manually, or via whatever framework you're running), click **Resume** on
the panel, or the group's row will unpause on its own once you signal it has pulled — see
[How the Rotation Works](#how-the-rotation-works) below.

---

## The Main Window

A single fleet-wide dashboard, regardless of which character it's open on:

- **Pause All / Resume All** — fleet-wide, every group at once
- **Not reporting in** — a warning strip listing real-group members who haven't checked in,
  each with a **Launch** button to fire them up via DanNet on the spot
- **One collapsible section per detected group** — labeled by tank name, with:
  - A **per-group pause toggle** (independent of Pause All/Resume All)
  - A row per item per holder — the tank's Bear, and a row for every active Gears holder —
    each with a live recast bar. The tank's Bear row shows the countdown to the *next allowed
    Gears click* while one is pending, not the Bear's own (uninteresting, ~1.5s) recast.
- **Settings** — Auto-Launch Missing toggle (see [Configuration](docs/configuration.md))
- **Console** *(collapsible)* — in-panel log output, Log Level / Log to File / Show Timestamps
  controls, matching ProLoot's console pattern

Click the version number in the header for **What's New / Dev Info** — release notes and a
link to file bugs on GitHub.

The **minimize button** (top-right of the panel) collapses ProZP into a small titleless
overlay showing just the logo, a Running/Paused toggle, and status text — click the logo to
restore the main window. Since ProZP is fleet-wide rather than per-character, that toggle
controls **Pause All / Resume All**, not any single group — the tooltip says so explicitly.

---

## How the Rotation Works

- **Turn order** is a fresh, alphabetically-sorted list of currently active Gears holders in
  your real group, recomputed every check — not an incrementally-built queue. This makes every
  character's instance agree on whose turn it is regardless of the order each one happened to
  learn about the others.
- **Pacing is a flat wall-clock timer**, not a live recast negotiation: after any Bear pull,
  every instance schedules its own next allowed Gears click at `GearsRecastSec / active holder
  count` (floored by `PostPullDelaySec`). The schedule is never blocked by another character's
  live state — only your own, and only ever to fire *sooner* (see `AllowEarlyGears` below), never
  to stall waiting on someone else.
- **The click itself still waits for the real item** — `GearsRecastSec` is a nominal pacing
  number, not a live readout, so the scheduled click only actually fires once your own item
  genuinely reports off cooldown. Worst case that's a short wait; it never silently "clicks" an
  item that's still recharging.
- **`AllowEarlyGears`** (on by default) lets the current turn-holder fire as soon as its own item
  is actually ready, instead of always waiting out the full scheduled interval — bounded so it
  can never go faster than one *more* holder than currently active would pace at.
- **`ExpeditionRecallCommand`** — said via `/say` by the holder about to click Gears, immediately
  before clicking, to recall anyone who wandered off to the zone-in spot ahead of the repop.
- Every group member clicks **Little Buddy** on a flat delay after Gears fires — no confirmation
  waited on from anyone else — and the tank pulls the **Bear** immediately after its own click.
- An optional **zone-clear gate** (off by default) can hold the next repop until the zone reads
  truly empty of NPCs/corpses, with a max-wait safety valve. See
  [Configuration](docs/configuration.md#zone-clear-gate) before turning it on.

---

## Slash Commands

Full command reference in [Commands](docs/commands.md).

```
/prozp pause              Pause every group
/prozp resume             Resume every group
/prozp show / hide        Show or hide the panel
/prozp mini [on|off]      Toggle Mini Mode
/prozp set <key> <value>  Change a setting
```

---

## Configuration

Every setting explained in [Configuration](docs/configuration.md).

---

## Per-Character vs Shared Settings

Item names, pacing (`GearsRecastSec`, `PostPullDelaySec`, `AllowEarlyGears`, the zone-clear
gate), and Auto-Launch Missing are **shared** — set once on any character, every character
picks it up on next load. `LogLevel`, `LogToFile`, `LogTimestamps`, and panel open/closed state
are **per-character**.

---

## Config Files

```
<MQ2 config dir>/ProZP/
├── SharedSettings_<Server>.ini
├── CharSettings_<Server>_<CharName>.ini
└── ConsoleLogs_<Server>_<CharName>.log   (only if Log to File is enabled)
```

The folder is created automatically on first run.

---

## Support

- Report bugs or request features via [GitHub Issues](../../issues)
- Future plans in [ROADMAP.md](ROADMAP.md)
