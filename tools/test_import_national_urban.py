import json
from pathlib import Path
import unittest
import numpy as np
from PIL import Image
from import_national_urban import cell_indices, mesh_bounds


class NationalUrbanTest(unittest.TestCase):
    def test_mesh_positions_and_extremes(self):
        rows, cols = cell_indices(np.array([b'5339000000', b'5339779999', b'5339452713'], dtype='S10'))
        self.assertEqual(rows.tolist(), [0, 799, 421])
        self.assertEqual(cols.tolist(), [0, 799, 573])
        self.assertEqual(mesh_bounds('5339'), (139, 106/3, 140, 36))

    def test_invalid_mesh_codes_are_rejected(self):
        for code in [b'5339800000', b'5339080000', b'5339abc123']:
            with self.assertRaises(ValueError):
                cell_indices(np.array([code], dtype='S10'))

    def test_all_prefectures_and_actual_masks(self):
        root = Path(__file__).resolve().parents[1] / 'assets/data/urban'
        report = json.loads((root / 'index.json').read_text())
        self.assertEqual(set(report['prefectures']), {f'{i:02}' for i in range(1, 48)})
        tiles = {t['id']: t for t in report['tiles']}
        for ids in report['prefectures'].values():
            self.assertTrue(ids)
            self.assertTrue(all(tiles[key]['cells'] > 0 for key in ids))
        for tile in tiles.values():
            with Image.open(root / (tile['id']+'.png')) as image:
                alpha = np.array(image.convert('RGBA'))[:, :, 3]
                self.assertEqual(alpha.shape, (800,800))
                self.assertEqual(np.count_nonzero(alpha), tile['cells'])
                self.assertTrue(set(np.unique(alpha)) <= {0,255})
            self.assertEqual(tile['verifiedShapeSamples'], min(3, tile['cells']))


if __name__ == '__main__':
    unittest.main()
