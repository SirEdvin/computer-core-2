#!/usr/bin/env python3
"""Run real Factorio bootstrap, tick and save/reload regressions in isolation."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import queue
import signal
import threading
import time
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--factorio', default=os.environ.get('FACTORIO_BIN', '/home/siredvin/tools/factorio/bin/x64/factorio'))
    parser.add_argument('--expansion', action='store_true')
    parser.add_argument('--archive', type=Path, help='Test packaged mod rather than the source checkout')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = Path(args.factorio).resolve()
    version = subprocess.check_output([str(binary), '--version'], text=True)
    if 'Version: 2.0.77 ' not in version:
        raise SystemExit('Tests are pinned to Factorio 2.0.77; found ' + version)
    base = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='cc2-tests-', dir=os.environ.get('TMPDIR')))
    base.mkdir(parents=True, exist_ok=True)
    (base / 'mods').mkdir(exist_ok=True)
    (base / 'write/saves').mkdir(parents=True, exist_ok=True)
    info = json.loads((ROOT / 'info.json').read_text())
    mod_name = f'{info["name"]}_{info["version"]}'
    if args.archive:
        shutil.copy2(args.archive, base / 'mods' / f'{mod_name}.zip')
    else:
        link = base / 'mods' / mod_name
        if not link.exists():
            link.symlink_to(ROOT, target_is_directory=True)
    test_info = json.loads((ROOT / 'tests/mod/info.json').read_text())
    test_dir = base / 'mods' / f'{test_info["name"]}_{test_info["version"]}'
    shutil.copytree(ROOT / 'tests/mod', test_dir, dirs_exist_ok=True)
    # Exercise the exact shipped example sources in the actual sandbox.
    fixtures = ['return {']
    for path in sorted((ROOT / 'examples').glob('*.lua')):
        source = path.read_text()
        separator = '='
        while f']{separator}]' in source:
            separator += '='
        fixtures.append(f'["{path.stem}"] = [{separator}[{source}]{separator}],')
    fixtures.append('}')
    (test_dir / 'examples.lua').write_text('\n'.join(fixtures))
    mods = [{'name': 'base', 'enabled': True}, {'name': 'computer_core_2', 'enabled': True}, {'name': 'computer_core_2_tests', 'enabled': True}]
    mods += [{'name': name, 'enabled': args.expansion} for name in ['quality', 'elevated-rails', 'space-age']]
    (base / 'mods/mod-list.json').write_text(json.dumps({'mods': mods}))
    (base / 'config.ini').write_text('[path]\nread-data=' + str(binary.parents[2] / 'data') + '\nwrite-data=' + str(base / 'write') + '\n[other]\ncheck-updates=false\n')
    settings = {'name': 'Computer Core 2 isolated regression', 'description': 'Local automated test', 'visibility': {'public': False, 'lan': False}, 'require_user_verification': False, 'auto_pause': False, 'autosave_interval': 0, 'allow_commands': 'admins-only'}
    (base / 'server.json').write_text(json.dumps(settings))
    common = [str(binary), '--config', str(base / 'config.ini'), '--mod-directory', str(base / 'mods')]
    def run(label, command, markers):
        process = subprocess.Popen(common + command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lines = []
        events = queue.Queue()
        def reader():
            assert process.stdout is not None
            for line in process.stdout:
                lines.append(line)
                events.put(line)
            events.put(None)
        thread = threading.Thread(target=reader, daemon=True)
        thread.start()
        deadline = time.monotonic() + 60
        completed = False
        try:
            while time.monotonic() < deadline:
                try:
                    line = events.get(timeout=max(0.1, deadline - time.monotonic()))
                except queue.Empty:
                    break
                if line is None:
                    break
                if 'CC2 ' in line or 'Error' in line:
                    print(line.rstrip(), flush=True)
                if '--start-server' in command and all(marker in ''.join(lines) for marker in markers):
                    completed = True
                    process.send_signal(signal.SIGINT)
                    break
            if process.poll() is None:
                if not completed:
                    process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            thread.join(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        output = ''.join(lines)
        (base / (label + '.log')).write_text(output)
        if process.returncode != 0 or any(marker not in output for marker in markers):
            print(output[-12000:])
            raise SystemExit(f'{label} FAILED (exit {process.returncode}); log: {base / (label + ".log")}')
        return output
    run('bootstrap', ['--create', str(base / 'initial.zip'), '--map-gen-seed', '42'], ['CC2 BOOTSTRAP PASS'])
    first = run('first', ['--start-server', str(base / 'initial.zip'), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', '80'], ['CC2 SNAPSHOT', 'CC2 COMPLETE FIRST'])
    save = base / 'write/saves/cc2-resume.zip'
    if not save.exists():
        raise SystemExit('Engine did not produce the requested save: ' + str(save))
    reload = run('reload', ['--start-server', str(save), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', '80'], ['CC2 COMPLETE RELOAD'])
    counts = []
    for output in [first, reload]:
        match = re.search(r'CC2 COMPLETE \w+ checks=(\d+)', output)
        assert match is not None, 'Missing completion count'
        counts.append(int(match.group(1)))
    summary = {'engine': '2.0.77', 'expansion': args.expansion, 'first_checks': counts[0], 'reload_checks': counts[1], 'save': str(save), 'logs': str(base)}
    (base / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    main()
