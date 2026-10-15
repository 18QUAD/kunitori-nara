import json
from pathlib import Path
import unittest
from shapely.geometry import Point, Polygon
from import_national_water import feature_allowed, coordinate, tile_index


class NationalWaterTest(unittest.TestCase):
    def test_surface_features_only(self):
        for code in [5301,5321]:
            self.assertTrue(feature_allowed('river',dict(ftCode=code)))
        for code in [5302,5311,5331,5000]:
            self.assertFalse(feature_allowed('river',dict(ftCode=code)))
        self.assertTrue(feature_allowed('waterarea',dict(ftCode=5000)))
        self.assertFalse(feature_allowed('waterarea',dict(ftCode=5001)))
        self.assertTrue(feature_allowed('label',dict(annoCtg=321,annoChar='琵琶湖')))
        self.assertFalse(feature_allowed('label',dict(annoCtg=321,annoChar='')))
        self.assertFalse(feature_allowed('label',dict(annoCtg=411,annoChar='山')))

    def test_projection_round_trip(self):
        for lon,lat in [(136.05,35.25),(140.85,42.6),(127.7,26.2)]:
            x,y=tile_index(lon,lat)
            west,south=coordinate(x,y+1)
            east,north=coordinate(x+1,y)
            self.assertTrue(west<=lon<=east and south<=lat<=north)

    def test_all_prefectures_and_real_lake(self):
        root=Path(__file__).resolve().parents[1]/'assets/data/water'
        report=json.loads((root/'index.json').read_text())
        self.assertEqual(set(report['prefectures']),{f'{i:02}' for i in range(1,48)})
        for p,counts in report['prefectures'].items():
            self.assertGreater(counts['riverParts']+counts['waterPolygons'],0)
            if p=='29':
                continue
            data=json.loads((root/(p+'.json')).read_text())
            self.assertEqual(len(data['lines']),counts['riverParts'])
            self.assertEqual(len(data['areas']),counts['waterPolygons'])
            self.assertEqual(len(data['labels']),counts['names'])
        for file in ['25.json','national.json']:
            data=json.loads((root/file).read_text())
            # Independent real-world positions: open Lake Biwa and Chikubu island.
            for areas in [data['areas'], data.get('overviewAreas', data['areas'])]:
                lake=[Polygon(p[0],p[1:]) for p in areas]
                self.assertTrue(all(p.is_valid for p in lake),file)
                self.assertTrue(any(p.contains(Point(136.05,35.25)) for p in lake),file)
                self.assertFalse(any(p.contains(Point(136.143,35.4219)) for p in lake),file)
            self.assertIn('琵琶湖',{l['name'] for l in data['labels']})


if __name__=='__main__':
    unittest.main()
