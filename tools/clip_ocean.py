"""Clip display geometry to 2020 N03 coastal land, preserving all gameplay data.

N03 originals are cached under data/raw/coastline. No network at runtime or here.
Only geometry is changed; IDs, population, graph, source-to-town mapping and saves
remain untouched. Nara and other inland prefectures are byte-for-byte retained.
"""
import concurrent.futures
import hashlib
import datetime
import time
import urllib.request
import json
from pathlib import Path
import zipfile
from shapely.geometry import shape, Polygon, MultiPolygon, box, Point
from shapely.ops import unary_union
from shapely import make_valid, prepare, to_wkb, from_wkb, set_precision

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT/'assets/data'
CACHE = ROOT/'data/raw/coastline'
INLAND = {'09','10','11','19','20','21','25','29'}


def read(path): return json.loads(path.read_text())


def components(geom):
    if geom.geom_type == 'Polygon':
        if not geom.is_empty: yield geom
    elif hasattr(geom,'geoms'):
        for part in geom.geoms: yield from components(part)


def from_polygons(rows):
    return unary_union([make_valid(Polygon(p[0],p[1:])) for p in rows if p and len(p[0])>=3])


def polygons(geom):
    return [[[[round(x,6),round(y,6)] for x,y in ring.coords]
             for ring in [p.exterior,*p.interiors]]
            for p in components(set_precision(geom,1e-6)) if p.area > 1e-12]


def download_sources():
    CACHE.mkdir(parents=True,exist_ok=True)
    def fetch(pid):
        path=CACHE/f'N03-20200101_{pid}_GML.zip'
        if not path.exists():
            url='https://nlftp.mlit.go.jp/ksj/gml/data/N03/N03-2020/'+path.name
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(url,timeout=90) as response:
                        raw=response.read()
                    import io
                    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                        assert any(n.endswith('.geojson') for n in archive.namelist())
                    path.write_bytes(raw)
                    break
                except Exception:
                    if attempt==2:raise
                    time.sleep(2)
        return pid
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for pid in pool.map(fetch,[f'{i:02d}' for i in range(1,48)]):
            print('N03 source',pid,flush=True)


def prepare_prefecture(pid):
    path=CACHE/f'N03-20200101_{pid}_GML.zip'
    dest=CACHE/f'{pid}.wkb'
    with zipfile.ZipFile(path) as z:
        source=next(n for n in z.namelist() if n.endswith('.geojson'))
        data=json.loads(z.read(source))
    result=unary_union([make_valid(shape(f['geometry'])) for f in data['features'] if f['geometry']])
    dest.write_bytes(to_wkb(result))
    return pid,hashlib.sha256(path.read_bytes()).hexdigest()


def prepare_land():
    hashes={}
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        for pid,digest in pool.map(prepare_prefecture,[f'{i:02d}' for i in range(1,48)]):
            hashes[pid]=digest
            print('Prepared N03',pid,flush=True)
    land=unary_union([from_wkb((CACHE/f'{i:02d}.wkb').read_bytes()) for i in range(1,48)])
    # Administrative N03 polygons contain internal lake jurisdictions too.
    assert land.covers(Point(136.05,35.25)), 'Lake Biwa must remain in administrative regions'
    assert land.covers(Point(139.6917,35.6896)), 'Tokyo land missing'
    assert not land.covers(Point(136.8,34.8)), 'Ise Bay must be ocean'
    (CACHE/'land.wkb').write_bytes(to_wkb(land))
    (CACHE/'sources.json').write_text(json.dumps(hashes,separators=(',',':')))
    print('Global land/coastal mask ready',flush=True)
    prepare_display_land()


def prepare_display_land():
    land=from_wkb((CACHE/'land.wkb').read_bytes())
    # ~5 m is finer than the census display geometry and image pixels. Preserve
    # topology so small islands and marine holes do not disappear.
    islands=list(components(land))
    # GEOS releases the GIL. Independent island simplification avoids a giant
    # global topology index; the final union resolves any sub-tolerance contacts.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        simplified=list(pool.map(lambda p:p.simplify(.00005,preserve_topology=True),islands))
    land=unary_union(simplified)
    (CACHE/'land_display.wkb').write_bytes(to_wkb(land))
    print('Display coastal mask ready',flush=True)


def clip_prefecture(pid):
    path=DATA/f'prefectures/{pid}.json'
    data=read(path)
    original=from_polygons(data['polygons'])
    land=from_wkb((CACHE/'land_display.wkb').read_bytes())
    # Retain neighboring prefectures' land across administrative rounding seams.
    land=land.intersection(box(*original.envelope.buffer(.01).bounds))
    prepare(land)
    counts=dict(changedTowns=0,emptyTowns=[],removedTownSquareDegrees=0)
    def clipped(rows,record_area=False):
        geom=from_polygons(rows)
        if geom.is_empty or land.covers(geom): return rows,False
        cut=geom.intersection(land)
        if record_area:counts['removedTownSquareDegrees']+=max(0,geom.area-cut.area)
        return polygons(cut),True
    for row in data['towns']:
        row['polygons'],changed=clipped(row['polygons'],record_area=True)
        if changed:counts['changedTowns']+=1
        if not row['polygons']:counts['emptyTowns'].append(row['id'])
    for row in data['cities']:
        row['polygons'],_=clipped(row['polygons'])
    outline,_=clipped(data['polygons'])
    # Coarse census prefecture outlines may miss tiny islands that are retained
    # in their cities. Parent outlines must include all clipped child land.
    data['polygons']=polygons(unary_union([from_polygons(outline),*[from_polygons(c['polygons']) for c in data['cities']]]))
    target=CACHE/'clipped'/f'{pid}.json'
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
    counts['bytes']=target.stat().st_size
    return pid,counts


