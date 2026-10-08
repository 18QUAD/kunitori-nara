"""Extract 2021 MLIT building land (0700); requires shapely, pyshp, pyproj."""
import argparse
import datetime
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

import shapefile
from pyproj import CRS, Transformer
from shapely.geometry import Polygon, shape, mapping, box
from shapely.ops import unary_union, transform

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'data/raw/urban'
SOURCE = 'https://nlftp.mlit.go.jp/ksj/gml/data/L03-b/L03-b-21/'
SPEC = 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L03-b-v3_1.html'
CODES = ['5035', '5036', '5135', '5136', '5235', '5236']


def polygons(g):
    if g.is_empty:
        return
    if g.geom_type == 'Polygon':
        yield g
    elif hasattr(g, 'geoms'):
        for part in g.geoms:
            yield from polygons(part)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, action='append', help='Repeat for all six source ZIPs')
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    archives = args.archive
    if archives is None:
        archives = []
        for code in CODES:
            path = CACHE / f'L03-b-21_{code}-jgd2011_GML.zip'
            if not path.exists():
                urllib.request.urlretrieve(SOURCE + path.name, path)
            archives.append(path)
    if sorted(p.name for p in archives) != sorted(f'L03-b-21_{c}-jgd2011_GML.zip' for c in CODES):
        raise ValueError('All six JGD2011 archives covering Nara are required')
    atlas = json.loads((ROOT / 'assets/data/nara.json').read_text())
    county = unary_union([Polygon(p[0], p[1:]).buffer(0) for t in atlas['towns'] for p in t['polygons']])
    cells, sources = [], []
    for path in sorted(archives):
        with zipfile.ZipFile(path) as z:
            name, = [n[:-4] for n in z.namelist() if n.endswith('.shp')]
            crs = CRS.from_wkt(z.read(name + '.prj').decode())
            if crs.to_epsg() != 6668:
                raise ValueError(f'Unexpected CRS: {crs}')
            project = Transformer.from_crs(crs, 4326, always_xy=True).transform
            reader = shapefile.Reader(**{ext: io.BytesIO(z.read(name + '.' + ext)) for ext in ['shp', 'shx', 'dbf']}, encoding='cp932')
            count = 0
            for record in reader.iterRecords():
                if record['L03b_002'] != '0700':
                    continue
                s = reader.shape(record.oid)
                if not county.intersects(box(*s.bbox)):
                    continue
                g = transform(project, shape(s.__geo_interface__))
                if g.intersects(county):
                    cells.append(g)
                    count += 1
            sources.append({'url': SOURCE + path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'crs': crs.to_string(), 'records': len(reader), 'building_cells_intersecting_nara': count})
            print(path.name, count, flush=True)
    if not cells:
        raise ValueError('No building cells extracted')
    # Snap sub-nanodegree source rounding before dissolving adjacent mesh cells.
    import shapely
    merged = unary_union([shapely.set_precision(g, 1e-8) for g in cells]).intersection(county)
    areas = [mapping(p)['coordinates'] for p in polygons(merged)]
    output = {'metadata': {'source': '国土交通省 国土数値情報 土地利用細分メッシュ', 'year': 2021, 'specification': SPEC, 'license': 'https://nlftp.mlit.go.jp/ksj/other/agreement.html', 'retrieved_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'classification_field': 'L03b_002', 'classification_code': '0700', 'classification': '建物用地', 'mesh_size_m_approx': 100, 'crs': 'EPSG:4326', 'processing': '建物用地を抽出、隣接セルを結合しアプリの奈良県境でクリップ。DIDではない。', 'sources': sources, 'cell_count': len(cells), 'polygon_count': len(areas)}, 'areas': areas}
    target = ROOT / 'assets/data/nara_urban.json'
    target.write_text(json.dumps(output, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(target, len(areas), target.stat().st_size)


if __name__ == '__main__':
    main()
