#!/usr/bin/env python3
"""Paper 3x3: permeability, pressure difference and saturation; truth/mean/std.

Prepare ensemble statistics through Slurm, then render one PNG from the cache.
All outputs are exclusive-create. Existing figures and simulation files are read-only.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import create_joint_permeability_movie as base
import h5py
import numpy as np
from matplotlib.text import Text
from matplotlib.ticker import MaxNLocator

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUN = ROOT / 'data/forward_comparisons/joint_perm_day1920_64_20260915T062645Z'
FIELDS = ('log10_k', 'dp_mpa', 'saturation')


class Moments:
    """Cellwise population moments using Float64 Welford accumulation."""
    def __init__(self):
        self.n = 0
        self.mean = np.zeros((256, 512), dtype=np.float64)
        self.m2 = np.zeros_like(self.mean)

    def add(self, values):
        values = np.asarray(values, dtype=np.float64)
        assert values.shape == self.mean.shape and np.isfinite(values).all()
        self.n += 1
        delta = values - self.mean
        self.mean += delta / self.n
        self.m2 += delta * (values - self.mean)

    def std(self):
        assert self.n > 1
        return np.sqrt(np.maximum(self.m2 / self.n, 0))


def prepare(args):
    assert 'SLURM_JOB_ID' in os.environ, 'Prepare the multi-file ensemble on Slurm'
    assert not args.cache.exists() and not args.cache.with_suffix('.json').exists()
    cfg = json.loads((args.run_dir / 'approval.json').read_text())
    positions = cfg['subset_positions']
    assert cfg['comparison_day'] == 1920 and len(positions) in (64, 128)
    assert len(set(positions)) == len(positions)
    n = len(positions)
    unique_n = len(set(cfg['subset_realization_ids']))
    index_path = ROOT / 'data/state/new/Wise128_state_t1_rtm1_broad_NL_SNR28.jld2'
    with h5py.File(index_path, 'r', locking=False) as f:
        indices = f['idx_t1'][:].flatten().astype(np.int64)
    assert len(indices) == 128
    np.testing.assert_array_equal(indices[np.array(positions)-1], cfg['subset_realization_ids'])
    if n == 128:
        assert positions == list(range(1, 129)) and unique_n == 125
    else:
        assert unique_n == 64
    moments = {k: Moments() for k in FIELDS}
    provenance = []
    sources = set()
    source_configs = {}
    for m in positions:
        source = cfg.get('member_sources', {}).get(str(m), {})
        source_root = Path(source.get('run_directory', args.run_dir))
        source_member = source.get('source_member', m)
        if source_root not in source_configs:
            source_cfg = json.loads((source_root / 'approval.json').read_text())
            for key in ('comparison_day', 'period_days', 'rates_m3_s', 'grid', 'cell_size_m',
                        'well_nominal_start_xyz_m', 'well_nominal_end_z_m',
                        'initial_pressure_sha256_f64', 'initial_saturation_sha256_f64',
                        'porosity_sha256_f64', 'p_max_sha256_f64', 'schedule_sha256_f64'):
                assert source_cfg[key] == cfg[key], (source_root, key)
            source_configs[source_root] = source_cfg
        d = base.read_member(source_root, source_member, source_configs[source_root])
        assert d['realization_id'] == int(indices[m-1])
        if source:
            assert d['permeability_sha256'] == source['permeability_sha256_f32']
        assert np.all(d['permeability_md'] > 0)
        assert d['co2_saturation'].min() >= -1e-8 and d['co2_saturation'].max() <= 1+1e-8
        values = (np.log10(d['permeability_md']), d['dp_mpa'], d['co2_saturation'])
        for key, value in zip(FIELDS, values):
            moments[key].add(value)
        sources.add(d['forward_source_sha256'])
        directory = source_root / 'members' / f'{source_member:03}'
        provenance.append({
            'ensemble_position': m, 'realization_id': d['realization_id'],
            'source_member': source_member, 'sample_weight': 1/n,
            'reused_identical_field': source_member != m,
            'inputs': str(directory / 'inputs.jld2'),
            'response': str(directory / 'day1920.jld2'),
            'permeability_sha256_f32': d['permeability_sha256'],
            'pressure_sha256_f64': base.ahash(d['pressure_pa']),
            'saturation_sha256_f64': base.ahash(d['co2_saturation']),
        })
        print(f'Validated member {m}, geological ID {d["realization_id"]}', flush=True)
    assert len(sources) == 1
    if 'expected_forward_source_sha256' in cfg:
        assert sources == {cfg['expected_forward_source_sha256']}
    data = {f'{key}_{stat}': (obj.mean if stat == 'mean' else obj.std())
            for key, obj in moments.items() for stat in ('mean', 'std')}
    # The same ensemble-mean geology provides context for BOTH response statistics.
    data['response_overlay_log10_k'] = data['log10_k_mean'].copy()
    perm_path = ROOT / 'data/geo/wise_perm_models_2000_new.jld2'
    with h5py.File(perm_path, 'r', locking=False) as f:
        ds = f['BroadK']
        assert ds.shape == (256, 512, 2000)
        truth_k = ds[:, :, 1999]
        data['truth_k_md'] = truth_k
        data['log10_k_truth'] = np.log10(truth_k)
        # Check selected simulator inputs directly against the authoritative library.
        for row in provenance:
            k = ds[:, :, row['realization_id'] - 1]
            assert base.ahash(k, '<f4') == row['permeability_sha256_f32']
        if args.permeability_ensemble == 'all2000':
            full = Moments()
            for start in range(0, 2000, 64):
                block = np.log10(ds[:, :, start:start+64])
                for i in range(block.shape[-1]):
                    full.add(block[:, :, i])
            data['log10_k_mean'], data['log10_k_std'] = full.mean, full.std()
    args.cache.parent.mkdir(parents=True, exist_ok=True)
    with args.cache.open('xb') as f:
        np.savez_compressed(f, **data)
    meta = {
        'ensemble_run': str(args.run_dir), 'day': 1920,
        'response_n': n, 'permeability_n': 2000 if args.permeability_ensemble == 'all2000' else n,
        'unique_permeability_count': unique_n,
        'sample_source': str(index_path), 'sample_index_key': 'idx_t1',
        'sample_scope': ('All 128 first-monitoring-step permeability samples, in original array order'
                         if n == 128 else 'Predeclared 64-position subset of first-monitoring-step samples'),
        'duplicate_policy': 'Retain each original sample position with equal weight, including repeated draws',
        'members': provenance, 'population_std_ddof': 0,
        'permeability_statistics': 'Mean and population std of log10(K [mD]); mean displayed on mD log scale',
        'pressure_difference': '(pressure_pa - identical initial_pressure_pa) / 1e6',
        'orientation': 'All arrays [z,x], shape (256,512); x right, depth positive down',
        'extent_m': list(base.EXTENT), 'permeability_library': str(perm_path),
        'ground_truth_realization_id': 2000,
        'truth_permeability_sha256_f32': base.ahash(truth_k, '<f4'),
        'common_hashes': {k: cfg[k] for k in (
            'initial_pressure_sha256_f64', 'initial_saturation_sha256_f64',
            'porosity_sha256_f64', 'p_max_sha256_f64', 'schedule_sha256_f64')},
        'rates_m3_s': cfg['rates_m3_s'], 'forward_source_sha256': list(sources)[0],
        'cache_sha256': base.fhash(args.cache), 'prepare_source_sha256': base.fhash(Path(__file__)),
        'slurm_job_id': os.environ['SLURM_JOB_ID'],
        'array_ranges': {k: [float(v.min()), float(v.max())] for k, v in data.items()},
    }
    base.write_json(args.cache.with_suffix('.json'), meta)
    print(f'Saved {args.cache}', flush=True)


def read_truth(directory, data, meta):
    assert (directory / 'COMPLETE.txt').is_file(), 'Reference forward has not completed'
    cfg = meta['common_hashes']
    with h5py.File(directory / 'inputs.jld2', 'r', locking=False) as f:
        assert int(f['realization_id'][()]) == 2000
        np.testing.assert_array_equal(f['permeability_md'][:], data['truth_k_md'])
        for field, key in [('initial_pressure_pa', 'initial_pressure_sha256_f64'),
                           ('initial_co2_saturation', 'initial_saturation_sha256_f64'),
                           ('porosity', 'porosity_sha256_f64'), ('p_max_pa', 'p_max_sha256_f64'),
                           ('rates_m3_s', 'schedule_sha256_f64')]:
            assert base.ahash(f[field][:]) == cfg[key], field
        p0 = f['initial_pressure_pa'][:]
        pmax = f['p_max_pa'][:]
        np.testing.assert_array_equal(f['grid'][:], [512, 1, 256])
        np.testing.assert_array_equal(f['cell_size_m'][:], [6.25, 100, 6.25])
        np.testing.assert_array_equal(f['well_start_xyz_m'][:], [1562.5, 100, 1193.75])
        assert f['well_end_z_m'][()] == 1231.25
    with h5py.File(directory / 'day1920.jld2', 'r', locking=False) as f:
        assert bool(f['complete'][()]) and f['time_days'][()] == 1920
        assert f['realization_id'][()] == 2000
        for saved, expected in [('initial_pressure_sha256', 'initial_pressure_sha256_f64'),
                                ('initial_saturation_sha256', 'initial_saturation_sha256_f64'),
                                ('porosity_sha256', 'porosity_sha256_f64'),
                                ('pressure_limit_sha256', 'p_max_sha256_f64'),
                                ('rate_sha256', 'schedule_sha256_f64')]:
            assert f[saved][()].decode() == cfg[expected]
        assert f['permeability_sha256'][()].decode() == meta['truth_permeability_sha256_f32']
        p, s = f['pressure_pa'][:], f['co2_saturation'][:]
        assert p.shape == s.shape == (256, 512) and np.isfinite(p).all() and np.isfinite(s).all()
        assert s.min() >= -1e-8 and s.max() <= 1+1e-8
        assert base.ahash(p) == f['pressure_sha256'][()].decode()
        assert base.ahash(s) == f['saturation_sha256'][()].decode()
        np.testing.assert_array_equal(f['pressure_difference_pa'][:], p-p0)
        np.testing.assert_array_equal(f['pressure_limit_exceedance_mask'][:], p > pmax)
        data['dp_mpa_truth'], data['saturation_truth'] = (p-p0)/1e6, s
        return {'directory': str(directory), 'realization_id': 2000,
                'pressure_sha256_f64': base.ahash(p), 'saturation_sha256_f64': base.ahash(s),
                'slurm_job_id': f['slurm_job_id'][()].decode(),
                'initial_state_schedule_grid_well_verified_against_ensemble': True}


def upper_limit(value):
    step = 10 ** np.floor(np.log10(value)) / 2
    return float(np.ceil(value / step) * step)


def make_figure(data, meta, dpi, reference_limits=None):
    plt = base.plt
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 16,
                         'axes.labelsize': 16, 'axes.titlesize': 24,
                         'xtick.labelsize': 14, 'ytick.labelsize': 14,
                         'mathtext.fontset': 'dejavusans', 'axes.linewidth': .8})
    width = 18.0
    left, right, gap = 1.52, .36, .40
    panel_w = (width-left-right-2*gap)/3
    panel_h = panel_w/2
    header, row_stride, footer = 1.00, panel_h+1.25, .76
    height = header + 2*row_stride + panel_h + footer + .68
    fig = plt.figure(figsize=(width, height), dpi=dpi, facecolor='white')
    heading = fig.text(.5, 1-.045/height, 'Permeability-Driven Uncertainty at Day 1920',
                      ha='center', va='top', fontsize=30, weight='bold')
    cmaps = [base.cc.cm['rainbow4'], base.cc.cm['CET_L3_r'], base.cmasher.rainforest_r]
    dp_min = min(-.1, float(data['dp_mpa_truth'].min()), float(data['dp_mpa_mean'].min()))
    dp_max = max(4., upper_limit(float(max(data['dp_mpa_truth'].max(), data['dp_mpa_mean'].max()))))
    limits = [[0., 4.], [float(np.floor(dp_min*10)/10), dp_max], [0., 1.]]
    std_limits = {k: [0., upper_limit(float(data[f'{k}_std'].max()))] for k in FIELDS}
    if reference_limits is not None:
        # Keep approved scales when they cover the new statistics; expand only
        # when needed to avoid silently clipping a larger ensemble uncertainty.
        for row, key in enumerate(FIELDS):
            old = reference_limits['truth_mean_limits'][key]
            limits[row] = [min(limits[row][0], old[0]), max(limits[row][1], old[1])]
            old_std = reference_limits['std_limits'][key]
            if data[f'{key}_std'].max() <= old_std[1]:
                std_limits[key] = list(old_std)
    row_names = ['Permeability', 'Pressure difference', r'CO$_2$ saturation']
    labels = ['Permeability [mD]', r'$p-p_0$ [MPa]', r'CO$_2$ saturation [–]']
    std_labels = [r'Std. dev. of $\log_{10} K$ [–]', r'Std. dev. of $p-p_0$ [MPa]',
                  r'Std. dev. of CO$_2$ saturation [–]']
    axes, caxes, colorbars, row_text = [], [], [], []
    for row, key in enumerate(FIELDS):
        y = height-header-row*row_stride-panel_h
        row_axes, images = [], []
        std_max = std_limits[key][1]
        limits_row = [limits[row], limits[row], [0., std_max]]
        row_text.append(fig.text(.018, (y+panel_h/2)/height, row_names[row], rotation=90,
                                 ha='center', va='center', fontsize=22, weight='bold'))
        for col, stat in enumerate(('truth', 'mean', 'std')):
            x = left+col*(panel_w+gap)
            ax = fig.add_axes([x/width, y/height, panel_w/width, panel_h/height])
            im = ax.imshow(data[f'{key}_{stat}'], extent=base.EXTENT, origin='upper',
                           interpolation='hanning', cmap=cmaps[row] if col < 2 else base.cc.cm['CET_L8'],
                           vmin=limits_row[col][0], vmax=limits_row[col][1])
            if row:
                geology = data['log10_k_truth'] if col == 0 else data['response_overlay_log10_k']
                ax.imshow(geology, extent=base.EXTENT, origin='upper', interpolation='hanning',
                          cmap=cmaps[0], vmin=0, vmax=4, alpha=.20)
            ax.set_xticks([0, 500, 1000, 1500, 2000, 2500, 3000])
            ax.set_yticks([0, 500, 1000, 1500])
            ax.set_xlabel('X [m]', labelpad=2)
            ax.tick_params(length=3, pad=2, labelleft=(col == 0))
            if col == 0:
                ax.set_ylabel('Depth [m]', labelpad=4)
            if row == 0:
                count = meta['response_n']
                mean_title = f'Ensemble Mean (N={count})'
                if meta['permeability_n'] != count:
                    mean_title = 'Ensemble Mean'
                ax.set_title(['Ground Truth', mean_title, 'Ensemble Std Dev'][col],
                             weight='bold', pad=6, fontsize=24)
            ax.text(.018, .955, f'({chr(97+row*3+col)})', transform=ax.transAxes,
                    va='top', ha='left', fontsize=17, weight='bold',
                    bbox={'facecolor': 'white', 'edgecolor': 'none', 'alpha': .85, 'pad': 2})
            if meta['permeability_n'] != meta['response_n'] and col == 1:
                count = meta['permeability_n'] if row == 0 else meta['response_n']
                ax.text(.97, .955, f'N={count}', transform=ax.transAxes, va='top', ha='right',
                        fontsize=17, bbox={'facecolor': 'white', 'edgecolor': 'none', 'alpha': .85})
            row_axes.append(ax); images.append(im)
        for std in (False, True):
            x = left+2*(panel_w+gap) if std else left
            cb_w = panel_w if std else 2*panel_w+gap
            cax = fig.add_axes([x/width, (y-.64)/height, cb_w/width, .12/height])
            cb = fig.colorbar(images[2 if std else 0], cax=cax, orientation='horizontal')
            cb.ax.tick_params(labelsize=16, length=2, pad=1)
            cb.set_label(std_labels[row] if std else labels[row], fontsize=19, labelpad=3)
            if row == 0 and not std:
                cb.set_ticks([0, 1, 2, 3, 4])
                cb.set_ticklabels(['1', r'$10^1$', r'$10^2$', r'$10^3$', r'$10^4$'])
            elif row == 2 and not std:
                cb.set_ticks(np.linspace(0, 1, 6))
            else:
                ticks = MaxNLocator(nbins=5, min_n_ticks=3).tick_values(cb.vmin, cb.vmax)
                cb.set_ticks(ticks[(ticks >= cb.vmin-1e-10) & (ticks <= cb.vmax+1e-10)])
            caxes.append(cax); colorbars.append(cb)
        axes.append(row_axes)
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    fw, fh = fig.canvas.get_width_height()
    clipped = []
    boxes = []
    for text in fig.findobj(Text):
        if text.get_visible() and text.get_text():
            b = text.get_window_extent(renderer)
            if b.width and b.height:
                if b.x0 < -.5 or b.y0 < -.5 or b.x1 > fw+.5 or b.y1 > fh+.5:
                    clipped.append(text.get_text())
                boxes.append((text.get_text(), b))
    assert not clipped, f'Text outside canvas: {clipped}'
    overlaps = []
    for i, (ta, a) in enumerate(boxes):
        for tb, b in boxes[i+1:]:
            if min(a.x1, b.x1)-max(a.x0, b.x0) > 1 and min(a.y1, b.y1)-max(a.y0, b.y0) > 1:
                overlaps.append([ta, tb])
    assert not overlaps, f'Overlapping text: {overlaps}'
    for i, row_axes in enumerate(axes):
        positions = [a.get_position() for a in row_axes]
        np.testing.assert_allclose([p.y0 for p in positions], positions[0].y0)
        for p in positions:
            assert abs((p.width*width)/(p.height*height)-2) < 1e-10
        assert abs(caxes[2*i].get_position().x0-positions[0].x0) < 1e-10
        assert abs(caxes[2*i].get_position().x1-positions[1].x1) < 1e-10
        np.testing.assert_allclose(caxes[2*i+1].get_position().intervalx, positions[2].intervalx)
        assert abs(caxes[2*i].get_position().y0-caxes[2*i+1].get_position().y0) < 1e-10
    layout = {'canvas_pixels': [fw, fh], 'dpi': dpi, 'text_clipping': clipped,
              'text_overlaps': overlaps, 'physical_aspect': 'equal, full cell-edge extent',
              'map_bounds': [[list(a.get_position().bounds) for a in row] for row in axes],
              'colorbar_bounds': [list(a.get_position().bounds) for a in caxes],
              'truth_mean_limits': dict(zip(FIELDS, limits)),
              'std_limits': std_limits,
              'overlay_alpha': .2, 'overlay_truth': 'truth log10 permeability',
              'overlay_mean_and_std': f'mean log10 permeability of the same {meta["response_n"]} response members'}
    return fig, layout


def render(args):
    assert args.reference_dir is not None and args.output is not None
    outputs = [args.output, args.output.with_suffix('.json'), args.output.with_suffix('.txt')]
    assert not any(p.exists() for p in outputs), 'Refusing to replace existing output'
    meta = json.loads(args.cache.with_suffix('.json').read_text())
    assert base.fhash(args.cache) == meta['cache_sha256']
    with np.load(args.cache) as f:
        data = {k: f[k] for k in f.files}
    truth_meta = read_truth(args.reference_dir, data, meta)
    reference_limits = None
    if args.limits_from is not None:
        reference_limits = json.loads(args.limits_from.read_text())['layout']
    fig, layout = make_figure(data, meta, args.dpi, reference_limits=reference_limits)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('xb') as f:
        fig.savefig(f, format='png', dpi=args.dpi)
    base.plt.close(fig)
    caption = (
        'Permeability-driven uncertainty at Day 1920. Rows show permeability, pressure difference '
        '(p-p0) in MPa, and dimensionless CO2 saturation; columns show the ground-truth-model '
        'response, ensemble mean, and ensemble population standard deviation (ddof=0). '
        f'Permeability statistics use {meta["permeability_n"]} samples; response statistics '
        f'use {meta["response_n"]} samples. '
        + ('These are all 128 permeability samples used at the first monitoring step, in their '
           'original array order (idx_t1): 125 distinct permeability fields, with three repeated '
           'draws retained at their original sample weights. Identical permeability fields share '
           'the same deterministic forward response because every other input is identical. '
           if meta['response_n'] == 128 else
           'These are the 64 predeclared first-monitoring-step subset used in the presentation. ')
        + 'Ground-truth permeability is BroadK realization 2000 and is excluded from the ensemble '
        'response statistics. Its response was simulated using the same initial pressure, initial '
        'saturation, well geometry, porosity, and selected unscaled 24-period PoF epsilon=0.01 '
        'injection schedule as the ensemble. There are no posterior-state replacements. '
        'Permeability mean and standard deviation are computed in log10(K [mD]); the mean '
        'permeability color scale therefore displays the geometric mean in mD. '
        'Pressure and saturation statistics are computed in physical units before any rendering. '
        'The 20%-opacity permeability overlays provide geological context: realization 2000 '
        f'underlies the reference response; the mean log10 permeability of the same {meta["response_n"]} samples '
        'underlies both response mean and standard-deviation maps. Colorbars describe the '
        'underlying response values before the contextual overlay. Full-domain maps use equal '
        'physical aspect with x=0–3200 m and depth=0–1600 m, positive downward. '
        'Permeability colors use the original 1–10000 mD display range; values below 1 mD '
        'take the lowest color without modifying data. The reference and mean share a color '
        'scale within each row; standard deviations use separate scales.'
    )
    with outputs[2].open('x') as f:
        f.write(caption+'\n')
    base.write_json(outputs[1], {'statistics': meta, 'reference': truth_meta, 'layout': layout,
        'cache': str(args.cache), 'output_sha256': base.fhash(args.output),
        'color_limits_reference': str(args.limits_from) if args.limits_from else None,
        'renderer_sha256': base.fhash(Path(__file__)),
        'array_ranges': {k: [float(v.min()), float(v.max())] for k, v in data.items()}})
    print(f'Saved {args.output}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, default=DEFAULT_RUN)
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--permeability-ensemble', choices=('matched', 'matched64', 'all2000'), default='matched',
                        help='Use the corresponding response samples (matched64 is retained as a legacy alias)')
    parser.add_argument('--reference-dir', type=Path)
    parser.add_argument('--limits-from', type=Path, help='Use the approved figure JSON color scales when sufficient')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--dpi', type=int, default=300)
    args = parser.parse_args()
    if args.prepare_only:
        prepare(args)
    else:
        render(args)


if __name__ == '__main__':
    main()
