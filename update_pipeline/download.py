"""Drive API only; never acknowledge abuse or scrape confirmation screens."""
import json
import os
import re
import urllib.request
from pathlib import Path
from archive import sha256

def request(query):
    file_id = os.environ['UPDATE_DRIVE_FILE_ID']
    if not re.fullmatch('[A-Za-z0-9_-]+', file_id):
        raise ValueError('Invalid Drive source file ID')
    base = 'https://www.googleapis.com/drive/v3/files/' + file_id
    token = os.environ['DRIVE_ACCESS_TOKEN']
    req = urllib.request.Request(base + query, headers={'Authorization': 'Bearer ' + token})
    return urllib.request.urlopen(req, timeout=120)

def metadata():
    with request('?fields=id,name,size,md5Checksum,sha256Checksum,version,capabilities/canDownload') as r:
        return json.load(r)

def download_current(directory='build'):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / 'source.zip'
    partial = directory / 'source.zip.part'
    # A failed refresh must never leave an old ZIP available to the next step.
    target.unlink(missing_ok=True)
    partial.unlink(missing_ok=True)
    (directory / 'source-metadata.json').unlink(missing_ok=True)
    try:
        return _download_current(directory, target, partial)
    finally:
        partial.unlink(missing_ok=True)

def _download_current(directory, target, partial):
    before = metadata()
    if before.get('name') != 'HeroWars_GUSSAR.zip' or not before.get('capabilities', {}).get('canDownload'):
        raise ValueError('Source identity or download permission failed')
    limit = 2 * 1024**3
    if not 0 < int(before.get('size', 0)) <= limit:
        raise ValueError('Source size outside limits')
    with request('?alt=media') as r, partial.open('wb') as f:
        total = 0
        while chunk := r.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise ValueError('Download exceeds limit')
            f.write(chunk)
    after = metadata()
    if before != after or total != int(before['size']):
        raise ValueError('Source changed during download')
    digest = sha256(partial)
    if before.get('sha256Checksum') and digest != before['sha256Checksum']:
        raise ValueError('Drive checksum mismatch')
    partial.replace(target)
    (directory / 'source-metadata.json').write_text(json.dumps(before), encoding='utf-8')
    return digest

def main():
    digest = download_current()
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as f:
        f.write('sha256=' + digest + '\n')

if __name__ == '__main__':
    main()
