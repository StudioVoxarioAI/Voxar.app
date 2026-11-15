#!/usr/bin/env python3
"""Fotorealistické PBR materiály staveb Valorie z fotoskenů Poly Haven (CC0).

  python3 tools/valoria_pbr.py [--cache <složka>] [--size 1024]
  python3 tools/valoria_assets.py        # modely si textury vloží do .glb

Pro každý materiál stáhne (jednou, do cache) barvu, normálovou mapu (OpenGL) a ARM mapu (okluze, drsnost,
kovovost = glTF ORM) a uloží je do Assets/Textures/valoria/pbr/<materiál>_{basecolor,normal,orm}.jpg.
Bez meshy.ai ani jiné generativní služby: jen fotoskeny CC0 a deterministické úpravy (zabarvení břidlice).
"""
from __future__ import annotations

import argparse
import os
import pathlib
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from terrain_pbr import fetch  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "Assets" / "Textures" / "valoria" / "pbr"
MAPS = {"albedo": "Diffuse", "normal": "nor_gl", "arm": "arm"}

# materiál -> (fotosken, skutečná velikost dlaždice v m, barevná úprava RGB)
MATERIALS = {
    "castle": ("medieval_blocks_03", 2.0, (1.0, 1.0, 1.0)),       # kvádrové zdivo hradu
    "stone": ("stone_brick_wall_001", 2.5, (1.0, 1.0, 1.0)),      # brána, most, sokly domů
    "cobble": ("cobblestone_floor_08", 2.0, (1.0, 1.0, 1.0)),     # dlažba ulic a podlaha hradu
    "plaster": ("white_stucco", 2.0, (1.0, 0.94, 0.82)),          # čistá krémová omítka hrázděných domů
    "timber": ("old_planks_02", 2.0, (0.8, 0.74, 0.68)),          # tmavé dubové trámy, dveře
    "slate": ("roof_slates_03", 3.0, (0.82, 0.92, 1.08)),         # modrošedá břidlice (hrad, brána, modrý dům)
    "clay": ("roof_09", 4.0, (1.0, 1.0, 1.0)),                    # pálené tašky (červený dům)
    "linen": ("rough_linen", 0.27, (0.32, 0.48, 0.85)),           # modré plátno markýz a praporů
    "marble": ("marble_rock_03", 1.8, (1.0, 1.0, 1.0)),           # sochy hrdinů
    "planks": ("brown_planks_05", 2.0, (0.92, 0.86, 0.8)),        # mola přístavu a trupy lodí
    "limestone": ("sandstone_blocks_08", 2.4, (1.0, 0.97, 0.92)),  # medový pískovec věží, brány a mostu (předloha)
    "lead": ("roof_slates_02", 2.5, (0.78, 0.86, 0.95)),          # olověné / břidlicové kopule a špičaté střechy
}


def tile_size(name: str) -> float:
    return MATERIALS[name][1]


def build(name: str, cache: pathlib.Path, size: int) -> None:
    asset, _, tint = MATERIALS[name]
    print(f"{name}: {asset}")
    p = fetch(asset, cache, MAPS)
    OUT.mkdir(parents=True, exist_ok=True)
    albedo = np.asarray(Image.open(p["albedo"]).convert("RGB").resize((size, size), Image.LANCZOS), np.float32)
    albedo = np.clip(albedo * np.array(tint, np.float32), 0, 255)
    Image.fromarray((albedo + 0.5).astype(np.uint8)).save(OUT / f"{name}_basecolor.jpg", quality=90, optimize=True)
    normal = Image.open(p["normal"]).convert("RGB").resize((size, size), Image.LANCZOS)
    normal.save(OUT / f"{name}_normal.jpg", quality=95, optimize=True)
    orm = np.asarray(Image.open(p["arm"]).convert("RGB").resize((size, size), Image.LANCZOS)).copy()
    orm[..., 2] = 0   # kámen, omítka, dřevo i tašky jsou nekovové
    Image.fromarray(orm).save(OUT / f"{name}_orm.jpg", quality=92, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.environ.get("ERYNDOR_TEXTURE_CACHE",
                                                      str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    ap.add_argument("--size", type=int, default=1024)
    args = ap.parse_args()
    for name in MATERIALS:
        build(name, pathlib.Path(args.cache), args.size)
    (OUT / "CREDITS.txt").write_text(
        "Materiály staveb Valorie: fotoskeny Poly Haven (https://polyhaven.com), licence CC0 1.0.\n"
        "Vygenerováno skriptem tools/valoria_pbr.py.\n\n" +
        "".join(f"{n}: https://polyhaven.com/a/{a}\n" for n, (a, _, _) in MATERIALS.items()), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
