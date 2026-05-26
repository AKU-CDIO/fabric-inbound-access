#' Connect to a Microsoft Fabric Lakehouse via OneLake
#'
#' Authenticates to OneLake using Azure CLI and returns a connection object
#' that can be used with \code{list_tables()} and \code{read_table()}.
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
  workspace_id  = "67f69cc9-00c9-4c9c-a85b-38fc30774b7b",
  lakehouse_id  = "67596566-8ea9-4fd6-a451-ca9654aa4f10",
  fabric_tenant = "a5d4252a-02f9-4e60-96f0-9733baae4919"
) {
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
