# Paper-repository handoff: ground-truth BHP response

Date: 2026-09-07. Scope: the three original selected control strategies and no control, using the existing ground-truth replays. The numerical audit is complete at the saved output times; calibrated BHP-limit compliance remains unassessed. This handoff adds manuscript text and packages existing results. It does not change the optimization, rate schedules, simulator configuration or pressure data.

## Manuscript paragraph

Use the following paragraph near the forward comparison of the original selected strategies. The notation `p_max` preserves the code/paper convention and denotes the prescribed model fracture-pressure bound, equivalently `p_frac^model`. It does not introduce a new bound or rename an existing manuscript variable globally.

```latex
To complement the reservoir-pressure fracture-risk assessment, we evaluated the bottom-hole pressure (BHP) response of the selected injection schedules on the ground-truth permeability realization (Fig.~\ref{fig:bhp_ground_truth}). BHP was extracted at the injector reference depth of 1196.875~m using the simulator's absolute-pressure convention. At eight-day saved outputs, the maximum BHPs over 1920 days were 14.554, 15.013 and 16.149~MPa for PoF ($\varepsilon=0$), PoF ($\varepsilon=0.01$) and CVaR ($\alpha=0.01$, $\gamma=0.1$), respectively; the no-control case reached 18.262~MPa at its day-728 shutdown. The prescribed model fracture-pressure bound, $p_{\max}(x,z)=p_0(x,z)+4\,\mathrm{MPa}$, is evaluated on reservoir-cell pressures. These BHP results are reported as a posteriori diagnostics because an independently calibrated BHP operating limit is not specified in the synthetic model.
```

## Figure and caption

Copy the existing PNG from `plots/paper_figures/bhp_four_selected_strategies_20260907/bhp_four_strategies.png` to `figures/bhp_four_strategies.png` in the paper repository, or adjust the path below to its figure-directory convention. The host document needs `graphicx`. Figure placement and width may be adapted to its layout.

```latex
\begin{figure}[t]
    \centering
    \includegraphics[width=\linewidth]{figures/bhp_four_strategies.png}
    \caption{Ground-truth BHP histories for the three original selected control strategies and no control. Pressures use the simulator's absolute-pressure convention at a reference depth of 1196.875~m and are sampled every eight days. The control strategies are evaluated through day 1920; the no-control trace ends at its day-728 shutdown. Filled circles mark the maximum saved BHP for each strategy, and vertical dotted lines indicate monitoring-step boundaries.}
    \label{fig:bhp_ground_truth}
\end{figure}
```

The single-panel PNG contains only the four requested histories. The older two-panel audit figure also contains multiplied sensitivity schedules in its right panel and is not the figure for this paragraph. No BHP limit line is added. The image is reused byte-for-byte; no PDF is generated.

## Verified results and interpretation

| Strategy | Maximum saved BHP (MPa) | Peak day | Last checked day | Saved outputs |
|---|---:|---:|---:|---:|
| PoF epsilon=0 | 14.554 | 1848 | 1920 | 240 |
| PoF epsilon=0.01 | 15.013 | 888 | 1920 | 240 |
| CVaR alpha=0.01, gamma=0.1 | 16.149 | 408 | 1920 | 240 |
| No control | 18.262 | 728 | 728 | 91 |

- BHP is Julia entry 1 of the length-8 injector pressure vector: one accumulator/reference node and seven perforated well nodes. The installed simulator's canonical BHP output was checked against entry 1. Maxima are taken along time for that entry, not across all eight nodes.
- All four histories use `BroadK[2000,:,:]` in `data/geo/wise_perm_models_2000_new.jld2`, with Julia shape `(512,256)` in `(x,z)` order and permeability stored in mD. Ground-truth state initialization and the historical rates are retained.
- The audit checked the installed rate-control configuration and achieved rates. The current selected optimization has no active BHP constraint; its `BHP_max` expression feeds diagnostics. These completed checks should not be relabeled pending merely because an external research note did not inspect the repository.
- `p_max=p0+4 MPa` is the existing prescribed model fracture-pressure bound, evaluated on reservoir-cell pressure. The code explicitly labels it "Fracture pressure" at `src/optim_inject.jl:697–700`; its definition is at lines 635–638. It has fracture meaning within the synthetic model, without constituting calibrated formation failure physics or a BHP operating limit.
- Physical BHP-limit compliance is **not assessed**. The existing data schema reports `physical_limit_status=not_calibrated`; that is not a pass result. Applying the fracture proxy to well-side/perforation pressure, deriving a trajectory-dependent hypothetical BHP bound or adding a control limiter would be separate work. None is claimed in this paragraph.
- Maxima cover saved outputs every eight days, not every internal solver step or continuous time. The no-control record ends at day 728; it is not extrapolated to day 1920. The tabulated maxima describe each stated window, not a matched-window percentage reduction.
- The result is a ground-truth diagnostic, with no ensemble-wide BHP-limit probability claim. The 89.5 Pa replay discrepancy concerns reservoir fields; it is not a BHP uncertainty estimate. The separate Figure 1 multiplied-CVaR verification is outside this paragraph.

## Provenance and transfer bundle

- Numerical replay code state: `d00940fe17a5c3f19a3aa402149613d1d7bc9ac9`, with the working-tree state recorded in the original audit inventory. Reusable audit scripts and the PNG exporter were committed in `db95377`.
- Julia 1.11.3; Jutul 0.2.11; JutulDarcy 0.2.7; JutulDarcyRules 0.2.8. The audit distinguishes these replay records from incomplete historical forward-export version metadata.
- Four-case source summary: `data/diagnostics/bhp_four_selected_strategies_20260907/bhp_four_strategies_summary.csv`. All-node and reference-depth histories are in the same directory.
- Replay evidence: `data/diagnostics/bhp_audit_20260907_12902263/`; full report: `docs/analysis/BHP_GROUND_TRUTH_AUDIT_2026-09-07.md`.
- Transfer archive: `data/diagnostics/bhp_paper_handoff_20260907.zip`, containing this handoff, `bhp_paragraph.tex`, `bhp_figure.tex`, `figures/bhp_four_strategies.png`, `bhp_summary.csv` and `provenance.json` with file hashes.

Extract the archive into a review directory, integrate the paragraph and figure into the paper's existing section and figure conventions, and retain the CSV/provenance as supporting records. The receiving paper repository has not been edited by this handoff. An external literature review is not substituted for the completed code audit, and no new literature-based numerical BHP limit is asserted.
