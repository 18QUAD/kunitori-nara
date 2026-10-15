"""Offline office markers. Preserve Nara quiz offices; import display-only P05/GSI points.
Uses the session proxy and TLS trust. Raw data and its hashes are retained for audit.
"""
import concurrent.futures
import csv
import datetime
import hashlib
import io
import json
import math
from pathlib import Path
import unicodedata
import urllib.request
import zipfile

import mapbox_vector_tile
import shapefile
from shapely.geometry import Point, Polygon
from shapely import STRtree, make_valid

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
CACHE = ROOT / 'data/raw/offices'
P05 = 'https://nlftp.mlit.go.jp/ksj/gml/data/P05/P05-22/P05-22_{p}_GML.zip'
CSV = 'https://raw.githubusercontent.com/codeforfukui/localgovjp/master/localgovjp-utf8.csv'
GSI = 'https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/14/{x}/{y}.pbf'


def fetch(url, path):
    if not path.exists():
        data = urllib.request.urlopen(url, timeout=90).read()
        path.write_bytes(data)
    return path.read_bytes()


def normalize(name):
    return unicodedata.normalize('NFKC', name).replace(' ', '').replace('ヶ', 'ケ').replace('梼', '檮')


def read_pref(p):
    data = fetch(P05.format(p=p), CACHE/f'P05-22_{p}_GML.zip')
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        stem = f'P05-22_{p}'
        reader = shapefile.Reader(**{e: io.BytesIO(z.read(stem+'.'+e))
                                    for e in ['shp', 'shx', 'dbf']}, encoding='cp932')
        return [dict(v.record.as_dict(), point=list(v.shape.points[0]), prefecture=p)
                for v in reader.iterShapeRecords() if v.record['P05_002'] == '1']


def gsi_office(seed, is_city):
    lon, lat = seed
    tx = int((lon+180)/360*2**14)
    ty = int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**14)
    candidates = []
    for x in range(tx-1, tx+2):
        for y in range(ty-1, ty+2):
            url = GSI.format(x=x, y=y)
            data = fetch(url, CACHE/f'14_{x}_{y}.pbf')
            for layer in mapbox_vector_tile.decode(data, default_options={'y_coord_down': True}).values():
                for f in layer['features']:
                    if f['properties'].get('ftCode') != (3205 if is_city else 3206):
                        continue
                    px, py = f['geometry']['coordinates']
                    lng = (x+px/layer['extent'])/2**14*360-180
                    latitude = math.degrees(math.atan(math.sinh(math.pi*(1-2*(y+py/layer['extent'])/2**14))))
                    distance = math.hypot((lng-lon)*math.cos(math.radians(lat)), latitude-lat)*111000
                    candidates.append((distance, [lng, latitude], url, hashlib.sha256(data).hexdigest()))
    if not candidates or min(c[0] for c in candidates) > 1500:
        raise ValueError(f'GSI headquarters needs review: {seed}, {sorted(candidates)[:1]}')
    return min(candidates)


