# ============================================================================
# HCW Student Survey Analysis
#
# ORIGINAL: Used ODBC → SQL Server (uzima-dmac.database.windows.net)
#           with ActiveDirectoryInteractive authentication.
#           Required ODBC Driver 17, TDS port 1433, firewall rules.
#
# NOW:      Uses fabriconnect → Fabric Lakehouse (OneLake HTTPS).
#           No ODBC driver, no TDS port, no hardcoded credentials.
#           All traffic on port 443.
#
# Prerequisites:
#   1. az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
#   2. remotes::install_github("AKU-CDIO/fabric-inbound-access",
#        subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
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

# ---- Connect (replaces ODBC) ----
# OLD:
#   con <- dbConnect(odbc(),
#     Driver = 'ODBC Driver 17 for SQL Server',
#     Server = 'uzima-dmac.database.windows.net',
#     Database = 'Uzima_db',
#     username = '',
#     Authentication = 'ActiveDirectoryInteractive')
#   baseline <- dbGetQuery(con, "SELECT * FROM [dbo].[Qualtrics_HCW_Student_Survey]")
#
# NEW: fabriconnect reads from the Lakehouse table directly via HTTPS.
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
# OLD: dbSendQuery(con, query) + dbFetch + dbClearResult
# NEW: query_tables(conn, query) via Fabric OneLake SQL
fetch_data <- function(query) {
  query_tables(conn, query)
}


