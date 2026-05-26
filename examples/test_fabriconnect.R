# Test: Connect to Fabric Lakehouse via OneLake + SQL JOIN example
# Copy this file to your working directory and run it.
# No ODBC/TDS needed — all traffic is HTTPS (port 443).
#
# Prerequisites:
#   - R packages: AzureStor, arrow, duckdb (for SQL example)
#   - Azure CLI logged in: az login
#   - Access to the Fabric workspace (IP firewall or public)

# ---- 1. Install packages (run once) ----
# In terminal: R CMD INSTALL fabriconnect/
# Or in R:
# install.packages("fabriconnect/", repos = NULL, type = "source")

# ---- 2. Load ----
library(fabriconnect)
library(duckdb)

# ---- 3. Connect to Lakehouse ----
conn <- connect_to_fabric()

# ---- 4. List tables ----
tables <- list_tables(conn)
cat("Tables found:", length(tables), "\n")
print(tables)

# ---- 5. Read two tables ----
participants <- read_table(conn, "dimenrolledparticipants")
cat("Participants:", nrow(participants), "rows\n")

sleep <- read_table(conn, "factfitbitsleeplogs")
cat("Sleep logs:", nrow(sleep), "rows\n")

# ---- 6. SQL JOIN via DuckDB ----
con <- dbConnect(duckdb())
dbWriteTable(con, "p", participants)
dbWriteTable(con, "s", sleep)

sql <- "
SELECT p.ParticipantIdentifier,
       p.Gender,
       p.Age,
       COUNT(s.Skey)             AS sleep_logs,
       AVG(s.MinutesAsleep)      AS avg_min_asleep,
       AVG(s.MinutesInBed)       AS avg_min_in_bed
FROM p
JOIN s ON p.Skey = s.ParticipantKey
GROUP BY p.ParticipantIdentifier, p.Gender, p.Age
ORDER BY sleep_logs DESC
"

result <- dbGetQuery(con, sql)
dbDisconnect(con, shutdown = TRUE)

cat("\nSleep summary per participant:\n")
cat("Rows:", nrow(result), "Cols:", ncol(result), "\n")
print(head(result, 10))

# ---- 7. Where does this work? ----
cat("\n--- About access scope ---\n")
cat("This script works from ANY machine where:\n")
cat("  1. Azure CLI is installed and logged in (az login)\n")
cat("  2. The user has access to the Fabric workspace\n")
cat("  3. The machine's IP is in the workspace firewall allowlist\n")
cat("    (or the workspace is set to 'Public (all)')\n")
cat("\nIf the IP firewall is 'Selected networks' with only this VM's IP,\n")
cat("then these packages will NOT work from other machines.\n")
cat("If set to 'Public (all)', they work from anywhere with valid login.\n")
cat("\nThe OneLake endpoints used:\n")
cat("  - https://onelake.dfs.fabric.microsoft.com (HTTPS/443)\n")
cat("  - https://onelake.blob.fabric.microsoft.com (HTTPS/443)\n")
cat("No TDS port 1433 is required.\n")
