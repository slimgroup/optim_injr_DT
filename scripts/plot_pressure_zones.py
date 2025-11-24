import numpy as np
import matplotlib.pyplot as plt

# -----------------------
# Smaller & more compact figure size
# -----------------------
plt.rcParams["figure.figsize"] = (6.5, 4.0)
plt.rcParams["font.size"] = 15

fig, ax = plt.subplots()

# region boundaries
y_safe_top     = 1.0
y_warning_top  = 2.0
y_fracture_lim = 2.8

# background zones
ax.axhspan(0,            y_safe_top,    facecolor="#e5f5d1")
ax.axhspan(y_safe_top,   y_warning_top, facecolor="#ffecb3")
ax.axhspan(y_warning_top,y_fracture_lim,facecolor="#f4c1b5")

# pressure curve
t = np.linspace(0, 1, 500)
pressure = 0.25 + 2.2 / (1 + np.exp(-8 * (t - 0.6)))
ax.plot(t, pressure, color="#1f77b4", linewidth=3)

# fracture & safety lines
ax.axhline(y_fracture_lim, color="#d62728", linewidth=2)
ax.axhline(y_warning_top, color="#d62728", linewidth=2, linestyle="--")

# labels
ax.text(0.02, y_fracture_lim + 0.12,
        "fracture pressure limit",
        ha="left", va="bottom")

ax.text(0.50, 0.5*y_safe_top, "safe zone", ha="center", va="center")
ax.text(0.73, 0.5*(y_safe_top+y_warning_top), "warning\nzone", ha="center", va="center")
ax.text(0.85, 0.5*(y_warning_top+y_fracture_lim), "violation", ha="center", va="center")

# simulated pressure arrow (slightly more compact)
t_sp = 0.32
y_sp = pressure[np.searchsorted(t, t_sp)]
ax.annotate("simulated\npressure",
            xy=(t_sp, y_sp),
            xytext=(0.24, 1.35),
            ha="center", va="center",
            arrowprops=dict(arrowstyle="->", linewidth=1.5,
                            connectionstyle="arc3,rad=-0.2"))

# safety margin arrow
ax.annotate("safety margin",
            xy=(0.72, y_warning_top),
            xytext=(0.55, y_fracture_lim - 0.18),
            ha="center", va="center",
            arrowprops=dict(arrowstyle="->", linewidth=1.5))

# double arrow for warning zone height
ax.annotate("",
            xy=(0.97, y_warning_top - 0.03),
            xytext=(0.97, y_safe_top + 0.03),
            arrowprops=dict(arrowstyle="<->", linewidth=1.5))

# axes cleanup
ax.set_xlim(0, 1)
ax.set_ylim(0, y_fracture_lim + 0.25)
ax.set_xlabel("time")
ax.set_xticks([])
ax.set_yticks([])

for spine in ["top", "right"]:
    ax.spines[spine].set_visible(False)

plt.tight_layout()
plt.savefig("pressure_zones_compact.png", dpi=400, bbox_inches='tight')
plt.show()
