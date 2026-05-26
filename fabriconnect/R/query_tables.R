#' Run a SQL query across Lakehouse tables using DuckDB
#'
#' Fetches the referenced tables from the Lakehouse and runs a SQL query
#' on them using DuckDB. Table names are automatically extracted from
#' \code{FROM} and \code{JOIN} clauses.
#'
#' @param conn A \code{fabric_connection} object.
#' @param sql  Character. SQL query. Use table names directly
#'   (e.g. \code{SELECT * FROM dimdate}).
#'
#' @return A \code{data.frame} with the query results.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' result <- query_tables(conn,
#'   "SELECT p.ParticipantIdentifier, COUNT(s.Skey) AS n
#'    FROM dimenrolledparticipants p
#'    JOIN factfitbitsleeplogs s ON p.Skey = s.ParticipantKey
#'    GROUP BY p.ParticipantIdentifier")
#' head(result)
#' }
#' @export
query_tables <- function(conn, sql) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required for SQL queries. Install with: install.packages('duckdb')")
  }
  tables <- unique(c(
    regmatches(sql, gregexpr("(?i)\\bFROM\\s+(\\w+)", sql, perl = TRUE))[[1]],
    regmatches(sql, gregexpr("(?i)\\bJOIN\\s+(\\w+)", sql, perl = TRUE))[[1]]
  ))
  tables <- gsub("(?i)^(FROM|JOIN)\\s+", "", tables, perl = TRUE)
  skip <- c("", "SELECT", "WHERE", "AND", "OR", "ON", "GROUP", "ORDER", "HAVING", "LIMIT", "AS",
            "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "NATURAL", "DISTINCT", "TOP",
            "BY", "DESC", "ASC", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
            "COUNT", "SUM", "AVG", "MIN", "MAX", "CAST", "COALESCE", "NULLIF",
            "TRUE", "FALSE", "WHEN", "THEN", "ELSE", "END", "CASE")
  tables <- setdiff(tables, skip)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  for (tbl in tables) {
    df <- read_table(conn, tbl)
    DBI::dbWriteTable(con, tbl, as.data.frame(df), overwrite = TRUE)
  }
  DBI::dbGetQuery(con, sql)
}
