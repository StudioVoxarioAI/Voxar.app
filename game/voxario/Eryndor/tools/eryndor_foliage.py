#!/usr/bin/env python3
"""Fotorealistická vegetace Eryndoru: trsy trávy a stromy z fotoskenů Poly Haven (CC0).

  python3 tools/eryndor_foliage.py [--cache <složka>]

Fotoskeny (stáhnou se jednou do cache):
  grass_medium_01   trsy trávy (atlas s průhledností) -> karty trávy
  island_tree_02    fotky listů                         -> textura větvičky s listy (složená z jednotlivých listů)
  fir_tree_01       větvičky jedle (atlas s průhledností) -> karty jehličí
  bark_brown_02     kůra listnáče (dlaždicová PBR)
  pine_bark         kůra jehličnanu (dlaždicová PBR)

Výstup:
  Assets/Textures/nature/foliage/*.png            atlasy karet (RGBA, barva rozšířená pod průhledné okraje)
  Assets/Textures/nature/pbr/bark_*_{basecolor,normal,orm}.jpg
  Assets/Models/nature/grass_clump_<n>.glb        trs trávy (3 překřížené karty, ~0,45 m)
  Assets/Models/nature/tree_<n>.glb               listnáč (větvený kmen + koruna z karet s listy)
  Assets/Models/nature/pine_<n>.glb               jehličnan (přesleny větví s kartami jehličí)

Materiály karet se jmenují „foliage …“ – engine ≥ 1.22 jim nechá normálu ohnutou k obloze z obou stran
a nechá světlo prosvítat (listí proti slunci svítí). Bez meshy.ai: jen fotoskeny CC0 a deterministický kód.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import sys
import urllib.request
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import Mesh, displace, lathe, merge, write_glb  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Assets"
NAT = ASSETS / "Models" / "nature"
FOL = ASSETS / "Textures" / "nature" / "foliage"
PBR = ASSETS / "Textures" / "nature" / "pbr"
API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "eryndor-foliage/1.0"}


# ------------------------------------------------------------------ stahování
def fetch(asset, maps, cache, res="2k"):
    folder = cache / asset
    folder.mkdir(parents=True, exist_ok=True)
    meta = folder / "files.json"
    if not meta.exists():
        with urllib.request.urlopen(urllib.request.Request(API + asset, headers=UA), timeout=60) as r:
            meta.write_bytes(r.read())
    data = json.loads(meta.read_text())
    out = {}
    for key in maps:
        formats = data[key][res]
        fmt = "png" if "alpha" in key.lower() and "png" in formats else ("jpg" if "jpg" in formats else "png")
        target = folder / f"{key}_{res}.{fmt}"
        if not target.exists():
            print(f"  stahuji {asset}/{key} ({res})")
            with urllib.request.urlopen(urllib.request.Request(formats[fmt]["url"], headers=UA), timeout=180) as r:
                tmp = target.with_suffix(".part")
                tmp.write_bytes(r.read())
                os.replace(tmp, target)
        out[key] = target
    return out


def rgba(diffuse, alpha):
    d = Image.open(diffuse).convert("RGB")
    a = Image.open(alpha).convert("L").resize(d.size, Image.LANCZOS)
    # téměř černé pixely atlasu (zbytky stínů / výplně mezi ostrůvky) nejsou list ani stéblo
    arr = np.asarray(d, np.float32)
    dark = arr.max(axis=2) < 22
    av = np.asarray(a).copy()
    av[dark] = 0
    img = d.copy()
    img.putalpha(Image.fromarray(av, "L"))
    return img


def bleed(img: Image.Image, steps=24) -> Image.Image:
    """Barva okrajů se rozšíří pod průhledné pixely (mipmapy pak nemají tmavé ani fialové lemy)."""
    arr = np.asarray(img, np.float32) / 255.0
    rgb, a = arr[..., :3], arr[..., 3:]
    mask = (a > 0.5).astype(np.float32)
    acc = rgb * mask
    w = mask.copy()
    out = rgb.copy()
    filled = mask[..., 0] > 0
    for _ in range(steps):
        acc = (acc + np.roll(acc, 1, 0) + np.roll(acc, -1, 0) + np.roll(acc, 1, 1) + np.roll(acc, -1, 1))
        w = (w + np.roll(w, 1, 0) + np.roll(w, -1, 0) + np.roll(w, 1, 1) + np.roll(w, -1, 1))
        new = (~filled) & (w[..., 0] > 1e-3)
        out[new] = acc[new] / w[new]
        filled |= new
        acc = np.where(filled[..., None], out * 1.0, 0.0)
        w = filled[..., None].astype(np.float32)
    mean = rgb[mask[..., 0] > 0].mean(0) if mask.any() else np.zeros(3)
    out[~filled] = mean
    res = np.concatenate([out, a], -1)
    return Image.fromarray((np.clip(res, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def sprites(alpha: Image.Image, scale=4, min_area=300):
    """Souvislé ostrůvky neprůhlednosti (jednotlivé listy / větvičky) – obdélníky v původním rozlišení."""
    small = np.asarray(alpha.convert("L").resize((alpha.width // scale, alpha.height // scale), Image.BILINEAR)) > 60
    h, w = small.shape
    seen = np.zeros_like(small)
    boxes = []
    for y in range(h):
        for x in range(w):
            if small[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                y0 = y1 = y
                x0 = x1 = x
                n = 0
                while q:
                    cy, cx = q.popleft()
                    n += 1
                    y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and small[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                if n * scale * scale >= min_area * scale:
                    boxes.append(((x0 - 1) * scale, (y0 - 1) * scale, (x1 + 2) * scale, (y1 + 2) * scale, n))
    return boxes


# ------------------------------------------------------------------ textury
# trsy trávy v atlasu grass_medium_01 (2048 px): x0, y0, x1, y1 (bez zatoulaných stébel nad / vedle trsu)
GRASS_CLUMPS = [(400, 1540, 920, 1800), (1207, 1547, 1640, 1760), (53, 1780, 413, 2000), (487, 1807, 1020, 2002),
                (1180, 1760, 1620, 2030)]


def grass_atlas(cache):
    p = fetch("grass_medium_01", ["Diffuse", "Alpha"], cache)
    src = rgba(p["Diffuse"], p["Alpha"])
    cells = []
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for i, box in enumerate(GRASS_CLUMPS):
        crop = src.crop(box).resize((512, 256), Image.LANCZOS)
        cx, cy = (i % 2) * 512, (i // 2) * 256
        atlas.paste(crop, (cx, cy))
        cells.append((cx / 1024, cy / 1024, (cx + 512) / 1024, (cy + 256) / 1024))
    # suchá varianta posledního řádku: žlutější trs (ne každé stéblo je zelené)
    dry = atlas.crop((0, 0, 512, 256))
    arr = np.asarray(dry, np.float32)
    arr[..., 0] *= 1.25
    arr[..., 1] *= 1.08
    arr[..., 2] *= 0.75
    atlas.paste(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA"), (512, 768))
    cells.append((0.5, 0.75, 1.0, 1.0))
    # fotosken je ve stínu ateliéru tmavší než louka na slunci
    arr = np.asarray(atlas, np.float32)
    arr[..., :3] *= np.array([1.22, 1.2, 1.1])
    atlas = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    FOL.mkdir(parents=True, exist_ok=True)
    bleed(atlas).save(FOL / "grass_clumps.png", optimize=True)
    return cells


def leaf_twig_atlas(cache, seed=5):
    """Větvičky s listy složené z fotek jednotlivých listů (island_tree_02) – 4 varianty v atlasu 1024 px."""
    p = fetch("island_tree_02", ["leaves_diff", "leaves_alpha"], cache)
    src = rgba(p["leaves_diff"], p["leaves_alpha"])
    boxes = [b for b in sprites(src.getchannel("A")) if (b[2] - b[0]) * (b[3] - b[1]) > 40000]
    leaves = []
    for x0, y0, x1, y1, _ in boxes:
        leaf = src.crop((max(x0, 0), max(y0, 0), min(x1, src.width), min(y1, src.height)))
        # stopka listu dole: list „visí“ ze stopky, orientace podle delší osy
        if leaf.width > leaf.height:
            leaf = leaf.rotate(90, expand=True)
        leaves.append(leaf)
    rng = np.random.default_rng(seed)
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    cells = []
    for v in range(4):
        cell = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        # tenká větvička uprostřed, listy střídavě do stran
        twig = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        tw = np.zeros((512, 512, 4), np.uint8)
        for y in range(40, 500):
            x = int(256 + 10 * math.sin(y / 70.0 + v))
            tw[y, x - 3:x + 3] = (78, 62, 44, 255)
        twig = Image.fromarray(tw, "RGBA")
        cell.alpha_composite(twig)
        for k in range(22):
            leaf = leaves[int(rng.integers(len(leaves)))]
            length = int(rng.uniform(120, 190))
            scale = length / leaf.height
            lf = leaf.resize((max(8, int(leaf.width * scale)), length), Image.LANCZOS)
            y = int(470 - k * 19 - rng.uniform(0, 12))
            side = -1 if k % 2 == 0 else 1
            angle = side * rng.uniform(35, 75) + rng.normal() * 8
            # odstín listu (mladé světlejší, staré tmavší)
            arr = np.asarray(lf, np.float32)
            tint = rng.uniform(0.72, 1.0)
            # letní listí: sytější zelená (fotky listů jsou do žluta), občas starší tmavší list
            arr[..., :3] *= np.array([tint * rng.uniform(0.66, 0.8), tint * 0.98, tint * rng.uniform(0.55, 0.7)])
            lf = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").rotate(angle, expand=True,
                                                                                   resample=Image.BICUBIC)
            x = int(256 + 10 * math.sin(y / 70.0 + v) - lf.width / 2 + side * lf.width * 0.32)
            cell.alpha_composite(lf, (int(np.clip(x, -lf.width // 2, 512 - lf.width // 2)),
                                      int(np.clip(y - lf.height * 0.5, 0, 512 - 8))))
        # stopka vlevo, větvička míří doprava (karta roste od větve ven podél U)
        atlas.paste(cell.rotate(-90), ((v % 2) * 512, (v // 2) * 512))
        cells.append(((v % 2) * 0.5, (v // 2) * 0.5, (v % 2) * 0.5 + 0.5, (v // 2) * 0.5 + 0.5))
    FOL.mkdir(parents=True, exist_ok=True)
    bleed(atlas).save(FOL / "leaf_twigs.png", optimize=True)
    return cells


def fir_atlas(cache):
    """Větvičky jedle (fir_tree_01) – největší ostrůvky atlasu, každá do vlastní buňky 512 px."""
    p = fetch("fir_tree_01", ["twig_diff", "twig_alpha"], cache)
    src = rgba(p["twig_diff"], p["twig_alpha"])
    boxes = sorted(sprites(src.getchannel("A")), key=lambda b: -(b[2] - b[0]) * (b[3] - b[1]))
    picks = []
    arr = np.asarray(src, np.float32)
    for b in boxes:
        w, h = b[2] - b[0], b[3] - b[1]
        if w < 250 or h < 250 or len(picks) >= 4:
            continue
        sub = arr[max(b[1], 0):b[3], max(b[0], 0):b[2]]
        opaque = sub[..., 3] > 128
        cover = opaque.mean()
        if not opaque.any():
            continue
        r, g = sub[..., 0][opaque].mean(), sub[..., 1][opaque].mean()
        # zelená řídká větvička (ne pruh kůry ani suchá větev)
        if g > r * 1.08 and cover < 0.5:
            picks.append(b)
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    cells = []
    for i, (x0, y0, x1, y1, _) in enumerate(picks):
        crop = src.crop((max(x0, 0), max(y0, 0), min(x1, src.width), min(y1, src.height)))
        # větvička míří od kmene (+X): delší osa vodorovně
        if crop.height > crop.width:
            crop = crop.rotate(-90, expand=True)
        crop.thumbnail((512, 512), Image.LANCZOS)
        cx, cy = (i % 2) * 512, (i // 2) * 512
        atlas.paste(crop, (cx + (512 - crop.width) // 2, cy + (512 - crop.height) // 2))
        cells.append((cx / 1024, cy / 1024, (cx + 512) / 1024, (cy + 512) / 1024))
    FOL.mkdir(parents=True, exist_ok=True)
    bleed(atlas).save(FOL / "fir_twigs.png", optimize=True)
    return cells


def bark(cache, asset, name):
    p = fetch(asset, ["Diffuse", "nor_gl", "arm"], cache, "1k")
    PBR.mkdir(parents=True, exist_ok=True)
    Image.open(p["Diffuse"]).convert("RGB").save(PBR / f"{name}_basecolor.jpg", quality=88)
    Image.open(p["nor_gl"]).convert("RGB").save(PBR / f"{name}_normal.jpg", quality=92)
    Image.open(p["arm"]).convert("RGB").save(PBR / f"{name}_orm.jpg", quality=88)
    return dict(name="bark", texture=str(PBR / f"{name}_basecolor.jpg"), normal=str(PBR / f"{name}_normal.jpg"),
                orm=str(PBR / f"{name}_orm.jpg"), uv_scale=1.2, roughness=1.0)


# ------------------------------------------------------------------ geometrie
def card(center, right, up, w, h, uv, normal_bend, pivot="bottom"):
    """Obdélníková karta: střed spodní hrany (pivot bottom) nebo kořene (pivot left) v `center`."""
    right = np.asarray(right, np.float32)
    up = np.asarray(up, np.float32)
    c = np.asarray(center, np.float32)
    if pivot == "bottom":
        P = [c - right * w / 2, c + right * w / 2, c + right * w / 2 + up * h, c - right * w / 2 + up * h]
    else:   # kořen karty u větve, karta míří podél `right`
        P = [c - up * h / 2, c + right * w - up * h / 2, c + right * w + up * h / 2, c + up * h / 2]
    u0, v0, u1, v1 = uv
    UV = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)] if pivot == "bottom" else [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
    m = Mesh(np.array(P, np.float32), [[0, 1, 2], [0, 2, 3]])
    m.UV = np.array(UV, np.float32)
    N = np.array([normal_bend(p) for p in P], np.float32)
    m.N = N / np.linalg.norm(N, axis=1, keepdims=True)
    return m


def foliage_material(texture, roughness=0.75, cutoff=0.45):
    return dict(name="foliage", texture=str(texture), double=True, alpha_cutoff=cutoff, roughness=roughness)


def grass_clump(cells, seed, out):
    rng = np.random.default_rng(seed)
    parts = []
    up = np.array([0.0, 1.0, 0.0])
    cell_ids = rng.choice(len(cells), 3, replace=True)
    for k in range(3):
        a = k * math.pi / 3 + rng.uniform(-0.25, 0.25)
        right = np.array([math.cos(a), 0.0, math.sin(a)])
        w = rng.uniform(0.75, 0.95)
        h = w * 0.5 * rng.uniform(0.9, 1.15)
        off = rng.normal(0, 0.06, 3) * np.array([1, 0, 1])
        m = card(off, right, up, w, h, cells[cell_ids[k]], lambda p: np.array([0.0, 1.0, 0.0]) * 1.0 +
                 np.array([p[0], 0.0, p[2]]) * 0.25)
        # zastínění u kořene (husté stébla se navzájem stíní)
        m.C[:, :3] = np.where(m.P[:, 1:2] < 0.05, 0.55, 1.0)
        parts.append(m)
    write_glb(str(out), [(merge(*parts), foliage_material(FOL / "grass_clumps.png", 0.8, 0.4))], name="GrassClump")


def bend_out(center, up_bias=0.8):
    c = np.asarray(center, np.float32)

    def f(p):
        d = np.asarray(p, np.float32) - c
        d /= max(np.linalg.norm(d), 1e-4)
        return d + np.array([0.0, up_bias, 0.0], np.float32)
    return f


def branch(start, direction, length, r0, r1, seg=6):
    """Válec od `start` ve směru `direction` (kónický)."""
    d = np.asarray(direction, np.float64)
    d /= np.linalg.norm(d)
    m = lathe([(r0, 0.0), (r1, length)], seg, False, False)
    # osa Y -> d
    y = np.array([0.0, 1.0, 0.0])
    v = np.cross(y, d)
    s, c = np.linalg.norm(v), float(np.dot(y, d))
    if s < 1e-6:
        R = np.eye(3) if c > 0 else np.diag([1, -1, -1])
    else:
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + vx + vx @ vx * ((1 - c) / (s * s))
    m.P = (m.P @ R.T + np.asarray(start)).astype(np.float32)
    return m


def broadleaf(seed, cells, bark_mat, out):
    """Listnáč ~9–12 m: kmen, 2 úrovně větví, koruna z ~260 karet větviček s listy."""
    rng = np.random.default_rng(seed)
    h = rng.uniform(4.2, 5.4)
    trunk = lathe([(0.34, 0.0), (0.27, 0.6), (0.22, h * 0.5), (0.16, h)], 10, True, True)
    displace(trunk, 0.03, 2.0, seed)
    wood = [trunk]
    tips = []
    crown_c = np.array([0.0, h + 2.6, 0.0])
    for i in range(int(rng.integers(5, 8))):
        a = i / 6 * 2 * math.pi + rng.uniform(-0.3, 0.3)
        y = h * rng.uniform(0.62, 1.0)
        d = np.array([math.cos(a), rng.uniform(0.55, 1.1), math.sin(a)])
        L = rng.uniform(2.6, 3.8)
        start = np.array([0.0, y, 0.0])
        wood.append(branch(start, d, L, 0.12, 0.05))
        end = start + d / np.linalg.norm(d) * L
        for j in range(3):
            d2 = d / np.linalg.norm(d) + rng.normal(0, 0.55, 3) + np.array([0, 0.3, 0])
            L2 = rng.uniform(1.0, 1.8)
            s2 = start + (end - start) * rng.uniform(0.5, 0.95)
            wood.append(branch(s2, d2, L2, 0.05, 0.02, 5))
            tips.append((s2, d2 / np.linalg.norm(d2), L2))
        tips.append((start, d / np.linalg.norm(d), L))
    wood.append(branch(np.array([0, h, 0]), np.array([0.05, 1, 0.02]), 2.2, 0.15, 0.05))
    tips.append((np.array([0, h, 0]), np.array([0, 1, 0]), 2.2))
    cards = []
    bend = bend_out(crown_c, 0.6)
    for s, d, L in tips:
        for _ in range(22):
            p = s + d * L * rng.uniform(0.3, 1.0) + rng.normal(0, 0.5, 3)
            out_dir = p - crown_c
            out_dir[1] *= 0.4
            out_dir = out_dir / max(np.linalg.norm(out_dir), 1e-3) + rng.normal(0, 0.5, 3)
            out_dir[1] -= 0.25   # listy převisají
            out_dir /= np.linalg.norm(out_dir)
            up = np.cross(out_dir, rng.normal(0, 1, 3))
            up /= np.linalg.norm(up)
            size = rng.uniform(0.75, 1.15)
            cards.append(card(p, out_dir, up, size, size, cells[int(rng.integers(len(cells)))], bend, pivot="left"))
    leaves = merge(*cards)
    # vnitřek koruny tmavší (samozastínění), vnějšek a vršek světlejší
    dist = np.linalg.norm((leaves.P - crown_c) * np.array([1, 1.4, 1]), axis=1)
    k = np.clip(dist / 3.2, 0.35, 1.0)
    leaves.C[:, :3] = (0.55 + 0.45 * k)[:, None] * np.clip(0.85 + 0.12 * (leaves.P[:, 1:2] - h) / 3, 0.75, 1.1)
    write_glb(str(out), [(merge(*wood), bark_mat), (leaves, foliage_material(FOL / "leaf_twigs.png", 0.7, 0.45))],
              name="Tree")


def conifer(seed, cells, bark_mat, out):
    """Jehličnan ~11–14 m: rovný kmen, přesleny větví (dolní delší, převislé), karty jehličí podél větví."""
    rng = np.random.default_rng(seed)
    h = rng.uniform(11.0, 14.0)
    trunk = lathe([(0.3, 0.0), (0.24, 0.8), (0.12, h * 0.75), (0.02, h)], 10, True, True)
    displace(trunk, 0.025, 2.0, seed)
    wood = [trunk]
    cards = []
    whorls = 13
    for wi in range(whorls):
        t = wi / (whorls - 1)
        y = h * (0.18 + 0.78 * t)
        reach = (1.0 - t) * 3.1 + 0.45
        n = int(rng.integers(5, 7))
        for bi in range(n):
            a = bi / n * 2 * math.pi + wi * 0.7 + rng.uniform(-0.2, 0.2)
            d = np.array([math.cos(a), -0.12 - 0.25 * (1 - t) + rng.uniform(-0.05, 0.08), math.sin(a)])
            d /= np.linalg.norm(d)
            start = np.array([0.0, y, 0.0])
            wood.append(branch(start, d, reach, 0.06 * (1 - t) + 0.02, 0.012, 4))
            # karty jehličí podél větve, natočené vodorovně (plochá „patra“) s mírným převisem
            steps = max(2, int(reach / 0.55))
            for s in range(steps):
                p = start + d * reach * (0.25 + 0.75 * s / steps)
                side = np.cross(d, np.array([0.0, 1.0, 0.0]))
                side /= np.linalg.norm(side)
                for sgn in (-1, 1):
                    dirc = d * 0.55 + side * sgn * 0.8 + np.array([0, -0.15, 0])
                    dirc /= np.linalg.norm(dirc)
                    up = np.cross(dirc, np.array([0.0, 1.0, 0.0]))
                    up = np.cross(up, dirc)
                    up /= np.linalg.norm(up)
                    tilt = rng.normal(0, 0.25)
                    up = up * math.cos(tilt) + side * math.sin(tilt)
                    size = rng.uniform(0.75, 1.05) * (0.6 + 0.4 * (1 - t))
                    cards.append(card(p, dirc, up, size, size * 0.7, cells[int(rng.integers(len(cells)))],
                                      bend_out(np.array([0, y + 0.8, 0]), 1.0), pivot="left"))
    # špička
    for k in range(4):
        a = k * math.pi / 2
        d = np.array([math.cos(a) * 0.4, 1.0, math.sin(a) * 0.4])
        d /= np.linalg.norm(d)
        up = np.cross(d, np.array([math.sin(a), 0, -math.cos(a)]))
        cards.append(card(np.array([0, h - 1.3, 0]), d, up, 1.3, 0.8, cells[k % len(cells)],
                          bend_out(np.array([0, h - 2, 0]), 1.0), pivot="left"))
    leaves = merge(*cards)
    r = np.linalg.norm(leaves.P[:, [0, 2]], axis=1)
    leaves.C[:, :3] = (0.5 + 0.5 * np.clip(r / 2.2, 0, 1))[:, None]
    write_glb(str(out), [(merge(*wood), bark_mat), (leaves, foliage_material(FOL / "fir_twigs.png", 0.75, 0.42))],
              name="Pine")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cache", default=os.environ.get("ERYNDOR_TEXTURE_CACHE",
                                                      str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    args = ap.parse_args()
    cache = pathlib.Path(args.cache) / "plants"
    grass_cells = grass_atlas(cache)
    for k in range(3):
        grass_clump(grass_cells, 40 + k, NAT / f"grass_clump_{k}.glb")
    oak = bark(cache, "bark_brown_02", "bark_oak")
    pine_bark = bark(cache, "pine_bark", "bark_pine")
    leaf_cells = leaf_twig_atlas(cache)
    for k in range(3):
        broadleaf(100 + k, leaf_cells, oak, NAT / f"tree_{k}.glb")
    fir_cells = fir_atlas(cache)
    for k in range(3):
        conifer(200 + k, fir_cells, pine_bark, NAT / f"pine_{k}.glb")
    (FOL / "CREDITS.txt").write_text(
        "Vegetace: fotoskeny Poly Haven (https://polyhaven.com), licence CC0 1.0 – grass_medium_01, island_tree_02,\n"
        "fir_tree_01, bark_brown_02, pine_bark. Vygenerováno skriptem tools/eryndor_foliage.py.\n", encoding="utf-8")
    print("hotovo")


if __name__ == "__main__":
    main()
