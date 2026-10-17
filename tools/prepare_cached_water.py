"""Prepare ingredients for integrated, high-resolution background image caches.

The displayed image combines terrain, urban land and water in one bitmap.
Uses existing attributed GIS only. Does not alter census or save data.
"""
import concurrent.futures
import json
import math
import struct
from pathlib import Path
from PIL import Image, ImageChops
from shapely.geometry import Polygon, box
from shapely import make_valid
from shapely.strtree import STRtree
import build_map_tiles as base
from build_uniform_tiles import mask
from restore_nara_water_tiles import nara_scale

OUT = base.DATA / 'map_tiles_uniform'
WORK = base.ROOT / 'data/raw/dry_tiles'
WATER = base.DATA / 'water_mesh'
PPD = 4096
SPAN = 256 / PPD


def export_water(source, target, scale):
    data = base.read(source)
    rows = [(False, rings) for rings in data['areas']]
    rows += [(True, [line]) for line in data['lines'] if len(line) >= 2]
    output = bytearray(b'KWA1' + struct.pack('<Id', len(rows), scale))
    for river, rings in rows:
        xs = [p[0] for ring in rings for p in ring]
        ys = [p[1] for ring in rings for p in ring]
        output.extend(struct.pack('<4fI', min(xs), min(ys), max(xs), max(ys),
                                  len(rings) | (0x80000000 if river else 0)))
        for ring in rings:
            output.extend(struct.pack('<I', len(ring)))
            for x, y in ring:
                output.extend(struct.pack('<ii', round(x * 1000000), round(y * 1000000)))
    target.write_bytes(output)
    return len(output)


def prefecture(pid):
    dest = WORK / pid
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob('dry_*.webp'): old.unlink()
    if pid == '29':
        data = base.read(base.DATA / 'nara.json')
        land = [p for t in data['towns'] for p in t['polygons']]
    else:
        data = base.read(base.DATA / f'prefectures/{pid}.json')
        land = data['polygons']
    del data
    shapes = [make_valid(Polygon(p[0], p[1:])) for p in land]
    tree = STRtree(shapes)
    bbox = (min(p.bounds[0] for p in shapes), min(p.bounds[1] for p in shapes),
            max(p.bounds[2] for p in shapes), max(p.bounds[3] for p in shapes))
    urban = base.read(base.DATA / 'urban/index.json')['tiles']
    urban = [r for r in urban if r['west'] < bbox[2] and r['east'] > bbox[0]
             and r['south'] < bbox[3] and r['north'] > bbox[1]]
    manifest = base.read(OUT / 'index.json')
    if pid == '29':
        nara_urban = base.read(base.DATA / 'nara_urban.json')['areas']
        urban_tree = STRtree([make_valid(Polygon(p[0], p[1:])) for p in nara_urban])
    count = 0
    for key in manifest['tiles']:
        if not key.startswith('6_') or not key.endswith('_detail'):
            continue
        _, x, y, _ = key.split('_'); x, y = int(x), int(y)
        west, north = 120 + x * SPAN, 48 - y * SPAN
        extent = box(west, north - SPAN, west + SPAN, north)
        hits = tree.query(extent, predicate='intersects')
        if not len(hits): continue
        rgba = Image.new('RGBA', (256, 256))
        for row in urban:
            if row['west'] < west + SPAN and row['east'] > west and row['south'] < north and row['north'] > north - SPAN:
                base.stamp(rgba, base.image(str(base.DATA / f"urban/{row['id']}.png")),
                           row, west, north, PPD, resampling=Image.Resampling.NEAREST)
        alpha = rgba.getchannel('A')
        if pid == '29':
            ids = urban_tree.query(extent, predicate='intersects')
            alpha = mask([nara_urban[int(i)] for i in ids], west, north)
        if not alpha.getbbox(): continue
        alpha = ImageChops.multiply(alpha, mask([land[int(i)] for i in hits], west, north))
        alpha = alpha.point(lambda v: round(v * 0x85 / 255))
        if not alpha.getbbox(): continue
        tile = Image.new('RGBA', (256, 256), (0xB6, 0xA0, 0xF5, 0))
        tile.putalpha(alpha)
        tile.save(dest / f'dry_{key}.webp', lossless=True, method=4)
        count += 1
    return pid, count


def main():
    WATER.mkdir(exist_ok=True)
    scale = nara_scale(base.read(base.DATA / 'nara.json'))
    ids = [f'{p:02}' for p in range(1, 48)]
    for pid in [*ids, 'national']:
        source = base.DATA / ('nara_water.json' if pid == '29' else f'water/{pid}.json')
        size = export_water(source, WATER / f'{pid}.bin', scale)
        print('Water', pid, size, flush=True)
    with concurrent.futures.ProcessPoolExecutor(max_workers=6) as pool:
        for pid, count in pool.map(prefecture, ids):
            print('Urban', pid, count, flush=True)
    for path in OUT.glob('dry_*.webp'): path.unlink()
    for pid in ids:
        for path in sorted((WORK / pid).glob('dry_*.webp')):
            target = OUT / path.name
            with Image.open(path) as child:
                tile = child.convert('RGBA')
            if target.exists():
                with Image.open(target) as old:
                    merged = old.convert('RGBA')
                merged.alpha_composite(tile); tile = merged
            tile.save(target, lossless=True, method=4)
    cells = {tuple(map(int, p.stem.split('_')[2:4])) for p in OUT.glob('dry_6_*_detail.webp')}
    for level in range(5, -1, -1):
        cells = {(x // 2, y // 2) for x, y in cells}
        for x, y in sorted(cells):
            tile = Image.new('RGBA', (512, 512))
            for dx in range(2):
                for dy in range(2):
                    p = OUT / f'dry_{level+1}_{x*2+dx}_{y*2+dy}_detail.webp'
                    if p.exists():
                        with Image.open(p) as source: tile.paste(source, (dx*256, dy*256))
            tile = tile.resize((256, 256), Image.Resampling.LANCZOS)
            if tile.getbbox():
                tile.save(OUT / f'dry_{level}_{x}_{y}_detail.webp', lossless=True, method=4)
                if level <= 4:
                    tile.save(OUT / f'dry_{level}_{x}_{y}_overview.webp', lossless=True, method=4)
        print('Dry LOD', level, len(cells), flush=True)
    manifest = base.read(OUT / 'index.json')
    tiles = {p.stem:p.stat().st_size for p in OUT.glob('*_shade.webp')}
    tiles.update({p.stem.removeprefix('dry_'):p.stat().st_size for p in OUT.glob('dry_*.webp')})
    manifest['tiles'] = tiles
    manifest['surfaceWater'] = 'separate precision water image cache'
    (OUT / 'index-dry.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    # Combined water images are no longer shipped; dry filenames invalidate HTTP caches.
    for pattern in ['[0-9]*_detail.webp', '[0-9]*_overview.webp']:
        for path in OUT.glob(pattern): path.unlink()
    print('Ready:', len(tiles), 'background images;', sum(p.stat().st_size for p in WATER.glob('*.bin')), 'water bytes', flush=True)


if __name__ == '__main__':
    main()
