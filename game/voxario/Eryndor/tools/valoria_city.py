#!/usr/bin/env python3
"""Valorie Harbor – stavebnice startovního města podle předlohy (gotické věže, kopule, hrázděné domy, brána
VALORIE, lucerny, přístav s loděmi, létající ostrovy).

  python3 tools/valoria_city.py      -> Assets/Models/valoria/city/*.glb, Assets/Textures/valoria/city/*.png

Materiály jsou fotoskeny Poly Haven (CC0, tools/valoria_pbr.py) – vápencové kvádry, břidlice / olovo, omítka,
dubové trámy, prkna, plátno; nápis brány a prapory se kreslí písmem DejaVu Serif. Bez generativních služeb.
Počátek každého modelu = střed půdorysu na zemi, +Z = průčelí (vstup).
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from meshkit import Mesh, box, cone, cylinder, lathe, merge, sphere, write_glb, displace
import valoria_assets as va

ASSETS = Path(__file__).resolve().parent.parent / "Assets"
OUT = ASSETS / "Models" / "valoria" / "city"
TEX = ASSETS / "Textures" / "valoria" / "city"
PBR = ASSETS / "Textures" / "valoria" / "pbr"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def pbr(name, label, tile, **extra):
    return dict(name=label, texture=str(PBR / f"{name}_basecolor.jpg"), normal=str(PBR / f"{name}_normal.jpg"),
                orm=str(PBR / f"{name}_orm.jpg"), uv_scale=tile, roughness=1.0, **extra)


LIME = pbr("limestone", "limestone", 2.0)
LEAD = pbr("lead", "lead roof", 2.5)
SLATE = pbr("slate", "slate roof", 3.0, uv_swap=True)
CLAY = pbr("clay", "clay roof", 4.0, uv_swap=True)
PLASTER = pbr("plaster", "plaster", 1.0)
WOOD = pbr("timber", "timber", 2.0)
PLANKS = pbr("planks", "planks", 2.0)
STONE = pbr("stone", "stone", 2.5)
COBBLE = pbr("cobble", "cobble", 2.0)
GOLD = dict(name="aged gold", color=(0.62, 0.45, 0.18), roughness=0.35, metallic=0.85)
IRON = dict(name="iron", color=(0.08, 0.08, 0.09), roughness=0.55, metallic=0.8)
GLASS = dict(name="dark glass", color=(0.04, 0.06, 0.08), roughness=0.2, metallic=0.1)
GLOW = dict(name="window glow", color=(0.2, 0.12, 0.05), emissive=(1.0, 0.58, 0.24), emissive_strength=1.4)
ROPE = dict(name="rope", color=(0.25, 0.2, 0.14), roughness=0.9)


def cloth(color, name):
    return dict(pbr("linen", name, 0.6), color=color, double=True)


SAILS = [cloth((1.9, 0.62, 0.45), "sail red"), cloth((0.75, 1.35, 1.2), "sail teal"),
         cloth((2.4, 2.0, 1.1), "sail cream")]


def b(x, y, z, sx, sy, sz):
    return box(sx, sy, sz, center=(x, y, z))


def uv_quad(p0, p1, p2, p3, normal):
    """Obdélník s UV 0..1 (nápisy, prapory)."""
    m = Mesh(np.array([p0, p1, p2, p3], np.float32), [[0, 1, 2], [0, 2, 3]])
    m.UV = np.array([[0, 1], [1, 1], [1, 0], [0, 0]], np.float32)
    m.N = np.repeat(np.array([normal], np.float32), 4, 0)
    return m


# ------------------------------------------------------------------ textury (nápis, prapor)
def textures():
    TEX.mkdir(parents=True, exist_ok=True)
    # nápis VALORIE: tmavě modrá deska se zlatým rámem a písmem
    w, h = 2048, 360
    img = Image.new("RGB", (w, h), (24, 34, 64))
    d = ImageDraw.Draw(img)
    for i in range(14):
        c = int(40 + i * 3)
        d.rectangle([i, i, w - 1 - i, h - 1 - i], outline=(c + 120, c + 80, c + 10) if i in (3, 4, 10, 11) else None)
    font = ImageFont.truetype(FONT, 250)
    text = "VALORIE"
    tw = d.textlength(text, font=font)
    for off, col in ((6, (10, 12, 22)), (0, (226, 186, 104))):
        d.text(((w - tw) / 2 + off, 38 + off), text, font=font, fill=col)
    # jemná patina
    arr = np.asarray(img, np.float32)
    noise = np.random.default_rng(3).normal(0, 6, arr.shape[:2])[..., None]
    img = Image.fromarray(np.clip(arr + noise, 0, 255).astype(np.uint8))
    img.save(TEX / "gate_sign.png")
    # prapor: modré plátno se zlatým V a lemem, cípy dole
    w, h = 256, 768
    ban = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(ban)
    d.polygon([(0, 0), (w, 0), (w, h - 90), (w // 2, h), (0, h - 90)], fill=(30, 48, 104, 255))
    d.line([(14, 20), (w - 14, 20)], fill=(212, 170, 88, 255), width=8)
    d.line([(14, 20), (14, h - 100), (w // 2, h - 22), (w - 14, h - 100), (w - 14, 20)], fill=(212, 170, 88, 255), width=8)
    font = ImageFont.truetype(FONT, 230)
    tw = d.textlength("V", font=font)
    d.text(((w - tw) / 2, 200), "V", font=font, fill=(222, 182, 98, 255))
    ban.save(TEX / "banner_v.png")


SIGN = dict(name="gate sign", texture=str(TEX / "gate_sign.png"), roughness=0.6)
BANNER = dict(name="banner", texture=str(TEX / "banner_v.png"), roughness=0.8, double=True, alpha_cutoff=0.5)


def banner(x, y, z, width, height, facing=1.0):
    """Svislý prapor na zdi (UV přes celý obrázek), facing = +1 průčelí +Z."""
    zz = z + 0.06 * facing
    return uv_quad((x - width / 2, y - height, zz), (x + width / 2, y - height, zz), (x + width / 2, y, zz),
                   (x - width / 2, y, zz), (0, 0, facing))


def window_unit(x, y, z, w, h, wood, glass, sill):
    """Okno do +Z: sklo (svítí / tmavé), dřevěný rám, křížová příčle, kamenný parapet."""
    glass.append(b(x, y, z + 0.01, w, h, 0.06))
    for dx in (-1, 1):
        wood.append(b(x + dx * (w / 2 + 0.04), y, z + 0.05, 0.1, h + 0.16, 0.1))
    for dy in (-1, 1):
        wood.append(b(x, y + dy * (h / 2 + 0.04), z + 0.05, w + 0.16, 0.1, 0.1))
    wood.append(b(x, y, z + 0.06, 0.05, h, 0.05))
    wood.append(b(x, y + h * 0.12, z + 0.06, w, 0.05, 0.05))
    sill.append(b(x, y - h / 2 - 0.1, z + 0.12, w + 0.3, 0.1, 0.24))


# ------------------------------------------------------------------ prvky
def windows(width, depth, levels, y0, step, seed, glow_ratio=0.35, round_r=None):
    """Úzká gotická okna na čtyřech stranách; část svítí (teplé světlo zevnitř)."""
    rng = np.random.default_rng(seed)
    dark, lit = [], []
    for lv in range(levels):
        y = y0 + lv * step
        for side in range(4):
            if round_r:
                a = side * math.pi / 2 + lv * 0.4
                x, z = math.cos(a) * (round_r + 0.02), math.sin(a) * (round_r + 0.02)
                win = box(0.9, 2.2, 0.12).rotate(0, -math.degrees(a) + 90, 0).translate(x, y, z)
                top = box(0.65, 0.65, 0.12).rotate(0, 0, 45).rotate(0, -math.degrees(a) + 90, 0).translate(
                    x, y + 1.1, z)
            else:
                horiz = side % 2 == 0
                sgn = 1 if side < 2 else -1
                if horiz:
                    x, z = 0.0, sgn * (depth / 2 + 0.03)
                    win = box(1.0, 2.3, 0.12).translate(x, y, z)
                    top = box(0.7, 0.7, 0.12).rotate(0, 0, 45).translate(x, y + 1.15, z)
                else:
                    x, z = sgn * (width / 2 + 0.03), 0.0
                    win = box(0.12, 2.3, 1.0).translate(x, y, z)
                    top = box(0.12, 0.7, 0.7).rotate(45, 0, 0).translate(x, y + 1.15, z)
            (lit if rng.random() < glow_ratio else dark).extend([win, top])
    return dark, lit


def spire_tower(w, h, spire, seed, round_tower=False, belfry=True):
    """Gotická věž: kvádrový / válcový dřík s opěráky a římsami, zvonice s okny, vysoká jehlancová střecha
    z olova se čtyřmi fiálami a zlatou makovicí."""
    stone, roof, gold, dark, lit = [], [], [], [], []
    stone.append(b(0, 0.8 - 4.0, 0, w + 1.6, 1.6 + 8.0, w + 1.6))   # sokl + základ 8 m pod terén
    if round_tower:
        r = w / 2
        stone.append(cylinder(r, r * 0.95, h, 20).translate(0, 0, 0))
        for y in np.arange(5.0, h, 7.0):
            stone.append(cylinder(r + 0.25, r + 0.25, 0.4, 20).translate(0, y, 0))
        stone.append(cylinder(r + 0.5, r + 0.5, 0.8, 20).translate(0, h, 0))
        d_, l_ = windows(w, w, max(1, int((h - 8) / 7)), 8.0, 7.0, seed, round_r=r * 0.97)
        dark += d_
        lit += l_
        roof.append(cone(r + 0.6, spire, 20).translate(0, h + 0.8, 0))
        top = h + 0.8 + spire
    else:
        stone.append(b(0, h / 2, 0, w, h, w))
        for sx in (-1, 1):
            for sz in (-1, 1):   # opěráky v rozích
                stone.append(b(sx * (w / 2 + 0.15), h * 0.45, sz * (w / 2 + 0.15), 1.1, h * 0.9, 1.1))
                stone.append(cone(0.75, 1.6, 4).rotate(0, 45, 0).translate(sx * (w / 2 + 0.15), h * 0.9, sz * (w / 2 + 0.15)))
        for y in np.arange(6.0, h - 2, 7.0):
            stone.append(b(0, y, 0, w + 0.5, 0.4, w + 0.5))
        d_, l_ = windows(w, w, max(1, int((h - 12) / 7)), 9.0, 7.0, seed)
        dark += d_
        lit += l_
        if belfry:   # zvonice: na každé straně dvojice vysokých oblouků
            for side in range(4):
                for k in (-1, 1):
                    off = k * w * 0.2
                    if side % 2 == 0:
                        z = (w / 2 + 0.04) * (1 if side == 0 else -1)
                        dark.append(b(off, h - 3.4, z, w * 0.22, 4.2, 0.14))
                        dark.append(box(w * 0.155, w * 0.155, 0.14).rotate(0, 0, 45).translate(off, h - 1.3, z))
                    else:
                        x = (w / 2 + 0.04) * (1 if side == 1 else -1)
                        dark.append(b(x, h - 3.4, off, 0.14, 4.2, w * 0.22))
                        dark.append(box(0.14, w * 0.155, w * 0.155).rotate(45, 0, 0).translate(x, h - 1.3, off))
        stone.append(b(0, h + 0.4, 0, w + 0.9, 0.8, w + 0.9))
        for sx in (-1, 1):   # fiály v rozích
            for sz in (-1, 1):
                stone.append(b(sx * w / 2, h + 1.6, sz * w / 2, 0.8, 1.6, 0.8))
                roof.append(cone(0.55, 3.8, 6).translate(sx * w / 2, h + 2.4, sz * w / 2))
                gold.append(sphere(0.18, 8, 6).translate(sx * w / 2, h + 6.3, sz * w / 2))
        roof.append(cone(w * 0.62, spire, 8).rotate(0, 22.5, 0).translate(0, h + 0.8, 0))
        top = h + 0.8 + spire
        # vikýře ve střeše (malé štíty s okny)
        for side in range(4):
            a = side * math.pi / 2
            dx, dz = math.sin(a), math.cos(a)
            yy = h + 0.8 + spire * 0.2
            rr = w * 0.62 * 0.8
            roof.append(box(1.4, 1.6, 1.0).rotate(0, math.degrees(a), 0).translate(dx * rr, yy + 0.8, dz * rr))
            dark.append(box(0.7, 1.0, 0.1).rotate(0, math.degrees(a), 0).translate(dx * (rr + 0.52), yy + 0.8, dz * (rr + 0.52)))
    gold.append(cylinder(0.07, 0.05, 2.6, 6).translate(0, top - 0.2, 0))
    gold.append(sphere(0.38, 10, 8).translate(0, top + 0.8, 0))
    return [(merge(*stone), LIME), (merge(*roof), LEAD), (merge(*dark), GLASS), (merge(*lit), GLOW),
            (merge(*gold), GOLD)]


def dome_hall(seed):
    """Kopulová rotunda (katedrála): kvádrová stavba s portikem, válcový tambur s okny, olověná kopule
    s lucernou a makovicí."""
    stone, roof, gold, dark, lit = [], [], [], [], []
    stone.append(b(0, 6.5 - 3.0, 0, 22, 13 + 6.0, 22))
    stone.append(b(0, 13.4, 0, 23, 0.8, 23))
    for x in np.linspace(-7.5, 7.5, 6):   # portikus
        stone.append(cylinder(0.7, 0.62, 10, 14).translate(x, 0, 12.5))
    stone.append(b(0, 10.6, 12.6, 18, 1.4, 3.4))
    stone.append(Mesh(np.array([[-9, 11.3, 14.3], [9, 11.3, 14.3], [0, 14.5, 14.3]], np.float32), [[0, 1, 2]]))
    stone.append(cylinder(8.0, 8.0, 7.0, 32).translate(0, 13.8, 0))
    stone.append(cylinder(8.4, 8.4, 0.6, 32).translate(0, 20.6, 0))
    d_, l_ = windows(16, 16, 1, 17.2, 0, seed, 0.5, round_r=8.0)
    dark += d_
    lit += l_
    d_, l_ = windows(22, 22, 2, 4.0, 5.0, seed + 3, 0.4)
    dark += d_
    lit += l_
    prof = [(8.3, 0.0)] + [(8.3 * math.cos(a), 7.6 * math.sin(a)) for a in np.linspace(0.05, math.pi / 2 - 0.08, 12)] + [(0.9, 7.55)]
    roof.append(lathe(prof, 32, False, True).translate(0, 21.0, 0))
    for k in range(16):   # žebra kopule
        a = k / 16 * 2 * math.pi
        rib = [cylinder(0.12, 0.12, 0.9, 4).rotate(0, 0, -math.degrees(t)).translate(
            8.35 * math.cos(t) * math.cos(a), 21.0 + 7.65 * math.sin(t), 8.35 * math.cos(t) * math.sin(a))
            for t in np.linspace(0.1, 1.35, 8)]
        gold += rib
    stone.append(cylinder(1.4, 1.4, 2.8, 12).translate(0, 28.4, 0))
    for k in range(6):
        a = k / 6 * 2 * math.pi
        lit.append(box(0.5, 1.4, 0.1).rotate(0, -math.degrees(a) + 90, 0).translate(1.45 * math.cos(a), 29.8, 1.45 * math.sin(a)))
    roof.append(lathe([(1.6, 0), (1.3, 0.8), (0.6, 1.5), (0.1, 1.8)], 12, False, True).translate(0, 31.2, 0))
    gold.append(sphere(0.4, 10, 8).translate(0, 33.4, 0))
    # malé kopule nad nárožími
    for sx in (-1, 1):
        for sz in (-1, 1):
            stone.append(cylinder(1.6, 1.6, 3.0, 12).translate(sx * 9.5, 13.8, sz * 9.5))
            roof.append(lathe([(1.9, 0), (1.5, 1.2), (0.7, 2.1), (0.1, 2.4)], 12, False, True).translate(sx * 9.5, 16.8, sz * 9.5))
            gold.append(sphere(0.18, 8, 6).translate(sx * 9.5, 19.4, sz * 9.5))
    return [(merge(*stone), LIME), (merge(*roof), LEAD), (merge(*dark), GLASS), (merge(*lit), GLOW),
            (merge(*gold), GOLD)]


def house(seed, width=9.0, depth=8.0, floors=3, roof_mat=SLATE):
    """Hrázděný městský dům: kamenné přízemí, vysunutá patra s trámy, strmá střecha s vikýřem a komínem."""
    rng = np.random.default_rng(seed)
    stone, plaster, wood, roof, dark, lit = [], [], [], [], [], []
    stone.append(b(0, 1.6 - 1.75, 0, width, 3.2 + 3.5, depth))   # přízemí + základ 3,5 m
    y = 3.2
    over = 0.0
    for f in range(floors - 1):
        over += 0.35
        w, d = width + over * 2 * 0.5, depth + over
        plaster.append(b(0, y + 1.45, over * 0.5, w, 2.9, d))
        fz = (d / 2 + over * 0.5) + 0.04
        # trámy průčelí (svislé, vodorovné, šikmé vzpěry)
        for x in np.linspace(-w / 2 + 0.15, w / 2 - 0.15, 5):
            wood.append(b(x, y + 1.45, fz, 0.22, 2.9, 0.16))
        wood.append(b(0, y + 0.1, fz, w, 0.25, 0.16))
        wood.append(b(0, y + 2.8, fz, w, 0.22, 0.16))
        for x in np.linspace(-w / 2 + 0.15, w / 2 - 0.15, 5)[:-1]:
            dx = (w - 0.3) / 4
            if rng.random() < 0.6:
                wood.append(box(0.18, math.hypot(dx, 2.6), 0.14).rotate(0, 0, math.degrees(math.atan2(dx, 2.6)) * (1 if (x > 0) else -1)).translate(x + dx / 2, y + 1.45, fz + 0.01))
        for x in np.linspace(-w / 2 + 0.15, w / 2 - 0.15, 5)[:-1]:   # okna mezi trámy
            dx = (w - 0.3) / 4
            window_unit(x + dx / 2, y + 1.55, fz + 0.02, dx * 0.5, 1.4, wood, lit if rng.random() < 0.35 else dark, stone)
        wood.append(b(0, y - 0.15, fz - 0.1, w, 0.3, 0.5))   # zhlaví vysunutého patra
        y += 2.9
    # přízemí: dveře a výloha
    wood.append(b(-width * 0.22, 1.25, depth / 2 + 0.05, 1.3, 2.5, 0.12))
    window_unit(width * 0.18, 1.6, depth / 2 + 0.02, 2.2, 1.4, wood, dark, stone)   # výloha
    stone.append(b(width * 0.18, 0.7, depth / 2 + 0.25, 2.6, 0.3, 0.5))
    # střecha: hřeben podél X (štít do ulice z boku), sklon ~52°
    w, d = width + over, depth + over
    zc = over * 0.5
    pitch = 52.0
    run = d / 2 + 0.5
    rise = math.tan(math.radians(pitch)) * (d / 2)
    slab = math.hypot(run, rise) + 0.2
    for sgn in (-1, 1):
        roof.append(box(w + 1.0, 0.35, slab).rotate(sgn * pitch, 0, 0).translate(0, y + rise / 2, zc + sgn * run / 2 - sgn * 0.25))
    for sx in (-1, 1):   # štíty
        x = sx * (w / 2)
        tri = Mesh(np.array([[x, y, zc - d / 2], [x, y, zc + d / 2], [x, y + rise, zc]], np.float32),
                   [[0, 1, 2]] if sx > 0 else [[0, 2, 1]])
        plaster.append(tri)
        wood.append(b(x + sx * 0.02, y + rise * 0.45, zc, 0.12, rise * 0.9, 0.2))
        lit.append(b(x + sx * 0.04, y + rise * 0.35, zc, 0.08, 1.0, 0.7)) if rng.random() < 0.5 else None
    # vikýř do ulice
    roof.append(b(0, y + rise * 0.35, zc + d / 2 - 0.6, 2.0, 1.8, 1.6))
    roof.append(box(2.6, 0.25, 1.9).rotate(0, 0, 0).translate(0, y + rise * 0.35 + 1.05, zc + d / 2 - 0.6))
    (lit if rng.random() < 0.5 else dark).append(b(0, y + rise * 0.33, zc + d / 2 + 0.22, 1.0, 1.0, 0.08))
    stone.append(b(w * 0.3, y + rise * 0.8, zc - 0.8, 0.9, rise * 0.9 + 1.2, 0.9))   # komín
    return [(merge(*stone), STONE), (merge(*plaster), dict(PLASTER, color=tuple(rng.uniform([0.92, 0.85, 0.7], [1.05, 1.0, 0.92])))),
            (merge(*wood), WOOD), (merge(*roof), roof_mat), (merge(*dark), GLASS), (merge(*lit), GLOW)]


def gate():
    """Brána VALORIE: dvě věže se špičatými střechami, oblouková brána, cimbuří, deska s nápisem a prapory.
    Průjezd vede podél osy Z (9 m široký, 12 m vysoký)."""
    parts = []
    for sx in (-1, 1):
        t = spire_tower(9.0, 26.0, 16.0, 40 + sx, belfry=True)
        for mesh, mat in t:
            parts.append((mesh.translate(sx * 10.5, 0, 0), mat))
    stone, dark = [], []
    span, height, thick = 12.0, 22.0, 9.0
    for i in range(48):   # zeď s obloukem (sloupky do výšky podle oblouku)
        x = -span / 2 + (i + 0.5) * span / 48
        bottom = 11.0 + 4.5 * math.sqrt(max(0.0, 1 - (x / 4.5) ** 2)) if abs(x) < 4.5 else 0.0
        stone.append(b(x, (bottom + height) / 2, 0, span / 48 + 0.01, height - bottom, thick))
    for i in range(25):   # klenák oblouku
        a = math.pi * i / 24
        stone.append(box(1.2, 0.9, 0.6).rotate(0, 0, -math.degrees(a)).translate(4.9 * math.cos(a), 11.0 + 4.9 * math.sin(a), thick / 2 + 0.2))
        stone.append(box(1.2, 0.9, 0.6).rotate(0, 0, -math.degrees(a)).translate(4.9 * math.cos(a), 11.0 + 4.9 * math.sin(a), -thick / 2 - 0.2))
    for x in np.arange(-5.5, 6.0, 2.2):   # cimbuří
        for z in (-thick / 2 + 0.4, thick / 2 - 0.4):
            stone.append(b(x, height + 0.9, z, 1.2, 1.8, 0.8))
    for sx in (-1, 1):   # tmavé obklady stěn průjezdu (průjezd zůstává volný)
        dark.append(b(sx * 4.42, 5.5, 0, 0.12, 11.0, thick - 0.6))
    # základy: brána stojí na hraně útesu – věže i zeď pokračují 36 m dolů do skály
    for sx in (-1, 1):
        stone.append(b(sx * 10.5, -18.0, 0, 10.6, 36.0, 10.6))
    stone.append(b(0, -18.0, 0, 12.0, 36.0, thick))
    parts += [(merge(*stone), LIME), (merge(*dark), dict(GLASS, color=(0.02, 0.02, 0.025)))]
    # podlaha průjezdu (y = 0 = mostovka) a mírná rampa do města (−Z), obojí s kolizí
    floor = [b(0, -0.25, 0, 8.8, 0.5, thick + 0.2),
             box(8.8, 0.4, 8.1).rotate(5.0, 0, 0).translate(0, -0.55, -thick / 2 - 4.0)]
    parts.append((merge(*floor), COBBLE))
    # deska s nápisem nad obloukem (obě strany) a zlatý rám
    sign, frame = [], []
    for sgn in (1, -1):
        z = sgn * (thick / 2 + 0.45)
        w, h, y = 11.0, 1.95, 18.0
        if sgn > 0:
            sign.append(uv_quad((-w / 2, y - h / 2, z), (w / 2, y - h / 2, z), (w / 2, y + h / 2, z), (-w / 2, y + h / 2, z), (0, 0, 1)))
        else:
            sign.append(uv_quad((w / 2, y - h / 2, z), (-w / 2, y - h / 2, z), (-w / 2, y + h / 2, z), (w / 2, y + h / 2, z), (0, 0, -1)))
        frame.append(b(0, y, z - sgn * 0.2, w + 0.5, h + 0.45, 0.35))
    parts += [(merge(*sign), SIGN), (merge(*frame), GOLD)]
    # prapory na věžích (do města i ven)
    flags = []
    for sx in (-1, 1):
        for sgn in (1, -1):
            m = banner(sx * 10.5, 22.5, sgn * (4.5 + 0.9), 3.0, 9.0, sgn)
            if sgn < 0:
                m.P[:, 0] = 2 * sx * 10.5 - m.P[:, 0]
            flags.append(m)
    parts.append((merge(*flags), BANNER))
    return parts


def lamp_post():
    """Litinová lampa: patka, štíhlý sloup, rameno a lucerna se svítícím sklem (světlo přidá hra)."""
    iron, glow = [], []
    iron.append(b(0, 0.25, 0, 0.6, 0.5, 0.6))
    iron.append(cylinder(0.11, 0.08, 4.2, 10).translate(0, 0.5, 0))
    iron.append(cylinder(0.16, 0.16, 0.2, 10).translate(0, 1.4, 0))
    iron.append(b(0, 4.6, 0, 0.55, 0.1, 0.55))
    for sx in (-1, 1):
        for sz in (-1, 1):
            iron.append(b(sx * 0.24, 5.0, sz * 0.24, 0.05, 0.8, 0.05))
    glow.append(b(0, 5.0, 0, 0.42, 0.72, 0.42))
    iron.append(cone(0.42, 0.45, 4).rotate(0, 45, 0).translate(0, 5.4, 0))
    iron.append(sphere(0.07, 6, 4).translate(0, 5.9, 0))
    return [(merge(*iron), IRON), (merge(*glow), dict(GLOW, emissive_strength=4.0))]


def ship(seed, sail_mat, length=20.0):
    """Plachetnice: trup z prken (příčné řezy), paluba, stěžeň s ráhnem a vzdutou plachtou, příďové čelen,
    lanoví. Příď míří k +Z, čára ponoru v y = 0."""
    rng = np.random.default_rng(seed)
    W, D = length * 0.26, 2.6
    rows, cols = 28, 13
    P = []
    for i in range(rows):
        s = i / (rows - 1)
        z = (s - 0.5) * length
        width = W / 2 * (1 - abs(2 * s - 1) ** 2.2) ** 0.55 + 0.05
        sheer = 1.4 + 1.2 * (2 * s - 1) ** 2   # vyšší příď a záď
        for j in range(cols):
            t = j / (cols - 1)
            a = math.pi * t
            x = -math.cos(a) * width
            yy = sheer - (D + sheer) * math.sin(a) ** 0.8
            P.append((x, yy, z))
    P = np.array(P, np.float32)
    idx = np.arange(rows * cols).reshape(rows, cols)
    I = []
    for i in range(rows - 1):
        for j in range(cols - 1):
            a0, b0, c0, d0 = idx[i, j], idx[i + 1, j], idx[i + 1, j + 1], idx[i, j + 1]
            I += [[a0, c0, b0], [a0, d0, c0]]
    hull = Mesh(P, I)
    deck = [b(0, 1.2, 0, W * 0.82, 0.15, length * 0.78)]
    deck.append(b(0, 2.1, -length * 0.33, W * 0.7, 1.6, length * 0.16))   # zadní kajuta
    wood = [cylinder(0.25, 0.16, 15.0, 8).translate(0, 1.2, length * 0.05)]   # stěžeň
    wood.append(cylinder(0.12, 0.12, W * 2.0, 6).rotate(0, 0, 90).translate(W, 14.0, length * 0.05))   # ráhno
    wood.append(cylinder(0.14, 0.07, 6.0, 6).rotate(-62, 0, 0).translate(0, 2.4, length * 0.48))   # čelen
    # vzdutá plachta (zakřivený čtyřúhelník mezi ráhnem a palubou)
    sail_rows, sail_cols = 8, 8
    SP = []
    for i in range(sail_rows):
        v = i / (sail_rows - 1)
        for j in range(sail_cols):
            u = j / (sail_cols - 1)
            x = (u - 0.5) * W * 1.9 * (1 - 0.1 * v)
            y = 13.8 - v * 10.5
            belly = 1.2 * math.sin(math.pi * u) * math.sin(math.pi * (0.15 + 0.7 * v))
            SP.append((x, y, length * 0.05 + 0.3 + belly))
    SP = np.array(SP, np.float32)
    sidx = np.arange(sail_rows * sail_cols).reshape(sail_rows, sail_cols)
    SI = []
    for i in range(sail_rows - 1):
        for j in range(sail_cols - 1):
            a0, b0, c0, d0 = sidx[i, j], sidx[i + 1, j], sidx[i + 1, j + 1], sidx[i, j + 1]
            SI += [[a0, b0, c0], [a0, c0, d0]]
    sail = Mesh(SP, SI)
    ropes = []
    top = np.array([0, 16.0, length * 0.05])
    for end in ([0, 2.0, length * 0.5], [0, 2.6, -length * 0.45], [W * 0.5, 1.4, -length * 0.1], [-W * 0.5, 1.4, -length * 0.1],
                [W * 0.5, 1.4, length * 0.2], [-W * 0.5, 1.4, length * 0.2]):
        e = np.array(end, np.float32)
        d = e - top
        L = float(np.linalg.norm(d))
        ax = d / L
        yaw = math.degrees(math.atan2(ax[0], ax[2]))
        pitch = math.degrees(math.acos(np.clip(ax[1], -1, 1)))
        ropes.append(cylinder(0.035, 0.035, L, 4).rotate(pitch, 0, 0).rotate(0, yaw, 0).translate(*top))
    flag = b(0, 16.6, length * 0.05 - 0.6, 0.05, 0.6, 1.2)
    return [(hull, PLANKS), (merge(*deck), PLANKS), (merge(*wood), WOOD), (sail, sail_mat), (merge(*ropes), ROPE),
            (flag, dict(sail_mat, double=True))]


def dock(length=60.0, width=5.0):
    """Molo z prken na kůlech (horní plocha y = 1,4 m nad hladinou, počátek u břehu, molo míří k +Z)."""
    planks, posts = [b(0, 1.25, length / 2, width, 0.3, length)], []
    for z in np.arange(1.0, length, 4.0):
        for x in (-width / 2 + 0.2, width / 2 - 0.2):
            posts.append(cylinder(0.22, 0.2, 7.5, 8).translate(x, -6.0, z))
    for z in np.arange(4.0, length, 12.0):   # úvazné sloupky
        posts.append(cylinder(0.25, 0.25, 1.0, 8).translate(width / 2 - 0.3, 1.4, z))
    return [(merge(*planks), PLANKS), (merge(*posts), WOOD)]


def city_wall(length=24.0, height=9.0, thick=3.2):
    """Úsek hradeb s cimbuřím (osa X, vnější líc +Z)."""
    stone = [b(0, height / 2 - 6.0, 0, length, height + 12.0, thick)]   # hradby až 12 m pod terén (svah útesu)
    for x in np.arange(-length / 2 + 0.9, length / 2, 2.2):
        stone.append(b(x, height + 0.8, thick / 2 - 0.35, 1.2, 1.6, 0.7))
        stone.append(b(x, height + 0.8, -thick / 2 + 0.35, 1.2, 1.6, 0.7))
    return [(merge(*stone), LIME)]


def wall_tower(seed):
    return spire_tower(7.0, 16.0, 9.0, seed, round_tower=True)


def stairs(length=150.0, rise=47.6, width=5.0):
    """Schodiště z přístavu na plošinu: šikmá rampa se stupni a zábradlím na opěrné zdi (počátek dole,
    stoupá k +Z)."""
    stone, steps = [], []
    n = int(length / 0.5)
    for i in range(n):
        z0 = i * length / n
        y = rise * (i + 1) / n
        steps.append(b(0, y - 0.12, z0 + length / n / 2, width, 0.24, length / n + 0.02))
    # opěrná zeď pod rampou (po úsecích)
    for k in range(0, int(length), 6):
        y = rise * (k + 3) / length
        stone.append(b(0, (y - 3.0) / 2, k + 3, width, y + 3.0, 6.05))
        stone.append(b(width / 2 + 0.25, y + 0.5, k + 3, 0.5, 1.0, 6.05))
    return [(merge(*stone), STONE), (merge(*steps), COBBLE)]


def floating_island(seed):
    """Létající ostrov (fantasy svět): převrácený skalní kužel s travnatým vrcholem a malou zříceninou."""
    rng = np.random.default_rng(seed)
    r = rng.uniform(26, 40)
    prof = [(0.4, -r * 1.6), (r * 0.35, -r * 1.1), (r * 0.75, -r * 0.45), (r, -0.6), (r * 0.98, 0.0)]
    rock = lathe(prof, 18, True, False)
    displace(rock, r * 0.12, 0.25, seed)
    top = cylinder(r * 0.97, r * 0.97, 0.6, 18).translate(0, -0.3, 0)
    displace(top, 0.3, 0.4, seed + 1)
    ruin = [b(r * 0.2, 2.0, 0, 3, 4, 3), cylinder(1.3, 1.2, 7, 10).translate(-r * 0.3, 0, r * 0.2)]
    grass = dict(name="grass top", texture=str(ASSETS / "Textures" / "terrain" / "pbr" / "trava_albedo.jpg"), uv_scale=4.0,
                 roughness=1.0)
    return [(rock, STONE), (top, grass), (merge(*ruin), LIME)]


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    textures()

    def save(name, parts):
        parts = [(m, mat) for m, mat in parts if len(m.P)]
        write_glb(str(OUT / f"{name}.glb"), parts, name=name)

    save("tower_a", spire_tower(8.0, 34.0, 20.0, 1))
    save("tower_b", spire_tower(6.5, 26.0, 15.0, 2))
    save("tower_c", spire_tower(10.0, 44.0, 24.0, 3))
    save("tower_round", spire_tower(7.0, 22.0, 13.0, 4, round_tower=True))
    save("dome_hall", dome_hall(5))
    for k, (w, d, f, roof) in enumerate([(9, 8, 3, SLATE), (8, 9, 4, CLAY), (10, 8, 3, CLAY), (7.5, 8, 4, SLATE)]):
        save(f"house_{k}", house(10 + k, w, d, f, roof))
    save("gate_valorie", gate())
    save("lamp_post", lamp_post())
    for k, sail in enumerate(SAILS):
        save(f"ship_{k}", ship(20 + k, sail, length=18.0 + 3 * k))
    save("dock", dock())
    save("city_wall", city_wall())
    save("wall_tower", wall_tower(30))
    save("harbor_stairs", stairs())
    for k in range(3):
        save(f"sky_island_{k}", floating_island(50 + k))


if __name__ == "__main__":
    generate()
    print("hotovo:", ", ".join(sorted(p.stem for p in OUT.glob("*.glb"))))
