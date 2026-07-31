#--- load library ---
library(tidyverse)
library(conflicted)
library(svDialogs)
library(googlesheets4)
library(DBI)
library(here)

conflicts_prefer(dplyr::filter)

#--- Helper: strip trailing "_<batchnum>" from sample_id
strip_batch_suffix <- function(x) sub("(.*)_[^_]*$", "\\1", x)

#--- pull data from Google sheets ---
wgs_sheet_id <- "1OUnMF78Nftwu442t7N3Ly6JoEW8Wmk5z9cNY7b_KOzY"

sheets <- c(
  df_batch        = "batch",
  df_bactscout    = "bactscout",
  df_gambit       = "gambit",
  df_checkm2      = "checkm2",
  df_assembly     = "assembly-scan",
  df_amrfinderplus = "amrfinderplus"
)

# Reads all sheets and assigns them directly to df_* variables in your environment
list2env(lapply(sheets, function(s) read_sheet(wgs_sheet_id, sheet = s)), envir = .GlobalEnv)


#--- pull data from Referred Database ---
# referred_db credentials
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "referred_db",
  host     = Sys.getenv("REFERRED_DB_HOST"),
  port     = 5432,
  user     = Sys.getenv("REFERRED_DB_USER"),
  password = Sys.getenv("REFERRED_DB_PASSWORD")
)

print("--- Connection Established Successfully! ---")


#  Download both tables into R memory
df_referred  <- dbReadTable(con, "Referred_Data") %>%
  rename_with(tolower) %>%
  mutate(patient_id = str_trim(patient_id)) %>%
  rename(organism = site_org) %>%
  mutate(spec_num = toupper(spec_num)) %>%
  mutate(spec_num = gsub(" ", "", spec_num)) %>%
  mutate(ref_val = TRUE)


#--- User input ---
batch_code <- dlgInput("Enter Batch Code:", Sys.info()[" "])$res
get_samplesheet <- dlgInput("Enter sample sheet file name:", Sys.info()[" "])$res


#--- Get sample name ---
sample_name <- df_batch %>%
  filter(batch_code == !!batch_code) %>%
  pull(sample_name) %>%
  gsub("-", "_", ., fixed = TRUE)


sample_name_clean <- strip_batch_suffix(sample_name)

#--- Clean and Merge tables ---
df_gambit <- rename(df_gambit, name = sample)
df_assembly <- rename(df_assembly, name = sample)
df_bactscout <- rename(df_bactscout, name = sample_id)

names(df_checkm2) <- tolower(names(df_checkm2))
df_checkm2$name <- gsub(".fna", "", df_checkm2$name, fixed = TRUE)

df_gambit <- df_gambit %>%
  mutate(species = if_else(predicted.rank == "species", predicted.name, next.name))

df_assembly <- df_assembly %>%
  mutate(gc_content = as.numeric(contig_percent_g) + as.numeric(contig_percent_c))

wgs_result_df <- list(
  df_gambit   %>% select(name, species),
  df_checkm2  %>% select(name, completeness, contamination, total_coding_sequences, genome_size),
  df_assembly %>% select(name, total_contig, gc_content, n50_contig_length)
) %>%
  reduce(full_join, by = "name") %>%
  mutate(name = str_replace_all(name, "-", "_") %>% toupper()) %>%
  filter(name %in% sample_name) %>%
  rename(sample_id = name)


#--- Match samples to referred data ---
result <- df_referred %>%
  rename(accession_no = accessionno, arsrl_org = ars_orgname) %>%
  select(accession_no, arsrl_org) %>%
  filter(accession_no %in% sample_name_clean) %>%
  rename(sample_id = accession_no) %>%
  mutate(arsrl_org = str_trim(arsrl_org)) %>%
  arrange(match(sample_id, sample_name_clean))


# Special sample-code prefixes that get a fixed organism assignment
# (no matching referral record exists for these).
special_orgs <- tribble(
  ~pattern,   ~arsrl_org,
  "UTP",      "Escherichia coli",
  "STC",      "Burkholderia cepacia",
  "QC_BBR",   "Bordetella bronchiseptica",
  "VC",       "Neisseria gonorrhoeae"
)

arsrl_result_df <- result
for (i in seq_len(nrow(special_orgs))) {
  matches <- grep(special_orgs$pattern[i], wgs_result_df$sample_id, value = TRUE)
  if (length(matches) > 0) {
    arsrl_result_df <- arsrl_result_df %>%
      add_row(sample_id = strip_suffix(matches), arsrl_org = special_orgs$arsrl_org[i])
  }
}

# Any sample still without a match: referred but not yet endorsed for DMU encoding
no_referred_data_id <- setdiff(sample_name_clean, arsrl_result_df$sample_id)
if (length(no_referred_data_id) > 0) {
  arsrl_result_df <- arsrl_result_df %>%
    add_row(sample_id = no_referred_data_id, arsrl_org = "No Referred Data")
}

#--- Render report ---
if (nrow(wgs_result_df) != 0) {
  rmarkdown::render(
    "wgs_qc_report_pdf.Rmd",
    output_file = paste0("reports/ARSRL_WGS_QC_report_", batch_code, ".pdf")
  )

} else {
  cat("No file found")
}



