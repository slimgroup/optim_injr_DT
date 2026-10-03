# Accepted focused posterior mean and standard deviation

The user accepted the focused relative-margin preview and requested that the
standard-deviation figures be updated as well. The new PNG-only handoff is
`plots/paper_figures/posterior_relative_margin_focused_20261002/`.
It contains the accepted 8 posterior mean/std maps for steps 1–4 and the 6
unchanged separate histogram/ECDF panels for steps 2–4. All images are 400 dpi.
No old export, dataset, or paper-repository file is overwritten.

## What focused changes

Pressure values are multiplied by **1**, including PoF epsilon=0.01 and CVaR.
Only the relative-margin row's linear color normalization is changed:

| Statistic | Wide-preview color limits | Accepted focused limits | Normalized scale slope ratio |
| --- | --- | --- | --- |
| Mean relative margin | -0.1 to 1.0 | 0.02 to 0.98 | 1.1 / 0.96 = 1.145833 |
| Standard deviation of relative margin | 0 to 1.0 | 0 to 0.029 | 1 / 0.029 = 34.482759 |

These ratios describe the slope of the numerical mapping into the colormap,
not multiplication of pressure, margin, uncertainty, or perceived color
contrast. The mean mapping also shifts its lower endpoint. The colormap itself
is unchanged between the wide and focused previews. Warm colors in the mean
map indicate smaller positive margins; they do not in themselves mean that
the fracture threshold was exceeded. All three cases and all four steps share
the same limits, with no clipping in the new relative-margin row.

The three rows are relative margin, pressure difference, and CO2 saturation.
For standard deviation, all three rows are the corresponding pointwise
population standard deviations across the 128 posterior samples (`ddof=0`).
The pressure-difference and saturation row arrays, color limits, colormaps,
orientation, and units remain those of the previous accepted delivery.

The definition remains `r = (p_max - p) / p_max`, with `p_max = pres_Hyd + 4 MPa`
from each matching step file. At a fixed grid cell,
`SD(r) = SD(p - pres_Hyd in Pa) / p_max`. The first two standard-deviation rows
therefore remain related views of the same pressure uncertainty.

## Files and reproducibility

Posterior names explicitly identify the new row order:

```text
posterior/posterior_mean_relative_margin_pressurediff_sat_step{k}.png
posterior/posterior_std_relative_margin_pressurediff_sat_step{k}.png
```

New manuscript-name copies live under `paper_compat/posterior/`, named
`state_mean_relative_margin_pressurediff_sat_all_cases_t{k}.png` and
`state_std_relative_margin_pressurediff_sat_all_cases_t{k}.png`. These names
avoid overwriting or misidentifying the old pressure-difference / pressure /
saturation layout. `manifest.json` maps old and new paper paths explicitly.

The handoff copies the already rendered, approved focused PNGs byte for byte.
It does not rerender, recompute samples or statistics, or change bootstrap
settings. All 6 statistical PNGs are byte-identical to the previous delivery;
their historical ECDF settings remain B=5000 and seed=42. The purple histogram
quantile interval remains absent.

The lightweight assembly command is:

```bash
python scripts/python_tools/maintenance/assemble_focused_posterior_handoff.py \
  --output plots/paper_figures/posterior_relative_margin_focused_20261002
```

Choose a fresh output directory for subsequent runs. Source manifest hashes,
PNG dimensions/dpi, and paper-copy identity are verified while assembling.
The source audits, derived posterior arrays, prior numerical reports, renderer
snapshots, generating commit, and Slurm job are included in the handoff.
Actual regeneration from original JLD2 inputs continues to use
`submit_posterior_margin_preview.sh` on Slurm, with `--variants focused`.

## Paper-repository intake prompt

<!-- PAPER_PROMPT_START -->
请使用 posterior_relative_margin_focused_20261002/ 中的 PNG 更新论文。

1. 先核对 manifest.json 与 delivery_checksums.json。这次采用已确认的 focused
   posterior 均值和标准差，共8张，k=1–4；所有图片为400 dpi PNG。
2. 新的三行顺序为 relative margin、pressure difference、CO2 saturation。
   将 paper_compat/posterior/ 下的新文件复制到 figs/posterior/：
   state_mean_relative_margin_pressurediff_sat_all_cases_t{k}.png
   state_std_relative_margin_pressurediff_sat_all_cases_t{k}.png
   根据 manifest 的 paper_current_path → paper_new_path 更新 QMD 路径，保留
   原 Quarto ID 和交叉引用；保留旧图片，不要用新行顺序覆盖旧名称的图。
3. 更新对应均值/std captions 的三行描述。统计量是在每个 reservoir grid cell
   上沿128个后验样本计算；std 使用总体标准差 ddof=0。
   relative margin 定义为 r=(p_max-p)/p_max，p_max=pres_Hyd+4 MPa。
   relative margin 和 saturation 均无量纲，pressure difference 单位为MPa。
4. 三个case顺序保持 PoF epsilon=0.0、PoF epsilon=0.01、
   CVaR gamma=0.1 / alpha=0.01；标题使用监测索引k。
   focused只调整relative-margin色标：均值0.02–0.98，std 0–0.029。
   各case和监测步骤共用相同色标，没有放大或修改压力数据。
   均值图暖色只表示裕度较小，不应解释为已经发生压力越限。
5. 本目录同时附带此前已经确认的6张统计图，文件内容逐字节不变。
   如果paper已采用最新的1×3 histogram/ECDF，不需要再次改统计图。
   如尚未采用，复制 paper_compat/statistical/ 下的
   grid_histogram_selected_1x3_t{k}.png 和 grid_cdf_selected_1x3_t{k}.png，k=2–4，
   将每步旧合并图引用更新为这两张图，保留相应figure ID/交叉引用。
6. 历史ECDF仍为B=5000、seed=42；没有改成10000，也没有更新q-star选择算法。
   Histogram的紫色quantile confidence interval仍已删除。
   保留strict PoF在k=2/3/4分别127/124/122个可行完成样本及排除1/4/6个的说明；
   其他rate cases为128。不要把rate子集数量套用到posterior-state maps。
7. Appendix E采用k=2–4的6张posterior图和6张统计图；k=1的2张posterior图用于主文。
   Appendix D的pressure-bound/BHP内容保持原安排。最后渲染并检查caption、
   图片宽度、figure ID和交叉引用。
<!-- PAPER_PROMPT_END -->
