"""Connect disconnected game-town groups by nearest polygon boundaries.

Uses the actual town graph exported by export_town_graph.dart. Run offline;
Shapely and NumPy are required. No geographic processing runs in the app.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from shapely import make_valid
from shapely.affinity import scale
from shapely.geometry import Polygon
from shapely.ops import nearest_points
from shapely.strtree import STRtree

RADIUS = 6371008.8
UNIT = math.pi * RADIUS / 180
COS = math.cos(math.radians(35))
SCALES = np.array([UNIT * COS, UNIT])


def boundary_distance(a, b):
    """Spherical straight-line metres, with local latitude scaling for endpoints."""
    pa, pb = nearest_points(a, b)
    if pa.distance(pb) < 1e-7:
        return 0.0
    # Refine boundary endpoints in a local distance-preserving approximation,
    # then measure the resulting pair on the sphere, rather than in map pixels.
    for _ in range(3):
        mid_lat = (pa.y + pb.y) / (2 * UNIT)
        factor = math.cos(math.radians(mid_lat)) / COS
        qa, qb = nearest_points(scale(a, xfact=factor, yfact=1, origin=(0, 0)),
                                scale(b, xfact=factor, yfact=1, origin=(0, 0)))
        from shapely.geometry import Point
        pa, pb = Point(qa.x / factor, qa.y), Point(qb.x / factor, qb.y)
    lon1, lat1 = math.radians(pa.x / SCALES[0]), math.radians(pa.y / UNIT)
    lon2, lat2 = math.radians(pb.x / SCALES[0]), math.radians(pb.y / UNIT)
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 2 * RADIUS * math.asin(min(1, math.sqrt(max(0, h))))


class ConnectionBuilder:
    def __init__(self, graph, polygons, municipality_target='outside'):
        self.towns = {t['id']: t for t in graph['towns']}
        self.parent = {tid: tid for tid in self.towns}
        self.city_members = collections.defaultdict(list)
        self.geoms, self.ids = [], []
        self.by_town = collections.defaultdict(list)
        self.municipality_target = municipality_target
        self.existing = set()
        for tid in sorted(self.towns):
            self.city_members[self.towns[tid]['cityId']].append(tid)
            if not polygons.get(tid):
                raise ValueError(f'Missing boundary geometry for game town {tid}')
            for poly in polygons[tid]:
                self.by_town[tid].append(len(self.geoms))
                self.geoms.append(poly)
                self.ids.append(tid)
            for other in self.towns[tid]['neighbors']:
                self.join(tid, other)
                self.existing.add(tuple(sorted((tid, other))))
        for a, b in graph.get('seaConnections', []):
            self.join(a, b)
            self.existing.add(tuple(sorted((a, b))))
        self.geoms = np.array(self.geoms, dtype=object)
        self.tree = STRtree(self.geoms)
        self.links, self.records, self.unavailable = set(), [], []

    def root(self, tid):
        while self.parent[tid] != tid:
            self.parent[tid] = self.parent[self.parent[tid]]
            tid = self.parent[tid]
        return tid

    def join(self, a, b):
        a, b = self.root(a), self.root(b)
        if a != b:
            self.parent[max(a, b)] = min(a, b)

    def groups(self):
        groups = collections.defaultdict(list)
        for tid in sorted(self.towns):
            groups[self.root(tid)].append(tid)
        return groups

    def nearest(self, members, roots, city=None, source=None):
        source_root = roots[members[0]]
        restrict_outside = city is None or self.municipality_target == 'outside'
        if city is not None and not any(
                tid != source and (not restrict_outside or roots[tid] != source_root)
                for tid in self.city_members[city]):
            return None
        indices = [i for tid in ([source] if source else members) for i in self.by_town[tid]]
        # Query each polygon separately. A town can span distant islands;
        # querying its combined bounding box would scan unrelated mainland towns.
        local_indices = None
        target_tree = self.tree
        if city is not None:
            local_indices = [i for tid in self.city_members[city] for i in self.by_town[tid]]
            target_tree = STRtree(self.geoms[local_indices])

        def pairs_within(radius):
            pairs = target_tree.query(self.geoms[indices], predicate='dwithin', distance=radius)
            result = []
            for source_i, target_i in zip(*pairs):
                source_i = indices[int(source_i)]
                target_i = int(target_i) if local_indices is None else local_indices[int(target_i)]
                tid = self.ids[target_i]
                if (tid != source and
                        (not restrict_outside or roots[tid] != source_root) and
                        self.ids[source_i] != tid):
                    result.append((source_i, target_i))
            return result

        radius, candidates = 0, pairs_within(0)
        while not candidates:
            radius = 25 if not radius else radius * 4
            if radius > 100000000:
                raise ValueError('No other town component found')
            candidates = pairs_within(radius)
        first = min(self.geoms[a].distance(self.geoms[b]) for a, b in candidates)
        candidates = pairs_within(first * 1.5 + .001)
        distances = [self.geoms[a].distance(self.geoms[b]) for a, b in candidates]
        minimum = min(distances)
        limit = minimum * 1.5 + .001
        possible = sorted({pair for pair, d in zip(candidates, distances) if d <= limit},
                          key=lambda pair: (self.ids[pair[0]], self.ids[pair[1]], pair))
        best = None
        for source_i, target_i in possible:
            metres = boundary_distance(self.geoms[source_i], self.geoms[target_i])
            key = (round(metres, 6), self.ids[source_i], self.ids[target_i])
            if best is None or key < best[0]:
                best = (key, dict(fromTown=self.ids[source_i], toTown=self.ids[target_i],
                                  distanceMetres=round(metres, 3)))
        if best is None:
            raise ValueError('No closest boundary candidate')
        return best[1]

    def add(self, link, reason, round_number):
        pair = tuple(sorted((link['fromTown'], link['toTown'])))
        added = pair not in self.existing and pair not in self.links
        if added:
            self.links.add(pair)
        self.records.append(dict(link, reason=reason, round=round_number,
                                 fromCity=self.towns[link['fromTown']]['cityId'],
                                 toCity=self.towns[link['toTown']]['cityId'], added=added))

    def build(self):
        initial = len(self.groups())
        round_number = 0
        while True:
            groups = self.groups()
            if len(groups) == 1:
                break
            round_number += 1
            roots = {tid: root for root, members in groups.items() for tid in members}
            anchor = min(groups, key=lambda root: (-len(groups[root]), root))
            choices = []
            for root, members in sorted(groups.items()):
                if root == anchor:
                    continue
                link = self.nearest(members, roots)
                self.add(link, 'nearest_component', round_number)
                choices.append(link)
                source, target = link['fromTown'], link['toTown']
                city = self.towns[source]['cityId']
                if city != self.towns[target]['cityId']:
                    local = self.nearest(members, roots, city=city, source=source)
                    if local:
                        self.add(local, 'same_municipality', round_number)
                        choices.append(local)
                    else:
                        self.unavailable.append(dict(town=source, city=city, round=round_number))
            for link in choices:
                self.join(link['fromTown'], link['toTown'])
            remaining = len(self.groups())
            print(f'Round {round_number}: {len(groups)} -> {remaining} components; {len(self.links)} extra links', flush=True)
            if remaining >= len(groups):
                raise ValueError('Connection generation made no progress')
        return dict(initialComponents=initial, finalComponents=1, towns=len(self.towns),
                    additionalConnections=len(self.links), rounds=round_number,
                    municipalityTarget=self.municipality_target,
                    distanceMethod='Shortest town-boundary distance; locally refined boundary endpoints and spherical distance (R=6371008.8m). Not centroid distance.',
                    links=self.records, noSameMunicipalityTarget=self.unavailable)


def load_polygons(assets, graph):
    polygons = collections.defaultdict(list)
    for pref in range(1, 48):
        name = 'nara.json' if pref == 29 else f'prefectures/{pref:02}.json'
        data = json.loads((assets/name).read_text())
        for town in data['towns']:
            tid = graph['sourceToTown'][town['id']]
            for rings in town['polygons']:
                if not rings or len(rings[0]) < 3:
                    continue
                exterior = np.array(rings[0]) * SCALES
                holes = [np.array(r) * SCALES for r in rings[1:] if len(r) >= 3]
                poly = Polygon(exterior, holes)
                if not poly.is_valid:
                    poly = make_valid(poly)
                if not poly.is_empty:
                    polygons[tid].append(poly)
        print(f'Loaded town boundaries {pref:02}', flush=True)
    return polygons


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--assets', type=Path, default=Path('assets/data'))
    p.add_argument('--graph', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('lib/nearest_connections.dart'))
    p.add_argument('--report', type=Path, default=Path('data/derived/nearest_connections.json'))
    p.add_argument('--municipality-target', choices=['outside', 'any'], default='outside')
    args = p.parse_args()
    graph = json.loads(args.graph.read_text())
    builder = ConnectionBuilder(graph, load_polygons(args.assets, graph), args.municipality_target)
    report = builder.build()
    report['graphSha256'] = hashlib.sha256(args.graph.read_bytes()).hexdigest()
    lines = ['// Generated by tools/build_nearest_connections.py.',
             '// Explicit gameplay links, not physical borders or real ferry routes.',
             'const nearestTownConnections = <List<String>>[']
    lines += [f"  ['{a}', '{b}']," for a, b in sorted(builder.links)]
    lines += ['];', '']
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text('\n'.join(lines))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ['links','noSameMunicipalityTarget']}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
