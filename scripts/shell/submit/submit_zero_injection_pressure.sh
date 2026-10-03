#!/bin/bash
# Bounded pilot by default. Full campaign requires the separately reviewed allocation token.
set -euo pipefail
audit_root="${1:?Usage: bash submit_zero_injection_pressure.sh AUDIT_ROOT [pilot|full]}"
mode="${2:-pilot}"
cd "$(dirname "$0")/../../.."
audit_root="$(realpath "$audit_root")"
[[ -s "$audit_root/provenance_manifest.json" && -s "$audit_root/members.csv" ]] || { echo "Prepare and freeze the protocol first" >&2; exit 2; }
case "$mode" in
  pilot) members="1,64,128%3"; minutes=45; cpus=4; memory=24G ;;
  full)
    : "${ZERO_PRESSURE_ALLOCATION_APPROVED:?Set only after user approves the estimated full allocation}"
    [[ "$ZERO_PRESSURE_ALLOCATION_APPROVED" == "$audit_root" ]] || exit 2
    concurrency="${ZERO_PRESSURE_CONCURRENCY:-4}"
    [[ "$concurrency" =~ ^[1-4]$ ]] || { echo "Concurrency must be 1–4" >&2; exit 2; }
    members="1-128%$concurrency"
    : "${ZERO_PRESSURE_MINUTES:?Set the wall time from the approved allocation}"
    minutes="$ZERO_PRESSURE_MINUTES"; cpus="${ZERO_PRESSURE_CPUS:-2}"; memory="${ZERO_PRESSURE_MEMORY:-8G}"
    [[ "$cpus" =~ ^[1-4]$ ]] || exit 2
    [[ "$minutes" =~ ^[0-9]+$ ]] && (( minutes>=1 && minutes<=1440 )) || exit 2 ;;
  *) exit 2 ;;
esac
audit_logs="logs/zero_pressure_2026-09-09/$(basename "$audit_root")"
mkdir -p "$audit_logs"
audit_job=$(sbatch --parsable --job-name="zero_pressure_${mode}" --account=gts-fherrmann9 --qos=inferno \
  --export=ALL,ZERO_PRESSURE_DAYS=960,ZERO_PRESSURE_SOLVER_PROFILE=production \
  --nodes=1 --ntasks=1 --cpus-per-task="$cpus" --mem="$memory" --time="$minutes" \
  --array="$members" --open-mode=append --output="$audit_logs/%A_%a.out" --error="$audit_logs/%A_%a.err" \
  scripts/shell/run/run_zero_injection_pressure.sh "$audit_root")
python3 - "$audit_root" "${audit_job%%;*}" "$mode" "$members" "$minutes" "$cpus" "$memory" <<'PY'
import json,sys
from pathlib import Path
root,job,mode,members,minutes,cpus,memory=sys.argv[1:]
p=Path(root)/'submissions'; p.mkdir(exist_ok=True)
with (p/(job+'.json')).open('x') as f:
    json.dump(dict(job_id=int(job),mode=mode,array=members,wall_minutes_per_member=int(minutes),
                   cpus_per_member=int(cpus),memory_per_member=memory),f,indent=2)
print(job)
PY
