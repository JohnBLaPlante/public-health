# generate_phas_demo_data.R
#
# Makes a SYNTHETIC zoonoses and antibiotic-resistance surveillance dataset
# for the Public Health Agency of Sweden (PHAS) demo. No real people, cases,
# or lab results are in this data.
#
# Hidden story for the demo:
#   1. Salmonella Enteritidis outbreak in Halland, Skåne and Kronoberg,
#      weeks starting 2026-08-24, 2026-08-31 and 2026-09-07.
#      All outbreak isolates share cgMLST cluster "CT-2026-017" and are
#      resistant to tetracycline only.
#   2. Ciprofloxacin resistance in domestic Campylobacter rises from about
#      25 % (2023) to about 45 % (2026).
#
# Output (in PHAS_DATA_DIR, default "data/"):
#   counties.csv        21 Swedish counties (län), population, lab
#   cases.csv           case line list            -> load into PostgreSQL
#   isolates.*          lab isolates              -> S3 bucket (Parquet)
#   ast_results.*       S/I/R test results        -> S3 bucket (Parquet)
#   amr_genes.*         resistance genes          -> S3 bucket (Parquet)
#   weekly_counts.*     "gold" weekly counts      -> S3 bucket (Parquet)
#   weekly_counts.ndjson                          -> MongoDB (mongoimport)
#   outbreak_truth.csv  presenter answer key (do not show)
#
# Parquet files are written only if the arrow package is installed.
# CSV files are always written.
#
# Optional: set PG_HOST, PG_DB, PG_USER, PG_PASSWORD (and PG_PORT) to load
# cases and counties into PostgreSQL.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

set.seed(20261123)

out_dir <- Sys.getenv("PHAS_DATA_DIR", "data")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# 1. Reference data
# ---------------------------------------------------------------------------

# Population figures are approximate (rounded) and only used for scaling.
counties <- tibble::tribble(
  ~county_code, ~county_name,       ~population, ~lab,
  "01",         "Stockholm",        2450000,     "Lab Stockholm",
  "03",         "Uppsala",           400000,     "Lab Uppsala",
  "04",         "Södermanland",      300000,     "Lab Stockholm",
  "05",         "Östergötland",      470000,     "Lab Linköping",
  "06",         "Jönköping",         370000,     "Lab Jönköping",
  "07",         "Kronoberg",         205000,     "Lab Jönköping",
  "08",         "Kalmar",            247000,     "Lab Linköping",
  "09",         "Gotland",            61000,     "Lab Stockholm",
  "10",         "Blekinge",          157000,     "Lab Malmö",
  "12",         "Skåne",            1420000,     "Lab Malmö",
  "13",         "Halland",           340000,     "Lab Göteborg",
  "14",         "Västra Götaland",  1770000,     "Lab Göteborg",
  "17",         "Värmland",          284000,     "Lab Örebro",
  "18",         "Örebro",            307000,     "Lab Örebro",
  "19",         "Västmanland",       280000,     "Lab Uppsala",
  "20",         "Dalarna",           288000,     "Lab Uppsala",
  "21",         "Gävleborg",         288000,     "Lab Uppsala",
  "22",         "Västernorrland",    243000,     "Lab Umeå",
  "23",         "Jämtland",          132000,     "Lab Umeå",
  "24",         "Västerbotten",      275000,     "Lab Umeå",
  "25",         "Norrbotten",        249000,     "Lab Umeå"
)
total_pop <- sum(counties$population)

pathogens <- tibble::tribble(
  ~pathogen,       ~annual_cases, ~season_amp, ~travel_prop, ~hosp_prop, ~isolate_prop, ~seq_prop,
  "Campylobacter", 4000,          0.60,        0.35,         0.10,       0.70,          0.60,
  "Salmonella",    1500,          0.50,        0.50,         0.20,       0.90,          1.00,
  "EHEC",           800,          0.50,        0.20,         0.15,       0.85,          1.00,
  "Listeria",       100,          0.20,        0.05,         0.90,       0.95,          1.00
)

