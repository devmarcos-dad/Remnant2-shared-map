# MapSync Steam transport (0.4.0-poc)

Goal: keep the Lua FoW protocol unchanged and **swap only the bridge transport** so remote Steam co-op can share minimap exploration.

## Architecture

```
[Host Remnant + UE4SS MapSync]          [Client Remnant + UE4SS MapSync]
         |                                           |
    outbox/*.msg                                inbox/*.msg
         |                                           ^
         v                                           |
   steam_bridge.exe  ---- transport ----  steam_bridge.exe
         |                                           |
    mode=steam (Steamworks P2P)   OR   mode=tcp (WAN test today)
```

Lua never talks to Steam directly. It only reads/writes `%TEMP%\MapSyncQueue\`.

## What works in this PR

| Piece | Status |
| --- | --- |
| Bidirectional FoW sync (Host ↔ Client) | **Done** in Lua (`BidirectionalSync = true`) |
| Force sync hotkey **F10** (push + `SYNC_REQ`) | **Done** |
| `steam_bridge -mode tcp` WAN path | **Done** (no Steamworks SDK required) |
| `steam_bridge -mode steam` | Scaffold only — needs Steamworks SDK + `-tags steamworks` |
| Same-house LAN | Still use `tools/lan_bridge/lan_bridge.exe` |

## Bidirectional sync + F10

1. Both PCs: MapSync 0.4.0-poc, FoW GO via **F7**, bridge running.
2. Explore on either machine — tiles/POS should merge on the other minimap.
3. Press **F10** on either PC to:
   - force-push local tiles/POS (and host fog)
   - send `SYNC_REQ` so the peer force-pushes back

Fog enable/disable stays **host-authoritative** to avoid Host↔Client fights.

## TCP WAN test (no Steamworks yet)

Pick one PC as listener (usually the Steam lobby host):

```bat
tools\steam_bridge\steam_bridge.exe -mode tcp -listen :27073
```

Other PC (replace HOST with the listener's public/LAN IP):

```bat
tools\steam_bridge\steam_bridge.exe -mode tcp -dial HOST:27073
```

In `config.lua` on both:

```lua
Transport = "tcp",
```

Forward TCP 27073 if you are across the internet. This validates the queue + bidirectional Lua path before Steam P2P.

## Steam mode (next milestone)

Remnant II AppID: **1282100**.

Planned flags:

```bat
steam_bridge.exe -mode steam -appid 1282100 -peer PARTNER_STEAMID64
```

Or write the partner id to:

```
%TEMP%\MapSyncQueue\steam_peer.txt
```

Build (once Steamworks SDK is present on a Windows box):

```bat
set STEAMWORKS=C:\path\to\sdk
go build -tags steamworks -o steam_bridge.exe .
```

`steam_steamworks.go` is the integration point for:

1. `SteamAPI_Init` + `steam_appid.txt`
2. `ISteamNetworkingMessages::SendMessageToUser`
3. `ReceiveMessagesOnChannel` → write inbox `.msg` files

Until that is linked, `-mode steam` exits with a pointer to this doc.

## Config knobs

In `Mods/MapSync/Scripts/config.lua`:

| Key | Default | Meaning |
| --- | --- | --- |
| `Transport` | `"lan"` | Hint for logs / which bridge to run |
| `BidirectionalSync` | `true` | Client also emits TILES/POS |
| `Lan.PollMs` | `1000` | Lua poll + emit cadence |
| `PositionIntervalMs` | `1000` | POS trail throttle |
| `Keys.ForceSync` | `"F10"` | Manual two-way sync |
| `Steam.AppId` | `1282100` | Remnant II |
| `Steam.PeerId` | `""` | Optional; bridge also reads `steam_peer.txt` |
