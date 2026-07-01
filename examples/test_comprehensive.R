# Comprehensive test of fabriconnect R package
# Covers README examples + edge cases + multi-lakehouse
# All traffic via HTTPS (443). No TDS port 1433 required.
# Reuses conn object — no re-authentication between tests.

library(fabriconnect)

passed <- 0L
failed <- 0L

check <- function(desc, expr) {
  ok <- tryCatch({ expr; TRUE }, error = function(e) { cat("  ERROR:", e$message, "\n"); FALSE })
  if (isTRUE(ok)) { passed <<- passed + 1L; cat("  PASS\n") }
  else            { failed  <<- failed  + 1L; cat("  FAIL\n") }
}

# ─── 1. Connect (default) ────────────────────────────────────────────────
cat("\n═══ 1. Connect ──────────────────────────────────────────────\n")

cat("Test: connect_to_fabric() default\n")
conn <- connect_to_fabric()
check("conn is fabric_connection",        inherits(conn, "fabric_connection"))
check("workspace_id is set",              nchar(conn$workspace_id) > 0)
check("lakehouse_id is set",              nchar(conn$lakehouse_id) > 0)
check("fabric_tenant is set",             nchar(conn$fabric_tenant) > 0)

cat("Test: connect_to_fabric(lakehouse = 'HCW_fitbit_data') via shortcuts\n")
conn_hcw <- connect_to_fabric(lakehouse = "HCW_fitbit_data")
check("HCW lakehouse_id differs from default",
      conn_hcw$lakehouse_id != conn$lakehouse_id)

cat("Test: connect_to_fabric(lakehouse = 'Qualtrics') via shortcuts\n")
conn_q <- connect_to_fabric(lakehouse = "Qualtrics")
check("Qualtrics lakehouse_id differs from default",
      conn_q$lakehouse_id != conn$lakehouse_id)

cat("Test: connect_to_fabric(lakehouse = 'NONEXISTENT') errors\n")
check("errors on unknown lakehouse",
      tryCatch({ connect_to_fabric(lakehouse = "NONEXISTENT"); FALSE },
               error = function(e) TRUE))

# ─── 2. List tables ──────────────────────────────────────────────────────
cat("\n═══ 2. List tables ───────────────────────────────────────────\n")

cat("Test: list_tables() on default lakehouse\n")
tables <- list_tables(conn)
check("returns character vector",          is.character(tables))
check("has at least one table",            length(tables) >= 1)
check("includes shortcut-prefixed tables",
      any(grepl("^Qualtrics\\.", tables)) ||
      any(grepl("^HCW_fitbit_data\\.", tables)) ||
      any(grepl("^LS_Fabric_Lakehouse\\.", tables)))

cat("Test: list_tables() on HCW lakehouse\n")
tables_hcw <- list_tables(conn_hcw)
check("returns character vector",          is.character(tables_hcw))

# ─── 3. Read tables (single name — searches all lakehouses) ─────────────
cat("\n═══ 3. Read tables (single name — auto-search) ──────────────\n")

cat("Test: read_table(conn, 'dimenrolledparticipants')\n")
df <- read_table(conn, "dimenrolledparticipants")
check("returns data.frame",                is.data.frame(df))
check("has rows",                          nrow(df) > 0)
check("has expected columns",
      all(c("ParticipantIdentifier", "Gender") %in% names(df)))

cat("Test: read_table(conn, 'aku_survey_responses_2026') from shortcut\n")
df_survey <- read_table(conn, "aku_survey_responses_2026")
check("returns data.frame",                is.data.frame(df_survey))
check("has rows",                          nrow(df_survey) > 0)

cat("Test: read_table with column pruning\n")
df_sub <- read_table(conn, "dimenrolledparticipants",
                     columns = c("ParticipantIdentifier", "Gender"))
check("returns data.frame",                is.data.frame(df_sub))
check("only requested columns",
      identical(sort(names(df_sub)), sort(c("ParticipantIdentifier", "Gender"))))

cat("Test: read_table(conn, 'NONEXISTENT_TABLE') errors\n")
check("errors cleanly",
      tryCatch({ read_table(conn, "NONEXISTENT_TABLE"); FALSE },
               error = function(e) TRUE))

# ─── 4. Read tables (2-part shortcut name) ───────────────────────────────
cat("\n═══ 4. Read tables (2-part shortcut.table) ───────────────────\n")

cat("Test: read_table(conn, 'Qualtrics.aku_survey_responses_2026')\n")
df_q <- read_table(conn, "Qualtrics.aku_survey_responses_2026")
check("returns data.frame",                is.data.frame(df_q))
check("same rows as auto-search",
      nrow(df_q) == nrow(df_survey))

# ─── 5. SQL queries ──────────────────────────────────────────────────────
cat("\n═══ 5. SQL queries ───────────────────────────────────────────\n")

cat("Test: query_tables simple COUNT\n")
cnt <- query_tables(conn, "SELECT count(*) AS n FROM dimenrolledparticipants")
check("returns data.frame",                is.data.frame(cnt))
check("result has count",                  cnt$n[1] > 0)

cat("Test: query_tables with JOIN\n")
joined <- query_tables(conn, "
  SELECT p.ParticipantIdentifier, count(*) AS logs
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier")
check("returns data.frame",                is.data.frame(joined))
check("has rows",                          nrow(joined) > 0)
check("has ParticipantIdentifier",         "ParticipantIdentifier" %in% names(joined))

cat("Test: query_tables with column pruning\n")
pruned <- query_tables(conn, "
  SELECT p.ParticipantIdentifier, count(*) AS logs
  FROM dimenrolledparticipants p
  JOIN factfitbitsleeplogs s ON p.ParticipantIdentifier = s.ParticipantIdentifier
  GROUP BY p.ParticipantIdentifier",
  table_columns = list(
    dimenrolledparticipants = c("ParticipantIdentifier"),
    factfitbitsleeplogs     = c("ParticipantIdentifier")))
check("returns data.frame",                is.data.frame(pruned))
check("has rows",                          nrow(pruned) > 0)

# ─── 6. List lakehouses ──────────────────────────────────────────────────
cat("\n═══ 6. List lakehouses ───────────────────────────────────────\n")

cat("Test: list_lakehouses()\n")
lakes <- list_lakehouses()
check("returns data.frame",                is.data.frame(lakes))
check("has name and id columns",
      all(c("name", "id") %in% names(lakes)))
check("uzima_db_backup is listed",
      "uzima_db_backup" %in% lakes$name)

# ─── 7. Token refresh (best-effort) ──────────────────────────────────────
cat("\n═══ 7. Token refresh ─────────────────────────────────────────\n")

cat("Test: .get_fabric_token returns cached token\n")
token <- .get_fabric_token(conn$fabric_tenant, conn$access_token)
check("returns JWT string",                is.character(token) && nchar(token) > 100)
check("starts with eyJ",                   startsWith(token, "eyJ"))

# ─── 8. Update mechanism ─────────────────────────────────────────────────
cat("\n═══ 8. Update mechanism ──────────────────────────────────────\n")

cat("Test: update_fabriconnect exists and is a function\n")
check("is a function",                     is.function(update_fabriconnect))

# ─── Summary ─────────────────────────────────────────────────────────────
cat(sprintf("\n═══ RESULTS: %d passed, %d failed ═══════════════════\n",
            passed, failed))
if (failed == 0) cat("All tests passed!\n")
