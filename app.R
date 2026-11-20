# PHAS Zoonoses Surveillance Dashboard (synthetic demo data)
#
# Data:
#   data/weekly_counts.parquet  weekly counts per county x pathogen
#   data/alerts_2026.parquet    Farrington alerts from the Slurm array job
#   data/isolates.parquet       lab isolates with cgMLST cluster
#   PostgreSQL table "cases"    case line list (connection from PG_* env vars)

library(shiny)
library(bslib)
library(bsicons)
library(leaflet)
library(DT)
library(dplyr)
library(tidyr)
library(ggplot2)
library(arrow)
library(DBI)

# ---------------------------------------------------------------------------
# Data (loaded once when the app starts)
# ---------------------------------------------------------------------------

data_dir <- Sys.getenv("PHAS_DATA_DIR", "./data")

weekly <- read_parquet(file.path(data_dir, "weekly_counts.parquet")) |>
  mutate(week_start = as.Date(week_start))

alerts <- read_parquet(file.path(data_dir, "alerts_2026.parquet")) |>
  filter(status == "ok") |>
  mutate(week_start = as.Date(week_start))

isolates <- read_parquet(file.path(data_dir, "isolates.parquet"))

con <- dbConnect(
  RPostgres::Postgres(),
  host     = Sys.getenv("PG_HOST"),
  port     = as.integer(Sys.getenv("PG_PORT", "5432")),
  dbname   = Sys.getenv("PG_DB"),
  user     = Sys.getenv("PG_USER"),
  password = Sys.getenv("PG_PASSWORD")
)
cases <- dbGetQuery(con, "
  SELECT case_id, pathogen, sample_date, county_name, hospitalised
  FROM cases
") |>
  mutate(sample_date = as.Date(sample_date))
dbDisconnect(con)

# County seat coordinates (approximate), used to place map markers.
county_xy <- tibble::tribble(
  ~county_name,      ~lat,  ~lng,
  "Stockholm",       59.33, 18.07,
  "Uppsala",         59.86, 17.64,
  "Södermanland",    58.75, 17.01,
  "Östergötland",    58.41, 15.62,
  "Jönköping",       57.78, 14.16,
  "Kronoberg",       56.88, 14.81,
  "Kalmar",          56.66, 16.36,
  "Gotland",         57.64, 18.30,
  "Blekinge",        56.16, 15.59,
  "Skåne",           55.60, 13.00,
  "Halland",         56.67, 12.86,
  "Västra Götaland", 57.71, 11.97,
  "Värmland",        59.38, 13.50,
  "Örebro",          59.27, 15.21,
  "Västmanland",     59.61, 16.55,
  "Dalarna",         60.61, 15.63,
  "Gävleborg",       60.67, 17.14,
  "Västernorrland",  62.63, 17.94,
  "Jämtland",        63.18, 14.64,
  "Västerbotten",    63.83, 20.26,
  "Norrbotten",      65.58, 22.15
)

alert_weeks  <- sort(unique(alerts$week_start))
default_week <- as.Date("2026-09-07")
if (!default_week %in% alert_weeks) default_week <- max(alert_weeks)

col_normal <- "#1F5A96"
col_alert  <- "#C0392B"

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- page_sidebar(
  title = tags$span("Zoonoses Surveillance",
                    tags$small(class = "text-muted ms-2", "synthetic demo data")),
  theme = bs_theme(version = 5, primary = col_normal),
  fillable = FALSE,
  sidebar = sidebar(
    selectInput("pathogen", "Pathogen",
                choices = sort(unique(weekly$pathogen)), selected = "Salmonella"),
    sliderInput("week", "Week starting",
                min = min(alert_weeks), max = max(alert_weeks),
                value = default_week, step = 7, timeFormat = "%Y-%m-%d",
                animate = animationOptions(interval = 1500)),
    selectInput("county", "County for trend",
                choices = c("All of Sweden", sort(county_xy$county_name))),
    helpText("Tip: click a county on the map to see its trend."),
    hr(),
    tags$small(class = "text-muted", textOutput("viewer"))
  ),
  layout_columns(
    fill = FALSE,
    value_box(title = "Cases this week", value = textOutput("vb_cases"),
              showcase = bs_icon("clipboard2-pulse"), theme = "primary"),
    value_box(title = "Change from last week", value = textOutput("vb_change"),
              showcase = bs_icon("arrow-down-up")),
    value_box(title = "Counties with an alert", value = textOutput("vb_alerts"),
              showcase = bs_icon("exclamation-triangle"), theme = "danger"),
    value_box(title = "Hospitalised this week", value = textOutput("vb_hosp"),
              showcase = bs_icon("hospital"))
  ),
  layout_columns(
    col_widths = c(5, 7),
    card(full_screen = TRUE, height = 520,
         card_header(textOutput("map_title", inline = TRUE)),
         leafletOutput("map", height = "100%")),
    card(full_screen = TRUE, height = 520,
         card_header(textOutput("trend_title", inline = TRUE)),
         plotOutput("trend", height = "100%"))
  ),
  navset_card_tab(
    nav_panel("Alerts, last 8 weeks", DTOutput("alert_tbl")),
    nav_panel("Genomic clusters, last 6 weeks", DTOutput("cluster_tbl"))
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  # Slider dates can drift by a day; always use the Monday of the week.
  wk <- reactive({
    d <- as.Date(input$week)
    d - (as.POSIXlt(d)$wday + 6) %% 7
  })

  output$viewer <- renderText({
    paste("Signed in as:", if (is.null(session$user)) "local user" else session$user)
  })

  # Counts and alerts for the selected pathogen and week, per county.
  county_week <- reactive({
    weekly |>
      filter(pathogen == input$pathogen, week_start == wk()) |>
      select(county_name, cases) |>
      left_join(alerts |>
                  filter(pathogen == input$pathogen, week_start == wk()) |>
                  select(county_name, threshold, alarm),
                by = "county_name") |>
      mutate(alarm = coalesce(alarm, FALSE)) |>
      inner_join(county_xy, by = "county_name")
  })

  # ---- Value boxes --------------------------------------------------------

  output$vb_cases <- renderText(sum(county_week()$cases))

  output$vb_change <- renderText({
    prev <- weekly |>
      filter(pathogen == input$pathogen, week_start == wk() - 7) |>
      pull(cases) |> sum()
    d <- sum(county_week()$cases) - prev
    sprintf("%+d", d)
  })

  output$vb_alerts <- renderText(sum(county_week()$alarm))

  output$vb_hosp <- renderText({
    cases |>
      filter(pathogen == input$pathogen, hospitalised,
             sample_date >= wk(), sample_date <= wk() + 6) |>
      nrow()
  })

  # ---- Map ----------------------------------------------------------------

  output$map_title <- renderText(
    sprintf("%s cases by county, week %s", input$pathogen, format(wk(), "%G-W%V"))
  )

  output$map <- renderLeaflet({
    m <- leaflet(options = leafletOptions(minZoom = 4))
    # OpenStreetMap tiles need no API key. Set PHAS_MAP_TILES=none for a
    # network without internet access (markers still show).
    if (Sys.getenv("PHAS_MAP_TILES", "osm") != "none") {
      m <- addTiles(m, options = tileOptions(opacity = 0.6))
    }
    m |>
      setView(lng = 16.5, lat = 61.5, zoom = 4) |>
      addLegend("bottomright", colors = c(col_normal, col_alert),
                labels = c("No alert", "Alert"), opacity = 0.8)
  })

  observe({
    d <- county_week()
    leafletProxy("map", data = d) |>
      clearMarkers() |>
      addCircleMarkers(
        lng = ~lng, lat = ~lat, layerId = ~county_name,
        radius = ~4 + 3 * sqrt(cases),
        color = ~ifelse(alarm, col_alert, col_normal),
        fillColor = ~ifelse(alarm, col_alert, col_normal),
        fillOpacity = 0.6, weight = 1,
        label = ~sprintf("%s: %d cases%s", county_name, cases,
                         ifelse(alarm, sprintf(" (alert, threshold %.1f)", threshold), ""))
      )
  })

  observeEvent(input$map_marker_click, {
    updateSelectInput(session, "county", selected = input$map_marker_click$id)
  })

  # ---- Trend --------------------------------------------------------------

  output$trend_title <- renderText(
    sprintf("%s, %s: last 52 weeks", input$pathogen, input$county)
  )

  output$trend <- renderPlot({
    from <- wk() - 7 * 51
    if (input$county == "All of Sweden") {
      series <- weekly |>
        filter(pathogen == input$pathogen, week_start >= from, week_start <= wk()) |>
        group_by(week_start) |>
        summarise(cases = sum(cases), .groups = "drop") |>
        mutate(threshold = NA_real_, alarm = FALSE)
    } else {
      series <- weekly |>
        filter(pathogen == input$pathogen, county_name == input$county,
               week_start >= from, week_start <= wk()) |>
        select(week_start, cases) |>
        left_join(alerts |>
                    filter(pathogen == input$pathogen, county_name == input$county) |>
                    select(week_start, threshold, alarm),
                  by = "week_start") |>
        mutate(alarm = coalesce(alarm, FALSE))
    }

    ggplot(series, aes(week_start, cases)) +
      geom_col(aes(fill = alarm), width = 6) +
      geom_step(aes(y = threshold), direction = "mid", colour = "grey25",
                na.rm = TRUE) +
      geom_vline(xintercept = wk(), linetype = "dashed", colour = "grey50") +
      scale_fill_manual(values = c(`FALSE` = "#9BB7D4", `TRUE` = col_alert),
                        labels = c(`FALSE` = "Normal", `TRUE` = "Alert"),
                        name = NULL, drop = FALSE) +
      labs(x = NULL, y = "Cases per week",
           caption = if (input$county == "All of Sweden") NULL
                     else "Line: alert threshold (from the Slurm alert job)") +
      theme_minimal(base_size = 14) +
      theme(legend.position = "top")
  }, res = 96)

  # ---- Tables -------------------------------------------------------------

  output$alert_tbl <- renderDT({
    alerts |>
      filter(pathogen == input$pathogen, alarm,
             week_start > wk() - 7 * 8, week_start <= wk()) |>
      arrange(desc(week_start), desc(observed / threshold)) |>
      transmute(Week = iso_week, County = county_name, Cases = observed,
                Threshold = round(threshold, 1),
                `Times threshold` = round(observed / threshold, 1)) |>
      datatable(rownames = FALSE, options = list(pageLength = 8, dom = "tip"))
  })

  output$cluster_tbl <- renderDT({
    week_end <- wk() + 6
    recent <- isolates |>
      filter(pathogen == input$pathogen, !is.na(cgmlst_cluster)) |>
      inner_join(cases |> select(case_id, sample_date, county_name), by = "case_id") |>
      filter(sample_date > week_end - 42, sample_date <= week_end) |>
      group_by(cgmlst_cluster) |>
      filter(n() >= 5) |>
      ungroup()

    if (nrow(recent) == 0) {
      return(datatable(
        tibble(Result = "No clusters with 5 or more isolates in the last 6 weeks."),
        rownames = FALSE, options = list(dom = "t")
      ))
    }

    recent |>
      group_by(cgmlst_cluster) |>
      summarise(
        Subtype  = paste(unique(subtype), collapse = ", "),
        Isolates = n(),
        Counties = paste(sort(unique(county_name)), collapse = ", "),
        `First sample` = min(sample_date),
        `Last sample`  = max(sample_date),
        .groups = "drop"
      ) |>
      rename(Cluster = cgmlst_cluster) |>
      arrange(desc(Isolates)) |>
      datatable(rownames = FALSE, options = list(pageLength = 8, dom = "tip"))
  })
}

shinyApp(ui, server)
