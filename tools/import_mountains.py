"""Extract mountain labels from GSI vector tiles and separate official summits.

Requires mapbox-vector-tile and shapely, like import_water.py. Annotation points
are cartographic label positions, not surveyed summit coordinates.
"""
import datetime
import argparse
import hashlib
import json
import urllib.request
from pathlib import Path
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from import_water import CACHE, OUT, SOURCE, SPEC, ZOOM, coordinate, download, tile_index

SUMMIT_SOURCE = 'https://maps.gsi.go.jp/overlay/mount1003/mount1003.geojson'


def add_summits(document, county, source_file=None):
    raw = (Path(source_file).read_bytes() if source_file else
           urllib.request.urlopen(SUMMIT_SOURCE, timeout=60).read())
    features = json.loads(raw)['features']
    summits, seen = [], set()
    for feature in features:
        geometry, props = feature['geometry'], feature['properties']
        if geometry['type'] != 'Point':
            continue
        point = geometry['coordinates'][:2]
        if not county.covers(Point(point)):
            continue
        name = props['山名']
        # The additional 1056 m Kongosan point is the Osaka prefectural
        # high point on the slope, not the 1125 m summit in Nara.
        if name == '金剛山' and props.get('標高(m）') == '1056':
            continue
        if props.get('山頂名'):
            name += '（' + props['山頂名'] + '）'
        key = (name, *point)
        if key not in seen:
            summits.append(dict(name=name, point=point))
            seen.add(key)
    if not summits:
        raise ValueError('No official summit coordinates found in Nara')
    document['summits'] = sorted(summits, key=lambda s: (s['name'], s['point']))
    document['metadata']['summits'] = dict(
        source=SUMMIT_SOURCE, sourceCount=len(features), count=len(summits),
        retrieved=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        sha256=hashlib.sha256(raw).hexdigest(),
        attribution='国土地理院「日本の主な山岳」データを加工して作成',
        processing='同梱の奈良県境界内にある公式座標を変更せず抽出。金剛山1056mの府内最高地点は山頂ではないため除外。境界外の県境付近の山と公式データ未収録の山は含まない。山名注記の位置から山頂を推測しない。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summits-only', action='store_true',
                        help='Preserve bundled annotation positions and refresh only summits')
    parser.add_argument('--summit-file', help='Use a downloaded official GeoJSON')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((OUT/'nara.json').read_text())
    county = unary_union([Polygon(p[0], p[1:]).buffer(0) for t in atlas['towns'] for p in t['polygons']])
    if args.summits_only:
        path = OUT/'nara_mountains.json'
        document = json.loads(path.read_text())
        add_summits(document, county, args.summit_file)
        path.write_text(json.dumps(document, ensure_ascii=False, indent=2)+'\n')
        print(json.dumps(document['metadata']['summits'], ensure_ascii=False))
        return
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
    document = dict(metadata=metadata, labels=labels)
    add_summits(document, county, args.summit_file)
    (OUT/'nara_mountains.json').write_text(json.dumps(document, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == '__main__':
    main()
