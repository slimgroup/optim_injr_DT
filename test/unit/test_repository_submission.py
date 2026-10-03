"""Exercise real submission wrappers with a local sbatch stub, without Slurm."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SubmissionPaths(unittest.TestCase):
    def run_submitter(self, name, args=()):
        with tempfile.TemporaryDirectory(prefix="optim-submit-test-") as tmp:
            directory = Path(tmp)
            record = directory / "calls.jsonl"
            stub = directory / "sbatch"
            stub.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['SUBMISSION_TEST_RECORD'], 'a') as f:\n"
                "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "print('12345' if '--parsable' in sys.argv else 'Submitted batch job 12345')\n"
            )
            stub.chmod(0o755)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"],
                       SUBMISSION_TEST_RECORD=str(record))
            for key in ("SAMPLE_RANGE", "MEMORY", "WALLTIME", "DEP_OPT"):
                env.pop(key, None)
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/shell/submit" / name), *args],
                cwd=directory, env=env, capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = [json.loads(line) for line in record.read_text().splitlines()]
            for call in calls:
                chdir = next(arg.split("=", 1)[1] for arg in call if arg.startswith("--chdir="))
                self.assertEqual(Path(chdir).resolve(), ROOT)
                self.assertEqual(Path(call[-1]).resolve(), ROOT / "scripts/shell/run/optim_inject_pace.sh")
                exported = next(arg for arg in call if arg.startswith("--export="))
                self.assertIn("CASE_TAG=", exported)
                self.assertIn("RISK_ARGS=", exported)
            return calls

    def test_step1_case_sweep_preserves_cases(self):
        calls = self.run_submitter("submit_all.sh")
        self.assertEqual(len(calls), 14)
        self.assertEqual(sum("--use_pof" in " ".join(c) for c in calls), 5)
        self.assertEqual(sum("--use_cvar" in " ".join(c) for c in calls), 9)

    def test_step2_prior_comparison(self):
        calls = self.run_submitter("submit_step2_dual_prior_smoketest.sh", ["--samples", "1-2"])
        self.assertEqual(len(calls), 4)
        for call in calls:
            self.assertIn("--array=1-2", call)
            self.assertIn("--monitoring_step 2", " ".join(call))

    def test_paired_smoke_cases_and_resource_arguments(self):
        for step in (3, 4):
            for case in ("pof_eps0.0", "pof_eps0.01", "cvar_g0.1_a0.01"):
                with self.subTest(step=step, case=case):
                    calls = self.run_submitter(f"submit_step{step}_paired_smoketest.sh",
                                              ["--case", case, "--samples", "7-8", "--mem", "8G",
                                               "--time", "01:00:00"])
                    self.assertEqual(len(calls), 1)
                    call = calls[0]
                    for arg in ("--array=7-8", "--mem=8G", "--time=01:00:00"):
                        self.assertIn(arg, call)
                    text = " ".join(call)
                    self.assertIn(f"--monitoring_step {step}", text)
                    self.assertIn(f"--case_key {case}", text)
                    self.assertIn("--prior_mode paired_posterior_sample", text)

    def test_step4_all_cases(self):
        calls = self.run_submitter("submit_step4_paired_all.sh", ["--case", "all", "--samples", "1-3"])
        self.assertEqual(len(calls), 3)
        for call in calls:
            self.assertIn("--array=1-3", call)
            self.assertIn("--monitoring_step 4", " ".join(call))


if __name__ == "__main__":
    unittest.main()
