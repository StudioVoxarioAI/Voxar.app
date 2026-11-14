#!/usr/bin/env python3
"""Cesty napříč Aethelgardem (engine ≥ 1.22, world.road).

  python3 tools/eryndor_roads.py

Trasy hledá A* po výškové mapě (buňky 8 m): cena roste se sklonem, voda a láva jsou zakázané – řeku Serpentine
cesty přecházejí jen po mostech (D.Bridges), na útesy nevedou. Výsledná osa se vyhladí (Douglas–Peucker +
Catmull-Rom v enginu).

Síť:
  Královská cesta     obloukový most z Valorie (útes) -> hraniční základna (dlážděná)
  Cesta k jezeru      základna -> jižní břeh zamrzlého jezera ve Frostfang Peaks
  Lesní cesta         základna -> most přes Serpentine -> elfí svatyně -> Tisíciletý strom (Verdant Canopy)
  Popelavá stezka     základna -> Pavoučí hnízdo -> okraj Ignis Scar
  Krystalová stezka   základna -> trhlina v Crystalariu

Výstup:
  Assets/Scripts/eryndor/roads_data.lua             osy cest po ~10 m {x, z}
  Assets/Terrain/aethelgard_splat0.png / splat1.png  krajnice cest jako hlína (vrstva 2) – tráva na cestě neroste
  Assets/Textures/roads/<fotosken>_{basecolor,normal,orm}.jpg   PBR povrchy cest (Poly Haven, CC0)
"""
from __future__ import annotations

import heapq
import json
import math
import os
import pathlib
import re
import urllib.request

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Assets"
TERRAIN = ASSETS / "Terrain"
WORLD_DATA = ASSETS / "Scripts" / "eryndor" / "world_data.lua"
SKY_DATA = ASSETS / "Scripts" / "eryndor" / "skybridge_data.lua"
OUT = ASSETS / "Scripts" / "eryndor" / "roads_data.lua"
TEX = ASSETS / "Textures" / "roads"
SIZE, BASE, RANGE = 8192.0, -80.0, 760.0
CELL = 8.0
SEA = 0.0
UA = {"User-Agent": "eryndor-roads/1.0"}

SURFACES = {"dirt": "stony_dirt_path", "stone": "grey_stone_path"}


def fetch_surface(name, asset, cache):
    folder = cache / asset
    folder.mkdir(parents=True, exist_ok=True)
    meta = folder / "files.json"
    if not meta.exists():
        with urllib.request.urlopen(urllib.request.Request("https://api.polyhaven.com/files/" + asset, headers=UA),
                                    timeout=60) as r:
            meta.write_bytes(r.read())
    data = json.loads(meta.read_text())
    TEX.mkdir(parents=True, exist_ok=True)
    for key, suffix in (("Diffuse", "basecolor"), ("nor_gl", "normal"), ("arm", "orm")):
        f = data[key]["1k"]["jpg"]
        src = folder / f"{key}_1k.jpg"
        if not src.exists():
            print(f"  stahuji {asset}/{key}")
            with urllib.request.urlopen(urllib.request.Request(f["url"], headers=UA), timeout=180) as r:
                src.write_bytes(r.read())
        img = Image.open(src).convert("RGB")
        if suffix == "basecolor" and name == "dirt":
            # fotosken je vlhký a tmavý: suchá prašná cesta – světlejší, méně sytá
            arr = np.asarray(img, np.float32) / 255.0
            luma = arr @ np.array([0.2126, 0.7152, 0.0722], np.float32)
            arr = (arr * 0.7 + luma[..., None] * 0.3) * np.array([1.38, 1.32, 1.25], np.float32)
            img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        img.save(TEX / f"{name}_{suffix}.jpg", quality=88)


def world_data():
    text = WORLD_DATA.read_text(encoding="utf-8")
    poi = {k: (float(x), float(z)) for k, x, z in re.findall(r"(\w+) = \{ x = ([-\d.]+), z = ([-\d.]+) \}", text)}
    lake = re.search(r"D.FrozenLake = \{ x = ([-\d.]+), z = ([-\d.]+), rx = ([-\d.]+), rz = ([-\d.]+)", text)
    bridges = [(float(x), float(z), float(y), float(L)) for x, z, y, L in
               re.findall(r"\{ x = ([-\d.]+), z = ([-\d.]+), yaw = ([-\d.]+), length = ([-\d.]+) \}", text)]
    regions = {k: (float(x), float(z)) for k, x, z in
               re.findall(r"(\w+) = \{ name = \"[^\"]+\", x = ([-\d.]+), z = ([-\d.]+) \}", text)}
    sky = SKY_DATA.read_text(encoding="utf-8")
    landing = re.search(r"landing = \{ x = ([-\d.]+), z = ([-\d.]+) \}", sky)
    return poi, tuple(map(float, lake.groups())), bridges, regions, (float(landing[1]), float(landing[2]))


