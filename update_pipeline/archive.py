"""Validate untrusted vendor ZIPs without executing their contents."""
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath

PROTECTED = {'profiles', 'screenshots', 'diagnostics', 'settings.json',
             'license.token', 'license.attempts', 'crash.log', '.hwlclk', '.hwlljt'}
MAX_TOTAL = 4 * 1024**3
MAX_FILES = 20000

def sha256(path):
    with open(path, 'rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def safe_name(name):
    if '\\' in name or ':' in name or name.startswith('/'):
        raise ValueError('Unsafe ZIP path')
    parts = name.rstrip('/').split('/')
    if any(p in ('', '.', '..') or p.endswith((' ', '.')) or
           re.search(r'[<>"|?*\x00-\x1f]', p) or
           re.fullmatch(r'(?i)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', p)
           for p in parts):
        raise ValueError('Unsafe Windows path')
    return '/'.join(parts)

def inspect(source, destination):
    destination = Path(destination)
    if destination.exists():
        raise ValueError('Extraction destination must not exist')
    with zipfile.ZipFile(source) as z:
        entries = z.infolist()
        if len(entries) > MAX_FILES or sum(i.file_size for i in entries) > MAX_TOTAL:
            raise ValueError('Archive exceeds limits')
        seen = set()
        files = []
        for i in entries:
            name = safe_name(i.filename)
            if name.casefold() in seen:
                raise ValueError('Case-insensitive duplicate ZIP path')
            seen.add(name.casefold())
            mode = i.external_attr >> 16
            if stat.S_ISLNK(mode) or i.flag_bits & 1:
                raise ValueError('Links and encrypted entries are forbidden')
            if i.file_size > max(i.compress_size, 1) * 1000:
                raise ValueError('Suspicious compression ratio')
            if not i.is_dir():
                files.append((i, name))
        exes = [name for _, name in files if PurePosixPath(name).name.casefold() == 'herowarsbro.exe']
        if len(exes) != 1:
            raise ValueError('Expected exactly one HeroWarsBro.exe')
        root = str(PurePosixPath(exes[0]).parent)
        prefix = '' if root == '.' else root + '/'
        if any(not name.startswith(prefix) for _, name in files):
            raise ValueError('Unexpected files outside application root')
        # Read every entry: CRC validation includes excluded user-data templates.
        payload = []
        for i, name in files:
            relative = name[len(prefix):]
            data = z.read(i)
            if relative.split('/')[0].casefold() in PROTECTED:
                continue
            if relative.casefold() in ('unins000.exe', 'unins000.dat') or relative.startswith('.titanmatik'):
                raise ValueError('Reserved installer path')
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            payload.append({'path': relative, 'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)})
        if (destination / 'HeroWarsBro.exe').read_bytes()[:2] != b'MZ':
            raise ValueError('Main executable is not a PE image')
    return {'source_sha256': sha256(source), 'files': payload}

if __name__ == '__main__':
    import sys
    manifest = inspect(sys.argv[1], sys.argv[2])
    Path(sys.argv[3]).write_text(json.dumps(manifest, indent=2), encoding='utf-8')
