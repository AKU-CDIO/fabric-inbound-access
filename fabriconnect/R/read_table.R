read_table <- function(conn, table_name, columns = NULL, overwrite = TRUE) {
  token <- .get_fabric_token(conn$fabric_tenant, conn$access_token)
  cfg <- .load_config()
  parts <- strsplit(table_name, "\\.")[[1]]
  ws_url <- sprintf("https://onelake.dfs.fabric.microsoft.com/%s", conn$workspace_id)

  # Build candidate base URLs in priority order
  candidates <- character(0)
  if (length(parts) >= 3) {
    target_id <- cfg$shortcuts[[parts[1]]]
    if (is.null(target_id))
      stop("Unknown lakehouse shortcut '", parts[1], "'. Add it to the 'shortcuts' map in inst/config.json")
    candidates <- sprintf("%s/%s/Tables/%s/%s", ws_url, target_id, parts[2], parts[3])
  } else if (length(parts) == 2 && !is.null(cfg$shortcuts[[parts[1]]])) {
    candidates <- sprintf("%s/%s/Tables/dbo/%s", ws_url, cfg$shortcuts[[parts[1]]], parts[2])
  } else if (length(parts) == 2) {
    candidates <- sprintf("%s/%s/Tables/%s/%s", ws_url, conn$lakehouse_id, parts[1], parts[2])
  } else {
    for (sc in c("", names(cfg$shortcuts))) {
      lid <- if (nzchar(sc)) cfg$shortcuts[[sc]] else conn$lakehouse_id
      candidates <- c(candidates,
        sprintf("%s/%s/Tables/dbo/%s", ws_url, lid, table_name),
        sprintf("%s/%s/Tables/%s", ws_url, lid, table_name))
    }
  }

  # Try candidates in order
  for (base in candidates) {
    list_url <- paste0(base, "?recursive=true&maxResults=1000&resource=filesystem")
    resp <- httr::GET(list_url, httr::add_headers(
      Authorization = paste("Bearer", token),
      Accept = "application/json;charset=utf-8",
      "x-ms-version" = "2024-08-04"
    ))
    if (httr::status_code(resp) != 200) next
    data <- httr::content(resp)
    if (is.null(data$paths) || length(data$paths) == 0) next
    all_names <- vapply(data$paths, function(x) if (is.null(x$name)) "" else x$name, character(1))
    parquet_paths <- grep("\\.parquet$", all_names, value = TRUE)
    parquet_paths <- grep("/_delta_log/", parquet_paths, value = TRUE, invert = TRUE)
    if (length(parquet_paths) == 0) next

    # Found it — download to temp dir and read
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

  stop("Table '", table_name, "' not found in the connected lakehouse or any shortcut. Use list_tables() to discover available tables.")
}
