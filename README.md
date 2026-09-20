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
   https://github.com/devmarcos-dad/Remnant2-shared-map/archive/refs/heads/cursor/steam-bidirectional-sync-adf5.zip
2. Extract it. Inside you will see `Mods\MapSync\` (includes `Bin\lan_bridge.exe`).
3. Delete the old folder completely:
   `D:\SteamLibrary\steamapps\common\Remnant2\Remnant2\Binaries\Win64\ue4ss\Mods\MapSync`
4. Copy the new `Mods\MapSync` into `ue4ss\Mods\` (same place).
5. Keep `MapSync : 1` in `ue4ss\Mods\mods.txt` (do not remove it).
6. Fully close Remnant 2 → open again → enter a world (solo is fine) → press **F7**.
7. Open `ue4ss\UE4SS.log` and look for:
   - `MapSync 0.4.1-poc` (confirms new build)
   - `boot bridge ok=true` (LAN auto-start)
   - `VIABILITY=GO` **or** `VIABILITY=NO-GO`
8. Also look at the minimap — fog must visibly change for a real GO.

PR: https://github.com/devmarcos-dad/Remnant2-shared-map/pull/2

## Phase 1 — validate FoW (do this first)

Play **solo / host local**. Keys:

| Key | Action |
| --- | --- |
| **F6** | Heavy reflection dump (can freeze the game for several seconds) |
| **F7** | Light FoW test — turns fog OFF for ~3s then restores it |
| **F8** | Toggle on-screen status line |
| **F9** | Print NetMode + sync state |
| **F10** | Force two-way map sync (push local + request peer dump) |

### What you should see on F7 (v0.1.2)

1. Open the **minimap** first.
2. Press **F7** — the game should **not** freeze (dump is F6 only now).
3. Fog should **disappear / clear for about 3 seconds**, then come back.
4. Log shows `MapSync 0.2.0-poc` and `VIABILITY=GO`.

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

## Phase 2 — LAN sync (0.4.1-poc)

Same-house co-op: Steam runs the session; MapSync uses a parallel LAN channel.
`lan_bridge.exe` ships under `Mods/MapSync/Bin/` and **auto-starts / auto-kills** with the game.

Full steps: [`docs/LAN.md`](docs/LAN.md)

Short version (both PCs):

1. Replace `ue4ss\Mods\MapSync` from this branch (includes `Bin\lan_bridge.exe`).
2. Start Remnant — bridge **auto-starts** (no manual `.exe` for LAN).
3. Co-op → world → **F7** → either player explores → the other minimap should go gray.
4. Optional: **F10** force two-way sync.
5. Quit the game — bridge **auto-kills**.
6. On failure, send only `[MapSync][FoW]` / `[MapSync][LAN]` lines from both logs.

## Phase 3 — Bidirectional + Steam P2P (0.5.0-poc)

- Lua: both roles emit FoW tiles/POS; **F10** pushes local map and requests the peer dump (`SYNC_REQ`).
- Bridge: `tools/steam_bridge` with **Steamworks P2P** (`-mode steam`, `-tags steamworks` build) and **TCP** diagnostic fallback.
- LAN auto-start still targets `lan_bridge.exe` when `Transport = "lan"`; for Steam/TCP set `AutoStartBridge = false` and run `steam_bridge` yourself.

Full steps: [`docs/STEAM.md`](docs/STEAM.md)

**Before any remote/Steam test:** confirm/restore your Desktop save backup (`Remnant2-SaveBackup-*`).

### Steamworks P2P (recommended for remote co-op)

```bat
cd tools\steam_bridge
set STEAMWORKS=C:\path\to\steamworks_sdk
build_steamworks.bat

REM Both PCs (Steam running + logged in). Peer via -peer, steam_peer.txt, or friend auto-discover:
steam_bridge.exe -mode steam -peer PARTNER_STEAMID64
```

In `config.lua`: `Transport = "steam"` and `AutoStartBridge = false`. Then Steam co-op → world → **F7** → explore / **F10**.

Requirements: Steamworks SDK, `steam_api64.dll` beside the exe, Steam client running. Details in [`docs/STEAM.md`](docs/STEAM.md).

### TCP diagnostic fallback (no Steamworks SDK)

```bat
REM Host (listener)
tools\steam_bridge\steam_bridge.exe -mode tcp -listen :27073

REM Client
tools\steam_bridge\steam_bridge.exe -mode tcp -dial HOST:27073
```

Set `Transport = "tcp"` in `config.lua`. Default `build.bat` (no SDK) still produces this binary; `-mode steam` then fails with a clear pointer to the docs.

## Logs

- UE4SS console / `ue4ss\UE4SS.log`
- Dumps: `%TEMP%\MapSyncLogs\fow_dump_*.txt`
- Queue: `%TEMP%\MapSyncQueue\outbox` and `inbox`

## Safety notes

- Remnant 2 has no kernel AC for this QoL path; still use at your own risk.
- This build is for **personal validation**, not Nexus release polish.
- Keep a Desktop save backup (`Remnant2-SaveBackup-*`) before co-op sync tests; restore it if progress looks wrong.
- Default `steam_bridge` builds keep TCP/LAN working without the Steamworks SDK; use `build_steamworks.bat` for real P2P.
