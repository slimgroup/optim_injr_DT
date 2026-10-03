#!/usr/bin/env python3
"""Render existing joint k=1 posteriors as a 3x3 comparison, without simulation.

Reuse the audited two-panel export's source, reference statistics and encoding.
All files are created under a new output directory; historical media stay intact.
"""
from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import shutil

os.environ.setdefault('MPLBACKEND', 'Agg')
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.text import Text
import colorcet as cc
import cmasher
import imageio_ffmpeg
from PIL import Image

import create_posterior_sample_video as base

CASES = [base.CASES[1], base.CASES[0], base.CASES[2]]
ROWS = [
    ('pressure_difference_MPa', 'Pressure difference\nDepth [m]', r'$p-p_0$ [MPa]', [-0.2, 5.2], cc.cm['CET_L3_r'], [0, 1, 2, 3, 4, 5]),
    ('pressure_MPa', 'Absolute pressure\nDepth [m]', 'MPa', [0.0, 18.0], cc.cm['CET_L3_r'], [0, 5, 10, 15]),
    ('saturation', 'CO$_2$ saturation\nDepth [m]', 'Dimensionless', [0.0, 0.9], cmasher.rainforest_r, [0, 0.2, 0.4, 0.6, 0.8]),
]


def make_figure():
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 18,
                         'axes.labelsize': 19, 'axes.linewidth': 0.8,
                         'xtick.labelsize': 16, 'ytick.labelsize': 16})
    fig = plt.figure(figsize=(19.2, 10.8), dpi=100, facecolor='white')
    fig.text(0.5, 0.970, 'Joint posterior samples across three control cases',
             ha='center', va='center', fontsize=28, weight='bold')
    sample_text = fig.text(0.5, 0.924, '', ha='center', va='center', fontsize=21)
    images = []
    data_axes = []
    colorbars = []
    height = 0.26 * 1920 / 1080 / (base.EXTENT[1] / base.EXTENT[2])
    for row, (_, ylabel, unit, limits, cmap, ticks) in enumerate(ROWS):
        bottom = 0.858 - height - row * 0.251
        for col, (_, _, title, _) in enumerate(CASES):
            ax = fig.add_axes([0.090 + col * 0.280, bottom, 0.260, height])
            im = ax.imshow(np.zeros((256, 512), dtype=np.float32),
                           origin='upper', extent=base.EXTENT, interpolation='nearest',
                           cmap=cmap, vmin=limits[0], vmax=limits[1])
            ax.set_xticks([0, 500, 1000, 1500, 2000, 2500, 3000])
            ax.set_yticks([0, 500, 1000, 1500])
            ax.tick_params(length=3, pad=3, labelbottom=(row == 2), labelleft=(col == 0))
            if row == 0:
                ax.set_title(f'({"abc"[col]}) {title}', fontsize=21, weight='bold', pad=10)
            if col == 0:
                ax.set_ylabel(ylabel, fontsize=19, labelpad=9)
            if row == 2:
                ax.set_xlabel('X [m]', fontsize=20, labelpad=4)
            data_axes.append(ax)
            images.append(im)
        cax = fig.add_axes([0.929, bottom, 0.011, height])
        cb = fig.colorbar(images[-1], cax=cax, ticks=ticks)
        cb.set_label(unit, fontsize=18, labelpad=8)
        cb.ax.tick_params(labelsize=16, pad=4, length=3)
        colorbars.append(cax)
    fig.text(0.5, 0.027, 'Different samples at the same time', ha='center', va='center',
             fontsize=20, weight='bold')
    return fig, images, sample_text, data_axes, colorbars


def set_sample(images, sample_text, source, p0, sample_id):
    displayed = {}
    for col, (key, _, _, _) in enumerate(CASES):
        joint = source[key][sample_id - 1]
        pressure = joint[1]
        fields = [(pressure - p0) * np.float32(1e-6), pressure * np.float32(1e-6), joint[0]]
        for row, field in enumerate(fields):
            images[row * 3 + col].set_data(field)
        displayed[key] = sample_id
    sample_text.set_text(r'Monitoring step $k=1$  |  Nominal day 480  |  '
                         f'Posterior sample {sample_id} / 128')
    return displayed


