"""Blue sprite provenance/geometry verification; not graphical-client acceptance."""
import json
import os
import shutil
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = runpy.run_path(str(ROOT / 'tools/blue_artwork.py'))
verify, SOURCES = TOOL['verify'], TOOL['SOURCES']


class BlueArtworkTests(unittest.TestCase):
    def test_checked_in_art_has_distinct_blue_files_and_pinned_originals(self):
        self.assertEqual(verify(ROOT), {'blue_artwork': 2})
        manifest = json.loads((ROOT / 'resources/blue/artwork.json').read_text())
        self.assertEqual([r['dimensions'] for r in manifest['files']], [[1000, 800], [32, 32]])
        for record in manifest['files']:
            self.assertNotEqual(record['source_sha256'], record['sha256'])

    def copy_fixture(self, root):
        paths = ['LICENSE', 'resources/blue/artwork.json']
        for source, (output, _) in SOURCES.items():
            paths.extend([source, output])
        for path in paths:
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / path, target)

    def test_verifier_uses_requested_root_and_refuses_changed_original_art(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            self.copy_fixture(root)
            self.assertEqual(verify(root), {'blue_artwork': 2})
            source = root / next(iter(SOURCES))
            source.write_bytes(source.read_bytes() + b'changed')
            with self.assertRaisesRegex(AssertionError, 'Original artwork changed'):
                verify(root)

    def test_geometry_and_manifest_mismatch_are_refused(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as directory:
            root = Path(directory)
            self.copy_fixture(root)
            source, (output, _) = next(iter(SOURCES.items()))
            (root / output).write_bytes((ROOT / 'graphics/icons/blue-computer-icon.png').read_bytes())
            with self.assertRaisesRegex(AssertionError, 'Geometry changed'):
                verify(root)
            shutil.copy2(ROOT / output, root / output)
            manifest = root / 'resources/blue/artwork.json'
            data = json.loads(manifest.read_text())
            data['files'][0]['sha256'] = '0' * 64
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(AssertionError, 'manifest is stale'):
                verify(root)


if __name__ == '__main__':
    unittest.main()
