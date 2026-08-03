#' Connect to Fabric SQL via service principal credentials in Azure Key Vault
#'
#' Researchers authenticate to Azure Key Vault with their Azure AD account and
#' MFA, fetch service-principal credentials at runtime, and use the resulting
#' service-principal token to connect to the Fabric SQL endpoint.
#'
#' @param database Fabric SQL database name. Defaults to configured UZIMA database.
#' @param server Fabric SQL endpoint host name.
#' @param vault_url Azure Key Vault URL that stores the service-principal secrets.
#' @param keyvault_tenant Azure AD tenant ID used for Key Vault login.
#' @param driver ODBC driver name.
#' @param auth Authentication method. Must be `"sp_vault"` for Key Vault service-principal access.
#' @param timeout Connection timeout in seconds.
#'
#' @return A DBI ODBC connection.
#'
#' @examples
#' \dontrun{
#' con <- connect_to_fabric_sql(auth = "sp_vault")
#' list_tables(con)
#' read_table(con, "dbo.dimenrolledparticipants")
#' DBI::dbDisconnect(con)
#' }
#' @export
connect_to_fabric_sql <- function(
  database = NULL,
  server = NULL,
  vault_url = NULL,
  keyvault_tenant = NULL,
  driver = "ODBC Driver 18 for SQL Server",
  auth = "sp_vault",
  timeout = 30
) {
  auth <- match.arg(auth, choices = "sp_vault")

  if (!requireNamespace("odbc", quietly = TRUE)) {
    stop("Package 'odbc' is required. Install with: install.packages('odbc')")
  }

  sql_cfg <- .get_sql_access_config(database, server, vault_url, keyvault_tenant)
  sp <- .get_service_principal_from_keyvault(sql_cfg)
  token <- .get_fabric_sql_token(sp$tenant_id, sp$client_id, sp$client_secret)

  DBI::dbConnect(
    odbc::odbc(),
    Driver = driver,
    Server = paste0(sql_cfg$server, ",1433"),
    Database = sql_cfg$database,
    Encrypt = "yes",
    TrustServerCertificate = "no",
    Timeout = timeout,
    ApplicationIntent = "ReadOnly",
    attributes = .sql_access_token_attribute(token)
  )
}

#' List schema-qualified tables from a Fabric SQL connection
#'
#' @param conn DBI ODBC connection created by \code{connect_to_fabric_sql()}.
#' @return A character vector of \code{schema.table} names.
#' @export
list_sql_tables <- function(conn) {
  tables <- DBI::dbGetQuery(conn, paste(
    "SELECT TABLE_SCHEMA, TABLE_NAME",
    "FROM INFORMATION_SCHEMA.TABLES",
    "ORDER BY TABLE_SCHEMA, TABLE_NAME"
  ))
  paste(tables$TABLE_SCHEMA, tables$TABLE_NAME, sep = ".")
}

#' Query Fabric SQL directly
#'
#' @param conn DBI ODBC connection created by \code{connect_to_fabric_sql()}.
#' @param sql SQL statement.
#' @return A data.frame.
#' @export
query_sql <- function(conn, sql) {
  .ensure_read_only_sql(sql)
  DBI::dbGetQuery(conn, sql)
}

#' Read a Fabric SQL table
#'
#' @param conn DBI ODBC connection created by \code{connect_to_fabric_sql()}.
#' @param table_name Table name, either \code{table} or \code{schema.table}.
#' @param columns Optional character vector of columns to select.
#' @param top Optional row limit using SQL Server \code{TOP} syntax.
#' @return A data.frame.
#' @export
read_sql_table <- function(conn, table_name, columns = NULL, top = NULL) {
  cols <- "*"
  if (!is.null(columns)) {
    cols <- paste(vapply(columns, .quote_sql_identifier, character(1)), collapse = ", ")
  }
  top_clause <- ""
  if (!is.null(top)) top_clause <- paste0("TOP ", as.integer(top), " ")
  sql <- sprintf("SELECT %s%s FROM %s", top_clause, cols, .format_sql_table_name(table_name))
  query_sql(conn, sql)
}

#' @noRd
.sql_without_literals_and_comments <- function(sql) {
  sql <- paste(sql, collapse = "\n")
  sql <- gsub("/\\*.*?\\*/", " ", sql, perl = TRUE)
  sql <- gsub("--[^\\r\\n]*", " ", sql, perl = TRUE)
  sql <- gsub("'(?:''|[^'])*'", "''", sql, perl = TRUE)
  sql
}

#' @noRd
.ensure_read_only_sql <- function(sql) {
  cleaned <- .sql_without_literals_and_comments(sql)
  if (!grepl("^\\s*(?:\\(\\s*)*[[:alpha:]_]", cleaned, perl = TRUE)) {
    stop("Only read-only SELECT queries are allowed by default.", call. = FALSE)
  }
  keyword <- tolower(sub("^\\s*(?:\\(\\s*)*([[:alpha:]_][[:alnum:]_]*).*", "\\1", cleaned, perl = TRUE))
  if (!keyword %in% c("select", "with")) {
    stop("Only read-only SELECT queries are allowed by default.", call. = FALSE)
  }
  blocked <- c(
    "alter", "backup", "create", "delete", "deny", "drop", "exec", "execute",
    "grant", "insert", "into", "merge", "restore", "revoke", "truncate", "update"
  )
  pattern <- paste0("\\b(", paste(blocked, collapse = "|"), ")\\b")
  if (grepl(pattern, cleaned, ignore.case = TRUE, perl = TRUE)) {
    stop("Only read-only SELECT queries are allowed by default.", call. = FALSE)
  }
}

