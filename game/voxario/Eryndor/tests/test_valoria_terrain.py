import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import valoria_terrain


class ValoriaTerrainTest(unittest.TestCase):
    def test_city_plateau_keep_harbor_and_unchanged_ocean(self):
        x = np.array([2950.0, 3000.0, 2650.0, 0.0, 3000.0])
        z = np.array([2400.0, 2165.0, 2530.0, 0.0, 2400.0])
        original = np.full(5, -40.0)
        height, mask = valoria_terrain.apply(original, x, z)
        self.assertAlmostEqual(height[0], valoria_terrain.PLATEAU_Y, delta=1.0)    # plošina města
        self.assertAlmostEqual(height[1], valoria_terrain.KEEP_Y, delta=1.0)       # hradní skála
        self.assertAlmostEqual(height[2], valoria_terrain.HARBOR_Y, delta=0.3)     # přístavní terasa
        self.assertEqual(height[3], original[3])
        self.assertEqual(mask[3], 0.0)

    def test_island_footprint_and_cliffs(self):
        x, z = np.meshgrid(np.arange(2200.0, 3801.0, 10.0), np.arange(1550.0, 3251.0, 10.0))
        original = np.full_like(x, -40.0)
        height, mask = valoria_terrain.apply(original, x, z)
        radius = np.hypot((x - 3000) / 600, (z - 2400) / 700)
        self.assertTrue(np.all(mask[radius >= 1.0] == 0))
        self.assertTrue(np.array_equal(height[radius >= 1.0], original[radius >= 1.0]))
        pr = valoria_terrain.plateau_radius(x - 3000, z - 2400)
        flat = pr < 0.9
        self.assertLess(np.ptp(height[flat & (np.hypot((x - 3000) / 150, (z - 2165) / 115) > 1.1)]), 2.0)
        # útes pod branou: na 30 m víc než 30 m převýšení
        self.assertGreater(height[(abs(x - 2720) < 1) & (abs(z - 2400) < 1)][0] -
                           height[(abs(x - 2690) < 1) & (abs(z - 2500) < 1)][0], 30.0)

    def test_surface_weights(self):
        h = np.array([2.0, 12.0, 20.0, -1.0])
        slope = np.array([0.1, 0.1, 0.8, 0.1])
        weights = np.array(valoria_terrain.surface_weights(h, slope, np.full(4, 0.5)))
        np.testing.assert_allclose(weights.sum(axis=0), 1.0)
        self.assertTrue(np.all(weights >= 0))
        self.assertGreater(weights[2, 0], 0.5)
        self.assertGreater(weights[0, 1], 0.5)
        self.assertGreater(weights[3, 2], 0.9)
        self.assertEqual(weights[2, 3], 1)


if __name__ == "__main__":
    unittest.main()
