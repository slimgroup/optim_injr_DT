#!/usr/bin/env python3
"""Audit dense-grid versus observed-jump bootstrap ECDF rate selection.

The historical plotting scripts evaluated the ECDF on a padded, evenly spaced
grid and also selected q_k* from that grid.  This script reproduces that
selection for several grid sizes and compares it with selection on the sorted
unique observed rates.  It does not alter optimization or posterior artifacts.
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

import h5py
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[3]
DATA_ROOT = REPO_ROOT / "data" / "DT_control"
DEFAULT_OUTPUT = REPO_ROOT / "docs" / "statistics" / "ecdf_q_grid_audit.csv"

B = 10_000
CONF = 0.95
THRESHOLD = 0.01
SEED = 42
GRID_SIZES = (250, 500, 1000, 1500, 3000, 6000)
SCHEDULE_LENGTH = 12
PLOT_INDEX = 5  # zero-based index of schedule element 6/12


@dataclass(frozen=True)
class CaseSpec:
    step: str
    scope: str
    label: str
    directory_pattern: str
    inj_start: float
    samples: range
    historical_side: str
    source_file: str


def case_specs() -> tuple[CaseSpec, ...]:
    step1_source = "scripts/julia_scripts/plotting/bootstrap_ecdf/plot_bootstrap_panels.jl"
    specs = [
        CaseSpec("step1", "primary-12-case", "PoF eps=0.0", "POF__HARD__eps=0.0__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "PoF eps=0.01", "POF__HARD__eps=0.01__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "PoF eps=0.05", "POF__HARD__eps=0.05__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.0 alpha=0.0", "CVaR__HARD__alpha=0.0__gamma=0.0__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.0 alpha=0.01", "CVaR__HARD__alpha=0.01__gamma=0.0__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.0 alpha=0.05", "CVaR__HARD__alpha=0.05__gamma=0.0__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.1 alpha=0.0", "CVaR__HARD__alpha=0.0__gamma=0.1__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.1 alpha=0.01", "CVaR__HARD__alpha=0.01__gamma=0.1__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.1 alpha=0.05", "CVaR__HARD__alpha=0.05__gamma=0.1__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.2 alpha=0.0", "CVaR__HARD__alpha=0.0__gamma=0.2__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.2 alpha=0.01", "CVaR__HARD__alpha=0.01__gamma=0.2__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "primary-12-case", "CVaR gamma=0.2 alpha=0.05", "CVaR__HARD__alpha=0.05__gamma=0.2__", 0.0001, range(1, 129), "left", step1_source),
        CaseSpec("step1", "additional-single-panel", "CVaR gamma=0.05 alpha=0.05", "CVaR__HARD__alpha=0.05__gamma=0.05__", 0.0001, range(1, 129), "left", step1_source),
    ]

    paired = {
        2: (0.02630, 0.04530, 0.07470),
        3: (0.04489, 0.07317, 0.11529),
        4: (0.06201, 0.08023, 0.11866),
    }
    case_info = (
        ("PoF eps=0.0", "case=pof_eps0.0__prior=paired_posterior_sample__"),
        ("PoF eps=0.01", "case=pof_eps0.01__prior=paired_posterior_sample__"),
        ("CVaR gamma=0.1 alpha=0.01", "case=cvar_g0.1_a0.01__prior=paired_posterior_sample__"),
    )
    for step, starts in paired.items():
        source = f"scripts/python_plots/posterior_stats/plot_step{step}_paired_posterior_stats.py"
        for (label, pattern), inj_start in zip(case_info, starts):
            specs.append(CaseSpec(f"step{step}", "primary-paired", label, pattern, inj_start, range(1, 129), "right", source))

    dual_source = "scripts/julia_scripts/plotting/posterior_stats/plot_step2_dual_prior_stats.jl"
    for prior in ("pointwise_median", "paired_posterior_sample"):
        specs.extend(
            (
                CaseSpec("step2", "dual-prior-32", f"PoF eps=0.01, {prior}", f"case=pof_eps0.01__prior={prior}__", 0.04530, range(1, 33), "left", dual_source),
                CaseSpec("step2", "dual-prior-32", f"CVaR gamma=0.1 alpha=0.01, {prior}", f"case=cvar_g0.1_a0.01__prior={prior}__", 0.07470, range(1, 33), "left", dual_source),
            )
        )
    return tuple(specs)


def final_endpoint(path: Path) -> float:
    with h5py.File(path, "r") as handle:
        raw = np.asarray(handle["inj_rate_arr"]).reshape(-1)
    valid = raw[np.isfinite(raw) & (raw != 0)]
    return float(valid[-1]) if valid.size else 1.0e-4


def load_rates(spec: CaseSpec) -> np.ndarray:
    root = DATA_ROOT / f"exp_name={spec.step}"
    matches = sorted(path for path in root.iterdir() if path.is_dir() and spec.directory_pattern in path.name)
    if len(matches) != 1:
        raise RuntimeError(f"Expected one directory for {spec.step} {spec.label}; found {len(matches)}")
    rates = []
    for sample in spec.samples:
        final_path = matches[0] / f"sample={sample}" / "final.jld2"
        if not final_path.is_file():
            continue
        schedule = np.linspace(spec.inj_start, final_endpoint(final_path), SCHEDULE_LENGTH)
        rates.append(float(schedule[PLOT_INDEX]))
    if not rates:
        raise RuntimeError(f"No completed samples for {spec.step} {spec.label}")
    return np.asarray(rates)


def upper_band_at_jumps(data: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Compute the seeded pointwise upper bootstrap band at observed endpoints."""
    rng = np.random.default_rng(SEED)
    n = len(data)
    points = np.unique(data)
    indices = rng.integers(0, n, size=(B, n))
    samples = np.sort(data[indices], axis=1)
    upper = np.asarray(
        [np.quantile(np.count_nonzero(samples <= point, axis=1) / n, 1 - (1 - CONF) / 2) for point in points]
    )
    return points, upper


