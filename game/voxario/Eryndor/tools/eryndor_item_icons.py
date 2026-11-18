#!/usr/bin/env python3
"""Ikony předmětů inventáře (profese, rybolov, mount, mazlíček, trofeje událostí).

Fotorealistické (výchozí pro hru): 3D modely předmětů (tools/eryndor_icon_models.py) vyfotí engine ve studiu
(samotest „ikony“ v main.lua) a tento skript je ořeže a zarámuje:
  VOXARIO_SELFTEST_ONLY=ikony VoxarioPlayer . --selftest <složka>
  python3 tools/eryndor_item_icons.py --from-shots <složka>   -> Assets/UI/icons/i_<id>.png (128 px)
Bez parametru kreslí záložní ikony kódem.

Pozadí a kovový rám jako ikony dovedností (tools/eryndor_icons.py), symbol předmětu se stínem a odleskem.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eryndor_icons import ICONS, S, background, c255  # noqa: E402

# id -> (symbol, barva symbolu, barva pozadí)
ITEMS = {
    "pickaxe": ("pickaxe", (0.6, 0.62, 0.66), (0.55, 0.45, 0.3)),
    "knife": ("knife", (0.85, 0.87, 0.9), (0.6, 0.3, 0.25)),
    "rod": ("rod", (0.55, 0.38, 0.2), (0.3, 0.55, 0.8)),
    "ore_silver": ("ore", (0.88, 0.9, 0.95), (0.45, 0.47, 0.52)),
    "ore_gold": ("ore", (1.0, 0.78, 0.3), (0.55, 0.42, 0.2)),
    "ore_diamond": ("gem", (0.85, 0.96, 1.0), (0.35, 0.5, 0.65)),
    "ore_mithril": ("gem", (0.5, 0.9, 1.0), (0.2, 0.45, 0.6)),
    "herb_mirumilka": ("flower", (0.97, 0.95, 0.9), (0.4, 0.6, 0.3)),
    "herb_stribrolist": ("leafs", (0.75, 0.82, 0.88), (0.35, 0.5, 0.45)),
    "herb_krvavy_trn": ("flower", (0.75, 0.08, 0.1), (0.35, 0.18, 0.15)),
    "herb_mesicni_lilie": ("bell", (0.8, 0.72, 1.0), (0.3, 0.25, 0.5)),
    "herb_ledovy_kvet": ("flower", (0.62, 0.9, 1.0), (0.3, 0.45, 0.6)),
    "hide_wolf": ("hide", (0.45, 0.42, 0.38), (0.4, 0.35, 0.28)),
    "hide_boar": ("hide", (0.32, 0.25, 0.18), (0.45, 0.32, 0.2)),
    "hide_stag": ("hide", (0.55, 0.32, 0.16), (0.5, 0.35, 0.2)),
    "hide_bear": ("hide", (0.28, 0.17, 0.09), (0.45, 0.28, 0.15)),
    "scale_dragon": ("scale", (0.55, 0.85, 1.0), (0.25, 0.4, 0.6)),
    "fish_pstruh": ("fish", (0.7, 0.75, 0.6), (0.25, 0.45, 0.6)),
    "fish_okoun": ("fish", (0.6, 0.7, 0.35), (0.25, 0.45, 0.55)),
    "fish_losos": ("fish", (0.95, 0.55, 0.45), (0.25, 0.4, 0.6)),
    "fish_stika": ("fish", (0.65, 0.85, 0.95), (0.25, 0.4, 0.65)),
    "fish_ohnivy": ("fish", (1.0, 0.45, 0.15), (0.5, 0.2, 0.1)),
    "fish_kapr": ("fish", (0.85, 0.8, 1.0), (0.3, 0.3, 0.6)),
    "horse": ("horseshoe", (0.75, 0.75, 0.78), (0.55, 0.4, 0.25)),
    "wolf_pet": ("paw", (0.85, 0.85, 0.9), (0.35, 0.4, 0.55)),
    "feather_angel": ("feather", (1.0, 0.97, 0.88), (0.85, 0.7, 0.35)),
    "horn_demon": ("horn", (0.2, 0.12, 0.1), (0.7, 0.15, 0.1)),
    "meteor_shard": ("gem", (1.0, 0.5, 0.2), (0.4, 0.15, 0.08)),
}


def glyph(kind, col, seed):
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    C = c255(col)
    L = c255(col, 1.35)
    D = c255(col, 0.55)
    c = S / 2
    rnd = random.Random(seed)
    if kind == "pickaxe":
        d.line((34, 100, 88, 36), fill=(120, 80, 45, 255), width=9)
        d.arc((20, 14, 112, 86), 200, 340, fill=C, width=13)
        d.arc((22, 17, 110, 84), 210, 330, fill=L, width=3)
    elif kind == "knife":
        d.polygon([(40, 92), (92, 30), (100, 36), (54, 98)], fill=C)
        d.line((44, 92, 94, 33), fill=L, width=2)
        d.line((28, 108, 50, 88), fill=(90, 55, 30, 255), width=12)
    elif kind == "rod":
        d.line((26, 108, 104, 18), fill=C, width=6)
        d.line((104, 18, 108, 70), fill=(230, 230, 230, 200), width=1)
        d.ellipse((102, 66, 114, 78), fill=(200, 40, 30, 255))
        d.ellipse((38, 86, 54, 102), fill=(190, 160, 90, 255))
    elif kind == "ore":
        pts = [(30, 80), (40, 44), (64, 32), (92, 42), (100, 74), (78, 98), (46, 98)]
        d.polygon(pts, fill=(78, 74, 70, 255))
        for _ in range(9):
            x, y, r = rnd.uniform(42, 88), rnd.uniform(44, 88), rnd.uniform(4, 9)
            d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=C)
            d.ellipse((x - r * 0.5, y - r * 0.6, x, y - r * 0.1), fill=L)
    elif kind == "gem":
        top = [(36, 52), (52, 34), (76, 34), (92, 52)]
        d.polygon([top[0], top[1], top[2], top[3], (64, 100)], fill=C)
        d.polygon([top[0], top[1], (64, 52)], fill=L)
        d.polygon([top[2], top[3], (64, 52)], fill=D)
        d.polygon([(36, 52), (64, 52), (64, 100)], fill=c255(col, 1.15))
        d.line((36, 52, 92, 52), fill=L, width=2)
    elif kind in ("flower", "bell", "leafs"):
        d.line((64, 110, 64, 58), fill=(70, 120, 50, 255), width=5)
        d.ellipse((38, 84, 64, 96), fill=(80, 140, 60, 255))
        d.ellipse((64, 76, 92, 88), fill=(80, 140, 60, 255))
        if kind == "flower":
            for k in range(7):
                a = k / 7 * math.tau
                x, y = 64 + math.cos(a) * 18, 46 + math.sin(a) * 18
                d.ellipse((x - 12, y - 12, x + 12, y + 12), fill=C)
            d.ellipse((54, 36, 74, 56), fill=(240, 200, 60, 255))
        elif kind == "bell":
            d.chord((40, 26, 88, 78), 180, 360, fill=C)
            d.polygon([(40, 52), (88, 52), (96, 66), (32, 66)], fill=C)
            d.ellipse((58, 60, 70, 72), fill=(255, 245, 190, 255))
        else:
            for k, a in enumerate((-50, -20, 10, 40)):
                x = 64 + math.sin(math.radians(a)) * 26
                y = 44 - math.cos(math.radians(a)) * 6
                d.ellipse((x - 10, y - 22, x + 10, y + 22), fill=C if k % 2 else L)
    elif kind == "hide":
        pts = [(34, 40), (50, 30), (64, 38), (78, 30), (94, 40), (90, 64), (100, 92), (78, 86), (64, 102), (50, 86), (28, 92), (38, 64)]
        d.polygon(pts, fill=C)
        for _ in range(60):
            x, y = rnd.uniform(40, 88), rnd.uniform(40, 92)
            d.line((x, y, x + rnd.uniform(-3, 3), y + 4), fill=D, width=1)
        d.polygon([(46, 44), (64, 44), (64, 60)], fill=L)
    elif kind == "scale":
        for k in range(3):
            y = 38 + k * 22
            for j in range(3 - (k % 2)):
                x = 40 + j * 24 + (k % 2) * 12
                d.chord((x - 14, y - 14, x + 14, y + 22), 0, 180, fill=C)
                d.arc((x - 14, y - 14, x + 14, y + 22), 0, 180, fill=L, width=2)
    elif kind == "fish":
        d.ellipse((26, 46, 94, 84), fill=C)
        d.polygon([(90, 64), (112, 44), (112, 84)], fill=D)
        d.ellipse((34, 56, 44, 66), fill=(250, 250, 250, 255))
        d.ellipse((37, 59, 42, 64), fill=(10, 10, 10, 255))
        d.arc((40, 52, 80, 80), 200, 340, fill=L, width=3)
        d.polygon([(56, 46), (70, 32), (76, 48)], fill=D)
    elif kind == "horseshoe":
        d.arc((28, 26, 100, 106), 140, 400, fill=C, width=16)
        for a in (160, 200, 340, 380):
            x = 64 + math.cos(math.radians(a)) * 28
            y = 66 + math.sin(math.radians(a)) * 32
            d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(40, 40, 40, 255))
    elif kind == "paw":
        d.ellipse((40, 58, 88, 100), fill=C)
        for x, y in ((34, 44), (52, 30), (76, 30), (94, 44)):
            d.ellipse((x - 9, y - 11, x + 9, y + 11), fill=C)
    elif kind == "feather":
        d.line((36, 104, 92, 24), fill=L, width=3)
        for k in range(14):
            t = k / 13
            x, y = 40 + t * 50, 98 - t * 70
            d.line((x, y, x - 22 + t * 10, y - 10), fill=C, width=4)
            d.line((x, y, x + 16 - t * 6, y + 8), fill=C, width=4)
    elif kind == "horn":
        pts = []
        for k in range(20):
            t = k / 19
            pts.append((36 + t * 60 + math.sin(t * 3) * 10, 100 - t * 76))
        for k in range(len(pts) - 1):
            w = int(18 * (1 - k / 20) + 3)
            d.line(pts[k] + pts[k + 1], fill=C, width=w)
        d.line(pts[0] + pts[6], fill=(120, 30, 20, 255), width=3)
    return g


def icon(name, kind, col, bg, seed):
    img = background(bg, seed)
    g = glyph(kind, col, seed)
    glow = g.filter(ImageFilter.GaussianBlur(5))
    tint = Image.new("RGBA", (S, S), c255(col, 1.3, 0))
    tint.putalpha(glow.getchannel("A").point(lambda a: int(a * 0.6)))
    img = Image.alpha_composite(img, tint)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 170), (3, 4), g.getchannel("A"))
    img = Image.alpha_composite(img, shadow)
    img = Image.alpha_composite(img, g)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, S - 1, S - 1), outline=(30, 26, 20, 255), width=6)
    d.rectangle((5, 5, S - 6, S - 6), outline=(150, 120, 70, 255), width=2)
    img.save(os.path.join(ICONS, "i_" + name + ".png"))


def from_shots(folder):
    """Fotorealistické ikony z fotek enginu (samotest „ikony“): čtvercový ořez kolem středu, jemná vinětace,
    kovový rám jako u ikon dovedností."""
    n = 0
    for name in ITEMS:
        f = os.path.join(folder, f"icon-{name}.png")
        if not os.path.exists(f):
            print("chybí foto:", name)
            continue
        im = Image.open(f).convert("RGBA")
        w, h = im.size
        c = int(h * 0.56)
        x0, y0 = (w - c) // 2, int(h * 0.5 - c * 0.5)
        im = im.crop((x0, y0, x0 + c, y0 + c)).resize((S, S), Image.LANCZOS)
        vig = Image.new("L", (S, S), 0)
        px = vig.load()
        for y in range(S):
            for x in range(S):
                r = math.hypot(x - S / 2, y - S / 2) / (S * 0.72)
                px[x, y] = int(max(0, min(1, r * r)) * 150)
        im = Image.alpha_composite(im, Image.merge("RGBA", (Image.new("L", (S, S), 0),) * 3 + (vig,)))
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, S - 1, S - 1), outline=(30, 26, 20, 255), width=6)
        d.rectangle((5, 5, S - 6, S - 6), outline=(150, 120, 70, 255), width=2)
        im.save(os.path.join(ICONS, "i_" + name + ".png"))
        n += 1
    print("fotorealistické ikony:", n)


def main():
    if "--from-shots" in sys.argv:
        from_shots(sys.argv[sys.argv.index("--from-shots") + 1])
        return
    os.makedirs(ICONS, exist_ok=True)
    for i, (name, (kind, col, bg)) in enumerate(sorted(ITEMS.items())):
        icon(name, kind, col, bg, i * 17 + 3)
    print("ikony předmětů:", len(ITEMS))


if __name__ == "__main__":
    main()
