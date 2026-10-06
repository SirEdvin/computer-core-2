"""Subprocess tests for harness shutdown, not Factorio acceptance."""
import signal
import subprocess
import sys
import threading
import unittest

from run_engine import stop_engine


class ShutdownTests(unittest.TestCase):
    def launch(self, handler, body="while True: time.sleep(0.01)\n"):
        code = ("import signal,time,sys\ncount=0\n" + handler
                + "\nsignal.signal(signal.SIGINT,interrupt)\nprint('ready',flush=True)\n"
                + body)
        process = subprocess.Popen([sys.executable, '-u', '-c', code],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        self.addCleanup(self.cleanup, process)
        assert process.stdout is not None
        stdout = process.stdout
        self.assertEqual(stdout.readline().strip(), 'ready')
        lines = []
        reader = threading.Thread(target=lambda: lines.extend(stdout), daemon=True)
        reader.start()
        return process, lines, reader

    @staticmethod
    def cleanup(process):
        if process.poll() is None:
            process.kill()
            process.wait()
        if process.stdin and not process.stdin.closed:
            process.stdin.close()
        if process.stdout:
            process.stdout.close()

    def test_acknowledged_interrupt_exits_cleanly(self):
        process, lines, reader = self.launch(
            "def interrupt(signum,frame):\n print('Received SIGINT, shutting down',flush=True)\n raise SystemExit(0)")
        result = stop_engine(process, lines, timeout=2, retry_after=0.2)
        reader.join(1)
        self.assertEqual(result['signals_sent'], 1)
        self.assertFalse(result['forced_kill'])
        self.assertEqual(result['exit_code'], 0)
        assert process.stdin is not None
        self.assertTrue(process.stdin.closed)

    def test_only_unacknowledged_interrupt_is_retried(self):
        process, lines, reader = self.launch(
            "def interrupt(signum,frame):\n global count\n count+=1\n"
            " if count==1: return\n print('Received SIGINT, shutting down',flush=True)\n raise SystemExit(0)")
        result = stop_engine(process, lines, timeout=2, retry_after=0.1)
        reader.join(1)
        self.assertEqual(result['signals_sent'], 2)
        self.assertEqual(result['exit_code'], 0)
        self.assertFalse(result['forced_kill'])

    def test_acknowledged_but_stuck_shutdown_is_not_signalled_again(self):
        process, lines, reader = self.launch(
            "def interrupt(signum,frame):\n print('Received SIGINT, shutting down',flush=True)")
        result = stop_engine(process, lines, timeout=0.4, retry_after=0.1)
        reader.join(1)
        self.assertTrue(result['acknowledged'])
        self.assertEqual(result['signals_sent'], 1)
        self.assertTrue(result['forced_kill'])
        self.assertEqual(result['exit_code'], -signal.SIGKILL)

    def test_ignored_interrupts_are_bounded_and_fail(self):
        process, lines, reader = self.launch("def interrupt(signum,frame): pass")
        result = stop_engine(process, lines, timeout=0.4, retry_after=0.1)
        reader.join(1)
        self.assertEqual(result['signals_sent'], 2)
        self.assertFalse(result['acknowledged'])
        self.assertTrue(result['forced_kill'])
        self.assertEqual(result['exit_code'], -signal.SIGKILL)

    def test_already_exited_process_is_not_signalled(self):
        process = subprocess.Popen([sys.executable, '-c', 'pass'], stdin=subprocess.PIPE)
        self.addCleanup(self.cleanup, process)
        process.wait(timeout=2)
        result = stop_engine(process, [], timeout=2, retry_after=0.1)
        self.assertEqual(result['signals_sent'], 0)
        self.assertEqual(result['exit_code'], 0)
        self.assertFalse(result['forced_kill'])


    def test_console_quit_does_not_send_interrupt(self):
        process, lines, reader = self.launch("def interrupt(signum,frame): raise SystemExit(7)",
            "assert sys.stdin.readline().strip()=='/quit'\nprint('Quitting: remote-quit.',flush=True)\n")
        result = stop_engine(process, lines, timeout=2, retry_after=0.2, console=True)
        reader.join(1)
        self.assertTrue(result['console_quit_sent'])
        self.assertEqual(result['signals_sent'], 0)
        self.assertEqual(result['exit_code'], 0)
        self.assertFalse(result['forced_kill'])

    def test_unacknowledged_console_quit_falls_back_to_interrupt(self):
        process, lines, reader = self.launch(
            "def interrupt(signum,frame):\n print('Received SIGINT, shutting down',flush=True)\n raise SystemExit(0)",
            "assert sys.stdin.readline().strip()=='/quit'\nwhile True: time.sleep(0.01)\n")
        result = stop_engine(process, lines, timeout=2, retry_after=0.1, console=True)
        reader.join(1)
        self.assertTrue(result['console_quit_sent'])
        self.assertEqual(result['signals_sent'], 1)
        self.assertEqual(result['exit_code'], 0)
        self.assertFalse(result['forced_kill'])


if __name__ == '__main__':
    unittest.main()
