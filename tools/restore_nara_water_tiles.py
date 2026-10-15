#!/usr/bin/env python3
"""Restore the original Nara water strokes in offline tiles, including fine LODs.

The old map projection has x=0.826*scale*longitude, y=scale*latitude.
Buffer in that projection, then transform back: widths/caps/holes match WaterLayer.
No vector water geometry is loaded by the game.
"""
import json
import math
from pathlib import Path
from PIL import Image, ImageChops
from shapely.geometry import Polygon, LineString, box
from shapely.affinity import scale as rescale
from shapely.strtree import STRtree
from shapely import make_valid
import build_map_tiles as base

DARK = (0x12, 0x3D, 0x59)
BLUE = (0x79, 0xD9, 0xFF)
FINE_LEVEL = 6


def parts(geom):
    if geom.geom_type == 'Polygon':
        yield geom
    elif hasattr(geom, 'geoms'):
        for g in geom.geoms:
            yield from parts(g)


def rings(geom):
    return [list(geom.exterior.coords), *[list(r.coords) for r in geom.interiors]]


def stroke(geom, width, projection_scale):
    projected = rescale(geom, xfact=0.826, yfact=1, origin=(0, 0))
    return rescale(projected.buffer(width / (2*projection_scale), cap_style='round', join_style='round'),
                   xfact=1/0.826, yfact=1, origin=(0, 0))


def water_shapes(water, projection_scale):
    dark, blue = [], []
    for row in water['areas']:
        geom = make_valid(Polygon(row[0], row[1:]))
        # Expanded fill equals boundary stroke followed by the original fill.
        dark.extend(parts(stroke(geom, 0.625, projection_scale)))
        blue.extend(parts(stroke(geom, 0.375, projection_scale)))
    for row in water['lines']:
        if len(row) < 2:
            continue
        geom = LineString(row)
        dark.extend(parts(stroke(geom, 0.625, projection_scale)))
        blue.extend(parts(stroke(geom, 0.375, projection_scale)))
    return dark, blue


def nara_scale(nara):
    points = [p for town in nara['towns'] for poly in town['polygons'] for ring in poly for p in ring]
    west, east = min(p[0] for p in points), max(p[0] for p in points)
    south, north = min(p[1] for p in points), max(p[1] for p in points)
    # Same scene and margins as TerritoryMap._buildPaths.
    return min(1020/((east-west)*0.826), 1420/(north-south))


