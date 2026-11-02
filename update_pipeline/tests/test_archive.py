import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from archive import inspect, safe_name

class ArchiveTests(unittest.TestCase):
    def make(self, files):
        scratch = Path.cwd() / '.test-temp'
        scratch.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        source = root / 'vendor.zip'
        with zipfile.ZipFile(source, 'w') as z:
            for name, data in files: z.writestr(name, data)
        return source, root / 'payload'

    def test_preserves_exe_name_and_excludes_user_templates(self):
        source, out = self.make([('app/HeroWarsBro.exe', b'MZfake'),
                                 ('app/Profiles/default', b'private'), ('app/license.token', b'secret'),
                                 ('app/Lib/a.dll', b'MZdll')])
        manifest = inspect(source, out)
        self.assertEqual({x['path'] for x in manifest['files']}, {'HeroWarsBro.exe', 'Lib/a.dll'})
        self.assertEqual(len(manifest['source_sha256']), 64)
        self.assertFalse((out / 'license.token').exists())

    def test_windows_path_attacks(self):
        for name in ['../evil', '/root', 'C:/evil', 'a\\b', 'NUL.txt', 'a./b', 'a:ads', 'a//b']:
            with self.subTest(name=name), self.assertRaises(ValueError): safe_name(name)

    def test_case_collision(self):
        source, out = self.make([('HeroWarsBro.exe', b'MZ'), ('herowarsbro.EXE', b'MZ')])
        with self.assertRaises(ValueError): inspect(source, out)

    def test_missing_executable(self):
        source, out = self.make([('HeroWars.exe', b'MZ')])
        with self.assertRaises(ValueError): inspect(source, out)

    def test_files_outside_root(self):
        source, out = self.make([('app/HeroWarsBro.exe', b'MZ'), ('unexpected.exe', b'MZ')])
        with self.assertRaises(ValueError): inspect(source, out)

    def test_symlink(self):
        source, out = self.make([('HeroWarsBro.exe', b'MZ')])
        with zipfile.ZipFile(source, 'a') as z:
            entry = zipfile.ZipInfo('linked')
            entry.external_attr = 0o120777 << 16
            z.writestr(entry, '/outside')
        with self.assertRaises(ValueError): inspect(source, out)

    def test_content_change_detected_without_date(self):
        source, out = self.make([('HeroWarsBro.exe', b'MZone')])
        first = inspect(source, out)['source_sha256']
        with zipfile.ZipFile(source, 'w') as z: z.writestr('HeroWarsBro.exe', b'MZtwo')
        second = inspect(source, out.parent / 'other')['source_sha256']
        self.assertNotEqual(first, second)

if __name__ == '__main__': unittest.main()
