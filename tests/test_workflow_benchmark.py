"""Matrix aggregation contracts, not engine/performance acceptance."""
import unittest

from run_workflow_benchmark import distribution, summarize


class WorkflowReportTests(unittest.TestCase):
    def test_nearest_rank_p95_keeps_slow_tail(self):
        result = distribution(list(range(1, 101)))
        assert result is not None
        self.assertEqual(result['median'], 50.5)
        self.assertEqual(result['p95'], 95)
        self.assertEqual(result['maximum'], 100)
        self.assertIsNone(distribution([]))

    def test_failures_are_retained_and_block_the_gate(self):
        failed = {'trial': 1, 'case': 'shell', 'backend': 'native',
                  'exit_code': 1, 'logs': 'labelled-unit-fixture'}
        report = summarize([failed], 10, 10)
        self.assertEqual(report['runs'], [failed])
        self.assertEqual(report['failures'], [failed])
        self.assertFalse(report['matrix_complete'])
        self.assertFalse(report['headless_performance_passed'])
        self.assertFalse(report['rollout_allowed'])

    def test_insufficient_sample_count_cannot_pass(self):
        runs = []
        for case in ('shell', 'basic', 'advanced'):
            for backend in ('vm', 'native'):
                ticks = 4 if backend == 'vm' else 1
                metrics = [{'phase': 'boot', 'ticks': ticks},
                           {'phase': 'echo', 'ticks': 1}]
                if case != 'shell':
                    metrics.append({'phase': 'launch', 'ticks': ticks})
                result = {'case': case, 'backend': backend, 'metrics': metrics, 'profiles': []}
                runs.append({'trial': 1, 'case': case, 'backend': backend,
                             'exit_code': 0, 'result': result})
        report = summarize(runs, 1, 1)
        self.assertTrue(report['matrix_complete'])
        self.assertFalse(report['headless_performance_passed'])
        self.assertTrue(report['gates']['shell']['boot_2x_passed'])
        self.assertFalse(report['gates']['shell']['sample_count_passed'])

    def test_duplicate_process_identity_is_rejected(self):
        failed = {'trial': 1, 'case': 'shell', 'backend': 'native',
                  'exit_code': 1, 'logs': 'labelled-unit-fixture'}
        with self.assertRaises(ValueError):
            summarize([failed, failed], 10, 10)

    def test_selected_direct_shell_matrix_does_not_require_editors_or_allow_rollout(self):
        runs = []
        for trial in range(1, 11):
            for backend in ('vm', 'shell'):
                metrics = [{'phase': 'boot', 'ticks': 109 if backend == 'vm' else 1}]
                metrics += [{'phase': 'echo', 'ticks': 2 if backend == 'vm' else 1} for _ in range(10)]
                result = {'case': 'shell', 'backend': backend, 'metrics': metrics, 'profiles': []}
                runs.append({'trial': trial, 'case': 'shell', 'backend': backend, 'exit_code': 0, 'result': result})
        report = summarize(runs, 10, 10, ('shell',), ('vm', 'shell'))
        self.assertTrue(report['matrix_complete'])
        self.assertTrue(report['headless_performance_passed'])
        self.assertTrue(report['rewritten_shell_not_identical_rom'])
        self.assertFalse(report['rollout_allowed'])
        self.assertEqual(report['selected_cases'], ['shell'])
        self.assertEqual(report['selected_backends'], ['vm', 'shell'])
        self.assertEqual(report['workflows']['shell']['shell']['echo_ticks']['samples'], 100)
        self.assertEqual(report['gates']['shell']['boot_speedup'], 109)

    def test_cold_profile_includes_compilation_without_echo_work(self):
        result = {'case': 'shell', 'backend': 'native', 'metrics': [],
                  'profiles': [{'kind': 'module-import', 'milliseconds': 3},
                               {'kind': 'creation', 'milliseconds': 2},
                               {'kind': 'scheduler', 'phase': 'boot', 'milliseconds': 7},
                               {'kind': 'scheduler', 'phase': 'echo', 'milliseconds': 100}]}
        run = {'trial': 1, 'case': 'shell', 'backend': 'native',
               'exit_code': 0, 'result': result}
        report = summarize([run], 10, 10)
        self.assertEqual(report['workflows']['shell']['native']['cold_profiled_startup_ms']['median'], 12)
        result['profiles'] = result['profiles'][:2] + result['profiles'][3:]
        report = summarize([run], 10, 10)
        self.assertIsNone(report['workflows']['shell']['native']['cold_profiled_startup_ms'])


if __name__ == '__main__':
    unittest.main()
