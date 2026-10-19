"""Precompute Nara's parent map shapes without modifying legacy town geometry.

Like the other prefectures, Nara loads municipal/prefecture unions from disk.
Retain all census holes and detached polygons: these shapes also drive clipping
and hit testing. No coordinate simplification or changes to gameplay data.
"""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

from build_border_tiles import joined, polygons

DATA = Path(__file__).resolve().parents[1] / 'assets/data'


def coordinates(geometry):
    return [
        [list(poly.exterior.coords), *[list(ring.coords) for ring in poly.interiors]]
        for poly in polygons(geometry)
    ]


def build(source):
    data = json.loads(source)
    by_city = defaultdict(list)
    for town in data['towns']:
        by_city[town['cityId']].extend(town['polygons'])
    cities = [
        {**city, 'polygons': coordinates(joined(by_city[city['id']]))}
        for city in data['cities']
    ]
    return {
        'schema': 1,
        'sourceSha256': hashlib.sha256(source).hexdigest(),
        'cities': cities,
        'polygons': coordinates(joined([
            polygon for city in cities for polygon in city['polygons']
        ])),
    }


if __name__ == '__main__':
    target = DATA / 'nara_outlines.json'
    target.write_text(json.dumps(build((DATA / 'nara.json').read_bytes()),
                                 ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{target.name}: {target.stat().st_size:,} bytes; original nara.json unchanged')
