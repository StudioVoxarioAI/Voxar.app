#!/usr/bin/env python3
"""Obloukový most Valoria – hlavní ostrov (viadukt přes Azure Ocean).

  python3 tools/valoria_skybridge.py

Navazuje na jižní konec Mostu hrdinů (x = 3000, z = 2670), stáčí se obloukem na západ, přechází moře na
kamenných pilířích s klenbami a stoupá na útes hlavního ostrova (údolí Serpentine leží za ním na západ).

Výstup:
  Assets/Models/valoria/skybridge.glb          model mostu (počátek = začátek mostovky, horní plocha y = 0)
  Assets/Scripts/eryndor/skybridge_data.lua    osa mostu po 10 m (x, z, výška mostovky vůči začátku) pro hru

Výšky terénu se čtou z výškové mapy (Assets/Terrain/aethelgard_height.png); hra posadí most na skutečnou
výšku Mostu hrdinů a konec mostovky se zanoří pod terén útesu (žádný schod ani mezera na konci).
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

from meshkit import Mesh, box, merge, write_glb
import valoria_assets as va

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Assets"
OUT = ASSETS / "Models" / "valoria"
DATA = ASSETS / "Scripts" / "eryndor" / "skybridge_data.lua"
SIZE, BASE, RANGE = 8192.0, -80.0, 760.0
SEA_Y = 0.0

START = np.array([2713.5, 2400.0])     # západní líc brány VALORIE na okraji plošiny města (50 m)
LANDING = np.array([2007.0, 2329.0])   # temeno útesu hlavního ostrova
GATE = (2718.0, 2400.0, 9.0, 12.0)     # střed brány, hloubka a šířka průjezdu (valoria.lua)
DECK_WIDTH = 14.0                      # mostovka (Most hrdinů má 20 m – rozšíření u napojení)
CORE_WIDTH = 11.0                      # klenby a pilíře pod mostovkou
DECK_THICK = 1.1
PARAPET_H, PARAPET_T = 1.15, 0.55
PIER_SPACING = 34.0
EXTEND = 14.0                          # mostovka pokračuje za LANDING pod terén
CHUNKS = 1
MAX_GRADE = 0.11
STEP = 2.0                             # vzorkování osy (m)

STONE = dict(va.pbr("limestone", "sandstone parapet", 2.4))   # zábradlí a římsy ve stejném pískovci
# medový pískovec jako brána a věže Valorie (předloha), mostovka z kočičích hlav
MASONRY = dict(va.pbr("limestone", "sandstone masonry", 2.4))
COBBLE = va.COBBLE


# ------------------------------------------------------------------ terén
_height = None


def terrain(x, z):
    """Bilineárně z výškové mapy (bez jemného detailu ± 0,45 m, ten má jen hra)."""
    global _height
    if _height is None:
        img = np.asarray(Image.open(ASSETS / "Terrain" / "aethelgard_height.png"), np.float32)
        _height = img / 65535.0 * RANGE + BASE
    n = _height.shape[0]
    cell = SIZE / (n - 1)
    fx = (np.asarray(x, np.float64) + SIZE / 2) / cell
    fz = (np.asarray(z, np.float64) + SIZE / 2) / cell
    x0 = np.clip(np.floor(fx).astype(int), 0, n - 2)
    z0 = np.clip(np.floor(fz).astype(int), 0, n - 2)
    tx, tz = fx - x0, fz - z0
    h = _height
    return ((h[z0, x0] * (1 - tx) + h[z0, x0 + 1] * tx) * (1 - tz)
            + (h[z0 + 1, x0] * (1 - tx) + h[z0 + 1, x0 + 1] * tx) * tz)


def hero_bridge_y():
    """Stejně jako valoria.lua (GateY): nejvyšší místo terénu pod průjezdem brány + 6 cm (+ rezerva na detail)."""
    gx, gz, depth, width = GATE
    xs, zs = np.meshgrid(np.arange(-depth / 2, depth / 2 + 0.5, 1.0) + gx, np.arange(-width / 2, width / 2 + 0.5, 1.0) + gz)
    return float(terrain(xs, zs).max()) + 0.06 + 0.45


# ------------------------------------------------------------------ osa
def centerline(step=STEP):
    """Body osy po `step` m: od brány rovně na západ nad přístavem, pak hladká křivka (Bézier) přes moře na útes."""
    pts = []
    for s in np.arange(0.0, 60.0, step):
        pts.append(START + np.array([-s, 0.0]))
    p0 = START + np.array([-60.0, 0.0])                 # směr -x
    p3 = LANDING
    span = np.linalg.norm(p3 - p0)
    p1 = p0 + np.array([-1.0, 0.0]) * span * 0.42
    toward = np.array([-0.93, -0.37])                     # na útes kolmo k pobřeží
    p2 = p3 - toward * span * 0.38
    t = np.linspace(0, 1, 4000)[:, None]
    bez = (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(bez, axis=0), axis=1))]
    for s in np.arange(0, seg[-1], step):
        pts.append(np.array([np.interp(s, seg, bez[:, 0]), np.interp(s, seg, bez[:, 1])]))
    pts.append(p3)
    d = toward / np.linalg.norm(toward)
    for s in np.arange(step, EXTEND + 1e-6, step):
        pts.append(p3 + d * s)
    P = np.array(pts)
    # rovnoměrné převzorkování
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]
    s = np.arange(0, seg[-1] + 1e-6, step)
    return np.stack([np.interp(s, seg, P[:, 0]), np.interp(s, seg, P[:, 1])], -1), s


def profile(s, land_s, y0, y_land, ground):
    """Výška horní plochy mostovky: plynulý náběh z vodorovného Mostu hrdinů, stálé stoupání s mírným klenutím
    nad mořem (oblouk); na útesu kopíruje terén (vždy 0,55 m nad ním) a za nájezdem se zanoří pod terén."""
    grade = np.clip(s / 70.0, 0, 1)
    grade = grade * grade * (3 - 2 * grade)
    acc = np.cumsum(grade)
    t = np.clip(s / land_s, 0, 1)
    base = y0 + (y_land - y0) * acc / np.interp(land_s, s, acc)
    crown = 5.0 * np.sin(np.pi * t) ** 2
    y = base + crown
    # max. terénu v okolí ± 3 m (detail terénu nesmí prorazit mostovku)
    g = np.array([ground[max(0, i - 2):i + 3].max() for i in range(len(ground))])
    land = s <= land_s
    req = np.where(land, np.maximum(y, g + 0.55), -1e9)
    # stoupání nejvýš MAX_GRADE: mostovka se před překážkou (hrana útesu) zvedne včas, žádný skok
    ds = np.abs(s[:, None] - s[None, :])
    y[land] = (req[None, :] - MAX_GRADE * ds).max(axis=1)[land]
    beyond = ~land
    y[beyond] = g[beyond] + 0.55 - 1.4 * np.clip((s[beyond] - land_s) / 8.0, 0, 1)
    return y


# ------------------------------------------------------------------ geometrie
def frames(C):
    T = np.gradient(C, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    Nrm = np.stack([T[:, 1], -T[:, 0]], -1)                # vpravo od směru
    return T, Nrm


def grid_mesh(G, flip=False):
    """Pás ze sítě bodů (řady × sloupce × 3); normály z mřížky (hladké podél, ostré hrany mezi pásy)."""
    rows, cols = G.shape[:2]
    P = G.reshape(-1, 3)
    idx = np.arange(rows * cols).reshape(rows, cols)
    a, b, c, d = idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]
    I = np.concatenate([np.stack([a, b, c], -1).reshape(-1, 3), np.stack([a, c, d], -1).reshape(-1, 3)])
    du = np.gradient(G, axis=0)
    dv = np.gradient(G, axis=1)
    N = np.cross(du, dv)
    if flip:
        I = I[:, ::-1]
        N = -N
    N = N / np.maximum(np.linalg.norm(N, axis=-1, keepdims=True), 1e-9)
    m = Mesh(P, I)
    m.N = N.reshape(-1, 3).astype(np.float32)
    return m


def ribbon(C, Nrm, off0, off1, y_bottom, y_top, caps=(True, True)):
    """Kvádr táhnoucí se po ose: příčně off0..off1 (m vpravo), svisle y_bottom..y_top (pole po bodech osy)."""
    def pt(off, y):
        return np.stack([C[:, 0] + Nrm[:, 0] * off, y, C[:, 1] + Nrm[:, 1] * off], -1)
    L0b, L0t = pt(off0, y_bottom), pt(off0, y_top)
    L1b, L1t = pt(off1, y_bottom), pt(off1, y_top)
    parts = [grid_mesh(np.stack([L0t, L1t], 1)),            # vršek
             grid_mesh(np.stack([L0b, L1b], 1), flip=True),  # spodek
             grid_mesh(np.stack([L1b, L1t], 1)),             # pravý bok
             grid_mesh(np.stack([L0b, L0t], 1), flip=True)]  # levý bok
    for k, end in enumerate(caps):
        if not end:
            continue
        i = 0 if k == 0 else -1
        q = np.array([L0b[i], L1b[i], L1t[i], L0t[i]])
        m = Mesh(q, [[0, 1, 2], [0, 2, 3]] if k == 1 else [[0, 2, 1], [0, 3, 2]])
        n = np.cross(q[1] - q[0], q[2] - q[0])
        n = n / np.linalg.norm(n) * (1 if k == 1 else -1)
        m.N = np.repeat(n[None], 4, 0).astype(np.float32)
        parts.append(m)
    return merge(*parts)


def oriented_box(center, tangent, size, yaw_extra=0.0):
    yaw = math.degrees(math.atan2(tangent[0], tangent[1])) + yaw_extra
    return box(*size).rotate(0, yaw, 0).translate(*center)


def build():
    C, s = centerline()
    T, Nrm = frames(C)
    total = s[-1]
    land_s = total - EXTEND
    y0_world = hero_bridge_y()
    y_land = float(terrain(LANDING[0], LANDING[1])) + 0.55
    # terén pod celou šířkou mostovky
    ground = np.max([terrain(C[:, 0] + Nrm[:, 0] * o, C[:, 1] + Nrm[:, 1] * o)
                     for o in np.linspace(-DECK_WIDTH / 2, DECK_WIDTH / 2, 7)], axis=0)
    deck = profile(s, land_s, y0_world, y_land, ground)    # světové výšky
    gmin = np.min([terrain(C[:, 0] + Nrm[:, 0] * o, C[:, 1] + Nrm[:, 1] * o)
                   for o in np.linspace(-CORE_WIDTH / 2 - 3, CORE_WIDTH / 2 + 3, 7)], axis=0)
    clearance = deck - ground
    over = s <= land_s
    worst = float(clearance[over].min())
    assert worst > 0.5, f"mostovka by prorážela terén (rezerva {worst:.2f} m v s = {s[over][clearance[over].argmin()]:.0f})"

    under = deck - DECK_THICK
    # pilíře: rovnoměrně mezi začátkem a nájezdem
    n_spans = max(1, int(round(land_s / PIER_SPACING)))
    pier_s = np.linspace(0, land_s, n_spans + 1)
    pier_w = 5.0
    bottom = np.full_like(s, -1e9)                          # spodní líc klenby / plné zdi (-1e9 = až do země)
    for a, b in zip(pier_s[:-1], pier_s[1:]):
        m = (s >= a) & (s <= b)
        u = s[m] - (a + b) / 2
        half = (b - a) / 2 - pier_w / 2
        crown = np.interp((a + b) / 2, s, under) - 2.2
        rise = min(half, max(4.0, crown - (np.interp((a + b) / 2, s, gmin) + 1.0)))
        spring = crown - rise
        arch = spring + rise * np.sqrt(np.clip(1 - (u / half) ** 2, 0, 1))
        arch[np.abs(u) >= half] = -1e9                      # pilíř: až do země
        bottom[m] = arch
    ground_c = np.minimum(gmin, ground) - 2.0               # založení pod terénem / mořským dnem
    # předmostí u brány: první pole je plný kamenný opěrák až do skály (žádná tenká deska nad roklí)
    abut = s <= pier_s[1] - pier_w / 2
    bottom[abut] = -1e9
    fill = bottom < gmin + 0.3                              # klenba by zasahovala do terénu: plná zeď
    bottom = np.where(fill, ground_c, bottom)
    bottom = np.minimum(bottom, under - 0.4)
    assert np.isfinite(bottom).all() and np.isfinite(deck).all()

    y0 = y0_world
    rel = lambda y: y - y0
    parts_by_chunk = [dict(deck=[], parapet=[], core=[]) for _ in range(CHUNKS)]
    edges = np.linspace(0, len(s) - 1, CHUNKS + 1).astype(int)
    Cl = C - START
    for k in range(CHUNKS):
        i0, i1 = edges[k], edges[k + 1] + 1
        sl = slice(i0, i1)
        c, nr = Cl[sl], Nrm[sl]
        dk, un, bt = rel(deck[sl]), rel(under[sl]), rel(bottom[sl])
        first, last = k == 0, k == CHUNKS - 1
        P = parts_by_chunk[k]
        P["deck"].append(ribbon(c, nr, -DECK_WIDTH / 2, DECK_WIDTH / 2, dk - DECK_THICK, dk, (first, last)))
        # římsa pod mostovkou
        P["parapet"].append(ribbon(c, nr, -DECK_WIDTH / 2 - 0.25, DECK_WIDTH / 2 + 0.25, dk - DECK_THICK - 0.45,
                                   dk - DECK_THICK + 0.05, (first, last)))
        for side in (-1, 1):
            o = side * (DECK_WIDTH / 2 - PARAPET_T / 2)
            P["parapet"].append(ribbon(c, nr, o - PARAPET_T / 2, o + PARAPET_T / 2, dk - 0.05, dk + PARAPET_H,
                                       (first, last)))
            P["parapet"].append(ribbon(c, nr, o - PARAPET_T / 2 - 0.12, o + PARAPET_T / 2 + 0.12,
                                       dk + PARAPET_H, dk + PARAPET_H + 0.18, (first, last)))
        # klenby a plné zdi
        P["core"].append(ribbon(c, nr, -CORE_WIDTH / 2, CORE_WIDTH / 2, bt, un + 0.02, (first, last)))
        # opěrák předmostí: v plné šířce mostovky až pod terén (lícuje s bránou a s útesem)
        ia = np.nonzero(abut[sl])[0]
        if len(ia) > 1:
            j = slice(ia[0], ia[-1] + 1)
            P["core"].append(ribbon(c[j], nr[j], -DECK_WIDTH / 2 - 0.25, DECK_WIDTH / 2 + 0.25,
                                    rel(ground_c[sl][j]) - 2.0, dk[j] - DECK_THICK - 0.45, (True, True)))

    # pilíře: zesílené s břitem proti vlnám a hlavicí pod patkou klenby
    for ps in pier_s[1:-1]:
        i = int(np.argmin(np.abs(s - ps)))
        k = min(int(np.searchsorted(edges, i, side="right") - 1), CHUNKS - 1)
        P = parts_by_chunk[k]
        top = rel(under[i]) - 1.0
        foot = rel(min(gmin[i], ground[i]) - 2.0)
        if top - foot < 3.0:
            continue
        cx, cz = Cl[i]
        h = top - foot
        center = (cx, foot + h / 2, cz)
        P["core"].append(oriented_box(center, T[i], (CORE_WIDTH + 2.2, h, pier_w + 1.2)))
        # břity (kosodélníkové hrany napříč proudem) po stranách pilíře
        for side in (-1, 1):
            ox, oz = Nrm[i] * side * (CORE_WIDTH / 2 + 1.1)
            P["core"].append(box(3.0, h, 3.0).rotate(0, 45 + math.degrees(math.atan2(T[i][0], T[i][1])), 0)
                             .translate(cx + ox, foot + h / 2, cz + oz))
        # hlavice (římsa) v patě klenby
        P["parapet"].append(oriented_box((cx, top + 0.35, cz), T[i], (CORE_WIDTH + 3.0, 0.7, pier_w + 2.0)))
        # u hladiny tmavší, vlnami omletý sokl
        if foot < rel(SEA_Y) < top:
            P["parapet"].append(oriented_box((cx, rel(SEA_Y) + 0.4, cz), T[i], (CORE_WIDTH + 3.0, 3.0, pier_w + 2.0)))

    # sloupky zábradlí po 12 m
    for ps in np.arange(6.0, land_s, 12.0):
        i = int(np.argmin(np.abs(s - ps)))
        k = min(int(np.searchsorted(edges, i, side="right") - 1), CHUNKS - 1)
        for side in (-1, 1):
            o = side * (DECK_WIDTH / 2 - PARAPET_T / 2)
            cx, cz = Cl[i] + Nrm[i] * o
            parts_by_chunk[k]["parapet"].append(
                oriented_box((cx, rel(deck[i]) + 0.85, cz), T[i], (PARAPET_T + 0.35, 1.7, 0.9)))

    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("skybridge*.glb"):
        old.unlink()
    for k, P in enumerate(parts_by_chunk):
        name = "skybridge" if CHUNKS == 1 else f"skybridge_{k}"
        write_glb(str(OUT / f"{name}.glb"),
                  [(merge(*P["deck"]), COBBLE), (merge(*P["parapet"]), STONE), (merge(*P["core"]), MASONRY)],
                  name=name)

    # data pro hru: osa po 10 m (pro rozmístění luceren, místa bez stromů a samotest)
    lines = ["-- Vygenerováno skriptem tools/valoria_skybridge.py – neupravovat ručně.",
             "-- Obloukový most Valoria – hlavní ostrov: osa po 10 m {x, z, výška mostovky vůči začátku, na moři}",
             "return {",
             f"    start = {{ x = {START[0]:.1f}, z = {START[1]:.1f} }},",
             f"    landing = {{ x = {LANDING[0]:.1f}, z = {LANDING[1]:.1f} }},",
             f"    chunks = {CHUNKS},",
             f"    width = {DECK_WIDTH},",
             f"    length = {land_s:.1f},",
             f"    landing_rise = {rel(y_land):.2f},",
             "    points = {"]
    for ps in np.arange(0.0, total + 1e-6, 10.0):
        i = int(np.argmin(np.abs(s - ps)))
        sea = 1 if ground[i] < SEA_Y else 0
        lines.append(f"        {{ {C[i, 0]:.1f}, {C[i, 1]:.1f}, {rel(deck[i]):.2f}, {sea} }},")
    lines += ["    },", "}", ""]
    DATA.write_text("\n".join(lines), encoding="utf-8")
    print(f"most: {land_s:.0f} m (+{EXTEND:.0f} m pod terén), stoupání {rel(y_land):.1f} m, "
          f"nejvyšší bod {deck.max():.1f} m n. m., rezerva nad terénem {worst:.2f} m, pilířů {n_spans - 1}, "
          f"max. sklon {np.max(np.abs(np.diff(deck[s <= land_s]) / np.diff(s[s <= land_s]))) * 100:.1f} %")
    return dict(s=s, C=C, deck=deck, ground=ground, y0=y0)


if __name__ == "__main__":
    build()