def check_layout(fig, axes, colorbars):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    visible = []
    for artist in fig.findobj(Text):
        if not artist.get_visible() or not artist.get_text().strip():
            continue
        box = artist.get_window_extent(renderer)
        if not box.width or not box.height:
            continue
        if box.x0 < 0 or box.y0 < 0 or box.x1 > 1920 or box.y1 > 1080:
            raise ValueError(f'Text outside canvas: {artist.get_text()} {box}')
        visible.append((artist.get_text(), box))
    # Check labels and annotations against each other, not only the canvas.
    for i, (a, box_a) in enumerate(visible):
        for b, box_b in visible[i + 1:]:
            if box_a.overlaps(box_b):
                raise ValueError(f'Overlapping text: {a!r} and {b!r}')
    sizes = [(ax.bbox.width, ax.bbox.height) for ax in axes]
    assert len(sizes) == 9 and np.allclose(sizes, sizes[0])
    for row, cax in enumerate(colorbars):
        assert np.allclose([cax.bbox.y0, cax.bbox.y1],
                           [axes[row * 3].bbox.y0, axes[row * 3].bbox.y1])
    return {'visible_text_inside_canvas': True, 'no_overlapping_text': True,
            'equal_panel_pixels': list(sizes[0]), 'colorbars_aligned_with_rows': True,
            'checked_text_count': len(visible)}


def validate_pressure_difference(source):
    results = []
    with h5py.File(source, 'r', locking=False) as f:
        p0 = f['pres_Hyd'][:]
        for key, _, _, label in CASES:
            dp = (f[key][:, 1] - p0) * np.float32(1e-6)
            low, high = float(dp.min()), float(dp.max())
            finite = bool(np.isfinite(dp).all())
            result = {'case': label, 'dataset': key, 'min_MPa': low,
                      'max_MPa': high, 'all_finite': finite}
            results.append(result)
            print('Pressure difference:', result, flush=True)
            assert finite and ROWS[0][3][0] <= low <= high <= ROWS[0][3][1]
    return results


