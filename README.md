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

1. Install UE4SS into `Remnant2\Remnant2\Binaries\Win64\` (experimental build recommended).
2. Copy the `Mods/MapSync` folder from this repo into `ue4ss\Mods\`.
3. Confirm `Mods/MapSync/enabled.txt` exists (empty file is fine).
4. In `ue4ss\Mods\mods.txt`, add: `MapSync : 1`
5. Start the game. Check `ue4ss\UE4SS.log` for `[MapSync] Ready`.

## Update MapSync (after a fix) — do this now for 0.1.1

The previous build bound a `Function` UObject and crashed with `TrivialObject`.
**0.1.1** targets live `ExplorableMinimapManager` / model instances instead.

1. Download the branch ZIP:
   https://github.com/devmarcos-dad/Remnant2-shared-map/archive/refs/heads/cursor/mapsync-fow-validation-76fb.zip
2. Extract it. Inside you will see `Mods\MapSync\`.
3. Delete the old folder completely:
   `D:\SteamLibrary\steamapps\common\Remnant2\Remnant2\Binaries\Win64\ue4ss\Mods\MapSync`
4. Copy the new `Mods\MapSync` into `ue4ss\Mods\` (same place).
5. Keep `MapSync : 1` in `ue4ss\Mods\mods.txt` (do not remove it).
6. Fully close Remnant 2 → open again → enter a world (solo is fine) → press **F7**.
7. Open `ue4ss\UE4SS.log` and look for:
   - `MapSync 0.1.1-poc` (confirms new build)
   - `VIABILITY=GO` **or** `VIABILITY=NO-GO`
8. Also look at the minimap — fog must visibly change for a real GO.

PR: https://github.com/devmarcos-dad/Remnant2-shared-map/pull/1

## Phase 1 — validate FoW (do this first)

Play **solo / host local**. Keys:

| Key | Action |
| --- | --- |
| **F6** | Heavy reflection dump (can freeze the game for several seconds) |
| **F7** | Light FoW test — turns fog OFF for ~3s then restores it |
| **F8** | Toggle on-screen status line |
| **F9** | Print NetMode + LAN state |

### What you should see on F7 (v0.1.2)

1. Open the **minimap** first.
2. Press **F7** — the game should **not** freeze (dump is F6 only now).
3. Fog should **disappear / clear for about 3 seconds**, then come back.
4. Log shows `MapSync 0.1.2-poc` and `VIABILITY=GO`.

If F7 freezes, you still have the old build. Re-download the branch ZIP.

### Success = GO

1. Open the minimap, then press **F7** (auto-probe is off in 0.1.2).
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
