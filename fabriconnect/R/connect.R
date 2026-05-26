#' Connect to a Microsoft Fabric Lakehouse via OneLake
#'
#' Authenticates to OneLake using Azure CLI and returns a connection object
#' that can be used with \code{list_tables()} and \code{read_table()}.
#' Defaults are read from the bundled configuration file.
#'
#' @param workspace_id   Character. The Fabric workspace GUID.
#' @param lakehouse_id   Character. The Lakehouse item GUID.
#' @param fabric_tenant  Character. The Fabric tenant ID.
#'
#' @return An object of class \code{"fabric_connection"} containing the
#'   authenticated storage container and identifiers.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' list_tables(conn)
#' }
#' @export
connect_to_fabric <- function(
  workspace_id  = NULL,
  lakehouse_id  = NULL,
  fabric_tenant = NULL
) {
  cfg <- .load_config()
  if (is.null(workspace_id))  workspace_id  <- cfg$workspace_guid
  if (is.null(lakehouse_id))  lakehouse_id  <- cfg$lakehouse_guid
  if (is.null(fabric_tenant)) fabric_tenant <- cfg$fabric_tenant
  token <- .get_fabric_token(fabric_tenant)
  ad <- storage_endpoint("https://onelake.dfs.fabric.microsoft.com", token = token)
  fs <- storage_container(ad, workspace_id)
  structure(
    list(fs = fs, workspace_id = workspace_id, lakehouse_id = lakehouse_id,
         fabric_tenant = fabric_tenant),
    class = "fabric_connection"
  )
}

#' @noRd
.get_fabric_token <- function(tenant) {
  cmd <- paste(
    "az.cmd account get-access-token",
    "--resource https://storage.azure.com",
    "--tenant", tenant,
    "--query accessToken -o tsv"
  )
  token <- system(cmd, intern = TRUE)
  if (length(token) == 0 || nchar(token[1]) == 0) {
    stop(paste0("Failed to obtain Azure access token. ",
                "Make sure you are logged in with 'az login'."))
  }
  token[1]
}

#' @noRd
.load_config <- function() {
  jsonlite::fromJSON(
    system.file("config.json", package = "fabriconnect")
  )
}
