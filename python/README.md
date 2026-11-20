# AMR Gene Summary (Python)

A Python script for the bioinformatics part of the PHAS demo. It summarises the resistance genes in the sequenced isolates. The data is synthetic.

## What it shows

| Cell | Output |
|---|---|
| 1. Gene prevalence | % of sequenced isolates with each gene, per pathogen. Chart: `gene_prevalence.png` |
| 2. Gene trend | gyrA T86I (ciprofloxacin) in Campylobacter, by year, domestic vs. travel. Chart: `gyrA_trend.png` |
| 3. Multidrug resistance | Isolates with genes for 3 or more antibiotic classes, domestic vs. travel |
| 4. Cluster gene profile | Genes in clusters with 5+ isolates in the 6 weeks to the report week |
| 5. Save | Parquet results in `results/amr/` that R, Connect or the dashboard can read |

Expected results:

- gyrA T86I in domestic Campylobacter rises from about 29 % (2023) to 41 % (2026). Travel cases stay at about 62–70 %.
- Multidrug resistance is highest in travel-associated Salmonella (about 7 %).
- Cluster `CT-2026-017`: 90 isolates, all carry tet(A).

## Data

- `data/isolates.parquet` and `data/amr_genes.parquet`
- PostgreSQL table `cases` (for sample date and travel status), through the `PG_*` environment variables. Set `PHAS_DB_URL` to use another database URL instead.

## Before you start

1. Copy the `python/` folder into the project, next to `data/`.
2. In Positron, create a Python environment for the project and select it as the interpreter.
3. Install the packages. If Package Manager has a PyPI repository, use it:

   ```bash
   pip install -r python/requirements.txt --index-url https://<package-manager>/pypi/latest/simple
   ```

4. Make sure the `PG_*` environment variables are set for Python. Python does not read `~/.Renviron`. Add `export PG_HOST=...` (and the other values) to `~/.bashrc`, then start a new Python console in Positron. To check, run `import os; os.environ.get("PG_HOST")` in the console.

## Procedure

- To run cell by cell: open `amr_gene_summary.py` in Positron and press **Ctrl+Enter** (**Cmd+Enter** on macOS) in each `# %%` cell. Charts show in the Plots pane. Tables show in the Console, and the data frames show in the Variables pane.
- To run the whole script: `python python/amr_gene_summary.py`

## Mistral prompts for the demo

Use the Mistral extension in Positron with the script open.

1. "Explain what cell 3 does and why the threshold is 3 antibiotic classes."
2. "Add a cell that lists the 5 most common gene combinations in travel-associated Salmonella isolates with multidrug resistance."
3. "Change the gyrA trend chart so it also shows the number of isolates for each point."

Check the code that Mistral writes before you run it.
