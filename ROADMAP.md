# ProZP Roadmap

## Completed

- **v0.1.0 — Initial release.** Detects Gears of Improved Life holders per real EQ group and
  stages an alphabetical, evenly-staggered rotation between them. Little Buddy rebuff and Bear
  pull sequenced automatically after every repop. Fleet dashboard shows every detected group
  (tank + holders only), with live recast bars and per-group / global Pause-Resume. Detects
  group members not reporting in and auto-launches them via DanNet.

- **v0.1.1 — Deadlock fix, flat-timer rewrite.** A real 35+ minute stall was traced to two Gears
  holders each believing it was the *other's* turn — the deployed build was still running an
  older queue/pointer-based tracker where every instance discovers itself first and inserts the
  other holder ahead of itself, producing a symmetric deadlock. Fixed by recomputing the
  canonical, alphabetically-sorted holder list fresh on every check instead of maintaining a
  mutable per-instance queue. At the same time, rotation pacing was simplified to a flat
  wall-clock timer (`GearsRecastSec / active holder count`) instead of gating on live item
  recast or waiting for Little Buddy ack broadcasts — both were cross-character reads that could
  desync and stall the whole group.

- **v0.1.2 — Log line attribution.** Log lines were tagged only with the group label (the
  tank's name), so every group member's log file showed the identical tag with no way to tell
  which character actually wrote a given line. Every line now also carries the logging
  character's own name.

- **v0.1.3 — `AllowEarlyGears`.** `GearsRecastSec` is a nominal guess, not the item's real
  cooldown, so the flat schedule was often more conservative than necessary. On by default: the
  current turn-holder can fire as soon as its own item is actually off recast, bounded so it
  never fires faster than one more holder than currently active would pace at.

- **v0.1.4 — `ExpeditionRecallCommand`.** The holder about to click Gears now says
  `#sendmeexpedition` (configurable) just before clicking, recalling stragglers to the zone-in
  spot ahead of the repop that would send them there anyway.

- **v0.1.5 — Per-sender dedup fix.** `cycleId` is each holder's own independent local counter,
  but the guard deciding whether a `gears_fired` broadcast was new compared every sender's
  counter against one shared high-water-mark — two holders' counters reaching the same value
  made the second holder's legitimate click look like a stale duplicate, silently swallowing it
  (best case, one wasted extra click; worst case, Little Buddy/Bear stuck until the original
  deadline arrived, discarding an early click entirely). The dedup guard is now tracked per
  sender name.

- **v0.1.6 — `TimerReady` gate on the actual click.** The scheduled Gears click used to fire
  blind the instant the flat deadline arrived, even if the real item wasn't actually off
  cooldown (e.g. leftover recast from before a restart) — `UseItem` has no success readback, so
  that click silently failed in-game while Little Buddy, the Bear pull, and turn advance all
  proceeded as if it had worked. The click now waits for the item's own `TimerReady` too — purely
  local and re-polled every ~100ms, so worst case is a short wait, never a stall.

- **v0.1.7 — `GearsRecastSec` recalibration.** An overnight multi-hour test run showed a
  consistent ~90s gap between the flat schedule's deadline and the item's real `TimerReady` on
  every tank, every cycle. Bumped the default from 600 to 690 to match; the v0.1.6 gate already
  made the mismatch harmless, this just removes the wasted wait.

- **v0.1.8 — Turn-fallback diagnostics.** A rare live incident (two holders in the same group
  clicking Gears in the same second, wasting a charge but not stalling or desyncing anything)
  pointed at `currentTurn()`'s "restart from the top" fallback being reachable from a single
  stale/transient `hasGears` heartbeat reading, not just a real holder leaving. Added two
  Debug-only, zero-behavior-change log lines to confirm it live next time: a `hasGears` flip
  logged in Roster, and every time the turn fallback actually fires logged in Rotation.

- **v0.1.9 — Mini Mode.** Added a minimize button and compact titleless overlay, mirroring
  ProLoot's mini panel — logo, app name, status text, click the logo to restore. Since ProZP
  coordinates a whole fleet rather than one character, the overlay's single toggle controls
  Pause All / Resume All rather than any one group, with an explicit tooltip saying so. New
  `/prozp mini [on|off]` command.

---

## Not Yet Built — Backend Exists, No UI

These settings are fully wired in `config.lua` and the rotation/roster engine but have no
controls in the main panel yet — set them via [`/prozp set`](docs/commands.md) in the meantime.

- **Zone-Clear Gate controls** (`WaitForZoneClear`, `ZoneClearRadius`, `ZoneClearCheckDelaySec`,
  `ZoneClearMaxWaitSec`, `WaitForLootSweep`) — needs a collapsible settings section, likely
  alongside or near the existing Settings block.
- **Auto-Launch tuning** (`LaunchCooldownSec`, `LaunchMaxRetries`) — `AutoLaunchMissing` itself
  has a panel toggle; the retry/cooldown values are config-only.
- **Pacing tuning** (`GearsRecastSec`, `PostPullDelaySec`, `LittleBuddyPauseSec`,
  `HeartbeatIntervalSec`, `RosterGraceSec`) — number inputs, likely in a new "Pacing" settings
  section.
- **`ExpeditionRecallCommand`** — text input to change or disable it without the slash command.

---

## Ideas / Not Yet Defined

- **GitHub release automation** — `gh` CLI isn't installed on the dev machine; releases are
  currently created via the GitHub API over PowerShell by hand (see `LOCAL_DEV_NOTES.md`). A
  small release script (bump version, tag, push, create release from `BUILD_NOTES`) would remove
  the manual PowerShell step.

- **Per-group `AllowEarlyGears` / pacing overrides** — all pacing settings are currently
  fleet-wide (shared across every group on the account). If different zones/groups warrant
  different `GearsRecastSec` or floor values, that would need a per-group settings layer, which
  the current two-tier (shared / per-character) config model doesn't support today.

- **Crash / disconnect resilience notes** — a couple of live test sessions surfaced real-world
  failure modes worth documenting once patterns are better understood: a full character client
  crash mid-session (the rotation degrades gracefully to fewer holders, which already works),
  and a multi-character simultaneous disconnect within one real group (no ProZP-level signal
  distinguishes this from an intentional pause yet). Not a code change until there's a clearer
  picture of what, if anything, ProZP could detect or surface for either case.
