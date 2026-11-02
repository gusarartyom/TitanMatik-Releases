"""No-R2 distribution: verified draft -> public prerelease -> latest release."""
import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from archive import sha256
from telegram_notify import send_message

SETUP = 'TitanMatik_Setup.exe'
MANIFEST = 'TitanMatik_manifest.json'
TAG = re.compile(r'tm-[a-f0-9]{64}-[a-f0-9]{64}')
MARKER = re.compile(r'<!-- titanmatik-notification: (.*?) -->')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None

class GitHub:
    def __init__(self, repository, token):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise ValueError('Invalid repository')
        self.repo = repository
        self.token = token
        self.base = 'https://api.github.com/repos/' + repository
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, method, suffix, value=None, *, raw=None, upload=False):
        base = ('https://uploads.github.com/repos/' + self.repo) if upload else self.base
        data = raw if raw is not None else (json.dumps(value).encode() if value is not None else None)
        request = urllib.request.Request(base + suffix, data=data, method=method, headers={
            'Authorization': 'Bearer ' + self.token,
            'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/octet-stream' if raw is not None else 'application/json',
            'User-Agent': 'TitanMatik-release-pipeline'})
        with self.opener.open(request, timeout=180) as response:
            return json.load(response)

    def optional(self, suffix):
        try:
            return self.request('GET', suffix)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            raise

    def assert_public(self):
        if self.request('GET', '').get('private') is not False:
            raise ValueError('This pipeline requires a PUBLIC distribution repository')

    def latest(self):
        return self.optional('/releases/latest')

    def by_tag(self, tag):
        if not TAG.fullmatch(tag):
            raise ValueError('Invalid TitanMatik release tag')
        return self.optional('/releases/tags/' + tag)

    def source_draft(self, tag):
        if not re.fullmatch('source-[a-f0-9]{64}', tag):
            raise ValueError('Invalid manual source tag')
        return self.optional('/releases/tags/' + tag)

    def create(self, tag, body):
        return self.request('POST', '/releases', {'tag_name': tag, 'name': 'TitanMatik ' + tag[3:15],
                            'body': body, 'draft': True, 'prerelease': True})

    def patch(self, release, **fields):
        return self.request('PATCH', '/releases/' + str(release['id']), fields)

    def upload(self, release, name, data):
        return self.request('POST', '/releases/' + str(release['id']) + '/assets?name=' +
                            urllib.parse.quote(name, safe=''), raw=data, upload=True)

    def read_asset(self, asset):
        # Do not forward a repository token to the redirected asset-storage host.
        request = urllib.request.Request(self.base + '/releases/assets/' + str(asset['id']), headers={
            'Authorization': 'Bearer ' + self.token, 'Accept': 'application/octet-stream',
            'User-Agent': 'TitanMatik-release-pipeline'})
        try:
            return self.opener.open(request, timeout=180)
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise
            url = error.headers.get('Location', '')
            parsed = urllib.parse.urlparse(url)
            if parsed.scheme != 'https' or not (parsed.hostname or '').endswith('.githubusercontent.com'):
                raise ValueError('Unexpected asset redirect')
            return self.opener.open(urllib.request.Request(url), timeout=180)

    def verify_public(self, release, digest):
        url = 'https://github.com/' + self.repo + '/releases/download/' + release['tag_name'] + '/' + SETUP
        with urllib.request.urlopen(url, timeout=180) as response:
            if hashlib.file_digest(response, 'sha256').hexdigest() != digest:
                raise ValueError('Anonymous release download failed SHA-256 verification')

def asset(release, name):
    found = [item for item in release.get('assets', []) if item['name'] == name]
    if len(found) != 1:
        raise ValueError('Missing or duplicate release asset: ' + name)
    return found[0]

def download_source(api, tag, destination='build'):
    """Manual test input only; scheduled runs still use the original Drive API."""
    api.assert_public()
    release = api.source_draft(tag)
    if not release or not release.get('draft'):
        raise ValueError('Manual source must be a private draft release')
    item = asset(release, 'HeroWars_GUSSAR.zip')
    if not 0 < item.get('size', 0) <= 2 * 1024**3:
        raise ValueError('Source asset size outside limits')
    directory = Path(destination)
    directory.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    total = 0
    with api.read_asset(item) as response, (directory / 'source.zip').open('wb') as output:
        while chunk := response.read(1024 * 1024):
            total += len(chunk)
            if total > item['size']:
                raise ValueError('Source download exceeds declared size')
            digest.update(chunk)
            output.write(chunk)
    if total != item['size'] or digest.hexdigest() != tag[7:]:
        raise ValueError('Manual source SHA-256 or size mismatch')
    (directory / 'source-metadata.json').write_text(json.dumps(
        {'origin': 'private GitHub draft for manual testing', 'source_sha256': digest.hexdigest()}), encoding='utf-8')
    return digest.hexdigest()

def record_of(api, release):
    with api.read_asset(asset(release, MANIFEST)) as response:
        record = json.load(response)
    for key in ('source_sha256', 'installer_sha256'):
        if not re.fullmatch('[a-f0-9]{64}', record.get(key, '')):
            raise ValueError('Invalid published manifest')
    expected = 'tm-' + record['source_sha256'] + '-' + record['installer_sha256']
    if expected != release['tag_name']:
        raise ValueError('Manifest does not match release identity')
    return record

