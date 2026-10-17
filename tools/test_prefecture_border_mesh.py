import unittest
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union
from prefecture_border_mesh import shared_network, outlines


class SharedPrefectureMeshTest(unittest.TestCase):
    def test_displaced_shared_edges_become_one_line_and_keep_the_coast(self):
        a = Polygon([(120, 46), (121, 46), (121, 47), (120, 47)])
        b = Polygon([(121.0001, 46), (122, 46), (122, 47), (121.0001, 47)])
        probe = LineString([(120.9, 46.5), (121.1, 46.5)])
        old = unary_union(outlines(a) + outlines(b))
        self.assertEqual(len(old.intersection(probe).geoms), 2)
        mesh = shared_network({'01': a, '02': b}, {('01', '02')})
        hit = mesh.intersection(probe)
        self.assertEqual(hit.geom_type, 'Point')
        self.assertAlmostEqual(hit.x, 121)
        # Trimmed coast ends connect exactly to the retained shared boundary.
        self.assertLess(mesh.distance(LineString([(121,46),(121.1,46)])), 1e-10)
        self.assertEqual(mesh.intersection(LineString([(120.5,45.9),(120.5,46.1)])).geom_type, 'Point')

    def test_straits_are_not_joined_even_when_coastlines_are_near(self):
        a = Polygon([(120,46),(121,46),(121,47),(120,47)])
        b = Polygon([(121.0001,46),(122,46),(122,47),(121.0001,47)])
        mesh = shared_network({'01':a,'02':b}, set())
        probe = LineString([(120.9,46.5),(121.1,46.5)])
        self.assertEqual(len(mesh.intersection(probe).geoms),2)

    def test_three_way_junction_is_connected_without_parallel_branches(self):
        shapes = {
            '01':Polygon([(120,46),(121,46),(121,48),(120,48)]),
            '02':Polygon([(121.0001,47),(122,47),(122,48),(121.0001,48)]),
            '03':Polygon([(121.0001,46),(122,46),(122,46.9999),(121.0001,46.9999)]),
        }
        mesh=shared_network(shapes,{('01','02'),('01','03'),('02','03')})
        for probe in [LineString([(120.9,47.5),(121.1,47.5)]),
                      LineString([(120.9,46.5),(121.1,46.5)]),
                      LineString([(121.5,46.9),(121.5,47.1)])]:
            self.assertEqual(mesh.intersection(probe).geom_type,'Point')

    def test_single_line_survives_rasterizing_the_shared_mesh(self):
        from tempfile import TemporaryDirectory
        from pathlib import Path
        from PIL import Image
        from build_border_tiles import raster
        from prefecture_border_mesh import lines
        a=Polygon([(120,46),(121,46),(121,47),(120,47)])
        b=Polygon([(121.001,46),(122,46),(122,47),(121.001,47)])
        mesh=shared_network({'01':a,'02':b},{('01','02')},tolerance=.002)
        with TemporaryDirectory() as tmp:
            folder=Path(tmp);raster(list(lines(mesh)),'pref',4,folder)
            # A horizontal scan across the shared side has ONE connected stroke.
            tile=Image.open(folder/'4_4_6_pref.webp').getchannel('A')
            active=[tile.getpixel((x,128))>=24 for x in range(24)]
            runs=sum(value and (x==0 or not active[x-1]) for x,value in enumerate(active))
            self.assertEqual(runs,1)
