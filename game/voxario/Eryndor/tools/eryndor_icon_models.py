#!/usr/bin/env python3
"""3D modely předmětů pro fotorealistické ikony inventáře (PBR textury, srst enginu, lesk šupin).

Ikony se fotí přímo v enginu (samotest „ikony“ v main.lua, studio s tmavým pozadím a sluncem) a ořežou nástrojem
tools/eryndor_item_icons.py --from-shots. Každý model je vystředěný a zmenšený do koule o poloměru 0,5 m.

  python3 tools/eryndor_icon_models.py   -> Assets/Models/icons/*.glb
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import Mesh, box, crystal, cylinder, displace, fbm, lathe, merge, sphere, write_glb  # noqa: E402
from eryndor_professions import BRASS, LEATHER, STEEL, STONE, WOOD, rgb  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets")
OUT = os.path.join(ROOT, "Models", "icons")
PROF = os.path.join(ROOT, "Models", "prof")


def save(name, parts):
    """Vystředí a zmenší do koule r = 0,5 (všechny díly stejně)."""
    P = np.concatenate([m.P for m, _ in parts])
    lo, hi = P.min(0), P.max(0)
    c = (lo + hi) / 2
    r = float(np.linalg.norm(hi - lo)) / 2
    for m, _ in parts:
        m.translate(*(-c)).scale(0.5 / r)
    write_glb(os.path.join(OUT, name + ".glb"), parts, name=name)


# ------------------------------------------------------------------ ryby
def fish(name, back, belly, spots=None, stripes=None, length=1.0, depth=0.24, red_band=None, glow=None):
    prof = []
    for k in range(25):
        t = k / 24
        w = math.sin(math.pi * t ** 0.8) * (1 - 0.65 * t) + 0.04 * (t > 0.9)
        prof.append((max(w * depth, 0.004), t * length))
    body = lathe(prof, 28, False, False)
    body.rotate(0, 0, -90)
    body.apply(lambda P: P * np.array([-1, 1, 1]) + np.array([length, 0, 0]))   # hlava (tlustý konec) v +X
    body.I = body.I[:, ::-1].copy()
    body.apply(lambda P: P * np.array([1, 1, 0.42]))   # zploštělá z boku
    body.invalidate()
    B, Bl = np.asarray(back), np.asarray(belly)

    def col(P, N):
        y = P[:, 1:2] / depth
        t = np.clip(0.5 + y * 0.9, 0, 1)
        c = Bl * (1 - t) + B * t
        n = fbm(P * np.array([1, 1, 1]), 14, 3, 7)[:, None]
        c = c * (0.85 + 0.3 * n)
        if spots is not None:
            s = fbm(P, 38, 2, 3)[:, None]
            c = np.where((s > 0.62) & (y > -0.2), np.asarray(spots), c)
        if stripes is not None:
            band = (np.sin(P[:, 0:1] * 40) > 0.55) & (y > -0.3)
            c = np.where(band, c * np.asarray(stripes), c)
        # šupiny: jemná mřížka (tmavší okraje šupin), na břiše slabší
        u, v = P[:, 0:1] * 70, P[:, 1:2] * 70 + 0.5 * np.floor(P[:, 0:1] * 70)
        sc = 0.88 + 0.12 * np.clip(np.abs(np.sin(u * math.pi)) + np.abs(np.sin(v * math.pi)) - 0.6, 0, 1) * np.clip(t + 0.3, 0, 1)
        c = c * sc
        if red_band is not None:
            rb = np.exp(-(y * 3.0) ** 2) * 0.35
            c = c * (1 - rb) + np.asarray(red_band) * rb
        return c
    body.paint(col)
    tail = Mesh(np.array([[-0.0, 0, 0], [-0.24, 0.17, 0], [-0.2, 0, 0], [-0.24, -0.17, 0]], np.float32) + np.array([0.04, 0, 0]),
                np.array([[0, 1, 2], [0, 2, 3]]))
    def top(x):   # výška hřbetu v místě x (profil těla)
        t = 1 - x / length
        return math.sin(math.pi * max(t, 0) ** 0.8) * (1 - 0.65 * t) * depth
    fins = [Mesh(np.array([[0.62, top(0.62) * 0.8, 0], [0.42, top(0.42) + depth * 0.45, 0], [0.34, top(0.34) * 0.8, 0]], np.float32), np.array([[0, 1, 2]])),
            Mesh(np.array([[0.7, -top(0.7) * 0.7, 0.02], [0.56, -top(0.56) - depth * 0.3, 0.05], [0.5, -top(0.5) * 0.7, 0.02]], np.float32), np.array([[0, 1, 2]]))]
    tail.P[:, 1] *= depth / 0.24
    fin = merge(tail, *fins)
    fin.paint(lambda P, N: np.asarray(back) * (0.55 + 0.25 * (np.sin(np.arctan2(P[:, 1:2], P[:, 0:1] - 0.4) * 60) > 0)))
    eye = sphere(0.022, 12, 8).translate(length * 0.86, depth * 0.18, depth * 0.36)
    eye2 = sphere(0.022, 12, 8).translate(length * 0.86, depth * 0.18, -depth * 0.36)
    skin = dict(name="fish skin", color=(1, 1, 1), roughness=0.3, metallic=0.1)
    if glow:
        skin.update(emissive=glow, emissive_strength=0.6)
    save(name, [(body, skin), (fin, dict(name="fin", color=(1, 1, 1), roughness=0.5, double=True)),
                (merge(eye, eye2), dict(name="eye", color=(0.02, 0.02, 0.02), roughness=0.05))])


# ------------------------------------------------------------------ kůže (srst enginu)
def hide(name, base, dark, fur_len, light=None):
    rng = np.random.default_rng(len(name))
    # obrys stažené kůže: trup, čtyři nohy, krk
    outline = []
    for k in range(64):
        a = k / 64 * 2 * math.pi
        r = 0.42 + 0.06 * math.sin(a * 3 + 1)
        for la in (0.75, 2.35, 3.95, 5.5):   # nohy
            r += 0.22 * math.exp(-((math.atan2(math.sin(a - la), math.cos(a - la))) / 0.16) ** 2)
        r += 0.14 * math.exp(-((math.atan2(math.sin(a - 1.57), math.cos(a - 1.57))) / 0.22) ** 2)   # krk
        r *= 1 + 0.05 * rng.standard_normal()
        outline.append((math.cos(a) * r * 1.05, math.sin(a) * r * 1.25))
    P = [(0.0, 0.0, 0.0)] + [(x, 0.0, z) for x, z in outline]
    I = [[0, k + 2 if k < 63 else 1, k + 1] for k in range(64)]
    m = Mesh(np.array(P, np.float32), np.array(I))
    # zjemnit (rozdělit na prstence) pro zvlnění
    rings = []
    for j in range(1, 9):
        t = j / 8
        rings.append([(x * t, z * t) for x, z in outline])
    P = [(0.0, 0.0, 0.0)]
    for ring in rings:
        P += [(x, 0.0, z) for x, z in ring]
    I = []
    for k in range(64):
        I.append([0, 1 + (k + 1) % 64, 1 + k])
    for j in range(len(rings) - 1):
        a0, b0 = 1 + j * 64, 1 + (j + 1) * 64
        for k in range(64):
            k2 = (k + 1) % 64
            I += [[a0 + k, a0 + k2, b0 + k], [a0 + k2, b0 + k2, b0 + k]]
    m = Mesh(np.array(P, np.float32), np.array(I))
    m.apply(lambda Q: Q + np.array([0, 1, 0]) * (0.05 * np.sin(Q[:, 0:1] * 7) * np.cos(Q[:, 2:3] * 5) - 0.12 * (Q[:, 0:1] ** 2 + Q[:, 2:3] ** 2)))
    m.invalidate()
    B, D = np.asarray(base), np.asarray(dark)

    def col(Q, N):
        n = fbm(Q, 6, 4, 11)[:, None]
        spine = np.exp(-(Q[:, 0:1] / 0.12) ** 2)
        c = B * (0.8 + 0.4 * n)
        c = c * (1 - 0.6 * spine) + D * 0.6 * spine
        if light is not None:
            edge = np.clip(np.hypot(Q[:, 0:1], Q[:, 2:3]) / 0.6, 0, 1) ** 3
            c = c * (1 - edge * 0.5) + np.asarray(light) * edge * 0.5
        return c
    m.paint(col)
    m.C[:, 3] = 1.0
    under = m.copy()
    under.I = under.I[:, ::-1].copy()
    under.translate(0, -0.006, 0)
    under.color(rgb("#c9b08a"))
    save(name, [(m, dict(name=f"Coat#fur:{fur_len}:420:0.35:0.6", color=(1, 1, 1), roughness=0.85)),
                (under, dict(LEATHER, name="hide back", color=(0.95, 0.85, 0.7)))])


def dragon_scale():
    scales = []
    for row in range(4):
        for k in range(5 - row % 2):
            s = sphere(0.12, 16, 8).scale(1.0, 0.18, 1.25)
            s.apply(lambda P: np.where(P[:, 2:3] < -0.02, P * np.array([0.6, 1, 1]), P))
            s.rotate(-12, 0, 0).translate((k - 2) * 0.2 + (row % 2) * 0.1, row * 0.035, -row * 0.17)
            scales.append(s)
    m = merge(*scales)
    m.paint(lambda P, N: np.array(rgb("#7cc8f0")) * (0.7 + 0.5 * fbm(P, 10, 3, 4)[:, None]))
    save("scale_dragon", [(m, dict(name="dragon scale", color=(1, 1, 1), roughness=0.15, metallic=0.6,
                                   emissive=(0.25, 0.6, 1.0), emissive_strength=0.4))])


# ------------------------------------------------------------------ ostatní
def horseshoe():
    pts = []
    for k in range(40):
        a = math.radians(-35 + k / 39 * 250)
        pts.append((math.cos(a) * 0.36, math.sin(a) * 0.4))
    segs = []
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        L = math.hypot(x1 - x0, z1 - z0)
        b = box(0.11, 0.05, L * 1.15).rotate(0, math.degrees(math.atan2(x1 - x0, z1 - z0)), 0).translate((x0 + x1) / 2, 0, (z0 + z1) / 2)
        segs.append(b)
    nails = [cylinder(0.018, 0.018, 0.06, 8).translate(pts[i][0], -0.005, pts[i][1]) for i in (6, 12, 27, 33)]
    save("horse", [(merge(*segs), dict(STEEL, name="horseshoe iron", color=(0.55, 0.55, 0.58), roughness=0.75)),
                   (merge(*nails), BRASS)])


def feather():
    shaft = lathe([(0.012, 0.0), (0.008, 0.6), (0.002, 1.2)], 8, True, True)
    vanes = []
    P, I = [], []
    for k in range(40):
        t = k / 39
        y = 0.12 + t * 1.06
        w = math.sin(math.pi * min(1, t * 1.1)) * 0.17 * (1 - 0.3 * t) + 0.01
        P += [(-w, y - 0.04 * w, 0.0), (0.0, y, 0.004), (w * 0.8, y - 0.06 * w, 0.0)]
    for k in range(39):
        a = k * 3
        b = a + 3
        I += [[a, b, a + 1], [b, b + 1, a + 1], [a + 1, b + 1, a + 2], [b + 1, b + 2, a + 2]]
    v = Mesh(np.array(P, np.float32), np.array(I))
    v.apply(lambda Q: Q + np.array([0, 0, 1]) * (0.04 * np.abs(Q[:, 0:1]) * 3))
    v.invalidate()
    v.paint(lambda Q, N: np.array([1.0, 0.97, 0.9]) * (0.85 + 0.2 * np.sin(Q[:, 1:2] * 90 + Q[:, 0:1] * 40)) )
    vanes.append(v)
    save("feather_angel", [(shaft, dict(name="quill", color=(0.95, 0.9, 0.75), roughness=0.4)),
                           (merge(*vanes), dict(name="vane", color=(1, 1, 1), roughness=0.7, double=True,
                                                emissive=(1.0, 0.85, 0.5), emissive_strength=0.25))])


def horn():
    segs = []
    for i in range(30):
        t = i / 29
        r = 0.16 * (1 - t) ** 0.9 + 0.008
        p = np.array([math.sin(t * 2.2) * 0.45, t * 0.9, (1 - math.cos(t * 2.2)) * 0.25])
        s = sphere(r, 18, 10).translate(*p)
        segs.append(s)
    m = merge(*segs)
    m.paint(lambda P, N: np.array(rgb("#2a1c14")) * (0.6 + 0.6 * fbm(P, 18, 3, 2)[:, None]) *
            (1 + 0.25 * np.sin(P[:, 1:2] * 60)[:, :1]))
    save("horn_demon", [(m, dict(name="horn", color=(1, 1, 1), roughness=0.35))])


def gem(name, color, glow, metallic=0.0):
    c = crystal(1.0, 0.42, 8, 0.45, 3)
    bottom = crystal(0.5, 0.42, 8, 1.0, 3).rotate(180, 0, 0)
    m = merge(c, bottom)
    m.flat = True
    save(name, [(m, dict(name=name, color=color, roughness=0.04, metallic=metallic, emissive=glow, emissive_strength=0.5))])


def ore_chunk(name, rock_tint, vein, kind, seed):
    r = sphere(0.5, 22, 14)
    displace(r, 0.12, 2.2, seed)
    r.paint(lambda P, N: np.asarray(rock_tint) * (0.6 + 0.6 * fbm(P, 4, 3, seed)[:, None]))
    rng = np.random.default_rng(seed)
    P, N = r.P, r.normals()
    bits = []
    for i in rng.choice(len(P), 22 if kind == "metal" else 16, replace=False):
        if P[i][1] < -0.15:
            continue
        p, n = P[i], N[i]
        if kind == "metal":
            s = 0.08 + 0.07 * rng.random()
            g = sphere(s, 10, 7)
            displace(g, s * 0.3, 14, int(rng.integers(99)))
            g.scale(1.3, 0.7, 1).translate(*(p - n * s * 0.2))
        else:
            g = crystal(0.18 + 0.2 * rng.random(), 0.05, 6, 0.3, int(rng.integers(99)))
            yaw = math.degrees(math.atan2(n[0], n[2]))
            pitch = math.degrees(math.acos(max(-1.0, min(1.0, n[1]))))
            g.rotate(pitch * 0.8, 0, 0).rotate(0, yaw, 0).translate(*(p - n * 0.02))
        bits.append(g)
    save(name, [(r, dict(STONE, name="ore rock")), (merge(*bits), vein)])


def from_generators():
    """Nástroje a byliny z eryndor_professions / eryndor_weapons – vystředěné kopie pro focení ikon."""
    import eryndor_professions as ep
    import eryndor_weapons as ew
    captured = {}
    real = ep.write_glb
    ep.write_glb = lambda path, parts, **kw: captured.__setitem__(os.path.basename(path)[:-4], parts)
    ep.pickaxe()
    ep.fishing_rod()
    for args, kw in ep.FLOWERS:
        ep.flower(*args, **kw)
    ep.write_glb = real
    captured["knife"] = ew.dagger()
    for k, parts in captured.items():
        if k in ("bobber",):
            continue
        save({"fishing_rod": "rod"}.get(k, k), parts)


def main():
    os.makedirs(OUT, exist_ok=True)
    from_generators()
    fish("fish_pstruh", (0.32, 0.36, 0.22), (0.92, 0.9, 0.82), spots=(0.12, 0.1, 0.08), red_band=(0.95, 0.45, 0.45))
    fish("fish_okoun", (0.32, 0.42, 0.14), (0.95, 0.85, 0.6), stripes=(0.45, 0.45, 0.4), depth=0.28)
    fish("fish_losos", (0.38, 0.45, 0.5), (0.95, 0.92, 0.9), spots=(0.15, 0.15, 0.18), depth=0.22)
    fish("fish_stika", (0.35, 0.52, 0.58), (0.92, 0.95, 0.97), spots=(0.85, 0.92, 0.95), depth=0.16, length=1.2)
    fish("fish_ohnivy", (0.65, 0.12, 0.03), (1.0, 0.6, 0.2), stripes=(0.4, 0.15, 0.1), depth=0.1, length=1.3, glow=(1.0, 0.35, 0.05))
    fish("fish_kapr", (0.55, 0.5, 0.75), (0.95, 0.92, 1.0), depth=0.32, glow=(0.5, 0.45, 1.0))
    hide("hide_wolf", (0.42, 0.39, 0.35), (0.12, 0.11, 0.1), 0.035, light=(0.75, 0.72, 0.66))
    hide("hide_boar", (0.25, 0.2, 0.15), (0.08, 0.06, 0.05), 0.03)
    hide("hide_stag", (0.5, 0.26, 0.11), (0.25, 0.12, 0.05), 0.016, light=(0.8, 0.7, 0.55))
    hide("hide_bear", (0.22, 0.12, 0.06), (0.1, 0.05, 0.03), 0.05)
    dragon_scale()
    horseshoe()
    feather()
    horn()
    gem("meteor_shard", (1.0, 0.45, 0.15), (1.0, 0.35, 0.05))
    ore_chunk("ore_silver", rgb("#5f5d5a"), dict(name="silver", color=(0.93, 0.92, 0.9), metallic=0.8, roughness=0.38), "metal", 21)
    ore_chunk("ore_gold", rgb("#6a5a48"), dict(name="gold", color=(1.0, 0.68, 0.22), metallic=0.75, roughness=0.32), "metal", 22)
    ore_chunk("ore_diamond", rgb("#4a4a52"), dict(name="diamond", color=(0.92, 0.97, 1.0), roughness=0.02,
                                                     emissive=(0.6, 0.85, 1.0), emissive_strength=0.5), "crystal", 23)
    ore_chunk("ore_mithril", rgb("#3f4650"), dict(name="mithril", color=(0.7, 0.92, 1.0), roughness=0.1, metallic=0.9,
                                                     emissive=(0.35, 0.85, 1.0), emissive_strength=1.2), "crystal", 24)
    print("modely ikon:", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()


def studio():
    """Fotostudio pro ikony: uzavřený box 8 m (normály dovnitř) s tmavým cykloramatem a softboxy (svítící panely
    pro odlesky kovů a krystalů). Model se vloží doprostřed, kamera kouká po -Z."""
    room = box(8.0, 8.0, 8.0).translate(0, 0, 0)
    room.I = room.I[:, ::-1].copy()
    room.paint(lambda P, N: np.array([0.05, 0.048, 0.045]) * (0.7 + 0.6 * np.clip((P[:, 1:2] + 4) / 8, 0, 1)))
    soft = box(2.4, 0.05, 1.6).translate(0.8, 3.2, 1.6)
    soft2 = box(0.05, 1.8, 2.4).translate(-3.2, 0.8, 0.8)
    write_glb(os.path.join(OUT, "studio.glb"), [
        (room, dict(name="cyclorama", color=(1, 1, 1), roughness=0.95)),
        (merge(soft, soft2), dict(name="softbox", color=(1, 1, 1), emissive=(1.0, 0.97, 0.92), emissive_strength=2.5))],
        name="studio")


if __name__ == "__main__" and "--studio" in sys.argv:
    studio()


# ------------------------------------------------------------------ výbava (zbraně a zbroj) pro ikony
def gear_icons():
    """Zbraně (eryndor_weapons) a kusy zbroje Armor Forge (klidová póza člověka) jako vystředěné statické modely
    Models/icons/g_<předmět>.glb – zbroj sdílí textury Models/armor/tex (odkaz ../armor/tex)."""
    import json as _json
    import struct as _struct
    import eryndor_weapons as ew
    W = {"g_sword_1h": ew.sword(0.74, 0.048, 0.2, 0.13, 0.024), "g_axe_1h": ew.axe_1handed(), "g_mace_1h": ew.mace_1handed(),
         "g_dagger": ew.dagger(), "g_sword_2h": ew.sword(1.02, 0.056, 0.3, 0.26, 0.03), "g_axe_2h": ew.axe_2handed(),
         "g_hammer_2h": ew.hammer_2handed(), "g_staff": ew.staff(), "g_wand": ew.wand(), "g_bow": ew.bow_long(),
         "g_crossbow": ew.crossbow(), "g_shield_round": ew.shield_round(), "g_shield_kite": ew.shield_kite(), "g_spellbook": ew.spellbook_open()}
    for k, parts in W.items():
        save(k, parts)
    armor = os.path.join(ROOT, "Models", "armor")
    for st in ("leather", "plate"):
        for slot in ("head", "shoulders", "chest", "hands", "legs", "feet"):
            src = os.path.join(armor, f"{st}_{slot}_clovek.glb")
            if not os.path.exists(src):
                continue
            b = open(src, "rb").read()
            jl = _struct.unpack("<I", b[12:16])[0]
            j = _json.loads(b[20:20 + jl])
            bin_ = bytearray(b[20 + jl + 8:])
            def acc(i, comps):
                a = j["accessors"][i]
                v = j["bufferViews"][a["bufferView"]]
                o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
                dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}[a["componentType"]]
                return np.frombuffer(bytes(bin_[o:o + a["count"] * comps * np.dtype(dt).itemsize]), dtype=dt).reshape(a["count"], comps).astype(np.float64 if dt == np.float32 else np.int64)
            prims = j["meshes"][0]["primitives"]
            data = []
            for p in prims:
                P = acc(p["attributes"]["POSITION"], 3)
                F = acc(p["indices"], 1).reshape(-1, 3)
                data.append((P, F))
            allP = np.concatenate([d[0] for d in data])
            # rukavice a boty: jen pravý kus (postava kouká po +Z, pravá strana je −X)
            keep_right = slot in ("hands", "feet")
            sel = (allP[:, 0] < 0) if keep_right else np.ones(len(allP), bool)
            lo, hi = allP[sel].min(0), allP[sel].max(0)
            c = (lo + hi) / 2
            r = float(np.linalg.norm(hi - lo)) / 2
            out = {"asset": {"version": "2.0"}, "nodes": [{"mesh": 0}], "meshes": [{"primitives": []}], "materials": j["materials"],
                   "images": [{"uri": "../armor/" + im["uri"]} for im in j["images"]], "textures": j["textures"], "samplers": j["samplers"],
                   "accessors": [], "bufferViews": [], "buffers": [], "scenes": [{"nodes": [0]}], "scene": 0}
            ob = bytearray()
            def add(arr, typ, comp, target=None, mm=False):
                while len(ob) % 4:
                    ob.extend(b"\0")
                off = len(ob)
                raw = np.ascontiguousarray(arr).tobytes()
                ob.extend(raw)
                out["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(raw), **({"target": target} if target else {})})
                a = {"bufferView": len(out["bufferViews"]) - 1, "componentType": comp, "count": int(len(arr)), "type": typ}
                if mm:
                    a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
                out["accessors"].append(a)
                return len(out["accessors"]) - 1
            for p, (P, F) in zip(prims, data):
                if keep_right:
                    ok = (P[F][:, :, 0] < 0).all(axis=1)
                    F = F[ok]
                if not len(F):
                    continue
                Q = ((P - c) * (0.5 / r)).astype(np.float32)
                N = acc(p["attributes"]["NORMAL"], 3).astype(np.float32)
                UV = acc(p["attributes"]["TEXCOORD_0"], 2).astype(np.float32)
                out["meshes"][0]["primitives"].append({"attributes": {"POSITION": add(Q, "VEC3", 5126, 34962, True), "NORMAL": add(N, "VEC3", 5126, 34962),
                                                                      "TEXCOORD_0": add(UV, "VEC2", 5126, 34962)},
                                                       "indices": add(F.reshape(-1).astype(np.uint32), "SCALAR", 5125, 34963), "material": p["material"]})
            while len(ob) % 4:
                ob.extend(b"\0")
            out["buffers"] = [{"byteLength": len(ob)}]
            js = _json.dumps(out).encode()
            js += b" " * ((4 - len(js) % 4) % 4)
            with open(os.path.join(OUT, f"g_{st}_{slot}.glb"), "wb") as f:
                f.write(_struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(ob)))
                f.write(_struct.pack("<I4s", len(js), b"JSON")); f.write(js)
                f.write(_struct.pack("<I4s", len(ob), b"BIN\0")); f.write(ob)
    print("ikony výbavy: hotovo")


if __name__ == "__main__" and "--gear" in sys.argv:
    gear_icons()
