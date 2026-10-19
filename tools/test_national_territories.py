"""Verify every indexed source row, including non-ASCII names and exact geometry."""
import hashlib
import json
import struct
import unittest
from build_national_territories import DATA, OUT, encode


def decode(index, source):
    magic, size, rows = struct.unpack_from('<4sII', index)
    assert magic == b'KNT3' and size == len(source)
    offset = 12
    for _ in range(rows):
        length = index[offset]
        offset += 1
        name = index[offset:offset + length].decode('ascii')
        offset += length
        start, size = struct.unpack_from('<II', index, offset)
        offset += 8
        row = json.loads(source[start:start + size])
        assert row['id'] == name
        yield row
    assert offset == len(index)


class NationalTerritoryTest(unittest.TestCase):
    def test_all_prefectures_are_lossless(self):
        index = json.loads((OUT / 'index.json').read_text())
        self.assertEqual(set(index['prefectures']), {f'{p:02d}' for p in range(1, 48)})
        for pref, stats in index['prefectures'].items():
            source = (DATA / ('nara.json' if pref == '29' else f'prefectures/{pref}.json')).read_bytes()
            binary = (OUT / f'{pref}.bin').read_bytes()
            self.assertEqual(hashlib.sha256(source).hexdigest(), stats['sourceSha256'])
            self.assertEqual(hashlib.sha256(binary).hexdigest(), stats['sha256'])
            original = json.loads(source)['towns']
            self.assertEqual(len(original), stats['towns'])
            for expected, actual in zip(original, decode(binary, source), strict=True):
                self.assertEqual(actual, expected, actual['id'])

    def test_unicode_whitespace_and_full_float64_precision(self):
        rows = [{'id': '29201001001', 'name': '池之内🌸', 'polygons': [[
            [[135.1, 34.2], [135.1, 34.3], [135.2, 34.2]],
            [[135.1234567890123, 34.1234567890123]],
        ]]}]
        source = json.dumps({'cities': [{'name': '奈良県'}], 'towns': rows},
                            ensure_ascii=False, indent=2).encode('utf8')
        self.assertEqual(list(decode(encode(source)[0], source)), rows)


if __name__ == '__main__':
    unittest.main()
