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
- Minimap visibly changes after the probe

Then set `EnableLanSync = true` and run `tools/lan_bridge` on both PCs.

### NO-GO

- `VIABILITY=NO-GO`
- No useful candidates in the dump
- Reveal calls error / no visual change

Stop. Attach the dump file and UE4SS log before trying deeper RE or alternate approaches. Do not enable LAN sync.
