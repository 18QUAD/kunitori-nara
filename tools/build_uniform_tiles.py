"""Bake all prefectures at Nara's 4096 px/degree and zoom-11 DEM detail.

Run prepare_fine_relief.py first. Runtime uses bounded, offline WebP images.
The preceding v2 PNG pyramid remains available to already-open clients.
"""
import concurrent.futures
import json
import math
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops
from shapely.geometry import Polygon, box
from shapely.strtree import STRtree
from shapely import make_valid
import build_map_tiles as base
from restore_nara_water_tiles import water_shapes, nara_scale, rings, DARK, BLUE

OUT = base.DATA/'map_tiles_uniform'
WORK = base.ROOT/'data/raw/uniform_tiles'
RELIEF = base.ROOT/'data/raw/fine_relief'
LEVEL = 6
PPD = 4096
SPAN = 256/PPD


def mask(polygons, west, north, size=256, ppd=PPD):
    """Avoid an image allocation for each hole-free water fragment."""
    result = Image.new('L', (size, size))
    draw = ImageDraw.Draw(result)
    for poly in polygons:
        if len(poly) == 1:
            draw.polygon(base.coordinates(poly[0], west, north, ppd), fill=255)
        else:
            part = base.polygons_mask([poly], west, north, size, ppd)
            result = ImageChops.lighter(result, part)
            draw = ImageDraw.Draw(result)
    return result


def save(path, tile):
    if tile.getbbox():
        tile.save(path, format='WEBP', lossless=True, method=4)


def build_prefecture(pid):
    dest = WORK/pid
    dest.mkdir(parents=True, exist_ok=True)
    for old in dest.glob('*.webp'): old.unlink()
    if pid == '29':
        count = 0
        for path in (base.DATA/'map_tiles_v2').glob('6_*.png'):
            with Image.open(path) as source:
                save(dest/(path.stem+'.webp'), source.convert('RGBA'))
            if path.stem.endswith('_shade'): count += 1
        return pid, count
    county = base.read(base.DATA/f'prefectures/{pid}.json')
    land = county['polygons']
    del county
    lands = [make_valid(Polygon(p[0], p[1:])) for p in land]
    landtree = STRtree(lands)
    xmin = min(g.bounds[0] for g in lands); xmax = max(g.bounds[2] for g in lands)
    ymin = min(g.bounds[1] for g in lands); ymax = max(g.bounds[3] for g in lands)
    dark, blue = water_shapes(base.read(base.DATA/f'water/{pid}.json'),
                              nara_scale(base.read(base.DATA/'nara.json')))
    features = [dark, blue]
    trees = [STRtree(dark), STRtree(blue)]
    relief = [r for r in base.read(RELIEF/'index.json')['tiles'] if r['available']]
    relief_tree = STRtree([box(r['west'], r['south'], r['east'], r['north']) for r in relief])
    urban = base.read(base.DATA/'urban/index.json')['tiles']
    urban_tree = STRtree([box(r['west'], r['south'], r['east'], r['north']) for r in urban])
    count = 0
    for x in range(math.floor((xmin-120)/SPAN), math.floor((xmax-120)/SPAN)+1):
        for y in range(math.floor((48-ymax)/SPAN), math.floor((48-ymin)/SPAN)+1):
            west, north = 120+x*SPAN, 48-y*SPAN
            extent = box(west, north-SPAN, west+SPAN, north)
            ids = landtree.query(extent, predicate='intersects')
            if not len(ids): continue
            landmask = mask([land[int(i)] for i in ids], west, north)
            if not landmask.getbbox(): continue
            shade = Image.new('RGBA', (256,256))
            for idx in relief_tree.query(extent):
                row = relief[int(idx)]
                base.stamp(shade, base.image(str(RELIEF/f"{row['x']}_{row['y']}.png")), row, west, north, PPD)
            alpha = ImageChops.multiply(ImageChops.invert(shade.convert('L')), shade.getchannel('A'))
            shade = Image.new('RGBA',(256,256))
            shade.putalpha(ImageChops.multiply(alpha,landmask))
            detail = Image.new('RGBA',(256,256))
            urban_image = Image.new('RGBA',(256,256))
            for idx in urban_tree.query(extent):
                row = urban[int(idx)]
                base.stamp(urban_image,base.image(str(base.DATA/f"urban/{row['id']}.png")),row,west,north,PPD,
                           resampling=Image.Resampling.NEAREST)
            urban_alpha = ImageChops.multiply(urban_image.getchannel('A'),landmask).point(lambda v:round(v*0x85/255))
            detail.paste((0xB6,0xA0,0xF5,255),(0,0),urban_alpha)
            for tree, geoms, color in zip(trees, features, [DARK,BLUE]):
                ids = tree.query(extent)
                watermask = mask([rings(geoms[int(i)]) for i in ids],west,north,size=1024,ppd=PPD*4)
                watermask = ImageChops.multiply(watermask.resize((256,256),Image.Resampling.LANCZOS),landmask)
                overlay = Image.new('RGBA',(256,256),(*color,0));overlay.putalpha(watermask)
                detail.alpha_composite(overlay)
            save(dest/f'6_{x}_{y}_shade.webp',shade)
            save(dest/f'6_{x}_{y}_detail.webp',detail)
            count += 1
    return pid, count



