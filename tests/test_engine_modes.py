"""Fixture routing and metric parsing, not engine acceptance."""
import unittest
import io
from unittest.mock import patch

from run_engine import fixture_mode, parse_benchmark_metrics, parse_workflow_metrics, parse_workflow_profiles, parse_workflow_diagnostics
from run_engine import main


class FixtureModeTests(unittest.TestCase):
    def test_existing_modes_keep_their_settings(self):
        self.assertEqual(fixture_mode('legacy'), ('tests/mod', 'CC2', 80, 60))
        self.assertEqual(fixture_mode('guest'), ('tests/guest-mod', 'CC2 GUEST', 80, 60))

    def test_native_probe_is_separate_from_vm_benchmark(self):
        self.assertEqual(fixture_mode('native'), ('tests/native-mod', 'CC2 NATIVE', 600, 180))
        self.assertEqual(fixture_mode('vm-benchmark'),
                         ('tests/vm-benchmark-mod', 'CC2 VM BENCH', 20000, 300))

    def test_unknown_mode_fails(self):
        with self.assertRaises(ValueError):
            fixture_mode('made-up')

    def test_direct_shell_has_an_independent_fixture(self):
        self.assertEqual(fixture_mode('shell'), ('tests/shell-mod', 'CC2 SHELL', 120, 60))

    def test_configuration_change_requires_the_shell_fixture_before_engine_execution(self):
        with patch('sys.argv', ['run_engine.py', '--guest', '--shell-config-change']), patch('sys.stderr', new_callable=io.StringIO) as error:
            with self.assertRaises(SystemExit) as stopped:
                main()
        self.assertEqual(stopped.exception.code, 2)
        self.assertIn('--shell-config-change requires --shell', error.getvalue())

    def test_real_tick_stress_is_separate_from_interaction_and_speed_gates(self):
        self.assertEqual(fixture_mode('shell-stress'),
                         ('tests/shell-stress-mod', 'CC2 SHELL STRESS', 40000, 600))

    def test_matched_workflow_is_a_separate_mode(self):
        self.assertEqual(fixture_mode('workflow-benchmark'),
                         ('tests/workflow-benchmark-mod', 'CC2 WORKFLOW', 20000, 300))

    def test_workflow_metrics_validate_counters_and_keep_all_samples(self):
        fields = {'phase': 'echo', 'case': 'shell', 'backend': 'native', 'sample': 1,
                  'ticks': 2, 'instructions': 30, 'collection_work': 0,
                  'collection_ticks': 0, 'display_revisions': 4, 'dirty_rows': 1,
                  'activation_work': 50}
        fields.update({name + '_work': 0 for name in
                       ['compiler', 'string', 'terminal', 'filesystem', 'event',
                        'advance', 'table', 'continuation']})
        line = 'CC2 WORKFLOW METRIC ' + ' '.join(f'{key}={value}' for key, value in fields.items())
        self.assertEqual(parse_workflow_metrics(line + '\n' + line), [fields, fields])
        with self.assertRaises(ValueError):
            parse_workflow_metrics(line.replace('ticks=2', 'ticks=0'))
        with self.assertRaises(ValueError):
            parse_workflow_metrics(line + ' unrecognized=1')

    def test_workflow_profiles_are_external_diagnostics(self):
        line = 'CC2 WORKFLOW PROFILE kind=scheduler backend=native case=basic phase=character tick=42 Duration: 1.25ms'
        self.assertEqual(parse_workflow_profiles(line), [{'kind': 'scheduler', 'backend': 'native',
                         'case': 'basic', 'phase': 'character', 'tick': 42, 'milliseconds': 1.25}])
        with self.assertRaises(ValueError):
            parse_workflow_profiles(line.replace('Duration: 1.25ms', 'unknown'))

    def test_metrics_retain_all_samples(self):
        output = ('log: CC2 VM BENCH METRIC phase=boot ticks=5 instructions=20 collection_work=0\n'
                  'log: CC2 VM BENCH METRIC phase=shell-char ticks=2 instructions=10 collection_work=3\n')
        metrics = parse_benchmark_metrics(output)
        self.assertEqual(len(metrics), 2)
        self.assertEqual(metrics[1], {'phase': 'shell-char', 'ticks': 2,
                                     'instructions': 10, 'collection_work': 3})

    def test_malformed_metric_is_not_silently_dropped(self):
        with self.assertRaises(ValueError):
            parse_benchmark_metrics('CC2 VM BENCH METRIC phase=boot ticks=bad\n')

    def test_allocation_diagnostics_keep_sources_and_reject_duplicates(self):
        line = ('CC2 WORKFLOW ALLOCATION phase=boot source=%3Csetup%3E proto=0 '
                'cells=3 other=1 steps=4 capture_bindings=0 new_captures=0 blocks=2')
        result = parse_workflow_diagnostics(line)
        self.assertEqual(result['allocations'][0]['source'], '<setup>')
        self.assertEqual(result['allocations'][0]['cells'], 3)
        with self.assertRaises(ValueError):
            parse_workflow_diagnostics(line + '\n' + line)
        with self.assertRaises(ValueError):
            parse_workflow_diagnostics(line.replace('cells=3', 'cells=-1'))
        with self.assertRaises(ValueError):
            parse_workflow_diagnostics(line + ' ignored=1')

    def test_retained_frames_are_distinct_per_snapshot_and_prototype(self):
        line = ('CC2 WORKFLOW FRAMES phase=boot sample=0 source=%2Fbios.lua '
                'proto=1 frames=1 temp_slots=20 temp_values=15 temp_refs=7')
        second = line.replace('proto=1', 'proto=2')
        self.assertEqual(len(parse_workflow_diagnostics(line + '\n' + second)['frames']), 2)
        with self.assertRaises(ValueError):
            parse_workflow_diagnostics(line + '\n' + line)


if __name__ == '__main__':
    unittest.main()
