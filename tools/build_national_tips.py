#!/usr/bin/env python3
"""Build source-grounded short municipality tips; never truncate sentences.

Fixed IDs use source identity + original sentence. The ID catalogue preserves
retired IDs so saved reading history remains valid when wording is edited.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/tips/nationwide'
OUT = ROOT / 'assets/data/tips'
BAD = re.compile(r'人口|世帯|推計|現在|近年|最近|この|その|それ|これ|同市|同町|同村|本市|本町|本村|同年|翌年|同区|当市|当町|当村|当区|令和|202[0-9]|201[0-9]|出典|不明|不詳|要検証|と思われ|とされ|らしい|ランキング|統計|減少|増加|以下|前述|後述|上述|同名|よって|その後|多く|最も|最大|最少|唯一|最古|最新|事故|死亡|被害|停電|奉迎|行幸|皇太子|患者|炊き出し|仮設住宅|郵便番号|字名|行政区|震災|大震災|被災|2011|ない|なく|無い|ただし|しかし|当初|かつての|特筆|特に|多い|少ない|上記|参照|^※|^-| - |–|—|→|%|％')
PREDICATE = re.compile(r'(である|ある|いる|れる|られた|だった|なった|であった|された|位置する|流れる|残る|する|した|なった|通る|続く|盛ん|町|市|村|区)$')


def clean(raw):
    text = re.sub(r'（[ぁ-んァ-ヶー・ 、]+）', '', raw.strip())
    text = re.sub(r'^(また、|なお、)', '', text)
    if BAD.search(text) or not re.search('は|が|には|では', text) or not PREDICATE.search(text):
        return None
    if any(text.count(a) != text.count(b) for a, b in [('「', '」'), ('『', '』'), ('（', '）'), ('(', ')')]):
        return None
    for old, new in [('であった', 'でした'), ('である', 'です'), ('ある', 'あります'), ('いる', 'います'), ('された', 'されました'), ('られた', 'られました'), ('だった', 'でした')]:
        if text.endswith(old):
            text = text[:-len(old)] + new
            break
    else:
        if text.endswith(('町', '市', '村', '区')):
            text += 'です'
    text += '。'
    return text if 14 <= len(text) <= 40 else None


def category(section):
    if any(w in section for w in ['観光', '名所', '旧跡', '文化', '祭', '伝統']): return '文化・名所', 30
    if any(w in section for w in ['産業', '農業', '特産', '経済']): return '産業', 25
    if any(w in section for w in ['地理', '地形', '自然']): return '地理・自然', 20
    if any(w in section for w in ['歴史', '沿革', '由来', '地名']): return '歴史', 15
    return '地域', 5


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sources = [e for p in sorted(SOURCE.glob('[0-9][0-9].json')) for e in json.loads(p.read_text())['municipalities']]
    overrides_path = SOURCE / 'short_tip_overrides.json'
    overrides = json.loads(overrides_path.read_text()) if overrides_path.exists() else {}
    official = json.loads((SOURCE / 'cultural_properties.json').read_text())
    official_by_city = {}
    for p in official['prefectures']:
        for record in p['records']:
            name = record['fields']['名称']
            kind = record['fields'].get('種別１', '')
            text = f'「{name}」は国指定の{kind}です。'
            if kind not in ['史跡', '名勝', '天然記念物'] or len(text) > 40 or '\n' in name or '■' in name:
                continue
            for cid in record['cityIds']:
                official_by_city.setdefault(cid, []).append({'text': text, 'category': '文化・名所', 'source': record['url'], 'evidence': record['fields'], 'score': 35, 'identity': record['url']})
    by_pref, audit, missing = {}, [], []
    for source in sources:
        cid = source['cityId']
        revision_url = 'https://ja.wikipedia.org/w/index.php?' + urlencode({'title': source['articleTitle'], 'oldid': source['revisionId']})
        candidates = list(official_by_city.get(cid, []))
        for m in source['materials']:
            # Named rivers/lakes/mountains listed under geography can be stated
            # directly without cutting a long explanatory paragraph in half.
            listed = re.match(r'^(河川|山岳|山|湖沼|湖)\s*[：:]\s*(.+)', m['text'])
            if listed and '地理' in m['section']:
                kind, names = listed.groups()
                names = re.sub(r'[（(].*?[）)]', '', names)
                for raw_name in re.split('[、,，・]', names)[:3]:
                    name = re.sub(r'[（(].*?[）)]', '', raw_name).strip()
                    if any(c in name for c in '（）()[]■') or not 3 <= len(name) <= 16 or '水系' in name or not re.search('(川|湖|沼|池|山|岳|峰|山地|山脈)$', name): continue
                    verb = 'が流れています' if kind == '河川' else 'があります'
                    text = source['cityName'] + 'には' + name + verb + '。'
                    if len(text) <= 40:
                        candidates.append({'text': text, 'category': '地理・自然', 'source': revision_url,
                            'evidence': {'section': m['section'], 'geographyList': m['text']}, 'score': 21,
                            'identity': source['articleUrl'] + '|geography-list:' + kind + ':' + name})
            cat, base = category(m['section'])
            if any(w in m['section'] for w in ['戦争', '災害', '震災', '地震', '気候', '行政', '鉄道', '交通', '経済']): continue
            # Only complete sentences from the original paragraph are eligible.
            for index, raw in enumerate(m['text'].split('。')[:-1]):
                original = raw.strip()
                # Standalone balloons need an explicit local subject. Do not
                # extract a dependent sentence or an event-list fragment.
                raw = re.sub(r'^' + re.escape(source['cityName']) + r'（[^）]+）', source['cityName'], raw.strip())
                local_name = source['cityName'].split('市')[-1] if source['cityName'].endswith('区') and '市' in source['cityName'] else source['cityName']
                raw = re.sub(r'^' + re.escape(local_name) + r'（[^）]+）', local_name, raw)
                local_subject = re.match(r'^(?:' + re.escape(local_name) + r'|市内|町内|村内|区内|市域|町域|村域|区域|市の|町の|村の|区の)', raw)
                if not local_subject:
                    continue
                text = clean(raw)
                if text:
                    candidates.append({'text': text, 'category': cat, 'source': revision_url,
                                       'evidence': {'section': m['section'], 'sentence': original},
                                       'score': base + (5 if index == 0 else 0),
                                       'identity': source['articleUrl'] + '|' + original})
        for item in overrides.get(cid, []):
            candidates.append({'text': item['text'], 'category': item['category'], 'source': revision_url,
                               'evidence': item['evidence'], 'score': 100, 'identity': source['articleUrl'] + '|editorial:' + item['key']})
        # The map retains the 2020 wards. Reorganized Hamamatsu wards
        # use explicitly dated editorial wording instead of present-tense intros.
        if cid in {'22131', '22132', '22133', '22134', '22135', '22136'}:
            candidates = [c for c in candidates if c['score'] == 100]
        selected, texts, cat_counts = [], set(), Counter()
        for candidate in sorted(candidates, key=lambda c: -c['score']):
            if candidate['text'] in texts or cat_counts[candidate['category']] >= 2: continue
            if len(selected) == 5: break
            identifier = cid + ':national:' + hashlib.sha256(candidate['identity'].encode()).hexdigest()[:12]
            selected.append({'id': identifier, 'cityId': cid, 'category': candidate['category'], 'text': candidate['text'], 'source': candidate['source']})
            audit.append({'id': identifier, 'cityId': cid, 'cityName': source['cityName'], **candidate})
            texts.add(candidate['text']); cat_counts[candidate['category']] += 1
        if not selected:
            # Explicitly sourced introductory location, shortened as a complete
            # sentence. Use this only if the article itself states the region.
            introductory = source['materials'][0]
            name, pref = source['cityName'], source['prefectureName']
            parent = name.split('市')[0] + '市' if name.endswith('区') and '市' in name else None
            region = parent or pref
            if region in introductory['text']:
                kind = '行政区' if parent else ('特別区' if name.endswith('区') else name[-1])
                text = f'{name}は{region}にある{kind}です。'
                identifier = cid + ':national:' + hashlib.sha256((source['articleUrl'] + '|intro-location').encode()).hexdigest()[:12]
                selected.append({'id': identifier, 'cityId': cid, 'category': '地理・自然', 'text': text, 'source': revision_url})
                audit.append({'id': identifier, 'cityId': cid, 'cityName': name, 'text': text, 'source': revision_url, 'evidence': introductory, 'identity': source['articleUrl'] + '|intro-location', 'score': 0})
        for row in selected:
            assert row['cityId'] == cid and len(row['text']) <= 40 and row['text'].endswith('。')
            assert not re.search(r'https?://|www\.|出典|脚注|Wikipedia|ウィキペディア|\[\d+\]|注\d+|要出典|参考|人口|世帯|推計|準備中|\n|■', row['text']), row
            for opening, closing in [('（', '）'), ('(', ')'), ('「', '」'), ('『', '』')]:
                assert row['text'].count(opening) == row['text'].count(closing), row
        if not selected: missing.append({'cityId': cid, 'name': source['cityName']})
        by_pref.setdefault(cid[:2], {})[cid] = selected
    (SOURCE / 'short_tip_audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    (SOURCE / 'short_tip_missing.json').write_text(json.dumps(missing, ensure_ascii=False, indent=2) + '\n')
    if missing:
        print('Missing', len(missing), missing)
        raise SystemExit(1)
    ids = {t['id'] for tips in by_pref.values() for ts in tips.values() for t in ts}
    index_path = OUT / 'index.json'
    old = json.loads(index_path.read_text()) if index_path.exists() else {}
    known = sorted(ids | set(old.get('knownIds', [])))
    for pid, cities in by_pref.items():
        (OUT / (pid + '.json')).write_text(json.dumps({'prefectureId': pid, 'cities': cities}, ensure_ascii=False, separators=(',', ':')) + '\n')
    index = {'version': 1, 'prefectures': sorted(by_pref), 'municipalities': len(sources), 'tips': len(ids), 'knownIds': known,
             'license': 'Wikipedia-derived tips: CC BY-SA 4.0; attribution and fixed revision in each source URL.'}
    index_path.write_text(json.dumps(index, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('DONE', len(sources), 'municipalities', len(ids), 'tips', Counter(len(ts) for cs in by_pref.values() for ts in cs.values()))


if __name__ == '__main__': main()
