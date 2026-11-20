# detect_one.R
#
# One Slurm array task = one county x pathogen series.
# Runs surveillance::farringtonFlexible() for every week where 3 years of
# history are available, and writes the result to results/alerts/.
#
# Slurm sets SLURM_ARRAY_TASK_ID (1-84). Run by hand for one task with:
#   SLURM_ARRAY_TASK_ID=5 Rscript slurm/detect_one.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(surveillance)
})

task_id  <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID", "1"))
data_dir <- Sys.getenv("PHAS_DATA_DIR", "data")
out_dir  <- Sys.getenv("PHAS_RESULTS_DIR", "results/alerts")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

node <- Sys.info()[["nodename"]]

weekly <- read_parquet(file.path(data_dir, "weekly_counts.parquet")) |>
  mutate(week_start = as.Date(week_start))

# Task list: same order every time, so task 1-84 always maps the same way.
tasks <- weekly |>
  distinct(pathogen, county_name) |>
  arrange(pathogen, county_name)

if (task_id < 1 || task_id > nrow(tasks)) {
  stop("SLURM_ARRAY_TASK_ID must be between 1 and ", nrow(tasks))
}
this <- tasks[task_id, ]

message(sprintf("[%s] task %d of %d: %s / %s on node %s",
                format(Sys.time(), "%H:%M:%S"), task_id, nrow(tasks),
                this$pathogen, this$county_name, node))

series <- weekly |>
  filter(pathogen == this$pathogen, county_name == this$county_name) |>
  arrange(week_start)

b <- 3   # years of history
w <- 3   # weeks either side of the same week in earlier years
n <- nrow(series)
first <- 52 * b + w + 1

ts_sts <- sts(
  observed    = matrix(series$cases, ncol = 1, dimnames = list(NULL, this$county_name)),
  epoch       = as.numeric(series$week_start),
  epochAsDate = TRUE,
  frequency   = 52
)

t0 <- Sys.time()
res <- tryCatch(
  farringtonFlexible(ts_sts, control = list(
    range = first:n, b = b, w = w, alpha = 0.01,
    noPeriods = 10, populationOffset = FALSE
  )),
  error = function(e) e
)
runtime <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)

if (inherits(res, "error")) {
  out <- tibble(
    week_start = as.Date(NA), iso_week = NA_character_,
    pathogen = this$pathogen, county_name = this$county_name,
    observed = NA_real_, threshold = NA_real_, alarm = NA,
    status = paste("error:", conditionMessage(res)),
    task_id = task_id, node = node, runtime_sec = runtime
  )
  message("Model failed: ", conditionMessage(res))
} else {
  wk <- as.Date(epoch(res))
  out <- tibble(
    week_start  = wk,
    iso_week    = format(wk, "%G-W%V"),
    pathogen    = this$pathogen,
    county_name = this$county_name,
    observed    = as.vector(observed(res)),
    threshold   = round(as.vector(upperbound(res)), 2),
    alarm       = as.vector(alarms(res)),
    status      = "ok",
    task_id     = task_id,
    node        = node,
    runtime_sec = runtime
  )
  message(sprintf("Done: %d weeks checked, %d alerts, %.2f s",
                  nrow(out), sum(out$alarm, na.rm = TRUE), runtime))
}

write_parquet(out, file.path(out_dir, sprintf("task_%03d.parquet", task_id)))
