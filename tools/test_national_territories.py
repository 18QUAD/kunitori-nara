"""Check prepared geometry against all original census regions and exact doubles."""
import hashlib
import json
import struct
import unittest
from collections import defaultdict
from build_national_territories import DATA, OUT, GROUPS, encode
from build_border_tiles import joined


def decode(binary):
    magic, rows = struct.unpack_from('<4sI', binary)
    assert magic == b'KNT4'
    offset = 8
    result = {}
    for _ in range(rows):
        length = binary[offset]
        offset += 1
        name = binary[offset:offset + length].decode('ascii')
        offset += length
        start, size = struct.unpack_from('<II', binary, offset)
        offset += 8
        pos = start
        def uint():
            nonlocal pos
            n, = struct.unpack_from('<I', binary, pos)
            pos += 4
            return n
        parts = []
        for _ in range(uint()):
            rings = []
            for _ in range(uint()):
                mode = binary[pos]
                pos += 1
                ring = []
                x = y = 0
                for _ in range(uint()):
                    if mode == 1:
                        dx, dy = struct.unpack_from('<ii', binary, pos)
                        pos += 8
                        x += dx
                        y += dy
                        ring.append([x / 1e6, y / 1e6])
                    else:
                        assert mode == 0
                        ring.append(list(struct.unpack_from('<dd', binary, pos)))
                        pos += 16
                rings.append(ring)
            parts.append(rings)
        assert pos == start + size
        result[name] = parts
    return result


class NationalTerritoryTest(unittest.TestCase):
    def test_every_prepared_town_matches_original_region(self):
        report = json.loads((OUT / 'index.json').read_text())
        mapping = json.loads(GROUPS.read_bytes())['sourceToTown']
        self.assertEqual(hashlib.sha256(GROUPS.read_bytes()).hexdigest(), report['groupSha256'])
        self.assertEqual(set(report['prefectures']), {f'{p:02d}' for p in range(1, 48)})
        for pref, stats in report['prefectures'].items():
            source = (DATA / ('nara.json' if pref == '29' else f'prefectures/{pref}.json')).read_bytes()
            binary = (OUT / f'{pref}.bin').read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), stats['sourceSha256'])
            self.assertEqual(hashlib.sha256(binary).hexdigest(), stats['sha256'])
            source = json.loads(source)
            groups = defaultdict(list)
            for row in source['towns']:
                groups[mapping[row['id']]].extend(row['polygons'])
            actual = decode(binary)
            self.assertEqual(set(actual), set(groups) | {c['id'] for c in source['cities']} | {'pref'})
            self.assertEqual(len(groups), stats['towns'])
            for name, parts in groups.items():
                expected, prepared = joined(parts), joined(actual[name])
                self.assertTrue(expected.equals(prepared), name)
                self.assertEqual(expected.bounds, prepared.bounds, name)
            parent = json.loads((DATA / 'nara_outlines.json').read_bytes()) if pref == '29' else source
            for row in parent['cities']:
                self.assertEqual(actual[row['id']], row['polygons'])
            self.assertEqual(actual['pref'], parent['polygons'])
            print('Verified', pref, len(groups), 'town regions', flush=True)

    def test_holes_islands_and_full_float64_precision(self):
        shapes = {'29201001001': [[
            [[135.1, 34.2], [135.1, 34.3], [135.2, 34.2]],
            [[135.1234567890123, 34.1234567890123]],
        ], [[[136.0, 35.0], [136.2, 35.1], [136.0, 35.0]]]]}
        self.assertEqual(decode(encode(shapes)), shapes)


if __name__ == '__main__':
    unittest.main()
