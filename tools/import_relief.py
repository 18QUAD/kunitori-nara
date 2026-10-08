"""Download GSI DEM PNG tiles and generate a georeferenced, offline hillshade.

Requires numpy and Pillow. Uses GSI dem_png at zoom 11 (~63 m at Nara).
PNG elevation encoding: signed 24-bit centimetres; 0x800000 is no data.
"""
import concurrent.futures
import datetime
import io
import json
import math
from pathlib import Path
import urllib.request
import urllib.error

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'data/raw/relief'
OUT = ROOT / 'assets/data'
ZOOM = 11
TEMPLATE = 'https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png'


def pixel(lon, lat):
    n = 256 * 2**ZOOM
    return (lon + 180) / 360 * n, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n


def tile(pair):
    x, y = pair
    path = CACHE / f'{ZOOM}_{x}_{y}.png'
    if not path.exists():
        url = TEMPLATE.format(z=ZOOM, x=x, y=y)
        try:
            data = urllib.request.urlopen(url, timeout=60).read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return x, y, np.full((256, 256), np.nan)
            raise
        Image.open(io.BytesIO(data)).verify()
        path.write_bytes(data)
    rgb = np.asarray(Image.open(path).convert('RGB'), dtype=np.int32)
    value = rgb[:, :, 0] * 65536 + rgb[:, :, 1] * 256 + rgb[:, :, 2]
    valid = value != 0x800000
    elevation = np.where(value >= 0x800000, value - 0x1000000, value) * 0.01
    elevation[~valid] = np.nan
    return x, y, elevation


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((OUT / 'nara.json').read_text())
    points = np.array([p for t in atlas['towns'] for poly in t['polygons'] for ring in poly for p in ring])
    west, south = points.min(axis=0) - 0.005
    east, north = points.max(axis=0) + 0.005
    left, top = pixel(west, north)
    right, bottom = pixel(east, south)
    x0, y0 = int(left // 256), int(top // 256)
    x1, y1 = int(right // 256), int(bottom // 256)
    dem = np.full(((y1-y0+1)*256, (x1-x0+1)*256), np.nan)
    pairs = [(x, y) for y in range(y0, y1+1) for x in range(x0, x1+1)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for x, y, data in pool.map(tile, pairs):
            dem[(y-y0)*256:(y-y0+1)*256, (x-x0)*256:(x-x0+1)*256] = data
    # Resample Mercator tiles onto the same linear lon/lat grid as TerritoryMap.
    width = math.ceil(right-left)
    height = math.ceil((north-south)/(east-west)*width/0.826)
    lon = np.linspace(west, east, width)
    lat = np.linspace(north, south, height)
    xs = (lon+180)/360 * (256*2**ZOOM) - x0*256
    ys = (1-np.arcsinh(np.tan(np.radians(lat)))/math.pi)/2 * (256*2**ZOOM) - y0*256
    grid = dem[np.rint(ys).astype(int)[:, None], np.rint(xs).astype(int)[None, :]]
    mask = Image.new('1', (width, height))
    for town in atlas['towns']:
        for poly in town['polygons']:
            part = Image.new('1', (width, height))
            draw = ImageDraw.Draw(part)
            for index, ring in enumerate(poly):
                draw.polygon([((p[0]-west)/(east-west)*(width-1), (north-p[1])/(north-south)*(height-1)) for p in ring], fill=1 if index == 0 else 0)
            mask.paste(1, mask=part)
    valid = np.isfinite(grid)
    if not valid[np.asarray(mask)].all():
        raise ValueError('Missing DEM pixels inside Nara; refusing to invent elevations')
    minimum, maximum = float(np.nanmin(grid)), float(np.nanmax(grid))
    grid = np.nan_to_num(grid)  # Outside-prefecture gaps remain transparent below.
    dx = (east-west)*111320*math.cos(math.radians((north+south)/2))/(width-1)
    dy = (north-south)*111320/(height-1)
    gy, gx = np.gradient(grid, dy, dx)
    # Light from northwest, altitude 45 degrees. Exaggerate relief for a small map.
    normal = np.stack([-gx*2, gy*2, np.ones_like(grid)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    light = np.array([-0.5, 0.5, math.sqrt(0.5)])
    shade = np.clip(normal @ light, 0, 1)
    gray = np.uint8(np.clip(0.30 + 0.70*shade, 0, 1)*255)
    rgba = np.dstack([gray, gray, gray, np.uint8(valid)*255])
    Image.fromarray(rgba).save(OUT / 'nara_relief.png', optimize=True)
    report = dict(west=float(west), south=float(south), east=float(east), north=float(north),
                  width=width, height=height, zoom=ZOOM, tiles=len(pairs),
                  source=TEMPLATE, attribution='国土地理院の標高タイルを加工して作成',
                  retrieved=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  processing='経緯度グリッドに再投影、北西光源・高度45度、陰影計算の高さ強調2倍',
                  sampleSpacingMetres=round(dx, 1), minElevation=minimum, maxElevation=maximum, missingPixelsInsideNara=0)
    (OUT / 'nara_relief.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
