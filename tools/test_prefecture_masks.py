"""Prefecture display masks must match detailed municipalities, not coarse hulls."""
import hashlib
import json
import struct
import unittest
from pathlib import Path
from shapely.geometry import Point
from build_border_tiles import joined
from test_national_territories import decode

ROOT = Path(__file__).resolve().parents[1] / 'assets/data/national_territories'


def entries(binary):
    count = struct.unpack_from('<I', binary, 4)[0]
    offset = 8
    for _ in range(count):
        length = binary[offset]
        offset += 1
        name = binary[offset:offset + length].decode('ascii')
        offset += length
        start, size = struct.unpack_from('<II', binary, offset)
        offset += 8
        yield name, binary[start:start + size]


def polygons(name, body):
    key = name.encode('ascii')
    start = 8 + 1 + len(key) + 8
    binary = struct.pack('<4sIB', b'KNT4', 1, len(key)) + key
    binary += struct.pack('<II', start, len(body)) + body
    return decode(binary)[name]


class PrefectureMaskTest(unittest.TestCase):
    def test_all_47_masks_equal_the_union_of_their_municipalities(self):
        report = json.loads((ROOT / 'index.json').read_text())
        self.assertEqual(len(report['prefectures']), 47)
        for pref, stats in report['prefectures'].items():
            binary = (ROOT / f'{pref}.bin').read_bytes()
            self.assertEqual(hashlib.sha256(binary).hexdigest(), stats['sha256'])
            selected = {key: polygons(key, body) for key, body in entries(binary)
                        if key == 'pref' or len(key) == 5}
            expected = joined([p for key, parts in selected.items()
                               if key != 'pref' for p in parts])
            actual = joined(selected['pref'])
            self.assertTrue(actual.equals(expected), pref)
            print('Verified precise prefecture mask:', pref, flush=True)

    def test_mie_inland_overhang_is_excluded(self):
        body = dict(entries((ROOT / '24.bin').read_bytes()))['pref']
        mask = joined(polygons('pref', body))
        self.assertFalse(mask.covers(Point(136.05192309050943, 34.657852)))
        self.assertTrue(mask.covers(Point(136.13, 34.768)))


if __name__ == '__main__':
    unittest.main()
