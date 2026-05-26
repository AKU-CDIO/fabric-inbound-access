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
  token <- .get_fabric_token(conn$fabric_tenant)
  url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables?recursive=true&maxResults=1000&resource=filesystem",
    conn$workspace_id,
    conn$lakehouse_id
  )
  resp <- httr::GET(url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  httr::stop_for_status(resp)
  data <- httr::content(resp)
  paths <- sapply(data$paths, `[[`, "name")
  paths <- grep("/_delta_log/", paths, value = TRUE, invert = TRUE)
  tables <- unique(sub("/.*", "", sub(".*/Tables/", "", paths)))
  tables <- tables[nchar(tables) > 0 & !grepl("^_", tables)]
  sort(tables)
}
