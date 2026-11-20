#' Monday of the week
#'
#' Returns the Monday (ISO week start) of the week that contains each date.
#'
#' @param x A `Date`, or something that [as.Date()] can convert.
#' @return A `Date` vector.
#' @export
#' @examples
#' week_monday("2026-09-10")  # 2026-09-07
week_monday <- function(x) {
  x <- as.Date(x)
  x - (as.POSIXlt(x)$wday + 6) %% 7
}

#' ISO week label
#'
#' @param x A `Date`, or something that [as.Date()] can convert.
#' @return A character vector such as `"2026-W37"`.
#' @export
#' @examples
#' iso_week("2026-09-07")
iso_week <- function(x) {
  format(as.Date(x), "%G-W%V")
}
