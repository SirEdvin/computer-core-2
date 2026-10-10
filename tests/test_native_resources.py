"""Native source-overlay provenance and refusal checks (not engine acceptance)."""
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
import runpy

resource_tool = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'tools/native_rom_source.py'))
ROOT, render, verify = (resource_tool[name] for name in ('ROOT', 'render', 'verify'))


class NativeResourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for directory in ('vendor', 'resources/native'):
            shutil.copytree(ROOT / directory, self.root / directory)
        (self.root / 'scripts/native').mkdir(parents=True)
        shutil.copyfile(ROOT / 'scripts/native/rom.lua', self.root / 'scripts/native/rom.lua')

    def test_inventory_provenance_and_deterministic_generation(self):
        first = render(self.root)
        self.assertEqual(first, render(self.root))
        self.assertEqual(verify(self.root), {'native_guest_files': 64, 'native_patches': 3})
        manifest = json.loads(first[1])
        changed = {r['guest_path'] for r in manifest['files'] if r['sha256'] != r['baseline_sha256']}
        self.assertEqual(changed, {'/rc/editors/basic.lua', '/rc/editors/advanced.lua', '/rc/modules/main/rc/io.lua'})
        for record in manifest['files']:
            self.assertEqual((ROOT / record['path']).read_bytes(), (self.root / record['path']).read_bytes())

    def test_stale_native_rom_is_rejected(self):
        path = self.root / 'scripts/native/rom.lua'
        path.write_text(path.read_text() + '-- stale\n')
        with self.assertRaisesRegex(AssertionError, 'native ROM is stale'):
            verify(self.root)

    def test_unlisted_patch_is_rejected(self):
        (self.root / 'resources/native/patches/extra.patch').write_text('invalid')
        with self.assertRaisesRegex(AssertionError, 'patch inventory'):
            render(self.root)

    def test_changed_baseline_is_rejected(self):
        path = self.root / 'vendor/recrafted/rom/editors/basic.lua'
        path.write_text(path.read_text() + '-- changed\n')
        with self.assertRaisesRegex(AssertionError, 'baseline resource changed'):
            render(self.root)

    def test_stale_provenance_is_rejected(self):
        path = self.root / 'resources/native/manifest.json'
        path.write_text('{}\n')
        with self.assertRaisesRegex(AssertionError, 'provenance manifest is stale'):
            verify(self.root)


if __name__ == '__main__':
    unittest.main()
