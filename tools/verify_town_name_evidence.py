"""Verify supplied audit inputs without changing data or approving new names.

Requires shapely (same dependency as import_japan.py). See the audit README.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import zipfile

from shapely.geometry import Point, Polygon
from import_japan import decode, polygons

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--abr-zip', type=Path, required=True)
    parser.add_argument('--codh-topojson', type=Path, required=True)
    parser.add_argument('--mlit-dir', type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads((ROOT / 'docs/town-name-audit/evidence.json').read_text())
    assert hashlib.sha256(args.abr_zip.read_bytes()).hexdigest() == evidence['abr_zip']['sha256']
    with zipfile.ZipFile(args.abr_zip) as archive:
        raw = archive.read('mt_town_all.csv')
        assert hashlib.sha256(raw).hexdigest() == evidence['abr_zip']['csv_sha256']
        rows = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
        kyotanabe = []
        count = 0
        for row in rows:
            count += 1
            if row['lg_code'] == '262111':
                kyotanabe.append(row)
        assert count == evidence['abr_zip']['row_count']
    tanabe = next(row for row in kyotanabe if row['machiaza_id'] == '0594000')
    assert (tanabe['oaza_cho'], tanabe['chome'], tanabe['koaza']) == ('田辺', '', '')
    assert not tanabe['ablt_date']
    raw_topology = args.codh_topojson.read_bytes()
    assert hashlib.sha256(raw_topology).hexdigest() == evidence['codh_original']['sha256']
    topology = json.loads(raw_topology)
    arcs = decode(topology)
    targets = {'26211010001': [], '26211012001': []}
    for geo in topology['objects']['town']['geometries']:
        key = geo['properties']['KEY_CODE']
        if key in targets:
            targets[key].append((geo['properties'], [
                Polygon(rings[0], rings[1:]) for rings in polygons(geo, arcs)
            ]))
    assert len(targets['26211010001']) == 1
    assert len(targets['26211012001']) == 2
    assert sum(p['JINKO'] or 0 for p, _ in targets['26211010001']) == 4911
    assert sum(p['JINKO'] or 0 for p, _ in targets['26211012001']) == 1714
    for archive_name, year, expected in [
        ('26000-14.0b.zip', 2020, evidence['mlit_2020']['26']['sha256']),
        ('26000-19.0b.zip', 2025, evidence['mlit_2025_kyoto']['sha256']),
    ]:
        archive_path = args.mlit_dir / archive_name
        assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == expected
        with zipfile.ZipFile(archive_path) as archive:
            name = next(name for name in archive.namelist() if name.endswith('.csv'))
            records = list(csv.DictReader(io.StringIO(archive.read(name).decode('cp932'))))
        points = [row for row in records if row['市区町村コード'] == '26211']
        reference = next(row for row in points if row['大字町丁目名'] == '田辺')
        point = Point(float(reference['経度']), float(reference['緯度']))
        assert any(p.contains(point) for _, parts in targets['26211010001'] for p in parts)
        # Independently inspect both components of the repeated Kawara ID.
        for props, parts in targets['26211012001']:
            assert all(p.is_valid for p in parts)
            hits = [row['大字町丁目名'] for row in points if any(
                p.contains(Point(float(row['経度']), float(row['緯度']))) for p in parts
            )]
            recorded = next(c for c in evidence['spatial_components']
                            if c['source_id'] == '26211012001' and c['component'] == props['KIGO_E'])
            assert sorted(hits) == sorted(p['大字町丁目名'] for p in recorded['reference_points'] if p['year'] == year)
    print('Verified ABR receipts, 2020/2025 Tanabe points, and both Kawara components; no new names approved.')


if __name__ == '__main__':
    main()
