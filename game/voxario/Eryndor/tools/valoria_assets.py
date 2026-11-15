#!/usr/bin/env python3
"""Reconstruct the first modular Valoria buildings from the previous session."""
import math
from pathlib import Path

from meshkit import Mesh, box, cone, cylinder, merge, sphere, write_glb

ASSETS = Path(__file__).resolve().parent.parent / "Assets"
OUT = ASSETS / "Models" / "valoria"

# fotorealistické PBR materiály z fotoskenů Poly Haven (CC0) – tools/valoria_pbr.py; uv_scale = skutečná velikost
# dlaždice fotoskenu v metrech, ať kvádry, dlažba i tašky mají reálnou velikost
PBR = ASSETS / "Textures/valoria/pbr"


def pbr(name, label, tile, **extra):
    return dict(name=label, texture=str(PBR / f"{name}_basecolor.jpg"), normal=str(PBR / f"{name}_normal.jpg"),
                orm=str(PBR / f"{name}_orm.jpg"), uv_scale=tile, roughness=1.0, **extra)


STONE = pbr("stone", "weathered stone", 2.5)            # brána, most, sokly domů
CASTLE_STONE = pbr("castle", "castle masonry", 2.0)     # kvádrové zdivo hradu
COBBLE = pbr("cobble", "cobblestone paving", 2.0)       # dlažba a podlaha hradu
PLASTER = pbr("plaster", "weathered plaster", 1.0)      # vápenná omítka
WOOD = pbr("timber", "wood", 2.0)                       # trámy hrázděných domů, dveře
BLUE = pbr("slate", "blue slate", 3.0)                  # břidlicové střechy
RED = pbr("clay", "red tile", 4.0)                      # pálené tašky
CLOTH = pbr("linen", "blue cloth", 0.27, double=True)    # markýzy a prapory
MARBLE = pbr("marble", "weathered marble", 1.8)         # (dříve sochy hrdinů)
LIME = pbr("limestone", "sandstone", 2.0)              # podstavce soch
GOLD = dict(name="aged gold", color=(0.53, 0.37, 0.14), roughness=0.4, metallic=0.75)
GLASS = dict(name="dark glass", color=(0.05, 0.09, 0.12), roughness=0.25, metallic=0.05)


def b(x, y, z, sx, sy, sz):
    return box(sx, sy, sz, center=(x, y, z))


def tower(x, z, height, radius):
    return cylinder(radius, radius * 0.88, height, 16).translate(x, 0, z)


def roof(x, y, z, radius, height):
    return cone(radius, height, 16).translate(x, y, z)


def gable(z):
    points = [[-6, 7, z], [6, 7, z], [0, 9.95, z]]
    indices = [[0, 2, 1]] if z < 0 else [[0, 1, 2]]
    return Mesh(points, indices)


