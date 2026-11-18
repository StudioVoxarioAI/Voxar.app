#!/bin/bash
# Zvěř (Assets/Models/fauna): vlk, divočák, laň, jelen, medvěd – Quadruped Forge z enginu Voxario
# (anatomická síť, srst z vrstev, kostra, klipy s IK nohou) + LOD se stejnou kostrou.
#   bash tools/eryndor_fauna.sh [cesta k Voxario-Studio-Engine]
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
engine="${1:-$here/../../../../Voxario-Studio-Engine}"
out="$here/Assets/Models/fauna"
mkdir -p "$out"
for a in wolf boar doe stag bear; do
    python3 -B "$engine/tools/creatures/quadruped_forge.py" "$a" "$out/$a.glb" --lod "$out/${a}_lo.glb"
done
