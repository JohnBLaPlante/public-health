# combine_alerts.R
#
# Runs after all array tasks finish. Merges results/alerts/task_*.parquet
# into data/alerts_2026.parquet and prints a short summary.

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
})

data_dir    <- Sys.getenv("PHAS_DATA_DIR", "data")
results_dir <- Sys.getenv("PHAS_RESULTS_DIR", "results/alerts")
expected    <- 84

files <- list.files(results_dir, pattern = "^task_\\d+\\.parquet$", full.names = TRUE)
if (length(files) < expected) {
  warning(sprintf("Found %d result files, expected %d.", length(files), expected))
}

alerts <- bind_rows(lapply(files, read_parquet))
write_parquet(alerts, file.path(data_dir, "alerts_2026.parquet"))

failed <- alerts |> filter(status != "ok")

cat("\n=== PHAS alert run summary ===\n")
cat(sprintf("Tasks: %d | Series OK: %d | Series failed: %d\n",
            length(files), n_distinct(alerts$task_id[alerts$status == "ok"]),
            n_distinct(failed$task_id)))
cat(sprintf("Compute nodes used: %d (%s)\n",
            n_distinct(alerts$node), paste(sort(unique(alerts$node)), collapse = ", ")))
cat(sprintf("Total model time: %.1f s (sum across tasks)\n",
            sum(distinct(alerts, task_id, runtime_sec)$runtime_sec)))

cat("\nAlerts per pathogen:\n")
alerts |>
  filter(status == "ok") |>
  group_by(pathogen) |>
  summarise(weeks_checked = n(), alerts = sum(alarm, na.rm = TRUE), .groups = "drop") |>
  as.data.frame() |>
  print(row.names = FALSE)

cat("\nStrongest alerts (cases / threshold):\n")
alerts |>
  filter(status == "ok", alarm) |>
  mutate(ratio = round(observed / threshold, 1)) |>
  arrange(desc(ratio)) |>
  select(iso_week, pathogen, county_name, observed, threshold, ratio) |>
  head(10) |>
  as.data.frame() |>
  print(row.names = FALSE)

if (nrow(failed) > 0) {
  cat("\nFailed series:\n")
  print(as.data.frame(distinct(failed, task_id, pathogen, county_name, status)), row.names = FALSE)
}

cat(sprintf("\nWrote %s\n", file.path(data_dir, "alerts_2026.parquet")))
