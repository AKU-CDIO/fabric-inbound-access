#' Connect to a Microsoft Fabric Lakehouse via OneLake
#'
#' Authenticates to OneLake and returns a connection object
#' that can be used with \code{list_tables()} and \code{read_table()}.
#' Supports multiple authentication methods (checked in order):
#' \enumerate{
#'   \item Explicit \code{access_token} parameter
#'   \item \code{FABRIC_ACCESS_TOKEN}, \code{FABRIC_DELEGATED_ACCESS_TOKEN},
#'     or \code{AZURE_ACCESS_TOKEN} environment variable
#'   \item Interactive device-code login
#'   \item Azure CLI (\code{az account get-access-token})
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
  access_token <- .normalize_access_token(access_token, required = TRUE)

  # lakehouse is a shorthand alias for lakehouse_name
  if (is.null(lakehouse_name) && !is.null(lakehouse)) {
    lakehouse_name <- lakehouse
  }

  if (!is.null(lakehouse_name)) {
    lakehouse_id <- cfg$shortcuts[[lakehouse_name]]
    if (is.null(lakehouse_id)) {
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
  }
  if (is.null(lakehouse_id)) lakehouse_id <- cfg$lakehouse_guid

  structure(
    list(workspace_id = workspace_id, lakehouse_id = lakehouse_id,
         fabric_tenant = fabric_tenant, access_token = access_token),
    class = "fabric_connection"
  )
}

.token_cache <- new.env(parent = emptyenv())
.token_refresh_buffer_seconds <- 300

#' @noRd
.normalize_access_token <- function(access_token, required = FALSE) {
  if (is.null(access_token) || length(access_token) == 0) {
    return(NULL)
  }

  token <- trimws(access_token[[1]])
  token <- sub("(?i)^Bearer\\s+", "", token, perl = TRUE)

  if (is.na(token) || !nzchar(token)) {
    return(NULL)
  }
  if (!grepl("^eyJ", token)) {
    if (required) {
      stop("Access token must be a JWT. Paste only the token value or 'Bearer <token>'.")
    }
    return(NULL)
  }

  token
}

#' @noRd
.try_webhook_token <- function(tenant, resource) {
  cfg <- .load_config()

  webhook_url <- Sys.getenv("FABRIC_WEBHOOK_URL", unset = "")
  if (!nzchar(webhook_url)) {
    webhook_url <- cfg$automation$webhook_url
    if (is.null(webhook_url) || !nzchar(webhook_url)) return(NULL)
  }

  email <- Sys.getenv("FABRIC_RESEARCHER_EMAIL", unset = "")
  if (!nzchar(email)) return(NULL)
  if (grepl("@aku\\.edu$", email)) return(NULL)

  sub <- cfg$automation$subscription_id
  rg  <- cfg$automation$resource_group
  aa  <- cfg$automation$account_name
  if (is.null(sub) || is.null(rg) || is.null(aa) ||
      !nzchar(sub) || !nzchar(rg) || !nzchar(aa)) {
    message("Auth service error: missing automation config for job polling.")
    return(NULL)
  }

  tryCatch({
    resp <- httr::POST(
      webhook_url,
      body = list(action = "get_token", email = email),
      encode = "json",
      httr::timeout(30)
    )
    if (httr::status_code(resp) != 200L) return(NULL)

    job_data <- httr::content(resp)
    job_ids <- job_data$JobIds
    if (is.null(job_ids) || length(job_ids) == 0) {
      message("Auth service error: no JobIds in webhook response.")
      return(NULL)
    }
    job_id <- job_ids[[1]]

    deadline <- Sys.time() + 120
    while (Sys.time() < deadline) {
      Sys.sleep(10)
      uri <- sprintf(
        "https://management.azure.com/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Automation/automationAccounts/%s/jobs/%s?api-version=2023-11-01",
        sub, rg, aa, job_id
      )
      raw <- suppressWarnings(system(
        paste("az.cmd rest --method GET --uri", shQuote(uri, type = "cmd"),
              "--query \"properties.status\" -o tsv"),
        intern = TRUE, ignore.stderr = TRUE
      ))
      status <- if (length(raw) > 0) trimws(raw[[1]]) else ""
      if (identical(status, "Completed")) break
      if (status %in% c("Failed", "Stopped", "Suspended")) {
        message("Auth service error: job ", status, ".")
        return(NULL)
      }
    }

    out_uri <- sprintf(
      "https://management.azure.com/subscriptions/%s/resourceGroups/%s/providers/Microsoft.Automation/automationAccounts/%s/jobs/%s/output?api-version=2023-11-01",
      sub, rg, aa, job_id
    )
    raw <- suppressWarnings(system(
      paste("az.cmd rest --method GET --uri", shQuote(out_uri, type = "cmd"), "-o json 2>nul"),
      intern = TRUE, ignore.stderr = TRUE
    ))
    output_text <- paste(raw, collapse = "\n")

    marker_start <- "---BEGIN-RESPONSE---"
    marker_end   <- "---END-RESPONSE---"
    start_idx <- regexpr(marker_start, output_text, fixed = TRUE)
    if (start_idx == -1) {
      message("Auth service error: unexpected response format (no BEGIN marker).")
      return(NULL)
    }
    start_idx <- start_idx + nchar(marker_start)
    end_idx <- regexpr(marker_end, output_text, fixed = TRUE)
    if (end_idx == -1) {
      message("Auth service error: unexpected response format (no END marker).")
      return(NULL)
    }
    json_str <- substr(output_text, start_idx, end_idx - 1)

    data <- jsonlite::fromJSON(trimws(json_str), simplifyVector = FALSE)
    if (identical(data$status, "success")) {
      token <- data$data$access_token
      if (!is.null(token)) {
        message("Authenticated as ", email)
        return(token)
      }
    }
    msg <- data$message
    if (is.null(msg)) msg <- "Access denied"
    message("Access denied: ", msg)
    NULL
  }, error = function(e) {
    message("Auth service error: ", e$message)
    NULL
  })
}

