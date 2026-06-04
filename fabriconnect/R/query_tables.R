query_tables <- function(conn, sql, table_columns = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required. Install with: install.packages('duckdb')")
  }
  is_multi <- !inherits(conn, "fabric_connection")

  # Extract table references from FROM and JOIN clauses.
  # For FROM: capture everything up to the next SQL clause keyword, then parse for table names.
  tables <- character(0)

  from_expr <- regmatches(sql, regexec(
    "(?i)\\bFROM\\s+(.+?)(?=\\s+(?:WHERE|GROUP|ORDER|HAVING|LIMIT|JOIN|CROSS|INNER|LEFT|RIGHT|FULL|UNION|EXCEPT|INTERSECT|$))",
    sql, perl = TRUE))[[1]][2]
  if (!is.na(from_expr)) {
    from_tables <- trimws(strsplit(from_expr, ",")[[1]])
    from_tables <- gsub("\\s+(AS\\s+)?\\w+.*$", "", from_tables, perl = TRUE)
    tables <- c(tables, from_tables)
  }

  join_matches <- regmatches(sql, gregexpr("(?i)\\bJOIN\\s+([\\w.]+)", sql, perl = TRUE))[[1]]
  join_tables <- gsub("(?i)^JOIN\\s+", "", join_matches)
  tables <- unique(c(tables, join_tables))
  # Remove empty strings
  tables <- tables[nchar(tables) > 0]

  db <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(db, shutdown = FALSE))

  for (tbl_ref in tables) {
    if (grepl("\\.", tbl_ref)) {
      parts <- strsplit(tbl_ref, "\\.")[[1]]
      schema <- parts[1]
      tbl <- parts[2]
    } else {
      if (is_multi) {
        stop(sprintf(
          "Table '%s' is not schema-qualified. Use schema.tablename (e.g. uzima.%s).",
          tbl_ref, tbl_ref))
      }
      schema <- NULL
      tbl <- tbl_ref
    }
    if (is_multi) {
      conn_use <- conn[[schema]]
      if (is.null(conn_use)) {
        stop(sprintf("No connection named '%s'. Available: %s",
                     schema, paste(names(conn), collapse = ", ")))
      }
    } else {
      conn_use <- conn
    }
    cols <- table_columns[[tbl_ref]]
    df <- read_table(conn_use, tbl, columns = cols)
    if (!is.null(schema)) {
      safe_name <- paste0("__", schema, "__", tbl)
      DBI::dbWriteTable(db, safe_name, as.data.frame(df), overwrite = TRUE)
      DBI::dbExecute(db, sprintf('CREATE SCHEMA IF NOT EXISTS "%s"', schema))
      DBI::dbExecute(db, sprintf('CREATE OR REPLACE VIEW "%s"."%s" AS SELECT * FROM "%s"',
                                 schema, tbl, safe_name))
    } else {
      DBI::dbWriteTable(db, tbl, as.data.frame(df), overwrite = TRUE)
    }
  }
  DBI::dbGetQuery(db, sql)
}
