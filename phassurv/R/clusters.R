#' Find recent genomic clusters
#'
#' Finds cgMLST clusters with at least `min_size` isolates of the same
#' pathogen, sampled in the `window_days` days up to the end of `week`.
#'
#' @param isolates A data frame with `isolate_id`, `case_id`, `pathogen`,
#'   `subtype` and `cgmlst_cluster`.
#' @param cases A data frame with `case_id`, `sample_date` and `county_name`.
#' @param week Report week (any date in the week).
#' @param pathogen Optional pathogen names to keep.
#' @param min_size Smallest cluster size to report.
#' @param window_days Length of the look-back window in days.
#' @param ast Optional antibiotic test results with `isolate_id`,
#'   `antibiotic` and `result`. If given, the output has a `resistant_to`
#'   column with the antibiotics that at least half of the cluster resists.
#' @return A tibble with one row per cluster, largest first.
#' @export
find_clusters <- function(isolates, cases, week, pathogen = NULL,
                          min_size = 5, window_days = 42, ast = NULL) {
  week_end <- week_monday(week) + 6
  iso <- isolates[!is.na(isolates$cgmlst_cluster), ]
  if (!is.null(pathogen)) iso <- iso[iso$pathogen %in% pathogen, ]

  recent <- iso |>
    dplyr::inner_join(
      cases[, c("case_id", "sample_date", "county_name")], by = "case_id"
    ) |>
    dplyr::filter(.data$sample_date > week_end - window_days,
                  .data$sample_date <= week_end) |>
    dplyr::group_by(.data$cgmlst_cluster, .data$pathogen) |>
    dplyr::filter(dplyr::n() >= min_size) |>
    dplyr::ungroup()

  if (nrow(recent) == 0) {
    return(tibble::tibble(
      cgmlst_cluster = character(), pathogen = character(),
      subtype = character(), isolates = integer(), counties = character(),
      first_sample = as.Date(character()), last_sample = as.Date(character())
    ))
  }

  out <- recent |>
    dplyr::group_by(.data$cgmlst_cluster, .data$pathogen) |>
    dplyr::summarise(
      subtype      = paste(unique(.data$subtype), collapse = ", "),
      isolates     = dplyr::n(),
      counties     = paste(sort(unique(.data$county_name)), collapse = ", "),
      first_sample = min(.data$sample_date),
      last_sample  = max(.data$sample_date),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(.data$isolates))

  if (!is.null(ast)) {
    profile <- ast |>
      dplyr::inner_join(recent[, c("isolate_id", "cgmlst_cluster")], by = "isolate_id") |>
      dplyr::group_by(.data$cgmlst_cluster, .data$antibiotic) |>
      dplyr::summarise(pct_r = mean(.data$result == "R"), .groups = "drop") |>
      dplyr::filter(.data$pct_r >= 0.5) |>
      dplyr::group_by(.data$cgmlst_cluster) |>
      dplyr::summarise(resistant_to = paste(sort(.data$antibiotic), collapse = ", "),
                       .groups = "drop")
    out <- out |>
      dplyr::left_join(profile, by = "cgmlst_cluster") |>
      dplyr::mutate(resistant_to = dplyr::coalesce(.data$resistant_to, "none"))
  }

  out
}
