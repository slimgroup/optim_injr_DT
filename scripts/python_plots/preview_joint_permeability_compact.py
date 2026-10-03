#!/usr/bin/env python3
"""Single saved-field preview with compact slide layout and reference K scale.

This inexpensive command makes one PNG only, with no simulation or animation.
Scientific arrays, spatial aspect, cellwise exceedance test and well stay intact.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

import create_joint_permeability_movie as base
import numpy as np
from matplotlib.collections import LineCollection
from matplotlib.lines import Line2D
from matplotlib.text import Text

COMPACT_SIZE = (1920, 552)


def compact_figure(data, limits, day=480):
    plt = base.plt
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 18,
                         'axes.labelsize': 19, 'axes.titlesize': 22,
                         'xtick.labelsize': 17, 'ytick.labelsize': 17,
                         'mathtext.fontset': 'dejavusans', 'axes.linewidth': .8})
    width, height = COMPACT_SIZE
    fig = plt.figure(figsize=(width/100, height/100), dpi=100, facecolor='white')
    p0 = data['initial_pressure_pa']
    s0 = data['initial_co2_saturation']
    dz = (base.EXTENT[2] - base.EXTENT[3])/p0.shape[0]
    gradient = np.diff(p0[:, 0])/dz/1000
    np.testing.assert_allclose(p0 - p0[:, [0]], 0)
    np.testing.assert_allclose(gradient, gradient[0])
    positive_s0 = np.unique(s0[s0 > 0])
    assert len(positive_s0) == 1 and np.all(s0 >= 0)
    initial_conditions = {
        'pressure_gradient_kPa_per_m': float(gradient[0]),
        'pressure_range_MPa': [float(p0.min()/1e6), float(p0.max()/1e6)],
        'pressure_at_well_start_MPa': float(p0[round(data['well_start_xyz_m'][2]/dz)-1, 0]/1e6),
        'nonzero_CO2_saturation': float(positive_s0[0]),
        'nonzero_CO2_cells': int(np.count_nonzero(s0)),
        'remaining_cells_CO2_saturation': 0.0}
    heading = fig.text(.5, 504/height,
                       f'Permeability effects on pressure buildup and CO$_2$ saturation at Day {day}',
                       ha='center', va='center', fontsize=30,
                       weight='bold', color='#23313b')
    k = np.log10(data['permeability_md'])
    arrays = [k, data['dp_mpa'], data['co2_saturation']]
    cmaps = [base.cc.cm['rainbow4'], base.cc.cm['CET_L3_r'], base.cmasher.rainforest_r]
    clims = [limits['log10_K_mD'], limits['pressure_difference_MPa'], limits['CO2_saturation']]
    titles = ['Permeability', 'Pressure difference', r'CO$_2$ saturation']
    labels = ['Permeability [mD], log scale', r'$p-p_0$ [MPa]', r'CO$_2$ saturation [–]']
    axes, caxes = [], []
    for col in range(3):
        left = 112 + col*592
        ax = fig.add_axes([left/width, 157/height, 558/width, 279/height])
        scalar = ax.imshow(arrays[col], origin='upper', extent=base.EXTENT,
                           interpolation='nearest', cmap=cmaps[col],
                           vmin=clims[col][0], vmax=clims[col][1])
        if col:
            ax.imshow(k, origin='upper', extent=base.EXTENT, interpolation='nearest',
                      cmap=cmaps[0], vmin=0, vmax=4, alpha=base.OVERLAY_ALPHA)
        ax.set_title(titles[col], weight='semibold', pad=8)
        ax.set_xlabel('X [m]', labelpad=2)
        ax.set_xticks([0, 800, 1600, 2400, 3200])
        ax.set_yticks([0, 400, 800, 1200, 1600])
        ax.tick_params(length=3, pad=3, labelleft=(col == 0))
        ax.get_xticklabels()[0].set_ha('left')
        ax.get_xticklabels()[-1].set_ha('right')
        if col == 0:
            ax.set_ylabel('Depth [m]', labelpad=5)
        ax.plot([1559.375]*2, [1190.625, 1228.125], color='white', lw=5, zorder=6)
        ax.plot([1559.375]*2, [1190.625, 1228.125], color='black', lw=2, zorder=7)
        if col == 1:
            ax.add_collection(LineCollection(base.mask_edges(data['mask']),
                              colors='#cf00ad', linewidths=1.1, zorder=8))
        cax = fig.add_axes([left/width, 72/height, 558/width, 14/height])
        cb = fig.colorbar(scalar, cax=cax, orientation='horizontal')
        cb.ax.tick_params(labelsize=17, length=2, pad=2)
        cb.set_label(labels[col], fontsize=19, labelpad=4)
        if col == 0:
            cb.set_ticks([0, 1, 2, 3, 4])
            cb.set_ticklabels(['1', r'$10^1$', r'$10^2$', r'$10^3$', r'$10^4$'])
        elif col == 2:
            cb.set_ticks([0, .2, .4, .6, .8, 1])
        axes.append(ax)
        caxes.append(cax)
    if data['mask'].any():
        axes[1].legend(handles=[Line2D([], [], color='#cf00ad', lw=2,
                       label='Pressure-limit exceedance')], loc='upper center',
                       facecolor='white', framealpha=.85, edgecolor='none', fontsize=14)
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    clipped = []
    for label in fig.findobj(Text):
        if label.get_visible() and label.get_text():
            b = label.get_window_extent(renderer)
            if b.width and b.height and (b.x0 < 0 or b.y0 < 0 or b.x1 > width+.5 or b.y1 > height+.5):
                clipped.append(label.get_text())
    assert not clipped, clipped
    heading_box = heading.get_window_extent(renderer)
    assert abs((heading_box.x0 + heading_box.x1)/2 - width/2) < .5
    heading_gap = heading_box.y0 - max(a.title.get_window_extent(renderer).y1 for a in axes)
    assert heading_gap > 0, 'Main heading overlaps panel titles'
    for a, b in zip(axes, axes[1:]):
        end_tick = a.get_xticklabels()[-1].get_window_extent(renderer)
        start_tick = b.get_xticklabels()[0].get_window_extent(renderer)
        assert end_tick.x1 < start_tick.x0, 'Adjacent panel tick labels overlap'
    bounds = [list(a.get_position().bounds) for a in caxes]
    np.testing.assert_allclose([b[1] for b in bounds], bounds[0][1])
    np.testing.assert_allclose([b[2:] for b in bounds], [bounds[0][2:]]*3)
    return fig, {'canvas_pixels': [width, height], 'text_clipping': clipped,
                 'panel_bounds': [list(a.get_position().bounds) for a in axes],
                 'colorbar_bounds': bounds, 'physical_aspect': 'equal',
                 'typography_points': {'main_title': 30, 'panel_titles': 22,
                                       'axis_and_colorbar_labels': 19, 'ticks': 17},
                 'main_title_centered': True,
                 'main_title': heading.get_text(),
                 'main_title_to_panel_title_gap_pixels': heading_gap,
                 'method_note': None,
                 'initial_conditions': initial_conditions,
                 'realization_id_location': None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('run_dir', type=Path)
    parser.add_argument('--member', type=int, default=1)
    parser.add_argument('--outdir', type=Path, required=True)
    parser.add_argument('--limits-manifest', type=Path, required=True)
    args = parser.parse_args()
    cfg, members, _ = base.audit(args.run_dir, [args.member])
    source_manifest = json.loads(args.limits_manifest.read_text())
    assert source_manifest['fixed_day'] == 480
    assert args.member in source_manifest['shown_members']
    limits = dict(source_manifest['color_limits'])
    limits['log10_K_mD'] = [0, 4]
    data = members[0]
    fig, layout = compact_figure(data, limits)
    args.outdir.mkdir(parents=True, exist_ok=False)
    output = args.outdir/'poster_compact.png'
    fig.savefig(output, dpi=100)
    base.plt.close(fig)
    assert base.Image.open(output).size == COMPACT_SIZE
    base.write_json(args.outdir/'preview_manifest.json', {
        'preview_only': True, 'fixed_day': 480, 'ensemble_position': args.member,
        'realization_id': data['realization_id'], 'input_run': str(args.run_dir),
        'initial_pressure_sha256': cfg['initial_pressure_sha256_f64'],
        'initial_saturation_sha256': cfg['initial_saturation_sha256_f64'],
        'pressure_sha256': base.ahash(data['pressure_pa']),
        'saturation_sha256': base.ahash(data['co2_saturation']),
        'color_limits': limits, 'response_limits_source': str(args.limits_manifest),
        'permeability_reference': 'scripts/python_plots/plot_perm_ensemble.py: rainbow4, log10 limits 0..4',
        'permeability_below_display_min_cells': int((data['permeability_md'] < 1).sum()),
        'permeability_above_display_max_cells': int((data['permeability_md'] > 1e4).sum()),
        'out_of_range_display': 'Clipped to palette endpoints as in reference; data unmodified',
        'overlay_alpha': base.OVERLAY_ALPHA,
        'pressure_limit_exceedance_cells': int(data['mask'].sum()),
        'layout_checks': layout, 'renderer_sha256': base.fhash(Path(__file__)),
        'poster_sha256': base.fhash(output)})
    print(output.resolve())


if __name__ == '__main__':
    main()