#' @noRd
.get_env_access_token <- function() {
  for (name in c("FABRIC_ACCESS_TOKEN", "FABRIC_DELEGATED_ACCESS_TOKEN", "AZURE_ACCESS_TOKEN")) {
    token <- .normalize_access_token(Sys.getenv(name, unset = ""), required = FALSE)
    if (!is.null(token)) {
      return(token)
    }
  }
  NULL
}



#' @noRd
.get_local_access_token_file <- function() {
  candidates <- unique(c(
    Sys.getenv("FABRIC_ACCESS_TOKEN_FILE", unset = ""),
    file.path(Sys.getenv("USERPROFILE", unset = ""), "fab_token.txt"),
    file.path(Sys.getenv("HOME", unset = ""), "fab_token.txt"),
    file.path(Sys.getenv("PROGRAMDATA", unset = "C:/ProgramData"), "UZIMA", "FabricTokenBroker", "fab_token.txt")
  ))
  candidates <- candidates[nzchar(candidates)]

  for (path in candidates) {
    if (!file.exists(path)) next
    raw <- tryCatch(readLines(path, warn = FALSE, n = 1), error = function(e) character(0))
    if (length(raw) == 0) next
    token <- .normalize_access_token(raw[[1]], required = FALSE)
    if (!is.null(token)) {
      return(token)
    }
  }
  NULL
}
#' @noRd
.token_is_usable <- function(entry) {
  is.list(entry) && !is.null(entry$expires_at) && Sys.time() < entry$expires_at
}

#' @noRd
.token_needs_refresh <- function(entry) {
  is.list(entry) &&
    !is.null(entry$expires_at) &&
    Sys.time() >= entry$expires_at - .token_refresh_buffer_seconds
}

