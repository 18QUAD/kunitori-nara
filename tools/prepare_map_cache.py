"""Create a content-versioned inventory for the on-device map image store."""
import hashlib
import json
import sys
from pathlib import Path


def prepare(root):
    assets = []
    for folder in ('map_tiles_uniform', 'border_tiles'):
        directory = root / 'assets/assets/data' / folder
        for path in sorted(directory.iterdir()):
            if path.suffix not in ('.webp', '.json'):
                continue
            data = path.read_bytes()
            assets.append([str(path.relative_to(root)), hashlib.sha256(data).hexdigest(), len(data)])
    if not assets:
        raise ValueError('Build the Flutter web bundle before preparing map storage')
    encoded = json.dumps(assets, separators=(',', ':')).encode()
    revision = hashlib.sha256(encoded).hexdigest()
    manifest = dict(schema=1, revision=revision, bytes=sum(a[2] for a in assets), assets=assets)
    (root / 'map-image-manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    # Always start from the source, so rerunning preparation is deterministic.
    source = (Path(__file__).resolve().parents[1] / 'web/map-cache-worker.js').read_text()
    (root / 'map-cache-worker.js').write_text(source.replace('__MAP_IMAGE_REVISION__', revision))
    print(f'Map storage inventory: {len(assets):,} files, {manifest["bytes"]:,} bytes, revision {revision[:12]}')


if __name__ == '__main__':
    prepare(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web'))
