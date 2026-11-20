#!/bin/bash
#SBATCH --job-name=phas-alerts
#SBATCH --array=1-84
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=00:10:00
#SBATCH --output=logs/alerts_%A_%a.out
##SBATCH --partition=<partition>   # remove one "#" to pick a partition

# One task per county x pathogen (21 counties x 4 pathogens = 84 tasks).
# Run from the project folder. The logs/ folder must exist (submit.sh makes it).

set -euo pipefail

# Use the same R version as your Workbench session, for example:
#   export R_BIN=/opt/R/4.4.1/bin/Rscript
R_BIN="${R_BIN:-Rscript}"

"$R_BIN" slurm/detect_one.R
