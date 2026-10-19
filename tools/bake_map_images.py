"""Bake complete backgrounds and thin transparent boundaries; no runtime GIS.

Existing attributed inputs only. 512px tiles, a power-of-two geographic pyramid.
Fine backgrounds are rendered from original water contours (never enlarged water
bitmaps). Areas without water can reuse their identical coarser shaded surface.
Run export_border_groups.dart first. Outputs are resumable, deterministic and
independent of gameplay/save data. Delete outputs when changing rendering rules.
"""
import argparse
import concurrent.futures as futures
from functools import lru_cache
import json
import math
from pathlib import Path
import hashlib

from PIL import Image, ImageDraw, ImageChops
import shapely
from shapely.geometry import Polygon, LineString, box
from shapely.strtree import STRtree
from build_border_tiles import joined, outlines, chunks
from restore_nara_water_tiles import nara_scale
from optimize_map_images import DELIVERY_MARKER

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
OUT = DATA / 'map_images'
SIZE, AA = 512, 2
MAX_LEVEL = 8
BACKGROUND_BASE_LEVEL = 5
SOURCE = DATA / 'map_tiles_uniform'
MIN_LEVEL = -3


def read(path):
    return json.loads(path.read_text())


def cells_for(shape, level, margin=0):
    west, south, east, north = shape.bounds
    span = 4 / 2**level
    return ((x, y)
            for x in range(math.floor((west-120-margin)/span), math.floor((east-120+margin)/span)+1)
            for y in range(math.floor((48-north-margin)/span), math.floor((48-south+margin)/span)+1))


@lru_cache(maxsize=24)
def source_image(name):
    with Image.open(SOURCE / name) as im:
        return im.convert('RGBA')


def source_layer(level, x, y, layer):
    # Source tiles are 256px. Render/crop their finest available data into the
    # new 512px cell without creating a giant intermediate image.
    lod = min(5 if layer == 'shade' else 6, max(0, level+1))
    span = 4 / 2**level
    childspan = 4 / 2**lod
    west, north = 120+x*span, 48-y*span
    ppd = SIZE/span
    result = Image.new('RGBA', (SIZE, SIZE))
    for cx in range(math.floor(x*span/childspan), math.ceil((x+1)*span/childspan)):
        for cy in range(math.floor(y*span/childspan), math.ceil((y+1)*span/childspan)):
            key = f'{lod}_{cx}_{cy}_{layer}'
            if key not in SOURCE_KEYS:
                continue
            name = ('' if layer == 'shade' else 'dry_') + key + '.webp'
            ox, oy = cx*childspan-x*span, cy*childspan-y*span
            area = (max(0, round(ox*ppd)), max(0, round(oy*ppd)),
                    min(SIZE, round((ox+childspan)*ppd)), min(SIZE, round((oy+childspan)*ppd)))
            if area[2] <= area[0] or area[3] <= area[1]:
                continue
            ratio = 256/childspan/ppd
            tile = source_image(name).transform((area[2]-area[0], area[3]-area[1]), Image.Transform.AFFINE,
                (ratio, 0, (area[0]/ppd-ox)*256/childspan,
                 0, ratio, (area[1]/ppd-oy)*256/childspan), Image.Resampling.BILINEAR)
            result.alpha_composite(tile, area[:2])
    return result


def parts(geometry):
    if geometry.geom_type == 'Polygon':
        yield geometry
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms:
            yield from parts(part)


def water_parts(geometry):
    if geometry.geom_type in ('Polygon', 'LineString'):
        if not geometry.is_empty: yield geometry
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms: yield from water_parts(part)


