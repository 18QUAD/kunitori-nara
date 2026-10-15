"""Import MLIT building-land meshes as compact, offline masks for all Japan.

Requires numpy, Pillow, shapely, pyshp, pyproj. Selects the newest published
JGD2000/JGD2011 archive for each first-level mesh (2021, then 2016/older).
The 10-digit mesh code places each ~100m cell exactly; source SHP cells are
sampled to verify this placement. Only classification 0700 (or legacy 07) is used.
"""
import concurrent.futures
import datetime
import hashlib
import io
import json
import re
import time
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image
import shapefile
from pyproj import CRS, Transformer
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
OUT = DATA / 'urban'
CACHE = ROOT / 'data/raw/urban'
SPEC = 'https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-L03-b-v3_1.html'
BASE = 'https://nlftp.mlit.go.jp/ksj/gml/data/L03-b/'


def mesh_bounds(code):
    south, west = int(code[:2])*2/3, 100+int(code[2:4])
    return west, south, west+1, south+2/3


def cell_indices(codes):
    digits = np.frombuffer(codes.tobytes(), dtype='u1').reshape(-1, 10).astype('i2')-48
    if np.any((digits < 0) | (digits > 9)) or np.any(digits[:, 4:6] > 7):
        raise ValueError('Invalid 10-digit mesh code')
    rows = digits[:, 4]*100 + digits[:, 6]*10 + digits[:, 8]
    cols = digits[:, 5]*100 + digits[:, 7]*10 + digits[:, 9]
    return rows, cols


def fetch(url, path):
    if not path.exists():
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=60) as response:
                    data = response.read()
                zipfile.ZipFile(io.BytesIO(data)).namelist()
                path.write_bytes(data)
                break
            except Exception:
                if attempt == 3:
                    raise
                time.sleep(attempt+1)


def process(item):
    code, name = item
    year = int(name[6:8])+2000
    url = BASE + f'L03-b-{year%100:02}/' + name
    path = CACHE / name
    fetch(url, path)
    with zipfile.ZipFile(path) as archive:
        stem = next(n[:-4] for n in archive.namelist() if n.endswith('.dbf'))
        raw = archive.read(stem+'.dbf')
        reader = shapefile.Reader(dbf=io.BytesIO(raw), encoding='cp932')
        fields = reader.fields[1:]
        if fields[0][2] != 10 or fields[1][2] not in (1, 2, 4):
            raise ValueError(f'Unexpected DBF layout: {name} {fields}')
        n, header, stride = int.from_bytes(raw[4:8], 'little'), int.from_bytes(raw[8:10], 'little'), int.from_bytes(raw[10:12], 'little')
        classifications = np.ndarray((n,), dtype=f'S{fields[1][2]}', buffer=raw, offset=header+11, strides=(stride,))
        deleted = np.ndarray((n,), dtype='S1', buffer=raw, offset=header, strides=(stride,))
        selected = np.isin(classifications, [b'0700', b'07', b'7']) & (deleted != b'*')
        codes = np.ndarray((n,), dtype='S10', buffer=raw, offset=header+1, strides=(stride,))[selected].copy()
        if any(not c.startswith(code.encode()) for c in codes):
            raise ValueError(f'Mesh outside archive: {name}')
        rows, cols = cell_indices(codes)
        mask = np.zeros((800, 800), dtype='u1')
        mask[799-rows, cols] = 1
        if int(mask.sum()) != len(codes):
            raise ValueError(f'Duplicate building cells: {name}')
        if stem+'.prj' in archive.namelist():
            crs = CRS.from_wkt(archive.read(stem+'.prj').decode())
        else:
            metadata = archive.read(next(n for n in archive.namelist() if n.startswith('KS-META') and n.endswith('.xml'))).decode('cp932')
            if 'JGD2000 / (B, L)' not in metadata:
                raise ValueError(f'Unspecified source datum: {name}')
            crs = CRS.from_epsg(4612)
        if crs.to_epsg() not in (4612, 6668):
            raise ValueError(f'Unexpected CRS: {name} {crs}')
        west, south, east, north = mesh_bounds(code)
        transformer = Transformer.from_crs(crs, 4326, always_xy=True)
        if max(abs(a-b) for a,b in zip(transformer.transform(west, south), (west, south))) > 1e-7:
            raise ValueError('A non-identity datum transform requires raster reprojection')
        # Independently compare mesh-derived coordinates with actual SHP geometry.
        sampled = 0
        if len(codes):
            shapes = shapefile.Reader(shp=io.BytesIO(archive.read(stem+'.shp')), shx=io.BytesIO(archive.read(stem+'.shx')))
            ids = np.flatnonzero(selected)
            for i in np.linspace(0, len(ids)-1, min(3, len(ids)), dtype=int):
                actual = shapes.shape(int(ids[i])).bbox
                expected = (west+cols[i]/800, south+rows[i]/1200, west+(cols[i]+1)/800, south+(rows[i]+1)/1200)
                if max(abs(a-b) for a,b in zip(actual, expected)) > 2e-7:
                    raise ValueError(f'Mesh/SHP mismatch: {name} {actual} {expected}')
                sampled += 1
    image = Image.fromarray(mask).convert('P')
    image.putpalette([0,0,0,255,255,255]+[0]*762)
    image.save(OUT / f'{code}.png', bits=1, transparency=0, optimize=True)
    return dict(id=code, west=west, south=south, east=east, north=north, year=year,
                cells=len(codes), records=n, source=url, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                crs=crs.to_string(), verifiedShapeSamples=sampled)