def load_height():
    h = np.asarray(Image.open(TERRAIN / "aethelgard_height.png"), np.float32) / 65535.0 * RANGE + BASE
    n = int(SIZE / CELL) + 1
    return np.asarray(Image.fromarray(h, "F").resize((n, n), Image.BILINEAR), np.float32)


def to_cell(x, z):
    return int(round((z + SIZE / 2) / CELL)), int(round((x + SIZE / 2) / CELL))


def to_world(r, c):
    return c * CELL - SIZE / 2, r * CELL - SIZE / 2


def cost_grid(height, lava, bridges):
    gz, gx = np.gradient(height, CELL)
    slope = np.hypot(gx, gz)
    cost = 1.0 + 40.0 * slope ** 2
    blocked = (height < SEA + 0.8) | (slope > 0.62)
    # láva: průchodná jen draze -> cesta ji přejde na nejužším místě (kamenný most, viz lava_bridges)
    cost = np.where(lava > 0.15, cost + 60.0, cost)
    # mosty přes Serpentine: průchod po ose mostu (+ nájezdy)
    n = height.shape[0]
    for bx, bz, yaw, length in bridges:
        dx, dz = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
        for t in np.arange(-length / 2 - 24, length / 2 + 24, CELL / 2):
            r, c = to_cell(bx + dx * t, bz + dz * t)
            for rr in range(r - 1, r + 2):
                for cc in range(c - 1, c + 2):
                    if 0 <= rr < n and 0 <= cc < n:
                        blocked[rr, cc] = False
                        cost[rr, cc] = 1.0
    cost[blocked] = np.inf
    return cost


def astar(cost, start, goal):
    n = cost.shape[0]
    sr, sc = start
    gr, gc = goal

    def free_near(r, c):
        best = None
        for rad in range(0, 40):
            for rr in range(r - rad, r + rad + 1):
                for cc in range(c - rad, c + rad + 1):
                    if 0 <= rr < n and 0 <= cc < n and np.isfinite(cost[rr, cc]):
                        d = (rr - r) ** 2 + (cc - c) ** 2
                        if best is None or d < best[0]:
                            best = (d, rr, cc)
            if best:
                return best[1], best[2]
        raise RuntimeError("žádná průchozí buňka")
    sr, sc = free_near(sr, sc)
    gr, gc = free_near(gr, gc)
    g = {(sr, sc): 0.0}
    came = {}
    heap = [(0.0, sr, sc)]
    steps = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0), (-1, -1, 1.414), (-1, 1, 1.414), (1, -1, 1.414),
             (1, 1, 1.414), (-2, -1, 2.236), (-2, 1, 2.236), (2, -1, 2.236), (2, 1, 2.236), (-1, -2, 2.236),
             (1, -2, 2.236), (-1, 2, 2.236), (1, 2, 2.236)]
    while heap:
        f, r, c = heapq.heappop(heap)
        if (r, c) == (gr, gc):
            break
        base = g[(r, c)]
        if f - math.hypot(r - gr, c - gc) > base + 1e-6:
            continue
        for dr, dc, w in steps:
            rr, cc = r + dr, c + dc
            if not (0 <= rr < n and 0 <= cc < n):
                continue
            k = cost[rr, cc]
            if not np.isfinite(k):
                continue
            if w > 2:   # skok o dvě buňky: i prostřední musí být průchozí
                mr, mc = r + int(round(dr / 2)), c + int(round(dc / 2))
                if not np.isfinite(cost[mr, mc]):
                    continue
            ng = base + w * 0.5 * (k + cost[r, c])
            if ng < g.get((rr, cc), math.inf):
                g[(rr, cc)] = ng
                came[(rr, cc)] = (r, c)
                heapq.heappush(heap, (ng + math.hypot(rr - gr, cc - gc), rr, cc))
    if (gr, gc) not in came:
        raise RuntimeError("cesta nenalezena")
    path = [(gr, gc)]
    while path[-1] != (sr, sc):
        path.append(came[path[-1]])
    return [to_world(r, c) for r, c in reversed(path)]


