"""Bake static prefecture, municipality and gameplay-town outlines into WebP.

Run tools/export_border_groups.dart first. Never changes geography or save IDs.
Each scale is rendered separately, rather than resampling thick fine borders.
Transparent borders overlay terrain/ownership and remain visible with terrain off.
"""
import argparse
import concurrent.futures
import hashlib
import json
import math
import shutil
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageChops
import shapely
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
WORK = ROOT / 'data/raw/border_tiles'
OUT = DATA / 'border_tiles'
MIN_LEVEL = -2
MAX_LEVEL = 6
LAYER_MAX_LEVELS = {'pref': 6, 'city': 6, 'town': 6}
SIZE = 256
AA = 4
PAD = 3


def polygons(geometry):
    if geometry.geom_type == 'Polygon':
        yield geometry
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms:
            yield from polygons(part)


def joined(parts):
    shapes = []
    for coordinates in parts:
        poly = Polygon(coordinates[0], coordinates[1:])
        if not poly.is_valid:
            poly = shapely.make_valid(poly)
        shapes.extend(polygons(poly))
    return unary_union(shapes) if len(shapes) != 1 else shapes[0]


def outlines(geometry):
    # Ignore interior census gaps, matching exteriorOutline in Flutter.
    return [LineString(poly.exterior.coords) for poly in polygons(geometry)]


def chunks(lines, ppd):
    output = []
    for line in shapely.simplify(lines, 0.18 / ppd, preserve_topology=False):
        coords = list(line.coords)
        for start in range(0, len(coords) - 1, 63):
            output.append(LineString(coords[start:start + 64]))
    return output


def raster(lines, layer, level, folder):
    ppd = 64 * 2**level
    span = SIZE / ppd
    segments = chunks(lines, ppd)
    if not segments:
        return 0
    tree = STRtree(segments)
    cells = set()
    margin = PAD / ppd
    for line in segments:
        west, south, east, north = line.bounds
        for x in range(math.floor((west - 120 - margin) / span), math.floor((east - 120 + margin) / span) + 1):
            for y in range(math.floor((48 - north - margin) / span), math.floor((48 - south + margin) / span) + 1):
                cells.add((x, y))
    count = 0
    for x, y in sorted(cells):
        west, north = 120 + x * span, 48 - y * span
        area = box(west - margin, north - span - margin, west + span + margin, north + margin)
        hits = tree.query(area, predicate='intersects')
        if not len(hits):
            continue
        alpha = Image.new('L', ((SIZE + 2 * PAD) * AA,) * 2)
        draw = ImageDraw.Draw(alpha)
        for hit in hits:
            points = [((lon - west) * ppd * AA + PAD * AA,
                       (north - lat) * ppd * AA + PAD * AA)
                      for lon, lat in segments[int(hit)].coords]
            draw.line(points, fill=255, width=3, joint='curve')
        alpha = alpha.resize((SIZE + 2 * PAD,) * 2, Image.Resampling.LANCZOS)
        alpha = alpha.crop((PAD, PAD, SIZE + PAD, SIZE + PAD))
        if not alpha.getbbox():
            continue
        image = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 0))
        image.putalpha(alpha)
        image.save(folder / f'{level}_{x}_{y}_{layer}.webp', lossless=True, method=4)
        count += 1
    return count


def build_prefecture(pid):
    folder = WORK / pid
    folder.mkdir(parents=True, exist_ok=True)
    marker = folder / 'complete.json'
    if marker.exists():
        return pid, json.loads(marker.read_text())
    mapping = json.loads((WORK / 'groups.json').read_text())['sourceToTown']
    county = json.loads((DATA / ('nara.json' if pid == '29' else f'prefectures/{pid}.json')).read_text())
    grouped = defaultdict(list)
    for town in county['towns']:
        grouped[mapping[town['id']]].extend(town['polygons'])
    towns = {key: joined(parts) for key, parts in grouped.items()}
    town_lines = [line for shape in towns.values() for line in outlines(shape)]
    if pid == '29':
        by_city = defaultdict(list)
        for key, shape in towns.items():
            by_city[key[:5]].append(shape)
        city_shapes = [unary_union(parts) for parts in by_city.values()]
    else:
        city_shapes = [joined(city['polygons']) for city in county['cities']]
    city_lines = [line for shape in city_shapes for line in outlines(shape)]
    pref = next(p for p in json.loads((DATA / 'japan.json').read_text())['prefectures'] if p['id'] == pid)
    pref_lines = outlines(joined(pref['polygons']))
    counts = {}
    for layer, lines in [('pref', pref_lines), ('city', city_lines), ('town', town_lines)]:
        for level in range(MIN_LEVEL, MAX_LEVEL + 1):
            counts[f'{level}_{layer}'] = raster(lines, layer, level, folder)
    counts['townGroups'] = len(towns)
    marker.write_text(json.dumps(counts))
    return pid, counts


