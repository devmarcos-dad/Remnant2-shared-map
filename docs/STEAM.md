# MapSync Steam transport (0.5.1-poc) — uso prático

O `steam_bridge.exe` **já vem buildado**. No Windows ele carrega `steam_api64.dll` em runtime (a mesma DLL que o Remnant já tem em `Binaries\Win64`). **Não precisa** de Steamworks SDK, nem CGO, nem `build_steamworks.bat` para jogar.

## Teste remoto (dois PCs) — checklist leigo

**Antes:** confirme o backup `Desktop\Remnant2-SaveBackup-*`.

1. Nos **dois** PCs: copie a pasta `Mods\MapSync` para o UE4SS (incluindo `Bin\steam_bridge.exe` e `Bin\lan_bridge.exe`).
2. Em `config.lua` (já é o padrão nesta branch):
   ```lua
   Transport = "steam",
   AutoStartBridge = true,
   BidirectionalSync = true,
   ```
3. Steam aberto e logado → entre no co-op Remnant → mundo → **F7** uma vez.
4. Explore num PC → o minimapa do outro deve atualizar. **F10** força sync 2 vias.

O mod **sobe o `steam_bridge.exe -mode steam` sozinho**. O peer costuma ser o friend que está no Remnant; se houver vários, grave o SteamID64 do parceiro em:

```
%TEMP%\MapSyncQueue\steam_peer.txt
```

(ou o seu id aparece em `steam_self.txt` para enviar ao amigo).

## Requisitos

- Windows + Remnant II + Steam logado
- UE4SS + MapSync com `Bin\steam_bridge.exe`
- `steam_api64.dll` no diretório do jogo (`Binaries\Win64`) — **já vem com o Remnant**

## Se o peer não conectar

1. Olhe o log do bridge / UE4SS por `steam local SteamID64` e `peer`.
2. Troquem os ids: cada um grava o `steam_self.txt` do outro em `steam_peer.txt`.
3. Confirme que só um Remnant co-op session está ativo e que os dois são friends na Steam.

## TCP (só diagnóstico)

```bat
steam_bridge.exe -mode tcp -listen :27073
steam_bridge.exe -mode tcp -dial HOST:27073
```

```lua
Transport = "tcp",
AutoStartBridge = false,
```

## LAN mesma casa (UDP)

```lua
Transport = "lan",  -- auto-start lan_bridge.exe
```

## Build opcional (devs)

```bat
cd tools\steam_bridge
build.bat
```

Copia o `.exe` para `Mods\MapSync\Bin\`. Linkagem CGO com SDK (`build_steamworks.bat`) é opcional e **não** é necessária para o usuário final.

## Arquitetura

Lua não fala com Steam. Só lê/escreve `%TEMP%\MapSyncQueue\` (`HELLO`/`FOG`/`TILE`/`TILES`/`POS`/`SYNC_REQ`). O bridge troca o transporte.
