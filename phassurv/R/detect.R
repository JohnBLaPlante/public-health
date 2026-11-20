#' Detect outbreaks in weekly counts
#'
#' Runs [surveillance::farringtonFlexible()] on each county x pathogen series
#' in `weekly`. Each week is compared with the same weeks in the previous
#' `b` years.
#'
#' @param weekly A data frame with columns `week_start` (Date), `county_name`,
#'   `pathogen` and `cases`. One row per week, county and pathogen, with zero
#'   counts included (for example from `read_phas("weekly_counts")`).
#' @param pathogen Optional pathogen names to keep.
#' @param county Optional county names to keep.
#' @param weeks Optional `Date` vector of week starts to check. Default: every
#'   week with enough history.
#' @param b Number of earlier years used as the baseline.
#' @param w Number of weeks either side of the same week in earlier years.
#' @param alpha Significance level for the alert threshold.
#' @return A tibble with one row per checked week and series: `week_start`,
#'   `iso_week`, `pathogen`, `county_name`, `observed`, `threshold`, `alarm`
#'   and `status` (`"ok"` or an error message).
#' @export
detect_outbreaks <- function(weekly, pathogen = NULL, county = NULL,
                             weeks = NULL, b = 3, w = 3, alpha = 0.01) {
  needed <- c("week_start", "county_name", "pathogen", "cases")
  if (!all(needed %in% names(weekly))) {
    stop("`weekly` needs the columns: ", paste(needed, collapse = ", "),
         call. = FALSE)
  }
  if (!is.null(pathogen)) weekly <- weekly[weekly$pathogen %in% pathogen, ]
  if (!is.null(county))   weekly <- weekly[weekly$county_name %in% county, ]
  if (nrow(weekly) == 0) {
    stop("No rows left after filtering by pathogen and county.", call. = FALSE)
  }

  series <- unique(weekly[, c("pathogen", "county_name")])
  results <- lapply(seq_len(nrow(series)), function(i) {
    one <- weekly[weekly$pathogen == series$pathogen[i] &
                    weekly$county_name == series$county_name[i], ]
    detect_series(one, weeks = weeks, b = b, w = w, alpha = alpha)
  })
  dplyr::bind_rows(results)
}

# One county x pathogen series. Not exported.
detect_series <- function(one, weeks, b, w, alpha) {
  one <- one[order(one$week_start), ]
  n <- nrow(one)
  first <- 52 * b + w + 1

  base <- tibble::tibble(
    pathogen = one$pathogen[1],
    county_name = one$county_name[1]
  )

  fail <- function(msg) {
    dplyr::bind_cols(
      tibble::tibble(week_start = as.Date(NA), iso_week = NA_character_),
      base,
      tibble::tibble(observed = NA_real_, threshold = NA_real_,
                     alarm = NA, status = paste("error:", msg))
    )
  }

  if (n < first) {
    return(fail(sprintf("needs at least %d weeks of data, has %d", first, n)))
  }

  range <- first:n
  if (!is.null(weeks)) {
    range <- intersect(range, which(one$week_start %in% as.Date(weeks)))
    if (length(range) == 0) {
      return(fail("none of `weeks` has enough history"))
    }
  }

  x <- surveillance::sts(
    observed    = matrix(one$cases, ncol = 1),
    epoch       = as.numeric(one$week_start),
    epochAsDate = TRUE,
    frequency   = 52
  )

  res <- tryCatch(
    surveillance::farringtonFlexible(x, control = list(
      range = range, b = b, w = w, alpha = alpha,
      noPeriods = 10, populationOffset = FALSE
    )),
    error = function(e) e
  )
  if (inherits(res, "error")) {
    return(fail(conditionMessage(res)))
  }

  wk <- as.Date(surveillance::epoch(res))
  dplyr::bind_cols(
    tibble::tibble(week_start = wk, iso_week = iso_week(wk)),
    base[rep(1, length(wk)), ],
    tibble::tibble(
      observed  = as.vector(surveillance::observed(res)),
      threshold = round(as.vector(surveillance::upperbound(res)), 2),
      alarm     = as.vector(surveillance::alarms(res)),
      status    = "ok"
    )
  )
}
