#!/usr/bin/env python3
"""Presentation revision: ~36 s, plain title, day 480, no explanatory footer.

Recommended six-panel view contains pressure difference and saturation. An
otherwise matched nine-panel version retains absolute pressure for review.
Reads only previously saved posterior arrays; rendering requires Slurm.
"""
from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import shutil
import subprocess

os.environ.setdefault('MPLBACKEND', 'Agg')
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.text import Text
from PIL import Image
import imageio_ffmpeg

import create_posterior_all_cases_video as previous

base = previous.base
FPS = 25
HOLD_FRAMES = 7
SAMPLE_COUNT = 128
DURATION = SAMPLE_COUNT * HOLD_FRAMES / FPS  # 35.84 s, equal hold for every sample


def make_figure(include_absolute, compact=False):
    rows = previous.ROWS if include_absolute else [previous.ROWS[0], previous.ROWS[2]]
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 18,
                         'axes.labelsize': 19, 'axes.linewidth': 0.8,
                         'xtick.labelsize': 16, 'ytick.labelsize': 16})
    fig = plt.figure(figsize=(19.2, 10.8), dpi=100, facecolor='white')
    fig.text(0.5, 0.968 if compact else (0.966 if include_absolute else 0.948), 'Posterior samples',
             ha='center', va='center', fontsize=32, weight='bold')
    sample_text = fig.text(0.5, 0.920 if compact else (0.914 if include_absolute else 0.884), '',
                           ha='center', va='center', fontsize=22)
    images, axes, colorbars = [], [], []
    height = 0.265 * 1920 / 1080 / (base.EXTENT[1] / base.EXTENT[2])
    # Keep the physical aspect ratio and full spatial extent in both versions.
    tops = [0.851, 0.600, 0.349] if include_absolute else [0.796, 0.454]
    left, width, column_step = 0.086, 0.265, 0.281
    colorbar_left, colorbar_width = 0.931, 0.011
    if compact:
        assert include_absolute, 'Compact presentation retains all three variables.'
        # Expand equal-aspect panels into the existing white margins. Pixel
        # positions keep 16 px between columns and 14 px between rows.
        left, width, column_step = 146 / 1920, 536 / 1920, 552 / 1920
        height = 536 / (base.EXTENT[1] / base.EXTENT[2]) / 1080
        tops = [1 - (145 + row * (height * 1080 + 14)) / 1080 for row in range(3)]
        colorbar_left, colorbar_width = 1810 / 1920, 18 / 1920
    for row, (_, ylabel, unit, limits, cmap, ticks) in enumerate(rows):
        bottom = tops[row] - height
        for col, (_, _, title, _) in enumerate(previous.CASES):
            ax = fig.add_axes([left + column_step * col, bottom, width, height])
            im = ax.imshow(np.zeros((256, 512), dtype=np.float32), extent=base.EXTENT,
                           origin='upper', interpolation='nearest', cmap=cmap,
                           vmin=limits[0], vmax=limits[1])
            ax.set_xticks([0, 500, 1000, 1500, 2000, 2500, 3000])
            ax.set_yticks([0, 500, 1000, 1500])
            ax.tick_params(length=3, pad=3, labelleft=(col == 0), labelbottom=(row == len(rows)-1))
            if row == 0:
                ax.set_title(f'({"abc"[col]}) {title}', fontsize=21, weight='bold', pad=7 if compact else 10)
            if col == 0:
                ax.set_ylabel(ylabel, fontsize=19, labelpad=8)
            if row == len(rows)-1:
                ax.set_xlabel('X [m]', fontsize=20, labelpad=4)
            images.append(im)
            axes.append(ax)
        cax = fig.add_axes([colorbar_left, bottom, colorbar_width, height])
        cb = fig.colorbar(images[-1], cax=cax, ticks=ticks)
        cb.set_label(unit, fontsize=18, labelpad=8)
        cb.ax.tick_params(labelsize=16, pad=4, length=3)
        colorbars.append(cax)
    return fig, images, sample_text, axes, colorbars, rows


def set_sample(images, sample_text, source, p0, sample_id, rows):
    for col, (key, _, _, _) in enumerate(previous.CASES):
        sample = source[key][sample_id-1]
        fields = {'pressure_difference_MPa': (sample[1]-p0)*np.float32(1e-6),
                  'pressure_MPa': sample[1]*np.float32(1e-6), 'saturation': sample[0]}
        for row, definition in enumerate(rows):
            images[row*3+col].set_data(fields[definition[0]])
    sample_text.set_text(r'Monitoring step $k=1$  |  Day 480  |  '
                         f'Posterior sample {sample_id} / 128')


