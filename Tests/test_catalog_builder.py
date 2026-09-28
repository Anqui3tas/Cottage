import importlib.util
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import zlib

SPEC = importlib.util.spec_from_file_location("catalog", Path(__file__).parents[1] / "Scripts/build_catalog.py")
catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(catalog)


def png(width=100, height=100):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\x00\x00' * width) * height)) + chunk(b'IEND', b'')


class CatalogBuilderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.artist = self.root / 'Artists/TestArtist'
        self.pack = self.artist / 'Test Collection/01.Episode One'
        self.pack.mkdir(parents=True)
        (self.artist / 'Artist image.png').write_bytes(png())
        self.profile = self.artist / 'TestArtist.txt'
        self.profile.write_text('Display Name: Test Artist\nLink: https://example.com/artist\nDescription: Bookish art\nUsage: The Cottage may distribute and cache these images.\nPersonal use only. Credit the artist.\n')
        (self.pack / '10.Zebra.png').write_bytes(png())
        (self.pack / '02.crème.png').write_bytes(png())

    def tearDown(self):
        self.temp.cleanup()

    def build(self):
        return catalog.build(self.root, 'example/artists', 'main')

    def test_order_unicode_usage_and_checksums(self):
        result = self.build()
        files = result['artworks'][0]['files']
        self.assertEqual([f['title'] for f in files], ['crème', 'Zebra'])
        self.assertIn('cr%C3%A8me.png', files[0]['url'])
        self.assertEqual(len(files[0]['sha256']), 64)
        self.assertIn('Personal use only.', result['artists'][0]['usage'])
        self.assertEqual(result['artworks'][0]['title'], 'Episode One')

    def test_reordering_preserves_identity(self):
        before = self.build()['artworks'][0]['files'][0]['id']
        (self.pack / '02.crème.png').rename(self.pack / '01.crème.png')
        self.assertEqual(before, self.build()['artworks'][0]['files'][0]['id'])

    def test_missing_usage_rejected(self):
        self.profile.write_text('Display Name: Artist\nDescription: Art\n')
        with self.assertRaisesRegex(ValueError, 'Usage'):
            self.build()

    def test_duplicate_identity_rejected(self):
        (self.pack / '03.crème.png').write_bytes(png())
        with self.assertRaisesRegex(ValueError, 'duplicate image'):
            self.build()

    def test_original_dimensions_and_wallpaper_override(self):
        (self.pack / '02.crème.png').write_bytes(png(8193, 1))
        with self.assertRaisesRegex(ValueError, 'dimensions'):
            self.build()
        (self.pack / '02.crème.png').write_bytes(png(1000, 100))
        self.assertEqual(self.build()['artworks'][0]['kind'], 'sticker_pack')
        (self.pack / 'Pack.txt').write_text('Type: wallpaper')
        self.assertEqual(self.build()['artworks'][0]['kind'], 'wallpaper')

    def test_missing_artists_root_rejected_but_explicit_empty_supported(self):
        shutil.rmtree(self.root / 'Artists')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            self.build()
        (self.root / 'Artists').mkdir()
        self.assertEqual(self.build()['artworks'], [])

    def test_removal_excludes_deleted_pack(self):
        shutil.rmtree(self.pack)
        self.assertEqual(self.build()['artworks'], [])

    def test_symlink_rejected(self):
        (self.pack / 'secret.png').symlink_to(self.artist / 'Artist image.png')
        with self.assertRaisesRegex(ValueError, 'symbolic'):
            self.build()

    def test_pending_terms_disable_downloads_and_banner_is_optional(self):
        self.profile.write_text('Name: Kyra\nDisplay Name: geyser.nerd\nDescription: Art\nUsage: Pending artist confirmation.\n')
        (self.artist / 'Artist image.png').unlink()
        result = self.build()
        self.assertIsNone(result['artists'][0]['headerURL'])
        self.assertEqual(result['artworks'][0]['deliveryKind'], 'planned')
        self.assertEqual(result['artworks'][0]['usageLicense'], 'unspecified')

    def test_template_prompts_rejected(self):
        self.profile.write_text('Display Name: Artist\nDescription: Art\nUsage: [Replace with terms]\n')
        with self.assertRaisesRegex(ValueError, 'Usage'):
            self.build()


if __name__ == '__main__':
    unittest.main()
