"""Guard deployed geography assets and the Pages size budget after a build."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]/'build/web'
compiled = (root/'main.dart.js').read_text()
for folder in ['water','urban','relief','map_tiles','map_tiles_v2']:
    path = f'assets/data/{folder}/'
    assert path not in compiled, f'Unexpected live reference to source GIS: {path}'
    assert not (root/'assets'/path).exists(), f'Unused source GIS was bundled: {path}'
assert 'assets/data/map_tiles_uniform/' in compiled
assert 'assets/data/map_labels/' in compiled
assert 'assets/data/border_tiles/' in compiled
assert (root/'assets/assets/data/border_tiles/index-plain.json').is_file()
size = sum(p.stat().st_size for p in root.rglob('*') if p.is_file())
assert size < 1024**3, f'Pages release exceeds 1 GiB: {size:,} bytes'
print(f'PASS: runtime uses baked geography/border tiles and labels; no source GIS references; release {size:,} bytes (<1 GiB).')
