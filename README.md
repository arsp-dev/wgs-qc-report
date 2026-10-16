# WGS QC Report Pipeline

Generates the ARSRL Whole Genome Sequencing (WGS) Quality Control report (PDF and HTML) for a given sequencing batch. The pipeline pulls QC and identification results from Google Sheets and the referred-samples database, matches them against submitted specimens, checks species concordance, and renders a formatted report.

## Files

| File | Purpose |
|---|---|
| `get_wgs_results.R` | Main driver script. Pulls data, prompts for batch code and sample sheet, builds the working data frames, then renders both Rmd files. |
| `wgs_qc_report_html.Rmd` | Report template — self-contained HTML output (interactive `DT` tables, `plotly` sunburst chart). |
| `wgs_qc_report_pdf.Rmd` | Report template — LaTeX/PDF output (`kableExtra` tables, static plots via `webshot2`). |

The two `.Rmd` files are **not standalone** — they expect several data frames (`wgs_result_df`, `arsrl_result_df`, `df_bactscout`, `df_amrfinderplus`, etc.) and variables (`batch_code`, `get_samplesheet`, `sample_name`, `sample_name_clean`) to already exist in the environment. They are only meant to be rendered from within `get_wgs_results.R` via `rmarkdown::render()`, not knitted directly.

## Pipeline overview

1. Pull 6 sheets from a shared Google Sheet (batch metadata, BactScout, GAMBIT, CheckM2, assembly-scan, AMRFinderPlus results).
2. Connect to `referred_db` (PostgreSQL) and pull the `Referred_Data` table.
3. Prompt the user for a **batch code** and a **sample sheet filename**.
4. Clean/rename/merge the QC tool outputs into `wgs_result_df`, filtered to the current batch's samples.
5. Match samples to referred-specimen organism data (`arsrl_result_df`), applying fixed organism codes for special sample-code prefixes (UTP, STC, QC_BBR, VC).
6. Render `wgs_qc_report_pdf.Rmd` and `wgs_qc_report_html.Rmd` into `reports/ARSRL_WGS_QC_report_<batch_code>.pdf` / `.html`.

## What you'll need to run this

### 1. Credentials / access
- **Google Sheets access** for sheet ID will trigger an OAuth flow the first time (`gs4_auth()`), or needs a cached token.
- **`referred_db` PostgreSQL credentials**, set as environment variables (e.g. in `.Renviron`):
  ```
  REFERRED_DB_HOST=
  REFERRED_DB_USER=
  REFERRED_DB_PASSWORD=
  ```

### 2. Reference/data files (expected under `data_files/`, resolved via `here::here()`)
- `data_files/whonet_codes_2024.xlsx` — WHONET organism code reference (sheet `"ORGANISM"`, columns `ORG_ARS`, `ORGANISM_name`).
- `data_files/<sample_sheet_name>.csv` — the sequencing run's sample sheet (needs `sample_id`, `description`, `index_plate_well`, `experiment_name` columns after lowercasing). The filename (without extension) is what the script prompts for as "sample sheet file name."
- `data_files/qualibact_filtered_metrics_07292026.csv` — QualiBact QC metrics file referenced in the PDF report. **Note:** this filename has a hardcoded date; it will need to be updated (or the code parameterized) each time a new metrics export is produced.

### 3. Output folder
- A `reports/` subfolder in the working directory (script does not create it automatically — confirm it exists before rendering, or add a `dir.create("reports", showWarnings = FALSE)` step).

### 4. R packages
```r
install.packages(c(
  "tidyverse", "conflicted", "svDialogs", "googlesheets4", "DBI", "RPostgres",
  "here", "readxl", "writexl", "openxlsx", "knitr", "kableExtra", "DT",
  "htmltools", "RColorBrewer", "scales", "plotly", "webshot2", "rmarkdown"
))
```
- PDF rendering additionally requires a **LaTeX distribution** with `lualatex` (e.g. TinyTeX via `tinytex::install_tinytex()`), plus the LaTeX packages listed in the PDF Rmd's `header-includes` (booktabs, longtable, colortbl, pdflscape, xcolor, etc. — most ship with TinyTeX/TeX Live).
- `webshot2` requires a working headless Chromium install (`webshot2::install_phantomjs()` is *not* what's needed — check `chromote`/Chrome dependency).

## Usage

```r
source("get_wgs_results.R")
```

You'll be prompted (via pop-up dialog) for:
1. **Batch Code** — must match a `batch_code` value in the `batch` Google Sheet.
2. **Sample sheet file name** — the CSV filename (no extension) under `data_files/`.

Reports are written to:
```
reports/ARSRL_WGS_QC_report_<batch_code>.pdf
reports/ARSRL_WGS_QC_report_<batch_code>.html
```

## Known issues to check before relying on this as documentation
- The hardcoded `qualibact_filtered_metrics_07292026.csv` filename will break once a newer metrics file is used.
