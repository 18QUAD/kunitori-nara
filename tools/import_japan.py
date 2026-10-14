"""Build nationwide 2020 census metadata and lazily loaded prefecture geometry.

Requires shapely. Uses the same CODH source and KEY_CODEs as import_nara.py.
Never rewrites nara.json: its IDs, population, grouping and existing saves remain stable.
All 47 prefectures are required; a partial or failed import cannot activate the build.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile

from shapely.geometry import shape, mapping
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'https://geoshape.ex.nii.ac.jp/ka/'
PREFECTURES = '北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県'.split()
# The administrative boundary index includes six northern-territory municipalities
# that have no 2020 Japanese census town data.
NO_CENSUS_CODES = {'01695', '01696', '01697', '01698', '01699', '01700'}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')),
                         encoding='utf-8')
    temporary.replace(path)


def fetch(code, cache, offline):
    target = cache / f'{code}.json'
    if not target.exists():
        if offline:
            raise FileNotFoundError(target)
        url = f'{SOURCE}topojson/2020/{code[:2]}/r2ka{code}.topojson'
        temporary = target.with_suffix('.download')
        subprocess.run(['curl', '--silent', '--show-error', '--fail', '--location',
                        '--retry', '2', '--max-time', '120', url, '-o', str(temporary)],
                       check=True)
        data = json.loads(temporary.read_text(encoding='utf-8'))
        if 'town' not in data.get('objects', {}):
            raise ValueError(f'Not town census topology: {code}')
        temporary.replace(target)
    data = json.loads(target.read_text(encoding='utf-8'))
    return code, data, hashlib.sha256(target.read_bytes()).hexdigest()


def decode(data):
    arcs = data['arcs']
    if 'transform' not in data:
        return arcs
    scale, translate = data['transform']['scale'], data['transform']['translate']
    result = []
    for arc in arcs:
        x = y = 0
        points = []
        for dx, dy in arc:
            x += dx
            y += dy
            points.append([x * scale[0] + translate[0], y * scale[1] + translate[1]])
        result.append(points)
    return result


def polygons(geometry, arcs):
    parts = [geometry['arcs']] if geometry['type'] == 'Polygon' else geometry['arcs']
    for polygon in parts:
        rings = []
        for ring in polygon:
            points = []
            for index in ring:
                arc = arcs[index] if index >= 0 else list(reversed(arcs[~index]))
                points.extend(arc if not points else arc[1:])
            rings.append([tuple(round(v, 6) for v in p[:2]) for p in points])
        yield rings


def coordinates(geometry, tolerance):
    simple = geometry.simplify(tolerance, preserve_topology=True)
    geo = mapping(simple)
    if geo['type'] == 'Polygon':
        return [geo['coordinates']]
    if geo['type'] == 'MultiPolygon':
        return geo['coordinates']
    return [p for g in simple.geoms if g.geom_type in ('Polygon', 'MultiPolygon')
            for p in coordinates(g, tolerance)]


def process_prefecture(datasets, edge_db):
    towns = {}
    cities = []
    segments = collections.defaultdict(set)
    hashes = {}
    for code, data, digest in datasets:
        hashes[code] = digest
        arcs = decode(data)
        city_name = None
        for geo in data['objects']['town']['geometries']:
            props = geo['properties']
            key = str(props['KEY_CODE'])
            if not key.startswith(code):
                raise ValueError(f'Unexpected town code: {key} / {code}')
            city_name = props['CITY_NAME']
            town = towns.setdefault(key, dict(
                id=key, name=props['S_NAME'] or '名称未設定', cityId=code,
                population=0, area=0, neighbors=[], polygons=[]))
            town['population'] += max(0, int(props.get('JINKO') or 0))
            town['area'] += float(props.get('AREA') or 0) / 1e6
            for polygon in polygons(geo, arcs):
                for ring in polygon:
                    for a, b in zip(ring, ring[1:]):
                        if a != b:
                            segments[tuple(sorted((a, b)))].add(key)
                town['polygons'].append(polygon)
        if not city_name:
            raise ValueError(f'No census towns for {code}')
        cities.append(dict(id=code, name=city_name))
    neighbors = {key: set() for key in towns}
    boundary = []
    for edge, owners in segments.items():
        if len(owners) > 1:
            for key in owners:
                neighbors[key].update(owners - {key})
        else:
            boundary.append((json.dumps(edge, separators=(',', ':')), next(iter(owners))))
    edge_db.executemany('INSERT INTO edges VALUES (?, ?)', boundary)
    edge_db.commit()
    geometries = []
    for key, town in towns.items():
        town['neighbors'] = sorted(neighbors[key])
        geometry = shape(dict(type='MultiPolygon', coordinates=town['polygons']))
        if not geometry.is_valid:
            # Fix self intersections for display only; raw segments define adjacency.
            geometry = geometry.buffer(0)
        geometries.append(geometry)
        town['polygons'] = coordinates(geometry, 0.00004)
        town['area'] = round(town['area'], 6)
    outline = coordinates(unary_union(geometries), 0.002)
    return cities, list(towns.values()), outline, hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--cache', type=Path, default=ROOT / 'data/raw/japan')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/data')
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    codes = json.loads((ROOT / 'tools/national_city_codes.json').read_text())['codes']
    codes = [c for c in codes if c not in NO_CENSUS_CODES]
    if {c[:2] for c in codes} != {f'{i:02}' for i in range(1, 48)}:
        raise ValueError('Code index must cover all 47 prefectures')
    nara = json.loads((ROOT / 'assets/data/nara.json').read_text(encoding='utf-8'))
    nara_towns = {t['id']: t for t in nara['towns']}
    cities, towns, prefectures, hashes = [], [], [], {}
    with tempfile.TemporaryDirectory(dir=args.cache) as work:
        staging = Path(work)
        db = sqlite3.connect(staging / 'edges.sqlite')
        db.execute('CREATE TABLE edges (edge TEXT, owner TEXT)')
        for index, name in enumerate(PREFECTURES, 1):
            pref = f'{index:02}'
            selected = [c for c in codes if c.startswith(pref)]
            with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
                datasets = list(pool.map(lambda c: fetch(c, args.cache, args.offline), selected))
            cs, ts, outline, source_hashes = process_prefecture(datasets, db)
            hashes.update(source_hashes)
            prefectures.append(dict(id=pref, name=name, polygons=outline))
            if pref == '29':
                if {t['id'] for t in ts} != set(nara_towns):
                    raise ValueError('Nara census IDs differ from existing saves')
                for t in ts:
                    if t['population'] != nara_towns[t['id']]['population']:
                        raise ValueError(f'Nara population changed: {t["id"]}')
            else:
                cities.extend(cs)
                write_json(staging / 'prefectures' / f'{pref}.json', {
                    'towns': [dict(id=t['id'], polygons=t['polygons']) for t in ts]})
                towns.extend({**t, 'polygons': []} for t in ts)
            print(f'{pref} {name}: {len(cs)} cities, {len(ts)} census towns', flush=True)
        db.execute('CREATE INDEX edges_index ON edges(edge)')
        cross = db.execute('SELECT DISTINCT a.owner,b.owner FROM edges a JOIN edges b '
                           'ON a.edge=b.edge AND a.owner<b.owner '
                           'WHERE substr(a.owner,1,2) != substr(b.owner,1,2)').fetchall()
        db.close()
        population = sum(t['population'] for t in towns) + sum(t['population'] for t in nara_towns.values())
        payload = dict(censusYear=2020, source=SOURCE, license='CC BY 4.0',
                       attribution=nara['attribution'], cities=cities, towns=towns,
                       prefectures=prefectures, crossPrefectureNeighbors=cross)
        write_json(staging / 'japan.json', payload)
        write_json(staging / 'japan_import_report.json', dict(
            prefectures=47, cities=len(cities)+len(nara['cities']),
            sourceTowns=len(towns)+len(nara_towns), population=population,
            crossPrefectureEdges=len(cross), sourceSha256=hashes))
        # Publish the activating metadata last. Failed imports leave the working build intact.
        for path in sorted((staging / 'prefectures').glob('*.json')):
            write_json(args.output / 'prefectures' / path.name, json.loads(path.read_text()))
        for filename in ['japan_import_report.json', 'japan.json']:
            write_json(args.output / filename, json.loads((staging / filename).read_text()))
        print(f'Nationwide population: {population:,}', flush=True)


if __name__ == '__main__':
    main()
