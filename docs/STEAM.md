# MapSync Steam transport (0.5.0-poc)

Goal: keep the Lua FoW protocol unchanged and **swap only the bridge transport** so remote Steam co-op can share minimap exploration over **Steamworks P2P**.

## Architecture

```
[Host Remnant + UE4SS MapSync]          [Client Remnant + UE4SS MapSync]
         |                                           |
    outbox/*.msg                                inbox/*.msg
         |                                           ^
         v                                           |
   steam_bridge.exe  ---- transport ----  steam_bridge.exe
         |                                           |
    mode=steam (ISteamNetworkingMessages)   OR   mode=tcp (diagnostic fallback)
```

Lua never talks to Steam directly. It only reads/writes `%TEMP%\MapSyncQueue\` with the same payloads (`HELLO` / `FOG` / `TILE` / `TILES` / `POS` / `SYNC_REQ`).

## Status

| Piece | Status |
| --- | --- |
| Bidirectional FoW sync (Host ↔ Client) | **Done** (`BidirectionalSync = true`) |
| Force sync hotkey **F10** | **Done** |
| `steam_bridge -mode steam` (Steamworks P2P) | **Done** — build with `build_steamworks.bat` |
| `steam_bridge -mode tcp` WAN diagnostic | **Done** (no Steamworks SDK) |
| Same-house LAN | Auto-started `Mods/MapSync/Bin/lan_bridge.exe` (or `tools/lan_bridge`) |

Fog enable/disable stays **host-authoritative**.

## Safety — saves

Before any in-game co-op test, restore/confirm your Remnant II save backup on the Desktop (`Remnant2-SaveBackup-*`). If progress looks wrong after a session, restore that backup before continuing.

## Build requirements (Windows Steamworks P2P)

1. **Go 1.22+** with a **C compiler** on `PATH` (TDM-GCC / MinGW-w64) — CGO must work.
2. **Steamworks SDK** (Valve partner download). Need at least:
   - `redistributable_bin\win64\steam_api64.dll`
   - `redistributable_bin\win64\steam_api64.lib` (link import library)
3. **Steam client** installed, running, user logged in (runtime).
4. Remnant II AppID: **1282100** (`steam_appid.txt` is written automatically / by the build script).

### Default build (TCP/LAN only)

```bat
cd tools\steam_bridge
build.bat
```

`-mode steam` on this binary exits with a message pointing here. TCP/LAN keep working.

### Steamworks P2P build

```bat
cd tools\steam_bridge
set STEAMWORKS=C:\path\to\steamworks_sdk
build_steamworks.bat
```

That produces:

- `steam_bridge.exe` (linked with `-tags steamworks`)
- `steam_api64.dll` (copied next to the exe)
- `steam_appid.txt` containing `1282100`

Keep `steam_api64.dll` and `steam_appid.txt` beside `steam_bridge.exe` when you run it.

If the linker complains about `SteamAPI_SteamUser_SteamAPI_v0xx` / Friends accessor names, open your SDK `steam_api_flat.h` and retarget the accessor symbols in `steam_abi.h` to the versions your SDK exports.

## Peer discovery

Both PCs must agree on a partner **SteamID64**. Options (first match wins at startup; inbound sessions can still fill a missing peer):

| Method | How |
| --- | --- |
| **CLI** | `steam_bridge.exe -mode steam -peer PARTNER_STEAMID64` |
| **File** | Write the partner id to `%TEMP%\MapSyncQueue\steam_peer.txt` |
| **Auto (friends)** | If exactly one Steam friend is in-game on AppID 1282100, that friend is selected |
| **Inbound session** | If the partner already targets you, accepting their NetworkingMessages session fills the peer |

On start, the bridge also writes **your** id to:

```
%TEMP%\MapSyncQueue\steam_self.txt
```

Share that value with your co-op partner (Discord, etc.) if auto-discover does not apply. Multiple friends playing Remnant II at once → pick manually with `-peer` / `steam_peer.txt`.

Lobby-based matchmaking is not required; Steam Networking Messages opens a P2P session when either side sends.

## Remote co-op test (two PCs, different networks)

1. Confirm save backups on both Desktops (`Remnant2-SaveBackup-*`).
2. Both PCs: MapSync mod installed, `EnableLanSync = true`, in `config.lua` set:

```lua
Transport = "steam",
AutoStartBridge = false,  -- LAN auto-start is for lan_bridge; run steam_bridge yourself
```

3. Both PCs: Steam open + logged in. Build/run the **steamworks** `steam_bridge.exe`:

```bat
REM Optional explicit peer (or rely on steam_peer.txt / friend auto-discover)
tools\steam_bridge\steam_bridge.exe -mode steam -appid 1282100 -peer PARTNER_STEAMID64
```

4. Join the same Remnant II Steam co-op session → enter world → press **F7** once (FoW bind).
5. Explore on either machine — the other minimap should update (tiles / POS merge).
6. Press **F10** on either PC to force-push local map and send `SYNC_REQ` (two-way dump).

### Expected logs

Bridge:

- `steam local SteamID64=...`
- `transport ready: steam`
- `shipped ....msg (... bytes) via steam`

UE4SS (`[MapSync][LAN]`):

- HELLO / TILES / POS / SYNC_REQ lines on both roles when bidirectional sync is on.

## TCP diagnostic fallback (no Steamworks)

Use when you need to validate the queue + Lua path without linking Steam:

```bat
REM Host
tools\steam_bridge\steam_bridge.exe -mode tcp -listen :27073

REM Client (HOST = listener public/LAN IP; forward TCP 27073 if needed)
tools\steam_bridge\steam_bridge.exe -mode tcp -dial HOST:27073
```

```lua
Transport = "tcp",
AutoStartBridge = false,
```

LAN same-house: keep `Transport = "lan"` so `Mods/MapSync/Bin/lan_bridge.exe` auto-starts.

## Config knobs

In `Mods/MapSync/Scripts/config.lua`:

| Key | Default | Meaning |
| --- | --- | --- |
| `Transport` | `"lan"` | Hint for logs / which bridge to run (`lan` / `tcp` / `steam`) |
| `AutoStartBridge` | `true` | Starts `lan_bridge.exe` when `Transport = "lan"` |
| `BidirectionalSync` | `true` | Client also emits TILES/POS |
| `Lan.PollMs` | `1000` | Lua poll + emit cadence |
| `PositionIntervalMs` | `1000` | POS trail throttle |
| `Keys.ForceSync` | `"F10"` | Manual two-way sync |
| `Steam.AppId` | `1282100` | Remnant II |
| `Steam.PeerId` | `""` | Optional; bridge also reads `steam_peer.txt` |
| `Steam.Channel` | `1` | Must match on both bridges |
