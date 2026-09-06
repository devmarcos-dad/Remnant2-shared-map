# MapSync LAN FoW sync (0.3.0-poc)

One-step retest: host explores → client minimap turns gray.

## On both PCs

1. Replace `ue4ss\Mods\MapSync` with this branch’s `Mods/MapSync` (config already has `EnableLanSync=true`).
2. Run the prebuilt bridge — **no Go install**:

```bat
tools\lan_bridge\lan_bridge.exe
```

Leave the window open. Allow private-network firewall if Windows asks.

3. Steam co-op → both enter the world → press **F7** once.
4. Host explores. Client opens the minimap — synced areas should go gray.

## Keys

| Key | Action |
| --- | --- |
| F7 | FoW bind + arm LAN |
| F9 | Dump role / peer / sent / applied / last error |
| F8 | Toggle on-screen status |

## If it fails

Send only log lines matching `[MapSync][FoW]` and `[MapSync][LAN]` from both PCs (`ue4ss\UE4SS.log`).

Bridge console should show peer discovery and shipped messages. Queue: `%TEMP%\MapSyncQueue\`.

## Notes

- Do **not** rebuild the bridge unless you changed Go code.
- Host sends `FOG` / `TILES` when available, plus `POS` every `HostPositionIntervalMs` as a trail fallback.
- Tile apply never treats global fog-off as success.
