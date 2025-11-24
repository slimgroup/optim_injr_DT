import numpy as np
import matplotlib.pyplot as plt
from scipy.special import erf

# ---------------- Global style ----------------
plt.rcParams["figure.figsize"] = (6.5, 4.0)
plt.rcParams["font.size"] = 14

fig, ax = plt.subplots()

# ---------------- Construct a right-skewed "pdf" ----------------
x = np.linspace(0.0, 1.0, 600)
mu, sigma = 0.35, 0.18
pdf = np.exp(- (x - mu) ** 2 / (2 * sigma ** 2))
pdf /= pdf.max()

alpha = 0.85
cdf = 0.5 * (1 + erf((x - mu) / (sigma * np.sqrt(2))))
idx = np.argmin(np.abs(cdf - alpha))
q_alpha = x[idx]

ax.set_xlim(-0.05, 1.05)
ax.set_ylim(-0.25, 1.05)

# ---------------- Fill areas ----------------
mask_left = x <= q_alpha
mask_right = x >= q_alpha

ax.fill_between(x[mask_left], 0, pdf[mask_left],
                color="#e68d93", alpha=0.95, linewidth=0)
ax.fill_between(x[mask_right], 0, pdf[mask_right],
                color="#d7d7d7", alpha=0.95, linewidth=0)

ax.plot(x, pdf, color="black", linewidth=2.2)

# ---------------- Custom axes with arrows ----------------
ax.set_xticks([])
ax.set_yticks([])
for spine in ax.spines.values():
    spine.set_visible(False)

ax.annotate("", xy=(1.02, 0), xytext=(0, 0),
            arrowprops=dict(arrowstyle="->", linewidth=1.8))
ax.annotate("", xy=(0, 1.02), xytext=(0, 0),
            arrowprops=dict(arrowstyle="->", linewidth=1.8))

ax.text(-0.07, 0.5, "Probability density",
        rotation=90, va="center", ha="center")
ax.text(1.03, -0.06, r"$g(d, Z)$",
        va="top", ha="right")

# ---------------- Q_alpha ----------------
ax.vlines(q_alpha, 0, pdf[mask_right][0],
          linestyles="--", linewidth=1.6, color="black")
ax.text(q_alpha, -0.10, r"$Q_\alpha$", ha="center", va="top")

# ---------------- Internal text ----------------
# POF: back inside the curve (new version)
ax.text(0.28, 0.72, "POF",
        ha="center", va="center")

ax.text(0.32, 0.42, "exceedance\nprobability",
        ha="center", va="center")

# ---------------- CVaR ----------------
ax.text(0.70, 0.65, "average of\nworst outcomes",
        ha="center", va="center")

ax.text(0.72, 0.40, "CVaR",
        ha="left", va="center")

ax.annotate(
    "",
    xy=(q_alpha + 0.10, pdf[mask_right][len(pdf[mask_right]) // 3]),
    xytext=(0.68, 0.58),
    arrowprops=dict(arrowstyle="->", linewidth=1.4),
)

# ---------------- Title ----------------
ax.set_title("Relationship between POF and CVaR", pad=12)

plt.tight_layout()
plt.savefig("pof_cvar.png", dpi=300, bbox_inches="tight")
plt.show()
