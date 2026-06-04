#' List all Lakehouses in the Fabric workspace
#'
#' Calls the Fabric REST API to discover all Lakehouse items. Returns
#' their display names and GUIDs so you can connect to any of them.
#' Supports multiple authentication methods (checked in order):
#' \enumerate{
#'   \item Explicit \code{access_token} parameter
#'   \item \code{FABRIC_ACCESS_TOKEN} environment variable
#'   \item Fabric CLI (\code{fab token})
#'   \item Azure CLI (\code{az account get-access-token})
#' }
#' Defaults are read from the bundled configuration file.
#'
#' @param workspace_id  Character. The Fabric workspace GUID.
#' @param fabric_tenant Character. The Fabric tenant ID.
#' @param access_token  Character. An existing access token for the Fabric API
#'   (\code{https://api.fabric.microsoft.com}).
#'
#' @return A data.frame with columns \code{name} and \code{id}.
#'
#' @examples
#' \dontrun{
#' lakehouses <- list_lakehouses()
#' print(lakehouses)
#' conn <- connect_to_fabric(lakehouse_id = lakes$id[1])
#' }
#' @export
list_lakehouses <- function(
  workspace_id  = NULL,
  fabric_tenant = NULL,
  access_token  = NULL
) {
  cfg <- .load_config()
  if (is.null(workspace_id))  workspace_id  <- cfg$workspace_guid
  if (is.null(fabric_tenant)) fabric_tenant <- cfg$fabric_tenant
  token <- .get_fabric_api_token(fabric_tenant, access_token)
  url <- sprintf("https://api.fabric.microsoft.com/v1/workspaces/%s/items",
                 workspace_id)
  resp <- httr::GET(url, httr::add_headers(Authorization = paste("Bearer", token)))
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

#' @noRd
.get_fabric_api_token <- function(tenant, access_token = NULL) {
  if (!is.null(access_token) && nchar(access_token) > 0) {
    return(access_token)
  }
  env_token <- Sys.getenv("FABRIC_ACCESS_TOKEN")
  if (nchar(env_token) > 0) {
    return(env_token)
  }
  fab_token <- tryCatch(
    system("fab token", intern = TRUE),
    warning = function(w) NULL, error = function(e) NULL
  )
  if (!is.null(fab_token) && length(fab_token) > 0 && nchar(fab_token[1]) > 0) {
    return(fab_token[1])
  }
  token <- system(
    paste("az.cmd account get-access-token",
          "--resource https://api.fabric.microsoft.com",
          "--tenant", tenant,
          "--query accessToken -o tsv"),
    intern = TRUE
  )
  if (length(token) > 0 && nchar(token[1]) > 0) {
    return(token[1])
  }
  stop(
    "No authentication method available for Fabric API.\n",
    "  Options:\n",
    "    1. Pass access_token = \"...\" to list_lakehouses()\n",
    "    2. Set FABRIC_ACCESS_TOKEN environment variable\n",
    "    3. Install Fabric CLI and run 'fab login'\n",
    "    4. Run 'az login --tenant ", tenant, " --use-device-code'"
  )
}
