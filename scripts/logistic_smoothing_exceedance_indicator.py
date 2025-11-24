import numpy as np
import matplotlib.pyplot as plt

# ---- NEW: unify all fonts to DejaVu Sans ----
plt.rcParams["mathtext.fontset"] = "dejavusans"
plt.rcParams["font.family"] = "DejaVu Sans"

def logistic_indicator(r, tau):
    return 1 / (1 + np.exp(r / tau))

tau = 0.3
r = np.linspace(-3, 3, 500)
y = logistic_indicator(r, tau)

plt.figure(figsize=(10, 4.5))
plt.plot(r, y, color='black', linewidth=3)
plt.fill_between(r, y, where=(r < 0), color='salmon', alpha=0.25)
plt.axvline(0, color='black', linestyle='--', linewidth=1)

plt.title("Logistic smoothing of exceedance indicator", fontsize=20, pad=15)

# Both x and y labels now use same font and same weight
plt.xlabel(r"Safety margin $r$", fontsize=18, labelpad=20)
plt.ylabel(r"$\sigma(-r/\tau)$", fontsize=18)

plt.tick_params(axis='x', pad=8)

plt.text(-1.8, 0.15, "Violation\n$r<0$", fontsize=14, ha='center')
plt.text(1.8, 0.15, "Safe\n$r>0$", fontsize=14, ha='center')

plt.text(0, -0.22, r"on limit  $r=0$", fontsize=13, ha='center')

plt.annotate(
    r"$\tau$ controls smoothness",
    xy=(1.0, logistic_indicator(1.0, tau)),
    xytext=(1.2, 0.55),
    arrowprops=dict(arrowstyle="->", lw=1.5),
    fontsize=14
)

plt.ylim(-0.05, 1.05)
plt.xlim(-3, 3)
plt.grid(False)
plt.tight_layout()
plt.savefig("logistic_smoothing_indicator.png", dpi=300)
plt.show()
