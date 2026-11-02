"""Generate explicit Inno file entries from the validated manifest."""
import json
from pathlib import Path

def main():
    manifest = json.loads(Path('build/manifest.json').read_text(encoding='utf-8'))
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
        binary = Path(item['path']).suffix.lower() in ('.exe', '.dll', '.pdb')
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