def simplify(points, tol=3.0):
    pts = np.asarray(points, np.float64)
    if len(pts) < 3:
        return pts
    keep = np.zeros(len(pts), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ab = pts[b] - pts[a]
        L = np.linalg.norm(ab)
        seg = pts[a + 1:b] - pts[a]
        if L < 1e-6:
            d = np.linalg.norm(seg, axis=1)
        else:
            d = np.abs(seg[:, 0] * ab[1] - seg[:, 1] * ab[0]) / L
        i = int(np.argmax(d))
        if d[i] > tol:
            keep[a + 1 + i] = True
            stack += [(a, a + 1 + i), (a + 1 + i, b)]
    return pts[keep]


def resample(points, step=10.0):
    pts = np.asarray(points, np.float64)
    seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
    s = np.arange(0, seg[-1], step)
    s = np.r_[s, seg[-1]]
    return np.stack([np.interp(s, seg, pts[:, 0]), np.interp(s, seg, pts[:, 1])], -1)


def smooth(points, iterations=3):
    p = np.asarray(points, np.float64).copy()
    for _ in range(iterations):
        p[1:-1] = p[1:-1] * 0.5 + (p[:-2] + p[2:]) * 0.25
    return p


def lava_bridges(points, lava):
    """Úseky cesty nad lávou -> (i0, i1) indexy bodů osy, kde začíná a končí most (s nájezdy)."""
    n = lava.shape[0]
    hot = []
    for x, z in points:
        r, c = to_cell(x, z)
        hot.append(lava[max(r - 1, 0):r + 2, max(c - 1, 0):c + 2].max() > 0.12)
    spans = []
    i = 0
    while i < len(hot):
        if hot[i]:
            j = i
            while j + 1 < len(hot) and hot[j + 1]:
                j += 1
            spans.append((max(i - 2, 0), min(j + 2, len(points) - 1)))
            i = j + 1
        else:
            i += 1
    merged = []
    for a, b in spans:
        if merged and a <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], b)
        else:
            merged.append((a, b))
    return merged


def terrain_at(x, z):
    """Bilineárně z 16bit výškové mapy (bez jemného detailu ± 0,45 m – ten přidává engine)."""
    global _H
    if "_H" not in globals():
        _H = np.asarray(Image.open(TERRAIN / "aethelgard_height.png"), np.float32) / 65535.0 * RANGE + BASE
    h = _H
    n = h.shape[0]
    cell = SIZE / (n - 1)
    fx, fz = (np.asarray(x) + SIZE / 2) / cell, (np.asarray(z) + SIZE / 2) / cell
    x0 = np.clip(np.floor(fx).astype(int), 0, n - 2)
    z0 = np.clip(np.floor(fz).astype(int), 0, n - 2)
    tx, tz = fx - x0, fz - z0
    return ((h[z0, x0] * (1 - tx) + h[z0, x0 + 1] * tx) * (1 - tz) + (h[z0 + 1, x0] * (1 - tx) + h[z0 + 1, x0 + 1] * tx) * tz)


