"""Rebuild municipal headquarters from MLIT P05 and GSI office symbols.
Requires shapely, pyshp, mapbox-vector-tile. Main offices only (P05_002=1).
Official address corrections are reviewed in office_overrides.json.
"""
import concurrent.futures
import datetime
import hashlib
import io
import json
import math
from pathlib import Path
import urllib.request
import zipfile
import mapbox_vector_tile
import shapefile
from shapely.geometry import Polygon, Point

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'data/raw/offices'
ZIP_URL = 'https://nlftp.mlit.go.jp/ksj/gml/data/P05/P05-22/P05-22_29_GML.zip'
TILE_URL = 'https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/14/{x}/{y}.pbf'


def tile(pair):
    x, y = pair
    path = CACHE / f'14_{x}_{y}.pbf'
    url = TILE_URL.format(x=x, y=y)
    if not path.exists():
        path.write_bytes(urllib.request.urlopen(url, timeout=60).read())
    out = []
    for layer in mapbox_vector_tile.decode(path.read_bytes(), default_options={'y_coord_down': True}).values():
        for f in layer['features']:
            code = f['properties'].get('ftCode')
            if code not in (3205, 3206):
                continue
            px, py = f['geometry']['coordinates']
            extent = layer['extent']
            lon = (x + px / extent) / 2**14 * 360 - 180
            lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + py / extent) / 2**14))))
            out.append({'point': [lon, lat], 'symbol_code': code, 'source': url,
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return out


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / 'P05-22_29_GML.zip'
    if not archive.exists():
        archive.write_bytes(urllib.request.urlopen(ZIP_URL, timeout=60).read())
    review = json.loads((ROOT / 'tools/office_overrides.json').read_text())
    atlas = json.loads((ROOT / 'assets/data/nara.json').read_text())
    with zipfile.ZipFile(archive) as z:
        stem = 'P05-22_29'
        reader = shapefile.Reader(**{e: io.BytesIO(z.read(stem + '.' + e)) for e in ['shp', 'shx', 'dbf']}, encoding='cp932')
        rows = [(r.record.as_dict(), list(r.shape.points[0])) for r in reader.iterShapeRecords() if r.record['P05_002'] == '1']
    assert len(rows) == 39
    pairs = set()
    for d, original in rows:
        lon, lat = review['overrides'].get(d['P05_001'], {}).get('seed', original)
        x = int((lon + 180) / 360 * 2**14)
        y = int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2**14)
        pairs.update((x + dx, y + dy) for dx in [-1, 0, 1] for dy in [-1, 0, 1])
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        features = [f for fs in pool.map(tile, sorted(pairs)) for f in fs]
    offices = []
    for d, original in rows:
        city = d['P05_001']
        override = review['overrides'].get(city, {})
        lon, lat = override.get('seed', original)
        code = 3205 if city.startswith('292') else 3206
        candidates = [f for f in features if f['symbol_code'] == code]
        f = min(candidates, key=lambda f: (f['point'][0] - lon)**2 * .826**2 + (f['point'][1] - lat)**2)
        distance = math.hypot((f['point'][0] - lon)*.826, f['point'][1] - lat)*111000
        if distance > 1000:
            raise ValueError(f'Office needs manual review: {city}, distance {distance}')
        point = Point(f['point'])
        hits = [t for t in atlas['towns'] if t['cityId'] == city and any(Polygon(p[0], p[1:]).buffer(0).covers(point) for p in t['polygons'])]
        if len(hits) != 1:
            raise ValueError(f'Office must fall inside exactly one census territory: {city}, {hits}')
        offices.append({'cityId': city, 'name': d['P05_003'], 'address': override.get('address', d['P05_004']),
            'point': f['point'], 'sourceTownId': hits[0]['id'], 'sourceTownName': hits[0]['name'],
            'officialUrl': override.get('source', review['official_urls'][city]),
            'coordinateSource': f['source'], 'coordinateSourceSha256': f['sha256'], 'symbolCode': code})
    assert {o['cityId'] for o in offices} == {c['id'] for c in atlas['cities']}
    metadata = {'source': ZIP_URL, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'specification': 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-P05-v3_0.html',
        'positionSource': '国土地理院ベクトルタイル提供実験 市役所3205・町村役場3206を加工',
        'retrievedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'addressCheckDate': review['address_check_date'], 'addressCheckUnavailable': review['address_check_unavailable'],
        'processing': '本庁舎のみ。公式所在地と地理院の役所記号を照合。記号座標を国勢調査の町境界に包含判定。分庁舎・支所は対象外。'}
    (ROOT / 'assets/data/nara_offices.json').write_text(json.dumps({'metadata': metadata, 'offices': offices}, ensure_ascii=False, indent=2)+'\n')
    def quote(s):
        return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"
    out = ["// Generated by tools/import_offices.py. Sources: assets/data/nara_offices.json.", "import 'municipal_office.dart';", '', 'const municipalOffices = <MunicipalOffice>[']
    for o in offices:
        fields = [quote(o[k]) for k in ['cityId','name','sourceTownId','address','officialUrl']]
        fields += [str(v) for v in o['point']]
        out.append('  MunicipalOffice('+', '.join(fields)+'),')
        print(o['name'], o['sourceTownName'], o['point'])
    out += ['];', '']
    (ROOT / 'lib/municipal_offices.dart').write_text('\n'.join(out))


if __name__ == '__main__':
    main()
