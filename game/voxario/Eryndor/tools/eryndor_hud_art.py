#!/usr/bin/env python3
"""Grafika HUD podle předlohy „Valorie Harbor“: zlatý prstenec kompasu s N/E/S/W, zdobené tmavé panely,
rámeček portrétu, rámeček ukazatelů, znak uprostřed akční lišty.

  python3 tools/eryndor_hud_art.py   -> Assets/UI/hud/*.png

Kreslí se kódem (PIL, písmo Cinzel z Assets/UI) – kov s přechody a jemným leskem, žádné cizí obrázky.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

UI = Path(__file__).resolve().parent.parent / "Assets" / "UI"
OUT = UI / "hud"
CINZEL = str(UI / "Cinzel-SemiBold.ttf")

GOLD_HI = np.array([255, 232, 160], np.float32)
GOLD = np.array([212, 166, 82], np.float32)
GOLD_LO = np.array([110, 74, 30], np.float32)


def metal(t):
    """Zlatý kov podle t 0..1 (tmavý okraj – světlý hřbet – tmavý okraj)."""
    t = np.clip(t, 0, 1)
    hi = np.exp(-((t - 0.38) / 0.16) ** 2)
    base = GOLD_LO + (GOLD - GOLD_LO) * np.sin(np.pi * t)[..., None]
    return base + (GOLD_HI - base) * hi[..., None] * 0.85


def ring(size, r0, r1, rgba, bevel=True):
    """Kruhový zlatý pás r0..r1 (px) do pole rgba."""
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx - c, yy - c)
    a = np.arctan2(yy - c, xx - c)
    m = (r >= r0 - 0.5) & (r <= r1 + 0.5)
    t = (r - r0) / max(r1 - r0, 1)
    col = metal(t if bevel else np.full_like(t, 0.4))
    col = col * (0.9 + 0.1 * np.cos(a * 2 + 0.8))[..., None]   # odlesk podle úhlu
    edge = np.clip(np.minimum(r - (r0 - 0.5), (r1 + 0.5) - r), 0, 1)
    rgba[..., :3] = np.where(m[..., None], col * edge[..., None] + rgba[..., :3] * (1 - edge[..., None]), rgba[..., :3])
    rgba[..., 3] = np.where(m, np.maximum(rgba[..., 3], 255 * edge), rgba[..., 3])


def compass(size=512):
    """Prstenec minimapy: tmavý okraj, zlatý dvojitý prstenec, rysky, hroty světových stran a písmena."""
    rgba = np.zeros((size, size, 4), np.float32)
    c = (size - 1) / 2
    R = size * 0.5
    # tmavý podklad prstence (mezi mapou a zlatem)
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx - c, yy - c)
    band = (r > R * 0.80) & (r < R * 0.93)
    rgba[band] = [16, 22, 34, 235]
    ring(size, R * 0.77, R * 0.81, rgba)
    ring(size, R * 0.91, R * 0.97, rgba)
    img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    # rysky po 15°
    for k in range(24):
        a = k / 24 * 2 * math.pi
        r0, r1 = R * (0.83 if k % 6 else 0.82), R * (0.86 if k % 2 else 0.885)
        d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)],
               fill=(222, 182, 98, 255), width=3 if k % 6 == 0 else 2)
    # hroty světových stran (zlatá kosočtverečná hvězda přes prstenec)
    for k in range(4):
        a = k * math.pi / 2 - math.pi / 2
        tip = (c + math.cos(a) * R * 1.0, c + math.sin(a) * R * 1.0)
        l = (c + math.cos(a - 0.06) * R * 0.94, c + math.sin(a - 0.06) * R * 0.94)
        rr = (c + math.cos(a + 0.06) * R * 0.94, c + math.sin(a + 0.06) * R * 0.94)
        d.polygon([tip, l, (c + math.cos(a) * R * 0.92, c + math.sin(a) * R * 0.92), rr], fill=(232, 196, 112, 255),
                  outline=(90, 60, 24, 255))
    font = ImageFont.truetype(CINZEL, int(size * 0.075))
    for k, letter in enumerate("NESW"):
        a = k * math.pi / 2 - math.pi / 2
        x, y = c + math.cos(a) * R * 0.86, c + math.sin(a) * R * 0.86
        tw = d.textlength(letter, font=font)
        d.text((x - tw / 2 + 2, y - size * 0.045 + 2), letter, font=font, fill=(10, 8, 4, 220))
        d.text((x - tw / 2, y - size * 0.045), letter, font=font, fill=(250, 236, 196, 255))
    # vnitřní stín přes okraj mapy
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([c - R * 0.79, c - R * 0.79, c + R * 0.79, c + R * 0.79], outline=(0, 0, 0, 150), width=int(size * 0.02))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.01))
    return Image.alpha_composite(shadow, img)


def panel(size=192, corner=36, fill=(12, 16, 26, 214)):
    """9-slice panel: tmavá výplň, zlatý dvojitý rám, ozdobné rohy (listy)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([6, 6, size - 7, size - 7], 10, fill=fill)
    d.rounded_rectangle([6, 6, size - 7, size - 7], 10, outline=(212, 166, 82, 255), width=3)
    d.rounded_rectangle([12, 12, size - 13, size - 13], 7, outline=(140, 104, 46, 200), width=1)
    for sx, sy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        x = 6 if sx == 0 else size - 7
        y = 6 if sy == 0 else size - 7
        dx = 1 if sx == 0 else -1
        dy = 1 if sy == 0 else -1
        d.polygon([(x - dx * 3, y - dy * 3), (x + dx * 26, y - dy * 1), (x + dx * 12, y + dy * 6), (x + dx * 6, y + dy * 12),
                   (x - dx * 1, y + dy * 26)], fill=(232, 192, 110, 255), outline=(96, 66, 26, 255))
        d.ellipse([x + dx * 4 - 4, y + dy * 4 - 4, x + dx * 4 + 4, y + dy * 4 + 4], fill=(70, 120, 200, 255),
                  outline=(250, 230, 170, 255))
    return img


