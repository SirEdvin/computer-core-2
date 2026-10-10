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
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]

def fixture_mode(scenario):
    modes = {
        'legacy': ('tests/mod', 'CC2', 80, 60),
        'guest': ('tests/guest-mod', 'CC2 GUEST', 80, 60),
        'native': ('tests/native-mod', 'CC2 NATIVE', 600, 180),
        'shell': ('tests/shell-mod', 'CC2 SHELL', 120, 60),
        'shell-stress': ('tests/shell-stress-mod', 'CC2 SHELL STRESS', 40000, 600),
        'vm-benchmark': ('tests/vm-benchmark-mod', 'CC2 VM BENCH', 20000, 300),
        'workflow-benchmark': ('tests/workflow-benchmark-mod', 'CC2 WORKFLOW', 20000, 300),
    }
    if scenario not in modes:
        raise ValueError('Unknown fixture mode: ' + scenario)
    return modes[scenario]


def parse_benchmark_metrics(output):
    metrics = []
    for line in output.splitlines():
        marker = 'CC2 VM BENCH METRIC '
        if marker not in line:
            continue
        fields = dict(field.split('=', 1) for field in line.split(marker, 1)[1].split())
        if set(fields) != {'phase', 'ticks', 'instructions', 'collection_work'}:
            raise ValueError('Malformed benchmark metric: ' + line)
        metrics.append({key: value if key == 'phase' else int(value)
                        for key, value in fields.items()})
    return metrics


def parse_workflow_metrics(output):
    metrics = []
    fields_expected = {'phase', 'case', 'backend', 'sample', 'ticks', 'instructions',
                       'collection_work', 'collection_ticks', 'display_revisions',
                       'dirty_rows', 'activation_work'}
    fields_expected |= {name + '_work' for name in
                        ['compiler', 'string', 'terminal', 'filesystem', 'event',
                         'advance', 'table', 'continuation']}
    for line in output.splitlines():
        marker = 'CC2 WORKFLOW METRIC '
        if marker not in line:
            continue
        fields = dict(field.split('=', 1) for field in line.split(marker, 1)[1].split())
        if set(fields) != fields_expected:
            raise ValueError('Malformed workflow metric: ' + line)
        metric = {key: value if key in {'phase', 'case', 'backend'} else int(value)
                  for key, value in fields.items()}
        if metric['phase'] not in {'boot', 'launch', 'echo'} or metric['case'] not in {'shell', 'basic', 'advanced'} or metric['backend'] not in {'vm', 'native', 'shell'}:
            raise ValueError('Unknown workflow metric identity: ' + line)
        if metric['ticks'] < 1 or any(value < 0 for value in metric.values() if isinstance(value, int)):
            raise ValueError('Invalid workflow metric counter: ' + line)
        metrics.append(metric)
    return metrics


def parse_workflow_profiles(output):
    profiles = []
    for line in output.splitlines():
        marker = 'CC2 WORKFLOW PROFILE '
        if marker not in line:
            continue
        match = re.fullmatch(r'(.*?) Duration: ([0-9.]+)ms', line.split(marker, 1)[1].strip())
        if not match:
            raise ValueError('Malformed workflow profile: ' + line)
        fields = dict(field.split('=', 1) for field in match[1].split())
        expected = {'kind', 'backend', 'case'}
        if fields.get('kind') == 'scheduler':
            expected |= {'phase', 'tick'}
        if set(fields) != expected or fields['kind'] not in {'scheduler', 'creation', 'module-import', 'ingress'}:
            raise ValueError('Malformed workflow profile identity: ' + line)
        profile: dict[str, str | int | float] = dict(fields)
        if 'tick' in fields:
            profile['tick'] = int(fields['tick'])
        profile['milliseconds'] = float(match[2])
        profiles.append(profile)
    return profiles


