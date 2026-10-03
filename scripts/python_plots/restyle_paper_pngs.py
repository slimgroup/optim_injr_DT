#!/usr/bin/env python3
"""Render compact posterior maps and separate 1x3 statistical PNGs from frozen arrays.

Run on Slurm. Existing artwork and source datasets are never modified. This
presentation export does not recompute posterior statistics or bootstrap results.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

os.environ.setdefault("MPLBACKEND", "Agg")
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
from matplotlib.gridspec import GridSpec
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from matplotlib.text import Annotation, Text
from matplotlib.ticker import MaxNLocator, FormatStrFormatter
from matplotlib.transforms import Bbox
import numpy as np
from PIL import Image

from export_posterior_appendix_e import (
    BASELINE_COMMIT, load_original, verify_numeric_contents,
)

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "plots/paper_figures/posterior_appendix_e_handoff_ecdf_only_20260909"
STYLE_DIRECTORY = ROOT / "plots/DT_control/exp_name=step1/statistical_analysis/ecdf/labels_reviewed_v6_20260915"
CASES = [r"(a) PoF $\varepsilon=0.0$", r"(b) PoF $\varepsilon=0.01$",
         r"(c) CVaR $\gamma=0.1$, $\alpha=0.01$"]
COLORS = ["#ff7900", "#287c32", "#166dcc"]
BOX_COLORS = ["#fff5e6", "#eef7e9", "#e9f3ff"]


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x") as f:
        json.dump(obj, f, indent=2, allow_nan=False)
        f.write("\n")


def verify_layout(fig, export_bbox=None):
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    canvas = (export_bbox.transformed(fig.dpi_scale_trans)
              if export_bbox is not None else fig.bbox)
    hidden_ticks, tick_boxes = set(), []
    for parent in fig.axes:
        for ax in (parent, *parent.child_axes):
            for axis in (ax.xaxis, ax.yaxis):
                lo, hi = sorted(axis.get_view_interval())
                boxes = []
                for tick in axis.get_major_ticks():
                    if not lo <= tick.get_loc() <= hi:
                        hidden_ticks.update([id(tick.label1), id(tick.label2)])
                    elif tick.label1.get_visible() and tick.label1.get_text():
                        boxes.append(tick.label1.get_window_extent(renderer))
                assert not any(a.overlaps(b) for a, b in zip(boxes, boxes[1:])), "Overlapping tick labels"
                tick_boxes.extend(boxes)
            annotations = [t.get_bbox_patch().get_window_extent(renderer)
                           for t in ax.texts if isinstance(t, Annotation) and t.get_bbox_patch()]
            assert not any(a.overlaps(b) for i, a in enumerate(annotations) for b in annotations[i+1:]), "Overlapping annotation boxes"
            bounds=ax.get_window_extent(renderer)
            assert all(a.x0 >= bounds.x0 and a.x1 <= bounds.x1 and
                       a.y0 >= bounds.y0 and a.y1 <= bounds.y1 for a in annotations), "Annotation box crosses the inset frame"
            for label in (ax.xaxis.label, ax.yaxis.label):
                if label.get_visible() and label.get_text():
                    b = label.get_window_extent(renderer)
                    assert not any(b.overlaps(t) for t in tick_boxes), "Axis label overlaps a tick label"
    for t in fig.findobj(Text):
        if not t.get_visible() or not t.get_text() or id(t) in hidden_ticks:
            continue
        b = t.get_window_extent(renderer)
        assert (b.x0 >= canvas.x0-1 and b.y0 >= canvas.y0-1 and
                b.x1 <= canvas.x1+1 and b.y1 <= canvas.y1+1), f"Clipped text: {t.get_text()}"
    return {"text_inside_canvas": True, "ticks_do_not_overlap": True,
            "axis_labels_clear_of_ticks": True, "annotation_boxes_do_not_overlap": True}


def draw_cdf(ax, data, index, inset=False):
    prefix = f"axes{index}"
    band = PolyCollection([data[prefix+"_collection0_path0"]], closed=False,
                          facecolor="#a6d2ff", edgecolor="#a6d2ff", alpha=.40, linewidth=.5)
    ax.add_collection(band)
    for j in range(5):
        x, y = data[f"{prefix}_line{j}_x"], data[f"{prefix}_line{j}_y"]
        if j == 0:
            ax.plot(x, y, color="#166dcc", lw=1.5 if inset else 2.2)
        elif j == 1:
            ax.plot(x, y, transform=ax.get_yaxis_transform(), color="#ed3035", lw=1.1, ls="--")
        else:
            ax.plot(x, y, color=COLORS[j-2], marker="*", ms=10 if inset else 7,
                    linestyle="None", zorder=5)
    ax.set_xlim(data[prefix+"_xlim"])
    ax.set_ylim(data[prefix+"_ylim"])


class Restyle:
    def __init__(self, args):
        self.args = args
        self.out = args.output.resolve()
        self.out.mkdir(parents=True, exist_ok=False)
        self.ref = args.reference.resolve()
        self.hashes = json.loads((self.ref / "delivery_checksums.json").read_text())
        self.inputs = {}
        self.entries = []
        self.manifest = json.loads(self.read("manifest.json").read_text())
        self.details = json.loads(self.read("validation/scientific_details.json").read_text())
        for source in [Path(__file__), ROOT / "scripts/python_plots/export_posterior_appendix_e.py",
                       ROOT / "scripts/shell/submit/submit_paper_png_restyle.sh"]:
            self.inputs[str(source.relative_to(ROOT))] = digest(source)
            dest = self.out / "provenance" / source.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest)
        for name in ["grid_cdf_selected_1x3.png", "grid_histogram_selected_1x3.png"]:
            path = STYLE_DIRECTORY / name
            self.inputs[str(path.relative_to(ROOT))] = digest(path)
        self.ppu = load_original("scripts/python_plots/plot_posterior_uncertainty.py", "frozen_posterior_style", self.out)

    def read(self, name):
        path = self.ref / name
        actual = digest(path)
        assert actual == self.hashes[name], name
        self.inputs[str(path.relative_to(ROOT))] = actual
        return path

    def cache(self, stem):
        with np.load(self.read(f"validation/{stem}.npz"), allow_pickle=False) as f:
            return {k:f[k].copy() for k in f.files}

    def save(self, fig, family, stem, paper_name, source_entry, numeric, layout, bbox=None, extra=None):
        target = self.out / family / (stem+".png")
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as f:
            fig.savefig(f, format="png", dpi=400, facecolor="white", bbox_inches=bbox, pad_inches=0)
        with Image.open(target) as im:
            info = {"pixels":list(im.size), "dpi":list(im.info["dpi"])}
            im.verify()
        compat = self.out / "paper_compat" / family / paper_name
        compat.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(target, compat)
        assert digest(target) == digest(compat)
        audit = f"validation/{stem}.json"
        write_json(self.out/audit, {"exact_numeric_equality":True, "numeric_arrays":numeric, "layout":layout, **(extra or {})})
        self.entries.append({"source_step":source_entry["source_step"],
            "source_path":source_entry["canonical_export_path"], "input_dataset":source_entry["input_dataset"],
            "historical_commit":BASELINE_COMMIT, "canonical_export_path":str(target.relative_to(ROOT)),
            "handoff_path":str(target.relative_to(self.out)), "paper_current_path":f"figs/{family}/{paper_name}",
            "replaces_paper_path":source_entry["paper_current_path"], "sha256":digest(target),
            "compat_path":str(compat.relative_to(self.out)), "numeric_validation":audit, **info, **(extra or {})})
        plt.close(fig)
        print(f"Validated and exported {stem}", flush=True)

    def posterior(self, step, stat):
        stem = f"posterior_{stat}_step{step}"
        source = next(e for e in self.manifest["figures"] if e["canonical_export_path"].endswith(stem+".png"))
        data = self.cache(stem)
        matplotlib.rcParams.update({"font.family":"DejaVu Sans", "mathtext.fontset":"dejavusans"})
        fig = plt.figure(figsize=(16, 8.2), dpi=400)
        gs = GridSpec(3,4,figure=fig,width_ratios=[1,1,1,.035],hspace=.10,wspace=.10,
                      left=.115,right=.945,top=.95,bottom=.08)
        labels = ["Pressure difference", "Reservoir pressure", r"CO$_2$ saturation"]
        field_axes, color_axes = [], []
        for row, var in enumerate(["pressure_diff","pressure","sat"]):
            for col in range(3):
                index = row*4+col
                ax = fig.add_subplot(gs[row,col]); field_axes.append(ax)
                cmap = self.ppu.VAR_CONFIG[var]["cmap"] if stat=="mean" else "inferno"
                im = ax.imshow(data[f"axes{index}_image0"], cmap=cmap,
                    extent=data[f"axes{index}_image0_extent"], origin=str(data[f"axes{index}_image0_origin"]),
                    vmin=data[f"axes{index}_image0_clim"][0], vmax=data[f"axes{index}_image0_clim"][1])
                ax.set_xlim(data[f"axes{index}_xlim"]); ax.set_ylim(data[f"axes{index}_ylim"])
                if row==0:ax.set_title(CASES[col],fontsize=17,weight="bold",pad=5)
                if col==0:
                    suffix = "\nstandard deviation" if stat=="std" else ""
                    ax.set_ylabel(labels[row]+suffix+"\nDepth [m]",fontsize=15,labelpad=12)
                else:ax.tick_params(labelleft=False)
                if row==2:
                    ax.set_xlabel("X [m]",fontsize=16)
                    ax.xaxis.set_major_locator(MaxNLocator(nbins=5))
                else:ax.tick_params(labelbottom=False)
                ax.tick_params(labelsize=13,length=3,pad=2)
            cax=fig.add_subplot(gs[row,3]);color_axes.append(cax)
            cb=fig.colorbar(im,cax=cax);cb.ax.tick_params(labelsize=13)
            if row<2:cb.set_label("MPa",fontsize=15)
        fig.canvas.draw()
        for row,cax in enumerate(color_axes):
            box=field_axes[row*3+2].get_position();old=cax.get_position()
            cax.set_position([old.x0,box.y0,old.width,box.height])
        renderer=fig.canvas.get_renderer()
        case_top=max(ax.title.get_window_extent(renderer).y1 for ax in field_axes[:3])
        title="Posterior mean" if stat=="mean" else "Posterior standard deviation"
        # Put the enlarged title just six points above the case headings,
        # instead of reserving the previous detached half-inch header.
        main=fig.suptitle(title+rf" at monitoring step $k={step}$",fontsize=28,weight="bold",
                         y=(case_top+6*fig.dpi/72)/fig.bbox.height,va="bottom")
        fig.canvas.draw()
        upper=main.get_window_extent(fig.canvas.get_renderer()).y1/fig.dpi+.055
        bbox=Bbox.from_bounds(0,0,16,upper)
        layout=verify_layout(fig,bbox)
        numeric=verify_numeric_contents(data,fig)
        self.save(fig,"posterior",stem,Path(source["paper_current_path"]).name,source,numeric,layout,bbox,
                  {"title_font_pt":28,"title_to_case_heading_gap_pt":6})

    def statistical(self, step, family):
        old_stem=f"injection_rate_hist_ecdf_step{step}"
        source=next(e for e in self.manifest["figures"] if e["canonical_export_path"].endswith(old_stem+".png"))
        data=self.cache(old_stem)
        details=list(self.details[f"statistical_step{step}"]["cases"].values())
        matplotlib.rcParams.update({"font.family":"DejaVu Sans","mathtext.fontset":"dejavusans",
            "font.size":14,"axes.linewidth":.9,"path.simplify":False})
        fig,axes=plt.subplots(1,3,figsize=(18,6.2),dpi=400)
        fig.subplots_adjust(left=.058,right=.988,bottom=.15,top=.80,wspace=.16)
        quantity="Distribution of optimized injection rates" if family=="histogram" else "Optimized-endpoint ECDFs"
        fig.suptitle(quantity+rf" at monitoring step $k={step}$",fontsize=28,weight="bold",y=.985)
        expected={}
        for col,ax in enumerate(axes):
            n=details[col]["completed_samples"]
            qualification=(f"{n} feasible completed; {128-n} excluded" if col==0 else f"{n} completed samples")
            ax.set_title(CASES[col]+"\n"+qualification,fontsize=17,weight="bold",pad=8)
            ax.set_xlabel(r"Injection-rate endpoint $q$ (m$^3$/s)",fontsize=17)
            ax.tick_params(labelsize=14)
            ax.grid(True,ls="--",lw=.5,alpha=.3);ax.set_axisbelow(True)
            if family=="histogram":
                for j in range(17):
                    x,y,w,h=data[f"axes{col}_patch{j}"]
                    ax.add_patch(Rectangle((x,y),w,h,fc="#7fb3d5",ec="#4d94c4",alpha=.8,lw=.8,
                        visible=j<16,transform=ax.transData if j<16 else ax.get_xaxis_transform()))
                ax.plot(data[f"axes{col}_line0_x"],data[f"axes{col}_line0_y"],
                        transform=ax.get_xaxis_transform(),color="#259c32",lw=2.3)
                ax.set_xlim(data[f"axes{col}_xlim"]);ax.set_ylim(data[f"axes{col}_ylim"])
                ax.xaxis.set_major_locator(MaxNLocator(nbins=5));ax.yaxis.set_major_locator(MaxNLocator(nbins=6,integer=True))
                for key,value in data.items():
                    if key.startswith(f"axes{col}_"):expected[key]=value
                qstar=data[f"axes{4+2*col}_annotation0_xy"][0]
                ax.axvline(qstar,color="#e3222b",ls="--",lw=2.4)
                expected[f"axes{col}_line1_x"]=np.array([qstar,qstar])
                expected[f"axes{col}_line1_y"]=np.array([0,1])
                legend=[Patch(fc="#7fb3d5",ec="#4d94c4",alpha=.8,label=f"Histogram (n={n})"),
                    Line2D([],[],color="#259c32",lw=2.3,label=f"1% quantile: {details[col]['quantile_01']:.5f}"),
                    Line2D([],[],color="#e3222b",lw=2.4,ls="--",label=rf"$q_k^*$: {qstar:.5f}")]
                ax.legend(handles=legend,loc="upper right",fontsize=12,framealpha=.95)
                x=np.array(details[col]["plotted_q_rate6"])
                ax.text(.97,.48,f"mean={np.mean(x):.5f}\nmedian={np.median(x):.5f}",ha="right",va="center",
                    transform=ax.transAxes,fontsize=13,bbox=dict(boxstyle="round,pad=.25",fc="#ffffe6",ec="#999999",alpha=.95))
                if col==0:ax.set_ylabel("Count",fontsize=17)
            else:
                old_index=3+2*col;new_index=2*col
                draw_cdf(ax,data,old_index)
                ax.xaxis.set_major_locator(MaxNLocator(nbins=5));ax.set_yticks([0,20,40,60,80,100])
                if col==0:ax.set_ylabel("Cumulative probability (%)",fontsize=17)
                inset=ax.inset_axes([.40,.10,.55,.45])
                draw_cdf(inset,data,old_index+1,inset=True)
                inset.set_title("Zoom (0–8%)",fontsize=12,pad=6)
                inset.xaxis.set_major_locator(MaxNLocator(nbins=3));inset.xaxis.set_major_formatter(FormatStrFormatter("%.3f"))
                inset.set_yticks([0,2,4,6,8]);inset.tick_params(labelsize=10.5)
                inset.grid(True,ls="--",lw=.4,alpha=.3);inset.set_axisbelow(True)
                for j,(label,pos) in enumerate(zip([r"$q_k^*$","ECDF","Opt."],[.16,.5,.84])):
                    xy=data[f"axes{old_index+1}_annotation{j}_xy"]
                    inset.annotate(label+f"\n{xy[0]:.5f}",xy=xy,xytext=(pos,.70),textcoords="axes fraction",
                        color=COLORS[j],ha="center",va="center",fontsize=11.5,weight="bold",
                        bbox=dict(boxstyle="round,pad=.15",fc=BOX_COLORS[j],ec=COLORS[j],alpha=.96),
                        arrowprops=dict(arrowstyle="->",color=COLORS[j],lw=1.1))
                for offset in (0,1):
                    for key,value in data.items():
                        prefix=f"axes{old_index+offset}_"
                        if key.startswith(prefix):expected[f"axes{new_index+offset}_"+key[len(prefix):]]=value
                if col==0:
                    handles=[Patch(fc="#a6d2ff",ec="#a6d2ff",alpha=.40,label="Pointwise 95% bootstrap CI\n(B=5000)"),
                             Line2D([],[],color="#166dcc",lw=2.2,label="Empirical CDF"),
                             Line2D([],[],color="#ed3035",lw=1.1,ls="--",label="Target p = 1%")]
                    # Prefer the reference's upper-right legend, lowering it
                    # only enough to keep the underlying confidence band clear.
                    for anchor in np.arange(.98,.65,-.02):
                        legend=ax.legend(handles=handles,loc="upper right",bbox_to_anchor=(.99,anchor),fontsize=10.5,framealpha=.95)
                        fig.canvas.draw()
                        b=legend.get_window_extent(fig.canvas.get_renderer())
                        path=ax.collections[0].get_paths()[0].transformed(ax.collections[0].get_transform())
                        if not path.intersects_bbox(b,filled=True) and not b.overlaps(inset.get_window_extent()):break
                    else:raise ValueError("No unobscured legend position")
        fig.canvas.draw()
        numeric=verify_numeric_contents(expected,fig)
        layout=verify_layout(fig)
        if family=="ecdf":
            for ax in axes:
                path=ax.collections[0].get_paths()[0].transformed(ax.collections[0].get_transform())
                assert not path.intersects_bbox(ax.child_axes[0].get_window_extent(),filled=True), "Inset obscures main confidence band"
            layout["insets_and_legend_clear_of_main_confidence_bands"]=True
        paper_name=f"grid_{'histogram' if family=='histogram' else 'cdf'}_selected_1x3_t{step}.png"
        self.save(fig,"statistical",f"injection_rate_{family}_step{step}",paper_name,source,numeric,layout,
                  extra={"layout":"1x3","bootstrap_replicates":5000,"bootstrap_seed":42,
                         "added_histogram_qstar_line_from_existing_ecdf_marker":family=="histogram"})

    def finish(self):
        for name,h in self.inputs.items():assert digest(ROOT/name)==h,name
        write_json(self.out/"input_checksums.json",self.inputs)
        write_json(self.out/"manifest.json",{"generating_commit":subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),
            "slurm_job_id":os.environ["SLURM_JOB_ID"],"historical_commit":BASELINE_COMMIT,
            "numpy":np.__version__,"matplotlib":matplotlib.__version__,
            "formats":["png"],"method":"Render checksum-matched frozen numerical arrays; no statistics recomputed",
            "scientific_results_unchanged":True,"histogram_quantile_interval_displayed":False,
            "figures":self.entries})
        shutil.copyfile(self.read("validation/scientific_details.json"),self.out/"validation/scientific_details.json")
        write_json(self.out/"checksums.json",{str(p.relative_to(self.out)):digest(p) for p in sorted(self.out.rglob('*')) if p.is_file()})
        print(f"Handoff complete: {self.out}",flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--reference",type=Path,default=REFERENCE)
    parser.add_argument("--steps",type=int,nargs="+",default=[1,2,3,4],choices=[1,2,3,4])
    parser.add_argument("--family",choices=["all","posterior","statistical"],default="all")
    args=parser.parse_args()
    if not os.environ.get("SLURM_JOB_ID"):parser.error("Run through sbatch or salloc")
    work=Restyle(args)
    for k in args.steps:
        if args.family in ("all","posterior"):
            for stat in ("mean","std"):work.posterior(k,stat)
        if k>1 and args.family in ("all","statistical"):
            for family in ("histogram","ecdf"):work.statistical(k,family)
    work.finish()


if __name__=="__main__":main()