def portrait_frame(size=192):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rgba = np.asarray(img, np.float32).copy()
    yy, xx = np.mgrid[0:size, 0:size]
    m = np.maximum(np.abs(xx - size / 2), np.abs(yy - size / 2))
    border = (m > size / 2 - 14) & (m < size / 2 - 2)
    t = (m - (size / 2 - 14)) / 12
    rgba[border, :3] = metal(t[border])
    rgba[border, 3] = 255
    img = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([14, 14, size - 15, size - 15], outline=(40, 30, 14, 255), width=2)
    return img


def emblem(size=192):
    """Znak uprostřed akční lišty: zlatý kruh s modrým drahokamem a stylizovaným V (Valorie)."""
    rgba = np.zeros((size, size, 4), np.float32)
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size]
    r = np.hypot(xx - c, yy - c)
    gem = r < size * 0.36
    t = np.clip(1 - r / (size * 0.36), 0, 1)
    rgba[gem, :3] = (np.array([20, 50, 120]) + np.array([90, 150, 235]) * (t[gem] ** 1.5)[:, None])
    rgba[gem, 3] = 255
    ring(size, size * 0.36, size * 0.47, rgba)
    img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(CINZEL, int(size * 0.42))
    tw = d.textlength("V", font=font)
    d.text((c - tw / 2, c - size * 0.27), "V", font=font, fill=(250, 232, 180, 255))
    return img


def bar_frame(w=256, h=48):
    """9-slice rámeček ukazatele HP / MP."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([1, 1, w - 2, h - 2], 8, fill=(8, 8, 12, 230), outline=(212, 166, 82, 255), width=3)
    d.rounded_rectangle([6, 6, w - 7, h - 7], 5, outline=(90, 64, 28, 255), width=1)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    compass().save(OUT / "compass_ring.png")
    panel().save(OUT / "panel_ornate.png")
    panel(fill=(10, 14, 22, 150)).save(OUT / "panel_ornate_light.png")
    portrait_frame().save(OUT / "portrait_frame.png")
    emblem().save(OUT / "emblem.png")
    bar_frame().save(OUT / "bar_frame.png")
    print("HUD:", ", ".join(p.name for p in sorted(OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
