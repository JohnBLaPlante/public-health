#' Connect to the surveillance database
#'
#' Opens a PostgreSQL connection. The connection values come from the
#' environment variables `PG_HOST`, `PG_PORT` (default 5432), `PG_DB`,
#' `PG_USER` and `PG_PASSWORD`. Set them in `~/.Renviron` on Workbench, or
#' as environment variables on the content in Connect.
#'
#' @return A DBI connection. Close it with [DBI::dbDisconnect()].
#' @export
phas_connect <- function() {
  if (!requireNamespace("RPostgres", quietly = TRUE)) {
    stop("Package 'RPostgres' is required for phas_connect().", call. = FALSE)
  }
  missing <- c("PG_HOST", "PG_DB", "PG_USER")[
    !nzchar(Sys.getenv(c("PG_HOST", "PG_DB", "PG_USER")))
  ]
  if (length(missing) > 0) {
    stop("Set these environment variables: ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = Sys.getenv("PG_HOST"),
    port     = as.integer(Sys.getenv("PG_PORT", "5432")),
    dbname   = Sys.getenv("PG_DB"),
    user     = Sys.getenv("PG_USER"),
    password = Sys.getenv("PG_PASSWORD")
  )
}

#' Read the case line list
#'
#' @param con A DBI connection, for example from [phas_connect()].
#' @param to Optional last sample date to include.
#' @return A tibble with one row per case. `sample_date` and `report_date`
#'   are `Date` columns.
#' @export
read_cases <- function(con, to = NULL) {
  sql <- "SELECT * FROM cases"
  if (!is.null(to)) {
    sql <- paste0(sql, " WHERE sample_date <= ",
                  DBI::dbQuoteLiteral(con, as.Date(to)))
  }
  out <- tibble::as_tibble(DBI::dbGetQuery(con, sql))
  for (col in intersect(c("sample_date", "report_date"), names(out))) {
    out[[col]] <- as.Date(out[[col]])
  }
  out
}

#' Folder with the surveillance data files
#'
#' @return The value of the `PHAS_DATA_DIR` environment variable, or `"data"`.
#' @export
phas_data_dir <- function() {
  Sys.getenv("PHAS_DATA_DIR", "data")
}

#' Read a Parquet table from the data folder
#'
#' @param name Table name without extension, for example `"weekly_counts"`,
#'   `"isolates"`, `"ast_results"` or `"alerts_2026"`.
#' @param dir Data folder. Default: [phas_data_dir()].
#' @return A tibble. Columns named `week_start` or ending in `_date` are
#'   converted to `Date`.
#' @export
read_phas <- function(name, dir = phas_data_dir()) {
  path <- file.path(dir, paste0(name, ".parquet"))
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }
  out <- tibble::as_tibble(arrow::read_parquet(path))
  date_cols <- names(out)[names(out) == "week_start" | grepl("_date$", names(out))]
  for (col in date_cols) {
    out[[col]] <- as.Date(out[[col]])
  }
  out
}