#' @noRd
.get_fabric_token <- function(tenant, access_token = NULL) {
  explicit_token <- .normalize_access_token(access_token, required = TRUE)
  if (!is.null(explicit_token)) {
    return(explicit_token)
  }

  cache_key <- paste0(tenant, ":https://storage.azure.com")

  local_file_token <- .get_local_access_token_file()
  if (!is.null(local_file_token)) {
    .token_cache[[cache_key]] <- list(
      access_token = local_file_token, refresh_token = NULL,
      expires_at = Sys.time() + 3300
    )
    return(local_file_token)
  }

  entry <- if (exists(cache_key, envir = .token_cache, inherits = FALSE)) {
    .token_cache[[cache_key]]
  } else {
    NULL
  }
  if (is.list(entry)) {
    if (!.token_needs_refresh(entry)) {
      return(entry$access_token)
    }
    if (!is.null(entry$refresh_token)) {
      refreshed <- .refresh_token(tenant, entry$refresh_token,
                                  "https://storage.azure.com")
      if (!is.null(refreshed)) {
        .token_cache[[cache_key]] <- refreshed
        return(refreshed$access_token)
      }
    }
    if (.token_is_usable(entry)) {
      return(entry$access_token)
    }
  }

  env_token <- .get_env_access_token()
  if (!is.null(env_token)) {
    .token_cache[[cache_key]] <- list(
      access_token = env_token, refresh_token = NULL,
      expires_at = Sys.time() + 3300
    )
    return(env_token)
  }

  webhook_token <- .try_webhook_token(tenant, "https://storage.azure.com")
  if (!is.null(webhook_token)) {
    .token_cache[[cache_key]] <- list(
      access_token = webhook_token, refresh_token = NULL,
      expires_at = Sys.time() + 3300
    )
    return(webhook_token)
  }

  msal_result <- .try_msal_device_code(tenant, "https://storage.azure.com")
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
          "--resource https://storage.azure.com",
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
    "No authentication method available.\n",
    "  Options:\n",
    "    1. Pass access_token = \"...\" to connect_to_fabric()\n",
    "    2. Set FABRIC_ACCESS_TOKEN environment variable\n",
    "    3. Interactive device-code login (automatic)\n",
    "    4. Run 'az login --tenant ", tenant, " --use-device-code'"
  )
}

#' @noRd
.refresh_token <- function(tenant, refresh_token, resource) {
  client_id <- "1950a258-227b-4e31-a9cf-717495945fc2"
  tok <- tryCatch(
    httr::content(httr::POST(
      sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenant),
      body = list(
        grant_type = "refresh_token",
        client_id = client_id,
        refresh_token = refresh_token,
        scope = sprintf("%s/.default offline_access", resource)
      ),
      encode = "form"
    )),
    error = function(e) NULL
  )
  if (is.null(tok) || is.null(tok$access_token)) return(NULL)
  list(
    access_token  = tok$access_token,
    refresh_token = if (is.null(tok$refresh_token)) refresh_token else tok$refresh_token,
    expires_at    = Sys.time() + 3300
  )
}

#' @noRd
.try_msal_device_code <- function(tenant, resource) {
  client_id <- "1950a258-227b-4e31-a9cf-717495945fc2"
  url_base <- sprintf("https://login.microsoftonline.com/%s", tenant)

  dev_resp <- httr::POST(
    sprintf("%s/oauth2/v2.0/devicecode", url_base),
    body = list(
      client_id = client_id,
      scope = sprintf("%s/.default offline_access", resource)
    ),
    encode = "form"
  )
  if (httr::status_code(dev_resp) != 200L) return(NULL)
  dev <- httr::content(dev_resp)
  if (is.null(dev$user_code)) return(NULL)

  message(
    "\n====================  SIGN IN REQUIRED  ====================\n",
    "To access the Fabric Lakehouse, sign in with your email.\n",
    "This supports MFA (e.g. Outlook / Microsoft Authenticator).\n",
    "\n  Opening your browser to: ", dev$verification_uri, "\n",
    "  Enter code: ", dev$user_code, "\n",
    "============================================================\n"
  )
  tryCatch(
    utils::browseURL(dev$verification_uri),
    error = function(e) NULL,
    warning = function(w) NULL
  )

  interval <- if (is.null(dev$interval)) 5L else dev$interval

  for (i in 1:120) {
    Sys.sleep(interval)
    tok <- tryCatch(
      httr::content(httr::POST(
        sprintf("%s/oauth2/v2.0/token", url_base),
        body = list(
          grant_type = "urn:ietf:params:oauth:grant-type:device_code",
          client_id = client_id,
          device_code = dev$device_code
        ),
        encode = "form"
      )),
      error = function(e) NULL
    )
    if (is.null(tok)) next

    if (!is.null(tok$access_token)) {
      message("Authentication successful.\n")
      return(list(
        access_token  = tok$access_token,
        refresh_token = tok$refresh_token
      ))
    }

    err <- tok$error
    if (is.null(err) || identical(err, "authorization_pending")) next
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
