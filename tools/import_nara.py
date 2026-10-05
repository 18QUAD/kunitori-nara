"""Rebuild offline Nara assets from CODH's CC BY 4.0 2020 census topology.

Network downloads use curl; no API key or Python dependencies required.
Adjacency is computed BEFORE display simplification, from shared boundary
segments (six decimal degrees). Point-only contact is not adjacency.
"""
import collections
import concurrent.futures
import json
import math
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'data' / 'raw'
OUT = ROOT / 'assets' / 'data'
CODES = '29201 29202 29203 29204 29205 29206 29207 29208 29209 29210 29211 29212 29322 29342 29343 29344 29345 29361 29362 29363 29385 29386 29401 29402 29424 29425 29426 29427 29441 29442 29443 29444 29446 29447 29449 29450 29451 29452 29453'.split()

def download(code):
    target = CACHE / f'{code}.json'
    if not target.exists():
        subprocess.run(['curl.exe', '-sS', '-L', '--fail', '--retry', '2',
            f'https://geoshape.ex.nii.ac.jp/ka/topojson/2020/29/r2ka{code}.topojson',
            '-o', str(target)], check=True)
    return json.loads(target.read_text(encoding='utf-8'))

def simplify(points, epsilon=0.00004):
    if len(points) < 4:
        return points
    a, b = points[0], points[-1]
    dx, dy = b[0]-a[0], b[1]-a[1]
    denom = dx*dx + dy*dy
    def distance(p):
        t = max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/denom)) if denom else 0
        return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
    i = max(range(1,len(points)-1), key=lambda n: distance(points[n]))
    if distance(points[i]) > epsilon:
        return simplify(points[:i+1],epsilon)[:-1]+simplify(points[i:],epsilon)
    return [a,b]

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    towns = {}
    segments = collections.defaultdict(set)
    cities = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        datasets = list(pool.map(download, CODES))
    for code, data in zip(CODES, datasets):
        arcs = data['arcs']
        transform = data.get('transform')
        if transform:
            decoded = []
            for arc in arcs:
                x=y=0; pts=[]
                for dx,dy in arc:
                    x+=dx; y+=dy
                    pts.append([x*transform['scale'][0]+transform['translate'][0],y*transform['scale'][1]+transform['translate'][1]])
                decoded.append(pts)
            arcs=decoded
        city_name = None
        for geo in data['objects']['town']['geometries']:
            p = geo['properties']
            key = p['KEY_CODE']
            city_name = p['CITY_NAME']
            if key not in towns:
                towns[key] = dict(id=key, name=p['S_NAME'] or '名称未設定', cityId=code,
                    population=0, area=0, center=[p['X_CODE'],p['Y_CODE']], polygons=[], neighbors=[])
            town=towns[key]
            # Duplicate/fragment records have their own census totals, summed by KEY_CODE.
            town['population'] += max(0, int(p.get('JINKO') or 0))
            town['area'] += float(p.get('AREA') or 0)
            polygons = [geo['arcs']] if geo['type']=='Polygon' else geo['arcs']
            for polygon in polygons:
                rings=[]
                for ring in polygon:
                    pts=[]
                    for index in ring:
                        arc=arcs[index] if index>=0 else list(reversed(arcs[~index]))
                        pts.extend(arc if not pts else arc[1:])
                    rounded=[tuple(round(v,6) for v in pt[:2]) for pt in pts]
                    for a,b in zip(rounded,rounded[1:]):
                        if a != b:
                            segments[tuple(sorted((a,b)))].add(key)
                    simple=simplify(rounded)
                    if len(simple)<4:
                        simple=rounded
                    rings.append(simple)
                town['polygons'].append(rings)
        cities.append(dict(id=code,name=city_name))
    adjacency={k:set() for k in towns}
    for owners in segments.values():
        if len(owners)>1:
            for a in owners:
                adjacency[a].update(owners-{a})
    for key,t in towns.items():
        t['neighbors']=sorted(adjacency[key])
        t['area']=round(t['area']/1e6,6)
    unseen=set(towns); components=[]
    while unseen:
        pending=[unseen.pop()]; comp=[]
        while pending:
            key=pending.pop(); comp.append(key)
            for n in adjacency[key]&unseen:
                unseen.remove(n); pending.append(n)
        components.append(comp)
    components.sort(key=len,reverse=True)
    payload=dict(version=1,prefecture='奈良県',censusYear=2020,cities=cities,towns=list(towns.values()),
        source='https://geoshape.ex.nii.ac.jp/ka/',license='CC BY 4.0',
        attribution='国勢調査町丁・字等別境界データセット（CODH作成）。令和2年国勢調査町丁・字等別境界データ（e-Stat）を加工。doi:10.20676/00000450',
        processing='同一KEY_CODEの領域を統合。描画境界を簡略化。隣接は元境界の共通線分から算出。',
        components=[len(c) for c in components])
    (OUT/'nara.json').write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    report=dict(cities=len(cities),towns=len(towns),population=sum(t['population'] for t in towns.values()),
        components=[len(c) for c in components],isolated=[c for c in components if len(c)<3])
    (OUT/'import_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report))

if __name__=='__main__':
    main()
