read_table <- function(conn, table_name, columns = NULL) {
  token <- .get_fabric_token(conn$fabric_tenant)

  list_url <- sprintf(
    "https://onelake.dfs.fabric.microsoft.com/%s/%s/Tables/%s?recursive=true&maxResults=1000&resource=filesystem",
    conn$workspace_id, conn$lakehouse_id, table_name
  )
  resp <- httr::GET(list_url, httr::add_headers(
    Authorization = paste("Bearer", token),
    Accept = "application/json;charset=utf-8",
    "x-ms-version" = "2024-08-04"
  ))
  httr::stop_for_status(resp)
  data <- httr::content(resp)
  parquet_paths <- grep("\\.parquet$", sapply(data$paths, `[[`, "name"), value = TRUE)
  parquet_paths <- grep("/_delta_log/", parquet_paths, value = TRUE, invert = TRUE)
  if (length(parquet_paths) == 0) {
    stop("No parquet files found for table '", table_name, "'")
  }

  base_url <- sprintf("https://onelake.dfs.fabric.microsoft.com/%s", conn$workspace_id)

  # Download to temp files (avoids Arrow in-memory raw parsing issues)
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  files <- file.path(tmp, basename(parquet_paths))
  for (i in seq_along(parquet_paths)) {
    file_url <- file.path(base_url, parquet_paths[i])
    resp <- httr::GET(file_url, httr::add_headers(Authorization = paste("Bearer", token)))
    httr::stop_for_status(resp)
    writeBin(httr::content(resp, as = "raw"), files[i])
  }

  # Read all parquet files and concatenate
  ds <- arrow::open_dataset(tmp, format = "parquet")
  out <- if (is.null(columns)) {
    as.data.frame(ds)
  } else {
    as.data.frame(ds[, columns, drop = FALSE])
  }
  out
}
