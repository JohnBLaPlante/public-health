# Small synthetic series: 4 years of weekly counts, spike in the last 2 weeks.
make_weekly <- function(spike = 25) {
  set.seed(1)
  weeks <- seq(as.Date("2023-01-02"), by = "week", length.out = 200)
  cases <- rpois(length(weeks), 3)
  cases[199:200] <- spike
  tibble::tibble(week_start = weeks, county_name = "Testlän",
                 pathogen = "Salmonella", cases = cases)
}

test_that("week_monday returns the Monday of the week", {
  expect_equal(week_monday("2026-09-10"), as.Date("2026-09-07"))
  expect_equal(week_monday("2026-09-07"), as.Date("2026-09-07"))
  expect_equal(week_monday("2026-09-13"), as.Date("2026-09-07"))
})

test_that("iso_week formats ISO weeks", {
  expect_equal(iso_week("2026-09-07"), "2026-W37")
  expect_equal(iso_week("2027-01-01"), "2026-W53")
})

test_that("detect_outbreaks flags a clear spike", {
  res <- detect_outbreaks(make_weekly())
  expect_true(all(res$status == "ok"))
  expect_true(all(res$alarm[res$week_start %in% tail(make_weekly()$week_start, 2)]))
  expect_named(res, c("week_start", "iso_week", "pathogen", "county_name",
                      "observed", "threshold", "alarm", "status"))
})

test_that("detect_outbreaks can check selected weeks only", {
  wk <- tail(make_weekly()$week_start, 1)
  res <- detect_outbreaks(make_weekly(), weeks = wk)
  expect_equal(nrow(res), 1)
  expect_equal(res$week_start, wk)
})

test_that("detect_outbreaks reports short series instead of failing", {
  short <- head(make_weekly(), 50)
  res <- detect_outbreaks(short)
  expect_match(res$status, "needs at least")
})

test_that("detect_outbreaks checks its input", {
  expect_error(detect_outbreaks(data.frame(x = 1)), "needs the columns")
  expect_error(detect_outbreaks(make_weekly(), pathogen = "None"), "No rows left")
})

test_that("find_clusters finds a recent cluster and its resistance", {
  cases <- tibble::tibble(
    case_id = sprintf("C%02d", 1:8),
    sample_date = as.Date("2026-09-01") + 0:7,
    county_name = rep(c("Halland", "Skåne"), 4)
  )
  isolates <- tibble::tibble(
    isolate_id = sprintf("I%02d", 1:8), case_id = cases$case_id,
    pathogen = "Salmonella", subtype = "Enteritidis",
    cgmlst_cluster = c(rep("CT-1", 6), "CT-2", NA)
  )
  ast <- tibble::tibble(
    isolate_id = rep(isolates$isolate_id, each = 2),
    antibiotic = rep(c("tetracycline", "ampicillin"), 8),
    result = rep(c("R", "S"), 8)
  )
  res <- find_clusters(isolates, cases, week = "2026-09-07", ast = ast)
  expect_equal(nrow(res), 1)
  expect_equal(res$cgmlst_cluster, "CT-1")
  expect_equal(res$isolates, 6)
  expect_equal(res$counties, "Halland, Skåne")
  expect_equal(res$resistant_to, "tetracycline")

  none <- find_clusters(isolates, cases, week = "2026-09-07", min_size = 10)
  expect_equal(nrow(none), 0)
})

test_that("theme and scale build", {
  expect_s3_class(theme_phas(), "theme")
  expect_s3_class(scale_fill_alert(), "Scale")
})
