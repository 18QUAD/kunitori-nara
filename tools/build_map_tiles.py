#!/usr/bin/env python3
"""Bake existing, attributed GIS assets into a linear lon/lat image pyramid.

No network requests. Run with the importer Python environment. Geography is
static; ownership, interaction, borders and collision-aware names stay in Flutter.
Highest level: 1024 pixels/degree (~90-110m); lower levels are area resamples.
The two layers preserve colored territory: hillshade is black alpha (grayscale multiply equivalent), details srcOver.
"""
import json
import math
from pathlib import Path
from functools import lru_cache
from PIL import Image, ImageDraw, ImageChops
from shapely.geometry import Polygon, LineString, box
from shapely.strtree import STRtree
from shapely import make_valid

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
OUT = DATA / 'map_tiles_v2'
SIZE = 256
MAX_LEVEL = 4
PPD = 64 * 2**MAX_LEVEL
SPAN = SIZE / PPD


def read(path):
    return json.loads(path.read_text())


@lru_cache(maxsize=40)
def image(path):
    return Image.open(path).convert('RGBA')


def stamp(dst, src, row, west, north, ppd, resampling=Image.Resampling.BILINEAR):
    """Affine resample only the overlap, avoiding intermediate giant images."""
    x0 = max(0, math.floor((row['west']-west)*ppd))
    y0 = max(0, math.floor((north-row['north'])*ppd))
    x1 = min(SIZE, math.ceil((row['east']-west)*ppd))
    y1 = min(SIZE, math.ceil((north-row['south'])*ppd))
    if x1 <= x0 or y1 <= y0:
        return
    sx = src.width/(row['east']-row['west'])
    sy = src.height/(row['north']-row['south'])
    part = src.transform((x1-x0, y1-y0), Image.Transform.AFFINE,
                         (sx/ppd, 0, (west-row['west'])*sx+x0*sx/ppd,
                          0, sy/ppd, (row['north']-north)*sy+y0*sy/ppd),
                         resampling)
    dst.alpha_composite(part, (x0, y0))


def coordinates(ring, west, north, scale):
    return [((p[0]-west)*scale, (north-p[1])*scale) for p in ring]


def polygons_mask(polygons, west, north, size=SIZE, ppd=PPD):
    mask = Image.new('L', (size, size))
    for polygon in polygons:
        if not polygon:
            continue
        part = Image.new('L', (size, size))
        draw = ImageDraw.Draw(part)
        draw.polygon(coordinates(polygon[0], west, north, ppd), fill=255)
        for hole in polygon[1:]:
            draw.polygon(coordinates(hole, west, north, ppd), fill=0)
        mask = ImageChops.lighter(mask, part)
    return mask


def save_merge(key, layer, tile):
    if not tile.getbbox():
        return False
    path = OUT / f'{key}_{layer}.png'
    if path.exists():
        old = Image.open(path).convert('RGBA')
        old.alpha_composite(tile)
        tile = old
    tile.save(path, optimize=True)
    return True


