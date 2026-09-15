#!/usr/bin/env python3
"""Render PoF 0, CVaR x1.22 and no-control from saved simulation fields.

Sensitivity provenance stays in metadata and reports; on-screen policy titles
remain compact. Existing movies and simulation inputs are never replaced.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess

os.environ.setdefault('HDF5_USE_FILE_LOCKING', 'FALSE')
os.environ.setdefault('MPLCONFIGDIR', '/tmp/mpl_static_reference_movies')
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap, BoundaryNorm, Normalize
import cmasher
import colorcet as cc
from PIL import Image
import imageio_ffmpeg

BASE = Path(__file__).resolve().parents[2]
SOURCE = BASE / 'plots/paper_figures'
KEYS = ['pof_eps0', 'cvar_alpha001_gamma01', 'no_control']
TITLES = [r'PoF $\varepsilon=0.0$', r'CVaR $\alpha=0.01,\ \gamma=0.1$', 'No control']
FPS, SECONDS = 30, 40
EXTENT = (0, 511*6.25, 255*6.25, 0)


def write_json(path, value):
    with path.open('x') as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write('\n')


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(8*1024*1024), b''):
            h.update(b)
    return h.hexdigest()


class HistoricalFields:
    def __init__(self, end_day, no_control_continuation=None):
        self.files, self.refs, self.rates = {}, {k: {} for k in KEYS}, {}
        self.end_day = end_day
        self.continued = no_control_continuation is not None
        self.base = self.open('forward_sim_four_steps_base_data.jld2')
        self.p0 = self.base['p0'][:].T
        self.pmax = self.base['p_max'][:]
        np.testing.assert_array_equal(self.pmax, self.p0+4e6)
        self.rates[KEYS[0]] = self.base['POF_eps0_rates'][:]
        first = self.open('first_step_substeps_POF_eps0.jld2')
        assert float(first['dt_days'][()]) == 8
        np.testing.assert_array_equal(first['rates'][:], self.rates[KEYS[0]][:6])
        self.add_times(KEYS[0], first, 'pres_all', 'sat_all')
        self.duplicates = []
        for i, index in enumerate(self.base['POF_eps0_snap_idx'][:]):
            day = int(index*8)
            if day in self.refs[KEYS[0]]:
                p, s = self.fields(KEYS[0], day)
                np.testing.assert_array_equal(p, self.base['POF_eps0_pres_snaps'][i])
                np.testing.assert_array_equal(s, self.base['POF_eps0_sat_snaps'][i])
                self.duplicates.append(day)
            else:
                self.refs[KEYS[0]][day] = (Path(self.base.filename).name, 'POF_eps0_pres_snaps', 'POF_eps0_sat_snaps', i)
        exact_pof = self.open('controlled_day728_POF_eps0.jld2')
        assert int(exact_pof['day'][()]) == 728
        self.refs[KEYS[0]][728] = (Path(exact_pof.filename).name, 'pres', 'sat', None)
        cvar = self.open('full_campaign_video_CVaR_g01_a001_sensitivity.jld2')
        assert float(cvar['cvar_sensitivity_multiplier'][()]) == 1.22
        assert float(cvar['dt_days'][()]) == 8
        self.rates[KEYS[1]] = cvar['rate_by_substep'][:][::10]
        np.testing.assert_array_equal(cvar['rate_by_substep'][:], np.repeat(self.base['CVaR_g01_a001_rates'][:]*1.22, 10))
        self.add_times(KEYS[1], cvar, 'pres_all', 'sat_all')
        historical_no_control = self.open('no_control_delayed_ramp_10_periods.jld2')
        assert float(historical_no_control['dt_days'][()]) == 8
        assert int(historical_no_control['severe_day'][()]) == 728
        self.stop_day = 728
        no_control = historical_no_control
        if self.continued:
            no_control = self.open(no_control_continuation.resolve())
            assert bool(no_control['continued_injection'][()])
            assert int(no_control['restart_day'][()]) == 800
            assert int(no_control['final_day'][()]) == 1920
            assert float(no_control['dt_days'][()]) == 8
            np.testing.assert_array_equal(no_control['time_days'][:], np.arange(8,1921,8))
            np.testing.assert_array_equal(no_control['full_rates'][:], historical_no_control['full_rates'][:])
            assert no_control['pres_all'].shape == no_control['sat_all'].shape == (240,256,512)
            for variable in ('pres_all','sat_all'):
                for i in range(100):
                    np.testing.assert_array_equal(no_control[variable][i], historical_no_control[variable][i])
            self.stop_day = 1920
        self.rates[KEYS[2]] = no_control['full_rates'][:]
        self.add_times(KEYS[2], no_control, 'pres_all', 'sat_all', until=self.stop_day)
        self.reference = self.open('cvar_day728_sensitivity_1p22x.jld2')
        assert float(self.reference['multiplier'][()]) == 1.22
        np.testing.assert_array_equal(self.reference['rates'][:], self.rates[KEYS[1]][:10])
        for f in self.files.values():
            assert int(f['ground_truth_idx'][()]) == 2000
            np.testing.assert_array_equal(f['p0'][:].T, self.p0)
            np.testing.assert_array_equal(f['p_max'][:], self.pmax)
        # Match the static reference's pressure limits, including its 5% headroom.
        static_fields = [exact_pof['pres'][:], self.reference['pres'][:], historical_no_control['pres_all'][90]]
        self.pressure_max = max(float(((p-self.p0)/1e6).max()) for p in static_fields)*1.05
        self.times = [d for d in sorted(set(self.refs[KEYS[0]]) & set(self.refs[KEYS[1]])) if d <= end_day]
        assert self.times[0] == 8 and self.times[-1] == end_day
        assert all(d in self.refs[KEYS[2]] for d in self.times if d <= self.stop_day)

    def open(self, name):
        path = SOURCE/name
        key = path.name
        if key not in self.files:
            self.files[key] = h5py.File(path, 'r', locking=False)
        else:
            assert Path(self.files[key].filename).resolve() == path.resolve()
        return self.files[key]

    def add_times(self, key, f, pk, sk, until=1920):
        assert f[pk].shape == f[sk].shape
        if 'time_days' in f:
            np.testing.assert_array_equal(f['time_days'][:], np.arange(1,f[pk].shape[0]+1)*8)
        for i in range(f[pk].shape[0]):
            day = (i+1)*8
            if day <= until:
                self.refs[key][day] = (Path(f.filename).name, pk, sk, i)

    def source_day(self, key, day):
        return min(day, self.stop_day) if key == 'no_control' else day

    def fields(self, key, day):
        name, pk, sk, index = self.refs[key][self.source_day(key, day)]
        f = self.files[name]
        if index is None:
            return f[pk][:].astype(float), f[sk][:].astype(float)
        return f[pk][index].astype(float), f[sk][index].astype(float)

    def metric(self, key, day):
        source_day = self.source_day(key, day)
        p, s = self.fields(key, source_day)
        assert p.shape == s.shape == (256, 512)
        assert np.isfinite(p).all() and np.isfinite(s).all()
        r = (self.pmax-p)/self.pmax
        dp = (p-self.p0)/1e6
        rates = self.rates[key]
        volume = np.sum(rates*np.clip(source_day-np.arange(len(rates))*80, 0, 80))*86400
        q = float(rates[int(np.ceil(source_day/80))-1])
        return dict(case=key, day=day, source_day=source_day,
                    rate_m3_s=q, mass_Mt=float(volume*700/1e9),
                    min_r=float(r.min()), max_r=float(r.max()),
                    exceeding_cells=int(np.count_nonzero(r<0)),
                    max_pressure_excess_MPa=max(0.,float(((p-self.pmax)/1e6).max())),
                    dp_min_MPa=float(dp.min()), dp_max_MPa=float(dp.max()),
                    sat_min=float(s.min()), sat_max=float(s.max()))

    def audit(self, out):
        rows=[]
        self.metrics={}
        for key in KEYS:
            self.metrics[key] = {}
            for day in self.times:
                m=self.metric(key, day)
                self.metrics[key][day]=m
                ref=self.refs[key][m['source_day']]
                rows.append(dict(**m, source_file=ref[0], pressure_dataset=ref[1], saturation_dataset=ref[2], python_index=ref[3]))
        with (out/'saved_time_validation.csv').open('x', newline='') as f:
            w=csv.DictWriter(f, fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
        with (out/'implemented_rates.csv').open('x', newline='') as f:
            w=csv.writer(f);w.writerow(['case','start_day_exclusive','end_day_inclusive','actual_rate_m3_s'])
            for key in KEYS:
                for i, q in enumerate(self.rates[key]):
                    end=min((i+1)*80, self.stop_day if key=='no_control' else self.end_day)
                    if end>i*80:w.writerow([key,i*80,end,repr(float(q))])
        p,s=self.fields(KEYS[1],728)
        comparison=dict(static_file=Path(self.reference.filename).name,
                        movie_file='full_campaign_video_CVaR_g01_a001_sensitivity.jld2',
                        multiplier_both=1.22,
                        pressure_max_abs_difference_Pa=float(np.abs(p-self.reference['pres'][:]).max()),
                        saturation_max_abs_difference=float(np.abs(s-self.reference['sat'][:]).max()),
                        static_exceeding_cells=int(np.count_nonzero(self.reference['pres'][:]>self.pmax)),
                        movie_exceeding_cells=self.metrics[KEYS[1]][728]['exceeding_cells'])
        with h5py.File(BASE/'data/geo/wise_perm_models_2000_new.jld2','r',locking=False) as f:
            truth=f['BroadK'][:,:,1999]
        # Use fixed static-reference limits, with explicit extensions for any
        # saved values outside those limits. Never normalize individual frames.
        self.pressure_extend = 'both' if max(r['dp_max_MPa'] for r in rows)>self.pressure_max else 'min'
        result=dict(render_slurm_job_id=os.environ.get('SLURM_JOB_ID'), case_order=KEYS,
                    cvar_sensitivity_multiplier=1.22, on_screen_multiplier_label=False,
                    annotation_rates='Actual implemented rates and integrated mass; not unscaled base annotations.',
                    common_days=self.times, saved_states=len(self.times), final_day=self.end_day,
                    no_control_final_saved_day=self.stop_day,
                    no_control_continued_injection=self.continued,
                    no_control_after_stop=('New counterfactual: historical days8:8:800 retained exactly; continued at original planned 0.2 m3/s through1920 in 80-day simulator calls.' if self.continued else 'If requested, hold day728 with explicit in-panel timestamp; no simulated extension.'),
                    exact_pof_overlap_days=self.duplicates,
                    ground_truth=dict(file='data/geo/wise_perm_models_2000_new.jld2',julia_slice=2000,sha256=hashlib.sha256(truth.tobytes()).hexdigest()),
                    grid=dict(shape_xyz=[512,1,256],cell_m=[6.25,100,6.25],display_order='z,x; depth down',extent=EXTENT),
                    quantities=dict(margin='(pmax-pres)/pmax',pressure_increase_MPa='(pres-p0)/1e6',saturation='original saved CO2 saturation',pmax='p0+4e6 Pa'),
                    shared_color_limits=dict(margin=[-.1,1],pressure_increase_MPa=[0,self.pressure_max],saturation=[0,1]),
                    colormaps=dict(margin='Static Reds_r (26 colors) + Blues (230 colors); bin boundary aligned exactly at r=0',pressure='colorcet CET_L3_r',saturation='cmasher rainforest_r'),
                    out_of_colorbar_range=dict(margin='Under-range red and lower extension; negative values retained',pressure=f'Fixed static limits with {self.pressure_extend} extension; raw values retained and extrema recorded.'),
                    day728=[self.metrics[k][728] for k in KEYS], cvar_day728_reference=comparison,
                    movie_sampled_peak_cells={k:max(m['exceeding_cells'] for m in self.metrics[k].values()) for k in KEYS},
                    global_displayed_extrema={q:[min(r[lo] for r in rows),max(r[hi] for r in rows)] for q,lo,hi in [('margin','min_r','max_r'),('pressure_MPa','dp_min_MPa','dp_max_MPa'),('saturation','sat_min','sat_max')]},
                    source_files=[dict(path=str(Path(f.filename).relative_to(BASE)),bytes=Path(f.filename).stat().st_size,sha256=sha256(Path(f.filename))) for f in self.files.values()],
                    limitations=['No saved t=0 fields.','Strict PoF has only 80-day fields after day480 plus day728.','CVaR time-series and static Figure 1 use different historical simulator-call boundaries.','Instantaneous cell counts are not fracture/leakage proof or ensemble PoF.'])
        write_json(out/'validation.json', result)
        return result


def figure(data, day, selected):
    n=len(selected);combined=n==3
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':16,'axes.labelsize':17,'xtick.labelsize':15,'ytick.labelsize':15})
    fig=plt.figure(figsize=(19.2 if combined else 6.4,10.8),dpi=200,facecolor='white')
    fig.text(.5,.977,f'Day {day:04d}  |  Monitoring step {int(np.ceil(day/480))}',ha='center',va='center',fontsize=24 if combined else 18,weight='bold')
    # Same color entries as the static figure, with an exact red/blue sign boundary.
    margin_cmap=ListedColormap(np.vstack([plt.cm.Reds_r(np.linspace(0,.85,26)),plt.cm.Blues(np.linspace(0,1,230))]))
    margin_cmap.set_under(plt.cm.Reds_r(0.))
    edges=np.r_[np.linspace(-.1,0,27),np.linspace(0,1,231)[1:]]
    pressure_cmap=cc.cm['CET_L3_r'].copy();pressure_cmap.set_under(pressure_cmap(0.))
    cmaps=[margin_cmap,pressure_cmap,cmasher.rainforest_r]
    norms=[BoundaryNorm(edges,256),Normalize(0,data.pressure_max,clip=False),Normalize(0,1,clip=False)]
    labels=['Relative margin r\nDepth [m]','Pressure increase\nDepth [m]','CO₂ saturation\nDepth [m]']
    left,width,gap,cbar_x=(.073,.275,.012,.944) if combined else (.207,.640,0,.868)
    bottoms=[.620,.350,.080];height=.242
    ims=[None]*3
    for column,key in enumerate(selected):
        center=left+column*(width+gap)+width/2
        i=KEYS.index(key);m=data.metrics[key][day]
        title = 'No control (continued)' if key=='no_control' and data.continued else TITLES[i]
        fig.text(center,.934,title,ha='center',va='center',fontsize=23 if combined else 21,weight='bold')
        if key=='no_control' and day>data.stop_day:
            # The field timestamp stays visible when the common controlled clock advances.
            fig.text(center,.902,'Ended at day 728 — showing final saved state',ha='center',fontsize=13)
        else:
            fig.text(center,.900,f"q: {m['rate_m3_s']:.5f} m³/s   |   {m['mass_Mt']:.2f} Mt   |   {m['exceeding_cells']:,} cells",ha='center',fontsize=15 if combined else 12)
        p,s=data.fields(key,day)
        arrays=[(data.pmax-p)/data.pmax,(p-data.p0)/1e6,s]
        for row,bottom in enumerate(bottoms):
            ax=fig.add_axes([left+column*(width+gap),bottom,width,height])
            ims[row]=ax.imshow(arrays[row],extent=EXTENT,origin='upper',interpolation='nearest',aspect='auto',cmap=cmaps[row],norm=norms[row])
            ax.set_xticks([0,1000,2000,3000]);ax.set_yticks([0,500,1000,1500])
            if row<2:ax.tick_params(labelbottom=False)
            else:ax.set_xlabel('X [m]',labelpad=2)
            if column==0:ax.set_ylabel(labels[row],labelpad=5,fontsize=17 if combined else 14)
            else:ax.tick_params(labelleft=False)
            ax.plot([1562.5]*2,[1200,1237.5],color='white',linewidth=2.4)
            ax.plot([1562.5]*2,[1200,1237.5],color='black',linewidth=.9)
    for row,bottom in enumerate(bottoms):
        cax=fig.add_axes([cbar_x,bottom,.010 if combined else .022,height])
        cb=fig.colorbar(ims[row],cax=cax,extend=['min',data.pressure_extend,'neither'][row],spacing='proportional')
        cb.ax.tick_params(labelsize=14 if combined else 11)
        cb.ax.set_title(['r [−]','MPa','S [−]'][row],fontsize=14 if combined else 12,pad=9)
        if row==0:
            cb.set_ticks([0,.25,.5,.75,1]);cb.ax.axhline(0,color='0.3',linewidth=.6)
        elif row==1:cb.set_ticks([0,2,4])
        else:cb.set_ticks([0,.2,.4,.6,.8,1])
    fig.text(.5,.012,'Red cells mean pressure-limit exceedance (r < 0).',ha='center',fontsize=19 if combined else 11)
    fig.canvas.draw()
    renderer=fig.canvas.get_renderer()
    from matplotlib.text import Text
    for artist in fig.findobj(match=Text):
        if artist.get_visible() and artist.get_text():
            box=artist.get_window_extent(renderer)
            if box.x0 < -2 or box.y0 < -2 or box.x1 > fig.bbox.width+2 or box.y1 > fig.bbox.height+2:
                raise ValueError(f'Text outside canvas: {artist.get_text()!r}: {box.bounds}')
    return fig


def render(data,out,preview_only=False):
    if preview_only:
        for stem, selected in [('comparison',KEYS),*[(k,[k]) for k in KEYS]]:
            fig=figure(data,728,selected);fig.savefig(out/f'{stem}_day728.png',dpi=200);plt.close(fig)
        return
    frames=out/'frames';frames.mkdir()
    # Repeat actual stored states; allocate durations using physical time gaps.
    saved=np.asarray(data.times,dtype=float)
    boundaries=np.r_[0,(saved[:-1]+saved[1:])/2,data.end_day]
    ticks=np.rint(boundaries/data.end_day*FPS*SECONDS).astype(int)
    repeats=np.diff(ticks)
    assert len(repeats)==len(data.times) and repeats.min()>0 and repeats.sum()==1200
    timeline=[]
    for index,(day,count) in enumerate(zip(data.times,repeats)):
        for stem,selected in [('comparison',KEYS),*[(k,[k]) for k in KEYS]]:
            fig=figure(data,day,selected);path=frames/f'{stem}_{index:03d}.png'
            fig.savefig(path,dpi=200);plt.close(fig)
            if day in (728,data.end_day):
                with Image.open(path) as im:
                    if day==728:im.save(out/f'{stem}_day728.png')
                    if day==data.end_day:im.save(out/f'{stem}_poster.png')
        timeline.append(dict(saved_day=day,encoded_start_frame=int(ticks[index]),repeat_frames=int(count),source_days={k:data.source_day(k,day) for k in KEYS}))
        if index%10==0:print(f'Rendered {index+1}/{len(data.times)} saved days; day {day}',flush=True)
    write_json(out/'playback_timeline.json',timeline)
    ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
    for stem in ['comparison',*KEYS]:
        size='3840x2160' if stem=='comparison' else '1280x2160'
        cmd=[ffmpeg,'-hide_banner','-loglevel','error','-n','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s',size,'-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','18','-threads','4','-pix_fmt','yuv420p','-movflags','+faststart',str(out/f'{stem}.mp4')]
        with subprocess.Popen(cmd,stdin=subprocess.PIPE) as process:
            for index,count in enumerate(repeats):
                with Image.open(frames/f'{stem}_{index:03d}.png') as im:raw=im.convert('RGB').tobytes()
                for _ in range(int(count)):process.stdin.write(raw)
            process.stdin.close()
            if process.wait():raise RuntimeError(f'Encoding failed: {stem}')
        print(f'Encoded {stem}',flush=True)
    write_json(out/'output_checksums.json',[dict(file=p.name,bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(out.iterdir()) if p.suffix in ('.png','.mp4')])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--outdir',type=Path,required=True)
    parser.add_argument('--end-day',type=int,choices=[728,1920],default=728)
    parser.add_argument('--no-control-continuation',type=Path,help='New saved continuation export; validates all 100 historical prefix states before use.')
    parser.add_argument('--preview-only',action='store_true')
    args=parser.parse_args();args.outdir.mkdir(parents=True,exist_ok=False)
    data=HistoricalFields(args.end_day,args.no_control_continuation);result=data.audit(args.outdir)
    print(json.dumps(dict(saved_states=len(data.times),day728=result['day728'],reference=result['cvar_day728_reference'])),flush=True)
    render(data,args.outdir,args.preview_only)
    for f in data.files.values():f.close()


if __name__=='__main__':main()
