"""Index exact census JSON rows so national colors decode only needed towns.

Original coordinates, IDs and source files are unchanged. The small indexes point
into the already downloaded source bytes; no duplicate geometry download is needed.
"""
import gzip
import hashlib
import io
import json
import re
import struct
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / 'assets/data'
OUT = DATA / 'national_territories'


def encode(source):
    text = source.decode('utf8')
    start = re.search(r'"towns"\s*:\s*\[', text).end()
    byte_offset = len(text[:start].encode('utf8'))
    decoder = json.JSONDecoder()
    entries = []
    while True:
        begin = start
        while text[begin] in ' \t\r\n,':
            begin += 1
        byte_offset += len(text[start:begin].encode('utf8'))
        if text[begin] == ']':
            break
        row, end = decoder.raw_decode(text, begin)
        length = len(text[begin:end].encode('utf8'))
        entries.append((row['id'], byte_offset, length))
        byte_offset += length
        start = end
    output = io.BytesIO()
    output.write(struct.pack('<4sII', b'KNT3', len(source), len(entries)))
    for source_id, offset, length in entries:
        name = source_id.encode('ascii')
        output.write(struct.pack('<B', len(name)))
        output.write(name)
        output.write(struct.pack('<II', offset, length))
    return output.getvalue(), len(entries)


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    report = {'schema': 1, 'encoding': 'KNT3/source-row-byte-index', 'prefectures': {}}
    for number in range(1, 48):
        pref = f'{number:02d}'
        source = DATA / ('nara.json' if pref == '29' else f'prefectures/{pref}.json')
        original = source.read_bytes()
        packed, rows = encode(original)
        (OUT / f'{pref}.bin').write_bytes(packed)
        report['prefectures'][pref] = {
            'sourceSha256': hashlib.sha256(original).hexdigest(), 'sourceBytes': len(original),
            'sha256': hashlib.sha256(packed).hexdigest(),
            'towns': rows, 'bytes': len(packed),
            'gzipBytes': len(gzip.compress(packed, mtime=0)),
        }
    (OUT / 'index.json').write_text(json.dumps(report, separators=(',', ':')) + '\n')
    print('47 lossless territory indexes:', sum(p['bytes'] for p in report['prefectures'].values()),
          'bytes;', sum(p['gzipBytes'] for p in report['prefectures'].values()), 'gzip bytes')
