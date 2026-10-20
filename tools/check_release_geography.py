"""Guard deployed geography assets and the Pages size budget after a build."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]/'build/web'
compiled = (root/'main.dart.js').read_text()
for folder in ['water','urban','relief','map_tiles','map_tiles_v2']:
    path = f'assets/data/{folder}/'
    assert path not in compiled, f'Unexpected live reference to source GIS: {path}'
    assert not (root/'assets'/path).exists(), f'Unused source GIS was bundled: {path}'
assert 'assets/data/map_images/' in compiled
assert 'assets/data/map_labels/' in compiled
for folder in ['map_tiles_uniform','border_tiles','water_mesh']:
    assert f'assets/data/{folder}/' not in compiled
    assert not (root/'assets/assets/data'/folder).exists()
assert 'assets/data/prefecture_border_mesh.bin' not in compiled
for name in ['japan_relief.png','japan_relief.json','nara_relief.png',
             'nara_relief.json','nara_water.json','nara_urban.json']:
    assert f'assets/data/{name}' not in compiled
    assert not (root/'assets/assets/data'/name).exists(), f'Unused source GIS: {name}'
index=json.loads((root/'assets/assets/data/map_images/index.json').read_text())
assert index['schema']==2 and index['sampling']==2
for layer, maximum in index['layerMaxLevels'].items():
    for level in range(index['minLevel'], maximum+1):
        assert any(k.startswith(f'{level}_') and k.endswith('_'+layer) for k in index['tiles']), (layer,level)
source=(root.parents[1]/'lib/geography_tiles.dart').read_text()
assert 'PictureRecorder' not in source and '.toImage(' not in source
assert 'WaterMesh' not in source and 'PrefectureBorderMesh' not in source
inventory = json.loads((root/'map-image-manifest.json').read_text())
assert inventory['packSchema'] == 2
assert len(index['prefectureCoverage']) == 47 and all(index['prefectureCoverage'].values())
import hashlib
assert hashlib.sha256((root/'assets/assets/data/map_images/index.json').read_bytes()).hexdigest() == inventory['indexSha256']
pack_root = root
if inventory.get('packBaseUrl'):
    import re
    assert re.fullmatch(r'https://raw\.githubusercontent\.com/18QUAD/kunitori-nara/[0-9a-f]{40}/data/prepared_maps/',inventory['packBaseUrl'])
    pack_root = root.parents[1]/'data/prepared_maps'
    assert not (root/'map-packs').exists(), 'Remote packs must not be duplicated on Pages'
cursor = 0
for name, digest, size, start, end in inventory['packs']:
    assert start == cursor and end > start
    assert size <= 1024 * 1024, 'Image packs must remain bounded'
    packed = (pack_root/name).read_bytes()
    assert len(packed) == size and hashlib.sha256(packed).hexdigest() == digest
    offset = 0
    for filename, length in inventory['assets'][start:end]:
        path = inventory['assetPrefix'] + filename
        data = packed[offset:offset+length]
        assert len(data) == length, path
        # The complete pack's checksum was checked above. Also compare every
        # slice to the actual prepared source to catch offset/index mistakes.
        source_image = root.parents[1]/'assets/data/map_images'/filename
        if source_image.exists(): assert data == source_image.read_bytes()
        if path.endswith('.json'):
            assert (root/path).read_bytes() == data
        else:
            assert not (root/path).exists(), 'Individual images duplicate pack bytes'
        offset += length
    assert offset == size
    cursor = end
assert cursor == len(inventory['assets'])
assert sum(entry[1] for entry in inventory['assets']) == inventory['bytes']
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

# Prepared town shapes must correspond to the exact original census and grouping.
territories = json.loads((root.parents[1]/'assets/data/national_territories/index.json').read_text())
assert len(territories['prefectures']) == 47
aliases = {entry['path']: entry for entry in runtime['files']}
for pref, entry in territories['prefectures'].items():
    original = 'nara.json' if pref == '29' else f'prefectures/{pref}.json'
    assert aliases['assets/assets/data/'+original]['sha256'] == entry['sourceSha256']
    alias = f'assets/assets/data/national_territories/{pref}.bin'
    assert aliases[alias]['sha256'] == entry['sha256']
    assert not (root/alias).exists(), 'Prepared shapes must not be duplicated on Pages'
print('PASS: all 47 prepared territory files match the deployed census and source hashes.')
