#' List all Lakehouses in the Fabric workspace
#'
#' Calls the Fabric REST API to discover all Lakehouse items. Returns
#' their display names and GUIDs so you can connect to any of them.
#' Supports multiple authentication methods (checked in order):
#' \enumerate{
#'   \item Explicit \code{access_token} parameter
#'   \item \code{FABRIC_ACCESS_TOKEN} environment variable
#'   \item Azure CLI (\code{az account get-access-token})
#'   \item Interactive device-code login (sign in with your email — MFA supported)
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

  cache_key <- paste0(tenant, ":https://api.fabric.microsoft.com")

  entry <- if (exists(cache_key, envir = .token_cache, inherits = FALSE)) {
    .token_cache[[cache_key]]
  } else {
    NULL
  }
  if (is.list(entry)) {
    if (Sys.time() < entry$expires_at) {
      return(entry$access_token)
    }
    if (!is.null(entry$refresh_token)) {
      refreshed <- .refresh_token(tenant, entry$refresh_token,
                                  "https://api.fabric.microsoft.com")
      if (!is.null(refreshed)) {
        .token_cache[[cache_key]] <- refreshed
        return(refreshed$access_token)
      }
    }
  }

  env_token <- Sys.getenv("FABRIC_ACCESS_TOKEN")
  if (nchar(env_token) > 0) {
    .token_cache[[cache_key]] <- list(
      access_token = env_token, refresh_token = NULL,
      expires_at = Sys.time() + 3300
    )
    return(env_token)
  }

  msal_result <- .try_msal_device_code(tenant, "https://api.fabric.microsoft.com")
  if (!is.null(msal_result)) {
    entry <- list(
      access_token = msal_result$access_token,
      refresh_token = msal_result$refresh_token,
      expires_at = Sys.time() + 3300
    )
    .token_cache[[cache_key]] <- entry
    return(entry$access_token)
  }

  raw <- suppressWarnings(system(
    paste("az.cmd account get-access-token",
          "--resource https://api.fabric.microsoft.com",
          "--tenant", tenant,
          "--query accessToken -o tsv"),
    intern = TRUE, ignore.stderr = TRUE
  ))
  if (length(raw) > 0 && nchar(raw[1]) > 0 && grepl("^eyJ", raw[1])) {
    .token_cache[[cache_key]] <- list(
      access_token = raw[1], refresh_token = NULL,
      expires_at = Sys.time() + 3300
    )
    return(raw[1])
  }
  stop(
    "No authentication method available for Fabric API.\n",
    "  Options:\n",
    "    1. Pass access_token = \"...\" to list_lakehouses()\n",
    "    2. Set FABRIC_ACCESS_TOKEN environment variable\n",
    "    3. Interactive device-code login (automatic)\n",
    "    4. Run 'az login --tenant ", tenant, " --use-device-code'"
  )
}
