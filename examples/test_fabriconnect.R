# Test: Connect to Fabric Lakehouse via OneLake + SQL JOIN example
# Copy this file to your working directory and run it.
# No ODBC/TDS needed -- all traffic is HTTPS (port 443).
#
# Prerequisites:
#   1. Azure login: az login --tenant a5d4252a-... --use-device-code
#   2. R packages: fabriconnect, duckdb (optional for SQL)
#   3. Access to the Fabric workspace (IP firewall or public)

# ---- 1. Install fabriconnect (run once) ----
# In R:
# install.packages(c("AzureStor", "arrow", "DBI", "httr", "jsonlite"))
# install.packages("remotes")
# remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect")

# ---- 2. Load ----
library(fabriconnect)

# ---- 3. Connect to Lakehouse (IDs from bundled config.json) ----
conn <- connect_to_fabric()

# ---- 4. List tables ----
tables <- list_tables(conn)
cat("Tables found:", length(tables), "\n")
print(tables)

# ---- 5. Read a table directly ----
df <- read_table(conn, "dimenrolledparticipants")
cat("\nParticipants:", nrow(df), "rows,", ncol(df), "cols\n")
head(df[, 1:6])

# ---- 6. SQL JOIN via query_tables() ----
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier,
           p.Gender,
           p.Age,
           COUNT(s.Skey)          AS sleep_logs,
           AVG(s.MinutesAsleep)   AS avg_min_asleep,
           AVG(s.MinutesInBed)    AS avg_min_in_bed
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier, p.Gender, p.Age
    ORDER BY sleep_logs DESC
")

cat("\nSleep summary per participant (top 10):\n")
cat("Rows:", nrow(result), "Cols:", ncol(result), "\n")
print(head(result, 10))

# ---- 7. Another query: demographics ----
demo <- query_tables(conn, "
    SELECT Gender,
           COUNT(*)     AS total,
           AVG(Age)     AS avg_age,
           MIN(Age)     AS min_age,
           MAX(Age)     AS max_age
    FROM dimenrolledparticipants
    WHERE Gender IS NOT NULL
    GROUP BY Gender
")
cat("\nDemographics:\n")
print(demo)

# ---- 8. Discover all Lakehouses ----
lakes <- list_lakehouses()
cat("\nLakehouses in workspace:\n")
print(lakes)

# ---- 9. Connect to a different Lakehouse ----
# conn2 <- connect_to_fabric(lakehouse_id = lakes$id[2])

# ---- 10. Where does this work? ----
cat("\n--- About access scope ---\n")
cat("This script works from ANY machine where:\n")
cat("  1. Azure CLI is installed and logged in (az login --use-device-code)\n")
cat("  2. The user has access to the Fabric workspace\n")
cat("  3. The machine's IP is in the workspace firewall allowlist\n")
cat("    (or the workspace is set to 'Public (all)')\n")
cat("\nIf the IP firewall is 'Selected networks' with only this VM's IP,\n")
cat("then these packages will NOT work from other machines.\n")
cat("If set to 'Public (all)', they work from anywhere with valid login.\n")
cat("\nAll traffic is HTTPS (443). No TDS port 1433 required.\n")

cat("\nDone.\n")
