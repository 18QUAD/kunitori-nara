"""Pack map images for native app downloads without decoding them."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

PACK_BYTES = 1024 * 1024
PACK_FILES = 512


def prepare(root, source_root):
    """Pack canonical map images for the Android/iOS download cache."""
    assets = []
    sources = []
    for folder in ('map_images',):
        directory = source_root / folder
        index = json.loads((directory/'index.json').read_text())
        allowed = {f'{key}.webp' for key in index['tiles']} | {'index.json'} if 'tiles' in index else None
        for path in sorted(directory.iterdir()):
            if path.suffix not in ('.webp', '.json'):
                continue
            if path.suffix == '.json':
                # The geographic index can be larger than a bounded image pack.
                # It is bundled separately from the native image packs.
                continue
            if allowed is not None and path.name not in allowed:
                continue
            data = path.read_bytes()
            assets.append([f'assets/assets/data/{folder}/{path.name}', hashlib.sha256(data).hexdigest(), len(data)])
            sources.append(path)
    if not assets:
        raise ValueError('Generate canonical map images before preparing native packs')
    encoded = json.dumps(assets, separators=(',', ':')).encode()
    # Keep the image revision/cursor stable: existing individual downloads remain valid.
    index_digest = hashlib.sha256((source_root/'map_images/index.json').read_bytes()).hexdigest()
    revision = hashlib.sha256(encoded + index_digest.encode()).hexdigest()
    directory = root / 'map-packs'
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir()
    packs = []
    start = 0
    while start < len(assets):
        end = start
        size = 0
        while end < len(assets) and end - start < PACK_FILES:
            length = assets[end][2]
            if end > start and size + length > PACK_BYTES:
                break
            size += length
            end += 1
        data = b''.join(path.read_bytes() for path in sources[start:end])
        digest = hashlib.sha256(data).hexdigest()
        name = f'map-packs/{digest}.bin'
        (root / name).write_bytes(data)
        packs.append([name, digest, len(data), start, end])
        start = end
    # Prepared images have no legacy per-image disk entries. Pack checksums
    # authenticate every byte; repeating a 64-character hash and full URL for
    # every tiny image needlessly bloats the native download inventory.
    entries = [[Path(a[0]).name, a[2]] for a in assets]
    manifest = dict(schema=1, packSchema=2, revision=revision,
                    bytes=sum(a[2] for a in assets), assets=entries, packs=packs)
    manifest['assetPrefix'] = 'assets/assets/data/map_images/'
    manifest['indexSha256'] = index_digest
    (root / 'map-image-manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    print(f'Map storage: {len(assets):,} assets, {len(packs):,} packs, {manifest["bytes"]:,} bytes, revision {revision[:12]}')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: prepare_map_cache.py OUTPUT_DIRECTORY SOURCE_DATA_DIRECTORY')
    prepare(Path(sys.argv[1]), Path(sys.argv[2]))