def finalize_layer_levels(out=OUT):
    # At ~40-50 m/px, LOD 5 already samples the ~63 m DEM more finely
    # than its source. Keep the full 4096 px/degree only for water/urban edges.
    for path in out.glob('6_*_shade.webp'):
        path.unlink()
    manifest = base.read(out/'index.json')
    manifest['layerMaxLevels'] = {'shade':5,'detail':6,'overview':4}
    manifest['tiles'] = {p.stem:p.stat().st_size for p in sorted(out.glob('*.webp'))}
    (out/'index.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
    report = base.read(out/'import_report.json')
    report['layerPixelsPerDegree'] = {'shade':2048,'detail':4096,'overview':1024}
    (out/'import_report.json').write_text(json.dumps(report,ensure_ascii=False,separators=(',',':')))
    print('Release layers:',len(manifest['tiles']),'images;',sum(manifest['tiles'].values()),'bytes',flush=True)


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob('*.webp'): old.unlink()
    ids = [p['id'] for p in base.read(base.DATA/'japan.json')['prefectures']]
    coverage = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(build_prefecture,pid) for pid in ids]
        for future in concurrent.futures.as_completed(futures):
            pid, count = future.result(); coverage[pid] = count
            print(f'{pid}: {count} fine cells; {len(coverage)}/47 prefectures',flush=True)
    # A fixed compositing order makes shared border pixels reproducible.
    for pid in sorted(ids):
        for path in sorted((WORK/pid).glob('*.webp')):
            target = OUT/path.name
            if target.exists():
                with Image.open(target) as old, Image.open(path) as new:
                    tile = old.convert('RGBA');tile.alpha_composite(new.convert('RGBA'))
                    save(target,tile)
            else: shutil.copy2(path,target)
    cells = {tuple(map(int,p.stem.split('_')[1:3])) for p in OUT.glob('6_*.webp')}
    for level in range(5,-1,-1):
        cells = {(x//2,y//2) for x,y in cells}
        for x,y in sorted(cells):
            for layer in ['shade','detail']:
                tile = Image.new('RGBA',(512,512))
                for dx in range(2):
                    for dy in range(2):
                        path = OUT/f'{level+1}_{x*2+dx}_{y*2+dy}_{layer}.webp'
                        if path.exists():
                            with Image.open(path) as child: tile.paste(child,(dx*256,dy*256))
                save(OUT/f'{level}_{x}_{y}_{layer}.webp',tile.resize((256,256),Image.Resampling.LANCZOS))
        print(f'Uniform LOD {level}: {len(cells)} cells',flush=True)
    # National water remains deliberately sparse; its terrain uses the new DEM.
    for path in (base.DATA/'map_tiles_v2').glob('*_overview.png'):
        with Image.open(path) as source: save(OUT/(path.stem+'.webp'),source.convert('RGBA'))
    report = base.read(RELIEF/'index.json')
    report.pop('tiles')
    report['processing'] = '全県を奈良と同じzoom 11（約63m）で画像化。奈良原本は維持。標高欠損と隣接画素は透明。'
    report['detailPixelsPerDegree'] = PPD
    report['prefectureCoverage'] = coverage
    report['waterStyle'] = dict(outline='#123D59',fill='#79D9FF',outlineMapUnits=.625,fillMapUnits=.375,
                                projectionScale=nara_scale(base.read(base.DATA/'nara.json')),cap='round',join='round')
    tiles = {p.stem:p.stat().st_size for p in sorted(OUT.glob('*.webp'))}
    manifest = dict(schema=1,tileSize=256,west=120,north=48,basePixelsPerDegree=64,maxLevel=4,
                    detailLevels={pid:LEVEL for pid in ids},prefectureCoverage=coverage,
                    tiles=tiles,layers=['shade','detail','overview'],format='lossless WebP',
                    attribution='国土地理院・国土交通省。出典は取込レポート参照。')
    (OUT/'index.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
    (OUT/'import_report.json').write_text(json.dumps(report,ensure_ascii=False,separators=(',',':')))
    finalize_layer_levels(OUT)
    print('Uniform baked before layer caps:',len(tiles),'images;',sum(tiles.values()),'bytes',flush=True)


if __name__ == '__main__':
    main()
