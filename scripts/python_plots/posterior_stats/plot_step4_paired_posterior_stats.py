#!/usr/bin/env python3

from __future__ import annotations

import csv
import subprocess
from dataclasses import dataclass
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
ROOT = REPO_ROOT / "data" / "DT_control" / "exp_name=step4"
OUTDIR = REPO_ROOT / "plots" / "step4_paired_posterior_stats"

B = 5000
CONF = 0.95
THRESH = 0.01
NBINS = 16
ECDF_PTS = 1500
SEED = 42
SAMPLES = range(1, 129)

plt.rcParams.update(
    {
        "font.family": "serif",
        "axes.titlesize": 14,
        "axes.labelsize": 12,
        "xtick.labelsize": 10,
        "ytick.labelsize": 10,
        "legend.fontsize": 9,
    }
)


@dataclass(frozen=True)
class CaseSpec:
    key: str
    slug: str
    title: str
    dirname: str
    inj_start: float
    array_job_id: str
    expected_running: set[int]


@dataclass
class Record:
    sample: int
    endpoint: float
    rate6: float


SPECS = (
    CaseSpec(
        "pof_eps0.0",
        "pof_eps0.0",
        "PoF eps=0.0",
        "case=pof_eps0.0__prior=paired_posterior_sample__POF__HARD__eps=0.0__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        0.06201,
        "6497599",
        set(),
    ),
    CaseSpec(
        "pof_eps0.01",
        "pof_eps0.01",
        "PoF eps=0.01",
        "case=pof_eps0.01__prior=paired_posterior_sample__POF__HARD__eps=0.01__tau=0.05__w=voltime__mode=relative__cvarhinge__kp=50.0__kc=50.0",
        0.08023,
        "6497601",
        set(),
    ),
    CaseSpec(
        "cvar_g0.1_a0.01",
        "cvar_g0.1_a0.01",
        "CVaR gamma=0.1, alpha=0.01",
        "case=cvar_g0.1_a0.01__prior=paired_posterior_sample__CVaR__HARD__alpha=0.01__gamma=0.1__w=voltime__mode=relative__cvarsoft__kp=50.0__kc=50.0",
        0.11866,
        "6497602",
        set(),
    ),
)


def last_nonzero_endpoint(fp: Path) -> float:
    with h5py.File(fp, "r") as f:
        arr = np.array(f["inj_rate_arr"]).reshape(-1)
    nz = np.flatnonzero(np.isfinite(arr) & (arr != 0))
    return float(arr[nz[-1]]) if nz.size else 1.0e-4


def rate6(endpoint: float, inj_start: float) -> float:
    return float(np.linspace(inj_start, endpoint, 12)[5])


def active_array_tasks(array_job_id: str) -> set[int]:
    cmd = f"squeue -h -j {array_job_id} -o '%i'"
    try:
        out = subprocess.check_output(["bash", "-lc", cmd], text=True, cwd=REPO_ROOT)
    except Exception:
        return set()
    tasks = set()
    for line in out.splitlines():
        token = line.strip()
        if "_" not in token:
            continue
        try:
            tasks.add(int(token.rsplit("_", 1)[1]))
        except ValueError:
            continue
    return tasks


def load_records(spec: CaseSpec) -> tuple[list[Record], list[int], list[int]]:
    out: list[Record] = []
    missing: list[int] = []
    active = active_array_tasks(spec.array_job_id)
    root = ROOT / spec.dirname
    for s in SAMPLES:
        fp = root / f"sample={s}" / "final.jld2"
        if not fp.is_file():
            if s in active or s in spec.expected_running:
                continue
            missing.append(s)
            continue
        ep = last_nonzero_endpoint(fp)
        out.append(Record(s, ep, rate6(ep, spec.inj_start)))
    return out, missing, sorted(active)


