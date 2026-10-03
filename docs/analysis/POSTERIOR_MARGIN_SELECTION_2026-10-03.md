# Selected posterior relative-margin sensitivity: factor 1.13

On 2026-10-03 the user selected the existing **1.13** pressure-increment
sensitivity version for both posterior means and standard deviations at
monitoring steps k=1–4. The 1.145 version remains a comparison preview;
both versions and all original assets remain available. The previous larger
factor was 1.145, not 1.45.

Use the eight 400 dpi PNGs in
`plots/paper_figures/posterior_margin_sensitivity_increment_1p13_20261002/`.
Its `PAPER_REPO_PROMPT.txt` and `handoff_manifest.json` provide the paper
instructions and exact mapping. Compatibility copies in `paper_compat/`
are byte-identical to the corresponding canonical PNGs.

The selected transformation is `p_used = pres_Hyd + 1.13 * (p - pres_Hyd)`,
applied only when computing relative margin, with the same factor across
all cases, steps, cells and samples. Mean-field exceeding counts are
`[0, 0, 69]` at k=2 and `[0, 0, 0]` at k=1, 3 and 4. These count grid cells
with negative transformed mean margin, not samples or failure probabilities.

Mean-margin color limits remain `[-0.1, 1]`, with an exact zero red/blue
boundary. Relative-margin std limits remain `[0, 0.032]` across all steps.
The proposed saturation-std color-limit change to `[0, 0.30]` has not been
adopted; the existing `[0, 0.9]` limits remain. Other rows and statistical
rate figures are unchanged. This selection required no numerical rerun
or image re-export.

All existing delivery checksums were verified on 2026-10-03, along with
the eight PNG dimensions (6400 by 3388), 400 dpi metadata, compatibility
copy identity, factor and exceeding-cell counts. The paper repository
has not been edited here. Its captions/methods must accompany the figures
with the sensitivity interpretation and the 1.13 transformation described
in the existing handoff prompt.

See [the 1.13 methodology and validation report](POSTERIOR_MARGIN_SENSITIVITY_2026-10-02.md).
