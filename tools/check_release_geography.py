"""Guard deployed geography assets and the Pages size budget after a build."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]/'build/web'
compiled = (root/'main.dart.js').read_text()
for folder in ['water','urban','relief','map_tiles','map_tiles_v2']:
    path = f'assets/data/{folder}/'
    assert path not in compiled, f'Unexpected live reference to source GIS: {path}'
    assert not (root/'assets'/path).exists(), f'Unused source GIS was bundled: {path}'
assert 'assets/data/map_tiles_uniform/' in compiled
assert 'assets/data/map_labels/' in compiled
assert 'assets/data/water_mesh/' in compiled
assert (root/'assets/assets/data/map_tiles_uniform/index-dry.json').is_file()
assert len(list((root/'assets/assets/data/water_mesh').glob('*.bin'))) == 48
assert not list((root/'assets/assets/data/map_tiles_uniform').glob('[0-9]*_detail.webp')), 'Blurred combined water was bundled'
assert 'assets/data/border_tiles/' in compiled
assert 'assets/data/prefecture_border_mesh.bin' in compiled
assert (root/'assets/assets/data/prefecture_border_mesh.bin').is_file()
assert (root/'assets/assets/data/border_tiles/index-slim.json').is_file()
assert all(p.name.startswith(('slim_', 'slimshared_')) for p in (root/'assets/assets/data/border_tiles').glob('*.webp')), 'Outdated border style was bundled'
inventory = json.loads((root/'map-image-manifest.json').read_text())
assert inventory['packSchema'] == 1
import hashlib
cursor = 0
for name, digest, size, start, end in inventory['packs']:
    assert start == cursor and end > start
    packed = (root/name).read_bytes()
    assert len(packed) == size and hashlib.sha256(packed).hexdigest() == digest
    offset = 0
    for path, checksum, length in inventory['assets'][start:end]:
        data = packed[offset:offset+length]
        assert len(data) == length and hashlib.sha256(data).hexdigest() == checksum, path
        if path.endswith('.json'):
            assert (root/path).read_bytes() == data
        else:
            assert not (root/path).exists(), 'Individual images duplicate pack bytes'
            if '/border_tiles/' in path:
                assert Path(path).name.startswith(('slim_', 'slimshared_'))
        offset += length
    assert offset == size
    cursor = end
assert cursor == len(inventory['assets'])
assert sum(entry[2] for entry in inventory['assets']) == inventory['bytes']
assert '__MAP_IMAGE_REVISION__' not in (root/'map-cache-worker.js').read_text(), 'Map worker was not prepared'
assert inventory['revision'] in (root/'map-cache-worker.js').read_text()
size = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
assert size < 1024**3, f'Pages release exceeds 1 GiB: {size:,} bytes'
print(f'PASS: runtime uses baked geography/border tiles and labels; no source GIS references; release {size:,} bytes (<1 GiB).')

# Offline runtime aliases reconstruct exactly the original data and code.
import gzip
runtime = json.loads((root/'runtime-data-manifest.json').read_text())
assert runtime['revision'] in (root/'map-cache-worker.js').read_text()
for chunk in runtime['chunks']:
    data=(root/chunk[0]).read_bytes()
    assert len(data)==chunk[2] and len(data)<=1024*1024
    assert hashlib.sha256(data).hexdigest()==chunk[1]
for entry in runtime['files']:
    packed=b''.join((root/runtime['chunks'][i][0]).read_bytes() for i in entry['chunks'])
    data=gzip.decompress(packed)
    assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],entry['path']
    if (root/entry['path']).exists(): assert (root/entry['path']).read_bytes()==data
print(f'PASS: {len(runtime["files"])} runtime files reconstruct byte-for-byte from verified bounded local chunks.')
