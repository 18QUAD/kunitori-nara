"""Extract real surface rivers, lakes and names for every Japanese prefecture.

Requires mapbox-vector-tile, shapely, numpy. GSI z11 PBFs are cached. Unrelated
vector layers are removed before geometry decoding. Nara's original assets stay
unchanged. Output is clipped to source tile and prefecture, preserving lake holes.
"""
import concurrent.futures
import datetime
import hashlib
import json
import math
from pathlib import Path
import time
import urllib.error
import urllib.request

import mapbox_vector_tile
from mapbox_vector_tile.Mapbox import vector_tile_pb2
import numpy as np
from shapely.geometry import Polygon, box, shape, mapping
from shapely.ops import unary_union, transform
from shapely import make_valid, set_precision
from import_water import components, rounded

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'assets/data'
OUT = DATA / 'water'
CACHE = ROOT / 'data/raw/national_water'
ZOOM = 11
SOURCE = 'https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf'
SPEC = 'https://raw.githubusercontent.com/gsi-cyberjapan/gsimaps-vector-experiment/master/README.md'
PREFECTURES = {}
ASSIGNMENTS = {}


def coordinate(x, y):
    return x / 2**ZOOM * 360 - 180, math.degrees(math.atan(math.sinh(math.pi*(1-2*y/2**ZOOM))))


def tile_index(lon, lat):
    return int((lon+180)/360*2**ZOOM), int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**ZOOM)


def tile_box(x, y):
    west, south = coordinate(x, y+1)
    east, north = coordinate(x+1, y)
    return box(west, south, east, north)


def selected_layers(data):
    tile = vector_tile_pb2.tile()
    tile.ParseFromString(data)
    filtered = vector_tile_pb2.tile()
    for layer in tile.layers:
        if layer.name in ['river', 'waterarea', 'label']:
            filtered.layers.add().CopyFrom(layer)
    return mapbox_vector_tile.decode(filtered.SerializeToString(), default_options={'y_coord_down': True})


def feature_allowed(layer, props):
    if layer == 'river':
        return props.get('ftCode') in [5301, 5321]
    if layer == 'waterarea':
        return props.get('ftCode') == 5000
    return layer == 'label' and props.get('annoCtg') in [321, 322, 820] and bool(props.get('annoChar'))


def process(pair):
    x, y = pair
    path = CACHE / f'{ZOOM}_{x}_{y}.pbf'
    missing = False
    if not path.exists():
        for attempt in range(4):
            try:
                with urllib.request.urlopen(SOURCE.format(z=ZOOM,x=x,y=y), timeout=45) as response:
                    raw = response.read()
                tile = vector_tile_pb2.tile()
                tile.ParseFromString(raw)
                path.write_bytes(raw)
                break
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    missing = True
                    break
                if attempt == 3:
                    raise
                time.sleep(attempt+1)
    bounds = tile_box(x, y)
    clips = {p: PREFECTURES[p].intersection(bounds) for p in ASSIGNMENTS[pair]}
    output = {p:dict(lines=[], areas=[], labels=[]) for p in clips}
    if missing:
        return dict(x=x,y=y,missing=True), output
    raw = path.read_bytes()
    layers = selected_layers(raw)
    for name, layer in layers.items():
        extent = layer['extent']
        def project(xs, ys, zs=None):
            xs, ys = np.asarray(xs), np.asarray(ys)
            return (x+xs/extent)/2**ZOOM*360-180, np.degrees(np.arctan(np.sinh(math.pi*(1-2*(y+ys/extent)/2**ZOOM))))
        for feature in layer['features']:
            props = feature['properties']
            if not feature_allowed(name, props):
                continue
            geom = transform(project, shape(feature['geometry']))
            if not geom.is_valid:
                geom = make_valid(geom)
            if not geom.intersects(bounds):
                continue
            geom = geom.intersection(bounds)
            for p, clip in clips.items():
                if clip.is_empty or not geom.intersects(clip):
                    continue
                cut = geom.intersection(clip)
                if name == 'label':
                    if cut.geom_type == 'Point' and not cut.is_empty:
                        output[p]['labels'].append(dict(name=props['annoChar'], point=rounded([cut.x,cut.y])))
                else:
                    kind = 'LineString' if name == 'river' else 'Polygon'
                    for part in components(cut, kind):
                        if part.length == 0:
                            continue
                        output[p]['lines' if name=='river' else 'areas'].append(rounded(mapping(part)['coordinates']))
    return dict(x=x,y=y,missing=False,sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw)), output


def normalize_areas(data):
    """Snap rounding may collapse sub-metre slivers at clipped tile boundaries."""
    areas = []
    repaired = 0
    for coords in data['areas']:
        polygon = Polygon(coords[0], coords[1:])
        if not polygon.is_valid:
            repaired += 1
        snapped = set_precision(make_valid(polygon), 1e-6)
        for part in components(snapped, 'Polygon'):
            if part.area > 0:
                areas.append(rounded(mapping(part)['coordinates']))
    data['areas'] = areas
    return repaired


