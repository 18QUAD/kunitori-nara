#!/usr/bin/env python3
"""Collect attributed Wikipedia source material, without changing app tips.

Only ja.wikipedia.org is requested, through the inherited proxy and CA trust.
HTML snapshots are cached under ignored data/raw; structured evidence is stored
under data/tips/nationwide. This is unreviewed source material, not app copy.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import threading
import time
from urllib.parse import quote, urljoin, urlsplit

import requests
from lxml import html

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'data/raw/national_tip_sources'
OUT = ROOT / 'data/tips/nationwide'
AGENT = 'KunitoriNaraTipsCollector/1.0 (https://github.com/18QUAD/kunitori-nara; offline regional tips research)'
_lock = threading.Lock()
_next_request = 0.0
_local = threading.local()
KEEP = re.compile('概要|地理|地形|歴史|地名|文化|観光|名所|旧跡|祭|特産|産業|農業|伝統|自然|交通|鉄道|沿革|由来|経済')
DROP = re.compile('人口|出身|著名|脚注|参考|関連項目|外部リンク|統計|議会|選挙|教育|行政|政治')


def fetch(title):
    global _next_request
    url = 'https://ja.wikipedia.org/wiki/' + quote(title.replace(' ', '_'), safe='()')
    key = hashlib.sha256(url.encode()).hexdigest()
    meta_path, html_path = CACHE / (key + '.json'), CACHE / (key + '.html.gz')
    if meta_path.exists() and html_path.exists():
        meta = json.loads(meta_path.read_text())
        body = gzip.decompress(html_path.read_bytes())
        if hashlib.sha256(body).hexdigest() == meta['sha256']:
            return body, meta
    if not hasattr(_local, 'session'):
        _local.session = requests.Session()
        _local.session.headers['User-Agent'] = AGENT
    for attempt in range(3):
        with _lock:
            now = time.monotonic()
            delay = max(0, _next_request - now)
            _next_request = max(now, _next_request) + 0.4  # <=2.5 requests/sec globally
        if delay:
            time.sleep(delay)
        response = _local.session.get(url, timeout=(15, 35), allow_redirects=False)
        if response.status_code in (429, 500, 502, 503, 504) and attempt < 2:
            time.sleep(min(30, max(2, int(response.headers.get('Retry-After', '2')))))
            continue
        if response.is_redirect:
            redirected = urljoin(url, response.headers['Location'])
            if urlsplit(redirected).hostname != 'ja.wikipedia.org':
                raise ValueError('Redirect outside allowed source: ' + redirected)
            url = redirected
            continue
        response.raise_for_status()
        body = response.content
        meta = {'requestedUrl': url, 'retrievedAt': datetime.now(timezone.utc).isoformat(),
                'sha256': hashlib.sha256(body).hexdigest(), 'snapshot': str(html_path.relative_to(ROOT))}
        html_path.write_bytes(gzip.compress(body, mtime=0))
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n')
        return body, meta
    raise ValueError('Unable to fetch ' + url)


def parse(body, meta, city, prefecture):
    doc = html.fromstring(body)
    title = ''.join(doc.xpath('//*[@id="firstHeading"]//text()')).strip()
    revisions = re.findall(rb'"wgRevisionId":(\d+)', body)
    canonical = doc.xpath('//link[@rel="canonical"]/@href')
    actual_pref = [' '.join(tr.xpath('./td//text()')).strip() for tr in doc.xpath('//tr')
                   if tr.xpath('./th[contains(.,"都道府県")]')]
    identity = any(prefecture['name'] in p for p in actual_pref)
    if not identity:
        return None, {'title': title, 'prefectureFields': actual_pref[:3], 'reason': 'municipality_identity_not_confirmed'}
    if not revisions or not title:
        return None, {'title': title, 'reason': 'missing_revision'}
    roots = doc.xpath('//*[contains(concat(" ",normalize-space(@class)," ")," mw-parser-output ")]')
    if not roots:
        return None, {'title': title, 'reason': 'missing_article_body'}
    # Some pages emit an empty auxiliary parser-output before the article.
    root = max(roots, key=lambda node: len(node.text_content()))
    for node in list(root.xpath('.//table | .//sup | .//style | .//script | .//*[contains(@class,"navbox")] | .//*[contains(@class,"reflist")]')):
        if node.getparent() is not None:
            node.getparent().remove(node)
    headings = {2: '概要'}
    section = '概要'
    materials, seen = [], set()
    for node in root.iter():
        tag = node.tag if isinstance(node.tag, str) else ''
        if tag in ('h2', 'h3', 'h4'):
            level = int(tag[1])
            headings = {k: v for k, v in headings.items() if k < level}
            headings[level] = re.sub(r'\[編集\]', '', node.text_content()).strip()
            section = ' / '.join(headings.values())
        elif tag in ('p', 'li') and not node.xpath('.//p | .//li'):
            if not KEEP.search(section) or DROP.search(section):
                continue
            text = re.sub(r'\s+', ' ', node.text_content()).strip()
            if not 12 <= len(text) <= 3000 or re.search('人口|世帯|推計', text) or text in seen:
                continue
            seen.add(text)
            materials.append({'section': section, 'text': text})
    revision = int(revisions[0])
    article_url = canonical[0] if canonical else meta['requestedUrl']
    if urlsplit(article_url).hostname != 'ja.wikipedia.org':
        raise ValueError('Unexpected canonical source')
    return {
        'cityId': city['id'], 'cityName': city['name'], 'prefectureId': prefecture['id'],
        'prefectureName': prefecture['name'], 'articleTitle': title, 'articleUrl': article_url,
        'revisionId': revision, 'revisionUrl': 'https://ja.wikipedia.org/w/index.php?oldid=' + str(revision),
        **meta, 'license': 'CC BY-SA 4.0', 'attribution': '日本語版Wikipedia「' + title + '」の執筆者',
        'parserVersion': 2, 'reviewStatus': 'unreviewed_source_material', 'materials': materials,
    }, None


def collect(city, prefecture):
    name = city['name']
    titles = []
    if name.endswith('区') and '市' in name:
        parent, ward = name.split('市', 1)
        titles.extend([ward + ' (' + parent + '市)', ward])
    titles.extend([name, name + ' (' + prefecture['name'] + ')'])
    errors = []
    for title in dict.fromkeys(titles):
        try:
            body, meta = fetch(title)
            record, error = parse(body, meta, city, prefecture)
            if record:
                return record
            errors.append(error)
        except (requests.RequestException, ValueError) as error:
            errors.append({'requestedTitle': title, 'reason': str(error)[:250]})
    return {'cityId': city['id'], 'cityName': name, 'prefectureId': prefecture['id'],
            'prefectureName': prefecture['name'], 'reviewStatus': 'unresolved', 'errors': errors}


def write(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefectures', help='Comma-separated prefecture IDs; defaults to all except Nara')
    parser.add_argument('--workers', type=int, default=3)
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = json.loads((ROOT / 'assets/data/japan.json').read_text())
    prefectures = {p['id']: p for p in atlas['prefectures'] if p['id'] != '29'}
    if args.prefectures:
        prefectures = {k: v for k, v in prefectures.items() if k in args.prefectures.split(',')}
    cities = [c for c in atlas['cities'] if c['id'][:2] in prefectures]
    saved = {}
    for path in OUT.glob('[0-9][0-9].json'):
        for entry in json.loads(path.read_text())['municipalities']:
            saved[entry['cityId']] = entry
    by_pref = {pid: {c['id']: saved[c['id']] for c in cities if c['id'][:2] == pid and
                     c['id'] in saved and saved[c['id']].get('revisionId') and saved[c['id']].get('parserVersion') == 2 and saved[c['id']].get('materials')} for pid in prefectures}
    pending = [c for c in cities if c['id'] not in by_pref[c['id'][:2]]]
    print('Municipalities:', len(cities), 'pending:', len(pending), flush=True)
    with ThreadPoolExecutor(max_workers=min(3, max(1, args.workers))) as pool:
        futures = {pool.submit(collect, c, prefectures[c['id'][:2]]): c for c in pending}
        for count, future in enumerate(as_completed(futures), 1):
            city = futures[future]
            record = future.result()
            pid = city['id'][:2]
            by_pref[pid][city['id']] = record
            write(OUT / (pid + '.json'), {'prefectureId': pid, 'municipalities': sorted(by_pref[pid].values(), key=lambda e: e['cityId'])})
            if count % 25 == 0 or not record.get('revisionId'):
                print(count, '/', len(pending), city['id'], city['name'], record['reviewStatus'], flush=True)
    entries = [e for p in by_pref.values() for e in p.values()]
    report = {'createdAt': datetime.now(timezone.utc).isoformat(), 'scope': 'collection_only_no_runtime_changes',
              'municipalities': len(cities), 'collected': sum(bool(e.get('revisionId')) for e in entries),
              'materials': sum(len(e.get('materials', [])) for e in entries),
              'unresolved': [e for e in entries if not e.get('revisionId')]}
    write(OUT / 'collection_report.json', report)
    print('DONE', {k: v for k, v in report.items() if k != 'unresolved'}, 'unresolved:', len(report['unresolved']), flush=True)


if __name__ == '__main__':
    main()
