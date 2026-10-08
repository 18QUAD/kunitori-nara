"""Extract mountain-name annotation positions from the cached GSI vector tiles.

Requires mapbox-vector-tile and shapely, like import_water.py. Annotation points
are cartographic label positions, not surveyed summit coordinates.
"""
import datetime
import json
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from import_water import CACHE, OUT, SOURCE, SPEC, ZOOM, coordinate, download, tile_index


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((OUT/'nara.json').read_text())
    county = unary_union([Polygon(p[0], p[1:]).buffer(0) for t in atlas['towns'] for p in t['polygons']])
    west, south, east, north = county.bounds
    x0, y0 = tile_index(west, north)
    x1, y1 = tile_index(east, south)
    labels, seen = [], set()
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            _, _, layers = download((x, y))
            layer = layers.get('label', {'features': [], 'extent': 4096})
            for feature in layer['features']:
                p, g = feature['properties'], feature['geometry']
                if p.get('annoCtg') != 312 or g['type'] != 'Point':
                    continue
                px, py = g['coordinates']
                lon, lat = coordinate(x+px/layer['extent'], y+py/layer['extent'])
                if not county.covers(Point(lon, lat)):
                    continue
                name = p.get('annoChar', '')
                point = [round(lon, 6), round(lat, 6)]
                key = (name, *point)
                if name and key not in seen:
                    labels.append(dict(name=name, point=point))
                    seen.add(key)
    labels.sort(key=lambda p: (p['name'], p['point']))
    if not labels:
        raise ValueError('No mountain labels found')
    water_meta = json.loads((OUT/'nara_water.json').read_text())['metadata']
    metadata = dict(source=SOURCE, specification=SPEC, sourceUpdated=water_meta['sourceUpdated'],
                    generated=datetime.datetime.now(datetime.timezone.utc).isoformat(), zoom=ZOOM,
                    count=len(labels), attribution='国土地理院ベクトルタイル提供実験を加工して作成',
                    processing='山・岳・峰等の注記（annoCtg=312）から奈良県内の注記位置を抽出し重複を除去。座標は山頂ではなく地図上の注記位置。')
    (OUT/'nara_mountains.json').write_text(json.dumps(dict(metadata=metadata, labels=labels), ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == '__main__':
    main()
