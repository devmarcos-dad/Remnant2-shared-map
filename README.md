# MapSync (Remnant 2) — minimapa compartilhado

Dois pacotes **prontos** (escolha um; os dois jogadores usam o **mesmo**):

| Pacote | Quando usar | Configuração |
| --- | --- | --- |
| [`drop-in/MapSync-Steam/`](drop-in/MapSync-Steam/) | Coop **remoto** (ou mesma casa via Steam) | Nenhuma |
| [`drop-in/MapSync-LAN/`](drop-in/MapSync-LAN/) | **Mesma rede** Wi-Fi / LAN | Nenhuma |

Cada um tem um `LEIA-ME.txt`. Copie só a pasta `MapSync` de dentro do pacote.

## Instalar (30 segundos)

1. UE4SS já instalado no Remnant II.
2. Copie `MapSync` → `Remnant2\Remnant2\Binaries\Win64\ue4ss\Mods\`
3. Em `ue4ss\Mods\mods.txt`: `MapSync : 1`
4. **Antes de testar:** confirme backup `Desktop\Remnant2-SaveBackup-*`
5. Jogo → coop → mundo → **F7** uma vez → explore. **F10** = sync forçado.

O bridge sobe sozinho (`AutoStartBridge = true`). Não edite `config.lua`.

## Qual baixar?

- **Amigos em casas diferentes** → `MapSync-Steam`
- **Dois PCs na mesma casa** → `MapSync-LAN` (mais simples) **ou** Steam (também funciona)

Não instale os dois pacotes ao mesmo tempo.

## Conteúdo do repo (devs)

| Path | Purpose |
| --- | --- |
| [`drop-in/`](drop-in/) | Pacotes zero-config para o jogador |
| [`Mods/MapSync/`](Mods/MapSync/) | Fonte do mod (padrão Steam) |
| [`tools/lan_bridge/`](tools/lan_bridge/) | Bridge UDP |
| [`tools/steam_bridge/`](tools/steam_bridge/) | Bridge Steam/TCP (pré-buildado) |
| [`docs/STEAM.md`](docs/STEAM.md) | Detalhes Steam / peer / fallbacks |
| [`docs/LAN.md`](docs/LAN.md) | Detalhes LAN |
| [`docs/VALIDATION.md`](docs/VALIDATION.md) | Probe FoW (F6/F7) |

Regenerar pacotes após mudar o mod:

```bat
bash tools/make_dropins.sh
```

## Hotkeys

| Key | Action |
| --- | --- |
| **F7** | Liga FoW + sync (faça 1x ao entrar no mundo) |
| **F10** | Sync forçado 2 vias |
| **F8** | Status on-screen (debug) |
| **F9** | Dump NetMode |
| **F6** | Dump pesado (pode travar) |

## Requirements

1. Remnant 2 on Windows  
2. [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)  
3. Pacote MapSync em `ue4ss\Mods\MapSync\`

## Safety

- Use por sua conta e risco.
- Mantenha backup `Remnant2-SaveBackup-*` no Desktop antes de testar coop.
- Pacote Steam usa `steam_api64.dll` do próprio jogo (sem SDK para o jogador).
