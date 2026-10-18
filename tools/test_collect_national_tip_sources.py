import unittest
from collect_national_tip_sources import parse


class SourceParserTest(unittest.TestCase):
    def source(self, prefecture='三重県'):
        return f'''<html><head><meta charset="utf-8"><link rel="canonical" href="https://ja.wikipedia.org/wiki/名張市"></head>
        <script>{{"wgRevisionId":12345}}</script><h1 id="firstHeading">名張市</h1>
        <div class="mw-parser-output"><table><tr><th>都道府県</th><td>{prefecture}</td></tr></table>
        <p>名張市は三重県の伊賀地方に位置する市です。</p>
        <h2>歴史</h2><h3>古代</h3><p>市内には古代寺院の跡が残っています。<sup>1</sup></p>
        <h2>人口</h2><p>この市の人口は架空の数値ですが採用してはいけません。</p>
        <h2>観光</h2><ul><li>歴史を伝える寺院と古い街並みがあります。</li></ul>
        <h2>参考文献</h2><p>この参考文献の文章は素材に含めてはいけません。</p></div></html>'''.encode()

    def parse_source(self, body):
        return parse(body, {'requestedUrl': 'https://ja.wikipedia.org/wiki/名張市'},
                     {'id': '24208', 'name': '名張市'}, {'id': '24', 'name': '三重県'})

    def test_wrong_prefecture_is_not_attached_to_same_named_city(self):
        record, error = self.parse_source(self.source('東京都'))
        self.assertIsNone(record)
        self.assertEqual(error['reason'], 'municipality_identity_not_confirmed')

    def test_history_subsections_keep_their_context_and_revision(self):
        record, error = self.parse_source(self.source())
        self.assertIsNone(error)
        self.assertEqual(record['revisionUrl'], 'https://ja.wikipedia.org/w/index.php?oldid=12345')
        self.assertEqual(record['materials'][1]['section'], '歴史 / 古代')
        self.assertNotIn('1', record['materials'][1]['text'])
        self.assertEqual(record['reviewStatus'], 'unreviewed_source_material')

    def test_empty_auxiliary_article_container_does_not_hide_real_content(self):
        body = self.source().replace(b'<div class="mw-parser-output">', b'<div class="mw-parser-output"></div><div class="mw-parser-output">', 1)
        record, error = self.parse_source(body)
        self.assertIsNone(error)
        self.assertEqual(len(record['materials']), 3)

    def test_population_and_reference_lists_are_not_tip_material(self):
        record, _ = self.parse_source(self.source())
        self.assertEqual(len(record['materials']), 3)
        self.assertFalse(any('人口' in p['text'] or '参考文献' in p['text'] for p in record['materials']))


if __name__ == '__main__':
    unittest.main()