def generate():
    OUT.mkdir(parents=True, exist_ok=True)

    def save(name, parts):
        write_glb(str(OUT / (name + ".glb")), parts, name=name)

    # Most hrdinů, stará brána a domy nahradila stavebnice Valorie Harbor (tools/valoria_city.py)
    save("paving", [(b(0, -0.08, 0, 2, 0.2, 2), COBBLE)])

    # socha hrdiny: stupňovitý podstavec z pískovce, rytíř v plášti s mečem a štítem (bílý kámen)
    base = [b(0, 0.35, 0, 4.4, 0.7, 4.4), b(0, 1.05, 0, 3.8, 0.7, 3.8), b(0, 2.0, 0, 3.0, 1.2, 3.0),
            b(0, 2.75, 0, 3.4, 0.3, 3.4)]
    fig = [cylinder(0.32, 0.26, 2.0, 12).translate(-0.4, 3.9, 0), cylinder(0.32, 0.26, 2.0, 12).translate(0.4, 3.9, 0),
           b(-0.4, 3.0, 0.12, 0.5, 0.25, 0.8), b(0.4, 3.0, 0.12, 0.5, 0.25, 0.8),
           cylinder(0.75, 0.62, 2.0, 16).translate(0, 5.6, 0),              # trup v kroužkové zbroji
           cylinder(0.8, 0.8, 0.25, 16).translate(0, 4.75, 0),              # opasek
           cone(1.15, 3.6, 16).translate(0, 3.2, -0.25).scale(1, 1, 0.55),  # plášť
           sphere(0.42, 16, 12).scale(1, 0.85, 1).translate(-0.95, 6.55, 0), sphere(0.42, 16, 12).scale(1, 0.85, 1).translate(0.95, 6.55, 0),
           cylinder(0.22, 0.2, 1.1, 10).translate(0, 6.95, 0),
           sphere(0.42, 16, 12).scale(1, 1.15, 1).translate(0, 7.55, 0),     # hlava
           cylinder(0.24, 0.2, 1.6, 10).rotate(0, 0, 25).translate(1.15, 5.85, 0.2),     # pravá paže
           cylinder(0.24, 0.2, 1.6, 10).rotate(0, 0, -20).translate(-1.15, 5.9, 0.3),    # levá paže
           cylinder(0.85, 0.85, 0.14, 20).rotate(90, 0, 0).translate(-1.35, 5.3, 0.55),  # štít
           b(1.45, 6.6, 0.25, 0.1, 3.2, 0.22), b(1.45, 5.05, 0.25, 0.8, 0.12, 0.25)]    # meč vztyčený, záštita
    save("hero", [(merge(*base), LIME), (merge(*fig), dict(PLASTER, color=(0.93, 0.93, 0.9), name="statue stone"))])

    keep = [b(0, 8, -11, 35, 16, 2),
            b(-16.5, 8, 0, 2, 16, 20), b(16.5, 8, 0, 2, 16, 20),
            b(-9.85, 8, 11, 15.3, 16, 2), b(9.85, 8, 11, 15.3, 16, 2),
            b(0, 11.2, 11, 4.4, 9.6, 2),
            b(0, 15.5, 0, 36, 1, 25)]
    spires, slits, door, trim, pennants = [], [], [], [], []
    for z in (-12.3, 12.3):
        for x in range(-15, 16, 3):
            keep.append(b(x, 17.0, z, 1.5, 2.0, 1.2))
        for x in (-12, -6, 6, 12):
            for y in (5, 10.5):
                slits.append(b(x, y, z, 1.0, 2.7, 0.2))
                trim.extend([b(x + dx, y, z, 0.3, 3.2, 0.35) for dx in (-0.68, 0.68)])
                trim.append(b(x, y + 1.55, z, 1.65, 0.3, 0.35))
    for x in (-17.8, 17.8):
        for z in range(-9, 10, 3):
            keep.append(b(x, 17.0, z, 1.2, 2.0, 1.5))
        for z in (-8, 0, 8):
            for y in (5, 10.5):
                slits.append(b(x, y, z, 0.2, 2.7, 1.0))
                trim.extend([b(x, y, z + dz, 0.35, 3.2, 0.3) for dz in (-0.68, 0.68)])
                trim.append(b(x, y + 1.55, z, 0.35, 0.3, 1.65))
    for side in (-1, 1):
        x = side * 2.58
        door.append(b(x, 3, 10.9, 0.25, 6.0, 2.2))
        door.extend([b(x - side * 0.14, 3, z, 0.08, 5.8, 0.12) for z in (10.15, 10.9, 11.65)])
        door.extend([b(x - side * 0.14, y, 10.9, 0.08, 0.18, 2.2) for y in (1, 3, 5)])
    for x in (-2.25, 2.25):
        trim.append(b(x, 3.2, 12.5, 0.5, 6.4, 0.55))
    for i in range(13):
        angle = math.pi * i / 12
        x, y = 2.25 * math.cos(angle), 6.4 + 2.25 * math.sin(angle)
        trim.append(box(0.7, 0.55, 0.55).rotate(0, 0, -math.degrees(angle)).translate(x, y, 12.5))
    for x, z, height in ((-18, -12, 32), (18, -12, 32), (-18, 12, 27),
                         (18, 12, 27), (0, 0, 42)):
        keep.append(tower(x, z, height, 4.5))
        keep.append(cylinder(4.9, 4.9, 0.8, 24).translate(x, height - 2, z))
        keep.append(cylinder(4.75, 4.75, 0.6, 24).translate(x, 3, z))
        for y in (9, 17):
            slits.append(b(x, y, z + 4.5 - 0.54 * y / height + 0.03, 0.65, 2.4, 0.18))
        spires.append(roof(x, height, z, 5.2, 12))
        pennants.append(sphere(0.35, 12, 8).translate(x, height + 12, z))
    floor = merge(b(0, -0.08, 0, 31, 0.2, 20), b(0, -0.08, 11, 4.4, 0.2, 2))
    save("keep_floor", [(floor, COBBLE)])
    save("keep_step", [(b(0, -0.08, 0, 4.0, 0.2, 2), COBBLE)])
    save("keep", [(merge(*keep, *trim), CASTLE_STONE), (merge(*spires), BLUE),
                  (merge(*slits), GLASS), (merge(*door), WOOD), (merge(*pennants), GOLD)])


if __name__ == "__main__":
    generate()
