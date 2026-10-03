"""Exercise status helpers against disposable data and mocked Slurm snapshots."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class StatusChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="optim-status-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.scripts = self.root / "scripts/shell/check"
        self.scripts.mkdir(parents=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.record = self.root / "slurm-calls.jsonl"
        for name in ("squeue", "sacct", "pgrep"):
            stub = self.bin / name
            stub.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "name = Path(sys.argv[0]).name\n"
                "with open(os.environ['STATUS_TEST_RECORD'], 'a') as f:\n"
                "    f.write(json.dumps([name, *sys.argv[1:]]) + '\\n')\n"
                "print(os.environ.get('STATUS_TEST_' + name.upper(), ''), end='')\n"
                "sys.exit(int(os.environ.get('STATUS_TEST_' + name.upper() + '_EXIT', '0')))\n"
            )
            stub.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        USER="test-user", STATUS_TEST_RECORD=str(self.record),
                        STATUS_TEST_PGREP_EXIT="1")
        self.env.pop("SUBMISSION_LOG", None)

    def run_check(self, name):
        target = self.scripts / name
        shutil.copy2(ROOT / "scripts/shell/check" / name, target)
        result = subprocess.run(["bash", str(target)], cwd=self.root, env=self.env,
                                capture_output=True, text=True, timeout=20)
        calls = [json.loads(line) for line in self.record.read_text().splitlines()]
        for name in ("squeue", "sacct"):
            selected = [call for call in calls if call[0] == name]
            self.assertEqual(len(selected), 1, calls)
            self.assertIn("-h" if name == "squeue" else "-X", selected[0])
        return result

    def test_cvar_sample_boundaries_and_allocation_counts(self):
        self.env["STATUS_TEST_SQUEUE"] = "\n".join(
            f"DT_CVaR_a=0.001_g=0.05_s{s}|{state}"
            for s, state in ((60, "R"), (64, "R"), (65, "R"), (109, "R"),
                             (119, "PD"), (128, "PD"), (129, "R"), (1280, "R"))
        ) + "\nDT_POF_eps=0.1_s65|R\n"
        self.env["STATUS_TEST_SACCT"] = "\n".join(
            f"DT_CVaR_a=0.001_g=0.05_s{s}|{state}|"
            for s, state in ((64, "COMPLETED"), (65, "COMPLETED"),
                             (109, "COMPLETED"), (119, "FAILED"),
                             (128, "FAILED"), (129, "FAILED"))
        )
        result = self.run_check("check_submit_65_128_progress.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        for expected in ("Running: 2", "Pending: 2", "Total in queue: 4",
                         "Completed: 2", "Failed: 2", "No submission log found"):
            self.assertIn(expected, result.stdout)
        self.assertNotIn("Remaining to submit:", result.stdout)

    def test_cvar_empty_submission_log(self):
        log = self.root / "logs/submit/submit_20_cases_65_128.log"
        log.parent.mkdir(parents=True)
        log.write_text("[INFO] Starting\n")
        result = self.run_check("check_submit_65_128_progress.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Submission attempts: 0\nSkip records: 0", result.stdout)

    def test_cvar_legacy_log_fallback(self):
        (self.root / "submit_65_128.log").write_text("[SUBMIT] attempt\n[SKIP] existing\n")
        result = self.run_check("check_submit_65_128_progress.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Submission attempts: 1\nSkip records: 1", result.stdout)

    def test_cvar_query_failure_is_not_zero_jobs(self):
        self.env.update(STATUS_TEST_SQUEUE_EXIT="1", STATUS_TEST_SACCT_EXIT="1")
        result = self.run_check("check_submit_65_128_progress.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Queue status unavailable", result.stdout)
        self.assertIn("Allocation status unavailable", result.stdout)
        self.assertNotIn("Running: 0", result.stdout)
        self.assertNotIn("Completed: 0", result.stdout)

    def test_pof_reports_all_missing_jobs(self):
        result = self.run_check("check_all_pof_cases.sh")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for expected in ("Total: 832 jobs", "Missing: 832", "Unknown: 0", "and 812 more"):
            self.assertIn(expected, result.stdout)

    def test_pof_exact_names_and_final_file_precedence(self):
        self.env["STATUS_TEST_SQUEUE"] = "DT_POF_eps=0.1_s128\nDT_POF_eps=0.01_s65\n"
        self.env["STATUS_TEST_SACCT"] = "DT_POF_eps=0.1_s127|\nDT_POF_eps=0x1_s126|\n"
        case = "POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0"
        final = self.root / "data/DT_control/exp_name=step1" / case / "sample=65/final.jld2"
        final.parent.mkdir(parents=True)
        final.write_bytes(b"test fixture; only existence is checked")
        result = self.run_check("check_all_pof_cases.sh")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for expected in ("Total: 832 jobs", "Completed: 1", "Submitted: 2", "Missing: 829"):
            self.assertIn(expected, result.stdout)

    def test_pof_query_failure_leaves_unobserved_samples_unknown(self):
        self.env.update(STATUS_TEST_SQUEUE_EXIT="1",
                        STATUS_TEST_SACCT="DT_POF_eps=0.1_s128|\n")
        result = self.run_check("check_all_pof_cases.sh")
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        for expected in ("Total: 832 jobs", "Submitted: 1", "Missing: 0", "Unknown: 831"):
            self.assertIn(expected, result.stdout)


if __name__ == "__main__":
    unittest.main()
