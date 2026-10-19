"""Bundle compressed map bytes into bounded disk/download packs (no image decode)."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

PACK_BYTES = 1024 * 1024
PACK_FILES = 512


def worker_source():
    web = Path(__file__).resolve().parents[1]/'web'
    return (web/'vendor/fast-sha256.js').read_text() + '\n' + (web/'map-cache-worker.js').read_text()


def prepare(root):
    previous = root / 'map-image-manifest.json'
    if previous.exists() and not any((root/'assets/assets/data/map_tiles_uniform').glob('*.webp')):
        manifest = json.loads(previous.read_text())
        if manifest.get('packSchema') == 1:
            assert all((root/pack[0]).is_file() for pack in manifest['packs'])
            source = worker_source()
            (root/'map-cache-worker.js').write_text(source.replace('__MAP_IMAGE_REVISION__', manifest['revision']))
            print(f'Map packs already prepared: {len(manifest["packs"]):,}')
            if (root/'main.dart.js').exists():
                from prepare_runtime_cache import prepare as prepare_runtime
                prepare_runtime(root)
            return
    assets = []
    sources = []
    for folder in ('map_tiles_uniform', 'border_tiles'):
        directory = root / 'assets/assets/data' / folder
        for path in sorted(directory.iterdir()):
            if path.suffix not in ('.webp', '.json'):
                continue
            data = path.read_bytes()
            assets.append([str(path.relative_to(root)), hashlib.sha256(data).hexdigest(), len(data)])
            sources.append(path)
    if not assets:
        raise ValueError('Build the Flutter web bundle before preparing map storage')
    encoded = json.dumps(assets, separators=(',', ':')).encode()
    # Keep the image revision/cursor stable: existing individual downloads remain valid.
    revision = hashlib.sha256(encoded).hexdigest()
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
    manifest = dict(schema=1, packSchema=1, revision=revision, bytes=sum(a[2] for a in assets), assets=assets, packs=packs)
    (root / 'map-image-manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    source = worker_source()
    (root / 'map-cache-worker.js').write_text(source.replace('__MAP_IMAGE_REVISION__', revision))
    # The worker serves original asset URLs from packs. Do not double the Pages
    # release by shipping 44,396 separate images as well. Keep JSON indices direct.
    for path in sources:
        if path.suffix == '.webp':
            path.unlink()
    print(f'Map storage: {len(assets):,} assets, {len(packs):,} requests/writes, {manifest["bytes"]:,} bytes, revision {revision[:12]}')
    if (root/'main.dart.js').exists():
        from prepare_runtime_cache import prepare as prepare_runtime
        prepare_runtime(root)


if __name__ == '__main__':
    prepare(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web'))
