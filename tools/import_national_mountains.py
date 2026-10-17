"""Extract prefecture-local mountain annotations from cached GSI z11 tiles.

Run after import_national_water.py with mapbox-vector-tile and shapely installed.
Uses the same annotation class and zoom as Nara; preserves the Nara asset.
Positions are cartographic annotations, never inferred summit coordinates.
"""
import hashlib
import json
import re
import urllib.request

import mapbox_vector_tile
from mapbox_vector_tile.Mapbox import vector_tile_pb2
from shapely import STRtree, make_valid
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union

from import_national_water import CACHE, DATA, SOURCE, SPEC, ZOOM, coordinate

SUMMIT_SOURCE = 'https://maps.gsi.go.jp/overlay/mount1003/mount1003.geojson'


def extract(raw):
    tile = vector_tile_pb2.tile()
    tile.ParseFromString(raw)
    filtered = vector_tile_pb2.tile()
    for layer in tile.layers:
        if layer.name != 'label':
            continue
        target = filtered.layers.add()
        target.CopyFrom(layer)
        target.ClearField('features')
        for feature in layer.features:
            props = {
                layer.keys[feature.tags[i]]: layer.values[feature.tags[i + 1]]
                for i in range(0, len(feature.tags), 2)
            }
            category = props.get('annoCtg')
            if category is not None and category.int_value == 312:
                target.features.add().CopyFrom(feature)
    layer = mapbox_vector_tile.decode(
        filtered.SerializeToString(), default_options={'y_coord_down': True}
    ).get('label', {'features': [], 'extent': 4096})
    return layer


def main():
    summit_file = DATA.parents[1] / 'data/raw/national_mountains/mount1003.geojson'
    if not summit_file.exists():
        summit_file.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(SUMMIT_SOURCE, timeout=60) as response:
            summit_file.write_bytes(response.read())
    summit_raw = summit_file.read_bytes()
    major_names = set()
    for feature in json.loads(summit_raw)['features']:
        for key in ['山名', '山頂名']:
            value = feature['properties'].get(key, '')
            major_names.update(name for name in re.split(r'[（）()〈〉]+', value) if name)
    prefectures = json.loads((DATA / 'japan.json').read_text())['prefectures']
    shapes = [
        unary_union([make_valid(Polygon(p[0], p[1:])) for p in pref['polygons']])
        for pref in prefectures
    ]
    tree = STRtree(shapes)
    output = {p['id']: {} for p in prefectures}
    water = json.loads((DATA / 'water/index.json').read_text())
    for index, record in enumerate(water['tiles'], 1):
        if record['missing']:
            continue
        x, y = record['x'], record['y']
        raw = (CACHE / f'{ZOOM}_{x}_{y}.pbf').read_bytes()
        assert hashlib.sha256(raw).hexdigest() == record['sha256']
        layer = extract(raw)
        for feature in layer['features']:
            name = feature['properties'].get('annoChar', '')
            if not name or feature['geometry']['type'] != 'Point':
                continue
            px, py = feature['geometry']['coordinates']
            lon, lat = coordinate(x + px / layer['extent'], y + py / layer['extent'])
            point = Point(lon, lat)
            rounded = [round(lon, 6), round(lat, 6)]
            for hit in tree.query(point, predicate='intersects'):
                pref = prefectures[int(hit)]['id']
                output[pref][(name, *rounded)] = dict(name=name, point=rounded)
        if index % 500 == 0:
            print(f'{index}/{len(water["tiles"])} tiles', flush=True)
    folder = DATA / 'mountains'
    folder.mkdir(exist_ok=True)
    counts = {}
    for pref, labels in output.items():
        if pref == '29':
            # Keep the original Nara annotations and legacy summit metadata.
            counts[pref] = len(json.loads((DATA / 'nara_mountains.json').read_text())['labels'])
            continue
        values = [labels[key] for key in sorted(labels)]
        assert values, f'No mountain annotations for {pref}'
        for label in values:
            label['overview'] = label['name'] in major_names
        if not any(label['overview'] for label in values):
            values[0]['overview'] = True
        document = dict(labels=values)
        (folder / f'{pref}.json').write_text(
            json.dumps(document, ensure_ascii=False, separators=(',', ':')) + '\n'
        )
        counts[pref] = len(values)
    metadata = dict(
        source=SOURCE, specification=SPEC, zoom=ZOOM,
        attribution='国土地理院ベクトルタイル提供実験を加工して作成',
        tiles=water['tiles'], prefectures=counts,
        overviewSource=SUMMIT_SOURCE,
        overviewSha256=hashlib.sha256(summit_raw).hexdigest(),
        processing='山名注記(annoCtg=312)の元座標を県境内で抽出し重複を除去。'
                   '経緯度小数6桁に丸め。山頂座標ではない。奈良県の既存データは変更しない。'
                   '県全体では国土地理院「日本の主な山岳」と同名の注記を優先。該当なしの場合は先頭の注記を使用。',
    )
    (folder / 'index.json').write_text(
        json.dumps(metadata, ensure_ascii=False, separators=(',', ':')) + '\n'
    )
    print(f'47 prefectures, {sum(counts.values()):,} mountain names', flush=True)


if __name__ == '__main__':
    main()
