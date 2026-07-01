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
  token <- .get_fabric_token(conn$fabric_tenant, conn$access_token)
  cfg <- .load_config()

  # Tables from the connected lakehouse
  all_tables <- character(0)
  url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables?recursive=true&maxResults=1000&resource=filesystem",
    conn$workspace_id, conn$lakehouse_id
  )
  resp <- httr::GET(url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  if (httr::status_code(resp) == 200) {
    data <- httr::content(resp)
    if (!is.null(data$paths) && length(data$paths) > 0) {
      all_names <- vapply(data$paths, function(x) if (is.null(x$name)) "" else x$name, character(1))
      delta_paths <- grep("/_delta_log/", all_names, value = TRUE)
      raw <- unique(sub("/_delta_log/.*", "", sub(".*/Tables/", "", delta_paths)))
      raw <- grep("^_", raw, value = TRUE, invert = TRUE)
      all_tables <- gsub("/", ".", raw)
    }
  }

  # Tables from shortcut lakehouses (prefix with shortcut name)
  for (sc_name in names(cfg$shortcuts)) {
    sc_id <- cfg$shortcuts[[sc_name]]
    sc_url <- sprintf(
      "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables?recursive=true&maxResults=1000&resource=filesystem",
      conn$workspace_id, sc_id
    )
    sc_resp <- httr::GET(sc_url, httr::add_headers(
      Authorization = paste("Bearer", token),
      Accept = "application/json;charset=utf-8",
      "x-ms-version" = "2024-08-04"
    ))
    if (httr::status_code(sc_resp) == 200) {
      sc_data <- httr::content(sc_resp)
      if (!is.null(sc_data$paths) && length(sc_data$paths) > 0) {
        sc_names <- vapply(sc_data$paths, function(x) if (is.null(x$name)) "" else x$name, character(1))
        sc_delta <- grep("/_delta_log/", sc_names, value = TRUE)
        sc_raw <- unique(sub("/_delta_log/.*", "", sub(".*/Tables/", "", sc_delta)))
        sc_raw <- grep("^_", sc_raw, value = TRUE, invert = TRUE)
        sc_tables <- paste0(sc_name, ".", gsub("/", ".", sc_raw))
        all_tables <- c(all_tables, sc_tables)
      }
    }
  }

  sort(unique(all_tables))
}
