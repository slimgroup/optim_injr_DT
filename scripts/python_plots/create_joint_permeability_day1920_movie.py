#!/usr/bin/env python3
"""Render approved64 saved Day1920 fields; compact slide and1080p MP4 exports."""
from __future__ import annotations
import argparse
import csv
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import create_joint_permeability_movie as base
from preview_joint_permeability_compact import COMPACT_SIZE, compact_figure
import numpy as np
import h5py
from PIL import Image


def audit(root, positions):
    cfg, data, limits = base.audit(root, positions)
    assert cfg['comparison_day'] == 1920 and cfg['approved']
    assert len({d['realization_id'] for d in data}) == len(data)
    np.testing.assert_array_equal(cfg['rates_m3_s'][:6], [.0001, .00914, .01818, .02722, .03626, .0453])
    assert len(cfg['rates_m3_s']) == 24 and cfg['period_days'] == 80
    limits['log10_K_mD'] = [0, 4]
    for d in data:
        path = root/'members'/f'{d["member"]:03}'
        expected_start = 480 if d['member'] in cfg['resume_from_day480_positions'] else 0
        with h5py.File(path/'inputs.jld2', 'r', locking=False) as f:
            assert f['start_day'][()] == expected_start
            # JLD2 encodes an empty String with a zero-size HDF5 datatype,
            # which h5py cannot open. Day0 members have no restart by design.
            d['restart_source'] = f['restart_source'][()].decode() if expected_start else ''
            d['restart_sha256'] = f['restart_sha256'][()].decode() if expected_start else ''
        with h5py.File(path/'day1920.jld2', 'r', locking=False) as f:
            assert f['start_day'][()] == expected_start
            if expected_start:
                assert f['restart_source'][()].decode() == d['restart_source']
                assert f['restart_sha256'][()].decode() == d['restart_sha256']
        d['start_day'] = expected_start
        if expected_start:
            assert base.fhash(Path(d['restart_source'])) == d['restart_sha256']
        if d['member'] == 1:
            with h5py.File(path/'restart_validation.jld2', 'r', locking=False) as f:
                assert bool(f['passed'][()])
                assert f['max_pressure_error_pa'][()] <= f['pressure_tolerance_pa'][()]
                assert f['max_saturation_error'][()] <= f['saturation_tolerance'][()]
    return cfg, data, limits


