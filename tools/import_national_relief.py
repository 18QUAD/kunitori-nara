"""Generate offline prefecture hillshade from GSI DEM (zoom 10, ~125 m).

Requires numpy, Pillow, shapely. Tile patches avoid enormous offshore bounding
boxes. Missing source elevations stay transparent and are counted in the report.
All downloads use the environment's standard urllib proxy and TLS configuration.
"""
import concurrent.futures
import datetime
import io
import json
import math
import time
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.geometry import Polygon, box

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/data/relief'
CACHE = ROOT / 'data/raw/national_relief'
ZOOM = 10
SOURCE = 'https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png'


def bounds(x, y):
    n = 2 ** ZOOM
    latitude = lambda v: math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * v / n))))
    return x / n * 360 - 180, latitude(y + 1), (x + 1) / n * 360 - 180, latitude(y)


def candidates(polygons):
    result = set()
    for rings in polygons:
        polygon = Polygon(rings[0], rings[1:])
        west, south, east, north = polygon.bounds
        tx = lambda lon: int((lon + 180) / 360 * 2 ** ZOOM)
        ty = lambda lat: int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * 2 ** ZOOM)
        for x in range(tx(west), tx(east) + 1):
            for y in range(ty(north), ty(south) + 1):
                if polygon.intersects(box(*bounds(x, y))):
                    result.add((x, y))
    return sorted(result)


def generate(pair):
    x, y = pair
    cache = CACHE / f'{x}_{y}.png'
    if not cache.exists():
        for attempt in range(4):
            try:
                raw = urllib.request.urlopen(SOURCE.format(z=ZOOM, x=x, y=y), timeout=45).read()
                Image.open(io.BytesIO(raw)).verify()
                cache.write_bytes(raw)
                break
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    return dict(x=x, y=y, missingPixels=65536, available=False)
                if attempt == 3:
                    raise
                time.sleep(attempt + 1)
    rgb = np.asarray(Image.open(cache).convert('RGB'), dtype=np.int32)
    value = rgb[:, :, 0] * 65536 + rgb[:, :, 1] * 256 + rgb[:, :, 2]
    valid = value != 0x800000
    elevation = np.where(value >= 0x800000, value - 0x1000000, value) * .01
    west, south, east, north = bounds(x, y)
    latitudes = np.linspace(north, south, 256)
    rows = np.rint((1 - np.arcsinh(np.tan(np.radians(latitudes))) / math.pi) / 2 * (256 * 2 ** ZOOM) - y * 256).astype(int).clip(0, 255)
    elevation, valid = elevation[rows], valid[rows]
    # Invalid values must not create fictitious coastal cliffs in adjacent pixels.
    elevation[~valid] = 0
    gy, gx = np.gradient(elevation, (north-south)*111320/255, (east-west)*111320*math.cos(math.radians((north+south)/2))/255)
    interior = valid.copy()
    interior[1:] &= valid[:-1]
    interior[:-1] &= valid[1:]
    interior[:, 1:] &= valid[:, :-1]
    interior[:, :-1] &= valid[:, 1:]
    normal = np.stack([-gx*2, gy*2, np.ones_like(elevation)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    shade = np.clip(normal @ np.array([-.5, .5, math.sqrt(.5)]), 0, 1)
    gray = np.uint8((.30 + .70*shade)*255)
    Image.fromarray(np.dstack([gray, gray, gray, np.uint8(interior)*255])).save(OUT / f'{x}_{y}.png', optimize=True)
    return dict(x=x, y=y, west=west, south=south, east=east, north=north, missingPixels=int((~valid).sum()), available=True)


def main():
    OUT.mkdir(exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((ROOT / 'assets/data/japan.json').read_text())
    prefectures = {p['id']: candidates(p['polygons']) for p in atlas['prefectures'] if p['id'] != '29'}
    pairs = sorted(set(pair for items in prefectures.values() for pair in items))
    records = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for i, record in enumerate(pool.map(generate, pairs), 1):
            records[(record['x'], record['y'])] = record
            if i % 50 == 0:
                print(f'{i}/{len(pairs)} tiles', flush=True)
    report = dict(zoom=ZOOM, source=SOURCE, attribution='国土地理院の標高タイルを加工して作成', retrieved=datetime.datetime.now(datetime.timezone.utc).isoformat(), processing='経緯度グリッド、北西光源・高度45度、高さ強調2倍。標高欠損と隣接画素は透明。奈良県は既存の約63mデータを維持。', tiles=list(records.values()), prefectures={key: [f'{x}_{y}' for x, y in pairs if records[(x, y)]['available']] for key, pairs in prefectures.items()})
    assert all(report['prefectures'].values()), 'A prefecture has no elevation tiles'
    (OUT / 'index.json').write_text(json.dumps(report, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f"Generated {len(records)} tiles for {len(prefectures)} prefectures", flush=True)


if __name__ == '__main__':
    main()
