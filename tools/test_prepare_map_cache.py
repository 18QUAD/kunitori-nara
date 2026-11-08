"""Native app packs preserve exact image bytes and stable identities."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import prepare_map_cache as build


class PackTest(unittest.TestCase):
    def test_native_roundtrip_and_stable_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'
            images = source / 'map_images'
            images.mkdir(parents=True)
            originals = {'a.webp': b'first-image', 'b.webp': b'second-image'}
            for name, data in originals.items():
                (images / name).write_bytes(data)
            (images / 'index.json').write_text(json.dumps({'tiles': {'a': {}, 'b': {}}}))
            output = Path(tmp) / 'packs'
            output.mkdir()
            with patch.object(build, 'PACK_BYTES', 16):
                build.prepare(output, source)
                manifest = json.loads((output / 'map-image-manifest.json').read_text())
                self.assertEqual(manifest['packSchema'], 2)
                for name, digest, size, start, end in manifest['packs']:
                    data = (output / name).read_bytes()
                    self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
                    self.assertEqual(len(data), size)
                    offset = 0
                    for filename, length in manifest['assets'][start:end]:
                        self.assertEqual(data[offset:offset + length], originals[filename])
                        self.assertEqual((images / filename).read_bytes(), originals[filename])
                        offset += length
                    self.assertEqual(offset, size)
                build.prepare(output, source)
                self.assertEqual(json.loads((output / 'map-image-manifest.json').read_text()), manifest)
            self.assertFalse((output / 'map-cache-worker.js').exists())


if __name__ == '__main__':
    unittest.main()
