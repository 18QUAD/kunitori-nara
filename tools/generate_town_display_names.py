"""Generate display names; --check verifies outputs without writing them.

--estat-dir verifies the checked-in field snapshot against all 47 original
e-Stat CSV downloads, including the SHA-256 hashes in source-receipts.json.
"""
import argparse
import collections
import csv
import gzip
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / 'docs/town-name-audit/naming-rules'


def read_fields(estat_dir=None):
    with gzip.open(AUDIT / 'source-fields.csv.gz', 'rt', encoding='utf-8', newline='') as stream:
        rows = list(csv.DictReader(stream))
    fields = {r['source_id']: (r['upper'], r['lower']) for r in rows}
    assert len(fields) == len(rows) == 220814
    if estat_dir:
        official = {}
        receipts = json.loads((AUDIT / 'source-receipts.json').read_text())
        assert len(receipts['sources']) == 47 and not receipts['failures']
        for receipt in receipts['sources']:
            raw = (estat_dir / Path(receipt['file']).name).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == receipt['sha256']
            reader = csv.reader(io.StringIO(raw.decode('cp932')))
            header = [next(reader) for _ in range(5)]
            assert header[4][9:11] == ['大字・町名', '字・丁目名']
            for row in reader:
                if row[3] not in ('2', '4'):
                    continue
                source = row[1] + row[2]
                assert source not in official
                official[source] = (row[9], row[10])
        assert official == fields, 'Snapshot differs from official census fields'
    return fields


def select_names(fields):
    compact = ROOT / 'assets/data/compact'
    index = json.loads((compact / 'index.json').read_text())
    regions = {}
    for filename in index['townFiles']:
        for tid, name, population, _area, _neighbors in json.loads((compact / filename).read_text()):
            assert tid not in regions
            regions[tid] = dict(canonical=name, population=population, uppers=set(), lowers=set(),
                                has_text=False, all_oaza_prefix=True)
    seen = set()
    for path in sorted((compact / 'legacy').glob('*.json')):
        for source, tid, _population in json.loads(path.read_text()):
            assert source not in seen
            seen.add(source)
            upper, lower = fields[source]
            r = regions[tid]
            r['uppers'].add(upper)
            r['lowers'].add(lower)
            r['has_text'] |= bool(upper or lower)
            r['all_oaza_prefix'] &= (upper + lower).startswith('大字')
    assert seen == fields.keys()
    assert len(regions) == 141900
    groups = collections.defaultdict(list)
    full_names = set()
    for tid, r in regions.items():
        assert r['uppers'] and r['lowers']
        r['full'] = ('大字' if r['all_oaza_prefix'] else '') + r['canonical']
        full_key = (tid[:5], r['full'])
        assert full_key not in full_names, full_key
        full_names.add(full_key)
        r['upper'] = next(iter(r['uppers'])) if len(r['uppers']) == 1 else ''
        r['lower'] = next(iter(r['lowers'])) if len(r['lowers']) == 1 else ''
        if r['upper']:
            groups[tid[:5], r['upper']].append(tid)
    labels, reasons, forced = {}, {}, set()
    for ids in groups.values():
        blank_group = any('' in regions[tid]['lowers'] for tid in ids)
        for tid in ids:
            r = regions[tid]
            if len(ids) == 1:
                labels[tid], reasons[tid] = r['upper'], 'unique_upper'
            elif blank_group:
                labels[tid], reasons[tid] = r['full'], 'blank_lower_group_full_name'
                forced.add(tid)
            elif r['lower']:
                labels[tid], reasons[tid] = r['lower'], 'single_lower'
            else:
                labels[tid], reasons[tid] = r['upper'], 'merged_lower_keep_upper'
    for tid, r in regions.items():
        if tid not in labels:
            labels[tid] = r['full']
            reasons[tid] = 'preserve_existing_merged_name' if r['has_text'] else 'both_fields_blank'
            forced.add(tid)
    while True:
        buckets = collections.defaultdict(list)
        for tid, label in labels.items():
            buckets[tid[:5], label].append(tid)
        clashes = [ids for ids in buckets.values() if len(ids) > 1]
        if not clashes:
            break
        changed = 0
        for ids in clashes:
            for tid in ids:
                if tid not in forced:
                    changed += 1
                    forced.add(tid)
                    labels[tid], reasons[tid] = regions[tid]['full'], 'collision_use_full_merged_name'
        assert changed, 'Cannot resolve collisions using existing full names'
    for tid, r in regions.items():
        if not r['has_text']:
            assert labels[tid] == r['canonical'] == '名称未設定'
    return regions, labels, reasons


def outputs(regions, labels, reasons):
    def dart_string(value):
        return json.dumps(value, ensure_ascii=False).replace('$', '\\$')
    changed = sorted(tid for tid in regions if labels[tid] != regions[tid]['canonical'])
    lines = ['// GENERATED by tools/generate_town_display_names.py. Do not edit.',
             "part of '../town_display_names.dart';", '',
             'const townDisplayNames = <String, ({String sourceName, String displayName})>{']
    for tid in changed:
        lines.append(f'  {dart_string(tid)}: (sourceName: {dart_string(regions[tid]["canonical"])}, displayName: {dart_string(labels[tid])}),')
    lines.append('};\n')
    audit = io.StringIO(newline='')
    writer = csv.writer(audit, lineterminator='\n')
    writer.writerow(['id', 'source_name', 'display_name', 'rule', 'upper_names', 'lower_names'])
    for tid in sorted(regions):
        r = regions[tid]
        writer.writerow([tid, r['canonical'], labels[tid], reasons[tid],
                         json.dumps(sorted(r['uppers']), ensure_ascii=False),
                         json.dumps(sorted(r['lowers']), ensure_ascii=False)])
    summary = dict(region_count=len(regions), changed_display_names=len(changed),
                   unchanged_unnamed_regions=sum(not r['has_text'] for r in regions.values()),
                   final_same_city_collisions=0, decision_counts=dict(sorted(collections.Counter(reasons.values()).items())),
                   source_fields_sha256=hashlib.sha256((AUDIT / 'source-fields.csv.gz').read_bytes()).hexdigest())
    return {
        ROOT / 'lib/generated/town_display_names.g.dart': '\n'.join(lines).encode(),
        AUDIT / 'selected-names.csv.gz': gzip.compress(audit.getvalue().encode(), mtime=0),
        AUDIT / 'summary.json': (json.dumps(summary, ensure_ascii=False, indent=2) + '\n').encode(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--estat-dir', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    generated = outputs(*select_names(read_fields(args.estat_dir)))
    for path, content in generated.items():
        if args.check:
            assert path.read_bytes() == content, f'Generated file differs: {path}'
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(generated[AUDIT / 'summary.json'].decode())


if __name__ == '__main__':
    main()
