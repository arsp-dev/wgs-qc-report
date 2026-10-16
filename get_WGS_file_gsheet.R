# Load package
library(tidyverse)
library(knitr)
library(readxl)
library(kableExtra)
library(RColorBrewer)
library(scales)
library(readr)
library(DBI)
library(svDialogs)
library(writexl)
library(conflicted)
library(data.table)
library(googlesheets4)

conflicts_prefer(openxlsx::write.xlsx)
conflicts_prefer(dplyr::filter)



# --- Set Working Directory ----
setwd("E:/DMU Projects/wgs-qc")



# --- Read Google Sheet for Referred Database ---
#referred_sheet_id <- "1JKtyRyLh0-ck2xCk0oIH4iidgs21996UKj69lvvlXAU"
#referred_df <- read_sheet(referred_sheet_id, sheet = 1)

# referred_db credentials
con <- dbConnect(
  RPostgres::Postgres(),
  dbname   = "referred_db",
  host     = "10.10.103.222",          # Ubuntu server IP
  port     = 5432,                     # Standard Postgres port
  user     = "referred_user",
  password = "arsp_referred"
)

print("--- Connection Established Successfully! ---")


#  Download both tables into R memory
referred_df  <- dbReadTable(con, "Referred_Data") %>%
  rename_with(tolower) %>%
  rename(accession_no = accessionno) %>%
  mutate(arsrl_org = ars_orgname)


# --- Google Sheet ID extracted from the URL ---
sheet_id <- "1OUnMF78Nftwu442t7N3Ly6JoEW8Wmk5z9cNY7b_KOzY"


# --- Read Google Sheets (RAW READS)---
df_batch <- read_sheet(sheet_id, sheet = "batch")
df_bactscout <- read_sheet(sheet_id, sheet = "bactscout")

# --- Read Google Sheets (ASSEMBLY)---
df_gambit <- read_sheet(sheet_id, sheet = "gambit")
df_checkm2 <- read_sheet(sheet_id, sheet = "checkm2")
df_assembly <- read_sheet(sheet_id, sheet = "assembly-scan")
#df_mlst <- read_sheet(sheet_id, sheet = "mlst")
#df_mlst <- read_sheet(sheet_id, sheet = "mlst_new")
df_amrfinderplus <- read_sheet(sheet_id, sheet = "amrfinderplus")




# --- Get Sample Sheet File ---
get_samplesheet <- dlgInput("Enter sample sheet file name:", Sys.info()[" "])$res
batch_code <- gsub("\\[edited\\]","" ,get_samplesheet)



# --- Filter Batch Dataframe based on Batch Code ---
batch_df <- df_batch[df_batch$batch_code == batch_code, ]
sample_name <- batch_df$sample_name
sample_name <- gsub("-", "_", sample_name, fixed=TRUE)


# --- Remove batch number from sample_name ---
sample_name_clean <- sub("(.*)_[^_]*$", "\\1", sample_name)


# --- Modify columns ---
colnames(df_bactscout)[which(names(df_bactscout) == "sample_id")] <- "name"
colnames(df_gambit)[which(names(df_gambit) == "sample")] <- "name"
colnames(df_assembly)[which(names(df_assembly) == "sample")] <- "name"



# --- checkm2 column names to lower ---
names(df_checkm2) <- tolower(names(df_checkm2))

# --- remove ".fna" ---
df_checkm2$name <- gsub(".fna", "", df_checkm2$name, fixed=TRUE)


# --- Get species name ---
df_gambit$species <- case_when(
  df_gambit$predicted.rank == "species" ~ df_gambit$predicted.name,
  TRUE ~ df_gambit$next.name
)


# --- Compute total GC Content ---
df_assembly$gc_content <- as.numeric(df_assembly$contig_percent_g) + as.numeric(df_assembly$contig_percent_c)



# --- Subset Columns per dataframe ---
gambit_sub_df <- subset(df_gambit, select = c(name, species))
checkm2_sub_df <- subset(df_checkm2, select = c(name, completeness, contamination, total_coding_sequences, genome_size))
assembly_sub_df <- subset(df_assembly, select = c(name, total_contig, gc_content, n50_contig_length))



# --- Put all data frames into list ---
df_list <- list(gambit_sub_df, checkm2_sub_df, assembly_sub_df)


# --- Merge all data frames in list ---
wgs_result_df <- df_list %>% reduce(full_join, by='name')

# --- Format Name Column ---
wgs_result_df$name <- gsub("-", "_", wgs_result_df$name, fixed=TRUE)
wgs_result_df$name <- toupper(wgs_result_df$name)


# --- Filter wgs_result_df based on sample_name ---
wgs_result_df <- wgs_result_df[wgs_result_df$name %in% sample_name, ]



# ---  Apply the function to the column of strings ---
wgs_result_df <- wgs_result_df %>% rename(sample_id = name)


# --- Subset referred_df ---
referred_df <- subset(referred_df, select = c(accession_no,arsrl_org))

# --- Create arsrl_result_df based on sample_name ---
arsrl_result_df <- referred_df[referred_df$accession_no %in% sample_name_clean, ]
colnames(arsrl_result_df) <- c('sample_id','arsrl_org')

# ---  Returns string without leading or trailing white space ---
arsrl_result_df$arsrl_org <- gsub("^\\s+|\\s+$", "", arsrl_result_df$arsrl_org)

# Arrange rows based on the target_vector
arsrl_result_df <- arsrl_result_df[match(sample_name_clean, arsrl_result_df$sample_id), ]



# --- Patterns and corresponding organisms to manually add ---
manual_samples <- tibble::tribble(
  ~pattern,    ~arsrl_org,
  "UTP",       "Escherichia coli",
  "STC",       "Burkholderia cepacia",
  "QC_BBR",    "Bordetella bronchiseptica",
  "VC",        "Neisseria gonorrhoeae"
)

# --- Loop through patterns and add rows if present ---
for(i in seq_len(nrow(manual_samples))) {

  matches <- grep(
    manual_samples$pattern[i],
    wgs_result_df$sample_id,
    value = TRUE
  )

  if(length(matches) > 0) {
    arsrl_result_df <- arsrl_result_df %>%
      add_row(
        sample_id = sub("(.*)_[^_]*$", "\\1", matches),
        arsrl_org = manual_samples$arsrl_org[i]
      )
  }
}




# --- Referred isolates with WGS result, but the referred data have not been endorsed for encoding to DMU ---
arsrl_id <- arsrl_result_df$sample_id
no_referred_data_id <- setdiff(sample_name_clean, arsrl_id)



# --- manually add no referred data ---
if(length(no_referred_data_id) !=0){
  sample_id = no_referred_data_id
  arsrl_org = "No Referred Data"

  arsrl_result_df <- arsrl_result_df %>%
    add_row(sample_id = sample_id, arsrl_org=arsrl_org)

}


arsrl_result_df <- arsrl_result_df %>%
  filter(!is.na(sample_id))


wgs_df1 <- wgs_result_df
#wgs_df <- wgs_df1
arsrl_result_df1 <- arsrl_result_df
#arsrl_result_df <- arsrl_result_df1






if(nrow(wgs_result_df) != 0){
  rmarkdown::render("wgs_qc_report_pdf.Rmd",
                    output_file = paste("reports/ARSRL_WGS_QC_report_",batch_code, '.pdf', sep='')
  )
}else{
  cat("No file found")
}




if(nrow(wgs_result_df) != 0){
  rmarkdown::render("wgs_qc_report_html.Rmd",
                    output_file = paste("reports/ARSRL_WGS_QC_report_",batch_code, '.html', sep='')
  )
}

