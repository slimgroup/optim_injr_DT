#!/usr/bin/env python3
"""Freeze accounting, source integrity and conditional estimates after this pilot.

This is deliberately specific to the dated pilot; it never submits simulations.
Existing output files are protected with exclusive creation.
"""
import csv
import hashlib
import io
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path("data/diagnostics/zero_pressure_2026-09-09")
JOBS = "13015513,13015612,13015764,13016431"


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda: f.read(8 * 1024**2), b""):
            h.update(b)
    return h.hexdigest()


def write_json(path, value):
    with path.open("x") as f:
        json.dump(value, f, indent=2)
        f.write("\n")


def write_csv(path, rows):
    with path.open("x", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def cpu_seconds(value):
    days, value = value.split("-", 1) if "-" in value else ("0", value)
    result = 0.0
    for p in value.split(":"):
        result = result * 60 + float(p)
    return result + int(days) * 86400


def main():
    accounting = subprocess.check_output([
        "sacct", "-j", JOBS,
        "--format=JobID,State,Start,End,ElapsedRaw,TotalCPU,AllocCPUS,ReqMem,MaxRSS,ExitCode", "-P"
    ], text=True)
    with (ROOT / "execution_accounting.psv").open("x") as f:
        f.write(accounting)
    raw = list(csv.DictReader(io.StringIO(accounting), delimiter="|"))
    resources = []
    for r in raw:
        if "." in r["JobID"]:
            continue
        batch = next(b for b in raw if b["JobID"] == r["JobID"] + ".batch")
        assert batch["MaxRSS"].endswith("K")
        resources.append(dict(job_id=r["JobID"], status=r["State"],
            wall_seconds=int(r["ElapsedRaw"]), cpu_seconds=cpu_seconds(r["TotalCPU"]),
            allocated_cpus=int(r["AllocCPUS"]), requested_memory=r["ReqMem"],
            peak_rss_gib=float(batch["MaxRSS"][:-1])/1024**2,
            allocated_core_hours=int(r["ElapsedRaw"])*int(r["AllocCPUS"])/3600))
    write_csv(ROOT / "execution_resources.csv", resources)
    baseline = next(r for r in resources if r["job_id"] == "13015764_1")
    block = ROOT / "short_diagnostic_8d/members/001/block_01.jld2"
    estimates = []
    for days in (480, 960):
        estimates.append(dict(window_days=days, members=128,
            pressure_and_p0_uncompressed_gib=(days//8+1)*512*256*8*128/1024**3,
            conditional_cpu_hours_128=baseline["cpu_seconds"]*(days//8)*128/3600,
            conditional_block_storage_gib_128=block.stat().st_size*(days//8)*128/1024**3))
    write_json(ROOT / "allocation_assessment.json", dict(
        status="FULL BATCH NOT APPROVED OR SUBMITTED; no reliable full-pilot estimate",
        measured_resources=resources,
        measured_total_cpu_hours=sum(r["cpu_seconds"] for r in resources)/3600,
        measured_total_allocated_core_hours=sum(r["allocated_core_hours"] for r in resources),
        maximum_measured_rss_gib=max(r["peak_rss_gib"] for r in resources),
        conditional_estimates=estimates,
        conditional_estimate_assumption="Every member and every eight-day interval repeats member 1's completed eight-day cost. CPU includes startup on every extrapolated interval; block storage includes raw nonlinear reports and a restart state on every interval. These are scenario illustrations, not forecasts or valid allocation requests.",
        limitation="None of the three selected members completed 480/960 days. Member speed differs strongly; memory and report growth at a completed 80-day block are unmeasured. A reliable upper bound cannot be inferred.",
        scheduling="Bounded 1-128 array, concurrency at most 4; user-approved wall time required; resume at completed 80-day blocks only. No primary pilot checkpoint is currently available.",
        accounting_timezone="America/New_York; scheduler grace period explains 45:29 elapsed vs requested 45 minutes"))

    short = []
    for profile, sub in (("production", "short_diagnostic_8d"), ("tighter_linear", "tighter_linear_8d")):
        rows = list(csv.DictReader((ROOT/sub/"summary_v1/per_member_8day.csv").open()))
        for r in rows:
            if r["domain"] != "all_cells":
                continue
            short.append(dict(profile=profile, window_days=8, limit_mpa=r["limit_mpa"],
                member=1, realization_id=741, completed_members=1,
                passing_members=int(r["any_exceedance_exact"] == "False"),
                exceeding_members=int(r["any_exceedance_exact"] == "True"),
                max_overpressure_pa=r["max_overpressure_pa"],
                scope="One realization, repeated solver diagnostic; not two ensemble members or a completed 480/960-day check"))
    write_csv(ROOT / "completed_short_window_counts.csv", short)

    original = json.loads((ROOT / "provenance_manifest.json").read_text())
    integrity = []
    for p, before in original["input_and_source_sha256"].items():
        after = sha(p)
        integrity.append(dict(path=p, sha256_before=before, sha256_after=after,
            unchanged=(before == after),
            scope="new_audit_script" if "zero_injection_pressure" in p or "prepare_zero_pressure_audit" in p else "preexisting_input_or_source"))
    assert all(r["unchanged"] for r in integrity if r["scope"] == "preexisting_input_or_source")
    write_csv(ROOT / "input_source_integrity.csv", integrity)
    scripts = sorted({p for p in Path("scripts").rglob("*") if p.is_file() and
        "__pycache__" not in str(p) and ("zero_pressure" in p.name or "zero_injection_pressure" in p.name)})
    scripts.append(Path("test/unit/test_zero_pressure_diagnostics.py"))
    artifact_hashes = {str(p): sha(p) for p in sorted(ROOT.rglob("*"))
        if p.is_file() and not p.is_symlink()}
    plots = Path("plots/diagnostics/zero_pressure_2026-09-09")
    artifact_hashes.update({str(p): sha(p) for p in plots.rglob("*.png")})
    write_json(ROOT / "execution_manifest.json", dict(
        finalized_utc=datetime.now(timezone.utc).isoformat(),
        repo_commit=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        original_manifest="provenance_manifest.json", addendum="provenance_addendum.json",
        final_long_summary="summary_v3", preserved_previous_summaries=["summary_v1", "summary_v2"],
        raw_job_ids=JOBS.split(","),
        runtime_sources={
            "13015513": "6fb6c7537104dbe36d000ef45ed9871d8b5f6b386bada2675395bf075ffb6f07",
            "13015764": "e40e373c504d65b2aecb78790cdfafce87c46e311d90ac7db30e4449953aafef",
            "13016431": "c3610a6b61609d578d45e6a3423ee09cf0ad4082cb47bcc74b8c465913b73dbf"},
        valid_short_solver_exports=["short_diagnostic_8d/solver_steps_v4.csv", "tighter_linear_8d/solver_steps.csv"],
        invalid_exports="Earlier short_diagnostic_8d solver_steps.csv, v2 and v3 attempts are preserved, not analysis inputs; original JLD2 nested tolerance dictionaries could not be reconstructed reliably.",
        validations=["four analytical diagnostic unit tests", "shell syntax", "Julia parse and actual Slurm execution", "raw HDF5 accepted intervals sum to eight days and Newton counts match logs", "saved achieved surface mass rate and CO2 saturation exactly zero", "all hashed preexisting inputs and sources unchanged"],
        current_script_sha256={str(p):sha(p) for p in scripts}, artifact_sha256=artifact_hashes))
    print(json.dumps(dict(resources=resources, conditional_estimates=estimates,
        preexisting_integrity="passed", output=str(ROOT/"execution_manifest.json")), indent=2))


if __name__ == "__main__":
    main()