def write_delivery(out, report, delta_audit, layout, videos):
    caption = ('Joint posterior pressure difference (p-p0), absolute pressure and CO2 saturation '
               'at monitoring step k=1 (nominal day 480). Columns show PoF epsilon=0, PoF '
               'epsilon=0.01 and CVaR alpha=0.01, gamma=0.1. Each frame advances the stored sample '
               'index while physical time stays fixed; pressure and saturation remain paired '
               'within each case. Equal indices across cases do not imply the same physical realization.')
    with (out / 'caption.txt').open('x') as f:
        f.write(caption + '\n')
    base.write_json(out / 'combined_provenance.json', {
        'source': report['source'], 'columns': [case[0] for case in CASES],
        'rows': [row[0] for row in ROWS], 'limits': {row[0]: row[3] for row in ROWS},
        'pressure_difference': '(stored pressure - pres_Hyd) * float32(1e-6)',
        'pressure_difference_audit': delta_audit, 'layout': layout,
        'time_label': 'Nominal day 480', 'monitoring_step': 1,
        'user_provenance_update': 'User identifies colleague Abhinav as the posterior producer and considers the day-480 first-monitoring posterior, case mapping and joint pairing correct. Original observation identity remains uncertain; upstream preprocessing is unconfirmed.',
        'pairing': 'Same original sample index for both channels within a case; independent posterior realizations across cases.',
        'statistical_reference_check': report['numeric_reference_match'],
        'unresolved_issues': report['unresolved_issues'], 'videos': videos,
    })
    with (out / 'provenance.csv').open('x', newline='') as f:
        fields = ['case', 'dataset', 'source', 'step', 'time', 'M', 'version',
                  'displayed_sample_ids', 'pressure_difference_limits_MPa', 'pressure_limits_MPa',
                  'saturation_limits', 'mean_std_check', 'video']
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for case in CASES:
            for video in videos:
                writer.writerow(dict(case=case[3], dataset=case[0], source=report['source']['path'],
                                     step=1, time='Nominal day 480', M=128, version=video['version'],
                                     displayed_sample_ids=' '.join(map(str, video['sample_ids'])),
                                     pressure_difference_limits_MPa='-0.2 5.2', pressure_limits_MPa='0 18',
                                     saturation_limits='0 0.9', mean_std_check='Exact float32 equality; ddof=0',
                                     video=video['path']))
    lines = ['# All-case posterior sample comparison', '', caption, '',
             '- [96-second full video, samples 1–128](posterior_all_cases_k1_full.mp4)',
             '- [24-second talk video, fixed 32-sample subset](posterior_all_cases_k1_talk.mp4)',
             '- [PNG poster, sample 1](poster.png)', '',
             'Layout matches the requested reference: columns are PoF epsilon=0, PoF epsilon=0.01, CVaR alpha=0.01 gamma=0.1; rows are pressure difference, absolute pressure and saturation. All nine panels have the same size and the three colorbars align with their rows.', '',
             '1920x1080, H.264/yuv420p, 24 fps. Each sample is held for 0.75 seconds; no blending, temporal interpolation or independent shuffling. Only existing t1 arrays are read. No inference, optimization, simulation or new fracture-risk estimate is performed.', '',
             'Shared fixed limits: pressure difference -0.2 to 5.2 MPa, absolute pressure 0 to 18 MPa, saturation 0 to 0.9. Pressure difference uses the matching pres_Hyd from the same posterior file. Every saved value falls within these limits; no clipping or replacement is applied.', '',
             'The full video shows each original array index 1–128. Talk sample IDs: ' + ', '.join(map(str, base.SHORT_IDS)) + '. These indices are selected uniformly in array order, not by appearance. The poster is sample 1.', '',
             'Grid orientation and extent follow the source plots: h5py [z,x], origin upper, depth increasing downward, x=0–3193.75 m and depth=0–1593.75 m. No invented well geometry or permeability pairing is added.', '',
             'The original 18 mean/std reference checks passed exactly, including the pressure-difference row, with the historical float32 and population-std convention (ddof=0). Pressure and pressure-increment std are mathematically redundant; this movie displays individual fields rather than summary statistics.', '',
             'Time remains labeled Nominal day 480: this matches the repository timeline and the user considers it correct, but the source file has no embedded timestamp. The user identifies Abhinav as the posterior producer. Original observation IDs and upstream preprocessing remain unverified. Details are retained in audit.json and combined_provenance.json.', '',
             'All historical videos, samples, schedules and slides are preserved. Scripts used for this export are snapshotted under provenance/.', '',
             'Reproduce in a new directory:', '', '```bash',
             'sbatch scripts/shell/submit/submit_posterior_all_cases_video.sh --output plots/posterior_sample_videos/NEW_DIRECTORY',
             '```', '']
    with (out / 'README.md').open('x') as f:
        f.write('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not os.environ.get('SLURM_JOB_ID'):
        parser.error('Animation rendering must run via sbatch or salloc on PACE.')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    provenance = out / 'provenance'
    provenance.mkdir()
    for source in [Path(__file__), Path(base.__file__),
                   base.ROOT / 'scripts/shell/submit/submit_posterior_all_cases_video.sh']:
        shutil.copyfile(source, provenance / source.name)
    report = base.audit(out)
    delta_audit = validate_pressure_difference(base.SOURCE)
    frames = out / 'frames'
    frames.mkdir()
    fig, images, sample_text, axes, colorbars = make_figure()
    with h5py.File(base.SOURCE, 'r', locking=False) as source:
        p0 = source['pres_Hyd'][:]
        set_sample(images, sample_text, source, p0, 128)
        layout = check_layout(fig, axes, colorbars)
        with (out / 'frame_samples.csv').open('x', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['frame_file', 'X_post1', 'X_post2', 'X_post3'])
            writer.writeheader()
            for sample_id in range(1, 129):
                ids = set_sample(images, sample_text, source, p0, sample_id)
                if sample_id == 1:
                    check_layout(fig, axes, colorbars)
                fig.canvas.draw()
                path = frames / f'sample_{sample_id:03d}.png'
                Image.fromarray(np.asarray(fig.canvas.buffer_rgba())).save(path)
                writer.writerow({'frame_file': path.name, **ids})
                if sample_id in [1, 32, 64, 96, 128]:
                    print(f'Rendered joint sample {sample_id}/128', flush=True)
    plt.close(fig)
    shutil.copyfile(frames / 'sample_001.png', out / 'poster.png')
    videos = []
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    for version, ids in [('full', list(range(1, 129))), ('talk', base.SHORT_IDS)]:
        path = out / f'posterior_all_cases_k1_{version}.mp4'
        command = base.encode(ffmpeg, frames, ids, path)
        verified = base.verify_video(ffmpeg, path, len(ids) * base.HOLD_FRAMES)
        videos.append({'version': version, 'path': path.name, 'sample_ids': ids,
                       'sha256': base.sha(path), 'duration_seconds': len(ids) * base.HOLD_FRAMES / base.FPS,
                       'encoder_command': command, 'verification': verified})
        print(f'Encoded and verified {path}', flush=True)
    assert base.sha(base.SOURCE) == report['source']['sha256']
    base.write_json(out / 'videos.json', videos)
    write_delivery(out, report, delta_audit, layout, videos)
    print(f'COMPLETE: {out}', flush=True)


if __name__ == '__main__':
    main()
