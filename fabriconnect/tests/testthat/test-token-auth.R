test_that("access tokens are normalized for delegated-token use", {
  token <- paste0("eyJ", paste(rep("a", 20), collapse = ""))

  expect_identical(fabriconnect:::.normalize_access_token(token, required = TRUE), token)
  expect_identical(fabriconnect:::.normalize_access_token(paste("Bearer", token), required = TRUE), token)
  expect_null(fabriconnect:::.normalize_access_token(""))
  expect_null(fabriconnect:::.normalize_access_token(NA_character_))
  expect_error(fabriconnect:::.normalize_access_token("not-a-jwt", required = TRUE), "Access token must be a JWT")
})

test_that("delegated token environment variable is accepted", {
  token <- paste0("eyJ", paste(rep("b", 20), collapse = ""))
  old_values <- Sys.getenv(
    c("FABRIC_ACCESS_TOKEN", "FABRIC_DELEGATED_ACCESS_TOKEN", "AZURE_ACCESS_TOKEN"),
    unset = NA_character_
  )
  on.exit({
    for (name in names(old_values)) {
      if (is.na(old_values[[name]])) {
        Sys.unsetenv(name)
      } else {
        do.call(Sys.setenv, as.list(setNames(old_values[[name]], name)))
      }
    }
  }, add = TRUE)

  Sys.unsetenv(c("FABRIC_ACCESS_TOKEN", "AZURE_ACCESS_TOKEN"))
  Sys.setenv(FABRIC_DELEGATED_ACCESS_TOKEN = paste("Bearer", token))

  expect_identical(fabriconnect:::.get_env_access_token(), token)
})

test_that("cached tokens refresh before expiry", {
  fresh <- list(access_token = "fresh", expires_at = Sys.time() + 600)
  near_expiry <- list(access_token = "soon", expires_at = Sys.time() + 120)
  expired <- list(access_token = "old", expires_at = Sys.time() - 1)

  expect_false(fabriconnect:::.token_needs_refresh(fresh))
  expect_true(fabriconnect:::.token_needs_refresh(near_expiry))
  expect_true(fabriconnect:::.token_is_usable(near_expiry))
  expect_false(fabriconnect:::.token_is_usable(expired))
})
