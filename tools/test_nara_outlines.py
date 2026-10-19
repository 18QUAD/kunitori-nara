"""The fast parent shapes must preserve every original Nara region and hole."""
import hashlib
import json
import unittest
from collections import defaultdict

from shapely import make_valid
from shapely.geometry import Polygon, shape
from shapely.ops import unary_union
from build_nara_outlines import DATA


class NaraOutlinesTest(unittest.TestCase):
    def test_source_coverage_and_holes_are_unchanged(self):
        source = (DATA / 'nara.json').read_bytes()
        original = json.loads(source)
        prepared = json.loads((DATA / 'nara_outlines.json').read_bytes())
        self.assertEqual(prepared['sourceSha256'], hashlib.sha256(source).hexdigest())
        self.assertEqual([(c['id'], c['name']) for c in prepared['cities']],
                         [(c['id'], c['name']) for c in original['cities']])
        groups = defaultdict(list)
        for town in original['towns']:
            groups[town['cityId']].extend(Polygon(p[0], p[1:]) for p in town['polygons'])
        parents = []
        for city in prepared['cities']:
            expected = unary_union([make_valid(p) for p in groups[city['id']]])
            actual = shape({'type': 'MultiPolygon', 'coordinates': city['polygons']})
            self.assertTrue(actual.is_valid, city['id'])
            self.assertLess(expected.symmetric_difference(actual).area, 1e-12, city['id'])
            self.assertEqual(actual.bounds, expected.bounds)
            parents.append(actual)
        prefecture = shape({'type': 'MultiPolygon', 'coordinates': prepared['polygons']})
        self.assertTrue(prefecture.is_valid)
        self.assertLess(unary_union(parents).symmetric_difference(prefecture).area, 1e-12)


if __name__ == '__main__':
    unittest.main()
