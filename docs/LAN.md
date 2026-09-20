# MapSync LAN FoW sync (0.5.1-poc)

Either player explores → the other minimap turns gray.

- **Remoto / padrão:** `Transport = "steam"` auto-inicia `Bin\steam_bridge.exe` — veja [`STEAM.md`](STEAM.md).
- **Mesma casa UDP:** `Transport = "lan"` auto-inicia `Bin\lan_bridge.exe` (sem abrir exe na mão).

Press **F10** to force a two-way dump.

## What 0.5.1 adds

- `steam_bridge.exe` **pré-buildado** com Steam P2P via `steam_api64.dll` em runtime (sem SDK para o jogador).
- Auto-start do `steam_bridge` quando `Transport = "steam"`.

## On both PCs (LAN UDP)

1. Replace `ue4ss\Mods\MapSync` (must include `Bin\`).
2. Set `Transport = "lan"` if you want UDP instead of Steam P2P.
3. Confirm log: `MapSync 0.5.1-poc` and `boot bridge ok=true`.
4. Co-op → **F7** → explore / **F10**.
5. Quit → bridge auto-kills.

For remote Steam steps: [`STEAM.md`](STEAM.md).

## Config

```lua
AutoStartBridge = true
Transport = "steam"  -- or "lan" / "tcp"
BidirectionalSync = true
```

## What this syncs / does not sync

| Syncs | Does **not** sync yet |
| --- | --- |
| Fog-of-war / explored gray areas (both ways) | Chest / item / loot icons on the map |
| Host + client trail via `POS` | Objectives / quest markers |
| Manual F10 two-way dump | — |

## If it fails

Send `[MapSync][FoW]` / `[MapSync][LAN]` from both logs (look for `boot bridge`, `force_sync`, `send TILES`, `apply`).