def first_crossing(points: np.ndarray, values: np.ndarray) -> float:
    indices = np.flatnonzero(values >= THRESHOLD)
    if not indices.size:
        raise RuntimeError("Upper bootstrap CDF does not cross the target threshold")
    return float(points[indices[0]])


def historical_grid_result(data: np.ndarray, points: np.ndarray, upper: np.ndarray, npts: int, side: str) -> tuple[float, float]:
    xmin, xmax = float(np.min(data)), float(np.max(data))
    span = xmax - xmin
    margin = 0.05 * span if span > 0 else max(abs(xmin) * 0.05, 1.0e-6)
    grid = np.linspace(xmin - margin, xmax + margin, npts)
    spacing = float(grid[1] - grid[0])

    # Map each grid point to the preceding observed jump.  `left` reproduces
    # the historical Julia count(X < q); `right` reproduces Python count(X <= q).
    preceding = np.searchsorted(points, grid, side=side)
    grid_upper = np.zeros(npts)
    valid = preceding > 0
    grid_upper[valid] = upper[preceding[valid] - 1]
    return spacing, first_crossing(grid, grid_upper)


def audit_rows() -> list[dict[str, object]]:
    rows = []
    for spec in case_specs():
        data = load_rates(spec)
        points, upper = upper_band_at_jumps(data)
        direct = first_crossing(points, upper)
        direct_upper = float(upper[np.flatnonzero(points == direct)[0]])
        grid_results = {
            npts: historical_grid_result(data, points, upper, npts, spec.historical_side)
            for npts in GRID_SIZES
        }
        q_1500 = grid_results[1500][1]
        for npts in GRID_SIZES:
            spacing, grid_q = grid_results[npts]
            signed = direct - grid_q
            absolute = abs(signed)
            signed_vs_1500 = grid_q - q_1500
            absolute_vs_1500 = abs(signed_vs_1500)
            rows.append(
                {
                    "step": spec.step,
                    "scope": spec.scope,
                    "case": spec.label,
                    "source_file": spec.source_file,
                    "samples_used": len(data),
                    "observed_min": float(np.min(data)),
                    "observed_max": float(np.max(data)),
                    "grid_points": npts,
                    "grid_spacing": spacing,
                    "q_grid": grid_q,
                    "q_direct": direct,
                    "signed_change_direct_minus_grid": signed,
                    "absolute_change": absolute,
                    "relative_change_percent_vs_grid": 100 * absolute / abs(grid_q),
                    "signed_change_grid_minus_1500": signed_vs_1500,
                    "absolute_change_vs_1500": absolute_vs_1500,
                    "relative_change_percent_vs_1500": 100 * absolute_vs_1500 / abs(q_1500),
                    "upper_cdf_at_direct_crossing": direct_upper,
                    "bootstrap_replicates": B,
                    "confidence": CONF,
                    "threshold": THRESHOLD,
                    "seed": SEED,
                }
            )
    return rows


def write_csv(rows: list[dict[str, object]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    rows = audit_rows()
    write_csv(rows, args.output)
    print(f"Wrote {len(rows)} rows to {args.output}")


if __name__ == "__main__":
    main()
