"""Krajina a stavby Eryndoru (vlastní tvorba, generováno kódem).

  python3 tools/eryndor_nature.py      -> Assets/Models/nature/*.glb, Assets/Models/build/*.glb

Styl: stylizované, ručně malované MMO – výrazné siluety, měkké přechody barev, zastínění namalované
do barev vrcholů, svítící magické prvky. Podle lore: Sylvaria (bílý mramor, obří živé stromy,
bioluminiscenční lesy, křišťálová jezera), Aethelgard (železo, kouř, ozubená kola), Aetherium (modré
krystaly), Umbrium (fialové krystaly Stínové nákazy).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (Mesh, box, capsule, cone, crystal, cylinder, displace, double_sided, fbm, lathe, merge,  # noqa: E402
                     plane, rounded_box, sphere, write_glb)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Models")
NAT = os.path.join(ROOT, "nature")
BLD = os.path.join(ROOT, "build")

# textury z listu přírodních textur (tools/eryndor_textures.sh), vloží se do modelů; uv_scale = m na dlaždici
TEX = os.path.join(ROOT, "..", "Textures", "nature")
BARK = dict(name="bark", roughness=0.95, texture=os.path.join(TEX, "kura.jpg"), uv_scale=0.9)
LEAF = dict(name="leaf", roughness=0.8, double=True, texture=os.path.join(TEX, "listi.jpg"), uv_scale=1.3)
STONE = dict(name="stone", roughness=0.9, texture=os.path.join(TEX, "skala.jpg"), uv_scale=1.1)
GIANT_BARK = dict(BARK, texture=os.path.join(TEX, "kura_bila.jpg"), uv_scale=2.2)
GIANT_LEAF = dict(LEAF, texture=os.path.join(TEX, "listi_sylvarie.jpg"), uv_scale=2.6)
MARBLE = dict(name="marble", roughness=0.45)
GOLD = dict(name="gold", roughness=0.35, metallic=0.85)
IRON = dict(name="iron", roughness=0.55, metallic=0.7)


def glow(rgb, strength=4.0, name="glow"):
    return dict(name=name, roughness=0.3, emissive=rgb, emissive_strength=strength)


def rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


# ------------------------------------------------------------------ stromy
def trunk(height, r0, r1, seg=10, bend=(0.0, 0.0), twist=0.0, roots=0, seed=0):
    rings = 10
    prof = []
    for k in range(rings + 1):
        t = k / rings
        r = r0 * (1 - t) + r1 * t
        if roots:
            r *= 1 + 0.9 * max(0.0, 0.25 - t) / 0.25   # rozšířený kořenový náběh
        prof.append((r, height * t))
    m = lathe(prof, seg, True, True)
    rng = np.random.default_rng(seed)

    def deform(P):
        t = np.clip(P[:, 1] / height, 0, 1)
        a = twist * t
        x = P[:, 0] * np.cos(a) - P[:, 2] * np.sin(a)
        z = P[:, 0] * np.sin(a) + P[:, 2] * np.cos(a)
        x = x + bend[0] * t * t * height
        z = z + bend[1] * t * t * height
        P = np.stack([x, P[:, 1], z], 1)
        if roots:   # kořeny: laloky u země
            ang = np.arctan2(P[:, 2], P[:, 0])
            lobe = np.maximum(0, np.cos(ang * roots + rng.random() * 6)) ** 3 * np.clip(1 - t / 0.2, 0, 1)
            P[:, 0] *= 1 + lobe * 0.9
            P[:, 2] *= 1 + lobe * 0.9
        return P
    m.apply(deform)
    displace(m, r0 * 0.08, 3.0 / max(r0, 0.1), seed)
    return m


def canopy_blob(r, seed, squash=0.75):
    s = sphere(r, 14, 9)
    s.scale(1.0, squash, 1.0)
    displace(s, r * 0.22, 1.6 / r, seed)
    return s


def paint_leaves(m, dark, light, glow_tint=None, seed=0):
    N = m.normals()
    up = np.clip(N[:, 1] * 0.5 + 0.5, 0, 1)
    n = fbm(m.P, 1.3, 3, seed)
    t = np.clip(up * 0.75 + n * 0.45 - 0.1, 0, 1)[:, None]
    c = np.asarray(dark) * (1 - t) + np.asarray(light) * t
    if glow_tint is not None:   # Sylvarie: tyrkysový nádech na spodcích
        under = np.clip(-N[:, 1], 0, 1)[:, None]
        c = c * (1 - under * 0.5) + np.asarray(glow_tint) * under * 0.5
    m.C[:, :3] = c
    return m


def paint_bark(m, dark, light, seed=0):
    n = fbm(m.P * np.array([3, 0.6, 3]), 2.5, 3, seed)
    t = np.clip(n * 1.3 - 0.15, 0, 1)[:, None]
    m.C[:, :3] = np.asarray(dark) * (1 - t) + np.asarray(light) * t
    m.shade_ao(0.35)
    return m


def giant_tree():
    """Obří živý strom Sylvarie (~28 m): zkroucený bělavý kmen, kořeny, široká koruna, svítící plody."""
    t = trunk(16, 2.4, 1.0, 16, (0.05, -0.03), 1.4, roots=6, seed=3)
    paint_bark(t, rgb("#6b6a72"), rgb("#c9c3b8"), 3)
    branches, blobs = [], []
    rng = np.random.default_rng(7)
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.random() * 0.4
        b = trunk(9, 0.75, 0.25, 8, (0, 0), 0.5, seed=10 + k)
        b.rotate(0, 0, -58 - rng.random() * 12).rotate(0, math.degrees(a), 0).translate(0, 11 + rng.random() * 3.5, 0)
        paint_bark(b, rgb("#6b6a72"), rgb("#c9c3b8"), 10 + k)
        branches.append(b)
        tip = np.array([math.cos(a), 0, -math.sin(a)]) * 8.5
        for j in range(2):
            bl = canopy_blob(4.6 + rng.random() * 1.6, 20 + k * 3 + j)
            bl.translate(tip[0] + rng.normal() * 1.5, 18 + rng.random() * 3, tip[2] + rng.normal() * 1.5)
            blobs.append(bl)
    for j in range(3):
        bl = canopy_blob(6.0, 60 + j)
        bl.translate(rng.normal() * 2, 22 + j * 2.2, rng.normal() * 2)
        blobs.append(bl)
    leaves = merge(*blobs)
    paint_leaves(leaves, rgb("#1f5f4a"), rgb("#7fcf8a"), rgb("#3fd6c8"), 5)
    # svítící plody / lucerny pod korunou
    fruits = []
    for k in range(26):
        a = rng.random() * 2 * math.pi
        d = 4 + rng.random() * 8
        f = sphere(0.32, 8, 6).translate(math.cos(a) * d, 14.5 + rng.random() * 4, math.sin(a) * d)
        fruits.append(f)
    fr = merge(*fruits).color(rgb("#9ff7ff"))
    write_glb(os.path.join(NAT, "giant_tree.glb"),
              [(merge(t, *branches), GIANT_BARK), (leaves, GIANT_LEAF), (fr, glow(rgb("#5ee6ff"), 6.0))], name="GiantTree")


def broadleaf(seed, out):
    rng = np.random.default_rng(seed)
    h = 5 + rng.random() * 1.5
    t = trunk(h, 0.32, 0.16, 8, (rng.normal() * 0.05, rng.normal() * 0.05), 0.6, roots=4, seed=seed)
    paint_bark(t, rgb("#4a3626"), rgb("#8a6a4a"), seed)
    blobs = []
    for j in range(5):
        bl = canopy_blob(1.9 + rng.random() * 0.7, seed * 10 + j)
        bl.translate(rng.normal() * 1.1, h + 0.4 + rng.random() * 1.6, rng.normal() * 1.1)
        blobs.append(bl)
    leaves = merge(*blobs)
    paint_leaves(leaves, rgb("#2c5a22"), rgb("#9ccc4a"), None, seed)
    write_glb(out, [(t, BARK), (leaves, LEAF)], name="Tree")


def pine(seed, out):
    rng = np.random.default_rng(seed)
    h = 9 + rng.random() * 3
    t = trunk(h * 0.85, 0.3, 0.1, 8, (0, 0), 0.2, roots=3, seed=seed)
    paint_bark(t, rgb("#3b2a20"), rgb("#6e5040"), seed)
    tiers = []
    for k in range(5):
        y = h * (0.25 + 0.15 * k)
        r = (2.6 - 0.45 * k) * (0.9 + 0.2 * rng.random())
        c = lathe([(r, 0), (r * 0.55, 0.5), (0.02, h * 0.24)], 9, True, False)
        displace(c, 0.15, 1.5, seed + k)
        c.translate(0, y, 0)
        tiers.append(c)
    leaves = merge(*tiers)
    paint_leaves(leaves, rgb("#173a2c"), rgb("#4e8a5a"), None, seed)
    write_glb(out, [(t, BARK), (leaves, LEAF)], name="Pine")


def glow_mushroom(seed, out, big=False):
    rng = np.random.default_rng(seed)
    parts = []
    caps = []
    n = 1 if big else 3 + int(rng.random() * 3)
    for k in range(n):
        s = (2.2 if big else 0.35 + rng.random() * 0.35)
        x, z = (0, 0) if big or k == 0 else (rng.normal() * 0.3, rng.normal() * 0.3)
        stalk = lathe([(0.12 * s, 0), (0.09 * s, 0.6 * s), (0.11 * s, 1.0 * s)], 8)
        stalk.rotate(rng.normal() * 6, 0, rng.normal() * 6).translate(x, 0, z)
        stalk.gradient(rgb("#5a5d7a"), rgb("#d8e6ff"))
        cap = lathe([(0.02 * s, 1.35 * s), (0.42 * s, 1.18 * s), (0.55 * s, 0.98 * s), (0.42 * s, 0.93 * s), (0.08 * s, 0.98 * s)], 12, False, False)
        cap.translate(x, 0, z)
        parts.append(stalk)
        caps.append(cap)
    st = merge(*parts)
    cp = merge(*caps)
    cp.paint(lambda P, N: np.where((N[:, 1:2] > 0), np.array(rgb("#2a3a8a")) * 0.9 + 0.1 * fbm(P, 6, 2, seed)[:, None],
                                   np.array(rgb("#58f2ff"))))
    # svítící tečky na kloboucích
    dots = []
    for cap in caps:
        top = cap.P[cap.P[:, 1] > cap.P[:, 1].max() - 0.25 * (cap.P[:, 1].max() - cap.P[:, 1].min())]
        for i in rng.choice(len(top), size=min(6, len(top)), replace=False):
            dots.append(sphere(0.035 * (5 if big else 1), 6, 4).translate(*top[i]))
    write_glb(out, [(st, dict(name="stalk", roughness=0.7)), (cp, dict(name="cap", roughness=0.5,
               emissive=rgb("#1a7f9a"), emissive_strength=1.2)), (merge(*dots).color((0.8, 1, 1)), glow(rgb("#7ff6ff"), 8))],
              name="Mushroom")


def tuft(seed, out, color_low, color_high, blades=9, h=0.6, w=0.06, curl=0.25):
    rng = np.random.default_rng(seed)
    ms = []
    for k in range(blades):
        p = plane(w, h, 1, 4)
        p.rotate(90, 0, 0)     # svisle (XZ -> XY)
        p.translate(0, h / 2, 0)
        def bendf(P, c=curl * (0.6 + rng.random())):
            t = np.clip(P[:, 1] / h, 0, 1)
            P = P.copy()
            P[:, 2] += c * t * t * h
            P[:, 0] *= 1 - t * 0.85
            return P
        p.apply(bendf)
        p.rotate(0, rng.random() * 360, rng.normal() * 8).translate(rng.normal() * 0.08, 0, rng.normal() * 0.08)
        p.gradient(color_low, color_high)
        ms.append(double_sided(p))
    write_glb(out, [(merge(*ms), dict(name="grass", roughness=0.85, double=True))], name="Tuft")


def fern(seed, out):
    rng = np.random.default_rng(seed)
    fronds = []
    for k in range(7):
        p = plane(0.32, 1.1, 2, 6)
        def shape(P):
            t = np.clip((P[:, 2] + 0.55) / 1.1, 0, 1)
            P = P.copy()
            P[:, 0] *= np.sin(t * math.pi) * 1.2
            P[:, 1] += 0.6 * np.sin(t * math.pi * 0.8) - 0.35 * t * t
            return P
        p.apply(shape).translate(0, 0, 0.55)
        p.rotate(-25 - rng.random() * 15, k / 7 * 360 + rng.random() * 20, 0)
        p.gradient(rgb("#1c4a34"), rgb("#4fbf86"), axis=1)
        fronds.append(double_sided(p))
    write_glb(out, [(merge(*fronds), dict(name="fern", roughness=0.8, double=True))], name="Fern")


def crystal_cluster(seed, out, color, glow_color, n=7, size=1.0, strength=3.5):
    rng = np.random.default_rng(seed)
    cs = []
    for k in range(n):
        h = size * (0.6 + rng.random() * 1.4) * (1.6 if k == 0 else 1.0)
        c = crystal(h, size * (0.12 + rng.random() * 0.1), 6, 0.3, seed + k)
        c.rotate(rng.normal() * 22 if k else 0, rng.random() * 360, rng.normal() * 22 if k else 0)
        c.translate(rng.normal() * size * 0.25, -0.05, rng.normal() * size * 0.25)
        cs.append(c)
    m = merge(*cs)
    m.gradient(np.asarray(color) * 0.45, np.asarray(color) * 1.2)
    base = rounded_box(size * 0.9, size * 0.3, size * 0.8, size * 0.12).translate(0, 0, 0)
    displace(base, 0.06 * size, 3, seed)
    base.gradient(rgb("#3a3a44"), rgb("#77747a"))
    write_glb(out, [(base, STONE), (m, dict(name="crystal", roughness=0.15, emissive=glow_color, emissive_strength=strength))],
              name="Crystals")


def rock(seed, out, w=2.0, h=1.2, d=1.6, tint=None):
    r = sphere(1.0, 14, 9)
    r.scale(w / 2, h / 2, d / 2).translate(0, h * 0.35, 0)
    displace(r, 0.18 * min(w, h, d), 1.4, seed)
    r.apply(lambda P: np.where(P[:, 1:2] < 0, P * np.array([1, 0.3, 1]), P))
    r.invalidate()
    base = np.asarray(tint or rgb("#7a7670"))
    r.paint(lambda P, N: base * (0.7 + 0.5 * fbm(P, 1.8, 3, seed)[:, None]) * (0.75 + 0.35 * np.clip(N[:, 1:2], 0, 1))
            + np.array(rgb("#3d5a2a")) * np.clip(N[:, 1:2] - 0.65, 0, 1) * 1.2)   # mech nahoře
    write_glb(out, [(r, STONE)], name="Rock")


# ------------------------------------------------------------------ stavby
def marble_column(out, h=6.0, broken=False):
    seg = 16
    prof = [(0.62, 0), (0.62, 0.25), (0.5, 0.35), (0.45, 0.4)]
    top = h * (0.55 if broken else 1.0)
    prof += [(0.43, top - 0.45), (0.5, top - 0.35), (0.66, top - 0.15), (0.66, top)]
    c = lathe(prof, seg, True, True)
    # kanelury
    def flutes(P):
        ang = np.arctan2(P[:, 2], P[:, 0])
        rr = np.hypot(P[:, 0], P[:, 2])
        mid = (P[:, 1] > 0.45) & (P[:, 1] < top - 0.45)
        k = 1 - 0.06 * (np.cos(ang * 16) * 0.5 + 0.5) * mid
        return np.stack([P[:, 0] * k, P[:, 1], P[:, 2] * k], 1)
    c.apply(flutes)
    if broken:
        displace(c, 0.06, 3, 11)
    c.paint(lambda P, N: np.array(rgb("#ece6dc")) * (0.85 + 0.2 * fbm(P, 2.2, 3, 4)[:, None]) * (0.8 + 0.2 * np.clip(N[:, 1:2] + 0.5, 0, 1)))
    c.shade_ao(0.3)
    gold = cylinder(0.5, 0.5, 0.06, 16).translate(0, top - 0.42, 0).color(rgb("#e0b04a")) if not broken else None
    parts = [(c, MARBLE)]
    if gold is not None:
        parts.append((gold, GOLD))
    write_glb(out, parts, name="Column")


def marble_arch(out):
    pieces = []
    for x in (-2.6, 2.6):
        p = lathe([(0.55, 0), (0.48, 0.3), (0.42, 4.2), (0.55, 4.5)], 12).translate(x, 0, 0)
        pieces.append(p)
    # oblouk z klínů
    for k in range(13):
        a = math.pi * k / 12
        b = box(0.75, 0.7, 0.8).rotate(0, 0, math.degrees(a) - 90).translate(-2.6 * math.cos(a), 4.6 + 2.6 * math.sin(a), 0)
        pieces.append(b)
    m = merge(*pieces)
    m.paint(lambda P, N: np.array(rgb("#efe9df")) * (0.82 + 0.25 * fbm(P, 1.8, 3, 9)[:, None]))
    m.shade_ao(0.3)
    # zlatá runa a světlo Aetheria uprostřed oblouku
    rune = crystal(0.9, 0.22, 4, 0.5, 3).rotate(0, 0, 180).translate(0, 7.6, 0).color(rgb("#8fe8ff"))
    trim = box(5.9, 0.12, 0.85).translate(0, 4.45, 0).color(rgb("#d9a840"))
    write_glb(out, [(m, MARBLE), (trim, GOLD), (rune, glow(rgb("#62d8ff"), 5))], name="Arch")


def shrine(out):
    """Sylvarská svatyně: kruhová mramorová plošina, šest sloupů, kopule z živých větví, krystal Aetheria."""
    parts = []
    base = lathe([(6.4, 0), (6.4, 0.4), (6.0, 0.45), (6.0, 0.8), (5.6, 0.85), (5.6, 1.1)], 32)
    base.paint(lambda P, N: np.array(rgb("#e9e2d6")) * (0.8 + 0.25 * fbm(P, 0.9, 3, 2)[:, None]))
    parts.append((base, MARBLE))
    cols = []
    for k in range(6):
        a = k / 6 * 2 * math.pi
        c = lathe([(0.45, 0), (0.36, 0.3), (0.32, 5.2), (0.48, 5.5)], 12).translate(4.7 * math.cos(a), 1.1, 4.7 * math.sin(a))
        cols.append(c)
    cm = merge(*cols)
    cm.paint(lambda P, N: np.array(rgb("#f1ece3")) * (0.85 + 0.2 * fbm(P, 2.0, 3, 5)[:, None]))
    parts.append((cm, MARBLE))
    # kopule z větví (živé dřevo)
    vines = []
    for k in range(6):
        a = k / 6 * 2 * math.pi
        for s in (-1, 1):
            pts = []
            for j in range(9):
                t = j / 8
                ang = a + s * t * 0.55
                r = 4.7 * (1 - t) + 0.25 * t
                y = 6.6 + math.sin(t * math.pi * 0.5) * 3.2
                pts.append((r * math.cos(ang), y, r * math.sin(ang)))
            for p0, p1 in zip(pts[:-1], pts[1:]):
                v = np.array(p1) - np.array(p0)
                L = np.linalg.norm(v)
                seg = cylinder(0.16, 0.13, L, 6, False)
                # natočit podél v
                yaw = math.degrees(math.atan2(v[0], v[2]))
                pitch = math.degrees(math.acos(np.clip(v[1] / L, -1, 1)))
                seg.rotate(pitch, 0, 0).rotate(0, yaw, 0).translate(*p0)
                vines.append(seg)
    vm = merge(*vines)
    paint_bark(vm, rgb("#5b6a5a"), rgb("#b7c4a4"), 4)
    parts.append((vm, BARK))
    leaves = []
    rng = np.random.default_rng(5)
    for k in range(16):
        a = rng.random() * 2 * math.pi
        bl = canopy_blob(1.1 + rng.random() * 0.5, 80 + k).translate(3.2 * math.cos(a), 8.0 + rng.random() * 1.8, 3.2 * math.sin(a))
        leaves.append(bl)
    lm = merge(*leaves)
    paint_leaves(lm, rgb("#215a48"), rgb("#86d79a"), rgb("#4be0d0"), 8)
    parts.append((lm, LEAF))
    # oltář s krystalem Aetheria
    altar = lathe([(1.1, 1.1), (0.8, 1.5), (0.6, 2.3), (1.0, 2.5)], 16)
    altar.paint(lambda P, N: np.array(rgb("#e4dccf")) * (0.85 + 0.2 * fbm(P, 3, 2, 1)[:, None]))
    parts.append((altar, MARBLE))
    cr = merge(*[crystal(1.6 - k * 0.3, 0.3 - k * 0.04, 6, 0.35, k).rotate(k * 14, k * 70, 0).translate(0, 2.4, 0) for k in range(4)])
    cr.gradient(rgb("#2f7fd8"), rgb("#bff4ff"))
    parts.append((cr, dict(name="aether", roughness=0.1, emissive=rgb("#3fc8ff"), emissive_strength=6)))
    gold = merge(*[cylinder(0.5, 0.5, 0.08, 12).translate(4.7 * math.cos(k / 6 * 2 * math.pi), 6.4, 4.7 * math.sin(k / 6 * 2 * math.pi))
                   for k in range(6)]).color(rgb("#e0b04a"))
    parts.append((gold, GOLD))
    write_glb(out, parts, name="Shrine")


def gear(r, teeth, thick):
    prof = []
    m = cylinder(r * 0.82, r * 0.82, thick, teeth * 2)
    ts = [box(r * 0.25, thick, r * 0.3).translate(0, thick / 2, 0).translate(r * 0.88, 0, 0).rotate(0, 360 * k / teeth, 0)
          for k in range(teeth)]
    hub = cylinder(r * 0.25, r * 0.25, thick * 1.4, 10).translate(0, -thick * 0.2, 0)
    return merge(m, *ts, hub)


def watchtower(out):
    """Strážní věž Aethelgardu: kamenný sokl, železná konstrukce, nýty, ozubená kola, komín, rudý prapor."""
    parts = []
    socle = lathe([(3.4, 0), (3.2, 3.5), (2.9, 4.0)], 8, True, True)
    socle.flat = True
    socle.paint(lambda P, N: np.array(rgb("#5b544e")) * (0.75 + 0.4 * fbm(P, 1.1, 3, 7)[:, None]))
    socle.shade_ao(0.4)
    parts.append((socle, STONE))
    # železné patro
    body = lathe([(2.7, 4.0), (2.5, 9.0), (3.3, 9.3), (3.3, 10.0)], 8, False, True)
    body.flat = True
    body.paint(lambda P, N: np.array(rgb("#3d3f45")) * (0.8 + 0.3 * fbm(P, 2.5, 2, 3)[:, None]))
    rivets = []
    for k in range(8):
        for y in (4.5, 6.3, 8.1):
            a = (k + 0.5) / 8 * 2 * math.pi
            rivets.append(sphere(0.12, 6, 4).translate(2.62 * math.cos(a), y, 2.62 * math.sin(a)))
    parts.append((merge(body, *rivets), IRON))
    # střecha s cimbuřím a komínem
    crenel = []
    for k in range(8):
        a = k / 8 * 2 * math.pi
        crenel.append(box(1.1, 0.9, 0.5).rotate(0, -math.degrees(a) + 90, 0).translate(3.05 * math.cos(a), 10.45, 3.05 * math.sin(a)))
    cm = merge(*crenel).color(rgb("#4a4c52"))
    cm.flat = True
    parts.append((cm, IRON))
    chimney = cylinder(0.45, 0.35, 3.2, 8).translate(1.4, 10.0, -1.0).color(rgb("#2c2c30"))
    parts.append((chimney, IRON))
    # ozubená kola na boku (mosaz)
    g1 = gear(1.4, 14, 0.25).rotate(90, 0, 0).translate(0, 7.0, 2.75)
    g2 = gear(0.85, 10, 0.25).rotate(90, 0, 0).translate(1.85, 8.35, 2.7)
    gm = merge(g1, g2).color(rgb("#b88a3a"))
    parts.append((gm, dict(name="brass", roughness=0.4, metallic=0.9)))
    # krystalová pec (Aetherium jako palivo) – žhnoucí okna
    windows = merge(*[box(0.6, 1.0, 0.1).rotate(0, -math.degrees(k / 4 * 2 * math.pi + math.pi / 8) + 90, 0)
                      .translate(2.55 * math.cos(k / 4 * 2 * math.pi + math.pi / 8), 8.4, 2.55 * math.sin(k / 4 * 2 * math.pi + math.pi / 8))
                      for k in range(4)]).color(rgb("#ffb050"))
    parts.append((windows, glow(rgb("#ff8a2a"), 5, "furnace")))
    # prapor Řádu Ocelového slunce (rudá s bronzovým kruhem)
    pole = cylinder(0.06, 0.06, 3.0, 6).translate(-1.6, 10.0, 1.2).color(rgb("#2a2a2a"))
    flag = plane(1.4, 1.0, 4, 3).rotate(90, 0, 0)
    flag.apply(lambda P: P + np.stack([np.zeros(len(P)), np.zeros(len(P)), 0.12 * np.sin(P[:, 0] * 3)], 1))
    flag.translate(-0.9, 12.4, 1.2).color(rgb("#8a1e1a"))
    sun = cylinder(0.28, 0.28, 0.02, 12).rotate(90, 0, 0).translate(-0.9, 12.4, 1.22).color(rgb("#d9a24a"))
    parts.append((pole, IRON))
    parts.append((double_sided(flag), dict(name="cloth", roughness=0.9, double=True)))
    parts.append((sun, GOLD))
    write_glb(out, parts, name="Watchtower")


def palisade(out):
    """Železná palisáda Aethelgardu (4 m dlouhý díl)."""
    ps = []
    for k in range(8):
        x = -1.75 + k * 0.5
        ps.append(cylinder(0.12, 0.1, 2.6, 6).translate(x, 0, 0))
        ps.append(cone(0.13, 0.35, 6).translate(x, 2.6, 0))
    bands = [box(4.0, 0.14, 0.1).translate(0, y, 0.1) for y in (0.6, 2.0)]
    m = merge(*ps, *bands)
    m.paint(lambda P, N: np.array(rgb("#45464c")) * (0.7 + 0.45 * fbm(P, 3, 2, 2)[:, None]))
    write_glb(out, [(m, IRON)], name="Palisade")


def crate(out):
    b = box(1.0, 0.8, 0.8, (0, 0.4, 0))
    b.paint(lambda P, N: np.array(rgb("#7a5634")) * (0.8 + 0.3 * fbm(P, 6, 2, 1)[:, None]))
    straps = merge(box(1.04, 0.08, 0.84, (0, 0.15, 0)), box(1.04, 0.08, 0.84, (0, 0.65, 0))).color(rgb("#3b3c40"))
    straps.flat = True
    write_glb(out, [(b, dict(name="wood", roughness=0.9)), (straps, IRON)], name="Crate")


def rift(out):
    """Stínová trhlina: kruh rozeklaných černých krystalů, fialové jádro a plovoucí úlomky."""
    rng = np.random.default_rng(21)
    shards = []
    for k in range(14):
        a = k / 14 * 2 * math.pi
        h = 2.0 + rng.random() * 3.5
        c = crystal(h, 0.35 + rng.random() * 0.25, 5, 0.4, k)
        c.rotate(rng.normal() * 10 - 18, 0, 0).rotate(0, -math.degrees(a) + 90, 0).translate(4.2 * math.cos(a), -0.3, 4.2 * math.sin(a))
        shards.append(c)
    sm = merge(*shards)
    sm.gradient(rgb("#0c0612"), rgb("#4a1d6a"))
    core = sphere(1.0, 16, 10).scale(1.6, 2.6, 0.25).translate(0, 3.0, 0)
    core.paint(lambda P, N: np.array(rgb("#c46bff")) * (0.6 + 0.6 * fbm(P, 2.5, 3, 3)[:, None]))
    ring = lathe([(2.0, -0.15), (2.15, 0.0), (2.0, 0.15)], 24, False, False).rotate(90, 0, 0).translate(0, 3.0, 0).color(rgb("#e6b0ff"))
    floats = merge(*[crystal(0.6, 0.12, 4, 0.5, 40 + k).rotate(rng.random() * 360, rng.random() * 360, 0)
                     .translate(rng.normal() * 2.2, 2.0 + rng.random() * 4, rng.normal() * 2.2) for k in range(10)])
    floats.gradient(rgb("#1a0b26"), rgb("#7a3aa8"))
    ground = lathe([(5.5, 0.0), (3.5, 0.05), (0.01, 0.08)], 24)
    ground.paint(lambda P, N: np.array(rgb("#1c1024")) * (0.6 + 0.6 * fbm(P, 1.2, 3, 4)[:, None]))
    write_glb(out, [(merge(sm, floats), dict(name="voidcrystal", roughness=0.2, emissive=rgb("#5a1a8a"), emissive_strength=1.5)),
                    (core, glow(rgb("#b44dff"), 7, "rift")), (ring, glow(rgb("#f0c0ff"), 9, "ring")),
                    (ground, dict(name="blight", roughness=0.95, emissive=rgb("#2a0a3a"), emissive_strength=1.0))], name="Rift")


def lamp_post(out):
    """Sylvarská lucerna: mramorový sloupek, zlatý háček, svítící krystal."""
    post = lathe([(0.18, 0), (0.12, 0.2), (0.1, 2.6), (0.16, 2.75)], 10)
    post.paint(lambda P, N: np.array(rgb("#ece6dc")) * (0.85 + 0.2 * fbm(P, 3, 2, 3)[:, None]))
    hook = merge(box(0.06, 0.06, 0.6, (0, 2.85, 0.25)), box(0.06, 0.3, 0.06, (0, 2.7, 0.52))).color(rgb("#d6a443"))
    lamp = crystal(0.45, 0.12, 6, 0.45, 2).rotate(180, 0, 0).translate(0, 2.55, 0.52).color(rgb("#c8f8ff"))
    write_glb(out, [(post, MARBLE), (hook, GOLD), (lamp, glow(rgb("#6fe2ff"), 7))], name="Lamp")


def main():
    os.makedirs(NAT, exist_ok=True)
    os.makedirs(BLD, exist_ok=True)
    # stromy (tree_*, pine_*, giant_tree) generuje fotorealisticky tools/eryndor_foliage.py – zde se nepřepisují
    glow_mushroom(1, os.path.join(NAT, "mushrooms.glb"))
    glow_mushroom(2, os.path.join(NAT, "mushroom_big.glb"), big=True)
    tuft(3, os.path.join(NAT, "grass.glb"), rgb("#2e5a22"), rgb("#9fd25a"))
    tuft(4, os.path.join(NAT, "grass_teal.glb"), rgb("#1d4a40"), rgb("#6fd8b4"), 8, 0.7)
    tuft(5, os.path.join(NAT, "grass_ash.glb"), rgb("#3a3430"), rgb("#8c7a62"), 7, 0.45, 0.05, 0.15)
    fern(6, os.path.join(NAT, "fern.glb"))
    crystal_cluster(7, os.path.join(NAT, "aetherium.glb"), rgb("#58c8ff"), rgb("#2aa8ff"), 7, 1.0, 4.0)
    crystal_cluster(8, os.path.join(NAT, "aetherium_big.glb"), rgb("#7ad8ff"), rgb("#3ab8ff"), 9, 2.6, 4.5)
    crystal_cluster(9, os.path.join(NAT, "umbrium.glb"), rgb("#9a4dff"), rgb("#7a22d8"), 6, 1.0, 3.0)
    for k in range(3):
        rock(300 + k, os.path.join(NAT, f"rock_{k}.glb"), 2.0 + k * 0.8, 1.2 + k * 0.4, 1.6 + k * 0.6)
    rock(310, os.path.join(NAT, "rock_dark.glb"), 3.0, 1.8, 2.4, rgb("#4a4440"))
    marble_column(os.path.join(BLD, "column.glb"))
    marble_column(os.path.join(BLD, "column_broken.glb"), broken=True)
    marble_arch(os.path.join(BLD, "arch.glb"))
    shrine(os.path.join(BLD, "shrine.glb"))
    watchtower(os.path.join(BLD, "watchtower.glb"))
    palisade(os.path.join(BLD, "palisade.glb"))
    crate(os.path.join(BLD, "crate.glb"))
    rift(os.path.join(BLD, "rift.glb"))
    lamp_post(os.path.join(BLD, "lamp.glb"))
    for d in (NAT, BLD):
        for f in sorted(os.listdir(d)):
            print(f"{os.path.basename(d)}/{f}: {os.path.getsize(os.path.join(d, f)) // 1024} KB")


if __name__ == "__main__":
    main()
