#!/bin/bash
set -euo pipefail
module load julia/1.11.3
cd "${SLURM_SUBMIT_DIR:-$PWD}"
export JULIA_DEPOT_PATH="$HOME/julia-depot"
mkdir -p "$JULIA_DEPOT_PATH"
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
audit_root="${1:?Missing audit root}"
member="${SLURM_ARRAY_TASK_ID:?Must run via bounded Slurm array}"
mkdir -p "$audit_root/resources"
mkdir -p "$audit_root/member_locks"
exec 9>"$audit_root/member_locks/$member.lock"
flock -n 9 || { echo "Member $member already has an active worker" >&2; exit 3; }
audit_source=$(python3 - "$audit_root" <<'PY'
from pathlib import Path
import hashlib,sys
b=Path('scripts/julia_scripts/utilities/audit_zero_injection_pressure.jl').read_bytes()
d=Path(sys.argv[1])/'source_snapshots';d.mkdir(exist_ok=True)
p=d/(hashlib.sha256(b).hexdigest()+'_audit_zero_injection_pressure.jl')
if p.exists():
    assert p.read_bytes()==b
else:
    with p.open('xb') as f:f.write(b)
print(p.resolve())
PY
)
audit_attempt="${SLURM_RESTART_COUNT:-0}_$(date -u +%Y%m%dT%H%M%S)_$$"
/usr/bin/time -v -o "$audit_root/resources/${SLURM_ARRAY_JOB_ID}_${audit_attempt}_${member}.txt" \
  julia --startup-file=no "$audit_source" "$member" "$audit_root"
