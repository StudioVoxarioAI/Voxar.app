#!/usr/bin/env python3
"""Realistické zbraně a výbava NPC (místo kreslených KayKit): skutečné rozměry, PBR materiály z fotoskenů
Poly Haven (CC0 – ocel, mosaz, kůže, dřevo; tools/eryndor_npc_pbr.py a tools/valoria_pbr.py).

  python3 tools/eryndor_weapons.py      -> Assets/Models/gear/real/*.glb

Orientace jako předměty KayKit (úchyt handslot): rukojeť v počátku, čepel / topůrko po +Y, šířka záštity po X,
štít v rovině XY lícem k +Z, kuše pažbou po +Z, otevřená kniha stránkami k +Z.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np

from meshkit import Mesh, box, cone, cylinder, lathe, merge, sphere, write_glb

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "Assets"
OUT = ASSETS / "Models" / "gear" / "real"
NPC = ASSETS / "Textures" / "npc" / "pbr"
VAL = ASSETS / "Textures" / "valoria" / "pbr"


def pbr(folder, tex, tile, **extra):
    d = dict(texture=str(folder / f"{tex}_basecolor.jpg"), normal=str(folder / f"{tex}_normal.jpg"),
             orm=str(folder / f"{tex}_orm.jpg"), uv_scale=tile, roughness=1.0)
    d.update(extra)
    return d


STEEL = pbr(NPC, "steel", 0.25, name="forged steel", color=(0.86, 0.88, 0.92), metallic=1.0, roughness=0.55)
DARK_STEEL = pbr(NPC, "steel", 0.25, name="blackened steel", color=(0.32, 0.33, 0.36), metallic=1.0, roughness=0.8)
BRASS = pbr(NPC, "gold", 0.2, name="brass", color=(0.95, 0.72, 0.38), metallic=1.0, roughness=0.6)
LEATHER = pbr(NPC, "leather", 0.12, name="grip leather", color=(0.42, 0.26, 0.16))
WOOD = pbr(VAL, "timber", 0.6, name="oak", color=(1.0, 0.9, 0.78))
PLANKS = pbr(VAL, "planks", 0.5, name="shield planks", color=(1.0, 0.9, 0.78))
CLOTH = pbr(NPC, "cloth", 0.15, name="parchment", color=(0.93, 0.88, 0.76))
COVER = pbr(NPC, "leather", 0.2, name="book cover", color=(0.38, 0.12, 0.1))
CRYSTAL = dict(name="aether crystal", color=(0.45, 0.85, 1.0), roughness=0.08, metallic=0.0,
               emissive=(0.35, 0.8, 1.0), emissive_strength=2.2)
STRING = dict(name="bowstring", color=(0.75, 0.7, 0.6), roughness=0.9)


def loft(sections, flat=True, caps=True):
    """Těleso z průřezů [(y, [(x, z), …])] (stejný počet bodů, proti směru hodinových ručiček zhora)."""
    P, I = [], []
    n = len(sections[0][1])
    for y, pts in sections:
        for x, z in pts:
            P.append((x, y, z))
    for s in range(len(sections) - 1):
        a0, b0 = s * n, (s + 1) * n
        for k in range(n):
            k2 = (k + 1) % n
            I += [[a0 + k, b0 + k, a0 + k2], [a0 + k2, b0 + k, b0 + k2]]
    if caps:
        for s, flip in ((0, True), (len(sections) - 1, False)):
            c = len(P)
            y = sections[s][0]
            P.append((np.mean([p[0] for p in sections[s][1]]), y, np.mean([p[1] for p in sections[s][1]])))
            for k in range(n):
                tri = [c, s * n + k, s * n + (k + 1) % n]
                I.append(tri[::-1] if not flip else tri)
    m = Mesh(np.array(P, np.float32), np.array(I))
    m.flat = flat
    return m


def blade_section(w, t, fuller=0.0):
    """Průřez čepele: ostří po stranách (x = ±w), hřbet / žlábek uprostřed (z = ±t)."""
    f = t * (1.0 - fuller)
    return [(w, 0.0), (w * 0.55, t * 0.85), (w * 0.15, f), (-w * 0.15, f), (-w * 0.55, t * 0.85), (-w, 0.0),
            (-w * 0.55, -t * 0.85), (-w * 0.15, -f), (w * 0.15, -f), (w * 0.55, -t * 0.85)]


def blade(length, width, thick, y0=0.0, fuller=0.35, tip=0.16):
    secs = []
    for f in np.linspace(0, 1, 9):
        y = y0 + length * f
        taper = 1.0 - 0.28 * f
        if f > 1.0 - tip:   # hrot
            taper *= max(0.02, (1.0 - f) / tip)
        fu = fuller if f < 0.72 else fuller * max(0.0, (0.85 - f) / 0.13)
        secs.append((y, blade_section(width / 2 * taper, thick / 2 * max(taper, 0.3), fu)))
    return loft(secs)


def grip(length, r, y0=0.0, wraps=True):
    g = cylinder(r, r * 0.92, length, 14).translate(0, y0, 0)
    parts = [g]
    if wraps:   # vinutí koženého pásku
        for k in range(int(length / 0.022)):
            parts.append(cylinder(r * 1.08, r * 1.08, 0.008, 14).translate(0, y0 + 0.01 + k * 0.022, 0))
    return merge(*parts)


def sword(blade_len, blade_w, guard_w, grip_len, pommel_r):
    steel = [blade(blade_len, blade_w, 0.007, y0=0.06)]
    brass = [box(guard_w, 0.026, 0.034).translate(0, 0.047, 0),                       # záštita
             sphere(0.016, 10, 8).translate(guard_w / 2, 0.047, 0), sphere(0.016, 10, 8).translate(-guard_w / 2, 0.047, 0),
             cylinder(0.02, 0.026, 0.024, 12).translate(0, 0.03, 0),                    # objímka u čepele
             sphere(pommel_r, 14, 10).scale(1, 0.8, 0.75).translate(0, -grip_len - pommel_r * 0.6, 0)]
    leather = [grip(grip_len, 0.016, -grip_len + 0.02)]
    return [(merge(*steel), STEEL), (merge(*brass), BRASS), (merge(*leather), LEATHER)]


def dagger():
    steel = [blade(0.24, 0.034, 0.006, y0=0.035, fuller=0.25, tip=0.25)]
    brass = [box(0.085, 0.018, 0.026).translate(0, 0.026, 0), sphere(0.018, 12, 8).translate(0, -0.11, 0)]
    return [(merge(*steel), STEEL), (merge(*brass), BRASS), (merge(grip(0.095, 0.014, -0.095)), LEATHER)]


def extrude(poly, z0, z1, scale_back=1.0):
    """Hranol z mnohoúhelníku v rovině XY (x, y) mezi z0 a z1; zadní strana zmenšená (zúžení ostří)."""
    n = len(poly)
    P = [(x, y, z1) for x, y in poly] + [(x * scale_back, y * scale_back, z0) for x, y in poly]
    cx, cy = np.mean([p[0] for p in poly]), np.mean([p[1] for p in poly])
    P += [(cx, cy, z1), (cx * scale_back, cy * scale_back, z0)]
    I = []
    for k in range(n):
        k2 = (k + 1) % n
        I += [[2 * n, k, k2], [2 * n + 1, n + k2, n + k], [k, n + k, k2], [k2, n + k, n + k2]]
    m = Mesh(np.array(P, np.float32), np.array(I))
    # orientace: normály ven od středu
    P_ = m.P.astype(np.float64)
    c = P_.mean(0)
    I2 = []
    for t in m.I:
        nrm = np.cross(P_[t[1]] - P_[t[0]], P_[t[2]] - P_[t[0]])
        I2.append(t if np.dot(nrm, P_[t].mean(0) - c) >= 0 else t[::-1])
    m.I = np.array(I2)
    m.flat = True
    return m


def axe_2handed():
    wood = [cylinder(0.02, 0.018, 1.15, 12).translate(0, -0.35, 0)]
    # kovaná hlava: půlměsícové ostří na +X, týl na -X, objímka kolem topůrka
    edge = [(0.03, 0.06), (0.1, 0.09), (0.19, 0.16), (0.25, 0.13), (0.27, 0.0), (0.25, -0.13), (0.19, -0.16), (0.1, -0.08), (0.03, -0.05)]
    back = [(-0.03, 0.04), (-0.03, -0.04), (-0.09, -0.03), (-0.1, 0.0), (-0.09, 0.03)]
    head = [extrude([(x, y + 0.66) for x, y in edge], -0.013, 0.013),
            extrude([(x, y + 0.66) for x, y in back], -0.016, 0.016),
            cylinder(0.034, 0.034, 0.13, 14).translate(0, 0.595, 0)]
    metal = [cylinder(0.024, 0.024, 0.03, 12).translate(0, -0.36, 0)]
    return [(merge(*wood), WOOD), (merge(*head), DARK_STEEL), (merge(*metal, grip(0.3, 0.021, -0.3)), LEATHER)]


def staff():
    shaft = lathe([(0.016, -0.8), (0.019, -0.4), (0.02, 0.2), (0.022, 0.75), (0.03, 0.88), (0.02, 0.95)], 12, True, True)
    wood = [shaft]
    for k in range(3):   # kořenové prsty kolem krystalu
        a = k / 3 * 2 * math.pi
        wood.append(cone(0.012, 0.16, 6).rotate(0, 0, 25).rotate(0, math.degrees(a), 0).translate(math.cos(a) * 0.03, 0.92, math.sin(a) * 0.03))
    crystal = [cone(0.035, 0.11, 6).translate(0, 1.0, 0), cone(0.035, 0.05, 6).rotate(180, 0, 0).translate(0, 1.0, 0)]
    brass = [cylinder(0.025, 0.025, 0.04, 12).translate(0, 0.86, 0), cylinder(0.02, 0.016, 0.05, 10).translate(0, -0.84, 0)]
    return [(merge(*wood), WOOD), (merge(*crystal), CRYSTAL), (merge(*brass), BRASS)]


def shield_round():
    r = 0.31
    disc = lathe([(1e-4, 0.03), (r * 0.95, 0.012), (r, 0.0), (r, -0.012), (1e-4, -0.012)], 40, True, True)
    disc.rotate(-90, 0, 0)   # osa lathe (Y) -> Z: líc k +Z
    rim = lathe([(r - 0.012, 0.02), (r + 0.006, 0.014), (r + 0.006, -0.016), (r - 0.012, -0.016)], 40, False, True).rotate(-90, 0, 0)
    boss = lathe([(0.075, 0.0), (0.072, 0.02), (0.055, 0.05), (0.02, 0.07), (1e-4, 0.072)], 24, True, True).rotate(-90, 0, 0).translate(0, 0, 0.025)
    studs = [sphere(0.008, 8, 6).translate(math.cos(a) * (r - 0.03), math.sin(a) * (r - 0.03), 0.028) for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
    bands = [box(0.04, 2 * r * 0.96, 0.006).translate(0, 0, 0.032), box(2 * r * 0.96, 0.04, 0.006).translate(0, 0, 0.032)]
    handle = [box(0.03, 0.14, 0.03).translate(0, 0, -0.045)]
    return [(disc, PLANKS), (merge(rim, boss, *studs), DARK_STEEL), (merge(*bands), BRASS), (merge(*handle), LEATHER)]


def crossbow():
    stock = [box(0.05, 0.06, 0.62).translate(0, 0.0, 0.2), box(0.045, 0.1, 0.16).rotate(-18, 0, 0).translate(0, -0.06, -0.06)]
    prod = []
    for sgn in (1, -1):   # ramena luku (ocelové pero)
        for k in range(6):
            x0, x1 = sgn * k * 0.05, sgn * (k + 1) * 0.05
            z0, z1 = 0.46 - 0.004 * k * k, 0.46 - 0.004 * (k + 1) ** 2
            prod.append(box(0.052, 0.022, 0.018).rotate(0, math.degrees(math.atan2(z1 - z0, x1 - x0)) * -1, 0)
                        .translate((x0 + x1) / 2, 0.03, (z0 + z1) / 2))
    string = [box(0.6, 0.004, 0.004).translate(0, 0.03, 0.3)]
    metal = [box(0.07, 0.03, 0.05).translate(0, 0.03, 0.47), box(0.012, 0.03, 0.06).translate(0, -0.04, 0.1)]
    return [(merge(*stock), WOOD), (merge(*prod, *metal), DARK_STEEL), (merge(*string), STRING)]


def spellbook_open():
    cover = [box(0.2, 0.28, 0.012).rotate(0, 12, 0).translate(-0.1, 0, 0), box(0.2, 0.28, 0.012).rotate(0, -12, 0).translate(0.1, 0, 0)]
    pages = [box(0.185, 0.265, 0.02).rotate(0, 12, 0).translate(-0.095, 0, 0.014),
             box(0.185, 0.265, 0.02).rotate(0, -12, 0).translate(0.095, 0, 0.014)]
    brass = [box(0.025, 0.025, 0.014).translate(sx * 0.18, sy * 0.125, 0.0) for sx in (-1, 1) for sy in (-1, 1)]
    return [(merge(*cover), COVER), (merge(*pages), CLOTH), (merge(*brass), BRASS)]


def bow_long():
    """Dlouhý luk: osa Y = délka, tětiva po +X (k lučištníkovi), ramena se k tětivě ohýbají, konce zpětně zahnuté."""
    wood, leather, metal = [], [], []
    L = 0.78
    def cx(y):
        t = abs(y) / L
        return 0.15 * t * t - 0.03 * max(0.0, (t - 0.88) / 0.12) ** 2      # ohyb ramene, zpětný zákrut špičky
    ys = np.linspace(-L, L, 41)
    for y0, y1 in zip(ys[:-1], ys[1:]):
        x0, x1 = cx(y0), cx(y1)
        t = abs((y0 + y1) / 2) / L
        w = 0.024 * (1 - 0.55 * t) + 0.006
        th = 0.016 * (1 - 0.45 * t) + 0.005
        seg = math.hypot(x1 - x0, y1 - y0)
        ang = math.degrees(math.atan2(x1 - x0, y1 - y0))
        (leather if abs((y0 + y1) / 2) < 0.08 else wood).append(
            box(th, seg * 1.02, w).rotate(0, 0, -ang).translate((x0 + x1) / 2, (y0 + y1) / 2, 0))
    for sgn in (1, -1):   # rohové špičky
        metal.append(sphere(0.008, 8, 6).translate(cx(sgn * L), sgn * L, 0))
    string = [box(0.0025, 2 * L - 0.01, 0.0025).translate(cx(L) + 0.004, 0, 0)]
    return [(merge(*wood), WOOD), (merge(*leather), LEATHER), (merge(*metal), BRASS), (merge(*string), STRING)]


def quiver():
    """Kožený toulec se šípy (na zádech, kost spine_03): osa Y vzhůru, otvor nahoře."""
    leather = [cylinder(0.055, 0.045, 0.56, 16).translate(0, -0.3, 0), cylinder(0.06, 0.06, 0.03, 16).translate(0, 0.24, 0)]
    straps = [box(0.02, 0.3, 0.13).translate(0.0, -0.05, 0.0)]
    shafts, fletch, tips = [], [], []
    for k in range(9):
        a = k / 9 * 2 * math.pi
        x, z = math.cos(a) * 0.03, math.sin(a) * 0.03
        h = 0.28 + 0.02 * ((k * 7) % 3)
        shafts.append(cylinder(0.004, 0.004, h, 6).translate(x, 0.0, z))
        for f in range(3):   # opeření
            b = a + f * 2.09
            fletch.append(box(0.002, 0.08, 0.016).rotate(0, math.degrees(b), 0).translate(x + math.cos(b) * 0.008, h - 0.05, z + math.sin(b) * 0.008))
    return [(merge(*leather), dict(LEATHER, color=(0.36, 0.22, 0.13))), (merge(*straps), LEATHER), (merge(*shafts), WOOD),
            (merge(*fletch), dict(name="fletching", color=(0.75, 0.2, 0.15), roughness=0.9))]


def wand():
    return [(lathe([(0.008, -0.12), (0.011, 0.0), (0.009, 0.2), (0.006, 0.28)], 10, True, True), WOOD),
            (cone(0.012, 0.04, 6).translate(0, 0.28, 0), CRYSTAL)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    items = {
        "sword_1handed": sword(0.74, 0.048, 0.2, 0.13, 0.024),
        "sword_2handed": sword(1.02, 0.056, 0.3, 0.26, 0.03),
        "dagger": dagger(),
        "axe_2handed": axe_2handed(),
        "staff": staff(),
        "shield_round": shield_round(),
        "crossbow_1handed": crossbow(),
        "spellbook_open": spellbook_open(),
        "wand": wand(),
        "bow_long": bow_long(),
        "quiver": quiver(),
    }
    for name, parts in items.items():
        write_glb(str(OUT / f"{name}.glb"), parts, name=name)
    print("zbraně:", ", ".join(items))


if __name__ == "__main__":
    main()
