#!/usr/bin/env python3
"""Check the pinned guest resource allowlist without network access."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from guest_rom_source import render as render_guest_rom
from native_rom_source import verify as verify_native_rom
from shell_resources import verify as verify_shell_resources
from blue_artwork import verify as verify_blue_artwork

ROOT = Path(__file__).resolve().parents[1]


def verify(root=ROOT, upstream=None):
    manifest = json.loads((root / 'vendor/manifest.json').read_text())
    assert (root / 'scripts/guest/rom.lua').read_text() == render_guest_rom(root), 'Generated guest ROM is stale'
    assert manifest['format'] == 1
    paths = [record['path'] for record in manifest['files']]
    assert len(paths) == len(set(paths)), 'Duplicate resource record'
    patches = {patch['path']: patch for patch in manifest['patches']}
    expected = set(paths) | set(patches) | {'vendor/manifest.json', 'vendor/README.md'}
    actual = {str(path.relative_to(root)) for path in (root / 'vendor').rglob('*') if path.is_file()}
    assert actual == expected, f'Unlisted/missing vendor files: {actual ^ expected}'
    guest_paths = set()
    compiler_modules = {Path(path).stem for path in paths if path.startswith('vendor/phobos/') and path.endswith('.lua')}
    for record in manifest['files']:
        path = root / record['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record['sha256'], f'Changed resource: {path}'
        assert record['copyright'] and record['license'] and record['source_url']
        assert record['revision'] == manifest['projects'][record['project']]['revision']
        assert (root / record['license_path']).is_file()
        if upstream:
            source = subprocess.check_output(['git', '-C', str(upstream / record['project']), 'show', record['revision'] + ':' + record['source']])
            assert hashlib.sha256(source).hexdigest() == record['source_sha256'], f'Upstream hash mismatch: {path}'
            if 'patch' in record:
                patch = root / record['patch']
                text = patch.read_text()
                assert text.startswith('--- ' + record['source'] + '\n+++ ' + record['path'] + '\n')
                with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
                    original = Path(directory) / 'original.lua'
                    original.write_bytes(source)
                    result = subprocess.run(['patch', '--silent', '--fuzz=0', '--output=-', str(original)],
                                            input=text.encode(), capture_output=True, check=True)
                    assert result.stdout == path.read_bytes(), f'Patch does not reproduce resource: {path}'
            else:
                assert source == path.read_bytes()
        if record['path'].endswith('.lua') and record['project'] == 'phobos':
            for module in re.findall(r'\brequire\("([^"]+)"\)', path.read_text()):
                prefix = '__computer_core_2__.vendor.phobos.'
                assert module.startswith(prefix) and module[len(prefix):] in compiler_modules, module
        if 'guest_path' in record:
            assert record['guest_path'] not in guest_paths
            guest_paths.add(record['guest_path'])
    for excluded in manifest['excluded']:
        assert not any(record['source'].endswith('/' + excluded) or record['source'] == excluded for record in manifest['files']), excluded
    completion = (root / 'vendor/recrafted/rom/modules/main/cc/completion.lua').read_text()
    assert 'local peripheral = require("peripheral")' not in completion.split('function c.peripheral', 1)[0]
    assert 'local peripheral = require("peripheral")' in completion.split('function c.peripheral', 1)[1]
    assert not any(path.endswith(('.so', '.dll', '.exe')) for path in paths)
    return {'resources': len(paths), 'compiler_modules': len(compiler_modules), 'guest_files': len(guest_paths),
            'patches': len(patches), **verify_native_rom(root), **verify_shell_resources(root), **verify_blue_artwork(root)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream', type=Path, help='Directory holding the pinned phobos and recrafted Git checkouts')
    args = parser.parse_args()
    print(json.dumps(verify(upstream=args.upstream), indent=2))


if __name__ == '__main__':
    main()
