"""Bundle compressed map bytes into bounded disk/download packs (no image decode)."""
import hashlib
import json
import shutil
import sys
import subprocess
from pathlib import Path

PACK_BYTES = 1024 * 1024
PACK_FILES = 512
PAGES_IMAGE_BUDGET = 750 * 1024 * 1024


def worker_source():
    web = Path(__file__).resolve().parents[1]/'web'
    return (web/'vendor/fast-sha256.js').read_text() + '\n' + (web/'map-cache-worker.js').read_text()


def prepare(root, source_root=None):
    prepared = Path(__file__).resolve().parents[1]/'data/prepared_maps'
    index = root/'assets/assets/data/map_images/index.json'
    packed_build = (source_root is None and index.exists()
                    and not any(index.parent.glob('*.webp'))
                    and (prepared/'map-image-manifest.json').exists())
    if packed_build:
        manifest = json.loads((prepared/'map-image-manifest.json').read_text())
        packed_build = hashlib.sha256(index.read_bytes()).hexdigest() == manifest['indexSha256']
        if not packed_build and (root/'main.dart.js').exists():
            raise ValueError('Prepared map packs do not match the built geographic index; regenerate and rebuild')
    if packed_build:
        # The source repository stores bounded, finished packs. Flutter's asset
        # manifest contains only the geographic index, not hundreds of thousands
        # of individual tile names that would be parsed into memory at startup.
        shutil.rmtree(root/'map-packs', ignore_errors=True)
        if manifest['bytes'] > PAGES_IMAGE_BUDGET:
            # Keep full-resolution images when the prepared nationwide pyramid
            # exceeds Pages' site limit. These are the same public repository's
            # immutable committed bytes, downloaded once and verified on disk.
            repo = prepared.parents[1]
            commit = subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
            committed = subprocess.check_output(['git','show','HEAD:data/prepared_maps/map-image-manifest.json'],cwd=repo)
            if committed != (prepared/'map-image-manifest.json').read_bytes():
                raise ValueError('Commit the finished image packs before preparing the public build')
            manifest['packBaseUrl'] = f'https://raw.githubusercontent.com/18QUAD/kunitori-nara/{commit}/data/prepared_maps/'
        else:
            shutil.copytree(prepared/'map-packs', root/'map-packs', dirs_exist_ok=True)
        (root/'map-image-manifest.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
        # Native platforms bundle these packs. The web worker serves one copy
        # from map-packs/, so don't ship a second copy in Flutter's asset tree.
        shutil.rmtree(root/'assets/data/prepared_maps', ignore_errors=True)
        (root/'map-cache-worker.js').write_text(worker_source().replace('__MAP_IMAGE_REVISION__', manifest['revision']))
        if (root/'main.dart.js').exists():
            from prepare_runtime_cache import prepare as prepare_runtime
            prepare_runtime(root)
        return
    previous = root / 'map-image-manifest.json'
    if source_root is None and previous.exists() and not any((root/'assets/assets/data/map_images').glob('*.webp')):
        manifest = json.loads(previous.read_text())
        if manifest.get('packSchema') in (1, 2):
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
    for folder in ('map_images',):
        directory = (source_root or root / 'assets/assets/data') / folder
        index = json.loads((directory/'index.json').read_text()) if source_root is not None else {}
        allowed = {f'{key}.webp' for key in index['tiles']} | {'index.json'} if 'tiles' in index else None
        for path in sorted(directory.iterdir()):
            if path.suffix not in ('.webp', '.json'):
                continue
            if source_root is not None and path.suffix == '.json':
                # The geographic index can be larger than a bounded image pack.
                # It is bundled separately and streamed through runtime chunks.
                continue
            if allowed is not None and path.name not in allowed:
                continue
            data = path.read_bytes()
            assets.append([f'assets/assets/data/{folder}/{path.name}', hashlib.sha256(data).hexdigest(), len(data)])
            sources.append(path)
    if not assets:
        raise ValueError('Build the Flutter web bundle before preparing map storage')
    encoded = json.dumps(assets, separators=(',', ':')).encode()
    # Keep the image revision/cursor stable: existing individual downloads remain valid.
    compact = source_root is not None
    index_digest = hashlib.sha256((source_root/'map_images/index.json').read_bytes()).hexdigest() if compact else ''
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
    # every tiny image needlessly bloats the worker's resident inventory.
    entries = [[Path(a[0]).name, a[2]] for a in assets] if compact else assets
    manifest = dict(schema=1, packSchema=2 if compact else 1, revision=revision,
                    bytes=sum(a[2] for a in assets), assets=entries, packs=packs)
    if compact:
        manifest['assetPrefix'] = 'assets/assets/data/map_images/'
        manifest['indexSha256'] = index_digest
    (root / 'map-image-manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    if source_root is None:
        source = worker_source()
        (root / 'map-cache-worker.js').write_text(source.replace('__MAP_IMAGE_REVISION__', revision))
    # The worker serves original asset URLs from packs. Do not double the Pages
    # release by shipping 44,396 separate images as well. Keep JSON indices direct.
    for path in sources:
        if source_root is None and path.suffix == '.webp':
            path.unlink()
    print(f'Map storage: {len(assets):,} assets, {len(packs):,} requests/writes, {manifest["bytes"]:,} bytes, revision {revision[:12]}')
    if (root/'main.dart.js').exists():
        from prepare_runtime_cache import prepare as prepare_runtime
        prepare_runtime(root)


if __name__ == '__main__':
    prepare(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web'))