def national_overview(prefectures):
    lines, areas, labels = [], [], []
    seen = set()
    for data in prefectures.values():
        for coords in data['lines']:
            line = shape(dict(type='LineString',coordinates=coords))
            if line.length >= .025:
                line = line.simplify(.0003)
                lines.append(rounded(mapping(line)['coordinates']))
        for coords in data['areas']:
            polygon = Polygon(coords[0],coords[1:])
            if polygon.area >= .00002:
                polygon = polygon.simplify(.0003, preserve_topology=True)
                for part in components(polygon,'Polygon'):
                    areas.append(rounded(mapping(part)['coordinates']))
        for label in data['labels']:
            key = (label['name'], *label['point'])
            if key not in seen:
                labels.append(label)
                seen.add(key)
    return dict(lines=lines,areas=areas,labels=labels)


def main():
    OUT.mkdir(exist_ok=True)
    CACHE.mkdir(parents=True,exist_ok=True)
    atlas = json.loads((DATA/'japan.json').read_text())
    for pref in atlas['prefectures']:
        county = unary_union([make_valid(Polygon(p[0],p[1:])) for p in pref['polygons']])
        PREFECTURES[pref['id']] = county
        pairs = set()
        for poly in components(county, 'Polygon'):
            west,south,east,north = poly.bounds
            x0,y0=tile_index(west,north)
            x1,y1=tile_index(east,south)
            for x in range(x0,x1+1):
                for y in range(y0,y1+1):
                    if poly.intersects(tile_box(x,y)):
                        pairs.add((x,y))
        for pair in pairs:
            ASSIGNMENTS.setdefault(pair,[]).append(pref['id'])
    with urllib.request.urlopen(SPEC, timeout=30) as response:
        specification=response.read().decode()
    (CACHE/'specification.md').write_text(specification)
    output={p:dict(lines=[],areas=[],labels=[]) for p in PREFECTURES}
    records=[]
    print(f'Downloading {len(ASSIGNMENTS)} tiles for 47 prefectures',flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for i,(record,parts) in enumerate(pool.map(process,sorted(ASSIGNMENTS)),1):
            records.append(record)
            for p,data in parts.items():
                for name in ['lines','areas','labels']:
                    output[p][name].extend(data[name])
            if i%100==0:
                print(f'{i}/{len(ASSIGNMENTS)} tiles',flush=True)
    counts={p:dict(riverParts=len(d['lines']),waterPolygons=len(d['areas']),names=len(d['labels'])) for p,d in output.items()}
    if len(counts)!=47 or any(c['riverParts']+c['waterPolygons']==0 for c in counts.values()):
        raise ValueError('A prefecture has no surface-water features')
    metadata=dict(source=SOURCE,specification=SPEC,attribution='国土地理院ベクトルタイル提供実験を加工して作成',
                  retrieved=datetime.datetime.now(datetime.timezone.utc).isoformat(),zoom=ZOOM,
                  specificationSha256=hashlib.sha256(specification.encode()).hexdigest(),tiles=records,prefectures=counts,
                  processing='地表の河川・人工水路(5301/5321)、水域(5000)、水辺の注記(321/322/820)を抽出。地下水路・枯れ川を除外。タイル境界と県境で切り出し、湖の穴を維持。経緯度小数6桁に丸め。奈良の従来データは変更しない。')
    overview=national_overview(output)
    repairs={}
    for p,data in output.items():
        if p=='29':
            continue
        repairs[p]=normalize_areas(data)
        counts[p]['waterPolygons']=len(data['areas'])
        (OUT/f'{p}.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
    repairs['national']=normalize_areas(overview)
    metadata['repairedRoundedPolygons']=repairs
    metadata['processing']+=' 1e-6度のスナップ丸めでタイル端の微小な無効形状を修復。'
    (OUT/'national.json').write_text(json.dumps(overview,ensure_ascii=False,separators=(',',':'))+'\n')
    metadata['national']=dict(riverParts=len(overview['lines']),waterPolygons=len(overview['areas']),names=len(overview['labels']),processing='約2.5km以上の河川区間、約0.2km²以上の水域を残し、約30mで簡略化。県・市町村版は元の詳細を維持。')
    (OUT/'index.json').write_text(json.dumps(metadata,ensure_ascii=False,separators=(',',':'))+'\n')
    print(f'Generated water for 47 prefectures; {sum(c["riverParts"] for c in counts.values()):,} river parts, {sum(c["waterPolygons"] for c in counts.values()):,} polygons',flush=True)


if __name__=='__main__':
    main()
