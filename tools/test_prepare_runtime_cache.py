import gzip
import hashlib
import json
import random
import tempfile
import unittest
from pathlib import Path
import prepare_runtime_cache as build


class RuntimeTest(unittest.TestCase):
    def test_chunks_are_bounded_lossless_and_repeatable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            files={'assets/assets/data/japan.json':b'{"population":123}',
                   'assets/assets/data/prefectures/24.json':b'{"towns":[]}',
                   'assets/assets/data/national_territories/24.bin':b'KNT3-test-index',
                   'assets/example.bin':random.Random(1).randbytes(2*1024*1024+73),
                   'main.dart.js':b'window.started=true;',
                   'canvaskit/canvaskit.wasm':b'\0asm\1\0\0\0'}
            for name,data in files.items():
                p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
            (root/'map-cache-worker.js').write_text("const REV='__RUNTIME_DATA_REVISION__';")
            build.prepare(root)
            first=json.loads((root/'runtime-data-manifest.json').read_text())
            self.assertFalse((root/'assets/assets/data/prefectures/24.json').exists())
            self.assertFalse((root/'assets/assets/data/national_territories/24.bin').exists())
            for f in first['files']:
                packed=b''.join((root/first['chunks'][i][0]).read_bytes() for i in f['chunks'])
                self.assertEqual(gzip.decompress(packed),files[f['path']])
                self.assertEqual(hashlib.sha256(files[f['path']]).hexdigest(),f['sha256'])
            self.assertTrue(all(c[2]<=1024*1024 for c in first['chunks']))
            build.prepare(root)
            self.assertEqual(json.loads((root/'runtime-data-manifest.json').read_text()),first)


if __name__=='__main__':unittest.main()
