#' List tables in a Fabric Lakehouse
#'
#' Returns the names of all user tables (excluding internal views
#' prefixed with \code{_vw_}) in the connected Lakehouse.
#' Works with both OneLake (\code{fabric_connection}) and
#' SQL (\code{DBIConnection}) connections.
#'
#' @param conn A \code{fabric_connection} or \code{DBIConnection} object
#'   created by \code{\link{connect_to_fabric}}.
#'
#' @return A character vector of table names.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' list_tables(conn)
#' conn <- connect_to_fabric(auth = "sp_vault")
#' list_tables(conn)
#' }
#' @export
list_tables <- function(conn) {
  if (inherits(conn, "DBIConnection")) {
    result <- DBI::dbGetQuery(conn,
      "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES ORDER BY TABLE_NAME")
    tabs <- result$TABLE_NAME[!grepl(
      "^(_vw_|_mat_|dm_|sys|exec_|managed_|external_|sql_pool|frequently|long_running)",
      result$TABLE_NAME, ignore.case = TRUE)]
    return(tabs)
  }

  token <- .get_fabric_token(conn$fabric_tenant, conn$access_token)
  url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables?recursive=true&maxResults=1000&resource=filesystem",
    conn$workspace_id, conn$lakehouse_id
  )
  resp <- httr::GET(url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  if (httr::status_code(resp) != 200) {
    return(character(0))
  }
  data <- httr::content(resp)
  if (is.null(data$paths) || length(data$paths) == 0) {
    return(character(0))
  }
  all_names <- vapply(data$paths, function(x) if (is.null(x$name)) "" else x$name, character(1))
  table_paths <- sub("/[^/]+$", "", sub(".*/Tables/", "", all_names))
  table_paths <- unique(table_paths[nchar(table_paths) > 0])
  table_paths <- grep("^_", table_paths, value = TRUE, invert = TRUE)
  sort(gsub("/", ".", table_paths))
}