def lava_bridge_model(a, b, width, out):
    """Kamenný obloukový most přes lávovou řeku: mostovka z A do B, pod ní klenba; konce zanořené do terénu."""
    import valoria_skybridge as vs
    from meshkit import merge, write_glb
    a, b = np.asarray(a, np.float64), np.asarray(b, np.float64)
    d = (b - a) / np.linalg.norm(b - a)
    L = float(np.linalg.norm(b - a))
    s = np.arange(-4.0, L + 4.0 + 1e-6, 1.0)
    C = a + d[None, :] * s[:, None]
    T, Nrm = vs.frames(C)
    ground = np.max([terrain_at(C[:, 0] + Nrm[:, 0] * o, C[:, 1] + Nrm[:, 1] * o)
                     for o in np.linspace(-width / 2 - 1, width / 2 + 1, 5)], axis=0)
    ya, yb = float(terrain_at(*a)) + 0.05, float(terrain_at(*b)) + 0.05
    t = np.clip(s / L, 0, 1)
    base = ya + (yb - ya) * t
    hump = np.sin(np.pi * t)
    need = np.max((ground + 4.0 - base)[(s > 6) & (s < L - 6)] / np.maximum(hump[(s > 6) & (s < L - 6)], 0.05))
    deck = base + max(need, 2.0) * hump
    deck[s < 0] = ya - 0.6 * (-s[s < 0] / 4.0)
    deck[s > L] = yb - 0.6 * ((s[s > L] - L) / 4.0)
    under = deck - 0.9
    # klenba: jeden velký oblouk mezi patkami (patky 6 m od konců), mimo něj plná zeď do terénu
    span0, span1 = 6.0, L - 6.0
    mid, half = (span0 + span1) / 2, (span1 - span0) / 2
    crown = float(np.interp(mid, s, under)) - 1.2
    rise = max(3.0, crown - float(ground[(s > span0) & (s < span1)].max()) - 1.0)
    rise = min(rise, half)
    arch = crown - rise + rise * np.sqrt(np.clip(1 - ((s - mid) / half) ** 2, 0, 1))
    bottom = np.where((s > span0) & (s < span1) & (arch > ground + 0.5), arch, ground - 2.0)
    bottom = np.minimum(bottom, under - 0.3)
    origin = np.array([a[0], 0.0, a[1]])
    Cl = C - a
    parts_deck = [vs.ribbon(Cl, Nrm, -width / 2, width / 2, deck - 0.9, deck)]
    parts_stone = [vs.ribbon(Cl, Nrm, -width / 2 + 0.6, width / 2 - 0.6, bottom, under + 0.02)]
    for side in (-1, 1):
        o = side * (width / 2 - 0.3)
        parts_stone.append(vs.ribbon(Cl, Nrm, o - 0.3, o + 0.3, deck - 0.05, deck + 1.0))
        parts_stone.append(vs.ribbon(Cl, Nrm, o - 0.42, o + 0.42, deck + 1.0, deck + 1.18))
    parts_stone.append(vs.ribbon(Cl, Nrm, -width / 2 - 0.2, width / 2 + 0.2, deck - 1.25, deck - 0.85))
    write_glb(str(out), [(merge(*parts_deck), vs.COBBLE), (merge(*parts_stone), vs.MASONRY)], name="LavaBridge")
    return float(deck.max())


