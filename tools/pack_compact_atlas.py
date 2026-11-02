import json,struct
from pathlib import Path
r=Path('assets/data/compact');d=json.loads((r/'index.json').read_text());rows=d.pop('towns');positions={row[0]:i for i,row in enumerate(rows)};rows=[[row[0],row[1],row[3],row[4],[positions[n] for n in row[5]]] for row in rows];parts=[]
for start in range(0,len(rows),20000):
 name=f'towns-{start//20000}.json';(r/name).write_text(json.dumps(rows[start:start+20000],ensure_ascii=False,separators=(',',':')));parts.append(name)
d['townFiles']=parts
b=bytearray()
for p in d['prefectures']:
 polygons=p.pop('polygons');b+=struct.pack('<I',len(polygons))
 for polygon in polygons:
  b+=struct.pack('<I',len(polygon))
  for ring in polygon:
   b+=struct.pack('<I',len(ring))
   for x,y in ring:b+=struct.pack('<dd',x,y)
(r/'coast.bin').write_bytes(b);(r/'index.json').write_text(json.dumps(d,ensure_ascii=False,separators=(',',':')))
print('index', (r/'index.json').stat().st_size,'coast',len(b),'town_parts',len(parts))
