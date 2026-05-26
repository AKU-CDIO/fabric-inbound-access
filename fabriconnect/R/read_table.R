#' Read a Delta table from a Fabric Lakehouse
#'
#' Downloads the parquet files backing a Delta table and returns them
#' as a \code{data.frame}.
#'
#' @param conn       A \code{fabric_connection} object.
#' @param table_name Character. Name of the table to read.
#'
#' @return A \code{data.frame} with the table contents.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' df <- read_table(conn, "dimenrolledparticipants")
#' head(df)
#' }
#' @export
read_table <- function(conn, table_name) {
  table_path <- file.path(conn$lakehouse_id, "Tables", table_name)
  files <- list_storage_files(conn$fs, table_path)
  parquet_files <- files$name[grepl("\\.parquet$", files$name)]
  if (length(parquet_files) == 0) {
    stop("No parquet files found for table '", table_name, "'")
  }
  local_dir <- file.path(tempdir(), "fabriconnect", table_name)
  dir.create(local_dir, showWarnings = FALSE, recursive = TRUE)
  local_files <- vapply(parquet_files, function(f) {
    local_path <- file.path(local_dir, basename(f))
    download_blob(conn$fs, f, local_path)
    local_path
  }, character(1))
  tables <- lapply(local_files, read_parquet)
  out <- tables[[1]]
  if (length(tables) > 1) {
    for (i in 2:length(tables)) {
      out <- rbind(out, tables[[i]])
    }
  }
  out
}