#' @noRd
.sql_access_token_attribute <- function(token) {
  list(azure_token = token)
}
#' @noRd
.get_sql_access_config <- function(database = NULL, server = NULL, vault_url = NULL, keyvault_tenant = NULL) {
  cfg <- .load_config()
  sql_cfg <- cfg$sql_access
  if (is.null(sql_cfg)) sql_cfg <- list()

  pick <- function(value, env_name, config_name, fallback = NULL) {
    env_value <- Sys.getenv(env_name, unset = "")
    if (!is.null(value) && nzchar(value)) return(value)
    if (nzchar(env_value)) return(env_value)
    config_value <- sql_cfg[[config_name]]
    if (!is.null(config_value) && nzchar(config_value)) return(config_value)
    fallback
  }

  out <- list(
    database = pick(database, "FABRIC_SQL_DATABASE", "default_database", cfg$lakehouse_name),
    server = pick(server, "FABRIC_SQL_SERVER", "server"),
    vault_url = pick(vault_url, "FABRIC_KEYVAULT_URL", "key_vault_url"),
    keyvault_tenant = pick(keyvault_tenant, "FABRIC_KEYVAULT_TENANT", "key_vault_tenant"),
    tenant_secret = sql_cfg$tenant_secret %||% "fabric-sp-tenant-id",
    client_id_secret = sql_cfg$client_id_secret %||% "fabric-sp-client-id",
    client_secret_secret = sql_cfg$client_secret_secret %||% "fabric-sp-client-secret"
  )
  missing <- names(out)[vapply(out, function(x) is.null(x) || !nzchar(x), logical(1))]
  if (length(missing)) {
    stop("Missing Fabric SQL access configuration: ", paste(missing, collapse = ", "),
         ". Set it in inst/config.json or environment variables.")
  }
  out
}

#' @noRd
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || !nzchar(x)) y else x
}

#' @noRd
.get_service_principal_from_keyvault <- function(sql_cfg) {
  list(
    tenant_id = .get_keyvault_secret(sql_cfg$vault_url, sql_cfg$keyvault_tenant, sql_cfg$tenant_secret),
    client_id = .get_keyvault_secret(sql_cfg$vault_url, sql_cfg$keyvault_tenant, sql_cfg$client_id_secret),
    client_secret = .get_keyvault_secret(sql_cfg$vault_url, sql_cfg$keyvault_tenant, sql_cfg$client_secret_secret)
  )
}

#' @noRd
.get_keyvault_secret <- function(vault_url, tenant, secret_name) {
  token <- .get_azure_cli_token("https://vault.azure.net", tenant)
  url <- paste0(sub("/+$", "", vault_url), "/secrets/", utils::URLencode(secret_name, reserved = TRUE), "?api-version=7.4")
  resp <- httr::GET(url, httr::add_headers(Authorization = paste("Bearer", token)))
  httr::stop_for_status(resp)
  httr::content(resp)$value
}

#' @noRd
.get_azure_cli_token <- function(resource, tenant) {
  az <- .az_command()
  args <- c(
    "account", "get-access-token",
    "--resource", resource,
    "--tenant", tenant,
    "--query", "accessToken",
    "-o", "tsv"
  )
  raw <- suppressWarnings(system2(az, args, stdout = TRUE, stderr = TRUE))
  status <- attr(raw, "status")
  if (!is.null(status) && status != 0) {
    stop("Run 'az login --tenant ", tenant, "' first, then retry Fabric SQL access.")
  }
  token <- trimws(raw[[1]])
  if (!nzchar(token)) stop("Azure CLI did not return a Key Vault access token.")
  token
}

#' @noRd
.az_command <- function() {
  candidates <- c("az.cmd", "az")
  found <- Sys.which(candidates)
  found <- found[nzchar(found)]
  if (length(found) == 0) stop("Azure CLI 'az' was not found on PATH.")
  unname(found[[1]])
}

#' @noRd
.get_fabric_sql_token <- function(tenant_id, client_id, client_secret) {
  resp <- httr::POST(
    sprintf("https://login.microsoftonline.com/%s/oauth2/v2.0/token", tenant_id),
    body = list(
      grant_type = "client_credentials",
      client_id = client_id,
      client_secret = client_secret,
      scope = "https://database.windows.net/.default"
    ),
    encode = "form"
  )
  httr::stop_for_status(resp)
  httr::content(resp)$access_token
}

#' @noRd
.quote_sql_identifier <- function(identifier) {
  if (is.null(identifier) || is.na(identifier) || !nzchar(identifier)) {
    stop("SQL identifier cannot be empty.")
  }
  paste0("[", gsub("]", "]]", identifier, fixed = TRUE), "]")
}

#' @noRd
.format_sql_table_name <- function(table_name) {
  parts <- strsplit(table_name, ".", fixed = TRUE)[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) == 1) parts <- c("dbo", parts)
  if (length(parts) != 2) stop("table_name must be 'table' or 'schema.table'.")
  paste(vapply(parts, .quote_sql_identifier, character(1)), collapse = ".")
}
