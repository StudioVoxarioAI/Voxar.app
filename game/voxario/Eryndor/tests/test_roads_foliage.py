"""Cesty napříč Aethelgardem (tools/eryndor_roads.py) a fotorealistická vegetace (tools/eryndor_foliage.py)."""
import json
import math
import re
import struct
import sys
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import eryndor_roads as roads  # noqa: E402

ASSETS = ROOT / "Assets"


def glb_json(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert (magic, version, length) == (b"glTF", 2, len(data))
    n, _ = struct.unpack_from("<I4s", data, 12)
    return json.loads(data[20:20 + n])


def parse_roads():
    text = (ASSETS / "Scripts" / "eryndor" / "roads_data.lua").read_text(encoding="utf-8")
    out = []
    for block in text.split("{ name = ")[1:]:
        name = re.match(r'"([^"]+)"', block)[1]
        seg_text, bridge_text = block.split("lava_bridges = {")
        segments = []
        for seg in seg_text.split("segments = {", 1)[1].split("        {\n")[1:]:
            pts = [(float(x), float(z)) for x, z in re.findall(r"\{ ([-\d.]+), ([-\d.]+) \}", seg)]
            if pts:
                segments.append(pts)
        bridges = [tuple(map(float, b)) for b in
                   re.findall(r"\{ ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+) \}", bridge_text.split("}", 1)[0] + "}")]
        width = float(re.search(r"width = ([\d.]+)", block)[1])
        out.append(dict(name=name, segments=segments, bridges=bridges, width=width))
    return out


class RoadsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roads = parse_roads()
        cls.poi, cls.lake, cls.bridges, cls.regions, cls.landing = roads.world_data()

    def test_network(self):
        names = [r["name"] for r in self.roads]
        self.assertEqual(names[:2], ["Královská cesta", "Cesta k zamrzlému jezeru"])
        self.assertGreaterEqual(len(self.roads), 5)
        total = sum(np.linalg.norm(np.diff(np.array(s), axis=0), axis=1).sum() for r in self.roads for s in r["segments"])
        self.assertGreater(total, 12000)

    def test_royal_road_links_valoria_bridge_and_outpost(self):
        royal = self.roads[0]
        first, last = royal["segments"][0][0], royal["segments"][-1][-1]
        self.assertLess(math.dist(first, self.landing), 40, "road must start at the arched bridge from Valoria")
        self.assertLess(math.dist(last, self.poi["Start"]), 70, "road must reach the outpost")
        self.assertEqual(len(royal["bridges"]), 1, "royal road crosses the lava river on one stone bridge")
        self.assertTrue((ASSETS / "Models" / "roads" / "lava_bridge_0.glb").exists())

    def test_lake_road_reaches_frozen_lake(self):
        lx, lz, rx, rz = self.lake
        end = self.roads[1]["segments"][-1][-1]
        # na jižním břehu: kousek za okrajem elipsy jezera
        e = ((end[0] - lx) / rx) ** 2 + ((end[1] - lz) / rz) ** 2
        self.assertLess(e, 2.5)
        self.assertLess(math.dist(self.roads[1]["segments"][0][0], self.poi["Start"]), 70)
        # všechny cesty začínají / končí na společném rozcestí u základny
        ends = [self.roads[0]["segments"][-1][-1]] + [r["segments"][0][0] for r in self.roads[1:]]
        for e in ends:
            self.assertLess(math.dist(e, ends[0]), 12)

    def test_roads_stay_on_land_except_river_bridges(self):
        for r in self.roads:
            for seg in r["segments"]:
                pts = np.array(seg)
                h = roads.terrain_at(pts[:, 0], pts[:, 1])
                wet = h < 0.4
                for (x, z) in pts[wet]:
                    near = min(math.hypot(x - b[0], z - b[1]) - b[3] / 2 for b in self.bridges)
                    self.assertLess(near, 30, f"{r['name']} enters water away from a bridge at {x:.0f},{z:.0f}")

    def test_grass_cleared_on_roads(self):
        s0 = np.asarray(Image.open(ASSETS / "Terrain" / "aethelgard_splat0.png").convert("RGBA"), np.float32)
        s1 = np.asarray(Image.open(ASSETS / "Terrain" / "aethelgard_splat1.png").convert("RGBA"), np.float32)
        n = s0.shape[0]
        for r in self.roads:
            seg = r["segments"][0]
            for x, z in seg[5:-5:7]:
                c, row = int((x + 4096) / 8192 * n), int((z + 4096) / 8192 * n)
                total = s0[row, c].sum() + s1[row, c].sum()
                self.assertGreater(s0[row, c, 1] / total, 0.6, f"{r['name']}: road is not soil at {x:.0f},{z:.0f}")


class FoliageTest(unittest.TestCase):
    def test_foliage_models_use_alpha_cards(self):
        nat = ASSETS / "Models" / "nature"
        for name in ["grass_clump_0", "grass_clump_1", "grass_clump_2", "tree_0", "tree_1", "tree_2",
                     "pine_0", "pine_1", "pine_2"]:
            with self.subTest(model=name):
                doc = glb_json(nat / f"{name}.glb")
                foliage = [m for m in doc["materials"] if m["name"].startswith("foliage")]
                self.assertEqual(len(foliage), 1)
                self.assertEqual(foliage[0]["alphaMode"], "MASK")
                self.assertTrue(foliage[0]["doubleSided"])
                prim = doc["meshes"][0]["primitives"]
                self.assertTrue(all("TEXCOORD_0" in p["attributes"] for p in prim))

    def test_atlases_have_transparency(self):
        for name in ["grass_clumps", "leaf_twigs", "fir_twigs"]:
            a = np.asarray(Image.open(ASSETS / "Textures" / "nature" / "foliage" / f"{name}.png").getchannel("A"))
            cover = (a > 128).mean()
            self.assertGreater(cover, 0.05)
            self.assertLess(cover, 0.8)

    def test_world_uses_grass_and_roads(self):
        lua = (ASSETS / "Scripts" / "eryndor" / "world.lua").read_text(encoding="utf-8")
        self.assertIn("W.grass({", lua)
        self.assertIn("W.road({", lua)
        self.assertIn('style = "realistic"', lua)


if __name__ == "__main__":
    unittest.main()
