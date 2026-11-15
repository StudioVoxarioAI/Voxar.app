#!/usr/bin/env bash
# Složí hru Eryndor z VoxarioPlayeru a Assets projektu (jako `VoxarioEditor --build-game`, bez editoru – CI).
#   tools/package-game.sh <složka enginu s VoxarioPlayer(.exe)> <výstup> [verze]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
engine="${1:?složka enginu}"
out="${2:?výstupní složka}"
version="${3:-dev}"
player="$(find "$engine" -maxdepth 6 -type f \( -name VoxarioPlayer.exe -o -name VoxarioPlayer \) | head -n 1)"
[ -n "$player" ] || { echo "VoxarioPlayer nebyl ve složce $engine nalezen" >&2; exit 1; }
bin="$(dirname "$player")"
case "$player" in *.exe) exe="Eryndor.exe" ;; *) exe="Eryndor" ;; esac
# assety se generují kódem (tools/*.py) – když chybí, vytvořit
[ -f "$here/Assets/Models/nature/giant_tree.glb" ] || python3 "$here/tools/eryndor_nature.py" >/dev/null
[ -f "$here/Assets/Models/chars/wolf.glb" ] || python3 "$here/tools/eryndor_chars.py" >/dev/null
for model in hero keep paving skybridge city/gate_valorie city/house_0 city/tower_a; do
    [ -f "$here/Assets/Models/valoria/$model.glb" ] || {
        echo "Chybí model Valorie: $model.glb (spusťte tools/valoria_assets.py a tools/valoria_city.py)" >&2
        exit 1
    }
done
rm -rf "$out"
mkdir -p "$out"
cp "$player" "$out/$exe"
chmod +x "$out/$exe"
find "$bin" -maxdepth 1 -type f \( -name "*.dll" -o -name "libnvidia-ngx-dlss.so*" \) -exec cp {} "$out/" \;
[ -d "$bin/licenses" ] && cp -r "$bin/licenses" "$out/licenses"
[ -d "$bin/../share/voxario-studio/licenses" ] && cp -r "$bin/../share/voxario-studio/licenses" "$out/licenses"
cp -r "$here/Assets" "$out/GameData"
cat > "$out/game.vgame" <<EOV
{
  "Name": "Eryndor",
  "StartupScene": "Scenes/Main.vscene",
  "Gravity": [0.0, -9.81, 0.0],
  "EnableDLSS": true,
  "Version": "$version"
}
EOV
echo "Hra složena do $out ($exe, verze $version, $(du -sh "$out" | cut -f1))"
