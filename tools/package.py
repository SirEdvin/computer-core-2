#!/usr/bin/env python3
"""Build a deterministic, self-contained Factorio mod archive (stdlib only)."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    info = json.loads((ROOT / 'info.json').read_text())
    prefix = f'{info["name"]}_{info["version"]}'
    files = [ROOT / name for name in ['info.json', 'data.lua', 'control.lua', 'LICENSE']]
    for directory in ['scripts', 'graphics', 'locale']:
        files.extend(path for path in (ROOT / directory).rglob('*') if path.is_file())
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f'{prefix}.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED) as out:
        for path in sorted(files):
            entry = zipfile.ZipInfo(f'{prefix}/{path.relative_to(ROOT).as_posix()}', (2020, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            out.writestr(entry, path.read_bytes())
    with zipfile.ZipFile(archive) as check:
        assert check.testzip() is None, 'Corrupt archive'
        assert json.loads(check.read(f'{prefix}/info.json')) == info
        assert not any('/tests/' in name or '/.git/' in name or '/docs/' in name or '/examples/' in name or name.endswith('/README.md') for name in check.namelist())
        count = len(check.namelist())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n')
    print(json.dumps({'archive': str(archive.resolve()), 'files': count, 'sha256': digest}, indent=2))


if __name__ == '__main__':
    main()