def polygon_mask(shapes, west, north, ppd):
    result = Image.new('L', (SIZE*AA, SIZE*AA))
    draw = ImageDraw.Draw(result)
    for shape in shapes:
        for polygon in parts(shape):
            for ring, color in [(polygon.exterior, 255), *[(r, 0) for r in polygon.interiors]]:
                draw.polygon([((lon-west)*ppd*AA, (north-lat)*ppd*AA) for lon, lat in ring.coords], fill=color)
    return result.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def render_background(item):
    level, x, y, layer = item
    key = f'{level}_{x}_{y}_{layer}'
    path = OUT / f'{key}.webp'
    span = 4 / 2**level
    west, north = 120+x*span, 48-y*span
    ppd = SIZE/span
    extent = box(west, north-span, west+span, north)
    water, tree = (OVERVIEW, OVERVIEW_TREE) if layer == 'overview' else (WATER, WATER_TREE)
    water_hits = tree.query(extent.buffer(.0004), predicate='intersects')
    if layer == 'background' and level > BACKGROUND_BASE_LEVEL and not len(water_hits):
        # A long winding river's bounding box is not water coverage. Avoid
        # baking thousands of dry fine cells inside those bounding rectangles.
        path.unlink(missing_ok=True)
        return None
    if path.exists():
        return key, path.stat().st_size
    hits = LAND_TREE.query(extent, predicate='intersects')
    if not len(hits):
        return None
    margin = max(.0004, 4/ppd)
    if any(LAND[int(i)].covers(extent.buffer(4/ppd)) for i in hits):
        land = Image.new('L', (SIZE, SIZE), 255)
    else:
        land = polygon_mask([shapely.clip_by_rect(LAND[int(i)], west-4/ppd, north-span-4/ppd,
                             west+span+4/ppd, north+4/ppd) for i in hits], west, north, ppd)
    if not land.getbbox():
        return None
    image = Image.new('RGBA', (SIZE, SIZE), (67, 97, 106, 255))
    image.alpha_composite(source_layer(level, x, y, 'shade'))
    image.alpha_composite(source_layer(level, x, y, 'detail'))
    visible_water = [part for hit in water_hits
        # A subpixel pond must not become a full raster sample at overview
        # scales. Fine backgrounds still retain the original small water areas.
        if not (level <= 4 and water[int(hit)].geom_type == 'Polygon'
                and water[int(hit)].area * ppd * ppd < .25)
        for part in water_parts(
        shapely.clip_by_rect(water[int(hit)], west-margin, north-span-margin,
                            west+span+margin, north+margin))]
    # Two antialiased passes reproduce the existing Nara water widths/caps.
    for color, width in [((18, 61, 89), .625), ((121, 217, 255), .375)]:
        mask = Image.new('L', (SIZE*AA, SIZE*AA))
        draw = ImageDraw.Draw(mask)
        pixel_width = width / WATER_SCALE * ppd * AA
        stroke = max(1, round(pixel_width))
        coverage = round(255 * min(1, pixel_width))
        for shape in visible_water:
            rings = [shape.coords] if shape.geom_type == 'LineString' else [shape.exterior.coords, *[r.coords for r in shape.interiors]]
            for r, ring in enumerate(rings):
                points = [((lon-west)*ppd*AA, (north-lat)*ppd*AA) for lon, lat in ring]
                if shape.geom_type == 'Polygon' and color == (121, 217, 255):
                    draw.polygon(points, fill=255 if r == 0 else 0)
                    if coverage < 255:
                        continue
                draw.line(points, fill=coverage, width=stroke, joint='curve')
                if shape.geom_type == 'LineString' and stroke > 1:
                    radius = stroke/2
                    for px, py in (points[0], points[-1]):
                        draw.ellipse((px-radius, py-radius, px+radius, py+radius), fill=coverage)
        mask = mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        overlay = Image.new('RGBA', (SIZE, SIZE), (*color, 0))
        overlay.putalpha(mask)
        image.alpha_composite(overlay)
    image.putalpha(ImageChops.multiply(image.getchannel('A'), land))
    temporary = path.with_suffix('.render.tmp')
    image.save(temporary, format='WEBP', quality=50, method=4, exact=True,
               xmp=DELIVERY_MARKER)
    temporary.replace(path)
    return key, path.stat().st_size


def initialize_background():
    global SOURCE_KEYS, LAND, LAND_TREE, WATER, WATER_TREE, OVERVIEW, OVERVIEW_TREE, WATER_SCALE
    SOURCE_KEYS = set(read(SOURCE / 'index-dry.json')['tiles'])
    LAND = [shapely.from_wkb((ROOT / f'data/raw/shared_prefectures/{pid:02}.wkb').read_bytes()) for pid in range(1,48)]
    shapely.prepare(LAND)
    LAND_TREE = STRtree(LAND)
    WATER_SCALE = nara_scale(read(DATA/'nara.json'))
    def load_water(ids):
        shapes = []
        for pid in ids:
            data = read(DATA / ('nara_water.json' if pid == '29' else f'water/{pid}.json'))
            shapes.extend(Polygon(r[0], r[1:]) for r in data['areas'])
            shapes.extend(LineString(r) for r in data['lines'] if len(r) >= 2)
        return shapes
    WATER = load_water([f'{pid:02}' for pid in range(1,48)])
    OVERVIEW = load_water(['national'])
    WATER_TREE, OVERVIEW_TREE = STRtree(WATER), STRtree(OVERVIEW)


