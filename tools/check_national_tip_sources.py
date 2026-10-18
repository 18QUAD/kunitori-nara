#!/usr/bin/env python3
"""Validate collected identity, revision attribution and snapshot integrity."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/tips/nationwide'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshots', action='store_true')
    args = parser.parse_args()
    atlas = json.loads((ROOT / 'assets/data/japan.json').read_text())
    cities = {c['id']: c['name'] for c in atlas['cities'] if not c['id'].startswith('29')}
    entries = [e for p in sorted(OUT.glob('[0-9][0-9].json')) for e in json.loads(p.read_text())['municipalities']]
    seen = Counter(e['cityId'] for e in entries)
    assert set(seen) == set(cities), {'missing': sorted(set(cities) - set(seen)), 'unexpected': sorted(set(seen) - set(cities))}
    assert all(v == 1 for v in seen.values()), 'Duplicate municipality records'
    counts = Counter()
    for entry in entries:
        cid = entry['cityId']
        assert cid[:2] == entry['prefectureId'] and not cid.startswith('29')
        assert entry['cityName'] == cities[cid]
        if not entry.get('revisionId'):
            counts['unresolved'] += 1
            continue
        u = urlsplit(entry['revisionUrl'])
        assert u.hostname == 'ja.wikipedia.org' and u.scheme == 'https'
        assert parse_qs(u.query)['oldid'] == [str(entry['revisionId'])]
        assert entry['license'] == 'CC BY-SA 4.0' and entry['attribution']
        assert entry['reviewStatus'] == 'unreviewed_source_material'
        assert entry['parserVersion'] == 2
        assert entry['retrievedAt'] and len(entry['sha256']) == 64
        assert all(not any(word in m['text'] for word in ['人口', '世帯', '推計']) for m in entry['materials'])
        if args.snapshots:
            data = gzip.decompress((ROOT / entry['snapshot']).read_bytes())
            assert hashlib.sha256(data).hexdigest() == entry['sha256'], cid
        counts['collected'] += 1
        counts['materials'] += len(entry['materials'])
        counts['withoutMaterials'] += not bool(entry['materials'])
    assert counts['unresolved'] == 0, 'Unresolved municipality sources remain'
    assert counts['withoutMaterials'] == 0, 'Empty article extraction remains'
    official = json.loads((OUT / 'cultural_properties.json').read_text())
    assert {p['prefectureId'] for p in official['prefectures']} == {cid[:2] for cid in cities}
    for pref in official['prefectures']:
        assert pref['prefectureId'] != '29'
        for record in pref['records']:
            assert urlsplit(record['url']).hostname == 'kunishitei.bunka.go.jp'
            assert record['prefectureName'] in record['fields']['所在都道府県']
            assert all(cid in cities and cid.startswith(record['prefectureId']) for cid in record['cityIds'])
            if args.snapshots:
                assert hashlib.sha256(gzip.decompress((ROOT / record['snapshot']).read_bytes())).hexdigest() == record['sha256']
            counts['officialRecords'] += 1
    print('PASS:', dict(counts), 'municipalities', len(cities), 'prefectures', len(set(cid[:2] for cid in seen)))


if __name__ == '__main__':
    main()
