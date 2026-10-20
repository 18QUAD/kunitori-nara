"""Prepare canonical gameplay-town fill geometry, offline, without changing saves.

KNT4 stores an ID directory and ready-to-draw polygon contours. Overlapping source
parts are unioned once here. Exact microdegree rings use int32 deltas; other rings
keep float64 coordinates, with no simplification or quantization.
Run tools/export_border_groups.dart before this builder when grouping changes.
"""
import gzip
import hashlib
import io
import json
import struct
from collections import defaultdict
from pathlib import Path
from build_border_tiles import joined, polygons

DATA = Path(__file__).resolve().parents[1] / 'assets/data'
OUT = DATA / 'national_territories'
GROUPS = DATA.parents[1] / 'data/raw/border_tiles/groups.json'


def coordinates(shape):
    return [[list(p.exterior.coords), *[list(r.coords) for r in p.interiors]]
            for p in polygons(shape)]


def encode(shapes):
    payload = io.BytesIO()
    entries = []
    for name, parts in shapes.items():
        start = payload.tell()
        payload.write(struct.pack('<I', len(parts)))
        for polygon in parts:
            payload.write(struct.pack('<I', len(polygon)))
            for ring in polygon:
                micro = [(round(x * 1e6), round(y * 1e6)) for x, y in ring]
                exact = all(ix / 1e6 == x and iy / 1e6 == y
                            for (ix, iy), (x, y) in zip(micro, ring))
                payload.write(struct.pack('<BI', int(exact), len(ring)))
                last_x = last_y = 0
                for (x, y), (ix, iy) in zip(ring, micro):
                    if exact:
                        payload.write(struct.pack('<ii', ix - last_x, iy - last_y))
                        last_x, last_y = ix, iy
                    else:
                        payload.write(struct.pack('<dd', x, y))
        entries.append((name, start, payload.tell() - start))
    header = 8 + sum(1 + len(name.encode('ascii')) + 8 for name, _, _ in entries)
    output = io.BytesIO()
    output.write(struct.pack('<4sI', b'KNT4', len(entries)))
    for name, start, length in entries:
        name = name.encode('ascii')
        output.write(struct.pack('<B', len(name)))
        output.write(name)
        output.write(struct.pack('<II', header + start, length))
    output.write(payload.getvalue())
    return output.getvalue()


def prepare(data, mapping, nara_outlines=None):
    groups = defaultdict(list)
    for row in data['towns']:
        groups[mapping[row['id']]].extend(row['polygons'])
    shapes = {name: coordinates(joined(parts)) for name, parts in groups.items()}
    parent = nara_outlines or data
    for city in parent['cities']:
        shapes[city['id']] = city['polygons']
    shapes['pref'] = parent['polygons']
    return shapes


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    group_bytes = GROUPS.read_bytes()
    mapping = json.loads(group_bytes)['sourceToTown']
    report = {'schema': 2, 'encoding': 'KNT4/prepared-town-contours',
              'groupSha256': hashlib.sha256(group_bytes).hexdigest(), 'prefectures': {}}
    for number in range(1, 48):
        pref = f'{number:02d}'
        source = DATA / ('nara.json' if pref == '29' else f'prefectures/{pref}.json')
        original = source.read_bytes()
        outlines = json.loads((DATA / 'nara_outlines.json').read_bytes()) if pref == '29' else None
        shapes = prepare(json.loads(original), mapping, outlines)
        packed = encode(shapes)
        (OUT / f'{pref}.bin').write_bytes(packed)
        report['prefectures'][pref] = {
            'sourceSha256': hashlib.sha256(original).hexdigest(), 'sourceBytes': len(original),
            'sha256': hashlib.sha256(packed).hexdigest(), 'towns': sum(len(k) > 5 for k in shapes),
            'bytes': len(packed), 'gzipBytes': len(gzip.compress(packed, mtime=0)),
        }
        print(pref, len(packed), flush=True)
    (OUT / 'index.json').write_text(json.dumps(report, separators=(',', ':')) + '\n')
    print('47 prepared shapes:', sum(p['bytes'] for p in report['prefectures'].values()),
          'bytes;', sum(p['gzipBytes'] for p in report['prefectures'].values()), 'gzip bytes')