def main():
    OUT.mkdir(exist_ok=True)
    # All outputs are reproducible; never mix a previous pyramid into this one.
    (OUT/'index.json').unlink(missing_ok=True)
    for path in OUT.glob('*.png'):
        path.unlink()
    relief = read(DATA/'relief/index.json')['tiles']
    for row in relief:
        row['file'] = str(DATA/f"relief/{row['x']}_{row['y']}.png")
    urban = read(DATA/'urban/index.json')['tiles']
    for row in urban:
        row['file'] = str(DATA/f"urban/{row['id']}.png")
    national = read(DATA/'japan.json')
    labeldir = DATA/'map_labels'
    labeldir.mkdir(exist_ok=True)
    top_keys = set()
    coverage = {}
    for pref in national['prefectures']:
        pid = pref['id']
        # Detailed county outline avoids coarse coastal masks at the highest LOD.
        if pid == '29':
            land = pref['polygons']
        else:
            land = read(DATA/f'prefectures/{pid}.json')['polygons']
        land = [p for p in land if p and len(p[0]) >= 3]
        lands = [make_valid(Polygon(p[0], p[1:])) for p in land]
        landtree = STRtree(lands)
        xmin = min(p.bounds[0] for p in lands)
        ymin = min(p.bounds[1] for p in lands)
        xmax = max(p.bounds[2] for p in lands)
        ymax = max(p.bounds[3] for p in lands)
        water = read(DATA/('nara_water.json' if pid == '29' else f'water/{pid}.json'))
        (labeldir/f'{pid}.json').write_text(json.dumps({'lines': [], 'areas': [], 'labels': water['labels']}, ensure_ascii=False, separators=(',', ':')))
        features = [Polygon(p[0], p[1:]) for p in water['areas'] if p and len(p[0])>=3]
        features += [LineString(p) for p in water['lines'] if len(p)>=2]
        tree = STRtree(features)
        if pid == '29':
            terrain_rows = [{**read(DATA/'nara_relief.json'), 'file': str(DATA/'nara_relief.png')}]
            urban_polygons = read(DATA/'nara_urban.json')['areas']
            urbangeoms = [Polygon(p[0], p[1:]) for p in urban_polygons if p and len(p[0])>=3]
            urbantree = STRtree(urbangeoms)
        else:
            terrain_rows = relief
        count = 0
        for x in range(math.floor((xmin-120)/SPAN), math.floor((xmax-120)/SPAN)+1):
            for y in range(math.floor((48-ymax)/SPAN), math.floor((48-ymin)/SPAN)+1):
                west, north = 120+x*SPAN, 48-y*SPAN
                extent = box(west, north-SPAN, west+SPAN, north)
                ids = landtree.query(extent, predicate='intersects')
                if not len(ids):
                    continue
                mask = polygons_mask([land[int(i)] for i in ids], west, north)
                if not mask.getbbox():
                    continue
                shade = Image.new('RGBA', (SIZE, SIZE))
                for row in terrain_rows:
                    if row['west'] < west+SPAN and row['east'] > west and row['north'] > north-SPAN and row['south'] < north:
                        stamp(shade, image(row['file']), row, west, north, PPD)
                shade.putalpha(ImageChops.multiply(shade.getchannel('A'), mask))
                detail = Image.new('RGBA', (SIZE, SIZE))
                if pid == '29':
                    ids = urbantree.query(extent, predicate='intersects')
                    umask = polygons_mask([urban_polygons[int(i)] for i in ids], west, north)
                else:
                    umask_rgba = Image.new('RGBA', (SIZE, SIZE))
                    for row in urban:
                        if row['west'] < west+SPAN and row['east'] > west and row['north'] > north-SPAN and row['south'] < north:
                            source = image(row['file'])
                            stamp(umask_rgba, source, row, west, north, PPD)
                    umask = umask_rgba.getchannel('A')
                umask = ImageChops.multiply(umask, mask).point(lambda v: round(v*0x85/255))
                detail.paste((0xB6, 0xA0, 0xF5, 255), (0, 0), umask)
                # Supersample water, preserving polygon holes and islands.
                wmask = Image.new('L', (SIZE*2, SIZE*2))
                for idx in tree.query(extent):
                    geom = features[int(idx)]
                    if geom.geom_type == 'Polygon':
                        rings = [list(geom.exterior.coords), *[list(r.coords) for r in geom.interiors]]
                        part = polygons_mask([rings], west, north, SIZE*2, PPD*2)
                        wmask = ImageChops.lighter(wmask, part)
                    else:
                        ImageDraw.Draw(wmask).line(coordinates(geom.coords, west, north, PPD*2), fill=255, width=1)
                wmask = ImageChops.multiply(wmask.resize((SIZE, SIZE), Image.Resampling.LANCZOS), mask)
                water_image = Image.new('RGBA', (SIZE, SIZE), (0x79, 0xD9, 0xFF, 0))
                water_image.putalpha(wmask)
                detail.alpha_composite(water_image)
                key = f'{MAX_LEVEL}_{x}_{y}'
                a = save_merge(key, 'shade', shade)
                b = save_merge(key, 'detail', detail)
                if a or b:
                    top_keys.add((x,y))
                count += 1
        coverage[pid] = count
        print(f'{pid} {pref["name"]}: {count} tiles', flush=True)
    # Build parents with area resampling; all lower LODs retain small coastal islands.
    keys = top_keys
    levels = {MAX_LEVEL: keys}
    for level in range(MAX_LEVEL-1, -1, -1):
        parents = {(x//2,y//2) for x,y in keys}
        for x,y in sorted(parents):
            for layer in ['shade', 'detail']:
                tile = Image.new('RGBA', (SIZE*2, SIZE*2))
                for dx in range(2):
                    for dy in range(2):
                        path = OUT/f'{level+1}_{x*2+dx}_{y*2+dy}_{layer}.png'
                        if path.exists():
                            with Image.open(path) as child:
                                tile.paste(child, (dx*SIZE,dy*SIZE))
                tile = tile.resize((SIZE,SIZE),Image.Resampling.LANCZOS)
                if tile.getbbox():
                    tile.save(OUT/f'{level}_{x}_{y}_{layer}.png', optimize=True)
        keys = parents
        levels[level] = keys
        print(f'LOD {level}: {len(keys)} tiles', flush=True)
    # A black alpha layer is equivalent to multiplying by grayscale hillshade,
    # and remains correct when Flutter raster-caches it in a RepaintBoundary.
    for path in OUT.glob('*_shade.png'):
        with Image.open(path) as source:
            source = source.convert('RGBA')
            alpha = ImageChops.multiply(ImageChops.invert(source.convert('L')), source.getchannel('A'))
            tile = Image.new('RGBA', source.size)
            tile.putalpha(alpha)
            tile.save(path, optimize=True)
    # Transparent details may be absent: explicitly list available layers.
    tiles = {p.stem: p.stat().st_size for p in sorted(OUT.glob('*.png'))}
    manifest = {'schema': 1, 'tileSize': SIZE, 'west':120, 'north':48, 'basePixelsPerDegree':64,
                'maxLevel':MAX_LEVEL, 'layers':['shade','detail'], 'tiles':tiles,
                'prefectureCoverage':coverage, 'attribution':'国土地理院・国土交通省の既存取得データを加工。原典・年次は各取込レポートを参照。',
                'processing':'経緯度画像タイル。地形陰影と透過の市街地・水域を分離。下位LODは面積縮小。人口・町ID・保存データは変更しない。'}
    (OUT/'index.json').write_text(json.dumps(manifest, ensure_ascii=False,separators=(',',':')))
    # National labels are already filtered for overview density.
    water = read(DATA/'water/national.json')
    (labeldir/'national.json').write_text(json.dumps({'lines':[], 'areas':[], 'labels':water['labels']}, ensure_ascii=False,separators=(',',':')))
    from restore_nara_water_tiles import restore
    restore(OUT)
    from build_national_water_tiles import build
    build(OUT)
    print(f'{len(tiles)} base images, {sum(tiles.values())/1024**2:.1f} MiB', flush=True)

if __name__ == '__main__':
    main()
