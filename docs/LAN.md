# MapSync LAN FoW sync (0.4.1-poc)

Either player explores → the other minimap turns gray. **No need to open `lan_bridge.exe` manually** for same-house LAN.
Press **F10** to force a two-way dump.

## What 0.4.1 combines

- **0.3.3**: auto-start / auto-kill `Mods/MapSync/Bin/lan_bridge.exe`
- **0.4.0**: bidirectional TILES/POS, F10 + `SYNC_REQ`, Steam/TCP scaffold ([`STEAM.md`](STEAM.md))
- FoW rebind after dungeon ↔ overworld (`ClientRestart`)

## On both PCs (LAN / same house)

1. Replace `ue4ss\Mods\MapSync` (must include `Bin\lan_bridge.exe`).
2. Confirm log: `MapSync 0.4.1-poc` and `boot bridge ok=true`.
3. Steam co-op → world → **F7** once.
4. Either player explores (dungeon + overworld). The other minimap should update.
5. Optional: **F10** for a full two-way sync.
6. After each zone change, wait ~3s for auto-rebind (`world changed` / `rebound after zone change`).
7. Quit the game → bridge process should exit (`shutdown bridge`).

Windows Firewall may ask once to allow `lan_bridge.exe` — allow on private networks.

For remote TCP / Steam bridge steps: [`STEAM.md`](STEAM.md).

## Config (`Scripts/config.lua`)

```lua
AutoStartBridge = true
AutoKillBridgeOnExit = true
BidirectionalSync = true
Transport = "lan"   -- or "tcp" / "steam" with steam_bridge (manual for now)
ForceLanRole = nil  -- or "Host" / "Client" if NetMode stays Unknown
```

## ForceLanRole (if needed)

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

Send `[MapSync][FoW]` / `[MapSync][LAN]` from both logs (look for `boot bridge`, `force_sync`, `world changed`, `send TILES`, `apply`).
