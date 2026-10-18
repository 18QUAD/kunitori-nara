#!/usr/bin/env python3
"""Build nationwide ad locations from the game's fixed municipality catalogue."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARENTS = dict(zip(
    ['札幌市','仙台市','さいたま市','千葉市','横浜市','川崎市','相模原市','新潟市','静岡市','浜松市','名古屋市','京都市','大阪市','堺市','神戸市','岡山市','広島市','北九州市','福岡市','熊本市'],
    ['01100','04100','11100','12100','14100','14130','14150','15100','22100','22130','23100','26100','27100','27140','28100','33100','34100','40100','40130','43100']))

def main():
    national = json.loads((ROOT/'assets/data/japan.json').read_text())
    nara = json.loads((ROOT/'assets/data/nara.json').read_text())
    prefs = {p['id']:p['name'] for p in national['prefectures']}
    path = ROOT/'server/regional-ads/regions.json'
    existing = json.loads(path.read_text())
    regions = {}
    for city in sorted(national['cities'] + nara['cities'], key=lambda c:c['id']):
        cid, name = city['id'], city['name']
        parent = next((p for p in PARENTS if name.startswith(p) and name.endswith('区')), None)
        regions[cid] = {**existing.get(cid, {'shops': []}), 'name':name,
                        'prefecture':prefs[cid[:2]], 'taxName':parent or name,
                        'taxCityId':PARENTS[parent] if parent else cid}
    assert len(regions) == 1896
    path.write_text(json.dumps(regions,ensure_ascii=False,indent=2)+'\n')
    print('Built',len(regions),'ad regions across',len(prefs),'prefectures')

if __name__ == '__main__': main()
