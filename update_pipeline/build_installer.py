"""Generate explicit Inno file entries from the validated manifest."""
import json
import hashlib
import shutil
from pathlib import Path

def main():
    manifest = json.loads(Path('build/manifest.json').read_text(encoding='utf-8'))
    helper = 'TitanMatik.Update.ps1'
    for name in (helper, 'TitanMatik.ico'):
        source = Path('installer') / name
        if not source.is_file():
            raise ValueError('Missing TitanMatik packaging asset: ' + name)
        target = Path('build/payload') / name
        shutil.copyfile(source, target)
        manifest['files'] = [item for item in manifest['files'] if item['path'].casefold() != name.casefold()]
        manifest['files'].append({'path': name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(), 'size': target.stat().st_size})
    Path('build/manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    lines = []
    rollback = []
    snapshot = []
    for item in manifest['files']:
        p = item['path'].replace('/', '\\')
        # Escape Inno constants; ZIP validation already excludes quotes/control chars.
        p = p.replace('{', '{{')
        parent = str(Path(item['path']).parent).replace('/', '\\')
        dest = '{app}' if parent == '.' else '{app}\\' + parent.replace('{', '{{')
        # Only vendor binaries replace existing files. Other vendor defaults are first-install only.
        binary = Path(item['path']).suffix.lower() in ('.exe', '.dll', '.pdb') or item['path'] in (helper, 'TitanMatik.ico')
        flags = 'ignoreversion uninsneveruninstall' + ('' if binary else ' onlyifdoesntexist')
        lines.append(f'Source: "..\\build\\payload\\{p}"; DestDir: "{dest}"; Flags: {flags}')
        pascal = item['path'].replace('/', '\\').replace("'", "''")
        rollback.append(f"  RestoreFile('{pascal}');")
        snapshot.append(f"  RememberOriginal('{pascal}');")
    Path('installer/payload.iss').write_text('\n'.join(lines), encoding='utf-8-sig')
    Path('installer/rollback.iss').write_text('\n'.join(rollback), encoding='utf-8-sig')
    Path('installer/snapshot.iss').write_text('\n'.join(snapshot), encoding='utf-8-sig')

if __name__ == '__main__':
    main()
