#!/usr/bin/env python3
"""Generate additive blue sprites with installed FFmpeg; verify pinned art bytes.

The linear luminance-to-blue matrix preserves alpha/silhouette and shading.
Original project assets and license remain unchanged. No runtime dependency.
"""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'resources/blue/artwork.json'
SOURCES = {
    'graphics/entities/computer_hr.png': ('graphics/entities/blue-computer_hr.png', 'bdddb9ec596d9f0a4ab96237b0de88021b8302391a9c4d1ccae55cf5314cf93d'),
    'graphics/icons/computer-icon.png': ('graphics/icons/blue-computer-icon.png', '1c9474ce622eb3e6ec305a3b99e4900175d543cce48c9a6bcd0638860a7fc4ec'),
}
FILTER = 'colorchannelmixer=rr=0.135:rg=0.265:rb=0.05:gr=0.269:gg=0.528:gb=0.103:br=0.463:bg=0.91:bb=0.177:aa=1'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dimensions(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and data[12:16] == b'IHDR', 'Invalid PNG'
    return list(struct.unpack('>II', data[16:24]))


def records(root=ROOT):
    result = []
    for source, (output, original) in SOURCES.items():
        assert digest(root / source) == original, f'Original artwork changed: {source}'
        assert dimensions(root / source) == dimensions(root / output), f'Geometry changed: {output}'
        assert digest(root / output) != original, f'Artwork is not distinct: {output}'
        result.append({'source': source, 'source_sha256': original, 'path': output,
                       'sha256': digest(root / output), 'dimensions': dimensions(root / output)})
    return {'format': 1, 'license': 'LICENSE', 'license_sha256': digest(root / 'LICENSE'),
            'transform': FILTER, 'files': result}


def verify(root=ROOT):
    assert json.loads((root / 'resources/blue/artwork.json').read_text()) == records(root), 'Blue artwork manifest is stale'
    return {'blue_artwork': len(SOURCES)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(verify(), indent=2))
        return
    for source, (output, original) in SOURCES.items():
        assert digest(ROOT / source) == original, f'Original artwork changed: {source}'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(ROOT / source),
                        '-vf', FILTER, '-frames:v', '1', '-threads', '1', '-pix_fmt', 'rgba',
                        str(ROOT / output)], check=True)
    # Verify the rendered pixel alpha, not just the PNG header/geometry.
    for source, (output, _) in SOURCES.items():
        pixels = []
        for path in (source, output):
            pixels.append(subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(ROOT / path),
                                          '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'],
                                         check=True, stdout=subprocess.PIPE).stdout)
        assert pixels[0][3::4] == pixels[1][3::4], f'Alpha changed: {output}'
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(records(), indent=2) + '\n')
    print(json.dumps(verify(), indent=2))


if __name__ == '__main__':
    main()