def main():
    OUT.mkdir(exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(SPEC, timeout=60) as response:
        index = response.read().decode()
    (CACHE / 'source-index.html').write_text(index)
    names = set(re.findall(r'L03-b-\d{2}_\d{4}-jgd(?:2011)?_GML.zip', index))
    selected = {}
    for name in sorted(names):
        year, code = re.match(r'L03-b-(\d{2})_(\d{4})', name).groups()
        if code not in selected or int(year) > int(selected[code][6:8]):
            selected[code] = name
    if len(selected) < 175:
        raise ValueError('Incomplete national archive list')
    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for i, record in enumerate(pool.map(process, sorted(selected.items())), 1):
            records.append(record)
            if i % 10 == 0:
                print(f'{i}/{len(selected)} archives, {sum(r["cells"] for r in records):,} building cells', flush=True)
    atlas = json.loads((DATA / 'japan.json').read_text())
    prefectures = {}
    for prefecture in atlas['prefectures']:
        boundary = unary_union([Polygon(p[0], p[1:]).buffer(0) for p in prefecture['polygons']])
        prefectures[prefecture['id']] = [r['id'] for r in records if r['cells'] and boundary.intersects(box(r['west'],r['south'],r['east'],r['north']))]
    assert len(prefectures) == 47 and all(prefectures.values())
    metadata = dict(source='国土交通省 国土数値情報 土地利用細分メッシュ', specification=SPEC,
                    license='https://nlftp.mlit.go.jp/ksj/other/agreement.html',
                    retrievedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    classification='建物用地', classificationCodes=['0700','07','7'], meshSizeMetresApprox=100,
                    processing='メッシュごとに公開済みの最新年次を採用。建物用地のみを抽出し透過マスク化。描画時に県境で切り抜く。DIDではない。奈良の県表示は従来のベクターデータを維持。',
                    indexSha256=hashlib.sha256(index.encode()).hexdigest(), tiles=records, prefectures=prefectures)
    (OUT / 'index.json').write_text(json.dumps(metadata, ensure_ascii=False, separators=(',', ':'))+'\n')
    # National overview: preserve coverage with area averaging, so small building
    # cells do not become whole urban pixels when the map is reduced.
    west, south, east, north = 122., 20., 154.5, 46.
    width, height = 4096, 3277
    overview = Image.new('RGBA', (width,height))
    for r in records:
        if not r['cells']:
            continue
        left, right = round((r['west']-west)/(east-west)*width), round((r['east']-west)/(east-west)*width)
        top, bottom = round((north-r['north'])/(north-south)*height), round((north-r['south'])/(north-south)*height)
        with Image.open(OUT / f"{r['id']}.png") as image:
            patch = image.convert('RGBA').resize((right-left,bottom-top), Image.Resampling.BOX)
            overview.alpha_composite(patch,(left,top))
    overview.save(OUT / 'national.png', optimize=True)
    (OUT / 'national.json').write_text(json.dumps(dict(west=west,south=south,east=east,north=north,width=width,height=height),separators=(',', ':'))+'\n')
    print(f'Generated {len(records)} masks for 47 prefectures, {sum(r["cells"] for r in records):,} building cells',flush=True)


if __name__ == '__main__':
    main()
