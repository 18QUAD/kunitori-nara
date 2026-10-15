import unittest
import json
from pathlib import Path
from PIL import Image
from shapely.geometry import Point
from restore_nara_water_tiles import water_shapes, nara_scale

ROOT = Path(__file__).resolve().parents[1]

class NaraWaterStyleTest(unittest.TestCase):
    def test_round_river_stroke_preserves_old_map_widths(self):
        dark,blue = water_shapes({'lines':[[[135,34],[135,35]]],'areas':[]},1500)
        self.assertAlmostEqual((dark[0].bounds[2]-dark[0].bounds[0])*.826*1500,.625,places=7)
        self.assertAlmostEqual((blue[0].bounds[2]-blue[0].bounds[0])*.826*1500,.375,places=7)
        self.assertLess(dark[0].bounds[1],34)  # round cap extends past endpoint
        self.assertTrue(dark[0].covers(blue[0]))

    def test_area_outline_keeps_island_holes(self):
        dark,blue = water_shapes({'lines':[], 'areas':[[[[0,0],[2,0],[2,2],[0,2],[0,0]],[[.5,.5],[1.5,.5],[1.5,1.5],[.5,1.5],[.5,.5]]]]},1500)
        self.assertFalse(dark[0].covers(Point(1,1)))
        self.assertFalse(blue[0].covers(Point(1,1)))
        self.assertTrue(dark[0].covers(Point(-.0002,1)))
        self.assertFalse(blue[0].covers(Point(-.0002,1)))

    def test_real_nara_tiles_include_outline_blue_fill_and_finer_images(self):
        folder = ROOT/'assets/data/map_tiles_v2'
        manifest = json.loads((folder/'index.json').read_text())
        scale = nara_scale(json.loads((ROOT/'assets/data/nara.json').read_text()))
        self.assertEqual(manifest['detailLevels']['29'],6)
        self.assertAlmostEqual(manifest['waterStyles']['29']['projectionScale'],scale)
        self.assertEqual(manifest['waterStyles']['29']['outlineMapUnits'],.625)
        self.assertEqual(manifest['waterStyles']['29']['fillMapUnits'],.375)
        files = list(folder.glob('6_*_detail.png'))
        self.assertGreater(len(files),100)
        found_dark = found_blue = False
        for path in files:
            with Image.open(path) as im:
                for r,g,b,a in im.convert('RGBA').getdata():
                    found_dark |= r<60 and g<120 and b<160 and a>12
                    found_blue |= g-r>50 and b-g<80 and a>128
            if found_dark and found_blue: break
        self.assertTrue(found_dark,'lost dark blue water outline')
        self.assertTrue(found_blue,'lost light blue water fill')

if __name__=='__main__': unittest.main()
