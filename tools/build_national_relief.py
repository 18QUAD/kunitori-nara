"""Build a compact, georeferenced national overview from the offline GSI relief.

Run import_national_relief.py first. No downloads; requires Pillow. Full-resolution
prefecture images remain available for prefecture/municipality views.
"""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
WEST, SOUTH, EAST, NORTH = 122., 20., 154.5, 46.
WIDTH = 4096
HEIGHT = math.ceil(WIDTH * (NORTH-SOUTH) / (EAST-WEST))


def main():
    overview = Image.new('RGBA', (WIDTH, HEIGHT))
    index = json.loads((DATA / 'relief/index.json').read_text())
    sources = []
    for tile in index['tiles']:
        if tile['available']:
            sources.append((DATA / f"relief/{tile['x']}_{tile['y']}.png", tile))
    # Nara retains its existing, finer elevation source, including central tiles
    # which need not overlap any other prefecture's DEM.
    sources.append((DATA / 'nara_relief.png', json.loads((DATA / 'nara_relief.json').read_text())))
    hashes = {}
    for path, bounds in sources:
        left = round((bounds['west']-WEST)/(EAST-WEST)*WIDTH)
        right = round((bounds['east']-WEST)/(EAST-WEST)*WIDTH)
        top = round((NORTH-bounds['north'])/(NORTH-SOUTH)*HEIGHT)
        bottom = round((NORTH-bounds['south'])/(NORTH-SOUTH)*HEIGHT)
        with Image.open(path) as image:
            patch = image.convert('RGBA').resize((right-left, bottom-top), Image.Resampling.LANCZOS)
            overview.alpha_composite(patch, (left, top))
        hashes[path.relative_to(DATA).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    overview.save(DATA / 'japan_relief.png', optimize=True)
    metadata = dict(west=WEST, south=SOUTH, east=EAST, north=NORTH, width=WIDTH, height=HEIGHT,
                    attribution=index['attribution'], source=index['source'],
                    processing='全国表示用に経緯度グリッドへ縮小合成。標高欠損は透明。描画時に県の形状で切り抜く。',
                    sourceHashes=hashes)
    (DATA / 'japan_relief.json').write_text(json.dumps(metadata, ensure_ascii=False, separators=(',', ':'))+'\n')
    print(f'National relief: {WIDTH} x {HEIGHT}, {(DATA / "japan_relief.png").stat().st_size:,} bytes')


if __name__ == '__main__':
    main()
