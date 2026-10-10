#!/usr/bin/env python3
"""Record the direct shell's project-source inventory without adapting VM ROM."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHELL = ('budget.lua', 'directory.lua', 'file_job.lua', 'import.lua', 'parser.lua',
         'resources.lua', 'runtime.lua', 'scheduler.lua')
SHARED = ('scripts/filesystem.lua', 'scripts/util.lua', 'scripts/guest/events.lua',
          'scripts/guest/limits.lua', 'scripts/guest/terminal.lua')
MANIFEST = 'resources/shell/manifest.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render(root=ROOT):
    actual = {p.relative_to(root).as_posix() for p in (root / 'scripts/shell').rglob('*') if p.is_file()}
    expected = {'scripts/shell/' + name for name in SHELL}
    assert actual == expected, 'Unexpected shell source inventory: ' + str(actual ^ expected)
    records = [{'path': path, 'sha256': sha(root / path), 'license': 'MIT',
                'license_path': 'LICENSE', 'origin': 'project-authored' if path in expected else 'shared-project-module'}
               for path in sorted(expected | set(SHARED))]
    manifest = {'format': 1, 'backend': 'event-shell', 'execution': 'trusted-built-ins-only',
                'rom_adaptations': [], 'files': records,
                'license_sha256': sha(root / 'LICENSE'),
                'unchanged_vm_resources': {'manifest_path': 'vendor/manifest.json',
                                           'manifest_sha256': sha(root / 'vendor/manifest.json'),
                                           'rom_path': 'scripts/guest/rom.lua',
                                           'rom_sha256': sha(root / 'scripts/guest/rom.lua')}}
    return json.dumps(manifest, indent=2) + '\n'


def verify(root=ROOT):
    assert (root / MANIFEST).read_text() == render(root), 'Shell provenance manifest is stale'
    return {'shell_sources': len(SHELL), 'shell_shared_modules': len(SHARED), 'shell_rom_adaptations': 0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not args.check:
        path = ROOT / MANIFEST
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render())
    print(json.dumps(verify(), indent=2))


if __name__ == '__main__':
    main()
