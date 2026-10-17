import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
from PIL import Image
from shapely.geometry import LineString, Point
from build_border_tiles import joined, outlines, raster, merge_tile


class BorderTilesTest(unittest.TestCase):
    def test_joined_gameplay_town_has_no_internal_chome_border(self):
        parts = [
            [[[0, 0], [.5, 0], [.5, 1], [0, 1], [0, 0]]],
            [[[.5, 0], [1, 0], [1, 1], [.5, 1], [.5, 0]]],
        ]
        lines = outlines(joined(parts))
        self.assertEqual(len(lines), 1)
        self.assertGreater(lines[0].distance(Point(.5, .5)), .4)

    def test_census_holes_do_not_become_display_borders(self):
        parts = [[
            [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]],
            [[.4, .4], [.6, .4], [.6, .6], [.4, .6], [.4, .4]],
        ]]
        lines = outlines(joined(parts))
        self.assertEqual(len(lines), 1)
        self.assertGreater(lines[0].distance(Point(.4, .5)), .3)

    def test_raster_edges_join_without_a_tile_seam(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            raster([LineString([(123.5, 47), (124.5, 47)])], 'town', 0, folder)
            with Image.open(folder / '0_0_0_town.webp') as left, Image.open(folder / '0_1_0_town.webp') as right:
                a, b = left.getchannel('A'), right.getchannel('A')
                self.assertEqual([a.getpixel((255, y)) for y in range(256)],
                                 [b.getpixel((0, y)) for y in range(256)])
                self.assertGreater(max(a.getpixel((255, y)) for y in range(256)), 0)

    def test_packed_tiles_keep_resolution_and_continuous_alpha(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            raster([LineString([(123.5, 47), (124.5, 47)])], 'town', 0, folder)
            with patch('build_border_tiles.OUT', folder):
                merge_tile(('-1_0_0_town.webp', [folder / '0_0_0_town.webp', folder / '0_1_0_town.webp']))
            with Image.open(folder / '-1_0_0_town.webp') as packed:
                self.assertEqual(packed.size, (512, 512))
                alpha = packed.getchannel('A')
                self.assertEqual([alpha.getpixel((255, y)) for y in range(512)],
                                 [alpha.getpixel((256, y)) for y in range(512)])
                self.assertTrue(all(value % 17 == 0 for value in alpha.tobytes()))

    def test_finest_town_edges_preserve_subpixel_position(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            raster([LineString([(135.8, 34.6), (135.81, 34.61)])], 'town', 7, folder)
            sources = list(folder.glob('7_*_town.webp'))
            self.assertTrue(sources)
            first = sources[0].stem.split('_')
            x, y = int(first[1]) // 2, int(first[2]) // 2
            group = [p for p in sources if int(p.stem.split('_')[1]) // 2 == x
                     and int(p.stem.split('_')[2]) // 2 == y]
            name = f'6_{x}_{y}_town.webp'
            with patch('build_border_tiles.OUT', folder):
                merge_tile((name, group))
            with Image.open(folder / name) as image:
                alpha = image.getchannel('A')
                self.assertTrue(set(alpha.tobytes()) <= {0, 85, 170, 255})
                self.assertTrue(set(alpha.tobytes()) & {85, 170})
                ppd = 8192
                west, north = 120 + x / 16, 48 - y / 16
                # The line is lon - lat = 101.2. Quantizing alpha does not
                # move its geometry, even along a diagonal at the finest LOD.
                for py in range(512):
                    for px in range(512):
                        if alpha.getpixel((px, py)):
                            lon = west + (px + .5) / ppd
                            lat = north - (py + .5) / ppd
                            self.assertLess(abs(lon - lat - 101.2) * ppd, 3)


if __name__ == '__main__':
    unittest.main()
