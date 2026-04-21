#!/usr/bin/env python3
"""
Rebuild posterior analysis plots/videos from the updated JLD2 file.

Stored array layout in Julia:
    (x, z, variable, sample) = (512, 256, 2, 128)

When read with h5py, the dataset appears as:
    (sample, variable, z, x) = (128, 2, 256, 512)
"""

import os
import shutil
import argparse
from pathlib import Path

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_POSTERIOR_JLD2 = os.path.join(
    PROJECT_ROOT, "data", "posterior", "three_set_posteriro_samples_t1_pof_cvar.jld2"
)

import h5py
import imageio
import matplotlib
import numpy as np
import colorcet as cc
import cmasher

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.gridspec import GridSpec

NX, NZ = 512, 256
NSAMPLES_EXPECTED = 128
DX, DZ = 6.25, 6.25
EXTENT = [0, (NX - 1) * DX, (NZ - 1) * DZ, 0]
FRAME_SIZE = (12.8, 6.4)  # 1280 x 640 at dpi=100, divisible by 16
FIG_DPI = 100

CASES = {
    "X_post1": r"POF $\varepsilon=0.0$ (CVaR $\gamma=0.0$)",
    "X_post2": r"POF $\varepsilon=0.01$",
    "X_post3": r"CVaR $\gamma=0.1$, $\alpha=0.01$",
}

CASE_SHORT = {
    "X_post1": "POF_eps0.0",
    "X_post2": "POF_eps0.01",
    "X_post3": "CVaR_g0.1_a0.01",
}

VAR_CONFIG = {
    "relative_margin": {
        "index": None,
        "title": "Relative Margin",
        "slug": "relative_margin",
        "cmap": None,
        "label": r"$r = (p_{\mathrm{frac}} - p) / p_{\mathrm{frac}}$",
        "display_scale": 1.0,
        "fixed_vmin": -0.1,
        "fixed_vmax": 1.0,
    },
    "sat": {
        "index": 0,
        "title": r"CO$_2$ Saturation",
        "slug": "sat",
        "cmap": None,
        "label": r"CO$_2$ Saturation",
        "display_scale": 1.0,
        "fixed_vmin": 0.0,
        "fixed_vmax": 0.9,
    },
    "pressure": {
        "index": 1,
        "title": "Reservoir Pressure",
        "slug": "pressure",
        "cmap": None,
        "label": "Reservoir Pressure [MPa]",
        "display_scale": 1e-6,
        "fixed_vmin": None,
        "fixed_vmax": None,
    },
    "pressure_diff": {
        "index": None,
        "title": "Pressure Difference",
        "slug": "pressure_diff",
        "cmap": None,
        "label": r"$p - p_{w,0}$ [MPa]",
        "display_scale": 1e-6,
        "fixed_vmin": None,
        "fixed_vmax": None,
    },
}


def make_rainforest_r():
    colors_data = [
        (0.0, "#2d004b"),
        (0.15, "#1b4332"),
        (0.35, "#2d6a4f"),
        (0.55, "#52b788"),
        (0.75, "#95d5b2"),
        (0.90, "#d8f3dc"),
        (1.0, "#ffffff"),
    ]
    positions = [c[0] for c in colors_data]
    hex_colors = [c[1] for c in colors_data]
    rgb = [matplotlib.colors.to_rgb(h) for h in hex_colors]
    cdict = {"red": [], "green": [], "blue": []}
    for pos, (r, g, b) in zip(positions, rgb):
        cdict["red"].append((pos, r, r))
        cdict["green"].append((pos, g, g))
        cdict["blue"].append((pos, b, b))
    return LinearSegmentedColormap("rainforest_r", cdict)


CMAP_SAT = cmasher.rainforest_r
CMAP_PRES = cc.cm["CET_L3_r"]
CMAP_MARGIN = LinearSegmentedColormap.from_list(
    "relative_margin_map",
    [
        (0.00, "#7f0000"),
        (0.08, "#ef8a62"),
        (0.10, "#f7f7f7"),
        (0.45, "#d1e5f0"),
        (0.75, "#67a9cf"),
        (1.00, "#2166ac"),
    ],
)
VAR_CONFIG["sat"]["cmap"] = CMAP_SAT
VAR_CONFIG["pressure"]["cmap"] = CMAP_PRES
VAR_CONFIG["pressure_diff"]["cmap"] = CMAP_PRES
VAR_CONFIG["relative_margin"]["cmap"] = CMAP_MARGIN


