import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import valoria_assets


class ValoriaAssetsTest(unittest.TestCase):
    def test_generated_models_are_valid_glb_with_meshes(self):
        with tempfile.TemporaryDirectory() as tmp:
            original = valoria_assets.OUT
            try:
                valoria_assets.OUT = Path(tmp)
                valoria_assets.generate()
            finally:
                valoria_assets.OUT = original

            paths = sorted(Path(tmp).glob("*.glb"))
            self.assertEqual(
                [path.stem for path in paths],
                ["hero", "keep", "keep_floor", "keep_step", "paving"],
            )
            for path in paths:
                with self.subTest(model=path.name):
                    data = path.read_bytes()
                    magic, version, length = struct.unpack_from("<4sII", data)
                    self.assertEqual((magic, version, length), (b"glTF", 2, len(data)))
                    json_length, chunk_type = struct.unpack_from("<I4s", data, 12)
                    self.assertEqual(chunk_type, b"JSON")
                    document = json.loads(data[20:20 + json_length])
                    self.assertTrue(document["meshes"])
                    self.assertTrue(document["materials"])
                    if path.stem == "paving":
                        position = document["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
                        bounds = document["accessors"][position]
                        for actual, expected in zip(bounds["min"], (-1.0, -0.18, -1.0)):
                            self.assertAlmostEqual(actual, expected)
                        for actual, expected in zip(bounds["max"], (1.0, 0.02, 1.0)):
                            self.assertAlmostEqual(actual, expected)
                    if path.stem == "keep":
                        self.assertTrue({"castle masonry", "blue slate", "dark glass", "wood", "aged gold"}
                                        <= {m["name"] for m in document["materials"]})
                    if path.stem == "keep_floor":
                        position = document["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
                        bounds = document["accessors"][position]
                        for actual, expected in zip(bounds["min"], (-15.5, -0.18, -10.0)):
                            self.assertAlmostEqual(actual, expected)
                        for actual, expected in zip(bounds["max"], (15.5, 0.02, 12.0)):
                            self.assertAlmostEqual(actual, expected)
                    for material in document["materials"]:
                        if material["name"] in ("weathered stone", "weathered plaster", "castle masonry"):
                            self.assertIn("baseColorTexture", material["pbrMetallicRoughness"])
                            self.assertIn("normalTexture", material)
                            self.assertIn("metallicRoughnessTexture", material["pbrMetallicRoughness"])
                            self.assertIn("occlusionTexture", material)


if __name__ == "__main__":
    unittest.main()
