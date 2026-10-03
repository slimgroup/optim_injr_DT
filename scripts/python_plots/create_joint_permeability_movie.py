#!/usr/bin/env python3
"""Render an audited fixed-Day-480 K / pressure-increment / CO2 movie.

No simulation. A single poster is inexpensive; animation requires Slurm.
All outputs are exclusive-create. No interpolation between realizations.
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

os.environ.setdefault('MPLCONFIGDIR', '/tmp/mpl_joint_permeability')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
os.environ.setdefault('HDF5_USE_FILE_LOCKING', 'FALSE')
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import Normalize
from matplotlib.collections import LineCollection
from matplotlib.text import Text
from matplotlib.lines import Line2D
import colorcet as cc
import cmasher
from PIL import Image
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
EXTENT = (0, 3200, 1600, 0)
FPS, HOLD = 24, 18
OVERLAY_ALPHA = 0.20


def ahash(a, dtype='<f8'):
    return hashlib.sha256(np.asarray(a, dtype=dtype).tobytes(order='C')).hexdigest()


def fhash(path):
    with path.open('rb') as f:
        h = hashlib.sha256()
        for block in iter(lambda: f.read(4*1024*1024), b''):
            h.update(block)
        return h.hexdigest()


def write_json(path, value):
    with path.open('x') as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write('\n')


def read_member(root, m, cfg):
    day = int(cfg.get('comparison_day', 480))
    directory = root / 'members' / f'{m:03}'
    if not (directory/'COMPLETE.txt').is_file():
        raise ValueError(f'Member {m} has no completed Day {day} forward')
    data = {}
    with h5py.File(directory/'inputs.jld2', 'r', locking=False) as f:
        for k in ['permeability_md', 'initial_pressure_pa', 'initial_co2_saturation',
                  'porosity', 'p_max_pa', 'rates_m3_s', 'well_start_xyz_m']:
            data[k] = f[k][:]
        assert f['well_end_z_m'][()] == 1231.25
        assert f['member'][()] == m
        data['realization_id'] = int(f['realization_id'][()])
        assert data['realization_id'] == cfg['subset_realization_ids'][cfg['subset_positions'].index(m)]
        for key, expected in [('initial_pressure_pa','initial_pressure_sha256_f64'),
                              ('initial_co2_saturation','initial_saturation_sha256_f64'),
                              ('porosity','porosity_sha256_f64'),('p_max_pa','p_max_sha256_f64')]:
            assert data[key].shape == (256,512)
            assert ahash(data[key]) == cfg[expected], (m,key)
        np.testing.assert_array_equal(data['rates_m3_s'], cfg['rates_m3_s'])
        np.testing.assert_array_equal(data['well_start_xyz_m'], cfg['well_nominal_start_xyz_m'])
        np.testing.assert_array_equal(f['grid'][:], cfg['grid'])
        np.testing.assert_array_equal(f['cell_size_m'][:], cfg['cell_size_m'])
        np.testing.assert_array_equal(data['p_max_pa'], data['initial_pressure_pa']+4e6)
        data['permeability_sha256'] = ahash(data['permeability_md'], '<f4')
        assert data['permeability_sha256'] == f['permeability_sha256'][()].decode()
    with h5py.File(directory/f'day{day}.jld2', 'r', locking=False) as f:
        assert bool(f['complete'][()]) and f['time_days'][()] == day
        assert int(f['member'][()]) == m and int(f['realization_id'][()]) == data['realization_id']
        for k in ['pressure_pa', 'co2_saturation']:
            data[k] = f[k][:]
            assert data[k].shape == (256,512) and np.isfinite(data[k]).all()
        assert ahash(data['pressure_pa']) == f['pressure_sha256'][()].decode()
        assert ahash(data['co2_saturation']) == f['saturation_sha256'][()].decode()
        for key, expected in [('initial_pressure_sha256','initial_pressure_sha256_f64'),
                              ('initial_saturation_sha256','initial_saturation_sha256_f64'),
                              ('porosity_sha256','porosity_sha256_f64'),('pressure_limit_sha256','p_max_sha256_f64')]:
            assert f[key][()].decode() == cfg[expected]
        assert f['permeability_sha256'][()].decode() == data['permeability_sha256']
        assert f['rate_sha256'][()].decode() == ahash(data['rates_m3_s'])
        dp_pa = data['pressure_pa'] - data['initial_pressure_pa']
        np.testing.assert_array_equal(f['pressure_difference_pa'][:], dp_pa)
        mask = data['pressure_pa'] > data['p_max_pa']
        np.testing.assert_array_equal(f['pressure_limit_exceedance_mask'][:].astype(bool), mask)
        data.update(dp_mpa=dp_pa/1e6, mask=mask, member=m,
                    job_id=f['slurm_job_id'][()].decode(),
                    array_job_id=f['slurm_array_job_id'][()].decode(),
                    forward_source_sha256=f['source_sha256'][()].decode())
    return data


def audit(root, positions):
    cfg = json.loads((root/'approval.json').read_text())
    assert set(positions).issubset(cfg['subset_positions'])
    members = [read_member(root, m, cfg) for m in positions]
    assert len({d['forward_source_sha256'] for d in members}) == 1
    kmin = min(float(d['permeability_md'].min()) for d in members)
    kmax = max(float(d['permeability_md'].max()) for d in members)
    assert kmin > 0
    # Retain familiar logarithmic mD ticks, extending only when required by data.
    klimits = [min(0, int(np.floor(np.log10(kmin)))), max(4, int(np.ceil(np.log10(kmax))))]
    dpmin = min(float(d['dp_mpa'].min()) for d in members)
    dpmax = max(float(d['dp_mpa'].max()) for d in members)
    dp_limits = [min(0., np.floor(dpmin*10)/10), max(4., np.ceil(dpmax*2)/2)]
    assert all(d['co2_saturation'].min() >= -1e-8 and d['co2_saturation'].max() <= 1+1e-8 for d in members)
    return cfg, members, {'log10_K_mD': klimits, 'pressure_difference_MPa': dp_limits, 'CO2_saturation': [0.,1.]}


def mask_edges(mask):
    """Outline the actual cell mask, including outer domain edges."""
    rows, cols = np.nonzero(mask)
    segments = []
    for r,c in zip(rows,cols):
        x,z = c*6.25,r*6.25
        if r==0 or not mask[r-1,c]: segments.append([(x,z),(x+6.25,z)])
        if r==255 or not mask[r+1,c]: segments.append([(x,z+6.25),(x+6.25,z+6.25)])
        if c==0 or not mask[r,c-1]: segments.append([(x,z),(x,z+6.25)])
        if c==511 or not mask[r,c+1]: segments.append([(x+6.25,z),(x+6.25,z+6.25)])
    return segments


def figure(data, limits, cfg, count):
    plt.rcParams.update({'font.family':'DejaVu Serif','font.size':18,
        'axes.labelsize':19,'axes.titlesize':26,'xtick.labelsize':16,'ytick.labelsize':16,
        'axes.linewidth':0.8,'mathtext.fontset':'dejavuserif'})
    fig=plt.figure(figsize=(19.2,10.8),dpi=100,facecolor='white')
    dark,teal = '#23313b','#477e78'
    fig.text(.5,.944,'Permeability uncertainty changes reservoir response',
             ha='center',va='center',fontsize=33,weight='bold',color=dark)
    fig.text(.5,.885,'Day 480, fixed time; permeability varies',ha='center',va='center',fontsize=24,color=teal)
    fig.text(.5,.833,f'Realization ID {data["realization_id"]}  |  Ensemble position {data["member"]}/128',
             ha='center',va='center',fontsize=21,color=dark)
    k = np.log10(data['permeability_md'])
    arrays=[k,data['dp_mpa'],data['co2_saturation']]
    cmaps=[cc.cm['rainbow4'],cc.cm['CET_L3_r'],cmasher.rainforest_r]
    clims=[limits['log10_K_mD'],limits['pressure_difference_MPa'],limits['CO2_saturation']]
    titles=['Permeability', 'Pressure difference', r'CO$_2$ saturation']
    labels=['Permeability [mD], log scale',r'$p-p_0$ [MPa]','CO$_2$ saturation [–]']
    axes, caxes = [], []
    for col in range(3):
        left=.070+col*.312
        ax=fig.add_axes([left,.495,.270,.270*1920/1080/2])
        image=ax.imshow(arrays[col],origin='upper',extent=EXTENT,interpolation='nearest',
                        cmap=cmaps[col],vmin=clims[col][0],vmax=clims[col][1])
        if col:
            ax.imshow(k,origin='upper',extent=EXTENT,interpolation='nearest',
                      cmap=cmaps[0],vmin=clims[0][0],vmax=clims[0][1],alpha=OVERLAY_ALPHA)
        ax.set_title(titles[col],color=teal,weight='bold',pad=15)
        ax.set_xlabel('X [m]',labelpad=5)
        ax.set_xticks([0,800,1600,2400,3200]);ax.set_yticks([0,400,800,1200,1600])
        ax.tick_params(length=4,pad=5,labelleft=(col==0))
        if col==0:ax.set_ylabel('Depth [m]',labelpad=9)
        # Well coordinates are actual reservoir cell centers, not nominal edges.
        ax.plot([1559.375,1559.375],[1190.625,1228.125],color='white',lw=5,zorder=6)
        ax.plot([1559.375,1559.375],[1190.625,1228.125],color='black',lw=2,zorder=7)
        if col==1:
            ax.add_collection(LineCollection(mask_edges(data['mask']),colors='#cf00ad',linewidths=1.1,zorder=8))
        cax=fig.add_axes([left,.384,.270,.017])
        cb=fig.colorbar(image,cax=cax,orientation='horizontal')
        cb.ax.tick_params(labelsize=16,length=3,pad=4)
        cb.set_label(labels[col],fontsize=19,labelpad=6)
        if col==0:
            ticks=np.arange(clims[0][0],clims[0][1]+1)
            cb.set_ticks(ticks)
            cb.set_ticklabels(['1' if t==0 else rf'$10^{{{t}}}$' for t in ticks])
        elif col==2:cb.set_ticks([0,.2,.4,.6,.8,1])
        axes.append(ax);caxes.append(cax)
    fig.legend(handles=[Line2D([],[],color='black',lw=2,label='Fixed injector'),
                        Line2D([],[],color='#cf00ad',lw=2,label='Pressure-limit exceedance')],
               loc='center',bbox_to_anchor=(.5,.273),ncol=2,frameon=False,fontsize=18,
               columnspacing=3,handlelength=2)
    fig.text(.5,.230,f'{int(data["mask"].sum()):,} cells above '+r'$p_0(x,z)+4$ MPa'+
             '  |  Faint permeability overlay in both response panels',
             ha='center',va='center',fontsize=18,color='#4a5559')
    fig.text(.5,.159,r'Fixed PoF $\varepsilon=0.01$ schedule [m$^3$/s]; each period lasts 80 days',
             ha='center',va='center',fontsize=20,color=dark)
    rates='  →  '.join(f'{q:.5f}' for q in cfg['rates_m3_s'])
    fig.text(.5,.116,rates,ha='center',va='center',fontsize=20,color=teal)
    fig.text(.5,.050,'Common initial pressure and saturation • Fixed well and model settings'+
             f'  |  {count} selected ensemble positions',ha='center',va='center',fontsize=18,color=dark)
    fig.canvas.draw()
    renderer=fig.canvas.get_renderer()
    violations=[]
    for text in fig.findobj(Text):
        if text.get_visible() and text.get_text():
            b=text.get_window_extent(renderer)
            if b.width and b.height and (b.x0<0 or b.y0<0 or b.x1>1920.5 or b.y1>1080.5):
                violations.append(text.get_text())
    assert not violations, f'Text outside canvas: {violations}'
    bounds=[a.get_position().bounds for a in axes]
    cbounds=[a.get_position().bounds for a in caxes]
    assert all(np.allclose(b[1:],bounds[0][1:]) for b in bounds)
    assert all(np.allclose(b[1:],cbounds[0][1:]) for b in cbounds)
    assert all(np.isclose(a[0],b[0]) and np.isclose(a[2],b[2]) for a,b in zip(bounds,cbounds))
    return fig, {'panel_bounds':bounds,'colorbar_bounds':cbounds,'text_clipping':violations}


def encode(out, n):
    ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
    movie=out/'joint_permeability_day480_v1.mp4'
    # Explicit repeated input frames avoid image-demuxer time-base rounding.
    cmd=[ffmpeg,'-nostdin','-hide_banner','-loglevel','warning','-n','-f','rawvideo',
         '-pixel_format','rgb24','-video_size','1920x1080','-framerate',str(FPS),
         '-i','pipe:0','-frames:v',str(n*HOLD),
         '-an','-c:v','libx264','-preset','medium','-crf','18','-threads','2',
         '-pix_fmt','yuv420p','-movflags','+faststart',str(movie)]
    with (out/'encoding.stderr').open('xb') as log:
        proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stderr=log)
        try:
            for i in range(n):
                with Image.open(out/'frames'/f'frame_{i:03}.png') as im:
                    frame=im.convert('RGB').tobytes()
                for _ in range(HOLD): proc.stdin.write(frame)
        finally:
            proc.stdin.close()
        if proc.wait()!=0:raise RuntimeError('Encoding failed; see encoding.stderr')
    stream=imageio_ffmpeg.read_frames(str(movie),input_params=['-threads','2'])
    metadata=next(stream);stream.close()
    assert tuple(metadata['size'])==(1920,1080)
    assert metadata['codec']=='h264' and metadata['pix_fmt'].startswith('yuv420p')
    assert metadata['fps']==FPS and abs(metadata['duration']-n*.75)<.05
    # Decode every frame, exposing corruption and checking the exact frame count.
    md5=out/'decoded_frames.framemd5'
    subprocess.run([ffmpeg,'-nostdin','-v','error','-n','-threads','2','-i',str(movie),
                    '-f','framemd5',str(md5)],check=True)
    ndecoded=sum(bool(x) and not x.startswith('#') for x in md5.read_text().splitlines())
    assert ndecoded==n*HOLD
    return {'command':cmd,'metadata':metadata,'decoded_frame_count':ndecoded,'sha256':fhash(movie)}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('run_dir',type=Path)
    ap.add_argument('--outdir',type=Path)
    ap.add_argument('--members',help='Explicit preview subset, comma separated; default approved 32')
    ap.add_argument('--poster-only',action='store_true')
    ap.add_argument('--validate-only',action='store_true')
    a=ap.parse_args()
    cfg=json.loads((a.run_dir/'approval.json').read_text())
    positions=[int(x) for x in a.members.split(',')] if a.members else cfg['subset_positions']
    cfg,members,limits=audit(a.run_dir,positions)
    if a.validate_only:
        print(json.dumps({'validated_members':positions,'limits':limits,'input_hashes_match':True}));return
    if not a.poster_only and 'SLURM_JOB_ID' not in os.environ:raise RuntimeError('Animation must run on Slurm')
    if a.outdir is None:raise ValueError('--outdir is required for rendering')
    a.outdir.mkdir(parents=True,exist_ok=False)
    (a.outdir/'frames').mkdir()
    rows=[];layout=None
    for i,d in enumerate(members):
        fig,layout=figure(d,limits,cfg,len(members))
        frame=a.outdir/'frames'/f'frame_{i:03}.png'
        fig.savefig(frame,dpi=100) # Preserve exact 1920x1080 canvas.
        plt.close(fig)
        assert Image.open(frame).size==(1920,1080)
        if i==0:shutil.copy2(frame,a.outdir/'poster.png')
        p=a.run_dir/'members'/f'{d["member"]:03}'
        rows.append({'frame_index':i,'ensemble_position':d['member'],
            'realization_id':d['realization_id'],'day':480,'slurm_job_id':d['job_id'],
            'slurm_array_job_id':d['array_job_id'],'initial_state_source':'fixed reconstructed step1 member1, seed 2025',
            'initial_pressure_sha256':cfg['initial_pressure_sha256_f64'],
            'initial_saturation_sha256':cfg['initial_saturation_sha256_f64'],
            'porosity_sha256':cfg['porosity_sha256_f64'],'permeability_sha256':d['permeability_sha256'],
            'pressure_sha256':ahash(d['pressure_pa']),'saturation_sha256':ahash(d['co2_saturation']),
            'schedule_source':cfg['schedule_source'],'rates_m3_s':json.dumps(cfg['rates_m3_s']),
            'time_days':480,'input_source':str(p/'inputs.jld2'),
            'pressure_source':str(p/'day480.jld2')+'::pressure_pa',
            'saturation_source':str(p/'day480.jld2')+'::co2_saturation',
            'permeability_units':'mD, logarithmic color scale','pressure_display_units':'MPa, (p-p0)',
            'saturation_units':'dimensionless','color_limits':json.dumps(limits),
            'pressure_limit_exceedance_cells':int(d['mask'].sum()),'overlay_alpha':OVERLAY_ALPHA,
            'frame_png':str(frame),'status':'complete'})
        print(f'Rendered {i+1}/{len(members)}: position {d["member"]}, ID {d["realization_id"]}',flush=True)
        if a.poster_only:break
    with (a.outdir/'provenance.csv').open('x',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    video=None if a.poster_only else encode(a.outdir,len(members))
    rendered=[r['ensemble_position'] for r in rows]
    all_status=[]
    with (a.run_dir/'permeability_cache_members.csv').open() as f:
        all_ids={int(r['member']):int(r['realization_id']) for r in csv.DictReader(f)}
    for m in range(1,129):
        p=a.run_dir/'members'/f'{m:03}'
        status='shown' if m in rendered else 'outside_fixed_32_subset' if m not in cfg['subset_positions'] else 'completed_not_shown_in_preview' if (p/'COMPLETE.txt').exists() else 'failed' if (p/'FAILED.txt').exists() else 'pending_or_unsubmitted'
        all_status.append({'ensemble_position':m,'realization_id':all_ids[m],'status':status})
    write_json(a.outdir/'manifest.json',{'run_directory':str(a.run_dir),'slide_id':'p1-perm-movie',
        'display':'Permeability / (p-p0) / CO2 saturation','fixed_day':480,
        'shown_members':rendered,'approved_subset':cfg['subset_positions'],
        'subset_rule':cfg['subset_rule'],'all_128_member_status':all_status,
        'color_limits':limits,'overlay':{'quantity':'log10 K in mD','cmap':'colorcet rainbow4','alpha':OVERLAY_ALPHA,
        'compositing':'Permeability texture at 20% opacity over each response map; colorbars show underlying scalar colormaps'},
        'colormaps':{'K':'colorcet rainbow4','pressure_difference':'colorcet CET_L3_r','saturation':'cmasher rainforest_r'},
        'layout_checks':layout,'encoding':video,'poster_sha256':fhash(a.outdir/'poster.png'),
        'software':{'python':sys.version,'numpy':np.__version__,'matplotlib':matplotlib.__version__,
                    'h5py':h5py.__version__,'colorcet':cc.__version__,'cmasher':cmasher.__version__},
        'renderer_sha256':fhash(Path(__file__)),'prior_startup_attempt':cfg.get('previous_attempt')})
    caption=('Permeability-driven variability in pressure increase and CO2 saturation at Day 480 under the selected PoF epsilon=0.01 injection schedule. '
             'Initial pressure and saturation, well geometry and all other model settings are held fixed. '
             'Faint permeability overlays reveal geological structure; magenta outlines mark cells with reservoir pressure above p0(x,z)+4 MPa. '
             f'{len(rows)} predeclared ensemble positions shown; frames compare realizations at one fixed time. '
             'This is not a posterior-sample or time-evolution movie.')
    (a.outdir/'caption.txt').write_text(caption+'\n')
    print(a.outdir.resolve())


if __name__=='__main__':main()