def boot_quantile(x: np.ndarray, q: float, b: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    idx = rng.integers(0, len(x), size=(b, len(x)))
    return np.quantile(x[idx], q, axis=1)


def boot_ecdf_ci(x: np.ndarray, b: int, conf: float, npts: int, seed: int):
    rng = np.random.default_rng(seed)
    xmin, xmax = float(np.min(x)), float(np.max(x))
    span = xmax - xmin
    margin = 0.05 * span if span > 0 else max(abs(xmin) * 0.05, 1e-6)
    grid = np.linspace(xmin - margin, xmax + margin, npts)
    sorted_x = np.sort(x)
    ecdf = np.searchsorted(sorted_x, grid, side="right") / len(x)
    boot = np.empty((b, npts), dtype=float)
    for i in range(b):
        s = np.sort(x[rng.integers(0, len(x), size=len(x))])
        boot[i, :] = np.searchsorted(s, grid, side="right") / len(x)
    alpha = 1 - conf
    return grid, ecdf, np.quantile(boot, alpha / 2, axis=0), np.quantile(boot, 1 - alpha / 2, axis=0)


def crossing(grid: np.ndarray, vals: np.ndarray, thr: float):
    idx = np.flatnonzero(vals >= thr)
    return float(grid[idx[0]]) if idx.size else None


def stats_text(x: np.ndarray, q01: float) -> str:
    return (
        f"n={len(x)}\n"
        f"mean={np.mean(x):.5f}\n"
        f"median={np.median(x):.5f}\n"
        f"std={np.std(x, ddof=1):.5f}\n"
        f"1% q={q01:.5f}"
    )


def plot_hist(x: np.ndarray, q01: float, qlo: float, qhi: float, title: str, out: Path) -> None:
    fig, ax = plt.subplots(figsize=(8.6, 5.8))
    edges = np.linspace(np.min(x), np.max(x), NBINS + 1)
    if np.allclose(edges[0], edges[-1]):
        edges = np.linspace(edges[0] - 1e-6, edges[0] + 1e-6, NBINS + 1)
    ax.hist(
        x,
        bins=edges,
        color="#7FB3D5",
        edgecolor="#1F618D",
        alpha=0.8,
        linewidth=0.8,
        label=f"Histogram (n={len(x)})",
    )
    ax.axvline(q01, color="#1E8449", linewidth=2.2, label=f"1% quantile = {q01:.5f}")
    ax.axvline(qlo, color="#CB4335", linewidth=1.6, linestyle="--", label=f"95% CI lower = {qlo:.5f}")
    ax.axvline(qhi, color="#7D3C98", linewidth=1.6, linestyle="--", label=f"95% CI upper = {qhi:.5f}")
    ax.axvspan(qlo, qhi, color="#D7BDE2", alpha=0.25)
    ax.text(
        0.98,
        0.96,
        stats_text(x, q01),
        transform=ax.transAxes,
        va="top",
        ha="right",
        fontsize=10,
        bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#9E9E9E", alpha=0.95),
    )
    ax.set_title(f"{title}\nHistogram of optimized injection schedule element 6/12", fontweight="bold")
    ax.set_xlabel("Injection rate (m^3/s)")
    ax.set_ylabel("Count")
    ax.grid(True, linestyle="--", linewidth=0.4, alpha=0.4)
    ax.legend(loc="upper left", framealpha=0.95)
    fig.tight_layout()
    fig.savefig(out, dpi=240, bbox_inches="tight")
    plt.close(fig)


def plot_cdf(
    x: np.ndarray,
    grid: np.ndarray,
    ecdf: np.ndarray,
    clo: np.ndarray,
    chi: np.ndarray,
    q01: float,
    title: str,
    out: Path,
) -> None:
    xcons = crossing(grid, chi, THRESH)
    xecdf = crossing(grid, ecdf, THRESH)
    xopt = crossing(grid, clo, THRESH)
    fig, ax = plt.subplots(figsize=(8.6, 5.8))
    ax.fill_between(grid, clo * 100, chi * 100, color="#AED6F1", alpha=0.55, label="95% bootstrap CI")
    ax.plot(grid, ecdf * 100, color="#1F618D", linewidth=2.2, label="Empirical CDF")
    ax.axhline(THRESH * 100, color="#C0392B", linewidth=1.5, linestyle="--", label="1% threshold")
    for val, color, label in [
        (xcons, "#D35400", "CI upper crossing"),
        (xecdf, "#117A65", "ECDF crossing"),
        (xopt, "#5B2C6F", "CI lower crossing"),
    ]:
        if val is not None:
            ax.plot(val, THRESH * 100, marker="*", color=color, markersize=11, label=label)
    ax.text(
        0.98,
        0.96,
        stats_text(x, q01),
        transform=ax.transAxes,
        va="top",
        ha="right",
        fontsize=10,
        bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#9E9E9E", alpha=0.95),
    )
    ax.set_title(f"{title}\nCDF of optimized injection schedule element 6/12 with 95% bootstrap CI", fontweight="bold")
    ax.set_xlabel("Injection rate (m^3/s)")
    ax.set_ylabel("Probability (%)")
    ax.set_ylim(0, 100)
    ax.grid(True, linestyle="--", linewidth=0.4, alpha=0.4)
    ax.legend(loc="upper left", fontsize=9.5, framealpha=0.95)

    inset = ax.inset_axes([0.43, 0.10, 0.52, 0.45])
    inset.fill_between(grid, clo * 100, chi * 100, color="#AED6F1", alpha=0.55)
    inset.plot(grid, ecdf * 100, color="#1F618D", linewidth=1.5)
    inset.axhline(THRESH * 100, color="#C0392B", linewidth=1.0, linestyle="--")
    zoom = [v for v in (xcons, xecdf, xopt) if v is not None]
    zmin, zmax = ((min(zoom) * 0.90, max(zoom) * 1.10) if zoom else (float(np.min(x)), float(np.max(x))))
    if np.isclose(zmin, zmax):
        zmin -= 1e-6
        zmax += 1e-6
    inset.set_xlim(zmin, zmax)
    inset.set_ylim(0, 8)
    inset.set_title("Left-tail zoom", fontsize=9)
    inset.tick_params(labelsize=8)
    inset.grid(True, linestyle="--", linewidth=0.3, alpha=0.35)
    afs = 8.5
    if xcons is not None:
        inset.plot(xcons, THRESH * 100, marker="*", color="#D35400", markersize=12, zorder=5)
        inset.annotate(
            f"q_k*\n{xcons:.4f}",
            xy=(xcons, THRESH * 100),
            xytext=(-28, 18),
            textcoords="offset points",
            fontsize=afs,
            color="#D35400",
            fontweight="bold",
            ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor="#FEF5E7", alpha=0.92, edgecolor="#D35400"),
            arrowprops=dict(arrowstyle="->", color="#D35400"),
        )
    if xecdf is not None:
        inset.plot(xecdf, THRESH * 100, marker="*", color="#117A65", markersize=12, zorder=5)
        inset.annotate(
            f"ECDF\n{xecdf:.4f}",
            xy=(xecdf, THRESH * 100),
            xytext=(0, 40),
            textcoords="offset points",
            fontsize=afs,
            color="#117A65",
            fontweight="bold",
            ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor="#E8F5E9", alpha=0.92, edgecolor="#117A65"),
            arrowprops=dict(arrowstyle="->", color="#117A65"),
        )
    if xopt is not None:
        inset.plot(xopt, THRESH * 100, marker="*", color="#5B2C6F", markersize=12, zorder=5)
        inset.annotate(
            f"Opt.\n{xopt:.4f}",
            xy=(xopt, THRESH * 100),
            xytext=(28, 18),
            textcoords="offset points",
            fontsize=afs,
            color="#5B2C6F",
            fontweight="bold",
            ha="center",
            bbox=dict(boxstyle="round,pad=0.2", facecolor="#F4ECF7", alpha=0.92, edgecolor="#5B2C6F"),
            arrowprops=dict(arrowstyle="->", color="#5B2C6F"),
        )
    fig.tight_layout()
    fig.savefig(out, dpi=240, bbox_inches="tight")
    plt.close(fig)