def parse_workflow_diagnostics(output):
    """Strict test-observer records; never use them as performance acceptance."""
    result = {'allocations': [], 'resident': [], 'frames': [], 'summary': None, 'state': None}
    schemas = {
        'ALLOCATION': ('allocations', {'phase', 'source', 'proto', 'cells', 'other',
                      'steps', 'capture_bindings', 'new_captures', 'blocks'}),
        'RESIDENT': ('resident', {'phase', 'sample', 'resident_cells', 'resident_captured',
                    'resident_other', 'frames', 'temp_slots', 'temp_values', 'temp_refs',
                    'unique_temp_refs', 'nodes', 'partial'}),
        'AUDIT': ('summary', {'allocated', 'steps', 'rows'}),
        'FRAMES': ('frames', {'phase', 'sample', 'source', 'proto', 'frames', 'temp_slots', 'temp_values', 'temp_refs'}),
        'STATE': ('state', {'allocations', 'steps', 'objects', 'next_id', 'revision', 'tick'}),
    }
    seen = set()
    for line in output.splitlines():
        for kind, (target, expected) in schemas.items():
            marker = 'CC2 WORKFLOW ' + kind + ' '
            if marker not in line:
                continue
            tokens = line.split(marker, 1)[1].split()
            fields = dict(field.split('=', 1) for field in tokens)
            if set(fields) != expected or len(fields) != len(tokens):
                raise ValueError('Malformed workflow diagnostic: ' + line)
            record = {key: unquote(value) if key == 'source' else value if key == 'phase' else int(value)
                      for key, value in fields.items()}
            if any(value < 0 for value in record.values() if isinstance(value, int)):
                raise ValueError('Negative workflow diagnostic counter: ' + line)
            if 'phase' in fields and fields['phase'] not in {'setup', 'boot', 'launch', 'character', 'settle', 'erase', 'echo'}:
                raise ValueError('Unknown workflow diagnostic phase: ' + line)
            identity = (kind, record.get('phase'), record.get('source'), record.get('proto'), record.get('sample'))
            if identity in seen:
                raise ValueError('Duplicate workflow diagnostic: ' + line)
            seen.add(identity)
            if target in {'summary', 'state'}:
                result[target] = record
            else:
                result[target].append(record)
                if len(result[target]) > (128 if target == 'resident' else 8192):
                    raise ValueError('Workflow diagnostic record bound exceeded')
    return result


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
    scenarios = parser.add_mutually_exclusive_group()
    scenarios.add_argument('--guest', action='store_true', help='Run the isolated guest feasibility scenario (not client acceptance)')
    scenarios.add_argument('--native', action='store_true', help='Run exact-engine native-load/persistence probes (not a completed runtime)')
    scenarios.add_argument('--shell', action='store_true', help='Run isolated direct event-shell regressions (not client acceptance)')
    parser.add_argument('--shell-config-change', action='store_true', help='Upgrade only the shell test fixture between processes to exercise a real configuration change')
    scenarios.add_argument('--shell-stress', action='store_true', help='Run maximum admitted shell jobs beside an interactive VM on real ticks')
    scenarios.add_argument('--vm-benchmark', action='store_true', help='Measure shipped VM workflows with one dispatch per simulation tick (not client latency)')
    scenarios.add_argument('--workflow-benchmark', action='store_true', help='Matched single cold-process shell/editor benchmark (not client latency)')
    parser.add_argument('--benchmark-backend', choices=['vm', 'native', 'shell'], default='native')
    parser.add_argument('--benchmark-case', choices=['shell', 'basic', 'advanced'], default='shell')
    parser.add_argument('--benchmark-characters', type=int, default=100)
    parser.add_argument('--benchmark-diagnostics', action='store_true', help='Test-only bounded native allocation/retention observers; timings include observer overhead')
    parser.add_argument('--columns', type=int, help='Override guest startup columns in the isolated test mod')
    parser.add_argument('--rows', type=int, help='Override guest startup rows in the isolated test mod')
    parser.add_argument('--reload-columns', type=int, help='Change real guest startup columns between engine processes')
    parser.add_argument('--reload-rows', type=int, help='Change real guest startup rows between engine processes')
    parser.add_argument('--archive', type=Path, help='Test packaged mod rather than the source checkout')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    scenario = 'guest' if args.guest else 'native' if args.native else 'shell-stress' if args.shell_stress else 'shell' if args.shell else 'vm-benchmark' if args.vm_benchmark else 'workflow-benchmark' if args.workflow_benchmark else 'legacy'
    if args.benchmark_characters < 1:
        parser.error('Benchmark character count must be positive')
    if args.shell_config_change and not args.shell:
        parser.error('--shell-config-change requires --shell')
    if args.benchmark_backend == 'shell' and (not args.workflow_benchmark or args.benchmark_case != 'shell'):
        parser.error('Direct shell benchmarking requires --workflow-benchmark --benchmark-case shell')
    if args.benchmark_diagnostics and (not args.workflow_benchmark or args.benchmark_backend != 'native' or args.benchmark_characters > 100):
        parser.error('Allocation diagnostics require native --workflow-benchmark and at most 100 characters')
    fixture_directory, prefix, until_tick, phase_timeout = fixture_mode(scenario)
    columns = args.columns if args.columns is not None else 51
    rows = args.rows if args.rows is not None else 19
    reload_columns = args.reload_columns if args.reload_columns is not None else columns
    reload_rows = args.reload_rows if args.reload_rows is not None else rows
    if any(value is not None for value in [args.columns, args.rows, args.reload_columns, args.reload_rows]) and not (args.guest or args.native):
        parser.error('Dimension overrides require --guest or --native')
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
    test_source = ROOT / fixture_directory
    test_info = json.loads((test_source / 'info.json').read_text())
    test_dir = base / 'mods' / f'{test_info["name"]}_{test_info["version"]}'
    shutil.copytree(test_source, test_dir, dirs_exist_ok=True)
    if args.workflow_benchmark:
        (test_dir / 'benchmark_config.lua').write_text(
            f'return {{backend="{args.benchmark_backend}",case="{args.benchmark_case}",characters={args.benchmark_characters},diagnostics={str(args.benchmark_diagnostics).lower()}}}\n')
    # Exercise repository-only examples against the packaged runtime.
    if args.archive:
        with zipfile.ZipFile(args.archive) as archive:
            gui_source = archive.read(f"{mod_name}/scripts/gui.lua").decode()
            assert json.loads(archive.read(f"{mod_name}/info.json")) == info
            assert not any(("/docs/" in name and name != f'{mod_name}/docs/SHELL_RUNTIME.md') or "/examples/" in name or (name.endswith("/README.md") and name != f'{mod_name}/vendor/README.md') for name in archive.namelist())
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
    if args.native:
        (test_dir / 'settings-updates.lua').write_text(
            f'data.raw["int-setting"]["computer-core-terminal-columns"].default_value = {columns}\n'
            f'data.raw["int-setting"]["computer-core-terminal-rows"].default_value = {rows}\n')
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
        deadline = time.monotonic() + phase_timeout
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
    run('bootstrap', ['--create', str(base / 'initial.zip'), '--map-gen-seed', '42'], [prefix + ' BOOTSTRAP PASS'])
    first = run('first', ['--start-server', str(base / 'initial.zip'), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', str(until_tick)], [prefix + ' SNAPSHOT', prefix + ' COMPLETE FIRST'])
    save = base / 'write/saves/cc2-resume.zip'
    if not save.exists():
        raise SystemExit('Engine did not produce the requested save: ' + str(save))
    if (args.guest or args.native) and (columns != reload_columns or rows != reload_rows):
        # A real data-stage constraint change forces saved startup values to the
        # new supported dimensions; do not substitute fixture dimensions at runtime.
        (test_dir / 'settings-updates.lua').write_text('\n'.join(
            f'data.raw["int-setting"]["computer-core-terminal-{name}"].{field} = {literal}'
            for name, value in [('columns', reload_columns), ('rows', reload_rows)]
            for field, literal in [('default_value', str(value)), ('allowed_values', f'{{{value}}}')]) + '\n')
    if args.shell_config_change:
        assert test_info['version'] == '0.0.1', 'Unexpected shell fixture version'
        test_info['version'] = '0.0.2'
        (test_dir / 'info.json').write_text(json.dumps(test_info, indent=2) + '\n')
        test_dir = test_dir.rename(test_dir.parent / f'{test_info["name"]}_{test_info["version"]}')
    reload = run('reload', ['--start-server', str(save), '--server-settings', str(base / 'server.json'), '--bind', '127.0.0.1', '--port', '0', '--until-tick', str(until_tick)], [prefix + ' COMPLETE RELOAD'])
    if args.shell_config_change:
        assert 'CC2 BLUE CONFIGURATION CHANGED' not in first and reload.count('CC2 BLUE CONFIGURATION CHANGED') == 1, 'Missing/duplicate configuration change'
    if scenario != 'legacy':
        assert prefix + ' COMPLETE RELOAD' not in first, 'Reload acceptance ran in the first process'
        assert prefix + ' COMPLETE FIRST' not in reload, 'Reload rebooted the scenario'
    counts = []
    for output in [first, reload]:
        match = re.search(re.escape(prefix) + r' COMPLETE \w+ checks=(\d+)', output)
        assert match is not None, 'Missing completion count'
        counts.append(int(match.group(1)))
    summary = {'engine': '2.0.77', 'scenario': scenario, 'expansion': args.expansion, 'first_checks': counts[0], 'reload_checks': counts[1], 'save': str(save), 'logs': str(base)}
    if args.shell:
        summary['configuration_change_verified'] = args.shell_config_change
    if args.vm_benchmark:
        summary['metrics'] = parse_benchmark_metrics(first)
        assert summary['metrics'], 'No simulation-tick benchmark metrics'
        summary['client_latency_verified'] = False
    if args.workflow_benchmark:
        summary['backend'] = args.benchmark_backend
        summary['case'] = args.benchmark_case
        summary['metrics'] = parse_workflow_metrics(first)
        summary['profiles'] = parse_workflow_profiles(first)
        summary['diagnostics_enabled'] = args.benchmark_diagnostics
        summary['diagnostics'] = parse_workflow_diagnostics(first)
        if args.benchmark_diagnostics:
            assert summary['diagnostics']['summary'] and summary['diagnostics']['state'], 'Missing allocation audit completion'
            assert len(summary['diagnostics']['resident']) == 1 + (args.benchmark_case != 'shell') + args.benchmark_characters, 'Missing resident snapshots'
        expected = 1 + (args.benchmark_case != 'shell') + args.benchmark_characters
        assert len(summary['metrics']) == expected, 'Missing or duplicated workflow samples'
        assert [m['sample'] for m in summary['metrics'] if m['phase'] == 'echo'] == list(range(1, args.benchmark_characters + 1)), 'Missing or duplicated character samples'
        assert all(m['backend'] == args.benchmark_backend and m['case'] == args.benchmark_case for m in summary['metrics']), 'Wrong workflow identity'
        summary['client_latency_verified'] = False
    summary['processes'] = phase_evidence
    if args.guest or args.native:
        summary['terminal'] = {'columns': columns, 'rows': rows}
        summary['reload_terminal'] = {'columns': reload_columns, 'rows': reload_rows}
    (base / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    main()
