#!/usr/bin/env python3
"""Small negative tests of the resource supervisor; no large allocations."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import run_validation as runner


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="mm-synthetic-supervisor-")
        self.addCleanup(self.tmp.cleanup)
        here = Path(self.tmp.name)
        self.patches = [patch.object(runner, "HERE", here), patch.object(runner, "REPORT", here / "results.json")]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)
        self.report = {"execution_s": 0.0, "deadline_epoch": time.time() + 10, "runs": []}

    def execute(self, code, allowance=2):
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.run_one(self.report, [sys.executable, "-c", code],
                {"phase": "guard", "name": self._testMethodName, "scenario": "supervisor-test"}, allowance)

    def test_success_and_machine_readable_report(self):
        r = self.execute("print('ok')")
        self.assertEqual(r["status"], "PASS")
        self.assertGreater(r["peak_rss_mib"], 0)
        self.assertEqual(json.loads(runner.REPORT.read_text())["runs"][0]["status"], "PASS")

    def test_output_normalization_preserves_raw_digest(self):
        import hashlib
        r = self.execute("print('observation  ')")
        self.assertEqual(r["status"], "PASS")
        self.assertEqual(r["log_raw_sha256"], hashlib.sha256(b"observation  \n").hexdigest())
        self.assertEqual((runner.HERE / r["log"]).read_bytes(), b"observation\n")
        self.assertNotIn(b"\r", (runner.HERE / "results.csv").read_bytes())

    def test_nonzero_exit_preserved(self):
        r = self.execute("import sys; print('deliberate-test-failure'); sys.exit(7)")
        self.assertEqual(r["status"], "FAIL")
        self.assertEqual(r["exit_code"], 7)
        self.assertIn("deliberate-test-failure", r["failure_output"])

    def test_timeout_terminates_child(self):
        r = self.execute("import time; time.sleep(5)", 0.05)
        self.assertEqual((r["status"], r["reason"]), ("FAIL", "TIME_STOP"))
        self.assertLess(r["wall_s"], 2)

    def test_timeout_is_not_pass_even_if_child_handles_term_with_zero(self):
        r = self.execute("import signal,sys,time; signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); time.sleep(5)", 0.25)
        self.assertEqual((r["status"], r["reason"]), ("FAIL", "TIME_STOP"))

    def test_scale_child_without_measurements_cannot_pass(self):
        with contextlib.redirect_stdout(io.StringIO()):
            r = runner.run_one(self.report, [sys.executable, "-c", "pass"],
                {"phase": "guard", "name": self._testMethodName, "n": 100, "scenario": "fan", "cap": 4}, 2)
        self.assertEqual((r["status"], r["reason"]), ("FAIL", "MISSING_RESULT"))

    def test_rss_tripwire_without_giant_allocation(self):
        with patch.object(runner, "process_rss_kib", return_value=runner.RSS_STOP_KIB):
            r = self.execute("import time; time.sleep(5)")
        self.assertEqual((r["status"], r["reason"]), ("FAIL", "MEMORY_STOP"))
        self.assertLess(r["wall_s"], 2)

    def test_expired_budget_cannot_launch_child(self):
        self.report["deadline_epoch"] = time.time() - 1
        with patch.object(runner.subprocess, "Popen", side_effect=AssertionError("MUST_NOT_START")):
            r = self.execute("raise AssertionError('unreachable')")
        self.assertEqual(r["status"], "NOT_RUN")
        self.assertEqual(r["reason"], "PACKAGE_TIME_BUDGET_EXHAUSTED")

    def test_address_space_limit_is_enforced(self):
        r = self.execute("import resource; n=resource.getrlimit(resource.RLIMIT_AS); assert n == (1610612736, 1610612736)")
        self.assertEqual(r["status"], "PASS")

    def test_repeated_names_do_not_overwrite_prior_logs(self):
        first = self.execute("print('first')")
        second = self.execute("print('second')")
        self.assertNotEqual(first["log"], second["log"])
        self.assertEqual((runner.HERE / first["log"]).read_text().strip(), "first")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SupervisorTests)
    if suite.countTestCases() == 0:
        raise SystemExit("No supervisor tests discovered")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