def backgrounds(workers):
    initialize_background()
    with futures.ProcessPoolExecutor(max_workers=workers) as pool:
        for layer, maximum in [('background', MAX_LEVEL), ('overview', 5)]:
            for level in range(MIN_LEVEL, maximum+1):
                # Above level 6 only original water needs additional sampling;
                # dry terrain/urban patches have no finer input to preserve.
                features = WATER if level > BACKGROUND_BASE_LEVEL else LAND
                cells = {cell for shape in features for cell in cells_for(shape, level, .0004 if level > BACKGROUND_BASE_LEVEL else 0)}
                # Include resumable cells so stale dry output is retired too.
                cells.update((int(p.stem.split('_')[1]), int(p.stem.split('_')[2])) for p in OUT.glob(f'{level}_*_{layer}.webp'))
                total = 0
                for result in pool.map(render_background, [(level,x,y,layer) for x,y in sorted(cells)], chunksize=16):
                    if result: total += 1
                print('Background', layer, level, total, flush=True)


def render_lines(lines, layer, levels, folder):
    for level in levels:
        ppd = 128 * 2**level
        span = SIZE/ppd
        segments = chunks(lines, ppd)
        tree = STRtree(segments)
        cells = {cell for line in segments for cell in cells_for(line, level, 2/ppd)}
        for x,y in cells:
            path = folder / f'{level}_{x}_{y}_{layer}.webp'
            if path.exists(): continue
            west, north = 120+x*span, 48-y*span
            hits = tree.query(box(west-2/ppd, north-span-2/ppd, west+span+2/ppd, north+2/ppd))
            alpha = Image.new('L', (SIZE*4, SIZE*4))
            draw = ImageDraw.Draw(alpha)
            for hit in hits:
                points = [((lon-west)*ppd*4, (north-lat)*ppd*4) for lon,lat in segments[int(hit)].coords]
                draw.line(points, fill=255, width=5, joint='curve')
            alpha = alpha.resize((SIZE,SIZE), Image.Resampling.LANCZOS)
            if not alpha.getbbox(): continue
            alpha = alpha.point(lambda value: min(255, round(value/32)*32))
            im = Image.new('RGBA', (SIZE,SIZE), (255,255,255,0))
            im.putalpha(alpha)
            temporary = path.with_suffix('.render.tmp')
            im.save(temporary, format='WEBP', lossless=True, method=4)
            temporary.replace(path)


def prefecture_borders(pid):
    from collections import defaultdict
    folder = ROOT / f'data/raw/baked_borders/{pid}'
    folder.mkdir(parents=True, exist_ok=True)
    if (folder/'complete').exists(): return pid
    mapping = read(ROOT/'data/raw/border_tiles/groups.json')['sourceToTown']
    data = read(DATA/('nara.json' if pid == '29' else f'prefectures/{pid}.json'))
    groups = defaultdict(list)
    for row in data['towns']: groups[mapping[row['id']]].extend(row['polygons'])
    shapes = {key: joined(polys) for key,polys in groups.items()}
    if pid == '29':
        cities = defaultdict(list)
        for key,shape in shapes.items(): cities[key[:5]].append(shape)
        city_shapes = [shapely.union_all(parts) for parts in cities.values()]
    else:
        city_shapes = [joined(row['polygons']) for row in data['cities']]
    for layer, geometries, maximum in [('town', shapes.values(), 8), ('city', city_shapes, 7)]:
        render_lines([line for shape in geometries for line in outlines(shape)], layer, range(MIN_LEVEL,maximum+1), folder)
    (folder/'complete').touch()
    return pid


