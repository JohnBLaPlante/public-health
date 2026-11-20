#!/bin/bash
# Submits the 84-task alert array, then a combine job that starts only
# when all 84 tasks succeed. Run from the project folder:
#   bash slurm/submit.sh

set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p logs results/alerts
rm -f results/alerts/task_*.parquet

R_BIN="${R_BIN:-Rscript}"
export R_BIN

array_id=$(sbatch --parsable --export=ALL slurm/run_alerts.sbatch)
echo "Submitted array job ${array_id} (84 tasks)"

combine_id=$(sbatch --parsable --export=ALL \
  --dependency=afterok:${array_id} \
  --job-name=phas-combine \
  --mem=2G --time=00:10:00 \
  --output=logs/combine_%j.out \
  --wrap="${R_BIN} slurm/combine_alerts.R")
echo "Submitted combine job ${combine_id} (starts after all 84 tasks succeed)"

echo
echo "Watch progress:  squeue -u \$USER"
echo "Summary:         cat logs/combine_${combine_id}.out"