def paint_splats(roads):
    s0 = np.asarray(Image.open(TERRAIN / "aethelgard_splat0.png").convert("RGBA"), np.float32)
    s1 = np.asarray(Image.open(TERRAIN / "aethelgard_splat1.png").convert("RGBA"), np.float32)
    n = s0.shape[0]
    px = SIZE / n
    weight = np.zeros((n, n), np.float32)
    for road, seg in ((r, s) for r in roads for s in r["segments"]):   # ne pod mosty přes lávu
        half = road["width"] / 2 + 2.5
        pts = resample(seg, px * 0.5)
        for x, z in pts:
            c, r = (x + SIZE / 2) / px, (z + SIZE / 2) / px
            rad = int(math.ceil(half / px)) + 1
            r0, c0 = int(r), int(c)
            rr, cc = np.mgrid[max(r0 - rad, 0):min(r0 + rad + 1, n), max(c0 - rad, 0):min(c0 + rad + 1, n)]
            d = np.hypot((rr + 0.5 - r) * px, (cc + 0.5 - c) * px)
            w = np.clip(1.0 - (d - road["width"] / 2) / 2.5, 0.0, 1.0) * 0.93
            weight[rr, cc] = np.maximum(weight[rr, cc], w)
    # rozcestí: prašné prostranství
    hx, hz = roads[0]["hub"]
    rr, cc = np.mgrid[0:n, 0:n]
    d = np.hypot((cc + 0.5) * px - SIZE / 2 - hx, (rr + 0.5) * px - SIZE / 2 - hz)
    weight = np.maximum(weight, np.clip(1.0 - (d - 12.0) / 6.0, 0.0, 1.0) * 0.8)
    w = weight[..., None]
    total = s0.sum(-1, keepdims=True) + s1.sum(-1, keepdims=True)
    s0 = s0 * (1 - w)
    s1 = s1 * (1 - w)
    s0[..., 1:2] += w * np.maximum(total, 1.0)   # vrstva 2 (hlína) = splat0 G
    Image.fromarray(np.clip(s0 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(TERRAIN / "aethelgard_splat0.png",
                                                                          optimize=True)
    Image.fromarray(np.clip(s1 + 0.5, 0, 255).astype(np.uint8), "RGBA").save(TERRAIN / "aethelgard_splat1.png",
                                                                          optimize=True)


def build():
    poi, lake, bridges, regions, landing = world_data()
    height = load_height()
    n = height.shape[0]
    lava = np.asarray(Image.open(TERRAIN / "aethelgard_splat1.png").convert("RGBA").resize((n, n), Image.BILINEAR),
                      np.float32)[..., 1] / 255.0
    cost = cost_grid(height, lava, bridges)
    start = poi["Start"]
    lx, lz, rx, rz = lake
    west_bridge = min(bridges, key=lambda b: math.hypot(b[0] - start[0], b[1] - start[1]))
    # konec obloukového mostu: mostovka se zanořuje 14 m za nájezdem směrem (-0.93, -0.37)
    land = (landing[0] - 0.93 * 18, landing[1] - 0.37 * 18)
    # rozcestí před branou základny (mimo palisádu): všechny cesty se sbíhají do jednoho bodu
    hub = (start[0] + 34.0, start[1] + 30.0)
    plan = [
        ("Královská cesta", "stone", 6.0, [land, hub]),
        ("Cesta k zamrzlému jezeru", "dirt", 4.5, [hub, (lx + 140, lz + rz + 60)]),
        ("Lesní cesta", "dirt", 4.5, [hub, (west_bridge[0], west_bridge[1]), poi["Shrine"], poi["Giant"]]),
        ("Popelavá stezka", "dirt", 4.0, [hub, poi["SpiderNest"], (regions["ignis"][0], regions["ignis"][1] - 260)]),
        ("Krystalová stezka", "dirt", 4.0, [hub, poi["Rift"]]),
    ]
    roads = []
    for name, surface, width, stops in plan:
        path = []
        for a, b in zip(stops[:-1], stops[1:]):
            seg = astar(cost, to_cell(*a), to_cell(*b))
            path += seg if not path else seg[1:]
        pts = smooth(resample(simplify(path, 4.0), 10.0), 4)
        spans = lava_bridges(pts, lava)
        bridges_on = [(pts[a].tolist(), pts[b].tolist()) for a, b in spans]
        # úseky cesty mezi mosty (pás cesty nekreslí přes lávu)
        segments, i0 = [], 0
        for a, b in spans:
            segments.append(pts[i0:a + 1])
            i0 = b
        segments.append(pts[i0:])
        segments = [seg for seg in segments if len(seg) >= 2]
        roads.append(dict(name=name, surface=surface, width=width, points=pts, lava_bridges=bridges_on,
                          segments=segments, hub=hub))
        length = float(np.linalg.norm(np.diff(pts, axis=0), axis=1).sum())
        print(f"{name}: {length / 1000:.2f} km, {len(pts)} bodů")
    return roads


def write(roads):
    lines = ["-- Vygenerováno skriptem tools/eryndor_roads.py – neupravovat ručně.",
             "-- Cesty napříč Aethelgardem: osa po ~10 m {x, z}; surface = dirt | stone (Textures/roads/<surface>_*.jpg)",
             "return {"]
    for r in roads:
        lines.append(f'    {{ name = "{r["name"]}", surface = "{r["surface"]}", width = {r["width"]}, segments = {{')
        for seg in r["segments"]:
            lines.append("        {")
            row = []
            for x, z in seg:
                row.append(f"{{ {x:.1f}, {z:.1f} }}")
                if len(row) == 6:
                    lines.append("            " + ", ".join(row) + ",")
                    row = []
            if row:
                lines.append("            " + ", ".join(row) + ",")
            lines.append("        },")
        lines.append("    },")
        lines.append("    lava_bridges = {")
        for (ax, az), (bx, bz) in r["lava_bridges"]:
            lines.append(f"        {{ {ax:.1f}, {az:.1f}, {bx:.1f}, {bz:.1f} }},")
        lines.append("    } },")
    lines += ["}", ""]
    OUT.write_text("\n".join(lines), encoding="utf-8")


def main():
    cache = pathlib.Path(os.environ.get("ERYNDOR_TEXTURE_CACHE", str(pathlib.Path.home() / ".cache" / "eryndor-polyhaven")))
    for name, asset in SURFACES.items():
        fetch_surface(name, asset, cache)
    roads = build()
    out = ASSETS / "Models" / "roads"
    out.mkdir(parents=True, exist_ok=True)
    k = 0
    for r in roads:
        for a, b in r["lava_bridges"]:
            top = lava_bridge_model(a, b, r["width"] + 1.5, out / f"lava_bridge_{k}.glb")
            print(f"most přes lávu {k}: {np.linalg.norm(np.subtract(b, a)):.0f} m, vrchol {top:.1f} m")
            k += 1
    write(roads)
    paint_splats(roads)
    print(f"{OUT.relative_to(ROOT)}: {len(roads)} cest")


if __name__ == "__main__":
    main()
