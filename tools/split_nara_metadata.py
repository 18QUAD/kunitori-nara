"""Keep legacy Nara statistics available without loading its map coordinates."""
import json
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / 'assets/data'


def metadata():
    data = json.loads((DATA / 'nara.json').read_text())
    for town in data['towns']:
        town['polygons'] = []
    return data


if __name__ == '__main__':
    target = DATA / 'nara_metadata.json'
    target.write_text(json.dumps(metadata(), ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{target.name}: {target.stat().st_size:,} bytes; original nara.json unchanged')
