# Test delegated Fabric access from R
# Usage: Rscript test-r-access.R   OR   source("test-r-access.R") in RStudio
# No setup needed -- token is fetched automatically from the VM.

cat("UZIMA Fabric Access Test\n")
cat("========================\n\n")
library(fabriconnect)

# --- Primary lakehouse (uzima_db_backup) ---
cat("1. Primary lakehouse (uzima_db_backup)\n")
conn <- connect_to_fabric()
tables <- list_tables(conn)
cat(sprintf("   %d tables found\n\n", length(tables)))

# --- HCW fitbit shortcut ---
cat("2. HCW_fitbit_data (shortcut)\n")
conn2 <- connect_to_fabric(lakehouse_id = "65058b40-a60c-4267-a882-9263e0ba0617")
tables2 <- list_tables(conn2)
cat(sprintf("   %d tables found\n", length(tables2)))
cat(paste("   -", tables2, collapse = "\n"), "\n\n")

# --- Qualtrics shortcut ---
cat("3. Qualtrics (shortcut)\n")
conn3 <- connect_to_fabric(lakehouse_id = "8bb92d0b-3f94-4bd1-94d4-b31b088e9061")
tables3 <- list_tables(conn3)
cat(sprintf("   %d tables found\n", length(tables3)))
cat(paste("   -", tables3, collapse = "\n"), "\n")

cat("\nDONE - All lakehouses accessible.\n")