def load_samples(filepath):
    f = h5py.File(filepath, "r")
    pres_hyd = f["pres_Hyd"][:].astype(np.float32)
    p_max = pres_hyd + np.float32(4.0e6)

    samples = {}
    for key in CASES:
        arr = f[key][:]  # h5py view: (sample, variable, z, x)
        if arr.shape != (NSAMPLES_EXPECTED, 2, NZ, NX):
            raise ValueError(f"{key} has unexpected shape {arr.shape}")
        pressure = arr[:, 1, :, :].astype(np.float32)
        samples[key] = {
            "sat": arr[:, 0, :, :].astype(np.float32),
            "pressure": pressure,
            "pressure_diff": pressure - pres_hyd[None, :, :],
            "relative_margin": (p_max[None, :, :] - pressure) / np.maximum(np.float32(1e-9), p_max[None, :, :]),
        }
    f.close()
    return samples, pres_hyd


def ensure_clean_output_dir(out_dir):
    if not os.path.isdir(out_dir):
        return
    for name in os.listdir(out_dir):
        if name.endswith((".png", ".mp4")) or name.startswith("frames_"):
            path = os.path.join(out_dir, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.remove(path)


def get_std_vmax(fields):
    vmax = float(np.std(fields, axis=0).max())
    return max(vmax * 1.05, 1e-6)


def to_display_units(fields, var_name):
    return fields * VAR_CONFIG[var_name]["display_scale"]


def get_display_limits(samples, var_name):
    cfg = VAR_CONFIG[var_name]
    if cfg["fixed_vmin"] is not None and cfg["fixed_vmax"] is not None:
        return cfg["fixed_vmin"], cfg["fixed_vmax"]

    all_fields = [to_display_units(samples[key][var_name], var_name) for key in CASES]
    vmin = min(float(fields.min()) for fields in all_fields)
    vmax = max(float(fields.max()) for fields in all_fields)
    return vmin, vmax


def draw_field(ax, field, cmap, vmin, vmax, title, add_xlabel=True, add_ylabel=False):
    im = ax.imshow(field, extent=EXTENT, cmap=cmap, vmin=vmin, vmax=vmax)
    ax.set_title(title, fontsize=11)
    if add_xlabel:
        ax.set_xlabel("X [m]", fontsize=11)
    if add_ylabel:
        ax.set_ylabel("Depth [m]", fontsize=11)
    return im


def save_figure(fig, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fig.savefig(path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


def plot_uncertainty_grid(samples, var_name, out_dir, monitoring_step_label):
    cfg = VAR_CONFIG[var_name]
    fig, axes = plt.subplots(2, 3, figsize=(16, 7))
    keys = list(CASES.keys())
    mean_vmin, mean_vmax = get_display_limits(samples, var_name)

    std_vmax = max(get_std_vmax(to_display_units(samples[key][var_name], var_name)) for key in keys)

    for col, key in enumerate(keys):
        fields = to_display_units(samples[key][var_name], var_name)
        mean_field = np.mean(fields, axis=0)
        std_field = np.std(fields, axis=0)

        im = draw_field(
            axes[0, col],
            mean_field,
            cfg["cmap"],
            mean_vmin,
            mean_vmax,
            f"{CASES[key]}\nMean (n={fields.shape[0]})",
            add_xlabel=False,
            add_ylabel=(col == 0),
        )
        fig.colorbar(im, ax=axes[0, col], fraction=0.046, pad=0.04)

        im = draw_field(
            axes[1, col],
            std_field,
            "inferno",
            0.0,
            std_vmax,
            "Std Dev",
            add_xlabel=True,
            add_ylabel=(col == 0),
        )
        fig.colorbar(im, ax=axes[1, col], fraction=0.046, pad=0.04)

    fig.suptitle(
        f"Posterior {cfg['title']} Uncertainty (Monitoring Step {monitoring_step_label})",
        fontsize=14,
        fontweight="bold",
    )
    plt.tight_layout()
    save_figure(fig, os.path.join(out_dir, f"{cfg['slug']}_uncertainty_all_cases.png"))


def plot_uncertainty_individual(samples, var_name, out_dir):
    cfg = VAR_CONFIG[var_name]
    mean_vmin, mean_vmax = get_display_limits(samples, var_name)
    for key in CASES:
        fields = to_display_units(samples[key][var_name], var_name)
        mean_field = np.mean(fields, axis=0)
        std_field = np.std(fields, axis=0)
        std_vmax = get_std_vmax(fields)

        fig, axes = plt.subplots(2, 1, figsize=(12, 8))

        im = draw_field(
            axes[0],
            mean_field,
            cfg["cmap"],
            mean_vmin,
            mean_vmax,
            f"Mean {cfg['title']} (n={fields.shape[0]} samples)",
            add_xlabel=False,
            add_ylabel=True,
        )
        clb = fig.colorbar(im, ax=axes[0], fraction=0.046, pad=0.04)
        clb.set_label(cfg["label"], fontsize=11)

        im = draw_field(
            axes[1],
            std_field,
            "inferno",
            0.0,
            std_vmax,
            f"{cfg['title']} Standard Deviation",
            add_xlabel=True,
            add_ylabel=True,
        )
        clb = fig.colorbar(im, ax=axes[1], fraction=0.046, pad=0.04)
        clb.set_label("Standard Deviation", fontsize=11)

        fig.suptitle(CASES[key], fontsize=14, fontweight="bold")
        plt.tight_layout()
        save_figure(
            fig,
            os.path.join(out_dir, f"{cfg['slug']}_uncertainty_{CASE_SHORT[key]}.png"),
        )


def plot_median_grid(samples, out_dir, monitoring_step_label):
    fig, axes = plt.subplots(3, 3, figsize=(16, 10))
    keys = list(CASES.keys())
    sat_vmin, sat_vmax = get_display_limits(samples, "sat")
    pres_vmin, pres_vmax = get_display_limits(samples, "pressure")
    diff_vmin, diff_vmax = get_display_limits(samples, "pressure_diff")

    for col, key in enumerate(keys):
        sat_med = np.median(to_display_units(samples[key]["sat"], "sat"), axis=0)
        pres_med = np.median(to_display_units(samples[key]["pressure"], "pressure"), axis=0)
        diff_med = np.median(to_display_units(samples[key]["pressure_diff"], "pressure_diff"), axis=0)

        im = draw_field(
            axes[0, col],
            sat_med,
            VAR_CONFIG["sat"]["cmap"],
            sat_vmin,
            sat_vmax,
            CASES[key],
            add_xlabel=False,
            add_ylabel=(col == 0),
        )
        fig.colorbar(im, ax=axes[0, col], fraction=0.046, pad=0.04)

        im = draw_field(
            axes[1, col],
            pres_med,
            VAR_CONFIG["pressure"]["cmap"],
            pres_vmin,
            pres_vmax,
            CASES[key],
            add_xlabel=True,
            add_ylabel=(col == 0),
        )
        fig.colorbar(im, ax=axes[1, col], fraction=0.046, pad=0.04)

        im = draw_field(
            axes[2, col],
            diff_med,
            VAR_CONFIG["pressure_diff"]["cmap"],
            diff_vmin,
            diff_vmax,
            CASES[key],
            add_xlabel=True,
            add_ylabel=(col == 0),
        )
        fig.colorbar(im, ax=axes[2, col], fraction=0.046, pad=0.04)

    axes[0, 0].set_ylabel("Depth [m]\n\nMedian CO$_2$ Saturation", fontsize=11)
    axes[1, 0].set_ylabel("Depth [m]\n\nMedian Pressure", fontsize=11)
    axes[2, 0].set_ylabel("Depth [m]\n\nMedian Pressure Difference", fontsize=11)
    fig.suptitle(
        f"Pointwise Median over 128 Posterior Samples ({monitoring_step_label})",
        fontsize=14,
        fontweight="bold",
    )
    plt.tight_layout()
    save_figure(fig, os.path.join(out_dir, "state_median_all_cases.png"))


def plot_paper_style_summary(samples, out_dir, stat_name, monitoring_step_label):
    is_mean = stat_name == "mean"
    fig = plt.figure(figsize=(16.0, 8.9))
    gs = GridSpec(
        3,
        4,
        figure=fig,
        width_ratios=[1.0, 1.0, 1.0, 0.035],
        hspace=0.10,
        wspace=0.10,
    )

    keys = list(CASES.keys())
    col_titles = [
        r"(a) POF $\varepsilon = 0.0$",
        r"(b) POF $\varepsilon = 0.01$",
        r"(c) CVaR $\gamma = 0.1, \alpha = 0.01$",
    ]
    row_vars = ["relative_margin", "pressure_diff", "sat"]
    row_labels = (
        ["Relative Margin", "Pressure Difference", r"CO$_2$ Saturation"]
        if is_mean
        else ["Relative Margin Std Dev", "Pressure Diff. Std Dev", r"CO$_2$ Sat. Std Dev"]
    )

    if is_mean:
        value_ranges = {
            var_name: get_display_limits(samples, var_name)
            for var_name in row_vars
        }
    else:
        value_ranges = {
            var_name: (
                0.0,
                max(get_std_vmax(to_display_units(samples[key][var_name], var_name)) for key in keys),
            )
            for var_name in row_vars
        }

    for row, var_name in enumerate(row_vars):
        cfg = VAR_CONFIG[var_name]
        row_images = []
        for col, key in enumerate(keys):
            ax = fig.add_subplot(gs[row, col])
            fields = to_display_units(samples[key][var_name], var_name)
            field = np.mean(fields, axis=0) if is_mean else np.std(fields, axis=0)
            vmin, vmax = value_ranges[var_name]
            cmap = cfg["cmap"] if is_mean else "inferno"
            im = ax.imshow(field, extent=EXTENT, cmap=cmap, vmin=vmin, vmax=vmax)
            row_images.append(im)
            if row == 0:
                ax.set_title(col_titles[col], fontsize=18, fontweight="bold", pad=3)
            if col == 0:
                ylabel_fs = 19 if is_mean else 17
                ax.set_ylabel(f"{row_labels[row]}\nDepth [m]", fontsize=ylabel_fs)
            else:
                ax.set_yticklabels([])
            if row == 2:
                ax.set_xlabel("X [m]", fontsize=19)
            else:
                ax.set_xticklabels([])
            ax.tick_params(labelsize=14, length=3, pad=2)

        cax = fig.add_subplot(gs[row, 3])
        if is_mean and var_name == "relative_margin":
            cbar = fig.colorbar(row_images[-1], cax=cax, extend="min")
            cbar.set_ticks([0.0, 0.25, 0.5, 0.75, 1.0])
            cbar.set_ticklabels(["0", "0.25", "0.5", "0.75", "1.0"])
            cbar.ax.tick_params(labelsize=14, pad=1, length=2)
            cbar.ax.text(
                0.5,
                1.02,
                "(safe)",
                transform=cbar.ax.transAxes,
                fontsize=10.5,
                ha="center",
                va="bottom",
                fontstyle="italic",
            )
            cbar.ax.text(
                0.5,
                -0.06,
                "<0 (frac.)",
                transform=cbar.ax.transAxes,
                fontsize=10.5,
                ha="center",
                va="top",
                fontstyle="italic",
            )
        else:
            cbar = fig.colorbar(row_images[-1], cax=cax)
            cbar.ax.tick_params(labelsize=14)
        if var_name == "pressure_diff":
            cbar.set_label("MPa", fontsize=16)

    title = (
        f"Pointwise Posterior Mean over 128 Samples ({monitoring_step_label})"
        if is_mean
        else f"Pointwise Posterior Std Dev over 128 Samples ({monitoring_step_label})"
    )
    fig.suptitle(title, fontsize=27, fontweight="bold", y=0.962)
    fig.subplots_adjust(left=0.075, right=0.965, top=0.885, bottom=0.10)
    out_name = "state_mean_all_cases.png" if is_mean else "state_std_all_cases.png"
    save_figure(fig, os.path.join(out_dir, out_name))


def render_frame(field, case_label, sample_idx, n_samp, var_name):
    cfg = VAR_CONFIG[var_name]
    fig, ax = plt.subplots(figsize=FRAME_SIZE, dpi=FIG_DPI)
    im = ax.imshow(field, extent=EXTENT, cmap=cfg["cmap"], vmin=cfg["vmin"], vmax=cfg["vmax"])
    clb = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    clb.set_label(cfg["label"], fontsize=11)
    ax.set_title(f"{case_label}  |  {cfg['title']}  |  Posterior Sample {sample_idx + 1}/{n_samp}", fontsize=13)
    ax.set_xlabel("X [m]", fontsize=11)
    ax.set_ylabel("Depth [m]", fontsize=11)
    plt.tight_layout()

    fig.canvas.draw()
    rgba = np.asarray(fig.canvas.buffer_rgba())
    frame = rgba[:, :, :3].copy()
    plt.close(fig)
    return frame


def generate_sample_video(fields, case_label, case_short, var_name, out_dir, fps=5):
    cfg = VAR_CONFIG[var_name]
    video_path = os.path.join(out_dir, f"{cfg['slug']}_animation_{case_short}.mp4")
    os.makedirs(os.path.dirname(video_path), exist_ok=True)
    writer = imageio.get_writer(
        video_path,
        fps=fps,
        codec="libx264",
        pixelformat="yuv420p",
        quality=8,
        macro_block_size=16,
    )

    n_samp = fields.shape[0]
    for i in range(n_samp):
        writer.append_data(render_frame(fields[i], case_label, i, n_samp, var_name))
        if (i + 1) % 16 == 0 or i == n_samp - 1:
            print(f"    {cfg['title']} frame {i + 1}/{n_samp}")

    writer.close()
    print(f"  Video: {video_path}")


def print_summary(samples):
    print("\n--- Data Summary ---")
    for key in CASES:
        print(f"{CASES[key]}:")
        for var_name in ["sat", "pressure"]:
            fields = samples[key][var_name]
            print(
                f"  {var_name}: shape={fields.shape}, min={fields.min():.6f}, "
                f"max={fields.max():.6f}, mean={fields.mean():.6f}, std={fields.std():.6f}"
            )


def infer_monitoring_step(path: str) -> str:
    stem = Path(path).stem
    for token in stem.split("_"):
        if token.startswith("t") and token[1:].isdigit():
            return token
    return "unknown"


def default_outdir_for(path: str) -> str:
    stem = Path(path).stem
    return os.path.join("plots", f"posterior_field_uncertainty_{stem}")


def parse_args():
    parser = argparse.ArgumentParser(description="Posterior field uncertainty analysis")
    parser.add_argument(
        "--input",
        default=DEFAULT_POSTERIOR_JLD2,
        help="Path to posterior JLD2 file",
    )
    parser.add_argument(
        "--outdir",
        default=None,
        help="Output directory for generated plots and videos",
    )
    parser.add_argument(
        "--monitoring-step",
        default=None,
        help="Monitoring step label used in figure titles, e.g. t=1 or t=2",
    )
    parser.add_argument(
        "--skip-videos",
        action="store_true",
        help="Generate plots only and skip MP4 animations",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    data_file = args.input
    out_dir = args.outdir or default_outdir_for(data_file)
    monitoring_step = args.monitoring_step or infer_monitoring_step(data_file)
    monitoring_step_label = monitoring_step if monitoring_step.startswith("t=") else monitoring_step
    if monitoring_step_label.startswith("t") and "=" not in monitoring_step_label:
        monitoring_step_label = monitoring_step_label.replace("t", "t=", 1)
    if not monitoring_step_label.startswith("t"):
        monitoring_step_label = f"t={monitoring_step_label}"

    ensure_clean_output_dir(out_dir)
    print("Loading posterior samples...")
    samples, pres_hyd = load_samples(data_file)
    print_summary(samples)
    print(
        f"\npres_Hyd: shape={pres_hyd.shape}, min={pres_hyd.min():.1f}, "
        f"max={pres_hyd.max():.1f}, mean={pres_hyd.mean():.1f}"
    )

    print("\nGenerating uncertainty plots...")
    for var_name in ["sat", "pressure", "pressure_diff"]:
        plot_uncertainty_grid(samples, var_name, out_dir, monitoring_step_label)
        plot_uncertainty_individual(samples, var_name, out_dir)

    print("\nGenerating pointwise median figure...")
    plot_median_grid(samples, out_dir, monitoring_step_label)
    print("Generating paper-style mean/std summary figures...")
    plot_paper_style_summary(samples, out_dir, "mean", monitoring_step_label)
    plot_paper_style_summary(samples, out_dir, "std", monitoring_step_label)

    if args.skip_videos:
        print("\nSkipping sample videos (--skip-videos).")
    else:
        print("\nGenerating all sample videos...")
        for var_name in ["sat", "pressure"]:
            vmin, vmax = get_display_limits(samples, var_name)
            VAR_CONFIG[var_name]["vmin"] = vmin
            VAR_CONFIG[var_name]["vmax"] = vmax
        for key in CASES:
            print(f"  Processing {CASES[key]}...")
            for var_name in ["sat", "pressure"]:
                generate_sample_video(
                    to_display_units(samples[key][var_name], var_name),
                    CASES[key],
                    CASE_SHORT[key],
                    var_name,
                    out_dir,
                    fps=5,
                )

    print("\nDone. Outputs written to:", out_dir)


if __name__ == "__main__":
    main()