def merge_border(item):
    import shutil
    name, paths = item
    target = OUT/name
    if target.exists(): return
    temporary = target.with_suffix('.merge.tmp')
    if len(paths) == 1:
        with Image.open(paths[0]) as source:
            histogram = source.getchannel('A').histogram()
        if all(not count or value == 255 or value % 32 == 0
               for value, count in enumerate(histogram)):
            # Most fine cells belong to one prefecture. Their pixels already
            # have the final alpha coverage; copying avoids a second encode.
            shutil.copyfile(paths[0], temporary)
            temporary.replace(target)
            return
    alpha = Image.new('L',(SIZE,SIZE))
    for path in paths:
        with Image.open(path) as im: alpha = ImageChops.lighter(alpha, im.getchannel('A'))
    # Eight subpixel coverage steps keep the fine geometry and line width while
    # avoiding hundreds of almost-identical alpha values in transparent packs.
    alpha = alpha.point(lambda value: min(255, round(value/32)*32))
    image = Image.new('RGBA',(SIZE,SIZE),(255,255,255,0))
    image.putalpha(alpha)
    image.save(temporary, format='WEBP', lossless=True, method=4)
    temporary.replace(target)


def borders(workers):
    from collections import defaultdict
    with futures.ProcessPoolExecutor(max_workers=workers) as pool:
        for pid in pool.map(prefecture_borders, [f'{pid:02}' for pid in range(1,48)]):
            print('Borders',pid,flush=True)
        paths = defaultdict(list)
        for path in (ROOT/'data/raw/baked_borders').glob('*/*.webp'): paths[path.name].append(path)
        for _ in pool.map(merge_border,paths.items(),chunksize=32): pass
    from prefecture_border_mesh import lines
    network = shapely.from_wkb((ROOT/'data/raw/shared_prefectures/network.wkb').read_bytes())
    render_lines(list(lines(network)), 'pref', range(MIN_LEVEL,6), OUT)


def manifest():
    tiles = {p.stem:p.stat().st_size for p in sorted(OUT.glob('*.webp'))}
    result = dict(schema=2,tileSize=SIZE,west=120,north=48,basePixelsPerDegree=128,
                  minLevel=MIN_LEVEL,maxLevel=MAX_LEVEL,
                  layerMaxLevels=dict(background=8,overview=5,pref=5,city=7,town=8),
                  sampling=2,borderLogicalWidth=.625,backgroundFallbackAbove=BACKGROUND_BASE_LEVEL,
                  layers=['background','overview','pref','city','town'],tiles=tiles,
                  sources='Existing attributed relief, urban, inland water and census geometry; no new sources.')
    result['prefectureCoverage'] = {
        f'{pid:02}': (ROOT/f'data/raw/baked_borders/{pid:02}/complete').exists()
        for pid in range(1,48)}
    result['sourceSha256'] = {
        str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in [DATA/'nara.json', DATA/'nara_water.json', SOURCE/'index-dry.json',
                  *sorted((DATA/'prefectures').glob('*.json')),
                  *sorted((DATA/'water').glob('[0-9][0-9].json')),
                  DATA/'water/national.json']}
    result['revision'] = hashlib.sha256(json.dumps(tiles,sort_keys=True).encode()).hexdigest()
    (OUT/'index.json').write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('Manifest',len(tiles),'tiles',sum(tiles.values()),'bytes',flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers',type=int,default=4)
    parser.add_argument('--only',choices=['backgrounds','borders','manifest'])
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    if args.only != 'manifest' and (not (ROOT/'data/raw/shared_prefectures/network.wkb').exists() or not all((ROOT/f'data/raw/shared_prefectures/{pid:02}.wkb').exists() for pid in range(1,48))):
        from prefecture_border_mesh import build_mesh
        build_mesh(args.workers)
    if args.only in (None,'backgrounds'): backgrounds(args.workers)
    if args.only in (None,'borders'): borders(args.workers)
    if args.only is None or args.only == 'manifest':
        assert all((ROOT/f'data/raw/baked_borders/{pid:02}/complete').exists() for pid in range(1,48)), 'Wait for every prefecture before packing'
        from optimize_map_images import optimize
        optimize(args.workers)
    manifest()
    if args.only is None or args.only == 'manifest':
        from prepare_map_cache import prepare
        prepared = ROOT/'data/prepared_maps'
        prepared.mkdir(parents=True, exist_ok=True)
        prepare(prepared, DATA)
