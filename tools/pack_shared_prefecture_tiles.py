"""Replace only national border images after prefecture_border_mesh.py."""
import concurrent.futures
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import build_border_tiles as bake
import contrast_border_tiles as style
from prefecture_border_mesh import WORK


def pack(item):
    bake.OUT = WORK/'packed'
    return bake.merge_tile(item)


def initialize(keys):
    style.initialize(keys)


def main():
    grouped=defaultdict(list)
    for path in (WORK/'tiles').glob('*_pref.webp'):
        level,x,y,_=path.stem.split('_')
        grouped[f'{int(level)-1}_{int(x)//2}_{int(y)//2}_pref.webp'].append(path)
    packed=WORK/'packed';packed.mkdir(exist_ok=True)
    for old in packed.glob('*.webp'):old.unlink()
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        list(pool.map(pack,sorted(grouped.items()),chunksize=32))
    source=style.SOURCE
    old=json.loads((source/'index.json').read_text())
    for path in source.glob('*_pref.webp'):path.unlink()
    import shutil
    for path in packed.glob('*.webp'):shutil.copyfile(path,source/path.name)
    old['tiles']={k:v for k,v in old['tiles'].items() if not k.endswith('_pref')}
    old['tiles'].update({p.stem:p.stat().st_size for p in packed.glob('*.webp')})
    report=dict(algorithm='one detailed shared network; lower prefecture ID owns shared arcs',
        toleranceDegrees=0.0002, simplificationDegrees=0.00004,
        networkSha256=hashlib.sha256((WORK/'network.wkb').read_bytes()).hexdigest(),
        sourceSha256={p.stem:p.read_text() for p in sorted(WORK.glob('??.sha256'))})
    old['sharedPrefectureMesh']=report
    (source/'index.json').write_text(json.dumps(old,ensure_ascii=False,separators=(',',':')))
    index=style.OUT/'index-plain.json'
    if not index.exists():index=style.OUT/'index-shared.json'
    data=json.loads(index.read_text())
    for path in style.OUT.glob('*_pref.webp'):path.unlink()
    data['tiles']={k:v for k,v in data['tiles'].items() if not k.endswith('_pref')}
    keys=[p.stem for p in packed.glob('*.webp')]
    jobs=style.candidates(keys)
    with concurrent.futures.ProcessPoolExecutor(max_workers=8,initializer=initialize,initargs=(keys,)) as pool:
        for done,result in enumerate(pool.map(style.render,jobs,chunksize=32),1):
            if result:data['tiles'][result[0]]=result[1]
            if done%2000==0:print('Styled shared tiles',done,'/',len(jobs),flush=True)
    data.update(layerFilenamePrefixes={'pref':'shared_'},sharedPrefectureMesh=report,
        sourceIndexSha256=hashlib.sha256((source/'index.json').read_bytes()).hexdigest())
    data['processing']+=' 県境は詳細な市区町村形状から全国共通の共有線網を生成し一度だけ描画。'
    (style.OUT/'index-shared.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')))
    (style.OUT/'index-plain.json').unlink(missing_ok=True)
    print('PASS shared pack:',len(keys),'source cells;',len(data['tiles']),'total cells',flush=True)


if __name__=='__main__':main()