def check_layout(fig, axes, colorbars):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    labels = []
    for artist in fig.findobj(Text):
        if not artist.get_visible() or not artist.get_text().strip():
            continue
        box = artist.get_window_extent(renderer)
        if not box.width or not box.height:
            continue
        assert 0 <= box.x0 < box.x1 <= 1920 and 0 <= box.y0 < box.y1 <= 1080, artist.get_text()
        labels.append((artist.get_text(), box))
    for i, (text, box) in enumerate(labels):
        for other_text, other_box in labels[i+1:]:
            assert not box.overlaps(other_box), (text, other_text)
    sizes = [(ax.bbox.width, ax.bbox.height) for ax in axes]
    assert len(sizes) in [6, 9] and np.allclose(sizes, sizes[0])
    for row, cb in enumerate(colorbars):
        assert np.allclose([cb.bbox.y0, cb.bbox.y1], [axes[row*3].bbox.y0, axes[row*3].bbox.y1])
    return {'visible_text_inside_canvas': True, 'no_overlapping_text': True,
            'panel_count': len(sizes), 'equal_panel_pixels': list(sizes[0]),
            'physical_aspect_preserved': True, 'row_colorbars_aligned': True}


def encode_and_verify(frames, destination):
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    # Exact rational source frame rate: each of the 128 PNGs holds for 7/25 s.
    # CFR duplication makes seven identical display frames per sample, with no blend.
    command = [ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'warning', '-n',
               '-framerate', f'{FPS}/{HOLD_FRAMES}', '-start_number', '1',
               '-i', str(frames/'sample_%03d.png'), '-vf', f'fps={FPS}',
               '-frames:v', str(SAMPLE_COUNT*HOLD_FRAMES), '-an', '-c:v', 'libx264',
               '-preset', 'medium', '-crf', '18', '-threads', '4', '-pix_fmt', 'yuv420p',
               '-movflags', '+faststart', str(destination)]
    subprocess.run(command, check=True)
    stream = imageio_ffmpeg.read_frames(str(destination), input_params=['-threads', '4'])
    metadata = next(stream)
    stream.close()
    assert tuple(metadata['size']) == (1920, 1080) and metadata['fps'] == FPS, metadata
    assert metadata['codec'] == 'h264' and metadata['pix_fmt'].startswith('yuv420p'), metadata
    assert abs(metadata['duration']-DURATION) < 0.01, metadata
    decoded = subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'error',
                              '-threads', '4', '-i', str(destination), '-map', '0:v:0',
                              '-progress', 'pipe:1', '-nostats', '-f', 'null', '-'],
                             check=True, capture_output=True, text=True)
    progress = dict(line.split('=', 1) for line in decoded.stdout.splitlines() if '=' in line)
    assert int(progress['frame']) == SAMPLE_COUNT*HOLD_FRAMES and progress['progress'] == 'end', progress
    assert not decoded.stderr.strip(), decoded.stderr
    return {'metadata': metadata, 'all_frames_decoded': int(progress['frame']),
            'decoder_errors': False, 'command': command, 'sha256': base.sha(destination)}


def render(out, include_absolute, compact=False):
    directory = out/('with_absolute_pressure' if include_absolute else 'pressure_difference_saturation')
    directory.mkdir()
    frames = directory/'frames'
    frames.mkdir()
    fig, images, sample_text, axes, colorbars, rows = make_figure(include_absolute, compact)
    with h5py.File(base.SOURCE, 'r', locking=False) as source:
        p0 = source['pres_Hyd'][:]
        set_sample(images, sample_text, source, p0, 128, rows)
        layout = check_layout(fig, axes, colorbars)
        with (directory/'frame_samples.csv').open('x', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['sample_id_X_post1_X_post2_X_post3', 'frame_file', 'first_video_frame_0based', 'hold_frames'])
            for sample_id in range(1, SAMPLE_COUNT+1):
                set_sample(images, sample_text, source, p0, sample_id, rows)
                if sample_id == 1:
                    check_layout(fig, axes, colorbars)
                fig.canvas.draw()
                path = frames/f'sample_{sample_id:03d}.png'
                Image.fromarray(np.asarray(fig.canvas.buffer_rgba())).save(path)
                writer.writerow([sample_id, path.name, (sample_id-1)*HOLD_FRAMES, HOLD_FRAMES])
                if sample_id in [1, 32, 64, 96, 128]:
                    print(f'{directory.name}: rendered sample {sample_id}/128', flush=True)
    plt.close(fig)
    shutil.copyfile(frames/'sample_001.png', directory/'poster.png')
    destination = directory/'posterior_samples_k1_36s.mp4'
    verification = encode_and_verify(frames, destination)
    print(f'Encoded and verified {destination}', flush=True)
    return {'path': str(destination.relative_to(out)), 'poster': str((directory/'poster.png').relative_to(out)),
            'recommended': compact or not include_absolute, 'rows': [row[0] for row in rows],
            'layout_style': 'compact_three_rows' if compact else 'original_presentation',
            'limits': {row[0]: row[3] for row in rows}, 'layout': layout, 'verification': verification}