def plot_grid(results, out: Path) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(18, 9.8))
    fig.suptitle(
        "Step-4 paired posterior summary on completed samples\nHistogram and empirical CDF of optimized injection schedule element 6/12",
        fontsize=18,
        fontweight="bold",
        y=0.98,
    )
    for j, (spec, x, q01, qlo, qhi, grid, ecdf, clo, chi) in enumerate(results):
        ax = axes[0, j]
        edges = np.linspace(np.min(x), np.max(x), NBINS + 1)
        if np.allclose(edges[0], edges[-1]):
            edges = np.linspace(edges[0] - 1e-6, edges[0] + 1e-6, NBINS + 1)
        ax.hist(x, bins=edges, color="#7FB3D5", edgecolor="#1F618D", alpha=0.8, linewidth=0.8)
        ax.axvline(q01, color="#1E8449", linewidth=2.0)
        ax.axvspan(qlo, qhi, color="#D7BDE2", alpha=0.25)
        ax.set_title(spec.title, fontweight="bold")
        ax.set_ylabel("Count")
        ax.grid(True, linestyle="--", linewidth=0.35, alpha=0.35)
        ax.text(
            0.98,
            0.96,
            f"mean={np.mean(x):.4f}\nmedian={np.median(x):.4f}\n1% q={q01:.4f}",
            transform=ax.transAxes,
            va="top",
            ha="right",
            fontsize=9,
            bbox=dict(boxstyle="round,pad=0.25", facecolor="white", edgecolor="#9E9E9E", alpha=0.92),
        )

        ax = axes[1, j]
        ax.fill_between(grid, clo * 100, chi * 100, color="#AED6F1", alpha=0.55)
        ax.plot(grid, ecdf * 100, color="#1F618D", linewidth=2.0)
        ax.axhline(THRESH * 100, color="#C0392B", linewidth=1.2, linestyle="--")
        xcons = crossing(grid, chi, THRESH)
        xecdf = crossing(grid, ecdf, THRESH)
        xopt = crossing(grid, clo, THRESH)
        for val, color in [(xcons, "#D35400"), (xecdf, "#117A65"), (xopt, "#5B2C6F")]:
            if val is not None:
                ax.plot(val, THRESH * 100, marker="*", color=color, markersize=9)
        inset = ax.inset_axes([0.43, 0.10, 0.50, 0.42])
        inset.fill_between(grid, clo * 100, chi * 100, color="#AED6F1", alpha=0.55)
        inset.plot(grid, ecdf * 100, color="#1F618D", linewidth=1.25)
        inset.axhline(THRESH * 100, color="#C0392B", linewidth=0.9, linestyle="--")
        zoom = [v for v in (xcons, xecdf, xopt) if v is not None]
        if zoom:
            zmin, zmax = min(zoom) * 0.85, max(zoom) * 1.15
        else:
            zmin, zmax = float(np.min(x)), float(np.max(x))
        if np.isclose(zmin, zmax):
            zmin -= 1e-6
            zmax += 1e-6
        inset.set_xlim(zmin, zmax)
        inset.set_ylim(0, 8)
        inset.set_title("Left-tail zoom", fontsize=8.5)
        inset.tick_params(labelsize=7.5)
        inset.grid(True, linestyle="--", linewidth=0.25, alpha=0.35)
        afs = 7.5
        if xcons is not None:
            inset.plot(xcons, THRESH * 100, marker="*", color="#D35400", markersize=10, zorder=5)
            inset.annotate(
                f"q_k*\n{xcons:.4f}",
                xy=(xcons, THRESH * 100),
                xytext=(-24, 14),
                textcoords="offset points",
                fontsize=afs,
                color="#D35400",
                fontweight="bold",
                ha="center",
                bbox=dict(boxstyle="round,pad=0.15", facecolor="#FEF5E7", alpha=0.92, edgecolor="#D35400"),
                arrowprops=dict(arrowstyle="->", color="#D35400"),
            )
        if xecdf is not None:
            inset.plot(xecdf, THRESH * 100, marker="*", color="#117A65", markersize=10, zorder=5)
            inset.annotate(
                f"ECDF\n{xecdf:.4f}",
                xy=(xecdf, THRESH * 100),
                xytext=(0, 30),
                textcoords="offset points",
                fontsize=afs,
                color="#117A65",
                fontweight="bold",
                ha="center",
                bbox=dict(boxstyle="round,pad=0.15", facecolor="#E8F5E9", alpha=0.92, edgecolor="#117A65"),
                arrowprops=dict(arrowstyle="->", color="#117A65"),
            )
        if xopt is not None:
            inset.plot(xopt, THRESH * 100, marker="*", color="#5B2C6F", markersize=10, zorder=5)
            inset.annotate(
                f"Opt.\n{xopt:.4f}",
                xy=(xopt, THRESH * 100),
                xytext=(24, 14),
                textcoords="offset points",
                fontsize=afs,
                color="#5B2C6F",
                fontweight="bold",
                ha="center",
                bbox=dict(boxstyle="round,pad=0.15", facecolor="#F4ECF7", alpha=0.92, edgecolor="#5B2C6F"),
                arrowprops=dict(arrowstyle="->", color="#5B2C6F"),
            )
        ax.set_xlabel("Injection rate (m^3/s)")
        ax.set_ylabel("Probability (%)")
        ax.set_ylim(0, 100)
        ax.grid(True, linestyle="--", linewidth=0.35, alpha=0.35)
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(out, dpi=240, bbox_inches="tight")
    plt.close(fig)


