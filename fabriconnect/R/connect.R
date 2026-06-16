#' Connect to a Microsoft Fabric Lakehouse via OneLake
#'
#' Authenticates to OneLake and returns a connection object
#' that can be used with \code{list_tables()} and \code{read_table()}.
#' Supports multiple authentication methods (checked in order):
#' \enumerate{
#'   \item Explicit \code{access_token} parameter
#'   \item \code{FABRIC_ACCESS_TOKEN} environment variable
#'   \item Azure CLI (\code{az account get-access-token})
#'   \item Interactive device-code login (sign in with your email — MFA supported)
#' }
#' Defaults are read from the bundled configuration file.
#'
#' @param workspace_id   Character. The Fabric workspace GUID.
#' @param lakehouse_id   Character. The Lakehouse item GUID (ignored if
#'   \code{lakehouse_name} is given).
#' @param lakehouse_name Character. Lakehouse display name (e.g. \code{"HCW_fitbit_data"}).
#'   Auto-resolved to GUID via the Fabric REST API. Overrides \code{lakehouse_id}.
#'   Can also be passed as the positional \code{lakehouse} argument.
#' @param lakehouse      Alias for \code{lakehouse_name}. Either works.
#' @param fabric_tenant  Character. The Fabric tenant ID.
#' @param access_token   Character. An existing access token for OneLake
#'   (\code{https://storage.azure.com}). When provided, no CLI is invoked.
#'
#' @return An object of class \code{"fabric_connection"} containing the
#'   workspace and lakehouse identifiers.
#'
#' @examples
#' \dontrun{
#' conn <- connect_to_fabric()
#' conn <- connect_to_fabric(lakehouse_name = "HCW_fitbit_data")
#' conn <- connect_to_fabric(lakehouse = "HCW_fitbit_data")      # same
#' conn <- connect_to_fabric(access_token = Sys.getenv("FABRIC_ACCESS_TOKEN"))
#' list_tables(conn)
#' }
#' @export
connect_to_fabric <- function(
  workspace_id   = NULL,
  lakehouse_id   = NULL,
  lakehouse      = NULL,
  lakehouse_name = NULL,
  fabric_tenant  = NULL,
  access_token   = NULL
) {
  cfg <- .load_config()
  if (is.null(workspace_id))  workspace_id  <- cfg$workspace_guid
  if (is.null(fabric_tenant)) fabric_tenant <- cfg$fabric_tenant

  # lakehouse is a shorthand alias for lakehouse_name
  if (is.null(lakehouse_name) && !is.null(lakehouse)) {
    lakehouse_name <- lakehouse
  }

  if (!is.null(lakehouse_name)) {
    lakes <- list_lakehouses(workspace_id = workspace_id,
                             fabric_tenant = fabric_tenant,
                             access_token = access_token)
    idx <- which(lakes$name == lakehouse_name)
    if (length(idx) == 0) {
      stop("Lakehouse '", lakehouse_name, "' not found in workspace. ",
           "Use list_lakehouses() to see available names.")
    }
    lakehouse_id <- lakes$id[idx[1]]
  }
  if (is.null(lakehouse_id)) lakehouse_id <- cfg$lakehouse_guid

  structure(
    list(workspace_id = workspace_id, lakehouse_id = lakehouse_id,
         fabric_tenant = fabric_tenant, access_token = access_token),
    class = "fabric_connection"
  )
}

#' @noRd
.get_fabric_token <- function(tenant, access_token = NULL) {
  # 1. Explicit token passed by user
  if (!is.null(access_token) && nchar(access_token) > 0) {
    return(access_token)
  }
  # 2. Environment variable
  env_token <- Sys.getenv("FABRIC_ACCESS_TOKEN")
  if (nchar(env_token) > 0) {
    return(env_token)
  }
  # 3. Interactive device-code login (email + MFA — like ODBC)
  msal_token <- .try_msal_device_code(tenant, "https://storage.azure.com")
  if (!is.null(msal_token)) {
    return(msal_token)
  }
  # 4. Azure CLI (fallback for automation / CI)
  raw <- suppressWarnings(system(
    paste("az.cmd account get-access-token",
          "--resource https://storage.azure.com",
          "--tenant", tenant,
          "--query accessToken -o tsv"),
    intern = TRUE, ignore.stderr = TRUE
  ))
  if (length(raw) > 0 && nchar(raw[1]) > 0 && grepl("^eyJ", raw[1])) {
    return(raw[1])
  }
  stop(
    "No authentication method available.\n",
    "  Options:\n",
    "    1. Pass access_token = \"...\" to connect_to_fabric()\n",
    "    2. Set FABRIC_ACCESS_TOKEN environment variable\n",
    "    3. Interactive device-code login (automatic — just follow the prompt)\n",
    "    4. Run 'az login --tenant ", tenant, " --use-device-code'"
  )
}

#' @noRd
.try_msal_device_code <- function(tenant, resource) {
  client_id <- "1950a258-227b-4e31-a9cf-717495945fc2"
  url_base <- sprintf("https://login.microsoftonline.com/%s", tenant)

  # Step 1: Initiate device-code flow
  dev_resp <- httr::POST(
    sprintf("%s/oauth2/v2.0/devicecode", url_base),
    body = list(
      client_id = client_id,
      scope = sprintf("%s/.default", resource)
    ),
    encode = "form"
  )
  if (httr::status_code(dev_resp) != 200L) {
    return(NULL)
  }
  dev <- httr::content(dev_resp)
  if (is.null(dev$user_code)) {
    return(NULL)
  }

  message(
    "\n====================  SIGN IN REQUIRED  ====================\n",
    "To access the Fabric Lakehouse, sign in with your email.\n",
    "This supports MFA (e.g. Outlook / Microsoft Authenticator).\n",
    "\n  1. Open: ", dev$verification_uri, "\n",
    "  2. Enter code: ", dev$user_code, "\n",
    "============================================================\n"
  )

  interval <- if (is.null(dev$interval)) 5L else dev$interval

  # Step 2: Poll for token
  for (i in 1:120) {
    Sys.sleep(interval)
    tok_resp <- httr::POST(
      sprintf("%s/oauth2/v2.0/token", url_base),
      body = list(
        grant_type = "urn:ietf:params:oauth:grant-type:device_code",
        client_id = client_id,
        device_code = dev$device_code
      ),
      encode = "form"
    )
    tok <- httr::content(tok_resp)

    if (!is.null(tok$access_token)) {
      message("Authentication successful.\n")
      return(tok$access_token)
    }

    err <- tok$error
    if (is.null(err) || identical(err, "authorization_pending")) {
      next
    }
    if (identical(err, "expired_token")) {
      message("Device code expired. Run connect_to_fabric() again to retry.")
      return(NULL)
    }
    if (identical(err, "access_denied")) {
      message("Authentication cancelled.")
      return(NULL)
    }
  }
  message("Authentication timed out (120 seconds). Run connect_to_fabric() to retry.")
  NULL
}

#' @noRd
.load_config <- function() {
  jsonlite::fromJSON(
    system.file("config.json", package = "fabriconnect")
  )
}
