# Zoonoses Surveillance Dashboard

A Shiny app for the PHAS demo. It shows cases and outbreak alerts by county and week, a trend per county, and genomic clusters. The data is synthetic.

## Data

| Source | Contents |
|---|---|
| `data/weekly_counts.parquet` | Weekly counts per county and pathogen |
| `data/alerts_2026.parquet` | Alerts from the Slurm array job (`slurm/submit.sh`) |
| `data/isolates.parquet` | Lab isolates with cgMLST cluster |
| PostgreSQL table `cases` | Case line list (dates, county, hospitalised) |

The app needs `alerts_2026.parquet`. Run the Slurm job first.

## Before you start

- Packages: `shiny`, `bslib`, `bsicons`, `leaflet`, `DT`, `dplyr`, `tidyr`, `ggplot2`, `arrow`, `DBI`, `RPostgres`.
- Set `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER` and `PG_PASSWORD` in `~/.Renviron` (Workbench) or as environment variables on the content (Connect).
- The map background loads tiles from CartoDB on the internet. If the network blocks it, the county markers still show on a blank background.

## Procedure

1. Copy `app.R` into a `dashboard/` folder in the project.
2. Make the data available to the app. Use one of these options:
   - Copy `data/` into `dashboard/data/`.
   - Set `PHAS_DATA_DIR` to the full path of the data folder.
3. In Workbench, open `app.R` and click **Run App**.
4. To publish, click the publish button in the editor and select Posit Connect. Include the `data/` folder in the files to publish, or set `PHAS_DATA_DIR` on Connect to a path the server can read.

## Demo path

1. Select **Salmonella** and week **2026-08-24**. Click play on the week slider to watch Halland, Skåne and Kronoberg turn red.
2. Click **Halland** on the map. The trend shows cases above the alert threshold.
3. Open **Genomic clusters**: cluster `CT-2026-017`, 90 isolates in three counties.
4. Point to "Signed in as" in the sidebar. On Connect, it shows the viewer's name from SSO.