def downsample(out, level, cells, layers):
    parents = {(x//2, y//2) for x,y in cells}
    images = {}
    for x,y in sorted(parents):
        for layer in layers:
            tile = Image.new('RGBA', (512,512))
            for dx in range(2):
                for dy in range(2):
                    path = out/f'{level+1}_{x*2+dx}_{y*2+dy}_{layer}.png'
                    if path.exists():
                        with Image.open(path) as child:
                            tile.paste(child,(dx*256,dy*256))
            images[x,y,layer] = tile.resize((256,256), Image.Resampling.LANCZOS)
    return parents, images


def restore(out):
    out = Path(out)
    data = base.DATA
    nara = base.read(data/'nara.json')
    projection_scale = nara_scale(nara)
    land = next(p['polygons'] for p in base.read(data/'japan.json')['prefectures'] if p['id']=='29')
    land_geoms = [Polygon(p[0], p[1:]) for p in land]
    landtree = STRtree(land_geoms)
    urban = base.read(data/'nara_urban.json')['areas']
    urbantree = STRtree([Polygon(p[0],p[1:]) for p in urban])
    dark, blue = water_shapes(base.read(data/'nara_water.json'), projection_scale)
    trees = [STRtree(dark),STRtree(blue)]
    features = [dark,blue]
    relief = base.read(data/'nara_relief.json')
    source_relief = base.image(str(data/'nara_relief.png'))
    ppd = 64 * 2**FINE_LEVEL
    span = 256/ppd
    west = min(g.bounds[0] for g in land_geoms)
    south = min(g.bounds[1] for g in land_geoms)
    east = max(g.bounds[2] for g in land_geoms)
    north = max(g.bounds[3] for g in land_geoms)
    cells = set()
    for x in range(math.floor((west-120)/span), math.floor((east-120)/span)+1):
        for y in range(math.floor((48-north)/span), math.floor((48-south)/span)+1):
            tw, tn = 120+x*span,48-y*span
            extent = box(tw,tn-span,tw+span,tn)
            ids = landtree.query(extent,predicate='intersects')
            if not len(ids): continue
            mask = base.polygons_mask([land[int(i)] for i in ids],tw,tn,ppd=ppd)
            if not mask.getbbox(): continue
            shade = Image.new('RGBA',(256,256))
            base.stamp(shade,source_relief,relief,tw,tn,ppd)
            alpha = ImageChops.multiply(ImageChops.invert(shade.convert('L')),shade.getchannel('A'))
            shade = Image.new('RGBA',(256,256))
            shade.putalpha(ImageChops.multiply(alpha,mask))
            detail = Image.new('RGBA',(256,256))
            ids = urbantree.query(extent,predicate='intersects')
            umask = base.polygons_mask([urban[int(i)] for i in ids],tw,tn,ppd=ppd)
            umask = ImageChops.multiply(umask,mask).point(lambda a:round(a*0x85/255))
            detail.paste((0xB6,0xA0,0xF5,255),(0,0),umask)
            # Render buffers at 4x for fractional-pixel stroke widths and round caps.
            for tree, geoms, color in zip(trees,features,[DARK,BLUE]):
                ids = tree.query(extent)
                wmask = base.polygons_mask([rings(geoms[int(i)]) for i in ids],tw,tn,size=1024,ppd=ppd*4)
                wmask = ImageChops.multiply(wmask.resize((256,256),Image.Resampling.LANCZOS),mask)
                water = Image.new('RGBA',(256,256),(*color,0))
                water.putalpha(wmask)
                detail.alpha_composite(water)
            for layer,tile in [('shade',shade),('detail',detail)]:
                tile.save(out/f'{FINE_LEVEL}_{x}_{y}_{layer}.png',optimize=True)
            cells.add((x,y))
    print('Nara fine water tiles:',len(cells),'projection scale:',projection_scale,flush=True)
    for level in [5,4]:
        parents, images = downsample(out,level,cells,['shade','detail'])
        for (x,y,layer),tile in images.items():
            path = out/f'{level}_{x}_{y}_{layer}.png'
            if level == 4:
                # Preserve neighboring prefectures' pixels in shared global tiles.
                if layer == 'shade': continue
                tw,tn = 120+x*0.25,48-y*0.25
                mask = base.polygons_mask(land,tw,tn)
                old = Image.open(path).convert('RGBA') if path.exists() else Image.new('RGBA',(256,256))
                old.putalpha(ImageChops.multiply(old.getchannel('A'),ImageChops.invert(mask)))
                old.alpha_composite(tile)
                tile = old
            tile.save(path,optimize=True)
        cells = parents
    # Rebuild only affected overview parents from the complete global child tiles.
    for level in [3,2,1,0]:
        parents, images = downsample(out,level,cells,['detail'])
        for (x,y,layer),tile in images.items():
            tile.save(out/f'{level}_{x}_{y}_{layer}.png',optimize=True)
        cells = parents
    manifest = base.read(out/'index.json')
    manifest['detailLevels'] = {'29':FINE_LEVEL}
    manifest['waterStyles'] = {'29':{'outline':'#123D59','fill':'#79D9FF','outlineMapUnits':0.625,
        'fillMapUnits':0.375,'projectionScale':projection_scale,'cap':'round','join':'round',
        'processing':'奈良県版WaterLayerと同じ投影で縁取り・青い線・面の塗りを画像化。町ID・人口は変更しない。'}}
    manifest['tiles'] = {p.stem:p.stat().st_size for p in sorted(out.glob('*.png'))}
    (out/'index.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
    print('Nara stroke restoration complete:',len(manifest['tiles']),'images',flush=True)

if __name__ == '__main__':
    restore(base.OUT)
