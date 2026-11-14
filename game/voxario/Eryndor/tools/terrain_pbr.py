#!/usr/bin/env python3
"""Fotorealistické PBR povrchy terénu Eryndoru z fotoskenů Poly Haven (CC0).

  python3 tools/terrain_pbr.py [--cache <složka>] [--albedo 2048] [--surface 1024]

Pro každou vrstvu world.terrain stáhne (jednou, do cache) barvu, normálovou mapu (OpenGL), drsnost,
výšku a okluzi a sbalí je do dvou souborů, které čte engine ≥ 1.19:

  Assets/Textures/terrain/pbr/<jméno>_albedo.jpg   sRGB barva se zapečenou okluzí
  Assets/Textures/terrain/pbr/<jméno>_surface.png  lineární RGBA: R, G = normála (tečný prostor, zelená
                                                   nahoru), B = drsnost, A = výška (roztažená na 0..1)

Láva a ametyst nemají fotosken – vznikají z tmavé a rozpraskané skály (láva v prohlubních, krystalické
zabarvení). Bez meshy.ai ani jiné generativní služby: jen fotoskeny CC0 a deterministické úpravy.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "Assets" / "Textures" / "terrain" / "pbr"
API = "https://api.polyhaven.com/files/"

# vrstva -> (fotosken Poly Haven, úprava)
LAYERS = {
    "trava": ("leafy_grass", "meadow"),        # 1 louky (Verdant)
    "zeme": ("forest_ground_04", None),        # 2 lesní půda a hlína
    "pisek": ("aerial_beach_01", None),        # 3 pláže a břehy (čeřiny písku)
    "skala": ("rock_face_03", None),           # 4 skalní svahy a útesy
    "snih": ("snow_02", "snow"),                 # 5 sníh a led (Frostfang)
    "lava": ("rock_boulder_cracked", "lava"),  # 6 láva: chladnoucí kůra + žhnoucí praskliny
    "cedic": ("burned_ground_01", "basalt"),   # 7 čedič a popel (Ignis)
    "ametyst": ("rock_boulder_cracked", "amethyst"),   # 8 ametystová půda (Crystalarium)
}
USER_AGENT = {"User-Agent": "eryndor-terrain-pbr/1.0"}   # Poly Haven odmítá výchozí agent urllib
MAPS = {"albedo": "Diffuse", "normal": "nor_gl", "rough": "Rough", "height": "Displacement", "ao": "AO"}


def fetch(asset: str, cache: pathlib.Path, maps: dict[str, str] | None = None) -> dict[str, pathlib.Path]:
    """Stáhne mapy fotoskenu ve 2k (JPG, kde existuje, jinak PNG) do cache."""
    folder = cache / asset
    folder.mkdir(parents=True, exist_ok=True)
    meta_path = folder / "files.json"
    if not meta_path.exists():
        with urllib.request.urlopen(urllib.request.Request(API + asset, headers=USER_AGENT), timeout=60) as r:
            meta_path.write_bytes(r.read())
    meta = json.loads(meta_path.read_text())
    paths = {}
    for key, name in (maps or MAPS).items():
        if name not in meta:
            continue
        formats = meta[name]["2k"]
        fmt = "jpg" if "jpg" in formats else "png"
        url = formats[fmt]["url"]
        target = folder / f"{name}.{fmt}"
        if not target.exists():
            print(f"  stahuji {asset}/{name}")
            tmp = target.with_suffix(".part")
            with urllib.request.urlopen(urllib.request.Request(url, headers=USER_AGENT), timeout=120) as r, open(tmp, "wb") as f:
                f.write(r.read())
            os.replace(tmp, target)
        paths[key] = target
    return paths


def load(path: pathlib.Path, size: int, mode: str) -> np.ndarray:
    img = Image.open(path)
    if img.mode in ("I;16", "I;16B", "I"):
        a = np.asarray(img, dtype=np.float32)
        a = a / (65535.0 if a.max() > 255 else 255.0)
        img = Image.fromarray(np.clip(a * 255.0, 0, 255).astype(np.uint8), "L")
    img = img.convert(mode).resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.float32) / 255.0


def stretch(h: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(h, 1.5), np.percentile(h, 98.5)
    return np.clip((h - lo) / max(hi - lo, 1e-4), 0.0, 1.0)


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def variant(kind: str | None, albedo: np.ndarray, rough: np.ndarray, height: np.ndarray):
    """Úpravy pro vrstvy bez vlastního fotoskenu (barva lineárně 0..1 v sRGB prostoru)."""
    if kind is None:
        return albedo, rough
    luma = albedo @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    if kind == "meadow":
        # svěží louka: zelenější stébla, suché listí zůstává (jen mírný posun, fotosken drží realismus)
        green = smoothstep(0.0, 0.08, albedo[..., 1] - albedo[..., 0])[..., None]
        lush = albedo * np.array([0.86, 1.08, 0.80], dtype=np.float32)
        albedo = albedo * (1.0 - green * 0.7) + lush * green * 0.7
        albedo = albedo * np.array([0.8, 0.94, 0.66], dtype=np.float32)   # sytější zelená (ladí s trsy trávy)
    elif kind == "snow":
        # čerstvý sníh: jasný (albedo ~0,85), stopy nečistot utlumené, chladný nádech ve stínech
        mean = albedo.mean(axis=(0, 1), keepdims=True)
        albedo = np.clip(0.84 + (albedo - mean) * 0.45, 0.0, 1.0) * np.array([0.97, 0.99, 1.02], dtype=np.float32)
    elif kind == "lava":
        # chladnoucí čedičová kůra, v prohlubních žhnoucí tavenina (jas = emise v enginu)
        crust = (albedo * 0.3 + luma[..., None] * 0.7) * 0.3 + 0.015   # tmavá, téměř šedá kůra
        # žhnoucí praskliny = místní prohlubně (rozmazaná výška - výška), k tomu jezírka v nejnižších místech
        size = height.shape[0]
        blur = np.asarray(Image.fromarray((height * 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(size / 160.0)), np.float32) / 255.0
        cracks = smoothstep(0.015, 0.07, blur - height)
        pools = 1.0 - smoothstep(0.015, 0.07, height)
        melt = np.maximum(cracks, pools)
        heat = melt[..., None]
        molten = np.stack([np.ones_like(melt), 0.28 + 0.5 * melt, 0.04 + 0.18 * melt * melt], -1)
        albedo = crust * (1.0 - heat) + molten * heat
        rough = rough * (1.0 - melt) * 0.95 + 0.35 * melt
    elif kind == "basalt":
        grey = luma[..., None]
        albedo = (albedo * 0.35 + grey * 0.65) * np.array([0.78, 0.74, 0.72], dtype=np.float32)
        ash = smoothstep(0.55, 0.9, height)[..., None] * 0.25   # popel na vyvýšeninách
        albedo = albedo * (1.0 - ash) + np.array([0.42, 0.40, 0.39], dtype=np.float32) * ash
    elif kind == "amethyst":
        dark = np.array([0.12, 0.05, 0.19], dtype=np.float32)
        light = np.array([0.74, 0.56, 0.92], dtype=np.float32)
        t = np.clip((luma - luma.mean()) * 1.6 + 0.45, 0.0, 1.0)[..., None]
        albedo = dark * (1.0 - t) + light * t
        glint = smoothstep(0.78, 0.95, height)
        albedo = albedo + glint[..., None] * np.array([0.22, 0.16, 0.30], dtype=np.float32)
        rough = rough * (1.0 - glint * 0.6)
    return np.clip(albedo, 0.0, 1.0), np.clip(rough, 0.03, 1.0)


def build(name: str, asset: str, kind: str | None, cache: pathlib.Path, albedo_size: int, surface_size: int) -> None:
    print(f"{name}: {asset}" + (f" ({kind})" if kind else ""))
    p = fetch(asset, cache)
    albedo = load(p["albedo"], albedo_size, "RGB")
    ao = load(p["ao"], albedo_size, "L") if "ao" in p else np.ones(albedo.shape[:2], np.float32)
    height_hi = stretch(load(p["height"], albedo_size, "L"))
    rough_hi = load(p["rough"], albedo_size, "L")
    albedo, _ = variant(kind, albedo, rough_hi, height_hi)
    albedo = albedo * (0.45 + 0.55 * ao)[..., None]   # zapečená okluze (G-buffer nemá kanál AO)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(albedo, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        OUT / f"{name}_albedo.jpg", quality=90, optimize=True, subsampling=0)

    normal = load(p["normal"], surface_size, "RGB")
    # sken bývá mírně nakloněný (svah při focení): průměrná normála musí mířit kolmo z povrchu, jinak by
    # celá vrstva působila jako osvětlená z jedné strany
    nxy = normal[..., :2] * 2.0 - 1.0
    nxy -= nxy.mean(axis=(0, 1), keepdims=True)
    normal = np.dstack([nxy * 0.5 + 0.5, normal[..., 2]])
    rough = load(p["rough"], surface_size, "L")
    height = stretch(load(p["height"], surface_size, "L"))
    small = np.asarray(Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8)).resize(
        (surface_size, surface_size), Image.LANCZOS), np.float32) / 255.0
    _, rough = variant(kind, small, rough, height)
    surface = np.dstack([normal[..., 0], normal[..., 1], rough, height])
    Image.fromarray((np.clip(surface, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(
        OUT / f"{name}_surface.png", optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.environ.get("ERYNDOR_TEXTURE_CACHE",
                                                      str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    ap.add_argument("--albedo", type=int, default=2048)
    ap.add_argument("--surface", type=int, default=1024)
    ap.add_argument("--only", nargs="*", help="jen vybrané vrstvy")
    args = ap.parse_args()
    cache = pathlib.Path(args.cache)
    for name, (asset, kind) in LAYERS.items():
        if args.only and name not in args.only:
            continue
        build(name, asset, kind, cache, args.albedo, args.surface)
    (OUT / "CREDITS.txt").write_text(
        "Povrchy terénu: fotoskeny Poly Haven (https://polyhaven.com), licence CC0 1.0.\n"
        "Vygenerováno skriptem tools/terrain_pbr.py.\n\n" +
        "".join(f"{n}: https://polyhaven.com/a/{a}\n" for n, (a, _) in LAYERS.items()), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
