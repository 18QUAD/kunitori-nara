import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image, ImageDraw
import contrast_border_tiles as borders


class ContrastBordersTest(unittest.TestCase):
    def test_thin_white_only_and_seam_match(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for x in [0, 1]:
                image = Image.new('RGBA', (512, 512), (255, 255, 255, 0))
                draw = ImageDraw.Draw(image)
                draw.line([(0, 64), (511, 64)], fill=(255, 255, 255, 196))
                image.save(root / f'0_{x}_0_pref.webp', lossless=True)
            keys = ['0_0_0_pref', '0_1_0_pref']
            with patch.object(borders, 'SOURCE', root), patch.object(borders, 'OUT', root):
                borders.source_alpha.cache_clear()
                borders.initialize(keys)
                for key in keys:
                    borders.render(key)
                with Image.open(root / 'slimshared_0_0_0_pref.webp') as left, Image.open(root / 'slimshared_0_1_0_pref.webp') as right:
                    a = [left.getpixel((511, y)) for y in range(512)]
                    b = [right.getpixel((0, y)) for y in range(512)]
                    self.assertEqual(a, b)
                    self.assertEqual(a.count((255, 255, 255, 255)), 1)
                    self.assertEqual(a.count((255, 255, 255, 64)), 2)
                    self.assertAlmostEqual(sum(pixel[3] for pixel in a) / 255, 1.5, delta=.01)
                    self.assertTrue(all(pixel[:3] == (255, 255, 255) for pixel in a if pixel[3]))
                    self.assertEqual(left.size, (512, 512))
                borders.source_alpha.cache_clear()

    def test_antialias_continues_into_an_originally_empty_neighbor(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = Image.new('RGBA', (512, 512), (255, 255, 255, 0))
            ImageDraw.Draw(image).line([(511, 30), (511, 100)], fill=(255, 255, 255, 196))
            image.save(root / '0_0_0_town.webp', lossless=True)
            with patch.object(borders, 'SOURCE', root), patch.object(borders, 'OUT', root):
                borders.source_alpha.cache_clear()
                borders.initialize(['0_0_0_town'])
                self.assertIn('0_1_0_town', borders.candidates(['0_0_0_town']))
                self.assertIsNotNone(borders.render('0_1_0_town'))
                with Image.open(root / 'slim_0_1_0_town.webp') as neighbor:
                    self.assertEqual(neighbor.getpixel((0, 60)), (255, 255, 255, 64))
                    self.assertEqual(neighbor.getpixel((1, 60))[3], 0)
                borders.source_alpha.cache_clear()


if __name__ == '__main__':
    unittest.main()
