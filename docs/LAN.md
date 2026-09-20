# MapSync LAN FoW sync (0.4.0-poc)

One-step retest: either player explores → the other minimap turns gray (also after zone changes).
Press **F10** to force a two-way dump.

## What 0.4.0 adds

- **Bidirectional sync**: client also emits TILES/POS (fog stays host-authoritative).
- **F10 force sync**: push local map + `SYNC_REQ` so the peer pushes back.
- Steam/TCP bridge scaffold: see [`docs/STEAM.md`](STEAM.md).

## What 0.3.2 fixed

After leaving a dungeon for overworld, FoW objects were still bound to the **old** zone, so new exploration stopped syncing. Now each `ClientRestart` rebinds FoW, clears tile caches, and forces a fresh TILES pass.

## On both PCs

1. Replace `ue4ss\Mods\MapSync` (confirm log: `MapSync 0.4.0-poc`).
2. Run `tools\lan_bridge\lan_bridge.exe` on both (same-house), **or** `tools\steam_bridge\steam_bridge.exe` for TCP/Steam — see [`STEAM.md`](STEAM.md).
3. Co-op → world → **F7** once.
4. Either player explores. The other minimap should update.
5. Optional: **F10** to force a full two-way sync.
6. After each zone change, wait ~3s for auto-rebind (log: `world changed` / `rebound after zone change`).

## ForceLanRole (if needed)

In `Mods/MapSync/Scripts/config.lua`:

- Host PC: `ForceLanRole = "Host",`
- Client PC: `ForceLanRole = "Client",`

## What this syncs / does not sync

| Syncs | Does **not** sync yet |
| --- | --- |
| Fog-of-war / explored gray areas (both ways) | Chest / item / loot icons on the map |
| Host + client trail via `POS` | Objectives / quest markers |
| Manual F10 two-way dump | Steam P2P (TCP fallback works; Steamworks next) |

Map icons are a separate Remnant system from FoW tiles.

## If it fails

Send `[MapSync][FoW]` / `[MapSync][LAN]` from both logs, especially around zone changes (`ClientRestart`, `world reset`, `send TILES`, `force_sync`, `apply`).