age_groups <- c("0-4", "5-14", "15-24", "25-44", "45-64", "65-79", "80+")
age_probs <- list(
  Campylobacter = c(0.05, 0.07, 0.15, 0.30, 0.25, 0.13, 0.05),
  Salmonella    = c(0.10, 0.10, 0.13, 0.27, 0.23, 0.12, 0.05),
  EHEC          = c(0.25, 0.15, 0.10, 0.20, 0.15, 0.10, 0.05),
  Listeria      = c(0.03, 0.01, 0.02, 0.07, 0.17, 0.40, 0.30),
  Outbreak      = c(0.04, 0.06, 0.15, 0.35, 0.25, 0.10, 0.05)
)

# Antibiotic panels and base resistance rates (domestic cases).
ast_panel <- tibble::tribble(
  ~pathogen,       ~antibiotic,                     ~base_r, ~gene,
  "Campylobacter", "ciprofloxacin",                 NA,      "gyrA_T86I",
  "Campylobacter", "erythromycin",                  0.02,    "23S_A2075G",
  "Campylobacter", "tetracycline",                  0.20,    "tet(O)",
  "Campylobacter", "gentamicin",                    0.01,    "aac(6')-Ie-aph(2'')-Ia",
  "Salmonella",    "ampicillin",                    0.12,    "blaTEM-1",
  "Salmonella",    "ciprofloxacin",                 0.10,    "gyrA_D87N",
  "Salmonella",    "cefotaxime",                    0.02,    "blaCTX-M-15",
  "Salmonella",    "meropenem",                     0.002,   "blaOXA-48",
  "Salmonella",    "tetracycline",                  0.15,    "tet(A)",
  "Salmonella",    "trimethoprim-sulfamethoxazole", 0.06,    "sul2",
  "EHEC",          "ampicillin",                    0.10,    "blaTEM-1",
  "EHEC",          "ciprofloxacin",                 0.04,    "gyrA_S83L",
  "EHEC",          "cefotaxime",                    0.03,    "blaCTX-M-15",
  "EHEC",          "tetracycline",                  0.12,    "tet(A)",
  "Listeria",      "ampicillin",                    0.002,   NA,
  "Listeria",      "meropenem",                     0.002,   NA,
  "Listeria",      "trimethoprim-sulfamethoxazole", 0.01,    "dfrD"
)

# ---------------------------------------------------------------------------
# 2. Weekly expected counts per county x pathogen
# ---------------------------------------------------------------------------

weeks <- seq(as.Date("2023-01-02"), as.Date("2026-11-09"), by = "week")
period_start <- min(weeks)
period_len   <- as.numeric(max(weeks) + 6 - period_start)

grid <- expand_grid(week_start = weeks, county_code = counties$county_code,
                    pathogen = pathogens$pathogen) |>
  left_join(counties, by = "county_code") |>
  left_join(pathogens, by = "pathogen") |>
  mutate(
    doy    = as.numeric(format(week_start, "%j")),
    season = 1 + season_amp * cos(2 * pi * (doy - 205) / 365.25),
    lambda = annual_cases * population / total_pop / 52.18 * season *
             exp(rnorm(n(), 0, 0.15)),
    n      = rpois(n(), lambda),
    outbreak = FALSE
  )

# Planted outbreak: Salmonella Enteritidis, 3 counties, 3 weeks.
outbreak_def <- expand_grid(
  week_start  = as.Date(c("2026-08-24", "2026-08-31", "2026-09-07")),
  county_code = c("13", "12", "07")
) |>
  mutate(
    week_mult   = rep(c(0.6, 1.0, 0.5), each = 3),
    county_mult = rep(c(1.0, 0.7, 0.4), times = 3),
    n           = rpois(n(), 22 * week_mult * county_mult),
    pathogen    = "Salmonella",
    outbreak    = TRUE
  ) |>
  left_join(counties, by = "county_code") |>
  left_join(pathogens, by = "pathogen")

