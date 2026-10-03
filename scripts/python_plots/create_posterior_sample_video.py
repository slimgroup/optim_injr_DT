#!/usr/bin/env python3
"""Export saved joint t1 posterior states only; run rendering in a Slurm allocation.

Never calls inference, optimization or a reservoir simulator. Refuses to reuse
an output directory. Reference statistics follow the historical float32 order.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone

import h5py
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'data/posterior/three_set_posteriro_samples_t1_pof_cvar.jld2'
REFERENCE = ROOT / 'plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909'
CASES = [
    ('X_post2', 'pof_eps001', r'PoF $\varepsilon=0.01$', 'PoF epsilon=0.01'),
    ('X_post1', 'pof_eps0', r'PoF $\varepsilon=0$', 'PoF epsilon=0'),
    ('X_post3', 'cvar_a001_g01', r'CVaR $\alpha=0.01,\ \gamma=0.1$', 'CVaR alpha=0.01, gamma=0.1'),
]
EXTENT = [0.0, 511 * 6.25, 255 * 6.25, 0.0]
LIMITS = {'pressure_MPa': [0.0, 18.0], 'saturation': [0.0, 0.9]}
FPS, HOLD_FRAMES = 24, 18
SHORT_IDS = np.rint(np.linspace(1, 128, 32)).astype(int).tolist()


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(8 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, obj):
    with Path(path).open('x') as f:
        json.dump(obj, f, indent=2, allow_nan=False)
        f.write('\n')


def record(path):
    return {'path': str(path.relative_to(ROOT)), 'sha256': sha(path), 'bytes': path.stat().st_size}


def audit(out):
    reference_inputs = json.loads((REFERENCE / 'input_checksums.json').read_text())
    source_info = record(SOURCE)
    expected = reference_inputs[str(SOURCE.relative_to(ROOT))]['sha256']
    if source_info['sha256'] != expected:
        raise ValueError('Posterior input differs from the verified manuscript handoff.')
    manifest = json.loads((REFERENCE / 'manifest.json').read_text())
    figures = [v for v in manifest['figures'] if v['source_step'] == 1]
    refs, tracked = {}, [source_info]
    for stat in ('mean', 'std'):
        p = REFERENCE / f'validation/posterior_{stat}_step1.npz'
        entry = next(v for v in figures if v['canonical_export_path'].endswith(f'posterior_{stat}_step1.png'))
        if sha(p) != entry['numeric_snapshot_sha256']:
            raise ValueError(f'Reference numeric checksum mismatch: {p}')
        refs[stat] = np.load(p)
        tracked.append(record(p))
        tracked.append(record(REFERENCE / entry['compat_path']))
    issues = [
        'The JLD2 contains only X_post1, X_post2, X_post3 and pres_Hyd; no embedded physical time, observation IDs, conditioning measurements, training checkpoint or original inference/export script.',
        'Nominal day 480 is the repository timeline mapping for k=1: six 80-day control periods. It is not an independently recovered timestamp from the posterior export.',
        'Case and posterior semantics are verified against the manuscript handoff and production prior loader. Original observation identity and any upstream inverse normalization/clamping cannot be independently audited here.',
        'The source mean/std figures contain no well overlays and the posterior export has no well geometry. These videos preserve that presentation with no invented or sample-dependent well markers.',
        'The current slide deck and active manuscript document are not present in this workspace. The exact requested figure basenames are resolved through the latest local manuscript handoff manifest; no slide replacement is performed.',
    ]
    report = {
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'slurm_job_id': os.environ.get('SLURM_JOB_ID'),
        'source': source_info, 'reference_handoff': str(REFERENCE.relative_to(ROOT)),
        'monitoring_step': 1, 'nominal_day': 480,
        'time_label': 'Nominal day 480',
        'time_evidence': ['scripts/python_plots/plot_injection_schedule_over_four_steps.py: PERIOD_DAYS=80, N_PERIODS_PER_STEP=6',
                          'scripts/python_plots/plot_pressure_risk_trajectory_over_four_steps.py: STEP_BOUNDARIES=(480,960,1440)',
                          'src/optim_prior_state.jl: previous_step_posterior_path(2) loads t1 as the immediately previous monitored state'],
        'units': {'stored_pressure': 'Pa, absolute', 'display_pressure': 'MPa, absolute (stored pressure * float32(1e-6))',
                  'saturation': 'dimensionless', 'inverse_normalization_applied': False},
        'units_evidence': 'Historical plotting loader uses pressure channel directly in Pa; production load_posterior_prior passes the same channel directly to simulation state. pres_Hyd is 62,500 to 16,000,000 Pa. No inverse normalization is required for these saved exports.',
        'grid': {'julia_shape': [512,256,2,128], 'h5py_shape': [128,2,256,512],
                 'channels_h5py': ['saturation','absolute pressure'], 'display_array': '[z,x], no transpose or flip',
                 'origin': 'upper', 'depth_increases': 'down', 'extent_m': EXTENT,
                 'cell_spacing_m': [6.25,6.25], 'extent_convention': 'Historical manuscript plotting extent retained (511 dx, 255 dz), distinct from full 512 dx by 256 dz mesh size.'},
        'color_limits_shared_across_all_cases_and_frames': LIMITS,
        'statistics': 'np.mean/np.std(axis=0, ddof=0), float32, after original display-unit multiplication; also check pressure difference row',
        'sample_policy': {'full': list(range(1,129)), 'talk': SHORT_IDS, 'talk_selection': 'rint(linspace(1,128,32)), fixed by index without looking at fields',
                          'seconds_each': HOLD_FRAMES/FPS, 'pairing': 'Original common sample index within each case; no cross-case realization identity claimed'},
        'cases': [], 'reference_files': tracked[1:], 'unresolved_issues': issues,
        'interpretation': 'Posterior-state uncertainty at one monitoring time. This is neither physical plume evolution, permeability-only sensitivity, a new fracture-probability estimate nor evidence of actual fracture.',
    }
    with h5py.File(SOURCE, 'r', locking=False) as f:
        assert list(f) == ['X_post1','X_post2','X_post3','pres_Hyd']
        p0 = f['pres_Hyd'][:].astype(np.float32)
        expected_p0 = np.broadcast_to(np.arange(1,257,dtype=np.float32)[:,None]*62500, (256,512))
        assert np.array_equal(p0, expected_p0), 'Unexpected hydrostatic orientation or units'
        for key, slug, _, label in CASES:
            a = f[key][:]
            assert a.shape == (128,2,256,512) and a.dtype == np.float32
            sat = a[:,0].astype(np.float32)
            pres = a[:,1].astype(np.float32)
            row = {'dataset': key, 'slug': slug, 'case': label, 'M': 128,
                   'pressure_Pa_min_max': [float(pres.min()),float(pres.max())],
                   'saturation_min_max': [float(sat.min()),float(sat.max())],
                   'nonfinite_pressure': int((~np.isfinite(pres)).sum()),
                   'nonfinite_saturation': int((~np.isfinite(sat)).sum()),
                   'saturation_below_zero': int((sat<0).sum()), 'saturation_above_one': int((sat>1).sum()),
                   'saturation_above_color_limit': int((sat>LIMITS['saturation'][1]).sum()),
                   'mean_std_checks': []}
            col = ['X_post1','X_post2','X_post3'].index(key)
            for row_index, (variable, fields) in enumerate([
                    ('pressure_diff_MPa',(pres-p0[None,:,:])*np.float32(1e-6)),
                    ('pressure_MPa',pres*np.float32(1e-6)), ('saturation',sat*np.float32(1.0))]):
                axis = row_index*4 + col
                for stat in ('mean','std'):
                    actual = np.mean(fields,axis=0) if stat=='mean' else np.std(fields,axis=0,ddof=0)
                    ref = refs[stat][f'axes{axis}_image0']
                    exact = bool(np.array_equal(actual,ref))
                    check = {'variable': variable, 'statistic': stat, 'reference_array': f'axes{axis}_image0',
                             'exact_equal': exact, 'max_absolute_error': float(np.max(np.abs(actual.astype(float)-ref)))}
                    row['mean_std_checks'].append(check)
                    assert np.array_equal(refs[stat][f'axes{axis}_image0_extent'],EXTENT)
                    assert str(refs[stat][f'axes{axis}_image0_origin']) == 'upper'
            report['cases'].append(row)
            print(json.dumps(row), flush=True)
    report['numeric_reference_match'] = all(c['exact_equal'] for row in report['cases'] for c in row['mean_std_checks'])
    report['valid_values'] = all(not any(row[k] for k in ['nonfinite_pressure','nonfinite_saturation','saturation_below_zero','saturation_above_one','saturation_above_color_limit']) for row in report['cases'])
    write_json(out/'audit.json',report)
    for ref in refs.values():
        ref.close()
    if not report['numeric_reference_match'] or not report['valid_values']:
        raise ValueError('Export stopped: inspect audit.json; no values are clipped, replaced or filtered.')
    if not all(0 <= row['pressure_Pa_min_max'][0] and row['pressure_Pa_min_max'][1] <= 18e6 for row in report['cases']):
        raise ValueError('Shared pressure limits fail to enclose data.')
    return report


def layout(fig):
    from matplotlib.text import Text
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    boxes = []
    for artist in fig.findobj(Text):
        if not artist.get_visible() or not artist.get_text().strip():
            continue
        box = artist.get_window_extent(renderer)
        if box.width and box.height:
            if box.x0 < 0 or box.y0 < 0 or box.x1 > 1920 or box.y1 > 1080:
                raise ValueError(f'Text outside canvas: {artist.get_text()} {box}')
            boxes.append(artist.get_text())
    axes = [ax for ax in fig.axes if ax.images]
    assert len(axes)==2
    sizes = [(ax.bbox.width, ax.bbox.height) for ax in axes]
    assert np.allclose(sizes[0],sizes[1])
    return {'visible_text_inside_canvas': True, 'equal_panel_pixels': list(sizes[0]), 'checked_text_count':len(boxes)}


def make_figure(title):
    import matplotlib.pyplot as plt
    import cmasher
    import colorcet as cc
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':20,'axes.labelsize':21,
                         'xtick.labelsize':18,'ytick.labelsize':18,'axes.linewidth':1.0})
    fig = plt.figure(figsize=(19.2,10.8),dpi=100,facecolor='white')
    fig.text(.5,.945,'Posterior-state uncertainty',ha='center',va='center',fontsize=31,weight='bold')
    fig.text(.5,.873,r'Monitoring step $k=1$  |  Nominal day 480  |  '+title,ha='center',va='center',fontsize=25)
    sample_text = fig.text(.5,.795,'Posterior sample 128 / 128',ha='center',va='center',fontsize=25)
    images=[]
    for i,(name,cmap,clim,label) in enumerate([
        ('Posterior pressure',cc.cm['CET_L3_r'],LIMITS['pressure_MPa'],'Absolute pressure [MPa]'),
        (r'Posterior CO$_2$ saturation',cmasher.rainforest_r,LIMITS['saturation'],'Saturation [dimensionless]')]):
        left=.075+.495*i
        ax=fig.add_axes([left,.335,.395,.395*1920/1080/(EXTENT[1]/EXTENT[2])])
        im=ax.imshow(np.zeros((256,512)),extent=EXTENT,origin='upper',interpolation='nearest',cmap=cmap,vmin=clim[0],vmax=clim[1])
        ax.set_title(name,fontsize=25,weight='bold',pad=18)
        ax.set_xlabel('Horizontal distance [m]',labelpad=8)
        if i==0:ax.set_ylabel('Depth [m]',labelpad=8)
        ax.set_xticks([0,800,1600,2400,3200]);ax.set_xlim(EXTENT[0],EXTENT[1])
        ax.set_yticks([0,400,800,1200,1600]);ax.set_ylim(EXTENT[2],EXTENT[3])
        ax.tick_params(length=5,pad=6)
        cax=fig.add_axes([left,.194,.395,.022])
        cb=fig.colorbar(im,cax=cax,orientation='horizontal')
        cb.set_label(label,fontsize=21,labelpad=8)
        cb.set_ticks([0,3,6,9,12,15,18] if i==0 else [0,.15,.30,.45,.60,.75,.90])
        cb.ax.tick_params(labelsize=18,pad=5)
        images.append(im)
    fig.text(.5,.075,'Different samples at the same time',ha='center',va='center',fontsize=27,weight='bold')
    fig.text(.5,.027,'Paired posterior states; sample changes do not represent physical time evolution.',ha='center',va='center',fontsize=17,color='#4b5563')
    return fig,images,sample_text


def encode(ffmpeg,frames,ids,path):
    playlist=path.with_suffix('.frames.txt')
    # Image paths are controlled relative paths without shell interpolation.
    with playlist.open('x') as f:
        for sample_id in ids:
            f.write(f"file '{frames.name}/sample_{sample_id:03d}.png'\n")
            f.write(f'duration {HOLD_FRAMES/FPS:.8f}\n')
        f.write(f"file '{frames.name}/sample_{ids[-1]:03d}.png'\n")
    cmd=[ffmpeg,'-nostdin','-hide_banner','-loglevel','warning','-n','-f','concat','-safe','1','-i',str(playlist),
         '-vf',f'fps={FPS}','-frames:v',str(len(ids)*HOLD_FRAMES),'-an','-c:v','libx264','-preset','medium',
         '-crf','18','-threads','4','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    subprocess.run(cmd,check=True)
    return cmd


def verify_video(ffmpeg,path,expected_frames):
    import imageio_ffmpeg
    stream=imageio_ffmpeg.read_frames(str(path),input_params=['-threads','4'])
    metadata=next(stream)
    stream.close()
    assert tuple(metadata['size']) == (1920,1080), metadata
    assert metadata['fps'] == FPS, metadata
    assert metadata['codec'] == 'h264', metadata
    assert metadata['pix_fmt'].split('(')[0].strip() == 'yuv420p', metadata
    assert abs(metadata['duration']-expected_frames/FPS) < .02, metadata
    # Decode every encoded frame, with bounded threads, to detect truncation.
    result=subprocess.run([ffmpeg,'-nostdin','-hide_banner','-loglevel','error',
                           '-threads','4','-i',str(path),'-map','0:v:0',
                           '-progress','pipe:1','-nostats','-f','null','-'],
                          check=True,capture_output=True,text=True)
    progress=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    assert int(progress['frame']) == expected_frames, progress
    assert progress['progress'] == 'end', progress
    assert not result.stderr.strip(), result.stderr
    return {'actual_metadata':metadata,'all_frames_decoded':int(progress['frame']),
            'decoder_errors':False}


def render(out,report):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import imageio_ffmpeg
    from PIL import Image
    ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
    videos=[]
    with h5py.File(SOURCE,'r',locking=False) as f:
        for key,slug,title,label in CASES:
            directory=out/slug
            directory.mkdir()
            frames=directory/'frames'
            frames.mkdir()
            fig,images,sample_text=make_figure(title)
            layout_check=layout(fig)
            for m in range(1,129):
                a=f[key][m-1]
                images[0].set_data(a[1]*np.float32(1e-6))
                images[1].set_data(a[0])
                sample_text.set_text(f'Posterior sample {m} / 128')
                fig.canvas.draw()
                frame=frames/f'sample_{m:03d}.png'
                Image.fromarray(np.asarray(fig.canvas.buffer_rgba())).save(frame)
                if m in [1,32,64,96,128]:print(f'{slug}: rendered sample {m}/128',flush=True)
            plt.close(fig)
            # The poster is sample 1, chosen by order and not by appearance.
            shutil.copyfile(frames/'sample_001.png',directory/'poster.png')
            for version,ids in [('full',list(range(1,129))),('talk',SHORT_IDS)]:
                path=directory/f'{slug}_k1_{version}.mp4'
                command=encode(ffmpeg,frames,ids,path)
                verification=verify_video(ffmpeg,path,len(ids)*HOLD_FRAMES)
                videos.append({'case':label,'dataset':key,'version':version,'path':str(path.relative_to(out)),
                               'poster':str((directory/'poster.png').relative_to(out)),
                               'sample_ids':ids,'duration_seconds':len(ids)*HOLD_FRAMES/FPS,
                               'frame_count':len(ids)*HOLD_FRAMES,'fps':FPS,'resolution':[1920,1080],
                               'codec':'H.264','pixel_format':'yuv420p','sha256':sha(path),
                               'layout_check':layout_check,'encoder_command':command,
                               'verification':verification})
                print(f'Encoded {path}',flush=True)
    if sha(SOURCE)!=report['source']['sha256']:raise ValueError('Source changed during export')
    write_json(out/'videos.json',videos)
    write_delivery(out,report,videos)


def write_delivery(out,report,videos):
    with (out/'provenance.csv').open('x',newline='') as f:
        names=['case','dataset','source_file','monitoring_step','time','M','version','displayed_sample_ids','duration_seconds','units','pressure_limits_MPa','saturation_limits','mean_std_check','issues','video','poster']
        w=csv.DictWriter(f,fieldnames=names);w.writeheader()
        for v in videos:
            w.writerow(dict(case=v['case'],dataset=v['dataset'],source_file=report['source']['path'],monitoring_step=1,
                            time='Nominal day 480; repository schedule mapping, no embedded timestamp',M=128,version=v['version'],
                            displayed_sample_ids=' '.join(map(str,v['sample_ids'])),duration_seconds=v['duration_seconds'],
                            units='Absolute pressure MPa; saturation dimensionless',pressure_limits_MPa='0 18',saturation_limits='0 0.9',
                            mean_std_check='Exact float32 equality: pressure, saturation and pressure difference; mean and ddof=0 std',
                            issues='See audit.json: observation/export metadata and well geometry unavailable; active deck not inspected',video=v['path'],poster=v['poster']))
    caption=('Paired posterior pressure and CO2-saturation samples at monitoring step k=1 '
             '(nominal day 480 in the documented campaign schedule). Each frame shows one saved joint sample '
             'conditioned on the same case-specific monitoring data; only sample index changes. '
             'All cases share fixed color scales. The movie depicts posterior-state uncertainty, '
             'not physical plume evolution or a permeability-only sensitivity experiment, and supplies '
             'neither a new fracture-probability estimate nor evidence of actual fracture. '
             'The original observation IDs and embedded export timestamp are unavailable locally.')
    (out/'caption.txt').write_text(caption+'\n')
    lines=['# Posterior sample movies — k=1','',caption,'',
           '| Case | 96 s / all 128 | 24 s / fixed 32 | Poster |','|---|---|---|---|']
    for key,slug,_,label in CASES:
        lines.append(f'| {label} | [MP4]({slug}/{slug}_k1_full.mp4) | [MP4]({slug}/{slug}_k1_talk.mp4) | [PNG]({slug}/poster.png) |')
    lines += ['', '1920 × 1080, 24 fps, H.264, yuv420p; each sample held for 18 frames (0.75 s), with hard cuts and no blending.',
              '', 'Full sample order: 1–128. Talk subset: '+', '.join(map(str,SHORT_IDS))+'. Posters use sample 1.',
              '', 'Source: `'+report['source']['path']+'`; SHA-256 `'+report['source']['sha256']+'`.',
              '', 'Case mapping: X_post2 → PoF epsilon=0.01; X_post1 → PoF epsilon=0; X_post3 → CVaR alpha=0.01, gamma=0.1.',
              '', 'Pressure is absolute, stored in Pa and displayed in MPa; saturation is dimensionless. No inverse normalization, per-frame scaling, clipping, filtering, sample synthesis or permeability pairing is applied.',
              '', 'Fixed color limits: pressure 0–18 MPa; saturation 0–0.9. Array layout: h5py (sample, variable, z, x), channel 0 saturation and channel 1 pressure. Depth increases downward; source plotting extent x=0–3193.75 m, depth=0–1593.75 m is preserved.',
              '', 'All 18 reference-field checks are exactly equal to the latest local manuscript handoff numeric snapshots: three cases × three variables × mean/std. The historical convention is float32 reduction after display scaling, std ddof=0. Pressure and p−p0 standard deviations are mathematically redundant (apart from floating-point roundoff).',
              '', 'All three arrays have 128 samples; no nonfinite pressure/saturation values or saturation values outside [0,1] were found.',
              '', '**Optional pressure view:** a separately labeled `Posterior pressure increment p−p0 [MPa]` would emphasize variation obscured by the hydrostatic gradient. It is not substituted for absolute pressure here. The matching p0 is this file’s pres_Hyd.',
              '', '## Provenance limitations','']
    lines += ['- '+issue for issue in report['unresolved_issues']]
    lines += ['', 'Full provenance table: [provenance.csv](provenance.csv). Numeric checks: [audit.json](audit.json). Encoding, sample IDs and file checksums: [videos.json](videos.json).',
              '', 'Reproduce from the repository root with a fresh output directory:', '', '```bash',
              'sbatch scripts/shell/submit/submit_posterior_sample_video.sh --output plots/posterior_sample_videos/NEW_DIRECTORY','```','']
    (out/'README.md').write_text('\n'.join(lines))


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    if not os.environ.get('SLURM_JOB_ID'):
        ap.error('Rendering must run via sbatch or salloc on PACE.')
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    provenance=out/'provenance';provenance.mkdir()
    for source in [Path(__file__),ROOT/'scripts/shell/submit/submit_posterior_sample_video.sh']:
        shutil.copyfile(source,provenance/source.name)
    report=audit(out)
    render(out,report)
    print(f'COMPLETE: {out}',flush=True)


if __name__=='__main__':main()
