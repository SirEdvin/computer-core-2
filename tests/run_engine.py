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
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def stop_engine(process, lines, timeout=15, retry_after=1, console=False):
    """Prefer orderly console quit; interrupt only unacknowledged shutdowns."""
    evidence = {'console_quit_sent': False, 'signals_sent': 0, 'acknowledged': False, 'forced_kill': False}
    if console and process.poll() is None and process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.write('/quit\n')
            process.stdin.flush()
            evidence['console_quit_sent'] = True
        except BrokenPipeError:
            pass
    def acknowledged():
        return any('Received SIGINT' in line or 'Quitting: signal.' in line or 'Quitting: remote-quit.' in line for line in lines)
    start = time.monotonic()
    deadline = start + timeout
    last_request = start
    while process.poll() is None:
        evidence['acknowledged'] = acknowledged()
        now = time.monotonic()
        if now >= deadline:
            evidence['forced_kill'] = True
            process.kill()
            process.wait()
            break
        if not evidence['acknowledged'] and evidence['signals_sent'] < 2 and (
                not evidence['console_quit_sent'] and evidence['signals_sent'] == 0
                or now - last_request >= retry_after):
            try:
                process.send_signal(signal.SIGINT)
                evidence['signals_sent'] += 1
                last_request = now
            except ProcessLookupError:
                pass
        try:
            process.wait(timeout=min(0.05, max(0.001, deadline - time.monotonic())))
        except subprocess.TimeoutExpired:
            pass
    evidence['acknowledged'] = acknowledged()
    evidence['exit_code'] = process.returncode
    if process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.close()
        except BrokenPipeError:
            pass
    return evidence

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--factorio', default=os.environ.get('FACTORIO_BIN', '/home/siredvin/tools/factorio/bin/x64/factorio'))
    parser.add_argument('--expansion', action='store_true')
    parser.add_argument('--guest', action='store_true', help='Run the isolated guest feasibility scenario (not client acceptance)')
    parser.add_argument('--columns', type=int, help='Override guest startup columns in the isolated test mod')
    parser.add_argument('--rows', type=int, help='Override guest startup rows in the isolated test mod')
    parser.add_argument('--reload-columns', type=int, help='Change real guest startup columns between engine processes')
    parser.add_argument('--reload-rows', type=int, help='Change real guest startup rows between engine processes')
    parser.add_argument('--archive', type=Path, help='Test packaged mod rather than the source checkout')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    columns = args.columns if args.columns is not None else 51
    rows = args.rows if args.rows is not None else 19
    reload_columns = args.reload_columns if args.reload_columns is not None else columns
    reload_rows = args.reload_rows if args.reload_rows is not None else rows
    if any(value is not None for value in [args.columns, args.rows, args.reload_columns, args.reload_rows]) and not args.guest:
        parser.error('Dimension overrides require --guest')
    if not 1 <= columns <= 160 or not 1 <= reload_columns <= 160:
        parser.error('Columns must be within the model bounds 1..160')
    if not 1 <= rows <= 60 or not 1 <= reload_rows <= 60:
        parser.error('Rows must be within the model bounds 1..60')
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
    test_source = ROOT / ('tests/guest-mod' if args.guest else 'tests/mod')
    test_info = json.loads((test_source / 'info.json').read_text())
    test_dir = base / 'mods' / f'{test_info["name"]}_{test_info["version"]}'
    shutil.copytree(test_source, test_dir, dirs_exist_ok=True)
    # Exercise repository-only examples against the packaged runtime.
    if args.archive:
        with zipfile.ZipFile(args.archive) as archive:
            gui_source = archive.read(f"{mod_name}/scripts/gui.lua").decode()
            assert json.loads(archive.read(f"{mod_name}/info.json")) == info
            assert not any("/docs/" in name or "/examples/" in name or (name.endswith("/README.md") and name != f"{mod_name}/vendor/README.md") for name in archive.namelist())
    else:
        gui_source = (ROOT / "scripts/gui.lua").read_text()
    sep = "="
    while f"]{sep}]" in gui_source:
        sep += "="
    (test_dir / "gui_source.lua").write_text(f"return [{sep}[{gui_source}]{sep}]\n")
    fixtures = ['return {']
    for path in sorted((ROOT / 'examples').glob('*.lua')):
        source = path.read_text()
        separator = '='
        while f']{separator}]' in source:
            separator += '='
        fixtures.append(f'["{path.stem}"] = [{separator}[{source}]{separator}],')
    fixtures.append('}')
    (test_dir / 'examples.lua').write_text('\n'.join(fixtures))
    if args.guest:
        fixtures = ['return {']
        (test_dir / 'guest_settings.lua').write_text(f'return {{columns={columns},rows={rows},reload_columns={reload_columns},reload_rows={reload_rows}}}\n')
        (test_dir / 'settings-updates.lua').write_text(
            f'data.raw["int-setting"]["computer-core-terminal-columns"].default_value = {columns}\n'
            f'data.raw["int-setting"]["computer-core-terminal-rows"].default_value = {rows}\n')
        for path in sorted((ROOT / 'tests/guest-fixtures').glob('*.lua')):
            source = path.read_text()
            separator = '='
            while f']{separator}]' in source:
                separator += '='
            fixtures.append(f'{{path={json.dumps(path.name)},source=[{separator}[{source}]{separator}]}},')
        assert len(fixtures) > 1, 'No guest fixtures found'
        fixtures.append('}')
        (test_dir / 'guest_fixtures.lua').write_text('\n'.join(fixtures))
    mods = [{'name': 'base', 'enabled': True}, {'name': 'computer_core_2', 'enabled': True}, {'name': test_info['name'], 'enabled': True}]
    mods += [{'name': name, 'enabled': args.expansion} for name in ['quality', 'elevated-rails', 'space-age']]
    (base / 'mods/mod-list.json').write_text(json.dumps({'mods': mods}))
    (base / 'config.ini').write_text('[path]\nread-data=' + str(binary.parents[2] / 'data') + '\nwrite-data=' + str(base / 'write') + '\n[other]\ncheck-updates=false\n')
    settings = {'name': 'Computer Core 2 isolated regression', 'description': 'Local automated test', 'visibility': {'public': False, 'lan': False}, 'require_user_verification': False, 'auto_pause': False, 'autosave_interval': 0, 'allow_commands': 'admins-only'}
    (base / 'server.json').write_text(json.dumps(settings))
    common = [str(binary), '--config', str(base / 'config.ini'), '--mod-directory', str(base / 'mods')]
    phase_evidence = {}
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
                    line = events.get(timeout=0.1)
                except queue.Empty:
                    line = ''
                if line is None:
                    # EOF can precede the child's final exit. Reap naturally
                    # within the original deadline before requesting shutdown.
                    try:
                        process.wait(timeout=max(0.001, deadline - time.monotonic()))
                    except subprocess.TimeoutExpired:
                        pass
                    break
                if 'CC2 ' in line or 'Error' in line:
                    print(line.rstrip(), flush=True)
                if '--start-server' in command and all(marker in ''.join(lines) for marker in markers):
                    # server_save is queued; the script marker precedes persistence.
                    # Do not interrupt the engine until its requested ZIP is readable.
                    if label == 'first' and not zipfile.is_zipfile(base / 'write/saves/cc2-resume.zip'):
                        continue
                    completed = True
                    break
            shutdown = stop_engine(process, lines, console=completed)
            thread.join(timeout=5)
            # The reader may observe the final acknowledgement after wait returns.
            shutdown['acknowledged'] = any('Received SIGINT' in line or 'Quitting: signal.' in line or 'Quitting: remote-quit.' in line for line in lines)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        output = ''.join(lines)
        (base / (label + '.log')).write_text(output)
        evidence = {'markers_present': all(marker in output for marker in markers),
                    'completion_requested_shutdown': completed, 'shutdown': shutdown}
        phase_evidence[label] = evidence
        (base / (label + '.process.json')).write_text(json.dumps(evidence, indent=2) + '\n')
        if process.returncode != 0 or shutdown['forced_kill'] or not evidence['markers_present']:
            print(output[-12000:])
            raise SystemExit(f'{label} FAILED (exit {process.returncode}); log: {base / (label + ".log")}')
        return output
    prefix = 'CC2 GUEST' if args.guest else 'CC2'
    run('bootstrap', ['--create', str(base / 'initial.zip'), '--map-gen-seed', '42'], [prefix + ' BOOTSTRAP PASS'])
    first = run('first', ['--start-server', str(base / 'initial.zip'), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', '80'], [prefix + ' SNAPSHOT', prefix + ' COMPLETE FIRST'])
    save = base / 'write/saves/cc2-resume.zip'
    if not save.exists():
        raise SystemExit('Engine did not produce the requested save: ' + str(save))
    if args.guest and (columns != reload_columns or rows != reload_rows):
        # A real data-stage constraint change forces saved startup values to the
        # new supported dimensions; do not substitute fixture dimensions at runtime.
        (test_dir / 'settings-updates.lua').write_text('\n'.join(
            f'data.raw["int-setting"]["computer-core-terminal-{name}"].{field} = {literal}'
            for name, value in [('columns', reload_columns), ('rows', reload_rows)]
            for field, literal in [('default_value', str(value)), ('allowed_values', f'{{{value}}}')]) + '\n')
    reload = run('reload', ['--start-server', str(save), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', '80'], [prefix + ' COMPLETE RELOAD'])
    if args.guest:
        assert prefix + ' COMPLETE RELOAD' not in first, 'Reload acceptance ran in the first process'
        assert prefix + ' COMPLETE FIRST' not in reload, 'Reload rebooted the scenario'
    counts = []
    for output in [first, reload]:
        match = re.search(re.escape(prefix) + r' COMPLETE \w+ checks=(\d+)', output)
        assert match is not None, 'Missing completion count'
        counts.append(int(match.group(1)))
    summary = {'engine': '2.0.77', 'scenario': 'guest' if args.guest else 'legacy', 'expansion': args.expansion, 'first_checks': counts[0], 'reload_checks': counts[1], 'save': str(save), 'logs': str(base)}
    summary['processes'] = phase_evidence
    if args.guest:
        summary['terminal'] = {'columns': columns, 'rows': rows}
        summary['reload_terminal'] = {'columns': reload_columns, 'rows': reload_rows}
    (base / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    main()
