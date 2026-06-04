# ============================================================================
# HCW Student Survey Analysis
# Uses fabriconnect to read from Fabric Lakehouse via HTTPS (port 443).
# No ODBC, no TDS, no hardcoded credentials.
#
# Prerequisites:
#   1. az login --tenant a5d4252a-02f9-4e60-96f0-9733baae4919 --use-device-code
#   2. remotes::install_github("AKU-CDIO/fabric-inbound-access",
#        subdir = "fabriconnect", force = TRUE, upgrade_dependencies = FALSE)
# ============================================================================

rm(list = ls())

library(fabriconnect)
library(dplyr)
library(readr)
library(summarytools)

# ---- Connect & read ----
conn <- connect_to_fabric()
baseline <- fabriconnect::read_table(conn, "qualtrics_hcw_student_survey", overwrite = TRUE)
cat("Rows:", nrow(baseline), "  Cols:", ncol(baseline), "\n")

View(baseline)
write_csv(baseline, "baseline.csv")

# ---- Filter ----
baseline_filtered <- baseline |>
  dplyr::filter(Consent3 == 1)
cat("Consented:", nrow(baseline_filtered), "participants\n")

# ---- Descriptives ----
summarise(baseline_filtered)

freq(baseline_filtered$monthlyincome)

print(table(baseline_filtered$Age, useNA = "ifany"))

print(summary(baseline$Age))

baseline_filtered$Age

print(summary(baseline_filtered$Age))

# ---- Utility ----
fetch_data <- function(query) {
  query_tables(conn, query)
}

cat("\nDone. HTTPS only (443).\n")
