# phassurv

Internal R package for the PHAS surveillance demo. It holds the code that the report, the Slurm job and the dashboard share. The data is synthetic.

| Function | Purpose |
|---|---|
| `phas_connect()` | Connect to PostgreSQL with the `PG_*` environment variables |
| `read_cases(con, to)` | Read the case line list |
| `read_phas(name)` | Read a Parquet table from the data folder (`PHAS_DATA_DIR`) |
| `week_monday()`, `iso_week()` | Week helpers |
| `detect_outbreaks(weekly, ...)` | Farrington outbreak detection for each county × pathogen |
| `find_clusters(isolates, cases, week, ...)` | Recent cgMLST clusters, with resistance profile |
| `theme_phas()`, `scale_fill_alert()`, `phas_colours` | Shared plot style |

## Example

```r
library(phassurv)

weekly <- read_phas("weekly_counts")
alerts <- detect_outbreaks(weekly, pathogen = "Salmonella",
                           weeks = as.Date("2026-09-07"))
subset(alerts, alarm)
```

## Publish through Package Manager

Package Manager builds the package from Git. Each new version tag becomes a new package version that users install with `install.packages()`.

### 1. Put the package in its own Git repository

The `phassurv/` folder is the root of the repository (DESCRIPTION is at the top level).

```bash
cd phassurv
git init
git add .
git commit -m "phassurv 0.1.0"
git tag v0.1.0
git remote add origin <git-url>
git push -u origin main --tags
```

The tag version must be the same as `Version:` in DESCRIPTION.

### 2. Set up the Git builder (Package Manager administrator)

```bash
rspm create source --type=git --name=internal-src
rspm create git-builder --url=<git-url> --source=internal-src --build-trigger=tags
rspm list git-builds --source=internal-src --name=phassurv
```

If the repository is private, add a credential first and use `--credential` with `create git-builder`. Package Manager needs an R installation to build Git packages.

### 3. Make the package available to users

Option A: a repository that has both CRAN and the internal packages (users need one repository URL).

```bash
rspm create repo --name=phas --description="CRAN and PHAS internal packages"
rspm subscribe --repo=phas --source=cran
rspm subscribe --repo=phas --source=internal-src
```

Option B: a separate internal repository.

```bash
rspm create repo --name=internal --description="PHAS internal packages"
rspm subscribe --repo=internal --source=internal-src
```

### 4. Install

```r
options(repos = c(PHAS = "https://<package-manager>/phas/latest"))
install.packages("phassurv")
```

## Release a new version

1. Change the code.
2. Increase `Version:` in DESCRIPTION, for example to `0.2.0`, and add a line to NEWS.md.
3. Commit, tag and push:

   ```bash
   git commit -am "phassurv 0.2.0"
   git tag v0.2.0
   git push --tags
   ```

4. Package Manager finds the new tag (it checks every 5 minutes by default) and builds 0.2.0. Version 0.1.0 stays in the archive, so older snapshots still install it.

## Demo story

1. Show the copied code: the same Farrington code is in the report, the Slurm task and the dashboard.
2. Show `phassurv`: one copy, with help pages (`?detect_outbreaks`) and tests.
3. Push a tag. Show the build in the Package Manager UI.
4. Install with `install.packages("phassurv")` in Positron.
5. Show the shorter Slurm task:

   ```r
   library(phassurv)
   task_id <- as.integer(Sys.getenv("SLURM_ARRAY_TASK_ID", "1"))
   weekly  <- read_phas("weekly_counts")
   series  <- unique(weekly[order(weekly$pathogen, weekly$county_name),
                            c("pathogen", "county_name")])[task_id, ]
   out <- detect_outbreaks(weekly, pathogen = series$pathogen,
                           county = series$county_name)
   arrow::write_parquet(out, sprintf("results/alerts/task_%03d.parquet", task_id))
   ```

## Development

```r
roxygen2::roxygenise()   # update NAMESPACE and help pages
testthat::test_local()   # run the tests
```