def write_delivery(out, report, delta_audit, videos, compact=False):
    provenance = {
        'source': report['source'], 'source_numeric_audit': 'numeric_reference/audit.json',
        'title': 'Posterior samples', 'time_label': 'Day 480', 'monitoring_step': 1,
        'layout_style': 'compact_three_rows' if compact else 'original_presentation',
        'presentation_choice': 'Retain absolute pressure, as requested by the user.' if compact else 'Two-row recommendation with three-row comparison.',
        'time_basis': 'Repository six-by-80-day monitoring schedule, corroborated by the user as the first monitored posterior; label simplified at user request. No embedded timestamp was recovered.',
        'sample_ids': list(range(1, 129)), 'fps': FPS, 'hold_frames': HOLD_FRAMES,
        'sample_hold_seconds': HOLD_FRAMES/FPS, 'duration_seconds': DURATION,
        'pairing': 'Original pressure/saturation sample index within each case. Same index across cases does not assert identical physical realization.',
        'columns': [case[0] for case in previous.CASES],
        'pressure_difference_audit': delta_audit,
        'unresolved_provenance': ['Original observation IDs and observation files are unconfirmed.',
                                'Upstream inverse normalization/clamping code and original export timestamp are unavailable. Saved fields are displayed in the same physical units as the verified manuscript figures.',
                                'The producer is identified by the user as colleague Abhinav.'],
        'interpretation': 'Variation across posterior samples at fixed physical time; not physical time evolution, a permeability-only experiment or a new fracture-probability estimate.',
        'videos': videos,
    }
    base.write_json(out/'provenance.json', provenance)
    with (out/'caption.txt').open('x') as f:
        quantities = 'pressure difference, absolute pressure and CO2 saturation' if compact else 'pressure difference and CO2 saturation'
        f.write(f'Posterior {quantities} at monitoring step k=1, day 480. '
                'All 128 saved samples are shown in array order at fixed physical time, with pressure and saturation paired within each control case. '
                'Pressure difference is p-p0, where p0 is the saved hydrostatic field.\n')
    lines = ['# Posterior presentation revision', '',
             '[Recommended: pressure difference + saturation, 35.84 s](pressure_difference_saturation/posterior_samples_k1_36s.mp4)', '',
             '[Matched comparison including absolute pressure, 35.84 s](with_absolute_pressure/posterior_samples_k1_36s.mp4)', '',
             '[Recommended PNG poster](pressure_difference_saturation/poster.png) · [Comparison PNG poster](with_absolute_pressure/poster.png)', '',
             'Both movies retain all 128 samples in their original order, with exactly seven display frames (0.28 s) per sample. They are 1920x1080, H.264/yuv420p, 25 fps. No subset, shuffling, interpolation or blending is used.', '',
             'The title is now Posterior samples, the time reads Monitoring step k=1 | Day 480, and the explanatory footer has been removed. The sample counter remains visible. Day 480 follows the repository monitoring schedule and the user’s corroboration; the JLD2 has no embedded timestamp.', '',
             'The recommended two-row view displays pressure difference and saturation. The matched three-row comparison adds absolute pressure. Since p0 is fixed, p=p0+(p-p0): absolute pressure and pressure difference contain the same sample-dependent pressure information. The pressure-difference view removes the dominant hydrostatic depth gradient and makes local sample variation easier to see.', '',
             'Columns: PoF epsilon=0 (X_post1), PoF epsilon=0.01 (X_post2), CVaR alpha=0.01 gamma=0.1 (X_post3). Equal indices across cases do not assert the same physical realization. Each case’s pressure and saturation stay paired.', '',
             'Shared fixed limits remain pressure difference -0.2 to 5.2 MPa, absolute pressure 0 to 18 MPa where included, and saturation 0 to 0.9. Full spatial extent, cell orientation and physical aspect ratio are retained. No values are clipped or replaced.', '',
             'The source checksum matches the earlier handoff. All 18 original mean/std reference checks are exact (float32, population std). New color-limit checks and complete MP4 decoding passed. Full provenance and unresolved observation/preprocessing details are in provenance.json. The historical numeric audit is retained under numeric_reference/.', '',
             'Original data and all previous videos remain untouched. Rendering only, with no inference, optimization, or simulation.', '',
             'Reproduce in a fresh output directory:', '', '```bash',
             'sbatch scripts/shell/submit/submit_posterior_presentation_video.sh --output plots/posterior_sample_videos/NEW_DIRECTORY',
             '```', '']
    if compact:
        lines = ['# Compact posterior presentation', '',
                 '[Three-row video, 35.84 seconds](with_absolute_pressure/posterior_samples_k1_36s.mp4)', '',
                 '[PNG poster](with_absolute_pressure/poster.png)', '',
                 'The user selected the version including absolute pressure. Rows are pressure difference, absolute pressure and CO2 saturation; columns are PoF epsilon=0, PoF epsilon=0.01 and CVaR alpha=0.01 gamma=0.1.', '',
                 'The layout uses larger 536-pixel-wide panels, 16-pixel column gaps and 14-pixel row gaps. Outer margins and the header are tightened while retaining all text, the full spatial extent, physical aspect ratio and aligned row colorbars. Reservoir regions with low/zero saturation are part of the data and are not cropped.', '',
                 'Playback is unchanged: all 128 original samples, seven frames (0.28 s) each at 25 fps, total 35.84 s. 1920x1080, H.264/yuv420p. Title: Posterior samples. Time: Monitoring step k=1 | Day 480. The sample counter remains; no explanatory footer is added.', '',
                 'Shared limits are unchanged: pressure difference -0.2 to 5.2 MPa, absolute pressure 0 to 18 MPa and saturation 0 to 0.9. Pressure difference uses the matching saved pres_Hyd. Within-case sample pairing and original sample order are retained; equal indices across cases do not imply the same physical realization.', '',
                 'All 18 historical mean/std numeric references match exactly. Text/canvas bounds, text overlaps, panel dimensions, colorbar alignment and full encoded-frame decoding are checked. See provenance.json and numeric_reference/audit.json.', '',
                 'Day 480 follows the repository timeline and user corroboration. Original observation IDs, upstream preprocessing and an embedded export timestamp remain unavailable. No simulation, inference or optimization was run. Previous exports and source data are preserved.', '',
                 'Reproduce with a new output directory:', '', '```bash',
                 'sbatch scripts/shell/submit/submit_posterior_presentation_video.sh --compact-absolute --output plots/posterior_sample_videos/NEW_DIRECTORY',
                 '```', '']
    with (out/'README.md').open('x') as f:
        f.write('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compact-absolute', action='store_true',
                        help='Render only the selected three-row layout with tighter margins and larger panels.')
    args = parser.parse_args()
    if not os.environ.get('SLURM_JOB_ID'):
        parser.error('Animation rendering must run via sbatch or salloc on PACE.')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    snapshots = out/'provenance'
    snapshots.mkdir()
    for path in [Path(__file__), Path(previous.__file__), Path(base.__file__),
                 base.ROOT/'scripts/shell/submit/submit_posterior_presentation_video.sh']:
        shutil.copyfile(path, snapshots/path.name)
    numeric = out/'numeric_reference'
    numeric.mkdir()
    report = base.audit(numeric)
    delta_audit = previous.validate_pressure_difference(base.SOURCE)
    variants = [True] if args.compact_absolute else [False, True]
    videos = [render(out, include_absolute, args.compact_absolute) for include_absolute in variants]
    assert base.sha(base.SOURCE) == report['source']['sha256']
    write_delivery(out, report, delta_audit, videos, args.compact_absolute)
    print(f'COMPLETE: {out}', flush=True)


if __name__ == '__main__':
    main()
