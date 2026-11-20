#!/bin/bash
# Runs the same 84 alert tasks WITHOUT Slurm, in parallel on this machine
# (for example, a Workbench session). Same scripts, same results.
#
# Run from the project folder:
#   bash slurm/run_local.sh          # uses all CPUs
#   bash slurm/run_local.sh 4        # uses 4 parallel tasks
#
# On a Slurm cluster, use slurm/submit.sh instead.

set -euo pipefail
cd "$(dirname "$0")/.."

TASKS=84
PARALLEL="${1:-$(getconf _NPROCESSORS_ONLN)}"
R_BIN="${R_BIN:-Rscript}"

mkdir -p logs results/alerts
rm -f results/alerts/task_*.parquet

echo "Running ${TASKS} tasks, ${PARALLEL} at a time (same as a Slurm array of ${TASKS})..."
start=$(date +%s)

# Each task gets its own SLURM_ARRAY_TASK_ID, exactly as Slurm would set it.
seq 1 "${TASKS}" | xargs -P "${PARALLEL}" -I{} sh -c \
  "SLURM_ARRAY_TASK_ID={} ${R_BIN} slurm/detect_one.R > logs/alerts_local_{}.out 2>&1 \
   && echo '  task {} done' || echo '  task {} FAILED (see logs/alerts_local_{}.out)'"

echo "All tasks finished in $(( $(date +%s) - start )) s. Combining results..."
"${R_BIN}" slurm/combine_alerts.R
