#!/usr/bin/env bash
# Hratelné rasy Eryndoru – modely z Meshy, kostra a VLASTNÍ animace enginu (Motion Forge, bez převzatých klipů).
#   tools/eryndor_races.sh <engine/bin>        (MESHY_API_KEY v prostředí; Python 3 + numpy pro --motion)
# Kamenný obr z obrázku dokumentace (tools/races/obr.png). Víla, Kočičí lid (sněžný levhart / zrzavý mourek),
# Člověk, Trpaslík a Elf jsou vlastní postavy z textu (obrázky v dokumentaci připomínají skutečné herce).
# --motion <styl>: engine napasuje klouby paží na model, spočítá váhy a vygeneruje 86 klipů ve stylu rasy;
# --wings 1: víla dostane kosti křídel a mává jimi.
set -euo pipefail
motion() {   # animace + oči na hotových modelech (Motion Forge)
    local mt="${VOXARIO_MOTION_DIR:?nastav VOXARIO_MOTION_DIR}/humanoid_motion.py"
    local races_dir humans_dir
    races_dir="$(cd "$(dirname "$0")" && pwd)/../Assets/Models/races"
    humans_dir="$(cd "$(dirname "$0")" && pwd)/../Assets/Models/humans"
    m() { local f="$1"; shift; python3 "$mt" "$f" "$f" "$@"; }
    m "$races_dir/clovek.glb" --style clovek --eye-pos 0.038,1.855,0.015,0.007 --eyes
    m "$races_dir/trpaslik.glb" --style trpaslik --eye-pos 0.045,1.886,0.016,0.012 --eyes
    m "$races_dir/elf.glb" --style elf --eye-pos 0.045,1.705,0.018,0.010 --eyes
    m "$races_dir/vila.glb" --style vila --wings --eye-pos 0.045,1.622,0.018,0.009 --eyes
    m "$races_dir/kocka.glb" --style kocka --eye-pos 0.045,1.783,0.024,0.015 --eyes
    m "$races_dir/kocka_zrzava.glb" --style kocka --eye-pos 0.055,1.81,0.027,0.022 --eyes
    m "$races_dir/obr.glb" --style obr
    for spec in syl_knight_m:sword:shield syl_mage_f:staff:none aeth_heavy_m:sword:none aeth_engineer_f:crossbow:dagger \
                cultist_m:dagger:dagger crusher:hammer:none lyrise:none:book; do
        IFS=: read -r n r l <<< "$spec"
        m "$humans_dir/$n.glb" --style "{\"weapons\":[\"$r\",\"$l\"]}" --eyes
    done
}
if [ "${1:-}" = "--motion-only" ]; then motion; exit 0; fi
bin="$1"
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/../Assets/Models/races"
humans="$here/../Assets/Models/humans"
mkdir -p "$out"
gen() {   # gen <jméno> <kostra> <styl> <obrázek|-> [parametry…]
    local name="$1" rig="$2" style="$3" img="$4"; shift 4
    "$bin/VoxarioImageTo3D" "$img" "$out/$name.glb" "$@" --backend meshy --pose a-pose \
        --rig-model "$humans/$rig.glb" --fit 1 --motion "$style"
}
gen obr syl_knight_m obr "$here/races/obr.png"
gen vila syl_mage_f vila - --wings 1 \
    --prompt "Delicate fantasy fairy girl, full body, standing upright, slim graceful body, pale blue-lilac skin with glowing turquoise swirl patterns on arms and legs, small pointed elf ears, golden blonde hair in an elegant updo with tiny flowers, large translucent iridescent butterfly wings with pink, blue and violet gradient and sparkles, short green leaf corset top, short layered pink and violet flower petal skirt above the knees, bare legs, barefoot, no horns, no long dress, beautiful high quality fantasy MMO character" \
    --texture-prompt "beautiful painted fantasy fairy, soft pale lilac-blue skin, glowing turquoise swirl tattoos, golden hair with small white flowers, iridescent pink-blue-violet butterfly wings with sparkles, fresh green leaf bodice, pink and violet petal skirt, magical soft lighting colors"
gen kocka syl_knight_m kocka - \
    --prompt "Original fantasy feline ranger, anthropomorphic snow leopard humanoid, full body, standing upright, slender agile build, human-like legs in tall boots, white and grey spotted fur, cat head with pale blue eyes and rounded ears, long thick spotted tail, fitted teal and silver leather armor with leaf engravings, hooded half cloak, stylized high quality fantasy MMO game character" \
    --texture-prompt "stylized hand-painted fantasy MMO character, soft white and grey snow leopard fur with dark rosettes, teal leather, silver trim, soft painted shading"
gen kocka_zrzava syl_knight_m kocka - \
    --prompt "Original fantasy feline warrior, anthropomorphic cat humanoid, full body, standing upright, athletic agile build, human-like legs in soft leather boots, orange tabby fur with cream chest, cat head with large green eyes and tufted lynx ears, long striped tail, light leather armor with brass buckles, red cloth sash and short cape, fingerless gloves, stylized high quality fantasy MMO game character" \
    --texture-prompt "stylized hand-painted fantasy MMO character, vivid orange tabby fur with clear stripes, warm leather, brass details, crimson cloth, soft painted shading"
gen clovek syl_knight_m clovek - --prompt "Original fantasy human adventurer, full body, standing, young man with short dark brown hair and stubble, padded leather jerkin over chainmail shirt, leather belt with pouches, bracers, sturdy boots, stylized hand-painted game character" --texture-prompt "stylized hand-painted fantasy game character, warm brown leather, steel chainmail, soft painted shading"
gen trpaslik syl_knight_m trpaslik - --prompt "Original fantasy dwarf blacksmith, full body, standing, short and very stocky, broad shoulders, long black beard with two silver-ringed braids, bald head with tattoo, sleeveless wool tunic, thick leather apron, leather gauntlets, heavy iron-toed boots, stylized game character" --texture-prompt "stylized hand-painted fantasy game character, dark wool, worn leather apron, iron details"
gen elf syl_mage_f elf - --prompt "Original fantasy elf ranger woman, full body, standing, slender, long silver-white hair in a single braid, long pointed ears, fitted green and gold leaf-pattern leather armor, short hooded cloak, high boots, stylized game character" --texture-prompt "stylized hand-painted fantasy game character, forest green and gold leaf patterns, soft painted shading"
# Animace, držení zbraní, prsty a oči (engine ≥ 1.27, bez Meshy – jen přegeneruje klipy na hotových modelech):
#   tools/eryndor_races.sh --motion-only
# Polohy namalovaných očí (x, y středu levého oka, polovina šířky a výšky v m) jsou změřené z textury obličeje;
# engine s víčky sám mrká. Lidské NPC (MakeHuman) mají vlastní bulvy – dostanou kosti pohledu a zavírací víčko.
# Kamenný obr má oči jen jako úzké štěrbiny v kamenné tváři – bez víček.
# VOXARIO_MOTION_DIR = složka tools/motion enginu (instalace: <Voxario Studio>/motion)
motion
