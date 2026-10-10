#!/usr/bin/env python3
"""Serial paired cold-process matrix. Failed gates never become rollout approval."""
import argparse
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
CASES = ('shell', 'basic', 'advanced')
BACKENDS = ('vm', 'native')


def distribution(values):
    if not values:
        return None
    ordered = sorted(values)
    return {'samples': len(values), 'median': statistics.median(ordered),
            'p95': ordered[math.ceil(0.95 * len(ordered)) - 1],
            'minimum': ordered[0], 'maximum': ordered[-1]}


def summarize(runs, trials, characters, cases=CASES, backends=BACKENDS):
    identities = [(r['trial'], r['case'], r['backend']) for r in runs]
    if len(set(identities)) != len(identities):
        raise ValueError('Duplicate cold-process identity in workflow matrix')
    report = {'requested_trials_per_case_backend': trials,
              'characters_per_cold_process': characters,
              'runs': runs, 'failures': [r for r in runs if r['exit_code'] != 0],
              'workflows': {}, 'gates': {}, 'client_latency_verified': False,
              'mixed_backend_neighbor_verified': False}
    results = [r['result'] for r in runs if r['exit_code'] == 0]
    for case in cases:
        workflow = {}
        for backend in backends:
            selected = [r for r in results if r['case'] == case and r['backend'] == backend]
            metrics = [m for r in selected for m in r['metrics']]
            profiles = [p for r in selected for p in r['profiles']]
            cold = [sum(p['milliseconds'] for p in r['profiles']
                        if p['kind'] in {'module-import', 'creation'} or p.get('phase') == 'boot')
                    for r in selected
                    if {'module-import', 'creation'} <= {p['kind'] for p in r['profiles']}
                    and any(p['kind'] == 'scheduler' and p.get('phase') == 'boot' for p in r['profiles'])]
            workflow[backend] = {
                'completed_processes': len(selected),
                'boot_ticks': distribution([m['ticks'] for m in metrics if m['phase'] == 'boot']),
                'launch_ticks': distribution([m['ticks'] for m in metrics if m['phase'] == 'launch']),
                'echo_ticks': distribution([m['ticks'] for m in metrics if m['phase'] == 'echo']),
                'scheduler_ms': distribution([p['milliseconds'] for p in profiles if p['kind'] == 'scheduler']),
                'module_import_ms': distribution([p['milliseconds'] for p in profiles if p['kind'] == 'module-import']),
                'creation_ms': distribution([p['milliseconds'] for p in profiles if p['kind'] == 'creation']),
                'ingress_ms': distribution([p['milliseconds'] for p in profiles if p['kind'] == 'ingress']),
                'cold_profiled_startup_ms': distribution(cold),
            }
        report['workflows'][case] = workflow
        vm, native = workflow['vm'], workflow[backends[1]]
        gates = {}
        for phase in ('boot', 'launch'):
            if phase == 'launch' and case == 'shell':
                continue
            before, after = vm[phase + '_ticks'], native[phase + '_ticks']
            ratio = before['median'] / after['median'] if before and after else None
            gates[phase + '_speedup'] = ratio
            gates[phase + '_2x_passed'] = ratio is not None and ratio >= 2
        gates['native_echo_p95_2_ticks_passed'] = native['echo_ticks'] is not None and native['echo_ticks']['p95'] <= 2
        gates['sample_count_passed'] = all(
            workflow[b]['completed_processes'] >= 10
            and workflow[b]['echo_ticks'] is not None
            and workflow[b]['echo_ticks']['samples'] >= 100 for b in backends)
        report['gates'][case] = gates
    report['matrix_complete'] = len(runs) == trials * len(cases) * len(backends) and not report['failures']
    report['selected_cases'] = list(cases)
    report['selected_backends'] = list(backends)
    report['rewritten_shell_not_identical_rom'] = 'shell' in backends
    report['headless_performance_passed'] = report['matrix_complete'] and all(
        value for gates in report['gates'].values() for key, value in gates.items() if key.endswith('_passed'))
    report['rollout_allowed'] = False
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--trials', type=int, default=10)
    parser.add_argument('--characters', type=int, default=10)
    parser.add_argument('--factorio', default=os.environ.get('FACTORIO_BIN', '/home/siredvin/tools/factorio/bin/x64/factorio'))
    parser.add_argument('--expansion', action='store_true')
    parser.add_argument('--shell-only', action='store_true', help='Compare original VM shell with rewritten direct shell; preserve historical editor matrix')
    args = parser.parse_args()
    if args.trials < 1 or args.characters < 1:
        parser.error('Trial and character counts must be positive')
    base = args.output.resolve()
    base.mkdir(parents=True, exist_ok=True)
    if (base / 'report.json').exists():
        parser.error('Choose a fresh output directory; prior evidence must be retained')
    runs = []
    cases = ('shell',) if args.shell_only else CASES
    backends = ('vm', 'shell') if args.shell_only else BACKENDS
    for trial in range(1, args.trials + 1):
        for case in cases:
            for backend in backends:
                target = base / f'{trial:02d}-{case}-{backend}'
                command = [sys.executable, str(ROOT / 'run_engine.py'), '--workflow-benchmark',
                           '--benchmark-backend', backend, '--benchmark-case', case,
                           '--benchmark-characters', str(args.characters), '--factorio', args.factorio,
                           '--output', str(target)]
                if args.expansion:
                    command.append('--expansion')
                print(f'Trial {trial}/{args.trials} {case} {backend}', flush=True)
                with (base / (target.name + '.stdout')).open('w') as log:
                    completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
                record = {'trial': trial, 'case': case, 'backend': backend,
                          'exit_code': completed.returncode, 'logs': str(target)}
                if completed.returncode == 0:
                    record['result'] = json.loads((target / 'result.json').read_text())
                runs.append(record)
                report = summarize(runs, args.trials, args.characters, cases, backends)
                (base / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
                print(f'  exit={completed.returncode}; retained {len(runs)} runs', flush=True)
    report = summarize(runs, args.trials, args.characters, cases, backends)
    (base / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in {'runs', 'failures'}}, indent=2))
    return 0 if report['headless_performance_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
