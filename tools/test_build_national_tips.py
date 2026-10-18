"""Validate shipped short tips, source evidence and fixed history IDs."""
import hashlib
import json
from pathlib import Path
import re
import unittest
from urllib.parse import urlsplit, parse_qs

ROOT = Path(__file__).resolve().parents[1]

class NationalTipAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = ROOT / 'data/tips/nationwide'
        cls.out = ROOT / 'assets/data/tips'
        cls.index = json.loads((cls.out / 'index.json').read_text())
        cls.cities = {c['id'] for c in json.loads((ROOT / 'assets/data/japan.json').read_text())['cities']}
        cls.rows = [t for p in cls.out.glob('[0-9][0-9].json') for ts in json.loads(p.read_text())['cities'].values() for t in ts]
        cls.audit = {t['id']: t for t in json.loads((cls.source / 'short_tip_audit.json').read_text())}
        cls.sources = {e['cityId']: e for p in cls.source.glob('[0-9][0-9].json') for e in json.loads(p.read_text())['municipalities']}
        cls.official = {r['url']: r for p in json.loads((cls.source / 'cultural_properties.json').read_text())['prefectures'] for r in p['records']}

    def test_complete_municipal_coverage_without_nara(self):
        self.assertEqual(len(self.cities), 1857)
        self.assertEqual({r['cityId'] for r in self.rows}, self.cities)
        self.assertEqual(len(self.rows), self.index['tips'])
        self.assertEqual(len({r['id'] for r in self.rows}), len(self.rows))
        self.assertEqual(self.index['municipalities'], 1857)
        self.assertEqual(self.index['prefectures'], sorted({c[:2] for c in self.cities}))
        for p in self.out.glob('[0-9][0-9].json'):
            data = json.loads(p.read_text())
            self.assertEqual(p.stem, data['prefectureId'])
            self.assertNotEqual(p.stem, '29')
            for cid, tips in data['cities'].items():
                self.assertTrue(cid.startswith(p.stem))
                self.assertTrue(1 <= len(tips) <= 5)

    def test_no_references_footnotes_or_population_in_balloon_text(self):
        forbidden = re.compile(r'https?://|www\.|出典|脚注|Wikipedia|ウィキペディア|\[\d+\]|注\d+|要出典|参考|人口|世帯|推計|準備中|\n|■')
        for row in self.rows:
            text = row['text']
            with self.subTest(id=row['id'], text=text):
                self.assertLessEqual(len(text), 40)
                self.assertTrue(text.endswith('。'))
                self.assertIsNone(forbidden.search(text))
                for a,b in [('（','）'),('(',')'),('「','」'),('『','』')]:
                    self.assertEqual(text.count(a), text.count(b))

    def test_reorganized_hamamatsu_wards_use_historical_wording(self):
        for cid in ['22131', '22132', '22133', '22134', '22135', '22136']:
            tips = [r['text'] for r in self.rows if r['cityId'] == cid]
            self.assertTrue(any('2024年' in text for text in tips), cid)
            self.assertTrue(all('2024年' in text or '旧' in text for text in tips), cid)

    def test_every_tip_retains_source_evidence_and_stable_id_outside_text(self):
        for row in self.rows:
            audit = self.audit[row['id']]
            self.assertEqual(row['text'], audit['text'])
            self.assertIn(row['id'], self.index['knownIds'])
            self.assertEqual(row['id'], row['cityId'] + ':national:' + hashlib.sha256(audit['identity'].encode()).hexdigest()[:12])
            url = urlsplit(row['source'])
            self.assertEqual(url.scheme, 'https')
            if url.hostname == 'ja.wikipedia.org':
                source = self.sources[row['cityId']]
                self.assertEqual(parse_qs(url.query)['oldid'], [str(source['revisionId'])])
                self.assertEqual(parse_qs(url.query)['title'], [source['articleTitle']])
                evidence = audit['evidence']
                original = evidence.get('sentence') or evidence.get('geographyList') or evidence.get('text')
                self.assertTrue(any(original in m['text'] for m in source['materials']), row['id'])
            else:
                self.assertEqual(url.hostname, 'kunishitei.bunka.go.jp')
                self.assertIn(row['cityId'], self.official[row['source']]['cityIds'])
                self.assertEqual(audit['evidence'], self.official[row['source']]['fields'])

if __name__ == '__main__': unittest.main()
