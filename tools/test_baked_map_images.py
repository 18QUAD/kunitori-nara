"""Offline generator regressions independent of the nationwide render run."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from shapely.geometry import LineString
import bake_map_images as bake
import prepare_map_cache as packer
import json
import hashlib
from optimize_map_images import DELIVERY_MARKER, encode


class BakedImagesTest(unittest.TestCase):
    def test_large_public_packs_use_committed_immutable_bytes_and_stable_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo=Path(tmp);prepared=repo/'data/prepared_maps';prepared.mkdir(parents=True)
            web=repo/'build/web';index=web/'assets/assets/data/map_images/index.json'
            index.parent.mkdir(parents=True);index.write_bytes(b'{"schema":2}')
            original=dict(packSchema=2,bytes=10,revision='images-v1',packs=[['map-packs/example.bin','digest',10,0,1]],
                          indexSha256=hashlib.sha256(index.read_bytes()).hexdigest(),assets=[['a.webp',10]])
            manifest=prepared/'map-image-manifest.json';manifest.write_text(json.dumps(original))
            commit='a'*40
            with patch.object(packer,'__file__',str(repo/'tools/prepare_map_cache.py')), \
                 patch.object(packer,'PAGES_IMAGE_BUDGET',0), \
                 patch.object(packer,'worker_source',return_value='__MAP_IMAGE_REVISION__'), \
                 patch.object(packer.subprocess,'check_output',side_effect=[commit+'\n',manifest.read_bytes()]):
                packer.prepare(web)
            public=json.loads((web/'map-image-manifest.json').read_text())
            self.assertEqual(public['packs'],original['packs'])
            self.assertEqual(public['packBaseUrl'],f'https://raw.githubusercontent.com/18QUAD/kunitori-nara/{commit}/data/prepared_maps/')
            self.assertFalse((web/'map-packs').exists())
            self.assertEqual(json.loads(manifest.read_text()),original)
            with patch.object(packer,'__file__',str(repo/'tools/prepare_map_cache.py')), \
                 patch.object(packer,'PAGES_IMAGE_BUDGET',0), \
                 patch.object(packer.subprocess,'check_output',side_effect=[commit+'\n',b'old manifest']):
                with self.assertRaisesRegex(ValueError,'Commit the finished'):
                    packer.prepare(web)

    def test_delivery_encoding_is_idempotent_even_without_the_work_journal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'sample_background.webp'
            Image.new('RGB',(512,512),(80,190,225)).save(path,quality=88)
            name,digest,changed=encode((path,None))
            self.assertTrue(changed)
            first=path.read_bytes()
            self.assertEqual(encode((path,None)),(name,digest,False))
            self.assertEqual(path.read_bytes(),first)
            with Image.open(path) as im:
                self.assertEqual(im.size,(512,512))
                self.assertEqual(im.info['xmp'],DELIVERY_MARKER)

    def test_every_scale_has_the_same_thin_boundary_without_casing(self):
        # Straight synthetic geometry isolates width from road curvature/slope.
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder)
            line=LineString([(135.73,34.5),(135.73,34.51)])
            bake.render_lines([line],'town',[3,5,8],folder)
            for level in [3,5,8]:
                ppd=128*2**level; span=512/ppd
                x=int((135.73-120)//span); y=int((48-34.505)//span)
                with Image.open(folder/f'{level}_{x}_{y}_town.webp') as im:
                    rgba=im.convert('RGBA'); py=int((48-y*span-34.505)*ppd)
                    coverage=sum(rgba.getpixel((px,py))[3]/255 for px in range(512))
                    self.assertAlmostEqual(coverage/2,.625,delta=.12)
                    self.assertTrue(all(pixel[:3]==(255,255,255) for pixel in rgba.getdata() if pixel[3]))

    def test_compact_packs_reconstruct_source_without_per_image_hash_strings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); data=root/'source'; images=data/'map_images'; images.mkdir(parents=True)
            originals={'0_1_2_background.webp':b'background','0_1_2_city.webp':b'boundary','index.json':b'{"schema":2}'}
            for name,content in originals.items(): (images/name).write_bytes(content)
            output=root/'prepared';output.mkdir()
            packer.prepare(output,data)
            manifest=json.loads((output/'map-image-manifest.json').read_text())
            self.assertEqual(manifest['packSchema'],2)
            self.assertEqual(manifest['indexSha256'],hashlib.sha256(originals['index.json']).hexdigest())
            for name,digest,size,start,end in manifest['packs']:
                content=(output/name).read_bytes();self.assertEqual(hashlib.sha256(content).hexdigest(),digest)
                offset=0
                for asset,length in manifest['assets'][start:end]:
                    self.assertEqual(content[offset:offset+length],originals[asset]);offset+=length
            self.assertTrue(all((images/name).exists() for name in originals))
            (images/'0_1_2_background.webp').write_bytes(b'new background')
            packer.prepare(output,data)
            changed=json.loads((output/'map-image-manifest.json').read_text())
            self.assertNotEqual(changed['revision'],manifest['revision'])


if __name__=='__main__':unittest.main()
