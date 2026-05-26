#' Read a Delta table from a Fabric Lakehouse
#'
#' Downloads the parquet files backing a Delta table and returns them
#' as a \code{data.frame}. Previous downloads for the same table are
#' cleaned up automatically before each call.
#'
#' For large tables (\strong{>1 GB}) use the \code{columns} parameter to
#' select only the columns you need. For very large tables (>100 GB)
#' consider using Python's \code{deltalake} which reads directly from
#' OneLake without downloading to disk.
#'
#' @param conn       A \code{fabric_connection} object.
#' @param table_name Character. Name of the table to read.
#' @param columns    Character vector. Optional column names to select.
#'   Reduces download size and memory usage. Passed to
#'   \code{arrow::read_parquet(col_select = ...)}.
#'
#' @return A \code{data.frame} with the table contents.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' df <- read_table(conn, "dimenrolledparticipants")
#' head(df)
#' # Read only 3 columns (much faster for wide tables)
#' df2 <- read_table(conn, "factfitbitsleeplogs",
#'                   columns = c("ParticipantKey", "MinutesAsleep"))
#' }
#' @export
read_table <- function(conn, table_name, columns = NULL) {
  local_dir <- file.path(tempdir(), "fabriconnect", table_name)
  unlink(local_dir, recursive = TRUE)
  dir.create(local_dir, showWarnings = FALSE, recursive = TRUE)

  table_path <- file.path(conn$lakehouse_id, "Tables", table_name)
  files <- list_storage_files(conn$fs, table_path)
  parquet_files <- files$name[grepl("\\.parquet$", files$name)]
  if (length(parquet_files) == 0) {
    stop("No parquet files found for table '", table_name, "'")
  }

  local_files <- vapply(parquet_files, function(f) {
    local_path <- file.path(local_dir, basename(f))
    download_blob(conn$fs, f, local_path, overwrite = TRUE)
    local_path
  }, character(1))

  if (!is.null(columns)) {
    tables <- lapply(local_files, function(f) read_parquet(f, col_select = columns))
  } else {
    tables <- lapply(local_files, read_parquet)
  }

  out <- tables[[1]]
  if (length(tables) > 1) {
    for (i in 2:length(tables)) {
      out <- rbind(out, tables[[i]])
    }
  }
  out
}
