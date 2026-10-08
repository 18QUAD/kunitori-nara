"""Extract offline Nara rivers, water polygons and names from GSI vector tiles.

Requires mapbox-vector-tile and shapely. Tiles are cached under data/raw/water.
Only surface rivers/canals (5301/5321) and water areas (5000) are included;
underground canals and dry riverbeds are not drawn as surface water.
"""
import concurrent.futures
import datetime
import json
import math
from pathlib import Path
import urllib.request

import mapbox_vector_tile
from shapely.geometry import Polygon, shape, box, mapping
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/data'
CACHE = ROOT / 'data/raw/water'
ZOOM = 11
SOURCE = 'https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf'
SPEC = 'https://raw.githubusercontent.com/gsi-cyberjapan/gsimaps-vector-experiment/master/README.md'


def coordinate(x, y):
    return x / 2**ZOOM * 360 - 180, math.degrees(math.atan(math.sinh(math.pi*(1-2*y/2**ZOOM))))


def tile_index(lon, lat):
    return int((lon+180)/360*2**ZOOM), int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**ZOOM)


def download(pair):
    x, y = pair
    path = CACHE / f'{ZOOM}_{x}_{y}.pbf'
    if not path.exists():
        data = urllib.request.urlopen(SOURCE.format(z=ZOOM, x=x, y=y), timeout=60).read()
        mapbox_vector_tile.decode(data)  # Validate before caching.
        path.write_bytes(data)
    return x, y, mapbox_vector_tile.decode(path.read_bytes(), default_options={'y_coord_down': True})


def components(geom, kind):
    if geom.is_empty:
        return
    if geom.geom_type == kind:
        yield geom
    elif hasattr(geom, 'geoms'):
        for part in geom.geoms:
            yield from components(part, kind)


def rounded(coords):
    if isinstance(coords[0], (int, float)):
        return [round(c, 6) for c in coords]
    return [rounded(c) for c in coords]


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((OUT/'nara.json').read_text())
    county = unary_union([Polygon(poly[0], poly[1:]).buffer(0) for t in atlas['towns'] for poly in t['polygons']])
    west, south, east, north = county.bounds
    x0, y0 = tile_index(west, north)
    x1, y1 = tile_index(east, south)
    pairs = [(x, y) for y in range(y0, y1+1) for x in range(x0, x1+1)]
    lines, areas, labels = [], [], []
    seen = set()
    spec = urllib.request.urlopen(SPEC, timeout=30).read().decode()
    (CACHE/'specification.md').write_text(spec)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for x, y, layers in pool.map(download, pairs):
            a, b = coordinate(x, y+1), coordinate(x+1, y)
            clip = county.intersection(box(a[0], a[1], b[0], b[1]))
            if clip.is_empty:
                continue
            for layer_name in ['river', 'waterarea', 'label']:
                layer = layers.get(layer_name, {'features': [], 'extent': 4096})
                extent = layer['extent']
                def project(c):
                    if isinstance(c[0], (int, float)):
                        return coordinate(x+c[0]/extent, y+c[1]/extent)
                    return [project(p) for p in c]
                for feature in layer['features']:
                    p = feature['properties']
                    if layer_name == 'river' and p.get('ftCode') not in [5301, 5321]:
                        continue
                    if layer_name == 'waterarea' and p.get('ftCode') != 5000:
                        continue
                    if layer_name == 'label' and p.get('annoCtg') not in [321, 322, 820]:
                        continue
                    geo = feature['geometry']
                    geom = shape({'type': geo['type'], 'coordinates': project(geo['coordinates'])})
                    if not geom.is_valid:
                        geom = geom.buffer(0)
                    geom = geom.intersection(clip)
                    if layer_name == 'label':
                        if geom.geom_type == 'Point' and not geom.is_empty:
                            name = p.get('annoChar', '')
                            key = (name, round(geom.x, 5), round(geom.y, 5))
                            if name and key not in seen:
                                labels.append({'name': name, 'point': rounded([geom.x, geom.y])})
                                seen.add(key)
                    else:
                        kind = 'LineString' if layer_name == 'river' else 'Polygon'
                        for part in components(geom, kind):
                            coords = rounded(mapping(part)['coordinates'])
                            key = (kind, json.dumps(coords, separators=(',', ':')))
                            if key not in seen:
                                (lines if kind == 'LineString' else areas).append(coords)
                                seen.add(key)
    if not lines or not areas:
        raise ValueError('No river/water features found')
    import re
    updated = re.search(r'データ更新情報.*?(\d{4}年\d+月\d+日時点)', spec, re.S)
    report = dict(source=SOURCE, specification=SPEC, sourceUpdated=updated.group(1) if updated else '未確認',
                  attribution='国土地理院ベクトルタイル提供実験を加工して作成',
                  retrieved=datetime.datetime.now(datetime.timezone.utc).isoformat(), zoom=ZOOM,
                  tiles=len(pairs), riverParts=len(lines), waterPolygons=len(areas), names=len(labels),
                  processing='地表の河川・人工水路、水域、河川・湖沼注記を抽出。タイル境界と奈良県境で切り出し、経緯度小数6桁に丸め。地下水路・枯れ川を除外。')
    (OUT/'nara_water.json').write_text(json.dumps(dict(metadata=report, lines=lines, areas=areas, labels=labels), ensure_ascii=False, separators=(',', ':'))+'\n')
    print(json.dumps(report, ensure_ascii=False))
    print('Names:', ', '.join(sorted(set(x['name'] for x in labels))))


if __name__ == '__main__':
    main()
