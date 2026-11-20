# %% [markdown]
# # Antimicrobial resistance gene summary (synthetic demo data)
#
# For the bioinformatics team: what resistance genes do our sequenced
# isolates carry, how do they change over time, which isolates are
# multidrug-resistant, and what is the gene profile of recent clusters?
#
# Run cell by cell in Positron (Ctrl/Cmd+Enter), or as a script:
#   python python/amr_gene_summary.py
#
# Data:
#   data/isolates.parquet, data/amr_genes.parquet  (Parquet files)
#   PostgreSQL table "cases"                         (PG_* environment variables)

# %% Setup
import os
from pathlib import Path
from urllib.parse import quote_plus

import matplotlib.pyplot as plt
import pandas as pd
from sqlalchemy import create_engine, text

DATA_DIR = Path(os.environ.get("PHAS_DATA_DIR", "data"))
OUT_DIR = Path(os.environ.get("PHAS_RESULTS_DIR", "results")) / "amr"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Week to report clusters for (any date in the week).
REPORT_WEEK = pd.Timestamp(os.environ.get("PHAS_REPORT_WEEK", "2026-09-07"))

# Antibiotic class for each antibiotic (used for multidrug resistance).
ANTIBIOTIC_CLASS = {
    "ciprofloxacin": "fluoroquinolones",
    "erythromycin": "macrolides",
    "tetracycline": "tetracyclines",
    "gentamicin": "aminoglycosides",
    "ampicillin": "penicillins",
    "cefotaxime": "cephalosporins",
    "meropenem": "carbapenems",
    "trimethoprim-sulfamethoxazole": "folate pathway inhibitors",
}

COLOURS = {"Domestic": "#1F5A96", "Travel-associated": "#E07A1F"}


def db_url() -> str:
    """SQLAlchemy URL from PHAS_DB_URL, or from the PG_* environment variables."""
    if url := os.environ.get("PHAS_DB_URL"):
        return url
    user = quote_plus(os.environ["PG_USER"])
    password = quote_plus(os.environ.get("PG_PASSWORD", ""))
    host = os.environ["PG_HOST"]
    port = os.environ.get("PG_PORT", "5432")
    db = os.environ["PG_DB"]
    return f"postgresql+psycopg://{user}:{password}@{host}:{port}/{db}"


# %% Load data
isolates = pd.read_parquet(DATA_DIR / "isolates.parquet")
genes = pd.read_parquet(DATA_DIR / "amr_genes.parquet")

engine = create_engine(db_url())
with engine.connect() as conn:
    cases = pd.read_sql(
        text("SELECT case_id, sample_date, county_name, travel_associated FROM cases"),
        conn,
        parse_dates=["sample_date"],
    )
cases["travel_associated"] = cases["travel_associated"].astype(bool)

seq = isolates[isolates["sequenced"]].merge(cases, on="case_id", how="inner")
seq["year"] = seq["sample_date"].dt.year
seq["origin"] = seq["travel_associated"].map({True: "Travel-associated", False: "Domestic"})

print(f"Sequenced isolates: {len(seq):,} | Gene hits: {len(genes):,}")
print(seq.groupby("pathogen").size().rename("sequenced").to_string())

# %% 1. Gene prevalence per pathogen
n_seq = seq.groupby("pathogen").size().rename("sequenced")

prevalence = (
    genes.merge(seq[["isolate_id", "pathogen"]], on="isolate_id")
    .groupby(["pathogen", "gene", "antibiotic"])["isolate_id"]
    .nunique()
    .rename("isolates")
    .reset_index()
    .merge(n_seq, on="pathogen")
)
prevalence["pct"] = (100 * prevalence["isolates"] / prevalence["sequenced"]).round(1)
prevalence = prevalence.sort_values(["pathogen", "pct"], ascending=[True, False])
print(prevalence.to_string(index=False))

# %% Plot: gene prevalence
pathogens = sorted(prevalence["pathogen"].unique())
fig, axes = plt.subplots(1, len(pathogens), figsize=(4 * len(pathogens), 4), sharex=True)
for ax, pathogen in zip(axes, pathogens):
    d = prevalence[prevalence["pathogen"] == pathogen].sort_values("pct")
    ax.barh(d["gene"], d["pct"], color="#1F5A96")
    ax.set_title(pathogen, fontweight="bold")
    ax.set_xlabel("% of sequenced isolates")
    ax.grid(axis="x", alpha=0.3)
