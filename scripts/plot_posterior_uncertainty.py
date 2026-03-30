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

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POSTERIOR_JLD2 = os.path.join(
    PROJECT_ROOT, "data", "three_set_posteriro_samples_t1_pof_cvar.jld2"
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
VAR_CONFIG["sat"]["cmap"] = CMAP_SAT
VAR_CONFIG["pressure"]["cmap"] = CMAP_PRES
VAR_CONFIG["pressure_diff"]["cmap"] = CMAP_PRES


def load_samples(filepath):
    f = h5py.File(filepath, "r")
    pres_hyd = f["pres_Hyd"][:]

    samples = {}
    for key in CASES:
        arr = f[key][:]  # h5py view: (sample, variable, z, x)
        if arr.shape != (NSAMPLES_EXPECTED, 2, NZ, NX):
            raise ValueError(f"{key} has unexpected shape {arr.shape}")
        samples[key] = {
            "sat": arr[:, 0, :, :].astype(np.float32),
            "pressure": arr[:, 1, :, :].astype(np.float32),
            "pressure_diff": arr[:, 1, :, :].astype(np.float32) - pres_hyd[None, :, :].astype(np.float32),
        }
    f.close()
    return samples, pres_hyd


def ensure_clean_output_dir(out_dir):
    os.makedirs(out_dir, exist_ok=True)
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
    fig.savefig(path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"  Saved: {path}")


def plot_uncertainty_grid(samples, var_name, out_dir):
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

    fig.suptitle(f"Posterior {cfg['title']} Uncertainty (Monitoring Step t=1)", fontsize=14, fontweight="bold")
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


def plot_median_grid(samples, out_dir):
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
    fig.suptitle("Pointwise Median over 128 Posterior Samples", fontsize=14, fontweight="bold")
    plt.tight_layout()
    save_figure(fig, os.path.join(out_dir, "state_median_all_cases.png"))


def plot_paper_style_summary(samples, out_dir, stat_name):
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
    row_vars = ["sat", "pressure", "pressure_diff"]
    row_labels = (
        [r"CO$_2$ Saturation", "Pressure", "Pressure Difference"]
        if is_mean
        else [r"CO$_2$ Sat. Std Dev", "Pressure Std Dev", "Pressure Diff. Std Dev"]
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
        cbar = fig.colorbar(row_images[-1], cax=cax)
        cbar.ax.tick_params(labelsize=14)
        if var_name != "sat":
            cbar.set_label("MPa", fontsize=16)

    title = "Pointwise Posterior Mean over 128 Samples" if is_mean else "Pointwise Posterior Std Dev over 128 Samples"
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


def main():
    data_file = POSTERIOR_JLD2
    out_dir = "plots/posterior_field_uncertainty"

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
        plot_uncertainty_grid(samples, var_name, out_dir)
        plot_uncertainty_individual(samples, var_name, out_dir)

    print("\nGenerating pointwise median figure...")
    plot_median_grid(samples, out_dir)
    print("Generating paper-style mean/std summary figures...")
    plot_paper_style_summary(samples, out_dir, "mean")
    plot_paper_style_summary(samples, out_dir, "std")

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
