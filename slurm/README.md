# Slurm Alert Job

This job runs outbreak detection (`surveillance::farringtonFlexible()`) for each county × pathogen series as a Slurm array: 21 counties × 4 pathogens = 84 tasks. Each task checks all 2026 weeks. A combine job merges the results into `data/alerts_2026.parquet`.

## Files

| File | Purpose |
|---|---|
| `detect_one.R` | Runs one county × pathogen series. Slurm gives the task number in `SLURM_ARRAY_TASK_ID`. |
| `run_alerts.sbatch` | Array job definition: 84 tasks, 1 CPU, 2 GB, 10 min each. |
| `combine_alerts.R` | Merges the 84 result files and prints a summary. |
| `submit.sh` | Submits the array, then the combine job with `--dependency=afterok`. |

## Before you start

- Copy the `slurm/` folder into the project folder, next to `data/`.
- The project folder must be on a file system that the compute nodes can read (for example, the shared home directory).
- The compute nodes must have R and the packages `dplyr`, `arrow` and `surveillance`. Packages in your user library on the shared home directory are available to the nodes.
- If `Rscript` on the nodes is not the same R version as your Workbench session, set `R_BIN`. Example: `export R_BIN=/opt/R/4.4.1/bin/Rscript`.
- If your cluster needs a partition, edit the `--partition` line in `run_alerts.sbatch`.

## Procedure

1. Open the Terminal in Workbench, in the project folder.
2. Test one task on the session node:

   ```bash
   SLURM_ARRAY_TASK_ID=70 Rscript slurm/detect_one.R
   ```

3. Submit the full job:

   ```bash
   bash slurm/submit.sh
   ```

4. Watch the tasks:

   ```bash
   squeue -u $USER
   ```

5. When the combine job is done, read the summary in `logs/combine_<job id>.out`.

## Without a Slurm cluster

`run_local.sh` runs the same 84 tasks in parallel on the current machine (for example, a Workbench session). It uses the same scripts and makes the same `data/alerts_2026.parquet`.

1. Open a Terminal in the project folder (in Positron: **Terminal > New Terminal**).
2. Run the script:

   ```bash
   bash slurm/run_local.sh
   ```

   To limit the number of parallel tasks, add a number. Example: `bash slurm/run_local.sh 4`.
3. Read the summary at the end of the output.

## Expected result

All 84 series finish with status "ok". The strongest alerts are Salmonella in Halland and Kronoberg in weeks 2026-W35 and 2026-W36. There are some single-week alerts for other pathogens and counties, which is normal at alpha = 0.01.
