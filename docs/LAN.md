# MapSync Phase 2 — LAN sync

Use this only after Phase 1 FoW GO (F7 visibly changes the minimap).

## Goal

Host reveals map → Client receives FoW updates over LAN (UDP) while Steam still runs the game session.

## What syncs

1. **Fog enabled bit** (`EnableFogOfWar`) — proven path from Phase 1
2. **Tiles** (best-effort) from `VisitedCoordinates*` / `RevealedHiddenAreasIDs`

Steam P2P is intentionally **not** in this branch. Fork later and swap only the transport.

## Setup (both PCs)

### 1. Same MapSync build

Install/update `ue4ss\Mods\MapSync` from this branch on **both** PCs.

### 2. Enable LAN in config

Edit `ue4ss\Mods\MapSync\Scripts\config.lua` on **both** PCs:

```lua
EnableLanSync = true
```

Keep `SyncFogEnabled = true`. Leave `SyncTiles = true` unless it misbehaves.

### 3. Build / run lan_bridge on both PCs

Requirements: [Go](https://go.dev/dl/) installed.

```bat
cd tools\lan_bridge
go build -o lan_bridge.exe .
lan_bridge.exe
```

Leave the window open while playing. It watches `%TEMP%\MapSyncQueue\` and shuttles `.msg` files over UDP ports **27071** / **27072**.

Windows Firewall: allow `lan_bridge.exe` on private networks when asked.

### 4. Play

1. Host starts Remnant 2 session (Steam co-op as usual).
2. Client joins.
3. Both: enter world, press **F7** once (FoW bind + arms LAN).
4. Press **F9** to print LAN status if needed.
5. Host explores — Client minimap should update (fog and/or tiles).

## Keys

| Key | Action |
| --- | --- |
| F6 | Heavy dump (optional, can hitch) |
| F7 | FoW bind + arm LAN when EnableLanSync=true |
| F8 | Toggle status |
| F9 | Net/LAN debug; starts LAN if armed |

## Logs

- `ue4ss\UE4SS.log` — look for `LAN started`, `host sent FOG`, `applied FOG`
- Bridge console — `peer discovered`, `shipped ...`
- Queue: `%TEMP%\MapSyncQueue\outbox` and `inbox`

## Troubleshooting

- No `peer discovered`: same LAN? firewall? both bridges running?
- FoW GO but no sync: `EnableLanSync=true`? F7 after world load? F9 dump?
- Client no change: host must explore / toggle fog after LAN Connected

## Later: Steam fork

Keep `net/protocol.lua` messages (`HELLO` / `FOG` / `TILES`). Replace only `tools/lan_bridge` with a Steamworks transport. Do not rewrite FoW apply logic.
