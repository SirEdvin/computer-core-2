"""Shell source/provenance contracts; engine acceptance is separate."""
import json
import os
from pathlib import Path
import runpy
import shutil
import tempfile
import unittest

TOOL = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'tools/shell_resources.py'))
ROOT, render, verify = (TOOL[name] for name in ('ROOT', 'render', 'verify'))


class ShellResourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        manifest = json.loads(render())
        paths = [r['path'] for r in manifest['files']]
        paths += ['LICENSE', 'vendor/manifest.json', 'scripts/guest/rom.lua', TOOL['MANIFEST']]
        for name in paths:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def test_deterministic_closed_source_inventory(self):
        self.assertEqual(render(self.root), render(self.root))
        self.assertEqual(verify(self.root), {'shell_sources': 8, 'shell_shared_modules': 5, 'shell_rom_adaptations': 0})
        manifest = json.loads(render(self.root))
        self.assertEqual(manifest['backend'], 'event-shell')
        self.assertEqual(manifest['execution'], 'trusted-built-ins-only')
        self.assertEqual(manifest['rom_adaptations'], [])
        self.assertEqual(len({r['path'] for r in manifest['files']}), len(manifest['files']))

    def test_changed_source_is_rejected(self):
        path = self.root / 'scripts/shell/resources.lua'
        path.write_text(path.read_text() + '-- changed\n')
        with self.assertRaisesRegex(AssertionError, 'provenance manifest is stale'):
            verify(self.root)

    def test_extra_source_is_rejected(self):
        (self.root / 'scripts/shell/plugin.lua').write_text('return {}\n')
        with self.assertRaisesRegex(AssertionError, 'source inventory'):
            verify(self.root)

    def test_missing_source_is_rejected(self):
        (self.root / 'scripts/shell/parser.lua').unlink()
        with self.assertRaisesRegex(AssertionError, 'source inventory'):
            verify(self.root)

    def test_changed_vm_rom_is_rejected(self):
        path = self.root / 'scripts/guest/rom.lua'
        path.write_text(path.read_text() + '-- changed\n')
        with self.assertRaisesRegex(AssertionError, 'provenance manifest is stale'):
            verify(self.root)

    def test_changed_license_is_rejected(self):
        (self.root / 'LICENSE').write_text('changed license\n')
        with self.assertRaisesRegex(AssertionError, 'provenance manifest is stale'):
            verify(self.root)


if __name__ == '__main__':
    unittest.main()
