"""Ostrov Valorie (startovní město) pro generátor Aethelgardu – podle předlohy „Valorie Harbor“.

Pobřeží zůstává stejné (elipsa 600 x 700 m kolem 3000, 2400). Uvnitř:
  * plošina města ve výšce 50 m obehnaná skalními útesy (město na skále nad mořem)
  * hradní skála na severu (62 m) – Královský hrad s věžemi
  * pod útesy nižší skalnaté svahy k moři
  * na západě pod branou přístavní terasa těsně nad hladinou (mola, lodě); hned za ní hluboká voda
"""
import numpy as np

CENTER_X = 3000.0
CENTER_Z = 2400.0
PLATEAU_Y = 50.0
KEEP_Y = 62.0
HARBOR_Y = 2.4
# plošina: poloosy (m) a posun středu – okraj na západě v x ≈ 2700 (brána VALORIE)
PLATEAU_RX, PLATEAU_RZ, PLATEAU_DZ = 300.0, 400.0, -20.0
# přístavní terasa (světové souřadnice): pod branou, jižně od obloukového mostu
HARBOR = (2605.0, 2690.0, 2430.0, 2640.0)


def _smoothstep(a, b, value):
    t = np.clip((value - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def coast(dx, dz):
    """Normalizovaný poloměr pobřeží a maska ostrova (stejné jako dřív – mapa i pobřeží sedí)."""
    radius = np.sqrt((dx / 600.0) ** 2 + (dz / 700.0) ** 2)
    coast_variation = (0.5 + 0.25 * np.sin(dx / 83.0 + dz / 139.0)
                       + 0.25 * np.sin(dz / 71.0 - dx / 169.0))
    coast_radius = radius + 0.20 * coast_variation * _smoothstep(0.55, 0.85, radius)
    mask = 1.0 - _smoothstep(0.65, 1.0, coast_radius)
    return coast_radius, mask


def plateau_radius(dx, dz):
    rim = 1.0 + 0.045 * np.sin(np.arctan2(dz, dx) * 7.0 + 0.6) + 0.025 * np.sin(np.arctan2(dz, dx) * 13.0)
    return np.sqrt((dx / PLATEAU_RX) ** 2 + ((dz - PLATEAU_DZ) / PLATEAU_RZ) ** 2) / rim


def harbor_mask(x, z):
    x0, x1, z0, z1 = HARBOR
    inside_x = _smoothstep(x0 - 30, x0 + 5, x) * (1 - _smoothstep(x1 - 5, x1 + 12, x))
    inside_z = _smoothstep(z0 - 10, z0 + 10, z) * (1 - _smoothstep(z1 - 10, z1 + 15, z))
    return inside_x * inside_z


def apply(height, x, z):
    dx, dz = x - CENTER_X, z - CENTER_Z
    coast_radius, mask = coast(dx, dz)
    # nižší skalnaté svahy: od paty útesu (~10 m) k pobřeží (2 m), mírné vlnění
    rolling = np.sin(dx / 61.0 + dz / 97.0) + 0.5 * np.sin(dz / 43.0 - dx / 77.0)
    low = (10.0 + 2.5 * rolling) * (1 - _smoothstep(0.55, 0.85, coast_radius)) + 2.0
    # plošina města (téměř rovná – ulice a stavby) s útesy po obvodu
    pr = plateau_radius(dx, dz)
    city = PLATEAU_Y + 0.6 * np.sin(dx / 53.0) * np.sin(dz / 71.0)
    cliff = _smoothstep(0.97, 1.06, pr)
    island = city * (1 - cliff) + low * cliff
    # hradní skála na severu
    keep_radius = np.sqrt((dx / 150.0) ** 2 + ((dz + 235.0) / 115.0) ** 2)
    island = island + (KEEP_Y - PLATEAU_Y) * (1 - _smoothstep(0.55, 1.0, keep_radius)) * (1 - cliff)
    # přístavní terasa pod branou (rovná, kousek nad hladinou)
    hm = harbor_mask(x, z) * _smoothstep(1.0, 1.06, pr)   # útes plošiny zůstane nad terasou
    island = island * (1 - hm) + HARBOR_Y * hm
    return height * (1.0 - mask) + island * mask, mask


def surface_weights(height, slope, noise):
    """Tráva, hlína, písek, skála; součet 1. Útesy skála, přístav a pobřeží písek / hlína."""
    sand = (1.0 - _smoothstep(1.0, 4.0, height)) * (1.0 - _smoothstep(0.35, 0.8, slope))
    rock = _smoothstep(0.30, 0.75, slope) * (1.0 - sand)
    soil = (1.0 - sand - rock) * (0.12 + 0.23 * np.clip(noise, 0.0, 1.0))
    grass = 1.0 - sand - rock - soil
    return grass, soil, sand, rock
