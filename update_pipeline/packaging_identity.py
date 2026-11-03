"""Rebuild unchanged vendor ZIPs when TitanMatik packaging changes."""
import hashlib
from pathlib import Path

def packaging_sha256():
    digest = hashlib.sha256()
    paths = [Path('installer/TitanMatik.iss'), Path('installer/TitanMatik.ico'),
             Path('installer/TitanMatik.Update.ps1')]
    paths += sorted(Path('update_pipeline').glob('*.py'))
    for path in paths:
        data = path.read_bytes()
        digest.update(path.as_posix().encode() + b'\0')
        digest.update(len(data).to_bytes(8, 'big'))
        digest.update(data)
    return digest.hexdigest()
