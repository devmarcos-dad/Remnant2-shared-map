# MapSync (Remnant 2) — FoW validation first

Personal UE4SS mod to answer one question first:

> Can we read/write Remnant 2 minimap Fog-of-War tiles in-process via reflection?

Only after that is a **GO** do we turn on LAN Host→Client sync.

## What this repo contains

| Path | Purpose |
| --- | --- |
| [`Mods/MapSync/`](Mods/MapSync/) | Drop-in UE4SS Lua mod (probe + status + gated LAN queue) |
| [`tools/lan_bridge/`](tools/lan_bridge/) | Tiny Go UDP bridge (Phase 2, after FoW GO) |
| [`docs/VALIDATION.md`](docs/VALIDATION.md) | How to decide GO / NO-GO |

## Requirements

1. Remnant 2 on Windows
2. [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) installed for Remnant 2  
   Typical layout:
   ```
   Remnant2\Binaries\Win64\dwmapi.dll
   Remnant2\Binaries\Win64\ue4ss\UE4SS.dll
   Remnant2\Binaries\Win64\ue4ss\Mods\
   ```
3. This mod copied to:
   ```
   Remnant2\Binaries\Win64\ue4ss\Mods\MapSync\
   ```

## Install (your PC)

1. Install UE4SS into `Remnant2\Binaries\Win64\` (experimental build recommended).
2. Copy the `Mods/MapSync` folder from this repo into `ue4ss\Mods\`.
3. Confirm `Mods/MapSync/enabled.txt` exists (empty file is fine).
4. If your UE4SS build uses `mods.txt`, add a line: `MapSync : 1`
5. Start the game. You should see UE4SS console output like `[MapSync] Ready...`.

## Phase 1 — validate FoW (do this first)

Play **solo / host local**. Keys:

| Key | Action |
| --- | --- |
| **F6** | Reflection dump (map/fog candidates → log + `%TEMP%\MapSyncLogs\`) |
| **F7** | Viability probe (bind candidate + attempt local reveal) |
| **F8** | Toggle on-screen status line |
| **F9** | Print NetMode + LAN state |

### Success = GO

1. Press **F7** (or wait for auto-probe).
2. Status shows `FoW OK`.
3. Log contains `VIABILITY=GO`.
4. **You visually confirm** the minimap/fog changed (tiles revealed).

If the log says `VIABILITY=NO-GO`, open the dump under `%TEMP%\MapSyncLogs\`, note candidate classes, and stop — do **not** enable LAN yet.

### Config

Edit [`Mods/MapSync/Scripts/config.lua`](Mods/MapSync/Scripts/config.lua):

- `EnableLanSync = false` until GO is confirmed visually.
- Hot-reload with UE4SS **Ctrl+R** while idle (not during level load).

## Phase 2 — LAN sync (only after GO)

Same-house co-op: Steam still runs the game session; MapSync uses a parallel LAN channel.

1. Set `EnableLanSync = true` in `config.lua` on **both** PCs.
2. Build/run the bridge on **both** PCs:
   ```bat
   cd tools\lan_bridge
   go build -o lan_bridge.exe .
   lan_bridge.exe
   ```
3. Keep the bridge running while you play. It watches `%TEMP%\MapSyncQueue\` and shuttles messages over UDP (ports `27071` / `27072`).
4. Host + Client both load MapSync. Status should move `Searching` → `Connected` / `Syncing`.

Firewall: allow `lan_bridge.exe` on private networks if Windows asks.

## Logs

- UE4SS console / `ue4ss\UE4SS.log`
- Dumps: `%TEMP%\MapSyncLogs\fow_dump_*.txt`
- Queue: `%TEMP%\MapSyncQueue\outbox` and `inbox`

## Safety notes

- Remnant 2 has no kernel AC for this QoL path; still use at your own risk.
- This build is for **personal validation**, not Nexus release polish.
- Steam P2P is intentionally out of scope until LAN FoW sync works for you.
