source(file.path("R", "02A_whitebox_fill_retry.R"))

output <- tempfile(fileext = ".tif")
attempt_count <- 0L
original_max_procs <- Sys.getenv("R_WHITEBOX_MAX_PROCS", unset = NA_character_)

whitebox_fill_depressions_with_retry(
  output = output,
  label = "test FillDepressions",
  run_fill = function() {
    stopifnot(identical(Sys.getenv("R_WHITEBOX_MAX_PROCS"), "1"))
    attempt_count <<- attempt_count + 1L
    if (attempt_count == 2L) writeBin(as.raw(1:4), output)
  }
)

stopifnot(
  attempt_count == 2L,
  file.info(output)$size == 4L,
  identical(
    Sys.getenv("R_WHITEBOX_MAX_PROCS", unset = NA_character_),
    original_max_procs
  )
)
unlink(output)

failed_output <- tempfile(fileext = ".tif")
failure_count <- 0L
err <- tryCatch(
  whitebox_fill_depressions_with_retry(
    output = failed_output,
    label = "failing test FillDepressions",
    run_fill = function() failure_count <<- failure_count + 1L
  ),
  error = identity
)

stopifnot(
  inherits(err, "error"),
  grepl("after 2 attempts", conditionMessage(err), fixed = TRUE),
  failure_count == 2L,
  identical(
    Sys.getenv("R_WHITEBOX_MAX_PROCS", unset = NA_character_),
    original_max_procs
  )
)

cat("PASS: Whitebox FillDepressions uses one worker and bounded retry\n")
