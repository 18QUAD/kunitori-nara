"""Bake thin white borders without casings from the original border pyramid.

Run build_border_tiles.py first on a fresh checkout. The first run preserves its
thin centerline images in data/raw/border_centerlines; subsequent runs reuse them
and never thicken an already styled image. Runtime only switches finished tiles.
"""
import argparse
import concurrent.futures
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/raw/border_centerlines'
OUT = ROOT / 'assets/data/border_tiles'
PREFIX = 'slim_'
PREF_PREFIX = 'slimshared_'
INDEX = 'index-slim.json'
SIZE = 512
PAD = 4
AVAILABLE = set()


@lru_cache(maxsize=128)
def source_alpha(key):
    with Image.open(SOURCE / f'{key}.webp') as image:
        return image.getchannel('A')


def initialize(keys):
    global AVAILABLE
    AVAILABLE = set(keys)


def quarter_expand(image):
    """Exact nearest-4x / 3x3 max / BOX reduction, using native-size arrays.

    Each output pixel has four central samples, eight side samples and four
    corner samples. Match Pillow's two-pass integer BOX rounding without the
    16-times larger intermediate bitmap.
    """
    padded = np.pad(np.asarray(image, dtype=np.uint16), 1, mode='edge')
    c = padded[1:-1, 1:-1]
    left, right = padded[1:-1, :-2], padded[1:-1, 2:]
    up, down = padded[:-2, 1:-1], padded[2:, 1:-1]
    middle = (2*c + np.maximum(c, left) + np.maximum(c, right) + 2) // 4
    cu, cd = np.maximum(c, up), np.maximum(c, down)
    top = (2*cu + np.maximum(cu, np.maximum(left, padded[:-2, :-2])) +
           np.maximum(cu, np.maximum(right, padded[:-2, 2:])) + 2) // 4
    bottom = (2*cd + np.maximum(cd, np.maximum(left, padded[2:, :-2])) +
              np.maximum(cd, np.maximum(right, padded[2:, 2:])) + 2) // 4
    return Image.fromarray(((2*middle + top + bottom + 2) // 4).astype(np.uint8))


def render(key):
    level, x, y, layer = key.split('_')
    x, y = int(x), int(y)
    side = SIZE + PAD * 2
    alpha = Image.new('L', (side, side))
    for dx in [-1, 0, 1]:
        for dy in [-1, 0, 1]:
            neighbor = f'{level}_{x+dx}_{y+dy}_{layer}'
            if neighbor not in AVAILABLE:
                continue
            ox, oy = PAD + dx * SIZE, PAD + dy * SIZE
            area = (max(0, ox), max(0, oy), min(side, ox+SIZE), min(side, oy+SIZE))
            crop = source_alpha(neighbor).crop((area[0]-ox, area[1]-oy,
                                                area[2]-ox, area[3]-oy))
            alpha.paste(crop, area[:2])
    # One width step thinner: expand by a quarter rather than half a source
    # pixel per side. Four coverage tones preserve that smaller antialias fringe.
    core = alpha.point(lambda value: min(255, value * 2))
    core = quarter_expand(core)
    core = core.point(lambda value: 0 if value < 32 else (64 if value < 144 else (192 if value < 224 else 255)))
    image = Image.new('RGBA', (side, side), (255, 255, 255, 0))
    image.putalpha(core)
    image = image.crop((PAD, PAD, SIZE+PAD, SIZE+PAD))
    if not image.getbbox():
        return None
    prefix = PREF_PREFIX if layer == 'pref' else PREFIX
    path = OUT / f'{prefix}{key}.webp'
    image.save(path, lossless=True, method=6)
    return key, path.stat().st_size


def candidates(keys):
    cells = set()
    for key in keys:
        level, x, y, layer = key.split('_')
        for dx in [-1, 0, 1]:
            for dy in [-1, 0, 1]:
                cells.add(f'{level}_{int(x)+dx}_{int(y)+dy}_{layer}')
    return sorted(cells)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    if (OUT / 'index.json').exists():
        original = json.loads((OUT / 'index.json').read_text())
        SOURCE.mkdir(parents=True, exist_ok=True)
        for key in original['tiles']:
            shutil.copyfile(OUT / f'{key}.webp', SOURCE / f'{key}.webp')
        shutil.copyfile(OUT / 'index.json', SOURCE / 'index.json')
    elif not (SOURCE / 'index.json').exists():
        parser.error('Original centerlines are missing; run build_border_tiles.py first')
    original = json.loads((SOURCE / 'index.json').read_text())
    jobs = candidates(original['tiles'])
    for old in OUT.glob('*.webp'):
        if old.name.startswith((PREFIX, PREF_PREFIX)): old.unlink()
    tiles = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers,
            initializer=initialize, initargs=(list(original['tiles']),)) as pool:
        for done, result in enumerate(pool.map(render, jobs, chunksize=32), 1):
            if result:
                tiles[result[0]] = result[1]
            if done % 5000 == 0:
                print('Processed', done, '/', len(jobs), 'cells;', len(tiles), 'images', flush=True)
    for old in OUT.glob('*.webp'):
        if not old.name.startswith((PREFIX, PREF_PREFIX)):
            old.unlink()
    (OUT / 'index.json').unlink(missing_ok=True)
    (OUT / 'index-contrast.json').unlink(missing_ok=True)
    (OUT / 'index-plain.json').unlink(missing_ok=True)
    (OUT / 'index-shared.json').unlink(missing_ok=True)
    original.update(tiles=dict(sorted(tiles.items())), filenamePrefix=PREFIX, layerFilenamePrefixes={'pref': PREF_PREFIX},
        style='slimmer antialiased white line without casing; quarter-pixel expansion',
        sourceIndexSha256=hashlib.sha256((SOURCE / 'index.json').read_bytes()).hexdigest(),
        processing=original['processing'] + ' 縁取りなしの細い白線を事前生成。隣接タイルの画素を含めて継ぎ目を防止。')
    (OUT / INDEX).write_text(json.dumps(original, ensure_ascii=False, separators=(',', ':')))
    print('Plain borders:', len(tiles), 'images;', sum(tiles.values()), 'bytes', flush=True)


if __name__ == '__main__':
    main()
