"""Reduce download bytes without changing tile resolution or geometry.

Q50 WebPs preserve native water edges and keep the bundle inside the Pages limit.
The renderer writes delivery images directly. A marker and source/delivery hashes
also allow older master images to be upgraded once without repeated lossy encodes.
"""
import concurrent.futures
import hashlib
import io
import os
from pathlib import Path
import sqlite3
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
DELIVERY_MARKER = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><prepared>kunitori-q50-v1</prepared></x:xmpmeta>'


def encode(item):
    path, previous = item
    source=path.read_bytes()
    digest=hashlib.sha256(source).hexdigest()
    if digest==previous: return path.name,digest,False
    with Image.open(io.BytesIO(source)) as im:
        if im.info.get('xmp') == DELIVERY_MARKER:
            return path.name,digest,False
        output=io.BytesIO()
        im.save(output,format='WEBP',quality=50,method=4,exact=True,xmp=DELIVERY_MARKER)
    data=output.getvalue()
    temp=path.with_suffix('.delivery.tmp')
    temp.write_bytes(data);os.replace(temp,path)
    return path.name,hashlib.sha256(data).hexdigest(),True


def optimize(workers=3, levels=None):
    cache=ROOT/'data/raw/delivery-images.sqlite'
    cache.parent.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(cache) as db:
        db.execute('CREATE TABLE IF NOT EXISTS images (name TEXT PRIMARY KEY, sha256 TEXT)')
        previous=dict(db.execute('SELECT name,sha256 FROM images'))
        paths=[p for p in (ROOT/'assets/data/map_images').glob('*.webp')
               if p.stem.split('_')[-1] in ('background','overview')
               and (levels is None or (p.stem.split('_')[-1],int(p.stem.split('_')[0])) in levels)]
        changed=0
        with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as pool:
            for count,(name,digest,updated) in enumerate(pool.map(encode,[(p,previous.get(p.name)) for p in paths],chunksize=16),1):
                if updated:
                    changed+=1
                if digest != previous.get(name):
                    db.execute('INSERT OR REPLACE INTO images VALUES (?,?)',(name,digest))
                if count%256==0:db.commit()
            db.commit()
        print('Delivery images',len(paths),'checked,',changed,'encoded',flush=True)


if __name__=='__main__':optimize()