grid <- bind_rows(grid, outbreak_def)

# ---------------------------------------------------------------------------
# 3. Case line list
# ---------------------------------------------------------------------------

cases <- grid[rep(seq_len(nrow(grid)), grid$n), ] |>
  mutate(
    case_id     = sprintf("C%06d", row_number()),
    sample_date = week_start + sample(0:6, n(), replace = TRUE),
    report_date = sample_date + 1 + rpois(n(), 2),
    sex         = sample(c("F", "M"), n(), replace = TRUE),
    travel_associated = if_else(outbreak, FALSE, rbinom(n(), 1, travel_prop) == 1),
    hospitalised      = rbinom(n(), 1, hosp_prop) == 1
  ) |>
  group_by(age_key = if_else(outbreak, "Outbreak", pathogen)) |>
  mutate(age_group = sample(age_groups, n(), replace = TRUE,
                            prob = age_probs[[first(age_key)]])) |>
  ungroup() |>
  mutate(iso_week = format(week_start, "%G-W%V"))

# ---------------------------------------------------------------------------
# 4. Isolates (lab results linked to cases)
# ---------------------------------------------------------------------------

salm_types <- c("Enteritidis", "Typhimurium", "monophasic Typhimurium", "Other")
isolates <- cases |>
  filter(rbinom(n(), 1, isolate_prop) == 1) |>
  mutate(
    isolate_id    = sprintf("I%06d", row_number()),
    received_date = sample_date + sample(1:3, n(), replace = TRUE),
    sequenced     = outbreak | rbinom(n(), 1, seq_prop) == 1,
    subtype = case_when(
      outbreak                    ~ "Enteritidis",
      pathogen == "Campylobacter" ~ sample(c("C. jejuni", "C. coli"), n(), TRUE, c(0.9, 0.1)),
      pathogen == "Salmonella"    ~ sample(salm_types, n(), TRUE, c(0.35, 0.25, 0.15, 0.25)),
      pathogen == "EHEC"          ~ sample(c("O157:H7", "O26:H11", "O103:H2", "Other"), n(), TRUE, c(0.4, 0.25, 0.15, 0.2)),
      pathogen == "Listeria"      ~ sample(c("IVb", "IIa", "IIb"), n(), TRUE, c(0.4, 0.45, 0.15))
    ),
    cgmlst_cluster = case_when(
      !sequenced ~ NA_character_,
      outbreak   ~ "CT-2026-017",
      TRUE       ~ sprintf("CT-%s-%03d", format(sample_date, "%Y"), sample(100:999, n(), TRUE))
    ),
    t_frac = as.numeric(sample_date - period_start) / period_len
  )

# ---------------------------------------------------------------------------
# 5. Antibiotic susceptibility testing (AST) results
# ---------------------------------------------------------------------------

ast <- isolates |>
  select(isolate_id, pathogen, outbreak, travel_associated, t_frac, sequenced) |>
  inner_join(ast_panel, by = "pathogen", relationship = "many-to-many") |>
  mutate(
    p_r = case_when(
      outbreak & antibiotic == "tetracycline"                    ~ 1,
      outbreak                                                   ~ 0,
      pathogen == "Campylobacter" & antibiotic == "ciprofloxacin" & travel_associated ~ 0.65,
      pathogen == "Campylobacter" & antibiotic == "ciprofloxacin" ~ 0.25 + 0.20 * t_frac,
      travel_associated ~ pmin(base_r * 2.5, 0.9),
      TRUE              ~ base_r
    ),
    resistant = runif(n()) < p_r,
    # A few "I" (susceptible, increased exposure) results for realism.
    result = case_when(
      resistant          ~ "R",
      runif(n()) < 0.02  ~ "I",
      TRUE               ~ "S"
    )
  )

ast_results <- ast |>
  select(isolate_id, antibiotic, result)

