"""Run with the Shapely import environment: python -m unittest discover -s tools."""
import unittest
from shapely.geometry import box, LineString
from import_japan import boundary_neighbors


class OriginalBoundaryTests(unittest.TestCase):
    def test_vertex_splitting_and_small_coordinate_offsets_match(self):
        a = box(0, 0, 1, 1).boundary
        b = LineString([(1.000005, 0), (1.000005, 0.4), (1.000005, 1)])
        self.assertEqual(boundary_neighbors(['292010001', '272010001'], [a, b]),
                         {('272010001', '292010001')})

    def test_point_contact_and_separated_land_do_not_match(self):
        a = box(0, 0, 1, 1).boundary
        point_contact = box(1, 1, 2, 2).boundary
        separated = box(1.001, 0, 2.001, 1).boundary
        for other in [point_contact, separated]:
            self.assertEqual(boundary_neighbors(
                ['292010001', '272010001'], [a, other]), set())

    def test_exact_short_shared_segment_is_preserved(self):
        a = LineString([(0, 0), (0, 0.000001)])
        b = LineString([(0, 0), (0, 0.0000005), (0, 0.000001)])
        self.assertEqual(len(boundary_neighbors(['292010001', '272010001'], [a, b])), 1)


if __name__ == '__main__':
    unittest.main()
