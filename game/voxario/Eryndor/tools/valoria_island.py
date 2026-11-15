#!/usr/bin/env python3
"""Přepíše ostrov Valorie ve výškové mapě a splat mapách Aethelgardu (bez přegenerování celého světa).

  python3 tools/valoria_island.py

Tvar ostrova je ve valoria_terrain.apply (stejná funkce používá aethelgard_world.py). Pod ostrovem se počítá
s mořským dnem okolí; mimo masku ostrova se nic nemění.
"""
from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image

import valoria_terrain as vt

ROOT = pathlib.Path(__file__).resolve().parent.parent
TERRAIN = ROOT / "Assets" / "Terrain"
SIZE, BASE, RANGE = 8192.0, -80.0, 760.0


def main():
    hp = TERRAIN / "aethelgard_height.png"
    h16 = np.asarray(Image.open(hp)).astype(np.float64)
    height = h16 / 65535.0 * RANGE + BASE
    n = height.shape[0]
    cell = SIZE / (n - 1)
    # oblast ostrova (s rezervou)
    x0, x1, z0, z1 = 2300.0, 3700.0, 1600.0, 3200.0
    c0, c1 = int((x0 + SIZE / 2) / cell), int((x1 + SIZE / 2) / cell) + 1
    r0, r1 = int((z0 + SIZE / 2) / cell), int((z1 + SIZE / 2) / cell) + 1
    xs = np.arange(c0, c1) * cell - SIZE / 2
    zs = np.arange(r0, r1) * cell - SIZE / 2
    X, Z = np.meshgrid(xs, zs)
    sub = height[r0:r1, c0:c1]
    _, mask = vt.coast(X - vt.CENTER_X, Z - vt.CENTER_Z)
    # mořské dno pod ostrovem: průměr okolí mimo masku
    ring = sub[(mask == 0)]
    seabed = float(np.median(ring[ring < -5])) if np.any(ring < -5) else -72.0
    base = np.where(mask > 0, seabed, sub)
    new, mask2 = vt.apply(base, X, Z)
    height[r0:r1, c0:c1] = new
    Image.fromarray(((height - BASE) / RANGE * 65535).clip(0, 65535).astype(np.uint16)).save(hp, optimize=True)

    # povrchy: splat mapy mají 2048 px (o jeden méně než výšková mapa)
    s0p, s1p = TERRAIN / "aethelgard_splat0.png", TERRAIN / "aethelgard_splat1.png"
    s0 = np.asarray(Image.open(s0p).convert("RGBA"), np.float32) / 255.0
    s1 = np.asarray(Image.open(s1p).convert("RGBA"), np.float32) / 255.0
    m = s0.shape[0]
    px = SIZE / m
    sc0, sc1 = int((x0 + SIZE / 2) / px), int((x1 + SIZE / 2) / px) + 1
    sr0, sr1 = int((z0 + SIZE / 2) / px), int((z1 + SIZE / 2) / px) + 1
    sx = (np.arange(sc0, sc1) + 0.5) * px - SIZE / 2
    sz = (np.arange(sr0, sr1) + 0.5) * px - SIZE / 2
    SX, SZ = np.meshgrid(sx, sz)
    # výška a sklon na pixelech splat map (z nové výškové mapy)
    fx = (SX + SIZE / 2) / cell
    fz = (SZ + SIZE / 2) / cell
    ix, iz = np.clip(fx.astype(int), 0, n - 2), np.clip(fz.astype(int), 0, n - 2)
    tx, tz = fx - ix, fz - iz
    hh = ((height[iz, ix] * (1 - tx) + height[iz, ix + 1] * tx) * (1 - tz) +
          (height[iz + 1, ix] * (1 - tx) + height[iz + 1, ix + 1] * tx) * tz)
    gz, gx = np.gradient(hh, px)
    slope = np.hypot(gx, gz)
    _, smask = vt.coast(SX - vt.CENTER_X, SZ - vt.CENTER_Z)
    noise = 0.5 + 0.5 * np.sin(SX / 37.0) * np.sin(SZ / 53.0)
    weights = vt.surface_weights(hh, slope, noise)
    w = smask[..., None]
    a0 = s0[sr0:sr1, sc0:sc1] * (1 - w)
    a1 = s1[sr0:sr1, sc0:sc1] * (1 - w)
    for i, wt in enumerate(weights):
        a0[..., i] += smask * wt
    total = a0.sum(-1, keepdims=True) + a1.sum(-1, keepdims=True)
    s0[sr0:sr1, sc0:sc1] = a0 / np.maximum(total, 1e-6)
    s1[sr0:sr1, sc0:sc1] = a1 / np.maximum(total, 1e-6)
    Image.fromarray((s0 * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGBA").save(s0p, optimize=True)
    Image.fromarray((s1 * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGBA").save(s1p, optimize=True)
    # maska jemného detailu terénu (engine ≥ 1.25: terrain detail_mask) – 4 m / px přes celý svět
    mp = TERRAIN / "aethelgard_detail_mask.png"
    m = 2048
    px = SIZE / (m - 1)
    mask = np.ones((m, m), np.float32)
    mc0, mc1 = int((x0 + SIZE / 2) / px), int((x1 + SIZE / 2) / px) + 1
    mr0, mr1 = int((z0 + SIZE / 2) / px), int((z1 + SIZE / 2) / px) + 1
    MX, MZ = np.meshgrid(np.arange(mc0, mc1) * px - SIZE / 2, np.arange(mr0, mr1) * px - SIZE / 2)
    mask[mr0:mr1, mc0:mc1] = vt.detail_strength(MX, MZ)
    Image.fromarray((mask * 255 + 0.5).astype(np.uint8), "L").save(mp, optimize=True)
    print(f"Valoria: plošina {vt.PLATEAU_Y:.0f} m, hrad {vt.KEEP_Y:.0f} m, přístav {vt.HARBOR_Y:.1f} m, dno {seabed:.1f} m")


if __name__ == "__main__":
    main()
