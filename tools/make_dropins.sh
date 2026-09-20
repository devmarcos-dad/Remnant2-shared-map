#!/usr/bin/env bash
# Build two zero-config drop-in packages from Mods/MapSync.
# Output:
#   drop-in/MapSync-Steam/MapSync/   → remoto (Steam P2P)
#   drop-in/MapSync-LAN/MapSync/     → rede local (UDP)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Mods/MapSync"
OUT="$ROOT/drop-in"

rm -rf "$OUT/MapSync-Steam" "$OUT/MapSync-LAN"
mkdir -p "$OUT/MapSync-Steam/MapSync" "$OUT/MapSync-LAN/MapSync"

# --- Steam package -----------------------------------------------------------
cp -a "$SRC/." "$OUT/MapSync-Steam/MapSync/"
# Keep both bridges (steam required; lan unused but harmless)
# Force steam transport + autostart in the packaged config
python3 - <<'PY'
from pathlib import Path
import re
p = Path("drop-in/MapSync-Steam/MapSync/Scripts/config.lua")
text = p.read_text(encoding="utf-8")
text = re.sub(r'^(\s*Transport\s*=\s*)"[^"]*"', r'\1"steam"', text, count=1, flags=re.M)
if 'Transport = "steam"' not in text:
    raise SystemExit("Steam package: Transport=steam missing")
if "AutoStartBridge = true" not in text:
    raise SystemExit("Steam package: AutoStartBridge=true missing")
lines = text.splitlines()
if lines and lines[0].startswith("--"):
    lines[0] = "-- MapSync STEAM package (zero-config) — não edite nada para jogar remoto"
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat > "$OUT/MapSync-Steam/LEIA-ME.txt" <<'EOF'
MapSync — pacote STEAM (coop remoto / também funciona na mesma casa)

INSTALAR (os dois jogadores fazem o mesmo):
1. Tenha UE4SS instalado no Remnant II.
2. Copie a pasta "MapSync" desta pasta para:
   Remnant2\Remnant2\Binaries\Win64\ue4ss\Mods\
3. Em ue4ss\Mods\mods.txt adicione a linha:
   MapSync : 1
4. Abra o Steam (logado) → abra o Remnant → entre no coop → mundo → aperte F7 uma vez.
5. Explore: o minimapa do outro deve atualizar. F10 força sync.

NÃO precisa editar config. O bridge sobe sozinho na primeira execução.

ANTES DE TESTAR: confirme o backup Desktop\Remnant2-SaveBackup-*

Se o sync não pegar o parceiro automaticamente, um jogador abre
%TEMP%\MapSyncQueue\steam_self.txt e o outro cola esse número em
%TEMP%\MapSyncQueue\steam_peer.txt
EOF

# --- LAN package -------------------------------------------------------------
cp -a "$SRC/." "$OUT/MapSync-LAN/MapSync/"
# LAN only needs lan_bridge.exe
rm -f "$OUT/MapSync-LAN/MapSync/Bin/steam_bridge.exe"
python3 - <<'PY'
from pathlib import Path
import re
p = Path("drop-in/MapSync-LAN/MapSync/Scripts/config.lua")
text = p.read_text(encoding="utf-8")
text = re.sub(r'^(\s*Transport\s*=\s*)"[^"]*"', r'\1"lan"', text, count=1, flags=re.M)
if 'Transport = "lan"' not in text:
    raise SystemExit("LAN package: Transport=lan missing")
if "AutoStartBridge = true" not in text:
    raise SystemExit("LAN package: AutoStartBridge=true missing")
lines = text.splitlines()
if lines and lines[0].startswith("--"):
    lines[0] = "-- MapSync LAN package (zero-config) — não edite nada para jogar na mesma rede"
p.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat > "$OUT/MapSync-LAN/LEIA-ME.txt" <<'EOF'
MapSync — pacote LAN (mesma casa / mesma rede Wi-Fi)

INSTALAR (os dois jogadores fazem o mesmo):
1. Tenha UE4SS instalado no Remnant II.
2. Copie a pasta "MapSync" desta pasta para:
   Remnant2\Remnant2\Binaries\Win64\ue4ss\Mods\
3. Em ue4ss\Mods\mods.txt adicione a linha:
   MapSync : 1
4. Abra o Remnant nos dois PCs → coop Steam → mundo → aperte F7 uma vez.
5. Explore: o minimapa do outro deve atualizar. F10 força sync.

NÃO precisa editar config. O lan_bridge sobe sozinho.

ANTES DE TESTAR: confirme o backup Desktop\Remnant2-SaveBackup-*

Windows Firewall pode pedir permissão para lan_bridge.exe — permita em rede privada.

NÃO use este pacote junto com o pacote Steam (escolha um).
EOF

cat > "$OUT/LEIA-ME.txt" <<'EOF'
Escolha UM pacote (os dois jogadores usam o MESMO):

  MapSync-Steam/   → coop pela internet (Steam P2P)  [recomendado remoto]
  MapSync-LAN/     → mesma casa / Wi-Fi local

Em cada pacote leia LEIA-ME.txt e copie a pasta MapSync para ue4ss\Mods\

Não ative os dois ao mesmo tempo.
EOF

echo "Drop-ins ready under drop-in/"
find "$OUT" -maxdepth 3 -type f | head -40
