"""Supplement overview water names with GSI zoom-14 municipal annotations.

Requires the same dependencies as import_water.py. Keeps river/area geometry.
Run after import_water.py when refreshing the bundled water dataset.
"""
import concurrent.futures
import datetime
import json
from shapely.geometry import Point, Polygon, box
from shapely.ops import unary_union
import import_water as water


def main():
    water.ZOOM = 14
    atlas = json.loads((water.OUT / 'nara.json').read_text())
    county = unary_union([Polygon(p[0], p[1:]).buffer(0)
                          for t in atlas['towns'] for p in t['polygons']])
    west, south, east, north = county.bounds
    x0, y0 = water.tile_index(west, north)
    x1, y1 = water.tile_index(east, south)
    pairs = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
             if county.intersects(box(*water.coordinate(x, y + 1),
                                      *water.coordinate(x + 1, y)))]
    target = water.OUT / 'nara_water.json'
    data = json.loads(target.read_text())
    labels = [l for l in data['labels'] if not l.get('detail')]
    seen = {(l['name'], *l['point']) for l in labels}
    print(f'Fetching {len(pairs)} detailed tiles', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for i, (x, y, layers) in enumerate(pool.map(water.download, pairs)):
            layer = layers.get('label', {'features': [], 'extent': 4096})
            for feature in layer['features']:
                p, g = feature['properties'], feature['geometry']
                if p.get('annoCtg') not in [321, 322, 820] or g['type'] != 'Point':
                    continue
                px, py = g['coordinates']
                lon, lat = water.coordinate(x + px / layer['extent'], y + py / layer['extent'])
                name = p.get('knj') or p.get('annoChar')
                point = [round(lon, 6), round(lat, 6)]
                key = (name, *point)
                if name and key not in seen and county.covers(Point(lon, lat)):
                    labels.append(dict(name=name, point=point, detail=True))
                    seen.add(key)
            if i % 100 == 0:
                print(f'{i + 1}/{len(pairs)} tiles, {len(labels)} names', flush=True)
    data['labels'] = labels
    data['metadata'].update(names=len(labels), labelZooms=[11, 14],
                            detailLabelsRetrieved=datetime.datetime.now(datetime.timezone.utc).isoformat())
    target.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'Saved {len(labels)} annotations', flush=True)


if __name__ == '__main__':
    main()
