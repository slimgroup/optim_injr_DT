#!/usr/bin/env python3
"""Validate and summarize all saved no-control continuation times, on Slurm."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path

os.environ.setdefault('HDF5_USE_FILE_LOCKING', 'FALSE')
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

BASE = Path(__file__).resolve().parents[3]


def file_sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(8*1024*1024), b''):
            h.update(b)
    return h.hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--outdir', type=Path, required=True)
    args = p.parse_args()
    out = args.outdir
    assert out.is_dir()
    assert not (out/'no_control_continuation_validation.json').exists()
    historical = BASE/'plots/paper_figures/no_control_delayed_ramp_10_periods.jld2'
    diagnostics = args.source.parent/'diagnostics.csv'
    with diagnostics.open() as f:
        recorded = list(csv.DictReader(f))
    rows = []
    with h5py.File(args.source,'r',locking=False) as f, h5py.File(historical,'r',locking=False) as old:
        days = f['time_days'][:]
        np.testing.assert_array_equal(days, np.arange(8,1921,8))
        assert len(recorded) == len(days) == 240
        assert f['pres_all'].shape == f['sat_all'].shape == (240,256,512)
        assert int(f['restart_day'][()]) == 800 and bool(f['continued_injection'][()])
        p0, pmax = f['p0'][:].T, f['p_max'][:]
        np.testing.assert_array_equal(pmax,p0+4e6)
        np.testing.assert_array_equal(pmax,old['p_max'][:])
        rates = f['full_rates'][:]
        np.testing.assert_array_equal(rates,old['full_rates'][:])
        np.testing.assert_array_equal(rates[10:],np.full(14,.2))
        actual = f['rate_actual_by_substep'][:]
        assert np.isnan(actual[:100]).all() and np.isfinite(actual[100:]).all()
        rate_error = float(np.max(np.abs(np.abs(actual[100:])-.2)))
        # A rate-limited continuation would invalidate schedule-based annotations.
        assert rate_error < 1e-8, f'Achieved rate differs from schedule: {rate_error}'
        for i, day in enumerate(days.astype(int)):
            pr, sat = f['pres_all'][i], f['sat_all'][i]
            assert np.isfinite(pr).all() and np.isfinite(sat).all()
            if i<100:
                np.testing.assert_array_equal(pr,old['pres_all'][i])
                np.testing.assert_array_equal(sat,old['sat_all'][i])
            r = (pmax-pr)/pmax
            dp = (pr-p0)/1e6
            row = dict(day=int(day),rate_m3_s=float(rates[(day-1)//80]),
                       mass_Mt=float(np.sum(rates*np.clip(day-np.arange(24)*80,0,80))*86400*700/1e9),
                       exceeding_cells=int(np.count_nonzero(r<0)), min_r=float(r.min()),
                       max_pressure_excess_MPa=max(0.,float(((pr-pmax)/1e6).max())),
                       pressure_increase_min_MPa=float(dp.min()),pressure_increase_max_MPa=float(dp.max()),
                       saturation_min=float(sat.min()),saturation_max=float(sat.max()),
                       cells_below_margin_colorbar=int(np.count_nonzero(r<-.1)),
                       cells_above_pressure_colorbar=int(np.count_nonzero(dp>5.932220286972219)),
                       source='historical' if i<100 else 'continuation')
            assert int(float(recorded[i]['day'])) == day
            assert row['exceeding_cells'] == int(recorded[i]['exceeding_cells']) == int(f['exceeding_cells_by_substep'][i])
            for key in ('mass_Mt','min_r','max_pressure_excess_MPa'):
                np.testing.assert_allclose(row[key],float(recorded[i][key]),rtol=1e-12,atol=1e-12)
            rows.append(row)
    by_day = {r['day']:r for r in rows}
    assert by_day[728]['exceeding_cells'] == 6953
    np.testing.assert_allclose(by_day[728]['mass_Mt'],3.967488,atol=1e-12,rtol=0)
    with (out/'no_control_all_saved_times.csv').open('x',newline='') as f:
        w = csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    peaks = {}
    for key, fn in [('exceeding_cells',max),('max_pressure_excess_MPa',max),('min_r',min)]:
        value = fn(r[key] for r in rows)
        peaks[key] = dict(value=value,days=[r['day'] for r in rows if r[key]==value])
    summary = dict(scenario='No control, continued injection at 0.2 m3/s after the historical ramp',
                   validation_slurm_job_id=os.environ.get('SLURM_JOB_ID'),
                   time_audit=dict(count=240,first_day=8,last_day=1920,interval_days=8,duplicates=[],missing=[],historical_prefix_days=800,first_new_day=808),
                   historical_prefix_pressure_and_saturation='100/100 states array-equal in float64',
                   continuation_rate_max_absolute_error_m3_s=rate_error,
                   historical_actual_rate_availability='Only historical target rates exported; achieved continuation rates verified independently.',
                   day728=by_day[728],day800=by_day[800],day1920=by_day[1920],peaks_all_240_saved_times=peaks,
                   new_continuation_peak_cells=max(r['exceeding_cells'] for r in rows if r['day']>800),
                   interpretation='Instantaneous pressure-limit exceedance in the unchanged flow model. The model does not predict fracture opening or leakage. No monotonic growth is assumed.',
                   files=[dict(path=str(q.resolve().relative_to(BASE.resolve())),sha256=file_sha(q)) for q in (args.source,historical,diagnostics)])
    with (out/'no_control_continuation_validation.json').open('x') as f:
        json.dump(summary,f,indent=2,allow_nan=False);f.write('\n')

    plt.rcParams.update({'font.size':13,'axes.labelsize':14,'axes.titlesize':15})
    fig, axes = plt.subplots(1,2,figsize=(13.2,4.9),layout='constrained')
    for ax, key, ylabel in [(axes[0],'exceeding_cells','Pressure-limit exceeding cells'),
                            (axes[1],'max_pressure_excess_MPa','Maximum pressure excess [MPa]')]:
        ax.plot(days,[r[key] for r in rows],color='#b2182b',linewidth=2.1)
        ax.axvline(800,color='0.4',linestyle='--',linewidth=1.2,label='Continuation starts at day 800')
        ax.scatter([728,1920],[by_day[728][key],by_day[1920][key]],s=35,color='#b2182b',zorder=4)
        ax.set(xlabel='Time [days]',ylabel=ylabel,xlim=(0,1920))
        ax.set_xticks([0,480,960,1440,1920]);ax.set_ylim(bottom=0)
        ax.grid(alpha=.2)
        peak=peaks[key]; peakday=peak['days'][0]
        value=f"{peak['value']:,}" if key=='exceeding_cells' else f"{peak['value']:.3f} MPa"
        ax.set_title(f'Peak: {value} at day {peakday}')
    axes[1].legend(loc='upper right',fontsize=10)
    fig.suptitle('No control: original ramp, then continued injection at 0.20000 m³/s',fontsize=17)
    fig.savefig(out/'no_control_violation_history.png',dpi=200)
    plt.close(fig)
    print(json.dumps(summary,indent=2),flush=True)


if __name__=='__main__':
    main()
