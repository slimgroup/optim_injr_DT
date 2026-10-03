# Validation and review

Slurm job 13818009 completed successfully (exit 0, elapsed 61 seconds).
All 14 figures are exported directly from frozen numerical plot arrays at
400 dpi. No PDF or SVG is generated. No optimization, posterior-statistic,
bootstrap, or rate-selection calculation was rerun.

Every posterior figure passes exact comparison of the complete original
numeric snapshot: images, colormaps, color limits, extents, orientation,
axes limits and colorbar numerical geometry. The main title is 28 points,
with a six-point gap above the case headings. PNGs are 6400 x 3390 pixels.

The six 1x3 statistical figures pass exact array comparisons using explicit
old-to-new axis mappings. Histogram bins/counts, sample-quantile lines,
ECDF and inset curves, confidence-path vertices, limits and all crossing
coordinates are unchanged. Histogram q-star lines are explicitly copied
from the existing ECDF crossing markers. The purple histogram quantile
confidence shading is not visible. Statistical PNGs are 7200 x 2480 pixels.

Layout checks at the final 400 dpi pass for every figure: text inside the
canvas, ticks without overlap, axis-label clearance, inset annotation-box
separation and containment, and visibility of main ECDF confidence bands
behind the inset and legend locations. Statistical preview layouts were
visually inspected for all three steps, followed by review of the final
ECDF and posterior standard-deviation exports. Representative posterior
mean/std and histogram exports were also inspected during layout development.

The scientific-details JSON is byte-identical to the reference. B=5000,
seed=42, historical grid crossings, sample counts and dataset mappings are
preserved. All generating input files retained their checksums. Each of
14 paper_compat PNGs is byte-identical to its corresponding canonical-name
PNG in this handoff. There are 14 distinct figures and 28 PNG files including
those compatibility copies; the copies are not different experiments.

Prior handoffs, canonical figures, all source datasets and pre-existing
working-tree/index changes remain intact. Paper-side QMD rendering remains
with the paper repository, which is not present in this checkout.

The mean/median display summaries are evaluated from the frozen rate arrays
using the historical formatting. All nine cases exactly match the previously
printed SVG labels; see validation/printed_statistics.json. This display
arithmetic does not recompute posterior statistics, ECDFs, bootstrap intervals
or rate selections.
