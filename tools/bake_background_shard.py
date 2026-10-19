"""Generate one deterministic geographic shard of the finest prepared images."""
import argparse
import concurrent.futures
import tarfile
from pathlib import Path
import bake_map_images as bake

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--shard', type=int, required=True)
parser.add_argument('--shards', type=int, default=8)
parser.add_argument('--workers', type=int, default=4)
args = parser.parse_args()
assert 0 <= args.shard < args.shards
work = bake.ROOT/'data/raw/shared_prefectures'
work.mkdir(parents=True, exist_ok=True)
with tarfile.open(bake.ROOT/'data/prepared_map_inputs/land.tar.gz') as archive:
    archive.extractall(work, filter='data')
bake.OUT.mkdir(exist_ok=True)
bake.initialize_background()
level = 8
cells = sorted({(x,y) for shape in bake.WATER
                for x,y in bake.cells_for(shape,level,.0004)
                if x % args.shards == args.shard})
count = 0
with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
    for result in pool.map(bake.render_background,
            [(level,x,y,'background') for x,y in cells], chunksize=16):
        if result: count += 1
print(f'Shard {args.shard}: {count} finished images',flush=True)
with tarfile.open(f'background-{args.shard}.tar.gz','w:gz',compresslevel=3) as archive:
    for path in sorted(bake.OUT.glob('8_*_background.webp')):
        archive.add(path,arcname=path.name)
