# MapSync validation checklist

## Goal

Prove we can **read** and **reveal** Remnant 2 minimap FoW tiles via UE4SS reflection **before** spending time on networking.

## Steps

1. Install UE4SS + drop in `Mods/MapSync` (see README).
2. Launch Remnant 2, load into a world (solo is fine).
3. Press **F6** — confirm a dump appears in `%TEMP%\MapSyncLogs\`.
4. Press **F7** — watch on-screen status / UE4SS log.

## Decision

### GO

- Log line: `VIABILITY=GO`
- Status: `FoW OK`
- Strategy mentions `ExplorableMinimapManager` / `RevealHiddenArea` / `ToggleFogOfWar` / `RevealRange`
- **Minimap visibly changes** after the probe (fog toggles or tiles reveal)

Then set `EnableLanSync = true` and run `tools/lan_bridge` on both PCs.

### NO-GO

- `VIABILITY=NO-GO`
- No live `ExplorableMinimapManager` instance found
- All strategies fail / no visual change

Send the new `UE4SS.log` + `%TEMP%\MapSyncLogs\fow_dump_*.txt`. Do not enable LAN sync yet.

## Remnant-specific targets (from live dump)

- `GunfireRuntime.ExplorableMinimapManager` (`EnableFogOfWar`, `GetExplorableMinimapModel`)
- `GunfireRuntime.ExplorableMinimapModel` / `Remnant.ExplorableMinimapModelRemnant` (`RevealHiddenArea`)
- `GunfireRuntime.ExplorableMinimapComponent` (`RevealRange`)
- `Remnant.RemnantCheatManager:ToggleFogOfWar`
- `Remnant.RemnantPlayerController:ClientUpdateFogOfWar`