fig.suptitle("Resistance gene prevalence, all years", fontweight="bold")
fig.tight_layout()
fig.savefig(OUT_DIR / "gene_prevalence.png", dpi=150)

# %% 2. Trend for one gene: gyrA T86I (ciprofloxacin) in Campylobacter


def gene_trend(pathogen: str, gene: str) -> pd.DataFrame:
    """% of sequenced isolates with `gene`, by year and travel status."""
    base = seq[seq["pathogen"] == pathogen]
    carriers = set(genes.loc[genes["gene"] == gene, "isolate_id"])
    out = (
        base.assign(has_gene=base["isolate_id"].isin(carriers))
        .groupby(["year", "origin"])["has_gene"]
        .agg(pct="mean", isolates="size")
        .reset_index()
    )
    out["pct"] = (100 * out["pct"]).round(1)
    return out


trend = gene_trend("Campylobacter", "gyrA_T86I")
print(trend.pivot(index="year", columns="origin", values="pct").to_string())

fig, ax = plt.subplots(figsize=(6, 4))
for origin, d in trend.groupby("origin"):
    ax.plot(d["year"], d["pct"], marker="o", linewidth=2, label=origin, color=COLOURS[origin])
ax.set_ylim(0, 100)
ax.set_xticks(sorted(trend["year"].unique()))
ax.set_ylabel("% of sequenced isolates")
ax.set_title("Campylobacter: gyrA T86I (ciprofloxacin resistance)", fontweight="bold")
ax.legend(frameon=False)
ax.grid(alpha=0.3)
fig.tight_layout()
fig.savefig(OUT_DIR / "gyrA_trend.png", dpi=150)

# %% 3. Multidrug resistance (genes for 3 or more antibiotic classes)
classes = genes.assign(ab_class=genes["antibiotic"].map(ANTIBIOTIC_CLASS))
n_classes = classes.groupby("isolate_id")["ab_class"].nunique().rename("n_classes")

mdr = seq[["isolate_id", "pathogen", "year", "origin"]].merge(
    n_classes, on="isolate_id", how="left"
)
mdr["n_classes"] = mdr["n_classes"].fillna(0).astype(int)
mdr["mdr"] = mdr["n_classes"] >= 3

mdr_summary = (
    mdr.groupby(["pathogen", "origin"])
    .agg(isolates=("isolate_id", "size"), mdr=("mdr", "sum"))
    .reset_index()
)
mdr_summary["pct_mdr"] = (100 * mdr_summary["mdr"] / mdr_summary["isolates"]).round(1)
print(mdr_summary.to_string(index=False))

# %% 4. Gene profile of recent clusters
week_start = REPORT_WEEK - pd.Timedelta(days=REPORT_WEEK.weekday())
week_end = week_start + pd.Timedelta(days=6)
recent = seq[
    seq["cgmlst_cluster"].notna()
    & (seq["sample_date"] > week_end - pd.Timedelta(days=42))
    & (seq["sample_date"] <= week_end)
]
sizes = recent.groupby(["cgmlst_cluster", "pathogen"]).size().rename("isolates")
big = sizes[sizes >= 5].reset_index()

cluster_genes = (
    genes.merge(recent[["isolate_id", "cgmlst_cluster"]], on="isolate_id")
    .groupby(["cgmlst_cluster", "gene"])["isolate_id"]
    .nunique()
    .rename("with_gene")
    .reset_index()
    .merge(big, on="cgmlst_cluster")
)
cluster_genes["pct"] = (100 * cluster_genes["with_gene"] / cluster_genes["isolates"]).round(1)

print(f"Clusters with 5+ isolates, 6 weeks to {week_end.date()}:")
print(big.to_string(index=False))
print(cluster_genes.sort_values(["cgmlst_cluster", "pct"], ascending=[True, False]).to_string(index=False))

# %% 5. Save results (Parquet can be read from R, Connect or the dashboard)
prevalence.to_parquet(OUT_DIR / "gene_prevalence.parquet", index=False)
trend.to_parquet(OUT_DIR / "gyrA_trend.parquet", index=False)
mdr_summary.to_parquet(OUT_DIR / "mdr_summary.parquet", index=False)
cluster_genes.to_parquet(OUT_DIR / "cluster_genes.parquet", index=False)
print(f"Wrote results to {OUT_DIR.resolve()}")
