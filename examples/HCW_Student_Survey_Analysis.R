# ============================================================================
# HCW Student Survey Analysis
#
# LEGACY:   Older notes used ODBC with browser/email sign-in. Do not use that
#           path for researchers.
#
# APPROVED: ODBC access now reads the connection string from Key Vault and uses
#           the cdiofabric managed identity. Managed identity examples live in:
#           fabric-personal-pc-odbc-access/examples/r/fabric_odbc_researcher_guide.Rmd
#
# NOW:      This script uses fabriconnect / Fabric Lakehouse where approved.
#           No personal researcher Fabric login is required.
# ============================================================================

df_list <- list()
rm(list=ls())

library(dplyr)
library(readr)
library(lubridate)
library(ggplot2)
library(tidyr)
library(purrr)
library(stringr)
library(broom)
library(flextable)
library(tidyverse)
library(vctrs)
library(tidyquant)
library(fabriconnect)

# ---- Connect ----
# For direct ODBC, use the managed identity example in:
# fabric-personal-pc-odbc-access/examples/r/fabric_odbc_researcher_guide.Rmd
conn <- connect_to_fabric()
baseline <- read_table(conn, "qualtrics_hcw_student_survey")

# View the dataset
View(baseline)

# Save dataset to CSV (optional)
write_csv(baseline, "baseline.csv")

# Filter consented participants
baseline_filtered <- baseline |>
  dplyr::filter(Consent3 == 1)

# ---- Descriptives  ----
filter(Date(baseline_filtered))

summarise(baseline_filtered)

freq(baseline_filtered$monthlyincome)

frequency(baseline_filtered$Age)

summarise(baseline$Age)

baseline_filtered$Age

summarize_each(baseline_filtered$Age)

summary(age)

# ---- Additional analysis packages (install once if needed) ----
# install.packages(c("gee", "weights", "anesrake",
#                    "glmnet", "twang", "mice",
#                    "geepack", "survey", "Hmisc",
#                    "matrixStats", "tableone",
#                    "gtsummary", "officer",
#                    "writexl", "readxl"))

# ---- Utility: fetch any query ----
fetch_data <- function(query) {
  query_tables(conn, query)
}