#!/usr/bin/env python3
"""Collect a first-page sample of official cultural-property records per prefecture.

This complements nationwide municipality articles; it is not a complete cultural
property inventory. Only the permitted kunishitei.bunka.go.jp host is requested.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import threading
import time
from urllib.parse import urljoin, urlsplit

from lxml import html
import requests

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'data/tips/nationwide'
CACHE = ROOT / 'data/raw/cultural_tip_sources'
LOCK = threading.Lock()
NEXT = 0.0
BASE = 'https://kunishitei.bunka.go.jp'


def request(session, method, path, **kwargs):
    global NEXT
    url = urljoin(BASE, path)
    assert urlsplit(url).hostname == 'kunishitei.bunka.go.jp'
    with LOCK:
        now = time.monotonic()
        delay = max(0, NEXT - now)
        NEXT = max(now, NEXT) + 1
    if delay:
        time.sleep(delay)
    result = session.request(method, url, timeout=(15, 40), allow_redirects=False, **kwargs)
    result.raise_for_status()
    if result.is_redirect:
        raise ValueError('Unexpected redirect')
    return result


def collect(pref, cities):
    session = requests.Session()
    session.headers['User-Agent'] = 'KunitoriNaraTipsCollector/1.0 (https://github.com/18QUAD/kunitori-nara; offline regional tips research)'
    result = request(session, 'GET', '/bsys/index')
    form = html.fromstring(result.content).xpath('//form')[1]
    values = {e.get('name'): e.get('value', '') for e in form.xpath('.//input[@name="_csrfToken" or @name="_method"]')}
    values.update(register_sub_id='401', seat_pref=pref['name'], screen_id='index', page_no='1')
    result = request(session, 'POST', '/bsys/searchlist', data=values)
    doc = html.fromstring(result.content)
    links = list(dict.fromkeys(doc.xpath('//a[contains(@href,"/heritage/detail/")]/@href')))[:5]
    records, errors = [], []
    for link in links:
        try:
            result = request(session, 'GET', link)
            doc = html.fromstring(result.content)
            fields = {}
            for tr in doc.xpath('//tr[not(.//tr)]'):
                cells = [' '.join(x.text_content().split()) for x in tr.xpath('./td|./th')]
                if len(cells) >= 3 and cells[1] in (':', '：'):
                    fields[cells[0]] = ' '.join(cells[2:])
            # Registry schemas vary by cultural-property class.
            fields['所在都道府県'] = next((v for k, v in fields.items() if k.startswith('所在都道府県')), '')
            address = next((v for k, v in fields.items() if k.startswith('所在地')), '')
            if pref['name'] not in fields['所在都道府県']:
                errors.append({'url': result.url, 'reason': 'prefecture_not_confirmed'})
                continue
            key = hashlib.sha256(result.url.encode()).hexdigest()
            snapshot = CACHE / (key + '_' + hashlib.sha256(result.content).hexdigest()[:16] + '.html.gz')
            snapshot.write_bytes(gzip.compress(result.content, mtime=0))
            records.append({'url': result.url, 'publisher': '文化庁 国指定文化財等データベース',
                            'retrievedAt': datetime.now(timezone.utc).isoformat(),
                            'sha256': hashlib.sha256(result.content).hexdigest(),
                            'snapshot': str(snapshot.relative_to(ROOT)),
                            'prefectureId': pref['id'], 'prefectureName': pref['name'],
                            'cityIds': [c['id'] for c in cities if c['id'].startswith(pref['id']) and c['name'] in address],
                            'fields': fields, 'reviewStatus': 'unreviewed_source_material'})
        except (requests.RequestException, ValueError) as error:
            errors.append({'url': urljoin(BASE, link), 'reason': str(error)[:200]})
    return {'prefectureId': pref['id'], 'prefectureName': pref['name'], 'sampleLimit': 5,
            'searchFilter': {'register_sub_id': '401', 'seat_pref': pref['name']}, 'records': records, 'errors': errors}


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((ROOT / 'assets/data/japan.json').read_text())
    prefs = [p for p in atlas['prefectures'] if p['id'] != '29']
    target = OUT / 'cultural_properties.json'
    saved = json.loads(target.read_text())['prefectures'] if target.exists() else []
    done = {p['prefectureId']: p for p in saved if p.get('searchFilter') and len(p['records']) == 5}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = {pool.submit(collect, p, atlas['cities']): p for p in prefs if p['id'] not in done}
        for future in as_completed(futures):
            pref = futures[future]
            try:
                result = future.result()
            except (requests.RequestException, ValueError) as error:
                result = {'prefectureId': pref['id'], 'prefectureName': pref['name'], 'records': [], 'errors': [{'reason': str(error)[:200]}]}
            done[pref['id']] = result
            target.write_text(json.dumps({'scope': 'first_five_designated_historic_scenic_natural_sites_per_prefecture_not_exhaustive', 'prefectures': sorted(done.values(), key=lambda p: p['prefectureId'])}, ensure_ascii=False, indent=2) + '\n')
            print(pref['id'], pref['name'], 'records', len(result['records']), 'errors', len(result['errors']), flush=True)
    print('DONE',len(done),'prefectures', sum(len(p['records']) for p in done.values()),'official records',flush=True)


if __name__ == '__main__':
    main()