def associate_pref(args):
    p, offices = args
    data = json.loads((DATA/f'prefectures/{p}.json').read_text())
    by_city = {}
    for row in data['towns']:
        bucket = by_city.setdefault(row['id'][:5], [])
        for rings in row['polygons']:
            shape = Polygon(rings[0], rings[1:])
            if not shape.is_valid: shape = make_valid(shape)
            if not shape.is_empty: bucket.append((shape, row['id']))
    trees = {city: (STRtree([s for s, _ in parts]), parts) for city, parts in by_city.items()}
    for office in offices:
        point = Point(office['point'])
        tree, parts = trees[office['cityId']]
        hits = [parts[i][1] for i in tree.query(point) if parts[i][0].covers(point)]
        office['sourceTownId'] = sorted(set(hits))[0] if hits else None
        office['distanceToTerritoryMeters'] = 0 if hits else round(min(
            parts[i][0].distance(point) for i in [tree.nearest(point)])*111000, 1)
    print(p, len(offices), 'markers;', sum(o['sourceTownId'] is None for o in offices), 'outside census town shapes', flush=True)
    return offices


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    fetch(CSV, CACHE/'localgovjp-utf8.csv')
    seeds = {r['cid'].zfill(5): r for r in csv.DictReader(
        io.StringIO((CACHE/'localgovjp-utf8.csv').read_text(encoding='utf-8-sig')))}
    cities = {c['id']: c['name'] for c in json.loads((DATA/'japan.json').read_text())['cities']}
    by_name = {(c[:2], normalize(n)): c for c, n in cities.items()}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        rows = sum(pool.map(read_pref, [f'{i:02}' for i in range(1, 48) if i != 29]), [])
    offices = {}
    primary = set()
    skipped = []
    for row in rows:
        name = row['P05_003']
        base = normalize(name).removesuffix('庁舎').removesuffix('役所').removesuffix('役場')
        city = by_name.get((row['prefecture'], base))
        location = row['P05_001']
        if city is None and location in cities and normalize(cities[location]).endswith(base):
            city = location  # Short ward-office names such as 青葉区役所.
        parent = city is None and location in cities and base.endswith('市') and normalize(cities[location]).startswith(base)
        if parent: city = location
        if city is None:
            skipped.append(dict(name=name, location=location, point=row['point']))
            continue
        marker_id = f'{city}:city-hall' if parent else city
        candidate = dict(id=marker_id, cityId=city, name=name, address=row['P05_004'],
                         point=row['point'], isCity=(parent or not cities[city].endswith(('町', '村'))),
                         coordinateSource=P05.format(p=row['prefecture']), sourceKind='P05-2022')
        if marker_id in offices:
            # Duplicate spelling variants: use the point closest to the independent seed.
            seed = seeds[city]
            def d(o): return (o['point'][0]-float(seed['lng']))**2+(o['point'][1]-float(seed['lat']))**2
            if d(offices[marker_id]) <= d(candidate): continue
        offices[marker_id] = candidate
        if not parent: primary.add(city)
    missing = sorted(set(cities)-primary)
    print('Supplemental GSI headquarters:', [(c, cities[c]) for c in missing], flush=True)
    for city in missing:
        seed = seeds[city]
        is_city = not cities[city].endswith(('町', '村'))
        distance, point, url, digest = gsi_office([float(seed['lng']), float(seed['lat'])], is_city)
        offices[city] = dict(id=city, cityId=city, name=cities[city]+('役所' if is_city else '役場'),
                            address='', point=point, isCity=is_city, coordinateSource=url,
                            coordinateSourceSha256=digest, sourceKind='GSI', seedDistanceMeters=round(distance, 1))
        print(city, cities[city], point, round(distance), 'm from seed', flush=True)
    grouped = {}
    for office in offices.values(): grouped.setdefault(office['cityId'][:2], []).append(office)
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        result = sum(pool.map(associate_pref, sorted(grouped.items())), [])
    # P05 includes former evacuation offices. Reconcile a distant mainland
    # headquarters against the GSI symbol at its municipality's independent seed.
    # These three island headquarters genuinely sit outside their own territory.
    external_island_offices = {'46303', '46304', '47381'}
    corrected = []
    affected = set()
    for office in result:
        if office['sourceTownId'] is not None or office['distanceToTerritoryMeters'] < 2000 or office['cityId'] in external_island_offices:
            continue
        city = office['cityId']
        seed = seeds[city]
        distance, point, url, digest = gsi_office([float(seed['lng']), float(seed['lat'])], office['isCity'])
        corrected.append(dict(id=office['id'], previousPoint=office['point'], previousAddress=office['address']))
        office.update(point=point, address='', coordinateSource=url, coordinateSourceSha256=digest,
                      sourceKind='GSI-reconciled', seedDistanceMeters=round(distance, 1))
        affected.add(city[:2])
    for p in sorted(affected):
        associate_pref((p, [o for o in result if o['cityId'].startswith(p)]))
    assert all(o['sourceTownId'] is not None or o['cityId'] in external_island_offices for o in result)
    assert {o['cityId'] for o in result if not o['id'].endswith(':city-hall')} == set(cities)
    assert len({o['id'] for o in result}) == len(result)
    metadata = dict(source='国土数値情報 市町村役場等及び公的集会施設 2022年・国土地理院ベクトルタイル提供実験',
                    specification='https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-v3_0.html',
                    supplementalSeedSource=CSV, supplementalSeedLicense='CC0',
                    supplementalSeedSha256=hashlib.sha256((CACHE/'localgovjp-utf8.csv').read_bytes()).hexdigest(),
                    archives={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(CACHE.glob('P05-22_*_GML.zip'))},
                    retrievedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), municipalities=len(cities),
                    officeCount=len(result), parentCityHalls=sum(o['id'].endswith(':city-hall') for o in result),
                    reconciledCoordinates=corrected,
                    noContainingTown=[dict(id=o['id'],name=o['name'],distance=o['distanceToTerritoryMeters']) for o in result if o['sourceTownId'] is None],
                    skippedRows=skipped, processing='表示専用。町への関連付けは同一自治体の実境界による包含判定。区域外の役所は実位置に表示し、町を推定しない。奈良の役所・クイズ・保存は変更しない。')
    (DATA/'japan_offices.json').write_text(json.dumps(dict(metadata=metadata,offices=sorted(result,key=lambda o:o['id'])),ensure_ascii=False,separators=(',',':'))+'\n')
    print('PASS:', len(cities), 'municipalities;', len(result), 'markers; existing Nara untouched', flush=True)


if __name__ == '__main__':
    main()
