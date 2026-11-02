import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import download


class DriveRefreshTests(unittest.TestCase):
    def setUp(self):
        scratch = Path.cwd()/'.test-temp'
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def fetch(self, data, *, changed=False, checksum=None):
        info = dict(name='HeroWars_GUSSAR.zip', size=str(len(data)),
                    capabilities={'canDownload': True}, version='1',
                    sha256Checksum=checksum or hashlib.sha256(data).hexdigest())
        after = dict(info, version='2') if changed else info
        responses = [io.BytesIO(json.dumps(info).encode()), io.BytesIO(data),
                     io.BytesIO(json.dumps(after).encode())]
        with patch.object(download, 'request', side_effect=responses) as request:
            result = download.download_current(self.directory)
        self.assertEqual(request.call_args_list[1].args, ('?alt=media',))
        return result

    def test_same_drive_source_downloads_new_bytes_on_every_run(self):
        first = self.fetch(b'PK-first version')
        second = self.fetch(b'PK-new version at the same Drive file')
        self.assertNotEqual(first, second)
        self.assertEqual((self.directory/'source.zip').read_bytes(), b'PK-new version at the same Drive file')

    def test_unchanged_content_keeps_same_digest(self):
        self.assertEqual(self.fetch(b'PK-same'), self.fetch(b'PK-same'))

    def test_failed_refresh_never_reuses_previous_zip(self):
        self.fetch(b'PK-old')
        with patch.object(download, 'request', side_effect=OSError('Drive unavailable')):
            with self.assertRaises(OSError):
                download.download_current(self.directory)
        self.assertFalse((self.directory/'source.zip').exists())

    def test_source_changed_during_download_is_rejected(self):
        with self.assertRaises(ValueError):
            self.fetch(b'PK-data', changed=True)
        self.assertFalse((self.directory/'source.zip').exists())
        self.assertFalse((self.directory/'source.zip.part').exists())

    def test_corrupt_download_is_rejected(self):
        with self.assertRaises(ValueError):
            self.fetch(b'PK-data', checksum='a'*64)
        self.assertFalse((self.directory/'source.zip').exists())
