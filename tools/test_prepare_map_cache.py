"""Check lossless pack layout, stable legacy revision and repeat preparation."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import prepare_map_cache as build


class PackTest(unittest.TestCase):
    def test_roundtrip_and_legacy_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            originals = {}
            for folder in ('map_images',):
                directory = root/'assets/assets/data'/folder
                directory.mkdir(parents=True)
                for name in ('a.webp', 'b.webp', 'index.json'):
                    data = (folder+name).encode()
                    path = directory/name
                    path.write_bytes(data)
                    originals[str(path.relative_to(root))] = data
            with patch.object(build, 'PACK_BYTES', 64), patch.object(build, 'PACK_FILES', 2):
                build.prepare(root)
            manifest = json.loads((root/'map-image-manifest.json').read_text())
            legacy = [[path, hashlib.sha256(data).hexdigest(), len(data)] for path, data in originals.items()]
            self.assertEqual(manifest['revision'], hashlib.sha256(json.dumps(legacy, separators=(',', ':')).encode()).hexdigest())
            for name, digest, size, start, end in manifest['packs']:
                packed = (root/name).read_bytes()
                self.assertEqual(hashlib.sha256(packed).hexdigest(), digest)
                self.assertEqual(len(packed), size)
                offset = 0
                for path, checksum, length in manifest['assets'][start:end]:
                    self.assertEqual(packed[offset:offset+length], originals[path])
                    self.assertEqual((root/path).exists(), path.endswith('.json'))
                    offset += length
            build.prepare(root)
            self.assertEqual(json.loads((root/'map-image-manifest.json').read_text()), manifest)


if __name__ == '__main__':
    unittest.main()
