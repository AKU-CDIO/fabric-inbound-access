#' Read a Delta table from a Fabric Lakehouse
#'
#' Reads parquet data directly from OneLake into memory — no temp files
#' written to disk. Previous downloads for the same table are cleaned
#' up automatically before each call.
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
  table_path <- file.path(conn$lakehouse_id, "Tables", table_name)
  files <- list_storage_files(conn$fs, table_path)
  parquet_files <- files$name[grepl("\\.parquet$", files$name)]
  if (length(parquet_files) == 0) {
    stop("No parquet files found for table '", table_name, "'")
  }

  # Download directly into memory (no disk writes)
  tbls <- lapply(parquet_files, function(f) {
    raw_data <- download_blob(conn$fs, f, NULL)
    if (!is.null(columns)) {
      arrow::read_parquet(raw_data, col_select = columns)
    } else {
      arrow::read_parquet(raw_data)
    }
  })

  out <- if (length(tbls) > 1) arrow::concat_tables(tbls) else tbls[[1]]
  as.data.frame(out)
}