def encode(out, n, compact, hold_frames):
    size = COMPACT_SIZE if compact else (1920, 1080)
    tag = 'compact' if compact else '1080p'
    movie = out/f'joint_permeability_day1920_64_{tag}.mp4'
    ffmpeg = base.imageio_ffmpeg.get_ffmpeg_exe()
    cmd = [ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'warning', '-n',
           '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', f'{size[0]}x{size[1]}',
           '-framerate', str(base.FPS), '-i', 'pipe:0', '-frames:v', str(n*hold_frames),
           '-an', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-threads', '2',
           '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(movie)]
    with (out/f'encoding_{tag}.stderr').open('xb') as log:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=log)
        try:
            for i in range(n):
                with Image.open(out/'frames'/f'frame_{i:03}.png') as source:
                    im = source.convert('RGB')
                    if not compact:
                        master = Image.new('RGB', size, 'white')
                        master.paste(im, (0, (1080-im.height)//2))
                        im = master
                    frame = im.tobytes()
                for _ in range(hold_frames):
                    proc.stdin.write(frame)
        finally:
            proc.stdin.close()
        if proc.wait() != 0:
            raise RuntimeError(f'Encoding failed: {tag}')
    stream = base.imageio_ffmpeg.read_frames(str(movie), input_params=['-threads', '2'])
    metadata = next(stream)
    stream.close()
    assert tuple(metadata['size']) == size
    assert metadata['codec'] == 'h264' and metadata['pix_fmt'].startswith('yuv420p')
    assert metadata['fps'] == base.FPS and abs(metadata['duration'] - n*hold_frames/base.FPS) < .05
    decoded = out/f'decoded_{tag}.framemd5'
    subprocess.run([ffmpeg, '-nostdin', '-v', 'error', '-n', '-threads', '2', '-i',
                    str(movie), '-f', 'framemd5', str(decoded)], check=True)
    count = sum(bool(line) and not line.startswith('#') for line in decoded.read_text().splitlines())
    assert count == n*hold_frames
    return {'path': str(movie), 'command': cmd, 'metadata': metadata,
            'decoded_frame_count': count, 'sha256': base.fhash(movie)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_dir', type=Path)
    parser.add_argument('--outdir', type=Path)
    parser.add_argument('--members', help='Explicit pilot/preview members; default approved64')
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--poster-only', action='store_true')
    parser.add_argument('--hold-seconds', type=float, default=.75,
                        help='Display duration per member, in whole frames at 24 fps (default: 0.75)')
    args = parser.parse_args()
    if not np.isfinite(args.hold_seconds) or args.hold_seconds <= 0:
        parser.error('--hold-seconds must be finite and positive')
    hold_frames = round(args.hold_seconds*base.FPS)
    if hold_frames < 1 or abs(hold_frames/base.FPS - args.hold_seconds) > 1e-9:
        parser.error('--hold-seconds must correspond to a whole number of frames at 24 fps')
    cfg = json.loads((args.run_dir/'approval.json').read_text())
    positions = [int(m) for m in args.members.split(',')] if args.members else cfg['subset_positions']
    cfg, data, limits = audit(args.run_dir, positions)
    if args.validate_only:
        print(json.dumps({'validated_members': positions, 'initial_hashes_identical': True,
                          'color_limits': limits, 'exceedance_cells': {d['member']: int(d['mask'].sum()) for d in data}}))
        return
    if not args.poster_only:
        assert 'SLURM_JOB_ID' in os.environ, 'Animation requires Slurm'
        assert positions == cfg['subset_positions'] and len(positions) == 64
    if args.outdir is None:
        raise ValueError('--outdir is required')
    args.outdir.mkdir(parents=True, exist_ok=False)
    (args.outdir/'frames').mkdir()
    rows, layouts = [], []
    for i, d in enumerate(data):
        fig, layout = compact_figure(d, limits, day=1920)
        frame = args.outdir/'frames'/f'frame_{i:03}.png'
        fig.savefig(frame, dpi=100)
        base.plt.close(fig)
        layouts.append(layout)
        if i == 0:
            shutil.copy2(frame, args.outdir/'poster_compact.png')
            with Image.open(frame) as im:
                master = Image.new('RGB', (1920, 1080), 'white')
                master.paste(im.convert('RGB'), (0, (1080-im.height)//2))
                master.save(args.outdir/'poster.png')
        directory = args.run_dir/'members'/f'{d["member"]:03}'
        rows.append({'frame_index': i, 'ensemble_position': d['member'], 'realization_id': d['realization_id'],
                     'time_days': 1920, 'slurm_job_id': d['job_id'], 'start_day': d['start_day'],
                     'initial_state_source': cfg['state_choice_requiring_approval'],
                     'initial_pressure_sha256': cfg['initial_pressure_sha256_f64'],
                     'initial_saturation_sha256': cfg['initial_saturation_sha256_f64'],
                     'porosity_sha256': cfg['porosity_sha256_f64'], 'permeability_sha256': d['permeability_sha256'],
                     'pressure_sha256': base.ahash(d['pressure_pa']), 'saturation_sha256': base.ahash(d['co2_saturation']),
                     'input_source': str(directory/'inputs.jld2'), 'restart_source': d['restart_source'],
                     'restart_sha256': d['restart_sha256'], 'pressure_source': str(directory/'day1920.jld2')+'::pressure_pa',
                     'saturation_source': str(directory/'day1920.jld2')+'::co2_saturation',
                     'schedule_source': cfg['schedule_source'], 'rates_m3_s': json.dumps(cfg['rates_m3_s']),
                     'permeability_units': 'mD, logarithmic', 'pressure_display_units': 'MPa, p-p0',
                     'saturation_units': 'dimensionless', 'color_limits': json.dumps(limits),
                     'pressure_limit_exceedance_cells': int(d['mask'].sum()),
                     'permeability_below_display_min_cells': int((d['permeability_md'] < 1).sum()),
                     'permeability_above_display_max_cells': int((d['permeability_md'] > 1e4).sum()),
                     'max_pressure_difference_MPa': float(d['dp_mpa'].max()),
                     'saturation_ge_0p01_domain_fraction': float((d['co2_saturation'] >= .01).mean()),
                     'overlay_alpha': base.OVERLAY_ALPHA, 'frame_png': str(frame), 'status': 'complete'})
        print(f'Rendered {i+1}/{len(data)}: member{d["member"]}, ID{d["realization_id"]}', flush=True)
        if args.poster_only:
            break
    with (args.outdir/'provenance.csv').open('x', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    videos = {} if args.poster_only else {tag: encode(args.outdir, len(data), compact, hold_frames) for tag, compact in [('compact', True), ('1080p', False)]}
    with (args.run_dir/'permeability_cache_members.csv').open() as f:
        all_ids = {int(row['member']): int(row['realization_id']) for row in csv.DictReader(f)}
    shown = [row['ensemble_position'] for row in rows]
    all_status = []
    for m in range(1, 129):
        p = args.run_dir/'members'/f'{m:03}'
        status = ('shown' if m in shown else 'outside_fixed64_subset' if m not in cfg['subset_positions']
                  else 'completed_not_shown_in_preview' if (p/'COMPLETE.txt').exists()
                  else 'failed' if (p/'FAILED.txt').exists() else 'pending_or_unsubmitted')
        all_status.append({'ensemble_position': m, 'realization_id': all_ids[m], 'status': status})
    base.write_json(args.outdir/'manifest.json', {
        'run_directory': str(args.run_dir), 'slide_id': 'p1-perm-movie', 'fixed_day': 1920,
        'shown_members': shown, 'approved_subset': cfg['subset_positions'], 'subset_rule': cfg['subset_rule'],
        'all128_member_status': all_status, 'color_limits': limits,
        'color_mapping_reference': 'plot_perm_ensemble.py: rainbow4, log10_mD limits0..4; out-of-range values use palette endpoints',
        'overlay': {'alpha': .2, 'colorbars': 'Underlying scalar palettes; K texture is contextual'},
        'layout_checks': layouts, 'encoding': videos, 'poster_sha256': base.fhash(args.outdir/'poster.png'),
        'compact_poster_sha256': base.fhash(args.outdir/'poster_compact.png'),
        'hold_seconds': args.hold_seconds, 'display_frames_per_member': hold_frames,
        'physical_interpolation': False,
        'master_1080p_layout': f'Same {COMPACT_SIZE[0]}x{COMPACT_SIZE[1]} content centered vertically with {(1080-COMPACT_SIZE[1])//2} white pixels above and below; no stretching',
        'renderer_sources': {str(p): base.fhash(p) for p in [Path(__file__), Path(base.__file__), Path(__file__).with_name('preview_joint_permeability_compact.py')]},
        'software': {'python': sys.version, 'numpy': np.__version__, 'matplotlib': base.matplotlib.__version__,
                     'h5py': h5py.__version__, 'colorcet': base.cc.__version__, 'cmasher': base.cmasher.__version__}})
    initial = layouts[0]['initial_conditions']
    caption = (f'Permeability effects on pressure buildup and CO2 saturation at Day 1920: {len(rows)} predeclared realizations. '
               f'Common initial conditions: hydrostatic pressure ({initial["pressure_gradient_kPa_per_m"]:g} kPa/m; '
               f'{initial["pressure_range_MPa"][0]:g}–{initial["pressure_range_MPa"][1]:g} MPa), '
               f'CO2 saturation {initial["nonzero_CO2_saturation"]:.6f} in {initial["nonzero_CO2_cells"]} near-well cells and zero elsewhere. '
               'All members use the selected 24-period PoF epsilon=0.01 schedule. '
               'Frames compare permeability realizations at one fixed time. Magenta outlines denote cells above p0(x,z)+4 MPa. '
               'Permeability is shown on the reference 1–10000 mD logarithmic scale with faint overlays in both response panels.')
    with (args.outdir/'caption.txt').open('x') as f:
        f.write(caption+'\n')
    print(args.outdir.resolve())


if __name__ == '__main__':
    main()
