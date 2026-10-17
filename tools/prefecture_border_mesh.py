"""Build one detailed shared prefecture boundary network, never simplified faces.

Only the static national border images change. Census/game geometry stays intact.
"""
import concurrent.futures
import json
import hashlib
from pathlib import Path
import shapely
from shapely.geometry import LineString, Point
from shapely.ops import unary_union, nearest_points
from build_border_tiles import joined, outlines, raster, DATA

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'data/raw/shared_prefectures'
# Source municipality display geometry is accurate to ~4m. Reconcile its small
# independently digitized differences before simplifying the ONE shared network.
TOLERANCE = 0.0002


def lines(geometry):
    if geometry.geom_type in ('LineString', 'LinearRing'):
        yield LineString(geometry.coords)
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms:
            yield from lines(part)


def detailed_prefecture(pid):
    cache = WORK / f'{pid}.wkb'
    source = DATA / ('nara.json' if pid == '29' else f'prefectures/{pid}.json')
    fingerprint = hashlib.sha256(source.read_bytes()).hexdigest()
    marker = cache.with_suffix('.sha256')
    if cache.exists() and marker.exists() and marker.read_text() == fingerprint:
        return pid, shapely.from_wkb(cache.read_bytes())
    data = json.loads(source.read_text())
    parts = data['towns'] if pid == '29' else data['cities']
    geometry = unary_union([joined(part['polygons']) for part in parts])
    # Close sub-metre digitizing slits inside the prefecture, not census holes.
    geometry = geometry.buffer(0.00001, join_style='mitre').buffer(-0.00001, join_style='mitre')
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_bytes(shapely.to_wkb(geometry))
    marker.write_text(fingerprint)
    return pid, geometry


def shared_network(shapes, adjacent, tolerance=TOLERANCE, verbose=False):
    """Lower ID owns each shared arc; remove its displaced duplicate, node once.

    Only known land-adjacent prefectures can share arcs. Never connect coastlines
    across straits. Snap trimmed endpoints onto the retained network so three-way
    junctions and the coast remain connected instead of leaving little stubs.
    """
    kept = {}
    for pid in sorted(shapes):
        boundary = unary_union(outlines(shapes[pid])).simplify(0.00004, preserve_topology=False)
        earlier = [kept[other] for other in kept if tuple(sorted((pid, other))) in adjacent]
        if earlier:
            west, south, east, north = boundary.bounds
            preferred = unary_union([shapely.clip_by_rect(part,
                west-tolerance*2, south-tolerance*2, east+tolerance*2, north+tolerance*2)
                for part in earlier])
            near = preferred.buffer(tolerance, cap_style='flat', join_style='mitre')
            remaining = boundary.difference(near)
            segments = []
            for part in lines(remaining):
                coords = list(part.coords)
                if len(coords) < 2:
                    continue
                for end in [0, -1]:
                    point = Point(coords[end])
                    if point.distance(preferred) <= tolerance * 1.5:
                        coords[end] = nearest_points(point, preferred)[1].coords[0]
                segment = LineString(coords)
                if segment.length:
                    segments.append(segment)
            boundary = unary_union(segments)
        kept[pid] = boundary
        if verbose: print("Shared arcs", pid, flush=True)
    return unary_union(list(kept.values()))


def build_mesh(workers=4):
    WORK.mkdir(parents=True, exist_ok=True)
    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as pool:
        shapes = {}
        for pid, shape in pool.map(detailed_prefecture, [f'{i:02}' for i in range(1, 48)]):
            shapes[pid] = shape
            print('Detailed prefecture', pid, flush=True)
    data = json.loads((DATA / 'japan.json').read_text())
    adjacent = {tuple(sorted((a[:2], b[:2]))) for a,b in data['crossPrefectureNeighbors']}
    mesh = shared_network(shapes, adjacent, verbose=True)
    (WORK/'network.wkb').write_bytes(shapely.to_wkb(mesh))
    print('Shared network:', len(list(lines(mesh))), 'arcs', flush=True)
    return mesh


def render_level(level):
    mesh = shapely.from_wkb((WORK/'network.wkb').read_bytes())
    folder = WORK/'tiles'
    folder.mkdir(exist_ok=True)
    for old in folder.glob(f'{level}_*_pref.webp'): old.unlink()
    return level, raster(list(lines(mesh)), 'pref', level, folder)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    build_mesh(args.workers)
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for level, count in pool.map(render_level, range(-2, 7)):
            print('Rendered shared level', level, count, flush=True)
