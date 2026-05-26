# Test: Connect to Fabric Lakehouse via OneLake + SQL JOIN example
# No ODBC/TDS needed -- all traffic is HTTPS (port 443).
#
# Prerequisites:
#   1. az login --tenant a5d4252a-... --use-device-code
#   2. R packages: fabriconnect, duckdb (optional for SQL)
#   3. Access to the Fabric workspace (IP firewall or public)

# ---- 1. Install (run once) ----
# install.packages(c("AzureStor", "arrow", "DBI", "httr", "jsonlite"))
# install.packages("remotes")
# If "destination file exists", run: remove.packages("fabriconnect")
# remotes::install_github("AKU-CDIO/fabric-inbound-access", subdir = "fabriconnect",
#                         upgrade = "always", force = TRUE)

# ---- 2. Load ----
library(fabriconnect)

# ---- 3. Connect (IDs from bundled config.json) ----
conn <- connect_to_fabric()

# Alternative: connect by name
# conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")

# ---- 4. List tables ----
tables <- list_tables(conn)
cat("Tables found:", length(tables), "\n")
print(tables)

# ---- 5. Read a table ----
df <- read_table(conn, "dimenrolledparticipants")
cat("\nParticipants:", nrow(df), "rows,", ncol(df), "cols\n")
head(df[, 1:6])

# ---- 6. SQL JOIN ----
result <- query_tables(conn, "
    SELECT p.ParticipantIdentifier, p.Gender, p.Age,
           COUNT(s.Skey)        AS sleep_logs,
           AVG(s.MinutesAsleep) AS avg_min_asleep,
           AVG(s.MinutesInBed)  AS avg_min_in_bed
    FROM dimenrolledparticipants p
    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
    GROUP BY p.ParticipantIdentifier, p.Gender, p.Age
    ORDER BY sleep_logs DESC
")
cat("\nSleep summary per participant (top 10):\n")
print(head(result, 10))

# ---- 7. Demographics ----
demo <- query_tables(conn, "
    SELECT Gender, COUNT(*) AS total, AVG(Age) AS avg_age,
           MIN(Age) AS min_age, MAX(Age) AS max_age
    FROM dimenrolledparticipants
    WHERE Gender IS NOT NULL GROUP BY Gender
")
cat("\nDemographics:\n")
print(demo)

# ---- 8. Discover all Lakehouses ----
lakes <- list_lakehouses()
cat("\nLakehouses in workspace:\n")
print(lakes)

# ---- 9. Connect to a different Lakehouse by name ----
# conn2 <- connect_to_fabric(lakehouse = "HCW_fitbit_data")

# ---- 10. Access scope ----
cat("\nAll traffic is HTTPS (443). No TDS port 1433 required.\n")
cat("Done.\n")
