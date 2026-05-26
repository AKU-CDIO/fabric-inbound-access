#' Update fabriconnect to the latest GitHub version
#'
#' Runs the install in a fresh R sub-process via \code{callr} so the current
#' session's DLL locks don't block the overwrite. After this completes,
#' restart R and load the package normally.
#'
#' @return Invisible \code{TRUE} on success.
#' @export
#'
#' @examples
#' \dontrun{
#' update_fabriconnect()
#' }
update_fabriconnect <- function() {
  if (!requireNamespace("callr", quietly = TRUE)) {
    utils::install.packages("callr")
  }
  cat("Installing latest fabriconnect in a fresh R process...\n")
  callr::r(function() {
    if ("fabriconnect" %in% rownames(utils::installed.packages())) {
      utils::remove.packages("fabriconnect")
    }
    remotes::install_github(
      "AKU-CDIO/fabric-inbound-access",
      subdir = "fabriconnect",
      upgrade = "always",
      force = TRUE
    )
  })
  cat("Done. Restart R, then: library(fabriconnect)\n")
  invisible(TRUE)
}
