#!/usr/bin/env python3
"""Modely pro profese, mounta a světové události Eryndoru (meshkit, PBR):

  rudné žíly (stříbro, zlato, diamant, mitril) – kámen se žílami a krystaly,
  byliny (5 druhů květin), nástroje (krumpáč, rybářský prut, splávek, stahovací nůž),
  sedlo pro koně, vchod do dolu (výdřeva, koleje, vozík, lucerna),
  křídla anděla (peří) a démona (blána), rohy, meteor (žhnoucí balvan) a kráter.

  python3 tools/eryndor_professions.py      -> Assets/Models/prof/*.glb

Předměty do ruky jsou orientované jako zbraně (úchyt handslot): rukojeť v počátku, násada po +Y.
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import (box, cone, crystal, cylinder, displace, fbm, lathe, merge, rounded_box, sphere,  # noqa: E402
                     write_glb)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets")
OUT = os.path.join(ROOT, "Models", "prof")
TEX = os.path.join(ROOT, "Textures")
NPC = os.path.join(TEX, "npc", "pbr")
VAL = os.path.join(TEX, "valoria", "pbr")


def pbr(folder, tex, tile, **extra):
    d = dict(texture=os.path.join(folder, f"{tex}_basecolor.jpg"), normal=os.path.join(folder, f"{tex}_normal.jpg"),
             orm=os.path.join(folder, f"{tex}_orm.jpg"), uv_scale=tile, roughness=1.0)
    d.update(extra)
    return d


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


STONE = dict(name="stone", roughness=0.92, texture=os.path.join(TEX, "nature", "skala.jpg"), uv_scale=1.1)
WOOD = pbr(VAL, "timber", 0.6, name="oak", color=(1.0, 0.9, 0.78))
STEEL = pbr(NPC, "steel", 0.25, name="forged steel", color=(0.8, 0.82, 0.86), metallic=1.0, roughness=0.6)
DARK_STEEL = pbr(NPC, "steel", 0.25, name="blackened steel", color=(0.3, 0.31, 0.34), metallic=1.0, roughness=0.8)
LEATHER = pbr(NPC, "leather", 0.15, name="saddle leather", color=(0.45, 0.24, 0.12))
BRASS = pbr(NPC, "gold", 0.2, name="brass", color=(0.95, 0.72, 0.38), metallic=1.0, roughness=0.55)
GOLD_METAL = dict(name="gold ore", color=(1.0, 0.68, 0.22), metallic=0.75, roughness=0.32)
CLOTH = pbr(NPC, "cloth", 0.2, name="saddle cloth", color=(0.42, 0.1, 0.09))


def rock_base(seed, w, h, d):
    r = sphere(1.0, 18, 12)
    r.scale(w / 2, h / 2, d / 2).translate(0, h * 0.32, 0)
    displace(r, 0.2 * min(w, h, d), 1.6, seed)
    r.apply(lambda P: np.where(P[:, 1:2] < 0, P * np.array([1, 0.25, 1]), P))
    r.invalidate()
    return r


def ore(name, seed, rock_tint, vein, kind):
    """Rudná žíla: balvan s tmavší horninou, kovové valouny / krystaly vyrůstající z povrchu."""
    w, h, d = 1.9, 1.25, 1.6
    r = rock_base(seed, w, h, d)
    base = np.asarray(rock_tint)
    r.paint(lambda P, N: base * (0.65 + 0.55 * fbm(P, 2.2, 3, seed)[:, None]) * (0.75 + 0.3 * np.clip(N[:, 1:2], 0, 1)))
    rng = np.random.default_rng(seed)
    bits = []
    P, N = r.P, r.normals()
    up = np.where(P[:, 1] > h * 0.15)[0]
    picks = rng.choice(up, 16 if kind == "metal" else 11, replace=False)
    for i in picks:
        p, n = P[i], N[i]
        if kind == "metal":
            s = 0.07 + 0.07 * rng.random()
            nug = sphere(s, 8, 6)
            displace(nug, s * 0.35, 9, int(rng.integers(999)))
            nug.scale(1.3, 0.75, 1.0).translate(*(p - n * s * 0.25))
            bits.append(nug)
        else:
            c = crystal(0.22 + 0.25 * rng.random(), 0.05 + 0.04 * rng.random(), 6, 0.3, int(rng.integers(999)))
            # krystal kolmo z povrchu (natočení podle normály)
            yaw = math.degrees(math.atan2(n[0], n[2]))
            pitch = math.degrees(math.acos(max(-1.0, min(1.0, n[1]))))
            c.rotate(pitch * 0.8, 0, 0).rotate(0, yaw, 0).translate(*(p - n * 0.03))
            bits.append(c)
    parts = [(r, STONE)]
    parts.append((merge(*bits), vein))
    write_glb(os.path.join(OUT, f"ore_{name}.glb"), parts, name=f"ore_{name}")


def flower(name, petal, center, petals=6, height=0.42, leaf=(0.2, 0.42, 0.12), glow=0.0, bell=False, heads=3, seed=1):
    rng = np.random.default_rng(seed)
    stems, leaves, petal_m, centers = [], [], [], []
    for k in range(heads):
        a = k / heads * 2 * math.pi + rng.random()
        off = (math.cos(a) * 0.07 * (k > 0), math.sin(a) * 0.07 * (k > 0))
        hh = height * (0.75 + 0.35 * rng.random())
        lean = rng.uniform(-12, 12)
        stems.append(cylinder(0.006, 0.004, hh, 6).rotate(lean, 0, rng.uniform(-10, 10)).translate(off[0], 0, off[1]))
        top = np.array([off[0] + math.sin(math.radians(lean)) * 0.0, hh * 0.98, off[1] + math.sin(math.radians(lean)) * hh * 0.2])
        if bell:   # zvonek (lilie): převrácený kalich
            b = lathe([(0.004, 0.0), (0.03, -0.02), (0.045, -0.06), (0.06, -0.085)], 10, False, False)
            b.translate(*top)
            petal_m.append(b)
        else:
            for p in range(petals):
                ang = p / petals * 360 + rng.uniform(-8, 8)
                pt = sphere(0.032, 8, 5).scale(0.55, 0.12, 1.0).translate(0, 0, 0.034).rotate(-18, ang, 0)
                pt.translate(*top)
                petal_m.append(pt)
        centers.append(sphere(0.016, 8, 6).scale(1, 0.6, 1).translate(top[0], top[1] + 0.004, top[2]))
    for k in range(5):   # přízemní listy (růžice)
        ang = k / 5 * 360 + rng.uniform(-20, 20)
        lf = sphere(0.05, 8, 4).scale(0.35, 0.06, 1.0).translate(0, 0.02, 0.05).rotate(-25, ang, 0)
        leaves.append(lf)
    st = merge(*stems, *leaves)
    L = np.asarray(leaf)
    st.paint(lambda P, N: L * (0.55 + 0.6 * np.clip(P[:, 1:2] / max(height, 1e-3), 0, 1)) * (0.85 + 0.3 * fbm(P, 40, 2, seed)[:, None]))
    pe = merge(*petal_m)
    Pc = np.asarray(petal)

    def petal_col(P, N):
        # od středu květu světleji ke špičce, jemné žilky, sytější okraj
        tops = np.array([c.P.mean(0) for c in centers])
        d = np.min(np.linalg.norm(P[:, None, :] - tops[None, :, :], axis=2), axis=1)[:, None]
        t = np.clip(d / 0.07, 0, 1)
        vein = 0.92 + 0.08 * np.sin(np.arctan2(P[:, 2:3] - 0, P[:, 0:1]) * 40)
        return Pc * (0.62 + 0.45 * t) * vein
    pe.paint(petal_col)
    green = dict(name="leaf", roughness=0.6, color=(1, 1, 1), double=True)
    pm = dict(name="petal", roughness=0.45, color=(1, 1, 1), double=True)
    if glow:
        pm.update(emissive=petal, emissive_strength=glow)
    write_glb(os.path.join(OUT, f"herb_{name}.glb"),
              [(st, green), (pe, pm),
               (merge(*centers), dict(name="pistil", roughness=0.6, color=center))], name=f"herb_{name}")


FLOWERS = [
    (("mirumilka", rgb("#f2efe6"), rgb("#f2c230")), dict(petals=9, height=0.36, seed=1)),            # heřmánek
    (("stribrolist", rgb("#b9c7d6"), rgb("#e6ecf2")), dict(petals=5, height=0.45, leaf=rgb("#8fa3a0"), seed=2)),
    (("krvavy_trn", rgb("#9e0f16"), rgb("#2a0a08")), dict(petals=6, height=0.55, leaf=rgb("#2d4a1c"), seed=3)),
    (("mesicni_lilie", rgb("#c9b8ff"), rgb("#fff4c0")), dict(height=0.6, glow=0.9, bell=True, seed=4)),
    (("ledovy_kvet", rgb("#9fe6ff"), rgb("#ffffff")), dict(petals=7, height=0.32, leaf=rgb("#6c8f99"), glow=1.4, seed=5)),
]


def pickaxe():
    shaft = cylinder(0.019, 0.016, 0.82, 12).translate(0, -0.18, 0)
    grip = cylinder(0.022, 0.022, 0.2, 12).translate(0, -0.18, 0)
    # hlava: zahnutý hrot na obě strany (oblouk z kvádrů), objímka
    segs = []
    for side in (-1, 1):
        for i in range(7):
            t = i / 6
            x = side * (0.03 + t * 0.26)
            y = 0.62 - (t * t) * 0.09
            w = 0.05 * (1 - t * 0.75) + 0.008
            seg = box(0.06, w, w * 0.8).rotate(0, 0, -side * (t * 28)).translate(x, y, 0)
            segs.append(seg)
    collar = box(0.07, 0.09, 0.06).translate(0, 0.62, 0)
    write_glb(os.path.join(OUT, "pickaxe.glb"), [(merge(shaft), WOOD), (merge(*segs, collar), DARK_STEEL),
                                                 (merge(grip), LEATHER)], name="pickaxe")


def fishing_rod():
    rod = lathe([(0.014, -0.25), (0.013, 0.1), (0.008, 0.8), (0.005, 1.5), (0.0025, 2.1)], 8, True, True)
    grip = cylinder(0.019, 0.017, 0.3, 10).translate(0, -0.25, 0)
    reel = cylinder(0.035, 0.035, 0.025, 14).rotate(0, 0, 90).translate(0.045, 0.05, 0)
    rings = [cylinder(0.008, 0.008, 0.004, 8).rotate(0, 0, 90).translate(0.012, y, 0) for y in (0.5, 0.95, 1.4, 1.85, 2.08)]
    write_glb(os.path.join(OUT, "fishing_rod.glb"),
              [(rod, dict(name="rod", color=rgb("#6b4a2a"), roughness=0.4)), (grip, LEATHER),
               (merge(reel, *rings), BRASS)], name="fishing_rod")
    top = sphere(0.035, 12, 8).translate(0, 0.02, 0)
    bottom = sphere(0.035, 12, 8).scale(1, 1.1, 1).translate(0, -0.015, 0)
    bottom.apply(lambda P: np.where(P[:, 1:2] > 0, P * np.array([1, 0, 1]), P))
    bottom.invalidate()
    top.apply(lambda P: np.where(P[:, 1:2] < 0.0, P * np.array([1, 0, 1]), P))
    top.invalidate()
    stick = cylinder(0.004, 0.003, 0.07, 6).translate(0, 0.04, 0)
    write_glb(os.path.join(OUT, "bobber.glb"),
              [(top, dict(name="bobber red", color=rgb("#c8231c"), roughness=0.35)),
               (bottom, dict(name="bobber white", color=rgb("#f2efe6"), roughness=0.35)),
               (stick, dict(name="bobber stick", color=rgb("#202020"), roughness=0.5))], name="bobber")


def saddle():
    # sedlo (osa koně = +Z): sedák s vysokou rozsochou vpředu a zadní rozsochou, podsedlová deka, třmeny
    seat = rounded_box(0.42, 0.08, 0.6, 0.04)
    seat.apply(lambda P: P + np.array([0, 1, 0]) * (0.06 * (P[:, 2:3] / 0.3) ** 2) - np.array([0, 1, 0]) * (0.05 * (P[:, 0:1] / 0.21) ** 2))
    seat.invalidate()
    pommel = rounded_box(0.22, 0.12, 0.08, 0.03).translate(0, 0.08, 0.27)
    cantle = rounded_box(0.36, 0.14, 0.07, 0.03).translate(0, 0.1, -0.29)
    flaps = [rounded_box(0.03, 0.4, 0.32, 0.02).rotate(0, 0, s * 18).translate(s * 0.25, -0.16, 0.0) for s in (-1, 1)]
    blanket = rounded_box(0.86, 0.025, 0.8, 0.012).translate(0, -0.05, -0.02)
    blanket.apply(lambda P: P - np.array([0, 1, 0]) * (np.abs(P[:, 0:1]) ** 1.6) * 0.75)
    blanket.invalidate()
    straps = [box(0.03, 0.5, 0.025).translate(s * 0.27, -0.42, 0.06) for s in (-1, 1)]
    stirrups = []
    for s in (-1, 1):
        st = lathe([(0.05, 0), (0.055, 0.01)], 12, False, False).rotate(90, 0, 0).translate(s * 0.29, -0.7, 0.06)
        stirrups.append(st)
        stirrups.append(box(0.1, 0.012, 0.05).translate(s * 0.29, -0.745, 0.06))
    write_glb(os.path.join(OUT, "saddle.glb"),
              [(merge(seat, pommel, cantle, *flaps, *straps), LEATHER), (blanket, CLOTH), (merge(*stirrups), STEEL)],
              name="saddle")


def mine_entrance():
    # výdřeva štoly (otvor 3,2 x 3,4 m) zapuštěná do svahu, tmavý tunel, koleje, vozík s rudou, lucerna
    posts = [cylinder(0.17, 0.15, 3.6, 10).translate(s * 1.75, 0, 0) for s in (-1, 1)]
    posts += [cylinder(0.16, 0.14, 3.6, 10).translate(s * 1.75, 0, -2.2) for s in (-1, 1)]
    beams = [cylinder(0.18, 0.18, 4.2, 10).rotate(0, 0, 90).translate(2.1, 3.55, z) for z in (0, -2.2)]
    planks = [box(4.0, 0.06, 0.28).translate(0, 3.72, -z * 0.3) for z in range(9)]
    braces = [box(0.12, 1.1, 0.12).rotate(0, 0, s * 40).translate(s * 1.45, 3.15, 0.05) for s in (-1, 1)]
    tunnel = box(3.4, 3.5, 6.0).translate(0, 1.75, -4.6)
    tunnel.I = tunnel.I[:, ::-1].copy()   # vnitřek (normály dovnitř)
    rails = [box(0.06, 0.08, 9.0).translate(s * 0.55, 0.04, 0.5) for s in (-1, 1)]
    ties = [box(1.5, 0.08, 0.2).translate(0, 0.0, 4.5 - k * 0.75) for k in range(13)]
    cart_body = box(1.0, 0.6, 1.3, bevel=0.03).translate(0, 0.62, 2.6)
    wheels = [cylinder(0.17, 0.17, 0.06, 12).rotate(0, 0, 90).translate(s * 0.55, 0.17, 2.6 + z) for s in (-1, 1) for z in (-0.4, 0.4)]
    load = [sphere(0.16 + 0.05 * (k % 3), 8, 6).translate(((k * 37) % 7 - 3) * 0.1, 0.98, 2.6 + ((k * 53) % 9 - 4) * 0.1) for k in range(9)]
    for b in load:
        displace(b, 0.05, 5, 3)
    lantern_frame = box(0.18, 0.26, 0.18).translate(1.55, 3.0, 0.3)
    lantern_hook = box(0.04, 0.04, 0.35).translate(1.62, 3.2, 0.15)
    glass = box(0.14, 0.2, 0.14).translate(1.55, 3.0, 0.3)
    write_glb(os.path.join(OUT, "mine_entrance.glb"), [
        (merge(*posts, *beams, *braces, *ties), WOOD), (merge(*planks), WOOD),
        (tunnel, dict(name="tunnel dark", color=(0.035, 0.03, 0.028), roughness=1.0)),
        (merge(*rails, *wheels, lantern_frame, lantern_hook), DARK_STEEL),
        (cart_body, WOOD), (merge(*load), STONE),
        (glass, dict(name="lantern glow", color=(1.0, 0.75, 0.4), emissive=(1.0, 0.62, 0.25), emissive_strength=3.0))],
        name="mine_entrance")


def wings(kind):
    """Křídla (uchycení u lopatek v počátku, rozpětí po ±X, vzad -Z, nahoru +Y)."""
    parts = []
    if kind == "angel":
        feathers = []
        for s in (-1, 1):
            for row, (n, length, y0) in enumerate(((14, 0.9, 0.0), (11, 0.6, 0.12), (8, 0.36, 0.22))):
                for k in range(n):
                    t = k / (n - 1)
                    ang = 15 + t * 95                               # vějíř od lopatky ven a dolů
                    rx = 0.15 + t * 1.25
                    base = np.array([s * rx, 0.55 + math.sin(t * math.pi) * 0.55 - t * 0.25 + y0, -0.12 - row * 0.03])
                    f = sphere(0.05, 8, 5).scale(0.65, 0.08, length / 0.1)
                    f.translate(0, 0, -length * 0.5)
                    f.rotate(-ang * 0.55 + 70, 0, 0).rotate(0, s * (60 + t * 35), 0)
                    f.translate(*base)
                    feathers.append(f)
        m = merge(*feathers)
        m.gradient(rgb("#e8e2d2"), rgb("#ffffff"))
        parts.append((m, dict(name="feathers", color=(1, 1, 1), roughness=0.6, double=True,
                              emissive=(1.0, 0.92, 0.7), emissive_strength=0.35)))
    else:
        bones_, membrane = [], []
        for s in (-1, 1):
            shoulder = np.array([s * 0.15, 0.6, -0.12])
            elbow = np.array([s * 0.75, 1.35, -0.35])
            tips = [np.array([s * 1.75, 1.65, -0.5]), np.array([s * 1.95, 0.9, -0.55]), np.array([s * 1.6, 0.2, -0.45]),
                    np.array([s * 0.95, -0.15, -0.35])]

            def bone_(a, b, r0, r1):
                d = b - a
                L = float(np.linalg.norm(d))
                c = cylinder(r0, r1, L, 8)
                pitch = math.degrees(math.acos(d[1] / L))
                yaw = math.degrees(math.atan2(d[0], d[2]))
                return c.rotate(pitch, 0, 0).rotate(0, yaw, 0).translate(*a)
            bones_.append(bone_(shoulder, elbow, 0.05, 0.04))
            for t in tips:
                bones_.append(bone_(elbow, t, 0.03, 0.008))
                bones_.append(cone(0.03, 0.12, 6).translate(*t))
            # blána: trojúhelníky mezi prsty, prověšené
            from meshkit import Mesh
            pts = [shoulder, elbow] + tips + [shoulder + np.array([0, -0.5, 0])]
            P, I = [], []
            ring = [elbow] + tips
            for k in range(len(ring) - 1):
                a, b = ring[k], ring[k + 1]
                mid = (a + b) / 2 + np.array([0, 0, 0.15])
                c0 = len(P)
                P += [shoulder.tolist(), a.tolist(), mid.tolist(), b.tolist()]
                I += [[c0, c0 + 1, c0 + 2], [c0, c0 + 2, c0 + 3]]
            last = len(P)
            P += [shoulder.tolist(), tips[-1].tolist(), pts[-1].tolist()]
            I += [[last, last + 1, last + 2]]
            m = Mesh(np.array(P, np.float32), np.array(I))
            m.flat = True
            membrane.append(m)
        parts.append((merge(*bones_), dict(name="wing bones", color=rgb("#1a0b0a"), roughness=0.6)))
        parts.append((merge(*membrane), dict(name="wing membrane", color=rgb("#4a0e0b"), roughness=0.7, double=True,
                                             emissive=(0.9, 0.12, 0.02), emissive_strength=0.25)))
    write_glb(os.path.join(OUT, f"wings_{kind}.glb"), parts, name=f"wings_{kind}")


def horns():
    hs = []
    for s in (-1, 1):
        segs = []
        for i in range(10):
            t = i / 9
            r = 0.06 * (1 - t) + 0.006
            p = np.array([s * (0.08 + t * 0.22), 0.05 + t * 0.2 + math.sin(t * 2.5) * 0.06, -t * 0.18])
            segs.append(sphere(r, 8, 6).translate(*p))
        hs += segs
    write_glb(os.path.join(OUT, "horns.glb"), [(merge(*hs), dict(name="horn", color=rgb("#1c1410"), roughness=0.45))], name="horns")


def halo():
    ring = lathe([(0.2, 0.0), (0.23, 0.01), (0.2, 0.02)], 32, False, False)
    write_glb(os.path.join(OUT, "halo.glb"), [(ring, dict(name="halo", color=(1.0, 0.9, 0.55), roughness=0.3, metallic=0.6,
                                                         emissive=(1.0, 0.85, 0.45), emissive_strength=4.0, double=True))], name="halo")


def meteor():
    r = sphere(1.0, 22, 16)
    displace(r, 0.22, 1.8, 77)
    r.paint(lambda P, N: np.array(rgb("#2a221e")) * (0.6 + 0.6 * fbm(P, 3.0, 3, 5)[:, None]))
    cracks = sphere(0.93, 22, 16)
    displace(cracks, 0.2, 1.8, 77)
    write_glb(os.path.join(OUT, "meteor.glb"), [
        (r, dict(STONE, name="meteor crust")),
        (cracks, dict(name="meteor glow", color=(1.0, 0.45, 0.12), emissive=(1.0, 0.38, 0.08), emissive_strength=6.0))],
        name="meteor")
    # kráter: prstenec vyvrženého kamení a spálené dno (průměr ~12 m)
    rim = lathe([(2.0, -0.4), (4.2, 0.2), (5.4, 0.9), (6.2, 0.5), (7.2, -0.3)], 40, False, False)
    displace(rim, 0.35, 0.6, 9)
    rim.paint(lambda P, N: np.array(rgb("#3b302a")) * (0.6 + 0.6 * fbm(P, 0.8, 3, 3)[:, None]))
    floor = lathe([(0.0, -0.35), (2.2, -0.38), (4.3, 0.15)], 40, False, False)
    floor.paint(lambda P, N: np.array(rgb("#1d1714")) * (0.6 + 0.5 * fbm(P, 1.2, 3, 4)[:, None]))
    write_glb(os.path.join(OUT, "crater.glb"), [(rim, dict(STONE, name="crater rim")),
                                                (floor, dict(name="scorched", color=(1, 1, 1), roughness=1.0))], name="crater")


def main():
    os.makedirs(OUT, exist_ok=True)
    ore("silver", 11, rgb("#5f5d5a"), dict(name="silver ore", color=(0.93, 0.92, 0.9), metallic=0.8, roughness=0.38), "metal")
    ore("gold", 12, rgb("#6a5a48"), GOLD_METAL, "metal")
    ore("diamond", 13, rgb("#4a4a52"), dict(name="diamond", color=(0.9, 0.97, 1.0), roughness=0.03,
                                             emissive=(0.6, 0.85, 1.0), emissive_strength=0.6), "crystal")
    ore("mithril", 14, rgb("#3f4650"), dict(name="mithril", color=(0.7, 0.9, 1.0), roughness=0.12, metallic=0.9,
                                             emissive=(0.35, 0.85, 1.0), emissive_strength=1.6), "crystal")
    for args, kw in FLOWERS:
        flower(*args, **kw)
    pickaxe()
    fishing_rod()
    saddle()
    mine_entrance()
    wings("angel")
    wings("demon")
    horns()
    halo()
    meteor()
    print("modely:", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
