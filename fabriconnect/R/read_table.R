read_table <- function(conn, table_name, columns = NULL, overwrite = TRUE) {
  token <- .get_fabric_token(conn$fabric_tenant, conn$access_token)
  ws_url <- sprintf("https://onelake.dfs.fabric.microsoft.com/%s", conn$workspace_id)

  table_path <- gsub("\\.", "/", table_name)
  base <- sprintf("%s/%s/Tables/%s", ws_url, conn$lakehouse_id, table_path)

  list_url <- paste0(base, "?recursive=true&maxResults=1000&resource=filesystem")
  resp <- httr::GET(list_url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  httr::stop_for_status(resp)
  data <- httr::content(resp)
  if (is.null(data$paths) || length(data$paths) == 0) {
    stop("No files found for table '", table_name, "'.")
  }
  all_names <- vapply(data$paths, function(x) if (is.null(x$name)) "" else x$name, character(1))
  parquet_paths <- grep("\\.parquet$", all_names, value = TRUE)
  parquet_paths <- grep("/_delta_log/", parquet_paths, value = TRUE, invert = TRUE)
  if (length(parquet_paths) == 0) {
    stop("No parquet files found for table '", table_name, "'.")
  }

  tmp <- file.path(tempdir(), sprintf("fabriconnect_%s_%d", gsub("[^A-Za-z0-9]", "_", table_name), as.integer(Sys.time())))
  if (dir.exists(tmp)) {
    if (overwrite) unlink(tmp, recursive = TRUE) else stop("tmp exists and overwrite is FALSE")
  }
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  files <- file.path(tmp, basename(parquet_paths))
  for (i in seq_along(parquet_paths)) {
    file_url <- file.path(ws_url, parquet_paths[i])
    r <- httr::GET(file_url, httr::add_headers(Authorization = paste("Bearer", token)))
    httr::stop_for_status(r)
    writeBin(httr::content(r, as = "raw"), files[i])
  }
  ds <- arrow::open_dataset(tmp, format = "parquet")
  return(if (is.null(columns)) as.data.frame(ds) else as.data.frame(ds[, columns, drop = FALSE]))
}
