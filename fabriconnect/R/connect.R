#' Connect to a Microsoft Fabric Lakehouse via OneLake
#'
#' Authenticates to OneLake using Azure CLI and returns a connection object
#' that can be used with \code{list_tables()} and \code{read_table()}.
#' Defaults are read from the bundled configuration file.
#'
#' @param workspace_id   Character. The Fabric workspace GUID.
#' @param lakehouse_id   Character. The Lakehouse item GUID (ignored if
#'   \code{lakehouse_name} is given).
#' @param lakehouse_name Character. Lakehouse display name (e.g. \code{"HCW_fitbit_data"}).
#'   Auto-resolved to GUID via the Fabric REST API. Overrides \code{lakehouse_id}.
#' @param fabric_tenant  Character. The Fabric tenant ID.
#'
#' @return An object of class \code{"fabric_connection"} containing the
#'   authenticated storage container and identifiers.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' conn <- connect_to_fabric(lakehouse_name = "HCW_fitbit_data")
#' list_tables(conn)
#' }
#' @export
connect_to_fabric <- function(
  workspace_id   = NULL,
  lakehouse_id   = NULL,
  lakehouse_name = NULL,
  fabric_tenant  = NULL
) {
  cfg <- .load_config()
  if (is.null(workspace_id))  workspace_id  <- cfg$workspace_guid
  if (is.null(fabric_tenant)) fabric_tenant <- cfg$fabric_tenant

  if (!is.null(lakehouse_name)) {
    lakes <- list_lakehouses(workspace_id = workspace_id,
                             fabric_tenant = fabric_tenant)
    idx <- which(lakes$name == lakehouse_name)
    if (length(idx) == 0) {
      stop("Lakehouse '", lakehouse_name, "' not found in workspace. ",
           "Use list_lakehouses() to see available names.")
    }
    lakehouse_id <- lakes$id[idx[1]]
  }
  if (is.null(lakehouse_id)) lakehouse_id <- cfg$lakehouse_guid

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
