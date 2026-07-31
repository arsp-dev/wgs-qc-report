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
