# MapSync LAN FoW sync (0.3.3-poc)

Host explores → client minimap turns gray. **No need to open `lan_bridge.exe` manually.**

## What 0.3.3 adds

- Auto-starts `Mods/MapSync/Bin/lan_bridge.exe` when the mod loads / LAN arms
- Auto-kills the bridge when the game exits (`AutoKillBridgeOnExit=true`)
- Still rebinds FoW after dungeon ↔ overworld (`ClientRestart`)

## On both PCs

1. Replace `ue4ss\Mods\MapSync` (must include `Bin\lan_bridge.exe`).
2. Confirm log: `MapSync 0.3.3-poc` and `boot bridge ok=true`.
3. Steam co-op → world → **F7** once.
4. Host explores (dungeon + overworld). Client minimap should update.
5. Quit the game → bridge process should exit (log: `shutdown bridge`).

Windows Firewall may ask once to allow `lan_bridge.exe` — allow on private networks.

## Config (`Scripts/config.lua`)

```lua
AutoStartBridge = true
AutoKillBridgeOnExit = true
ForceLanRole = nil   -- or "Host" / "Client" if NetMode stays Unknown
```

## ForceLanRole (if needed)

- Host PC: `ForceLanRole = "Host",`
- Client PC: `ForceLanRole = "Client",`

## What this syncs / does not sync

| Syncs | Does **not** sync yet |
| --- | --- |
| Fog-of-war / explored gray areas | Chest / item / loot icons |
| Host trail via `POS` (fallback) | Quest / objective markers |

## If it fails

Send `[MapSync][FoW]` / `[MapSync][LAN]` from both logs (look for `boot bridge`, `world changed`, `send TILES`, `apply`).
