#' Read a Delta table from a Fabric Lakehouse
#'
#' Lists parquet files via the OneLake DFS REST API and downloads them
#' directly into memory — no temp files written to disk.
#'
#' For large tables (\strong{>1 GB}) use the \code{columns} parameter to
#' select only the columns you need. For very large tables (>100 GB)
#' consider using Python's \code{deltalake} which supports storage-level
#' predicate pushdown (only requested bytes cross the network).
#'
#' @param conn       A \code{fabric_connection} object.
#' @param table_name Character. Name of the table to read.
#' @param columns    Character vector. Optional column names to select.
#'   Passed to \code{arrow::read_parquet(col_select = ...)} after download.
#'
#' @return A \code{data.frame} with the table contents.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' df <- read_table(conn, "dimenrolledparticipants")
#' head(df)
#' df2 <- read_table(conn, "factfitbitsleeplogs",
#'                   columns = c("ParticipantKey", "MinutesAsleep"))
#' }
#' @export
read_table <- function(conn, table_name, columns = NULL) {
  token <- .get_fabric_token(conn$fabric_tenant)

  # List parquet files via OneLake DFS API
  list_url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables/%s?recursive=true&maxResults=1000&resource=filesystem",
    conn$workspace_id, conn$lakehouse_id, table_name
  )
  resp <- httr::GET(list_url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  httr::stop_for_status(resp)
  data <- httr::content(resp)
  parquet_paths <- grep(
    "\\.parquet$",
    sapply(data$paths, `[[`, "name"),
    value = TRUE
  )
  # Exclude Delta transaction log files
  parquet_paths <- grep("/_delta_log/", parquet_paths, value = TRUE, invert = TRUE)
  if (length(parquet_paths) == 0) {
    stop("No parquet files found for table '", table_name, "'")
  }

  # Download each parquet file directly into memory
  base_url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s",
    conn$workspace_id
  )
  tbls <- lapply(parquet_paths, function(p) {
    file_url <- file.path(base_url, p)
    resp <- httr::GET(file_url, httr::add_headers(
      Authorization = paste("Bearer", token)
    ))
    httr::stop_for_status(resp)
    raw_data <- httr::content(resp, as = "raw")
    if (!is.null(columns)) {
      arrow::read_parquet(raw_data, col_select = columns)
    } else {
      arrow::read_parquet(raw_data)
    }
  })

  out <- if (length(tbls) > 1) arrow::concat_tables(tbls) else tbls[[1]]
  as.data.frame(out)
}
