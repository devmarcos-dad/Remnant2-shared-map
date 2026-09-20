# MapSync Steam — pacote zero-config

Para o jogador: use **`drop-in/MapSync-Steam/`** (leia o `LEIA-ME.txt` de lá).  
Não precisa buildar SDK, nem editar `Transport`.

## Instalar

1. Copie `drop-in/MapSync-Steam/MapSync` → `ue4ss\Mods\`
2. `mods.txt`: `MapSync : 1`
3. Backup `Desktop\Remnant2-SaveBackup-*`
4. Steam logado → coop → **F7** → explore / **F10**

Na primeira execução o `steam_bridge` sobe sozinho, grava `steam_appid.txt` / `steam_self.txt` e tenta achar o peer (friend no Remnant).

## Pacote LAN

Mesma ideia em `drop-in/MapSync-LAN/` (UDP local).

## Devs / fallbacks

- Fonte: `Mods/MapSync` (Transport padrão = steam, AutoStartBridge = true)
- Regenerar drop-ins: `bash tools/make_dropins.sh`
- TCP diagnóstico: `steam_bridge.exe -mode tcp ...` com `Transport = "tcp"` e `AutoStartBridge = false` (só debug)
- Build opcional CGO: `build_steamworks.bat` (não necessário para jogar)