amr_genes <- ast |>
  filter(resistant, sequenced, !is.na(gene)) |>
  transmute(isolate_id, gene, antibiotic)

# ---------------------------------------------------------------------------
# 6. Gold layer: weekly counts per county x pathogen (with zeros)
# ---------------------------------------------------------------------------

weekly_counts <- cases |>
  count(week_start, county_code, pathogen, name = "cases") |>
  complete(week_start = weeks, county_code = counties$county_code,
           pathogen = pathogens$pathogen, fill = list(cases = 0L)) |>
  left_join(counties |> select(county_code, county_name, population), by = "county_code") |>
  mutate(
    iso_week = format(week_start, "%G-W%V"),
    incidence_per_100k = round(cases / population * 1e5, 2)
  ) |>
  arrange(week_start, county_code, pathogen)

# ---------------------------------------------------------------------------
# 7. Write files
# ---------------------------------------------------------------------------

cases_out <- cases |>
  select(case_id, pathogen, sample_date, report_date, iso_week, county_code,
         county_name, age_group, sex, travel_associated, hospitalised)

isolates_out <- isolates |>
  select(isolate_id, case_id, pathogen, subtype, lab, received_date,
         sequenced, cgmlst_cluster)

outbreak_truth <- cases |>
  filter(outbreak) |>
  select(case_id, sample_date, county_name) |>
  left_join(isolates |> select(case_id, isolate_id), by = "case_id")

write_both <- function(df, name) {
  utils::write.csv(df, file.path(out_dir, paste0(name, ".csv")), row.names = FALSE,
                   fileEncoding = "UTF-8")
  if (requireNamespace("arrow", quietly = TRUE)) {
    arrow::write_parquet(df, file.path(out_dir, paste0(name, ".parquet")))
  }
}

utils::write.csv(counties, file.path(out_dir, "counties.csv"), row.names = FALSE, fileEncoding = "UTF-8")
utils::write.csv(cases_out, file.path(out_dir, "cases.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write_both(isolates_out, "isolates")
write_both(ast_results, "ast_results")
write_both(amr_genes, "amr_genes")
write_both(weekly_counts, "weekly_counts")
utils::write.csv(outbreak_truth, file.path(out_dir, "outbreak_truth.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# NDJSON for mongoimport (one document per line).
con <- file(file.path(out_dir, "weekly_counts.ndjson"), open = "w", encoding = "UTF-8")
jsonlite::stream_out(weekly_counts |> mutate(week_start = as.character(week_start)),
                     con, verbose = FALSE)
close(con)

# Optional: load the case line list into PostgreSQL.
if (nzchar(Sys.getenv("PG_HOST"))) {
  pg <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("PG_HOST"), port = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname = Sys.getenv("PG_DB"), user = Sys.getenv("PG_USER"),
    password = Sys.getenv("PG_PASSWORD")
  )
  DBI::dbWriteTable(pg, "counties", counties, overwrite = TRUE)
  DBI::dbWriteTable(pg, "cases", cases_out, overwrite = TRUE)
  DBI::dbDisconnect(pg)
  message("Loaded cases and counties into PostgreSQL.")
}

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------

message("Output folder: ", normalizePath(out_dir))
message("Cases: ", nrow(cases_out), " | Isolates: ", nrow(isolates_out),
        " | AST results: ", nrow(ast_results), " | AMR genes: ", nrow(amr_genes),
        " | Weekly rows: ", nrow(weekly_counts))
message("Outbreak cases planted: ", nrow(outbreak_truth))
print(cases_out |> count(pathogen))
cipro <- ast |>
  filter(pathogen == "Campylobacter", antibiotic == "ciprofloxacin", !travel_associated) |>
  left_join(isolates |> select(isolate_id, sample_date), by = "isolate_id") |>
  group_by(year = format(sample_date, "%Y")) |>
  summarise(pct_R = round(100 * mean(resistant), 1), .groups = "drop")
message("Domestic Campylobacter ciprofloxacin resistance (%) by year:")
print(cipro)
