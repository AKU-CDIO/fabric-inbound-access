#' List tables in a Fabric Lakehouse
#'
#' Returns the names of all user tables (excluding internal views
#' prefixed with \code{_vw_}) in the connected Lakehouse.
#'
#' @param conn A \code{fabric_connection} object created by
#'   \code{\link{connect_to_fabric}}.
#'
#' @return A character vector of table names.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' list_tables(conn)
#' }
#' @export
list_tables <- function(conn) {
  items <- list_storage_files(
    conn$fs,
    file.path(conn$lakehouse_id, "Tables")
  )
  all_names <- basename(items$name[items$isdir])
  all_names[!grepl("^_", all_names)]
}
