# Test delegated Fabric access from R
# Usage: Rscript test-r-access.R   OR   source("test-r-access.R") in RStudio
# No setup needed -- token is fetched automatically from the VM.

cat("UZIMA Fabric Access Test\n")
cat("========================\n\n")

library(fabriconnect)
conn <- connect_to_fabric()
tables <- list_tables(conn)
cat(sprintf("PASS: Found %d tables\n", length(tables)))
cat("First 10:\n")
for (t in head(tables, 10)) {
  cat(sprintf("  - %s\n", t))
}
cat("\nDONE - You're ready to use fabriconnect!\n")