def merge_tile(item):
    name, sources = item
    alpha = Image.new('L', (SIZE * 2, SIZE * 2))
    for source in sources:
        _, x, y, _ = source.stem.split('_')
        offset = (int(x) % 2 * SIZE, int(y) % 2 * SIZE)
        with Image.open(source) as image:
            region = (offset[0], offset[1], offset[0] + SIZE, offset[1] + SIZE)
            alpha.paste(ImageChops.lighter(alpha.crop(region), image.getchannel('A')), offset)
    alpha = alpha.point(lambda value: round(value / 17) * 17)
    image = Image.new('RGBA', (SIZE * 2, SIZE * 2), (255, 255, 255, 0))
    image.putalpha(alpha)
    image.save(OUT / name, lossless=True, method=6)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefectures', nargs='*')
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--finalize-only', action='store_true')
    parser.add_argument('--rebuild', action='store_true',
                        help='Discard cached rendering after changing source data or rendering rules')
    args = parser.parse_args()
    ids = args.prefectures or [f'{i:02d}' for i in range(1, 48)]
    if not set(ids) <= {f'{i:02d}' for i in range(1, 48)}:
        parser.error('Prefectures must be two-digit codes 01 through 47')
    if args.rebuild and args.finalize_only:
        parser.error('--rebuild cannot be combined with --finalize-only')
    if args.rebuild:
        for pid in ids:
            shutil.rmtree(WORK / pid, ignore_errors=True)
    coverage = {}
    if args.finalize_only:
        coverage = {pid: json.loads((WORK / pid / 'complete.json').read_text()) for pid in ids}
    else:
        with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
            for pid, counts in pool.map(build_prefecture, ids):
                coverage[pid] = counts
                print(pid, 'complete;', len(coverage), '/', len(ids), flush=True)
    if args.prefectures:
        return
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob('*.webp'):
        old.unlink()
    sources = defaultdict(list)
    for pid in ids:
        for path in (WORK / pid).glob('*.webp'):
            level, x, y, layer = path.stem.split('_')
            if int(level) > LAYER_MAX_LEVELS[layer]:
                continue
            name = f'{int(level)-1}_{int(x)//2}_{int(y)//2}_{layer}.webp'
            sources[name].append(path)
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        for index, _ in enumerate(pool.map(merge_tile, sorted(sources.items()), chunksize=64), 1):
            if index % 5000 == 0:
                print('Packed', index, '/', len(sources), 'border images', flush=True)
    tiles = {p.stem: p.stat().st_size for p in sorted(OUT.glob('*.webp'))}
    document = dict(schema=1, minLevel=MIN_LEVEL-1, maxLevel=MAX_LEVEL-1,
                    tileSize=SIZE*2, west=120, north=48, basePixelsPerDegree=128,
                    detailLevels={pid: MAX_LEVEL-1 for pid in ids},
                    layerMaxLevels={k: v-1 for k, v in LAYER_MAX_LEVELS.items()},
                    prefectureCoverage=coverage, tiles=tiles,
                    layers=['pref', 'city', 'town'], format='lossless WebP',
                    groupSha256=hashlib.sha256((WORK / 'groups.json').read_bytes()).hexdigest(),
                    attribution='国勢調査町丁・字等別境界データセット（CODH作成）、e-Stat。CC BY 4.0。',
                    processing='ゲーム本体の町統合結果で結合。固定境界線のみを縮尺別に事前描画。内部の穴を除外し、タイル端をパディングして継ぎ目を抑制。共有線のアルファを最大値で合成。')
    (OUT / 'index.json').write_text(json.dumps(document, ensure_ascii=False, separators=(',', ':')))
    print('Border images:', len(tiles), 'bytes:', sum(tiles.values()), flush=True)


if __name__ == '__main__':
    main()
