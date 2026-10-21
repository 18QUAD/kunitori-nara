import unittest
from shapely.geometry import box
import build_nearest_connections as module


def polygon(west, east, south=35, north=35.001):
    return box(west*module.SCALES[0], south*module.SCALES[1],
               east*module.SCALES[0], north*module.SCALES[1])


def build(rows, geometry, municipality_target='outside'):
    graph = {'towns': [dict(id=tid, cityId=city, neighbors=neighbors)
                       for tid, city, neighbors in rows]}
    return module.ConnectionBuilder(graph, geometry, municipality_target)


class NearestConnectionTests(unittest.TestCase):
    def test_uses_boundaries_instead_of_centroids(self):
        b = build([('wide', 'a', []), ('centroid', 'a', []), ('island', 'a', [])], {
            'wide': [polygon(135, 135.01)],
            'centroid': [polygon(135.011, 135.0111)],
            'island': [polygon(135.0101, 135.0102)],
        })
        roots = {tid:b.root(tid) for tid in b.towns}
        result = b.nearest(['island'], roots)
        self.assertEqual(result['toTown'], 'wide')
        self.assertGreater(result['distanceMetres'], 8)
        self.assertLess(result['distanceMetres'], 10)

    def test_cross_city_adds_nearest_same_city_outside_group(self):
        b = build([('main', 'x', ['local']), ('local', 'c', ['main']),
                   ('island', 'c', [])], {
            'main': [polygon(135, 135.001)],
            'local': [polygon(135.03, 135.031)],
            'island': [polygon(135.01, 135.011)],
        })
        report = b.build()
        self.assertEqual(b.links, {('island','main'), ('island','local')})
        self.assertEqual(report['finalComponents'], 1)
        self.assertEqual({r['reason'] for r in report['links']},
                         {'nearest_component','same_municipality'})

    def test_same_city_target_excludes_already_connected_group(self):
        b = build([('main', 'x', ['local', 'main3']), ('local', 'c', ['main']),
                   ('main3', 'x', ['main']),
                   ('i1', 'c', ['i2']), ('i2', 'c', ['i1'])], {
            'main': [polygon(135, 135.001)],
            'main3': [polygon(135.001, 135.002)],
            'local': [polygon(135.03, 135.031)],
            'i1': [polygon(135.01, 135.011)],
            'i2': [polygon(135.011, 135.012)],
        })
        report = b.build()
        local = next(r for r in report['links'] if r['reason']=='same_municipality')
        self.assertEqual(local['toTown'], 'local')

    def test_repeats_when_two_islands_only_choose_each_other(self):
        b = build([('main', 'c', ['main2']), ('main2', 'c', ['main']),
                   ('i1', 'c', []), ('i2', 'c', [])], {
            'main': [polygon(135, 135.001)],
            'main2': [polygon(135.001, 135.002)],
            'i1': [polygon(135.03, 135.031)],
            'i2': [polygon(135.032, 135.033)],
        })
        report = b.build()
        self.assertEqual(report['rounds'], 2)
        self.assertEqual(report['finalComponents'], 1)
        self.assertEqual(len(b.links), 2)

    def test_multiple_islands_in_one_town_remain_one_node(self):
        b = build([('main', 'c', ['main2']), ('main2', 'c', ['main']),
                   ('one-town', 'c', [])], {
            'main': [polygon(135, 135.001)],
            'main2': [polygon(135.001, 135.002)],
            'one-town': [polygon(135.003, 135.004), polygon(135.1,135.101)],
        })
        report = b.build()
        self.assertEqual(report['towns'], 3)
        self.assertEqual(len(b.links), 1)
        self.assertIn(('main2','one-town'),b.links)

    def test_no_other_same_city_town_is_reported_without_fabrication(self):
        b = build([('main', 'x', ['main2']), ('main2','x',['main']), ('island','c',[])], {
            'main':[polygon(135,135.001)],'main2':[polygon(135.001,135.002)],
            'island':[polygon(135.01,135.011)],
        })
        report = b.build()
        self.assertEqual(len(report['noSameMunicipalityTarget']),1)
        self.assertEqual(len(b.links),1)

    def test_touching_boundaries_are_zero_distance(self):
        self.assertEqual(module.boundary_distance(polygon(135,135.001),
                                                  polygon(135.001,135.002)),0)

    def test_missing_geometry_fails_instead_of_guessing(self):
        with self.assertRaisesRegex(ValueError,'Missing boundary'):
            build([('missing','c',[])],{})


if __name__ == '__main__':
    unittest.main()
