"""Verify that artifact organizers preserve collisions, using temporary files only."""

from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAINTENANCE = ROOT / "scripts/python_tools/maintenance"


def load_organizer(name):
    spec = importlib.util.spec_from_file_location(name, MAINTENANCE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ArtifactOrganizers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="optim-organizer-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def test_step1_preserves_all_collision_types_and_moves_new_artifacts(self):
        tool = load_organizer("organize_step1_data")
        tool.ROOT = self.root
        tool.STEP1 = self.root / "data/DT_control/exp_name=step1"
        tool.PLOTS = self.root / "plots/DT_control/exp_name=step1/statistical_analysis"
        tool.AGG = tool.STEP1 / "_aggregates"
        tool.STEP1.mkdir(parents=True)
        destinations = {
            "pof_eps0.png": tool.PLOTS / "kde/single_case/pof_eps0.png",
            "table.csv": tool.AGG / "csv/table.csv",
            "samples.jld2": tool.AGG / "jld2/samples.jld2",
            "note.md": tool.AGG / "notes/note.md",
        }
        for name, target in destinations.items():
            (tool.STEP1 / name).write_bytes(b"source")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"existing")
        dangling = tool.AGG / "jld2/dangling.jld2"
        dangling.symlink_to("absent.jld2")
        (tool.STEP1 / dangling.name).write_bytes(b"preserve me")
        (tool.STEP1 / "fresh.csv").write_bytes(b"new table")
        with redirect_stdout(io.StringIO()):
            tool.main()
        for name, target in destinations.items():
            self.assertEqual((tool.STEP1 / name).read_bytes(), b"source")
            self.assertEqual(target.read_bytes(), b"existing")
        self.assertTrue(dangling.is_symlink())
        self.assertEqual((tool.STEP1 / dangling.name).read_bytes(), b"preserve me")
        self.assertEqual((tool.AGG / "csv/fresh.csv").read_bytes(), b"new table")
        self.assertFalse((tool.STEP1 / "fresh.csv").exists())

    def test_log_organizer_preserves_collisions_and_moves_new_logs(self):
        tool = load_organizer("organize_logs")
        tool.ROOT = self.root
        tool.LOGS = self.root / "logs"
        tool.LOGS.mkdir()
        names = ("out_DT_POF_step3_s1.txt", "err_DT_POF_step3_s1.txt")
        for name in names:
            target = tool.dest_for_dt_log(name) / name
            target.parent.mkdir(parents=True, exist_ok=True)
            (tool.LOGS / name).write_bytes(b"source")
            if name.startswith("out_"):
                target.write_bytes(b"existing")
            else:
                target.symlink_to("absent.txt")
        (tool.LOGS / "out_DT_POF_step3_s2.txt").write_bytes(b"new log")
        with redirect_stdout(io.StringIO()):
            tool.main()
        for name in names:
            self.assertEqual((tool.LOGS / name).read_bytes(), b"source")
        self.assertEqual((tool.dest_for_dt_log(names[0]) / names[0]).read_bytes(), b"existing")
        self.assertTrue((tool.dest_for_dt_log(names[1]) / names[1]).is_symlink())
        self.assertEqual((tool.LOGS / "optimization/step3/out_DT_POF_step3_s2.txt").read_bytes(), b"new log")


if __name__ == "__main__":
    unittest.main()