def verify_asset(api, release, digest):
    with api.read_asset(asset(release, SETUP)) as response:
        if hashlib.file_digest(response, 'sha256').hexdigest() != digest:
            raise ValueError('Uploaded installer failed SHA-256 verification')

def prepare(api, manifest, installer, mode):
    if mode not in ('candidate', 'stage'):
        raise ValueError('Invalid preparation mode')
    api.assert_public()
    digest = sha256(installer)
    source = manifest['source_sha256']
    tag = 'tm-' + source + '-' + digest
    record = dict(manifest, installer_sha256=digest, run_url=os.environ['RUN_URL'])
    release = api.by_tag(tag)
    if not release:
        release = api.create(tag, 'Проверенная сборка установщика TitanMatik.\n\n'
                             'Source SHA-256: ' + source + '\nInstaller SHA-256: ' + digest +
                             '\nBuild: ' + os.environ['RUN_URL'])
    required = {SETUP: Path(installer).read_bytes(), MANIFEST: json.dumps(record, indent=2).encode(),
                'SHA256SUMS': (digest + '  ' + SETUP + '\n').encode()}
    # Resume a partial draft without deleting/replacing immutable uploaded assets.
    for name, data in required.items():
        if not any(item['name'] == name for item in release.get('assets', [])):
            api.upload(release, name, data)
    release = api.by_tag(tag)
    stored = record_of(api, release)
    if stored['source_sha256'] != source or stored['installer_sha256'] != digest:
        raise ValueError('Release identity collision')
    verify_asset(api, release, digest)
    if mode == 'stage':
        if release['draft']:
            release = api.patch(release, draft=False, prerelease=True, make_latest='false')
        api.verify_public(release, digest)
    return release

def promote(api, tag):
    if os.environ.get('PRODUCTION_ENABLED') != 'true':
        raise ValueError('Production release gate is closed')
    api.assert_public()
    release = api.by_tag(tag)
    if not release or release['draft']:
        raise ValueError('Promote requires an existing staged public release')
    record = record_of(api, release)
    verify_asset(api, release, record['installer_sha256'])
    api.verify_public(release, record['installer_sha256'])
    current = api.latest()
    if current and current['id'] == release['id']:
        return release
    previous = current['tag_name'] if current else 'none'
    # One GitHub update marks this verified prerelease as the latest stable release.
    return api.patch(release, prerelease=False, make_latest='true',
                     body=release.get('body', '') + '\n\nPrevious stable release: ' + previous)

def announce(api, release):
    current = api.latest()
    if not current or current['id'] != release['id']:
        raise ValueError('Only the latest stable release may be announced')
    release = current
    body = release.get('body', '')
    existing = MARKER.search(body)
    if existing:
        status = json.loads(existing.group(1))
        if status.get('status') == 'sent':
            return
        raise ValueError('Telegram delivery uncertain; inspect channel before retrying')
    # Workflow concurrency serializes this repo. Claim before sending, and never
    # automatically repeat ambiguous delivery. No extra database/storage is used.
    sending = '<!-- titanmatik-notification: {"status":"sending"} -->'
    api.patch(release, body=body + '\n' + sending)
    url = 'https://github.com/' + api.repo + '/releases/latest/download/' + SETUP
    message_id = send_message(os.environ['UPDATE_CHANNEL_ID'],
        '🔄 Обновление TitanMatik\n\nВышла новая версия программы.\n\n'
        'Как обновиться:\n1. Закройте TitanMatik.\n2. Скачайте установщик.\n'
        '3. Выберите папку существующей установки.\n\n'
        'Профили, настройки и лицензия сохраняются при корректном обновлении.\n\nСкачать: ' + url)
    sent = '<!-- titanmatik-notification: ' + json.dumps({'status': 'sent', 'message_id': message_id}) + ' -->'
    api.patch(release, body=body + '\n' + sent)

def main():
    import sys
    api = GitHub(os.environ['GITHUB_REPOSITORY'], os.environ['GH_TOKEN'])
    api.assert_public()
    command = sys.argv[1]
    if command == 'source':
        digest = download_source(api, os.environ['SOURCE_RELEASE_TAG'])
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('sha256=' + digest + '\n')
    elif command == 'check':
        current = api.latest()
        changed = not current or record_of(api, current)['source_sha256'] != os.environ['SOURCE_SHA']
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('changed=' + str(changed).lower() + '\n')
    elif command == 'prepare':
        mode = sys.argv[2]
        if mode == 'auto' and os.environ.get('PRODUCTION_ENABLED') != 'true':
            raise ValueError('Production release gate is closed')
        manifest = json.loads(Path('build/manifest.json').read_text(encoding='utf-8'))
        release = prepare(api, manifest, 'build/installer/' + SETUP, 'stage' if mode == 'auto' else mode)
        print('Verified release tag: ' + release['tag_name'])
        if mode == 'auto':
            announce(api, promote(api, release['tag_name']))
    elif command == 'promote':
        announce(api, promote(api, os.environ['RELEASE_TAG']))
    elif command == 'announce':
        if os.environ.get('PRODUCTION_ENABLED') != 'true':
            raise ValueError('Production release gate is closed')
        current = api.latest()
        if not current:
            raise ValueError('No stable release')
        announce(api, current)
    else:
        raise ValueError('Unknown command')

if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Release operation failed. Credentials and signed URLs suppressed; inspect the failed workflow step.')
        raise SystemExit(1)
