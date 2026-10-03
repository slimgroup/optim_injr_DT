# Historical histogram layout discussion

Recorded on 2025-12-28 for a 20-case, five-row/four-column grid. These are layout
experiments, not the current selected paper style. Use the established paired
posterior style and [figure manifest](../reference/PAPER_FIGURE_MANIFEST.md) for
current work.

| Setting | Recorded value |
|---|---|
| Panel titles | 13 pt |
| Axis labels | 16 pt |
| Tick labels | 13 pt |
| Main title | 18 pt |
| Figure size | `(4.0*ncols, 3.0*nrows)`, or 16 × 15 inches for 20 cases |
| Horizontal/vertical spacing | `wspace=0.25`, `hspace=0.35` |
| Margins | left=0.08, right=0.95, top=0.94, bottom=0.06 |

Exploratory alternatives reduced spacing to 0.15/0.25, enlarged each panel to
4.5 × 3.5 inches, or split the cases across two figures. A compact variant used
margins 0.07/0.96/0.95/0.05; a larger variant used spacing 0.20/0.30.

The note also considered reducing 30 histogram bins to 20–25 or using a log
axis. Those changes affect presentation of the distribution and must be
justified explicitly rather than used only to make bars look wider. Preserve
the selected sample set and statistic. Check the exported figure for clipping,
overlap, and legibility; avoid conflicting automatic and manual layout calls.
