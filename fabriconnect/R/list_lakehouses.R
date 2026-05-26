#' List all Lakehouses in the Fabric workspace
#'
#' Calls the Fabric REST API to discover all Lakehouse items. Returns
#' their display names and GUIDs so you can connect to any of them.
#'
#' @param workspace_id  Character. The Fabric workspace GUID.
#' @param fabric_tenant Character. The Fabric tenant ID.
#'
#' @return A data.frame with columns \code{name} and \code{id}.
#'
#' @examples
#' \dontrun{
#' lakehouses <- list_lakehouses()
#' print(lakehouses)
#' conn <- connect_to_fabric(lakehouse_id = lakehouses$id[1])
#' }
#' @export
list_lakehouses <- function(
  workspace_id  = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  fabric_tenant = "a5d4252a-02f9-4e60-96f0-9733baae4919"
) {
  token <- system(
    paste("az.cmd account get-access-token",
          "--resource https://api.fabric.microsoft.com",
          "--tenant", fabric_tenant,
          "--query accessToken -o tsv"),
    intern = TRUE
  )
  if (length(token) == 0 || nchar(token[1]) == 0) {
    stop("Failed to obtain Fabric API token.")
  }
  url <- sprintf("https://api.fabric.microsoft.com/v1/workspaces/%s/items",
                 workspace_id)
  resp <- httr::GET(url, httr::add_headers(Authorization = paste("Bearer", token[1])))
  httr::stop_for_status(resp)
  items <- httr::content(resp)$value
  lakes <- list()
  for (item in items) {
    if (item$type == "Lakehouse") {
      lakes <- c(lakes, list(data.frame(
        name = item$displayName,
        id   = item$id,
        stringsAsFactors = FALSE
      )))
    }
  }
  do.call(rbind, lakes)
}
