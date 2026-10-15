"""Bake overview-only water with urban imagery; prefecture images stay intact."""
import json
from PIL import Image, ImageDraw, ImageChops
from shapely.geometry import Polygon, LineString, box, Point
from shapely.strtree import STRtree
from build_map_tiles import (DATA, OUT, SIZE, PPD, SPAN, read, stamp, image,
                             polygons_mask, coordinates)


def build(out=OUT):
    manifest = read(out/'index.json')
    water = read(DATA/'water/national.json')
    features = [Polygon(p[0], p[1:]) for p in water['areas'] if p and len(p[0]) >= 3]
    features += [LineString(p) for p in water['lines'] if len(p) >= 2]
    tree = STRtree(features)
    urban = read(DATA/'urban/index.json')['tiles']
    keys = [tuple(map(int, k.split('_')[1:3])) for k in manifest['tiles']
            if k.startswith('4_') and k.endswith('_shade')]
    for path in out.glob('*_overview.png'):
        path.unlink()
    for count, (x, y) in enumerate(keys, 1):
        west, north = 120+x*SPAN, 48-y*SPAN
        extent = box(west, north-SPAN, west+SPAN, north)
        tile = Image.new('RGBA', (SIZE, SIZE))
        urban_mask = Image.new('RGBA', (SIZE, SIZE))
        for row in urban:
            if row['west'] < west+SPAN and row['east'] > west and row['north'] > north-SPAN and row['south'] < north:
                stamp(urban_mask, image(str(DATA/f"urban/{row['id']}.png")), row, west, north, PPD)
        tile.paste((0xB6, 0xA0, 0xF5, 255), (0, 0), urban_mask.getchannel('A').point(lambda v: round(v*0x85/255)))
        mask = Image.new('L', (SIZE*2, SIZE*2))
        for idx in tree.query(extent):
            geom = features[int(idx)]
            if geom.geom_type == 'Polygon':
                rings = [list(geom.exterior.coords), *[list(r.coords) for r in geom.interiors]]
                mask = ImageChops.lighter(mask, polygons_mask([rings], west, north, SIZE*2, PPD*2))
            else:
                ImageDraw.Draw(mask).line(coordinates(geom.coords, west, north, PPD*2), fill=255, width=1)
        blue = Image.new('RGBA', (SIZE, SIZE), (0x79, 0xD9, 0xFF, 0))
        blue.putalpha(mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS))
        tile.alpha_composite(blue)
        if tile.getbbox():
            tile.save(out/f'4_{x}_{y}_overview.png', optimize=True)
        if count % 100 == 0:
            print(f'Overview {count}/{len(keys)} cells', flush=True)
    for level in range(3, -1, -1):
        keys = sorted({(x//2, y//2) for x, y in keys})
        for x, y in keys:
            tile = Image.new('RGBA', (SIZE*2, SIZE*2))
            for dx in range(2):
                for dy in range(2):
                    path = out/f'{level+1}_{x*2+dx}_{y*2+dy}_overview.png'
                    if path.exists():
                        with Image.open(path) as child:
                            tile.paste(child, (dx*SIZE, dy*SIZE))
            tile = tile.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
            if tile.getbbox():
                tile.save(out/f'{level}_{x}_{y}_overview.png', optimize=True)
    # Keep names only beside water that survives the overview filter.
    labels = [label for label in water['labels']
              if len(tree.query(Point(label['point']).buffer(.003), predicate='intersects'))]
    (DATA/'map_labels/national.json').write_text(json.dumps(dict(lines=[], areas=[], labels=labels), ensure_ascii=False, separators=(',', ':')))
    manifest['tiles'] = {p.stem:p.stat().st_size for p in sorted(out.glob('*.png'))}
    manifest['overviewWater'] = dict(layer='overview', source='water/national.json',
                                   riverParts=len(water['lines']), waterPolygons=len(water['areas']),
                                   processing='全国用: 約2.5km以上の河川区間と約0.2km²以上の水域。県・市町村の詳細画像は変更しない。')
    (out/'index.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')))
    print('Overview images:', len(list(out.glob('*_overview.png'))), 'labels:', len(labels), flush=True)


if __name__ == '__main__':
    build()