def write_csv(sample_ids, lookups, out: Path) -> None:
    fields = ["sample"]
    for spec in SPECS:
        fields += [f"{spec.slug}_endpoint", f"{spec.slug}_rate6"]
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for s in sample_ids:
            row = {"sample": s}
            for spec in SPECS:
                rec = lookups[spec.key].get(s)
                row[f"{spec.slug}_endpoint"] = "" if rec is None else rec.endpoint
                row[f"{spec.slug}_rate6"] = "" if rec is None else rec.rate6
            w.writerow(row)


def main() -> None:
    OUTDIR.mkdir(parents=True, exist_ok=True)
    all_records = {}
    missing_by_case = {}
    active_by_case = {}
    for spec in SPECS:
        records, missing, active = load_records(spec)
        all_records[spec.key] = records
        missing_by_case[spec.key] = missing
        active_by_case[spec.key] = active

    lookups = {k: {r.sample: r for r in recs} for k, recs in all_records.items()}
    sample_sets = [set(r.sample for r in recs) for recs in all_records.values() if recs]
    all_sample_ids = sorted(set.union(*sample_sets)) if sample_sets else []

    results = []
    lines = [
        "# Step-4 paired posterior summary",
        "",
        "Main plotted statistic: the 6th element of the optimized injection schedule of total length 12, reconstructed from `inj_rate_arr` using the case-level step-3 `inj_start`.",
        "",
        "The final endpoint is mathematically redundant with this plotted statistic within each case because the 6th schedule element is a fixed affine transform of that endpoint.",
        "",
        "Only completed samples with `final.jld2` are included in the histogram/CDF plots.",
        "Active samples are excluded until they finish. Samples without `final.jld2` and without an active job are reported separately as fracture / no-final candidates.",
        "",
        "| Case | completed samples used | active samples excluded | no-final candidates | mean | median | std | 1% q | 95% CI for 1% q |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]

    for spec in SPECS:
        records = all_records[spec.key]
        x = np.array([r.rate6 for r in records], dtype=float)
        boot = boot_quantile(x, THRESH, B, SEED)
        q01 = float(np.quantile(x, THRESH))
        qlo = float(np.quantile(boot, (1 - CONF) / 2))
        qhi = float(np.quantile(boot, 1 - (1 - CONF) / 2))
        grid, ecdf, clo, chi = boot_ecdf_ci(x, B, CONF, ECDF_PTS, SEED)
        plot_hist(x, q01, qlo, qhi, spec.title, OUTDIR / f"hist_{spec.slug}.png")
        plot_cdf(x, grid, ecdf, clo, chi, q01, spec.title, OUTDIR / f"cdf_{spec.slug}.png")
        results.append((spec, x, q01, qlo, qhi, grid, ecdf, clo, chi))
        lines.append(
            f"| {spec.title} | {len(records)} | {len(active_by_case[spec.key])} | {len(missing_by_case[spec.key])} | "
            f"{np.mean(x):.5f} | {np.median(x):.5f} | {np.std(x, ddof=1):.5f} | {q01:.5f} | [{qlo:.5f}, {qhi:.5f}] |"
        )

    lines += ["", "Case details:"]
    for spec in SPECS:
        active = active_by_case[spec.key]
        missing = missing_by_case[spec.key]
        if active:
            lines.append(f"- {spec.title} active samples excluded: `{', '.join(map(str, active))}`")
        if missing:
            lines.append(f"- {spec.title} no-final candidates: `{', '.join(map(str, missing))}`")
            if spec.key == "pof_eps0.0":
                lines.append("- All no-final candidates for `PoF eps=0.0` hit `first_forward failed even at minimum injection rate 0.0001`, so they are strong infeasible / fracture candidates rather than generic save failures.")
        else:
            lines.append(f"- {spec.title} no-final candidates: `none`")

    lines += [
        "",
        "Bias note for `PoF eps=0.0`:",
        "- The step-4 histogram / CDF for `PoF eps=0.0` is fitted on the `122` feasible completed samples only.",
        "- Samples `5, 16, 28, 36, 47, 117` are excluded because `first_forward` fails even at the minimum injection rate `0.0001`, so they represent an infeasible / fracture-candidate mass rather than ordinary low-rate completed realizations.",
        "- This means the reported step-4 `q_k*` for `PoF eps=0.0` is a conservative left-tail estimate conditional on feasibility, not an unbiased full-128-sample tail metric.",
        "- As a result, the left tail for `PoF eps=0.0` should be interpreted together with the separate no-final mass, not as a complete all-sample distribution.",
    ]

    plot_grid(results, OUTDIR / "summary_grid_hist_cdf.png")
    write_csv(all_sample_ids, lookups, OUTDIR / "samplewise_plot_data.csv")
    (OUTDIR / "summary.md").write_text("\n".join(lines) + "\n")

    log_lines = [
        "# Step-4 no-final / active sample log summary",
        "",
        "This note summarizes the samples that do not currently have `final.jld2`.",
        "A sample is labelled `active` only if Slurm still reports it running.",
        "A sample is labelled `no-final candidate` when its job has finished but no `final.jld2` exists in the data directory.",
        "",
    ]
    for spec in SPECS:
        active = active_by_case[spec.key]
        missing = missing_by_case[spec.key]
        if not active and not missing:
            continue
        log_lines.append(f"## {spec.title}")
        if active:
            log_lines.append(f"- active samples: `{', '.join(map(str, active))}`")
        if missing:
            log_lines.append(f"- no-final candidates: `{', '.join(map(str, missing))}`")
            if spec.key == "pof_eps0.0":
                log_lines.append("- These `PoF eps=0.0` no-final candidates all failed with `first_forward failed even at minimum injection rate 0.0001`.")
        log_lines.append("")
    if len(log_lines) == 6:
        log_lines += ["All samples currently have `final.jld2` or are still active.", ""]
    (OUTDIR / "no_final_samples_summary.md").write_text("\n".join(log_lines) + "\n")


if __name__ == "__main__":
    import sys
    if "--paper-export" in sys.argv:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from export_posterior_appendix_e import main as export_main
        export_main([arg for arg in sys.argv[1:] if arg != "--paper-export"], family="statistical", steps=[4])
    else:
        main()
