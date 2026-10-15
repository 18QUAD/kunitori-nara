"""Verify fine raster precision, topology and complete uniform coverage."""
import json
import unittest
from PIL import Image
from build_uniform_tiles import mask, OUT
from build_map_tiles import stamp


class UniformTilesTest(unittest.TestCase):
    def test_holes_and_overlaps(self):
        outer = [[0,0],[1,0],[1,1],[0,1],[0,0]]
        hole = [[.4,.4],[.6,.4],[.6,.6],[.4,.6],[.4,.4]]
        other = [[.45,.45],[.55,.45],[.55,.55],[.45,.55],[.45,.45]]
        result = mask([[outer,hole],[other]],0,1,size=100,ppd=100)
        self.assertEqual(result.getpixel((42,50)),0)
        self.assertEqual(result.getpixel((50,50)),255)
        self.assertEqual(result.getpixel((25,25)),255)

    def test_urban_mesh_edges_do_not_blur(self):
        src = Image.new('RGBA',(2,2));src.putpixel((0,0),(255,255,255,255))
        dst = Image.new('RGBA',(256,256))
        stamp(dst,src,dict(west=0,east=1,north=1,south=0),0,1,256,resampling=Image.Resampling.NEAREST)
        self.assertEqual(dst.getpixel((127,30))[3],255)
        self.assertEqual(dst.getpixel((128,30))[3],0)

    def test_nara_detail_pixels_are_preserved(self):
        from PIL import ImageChops
        original = OUT.parent/'map_tiles_v2/6_252_216_detail.png'
        with Image.open(original) as src, Image.open(OUT/'6_252_216_detail.webp') as dst:
            a, b = src.convert('RGBA'), dst.convert('RGBA')
            # Fully transparent RGB values do not affect rendering and may be
            # normalized by WebP; compare premultiplied visible color and alpha.
            for left, right in zip(a.split(), b.split()):
                diff = ImageChops.difference(left,right)
                diff = ImageChops.multiply(diff,a.getchannel('A'))
                self.assertIsNone(diff.getbbox())

    def test_all_prefectures_have_the_same_fine_resolution(self):
        manifest = json.loads((OUT/'index.json').read_text())
        report = json.loads((OUT/'import_report.json').read_text())
        ids = {f'{i:02d}' for i in range(1,48)}
        self.assertEqual(set(manifest['detailLevels']),ids)
        self.assertEqual(set(manifest['detailLevels'].values()),{6})
        self.assertEqual(set(manifest['prefectureCoverage']),ids)
        self.assertTrue(all(manifest['prefectureCoverage'].values()))
        self.assertEqual(manifest['layerMaxLevels'],{'shade':5,'detail':6,'overview':4})
        self.assertFalse(any(k.startswith('6_') and k.endswith('_shade') for k in manifest['tiles']))
        self.assertEqual(report['zoom'],11)
        self.assertEqual(report['detailPixelsPerDegree'],4096)
        self.assertTrue(all((OUT/f'{key}.webp').is_file() for key in manifest['tiles']))
        # Lossless WebP also preserves fully transparent lake islands.
        for key in list(manifest['tiles'])[::400]:
            with Image.open(OUT/f'{key}.webp') as tile:
                self.assertEqual(tile.size,(256,256))
                self.assertEqual(tile.format,'WEBP')


if __name__ == '__main__':
    unittest.main()
