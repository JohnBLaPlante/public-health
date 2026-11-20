#' Agency colours
#'
#' A named character vector of the colours used in reports and dashboards.
#'
#' @export
#' @examples
#' phas_colours["alert"]
phas_colours <- c(
  primary  = "#1F5A96",
  light    = "#9BB7D4",
  alert    = "#C0392B",
  accent   = "#E07A1F",
  highlight = "#F4D35E"
)

#' ggplot2 theme for surveillance plots
#'
#' @param base_size Base font size.
#' @return A ggplot2 theme.
#' @export
#' @examples
#' library(ggplot2)
#' ggplot(mtcars, aes(wt, mpg)) + geom_point() + theme_phas()
theme_phas <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.title       = ggplot2::element_text(face = "bold", colour = phas_colours[["primary"]]),
      legend.position  = "top",
      panel.grid.minor = ggplot2::element_blank(),
      strip.text       = ggplot2::element_text(face = "bold")
    )
}

#' Fill scale for alert / normal bars
#'
#' Use with a logical `alarm` column mapped to `fill`.
#'
#' @param ... Passed to [ggplot2::scale_fill_manual()].
#' @return A ggplot2 scale.
#' @export
scale_fill_alert <- function(...) {
  ggplot2::scale_fill_manual(
    values = c(`FALSE` = phas_colours[["light"]], `TRUE` = phas_colours[["alert"]]),
    labels = c(`FALSE` = "Normal", `TRUE` = "Alert"),
    name = NULL, drop = FALSE, ...
  )
}
