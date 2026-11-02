import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import download

class Response(io.BytesIO):
    def __init__(self,data,declared=None):
        super().__init__(data); self.headers={'Content-Length':str(len(data) if declared is None else declared)}

def zip_bytes(data):
    b=io.BytesIO()
    with zipfile.ZipFile(b,'w') as z: z.writestr('HeroWarsBro.exe',data)
    return b.getvalue()

FORM='''<p>too large for Google to scan for viruses</p><form id="download-form" action="https://drive.usercontent.google.com/download"><input type="hidden" name="id" value="fixture-id"><input type="hidden" name="export" value="download"><input type="hidden" name="confirm" value="t"><input type="hidden" name="uuid" value="fixture"></form>'''

class DriveRefreshTests(unittest.TestCase):
    def setUp(self):
        scratch=Path.cwd()/'.test-temp'; scratch.mkdir(exist_ok=True)
        self.temp=tempfile.TemporaryDirectory(dir=scratch); self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name)
        self.env=patch.dict(os.environ,{'UPDATE_DRIVE_FILE_ID':'fixture-id'}); self.env.start(); self.addCleanup(self.env.stop)
    def fetch(self,data,form=False):
        responses=([Response(FORM.encode())] if form else [])+[Response(data)]
        with patch.object(download,'open_response',side_effect=responses) as request:
            digest=download.download_current(self.directory)
        return digest,request
    def test_same_link_fetches_changed_contents(self):
        first,_=self.fetch(zip_bytes(b'MZ-first'))
        second,_=self.fetch(zip_bytes(b'MZ-new'))
        self.assertNotEqual(first,second)
    def test_unchanged_content_keeps_same_digest(self):
        data=zip_bytes(b'MZ-same'); self.assertEqual(self.fetch(data)[0],self.fetch(data)[0])
    def test_standard_large_file_confirmation_downloads_zip(self):
        data=zip_bytes(b'MZ-new'); digest,request=self.fetch(data,True)
        self.assertEqual(digest,hashlib.sha256(data).hexdigest())
        self.assertEqual(request.call_count,2)
        self.assertTrue(request.call_args.args[1].startswith('https://drive.usercontent.google.com/download?'))
    def test_failed_refresh_does_not_reuse_old_zip(self):
        self.fetch(zip_bytes(b'MZ-old'))
        with patch.object(download,'open_response',side_effect=OSError('offline')):
            with self.assertRaises(OSError): download.download_current(self.directory)
        self.assertFalse((self.directory/'source.zip').exists())
    def test_incomplete_download_rejected(self):
        with patch.object(download,'open_response',return_value=Response(zip_bytes(b'MZ'),9999)):
            with self.assertRaises(ValueError): download.download_current(self.directory)
        self.assertFalse((self.directory/'source.zip').exists())
    def test_corrupt_zip_rejected(self):
        with self.assertRaises(zipfile.BadZipFile): self.fetch(b'PK\x03\x04broken')
    def test_malware_block_is_not_confirmed(self):
        with self.assertRaises(ValueError): download.confirmation_url(FORM+'identified as malware','fixture-id')
    def test_foreign_form_host_and_file_id_rejected(self):
        for form in (FORM.replace('https://drive.usercontent.google.com/download','https://evil.example/download'),FORM.replace('fixture-id','different-file')):
            with self.assertRaises(ValueError): download.confirmation_url(form,'fixture-id')
    def test_metadata_contains_no_source_name_or_url(self):
        self.fetch(zip_bytes(b'MZ-new'),True)
        info=json.loads((self.directory/'source-metadata.json').read_text())
        self.assertEqual(set(info),{'origin','size','source_sha256'})