def generate():
    baseline=read(DATA/'japan.json')
    metadata={k:v for k,v in baseline.items() if k!='prefectures'}
    land=from_wkb((CACHE/'land_display.wkb').read_bytes());prepare(land)
    results={}
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        for pid,counts in pool.map(clip_prefecture,[f'{i:02d}' for i in range(1,48) if f'{i:02d}' not in INLAND]):
            results[pid]=counts
            print(pid,counts['changedTowns'],'changed;',len(counts['emptyTowns']),'empty',flush=True)
    for pref in baseline['prefectures']:
        if pref['id'] in INLAND:continue
        # Use the repaired county outline including its offshore child land.
        child=read(CACHE/'clipped'/f"{pref['id']}.json")['polygons']
        pref['polygons']=polygons(from_polygons(child).simplify(.00015,preserve_topology=True))
    target=CACHE/'clipped/japan.json'
    target.write_text(json.dumps(baseline,ensure_ascii=False,separators=(',',':'))+'\n')
    assert {k:v for k,v in baseline.items() if k!='prefectures'}==metadata
    populations={t['id']:t['population'] for t in baseline['towns']}
    empty=[dict(id=town,population=populations[town]) for stats in results.values() for town in stats['emptyTowns']]
    report=dict(source='国土交通省 国土数値情報 行政区域データ 2020年',
                url='https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N03-v3_1.html',
                license='https://nlftp.mlit.go.jp/ksj/other/agreement.html',
                coastDate='2020-01-01',displayToleranceDegrees=.00005,nationalDisplayToleranceDegrees=.00015,processedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),sources=read(CACHE/'sources.json'),prefectures=results,
                emptyGeometryRecords=empty,
                processing='全国の行政区域を結合した海岸線で海を除く。内水面は維持。ID・人口・隣接・進捗・奈良原本は変更しない。')
    (CACHE/'clip_report.json').write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
    print('Geometry generated; empty populated records:',[x for x in empty if x['population']],flush=True)


def filter_coastal_labels():
    land=from_wkb((CACHE/'land_display.wkb').read_bytes());prepare(land)
    removed={}
    for i in range(1,48):
        pid=f'{i:02d}'
        if pid in INLAND:continue
        path=DATA/f'map_labels/{pid}.json';data=read(path)
        before=len(data['labels'])
        data['labels']=[p for p in data['labels'] if land.covers(Point(p['point']))]
        removed[pid]=before-len(data['labels'])
        path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')))
    return removed


def apply_generated():
    import shutil
    candidate=CACHE/'clipped'
    old=read(DATA/'japan.json');new=read(candidate/'japan.json')
    assert {k:v for k,v in old.items() if k!='prefectures'}=={k:v for k,v in new.items() if k!='prefectures'}, 'Gameplay metadata changed'
    report=read(CACHE/'clip_report.json')
    assert not report['emptyGeometryRecords'], 'A town would lose all geometry'
    for path in sorted(candidate.glob('*.json')):
        if path.name=='japan.json':continue
        before=read(DATA/'prefectures'/path.name);after=read(path)
        for kind in ['towns','cities']:
            assert len(before[kind])==len(after[kind])
            for a,b in zip(before[kind],after[kind]):
                assert {k:v for k,v in a.items() if k!='polygons'}=={k:v for k,v in b.items() if k!='polygons'}, (path.name,a['id'])
        assert after['polygons']
    report['unchangedInlandSha256']={pid:hashlib.sha256((DATA/f'prefectures/{pid}.json').read_bytes()).hexdigest() for pid in INLAND if (DATA/f'prefectures/{pid}.json').exists()}
    report['unchangedNaraSha256']=hashlib.sha256((DATA/'nara.json').read_bytes()).hexdigest()
    report['population']=sum(t['population'] for t in old['towns'])+sum(t['population'] for t in read(DATA/'nara.json')['towns'])
    report['sourceTownRecords']=len(old['towns'])+len(read(DATA/'nara.json')['towns'])
    for path in candidate.glob('*.json'):
        shutil.copy2(path,DATA/('japan.json' if path.name=='japan.json' else 'prefectures/'+path.name))
    report['removedMarineLabels']=filter_coastal_labels()
    (DATA/'coastline_import_report.json').write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
    print('Applied geometry only; IDs, population, graph, area, Nara and saves unchanged:',report['population'],flush=True)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true')
    parser.add_argument('--download',action='store_true')
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    if args.apply:apply_generated()
    elif args.download:download_sources()
    elif args.prepare:prepare_land()
    else:generate()
