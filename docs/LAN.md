# MapSync LAN FoW sync (0.3.2-poc)

One-step retest: host explores → client minimap turns gray (also after zone changes).

## What 0.3.2 fixes

After leaving a dungeon for overworld, FoW objects were still bound to the **old** zone, so new exploration stopped syncing. Now each `ClientRestart` rebinds FoW, clears tile caches, and forces a fresh TILES pass.

## On both PCs

1. Replace `ue4ss\Mods\MapSync` (confirm log: `MapSync 0.3.2-poc`).
2. Run `tools\lan_bridge\lan_bridge.exe` on both.
3. Co-op → world → **F7** once.
4. Host explores (dungeon and overworld). Client minimap should update in **both**.
5. After each zone change, wait ~3s for auto-rebind (log: `world changed` / `rebound after zone change`).

## ForceLanRole (if needed)

In `Mods/MapSync/Scripts/config.lua`:

- Host PC: `ForceLanRole = "Host",`
- Client PC: `ForceLanRole = "Client",`

## What this syncs / does not sync

| Syncs | Does **not** sync yet |
| --- | --- |
| Fog-of-war / explored gray areas | Chest / item / loot icons on the map |
| Host trail via `POS` (fallback) | Objectives / quest markers |

Map icons are a separate Remnant system from FoW tiles.

## If it fails

Send `[MapSync][FoW]` / `[MapSync][LAN]` from both logs, especially around zone changes (`ClientRestart`, `world reset`, `send TILES`, `apply`).
